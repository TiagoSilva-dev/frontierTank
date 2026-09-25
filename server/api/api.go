package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// Error codes are stable strings: the game translates them for the player.
const (
	codeBadRequest   = "bad_request"
	codeUsername     = "username_invalid"
	codePassword     = "password_weak"
	codeTaken        = "username_taken"
	codeCredentials  = "invalid_credentials"
	codeBanned       = "banned"
	codeRateLimited  = "rate_limited"
	codeUnauthorized = "unauthorized"
	codeNotFound     = "not_found"
	codeConflict     = "version_conflict"
	codeNameTaken    = "name_taken"
	codeOtherServer  = "online_elsewhere"
	codeInternal     = "internal"
)

var usernamePattern = regexp.MustCompile(`^[A-Za-z0-9_]{3,16}$`)

type API struct {
	store   *Store
	cfg     Config
	limiter *RateLimiter
	log     *slog.Logger
	// A real hash to compare against when the user does not exist, so both cases take
	// the same time (no account enumeration by timing).
	dummyHash string
}

func newAPI(store *Store, cfg Config, logger *slog.Logger) (*API, error) {
	dummy, err := hashPassword("frontier-tank-dummy", cfg.PBKDF2Iterations)
	if err != nil {
		return nil, err
	}
	return &API{store: store, cfg: cfg, limiter: NewRateLimiter(cfg.AuthPerMinute, time.Minute), log: logger, dummyHash: dummy}, nil
}

func (a *API) publicRoutes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", a.health)
	mux.HandleFunc("GET /v1/servers", a.servers)
	mux.HandleFunc("POST /v1/auth/register", a.register)
	mux.HandleFunc("POST /v1/auth/login", a.login)
	mux.HandleFunc("POST /v1/auth/logout", a.logout)
	mux.HandleFunc("GET /v1/me", a.me)
	mux.HandleFunc("POST /v1/me/password", a.changePassword)
	mux.HandleFunc("DELETE /v1/me", a.deleteMe)
	return a.cors(limitBody(mux, 64<<10))
}

func (a *API) internalRoutes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /internal/health", a.health)
	mux.HandleFunc("POST /internal/sessions/verify", a.verifySession)
	mux.HandleFunc("GET /internal/profiles/{id}", a.getProfile)
	mux.HandleFunc("PUT /internal/profiles/{id}", a.putProfile)
	mux.HandleFunc("GET /internal/names/check", a.checkName)
	mux.HandleFunc("POST /internal/audit", a.audit)
	mux.HandleFunc("POST /internal/heartbeat", a.heartbeat)
	mux.HandleFunc("POST /internal/presence/claim", a.claimPresence)
	mux.HandleFunc("POST /internal/presence/release", a.releasePresence)
	a.auctionRoutes(mux)
	return a.internalOnly(limitBody(mux, 8<<20))
}

// ---------- helpers ----------

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]string{"error": code, "message": message})
}

func (a *API) fail(w http.ResponseWriter, err error) {
	a.log.Error("request failed", "err", err)
	writeError(w, http.StatusInternalServerError, codeInternal, "internal error")
}

func readJSON(r *http.Request, target any) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}

func limitBody(next http.Handler, limit int64) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, limit)
		next.ServeHTTP(w, r)
	})
}

