package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/cookiejar"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The admin panel: TOTP, login and its limits, roles, CSRF, every action and its record in
// admin_audit. Needs PostgreSQL (TEST_DATABASE_URL) like the other integration tests.

func TestTOTP(t *testing.T) {
	// RFC 6238, appendix B: the SHA-1 secret "12345678901234567890" at T = 59 s is 94287082
	// with 8 digits, so 287082 with 6.
	secret := []byte("12345678901234567890")
	if code := hotp(secret, 1); code != "287082" {
		t.Fatalf("hotp(1) = %s, want 287082", code)
	}
	now := time.Unix(59, 0)
	step, ok := totpVerify(secret, "287082", now, 0)
	if !ok || step != 1 {
		t.Fatalf("the code of the current step verifies: %d %v", step, ok)
	}
	if _, ok := totpVerify(secret, "287082", now, step); ok {
		t.Fatal("the same code is not valid twice")
	}
	if _, ok := totpVerify(secret, hotp(secret, 2), now, step); !ok {
		t.Fatal("the next step is accepted (clock drift)")
	}
	if _, ok := totpVerify(secret, hotp(secret, 5), now, 0); ok {
		t.Fatal("a step far away is refused")
	}
	if _, ok := totpVerify(secret, "28 70 82", now, 0); !ok {
		t.Fatal("spaces in the code are ignored")
	}
	if _, ok := totpVerify(secret, "12345", now, 0); ok {
		t.Fatal("short codes are refused")
	}
	key := totpKey("a-long-internal-key")
	sealed, err := sealSecret(key, secret)
	if err != nil || strings.Contains(sealed, "MTIzNDU2") {
		t.Fatalf("the secret is sealed: %v %s", err, sealed)
	}
	back, err := openSecret(key, sealed)
	if err != nil || !bytes.Equal(back, secret) {
		t.Fatalf("the sealed secret opens: %v", err)
	}
	if _, err := openSecret(totpKey("another-key-entirely"), sealed); err == nil {
		t.Fatal("another key does not open it")
	}
	if !strings.HasPrefix(totpURI("Gustfire", "ana", secret), "otpauth://totp/Gustfire:ana?") {
		t.Fatal("the URI is an otpauth link")
	}
}

func TestAllowList(t *testing.T) {
	list, err := parseAllowList("10.0.0.0/8, 203.0.113.7")
	if err != nil || len(list) != 2 {
		t.Fatalf("parse: %v %v", list, err)
	}
	a := &API{cfg: Config{Admin: AdminConfig{AllowIPs: list}}}
	for ip, want := range map[string]bool{"10.2.3.4": true, "203.0.113.7": true, "203.0.113.8": false, "192.168.0.1": false, "not-an-ip": false} {
		if a.adminAllowed(ip) != want {
			t.Errorf("adminAllowed(%s) should be %v", ip, want)
		}
	}
	if _, err := parseAllowList("300.1.1.1"); err == nil {
		t.Fatal("a bad address is a configuration error")
	}
}

// ---------- helpers ----------

type adminClient struct {
	t    *testing.T
	base string
	http *http.Client
	csrf string
}

func adminOptions(require2FA bool) func(*Config) {
	return func(cfg *Config) {
		cfg.Admin = AdminConfig{Enabled: true, Require2FA: require2FA, SessionHours: 12, IdleMinutes: 120, Issuer: "Gustfire", AuditDays: 0}
	}
}

func (h *harness) newAdmin(username, role, password string) int64 {
	h.t.Helper()
	hash, err := hashPassword(password, 1000)
	if err != nil {
		h.t.Fatal(err)
	}
	id, err := h.store.CreateAdmin(context.Background(), username, hash, role, "test", false)
	if err != nil {
		h.t.Fatal(err)
	}
	return id
}

func (h *harness) adminClient() *adminClient {
	jar, _ := cookiejar.New(nil)
	return &adminClient{t: h.t, base: h.public.URL, http: &http.Client{Jar: jar}}
}

// do sends a JSON request and decodes the JSON answer (an object or an array).
func (c *adminClient) do(method, path string, body any) (int, any) {
	c.t.Helper()
	var reader io.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		reader = bytes.NewReader(data)
	}
	request, _ := http.NewRequest(method, c.base+path, reader)
	if body != nil || method != http.MethodGet {
		request.Header.Set("Content-Type", "application/json")
	}
	if c.csrf != "" {
		request.Header.Set("X-CSRF-Token", c.csrf)
	}
	response, err := c.http.Do(request)
	if err != nil {
		c.t.Fatal(err)
	}
	defer response.Body.Close()
	data, _ := io.ReadAll(response.Body)
	var decoded any
	_ = json.Unmarshal(data, &decoded)
	return response.StatusCode, decoded
}

func (c *adminClient) get(path string) (int, any)            { return c.do("GET", path, nil) }
func (c *adminClient) post(path string, body any) (int, any) { return c.do("POST", path, body) }

func obj(value any) map[string]any {
	if m, ok := value.(map[string]any); ok {
		return m
	}
	return map[string]any{}
}

func list(value any) []any {
	if l, ok := value.([]any); ok {
		return l
	}
	return nil
}

