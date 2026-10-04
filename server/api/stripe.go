package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Real money outside Steam (web and mobile): Stripe Checkout with card and Pix.
//
// The game server, which knows the catalog (shared/balance/store.json), asks
// /internal/store/checkout; the API opens the order and a Checkout Session and answers
// the page address, which the game opens in the browser. The player pays there.
// Stripe then calls POST /v1/store/stripe/webhook (signed); the order is marked paid and
// the items go to the Correio in the same transaction as for Steam (Store.PayOrder).
//
// The webhook can be late, so the game also asks /internal/store/status while it waits,
// and every login runs /internal/store/reconcile: both read the session from Stripe and
// finish the order the same way. Delivery is idempotent: PayOrder pays an order once.

const (
	codeStripeUnavailable = "pay_unavailable"
	codePayError          = "pay_error"
	// Prices for Stripe come from the BRL column of store.json for now.
	stripeCurrency = "BRL"
	// A checkout page lives this long; the same order reopens its page until then.
	checkoutLife = time.Hour
	// Open orders an account may create in ten minutes before it is told to wait.
	openOrderLimit = 5
)

func (a *API) stripeRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/store/stripe/webhook", a.stripeWebhook)
}

func (a *API) stripeInternalRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /internal/store/checkout", a.storeCheckout)
	mux.HandleFunc("POST /internal/store/status", a.storeStatus)
}

type checkoutBody struct {
	AccountID   int64           `json:"account_id"`
	SKU         string          `json:"sku"`
	Description string          `json:"description"`
	Items       json.RawMessage `json:"items"`
	Prices      map[string]int  `json:"prices"`
	Language    string          `json:"language"`
}

func (a *API) storeCheckout(w http.ResponseWriter, r *http.Request) {
	var body checkoutBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 || body.SKU == "" || len(body.Prices) == 0 || !json.Valid(body.Items) {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid order")
		return
	}
	if !a.stripe.Enabled() {
		writeError(w, http.StatusServiceUnavailable, codeStripeUnavailable, "stripe is not configured")
		return
	}
	amount := body.Prices[stripeCurrency]
	if amount <= 0 {
		writeError(w, http.StatusConflict, codeCurrency, "no price in "+stripeCurrency)
		return
	}
	ctx := r.Context()
	// The same product still waiting for payment: reopen its page instead of a new order.
	if open, err := a.store.OpenStripeOrder(ctx, body.AccountID, body.SKU); err == nil {
		writeJSON(w, http.StatusOK, orderAnswer(open))
		return
	} else if !errors.Is(err, ErrNotFound) {
		a.fail(w, err)
		return
	}
	recent, err := a.store.RecentStripeOrders(ctx, body.AccountID, 10*time.Minute)
	if err != nil {
		a.fail(w, err)
		return
	}
	if recent >= openOrderLimit {
		writeError(w, http.StatusTooManyRequests, codeRateLimited, "too many open orders")
		return
	}
	language := body.Language
	if language != "pt" && language != "en" {
		language = "pt"
	}
	order := Order{AccountID: body.AccountID, SKU: body.SKU, Description: truncate(body.Description, 128), Items: body.Items, Amount: amount, Currency: stripeCurrency, Status: "init", Provider: "stripe"}
	order.OrderID, err = a.store.CreateStripeOrder(ctx, order)
	if err != nil {
		a.fail(w, err)
		return
	}
	session, err := a.stripe.CreateCheckout(ctx, CheckoutParams{OrderID: order.OrderID, Description: order.Description, Amount: amount, Currency: stripeCurrency, Language: language, Expires: time.Now().Add(checkoutLife)})
	if err != nil || session.ID == "" || session.URL == "" {
		a.log.Error("stripe checkout", "order", order.OrderID, "err", err)
		_ = a.store.SetOrderStatus(ctx, order.OrderID, "failed", "checkout")
		writeError(w, http.StatusBadGateway, codePayError, "stripe refused the order")
		return
	}
	if err := a.store.SetStripeSession(ctx, order.OrderID, session.ID, session.URL); err != nil {
		a.fail(w, err)
		return
	}
	order.CheckoutURL = session.URL
	writeJSON(w, http.StatusOK, orderAnswer(order))
}

