package main

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"testing"
)

// Leilão (0.12): custody, sale, mail, cancel, expiry, repeated op ids, two buyers at
// once and account deletion. Needs PostgreSQL (TEST_DATABASE_URL), like the other
// integration tests.

type trader struct {
	id      int64
	name    string
	version int64
}

func (h *harness) newTrader(username, name string) *trader {
	h.t.Helper()
	status, reply := h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": username, "password": "senha-forte-1"}, nil)
	if status != http.StatusCreated {
		h.t.Fatalf("register %s: %d %v", username, status, reply)
	}
	who := &trader{id: int64(reply["account"].(map[string]any)["id"].(float64)), name: name}
	status, reply = h.internalCall("PUT", "/internal/profiles/"+strconv.FormatInt(who.id, 10), map[string]any{"name": name, "data": map[string]any{"coins": 100}, "version": 0})
	if status != http.StatusOK {
		h.t.Fatalf("profile %s: %d %v", name, status, reply)
	}
	who.version = int64(reply["version"].(float64))
	return who
}

func (who *trader) profile(note string) map[string]any {
	return map[string]any{"name": who.name, "data": map[string]any{"note": note}, "version": who.version}
}

func weaponListing(price int) map[string]any {
	return map[string]any{"kind": "item", "item": map[string]any{"id": "trovao", "quality": "verdadeira", "ilvl": 12, "level": 3, "mods": []any{}},
		"slot": "arma", "item_id": "trovao", "quality": "verdadeira", "item_level": 12, "strengthen": 3, "mods": []string{"dano", "critico"},
		"price_solar": price, "price_estrela": 4, "fee_solar": price / 20, "fee_estrela": 0, "hours": 24}
}

func (h *harness) list(who *trader, op string, listing map[string]any, maxActive int) (int, map[string]any) {
	status, reply := h.internalCall("POST", "/internal/auction/listings", map[string]any{"op_id": op, "server_id": "s1", "account_id": who.id, "profile": who.profile(op), "listing": listing, "max_active": maxActive})
	if status == http.StatusOK {
		who.version = int64(reply["version"].(float64))
	}
	return status, reply
}

func (h *harness) buy(who *trader, op string, listing int64, solar, estrela int) (int, map[string]any) {
	status, reply := h.internalCall("POST", fmt.Sprintf("/internal/auction/listings/%d/buy", listing), map[string]any{"op_id": op, "server_id": "s1", "account_id": who.id, "price_solar": solar, "price_estrela": estrela, "profile": who.profile(op)})
	if status == http.StatusOK {
		who.version = int64(reply["version"].(float64))
	}
	return status, reply
}

func (h *harness) search(filter map[string]any) []any {
	h.t.Helper()
	status, reply := h.internalCall("POST", "/internal/auction/search", filter)
	if status != http.StatusOK {
		h.t.Fatalf("search: %d %v", status, reply)
	}
	return reply["listings"].([]any)
}

func (h *harness) mail(who *trader) []any {
	h.t.Helper()
	status, reply := h.internalCall("GET", "/internal/mail?account="+strconv.FormatInt(who.id, 10), nil)
	if status != http.StatusOK {
		h.t.Fatalf("mail: %d %v", status, reply)
	}
	return reply["mail"].([]any)
}

func listingID(reply map[string]any) int64 {
	return int64(reply["listing"].(map[string]any)["id"].(float64))
}

