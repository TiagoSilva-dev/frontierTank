package main

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The read side of the panel: dashboard, economy, players, reports, payments, auction,
// audit, servers and system. Postgres builds the JSON (Store.jsonRows / jsonOne), so each
// page is one query or a handful.

type adminRouter func(pattern string, role int, handler adminHandler)

func (a *API) adminDataRoutes(api adminRouter) {
	api("GET /admin/api/overview", roleViewer, a.adminOverview)
	api("GET /admin/api/economy", roleViewer, a.adminEconomy)
	api("GET /admin/api/economy/top", roleViewer, a.adminTopHolders)
	api("GET /admin/api/servers", roleViewer, a.adminServers)
	api("GET /admin/api/catalog", roleViewer, a.adminCatalogRoute)
	api("GET /admin/api/players", roleSupport, a.adminPlayers)
	api("GET /admin/api/players/{id}", roleSupport, a.adminPlayer)
	api("GET /admin/api/reports", roleSupport, a.adminReports)
	api("GET /admin/api/orders", roleSupport, a.adminOrders)
	api("GET /admin/api/auction", roleSupport, a.adminAuction)
	api("GET /admin/api/audit", roleSupport, a.adminAudit)
	api("GET /admin/api/audit/kinds", roleSupport, a.adminAuditKinds)
	api("GET /admin/api/audit.csv", roleAdmin, a.adminAuditCSV)
	api("GET /admin/api/staff-actions", roleAdmin, a.adminStaffActions)
	api("GET /admin/api/system", roleOwner, a.adminSystem)
}

// ---------- helpers ----------

func (a *API) adminReply(w http.ResponseWriter, data json.RawMessage, err error) {
	if err != nil {
		a.fail(w, err)
		return
	}
	writeRaw(w, data)
}

func pageParams(r *http.Request, max int) (limit, offset int) {
	limit, _ = strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > max {
		limit = 50
	}
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 0 || page > 100000 {
		page = 0
	}
	return limit, page * limit
}

func queryInt(r *http.Request, name string) (int64, bool) {
	value, err := strconv.ParseInt(r.URL.Query().Get(name), 10, 64)
	return value, err == nil && value > 0
}

// queryTime reads a date ("2026-10-06") or a time (RFC 3339).
func queryTime(r *http.Request, name string) (time.Time, bool) {
	text := r.URL.Query().Get(name)
	for _, layout := range []string{time.RFC3339, "2006-01-02"} {
		if value, err := time.Parse(layout, text); err == nil {
			return value, true
		}
	}
	return time.Time{}, false
}

// where builds a WHERE clause with numbered arguments.
type where struct {
	parts []string
	args  []any
}

// add appends a condition; every ? in it becomes the same numbered argument.
func (w *where) add(condition string, value any) {
	w.args = append(w.args, value)
	w.parts = append(w.parts, strings.ReplaceAll(condition, "?", "$"+strconv.Itoa(len(w.args))))
}

func (w *where) addRaw(condition string) { w.parts = append(w.parts, condition) }

func (w *where) clause() string {
	if len(w.parts) == 0 {
		return ""
	}
	return " WHERE " + strings.Join(w.parts, " AND ")
}

func (s *Store) jsonValue(ctx context.Context, sql string, args ...any) (json.RawMessage, error) {
	var out json.RawMessage
	err := s.pool.QueryRow(ctx, sql, args...).Scan(&out)
	return out, err
}

// listResult is the usual answer of a paged list.
func listResult(rows json.RawMessage, total int) json.RawMessage {
	out, _ := json.Marshal(map[string]any{"rows": rows, "total": total})
	return out
}

// number reads a counter out of a profile JSON that may hold a float or a missing key.
func profileNumber(expr string) string {
	return `CASE WHEN ` + expr + ` ~ '^[0-9]+(\.[0-9]+)?$' THEN floor((` + expr + `)::numeric) ELSE 0 END`
}

// ---------- overview ----------

type ttlCache struct {
	mu   sync.Mutex
	at   time.Time
	data json.RawMessage
}

func (c *ttlCache) get(ttl time.Duration, load func() (json.RawMessage, error)) (json.RawMessage, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.data != nil && time.Since(c.at) < ttl {
		return c.data, nil
	}
	data, err := load()
	if err == nil {
		c.data, c.at = data, time.Now()
	}
	return data, err
}