func (c *adminClient) login(username, password, code string) (int, map[string]any) {
	c.t.Helper()
	status, reply := c.post("/admin/api/login", map[string]string{"username": username, "password": password, "code": code})
	if status == http.StatusOK {
		c.csrf = obj(reply)["csrf"].(string)
	}
	return status, obj(reply)
}

// loggedIn: a staff account of the role, already signed in (second factor off).
func (h *harness) loggedIn(role string) *adminClient {
	h.t.Helper()
	name := "staff_" + role
	h.newAdmin(name, role, "senha-da-equipe-1")
	client := h.adminClient()
	if status, reply := client.login(name, "senha-da-equipe-1", ""); status != http.StatusOK {
		h.t.Fatalf("login %s: %d %v", role, status, reply)
	}
	return client
}

func (h *harness) register(username string) int64 {
	h.t.Helper()
	status, reply := h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": username, "password": "senha-forte-1", "accept_terms": testTerms}, nil)
	if status != http.StatusCreated {
		h.t.Fatalf("register %s: %d %v", username, status, reply)
	}
	return int64(reply["account"].(map[string]any)["id"].(float64))
}

func (h *harness) auditActions(account int64) []string {
	h.t.Helper()
	rows, err := h.store.pool.Query(context.Background(), `SELECT action FROM admin_audit WHERE account_id = $1 ORDER BY id`, account)
	if err != nil {
		h.t.Fatal(err)
	}
	defer rows.Close()
	var actions []string
	for rows.Next() {
		var action string
		_ = rows.Scan(&action)
		actions = append(actions, action)
	}
	return actions
}

// ---------- tests ----------

func TestAdminDisabled(t *testing.T) {
	h := newHarness(t)
	for _, path := range []string{"/admin/", "/admin/api/me", "/admin/static/admin.js"} {
		if status, _ := h.call(h.public, "GET", path, nil, nil); status != http.StatusNotFound {
			t.Errorf("%s without ADMIN_ENABLED must be 404, got %d", path, status)
		}
	}
}

func TestAdminLoginAndSecondFactor(t *testing.T) {
	h := newHarness(t, adminOptions(true))
	h.newAdmin("dona", "owner", "senha-da-equipe-1")
	client := h.adminClient()

	if status, _ := client.get("/admin/api/overview"); status != http.StatusUnauthorized {
		t.Fatalf("no session: %d", status)
	}
	if status, reply := client.login("dona", "senha-errada-123", ""); status != http.StatusUnauthorized || reply["error"] != codeCredentials {
		t.Fatalf("wrong password: %d %v", status, reply)
	}
	if status, reply := client.login("ninguem", "senha-da-equipe-1", ""); status != http.StatusUnauthorized || reply["error"] != codeCredentials {
		t.Fatalf("unknown user answers the same: %d %v", status, reply)
	}
	status, reply := client.login("DONA", "senha-da-equipe-1", "")
	if status != http.StatusOK || reply["stage"] != "enroll" {
		t.Fatalf("the first login only enrols the second factor: %d %v", status, reply)
	}
	if status, reply := client.get("/admin/api/overview"); status != http.StatusForbidden || obj(reply)["error"] != "two_factor_required" {
		t.Fatalf("data needs the second factor: %d %v", status, reply)
	}
	if status, _ := client.get("/admin/api/me"); status != http.StatusOK {
		t.Fatal("me works while enrolling")
	}
	status, setup := client.post("/admin/api/totp/setup", map[string]string{})
	if status != http.StatusOK {
		t.Fatalf("setup: %d %v", status, setup)
	}
	secret, err := totpEncoding.DecodeString(obj(setup)["secret"].(string))
	if err != nil || !strings.HasPrefix(obj(setup)["uri"].(string), "otpauth://") {
		t.Fatalf("setup gives the secret and the link: %v %v", err, setup)
	}
	step := time.Now().Unix() / totpStep
	if status, _ := client.post("/admin/api/totp/confirm", map[string]string{"code": "000000"}); status != http.StatusUnauthorized {
		t.Fatalf("a wrong code does not enrol: %d", status)
	}
	if status, reply := client.post("/admin/api/totp/confirm", map[string]string{"code": hotp(secret, step)}); status != http.StatusNoContent {
		t.Fatalf("confirm: %d %v", status, reply)
	}
	if status, _ := client.get("/admin/api/overview"); status != http.StatusOK {
		t.Fatalf("with the second factor the session is complete: %d", status)
	}
	if status, _ := client.post("/admin/api/logout", map[string]string{}); status != http.StatusNoContent {
		t.Fatalf("logout: %d", status)
	}
	if status, _ := client.get("/admin/api/overview"); status != http.StatusUnauthorized {
		t.Fatalf("after logout: %d", status)
	}

	// The next login asks for the code, and the code used to enrol is spent.
	if status, reply := client.login("dona", "senha-da-equipe-1", ""); status != http.StatusUnauthorized || reply["error"] != "code_required" {
		t.Fatalf("the code is required: %d %v", status, reply)
	}
	if status, _ := client.login("dona", "senha-da-equipe-1", hotp(secret, step)); status != http.StatusUnauthorized {
		t.Fatalf("a code that was already used is refused: %d", status)
	}
	if status, reply := client.login("dona", "senha-da-equipe-1", hotp(secret, step+1)); status != http.StatusOK || reply["stage"] != "full" {
		t.Fatalf("login with the next code: %d %v", status, reply)
	}

	// An owner clears a lost second factor; the next login enrols again.
	other := h.newAdmin("ana", "support", "senha-da-equipe-2")
	if status, _ := client.post("/admin/api/staff/"+strconv.FormatInt(other, 10)+"/reset-2fa", map[string]string{}); status != http.StatusNoContent {
		t.Fatalf("reset 2fa: %d", status)
	}
}