func TestAuction(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	seller := h.newTrader("vendedor", "Sol")
	buyer := h.newTrader("comprador", "Lua")
	rival := h.newTrader("rival", "Vento")

	// Custody: the listing and the seller's profile are written together.
	status, reply := h.list(seller, "op-list-1", weaponListing(20), 2)
	if status != http.StatusOK || seller.version != 2 {
		t.Fatalf("create listing: %d %v", status, reply)
	}
	first := listingID(reply)
	again, repeated := h.internalCall("POST", "/internal/auction/listings", map[string]any{"op_id": "op-list-1", "server_id": "s1", "account_id": seller.id, "profile": map[string]any{"name": "Sol", "data": map[string]any{}, "version": 1}, "listing": weaponListing(20), "max_active": 2})
	if again != http.StatusOK || listingID(repeated) != first || len(h.search(map[string]any{})) != 1 {
		t.Fatalf("a repeated op id returns the first result and lists nothing new: %d %v", again, repeated)
	}
	if status, reply = h.internalCall("POST", "/internal/auction/listings", map[string]any{"op_id": "op-stale", "server_id": "s1", "account_id": seller.id, "profile": map[string]any{"name": "Sol", "data": map[string]any{}, "version": 1}, "listing": weaponListing(20), "max_active": 5}); reply["error"] != codeConflict {
		t.Fatalf("a stale profile version lists nothing: %d %v", status, reply)
	}
	if status, reply = h.list(seller, "op-list-bad", map[string]any{"kind": "item", "item": map[string]any{"id": "x"}, "slot": "arma", "item_id": "x", "quality": "normal", "item_level": 1, "price_solar": 0, "price_estrela": 0, "hours": 12}, 5); status != http.StatusBadRequest {
		t.Fatalf("a listing needs a price: %d %v", status, reply)
	}
	mapListing := map[string]any{"kind": "map", "item": map[string]any{"instance": "templo_sol", "level": 9, "quality": "excelente", "mods": []any{}}, "slot": "mapa", "item_id": "templo_sol", "quality": "excelente", "item_level": 9, "mods": []string{"quantidade"}, "price_solar": 0, "price_estrela": 6, "hours": 12}
	if status, reply = h.list(seller, "op-list-map", mapListing, 2); status != http.StatusOK {
		t.Fatalf("a map is listed: %d %v", status, reply)
	}
	mapID := listingID(reply)
	if status, reply = h.list(seller, "op-list-3", weaponListing(5), 2); reply["error"] != codeTooMany {
		t.Fatalf("the listing limit holds: %d %v", status, reply)
	}

	// Search and its filters.
	cases := []struct {
		filter map[string]any
		want   int
	}{
		{map[string]any{}, 2},
		{map[string]any{"slot": "arma"}, 1},
		{map[string]any{"slot": "mapa", "min_level": 9}, 1},
		{map[string]any{"slot": "mapa", "min_level": 10}, 0},
		{map[string]any{"quality": "verdadeira", "min_strengthen": 3}, 1},
		{map[string]any{"min_strengthen": 4}, 0},
		{map[string]any{"mod": "critico"}, 1},
		{map[string]any{"mod": "vida"}, 0},
		{map[string]any{"max_solar": 19}, 1},
		{map[string]any{"max_solar": 0}, 1},
		{map[string]any{"max_estrela": 3}, 0},
		{map[string]any{"item_id": "trovao", "max_level": 12}, 1},
	}
	for _, c := range cases {
		if got := len(h.search(c.filter)); got != c.want {
			t.Errorf("search %v: %d listings, want %d", c.filter, got, c.want)
		}
	}
	if sorted := h.search(map[string]any{"sort": "price"}); int64(sorted[0].(map[string]any)["id"].(float64)) != mapID {
		t.Errorf("sorting by price puts the cheapest in Solares first")
	}
	if paged := h.search(map[string]any{"per_page": 1, "page": 1}); len(paged) != 1 {
		t.Errorf("pages: %v", paged)
	}

	// Buying.
	if status, reply = h.buy(seller, "op-own", first, 20, 4); reply["error"] != codeOwnListing {
		t.Fatalf("nobody buys their own listing: %d %v", status, reply)
	}
	if status, reply = h.buy(buyer, "op-cheap", first, 19, 4); reply["error"] != codePriceChanged {
		t.Fatalf("the price must be the listed one: %d %v", status, reply)
	}
	if status, reply = h.buy(buyer, "op-buy-1", first, 20, 4); status != http.StatusOK || buyer.version != 2 || int64(reply["seller_id"].(float64)) != seller.id {
		t.Fatalf("buy: %d %v", status, reply)
	}
	repeatedStatus, repeatedReply := h.internalCall("POST", fmt.Sprintf("/internal/auction/listings/%d/buy", first), map[string]any{"op_id": "op-buy-1", "server_id": "s1", "account_id": buyer.id, "price_solar": 20, "price_estrela": 4, "profile": map[string]any{"name": "Lua", "data": map[string]any{}, "version": 1}})
	if repeatedStatus != http.StatusOK || repeatedReply["mail_id"] != reply["mail_id"] {
		t.Fatalf("a repeated buy returns the same sale: %d %v", repeatedStatus, repeatedReply)
	}
	if status, reply = h.buy(rival, "op-late", first, 20, 4); reply["error"] != codeListingGone {
		t.Fatalf("a sold listing cannot be bought again: %d %v", status, reply)
	}
	if len(h.search(map[string]any{"slot": "arma"})) != 0 {
		t.Fatalf("a sold listing leaves the search")
	}

	// The item goes to the buyer's mail, the price minus the commission to the seller's.
	bought := h.mail(buyer)
	if len(bought) != 1 || bought[0].(map[string]any)["kind"] != "purchase" || bought[0].(map[string]any)["item"].(map[string]any)["id"] != "trovao" {
		t.Fatalf("buyer mail: %v", bought)
	}
	sold := h.mail(seller)
	if len(sold) != 1 || sold[0].(map[string]any)["currencies"].(map[string]any)["solar"].(float64) != 19 || sold[0].(map[string]any)["currencies"].(map[string]any)["estrela"].(float64) != 4 {
		t.Fatalf("seller mail (20 Solares, 5%% commission = 1; 4 Estrelas without commission): %v", sold)
	}
	mailID := int64(bought[0].(map[string]any)["id"].(float64))
	claim := func(who *trader, op string, ids []int64) (int, map[string]any) {
		status, reply := h.internalCall("POST", "/internal/mail/claim", map[string]any{"op_id": op, "server_id": "s1", "account_id": who.id, "ids": ids, "profile": who.profile(op)})
		if status == http.StatusOK {
			who.version = int64(reply["version"].(float64))
		}
		return status, reply
	}
	if status, reply = claim(seller, "op-claim-other", []int64{mailID}); reply["error"] != codeMailGone {
		t.Fatalf("nobody receives someone else's mail: %d %v", status, reply)
	}
	if status, reply = claim(buyer, "op-claim-1", []int64{mailID}); status != http.StatusOK || buyer.version != 3 {
		t.Fatalf("claim: %d %v", status, reply)
	}
	if status, reply = claim(buyer, "op-claim-2", []int64{mailID}); reply["error"] != codeMailGone || len(h.mail(buyer)) != 0 {
		t.Fatalf("mail is received once: %d %v", status, reply)
	}

	// Price history.
	status, reply = h.internalCall("POST", "/internal/auction/history", map[string]any{"kind": "item", "item_id": "trovao", "quality": "verdadeira"})
	if sales := reply["sales"].([]any); status != http.StatusOK || len(sales) != 1 || sales[0].(map[string]any)["price_solar"].(float64) != 20 {
		t.Fatalf("history: %d %v", status, reply)
	}

	// Cancel: only the seller, once, and the item comes back by mail.
	if status, reply = h.internalCall("POST", fmt.Sprintf("/internal/auction/listings/%d/cancel", mapID), map[string]any{"op_id": "op-cancel-x", "account_id": buyer.id}); reply["error"] != codeNotYours {
		t.Fatalf("only the seller cancels: %d %v", status, reply)
	}
	if status, reply = h.internalCall("POST", fmt.Sprintf("/internal/auction/listings/%d/cancel", mapID), map[string]any{"op_id": "op-cancel-1", "account_id": seller.id}); status != http.StatusOK {
		t.Fatalf("cancel: %d %v", status, reply)
	}
	if status, reply = h.internalCall("POST", fmt.Sprintf("/internal/auction/listings/%d/cancel", mapID), map[string]any{"op_id": "op-cancel-2", "account_id": seller.id}); reply["error"] != codeListingGone {
		t.Fatalf("a listing is cancelled once: %d %v", status, reply)
	}
	back := h.mail(seller)
	if len(back) != 2 || back[1].(map[string]any)["kind"] != "returned" || back[1].(map[string]any)["item_kind"] != "map" {
		t.Fatalf("the cancelled map comes back by mail: %v", back)
	}

	// Expiry: out of the search, and back to the seller's mail.
	status, reply = h.list(seller, "op-list-expire", weaponListing(8), 5)
	expiring := listingID(reply)
	if _, err := h.store.pool.Exec(ctx, `UPDATE auction_listings SET expires_at = now() - interval '1 minute' WHERE id = $1`, expiring); err != nil {
		t.Fatal(err)
	}
	if len(h.search(map[string]any{})) != 0 {
		t.Fatalf("an expired listing leaves the search at once")
	}
	if status, reply = h.buy(buyer, "op-buy-expired", expiring, 8, 4); reply["error"] != codeListingGone {
		t.Fatalf("an expired listing cannot be bought: %d %v", status, reply)
	}
	if count, err := h.store.ExpireListings(ctx); err != nil || count != 1 {
		t.Fatalf("expire: %d %v", count, err)
	}
	if back = h.mail(seller); len(back) != 3 || back[2].(map[string]any)["detail"].(map[string]any)["reason"] != "expired" {
		t.Fatalf("the expired item comes back by mail: %v", back)
	}

	// Two buyers at the same moment: exactly one gets it.
	status, reply = h.list(seller, "op-list-race", weaponListing(3), 5)
	race := listingID(reply)
	var wait sync.WaitGroup
	results := make([]string, 2)
	for i, who := range []*trader{buyer, rival} {
		wait.Add(1)
		go func(i int, who *trader) {
			defer wait.Done()
			_, answer := h.internalCall("POST", fmt.Sprintf("/internal/auction/listings/%d/buy", race), map[string]any{"op_id": fmt.Sprintf("op-race-%d", i), "account_id": who.id, "price_solar": 3, "price_estrela": 4, "profile": who.profile("race")})
			results[i] = fmt.Sprint(answer["error"])
		}(i, who)
	}
	wait.Wait()
	wins := 0
	for _, result := range results {
		if result == "<nil>" {
			wins++
		} else if result != codeListingGone {
			t.Errorf("the other buyer is told the listing is gone: %v", results)
		}
	}
	if wins != 1 {
		t.Fatalf("exactly one of two simultaneous buyers wins: %v", results)
	}

	// The seller's view.
	status, reply = h.list(seller, "op-list-last", weaponListing(30), 5)
	status, reply = h.internalCall("GET", "/internal/auction/mine?account="+strconv.FormatInt(seller.id, 10), nil)
	if active, closed := reply["active"].([]any), reply["closed"].([]any); status != http.StatusOK || len(active) != 1 || len(closed) != 4 {
		t.Fatalf("mine: %d %v", status, reply)
	}

	// Deleting the account takes its listings off the auction.
	var sessionToken string
	_, login := h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "vendedor", "password": "senha-forte-1"}, nil)
	sessionToken = login["token"].(string)
	if status, _ = h.call(h.public, "DELETE", "/v1/me", map[string]string{"password": "senha-forte-1"}, map[string]string{"Authorization": "Bearer " + sessionToken}); status != http.StatusNoContent {
		t.Fatalf("delete: %d", status)
	}
	if len(h.search(map[string]any{})) != 0 {
		t.Fatalf("a deleted account's listings leave the auction")
	}
	var named int
	if err := h.store.pool.QueryRow(ctx, `SELECT count(*) FROM auction_listings WHERE seller_name = 'Sol'`).Scan(&named); err != nil || named != 0 {
		t.Fatalf("the history keeps no name of a deleted account: %d %v", named, err)
	}
}
