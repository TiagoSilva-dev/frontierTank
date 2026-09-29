package main

import (
	"context"
	"fmt"
	"sync"
	"testing"
)

func TestExchangeMath(t *testing.T) {
	maker := ExchangeOrder{Account: 1, Give: "estrela", Want: "brasa", GiveUnit: 1, WantUnit: 2, Remaining: 5}
	taker := ExchangeOrder{Account: 2, Give: "brasa", Want: "estrela", GiveUnit: 3, WantUnit: 1, Remaining: 3}
	tl, ml, pay, receive := exchangeFill(taker, maker)
	if tl != 3 || ml != 3 || pay != 6 || receive != 3 {
		t.Fatal(tl, ml, pay, receive)
	}
	taker.Account = 1
	if a, _, _, _ := exchangeFill(taker, maker); a != 0 {
		t.Fatal("self trade")
	}
	taker.Account = 2
	taker.GiveUnit = 1
	if a, _, _, _ := exchangeFill(taker, maker); a != 0 {
		t.Fatal("worse price")
	}
	maker.GiveUnit = 3
	maker.WantUnit = 2
	taker.GiveUnit = 2
	taker.WantUnit = 2
	taker.Remaining = 2
	if a, _, _, _ := exchangeFill(taker, maker); a != 0 {
		t.Fatal("fractional lots must wait")
	}
	for _, id := range []string{"brasa", "strength_stone_12", "pedra_fortalecimento"} {
		if !validExchange(ExchangeOrder{Give: id, Want: "solar", GiveUnit: 1, WantUnit: 2, Lots: 4}) {
			t.Fatal(id)
		}
	}
	for _, o := range []ExchangeOrder{{Give: "coins", Want: "solar", GiveUnit: 1, WantUnit: 1, Lots: 1}, {Give: "solar", Want: "solar", GiveUnit: 1, WantUnit: 1, Lots: 1}, {Give: "brasa", Want: "solar", GiveUnit: 1000000, WantUnit: 1, Lots: 2}} {
		if validExchange(o) {
			t.Fatal("invalid order accepted", o)
		}
	}
}
func (h *harness) exchange(who *trader, op, give, want string, g, w, l int64) (int, map[string]any) {
	status, out := h.internalCall("POST", "/internal/exchange/create", map[string]any{"op_id": op, "server_id": "s1", "account_id": who.id, "profile": who.profile(op), "order": map[string]any{"give_id": give, "want_id": want, "give_unit": g, "want_unit": w, "lots": l}})
	if status == 200 {
		who.version = int64(out["version"].(float64))
	}
	return status, out
}
func TestExchangeTransactions(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	seller := h.newTrader("exchange_seller", "Vendedor")
	buyer := h.newTrader("exchange_buyer", "Comprador")
	status, out := h.exchange(seller, "exchange-maker", "estrela", "brasa", 5, 10, 1)
	if status != 200 {
		t.Fatal(status, out)
	}
	order := out["order"].(map[string]any)
	id := int64(order["id"].(float64))
	if order["give_unit"].(float64) != 1 || order["remaining"].(float64) != 5 {
		t.Fatal("normalization", order)
	}
	status, out = h.exchange(buyer, "exchange-taker", "brasa", "estrela", 3, 1, 3)
	if status != 200 {
		t.Fatal(status, out)
	}
	if out["order"].(map[string]any)["status"] != "filled" {
		t.Fatal(out)
	}
	// Retrying the op returns its original result without a second debit or mail.
	_, retry := h.exchange(buyer, "exchange-taker", "brasa", "estrela", 3, 1, 3)
	if retry["version"] != out["version"] {
		t.Fatal("non-idempotent retry")
	}
	var brasa, estrela int
	err := h.store.pool.QueryRow(ctx, `SELECT COALESCE(sum((currencies->>'brasa')::int),0), COALESCE(sum((currencies->>'estrela')::int),0) FROM mail WHERE account_id=$1`, buyer.id).Scan(&brasa, &estrela)
	if err != nil || brasa != 3 || estrela != 3 {
		t.Fatal("better price refund", brasa, estrela, err)
	}
	status, out = h.internalCall("POST", "/internal/exchange/cancel", map[string]any{"op_id": "exchange-wrong-owner", "account_id": buyer.id, "id": id})
	if status != 409 || out["error"] != "not_yours" {
		t.Fatal(status, out)
	}
	status, out = h.internalCall("POST", "/internal/exchange/cancel", map[string]any{"op_id": "exchange-cancel", "account_id": seller.id, "id": id})
	if status != 200 {
		t.Fatal(status, out)
	}
	err = h.store.pool.QueryRow(ctx, `SELECT COALESCE(sum((currencies->>'brasa')::int),0),COALESCE(sum((currencies->>'estrela')::int),0) FROM mail WHERE account_id=$1`, seller.id).Scan(&brasa, &estrela)
	if err != nil || brasa != 6 || estrela != 2 {
		t.Fatal("escrow refund", brasa, estrela, err)
	}
	// Stone trades use the exact same custody and settlement path.
	status, out = h.exchange(seller, "exchange-stone", "strength_stone_12", "solar", 1, 4, 1)
	if status != 200 {
		t.Fatal(out)
	}
	status, out = h.exchange(buyer, "exchange-stone-buy", "solar", "strength_stone_12", 4, 1, 1)
	if status != 200 || out["order"].(map[string]any)["status"] != "filled" {
		t.Fatal(status, out)
	}
	// Version conflicts must not create escrow.
	seller.version = 0
	status, out = h.exchange(seller, "exchange-stale", "brasa", "solar", 1, 1, 1)
	if status != 409 || out["error"] != "version_conflict" {
		t.Fatal(status, out)
	}
	var n int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM exchange_orders WHERE account_id=$1 AND give_id='brasa'`, seller.id).Scan(&n)
	if n != 0 {
		t.Fatal("partial transaction survived")
	}
	if err = h.store.DeleteAccount(ctx, buyer.id); err != nil {
		t.Fatal(err)
	}
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM exchange_orders WHERE account_id=$1`, buyer.id).Scan(&n)
	if n != 0 {
		t.Fatal("account deletion left orders")
	}
}
func TestExchangeConcurrentAndPriority(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	expensive := h.newTrader("ex_expensive", "Caro")
	cheap := h.newTrader("exchange_cheap", "Barato")
	if s, r := h.exchange(expensive, "expensive", "estrela", "brasa", 1, 4, 4); s != 200 {
		t.Fatal(r)
	}
	if s, r := h.exchange(cheap, "cheap", "estrela", "brasa", 1, 2, 2); s != 200 {
		t.Fatal(r)
	}
	buyers := []*trader{}
	for i := 0; i < 8; i++ {
		buyers = append(buyers, h.newTrader(fmt.Sprintf("buyer_%d", i), fmt.Sprintf("Buyer%d", i)))
	}
	var wg sync.WaitGroup
	var mu sync.Mutex
	filled := 0
	for i, b := range buyers {
		wg.Add(1)
		go func(i int, b *trader) {
			defer wg.Done()
			s, r := h.exchange(b, fmt.Sprintf("race-%d", i), "brasa", "estrela", 3, 1, 1)
			mu.Lock()
			defer mu.Unlock()
			if s != 200 {
				t.Errorf("race %d: %d %v", i, s, r)
			} else if r["order"].(map[string]any)["status"] == "filled" {
				filled++
			}
		}(i, b)
	}
	wg.Wait()
	if filled != 2 {
		t.Fatal("over/underfilled", filled)
	}
	var remaining int
	if err := h.store.pool.QueryRow(ctx, `SELECT remaining FROM exchange_orders WHERE account_id=$1`, expensive.id).Scan(&remaining); err != nil || remaining != 4 {
		t.Fatal("executed worse price", remaining, err)
	}
	var total int
	if err := h.store.pool.QueryRow(ctx, `SELECT COALESCE(sum((currencies->>'estrela')::int),0) FROM mail`).Scan(&total); err != nil || total != 2 {
		t.Fatal("currency duplication", total, err)
	}
	// Same-account opposite orders never match.
	if s, r := h.exchange(expensive, "self", "brasa", "estrela", 4, 1, 1); s != 200 || r["order"].(map[string]any)["status"] != "active" {
		t.Fatal("self match", s, r)
	}
}

