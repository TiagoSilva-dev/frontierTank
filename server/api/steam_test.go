package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
)

// fakeSteam answers the Steam Web API calls the API makes (the sandbox microtransaction
// interface): tickets, the wallet currency and the life of an order.
type fakeSteam struct {
	mu       sync.Mutex
	tickets  map[string]string // ticket → SteamID
	currency map[string]string // SteamID → wallet currency
	orders   map[string]map[string]string
	calls    []string
}

func newFakeSteam(t *testing.T) (*fakeSteam, *httptest.Server) {
	fake := &fakeSteam{tickets: map[string]string{}, currency: map[string]string{}, orders: map[string]map[string]string{}}
	server := httptest.NewServer(http.HandlerFunc(fake.serve))
	t.Cleanup(server.Close)
	return fake, server
}

func steamReply(w http.ResponseWriter, response map[string]any) {
	_ = json.NewEncoder(w).Encode(map[string]any{"response": response})
}

func steamFailure(w http.ResponseWriter, code int, desc string) {
	steamReply(w, map[string]any{"result": "Failure", "error": map[string]any{"errorcode": code, "errordesc": desc}})
}

func (f *fakeSteam) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	_ = r.ParseForm()
	f.calls = append(f.calls, r.Method+" "+r.URL.Path)
	if r.Form.Get("key") != "publisher-key" || r.Form.Get("appid") != "480" {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	switch r.URL.Path {
	case "/ISteamUserAuth/AuthenticateUserTicket/v1/":
		steamID, ok := f.tickets[r.Form.Get("ticket")]
		if !ok || r.Form.Get("identity") != "frontiertank" {
			steamReply(w, map[string]any{"error": map[string]any{"errorcode": 101, "errordesc": "Invalid ticket"}})
			return
		}
		steamReply(w, map[string]any{"params": map[string]any{"result": "OK", "steamid": steamID, "ownersteamid": steamID, "vacbanned": false, "publisherbanned": false}})
	case "/ISteamMicroTxnSandbox/GetUserInfo/v2/":
		steamReply(w, map[string]any{"result": "OK", "params": map[string]any{"state": "", "country": "BR", "currency": f.currency[r.Form.Get("steamid")], "status": "Active"}})
	case "/ISteamMicroTxnSandbox/InitTxn/v3/":
		if r.Method != http.MethodPost || r.Form.Get("itemcount") != "1" || r.Form.Get("usersession") != "client" || r.Form.Get("itemid[0]") == "" || r.Form.Get("description[0]") == "" {
			steamFailure(w, 2, "bad InitTxn")
			return
		}
		f.orders[r.Form.Get("orderid")] = map[string]string{"status": "Init", "steamid": r.Form.Get("steamid"), "amount": r.Form.Get("amount[0]"), "currency": r.Form.Get("currency"), "itemid": r.Form.Get("itemid[0]"), "language": r.Form.Get("language"), "description": r.Form.Get("description[0]")}
		steamReply(w, map[string]any{"result": "OK", "params": map[string]any{"orderid": r.Form.Get("orderid"), "transid": "9" + r.Form.Get("orderid")}})
	case "/ISteamMicroTxnSandbox/FinalizeTxn/v2/":
		order := f.orders[r.Form.Get("orderid")]
		if order == nil || order["status"] != "Approved" {
			steamFailure(w, 100, "Order not approved")
			return
		}
		order["status"] = "Succeeded"
		steamReply(w, map[string]any{"result": "OK", "params": map[string]any{"orderid": r.Form.Get("orderid")}})
	case "/ISteamMicroTxnSandbox/QueryTxn/v3/":
		order := f.orders[r.Form.Get("orderid")]
		if order == nil {
			steamFailure(w, 7, "Order not found")
			return
		}
		steamReply(w, map[string]any{"result": "OK", "params": map[string]any{"orderid": r.Form.Get("orderid"), "status": order["status"]}})
	default:
		http.NotFound(w, r)
	}
}

