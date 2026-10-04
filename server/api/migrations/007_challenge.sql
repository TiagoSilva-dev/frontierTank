-- Daily challenge (0.22): the best verified score of each player for each day. The game
-- server re-runs the player's replay before it sends a score here, and keeps the replay of
-- the best run so the best runs of the day can be watched.
CREATE TABLE challenge_scores (
	day INT NOT NULL,
	account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
	name TEXT NOT NULL DEFAULT '',
	score INT NOT NULL CHECK (score >= 0),
	ticks INT NOT NULL DEFAULT 0,
	replay JSONB NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	PRIMARY KEY (day, account_id)
);
CREATE INDEX challenge_scores_rank ON challenge_scores (day, score DESC, created_at);
