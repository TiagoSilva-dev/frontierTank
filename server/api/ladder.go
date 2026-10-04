package main

import (
	"context"
	"net/http"
	"strconv"
)

// Ranked ladder (0.22). The rating (season, mmr, games, wins, losses) lives inside the
// profile JSON, written only by the game server after a ranked match, so the board is a
// query over `profiles`: no second copy that could disagree. Only characters that played
// at least one ranked game of the season are listed.

const ladderMax = 100

type LadderRow struct {
	Account  int64  `json:"account"`
	Name     string `json:"name"`
	Position int    `json:"position"`
	MMR      int    `json:"mmr"`
	Games    int    `json:"games"`
	Wins     int    `json:"wins"`
	Losses   int    `json:"losses"`
}

// ladderRated lists the profiles with a rating of `season` and at least one game, ranked
// by rating, then wins, then account (stable).
const ladderRated = `
	SELECT account_id, COALESCE(name, '') AS name,
		(data #>> '{rating,mmr}')::int AS mmr,
		(data #>> '{rating,games}')::int AS games,
		COALESCE((data #>> '{rating,wins}')::int, 0) AS wins,
		COALESCE((data #>> '{rating,losses}')::int, 0) AS losses
	FROM profiles
	WHERE (data #>> '{rating,season}') ~ '^[0-9]+$' AND (data #>> '{rating,season}')::int = $1
		AND (data #>> '{rating,games}') ~ '^[0-9]+$' AND (data #>> '{rating,games}')::int > 0
		AND (data #>> '{rating,mmr}') ~ '^[0-9]+$'`

// Ladder returns the top `limit` rows of the season, the position of `account` (0 when
// it is not listed) and how many characters are listed.
func (s *Store) Ladder(ctx context.Context, season, limit int, account int64) ([]LadderRow, int, int, error) {
	rows, err := s.pool.Query(ctx, `SELECT account_id, name, mmr, games, wins, losses, pos FROM (
		SELECT *, ROW_NUMBER() OVER (ORDER BY mmr DESC, wins DESC, account_id) AS pos FROM (`+ladderRated+`) rated) ranked
		WHERE pos <= $2 OR account_id = $3 ORDER BY pos`, season, limit, account)
	if err != nil {
		return nil, 0, 0, err
	}
	defer rows.Close()
	list := []LadderRow{}
	position := 0
	for rows.Next() {
		var row LadderRow
		if err := rows.Scan(&row.Account, &row.Name, &row.MMR, &row.Games, &row.Wins, &row.Losses, &row.Position); err != nil {
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
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM (`+ladderRated+`) rated`, season).Scan(&total); err != nil {
		return nil, 0, 0, err
	}
	return list, position, total, nil
}

func (a *API) ladderRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /internal/ladder", a.ladder)
}

// GET /internal/ladder?season=1&limit=50&account=12
func (a *API) ladder(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	season, err := strconv.Atoi(query.Get("season"))
	if err != nil || season < 1 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid season")
		return
	}
	limit, err := strconv.Atoi(query.Get("limit"))
	if err != nil || limit < 1 || limit > ladderMax {
		limit = 50
	}
	account, _ := strconv.ParseInt(query.Get("account"), 10, 64)
	rows, position, total, err := a.store.Ladder(r.Context(), season, limit, account)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"season": season, "rows": rows, "position": position, "total": total})
}