func (a *API) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", a.cfg.AllowOrigin)
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *API) internalOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("X-Internal-Key")
		if subtle.ConstantTimeCompare([]byte(key), []byte(a.cfg.InternalKey)) != 1 {
			writeError(w, http.StatusUnauthorized, codeUnauthorized, "invalid internal key")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *API) clientIP(r *http.Request) string {
	if a.cfg.TrustProxy {
		if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
			return strings.TrimSpace(strings.Split(forwarded, ",")[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func newToken() (string, []byte, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", nil, err
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	return token, tokenHash(token), nil
}

func tokenHash(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

func bearer(r *http.Request) string {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		return ""
	}
	return strings.TrimSpace(header[len("Bearer "):])
}

func (a *API) sessionAccount(w http.ResponseWriter, r *http.Request) (Account, bool) {
	token := bearer(r)
	if token == "" {
		writeError(w, http.StatusUnauthorized, codeUnauthorized, "missing token")
		return Account{}, false
	}
	account, err := a.store.SessionAccount(r.Context(), tokenHash(token))
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusUnauthorized, codeUnauthorized, "session expired")
		return account, false
	}
	if err != nil {
		a.fail(w, err)
		return account, false
	}
	return account, true
}

func validPassword(password string) bool {
	count := utf8.RuneCountInString(password)
	return count >= 8 && count <= 128
}

// validCharacterName: 2–14 letters (accents allowed), digits, spaces, "_", "-" and ".",
// no leading/trailing space.
func validCharacterName(name string) bool {
	count := utf8.RuneCountInString(name)
	if count < 2 || count > 14 || strings.TrimSpace(name) != name {
		return false
	}
	for _, r := range name {
		if !(unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' || r == '_' || r == '-' || r == '.') {
			return false
		}
	}
	return true
}

// ---------- public ----------

func (a *API) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.store.pool.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, codeInternal, "database unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) servers(w http.ResponseWriter, r *http.Request) {
	list, err := a.store.Servers(r.Context(), 30*time.Second)
	if err != nil {
		a.fail(w, err)
		return
	}
	if list == nil {
		list = []GameServer{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"servers": list})
}

type credentials struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (a *API) startSession(w http.ResponseWriter, r *http.Request, account Account, status int) {
	token, hash, err := newToken()
	if err != nil {
		a.fail(w, err)
		return
	}
	expires := time.Now().Add(a.cfg.SessionTTL)
	if err := a.store.CreateSession(r.Context(), account.ID, hash, expires); err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, status, map[string]any{"token": token, "account": account, "expires_at": expires.UTC().Format(time.RFC3339)})
}

func (a *API) register(w http.ResponseWriter, r *http.Request) {
	if !a.limiter.Allow("auth:" + a.clientIP(r)) {
		writeError(w, http.StatusTooManyRequests, codeRateLimited, "too many attempts")
		return
	}
	var body credentials
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	if !usernamePattern.MatchString(body.Username) {
		writeError(w, http.StatusBadRequest, codeUsername, "username: 3-16 letters, digits or _")
		return
	}
	if !validPassword(body.Password) {
		writeError(w, http.StatusBadRequest, codePassword, "password: 8-128 characters")
		return
	}
	hash, err := hashPassword(body.Password, a.cfg.PBKDF2Iterations)
	if err != nil {
		a.fail(w, err)
		return
	}
	account, err := a.store.CreateAccount(r.Context(), body.Username, hash)
	if errors.Is(err, ErrTaken) {
		writeError(w, http.StatusConflict, codeTaken, "username already registered")
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	a.log.Info("account created", "id", account.ID, "username", account.Username)
	a.startSession(w, r, account, http.StatusCreated)
}

func (a *API) login(w http.ResponseWriter, r *http.Request) {
	if !a.limiter.Allow("auth:" + a.clientIP(r)) {
		writeError(w, http.StatusTooManyRequests, codeRateLimited, "too many attempts")
		return
	}
	var body credentials
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	account, hash, err := a.store.AccountByUsername(r.Context(), body.Username)
	if err != nil && !errors.Is(err, ErrNotFound) {
		a.fail(w, err)
		return
	}
	if errors.Is(err, ErrNotFound) {
		verifyPassword(body.Password, a.dummyHash)
		writeError(w, http.StatusUnauthorized, codeCredentials, "wrong username or password")
		return
	}
	if !verifyPassword(body.Password, hash) {
		writeError(w, http.StatusUnauthorized, codeCredentials, "wrong username or password")
		return
	}
	if account.Banned {
		writeError(w, http.StatusForbidden, codeBanned, "account suspended")
		return
	}
	if passwordRounds(hash) < a.cfg.PBKDF2Iterations {
		// Upgrade old hashes to the current number of rounds.
		if upgraded, err := hashPassword(body.Password, a.cfg.PBKDF2Iterations); err == nil {
			_ = a.store.UpdatePassword(r.Context(), account.ID, upgraded)
		}
	}
	_ = a.store.TouchLogin(r.Context(), account.ID)
	a.startSession(w, r, account, http.StatusOK)
}

func (a *API) logout(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	if token != "" {
		if err := a.store.DeleteSession(r.Context(), tokenHash(token)); err != nil {
			a.fail(w, err)
			return
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) me(w http.ResponseWriter, r *http.Request) {
	account, ok := a.sessionAccount(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"account": account})
}

func (a *API) changePassword(w http.ResponseWriter, r *http.Request) {
	account, ok := a.sessionAccount(w, r)
	if !ok {
		return
	}
	var body struct {
		Old string `json:"old"`
		New string `json:"new"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	hash, err := a.store.AccountPasswordHash(r.Context(), account.ID)
	if err != nil {
		a.fail(w, err)
		return
	}
	if !verifyPassword(body.Old, hash) {
		writeError(w, http.StatusUnauthorized, codeCredentials, "wrong password")
		return
	}
	if !validPassword(body.New) {
		writeError(w, http.StatusBadRequest, codePassword, "password: 8-128 characters")
		return
	}
	updated, err := hashPassword(body.New, a.cfg.PBKDF2Iterations)
	if err != nil {
		a.fail(w, err)
		return
	}
	if err := a.store.UpdatePassword(r.Context(), account.ID, updated); err != nil {
		a.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// deleteMe removes the account and all its data (LGPD/GDPR right to erasure).
func (a *API) deleteMe(w http.ResponseWriter, r *http.Request) {
	account, ok := a.sessionAccount(w, r)
	if !ok {
		return
	}
	var body struct {
		Password string `json:"password"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	hash, err := a.store.AccountPasswordHash(r.Context(), account.ID)
	if err != nil {
		a.fail(w, err)
		return
	}
	if !verifyPassword(body.Password, hash) {
		writeError(w, http.StatusUnauthorized, codeCredentials, "wrong password")
		return
	}
	if err := a.store.DeleteAccount(r.Context(), account.ID); err != nil {
		a.fail(w, err)
		return
	}
	a.log.Info("account deleted", "id", account.ID)
	w.WriteHeader(http.StatusNoContent)
}

// ---------- internal (game servers only) ----------

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

func (a *API) verifySession(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Token string `json:"token"`
	}
	if err := readJSON(r, &body); err != nil || body.Token == "" {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	account, err := a.store.SessionAccount(r.Context(), tokenHash(body.Token))
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusUnauthorized, codeUnauthorized, "session expired")
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	if account.Banned {
		writeError(w, http.StatusForbidden, codeBanned, "account suspended")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"account": account})
}

func (a *API) getProfile(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	profile, err := a.store.Profile(r.Context(), id)
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, codeNotFound, "no profile yet")
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

func (a *API) putProfile(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body Profile
	if err := readJSON(r, &body); err != nil || len(body.Data) == 0 || !json.Valid(body.Data) {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	if body.Name != nil {
		name := normalizeName(*body.Name)
		if !validCharacterName(name) {
			writeError(w, http.StatusBadRequest, codeBadRequest, "invalid character name")
			return
		}
		body.Name = &name
	}
	version, err := a.store.SaveProfile(r.Context(), id, body.Name, body.Data, body.Version)
	switch {
	case errors.Is(err, ErrNameTaken):
		writeError(w, http.StatusConflict, codeNameTaken, "character name in use")
	case errors.Is(err, ErrConflict):
		writeError(w, http.StatusConflict, codeConflict, "profile changed elsewhere")
	case err != nil:
		a.fail(w, err)
	default:
		writeJSON(w, http.StatusOK, map[string]int64{"version": version})
	}
}

func (a *API) checkName(w http.ResponseWriter, r *http.Request) {
	name := normalizeName(r.URL.Query().Get("name"))
	account, _ := strconv.ParseInt(r.URL.Query().Get("account"), 10, 64)
	if !validCharacterName(name) {
		writeJSON(w, http.StatusOK, map[string]any{"valid": false, "taken": false})
		return
	}
	taken, err := a.store.NameTaken(r.Context(), name, account)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"valid": true, "taken": taken})
}

