package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeStripe answers the Stripe calls the API makes: opening a Checkout Session and reading it.
type fakeStripe struct {
	mu       sync.Mutex
	sessions map[string]*StripeSession
	forms    map[string]url.Values
	calls    int
	fail     bool
	pixOff   bool // the account has no Pix: Stripe refuses payment_method_types[]=pix
}

func newFakeStripe(t *testing.T) (*fakeStripe, *httptest.Server) {
	fake := &fakeStripe{sessions: map[string]*StripeSession{}, forms: map[string]url.Values{}}
	server := httptest.NewServer(http.HandlerFunc(fake.serve))
	t.Cleanup(server.Close)
	return fake, server
}

func (f *fakeStripe) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if r.Header.Get("Authorization") != "Bearer sk_test_fake" {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"type": "invalid_request_error", "message": "bad key"}})
		return
	}
	switch {
	case r.Method == http.MethodPost && r.URL.Path == "/v1/checkout/sessions":
		_ = r.ParseForm()
		f.calls++
		if f.pixOff && r.Form.Get("payment_method_types[1]") == "pix" {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"type": "invalid_request_error", "message": "The payment method type provided: pix is invalid."}})
			return
		}
		if f.fail {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"type": "invalid_request_error", "code": "payment_method_unavailable", "message": "pix is not enabled"}})
			return
		}
		amount, _ := strconv.Atoi(r.Form.Get("line_items[0][price_data][unit_amount]"))
		id := fmt.Sprintf("cs_test_%d", len(f.sessions)+1)
		session := &StripeSession{ID: id, URL: "https://checkout.stripe.test/" + id, Status: "open", PaymentStatus: "unpaid", AmountTotal: amount, Currency: r.Form.Get("line_items[0][price_data][currency]"), ClientRef: r.Form.Get("client_reference_id")}
		f.sessions[id] = session
		f.forms[id] = r.Form
		_ = json.NewEncoder(w).Encode(session)
	case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/v1/checkout/sessions/"):
		session := f.sessions[strings.TrimPrefix(r.URL.Path, "/v1/checkout/sessions/")]
		if session == nil {
			w.WriteHeader(http.StatusNotFound)
			_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"type": "invalid_request_error", "code": "resource_missing"}})
			return
		}
		_ = json.NewEncoder(w).Encode(session)
	default:
		http.NotFound(w, r)
	}
}

// pay: the player paid the page (card, or Pix confirmed).
func (f *fakeStripe) pay(id string) StripeSession {
	f.mu.Lock()
	defer f.mu.Unlock()
	session := f.sessions[id]
	session.Status, session.PaymentStatus, session.PaymentIntent = "complete", "paid", "pi_"+id
	return *session
}

func (f *fakeStripe) expire(id string) StripeSession {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sessions[id].Status = "expired"
	return *f.sessions[id]
}

const webhookSecret = "whsec_test_secret"

// webhook sends a signed event to the public API.
func (h *harness) webhook(eventID, kind string, object any, signSecret string, age time.Duration) (int, map[string]any) {
	h.t.Helper()
	payload, _ := json.Marshal(map[string]any{"id": eventID, "type": kind, "data": map[string]any{"object": object}})
	stamp := time.Now().Add(-age).Unix()
	request, _ := http.NewRequest("POST", h.public.URL+"/v1/store/stripe/webhook", bytes.NewReader(payload))
	request.Header.Set("Stripe-Signature", fmt.Sprintf("t=%d,v1=%s", stamp, signStripe(signSecret, stamp, payload)))
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		h.t.Fatal(err)
	}
	defer response.Body.Close()
	reply := map[string]any{}
	_ = json.NewDecoder(response.Body).Decode(&reply)
	return response.StatusCode, reply
}

