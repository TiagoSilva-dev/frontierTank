package main

import (
	"context"
	"crypto/subtle"
	"embed"
	"errors"
	"io/fs"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// The admin panel (/admin/): a page for the staff, served by this API from files embedded
// in the binary (admin_ui/, no build step), and its JSON API under /admin/api/. It is off
// unless ADMIN_ENABLED=1. Staff accounts are not player accounts: own table, PBKDF2
// password, TOTP second factor, short sessions in an HttpOnly SameSite=Strict cookie, a CSRF
// token on every change, a login limit and lockout, an optional address allow list, and
// admin_audit with everything done (who, what, to whom, why). docs/ADMIN.md.

//go:embed admin_ui
var adminUIFiles embed.FS

const (
	adminCookie = "gf_admin"
	// Day boundaries of the charts: the team is in Brazil.
	adminTZ = "America/Sao_Paulo"
)

// Roles, from the least to the most powerful.
const (
	roleViewer  = 1
	roleSupport = 2
	roleAdmin   = 3
	roleOwner   = 4
	// Routes with no role: roleOpen needs no session, roleSession any session (even one that
	// still has to enrol the second factor or change the password).
	roleOpen    = -1
	roleSession = 0
)

var roleRanks = map[string]int{"viewer": roleViewer, "support": roleSupport, "admin": roleAdmin, "owner": roleOwner}

type adminHandler func(w http.ResponseWriter, r *http.Request, s *adminSession)

func (a *API) adminHandler() http.Handler {
	mux := http.NewServeMux()
	ui, err := fs.Sub(adminUIFiles, "admin_ui")
	if err != nil {
		panic(err)
	}
	files := http.FileServerFS(ui)
	mux.HandleFunc("GET /admin/{$}", func(w http.ResponseWriter, r *http.Request) {
		r.URL.Path = "/"
		files.ServeHTTP(w, r)
	})
	mux.Handle("GET /admin/static/", http.StripPrefix("/admin/static/", files))

	api := func(pattern string, role int, handler adminHandler) { a.adminRoute(mux, pattern, role, handler) }
	api("POST /admin/api/login", roleOpen, a.adminLogin)
	api("POST /admin/api/logout", roleSession, a.adminLogout)
	api("GET /admin/api/me", roleSession, a.adminMe)
	api("POST /admin/api/password", roleSession, a.adminChangePassword)
	api("POST /admin/api/totp/setup", roleSession, a.adminTOTPSetup)
	api("POST /admin/api/totp/confirm", roleSession, a.adminTOTPConfirm)
	a.adminDataRoutes(api)
	a.adminActionRoutes(api)
	a.adminStaffRoutes(api)
	mux.HandleFunc("/admin/api/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, codeNotFound, "Rota inexistente.")
	})
	return a.adminGate(mux)
}

// adminGate: the address allow list, the headers every response carries and the body limit.
func (a *API) adminGate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if len(a.cfg.Admin.AllowIPs) > 0 && !a.adminAllowed(a.clientIP(r)) {
			// Not "forbidden": the panel does not announce itself.
			http.NotFound(w, r)
			return
		}
		header := w.Header()
		header.Set("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
		header.Set("X-Content-Type-Options", "nosniff")
		header.Set("X-Frame-Options", "DENY")
		header.Set("Referrer-Policy", "no-referrer")
		header.Set("X-Robots-Tag", "noindex, nofollow")
		if strings.HasPrefix(r.URL.Path, "/admin/api/") {
			header.Set("Cache-Control", "no-store")
		} else {
			header.Set("Cache-Control", "no-cache")
		}
		r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
		next.ServeHTTP(w, r)
	})
}

func (a *API) adminAllowed(ip string) bool {
	parsed := net.ParseIP(ip)
	if parsed == nil {
		return false
	}
	for _, network := range a.cfg.Admin.AllowIPs {
		if network.Contains(parsed) {
			return true
		}
	}
	return false
}