func (a *API) audit(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ServerID string       `json:"server_id"`
		Entries  []AuditEntry `json:"entries"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	if err := a.store.AddAudit(r.Context(), body.ServerID, body.Entries); err != nil {
		a.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) heartbeat(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Server  GameServer `json:"server"`
		Players []int64    `json:"players"`
	}
	if err := readJSON(r, &body); err != nil || body.Server.ID == "" || body.Server.URL == "" {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	if body.Players == nil {
		body.Players = []int64{}
	}
	if err := a.store.Heartbeat(r.Context(), body.Server, body.Players); err != nil {
		a.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type presenceBody struct {
	AccountID int64  `json:"account_id"`
	ServerID  string `json:"server_id"`
}

func (a *API) claimPresence(w http.ResponseWriter, r *http.Request) {
	var body presenceBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 || body.ServerID == "" {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	holder, err := a.store.ClaimPresence(r.Context(), body.AccountID, body.ServerID)
	if errors.Is(err, ErrOtherServer) {
		writeJSON(w, http.StatusConflict, map[string]string{"error": codeOtherServer, "message": "online on another server", "server_id": holder})
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) releasePresence(w http.ResponseWriter, r *http.Request) {
	var body presenceBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	if err := a.store.ReleasePresence(r.Context(), body.AccountID, body.ServerID); err != nil {
		a.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
