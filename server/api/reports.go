package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Chat reports (launch checklist). The game server checks the report (the message
// exists, it is not the reporter's own, limits per player) and sends it with the lines
// around it; the team reviews them on the internal port (tools/moderate.py): dismiss,
// warn or ban. A ban uses accounts.banned (login and game servers refuse the account)
// and ends its sessions.

var reportReasons = map[string]bool{"ofensa": true, "odio": true, "spam": true, "golpe": true, "dados": true, "nome": true, "outro": true}

type ChatReport struct {
	ID           int64           `json:"id"`
	ServerID     string          `json:"server_id"`
	ReporterID   *int64          `json:"reporter_id"`
	ReporterName string          `json:"reporter_name"`
	ReportedID   *int64          `json:"reported_id"`
	ReportedName string          `json:"reported_name"`
	Reason       string          `json:"reason"`
	Note         string          `json:"note"`
	Message      string          `json:"message"`
	Context      json.RawMessage `json:"context"`
	AutoMuted    bool            `json:"auto_muted"`
	Status       string          `json:"status"`
	Reviewer     string          `json:"reviewer"`
	ReviewNote   string          `json:"review_note"`
	CreatedAt    time.Time       `json:"created_at"`
	ReviewedAt   *time.Time      `json:"reviewed_at"`
	// Other reports against the same account in the last 30 days (for the reviewer).
	Previous int `json:"previous"`
}

func (a *API) reportRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /internal/reports", a.createReport)
	mux.HandleFunc("GET /internal/reports", a.listReports)
	mux.HandleFunc("POST /internal/reports/{id}/review", a.reviewReport)
}

func init() {
	// The player's copy of their data has the reports they made (not the ones about
	// them: those carry other players' data).
	extraExports = append(extraExports, struct{ key, sql string }{"chat_reports_made", `SELECT COALESCE(json_agg(json_build_object('reported_name', reported_name, 'reason', reason, 'note', note, 'message', message, 'status', status, 'created_at', created_at) ORDER BY created_at DESC), '[]'::json) FROM chat_reports WHERE reporter_id = $1`})
}

func (a *API) createReport(w http.ResponseWriter, r *http.Request) {
	var body ChatReport
	if err := readJSON(r, &body); err != nil || body.ReporterID == nil || body.ReportedID == nil || !reportReasons[body.Reason] || strings.TrimSpace(body.Message) == "" {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid report")
		return
	}
	if len(body.Context) == 0 || !json.Valid(body.Context) {
		body.Context = json.RawMessage("[]")
	}
	body.Note = truncate(body.Note, 200)
	body.Message = truncate(body.Message, 200)
	id, recent, err := a.store.CreateReport(r.Context(), body)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "recent": recent})
}

func (a *API) listReports(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "open"
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	reports, err := a.store.Reports(r.Context(), status, limit)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"reports": reports})
}

func (a *API) reviewReport(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Status   string `json:"status"`
		Reviewer string `json:"reviewer"`
		Note     string `json:"note"`
	}
	if err := readJSON(r, &body); err != nil || !(body.Status == "dismissed" || body.Status == "warned" || body.Status == "banned") || strings.TrimSpace(body.Reviewer) == "" {
		writeError(w, http.StatusBadRequest, codeBadRequest, "status: dismissed, warned or banned; reviewer required")
		return
	}
	err := a.store.ReviewReport(r.Context(), id, body.Status, truncate(body.Reviewer, 64), truncate(body.Note, 500))
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, codeNotFound, "no such report")
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	a.log.Info("chat report reviewed", "id", id, "status", body.Status, "reviewer", body.Reviewer)
	w.WriteHeader(http.StatusNoContent)
}

func truncate(text string, limit int) string {
	runes := []rune(strings.TrimSpace(text))
	if len(runes) > limit {
		runes = runes[:limit]
	}
	return string(runes)
}

// ---------- store ----------

// CreateReport stores a report and says how many open reports the reported account got
// in the last 24 hours (this one included).
func (s *Store) CreateReport(ctx context.Context, report ChatReport) (int64, int, error) {
	var id int64
	var recent int
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		// Accounts deleted meanwhile are kept as no account (the report still counts).
		err := tx.QueryRow(ctx, `INSERT INTO chat_reports (server_id, reporter_id, reporter_name, reported_id, reported_name, reason, note, message, context, auto_muted)
			VALUES ($1, (SELECT id FROM accounts WHERE id = $2), $3, (SELECT id FROM accounts WHERE id = $4), $5, $6, $7, $8, $9, $10) RETURNING id`,
			report.ServerID, report.ReporterID, report.ReporterName, report.ReportedID, report.ReportedName, report.Reason, report.Note, report.Message, report.Context, report.AutoMuted).Scan(&id)
		if err != nil {
			return err
		}
		return tx.QueryRow(ctx, `SELECT count(*) FROM chat_reports WHERE reported_id = $1 AND status = 'open' AND created_at > now() - interval '24 hours'`, report.ReportedID).Scan(&recent)
	})
	return id, recent, err
}

func (s *Store) Reports(ctx context.Context, status string, limit int) ([]ChatReport, error) {
	rows, err := s.pool.Query(ctx, `SELECT r.id, r.server_id, r.reporter_id, r.reporter_name, r.reported_id, r.reported_name, r.reason, r.note, r.message, r.context, r.auto_muted, r.status, r.reviewer, r.review_note, r.created_at, r.reviewed_at,
			(SELECT count(*) FROM chat_reports o WHERE o.reported_id = r.reported_id AND o.id <> r.id AND o.created_at > now() - interval '30 days')
		FROM chat_reports r WHERE r.status = $1 ORDER BY r.created_at LIMIT $2`, status, limit)
	if err != nil {
		return nil, err
	}
	reports, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (ChatReport, error) {
		var report ChatReport
		err := row.Scan(&report.ID, &report.ServerID, &report.ReporterID, &report.ReporterName, &report.ReportedID, &report.ReportedName, &report.Reason, &report.Note, &report.Message, &report.Context, &report.AutoMuted, &report.Status, &report.Reviewer, &report.ReviewNote, &report.CreatedAt, &report.ReviewedAt, &report.Previous)
		return report, err
	})
	if reports == nil {
		reports = []ChatReport{}
	}
	return reports, err
}

// ReviewReport closes a report; "banned" also suspends the reported account and ends
// its sessions (the game server refuses it from the next login).
func (s *Store) ReviewReport(ctx context.Context, id int64, status, reviewer, note string) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var reported *int64
		err := tx.QueryRow(ctx, `UPDATE chat_reports SET status = $2, reviewer = $3, review_note = $4, reviewed_at = now() WHERE id = $1 RETURNING reported_id`, id, status, reviewer, note).Scan(&reported)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil || status != "banned" || reported == nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE accounts SET banned = true WHERE id = $1`, *reported); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `DELETE FROM sessions WHERE account_id = $1`, *reported)
		return err
	})
}

// PurgeReports removes reviewed reports after the retention period (Privacy Policy).
func (s *Store) PurgeReports(ctx context.Context, days int) error {
	if days <= 0 {
		return nil
	}
	_, err := s.pool.Exec(ctx, `DELETE FROM chat_reports WHERE status <> 'open' AND reviewed_at < now() - make_interval(days => $1)`, days)
	return err
}
