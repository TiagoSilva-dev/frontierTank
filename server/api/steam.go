package main

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"time"

	"github.com/jackc/pgx/v5"
)

// Steam (launch checklist, roadmap item 4).
//
// Login: the game gets a ticket with GetAuthTicketForWebApi (GodotSteam) and sends it to
// POST /v1/auth/steam. The API checks it with Steam and logs in the account linked to that
// SteamID; the first time, it creates one (after the player accepted the Terms and the
// Privacy Policy, like any new account). POST /v1/me/steam links Steam to an account that
// already exists (players from the web closed tests).
//
// Purchases (Steam Wallet, ISteamMicroTxn): the game server, which knows the catalog
// (shared/balance/store.json), asks /internal/store/init; the API opens the order with
// Steam and the overlay asks the player. When the game reports the approval,
// /internal/store/finalize charges it and, in the same transaction, marks the order paid
// and puts the items in the player's Correio. /internal/store/reconcile finishes orders
// whose approval got lost (the game closed); run at every login.

const (
	codeSteamUnavailable = "steam_unavailable"
	codeSteamInvalid     = "steam_invalid"
	codeSteamTaken       = "steam_taken"
	codeSteamRequired    = "steam_required"
	codeSteamError       = "steam_error"
	codeCurrency         = "currency_unsupported"
	codeOrderState       = "order_state"
)

var (
	ErrOrderState  = errors.New("order state")
	steamIDPattern = regexp.MustCompile(`^[0-9]{17}$`)
	hexPattern     = regexp.MustCompile(`^[0-9A-Fa-f]+$`)
)

type Order struct {
	OrderID     int64           `json:"order_id"`
	AccountID   int64           `json:"account_id"`
	SteamID     string          `json:"-"`
	SKU         string          `json:"sku"`
	SteamItemID int64           `json:"steam_item_id"`
	Description string          `json:"description"`
	Items       json.RawMessage `json:"items"`
	Amount      int             `json:"amount"`
	Currency    string          `json:"currency"`
	Status      string          `json:"status"`
	CreatedAt   time.Time       `json:"created_at"`
}

func (a *API) steamRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/auth/steam", a.steamLogin)
	mux.HandleFunc("POST /v1/me/steam", a.steamLink)
}

func (a *API) storeRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /internal/store/init", a.storeInit)
	mux.HandleFunc("POST /internal/store/finalize", a.storeFinalize)
	mux.HandleFunc("POST /internal/store/cancel", a.storeCancel)
	mux.HandleFunc("POST /internal/store/reconcile", a.storeReconcile)
}

func init() {
	extraExports = append(extraExports,
		struct{ key, sql string }{"steam", `SELECT COALESCE((SELECT json_build_object('steam_id', steam_id) FROM accounts WHERE id = $1 AND steam_id IS NOT NULL), 'null'::json)`},
		struct{ key, sql string }{"store_orders", `SELECT COALESCE(json_agg(json_build_object('order_id', order_id, 'sku', sku, 'description', description, 'amount', amount, 'currency', currency, 'status', status, 'created_at', created_at) ORDER BY created_at DESC), '[]'::json) FROM store_orders WHERE account_id = $1`},
	)
}

// validTicket: the hex of a web API ticket (about 240 bytes today).
func validTicket(ticket string) bool {
	return len(ticket) >= 16 && len(ticket) <= 4096 && hexPattern.MatchString(ticket)
}