func TestStripeSignature(t *testing.T) {
	c := &StripeClient{Key: "sk_test_fake", WebhookSecret: webhookSecret}
	body := []byte(`{"id":"evt_1"}`)
	now := time.Now()
	header := func(secret string, at time.Time, payload []byte) string {
		return fmt.Sprintf("t=%d,v1=%s", at.Unix(), signStripe(secret, at.Unix(), payload))
	}
	if err := c.VerifySignature(body, header(webhookSecret, now, body), now); err != nil {
		t.Fatalf("a good signature: %v", err)
	}
	// Stripe may send several v1 (rotating secrets): one matching is enough.
	if err := c.VerifySignature(body, "t="+strconv.FormatInt(now.Unix(), 10)+",v1=00,v1="+signStripe(webhookSecret, now.Unix(), body), now); err != nil {
		t.Fatalf("one of several signatures: %v", err)
	}
	for name, bad := range map[string]string{
		"wrong secret": header("whsec_other", now, body),
		"old":          header(webhookSecret, now.Add(-10*time.Minute), body),
		"future":       header(webhookSecret, now.Add(10*time.Minute), body),
		"empty":        "",
		"no v1":        "t=" + strconv.FormatInt(now.Unix(), 10),
		"garbage":      "xyz",
	} {
		if c.VerifySignature(body, bad, now) == nil {
			t.Errorf("%s must be refused", name)
		}
	}
	if c.VerifySignature([]byte(`{"id":"evt_2"}`), header(webhookSecret, now, body), now) == nil {
		t.Error("a changed body must be refused")
	}
	if (&StripeClient{Key: "sk_test_fake"}).VerifySignature(body, header("", now, body), now) == nil {
		t.Error("without a webhook secret nothing is accepted")
	}
}

func TestStripeDisabled(t *testing.T) {
	h := newHarness(t)
	if status, reply := h.internalCall("POST", "/internal/store/checkout", map[string]any{"account_id": 1, "sku": "x", "items": []string{}, "prices": map[string]int{"BRL": 499}}); status != http.StatusServiceUnavailable || reply["error"] != codeStripeUnavailable {
		t.Fatalf("without the key Stripe is off: %d %v", status, reply)
	}
	if status, _ := h.webhook("evt_1", "checkout.session.completed", map[string]any{}, webhookSecret, 0); status != http.StatusServiceUnavailable {
		t.Fatalf("without the key the webhook is off: %d", status)
	}
}