// approve: the player clicked "Authorize" in the Steam overlay.
func (f *fakeSteam) approve(orderID int64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.orders[strconv.FormatInt(orderID, 10)]["status"] = "Approved"
}

func TestSteamDisabled(t *testing.T) {
	h := newHarness(t)
	if status, reply := h.call(h.public, "POST", "/v1/auth/steam", map[string]string{"ticket": strings.Repeat("ab", 20)}, nil); status != http.StatusServiceUnavailable || reply["error"] != codeSteamUnavailable {
		t.Fatalf("without the Steam keys the Steam login is off: %d %v", status, reply)
	}
}

func TestSteam(t *testing.T) {
	fake, steamServer := newFakeSteam(t)
	h := newHarness(t, func(cfg *Config) {
		cfg.Steam = SteamClient{Base: steamServer.URL, Key: "publisher-key", AppID: 480, Identity: "frontiertank", Sandbox: true}
	})
	ctx := context.Background()
	nilo, lia := "76561198000000001", "76561198000000002"
	ticket := func(steamID string) string {
		value := strings.Repeat("0a", 30) + steamID
		fake.tickets[value] = steamID
		return value
	}
	fake.currency[nilo] = "BRL"
	fake.currency[lia] = "USD"

	// Login: a new SteamID needs the consent before an account exists.
	status, reply := h.call(h.public, "POST", "/v1/auth/steam", map[string]string{"ticket": ticket(nilo)}, nil)
	if status != http.StatusForbidden || reply["error"] != codeTermsRequired {
		t.Fatalf("a new Steam player accepts the terms first: %d %v", status, reply)
	}
	var count int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM accounts`).Scan(&count)
	if count != 0 {
		t.Fatalf("no account without consent: %d", count)
	}
	status, reply = h.call(h.public, "POST", "/v1/auth/steam", map[string]string{"ticket": ticket(nilo), "accept_terms": testTerms}, nil)
	account := reply["account"].(map[string]any)
	if status != http.StatusCreated || !strings.HasPrefix(account["username"].(string), "steam_") || account["steam"] != true || account["no_password"] != true || account["terms_version"] != testTerms {
		t.Fatalf("steam account created: %d %v", status, reply)
	}
	niloID := int64(account["id"].(float64))
	niloToken := reply["token"].(string)
	status, reply = h.call(h.public, "POST", "/v1/auth/steam", map[string]string{"ticket": ticket(nilo)}, nil)
	if status != http.StatusOK || int64(reply["account"].(map[string]any)["id"].(float64)) != niloID {
		t.Fatalf("the same SteamID logs in to the same account: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/auth/steam", map[string]string{"ticket": strings.Repeat("ff", 30)}, nil); status != http.StatusUnauthorized || reply["error"] != codeSteamInvalid {
		t.Fatalf("a ticket Steam refuses: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/auth/steam", map[string]string{"ticket": "not hex!"}, nil); status != http.StatusBadRequest {
		t.Fatalf("a malformed ticket: %d %v", status, reply)
	}
	if status, _ = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": account["username"].(string), "password": ""}, nil); status != http.StatusUnauthorized {
		t.Fatalf("a Steam account has no password to log in with: %d", status)
	}
	var access int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM access_log WHERE account_id = $1 AND action LIKE 'steam_%'`, niloID).Scan(&access)
	if access != 2 {
		t.Fatalf("Steam logins are in the access log: %d", access)
	}

	// Linking Steam to an account that already exists (web tests).
	_, reply = h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": "lia", "password": "senha-forte-1", "accept_terms": testTerms}, nil)
	liaID := int64(reply["account"].(map[string]any)["id"].(float64))
	liaAuth := map[string]string{"Authorization": "Bearer " + reply["token"].(string)}
	if status, reply = h.call(h.public, "POST", "/v1/me/steam", map[string]string{"ticket": ticket(nilo)}, liaAuth); status != http.StatusConflict || reply["error"] != codeSteamTaken {
		t.Fatalf("a SteamID links to one account: %d %v", status, reply)
	}
	if status, reply = h.call(h.public, "POST", "/v1/me/steam", map[string]string{"ticket": ticket(lia)}, liaAuth); status != http.StatusOK || reply["account"].(map[string]any)["steam"] != true {
		t.Fatalf("link: %d %v", status, reply)
	}
	if _, reply = h.call(h.public, "POST", "/v1/auth/steam", map[string]string{"ticket": ticket(lia)}, nil); int64(reply["account"].(map[string]any)["id"].(float64)) != liaID {
		t.Fatalf("after linking, the Steam login opens the old account: %v", reply)
	}

	// Purchases: the game server sends the product; the price is in the wallet currency.
	product := map[string]any{"sku": "pacote_tinturas", "steam_item_id": 1100, "description": "Pacote de Tinturas", "language": "pt",
		"items":  []map[string]any{{"id": "cabelo_rosa_neon", "quality": "normal", "level": 0, "bound": true}, {"id": "cabelo_aurora", "quality": "normal", "level": 0, "bound": true}},
		"prices": map[string]int{"USD": 299, "BRL": 1499}}
	initOrder := func(account int64) (int, map[string]any) {
		body := map[string]any{"account_id": account}
		for key, value := range product {
			body[key] = value
		}
		return h.internalCall("POST", "/internal/store/init", body)
	}
	_, reply = h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": "semsteam", "password": "senha-forte-1", "accept_terms": testTerms}, nil)
	if status, reply = initOrder(int64(reply["account"].(map[string]any)["id"].(float64))); status != http.StatusConflict || reply["error"] != codeSteamRequired {
		t.Fatalf("purchases need a Steam account: %d %v", status, reply)
	}
	status, reply = initOrder(niloID)
	if status != http.StatusOK || reply["currency"] != "BRL" || reply["amount"].(float64) != 1499 {
		t.Fatalf("init in the wallet currency: %d %v", status, reply)
	}
	orderID := int64(reply["order_id"].(float64))
	sent := fake.orders[strconv.FormatInt(orderID, 10)]
	if sent["steamid"] != nilo || sent["amount"] != "1499" || sent["itemid"] != "1100" || sent["language"] != "pt" || sent["description"] != "Pacote de Tinturas" {
		t.Fatalf("InitTxn got the order: %v", sent)
	}
	finalize := func(account, order int64) (int, map[string]any) {
		return h.internalCall("POST", "/internal/store/finalize", map[string]any{"server_id": "s1", "account_id": account, "order_id": order})
	}
	if status, reply = finalize(niloID, orderID); status != http.StatusBadGateway {
		t.Fatalf("an order the player did not approve is not charged: %d %v", status, reply)
	}
	if status, _ = finalize(liaID, orderID); status != http.StatusNotFound {
		t.Fatalf("another account cannot finalize the order: %d", status)
	}
	fake.approve(orderID)
	status, reply = finalize(niloID, orderID)
	if status != http.StatusOK || reply["order"].(map[string]any)["status"] != "paid" {
		t.Fatalf("finalize: %d %v", status, reply)
	}
	var letters int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id = $1 AND kind = 'store' AND item->>'bound' = 'true'`, niloID).Scan(&letters)
	if letters != 2 {
		t.Fatalf("each item arrives in the Correio, bound: %d", letters)
	}
	if status, _ = finalize(niloID, orderID); status != http.StatusOK {
		t.Fatalf("finalizing again answers again: %d", status)
	}
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id = $1 AND kind = 'store'`, niloID).Scan(&letters)
	if letters != 2 {
		t.Fatalf("an order is delivered once: %d", letters)
	}
	if status, reply = h.internalCall("POST", "/internal/store/cancel", map[string]any{"account_id": niloID, "order_id": orderID}); status != http.StatusConflict || reply["error"] != codeOrderState {
		t.Fatalf("a paid order cannot be cancelled: %d %v", status, reply)
	}
	var audited int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM audit_log WHERE kind = 'store.paid' AND account_id = $1`, niloID).Scan(&audited)
	if audited != 1 {
		t.Fatalf("the payment is in the audit log: %d", audited)
	}

	// The player approved but the game closed: the next login delivers it.
	_, reply = initOrder(niloID)
	lost := int64(reply["order_id"].(float64))
	fake.approve(lost)
	h.store.pool.Exec(ctx, `UPDATE store_orders SET created_at = now() - interval '2 minutes' WHERE order_id = $1`, lost)
	status, reply = h.internalCall("POST", "/internal/store/reconcile", map[string]any{"server_id": "s1", "account_id": niloID})
	if delivered := reply["delivered"].([]any); status != http.StatusOK || len(delivered) != 1 || int64(delivered[0].(float64)) != lost {
		t.Fatalf("reconcile delivers approved orders: %d %v", status, reply)
	}
	// Given up in the overlay: cancelled, nothing charged.
	_, reply = initOrder(niloID)
	dropped := int64(reply["order_id"].(float64))
	if status, reply = h.internalCall("POST", "/internal/store/cancel", map[string]any{"account_id": niloID, "order_id": dropped}); status != http.StatusOK || reply["order"].(map[string]any)["status"] != "cancelled" {
		t.Fatalf("cancel: %d %v", status, reply)
	}
	fake.currency[lia] = "JPY"
	if status, reply = initOrder(liaID); status != http.StatusConflict || reply["error"] != codeCurrency {
		t.Fatalf("a currency without a price is refused: %d %v", status, reply)
	}

	// The copy of the data has the SteamID and the orders.
	request, _ := http.NewRequest("GET", h.public.URL+"/v1/me/export", nil)
	request.Header.Set("Authorization", "Bearer "+niloToken)
	response, _ := http.DefaultClient.Do(request)
	var export map[string]any
	_ = json.NewDecoder(response.Body).Decode(&export)
	response.Body.Close()
	if export["steam"].(map[string]any)["steam_id"] != nilo || len(export["store_orders"].([]any)) != 3 {
		t.Fatalf("export with Steam data: %v %v", export["steam"], export["store_orders"])
	}

	// Deleting a Steam-only account: a fresh ticket of the same SteamID confirms it.
	auth := map[string]string{"Authorization": "Bearer " + niloToken}
	if status, _ = h.call(h.public, "DELETE", "/v1/me", map[string]string{"password": ""}, auth); status != http.StatusUnauthorized {
		t.Fatalf("no password, no ticket: %d", status)
	}
	if status, _ = h.call(h.public, "DELETE", "/v1/me", map[string]string{"steam_ticket": ticket(lia)}, auth); status != http.StatusUnauthorized {
		t.Fatalf("another SteamID's ticket does not delete: %d", status)
	}
	if status, _ = h.call(h.public, "DELETE", "/v1/me", map[string]string{"steam_ticket": ticket(nilo)}, auth); status != http.StatusNoContent {
		t.Fatalf("delete with the Steam ticket: %d", status)
	}
	var kept int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM store_orders WHERE account_id IS NULL AND steam_id = $1`, nilo).Scan(&kept)
	if kept != 3 {
		t.Fatalf("orders stay for the legal period, without the account: %d", kept)
	}
	// Linked accounts with a password still use the password (internal route too).
	if status, _ = h.internalCall("POST", "/internal/accounts/"+strconv.FormatInt(liaID, 10)+"/delete", map[string]string{"steam_ticket": ticket(lia)}); status != http.StatusUnauthorized {
		t.Fatalf("an account with a password is deleted with the password: %d", status)
	}
	if status, _ = h.internalCall("POST", "/internal/accounts/"+strconv.FormatInt(liaID, 10)+"/delete", map[string]string{"password": "senha-forte-1"}); status != http.StatusNoContent {
		t.Fatalf("internal delete with password: %d", status)
	}
}