// The charts count whole days in the team's time zone, over the last 14 days.
const overviewSQL = `
WITH days AS (
	SELECT generate_series((now() AT TIME ZONE '` + adminTZ + `')::date - 13, (now() AT TIME ZONE '` + adminTZ + `')::date, interval '1 day')::date AS d
), signups AS (
	SELECT (created_at AT TIME ZONE '` + adminTZ + `')::date AS d, count(*) AS n FROM accounts WHERE created_at >= now() - interval '15 days' GROUP BY 1
), active AS (
	SELECT (created_at AT TIME ZONE '` + adminTZ + `')::date AS d, count(DISTINCT account_id) AS n FROM access_log
	WHERE created_at >= now() - interval '15 days' AND action IN ('login', 'steam_login', 'register', 'steam_register') GROUP BY 1
), matches AS (
	SELECT (created_at AT TIME ZONE '` + adminTZ + `')::date AS d, count(*) AS n FROM audit_log WHERE kind = 'match' AND created_at >= now() - interval '15 days' GROUP BY 1
), revenue AS (
	SELECT (updated_at AT TIME ZONE '` + adminTZ + `')::date AS d, currency, sum(amount)::bigint AS total FROM store_orders
	WHERE status = 'paid' AND updated_at >= now() - interval '15 days' GROUP BY 1, 2
)
SELECT json_build_object(
	'servers', (SELECT COALESCE(json_agg(json_build_object('id', id, 'name', name, 'online', online, 'capacity', capacity, 'age_seconds', extract(epoch FROM now() - updated_at)::int) ORDER BY id), '[]'::json)
		FROM game_servers WHERE updated_at > now() - interval '10 minutes'),
	'accounts', json_build_object(
		'total', (SELECT count(*) FROM accounts),
		'with_character', (SELECT count(*) FROM profiles),
		'new_24h', (SELECT count(*) FROM accounts WHERE created_at > now() - interval '24 hours'),
		'new_7d', (SELECT count(*) FROM accounts WHERE created_at > now() - interval '7 days'),
		'active_24h', (SELECT count(*) FROM accounts WHERE last_login > now() - interval '24 hours'),
		'active_7d', (SELECT count(*) FROM accounts WHERE last_login > now() - interval '7 days'),
		'active_30d', (SELECT count(*) FROM accounts WHERE last_login > now() - interval '30 days'),
		'banned', (SELECT count(*) FROM accounts WHERE banned)),
	'revenue', (SELECT COALESCE(json_agg(r ORDER BY r.currency), '[]'::json) FROM (
		SELECT currency,
			COALESCE(sum(amount) FILTER (WHERE updated_at > now() - interval '24 hours'), 0)::bigint AS d1,
			COALESCE(sum(amount) FILTER (WHERE updated_at > now() - interval '7 days'), 0)::bigint AS d7,
			COALESCE(sum(amount) FILTER (WHERE updated_at > now() - interval '30 days'), 0)::bigint AS d30,
			COALESCE(sum(amount), 0)::bigint AS total, count(*)::int AS orders
		FROM store_orders WHERE status = 'paid' GROUP BY currency) r),
	'refunds_30d', (SELECT count(*) FROM store_orders WHERE status = 'refunded' AND updated_at > now() - interval '30 days'),
	'queue', json_build_object(
		'reports_open', (SELECT count(*) FROM chat_reports WHERE status = 'open'),
		'orders_pending', (SELECT count(*) FROM store_orders WHERE status = 'init' AND created_at > now() - interval '1 hour'),
		'listings_active', (SELECT count(*) FROM auction_listings WHERE status = 'active' AND expires_at > now()),
		'mail_unclaimed', (SELECT count(*) FROM mail WHERE claimed_at IS NULL)),
	'alerts', json_build_object(
		'desync_24h', (SELECT count(*) FROM audit_log WHERE kind = 'desync' AND created_at > now() - interval '24 hours'),
		'mismatch_30d', (SELECT count(*) FROM audit_log WHERE kind = 'store.mismatch' AND created_at > now() - interval '30 days'),
		'auto_muted_24h', (SELECT count(*) FROM chat_reports WHERE auto_muted AND created_at > now() - interval '24 hours')),
	'series', (SELECT json_agg(json_build_object('day', days.d, 'signups', COALESCE(signups.n, 0), 'active', COALESCE(active.n, 0), 'matches', COALESCE(matches.n, 0),
			'revenue', COALESCE((SELECT json_object_agg(revenue.currency, revenue.total) FROM revenue WHERE revenue.d = days.d), '{}'::json)) ORDER BY days.d)
		FROM days LEFT JOIN signups ON signups.d = days.d LEFT JOIN active ON active.d = days.d LEFT JOIN matches ON matches.d = days.d),
	'generated_at', now())`

