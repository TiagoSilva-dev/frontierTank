package main

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"net/http"
	"sort"
)

const exchangeMax = int64(1000000)

var ErrExchangeInput = errors.New("invalid exchange order")

type ExchangeOrder struct {
	ID        int64  `json:"id"`
	Account   int64  `json:"-"`
	Give      string `json:"give_id"`
	Want      string `json:"want_id"`
	GiveUnit  int64  `json:"give_unit"`
	WantUnit  int64  `json:"want_unit"`
	Lots      int64  `json:"lots"`
	Remaining int64  `json:"remaining"`
	Fee       int64  `json:"fee"`
	Status    string `json:"status"`
	Created   int64  `json:"created_at"`
}

const exchangeColumns = `id,account_id,give_id,want_id,give_unit,want_unit,lots,remaining,fee,status,extract(epoch from created_at)::bigint`

func scanExchange(r pgx.Row) (o ExchangeOrder, err error) {
	err = r.Scan(&o.ID, &o.Account, &o.Give, &o.Want, &o.GiveUnit, &o.WantUnit, &o.Lots, &o.Remaining, &o.Fee, &o.Status, &o.Created)
	return
}
func exchangeAsset(id string) bool {
	switch id {
	case "brasa", "coroa", "estrela", "tormenta", "solar", "eclipse", "espelho",
		"pedra_fortalecimento", "strength_stone_ii", "strength_stone_iii", "strength_stone_iv",
		"strength_stone_5", "strength_stone_6", "strength_stone_7", "strength_stone_8", "strength_stone_9", "strength_stone_10", "strength_stone_11", "strength_stone_12":
		return true
	}
	return false
}
func validExchange(o ExchangeOrder) bool {
	return exchangeAsset(o.Give) && exchangeAsset(o.Want) && o.Give != o.Want && o.GiveUnit > 0 && o.WantUnit > 0 && o.Lots > 0 && o.GiveUnit <= exchangeMax && o.WantUnit <= exchangeMax && o.Lots <= exchangeMax && o.GiveUnit*o.Lots <= exchangeMax && o.WantUnit*o.Lots <= exchangeMax
}
func exchangeFee(o ExchangeOrder) int64 { return 5 + (o.GiveUnit*o.Lots+99)/100 }
func gcdExchange(a, b int64) int64 {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

// Execution uses the resting order's price, price/time priority and integral lots.
// The incoming order's unused budget is returned; neither side receives fractions.
func exchangeFill(t, m ExchangeOrder) (tLots, mLots, pay, receive int64) {
	if t.Account == m.Account || t.Give != m.Want || t.Want != m.Give || t.GiveUnit*m.GiveUnit < t.WantUnit*m.WantUnit {
		return
	}
	block := t.WantUnit / gcdExchange(t.WantUnit, m.GiveUnit) * m.GiveUnit
	tb, mb := block/t.WantUnit, block/m.GiveUnit
	n := min(t.Remaining/tb, m.Remaining/mb)
	return n * tb, n * mb, n * mb * m.WantUnit, n * block
}
func exchangeMail(ctx context.Context, tx pgx.Tx, account, order int64, kind string, bundle map[string]int64) error {
	data, _ := json.Marshal(bundle)
	detail, _ := json.Marshal(map[string]any{"order": order})
	_, err := tx.Exec(ctx, `INSERT INTO mail(account_id,kind,currencies,detail) VALUES($1,$2,$3,$4)`, account, kind, data, detail)
	return err
}
func (s *Store) CreateExchange(ctx context.Context, op, server string, account int64, profile ProfileWrite, in ExchangeOrder) (json.RawMessage, error) {
	if !validExchange(in) {
		return nil, ErrExchangeInput
	}
	divisor := gcdExchange(in.GiveUnit, in.WantUnit)
	in.GiveUnit /= divisor
	in.WantUnit /= divisor
	in.Lots *= divisor
	return s.runOp(ctx, op, account, func(tx pgx.Tx) (any, error) {
		// One short matching transaction at a time also serializes cancellations and limits.
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(7062026)`); err != nil {
			return nil, err
		}
		version, err := saveProfile(ctx, tx, account, profile.Name, profile.Data, profile.Version)
		if err != nil {
			return nil, err
		}
		var count int
		if err = tx.QueryRow(ctx, `SELECT count(*) FROM exchange_orders WHERE account_id=$1 AND status='active'`, account).Scan(&count); err != nil {
			return nil, err
		}
		if count >= 10 {
			return nil, ErrTooMany
		}
		in, err = scanExchange(tx.QueryRow(ctx, `INSERT INTO exchange_orders(account_id,give_id,want_id,give_unit,want_unit,lots,remaining,fee) VALUES($1,$2,$3,$4,$5,$6,$6,$7) RETURNING `+exchangeColumns, account, in.Give, in.Want, in.GiveUnit, in.WantUnit, in.Lots, exchangeFee(in)))
		if err != nil {
			return nil, err
		}
		rows, err := tx.Query(ctx, `SELECT `+exchangeColumns+` FROM exchange_orders WHERE give_id=$1 AND want_id=$2 AND status='active' AND account_id<>$3 AND give_unit*$4 >= want_unit*$5 ORDER BY want_unit::numeric/give_unit,id FOR UPDATE`, in.Want, in.Give, account, in.GiveUnit, in.WantUnit)
		if err != nil {
			return nil, err
		}
		makers, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (ExchangeOrder, error) { return scanExchange(r) })
		if err != nil {
			return nil, err
		}
		// Compare rational prices exactly (all products fit int64).
		sort.SliceStable(makers, func(i, j int) bool {
			return makers[i].WantUnit*makers[j].GiveUnit < makers[j].WantUnit*makers[i].GiveUnit
		})
		receipts := map[string]int64{}
		notify := []int64{}
		for _, m := range makers {
			tl, ml, pay, receive := exchangeFill(in, m)
			if tl == 0 {
				continue
			}
			in.Remaining -= tl
			m.Remaining -= ml
			if m.Remaining == 0 {
				m.Status = "filled"
			}
			if _, err = tx.Exec(ctx, `UPDATE exchange_orders SET remaining=$2,status=$3 WHERE id=$1`, m.ID, m.Remaining, m.Status); err != nil {
				return nil, err
			}
			if err = exchangeMail(ctx, tx, m.Account, m.ID, "exchange_fill", map[string]int64{m.Want: pay}); err != nil {
				return nil, err
			}
			receipts[in.Want] += receive
			if refund := tl*in.GiveUnit - pay; refund > 0 {
				receipts[in.Give] += refund
			}
			notify = append(notify, m.Account)
			if err = auditTx(ctx, tx, &account, server, "exchange.fill", map[string]any{"order": in.ID, "maker_order": m.ID, "give_id": in.Give, "want_id": in.Want, "paid": pay, "received": receive}); err != nil {
				return nil, err
			}
			if err = auditTx(ctx, tx, &m.Account, server, "exchange.fill", map[string]any{"order": m.ID, "taker_order": in.ID, "give_id": m.Give, "want_id": m.Want, "paid": receive, "received": pay}); err != nil {
				return nil, err
			}
			if in.Remaining == 0 {
				break
			}
		}
		if in.Remaining == 0 {
			in.Status = "filled"
		}
		if _, err = tx.Exec(ctx, `UPDATE exchange_orders SET remaining=$2,status=$3 WHERE id=$1`, in.ID, in.Remaining, in.Status); err != nil {
			return nil, err
		}
		if len(receipts) > 0 {
			if err = exchangeMail(ctx, tx, account, in.ID, "exchange_fill", receipts); err != nil {
				return nil, err
			}
		}
		if err = auditTx(ctx, tx, &account, server, "exchange.create", in); err != nil {
			return nil, err
		}
		return map[string]any{"version": version, "order": in, "notify": notify}, nil
	})
}
func (s *Store) CancelExchange(ctx context.Context, op, server string, account, id int64) (json.RawMessage, error) {
	return s.runOp(ctx, op, account, func(tx pgx.Tx) (any, error) {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(7062026)`); err != nil {
			return nil, err
		}
		o, err := scanExchange(tx.QueryRow(ctx, `SELECT `+exchangeColumns+` FROM exchange_orders WHERE id=$1 FOR UPDATE`, id))
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrListingGone
		}
		if err != nil {
			return nil, err
		}
		if o.Account != account {
			return nil, ErrNotYours
		}
		if o.Status != "active" {
			return nil, ErrListingGone
		}
		if err = exchangeMail(ctx, tx, account, id, "exchange_return", map[string]int64{o.Give: o.GiveUnit * o.Remaining}); err != nil {
			return nil, err
		}
		if _, err = tx.Exec(ctx, `UPDATE exchange_orders SET status='cancelled' WHERE id=$1`, id); err != nil {
			return nil, err
		}
		o.Status = "cancelled"
		if err = auditTx(ctx, tx, &account, server, "exchange.cancel", o); err != nil {
			return nil, err
		}
		return map[string]any{"order": o}, nil
	})
}
func (s *Store) ExchangeBook(ctx context.Context, account int64, give, want string) (map[string]any, error) {
	read := func(sql string, args ...any) ([]ExchangeOrder, error) {
		rows, err := s.pool.Query(ctx, sql, args...)
		if err != nil {
			return nil, err
		}
		out, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (ExchangeOrder, error) { return scanExchange(r) })
		if out == nil {
			out = []ExchangeOrder{}
		}
		return out, err
	}
	offers, err := read(`SELECT `+exchangeColumns+` FROM exchange_orders WHERE status='active' AND give_id=$1 AND want_id=$2 AND account_id<>$3 ORDER BY want_unit::numeric/give_unit,id LIMIT 50`, want, give, account)
	if err != nil {
		return nil, err
	}
	competing, err := read(`SELECT `+exchangeColumns+` FROM exchange_orders WHERE status='active' AND give_id=$1 AND want_id=$2 AND account_id<>$3 ORDER BY give_unit::numeric/want_unit DESC,id LIMIT 50`, give, want, account)
	if err != nil {
		return nil, err
	}
	mine, err := read(`SELECT `+exchangeColumns+` FROM exchange_orders WHERE account_id=$1 ORDER BY (status='active') DESC,id DESC LIMIT 50`, account)
	if err != nil {
		return nil, err
	}
	return map[string]any{"offers": offers, "competing": competing, "orders": mine}, nil
}
func (a *API) exchangeRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /internal/exchange/{action}", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Op      string        `json:"op_id"`
			Server  string        `json:"server_id"`
			Account int64         `json:"account_id"`
			Profile ProfileWrite  `json:"profile"`
			Order   ExchangeOrder `json:"order"`
			ID      int64         `json:"id"`
			Give    string        `json:"give_id"`
			Want    string        `json:"want_id"`
		}
		if readJSON(r, &in) != nil || in.Account <= 0 {
			writeError(w, 400, codeBadRequest, "invalid exchange")
			return
		}
		action := r.PathValue("action")
		if action == "book" {
			if !exchangeAsset(in.Give) || !exchangeAsset(in.Want) || in.Give == in.Want {
				writeError(w, 400, codeBadRequest, "invalid pair")
				return
			}
			out, err := a.store.ExchangeBook(r.Context(), in.Account, in.Give, in.Want)
			if err != nil {
				a.fail(w, err)
				return
			}
			writeJSON(w, 200, out)
			return
		}
		if !validOpID(in.Op) {
			writeError(w, 400, codeBadRequest, "invalid operation")
			return
		}
		var out json.RawMessage
		var err error
		switch action {
		case "create":
			if !validExchange(in.Order) || !validProfileWrite(&in.Profile) {
				writeError(w, 400, codeBadRequest, "invalid order")
				return
			}
			out, err = a.store.CreateExchange(r.Context(), in.Op, in.Server, in.Account, in.Profile, in.Order)
		case "cancel":
			out, err = a.store.CancelExchange(r.Context(), in.Op, in.Server, in.Account, in.ID)
		default:
			writeError(w, 404, codeBadRequest, "unknown operation")
			return
		}
		if err != nil {
			a.auctionFail(w, err)
			return
		}
		writeRaw(w, out)
	})
}
