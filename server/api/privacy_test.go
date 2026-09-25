package main

import (
	"context"
	"io"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

func TestPrivacy(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	register := func(body map[string]string) (int, map[string]any) {
		return h.call(h.public, "POST", "/v1/auth/register", body, nil)
	}
	if status, reply := register(map[string]string{"username": "semaceite", "password": "senha-forte-1"}); status != http.StatusBadRequest || reply["error"] != codeTermsRequired {
		t.Fatalf("an account needs the accepted terms: %d %v", status, reply)
	}
	if status, reply := register(map[string]string{"username": "antigo", "password": "senha-forte-1", "accept_terms": "2020-01-01"}); status != http.StatusBadRequest || reply["error"] != codeTermsOutdated {
		t.Fatalf("an old version of the terms is refused: %d %v", status, reply)
	}
	status, reply := register(map[string]string{"username": "nilo", "password": "canhao-forte", "accept_terms": testTerms})
	if status != http.StatusCreated || reply["account"].(map[string]any)["terms_version"] != testTerms {
		t.Fatalf("register with consent: %d %v", status, reply)
	}
	token := reply["token"].(string)
	auth := map[string]string{"Authorization": "Bearer " + token}
	id := int64(reply["account"].(map[string]any)["id"].(float64))
	var accepted *string
	if err := h.store.pool.QueryRow(ctx, `SELECT terms_accepted_at::text FROM accounts WHERE id = $1`, id).Scan(&accepted); err != nil || accepted == nil {
		t.Fatalf("the moment of the consent is recorded: %v", err)
	}
	if _, reply = h.call(h.public, "GET", "/v1/legal", nil, nil); reply["version"] != testTerms {
		t.Fatalf("legal version: %v", reply)
	}
	if status, _ = h.internalCall("POST", "/internal/sessions/verify", map[string]string{"token": token}); status != http.StatusOK {
		t.Fatalf("verify with the current terms: %d", status)
	}

	// New terms: the game server refuses the player until they accept them again.
	h.store.pool.Exec(ctx, `UPDATE accounts SET terms_version = '2025-01-01' WHERE id = $1`, id)
	if status, reply = h.internalCall("POST", "/internal/sessions/verify", map[string]string{"token": token}); status != http.StatusForbidden || reply["error"] != codeTermsRequired {
		t.Fatalf("outdated terms block the game server: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/me/terms", map[string]string{"version": "2025-01-01"}, auth); reply["error"] != codeTermsOutdated {
		t.Fatalf("accepting an old version does not count: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/me/terms", map[string]string{"version": testTerms}, auth); status != http.StatusOK || reply["account"].(map[string]any)["terms_version"] != testTerms {
		t.Fatalf("accept the new terms: %d %v", status, reply)
	}
	if status, _ = h.internalCall("POST", "/internal/sessions/verify", map[string]string{"token": token}); status != http.StatusOK {
		t.Fatalf("verify after accepting: %d", status)
	}

	// Export: the player's data, never the password hash or the session tokens.
	path := "/internal/profiles/" + strconv.FormatInt(id, 10)
	h.internalCall("PUT", path, map[string]any{"name": "Nilo", "data": map[string]any{"version": 5, "coins": 300}, "version": 0})
	h.internalCall("POST", "/internal/audit", map[string]any{"server_id": "s1", "entries": []map[string]any{
		{"account_id": id, "kind": "chat", "detail": map[string]any{"text": "oi pessoal"}},
		{"account_id": id, "kind": "op.create", "detail": map[string]any{"args": []string{"Nilo", "m"}}},
		{"account_id": id, "kind": "op.buy", "detail": map[string]any{"id": "quebra_tijolos"}},
	}})
	request, _ := http.NewRequest("GET", h.public.URL+"/v1/me/export", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := io.ReadAll(response.Body)
	response.Body.Close()
	body := string(data)
	if response.StatusCode != http.StatusOK || !strings.Contains(response.Header.Get("Content-Disposition"), "attachment") {
		t.Fatalf("export: %d %v", response.StatusCode, response.Header)
	}
	for _, want := range []string{`"access_log"`, `"action":"register"`, `"username":"nilo"`, `"name":"Nilo"`, `"oi pessoal"`, `"terms_version":"` + testTerms + `"`, `"activity_log"`, `"sessions"`} {
		if !strings.Contains(body, want) {
			t.Fatalf("the export has %s: %s", want, body)
		}
	}
	for _, secret := range []string{"password", "pbkdf2", "token_hash"} {
		if strings.Contains(body, secret) {
			t.Fatalf("the export never has %s", secret)
		}
	}

	// Deleting from the game (through the game server): the password is required.
	remove := func(password string) (int, map[string]any) {
		return h.internalCall("POST", "/internal/accounts/"+strconv.FormatInt(id, 10)+"/delete", map[string]string{"password": password})
	}
	if status, reply = remove("errada-123"); status != http.StatusUnauthorized || reply["error"] != codeCredentials {
		t.Fatalf("delete with a wrong password: %d %v", status, reply)
	}
	if status, _ = remove("canhao-forte"); status != http.StatusNoContent {
		t.Fatalf("delete: %d", status)
	}
	if status, _ = remove("canhao-forte"); status != http.StatusNotFound {
		t.Fatalf("an account is deleted once: %d", status)
	}
	if status, _ = h.internalCall("GET", path, nil); status != http.StatusNotFound {
		t.Fatalf("the profile goes with the account: %d", status)
	}
	var chats, anonymous int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM audit_log WHERE kind IN ('chat', 'op.create') AND (account_id = $1 OR account_id IS NULL)`, id).Scan(&chats)
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM audit_log WHERE kind = 'op.buy' AND account_id IS NULL`).Scan(&anonymous)
	if chats != 0 || anonymous != 1 {
		t.Fatalf("chat and the character name leave the log, economy records stay anonymous: %d %d", chats, anonymous)
	}
	// A game server still sending lines of the deleted account does not break the log.
	if status, _ = h.internalCall("POST", "/internal/audit", map[string]any{"server_id": "s1", "entries": []map[string]any{{"account_id": id, "kind": "op.sell", "detail": map[string]any{}}}}); status != http.StatusNoContent {
		t.Fatalf("audit of a deleted account: %d", status)
	}
	if status, _ = h.call(h.public, "GET", "/v1/me", nil, auth); status != http.StatusUnauthorized {
		t.Fatalf("the sessions go with the account: %d", status)
	}

	// The access records stay after the deletion (Marco Civil da Internet, art. 15).
	var accesses int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM access_log WHERE account_id = $1`, id).Scan(&accesses)
	if accesses != 1 {
		t.Fatalf("the access log is kept for the legal period: %d", accesses)
	}

	// Retention: chat after CHAT days, everything after AUDIT days, access after ACCESS days.
	h.store.pool.Exec(ctx, `INSERT INTO access_log (account_id, ip, action, created_at) VALUES ($1, '10.0.0.1', 'login', now() - interval '200 days')`, id)
	h.store.pool.Exec(ctx, `INSERT INTO audit_log (kind, detail, created_at) VALUES ('chat', '{}', now() - interval '100 days'), ('op.buy', '{}', now() - interval '100 days'), ('op.buy', '{}', now() - interval '400 days')`)
	if err := h.store.PurgeAudit(ctx, Retention{AuditDays: 365, ChatDays: 90, AccessDays: 183}); err != nil {
		t.Fatal(err)
	}
	var old, oldChat int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM audit_log WHERE created_at < now() - interval '90 days'`).Scan(&old)
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM audit_log WHERE kind = 'chat' AND created_at < now() - interval '90 days'`).Scan(&oldChat)
	if old != 1 || oldChat != 0 {
		t.Fatalf("retention purge: %d old rows, %d old chat", old, oldChat)
	}
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM access_log WHERE account_id = $1`, id).Scan(&accesses)
	if accesses != 1 {
		t.Fatalf("access records older than 6 months go: %d left", accesses)
	}
}
