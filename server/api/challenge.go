package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
)

// Daily challenge (0.22). The game server re-runs the replay of a run and sends the score
// it computed itself; this API only keeps the best score of each player for each day (with
// the replay of that run) and lists the day's best.

const challengeMax = 100
const challengeReplayMax = 256 << 10

type ChallengeRow struct {
	Account  int64  `json:"account"`
	Name     string `json:"name"`
	Position int    `json:"position"`
	Score    int    `json:"score"`
	Ticks    int    `json:"ticks"`
}

// SubmitChallenge keeps `score` if it beats the stored best of the day (or none was
// stored). Returns whether it is the new best, the best score now, the position of the
// player and how many are listed.
func (s *Store) SubmitChallenge(ctx context.Context, day int, account int64, name string, score, ticks int, replay json.RawMessage) (bool, int, int, int, error) {
	var best int
	var improved bool
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var stored int
		err := tx.QueryRow(ctx, `SELECT score FROM challenge_scores WHERE day = $1 AND account_id = $2 FOR UPDATE`, day, account).Scan(&stored)
		switch {
		case errors.Is(err, pgx.ErrNoRows):
			improved = true
		case err != nil:
			return err
		default:
			improved = score > stored
		}
		if improved {
			_, err = tx.Exec(ctx, `INSERT INTO challenge_scores (day, account_id, name, score, ticks, replay) VALUES ($1, $2, $3, $4, $5, $6)
				ON CONFLICT (day, account_id) DO UPDATE SET name = EXCLUDED.name, score = EXCLUDED.score, ticks = EXCLUDED.ticks, replay = EXCLUDED.replay, created_at = now()`,
				day, account, name, score, ticks, []byte(replay))
			if err != nil {
				return err
			}
			best = score
		} else {
			best = stored
		}
		return nil
	})
	if err != nil {
		return false, 0, 0, 0, err
	}
	_, position, total, err := s.ChallengeTop(ctx, day, 1, account)
	return improved, best, position, total, err
}

// ChallengeTop returns the top `limit` of the day, the position of `account` (0 = none)
// and how many players are listed.
func (s *Store) ChallengeTop(ctx context.Context, day, limit int, account int64) ([]ChallengeRow, int, int, error) {
	rows, err := s.pool.Query(ctx, `SELECT account_id, name, score, ticks, pos FROM (
		SELECT account_id, name, score, ticks, ROW_NUMBER() OVER (ORDER BY score DESC, created_at, account_id) AS pos FROM challenge_scores WHERE day = $1) ranked
		WHERE pos <= $2 OR account_id = $3 ORDER BY pos`, day, limit, account)
	if err != nil {
		return nil, 0, 0, err
	}
	defer rows.Close()
	list := []ChallengeRow{}
	position := 0
	for rows.Next() {
		var row ChallengeRow
		if err := rows.Scan(&row.Account, &row.Name, &row.Score, &row.Ticks, &row.Position); err != nil {
			return nil, 0, 0, err
		}
		if row.Account == account {
			position = row.Position
		}
		if row.Position <= limit {
			list = append(list, row)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, 0, 0, err
	}
	var total int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM challenge_scores WHERE day = $1`, day).Scan(&total); err != nil {
		return nil, 0, 0, err
	}
	return list, position, total, nil
}

// ChallengeReplay is the replay of the best run of `account` on `day`.
func (s *Store) ChallengeReplay(ctx context.Context, day int, account int64) (json.RawMessage, error) {
	var replay []byte
	err := s.pool.QueryRow(ctx, `SELECT replay FROM challenge_scores WHERE day = $1 AND account_id = $2`, day, account).Scan(&replay)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return replay, err
}

// PurgeChallenge drops the scores older than `keep` days from the newest day listed.
func (s *Store) PurgeChallenge(ctx context.Context, keep int) error {
	if keep <= 0 {
		return nil
	}
	_, err := s.pool.Exec(ctx, `DELETE FROM challenge_scores WHERE day < (SELECT COALESCE(max(day), 0) FROM challenge_scores) - $1`, keep)
	return err
}

func (a *API) challengeRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /internal/challenge/submit", a.challengeSubmit)
	mux.HandleFunc("GET /internal/challenge/top", a.challengeTop)
	mux.HandleFunc("GET /internal/challenge/replay", a.challengeReplay)
}

// POST /internal/challenge/submit {day, account_id, name, score, ticks, replay}
func (a *API) challengeSubmit(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Day     int             `json:"day"`
		Account int64           `json:"account_id"`
		Name    string          `json:"name"`
		Score   int             `json:"score"`
		Ticks   int             `json:"ticks"`
		Replay  json.RawMessage `json:"replay"`
	}
	if err := readJSON(r, &body); err != nil || body.Day < 0 || body.Account <= 0 || body.Score < 0 || len(body.Replay) == 0 || len(body.Replay) > challengeReplayMax || !json.Valid(body.Replay) {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	improved, best, position, total, err := a.store.SubmitChallenge(r.Context(), body.Day, body.Account, body.Name, body.Score, body.Ticks, body.Replay)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"best": improved, "score": best, "position": position, "total": total})
}

// GET /internal/challenge/top?day=3&limit=50&account=12
func (a *API) challengeTop(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	day, err := strconv.Atoi(query.Get("day"))
	if err != nil || day < 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid day")
		return
	}
	limit, err := strconv.Atoi(query.Get("limit"))
	if err != nil || limit < 1 || limit > challengeMax {
		limit = 50
	}
	account, _ := strconv.ParseInt(query.Get("account"), 10, 64)
	rows, position, total, err := a.store.ChallengeTop(r.Context(), day, limit, account)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"day": day, "rows": rows, "position": position, "total": total})
}

// GET /internal/challenge/replay?day=3&account=12
func (a *API) challengeReplay(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	day, err := strconv.Atoi(query.Get("day"))
	account, err2 := strconv.ParseInt(query.Get("account"), 10, 64)
	if err != nil || err2 != nil || day < 0 || account <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid query")
		return
	}
	replay, err := a.store.ChallengeReplay(r.Context(), day, account)
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, codeNotFound, "no replay")
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"replay": replay})
}