func TestAdminLockoutAndCSRF(t *testing.T) {
	h := newHarness(t, adminOptions(false))
	h.newAdmin("dona", "owner", "senha-da-equipe-1")
	client := h.adminClient()
	for i := 0; i < 5; i++ {
		if status, _ := client.login("dona", "senha-errada-123", ""); status != http.StatusUnauthorized {
			t.Fatalf("attempt %d: %d", i, status)
		}
	}
	if status, _ := client.login("dona", "senha-da-equipe-1", ""); status != http.StatusUnauthorized {
		t.Fatalf("five wrong passwords lock the account, even for the right one: %d", status)
	}
	if _, err := h.store.pool.Exec(context.Background(), `UPDATE admin_users SET locked_until = NULL`); err != nil {
		t.Fatal(err)
	}
	if status, reply := client.login("dona", "senha-da-equipe-1", ""); status != http.StatusOK {
		t.Fatalf("after the lock: %d %v", status, reply)
	}

	// Changes need the token of the session, a JSON body and the right origin.
	good := client.csrf
	client.csrf = ""
	if status, reply := client.post("/admin/api/staff", map[string]string{"username": "novo_um", "role": "viewer"}); status != http.StatusForbidden || obj(reply)["error"] != "csrf" {
		t.Fatalf("no CSRF token: %d %v", status, reply)
	}
	client.csrf = good
	request, _ := http.NewRequest("POST", client.base+"/admin/api/staff", strings.NewReader(`{"username":"novo_um","role":"viewer"}`))
	request.Header.Set("Content-Type", "text/plain")
	request.Header.Set("X-CSRF-Token", good)
	response, _ := client.http.Do(request)
	response.Body.Close()
	if response.StatusCode != http.StatusUnsupportedMediaType {
		t.Fatalf("a form post is refused: %d", response.StatusCode)
	}
	request, _ = http.NewRequest("POST", client.base+"/admin/api/staff", strings.NewReader(`{"username":"novo_um","role":"viewer"}`))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-CSRF-Token", good)
	request.Header.Set("Origin", "https://evil.example")
	response, _ = client.http.Do(request)
	response.Body.Close()
	if response.StatusCode != http.StatusForbidden {
		t.Fatalf("another origin is refused: %d", response.StatusCode)
	}
	if status, reply := client.post("/admin/api/staff", map[string]string{"username": "novo_um", "role": "viewer"}); status != http.StatusCreated || obj(reply)["password"] == nil {
		t.Fatalf("create staff: %d %v", status, reply)
	}

	// The security headers are on every answer.
	response, _ = client.http.Get(client.base + "/admin/")
	response.Body.Close()
	if !strings.Contains(response.Header.Get("Content-Security-Policy"), "script-src 'self'") || response.Header.Get("X-Frame-Options") != "DENY" {
		t.Fatalf("security headers: %v", response.Header)
	}
}

func TestAdminRolesAndPasswords(t *testing.T) {
	h := newHarness(t, adminOptions(false))
	owner := h.loggedIn("owner")
	player := h.register("jogador1")
	pid := "/admin/api/players/" + strconv.FormatInt(player, 10)

	// A new account gets a temporary password and must replace it before anything else.
	status, reply := owner.post("/admin/api/staff", map[string]string{"username": "nova_ana", "role": "support"})
	if status != http.StatusCreated {
		t.Fatalf("create: %d %v", status, reply)
	}
	temporary := obj(reply)["password"].(string)
	if status, _ := owner.post("/admin/api/staff", map[string]string{"username": "NOVA_ANA", "role": "support"}); status != http.StatusConflict {
		t.Fatalf("staff usernames are unique: %d", status)
	}
	ana := h.adminClient()
	if status, reply := ana.login("nova_ana", temporary, ""); status != http.StatusOK || reply["must_change_password"] != true {
		t.Fatalf("temporary login: %d %v", status, reply)
	}
	if status, reply := ana.get("/admin/api/players"); status != http.StatusForbidden || obj(reply)["error"] != "password_change_required" {
		t.Fatalf("the temporary password only changes the password: %d %v", status, reply)
	}
	if status, _ := ana.post("/admin/api/password", map[string]string{"current": temporary, "new": "curta"}); status != http.StatusBadRequest {
		t.Fatalf("a short password is refused: %d", status)
	}
	if status, _ := ana.post("/admin/api/password", map[string]string{"current": "errada-errada-1", "new": "uma-senha-nova-longa"}); status != http.StatusUnauthorized {
		t.Fatalf("the current password is checked: %d", status)
	}
	if status, _ := ana.post("/admin/api/password", map[string]string{"current": temporary, "new": "uma-senha-nova-longa"}); status != http.StatusNoContent {
		t.Fatalf("change password: %d", status)
	}
	if status, _ := ana.get("/admin/api/players"); status != http.StatusOK {
		t.Fatal("support reads players after changing the password")
	}

	// Support cannot ban, cannot see staff or the system; viewer only sees numbers.
	if status, _ := ana.post(pid+"/ban", map[string]any{"reason": "teste de papel", "hours": 0}); status != http.StatusForbidden {
		t.Fatalf("support cannot ban: %d", status)
	}
	for _, path := range []string{"/admin/api/staff", "/admin/api/system", "/admin/api/audit.csv"} {
		if status, _ := ana.get(path); status != http.StatusForbidden {
			t.Errorf("support must not read %s: %d", path, status)
		}
	}
	viewer := h.loggedIn("viewer")
	for path, want := range map[string]int{"/admin/api/overview": 200, "/admin/api/economy": 200, "/admin/api/servers": 200, "/admin/api/players": 403, "/admin/api/orders": 403, "/admin/api/audit": 403} {
		if status, _ := viewer.get(path); status != want {
			t.Errorf("viewer %s = %d, want %d", path, status, want)
		}
	}

	// Owners cannot demote themselves; others take effect at once.
	staff := list(func() any { _, v := owner.get("/admin/api/staff"); return v }())
	var anaID int64
	for _, row := range staff {
		if obj(row)["username"] == "nova_ana" {
			anaID = int64(obj(row)["id"].(float64))
		}
	}
	if status, _ := owner.post("/admin/api/staff/"+strconv.FormatInt(anaID, 10)+"/update", map[string]any{"active": false}); status != http.StatusNoContent {
		t.Fatalf("deactivate: %d", status)
	}
	if status, _ := ana.get("/admin/api/players"); status != http.StatusUnauthorized {
		t.Fatalf("a deactivated account loses its session at once: %d", status)
	}
	var ownerID int64
	for _, row := range staff {
		if obj(row)["username"] == "staff_owner" {
			ownerID = int64(obj(row)["id"].(float64))
		}
	}
	if status, _ := owner.post("/admin/api/staff/"+strconv.FormatInt(ownerID, 10)+"/update", map[string]any{"role": "viewer"}); status != http.StatusConflict {
		t.Fatalf("an owner cannot demote themselves: %d", status)
	}
}