func (a *API) adminOverview(w http.ResponseWriter, r *http.Request, s *adminSession) {
	data, err := a.overviewCache.get(30*time.Second, func() (json.RawMessage, error) {
		return a.store.jsonValue(r.Context(), overviewSQL)
	})
	a.adminReply(w, data, err)
}

// ---------- economy ----------

var assetKey = regexp.MustCompile(`^[a-z0-9_]{1,40}$`)

func (a *API) adminEconomy(w http.ResponseWriter, r *http.Request, s *adminSession) {
	data, err := a.economyCache.get(60*time.Second, func() (json.RawMessage, error) {
		return a.store.jsonValue(r.Context(), `
WITH p AS (SELECT account_id, data FROM profiles)
SELECT json_build_object(
	'players', (SELECT count(*) FROM p),
	'coins', (SELECT COALESCE(sum(`+profileNumber(`data->>'coins'`)+`), 0)::bigint FROM p),
	'assets', (SELECT COALESCE(json_object_agg(key, total), '{}'::json) FROM (
		SELECT e.key, sum(floor(e.value::numeric))::bigint AS total
		FROM p, jsonb_each_text(CASE WHEN jsonb_typeof(p.data->'items') = 'object' THEN p.data->'items' ELSE '{}'::jsonb END) e
		WHERE e.value ~ '^[0-9]+(\.[0-9]+)?$' GROUP BY e.key) t),
	'auction', json_build_object(
		'active', (SELECT count(*) FROM auction_listings WHERE status = 'active' AND expires_at > now()),
		'sold_7d', (SELECT count(*) FROM auction_listings WHERE status = 'sold' AND closed_at > now() - interval '7 days'),
		'volume_solar_7d', (SELECT COALESCE(sum(price_solar), 0)::bigint FROM auction_listings WHERE status = 'sold' AND closed_at > now() - interval '7 days'),
		'volume_estrela_7d', (SELECT COALESCE(sum(price_estrela), 0)::bigint FROM auction_listings WHERE status = 'sold' AND closed_at > now() - interval '7 days'),
		'fees_solar_7d', (SELECT COALESCE(sum(fee_solar), 0)::bigint FROM auction_listings WHERE status = 'sold' AND closed_at > now() - interval '7 days'),
		'fees_estrela_7d', (SELECT COALESCE(sum(fee_estrela), 0)::bigint FROM auction_listings WHERE status = 'sold' AND closed_at > now() - interval '7 days')),
	'exchange', json_build_object(
		'active', (SELECT count(*) FROM exchange_orders WHERE status = 'active'),
		'fills_7d', (SELECT count(*) FROM audit_log WHERE kind = 'exchange.fill' AND created_at > now() - interval '7 days')),
	'generated_at', now())`)
	})
	a.adminReply(w, data, err)
}

// adminTopHolders: who holds the most of an asset ("coins" or an item counter such as
// "estrela"): the first place to look when a currency inflates.
func (a *API) adminTopHolders(w http.ResponseWriter, r *http.Request, s *adminSession) {
	asset := r.URL.Query().Get("asset")
	if asset != "coins" && !assetKey.MatchString(asset) {
		writeError(w, http.StatusBadRequest, codeBadRequest, "Moeda inválida.")
		return
	}
	expr := `p.data->>'coins'`
	args := []any{}
	if asset != "coins" {
		expr = `p.data->'items'->>$1`
		args = append(args, asset)
	}
	data, err := a.store.jsonRows(r.Context(), `SELECT a.id AS account_id, a.username, p.name AS character, a.banned, (`+profileNumber(expr)+`)::bigint AS amount
		FROM profiles p JOIN accounts a ON a.id = p.account_id ORDER BY amount DESC, a.id LIMIT 20`, args...)
	a.adminReply(w, data, err)
}

