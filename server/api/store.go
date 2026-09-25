package main

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

var (
	ErrNotFound        = errors.New("not found")
	ErrTaken           = errors.New("already taken")
	ErrNameTaken       = errors.New("name taken")
	ErrConflict        = errors.New("version conflict")
	ErrOtherServer     = errors.New("online on another server")
	errUniqueViolation = "23505"
)

type Account struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	Banned   bool   `json:"banned,omitempty"`
}

type Profile struct {
	Name    *string         `json:"name"`
	Data    json.RawMessage `json:"data"`
	Version int64           `json:"version"`
}

type GameServer struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	URL      string `json:"url"`
	Online   int    `json:"online"`
	Capacity int    `json:"capacity"`
}

type AuditEntry struct {
	AccountID *int64          `json:"account_id"`
	Kind      string          `json:"kind"`
	Detail    json.RawMessage `json:"detail"`
}

type Store struct {
	pool *pgxpool.Pool
}

func openStore(ctx context.Context, url string) (*Store, error) {
	var pool *pgxpool.Pool
	var err error
	// The database may still be starting (docker compose): retry for a while.
	for attempt := 0; attempt < 30; attempt++ {
		pool, err = pgxpool.New(ctx, url)
		if err == nil {
			if err = pool.Ping(ctx); err == nil {
				return &Store{pool: pool}, nil
			}
			pool.Close()
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Second):
		}
	}
	return nil, fmt.Errorf("database: %w", err)
}

func (s *Store) Close() { s.pool.Close() }

// migrate applies migrations/*.sql in name order, once each.
func (s *Store) migrate(ctx context.Context) error {
	if _, err := s.pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`); err != nil {
		return err
	}
	names, err := fs.Glob(migrationFiles, "migrations/*.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)
	for _, name := range names {
		var done bool
		if err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE name = $1)`, name).Scan(&done); err != nil {
			return err
		}
		if done {
			continue
		}
		sql, err := migrationFiles.ReadFile(name)
		if err != nil {
			return err
		}
		err = pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
			if _, err := tx.Exec(ctx, string(sql)); err != nil {
				return err
			}
			_, err := tx.Exec(ctx, `INSERT INTO schema_migrations (name) VALUES ($1)`, name)
			return err
		})
		if err != nil {
			return fmt.Errorf("migration %s: %w", name, err)
		}
	}
	return nil
}

func isUnique(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == errUniqueViolation
}

func (s *Store) CreateAccount(ctx context.Context, username, hash string) (Account, error) {
	account := Account{Username: username}
	err := s.pool.QueryRow(ctx, `INSERT INTO accounts (username, password_hash, last_login) VALUES ($1, $2, now()) RETURNING id`, username, hash).Scan(&account.ID)
	if isUnique(err) {
		return account, ErrTaken
	}
	return account, err
}

func (s *Store) AccountByUsername(ctx context.Context, username string) (Account, string, error) {
	var account Account
	var hash string
	err := s.pool.QueryRow(ctx, `SELECT id, username, password_hash, banned FROM accounts WHERE lower(username) = lower($1)`, username).Scan(&account.ID, &account.Username, &hash, &account.Banned)
	if errors.Is(err, pgx.ErrNoRows) {
		return account, "", ErrNotFound
	}
	return account, hash, err
}

func (s *Store) AccountPasswordHash(ctx context.Context, id int64) (string, error) {
	var hash string
	err := s.pool.QueryRow(ctx, `SELECT password_hash FROM accounts WHERE id = $1`, id).Scan(&hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return hash, err
}

func (s *Store) UpdatePassword(ctx context.Context, id int64, hash string) error {
	_, err := s.pool.Exec(ctx, `UPDATE accounts SET password_hash = $2 WHERE id = $1`, id, hash)
	return err
}

func (s *Store) TouchLogin(ctx context.Context, id int64) error {
	_, err := s.pool.Exec(ctx, `UPDATE accounts SET last_login = now() WHERE id = $1`, id)
	return err
}

func (s *Store) DeleteAccount(ctx context.Context, id int64) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM accounts WHERE id = $1`, id)
	return err
}

func (s *Store) CreateSession(ctx context.Context, accountID int64, tokenHash []byte, expires time.Time) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO sessions (token_hash, account_id, expires_at) VALUES ($1, $2, $3)`, tokenHash, accountID, expires)
	return err
}

func (s *Store) SessionAccount(ctx context.Context, tokenHash []byte) (Account, error) {
	var account Account
	err := s.pool.QueryRow(ctx, `SELECT a.id, a.username, a.banned FROM sessions s JOIN accounts a ON a.id = s.account_id WHERE s.token_hash = $1 AND s.expires_at > now()`, tokenHash).Scan(&account.ID, &account.Username, &account.Banned)
	if errors.Is(err, pgx.ErrNoRows) {
		return account, ErrNotFound
	}
	return account, err
}