func (a *API) adminRoute(mux *http.ServeMux, pattern string, role int, handler adminHandler) {
	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead && !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
			// A page of another site cannot post JSON without a preflight the panel never allows.
			writeError(w, http.StatusUnsupportedMediaType, codeBadRequest, "Use application/json.")
			return
		}
		if role == roleOpen {
			handler(w, r, &adminSession{IP: a.clientIP(r)})
			return
		}
		session, ok := a.adminAuth(w, r)
		if !ok {
			return
		}
		if role != roleSession {
			switch {
			case session.Stage != "full":
				writeError(w, http.StatusForbidden, "two_factor_required", "Cadastre o segundo fator antes de continuar.")
				return
			case session.MustChange:
				writeError(w, http.StatusForbidden, "password_change_required", "Troque a senha antes de continuar.")
				return
			case roleRanks[session.Role] < role:
				writeError(w, http.StatusForbidden, "forbidden", "Seu papel não permite esta ação.")
				return
			}
		}
		handler(w, r, session)
	})
}

func adminToken(r *http.Request) string {
	cookie, err := r.Cookie(adminCookie)
	if err != nil {
		return ""
	}
	return cookie.Value
}

// adminAuth checks the cookie, and for anything that is not a read the CSRF token and the
// origin. It answers the error itself.
func (a *API) adminAuth(w http.ResponseWriter, r *http.Request) (*adminSession, bool) {
	token := adminToken(r)
	if token == "" {
		writeError(w, http.StatusUnauthorized, codeUnauthorized, "Entre para continuar.")
		return nil, false
	}
	idle := time.Duration(a.cfg.Admin.IdleMinutes) * time.Minute
	session, err := a.store.AdminSessionFor(r.Context(), tokenHash(token), idle)
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusUnauthorized, codeUnauthorized, "Sessão encerrada. Entre de novo.")
		return nil, false
	}
	if err != nil {
		a.fail(w, err)
		return nil, false
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-CSRF-Token")), []byte(session.CSRF)) != 1 {
			writeError(w, http.StatusForbidden, "csrf", "Token de segurança inválido. Recarregue a página.")
			return nil, false
		}
		if origin := r.Header.Get("Origin"); origin != "" && !sameHost(origin, r.Host) {
			writeError(w, http.StatusForbidden, "csrf", "Origem não permitida.")
			return nil, false
		}
	}
	session.IP = a.clientIP(r)
	return &session, true
}

func sameHost(origin, host string) bool {
	trimmed := strings.TrimPrefix(strings.TrimPrefix(origin, "https://"), "http://")
	return strings.EqualFold(trimmed, host)
}

func (a *API) adminSetCookie(w http.ResponseWriter, r *http.Request, token string, maxAge int) {
	secure := r.TLS != nil
	if a.cfg.TrustProxy && strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
		secure = true
	}
	switch a.cfg.Admin.SecureCookie {
	case "1":
		secure = true
	case "0":
		secure = false
	}
	http.SetCookie(w, &http.Cookie{Name: adminCookie, Value: token, Path: "/admin", HttpOnly: true, Secure: secure, SameSite: http.SameSiteStrictMode, MaxAge: maxAge})
}

// validAdminPassword: staff passwords are longer than the players'.
func validAdminPassword(password, username string) bool {
	length := utf8.RuneCountInString(password)
	if length < 12 || length > 128 || strings.EqualFold(password, username) {
		return false
	}
	first, _ := utf8.DecodeRuneInString(password)
	return strings.Trim(password, string(first)) != ""
}

type adminLoginBody struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Code     string `json:"code"`
}