// steamUser checks a ticket; on failure it writes the error and returns false.
func (a *API) steamUser(w http.ResponseWriter, r *http.Request, ticket string) (SteamUser, bool) {
	if !a.steam.Enabled() {
		writeError(w, http.StatusServiceUnavailable, codeSteamUnavailable, "steam is not configured")
		return SteamUser{}, false
	}
	if !validTicket(ticket) {
		writeError(w, http.StatusBadRequest, codeSteamInvalid, "invalid ticket")
		return SteamUser{}, false
	}
	user, err := a.steam.AuthenticateTicket(r.Context(), ticket)
	var refused *SteamError
	if errors.As(err, &refused) {
		writeError(w, http.StatusUnauthorized, codeSteamInvalid, "steam refused the ticket")
		return user, false
	}
	if err != nil {
		a.log.Error("steam ticket", "err", err)
		writeError(w, http.StatusBadGateway, codeSteamUnavailable, "steam did not answer")
		return user, false
	}
	if !steamIDPattern.MatchString(user.SteamID) {
		writeError(w, http.StatusUnauthorized, codeSteamInvalid, "invalid steam id")
		return user, false
	}
	return user, true
}

func (a *API) steamLogin(w http.ResponseWriter, r *http.Request) {
	if !a.limiter.Allow("auth:" + a.clientIP(r)) {
		writeError(w, http.StatusTooManyRequests, codeRateLimited, "too many attempts")
		return
	}
	var body struct {
		Ticket      string `json:"ticket"`
		AcceptTerms string `json:"accept_terms,omitempty"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	user, ok := a.steamUser(w, r, body.Ticket)
	if !ok {
		return
	}
	if user.PublisherBanned {
		writeError(w, http.StatusForbidden, codeBanned, "banned by the publisher")
		return
	}
	account, err := a.store.AccountBySteam(r.Context(), user.SteamID)
	if errors.Is(err, ErrNotFound) {
		// A new player: the account is created only with the consent (LGPD/GDPR).
		if code := a.checkTerms(body.AcceptTerms); code != "" {
			writeError(w, http.StatusForbidden, code, "accept the current terms to create the account")
			return
		}
		account, err = a.store.CreateSteamAccount(r.Context(), user.SteamID, body.AcceptTerms)
		if err != nil {
			a.fail(w, err)
			return
		}
		a.log.Info("steam account created", "id", account.ID, "username", account.Username)
		a.logAccess(r, account.ID, "steam_register")
		a.startSession(w, r, account, http.StatusCreated)
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
	_ = a.store.TouchLogin(r.Context(), account.ID)
	a.logAccess(r, account.ID, "steam_login")
	a.startSession(w, r, account, http.StatusOK)
}

func (a *API) steamLink(w http.ResponseWriter, r *http.Request) {
	account, ok := a.sessionAccount(w, r)
	if !ok {
		return
	}
	var body struct {
		Ticket string `json:"ticket"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	user, ok := a.steamUser(w, r, body.Ticket)
	if !ok {
		return
	}
	err := a.store.LinkSteam(r.Context(), account.ID, user.SteamID)
	if errors.Is(err, ErrTaken) {
		writeError(w, http.StatusConflict, codeSteamTaken, "this steam account is linked to another account")
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	account.Steam = true
	writeJSON(w, http.StatusOK, map[string]any{"account": account})
}

// steamConfirms: the account is Steam-only (no password) and the ticket is from its
// SteamID. Used to delete such an account, where there is no password to type.
func (a *API) steamConfirms(ctx context.Context, accountID int64, ticket string) bool {
	if !a.steam.Enabled() || !validTicket(ticket) {
		return false
	}
	steamID, err := a.store.AccountSteamID(ctx, accountID)
	if err != nil || steamID == "" {
		return false
	}
	user, err := a.steam.AuthenticateTicket(ctx, ticket)
	return err == nil && user.SteamID == steamID
}

// ---------- purchases (internal: game servers) ----------

type storeInitBody struct {
	AccountID   int64           `json:"account_id"`
	SKU         string          `json:"sku"`
	SteamItemID int64           `json:"steam_item_id"`
	Description string          `json:"description"`
	Items       json.RawMessage `json:"items"`
	Prices      map[string]int  `json:"prices"`
	Language    string          `json:"language"`
}

func (a *API) storeInit(w http.ResponseWriter, r *http.Request) {
	var body storeInitBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 || body.SKU == "" || body.SteamItemID <= 0 || len(body.Prices) == 0 || !json.Valid(body.Items) {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid order")
		return
	}
	if !a.steam.Enabled() {
		writeError(w, http.StatusServiceUnavailable, codeSteamUnavailable, "steam is not configured")
		return
	}
	steamID, err := a.store.AccountSteamID(r.Context(), body.AccountID)
	if err != nil && !errors.Is(err, ErrNotFound) {
		a.fail(w, err)
		return
	}
	if steamID == "" {
		writeError(w, http.StatusConflict, codeSteamRequired, "the account is not linked to steam")
		return
	}
	currency, _, err := a.steam.UserInfo(r.Context(), steamID)
	if err != nil {
		a.log.Error("steam user info", "err", err)
		writeError(w, http.StatusBadGateway, codeSteamError, "steam did not answer")
		return
	}
	amount := body.Prices[currency]
	if amount <= 0 {
		writeError(w, http.StatusConflict, codeCurrency, "no price in "+currency)
		return
	}
	language := body.Language
	if language != "pt" && language != "en" {
		language = "en"
	}
	order := Order{AccountID: body.AccountID, SteamID: steamID, SKU: body.SKU, SteamItemID: body.SteamItemID, Description: truncate(body.Description, 128), Items: body.Items, Amount: amount, Currency: currency, Status: "init"}
	order.OrderID, err = a.store.CreateOrder(r.Context(), order)
	if err != nil {
		a.fail(w, err)
		return
	}
	if err := a.steam.InitTxn(r.Context(), order, language); err != nil {
		a.log.Error("steam InitTxn", "order", order.OrderID, "err", err)
		_ = a.store.SetOrderStatus(r.Context(), order.OrderID, "failed", err.Error())
		writeError(w, http.StatusBadGateway, codeSteamError, "steam refused the order")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"order_id": order.OrderID, "amount": amount, "currency": currency})
}

type orderBody struct {
	ServerID  string `json:"server_id"`
	AccountID int64  `json:"account_id"`
	OrderID   int64  `json:"order_id"`
}

func (a *API) storeFinalize(w http.ResponseWriter, r *http.Request) {
	var body orderBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 || body.OrderID <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	order, err := a.finalizeOrder(r.Context(), body.ServerID, body.AccountID, body.OrderID)
	a.orderReply(w, order, err)
}

func (a *API) orderReply(w http.ResponseWriter, order Order, err error) {
	var refused *SteamError
	switch {
	case errors.Is(err, ErrNotFound):
		writeError(w, http.StatusNotFound, codeNotFound, "no such order")
	case errors.Is(err, ErrOrderState):
		writeError(w, http.StatusConflict, codeOrderState, "the order is "+order.Status)
	case errors.As(err, &refused):
		writeError(w, http.StatusBadGateway, codeSteamError, refused.Desc)
	case err != nil:
		a.fail(w, err)
	default:
		writeJSON(w, http.StatusOK, map[string]any{"order": order})
	}
}

// finalizeOrder charges an order the player approved and delivers it. Running it twice
// is safe: a paid order just answers again.
func (a *API) finalizeOrder(ctx context.Context, serverID string, accountID, orderID int64) (Order, error) {
	return a.store.PayOrder(ctx, serverID, accountID, orderID, func(order Order) error {
		err := a.steam.FinalizeTxn(ctx, order.OrderID)
		if err == nil {
			return nil
		}
		// Finalized before (the answer got lost)? Steam says Succeeded.
		if status, queryErr := a.steam.QueryTxn(ctx, order.OrderID); queryErr == nil && status == "Succeeded" {
			return nil
		}
		return err
	})
}

func (a *API) storeCancel(w http.ResponseWriter, r *http.Request) {
	var body orderBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 || body.OrderID <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	order, err := a.store.CancelOrder(r.Context(), body.AccountID, body.OrderID)
	a.orderReply(w, order, err)
}

// storeReconcile finishes the account's orders left open: approved on Steam but never
// finalized (the game closed), or given up.
func (a *API) storeReconcile(w http.ResponseWriter, r *http.Request) {
	var body orderBody
	if err := readJSON(r, &body); err != nil || body.AccountID <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	delivered := []int64{}
	if a.steam.Enabled() {
		orders, err := a.store.OpenOrders(r.Context(), body.AccountID, 30*time.Second)
		if err != nil {
			a.fail(w, err)
			return
		}
		for _, order := range orders {
			status, err := a.steam.QueryTxn(r.Context(), order.OrderID)
			if err != nil {
				continue
			}
			switch status {
			case "Approved", "Succeeded":
				if _, err := a.finalizeOrder(r.Context(), body.ServerID, body.AccountID, order.OrderID); err == nil {
					delivered = append(delivered, order.OrderID)
				}
			case "Failed":
				_ = a.store.SetOrderStatus(r.Context(), order.OrderID, "failed", status)
			default:
				if time.Since(order.CreatedAt) > 24*time.Hour {
					_ = a.store.SetOrderStatus(r.Context(), order.OrderID, "cancelled", status)
				}
			}
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"delivered": delivered})
}

// ---------- store ----------

func (s *Store) AccountBySteam(ctx context.Context, steamID string) (Account, error) {
	var account Account
	err := s.pool.QueryRow(ctx, `SELECT id, username, banned, terms_version, password_hash = '' FROM accounts WHERE steam_id = $1`, steamID).Scan(&account.ID, &account.Username, &account.Banned, &account.TermsVersion, &account.NoPassword)
	if errors.Is(err, pgx.ErrNoRows) {
		return account, ErrNotFound
	}
	account.Steam = true
	return account, err
}

// CreateSteamAccount makes an account for a SteamID, with a generated name
// (steam_ and the end of the SteamID) and no password: it logs in only through Steam.
func (s *Store) CreateSteamAccount(ctx context.Context, steamID, terms string) (Account, error) {
	base := "steam_" + steamID[len(steamID)-8:]
	for attempt := 0; attempt < 5; attempt++ {
		name := base
		if attempt > 0 {
			var suffix [2]byte
			_, _ = rand.Read(suffix[:])
			name = fmt.Sprintf("%s%d", base[:12], binary.BigEndian.Uint16(suffix[:])%10000)
		}
		account := Account{Username: name, TermsVersion: terms, Steam: true, NoPassword: true}
		err := s.pool.QueryRow(ctx, `INSERT INTO accounts (username, password_hash, last_login, terms_version, terms_accepted_at, steam_id) VALUES ($1, '', now(), $2, now(), $3) RETURNING id`, name, terms, steamID).Scan(&account.ID)
		if err == nil || !isUnique(err) {
			return account, err
		}
		// The same SteamID created an account at the same moment: use that one.
		if existing, findErr := s.AccountBySteam(ctx, steamID); findErr == nil {
			return existing, nil
		}
	}
	return Account{}, ErrTaken
}

func (s *Store) LinkSteam(ctx context.Context, accountID int64, steamID string) error {
	_, err := s.pool.Exec(ctx, `UPDATE accounts SET steam_id = $2 WHERE id = $1`, accountID, steamID)
	if isUnique(err) {
		return ErrTaken
	}
	return err
}

func (s *Store) AccountSteamID(ctx context.Context, accountID int64) (string, error) {
	var steamID *string
	err := s.pool.QueryRow(ctx, `SELECT steam_id FROM accounts WHERE id = $1`, accountID).Scan(&steamID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	if steamID == nil {
		return "", err
	}
	return *steamID, err
}

func (s *Store) CreateOrder(ctx context.Context, order Order) (int64, error) {
	var id int64
	err := s.pool.QueryRow(ctx, `INSERT INTO store_orders (order_id, account_id, steam_id, sku, steam_item_id, description, items, amount, currency)
		VALUES (nextval('store_order_seq'), $1, $2, $3, $4, $5, $6, $7, $8) RETURNING order_id`,
		order.AccountID, order.SteamID, order.SKU, order.SteamItemID, order.Description, order.Items, order.Amount, order.Currency).Scan(&id)
	return id, err
}

func (s *Store) SetOrderStatus(ctx context.Context, orderID int64, status, steamStatus string) error {
	_, err := s.pool.Exec(ctx, `UPDATE store_orders SET status = $2, steam_status = $3, updated_at = now() WHERE order_id = $1 AND status = 'init'`, orderID, status, truncate(steamStatus, 200))
	return err
}

const orderColumns = `order_id, account_id, steam_id, sku, steam_item_id, description, items, amount, currency, status, created_at`

func scanOrder(row pgx.Row) (Order, error) {
	var order Order
	var account *int64
	err := row.Scan(&order.OrderID, &account, &order.SteamID, &order.SKU, &order.SteamItemID, &order.Description, &order.Items, &order.Amount, &order.Currency, &order.Status, &order.CreatedAt)
	if account != nil {
		order.AccountID = *account
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return order, ErrNotFound
	}
	return order, err
}

// PayOrder locks the order, calls charge (FinalizeTxn) and, in the same transaction,
// marks it paid and puts one letter per item in the Correio.
func (s *Store) PayOrder(ctx context.Context, serverID string, accountID, orderID int64, charge func(Order) error) (Order, error) {
	var order Order
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var err error
		order, err = scanOrder(tx.QueryRow(ctx, `SELECT `+orderColumns+` FROM store_orders WHERE order_id = $1 FOR UPDATE`, orderID))
		if err != nil {
			return err
		}
		if order.AccountID != accountID {
			return ErrNotFound
		}
		if order.Status == "paid" {
			return nil
		}
		if order.Status != "init" {
			return ErrOrderState
		}
		if err := charge(order); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE store_orders SET status = 'paid', steam_status = 'Succeeded', updated_at = now() WHERE order_id = $1`, orderID); err != nil {
			return err
		}
		var items []json.RawMessage
		if err := json.Unmarshal(order.Items, &items); err != nil {
			return err
		}
		detail, _ := json.Marshal(map[string]any{"sku": order.SKU, "order_id": order.OrderID, "description": order.Description})
		for _, item := range items {
			if _, err := tx.Exec(ctx, `INSERT INTO mail (account_id, kind, item_kind, item, detail) VALUES ($1, 'store', 'item', $2, $3)`, accountID, item, detail); err != nil {
				return err
			}
		}
		order.Status = "paid"
		return auditTx(ctx, tx, &accountID, serverID, "store.paid", map[string]any{"order_id": order.OrderID, "sku": order.SKU, "amount": order.Amount, "currency": order.Currency})
	})
	return order, err
}

func (s *Store) CancelOrder(ctx context.Context, accountID, orderID int64) (Order, error) {
	order, err := scanOrder(s.pool.QueryRow(ctx, `UPDATE store_orders SET status = 'cancelled', updated_at = now() WHERE order_id = $1 AND account_id = $2 AND status = 'init' RETURNING `+orderColumns, orderID, accountID))
	if errors.Is(err, ErrNotFound) {
		current, findErr := scanOrder(s.pool.QueryRow(ctx, `SELECT `+orderColumns+` FROM store_orders WHERE order_id = $1 AND account_id = $2`, orderID, accountID))
		if findErr != nil {
			return current, findErr
		}
		return current, ErrOrderState
	}
	return order, err
}

func (s *Store) OpenOrders(ctx context.Context, accountID int64, olderThan time.Duration) ([]Order, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+orderColumns+` FROM store_orders WHERE account_id = $1 AND status = 'init' AND created_at < now() - make_interval(secs => $2) ORDER BY created_at LIMIT 20`, accountID, olderThan.Seconds())
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (Order, error) { return scanOrder(row) })
}

// PurgeOrders removes orders older than the retention period (5 years by default).
func (s *Store) PurgeOrders(ctx context.Context, days int) error {
	if days <= 0 {
		return nil
	}
	_, err := s.pool.Exec(ctx, `DELETE FROM store_orders WHERE created_at < now() - make_interval(days => $1)`, days)
	return err
}