// ---------- servers ----------

func (a *API) adminServers(w http.ResponseWriter, r *http.Request, s *adminSession) {
	ctx := r.Context()
	servers, err := a.store.jsonRows(ctx, `SELECT g.id, g.name, g.url, g.online, g.capacity, extract(epoch FROM now() - g.updated_at)::int AS age_seconds,
		(SELECT count(*) FROM presence p WHERE p.server_id = g.id AND p.expires_at > now())::int AS present FROM game_servers g ORDER BY g.id`)
	if err != nil {
		a.fail(w, err)
		return
	}
	database, err := a.store.jsonOne(ctx, `SELECT now() AS now, pg_database_size(current_database())::bigint AS size_bytes, version() AS version`)
	if err != nil {
		a.fail(w, err)
		return
	}
	out, _ := json.Marshal(map[string]any{"servers": servers, "database": database, "api_started": startedAt, "internal_key_set": a.cfg.InternalKey != ""})
	writeRaw(w, out)
}

var startedAt = time.Now().UTC()

// ---------- players ----------

func (a *API) adminPlayers(w http.ResponseWriter, r *http.Request, s *adminSession) {
	query := r.URL.Query()
	limit, offset := pageParams(r, 100)
	var cond where
	if q := strings.TrimSpace(query.Get("q")); q != "" {
		if len(q) > 64 {
			q = q[:64]
		}
		_, parseErr := strconv.ParseInt(q, 10, 64)
		switch {
		case parseErr == nil:
			// The account id or the SteamID (both are numbers).
			cond.add("(a.id::text = ? OR a.steam_id = ?)", q)
		case strings.ContainsAny(q, ".:") && !strings.ContainsAny(q, " %"):
			cond.add("EXISTS (SELECT 1 FROM access_log l WHERE l.account_id = a.id AND l.ip = ?)", q)
		default:
			cond.add("(a.username ILIKE ? OR p.name ILIKE ?)", likePattern(q))
		}
	}
	switch query.Get("status") {
	case "banned":
		cond.addRaw("a.banned")
	case "online":
		cond.addRaw("pr.server_id IS NOT NULL")
	case "no_character":
		cond.addRaw("p.account_id IS NULL")
	}
	from := ` FROM accounts a LEFT JOIN profiles p ON p.account_id = a.id LEFT JOIN presence pr ON pr.account_id = a.id AND pr.expires_at > now()` + cond.clause()
	order := "a.id DESC"
	if query.Get("sort") == "login" {
		order = "a.last_login DESC NULLS LAST, a.id DESC"
	}
	ctx := r.Context()
	var total int
	if err := a.store.pool.QueryRow(ctx, `SELECT count(*)`+from, cond.args...).Scan(&total); err != nil {
		a.fail(w, err)
		return
	}
	args := append(append([]any{}, cond.args...), limit, offset)
	rows, err := a.store.jsonRows(ctx, `SELECT a.id, a.username, p.name AS character, a.created_at, a.last_login, a.banned, a.ban_reason, a.ban_until,
		(a.steam_id IS NOT NULL) AS steam, pr.server_id AS online_on,
		(`+profileNumber(`p.data->>'matches'`)+`)::bigint AS matches, (`+profileNumber(`p.data->>'experience'`)+`)::bigint AS experience`+
		from+fmt.Sprintf(` ORDER BY %s LIMIT $%d OFFSET $%d`, order, len(cond.args)+1, len(cond.args)+2), args...)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeRaw(w, listResult(rows, total))
}

