package main

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ErrDuplicate: a request id the panel already used (a double click or a retry).
var ErrDuplicate = errors.New("duplicate request")

// AdminUser is a staff account (never a player).
type AdminUser struct {
	ID          int64      `json:"id"`
	Username    string     `json:"username"`
	Role        string     `json:"role"`
	TOTPEnabled bool       `json:"totp_enabled"`
	Active      bool       `json:"active"`
	MustChange  bool       `json:"must_change_password"`
	Locked      bool       `json:"locked"`
	CreatedBy   string     `json:"created_by"`
	CreatedAt   time.Time  `json:"created_at"`
	LastLogin   *time.Time `json:"last_login"`
}

// adminLogin is what the login needs to decide.
type adminLogin struct {
	AdminUser
	Hash     string
	Secret   string
	LastStep int64
}

type adminSession struct {
	AdminID     int64
	Username    string
	Role        string
	Stage       string
	CSRF        string
	MustChange  bool
	TOTPEnabled bool
	IP          string
}

// adminEntry is one line of admin_audit.
type adminEntry struct {
	Action     string
	TargetType string
	TargetID   string
	AccountID  *int64
	Reason     string
	Detail     map[string]any
	RequestID  string
}

const adminUserColumns = `id, username, role, totp_enabled, active, must_change_password, locked_until IS NOT NULL AND locked_until > now(), created_by, created_at, last_login`

func scanAdminUser(row pgx.Row, extra ...any) (AdminUser, error) {
	var user AdminUser
	err := row.Scan(append([]any{&user.ID, &user.Username, &user.Role, &user.TOTPEnabled, &user.Active, &user.MustChange, &user.Locked, &user.CreatedBy, &user.CreatedAt, &user.LastLogin}, extra...)...)
	if errors.Is(err, pgx.ErrNoRows) {
		return user, ErrNotFound
	}
	return user, err
}

func (s *Store) AdminCount(ctx context.Context) (int, error) {
	var count int
	err := s.pool.QueryRow(ctx, `SELECT count(*) FROM admin_users`).Scan(&count)
	return count, err
}

func (s *Store) CreateAdmin(ctx context.Context, username, hash, role, createdBy string, mustChange bool) (int64, error) {
	var id int64
	err := s.pool.QueryRow(ctx, `INSERT INTO admin_users (username, password_hash, role, created_by, must_change_password) VALUES ($1, $2, $3, $4, $5) RETURNING id`, username, hash, role, createdBy, mustChange).Scan(&id)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == errUniqueViolation {
		return 0, ErrTaken
	}
	return id, err
}

// BootstrapAdmin creates the first owner, only if there is no staff account at all.
func (s *Store) BootstrapAdmin(ctx context.Context, username, hash string) (bool, error) {
	tag, err := s.pool.Exec(ctx, `INSERT INTO admin_users (username, password_hash, role, created_by, must_change_password)
		SELECT $1, $2, 'owner', 'bootstrap', true WHERE NOT EXISTS (SELECT 1 FROM admin_users)`, username, hash)
	return tag.RowsAffected() == 1, err
}

func (s *Store) AdminForLogin(ctx context.Context, username string) (adminLogin, error) {
	var login adminLogin
	user, err := scanAdminUser(s.pool.QueryRow(ctx, `SELECT `+adminUserColumns+`, password_hash, totp_secret, totp_last_step FROM admin_users WHERE lower(username) = lower($1)`, username), &login.Hash, &login.Secret, &login.LastStep)
	login.AdminUser = user
	return login, err
}

func (s *Store) AdminByID(ctx context.Context, id int64) (AdminUser, error) {
	return scanAdminUser(s.pool.QueryRow(ctx, `SELECT `+adminUserColumns+` FROM admin_users WHERE id = $1`, id))
}

// AdminLoginFailed counts a wrong password or code: five in a row lock the account for 15
// minutes.
func (s *Store) AdminLoginFailed(ctx context.Context, id int64) error {
	_, err := s.pool.Exec(ctx, `UPDATE admin_users SET
		locked_until = CASE WHEN failed_logins + 1 >= 5 THEN now() + interval '15 minutes' ELSE locked_until END,
		failed_logins = CASE WHEN failed_logins + 1 >= 5 THEN 0 ELSE failed_logins + 1 END WHERE id = $1`, id)
	return err
}