func TestStripe(t *testing.T) {
	fake, stripeServer := newFakeStripe(t)
	h := newHarness(t, func(cfg *Config) {
		cfg.Stripe = StripeClient{Base: stripeServer.URL, Key: "sk_test_fake", WebhookSecret: webhookSecret, ReturnURL: "https://gustfire.test/jogar/"}
	})
	ctx := context.Background()
	register := func(name string) int64 {
		_, reply := h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": name, "password": "senha-forte-1", "accept_terms": testTerms}, nil)
		return int64(reply["account"].(map[string]any)["id"].(float64))
	}
	nilo, lia := register("nilo"), register("lia")
	product := map[string]any{"sku": "pacote_tinturas", "description": "Pacote de Tinturas", "language": "pt",
		"items":  []map[string]any{{"id": "cabelo_rosa_neon", "quality": "normal", "level": 0, "bound": true}, {"id": "cabelo_aurora", "quality": "normal", "level": 0, "bound": true}},
		"prices": map[string]int{"USD": 299, "BRL": 1499}}
	checkout := func(account int64, overrides map[string]any) (int, map[string]any) {
		body := map[string]any{"account_id": account}
		for key, value := range product {
			body[key] = value
		}
		for key, value := range overrides {
			body[key] = value
		}
		return h.internalCall("POST", "/internal/store/checkout", body)
	}
	status := func(account, order int64) (int, map[string]any) {
		return h.internalCall("POST", "/internal/store/status", map[string]any{"account_id": account, "order_id": order})
	}
	letters := func(account int64) int {
		var n int
		h.store.pool.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id = $1 AND kind = 'store'`, account).Scan(&n)
		return n
	}

	// A product without a BRL price is not sold here.
	if code, reply := checkout(nilo, map[string]any{"prices": map[string]int{"USD": 299}}); code != http.StatusConflict || reply["error"] != codeCurrency {
		t.Fatalf("no BRL price: %d %v", code, reply)
	}
	code, reply := checkout(nilo, nil)
	if code != http.StatusOK || reply["currency"] != "BRL" || reply["amount"].(float64) != 1499 || !strings.HasPrefix(reply["url"].(string), "https://checkout.stripe.test/") {
		t.Fatalf("checkout: %d %v", code, reply)
	}
	orderID := int64(reply["order_id"].(float64))
	session := "cs_test_1"
	form := fake.forms[session]
	if form.Get("mode") != "payment" || form.Get("client_reference_id") != strconv.FormatInt(orderID, 10) || form.Get("line_items[0][price_data][currency]") != "brl" ||
		form.Get("line_items[0][price_data][unit_amount]") != "1499" || form.Get("payment_method_types[0]") != "card" || form.Get("payment_method_types[1]") != "pix" ||
		form.Get("locale") != "pt-BR" || form.Get("metadata[order_id]") != strconv.FormatInt(orderID, 10) || form.Get("payment_intent_data[metadata][order_id]") == "" ||
		!strings.HasPrefix(form.Get("success_url"), "https://gustfire.test/jogar/?compra=ok&pedido=") || form.Get("line_items[0][price_data][product_data][name]") != "Pacote de Tinturas" {
		t.Fatalf("the session asked Stripe for card and Pix in BRL: %v", form)
	}

	// The page is reused while the order waits for payment (a double click is no second order).
	code, again := checkout(nilo, nil)
	if code != http.StatusOK || int64(again["order_id"].(float64)) != orderID || again["url"] != reply["url"] || fake.calls != 1 {
		t.Fatalf("the same product reopens its page: %d %v calls=%d", code, again, fake.calls)
	}
	if code, orderStatus := status(nilo, orderID); code != http.StatusOK || orderStatus["order"].(map[string]any)["status"] != "init" {
		t.Fatalf("waiting for payment: %d %v", code, orderStatus)
	}
	if code, _ := status(lia, orderID); code != http.StatusNotFound {
		t.Fatalf("another account cannot read the order: %d", code)
	}
	if letters(nilo) != 0 {
		t.Fatal("nothing is delivered before payment")
	}

	// Webhooks: unsigned, wrongly signed and old ones change nothing.
	paid := fake.pay(session)
	if code, _ := h.webhook("evt_a", "checkout.session.completed", paid, "whsec_wrong", 0); code != http.StatusBadRequest {
		t.Fatalf("a wrong signature is refused: %d", code)
	}
	if code, _ := h.webhook("evt_a", "checkout.session.completed", paid, webhookSecret, 20*time.Minute); code != http.StatusBadRequest {
		t.Fatalf("an old event is refused (replay): %d", code)
	}
	if letters(nilo) != 0 {
		t.Fatal("refused webhooks deliver nothing")
	}
	// A session whose amount differs from the order is not delivered.
	tampered := paid
	tampered.AmountTotal = 1
	if code, _ := h.webhook("evt_t", "checkout.session.completed", tampered, webhookSecret, 0); code != http.StatusInternalServerError || letters(nilo) != 0 {
		t.Fatalf("a different amount is not delivered: %d letters=%d", code, letters(nilo))
	}
	// The real one.
	if code, reply := h.webhook("evt_b", "checkout.session.completed", paid, webhookSecret, 0); code != http.StatusOK {
		t.Fatalf("webhook: %d %v", code, reply)
	}
	if letters(nilo) != 2 {
		t.Fatalf("each item arrives in the Correio: %d", letters(nilo))
	}
	var bound int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id = $1 AND kind = 'store' AND item->>'bound' = 'true'`, nilo).Scan(&bound)
	if bound != 2 {
		t.Fatalf("items arrive bound: %d", bound)
	}
	// Stripe sends the same event again, and a second event for the same session: once only.
	if code, reply := h.webhook("evt_b", "checkout.session.completed", paid, webhookSecret, 0); code != http.StatusOK || reply["duplicate"] != true {
		t.Fatalf("a repeated event is acknowledged: %d %v", code, reply)
	}
	h.webhook("evt_c", "checkout.session.async_payment_succeeded", paid, webhookSecret, 0)
	if _, orderStatus := status(nilo, orderID); letters(nilo) != 2 || orderStatus["order"].(map[string]any)["status"] != "paid" {
		t.Fatalf("delivered once: letters=%d %v", letters(nilo), orderStatus)
	}
	var audited, intents int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM audit_log WHERE kind = 'store.paid' AND account_id = $1 AND detail->>'provider' = 'stripe'`, nilo).Scan(&audited)
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM store_orders WHERE order_id = $1 AND payment_ref = 'pi_cs_test_1'`, orderID).Scan(&intents)
	if audited != 1 || intents != 1 {
		t.Fatalf("payment audited and payment intent stored: %d %d", audited, intents)
	}
	if code, reply := h.internalCall("POST", "/internal/store/finalize", map[string]any{"server_id": "s1", "account_id": nilo, "order_id": orderID}); code != http.StatusOK {
		t.Fatalf("finalizing a paid order just answers: %d %v", code, reply)
	}

	// A Stripe order is never charged through the Steam finalize.
	_, second := checkout(lia, nil)
	liaOrder := int64(second["order_id"].(float64))
	if code, reply := h.internalCall("POST", "/internal/store/finalize", map[string]any{"server_id": "s1", "account_id": lia, "order_id": liaOrder}); code != http.StatusConflict {
		t.Fatalf("the game cannot finalize a Stripe order: %d %v", code, reply)
	}
	if letters(lia) != 0 {
		t.Fatal("no delivery by finalize")
	}

	// The webhook is late: the status poll reads the session and delivers.
	fake.pay("cs_test_2")
	if code, orderStatus := status(lia, liaOrder); code != http.StatusOK || orderStatus["order"].(map[string]any)["status"] != "paid" || letters(lia) != 2 {
		t.Fatalf("polling delivers a paid session: %d %v letters=%d", code, orderStatus, letters(lia))
	}
	// And the webhook that arrives later does not deliver twice.
	h.webhook("evt_d", "checkout.session.completed", fake.sessions["cs_test_2"], webhookSecret, 0)
	if letters(lia) != 2 {
		t.Fatalf("late webhook after polling: %d", letters(lia))
	}

	// Reconcile at login: a paid session whose player left the game.
	_, third := checkout(nilo, map[string]any{"sku": "tintura_chama", "description": "Cabelo Chama", "items": []map[string]any{{"id": "cabelo_chama", "quality": "normal", "level": 0, "bound": true}}, "prices": map[string]int{"BRL": 499}})
	lost := int64(third["order_id"].(float64))
	fake.pay("cs_test_3")
	code, reply = h.internalCall("POST", "/internal/store/reconcile", map[string]any{"server_id": "s1", "account_id": nilo})
	if delivered := reply["delivered"].([]any); code != http.StatusOK || len(delivered) != 1 || int64(delivered[0].(float64)) != lost {
		t.Fatalf("reconcile delivers paid Stripe orders: %d %v", code, reply)
	}

	// Pix not paid in time: the session expires and the order is cancelled.
	_, fourth := checkout(nilo, map[string]any{"sku": "tintura_aurora", "description": "Cabelo Aurora", "items": []map[string]any{{"id": "cabelo_aurora", "quality": "normal", "level": 0, "bound": true}}, "prices": map[string]int{"BRL": 499}})
	expired := int64(fourth["order_id"].(float64))
	h.webhook("evt_e", "checkout.session.expired", fake.expire("cs_test_4"), webhookSecret, 0)
	if _, orderStatus := status(nilo, expired); orderStatus["order"].(map[string]any)["status"] != "cancelled" {
		t.Fatalf("an expired page cancels the order: %v", orderStatus)
	}
	// A failed Pix.
	_, fifth := checkout(nilo, map[string]any{"sku": "tintura_chama", "description": "Cabelo Chama", "items": []map[string]any{{"id": "cabelo_chama", "quality": "normal", "level": 0, "bound": true}}, "prices": map[string]int{"BRL": 499}})
	failed := int64(fifth["order_id"].(float64))
	h.webhook("evt_f", "checkout.session.async_payment_failed", fake.sessions["cs_test_5"], webhookSecret, 0)
	if _, orderStatus := status(nilo, failed); orderStatus["order"].(map[string]any)["status"] != "failed" {
		t.Fatalf("a failed payment closes the order: %v", orderStatus)
	}

	// Refund: unopened letters are taken back; the audit log says what was already claimed.
	h.store.pool.Exec(ctx, `UPDATE mail SET claimed_at = now() WHERE account_id = $1 AND kind = 'store' AND detail->>'order_id' = $2 AND item->>'id' = 'cabelo_rosa_neon'`, nilo, strconv.FormatInt(orderID, 10))
	charge := map[string]any{"payment_intent": "pi_cs_test_1", "amount": 1499, "amount_refunded": 500}
	h.webhook("evt_g", "charge.refunded", charge, webhookSecret, 0)
	if _, orderStatus := status(nilo, orderID); orderStatus["order"].(map[string]any)["status"] != "paid" {
		t.Fatalf("a partial refund does not undo the order: %v", orderStatus)
	}
	charge["amount_refunded"] = 1499
	h.webhook("evt_h", "charge.refunded", charge, webhookSecret, 0)
	if _, orderStatus := status(nilo, orderID); orderStatus["order"].(map[string]any)["status"] != "refunded" {
		t.Fatalf("a full refund: %v", orderStatus)
	}
	var left int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id = $1 AND kind = 'store' AND detail->>'order_id' = $2`, nilo, strconv.FormatInt(orderID, 10)).Scan(&left)
	var detail string
	h.store.pool.QueryRow(ctx, `SELECT detail::text FROM audit_log WHERE kind = 'store.refunded'`).Scan(&detail)
	if left != 1 || !strings.Contains(detail, `"items_already_claimed": 1`) || !strings.Contains(detail, `"letters_removed": 1`) {
		t.Fatalf("refund takes back the unopened letter: left=%d %s", left, detail)
	}
	// Events for orders that are not ours are ignored.
	if code, _ := h.webhook("evt_i", "checkout.session.completed", map[string]any{"id": "cs_other", "payment_status": "paid"}, webhookSecret, 0); code != http.StatusOK {
		t.Fatalf("an unknown session is acknowledged and ignored: %d", code)
	}

	// Stripe refusing the session (Pix not enabled in the account) closes the order.
	fake.fail = true
	if code, reply := checkout(lia, map[string]any{"sku": "tintura_rosa_neon", "description": "Cabelo Rosa Neon", "items": []map[string]any{{"id": "cabelo_rosa_neon", "quality": "normal", "level": 0, "bound": true}}, "prices": map[string]int{"BRL": 499}}); code != http.StatusBadGateway || reply["error"] != codePayError {
		t.Fatalf("Stripe refused: %d %v", code, reply)
	}
	var failedOrders int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM store_orders WHERE account_id = $1 AND provider = 'stripe' AND status = 'failed'`, lia).Scan(&failedOrders)
	if failedOrders != 1 {
		t.Fatalf("the refused order is closed: %d", failedOrders)
	}
	fake.fail = false

	// Pix not active in the account: the page is still sold, by card alone.
	fake.pixOff = true
	code, cardOnly := checkout(nilo, map[string]any{"sku": "tintura_card", "description": "Cabelo Card", "prices": map[string]int{"BRL": 499}})
	fake.pixOff = false
	if code != http.StatusOK || !strings.HasPrefix(cardOnly["url"].(string), "https://checkout.stripe.test/") {
		t.Fatalf("without Pix the checkout falls back to card: %d %v", code, cardOnly)
	}
	cardForm := fake.forms[strings.TrimPrefix(cardOnly["url"].(string), "https://checkout.stripe.test/")]
	if cardForm.Get("payment_method_types[0]") != "card" || cardForm.Get("payment_method_types[1]") != "" || cardForm.Get("payment_method_options[pix][expires_after_seconds]") != "" {
		t.Fatalf("the fallback asks for card only: %v", cardForm)
	}

	// Orders in a row are limited (a script cannot open hundreds of Stripe sessions).
	var limited bool
	for i := 0; i < 8 && !limited; i++ {
		code, _ := checkout(lia, map[string]any{"sku": "aba_mochila_" + strconv.Itoa(i), "description": "Aba", "prices": map[string]int{"BRL": 990}})
		limited = code == http.StatusTooManyRequests
	}
	if !limited {
		t.Fatal("open orders per account are limited")
	}
}