func (a *API) adminPlayer(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	account, err := a.store.jsonOne(ctx, `SELECT id, username, created_at, last_login, banned, ban_reason, ban_until, banned_at, banned_by, terms_version, terms_accepted_at,
		steam_id, (password_hash = '') AS no_password FROM accounts WHERE id = $1`, id)
	if err != nil {
		a.fail(w, err)
		return
	}
	if string(account) == "null" {
		writeError(w, http.StatusNotFound, codeNotFound, "Conta não encontrada.")
		return
	}
	queries := []struct{ key, sql string }{
		{"profile", `SELECT name, version, updated_at, data FROM profiles WHERE account_id = $1`},
		{"presence", `SELECT server_id, expires_at FROM presence WHERE account_id = $1 AND expires_at > now()`},
		{"sessions", `SELECT count(*)::int AS open, max(created_at) AS last_created FROM sessions WHERE account_id = $1 AND expires_at > now()`},
	}
	out := map[string]json.RawMessage{"account": account}
	for _, query := range queries {
		if out[query.key], err = a.store.jsonOne(ctx, query.sql, id); err != nil {
			a.fail(w, err)
			return
		}
	}
	lists := []struct{ key, sql string }{
		{"access", `SELECT ip, action, created_at FROM access_log WHERE account_id = $1 ORDER BY created_at DESC LIMIT 30`},
		{"shared_ips", `SELECT a.id, a.username, a.banned, count(*)::int AS hits, max(l.created_at) AS last_seen, array_agg(DISTINCT l.ip) AS ips
			FROM access_log l JOIN accounts a ON a.id = l.account_id
			WHERE l.account_id <> $1 AND l.ip IN (SELECT ip FROM access_log WHERE account_id = $1 AND created_at > now() - interval '90 days')
			GROUP BY a.id ORDER BY hits DESC LIMIT 20`},
		{"orders", `SELECT order_id, sku, description, amount, currency, status, provider, created_at, updated_at FROM store_orders WHERE account_id = $1 ORDER BY created_at DESC LIMIT 20`},
		{"listings", `SELECT id, kind, item_id, quality, strengthen, price_solar, price_estrela, status, created_at, closed_at FROM auction_listings WHERE seller_id = $1 ORDER BY id DESC LIMIT 20`},
		{"purchases", `SELECT id, kind, item_id, quality, price_solar, price_estrela, closed_at FROM auction_listings WHERE buyer_id = $1 ORDER BY id DESC LIMIT 20`},
		{"mail", `SELECT id, kind, item_kind, coins, currencies, detail, created_at, claimed_at FROM mail WHERE account_id = $1 ORDER BY id DESC LIMIT 30`},
		{"reports_against", `SELECT id, reporter_name, reason, message, status, created_at FROM chat_reports WHERE reported_id = $1 ORDER BY created_at DESC LIMIT 20`},
		{"notes", `SELECT id, admin_name, note, created_at FROM account_notes WHERE account_id = $1 ORDER BY created_at DESC`},
		{"staff_actions", `SELECT id, admin_name, action, reason, detail, created_at FROM admin_audit WHERE account_id = $1 ORDER BY created_at DESC LIMIT 50`},
		{"activity", `SELECT id, kind, server_id, detail, created_at FROM audit_log WHERE account_id = $1 ORDER BY id DESC LIMIT 40`},
	}
	for _, query := range lists {
		if out[query.key], err = a.store.jsonRows(ctx, query.sql, id); err != nil {
			a.fail(w, err)
			return
		}
	}
	reportsMade, err := a.store.jsonOne(ctx, `SELECT count(*)::int AS made FROM chat_reports WHERE reporter_id = $1`, id)
	if err != nil {
		a.fail(w, err)
		return
	}
	out["reports_made"] = reportsMade
	data, _ := json.Marshal(out)
	writeRaw(w, data)
}

// ---------- reports ----------

func (a *API) adminReports(w http.ResponseWriter, r *http.Request, s *adminSession) {
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "open"
	}
	if status != "all" && status != "open" && status != "dismissed" && status != "warned" && status != "banned" {
		writeError(w, http.StatusBadRequest, codeBadRequest, "Situação inválida.")
		return
	}
	limit, offset := pageParams(r, 100)
	ctx := r.Context()
	var total int
	if err := a.store.pool.QueryRow(ctx, `SELECT count(*) FROM chat_reports WHERE $1 = 'all' OR status = $1`, status).Scan(&total); err != nil {
		a.fail(w, err)
		return
	}
	rows, err := a.store.jsonRows(ctx, `SELECT r.id, r.server_id, r.reporter_id, r.reporter_name, r.reported_id, r.reported_name, r.reason, r.note, r.message, r.context, r.auto_muted,
			r.status, r.reviewer, r.review_note, r.created_at, r.reviewed_at,
			(SELECT count(*) FROM chat_reports o WHERE o.reported_id = r.reported_id AND o.id <> r.id AND o.created_at > now() - interval '30 days')::int AS previous,
			COALESCE((SELECT banned FROM accounts WHERE id = r.reported_id), false) AS reported_banned
		FROM chat_reports r WHERE $1 = 'all' OR r.status = $1
		ORDER BY CASE WHEN $1 = 'open' THEN r.created_at END ASC NULLS LAST, r.created_at DESC LIMIT $2 OFFSET $3`, status, limit, offset)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeRaw(w, listResult(rows, total))
}