func (s *Store) AdminLoginOK(ctx context.Context, id, step int64) error {
	_, err := s.pool.Exec(ctx, `UPDATE admin_users SET failed_logins = 0, locked_until = NULL, last_login = now(), totp_last_step = GREATEST(totp_last_step, $2) WHERE id = $1`, id, step)
	return err
}

func (s *Store) CreateAdminSession(ctx context.Context, adminID int64, tokenHash []byte, csrf, stage, ip string, ttl time.Duration) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO admin_sessions (token_hash, admin_id, csrf, stage, ip, expires_at) VALUES ($1, $2, $3, $4, $5, now() + make_interval(secs => $6))`,
		tokenHash, adminID, csrf, stage, ip, ttl.Seconds())
	return err
}

// AdminSessionFor finds a live session: not expired, not idle too long, and the staff
// account still active.
func (s *Store) AdminSessionFor(ctx context.Context, tokenHash []byte, idle time.Duration) (adminSession, error) {
	var session adminSession
	err := s.pool.QueryRow(ctx, `SELECT u.id, u.username, u.role, s.stage, s.csrf, u.must_change_password, u.totp_enabled, s.ip
		FROM admin_sessions s JOIN admin_users u ON u.id = s.admin_id
		WHERE s.token_hash = $1 AND s.expires_at > now() AND u.active AND s.last_seen > now() - make_interval(secs => $2)`, tokenHash, idle.Seconds()).
		Scan(&session.AdminID, &session.Username, &session.Role, &session.Stage, &session.CSRF, &session.MustChange, &session.TOTPEnabled, &session.IP)
	if errors.Is(err, pgx.ErrNoRows) {
		return session, ErrNotFound
	}
	if err == nil {
		// Once a minute is enough to keep "idle" honest without a write per request.
		_, _ = s.pool.Exec(ctx, `UPDATE admin_sessions SET last_seen = now() WHERE token_hash = $1 AND last_seen < now() - interval '1 minute'`, tokenHash)
	}
	return session, err
}

func (s *Store) DeleteAdminSession(ctx context.Context, tokenHash []byte) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM admin_sessions WHERE token_hash = $1`, tokenHash)
	return err
}