func (a *API) adminLogin(w http.ResponseWriter, r *http.Request, s *adminSession) {
	var body adminLoginBody
	if err := readJSON(r, &body); err != nil || body.Username == "" || body.Password == "" || len(body.Username) > 64 || len(body.Password) > 256 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "Informe usuário e senha.")
		return
	}
	if !a.adminLimiter.Allow(s.IP) {
		writeError(w, http.StatusTooManyRequests, codeRateLimited, "Muitas tentativas. Espere um minuto.")
		return
	}
	ctx := r.Context()
	wrong := func() {
		writeError(w, http.StatusUnauthorized, codeCredentials, "Usuário, senha ou código incorretos.")
	}
	login, err := a.store.AdminForLogin(ctx, body.Username)
	if err != nil && !errors.Is(err, ErrNotFound) {
		a.fail(w, err)
		return
	}
	// The same work whether or not the account exists (no guessing usernames by timing).
	hash := login.Hash
	if errors.Is(err, ErrNotFound) {
		hash = a.dummyHash
	}
	passwordOK := verifyPassword(body.Password, hash)
	if errors.Is(err, ErrNotFound) || !login.Active || login.Locked {
		wrong()
		return
	}
	if !passwordOK {
		_ = a.store.AdminLoginFailed(ctx, login.ID)
		wrong()
		return
	}
	stage := "full"
	var step int64
	switch {
	case login.TOTPEnabled:
		if strings.TrimSpace(body.Code) == "" {
			writeError(w, http.StatusUnauthorized, "code_required", "Digite o código do aplicativo autenticador.")
			return
		}
		secret, err := openSecret(totpKey(a.cfg.InternalKey), login.Secret)
		if err != nil {
			a.fail(w, err)
			return
		}
		var ok bool
		if step, ok = totpVerify(secret, body.Code, time.Now(), login.LastStep); !ok {
			_ = a.store.AdminLoginFailed(ctx, login.ID)
			wrong()
			return
		}
	case a.cfg.Admin.Require2FA:
		stage = "enroll"
	}
	token, hashed, err := newToken()
	if err != nil {
		a.fail(w, err)
		return
	}
	csrf, _, err := newToken()
	if err != nil {
		a.fail(w, err)
		return
	}
	ttl := time.Duration(a.cfg.Admin.SessionHours) * time.Hour
	if err := a.store.CreateAdminSession(ctx, login.ID, hashed, csrf, stage, s.IP, ttl); err != nil {
		a.fail(w, err)
		return
	}
	if err := a.store.AdminLoginOK(ctx, login.ID, step); err != nil {
		a.fail(w, err)
		return
	}
	session := &adminSession{AdminID: login.ID, Username: login.Username, IP: s.IP}
	_ = a.store.adminDo(ctx, session, adminEntry{Action: "login", TargetType: "admin", TargetID: idText(login.ID)}, nil)
	a.adminSetCookie(w, r, token, int(ttl.Seconds()))
	writeJSON(w, http.StatusOK, a.adminMeBody(login.AdminUser, csrf, stage))
}

func (a *API) adminMeBody(user AdminUser, csrf, stage string) map[string]any {
	return map[string]any{
		"admin": user, "csrf": csrf, "stage": stage, "require_2fa": a.cfg.Admin.Require2FA,
		"must_change_password": user.MustChange, "server_time": time.Now().UTC(),
	}
}

func (a *API) adminLogout(w http.ResponseWriter, r *http.Request, s *adminSession) {
	_ = a.store.DeleteAdminSession(r.Context(), tokenHash(adminToken(r)))
	a.adminSetCookie(w, r, "", -1)
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) adminMe(w http.ResponseWriter, r *http.Request, s *adminSession) {
	user, err := a.store.AdminByID(r.Context(), s.AdminID)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, a.adminMeBody(user, s.CSRF, s.Stage))
}