func TestAdminPlayerActions(t *testing.T) {
	h := newHarness(t, adminOptions(false))
	admin := h.loggedIn("admin")
	support := h.adminClient()
	h.newAdmin("suporte", "support", "senha-da-equipe-3")
	support.login("suporte", "senha-da-equipe-3", "")

	troll := h.newTrader("troll", "Troll")
	lia := h.newTrader("lia", "Lia")
	trollPath := "/admin/api/players/" + strconv.FormatInt(troll.id, 10)

	// Search by name, id and IP; the detail page gathers everything.
	status, reply := admin.get("/admin/api/players?q=tro")
	if status != http.StatusOK || obj(reply)["total"].(float64) != 1 {
		t.Fatalf("search by name: %d %v", status, reply)
	}
	if _, reply = admin.get("/admin/api/players?q=" + strconv.FormatInt(lia.id, 10)); obj(reply)["total"].(float64) != 1 {
		t.Fatalf("search by id: %v", reply)
	}
	if _, reply = admin.get("/admin/api/players?q=nao_existe"); obj(reply)["total"].(float64) != 0 {
		t.Fatalf("search without a match: %v", reply)
	}
	if _, reply = admin.get("/admin/api/players?q=100%25"); obj(reply)["total"].(float64) != 0 {
		t.Fatalf("a percent sign is not a wildcard: %v", reply)
	}
	status, reply = admin.get(trollPath)
	detail := obj(reply)
	if status != http.StatusOK || obj(detail["account"])["username"] != "troll" || obj(detail["profile"])["name"] != "Troll" || len(list(detail["access"])) == 0 {
		t.Fatalf("player detail: %d %v", status, reply)
	}
	if status, _ = admin.get("/admin/api/players/999999"); status != http.StatusNotFound {
		t.Fatalf("unknown player: %d", status)
	}

	// A ban needs a reason, ends the sessions and shows who did it; support cannot.
	if status, _ = admin.post(trollPath+"/ban", map[string]any{"reason": "x", "hours": 0}); status != http.StatusBadRequest {
		t.Fatalf("a ban needs a reason: %d", status)
	}
	if status, _ = support.post(trollPath+"/ban", map[string]any{"reason": "ofensas no chat", "hours": 0}); status != http.StatusForbidden {
		t.Fatalf("support cannot ban: %d", status)
	}
	if status, reply = admin.post(trollPath+"/ban", map[string]any{"reason": "ofensas no chat", "hours": 24}); status != http.StatusNoContent {
		t.Fatalf("ban: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "troll", "password": "senha-forte-1"}, nil); status != http.StatusForbidden || obj(reply)["error"] != codeBanned {
		t.Fatalf("a banned player cannot log in: %d %v", status, reply)
	}
	_, reply = admin.get(trollPath)
	account := obj(obj(reply)["account"])
	if account["banned"] != true || account["ban_reason"] != "ofensas no chat" || account["banned_by"] != "staff_admin" || account["ban_until"] == nil {
		t.Fatalf("the ban is on the page: %v", account)
	}
	if _, err := h.store.pool.Exec(context.Background(), `UPDATE accounts SET ban_until = now() - interval '1 minute' WHERE id = $1`, troll.id); err != nil {
		t.Fatal(err)
	}
	if count, err := h.store.ExpireBans(context.Background()); err != nil || count != 1 {
		t.Fatalf("a ban with a time limit ends by itself: %d %v", count, err)
	}
	if status, _ = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "troll", "password": "senha-forte-1"}, nil); status != http.StatusOK {
		t.Fatalf("the player is back after the ban: %d", status)
	}
	admin.post(trollPath+"/ban", map[string]any{"reason": "reincidência", "hours": 0})
	if status, _ = admin.post(trollPath+"/unban", map[string]any{"reason": "recurso aceito"}); status != http.StatusNoContent {
		t.Fatalf("unban: %d", status)
	}

	// Notes, sessions and the temporary password.
	if status, _ = support.post(trollPath+"/notes", map[string]string{"note": "pediu desculpas no ticket 123"}); status != http.StatusNoContent {
		t.Fatalf("note: %d", status)
	}
	if status, _ = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "troll", "password": "senha-forte-1"}, nil); status != http.StatusOK {
		t.Fatalf("login before revoking: %d", status)
	}
	if status, reply = admin.post(trollPath+"/sessions/revoke", map[string]string{"reason": "conta invadida"}); status != http.StatusOK || obj(reply)["sessions"].(float64) < 1 {
		t.Fatalf("revoke sessions: %d %v", status, reply)
	}
	status, reply = admin.post(trollPath+"/password", map[string]string{"reason": "confirmou o e-mail do ticket 123"})
	temporary, _ := obj(reply)["password"].(string)
	if status != http.StatusOK || len(temporary) != 14 {
		t.Fatalf("temporary password: %d %v", status, reply)
	}
	if status, _ = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "troll", "password": temporary}, nil); status != http.StatusOK {
		t.Fatalf("the player logs in with the temporary password: %d", status)
	}
	if _, err := h.store.pool.Exec(context.Background(), `UPDATE accounts SET password_hash = '' WHERE id = $1`, lia.id); err != nil {
		t.Fatal(err)
	}
	if status, _ = admin.post("/admin/api/players/"+strconv.FormatInt(lia.id, 10)+"/password", map[string]string{"reason": "teste de conta Steam"}); status != http.StatusConflict {
		t.Fatalf("a Steam-only account has no password to reset: %d", status)
	}

	want := []string{"player.ban", "player.unban", "player.ban", "player.unban", "player.note", "player.revoke_sessions", "player.reset_password"}
	got := h.auditActions(troll.id)
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("every action is recorded:\n got  %v\n want %v", got, want)
	}
	var reason, who string
	if err := h.store.pool.QueryRow(context.Background(), `SELECT reason, admin_name FROM admin_audit WHERE action = 'player.reset_password'`).Scan(&reason, &who); err != nil || who != "staff_admin" || !strings.Contains(reason, "ticket 123") {
		t.Fatalf("the record says who and why: %v %s %s", err, who, reason)
	}
}