// RevokeAdminSessions ends every session of the account except `keep` (nil = none).
func (s *Store) RevokeAdminSessions(ctx context.Context, adminID int64, keep []byte) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM admin_sessions WHERE admin_id = $1 AND ($2::bytea IS NULL OR token_hash <> $2)`, adminID, keep)
	return err
}

func (s *Store) PromoteAdminSession(ctx context.Context, tokenHash []byte) error {
	_, err := s.pool.Exec(ctx, `UPDATE admin_sessions SET stage = 'full' WHERE token_hash = $1`, tokenHash)
	return err
}

func (s *Store) AdminHash(ctx context.Context, id int64) (string, error) {
	var hash string
	err := s.pool.QueryRow(ctx, `SELECT password_hash FROM admin_users WHERE id = $1`, id).Scan(&hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return hash, err
}

func (s *Store) AdminSetPassword(ctx context.Context, id int64, hash string, mustChange bool) error {
	_, err := s.pool.Exec(ctx, `UPDATE admin_users SET password_hash = $2, must_change_password = $3, failed_logins = 0, locked_until = NULL WHERE id = $1`, id, hash, mustChange)
	return err
}

// AdminSetTOTP stores a new (not yet confirmed) secret.
func (s *Store) AdminSetTOTP(ctx context.Context, id int64, sealed string) error {
	_, err := s.pool.Exec(ctx, `UPDATE admin_users SET totp_secret = $2, totp_enabled = false, totp_last_step = 0 WHERE id = $1`, id, sealed)
	return err
}

func (s *Store) AdminTOTP(ctx context.Context, id int64) (sealed string, enabled bool, last int64, err error) {
	err = s.pool.QueryRow(ctx, `SELECT totp_secret, totp_enabled, totp_last_step FROM admin_users WHERE id = $1`, id).Scan(&sealed, &enabled, &last)
	return
}

func (s *Store) AdminEnableTOTP(ctx context.Context, id, step int64) error {
	_, err := s.pool.Exec(ctx, `UPDATE admin_users SET totp_enabled = true, totp_last_step = $2 WHERE id = $1 AND totp_secret <> ''`, id, step)
	return err
}

// adminDo runs one staff action: it writes the audit line and the effect in a single
// transaction, so nothing happens without a record and nothing is recorded without
// happening. A repeated request id fails with ErrDuplicate before any effect. `effect` may
// return extra detail (counts, ids) that is added to the audit line.
func (s *Store) adminDo(ctx context.Context, session *adminSession, entry adminEntry, effect func(tx pgx.Tx) (map[string]any, error)) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		detail := entry.Detail
		if detail == nil {
			detail = map[string]any{}
		}
		var request any
		if entry.RequestID != "" {
			request = entry.RequestID
		}
		var id int64
		err := tx.QueryRow(ctx, `INSERT INTO admin_audit (admin_id, admin_name, action, target_type, target_id, account_id, reason, detail, request_id, ip)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) ON CONFLICT (request_id) WHERE request_id IS NOT NULL DO NOTHING RETURNING id`,
			session.AdminID, session.Username, entry.Action, entry.TargetType, entry.TargetID, entry.AccountID, entry.Reason, detail, request, session.IP).Scan(&id)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrDuplicate
		}
		if err != nil {
			return err
		}
		if effect == nil {
			return nil
		}
		extra, err := effect(tx)
		if err != nil {
			return err
		}
		if len(extra) == 0 {
			return nil
		}
		_, err = tx.Exec(ctx, `UPDATE admin_audit SET detail = detail || $2 WHERE id = $1`, id, extra)
		return err
	})
}

// jsonRows runs a query and returns its rows as a JSON array (Postgres builds the JSON, so
// the shapes live in the SQL).
func (s *Store) jsonRows(ctx context.Context, sql string, args ...any) (json.RawMessage, error) {
	var out json.RawMessage
	err := s.pool.QueryRow(ctx, `SELECT COALESCE(json_agg(t), '[]'::json) FROM (`+sql+`) t`, args...).Scan(&out)
	return out, err
}

// jsonOne returns the first row of a query as a JSON object (null when there is none).
func (s *Store) jsonOne(ctx context.Context, sql string, args ...any) (json.RawMessage, error) {
	var out json.RawMessage
	err := s.pool.QueryRow(ctx, `SELECT COALESCE((SELECT row_to_json(t) FROM (`+sql+`) t LIMIT 1), 'null'::json)`, args...).Scan(&out)
	return out, err
}

// likePattern turns text into a contains pattern for ILIKE, escaping % _ and \.
func likePattern(text string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return "%" + replacer.Replace(text) + "%"
}

// PurgeAdmin drops expired sessions and, after the retention period, old staff records.
func (s *Store) PurgeAdmin(ctx context.Context, auditDays int) error {
	if _, err := s.pool.Exec(ctx, `DELETE FROM admin_sessions WHERE expires_at < now()`); err != nil {
		return err
	}
	if auditDays > 0 {
		if _, err := s.pool.Exec(ctx, `DELETE FROM admin_audit WHERE created_at < now() - make_interval(days => $1)`, auditDays); err != nil {
			return err
		}
	}
	return nil
}

// ExpireBans lifts the bans whose time is over and records it.
func (s *Store) ExpireBans(ctx context.Context) (int, error) {
	var count int
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `UPDATE accounts SET banned = false, ban_until = NULL WHERE banned AND ban_until IS NOT NULL AND ban_until <= now() RETURNING id`)
		if err != nil {
			return err
		}
		ids, err := pgx.CollectRows(rows, pgx.RowTo[int64])
		if err != nil {
			return err
		}
		count = len(ids)
		for _, id := range ids {
			if _, err := tx.Exec(ctx, `INSERT INTO admin_audit (admin_name, action, target_type, target_id, account_id, reason) VALUES ('sistema', 'player.unban', 'account', $1, $2, 'banimento com prazo terminou')`, strconv.FormatInt(id, 10), id); err != nil {
				return err
			}
		}
		return nil
	})
	return count, err
}