// ---------- payments ----------

func (a *API) adminOrders(w http.ResponseWriter, r *http.Request, s *adminSession) {
	query := r.URL.Query()
	limit, offset := pageParams(r, 100)
	var cond where
	if status := query.Get("status"); status != "" {
		cond.add("o.status = ?", status)
	}
	if provider := query.Get("provider"); provider != "" {
		cond.add("o.provider = ?", provider)
	}
	if account, ok := queryInt(r, "account_id"); ok {
		cond.add("o.account_id = ?", account)
	}
	if q := strings.TrimSpace(query.Get("q")); q != "" {
		if _, err := strconv.ParseInt(q, 10, 64); err == nil {
			cond.add("(o.order_id::text = ? OR o.account_id::text = ?)", q)
		} else {
			// The SKU, the player, or a Stripe reference (cs_..., pi_...).
			cond.add("(o.sku ILIKE ? OR a.username ILIKE ? OR o.payment_ref ILIKE ? OR o.provider_ref ILIKE ?)", likePattern(q))
		}
	}
	from := ` FROM store_orders o LEFT JOIN accounts a ON a.id = o.account_id` + cond.clause()
	ctx := r.Context()
	var total int
	if err := a.store.pool.QueryRow(ctx, `SELECT count(*)`+from, cond.args...).Scan(&total); err != nil {
		a.fail(w, err)
		return
	}
	args := append(append([]any{}, cond.args...), limit, offset)
	rows, err := a.store.jsonRows(ctx, `SELECT o.order_id, o.account_id, a.username, o.sku, o.description, o.items, o.amount, o.currency, o.status, o.provider,
		o.provider_ref, o.payment_ref, o.steam_status, o.created_at, o.updated_at`+from+fmt.Sprintf(` ORDER BY o.created_at DESC LIMIT $%d OFFSET $%d`, len(cond.args)+1, len(cond.args)+2), args...)
	if err != nil {
		a.fail(w, err)
		return
	}
	bySKU, err := a.store.jsonRows(ctx, `SELECT sku, currency, count(*)::int AS orders, sum(amount)::bigint AS total FROM store_orders
		WHERE status = 'paid' AND updated_at > now() - interval '30 days' GROUP BY sku, currency ORDER BY total DESC LIMIT 20`)
	if err != nil {
		a.fail(w, err)
		return
	}
	out, _ := json.Marshal(map[string]any{"rows": rows, "total": total, "by_sku_30d": bySKU})
	writeRaw(w, out)
}

// ---------- auction ----------