func TestAdminGifts(t *testing.T) {
	h := newHarness(t, adminOptions(false))
	admin := h.loggedIn("admin")
	support := h.adminClient()
	h.newAdmin("suporte", "support", "senha-da-equipe-3")
	support.login("suporte", "senha-da-equipe-3", "")
	nilo := h.newTrader("nilo", "Nilo")
	path := "/admin/api/players/" + strconv.FormatInt(nilo.id, 10) + "/gift"

	status, reply := support.get("/admin/api/catalog")
	if status != http.StatusOK || obj(obj(reply)["gift_caps"])["coins"].(float64) != 5000 || len(list(obj(reply)["assets"])) < 10 {
		t.Fatalf("catalog: %d %v", status, reply)
	}
	gift := func(overrides map[string]any) map[string]any {
		body := map[string]any{"coins": 500, "assets": map[string]int{"estrela": 3}, "note": "Compensação pela queda de ontem", "reason": "ticket 77", "request_id": "req-" + strconv.FormatInt(time.Now().UnixNano(), 36)}
		for key, value := range overrides {
			body[key] = value
		}
		return body
	}
	bad := map[string]map[string]any{
		"unknown asset":  gift(map[string]any{"assets": map[string]int{"ouro_falso": 1}}),
		"over the cap":   gift(map[string]any{"coins": 5001}),
		"asset over cap": gift(map[string]any{"assets": map[string]int{"estrela": 51}}),
		"negative":       gift(map[string]any{"assets": map[string]int{"estrela": -1}}),
		"empty":          gift(map[string]any{"coins": 0, "assets": map[string]int{}}),
		"no note":        gift(map[string]any{"note": ""}),
		"no reason":      gift(map[string]any{"reason": "a"}),
		"no request id":  gift(map[string]any{"request_id": ""}),
	}
	for name, body := range bad {
		if status, reply := support.post(path, body); status != http.StatusBadRequest {
			t.Errorf("%s must be refused: %d %v", name, status, reply)
		}
	}
	good := gift(nil)
	if status, reply = support.post(path, good); status != http.StatusNoContent {
		t.Fatalf("gift: %d %v", status, reply)
	}
	if status, reply = support.post(path, good); status != http.StatusConflict || obj(reply)["error"] != "duplicate" {
		t.Fatalf("the same request id never sends twice: %d %v", status, reply)
	}
	letters := h.mail(nilo)
	if len(letters) != 1 {
		t.Fatalf("one letter: %v", letters)
	}
	letter := obj(letters[0])
	if letter["kind"] != "gift" || letter["coins"].(float64) != 500 || obj(letter["currencies"])["estrela"].(float64) != 3 || obj(letter["detail"])["note"] != "Compensação pela queda de ontem" {
		t.Fatalf("the letter carries the gift: %v", letter)
	}
	if status, _ = support.post("/admin/api/players/999999/gift", gift(nil)); status != http.StatusNotFound {
		t.Fatalf("a gift to nobody: %d", status)
	}
	if status, _ = admin.post(path, gift(map[string]any{"coins": 900000})); status != http.StatusNoContent {
		t.Fatalf("an admin may send more: %d", status)
	}

	// A mass sending: the number of recipients is confirmed first.
	h.newTrader("bia", "Bia")
	banned := h.newTrader("ban", "Ban")
	admin.post("/admin/api/players/"+strconv.FormatInt(banned.id, 10)+"/ban", map[string]any{"reason": "teste de envio em massa", "hours": 0})
	h.register("semperfil")
	if status, reply = admin.get("/admin/api/broadcast/count?segment=all"); status != http.StatusOK || obj(reply)["count"].(float64) != 2 {
		t.Fatalf("recipients have a character and are not banned: %d %v", status, reply)
	}
	mass := map[string]any{"segment": "all", "expect": 3, "coins": 100, "assets": map[string]int{"coroa": 2}, "note": "Presente de lançamento", "reason": "campanha de lançamento", "request_id": "mass-0001-launch"}
	if status, reply = admin.post("/admin/api/broadcast", mass); status != http.StatusConflict {
		t.Fatalf("a wrong count sends nothing: %d %v", status, reply)
	}
	if len(h.mail(nilo)) != 2 {
		t.Fatal("nothing was sent")
	}
	mass["expect"] = 2
	if status, reply = admin.post("/admin/api/broadcast", mass); status != http.StatusOK || obj(reply)["sent"].(float64) != 2 {
		t.Fatalf("broadcast: %d %v", status, reply)
	}
	if status, _ = admin.post("/admin/api/broadcast", mass); status != http.StatusConflict {
		t.Fatalf("a repeated mass sending is refused: %d", status)
	}
	if status, _ = support.post("/admin/api/broadcast", mass); status != http.StatusForbidden {
		t.Fatalf("support cannot send to everyone: %d", status)
	}
	mass["request_id"], mass["coins"] = "mass-0002-big", 100001
	if status, _ = admin.post("/admin/api/broadcast", mass); status != http.StatusBadRequest {
		t.Fatalf("a mass sending has a lower cap: %d", status)
	}
	if len(h.mail(nilo)) != 3 {
		t.Fatalf("Nilo has the two gifts and the broadcast: %v", h.mail(nilo))
	}
	if len(h.mail(banned)) != 0 {
		t.Fatal("banned players are left out")
	}
}

