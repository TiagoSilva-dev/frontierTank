package main

import (
	"context"
	"net/http"
	"strconv"
	"testing"
)

func TestChatReports(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	account := func(name string) (int64, string) {
		_, reply := h.call(h.public, "POST", "/v1/auth/register", map[string]string{"username": name, "password": "senha-forte-1", "accept_terms": testTerms}, nil)
		return int64(reply["account"].(map[string]any)["id"].(float64)), reply["token"].(string)
	}
	lia, liaToken := account("lia")
	troll, trollToken := account("troll")
	report := map[string]any{"server_id": "s1", "reporter_id": lia, "reporter_name": "Lia", "reported_id": troll, "reported_name": "Troll", "reason": "ofensa", "note": "xingou todo mundo", "message": "texto ofensivo",
		"context": []map[string]any{{"author": "Lia", "text": "gg"}, {"author": "Troll", "text": "texto ofensivo"}}}
	status, reply := h.internalCall("POST", "/internal/reports", report)
	if status != http.StatusCreated || reply["recent"].(float64) != 1 {
		t.Fatalf("create report: %d %v", status, reply)
	}
	first := int64(reply["id"].(float64))
	report["reason"] = "invalido"
	if status, _ = h.internalCall("POST", "/internal/reports", report); status != http.StatusBadRequest {
		t.Fatalf("unknown reasons are refused: %d", status)
	}
	report["reason"] = "spam"
	report["auto_muted"] = true
	if _, reply = h.internalCall("POST", "/internal/reports", report); reply["recent"].(float64) != 2 {
		t.Fatalf("recent reports against the same account are counted: %v", reply)
	}
	second := int64(reply["id"].(float64))

	status, reply = h.internalCall("GET", "/internal/reports", nil)
	list := reply["reports"].([]any)
	if status != http.StatusOK || len(list) != 2 {
		t.Fatalf("open reports: %d %v", status, reply)
	}
	oldest := list[0].(map[string]any)
	if oldest["message"] != "texto ofensivo" || oldest["previous"].(float64) != 1 || len(oldest["context"].([]any)) != 2 {
		t.Fatalf("a report carries the message, the context and the history: %v", oldest)
	}

	// The copy of the reporter's data has the reports they made.
	request, _ := http.NewRequest("GET", h.public.URL+"/v1/me/export", nil)
	request.Header.Set("Authorization", "Bearer "+liaToken)
	response, _ := http.DefaultClient.Do(request)
	response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("export with reports: %d", response.StatusCode)
	}

	review := func(id int64, status string) (int, map[string]any) {
		return h.internalCall("POST", "/internal/reports/"+strconv.FormatInt(id, 10)+"/review", map[string]string{"status": status, "reviewer": "mod1", "note": "ok"})
	}
	if status, _ = review(first, "reopen"); status != http.StatusBadRequest {
		t.Fatalf("unknown review status: %d", status)
	}
	if status, _ = review(first, "dismissed"); status != http.StatusNoContent {
		t.Fatalf("dismiss: %d", status)
	}
	if status, _ = review(9999, "dismissed"); status != http.StatusNotFound {
		t.Fatalf("unknown report: %d", status)
	}
	if status, _ = review(second, "banned"); status != http.StatusNoContent {
		t.Fatalf("ban: %d", status)
	}
	if status, _ = h.call(h.public, "GET", "/v1/me", nil, map[string]string{"Authorization": "Bearer " + trollToken}); status != http.StatusUnauthorized {
		t.Fatalf("a ban ends the sessions: %d", status)
	}
	if status, reply = h.call(h.public, "POST", "/v1/auth/login", map[string]string{"username": "troll", "password": "senha-forte-1"}, nil); status != http.StatusForbidden || reply["error"] != codeBanned {
		t.Fatalf("a banned account cannot log in: %d %v", status, reply)
	}
	// A game server hosting the banned player hears it at the next heartbeat.
	status, reply = h.internalCall("POST", "/internal/heartbeat", map[string]any{"server": map[string]any{"id": "s1", "name": "S1", "url": "ws://x", "online": 2, "capacity": 10}, "players": []int64{lia, troll}})
	if banned := reply["banned"].([]any); status != http.StatusOK || len(banned) != 1 || int64(banned[0].(float64)) != troll {
		t.Fatalf("the heartbeat names the banned players: %d %v", status, reply)
	}
	if _, reply = h.internalCall("GET", "/internal/reports?status=banned", nil); len(reply["reports"].([]any)) != 1 {
		t.Fatalf("reviewed reports by status: %v", reply)
	}

	// Deleting the reporter keeps the report, without the name; retention after review.
	h.call(h.public, "DELETE", "/v1/me", map[string]string{"password": "senha-forte-1"}, map[string]string{"Authorization": "Bearer " + liaToken})
	var name string
	var reporter *int64
	h.store.pool.QueryRow(ctx, `SELECT reporter_name, reporter_id FROM chat_reports WHERE id = $1`, first).Scan(&name, &reporter)
	if name != "" || reporter != nil {
		t.Fatalf("the deleted reporter leaves no name: %q %v", name, reporter)
	}
	h.store.pool.Exec(ctx, `UPDATE chat_reports SET reviewed_at = now() - interval '200 days' WHERE id = $1`, first)
	if err := h.store.PurgeAudit(ctx, Retention{ReportDays: 180}); err != nil {
		t.Fatal(err)
	}
	var left int
	h.store.pool.QueryRow(ctx, `SELECT count(*) FROM chat_reports`).Scan(&left)
	if left != 1 {
		t.Fatalf("reviewed reports go after the retention period: %d left", left)
	}
}
