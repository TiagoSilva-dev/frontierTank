package main

import (
	"strconv"
	"testing"
)

// Daily challenge (0.22): one best score per player and day, the day's top, the replay of
// the best run, the export and the purge.
func (h *harness) submitChallenge(who *trader, day, score int, replay string) (int, map[string]any) {
	return h.internalCall("POST", "/internal/challenge/submit", map[string]any{"day": day, "account_id": who.id, "name": who.name, "score": score, "ticks": 600, "replay": map[string]any{"v": 1, "note": replay}})
}

func TestChallengeScores(t *testing.T) {
	h := newHarness(t)
	a := h.newTrader("chal_a", "Alfa")
	b := h.newTrader("chal_b", "Beta")
	c := h.newTrader("chal_c", "Gama")
	status, out := h.submitChallenge(a, 3, 2000, "a1")
	if status != 200 || out["best"] != true || out["score"].(float64) != 2000 || out["position"].(float64) != 1 || out["total"].(float64) != 1 {
		t.Fatal("first score", status, out)
	}
	if status, out = h.submitChallenge(a, 3, 1500, "a2"); status != 200 || out["best"] != false || out["score"].(float64) != 2000 {
		t.Fatal("a worse score never replaces the best", status, out)
	}
	if status, out = h.submitChallenge(a, 3, 2600, "a3"); out["best"] != true || out["score"].(float64) != 2600 {
		t.Fatal("a better score does", status, out)
	}
	h.submitChallenge(b, 3, 3000, "b1")
	h.submitChallenge(c, 3, 2600, "c1")
	h.submitChallenge(c, 4, 100, "c-other-day")
	status, out = h.internalCall("GET", "/internal/challenge/top?day=3&limit=2&account="+strconv.FormatInt(c.id, 10), nil)
	rows := out["rows"].([]any)
	if status != 200 || len(rows) != 2 || rows[0].(map[string]any)["name"] != "Beta" || rows[1].(map[string]any)["name"] != "Alfa" {
		t.Fatalf("ordered by score, ties by who got there first: %v", out)
	}
	if out["position"].(float64) != 3 || out["total"].(float64) != 3 {
		t.Fatalf("the third of three, other days not counted: %v", out)
	}
	status, out = h.internalCall("GET", "/internal/challenge/top?day=4", nil)
	if status != 200 || len(out["rows"].([]any)) != 1 || out["position"].(float64) != 0 {
		t.Fatalf("each day has its own list: %v", out)
	}
	status, out = h.internalCall("GET", "/internal/challenge/replay?day=3&account="+strconv.FormatInt(a.id, 10), nil)
	replay, _ := out["replay"].(map[string]any)
	if status != 200 || replay["note"] != "a3" {
		t.Fatalf("the replay is the one of the best run: %v", out)
	}
	if status, _ = h.internalCall("GET", "/internal/challenge/replay?day=9&account="+strconv.FormatInt(a.id, 10), nil); status != 404 {
		t.Fatal("no replay for a day not played", status)
	}
	if status, _ = h.internalCall("POST", "/internal/challenge/submit", map[string]any{"day": -1, "account_id": a.id, "score": 5, "replay": map[string]any{}}); status != 400 {
		t.Fatal("a bad day is refused", status)
	}
	if status, _ = h.internalCall("POST", "/internal/challenge/submit", map[string]any{"day": 1, "account_id": a.id, "score": -5, "replay": map[string]any{"v": 1}}); status != 400 {
		t.Fatal("a negative score is refused", status)
	}
	if status, _ = h.call(h.public, "GET", "/internal/challenge/top?day=3", nil, nil); status == 200 {
		t.Fatal("the public port does not serve it")
	}
	// The player's export lists the scores, without the replays.
	var exported int
	if err := h.store.pool.QueryRow(h.t.Context(), `SELECT count(*) FROM challenge_scores WHERE account_id = $1`, a.id).Scan(&exported); err != nil || exported != 1 {
		t.Fatal("one row for the player", exported, err)
	}
	data, err := h.store.ExportAccount(h.t.Context(), a.id)
	if err != nil || data["challenge_scores"] == nil {
		t.Fatal("export", err, data)
	}
	// Old days are purged from the newest one.
	h.submitChallenge(a, 40, 700, "late")
	if err := h.store.PurgeChallenge(h.t.Context(), 30); err != nil {
		t.Fatal(err)
	}
	if err := h.store.pool.QueryRow(h.t.Context(), `SELECT count(*) FROM challenge_scores`).Scan(&exported); err != nil || exported != 1 {
		t.Fatal("only the day within 30 of the newest stays", exported, err)
	}
}