func TestAdminReportsAuctionAndData(t *testing.T) {
	h := newHarness(t, adminOptions(false))
	admin := h.loggedIn("admin")
	support := h.adminClient()
	h.newAdmin("suporte", "support", "senha-da-equipe-3")
	support.login("suporte", "senha-da-equipe-3", "")
	lia := h.newTrader("lia", "Lia")
	troll := h.newTrader("troll", "Troll")

	// Reports: support dismisses, only an admin bans; a ban says why.
	report := map[string]any{"server_id": "s1", "reporter_id": lia.id, "reporter_name": "Lia", "reported_id": troll.id, "reported_name": "Troll", "reason": "ofensa", "note": "", "message": "<img src=x onerror=alert(1)>",
		"context": []map[string]any{{"author": "Troll", "text": "oi"}}}
	_, reply := h.internalCall("POST", "/internal/reports", report)
	first := strconv.FormatInt(int64(reply["id"].(float64)), 10)
	_, reply = h.internalCall("POST", "/internal/reports", report)
	second := strconv.FormatInt(int64(reply["id"].(float64)), 10)
	status, listed := support.get("/admin/api/reports")
	if status != http.StatusOK || obj(listed)["total"].(float64) != 2 || obj(list(obj(listed)["rows"])[0])["message"] != "<img src=x onerror=alert(1)>" {
		t.Fatalf("open reports: %d %v", status, listed)
	}
	if status, _ = support.post("/admin/api/reports/"+first+"/review", map[string]string{"status": "dismissed", "note": "sem prova"}); status != http.StatusNoContent {
		t.Fatalf("support dismisses: %d", status)
	}
	if status, _ = support.post("/admin/api/reports/"+second+"/review", map[string]string{"status": "banned"}); status != http.StatusForbidden {
		t.Fatalf("support cannot ban from a report: %d", status)
	}
	if status, _ = admin.post("/admin/api/reports/"+second+"/review", map[string]string{"status": "banned", "note": "reincidente"}); status != http.StatusNoContent {
		t.Fatalf("admin bans from a report: %d", status)
	}
	if status, _ = admin.post("/admin/api/reports/99999/review", map[string]string{"status": "dismissed"}); status != http.StatusNotFound {
		t.Fatalf("unknown report: %d", status)
	}
	var reason, by string
	if err := h.store.pool.QueryRow(context.Background(), `SELECT ban_reason, banned_by FROM accounts WHERE id = $1`, troll.id).Scan(&reason, &by); err != nil || by != "staff_admin" || !strings.Contains(reason, second) {
		t.Fatalf("the ban from a report keeps who and why: %v %q %q", err, by, reason)
	}
	if _, listed = admin.get("/admin/api/reports?status=all"); obj(listed)["total"].(float64) != 2 {
		t.Fatalf("all reports: %v", listed)
	}

	// The auction: an admin takes a listing down and the item goes back by mail.
	if status, reply = h.list(lia, "op-1", weaponListing(1000), 10); status != http.StatusOK {
		t.Fatalf("list: %d %v", status, reply)
	}
	listing := strconv.FormatInt(int64(reply["listing"].(map[string]any)["id"].(float64)), 10)
	status, listed = admin.get("/admin/api/auction")
	if status != http.StatusOK || obj(listed)["total"].(float64) != 1 {
		t.Fatalf("auction: %d %v", status, listed)
	}
	if status, _ = support.post("/admin/api/auction/"+listing+"/cancel", map[string]string{"reason": "anúncio suspeito"}); status != http.StatusForbidden {
		t.Fatalf("support cannot cancel listings: %d", status)
	}
	if status, _ = admin.post("/admin/api/auction/"+listing+"/cancel", map[string]string{"reason": "preço absurdo, possível golpe"}); status != http.StatusNoContent {
		t.Fatalf("cancel: %d", status)
	}
	if status, _ = admin.post("/admin/api/auction/"+listing+"/cancel", map[string]string{"reason": "de novo"}); status != http.StatusConflict {
		t.Fatalf("a closed listing cannot be cancelled again: %d", status)
	}
	returned := h.mail(lia)
	if len(returned) != 1 || obj(returned[0])["kind"] != "returned" {
		t.Fatalf("the item goes back by mail: %v", returned)
	}

	// Payments, the audit log, the dashboard and the economy read without errors.
	if _, err := h.store.pool.Exec(context.Background(), `INSERT INTO store_orders (order_id, account_id, sku, description, items, amount, currency, status, provider, payment_ref)
		VALUES (nextval('store_order_seq'), $1, 'pet_raro', 'Mascote Raro', '[]', 2490, 'BRL', 'paid', 'stripe', 'pi_123')`, lia.id); err != nil {
		t.Fatal(err)
	}
	if status, listed = support.get("/admin/api/orders?q=pi_123"); status != http.StatusOK || obj(listed)["total"].(float64) != 1 || len(list(obj(listed)["by_sku_30d"])) != 1 {
		t.Fatalf("orders: %d %v", status, listed)
	}
	if status, listed = support.get("/admin/api/orders?status=paid&provider=stripe&q=" + strconv.FormatInt(lia.id, 10)); status != http.StatusOK || obj(listed)["total"].(float64) != 1 {
		t.Fatalf("orders by account: %d %v", status, listed)
	}
	if status, listed = support.get("/admin/api/audit?kind=auction.*"); status != http.StatusOK || len(list(listed)) == 0 {
		t.Fatalf("audit by kind prefix: %d %v", status, listed)
	}
	if status, _ = support.get("/admin/api/audit?account_id=" + strconv.FormatInt(lia.id, 10) + "&since=2020-01-01&until=2099-01-01&q=trovao"); status != http.StatusOK {
		t.Fatalf("audit filters: %d", status)
	}
	if status, _ = support.get("/admin/api/audit/kinds"); status != http.StatusOK {
		t.Fatalf("audit kinds: %d", status)
	}
	request, _ := http.NewRequest("GET", admin.base+"/admin/api/audit.csv", nil)
	response, err := admin.http.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	csvBody, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusOK || !strings.HasPrefix(string(csvBody), "id,quando,tipo") {
		t.Fatalf("csv: %d %s", response.StatusCode, csvBody)
	}
	if csvSafe("=HYPERLINK(1)") != "'=HYPERLINK(1)" || csvSafe("ok") != "ok" {
		t.Fatal("cells that start like a formula are neutralised")
	}
	for _, path := range []string{"/admin/api/overview", "/admin/api/economy", "/admin/api/economy/top?asset=coins", "/admin/api/economy/top?asset=estrela", "/admin/api/servers", "/admin/api/staff-actions", "/admin/api/players?status=banned&sort=login"} {
		if status, _ = admin.get(path); status != http.StatusOK {
			t.Errorf("%s: %d", path, status)
		}
	}
	if status, _ = admin.get("/admin/api/economy/top?asset=x;drop"); status != http.StatusBadRequest {
		t.Fatalf("the asset name is checked: %d", status)
	}
	_, overview := admin.get("/admin/api/overview")
	accounts := obj(obj(overview)["accounts"])
	if accounts["total"].(float64) != 2 || accounts["banned"].(float64) != 1 || len(list(obj(overview)["series"])) != 14 || len(list(obj(overview)["revenue"])) != 1 {
		t.Fatalf("overview numbers: %v", overview)
	}
	_, economy := admin.get("/admin/api/economy")
	if obj(economy)["players"].(float64) != 2 || obj(economy)["coins"].(float64) != 100 {
		t.Fatalf("economy numbers: %v", economy)
	}
}