func (a *API) adminAuction(w http.ResponseWriter, r *http.Request, s *adminSession) {
	query := r.URL.Query()
	limit, offset := pageParams(r, 100)
	var cond where
	status := query.Get("status")
	if status == "" {
		status = "active"
	}
	if status != "all" {
		cond.add("l.status = ?", status)
	}
	if q := strings.TrimSpace(query.Get("q")); q != "" {
		cond.add("(l.item_id ILIKE ? OR l.seller_name ILIKE ?)", likePattern(q))
	}
	from := ` FROM auction_listings l LEFT JOIN accounts b ON b.id = l.buyer_id` + cond.clause()
	ctx := r.Context()
	var total int
	if err := a.store.pool.QueryRow(ctx, `SELECT count(*)`+from, cond.args...).Scan(&total); err != nil {
		a.fail(w, err)
		return
	}
	args := append(append([]any{}, cond.args...), limit, offset)
	// median: what the same item and quality sold for in the last 30 days, to spot a price
	// far from the market (a typo, or a trade between friends that moves goods).
	rows, err := a.store.jsonRows(ctx, `SELECT l.id, l.seller_id, l.seller_name, b.username AS buyer, l.kind, l.item_id, l.quality, l.item_level, l.strengthen, l.mods,
		l.price_solar, l.price_estrela, l.fee_solar, l.fee_estrela, l.status, l.created_at, l.expires_at, l.closed_at,
		(SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY h.price_solar)::float8 FROM auction_listings h WHERE h.status = 'sold' AND h.item_id = l.item_id AND h.quality = l.quality
			AND h.price_solar > 0 AND h.closed_at > now() - interval '30 days' AND h.id <> l.id) AS median_solar`+
		from+fmt.Sprintf(` ORDER BY l.id DESC LIMIT $%d OFFSET $%d`, len(cond.args)+1, len(cond.args)+2), args...)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeRaw(w, listResult(rows, total))
}

// ---------- audit ----------

// auditFilter reads kind (exact, or a prefix with a trailing *), account_id, since, until
// and q (text inside the detail). Without a start, only the last 7 days are searched.
func auditFilter(r *http.Request) where {
	var cond where
	query := r.URL.Query()
	if kind := query.Get("kind"); kind != "" {
		if prefix, ok := strings.CutSuffix(kind, "*"); ok {
			cond.add(`l.kind LIKE ?`, likePattern(prefix)[1:])
		} else {
			cond.add("l.kind = ?", kind)
		}
	}
	if account, ok := queryInt(r, "account_id"); ok {
		cond.add("l.account_id = ?", account)
	}
	if since, ok := queryTime(r, "since"); ok {
		cond.add("l.created_at >= ?", since)
	} else {
		cond.addRaw("l.created_at >= now() - interval '7 days'")
	}
	if until, ok := queryTime(r, "until"); ok {
		cond.add("l.created_at < ?", until.Add(24*time.Hour-time.Nanosecond))
	}
	if q := strings.TrimSpace(query.Get("q")); q != "" {
		cond.add("l.detail::text ILIKE ?", likePattern(q))
	}
	if before, ok := queryInt(r, "before"); ok {
		cond.add("l.id < ?", before)
	}
	return cond
}

func (a *API) adminAudit(w http.ResponseWriter, r *http.Request, s *adminSession) {
	limit, _ := pageParams(r, 200)
	cond := auditFilter(r)
	args := append(append([]any{}, cond.args...), limit)
	rows, err := a.store.jsonRows(r.Context(), `SELECT l.id, l.created_at, l.kind, l.account_id, a.username, l.server_id, l.detail
		FROM audit_log l LEFT JOIN accounts a ON a.id = l.account_id`+cond.clause()+fmt.Sprintf(` ORDER BY l.id DESC LIMIT $%d`, len(cond.args)+1), args...)
	a.adminReply(w, rows, err)
}

func (a *API) adminAuditKinds(w http.ResponseWriter, r *http.Request, s *adminSession) {
	rows, err := a.store.jsonRows(r.Context(), `SELECT kind, count(*)::int AS n FROM audit_log WHERE created_at > now() - interval '7 days' GROUP BY kind ORDER BY n DESC LIMIT 100`)
	a.adminReply(w, rows, err)
}

