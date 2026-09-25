package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"testing"
	"time"
)

func TestPasswordHash(t *testing.T) {
	hash, err := hashPassword("segredo-forte", 1000)
	if err != nil {
		t.Fatal(err)
	}
	if !verifyPassword("segredo-forte", hash) {
		t.Fatal("the right password must verify")
	}
	if verifyPassword("segredo-fraco", hash) {
		t.Fatal("a wrong password must not verify")
	}
	other, _ := hashPassword("segredo-forte", 1000)
	if other == hash {
		t.Fatal("each hash must use its own salt")
	}
	if passwordRounds(hash) != 1000 {
		t.Fatal("rounds are stored in the hash")
	}
	if verifyPassword("x", "md5$abc") {
		t.Fatal("unknown schemes never verify")
	}
}

func TestValidation(t *testing.T) {
	for _, name := range []string{"ab", "nome com espaço", "muito_longo_demais_x", "ção"} {
		if usernamePattern.MatchString(name) {
			t.Errorf("username %q must be rejected", name)
		}
	}
	for _, name := range []string{"tiago", "Player_01", "abc"} {
		if !usernamePattern.MatchString(name) {
			t.Errorf("username %q must be accepted", name)
		}
	}
	for _, name := range []string{"Explorador", "João Silva", "Lia-2", "Ñandú"} {
		if !validCharacterName(name) {
			t.Errorf("character name %q must be accepted", name)
		}
	}
	for _, name := range []string{"A", " Nilo", "Nilo ", "nome<script>", "quinze_letras_x"} {
		if validCharacterName(name) {
			t.Errorf("character name %q must be rejected", name)
		}
	}
}

func TestRateLimiter(t *testing.T) {
	limiter := NewRateLimiter(3, time.Minute)
	now := time.Unix(1000, 0)
	limiter.now = func() time.Time { return now }
	for i := 0; i < 3; i++ {
		if !limiter.Allow("ip") {
			t.Fatal("the first attempts pass")
		}
	}
	if limiter.Allow("ip") {
		t.Fatal("the fourth attempt in the window is blocked")
	}
	if !limiter.Allow("other") {
		t.Fatal("other keys are independent")
	}
	now = now.Add(time.Minute)
	if !limiter.Allow("ip") {
		t.Fatal("a new window allows again")
	}
}

// ---------- integration (needs PostgreSQL: TEST_DATABASE_URL) ----------

type harness struct {
	t        *testing.T
	public   *httptest.Server
	internal *httptest.Server
	key      string
}

