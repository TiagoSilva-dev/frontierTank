package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
)

// Privacy and accounts (launch checklist, LGPD/GDPR): the version of the Terms of Use
// and Privacy Policy each account accepted, the player's copy of their data and the
// deletion of the account from inside the game (through the game server, which drops
// its copy of the profile first).

const (
	codeTermsRequired = "terms_required"
	codeTermsOutdated = "terms_outdated"
)

func (a *API) privacyRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/legal", a.legal)
	mux.HandleFunc("POST /v1/me/terms", a.acceptTerms)
	mux.HandleFunc("GET /v1/me/export", a.exportMe)
}

func (a *API) privacyInternalRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /internal/accounts/{id}/delete", a.deleteAccountInternal)
}

// checkTerms: "" when `version` is the current one; the error code otherwise.
func (a *API) checkTerms(version string) string {
	switch {
	case version == "":
		return codeTermsRequired
	case version != a.cfg.LegalVersion:
		return codeTermsOutdated
	}
	return ""
}

func (a *API) legal(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"version": a.cfg.LegalVersion})
}

func (a *API) acceptTerms(w http.ResponseWriter, r *http.Request) {
	account, ok := a.sessionAccount(w, r)
	if !ok {
		return
	}
	var body struct {
		Version string `json:"version"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	if code := a.checkTerms(body.Version); code != "" {
		writeError(w, http.StatusBadRequest, code, "accept the current terms: "+a.cfg.LegalVersion)
		return
	}
	if err := a.store.AcceptTerms(r.Context(), account.ID, body.Version); err != nil {
		a.fail(w, err)
		return
	}
	account.TermsVersion = body.Version
	writeJSON(w, http.StatusOK, map[string]any{"account": account})
}

// exportMe: everything stored about the account, as JSON (right of access and
// portability). Only the player's own data: other players appear by what the game
// already showed them (the buyer's character name in a sale letter).
func (a *API) exportMe(w http.ResponseWriter, r *http.Request) {
	account, ok := a.sessionAccount(w, r)
	if !ok {
		return
	}
	if !a.limiter.Allow("export:" + strconv.FormatInt(account.ID, 10)) {
		writeError(w, http.StatusTooManyRequests, codeRateLimited, "too many exports")
		return
	}
	data, err := a.store.ExportAccount(r.Context(), account.ID)
	if err != nil {
		a.fail(w, err)
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="frontier_tank_`+account.Username+`.json"`)
	writeJSON(w, http.StatusOK, data)
}

// deleteAccountInternal: the game server asks, with the password the player typed, after
// dropping its own copy of the profile (so nothing is saved back).
func (a *API) deleteAccountInternal(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
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
	if !a.limiter.Allow("delete:" + strconv.FormatInt(id, 10)) {
		writeError(w, http.StatusTooManyRequests, codeRateLimited, "too many attempts")
		return
	}
	hash, err := a.store.AccountPasswordHash(r.Context(), id)
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, codeNotFound, "no such account")
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	if !verifyPassword(body.Password, hash) {
		writeError(w, http.StatusUnauthorized, codeCredentials, "wrong password")
		return
	}
	if err := a.store.DeleteAccount(r.Context(), id); err != nil {
		a.fail(w, err)
		return
	}
	a.log.Info("account deleted from the game", "id", id)
	w.WriteHeader(http.StatusNoContent)
}

// ---------- store ----------

func (s *Store) AcceptTerms(ctx context.Context, id int64, version string) error {
	_, err := s.pool.Exec(ctx, `UPDATE accounts SET terms_version = $2, terms_accepted_at = now() WHERE id = $1`, id, version)
	return err
}