func orderAnswer(order Order) map[string]any {
	return map[string]any{"order_id": order.OrderID, "url": order.CheckoutURL, "amount": order.Amount, "currency": order.Currency}
}

// storeStatus: where the order is. A Stripe order still open is checked with Stripe first,
// so the answer is right even when the webhook has not arrived.
func (a *API) storeStatus(w http.ResponseWriter, r *http.Request) {
	var body orderBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 || body.OrderID <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	order, err := a.store.OrderOf(r.Context(), body.AccountID, body.OrderID)
	if err != nil {
		a.orderReply(w, order, err)
		return
	}
	if order.Status == "init" && order.Provider == "stripe" {
		order, err = a.stripeSync(r.Context(), order)
		if err != nil {
			a.log.Error("stripe sync", "order", order.OrderID, "err", err)
			// Stripe did not answer: the order is as it was.
			order, _ = a.store.OrderOf(r.Context(), body.AccountID, body.OrderID)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"order": map[string]any{"order_id": order.OrderID, "sku": order.SKU, "status": order.Status, "url": order.CheckoutURL}})
}

// stripeSync reads the session from Stripe and settles the order: paid, or expired.
func (a *API) stripeSync(ctx context.Context, order Order) (Order, error) {
	if !a.stripe.Enabled() || order.ProviderRef == "" {
		return order, nil
	}
	session, err := a.stripe.GetSession(ctx, order.ProviderRef)
	if err != nil {
		return order, err
	}
	return a.stripeApply(ctx, order, session)
}

func paidSession(session StripeSession) bool {
	return session.PaymentStatus == "paid" || session.PaymentStatus == "no_payment_required"
}

// stripeApply moves an order along with what Stripe says about its session.
func (a *API) stripeApply(ctx context.Context, order Order, session StripeSession) (Order, error) {
	switch {
	case paidSession(session):
		return a.stripeSettle(ctx, order, session)
	case session.Status == "expired":
		if err := a.store.SetOrderStatus(ctx, order.OrderID, "cancelled", "expired"); err != nil {
			return order, err
		}
		return a.store.OrderOf(ctx, order.AccountID, order.OrderID)
	}
	return order, nil
}

// stripeSettle delivers a paid order, once. Amount and currency must match what the API
// asked for: a session that does not is left alone and written to the audit log.
func (a *API) stripeSettle(ctx context.Context, order Order, session StripeSession) (Order, error) {
	if order.AccountID == 0 {
		return order, ErrNotFound
	}
	if session.AmountTotal != order.Amount || !strings.EqualFold(session.Currency, order.Currency) {
		a.log.Error("stripe amount mismatch", "order", order.OrderID, "paid", session.AmountTotal, "asked", order.Amount)
		_ = a.store.Audit(ctx, &order.AccountID, "stripe", "store.mismatch", map[string]any{"order_id": order.OrderID, "amount": session.AmountTotal, "currency": session.Currency})
		return order, errors.New("stripe amount mismatch")
	}
	if err := a.store.SetPaymentRef(ctx, order.OrderID, session.PaymentIntent); err != nil {
		return order, err
	}
	return a.store.PayOrder(ctx, "stripe", order.AccountID, order.OrderID, func(Order) error { return nil })
}

// stripeReconcile finishes the account's Stripe orders left open (called by storeReconcile).
func (a *API) stripeReconcile(ctx context.Context, accountID int64) []int64 {
	delivered := []int64{}
	if !a.stripe.Enabled() {
		return delivered
	}
	orders, err := a.store.OpenStripeOrders(ctx, accountID)
	if err != nil {
		return delivered
	}
	for _, order := range orders {
		if updated, err := a.stripeSync(ctx, order); err == nil && updated.Status == "paid" {
			delivered = append(delivered, order.OrderID)
		}
	}
	return delivered
}

// ---------- webhook ----------

type stripeEvent struct {
	ID   string `json:"id"`
	Type string `json:"type"`
	Data struct {
		Object json.RawMessage `json:"object"`
	} `json:"data"`
}