func newHarness(t *testing.T) *harness {
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	store, err := openStore(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.pool.Exec(ctx, `DROP TABLE IF EXISTS presence, game_servers, audit_log, profiles, sessions, accounts, schema_migrations CASCADE`)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.migrate(ctx); err != nil {
		t.Fatal(err)
	}
	cfg := Config{InternalKey: "test-internal-key-123", SessionTTL: time.Hour, PBKDF2Iterations: 1000, AllowOrigin: "*", AuthPerMinute: 1000}
	api, err := newAPI(store, cfg, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	h := &harness{t: t, public: httptest.NewServer(api.publicRoutes()), internal: httptest.NewServer(api.internalRoutes()), key: cfg.InternalKey}
	t.Cleanup(func() {
		h.public.Close()
		h.internal.Close()
		store.Close()
	})
	return h
}

func (h *harness) call(base *httptest.Server, method, path string, body any, headers map[string]string) (int, map[string]any) {
	h.t.Helper()
	var reader io.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		reader = bytes.NewReader(data)
	}
	request, _ := http.NewRequest(method, base.URL+path, reader)
	for key, value := range headers {
		request.Header.Set(key, value)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		h.t.Fatal(err)
	}
	defer response.Body.Close()
	result := map[string]any{}
	_ = json.NewDecoder(response.Body).Decode(&result)
	return response.StatusCode, result
}

func (h *harness) internalCall(method, path string, body any) (int, map[string]any) {
	return h.call(h.internal, method, path, body, map[string]string{"X-Internal-Key": h.key})
}

func TestAccountsAndProfiles(t *testing.T) {
	h := newHarness(t)
	status, reply := h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": "nilo", "password": "canhao-forte"}, nil)
	if status != http.StatusCreated || reply["token"] == nil {
		t.Fatalf("register: %d %v", status, reply)
	}
	token := reply["token"].(string)
	account := reply["account"].(map[string]any)
	id := int64(account["id"].(float64))
	if status, reply = h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": "NILO", "password": "outra-senha"}, nil); status != http.StatusConflict || reply["error"] != codeTaken {
		t.Fatalf("usernames are unique regardless of case: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": "lia", "password": "curta"}, nil); reply["error"] != codePassword {
		t.Fatalf("short passwords are rejected: %v", reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "nilo", "password": "errada-123"}, nil); status != http.StatusUnauthorized || reply["error"] != codeCredentials {
		t.Fatalf("wrong password: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "fantasma", "password": "qualquer-coisa"}, nil); reply["error"] != codeCredentials {
		t.Fatalf("unknown user gives the same error: %v", reply)
	}
	status, reply = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "Nilo", "password": "canhao-forte"}, nil)
	if status != http.StatusOK {
		t.Fatalf("login: %d %v", status, reply)
	}
	second := reply["token"].(string)
	if status, _ = h.call(h.public, "GET", "/v1/me", nil, map[string]string{"Authorization": "Bearer " + second}); status != http.StatusOK {
		t.Fatalf("me: %d", status)
	}

	// Internal API: the key is required.
	if status, _ = h.call(h.internal, "POST", "/internal/sessions/verify", map[string]string{"token": token}, nil); status != http.StatusUnauthorized {
		t.Fatalf("internal API without the key must fail: %d", status)
	}
	status, reply = h.internalCall("POST", "/internal/sessions/verify", map[string]string{"token": token})
	if status != http.StatusOK || int64(reply["account"].(map[string]any)["id"].(float64)) != id {
		t.Fatalf("verify: %d %v", status, reply)
	}
	if status, _ = h.internalCall("POST", "/internal/sessions/verify", map[string]string{"token": "forjado"}); status != http.StatusUnauthorized {
		t.Fatalf("forged tokens fail: %d", status)
	}

	// Profiles with optimistic versions.
	path := "/internal/profiles/" + strconv.FormatInt(id, 10)
	if status, _ = h.internalCall("GET", path, nil); status != http.StatusNotFound {
		t.Fatalf("no profile yet: %d", status)
	}
	data := map[string]any{"version": 5, "coins": 300}
	status, reply = h.internalCall("PUT", path, map[string]any{"name": nil, "data": data, "version": 0})
	if status != http.StatusOK || reply["version"].(float64) != 1 {
		t.Fatalf("create profile: %d %v", status, reply)
	}
	if status, reply = h.internalCall("PUT", path, map[string]any{"name": nil, "data": data, "version": 0}); status != http.StatusConflict {
		t.Fatalf("creating twice conflicts: %d %v", status, reply)
	}
	data["coins"] = 450
	status, reply = h.internalCall("PUT", path, map[string]any{"name": "Nilo", "data": data, "version": 1})
	if status != http.StatusOK || reply["version"].(float64) != 2 {
		t.Fatalf("update profile: %d %v", status, reply)
	}
	if status, reply = h.internalCall("PUT", path, map[string]any{"name": "Nilo", "data": data, "version": 1}); reply["error"] != codeConflict {
		t.Fatalf("a stale version is refused: %d %v", status, reply)
	}
	status, reply = h.internalCall("GET", path, nil)
	if status != http.StatusOK || reply["name"] != "Nilo" || reply["data"].(map[string]any)["coins"].(float64) != 450 {
		t.Fatalf("read profile: %d %v", status, reply)
	}

	// Character names are unique.
	_, lia := h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": "lia", "password": "arco-iris-99"}, nil)
	liaID := int64(lia["account"].(map[string]any)["id"].(float64))
	liaPath := "/internal/profiles/" + strconv.FormatInt(liaID, 10)
	if status, reply = h.internalCall("PUT", liaPath, map[string]any{"name": "nilo", "data": data, "version": 0}); reply["error"] != codeNameTaken {
		t.Fatalf("names are unique regardless of case: %d %v", status, reply)
	}
	if _, reply = h.internalCall("GET", "/internal/names/check?name=NILO&account="+strconv.FormatInt(liaID, 10), nil); reply["taken"] != true {
		t.Fatalf("name check: %v", reply)
	}
	if _, reply = h.internalCall("GET", "/internal/names/check?name=Nilo&account="+strconv.FormatInt(id, 10), nil); reply["taken"] != false {
		t.Fatalf("your own name is not taken for you: %v", reply)
	}

	// Presence: one game server per account.
	claim := func(server string) (int, map[string]any) {
		return h.internalCall("POST", "/internal/presence/claim", map[string]any{"account_id": id, "server_id": server})
	}
	if status, _ = claim("s1"); status != http.StatusNoContent {
		t.Fatalf("claim: %d", status)
	}
	if status, _ = claim("s1"); status != http.StatusNoContent {
		t.Fatalf("the same server can claim again: %d", status)
	}
	if status, reply = claim("s2"); status != http.StatusConflict || reply["server_id"] != "s1" {
		t.Fatalf("another server is refused: %d %v", status, reply)
	}
	h.internalCall("POST", "/internal/presence/release", map[string]any{"account_id": id, "server_id": "s1"})
	if status, _ = claim("s2"); status != http.StatusNoContent {
		t.Fatalf("after release another server can claim: %d", status)
	}

	// Server list and audit.
	h.internalCall("POST", "/internal/heartbeat", map[string]any{"server": map[string]any{"id": "s1", "name": "S1", "url": "ws://localhost:7350", "online": 1, "capacity": 500}, "players": []int64{id}})
	status, reply = h.call(h.public, "GET", "/v1/servers", nil, nil)
	if servers := reply["servers"].([]any); status != http.StatusOK || len(servers) != 1 {
		t.Fatalf("servers: %d %v", status, reply)
	}
	if status, _ = h.internalCall("POST", "/internal/audit", map[string]any{"server_id": "s1", "entries": []map[string]any{{"account_id": id, "kind": "op.buy", "detail": map[string]any{"id": "quebra_tijolos"}}}}); status != http.StatusNoContent {
		t.Fatalf("audit: %d", status)
	}

	// Logout and account deletion.
	h.call(h.public, "POST", "/v1/auth/logout", nil, map[string]string{"Authorization": "Bearer " + second})
	if status, _ = h.call(h.public, "GET", "/v1/me", nil, map[string]string{"Authorization": "Bearer " + second}); status != http.StatusUnauthorized {
		t.Fatalf("logged out token fails: %d", status)
	}
	if status, _ = h.call(h.public, "DELETE", "/v1/me", map[string]string{"password": "errada-123"}, map[string]string{"Authorization": "Bearer " + token}); status != http.StatusUnauthorized {
		t.Fatalf("deletion needs the password: %d", status)
	}
	if status, _ = h.call(h.public, "DELETE", "/v1/me", map[string]string{"password": "canhao-forte"}, map[string]string{"Authorization": "Bearer " + token}); status != http.StatusNoContent {
		t.Fatalf("delete: %d", status)
	}
	if status, _ = h.internalCall("GET", path, nil); status != http.StatusNotFound {
		t.Fatalf("the profile goes with the account: %d", status)
	}
}