func (s *Store) DeleteSession(ctx context.Context, tokenHash []byte) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM sessions WHERE token_hash = $1`, tokenHash)
	return err
}

func (s *Store) PurgeExpired(ctx context.Context) error {
	if _, err := s.pool.Exec(ctx, `DELETE FROM sessions WHERE expires_at < now()`); err != nil {
		return err
	}
	_, err := s.pool.Exec(ctx, `DELETE FROM presence WHERE expires_at < now()`)
	return err
}

func (s *Store) Profile(ctx context.Context, accountID int64) (Profile, error) {
	var profile Profile
	err := s.pool.QueryRow(ctx, `SELECT name, data, version FROM profiles WHERE account_id = $1`, accountID).Scan(&profile.Name, &profile.Data, &profile.Version)
	if errors.Is(err, pgx.ErrNoRows) {
		return profile, ErrNotFound
	}
	return profile, err
}

// SaveProfile writes a profile if the stored version is still `expected` (0 = the
// profile does not exist yet) and returns the new version.
func (s *Store) SaveProfile(ctx context.Context, accountID int64, name *string, data json.RawMessage, expected int64) (int64, error) {
	var version int64
	var err error
	if expected == 0 {
		err = s.pool.QueryRow(ctx, `INSERT INTO profiles (account_id, name, data, version) VALUES ($1, $2, $3, 1) ON CONFLICT (account_id) DO NOTHING RETURNING version`, accountID, name, data).Scan(&version)
	} else {
		err = s.pool.QueryRow(ctx, `UPDATE profiles SET name = $2, data = $3, version = version + 1, updated_at = now() WHERE account_id = $1 AND version = $4 RETURNING version`, accountID, name, data, expected).Scan(&version)
	}
	if isUnique(err) {
		return 0, ErrNameTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrConflict
	}
	return version, err
}

func (s *Store) NameTaken(ctx context.Context, name string, accountID int64) (bool, error) {
	var taken bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM profiles WHERE lower(name) = lower($1) AND account_id <> $2)`, name, accountID).Scan(&taken)
	return taken, err
}

func (s *Store) AddAudit(ctx context.Context, serverID string, entries []AuditEntry) error {
	if len(entries) == 0 {
		return nil
	}
	batch := &pgx.Batch{}
	for _, entry := range entries {
		detail := entry.Detail
		if len(detail) == 0 {
			detail = json.RawMessage("{}")
		}
		batch.Queue(`INSERT INTO audit_log (account_id, server_id, kind, detail) VALUES ($1, $2, $3, $4)`, entry.AccountID, serverID, entry.Kind, detail)
	}
	return s.pool.SendBatch(ctx, batch).Close()
}

// Heartbeat records a game server and renews the presence of its players.
func (s *Store) Heartbeat(ctx context.Context, server GameServer, players []int64) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `INSERT INTO game_servers (id, name, url, online, capacity, updated_at) VALUES ($1, $2, $3, $4, $5, now())
			ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, url = EXCLUDED.url, online = EXCLUDED.online, capacity = EXCLUDED.capacity, updated_at = now()`,
			server.ID, server.Name, server.URL, server.Online, server.Capacity)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE presence SET expires_at = now() + interval '90 seconds' WHERE server_id = $1 AND account_id = ANY($2)`, server.ID, players)
		return err
	})
}

func (s *Store) Servers(ctx context.Context, maxAge time.Duration) ([]GameServer, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, name, url, online, capacity FROM game_servers WHERE updated_at > now() - make_interval(secs => $1) ORDER BY id`, maxAge.Seconds())
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (GameServer, error) {
		var server GameServer
		err := row.Scan(&server.ID, &server.Name, &server.URL, &server.Online, &server.Capacity)
		return server, err
	})
}

// ClaimPresence reserves the account for one game server. Another live server keeps
// it (ErrOtherServer, with that server's id); an expired reservation is taken over.
func (s *Store) ClaimPresence(ctx context.Context, accountID int64, serverID string) (string, error) {
	var holder string
	err := s.pool.QueryRow(ctx, `INSERT INTO presence (account_id, server_id, expires_at) VALUES ($1, $2, now() + interval '90 seconds')
		ON CONFLICT (account_id) DO UPDATE SET server_id = EXCLUDED.server_id, expires_at = EXCLUDED.expires_at
		WHERE presence.server_id = EXCLUDED.server_id OR presence.expires_at < now()
		RETURNING server_id`, accountID, serverID).Scan(&holder)
	if errors.Is(err, pgx.ErrNoRows) {
		err = s.pool.QueryRow(ctx, `SELECT server_id FROM presence WHERE account_id = $1`, accountID).Scan(&holder)
		if err != nil {
			return "", err
		}
		return holder, ErrOtherServer
	}
	return holder, err
}

func (s *Store) ReleasePresence(ctx context.Context, accountID int64, serverID string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM presence WHERE account_id = $1 AND server_id = $2`, accountID, serverID)
	return err
}

func normalizeName(name string) string {
	return strings.TrimSpace(name)
}