func (a *API) stripeWebhook(w http.ResponseWriter, r *http.Request) {
	if !a.stripe.Enabled() || a.stripe.WebhookSecret == "" {
		writeError(w, http.StatusServiceUnavailable, codeStripeUnavailable, "stripe webhook is not configured")
		return
	}
	payload, err := io.ReadAll(r.Body)
	if err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	if err := a.stripe.VerifySignature(payload, r.Header.Get("Stripe-Signature"), time.Now()); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid signature")
		return
	}
	var event stripeEvent
	if err := json.Unmarshal(payload, &event); err != nil || event.ID == "" {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid event")
		return
	}
	ctx := r.Context()
	if seen, err := a.store.StripeEventSeen(ctx, event.ID); err != nil {
		a.fail(w, err)
		return
	} else if seen {
		writeJSON(w, http.StatusOK, map[string]any{"received": true, "duplicate": true})
		return
	}
	if err := a.stripeEvent(ctx, event); err != nil {
		// 500: Stripe sends the event again later.
		a.log.Error("stripe event", "id", event.ID, "type", event.Type, "err", err)
		writeError(w, http.StatusInternalServerError, codePayError, "could not handle the event")
		return
	}
	if err := a.store.StripeEventDone(ctx, event.ID, event.Type); err != nil {
		a.log.Error("stripe event log", "id", event.ID, "err", err)
	}
	writeJSON(w, http.StatusOK, map[string]any{"received": true})
}

func (a *API) stripeEvent(ctx context.Context, event stripeEvent) error {
	switch event.Type {
	case "checkout.session.completed", "checkout.session.async_payment_succeeded", "checkout.session.async_payment_failed", "checkout.session.expired":
		var session StripeSession
		if err := json.Unmarshal(event.Data.Object, &session); err != nil {
			return err
		}
		order, err := a.store.OrderByRef(ctx, session.ID)
		if errors.Is(err, ErrNotFound) {
			return nil // not ours (another product of the same Stripe account)
		}
		if err != nil {
			return err
		}
		if event.Type == "checkout.session.async_payment_failed" {
			return a.store.SetOrderStatus(ctx, order.OrderID, "failed", "async_payment_failed")
		}
		if order.Status != "init" {
			return nil
		}
		// A completed Pix not yet paid stays open (payment_status unpaid) until the
		// async_payment_succeeded event.
		_, err = a.stripeApply(ctx, order, session)
		return err
	case "charge.refunded":
		var charge struct {
			PaymentIntent  string `json:"payment_intent"`
			Amount         int    `json:"amount"`
			AmountRefunded int    `json:"amount_refunded"`
		}
		if err := json.Unmarshal(event.Data.Object, &charge); err != nil {
			return err
		}
		if charge.PaymentIntent == "" {
			return nil
		}
		return a.store.RefundOrder(ctx, charge.PaymentIntent, charge.AmountRefunded >= charge.Amount)
	}
	return nil // other events are ignored
}

// ---------- store ----------

func (s *Store) CreateStripeOrder(ctx context.Context, order Order) (int64, error) {
	var id int64
	err := s.pool.QueryRow(ctx, `INSERT INTO store_orders (order_id, account_id, sku, description, items, amount, currency, provider)
		VALUES (nextval('store_order_seq'), $1, $2, $3, $4, $5, $6, 'stripe') RETURNING order_id`,
		order.AccountID, order.SKU, order.Description, order.Items, order.Amount, order.Currency).Scan(&id)
	return id, err
}

func (s *Store) SetStripeSession(ctx context.Context, orderID int64, sessionID, checkoutURL string) error {
	_, err := s.pool.Exec(ctx, `UPDATE store_orders SET provider_ref = $2, checkout_url = $3, updated_at = now() WHERE order_id = $1`, orderID, sessionID, checkoutURL)
	return err
}

func (s *Store) SetPaymentRef(ctx context.Context, orderID int64, paymentRef string) error {
	if paymentRef == "" {
		return nil
	}
	_, err := s.pool.Exec(ctx, `UPDATE store_orders SET payment_ref = $2 WHERE order_id = $1`, orderID, paymentRef)
	return err
}