// adminAuditCSV exports up to 5000 lines of the audit log; the export itself is recorded.
func (a *API) adminAuditCSV(w http.ResponseWriter, r *http.Request, s *adminSession) {
	cond := auditFilter(r)
	ctx := r.Context()
	err := a.store.adminDo(ctx, s, adminEntry{Action: "audit.export", TargetType: "audit", Detail: map[string]any{"filter": r.URL.RawQuery}}, nil)
	if err != nil {
		a.fail(w, err)
		return
	}
	rows, err := a.store.pool.Query(ctx, `SELECT l.id, l.created_at, l.kind, COALESCE(l.account_id, 0), COALESCE(a.username, ''), l.server_id, l.detail::text
		FROM audit_log l LEFT JOIN accounts a ON a.id = l.account_id`+cond.clause()+` ORDER BY l.id DESC LIMIT 5000`, cond.args...)
	if err != nil {
		a.fail(w, err)
		return
	}
	defer rows.Close()
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="auditoria.csv"`)
	out := csv.NewWriter(w)
	_ = out.Write([]string{"id", "quando", "tipo", "conta", "usuario", "servidor", "detalhe"})
	for rows.Next() {
		var id, account int64
		var at time.Time
		var kind, username, server, detail string
		if err := rows.Scan(&id, &at, &kind, &account, &username, &server, &detail); err != nil {
			return
		}
		_ = out.Write([]string{strconv.FormatInt(id, 10), at.UTC().Format(time.RFC3339), csvSafe(kind), strconv.FormatInt(account, 10), csvSafe(username), csvSafe(server), csvSafe(detail)})
	}
	out.Flush()
}

// csvSafe stops a spreadsheet from running a cell that a player controls as a formula.
func csvSafe(text string) string {
	if text != "" && strings.ContainsRune("=+-@\t\r", rune(text[0])) {
		return "'" + text
	}
	return text
}

// adminStaffActions: the record of what the staff did, filtered by who, what and whom.
func (a *API) adminStaffActions(w http.ResponseWriter, r *http.Request, s *adminSession) {
	query := r.URL.Query()
	limit, offset := pageParams(r, 200)
	var cond where
	if admin, ok := queryInt(r, "admin_id"); ok {
		cond.add("admin_id = ?", admin)
	}
	if account, ok := queryInt(r, "account_id"); ok {
		cond.add("account_id = ?", account)
	}
	if action := query.Get("action"); action != "" {
		cond.add("action = ?", action)
	}
	ctx := r.Context()
	var total int
	if err := a.store.pool.QueryRow(ctx, `SELECT count(*) FROM admin_audit`+cond.clause(), cond.args...).Scan(&total); err != nil {
		a.fail(w, err)
		return
	}
	args := append(append([]any{}, cond.args...), limit, offset)
	rows, err := a.store.jsonRows(ctx, `SELECT id, created_at, admin_id, admin_name, action, target_type, target_id, account_id, reason, detail, ip FROM admin_audit`+cond.clause()+
		fmt.Sprintf(` ORDER BY id DESC LIMIT $%d OFFSET $%d`, len(cond.args)+1, len(cond.args)+2), args...)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeRaw(w, listResult(rows, total))
}

// ---------- system ----------

func (a *API) adminSystem(w http.ResponseWriter, r *http.Request, s *adminSession) {
	ctx := r.Context()
	migrations, err := a.store.jsonRows(ctx, `SELECT name, applied_at FROM schema_migrations ORDER BY name`)
	if err != nil {
		a.fail(w, err)
		return
	}
	tables, err := a.store.jsonRows(ctx, `SELECT relname AS "table", n_live_tup::bigint AS rows, pg_total_relation_size(relid)::bigint AS bytes FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 30`)
	if err != nil {
		a.fail(w, err)
		return
	}
	cfg := a.cfg
	settings := map[string]any{
		"legal_version": cfg.LegalVersion, "trust_proxy": cfg.TrustProxy, "session_days": int(cfg.SessionTTL.Hours() / 24), "auth_per_minute": cfg.AuthPerMinute,
		"stripe_api": cfg.Stripe.Key != "", "stripe_webhook": cfg.Stripe.WebhookSecret != "", "steam_api": cfg.Steam.Key != "" && cfg.Steam.AppID != 0, "steam_sandbox": cfg.Steam.Sandbox,
		"retention_days": map[string]int{"audit": cfg.Retention.AuditDays, "chat": cfg.Retention.ChatDays, "access": cfg.Retention.AccessDays, "reports": cfg.Retention.ReportDays, "orders": cfg.Retention.OrderDays, "challenge": cfg.Retention.ChallengeDays},
		"admin":          map[string]any{"require_2fa": cfg.Admin.Require2FA, "session_hours": cfg.Admin.SessionHours, "idle_minutes": cfg.Admin.IdleMinutes, "allowed_networks": len(cfg.Admin.AllowIPs), "audit_days": cfg.Admin.AuditDays},
	}
	out, _ := json.Marshal(map[string]any{"settings": settings, "migrations": migrations, "tables": tables, "api_started": startedAt})
	writeRaw(w, out)
}