func TestExchangeLimitsAndCancelRetry(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	owner := h.newTrader("ex_limit", "Limite")
	var first int64
	for i := 0; i < 10; i++ {
		status, out := h.exchange(owner, fmt.Sprintf("limit-%d", i), "brasa", "solar", 1, 1, 1)
		if status != 200 {
			t.Fatal(status, out)
		}
		if i == 0 {
			first = int64(out["order"].(map[string]any)["id"].(float64))
		}
	}
	status, out := h.exchange(owner, "limit-over", "brasa", "solar", 1, 1, 1)
	if status != 409 || out["error"] != "too_many_listings" {
		t.Fatal(status, out)
	}
	body := map[string]any{"op_id": "cancel-retry", "account_id": owner.id, "id": first}
	for i := 0; i < 2; i++ {
		status, out = h.internalCall("POST", "/internal/exchange/cancel", body)
		if status != 200 {
			t.Fatal(status, out)
		}
	}
	var mails int
	if err := h.store.pool.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id=$1`, owner.id).Scan(&mails); err != nil || mails != 1 {
		t.Fatal("duplicate cancellation refund", mails, err)
	}
	status, out = h.exchange(owner, "after-cancel", "brasa", "solar", 1, 1, 1)
	if status != 200 {
		t.Fatal(status, out)
	}
	body["op_id"] = "cancel-again"
	status, out = h.internalCall("POST", "/internal/exchange/cancel", body)
	if status != 409 {
		t.Fatal("cancelled twice", out)
	}
}
func TestExchangePriceTime(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	first := h.newTrader("first_maker", "Primeiro")
	second := h.newTrader("second_maker", "Segundo")
	buyer := h.newTrader("time_buyer", "Terceiro")
	h.exchange(first, "first", "estrela", "brasa", 1, 2, 1)
	h.exchange(second, "second", "estrela", "brasa", 1, 2, 1)
	status, out := h.exchange(buyer, "take-first", "brasa", "estrela", 2, 1, 1)
	if status != 200 {
		t.Fatal(status, out)
	}
	var state string
	if err := h.store.pool.QueryRow(ctx, `SELECT status FROM exchange_orders WHERE account_id=$1`, first.id).Scan(&state); err != nil || state != "filled" {
		t.Fatal("time priority", state, err)
	}
	if err := h.store.pool.QueryRow(ctx, `SELECT status FROM exchange_orders WHERE account_id=$1`, second.id).Scan(&state); err != nil || state != "active" {
		t.Fatal("time priority", state, err)
	}
}