// OpenStripeOrder: the account's unpaid order of this product whose page is still alive.
func (s *Store) OpenStripeOrder(ctx context.Context, accountID int64, sku string) (Order, error) {
	return scanOrder(s.pool.QueryRow(ctx, `SELECT `+orderColumns+` FROM store_orders
		WHERE account_id = $1 AND sku = $2 AND provider = 'stripe' AND status = 'init' AND checkout_url IS NOT NULL
		AND created_at > now() - make_interval(secs => $3) ORDER BY created_at DESC LIMIT 1`, accountID, sku, (checkoutLife - 5*time.Minute).Seconds()))
}

func (s *Store) RecentStripeOrders(ctx context.Context, accountID int64, within time.Duration) (int, error) {
	var count int
	err := s.pool.QueryRow(ctx, `SELECT count(*) FROM store_orders WHERE account_id = $1 AND provider = 'stripe' AND created_at > now() - make_interval(secs => $2)`, accountID, within.Seconds()).Scan(&count)
	return count, err
}

func (s *Store) OpenStripeOrders(ctx context.Context, accountID int64) ([]Order, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+orderColumns+` FROM store_orders WHERE account_id = $1 AND provider = 'stripe' AND status = 'init' AND provider_ref IS NOT NULL ORDER BY created_at LIMIT 20`, accountID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (Order, error) { return scanOrder(row) })
}

func (s *Store) OrderOf(ctx context.Context, accountID, orderID int64) (Order, error) {
	order, err := scanOrder(s.pool.QueryRow(ctx, `SELECT `+orderColumns+` FROM store_orders WHERE order_id = $1`, orderID))
	if err == nil && order.AccountID != accountID {
		return Order{}, ErrNotFound
	}
	return order, err
}

func (s *Store) OrderByRef(ctx context.Context, ref string) (Order, error) {
	return scanOrder(s.pool.QueryRow(ctx, `SELECT `+orderColumns+` FROM store_orders WHERE provider_ref = $1`, ref))
}

func (s *Store) Audit(ctx context.Context, accountID *int64, serverID, kind string, detail any) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error { return auditTx(ctx, tx, accountID, serverID, kind, detail) })
}

func (s *Store) StripeEventSeen(ctx context.Context, id string) (bool, error) {
	var seen bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM stripe_events WHERE event_id = $1)`, id).Scan(&seen)
	return seen, err
}

func (s *Store) StripeEventDone(ctx context.Context, id, kind string) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO stripe_events (event_id, kind) VALUES ($1, $2) ON CONFLICT DO NOTHING`, id, kind)
	return err
}

// RefundOrder marks the order refunded (a full refund) and takes back the letters the
// player has not opened. Items already claimed are left in the profile and written to the
// audit log with their count, for the team to review (the Terms: a refunded purchase is
// removed from the account).
func (s *Store) RefundOrder(ctx context.Context, paymentRef string, full bool) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		order, err := scanOrder(tx.QueryRow(ctx, `SELECT `+orderColumns+` FROM store_orders WHERE payment_ref = $1 FOR UPDATE`, paymentRef))
		if errors.Is(err, ErrNotFound) {
			return nil
		}
		if err != nil {
			return err
		}
		if !full || order.Status == "refunded" {
			return nil
		}
		if order.Status != "paid" {
			return nil
		}
		if _, err := tx.Exec(ctx, `UPDATE store_orders SET status = 'refunded', updated_at = now() WHERE order_id = $1`, order.OrderID); err != nil {
			return err
		}
		orderRef := strconv.FormatInt(order.OrderID, 10)
		removed, err := tx.Exec(ctx, `DELETE FROM mail WHERE account_id = $1 AND kind = 'store' AND claimed_at IS NULL AND detail->>'order_id' = $2`, order.AccountID, orderRef)
		if err != nil {
			return err
		}
		var claimed int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id = $1 AND kind = 'store' AND claimed_at IS NOT NULL AND detail->>'order_id' = $2`, order.AccountID, orderRef).Scan(&claimed); err != nil {
			return err
		}
		var account *int64
		if order.AccountID != 0 {
			account = &order.AccountID
		}
		return auditTx(ctx, tx, account, "stripe", "store.refunded", map[string]any{"order_id": order.OrderID, "sku": order.SKU, "letters_removed": removed.RowsAffected(), "items_already_claimed": claimed})
	})
}
