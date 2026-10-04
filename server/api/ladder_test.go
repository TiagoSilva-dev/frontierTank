package main

import (
	"strconv"
	"testing"
)

// Ranked ladder (0.22): the board is a query over the rating inside each profile.
func (h *harness) rate(who *trader, rating map[string]any) {
	h.t.Helper()
	status, out := h.internalCall("PUT", "/internal/profiles/"+strconv.FormatInt(who.id, 10), map[string]any{"name": who.name, "data": map[string]any{"rating": rating}, "version": who.version})
	if status != 200 {
		h.t.Fatal(status, out)
	}
	who.version = int64(out["version"].(float64))
}

func TestLadder(t *testing.T) {
	h := newHarness(t)
	a := h.newTrader("ladder_a", "Alfa")
	b := h.newTrader("ladder_b", "Beta")
	c := h.newTrader("ladder_c", "Gama")
	d := h.newTrader("ladder_d", "Delta")
	e := h.newTrader("ladder_e", "Epsilon")
	f := h.newTrader("ladder_f", "Zeta")
	h.rate(a, map[string]any{"season": 1, "mmr": 1100, "games": 10, "wins": 5, "losses": 5})
	h.rate(b, map[string]any{"season": 1, "mmr": 1100, "games": 12, "wins": 7, "losses": 5})
	h.rate(c, map[string]any{"season": 1, "mmr": 900, "games": 6, "wins": 1, "losses": 5})
	h.rate(d, map[string]any{"season": 2, "mmr": 1500, "games": 6, "wins": 6, "losses": 0})
	h.rate(e, map[string]any{"season": 1, "mmr": 1700, "games": 0, "wins": 0, "losses": 0})
	h.rate(f, map[string]any{"season": "oops", "mmr": "x"})

	status, out := h.internalCall("GET", "/internal/ladder?season=1&limit=2&account="+strconv.FormatInt(c.id, 10), nil)
	if status != 200 {
		t.Fatal(status, out)
	}
	rows := out["rows"].([]any)
	if len(rows) != 2 || rows[0].(map[string]any)["name"] != "Beta" || rows[1].(map[string]any)["name"] != "Alfa" {
		t.Fatalf("the top is ordered by rating, then wins: %v", rows)
	}
	if rows[0].(map[string]any)["position"].(float64) != 1 || rows[1].(map[string]any)["mmr"].(float64) != 1100 {
		t.Fatalf("positions and ratings: %v", rows)
	}
	if out["position"].(float64) != 3 || out["total"].(float64) != 3 {
		t.Fatalf("the asking account is third of three (other seasons, no games and broken ratings are left out): %v", out)
	}
	status, out = h.internalCall("GET", "/internal/ladder?season=1&limit=50", nil)
	if status != 200 || len(out["rows"].([]any)) != 3 || out["position"].(float64) != 0 {
		t.Fatalf("without an account there is no position: %v", out)
	}
	status, out = h.internalCall("GET", "/internal/ladder?season=2", nil)
	if status != 200 || len(out["rows"].([]any)) != 1 || out["rows"].([]any)[0].(map[string]any)["name"] != "Delta" {
		t.Fatalf("each season has its own board: %v", out)
	}
	if status, _ = h.internalCall("GET", "/internal/ladder?season=0", nil); status != 400 {
		t.Fatal("a season below 1 is refused", status)
	}
	if status, out = h.call(h.public, "GET", "/internal/ladder?season=1", nil, nil); status == 200 {
		t.Fatal("the public port does not serve the board", out)
	}
}