func TestAdminLGPD(t *testing.T) {
	h := newHarness(t, adminOptions(false))
	admin := h.loggedIn("admin")
	owner := h.adminClient()
	h.newAdmin("dona", "owner", "senha-da-equipe-1")
	owner.login("dona", "senha-da-equipe-1", "")
	nilo := h.newTrader("nilo", "Nilo")
	path := "/admin/api/players/" + strconv.FormatInt(nilo.id, 10)

	if status, _ := admin.get(path + "/export?reason=pedido+por+e-mail"); status != http.StatusForbidden {
		t.Fatalf("only owners export: %d", status)
	}
	if status, _ := owner.get(path + "/export"); status != http.StatusBadRequest {
		t.Fatalf("an export needs a reason: %d", status)
	}
	status, reply := owner.get(path + "/export?reason=pedido+por+e-mail+em+06/10")
	if status != http.StatusOK || obj(obj(reply)["account"])["username"] != "nilo" {
		t.Fatalf("export: %d %v", status, reply)
	}

	if status, reply = owner.get("/admin/api/system"); status != http.StatusOK || len(list(obj(reply)["migrations"])) < 9 || obj(obj(reply)["settings"])["legal_version"] != testTerms {
		t.Fatalf("system: %d %v", status, reply)
	}

	// Deleting needs the username typed and a player who is offline.
	if status, _ = owner.do("DELETE", path, map[string]string{"reason": "pedido da pessoa", "confirm": "errado"}); status != http.StatusConflict {
		t.Fatalf("the username confirms the deletion: %d", status)
	}
	if _, err := h.store.pool.Exec(context.Background(), `INSERT INTO presence (account_id, server_id, expires_at) VALUES ($1, 's1', now() + interval '1 minute')`, nilo.id); err != nil {
		t.Fatal(err)
	}
	if status, reply = owner.do("DELETE", path, map[string]string{"reason": "pedido da pessoa", "confirm": "nilo"}); status != http.StatusConflict || !strings.Contains(obj(reply)["message"].(string), "online") {
		t.Fatalf("an online player is not deleted: %d %v", status, reply)
	}
	if _, err := h.store.pool.Exec(context.Background(), `DELETE FROM presence`); err != nil {
		t.Fatal(err)
	}
	if status, _ = admin.do("DELETE", path, map[string]string{"reason": "pedido da pessoa", "confirm": "nilo"}); status != http.StatusForbidden {
		t.Fatalf("only owners delete: %d", status)
	}
	if status, reply = owner.do("DELETE", path, map[string]string{"reason": "pedido da pessoa", "confirm": "NILO"}); status != http.StatusNoContent {
		t.Fatalf("delete: %d %v", status, reply)
	}
	if status, _ = owner.get(path); status != http.StatusNotFound {
		t.Fatalf("the account is gone: %d", status)
	}
	if actions := h.auditActions(nilo.id); strings.Join(actions, ",") != "player.export,player.delete" {
		t.Fatalf("the staff record outlives the account: %v", actions)
	}
}