// exportQueries: each one returns a JSON value for the account $1.
var exportQueries = []struct {
	key string
	sql string
}{
	{"account", `SELECT json_build_object('id', id, 'username', username, 'created_at', created_at, 'last_login', last_login, 'banned', banned, 'terms_version', terms_version, 'terms_accepted_at', terms_accepted_at) FROM accounts WHERE id = $1`},
	{"profile", `SELECT COALESCE((SELECT json_build_object('name', name, 'data', data, 'version', version, 'updated_at', updated_at) FROM profiles WHERE account_id = $1), 'null'::json)`},
	{"sessions", `SELECT COALESCE(json_agg(json_build_object('created_at', created_at, 'expires_at', expires_at) ORDER BY created_at DESC), '[]'::json) FROM sessions WHERE account_id = $1`},
	{"presence", `SELECT COALESCE((SELECT json_build_object('server_id', server_id, 'expires_at', expires_at) FROM presence WHERE account_id = $1), 'null'::json)`},
	{"auction_listings", `SELECT COALESCE(json_agg(json_build_object('id', id, 'kind', kind, 'item', item, 'price_solar', price_solar, 'price_estrela', price_estrela, 'fee_solar', fee_solar, 'fee_estrela', fee_estrela, 'status', status, 'created_at', created_at, 'expires_at', expires_at, 'closed_at', closed_at) ORDER BY id DESC), '[]'::json) FROM auction_listings WHERE seller_id = $1`},
	{"auction_purchases", `SELECT COALESCE(json_agg(json_build_object('id', id, 'kind', kind, 'item', item, 'price_solar', price_solar, 'price_estrela', price_estrela, 'closed_at', closed_at) ORDER BY id DESC), '[]'::json) FROM auction_listings WHERE buyer_id = $1`},
	{"mail", `SELECT COALESCE(json_agg(json_build_object('id', id, 'kind', kind, 'item_kind', item_kind, 'item', item, 'currencies', currencies, 'coins', coins, 'detail', detail, 'created_at', created_at, 'claimed_at', claimed_at) ORDER BY id DESC), '[]'::json) FROM mail WHERE account_id = $1`},
	{"access_log", `SELECT COALESCE(json_agg(json_build_object('ip', ip, 'action', action, 'created_at', created_at) ORDER BY created_at DESC), '[]'::json) FROM access_log WHERE account_id = $1`},
	{"activity_log", `SELECT COALESCE(json_agg(json_build_object('kind', kind, 'detail', detail, 'server_id', server_id, 'created_at', created_at) ORDER BY created_at DESC), '[]'::json) FROM (SELECT kind, detail, server_id, created_at FROM audit_log WHERE account_id = $1 ORDER BY created_at DESC LIMIT 20000) recent`},
}

// extraExports are added by other parts of the API (chat reports, Steam).
var extraExports []struct {
	key string
	sql string
}

func (s *Store) ExportAccount(ctx context.Context, id int64) (map[string]any, error) {
	result := map[string]any{"exported_at": time.Now().UTC().Format(time.RFC3339), "format": "frontier-tank-export-1"}
	err := pgx.BeginTxFunc(ctx, s.pool, pgx.TxOptions{AccessMode: pgx.ReadOnly, IsoLevel: pgx.RepeatableRead}, func(tx pgx.Tx) error {
		for _, query := range append(append([]struct{ key, sql string }{}, exportQueries...), extraExports...) {
			var value json.RawMessage
			if err := tx.QueryRow(ctx, query.sql, id).Scan(&value); err != nil {
				return err
			}
			result[query.key] = value
		}
		return nil
	})
	return result, err
}

// LogAccess records the IP, date and time of a login or a new account (Marco Civil da
// Internet, art. 15: kept for 6 months).
func (s *Store) LogAccess(ctx context.Context, accountID int64, ip, action string) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO access_log (account_id, ip, action) VALUES ($1, $2, $3)`, accountID, ip, action)
	return err
}

// Retention of the logs (privacy policy): chat lines go sooner than the rest of the
// audit log; access logs stay the 6 months the law asks for.
type Retention struct {
	AuditDays  int
	ChatDays   int
	AccessDays int
	// Chat reports, counted from the review (open reports stay until reviewed).
	ReportDays int
}

func (s *Store) PurgeAudit(ctx context.Context, keep Retention) error {
	if keep.ChatDays > 0 {
		if _, err := s.pool.Exec(ctx, `DELETE FROM audit_log WHERE kind = 'chat' AND created_at < now() - make_interval(days => $1)`, keep.ChatDays); err != nil {
			return err
		}
	}
	if keep.AuditDays > 0 {
		if _, err := s.pool.Exec(ctx, `DELETE FROM audit_log WHERE created_at < now() - make_interval(days => $1)`, keep.AuditDays); err != nil {
			return err
		}
	}
	if err := s.PurgeReports(ctx, keep.ReportDays); err != nil {
		return err
	}
	if keep.AccessDays > 0 {
		if _, err := s.pool.Exec(ctx, `DELETE FROM access_log WHERE created_at < now() - make_interval(days => $1)`, keep.AccessDays); err != nil {
			return err
		}
	}
	return nil
}