func (a *API) adminChangePassword(w http.ResponseWriter, r *http.Request, s *adminSession) {
	var body struct {
		Current string `json:"current"`
		New     string `json:"new"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "Pedido inválido.")
		return
	}
	ctx := r.Context()
	hash, err := a.store.AdminHash(ctx, s.AdminID)
	if err != nil {
		a.fail(w, err)
		return
	}
	if !verifyPassword(body.Current, hash) {
		writeError(w, http.StatusUnauthorized, codeCredentials, "A senha atual está incorreta.")
		return
	}
	if !validAdminPassword(body.New, s.Username) || body.New == body.Current {
		writeError(w, http.StatusBadRequest, codePassword, "A nova senha precisa ter de 12 a 128 caracteres, diferente da atual e do usuário.")
		return
	}
	hashed, err := hashPassword(body.New, a.cfg.PBKDF2Iterations)
	if err != nil {
		a.fail(w, err)
		return
	}
	err = a.store.adminDo(ctx, s, adminEntry{Action: "admin.password", TargetType: "admin", TargetID: idText(s.AdminID)}, nil)
	if err == nil {
		err = a.store.AdminSetPassword(ctx, s.AdminID, hashed, false)
	}
	if err == nil {
		// Every other session of this account ends: the old password may have been stolen.
		err = a.store.RevokeAdminSessions(ctx, s.AdminID, tokenHash(adminToken(r)))
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// adminTOTPSetup makes a new secret for the account that has no second factor yet; it only
// counts after the first code is confirmed.
func (a *API) adminTOTPSetup(w http.ResponseWriter, r *http.Request, s *adminSession) {
	if s.TOTPEnabled {
		writeError(w, http.StatusConflict, "conflict", "O segundo fator já está ativo. Peça ao dono para reiniciá-lo.")
		return
	}
	secret, err := newTOTPSecret()
	if err != nil {
		a.fail(w, err)
		return
	}
	sealed, err := sealSecret(totpKey(a.cfg.InternalKey), secret)
	if err == nil {
		err = a.store.AdminSetTOTP(r.Context(), s.AdminID, sealed)
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"secret": totpEncoding.EncodeToString(secret), "uri": totpURI(a.cfg.Admin.Issuer, s.Username, secret)})
}

func (a *API) adminTOTPConfirm(w http.ResponseWriter, r *http.Request, s *adminSession) {
	var body struct {
		Code string `json:"code"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "Pedido inválido.")
		return
	}
	ctx := r.Context()
	sealed, enabled, last, err := a.store.AdminTOTP(ctx, s.AdminID)
	if err != nil {
		a.fail(w, err)
		return
	}
	if enabled || sealed == "" {
		writeError(w, http.StatusConflict, "conflict", "Gere um novo segredo antes de confirmar.")
		return
	}
	secret, err := openSecret(totpKey(a.cfg.InternalKey), sealed)
	if err != nil {
		a.fail(w, err)
		return
	}
	step, ok := totpVerify(secret, body.Code, time.Now(), last)
	if !ok {
		writeError(w, http.StatusUnauthorized, codeCredentials, "Código incorreto. Confira o relógio do celular e tente de novo.")
		return
	}
	err = a.store.AdminEnableTOTP(ctx, s.AdminID, step)
	if err == nil {
		err = a.store.PromoteAdminSession(ctx, tokenHash(adminToken(r)))
	}
	if err == nil {
		err = a.store.adminDo(ctx, s, adminEntry{Action: "admin.totp", TargetType: "admin", TargetID: idText(s.AdminID)}, nil)
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// bootstrapAdmin creates the first owner from ADMIN_BOOTSTRAP_USER/PASSWORD when there is
// no staff account yet.
func (a *API) bootstrapAdmin(ctx context.Context) {
	cfg := a.cfg.Admin
	if !cfg.Enabled || cfg.BootstrapUser == "" {
		return
	}
	if !usernamePattern.MatchString(cfg.BootstrapUser) || !validAdminPassword(cfg.BootstrapPassword, cfg.BootstrapUser) {
		a.log.Warn("admin bootstrap skipped: ADMIN_BOOTSTRAP_USER must be 3-16 letters, digits or _ and the password 12-128 characters")
		return
	}
	hash, err := hashPassword(cfg.BootstrapPassword, a.cfg.PBKDF2Iterations)
	if err != nil {
		a.log.Error("admin bootstrap", "err", err)
		return
	}
	created, err := a.store.BootstrapAdmin(ctx, cfg.BootstrapUser, hash)
	if err != nil {
		a.log.Error("admin bootstrap", "err", err)
		return
	}
	if created {
		a.log.Info("first admin created: change the password at the first login", "username", cfg.BootstrapUser)
	}
}

func idText(id int64) string { return strconv.FormatInt(id, 10) }