func TestAdminCookie(t *testing.T) {
	cookieFor := func(options []func(*Config), headers map[string]string) *http.Cookie {
		h := newHarness(t, options...)
		h.newAdmin("dona", "owner", "senha-da-equipe-1")
		data, _ := json.Marshal(map[string]string{"username": "dona", "password": "senha-da-equipe-1"})
		request, _ := http.NewRequest("POST", h.public.URL+"/admin/api/login", bytes.NewReader(data))
		request.Header.Set("Content-Type", "application/json")
		for key, value := range headers {
			request.Header.Set(key, value)
		}
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		for _, cookie := range response.Cookies() {
			if cookie.Name == adminCookie {
				return cookie
			}
		}
		t.Fatalf("no session cookie (status %d)", response.StatusCode)
		return nil
	}
	proxied := func(cfg *Config) { cfg.TrustProxy = true }
	cookie := cookieFor([]func(*Config){adminOptions(false)}, nil)
	if !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/admin" || cookie.Secure {
		t.Fatalf("a local cookie is HttpOnly, SameSite=Strict, scoped to /admin and not Secure over plain http: %+v", cookie)
	}
	if cookie = cookieFor([]func(*Config){adminOptions(false), proxied}, map[string]string{"X-Forwarded-Proto": "https"}); !cookie.Secure {
		t.Fatal("behind a proxy that says https the cookie is Secure")
	}
	if cookie = cookieFor([]func(*Config){adminOptions(false)}, map[string]string{"X-Forwarded-Proto": "https"}); cookie.Secure {
		t.Fatal("X-Forwarded-Proto is only believed with TRUST_PROXY")
	}
	force := func(cfg *Config) { cfg.Admin.SecureCookie = "1" }
	if cookie = cookieFor([]func(*Config){adminOptions(false), force}, nil); !cookie.Secure {
		t.Fatal("ADMIN_SECURE_COOKIE=1 forces Secure")
	}
}

func TestAdminAllowListGate(t *testing.T) {
	list, _ := parseAllowList("10.0.0.0/8")
	h := newHarness(t, adminOptions(false), func(cfg *Config) { cfg.Admin.AllowIPs = list; cfg.TrustProxy = true })
	for ip, want := range map[string]int{"10.9.8.7": http.StatusUnauthorized, "198.51.100.4": http.StatusNotFound} {
		status, _ := h.call(h.public, "GET", "/admin/api/me", nil, map[string]string{"X-Forwarded-For": ip})
		if status != want {
			t.Errorf("from %s: %d, want %d", ip, status, want)
		}
	}
}
