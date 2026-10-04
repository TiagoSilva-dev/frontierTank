package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// StripeClient talks to the Stripe API with the secret key (sk_...): Checkout Sessions
// (the hosted page with card and Pix) and the webhook signature. No SDK, like SteamClient.
// Tests point Base at a fake server. Without Key, Stripe is off.
type StripeClient struct {
	Base          string
	Key           string
	WebhookSecret string
	// Where Checkout sends the player after paying or giving up (the web game).
	ReturnURL string
	HTTP      *http.Client
}

var (
	ErrStripeDisabled = errors.New("stripe is not configured")
	ErrBadSignature   = errors.New("invalid stripe signature")
)

// StripeError is an error answered by Stripe.
type StripeError struct {
	Status  int
	Type    string
	Code    string
	Message string
}

func (e *StripeError) Error() string {
	return fmt.Sprintf("stripe %d %s %s: %s", e.Status, e.Type, e.Code, e.Message)
}

// StripeSession is the part of a Checkout Session the API uses.
type StripeSession struct {
	ID            string `json:"id"`
	URL           string `json:"url"`
	Status        string `json:"status"`         // open, complete or expired
	PaymentStatus string `json:"payment_status"` // paid, unpaid or no_payment_required
	AmountTotal   int    `json:"amount_total"`
	Currency      string `json:"currency"`
	PaymentIntent string `json:"payment_intent"`
	ClientRef     string `json:"client_reference_id"`
}

func (c *StripeClient) Enabled() bool { return c != nil && c.Key != "" }

func (c *StripeClient) client() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 20 * time.Second}
}

func (c *StripeClient) base() string {
	if c.Base != "" {
		return strings.TrimSuffix(c.Base, "/")
	}
	return "https://api.stripe.com"
}

func (c *StripeClient) call(ctx context.Context, method, path string, params url.Values, idempotency string, target any) error {
	if !c.Enabled() {
		return ErrStripeDisabled
	}
	var body io.Reader
	endpoint := c.base() + path
	if method == http.MethodGet {
		if len(params) > 0 {
			endpoint += "?" + params.Encode()
		}
	} else {
		body = strings.NewReader(params.Encode())
	}
	request, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+c.Key)
	if method != http.MethodGet {
		request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	if idempotency != "" {
		request.Header.Set("Idempotency-Key", idempotency)
	}
	reply, err := c.client().Do(request)
	if err != nil {
		return err
	}
	defer reply.Body.Close()
	data, err := io.ReadAll(io.LimitReader(reply.Body, 1<<20))
	if err != nil {
		return err
	}
	if reply.StatusCode/100 != 2 {
		var failure struct {
			Error struct {
				Type    string `json:"type"`
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.Unmarshal(data, &failure)
		return &StripeError{Status: reply.StatusCode, Type: failure.Error.Type, Code: failure.Error.Code, Message: failure.Error.Message}
	}
	return json.Unmarshal(data, target)
}

// CheckoutParams describes one order: a single line with the price in cents.
type CheckoutParams struct {
	OrderID     int64
	Description string
	Amount      int
	Currency    string // lower case: "brl"
	Language    string // "pt" or "en"
	Expires     time.Time
}

// CreateCheckout opens a Checkout Session paid by card or Pix. The order id travels as
// client_reference_id and in the metadata (also on the PaymentIntent, so refunds find it).
// The idempotency key makes a retried call return the same session.
func (c *StripeClient) CreateCheckout(ctx context.Context, p CheckoutParams) (StripeSession, error) {
	order := strconv.FormatInt(p.OrderID, 10)
	locale := "pt-BR"
	if p.Language == "en" {
		locale = "en"
	}
	params := url.Values{
		"mode":                    {"payment"},
		"client_reference_id":     {order},
		"locale":                  {locale},
		"success_url":             {c.returnURL("ok", order)},
		"cancel_url":              {c.returnURL("cancelado", order)},
		"payment_method_types[0]": {"card"},
		"payment_method_types[1]": {"pix"},
		"payment_method_options[pix][expires_after_seconds]": {"1800"},
		"line_items[0][quantity]":                            {"1"},
		"line_items[0][price_data][currency]":                {strings.ToLower(p.Currency)},
		"line_items[0][price_data][unit_amount]":             {strconv.Itoa(p.Amount)},
		"line_items[0][price_data][product_data][name]":      {p.Description},
		"metadata[order_id]":                                 {order},
		"payment_intent_data[metadata][order_id]":            {order},
		"payment_intent_data[description]":                   {"Gustfire " + p.Description + " #" + order},
		"expires_at":                                         {strconv.FormatInt(p.Expires.Unix(), 10)},
	}
	var session StripeSession
	err := c.call(ctx, http.MethodPost, "/v1/checkout/sessions", params, "gustfire-order-"+order, &session)
	return session, err
}

func (c *StripeClient) returnURL(result, order string) string {
	base := c.ReturnURL
	if base == "" {
		base = "http://localhost:8000/jogar/"
	}
	separator := "?"
	if strings.Contains(base, "?") {
		separator = "&"
	}
	return base + separator + "compra=" + result + "&pedido=" + order
}

// GetSession reads a session (the source of truth when a webhook is late or lost).
func (c *StripeClient) GetSession(ctx context.Context, id string) (StripeSession, error) {
	var session StripeSession
	err := c.call(ctx, http.MethodGet, "/v1/checkout/sessions/"+url.PathEscape(id), nil, "", &session)
	return session, err
}

// stripeTolerance: how old a signed webhook may be (replay protection).
const stripeTolerance = 5 * time.Minute

// VerifySignature checks the Stripe-Signature header ("t=...,v1=...,v1=...") against the
// raw body: HMAC-SHA256 of "<t>.<body>" with the webhook secret, compared in constant time.
func (c *StripeClient) VerifySignature(payload []byte, header string, now time.Time) error {
	if c.WebhookSecret == "" {
		return ErrBadSignature
	}
	var timestamp int64
	var signatures []string
	for _, part := range strings.Split(header, ",") {
		key, value, found := strings.Cut(strings.TrimSpace(part), "=")
		if !found {
			continue
		}
		switch key {
		case "t":
			timestamp, _ = strconv.ParseInt(value, 10, 64)
		case "v1":
			signatures = append(signatures, value)
		}
	}
	if timestamp == 0 || len(signatures) == 0 {
		return ErrBadSignature
	}
	if age := now.Sub(time.Unix(timestamp, 0)); age > stripeTolerance || age < -stripeTolerance {
		return ErrBadSignature
	}
	expected := signStripe(c.WebhookSecret, timestamp, payload)
	for _, signature := range signatures {
		if hmac.Equal([]byte(signature), []byte(expected)) {
			return nil
		}
	}
	return ErrBadSignature
}

func signStripe(secret string, timestamp int64, payload []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	fmt.Fprintf(mac, "%d.", timestamp)
	mac.Write(payload)
	return hex.EncodeToString(mac.Sum(nil))
}
