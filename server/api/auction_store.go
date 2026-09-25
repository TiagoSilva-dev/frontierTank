package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Leilão (0.12). The game server knows the rules (what can be sold, the listing fee,
// the commission) and sends every field ready; the API keeps the items in custody and
// moves items and currencies in PostgreSQL transactions. Whenever an operation changes
// a player's profile (the item leaves the Mochila, the price leaves the buyer, the mail
// enters it), the profile is written in the same transaction, with the version check
// of SaveProfile: either everything happens or nothing does, so nothing is duplicated.

var (
	ErrListingGone  = errors.New("listing gone")
	ErrPriceChanged = errors.New("price changed")
	ErrOwnListing   = errors.New("own listing")
	ErrNotYours     = errors.New("not yours")
	ErrTooMany      = errors.New("too many listings")
	ErrMailGone     = errors.New("mail gone")
)

// ProfileWrite is the profile a game server wants stored with an auction operation.
type ProfileWrite struct {
	Name    *string         `json:"name"`
	Data    json.RawMessage `json:"data"`
	Version int64           `json:"version"`
}

type ListingInput struct {
	Kind         string          `json:"kind"`
	Item         json.RawMessage `json:"item"`
	Slot         string          `json:"slot"`
	ItemID       string          `json:"item_id"`
	Quality      string          `json:"quality"`
	ItemLevel    int             `json:"item_level"`
	Strengthen   int             `json:"strengthen"`
	Mods         []string        `json:"mods"`
	PriceSolar   int             `json:"price_solar"`
	PriceEstrela int             `json:"price_estrela"`
	FeeSolar     int             `json:"fee_solar"`
	FeeEstrela   int             `json:"fee_estrela"`
	Hours        int             `json:"hours"`
}

// Times travel as Unix seconds (with the server's "now" beside them), which is what the
// game shows as time left.
type Listing struct {
	ID           int64           `json:"id"`
	SellerID     *int64          `json:"seller_id"`
	SellerName   string          `json:"seller_name"`
	Kind         string          `json:"kind"`
	Item         json.RawMessage `json:"item"`
	Slot         string          `json:"slot"`
	ItemID       string          `json:"item_id"`
	Quality      string          `json:"quality"`
	ItemLevel    int             `json:"item_level"`
	Strengthen   int             `json:"strengthen"`
	Mods         []string        `json:"mods"`
	PriceSolar   int             `json:"price_solar"`
	PriceEstrela int             `json:"price_estrela"`
	FeeSolar     int             `json:"fee_solar"`
	FeeEstrela   int             `json:"fee_estrela"`
	Status       string          `json:"status"`
	BuyerID      *int64          `json:"buyer_id"`
	CreatedAt    int64           `json:"created_at"`
	ExpiresAt    int64           `json:"expires_at"`
	ClosedAt     *int64          `json:"closed_at"`
}

type Mail struct {
	ID         int64           `json:"id"`
	Kind       string          `json:"kind"`
	ListingID  *int64          `json:"listing_id"`
	ItemKind   string          `json:"item_kind"`
	Item       json.RawMessage `json:"item"`
	Currencies json.RawMessage `json:"currencies"`
	Coins      int             `json:"coins"`
	Detail     json.RawMessage `json:"detail"`
	CreatedAt  int64           `json:"created_at"`
}

type SearchFilter struct {
	Slot          string `json:"slot"`
	ItemID        string `json:"item_id"`
	Quality       string `json:"quality"`
	MinLevel      int    `json:"min_level"`
	MaxLevel      int    `json:"max_level"`
	MinStrengthen int    `json:"min_strengthen"`
	Mod           string `json:"mod"`
	// nil = any price in that currency; 0 = only listings without it.
	MaxSolar   *int   `json:"max_solar"`
	MaxEstrela *int   `json:"max_estrela"`
	Sort       string `json:"sort"`
	Page       int    `json:"page"`
	PerPage    int    `json:"per_page"`
}

type HistoryQuery struct {
	Kind     string `json:"kind"`
	ItemID   string `json:"item_id"`
	Quality  string `json:"quality"`
	MinLevel int    `json:"min_level"`
	MaxLevel int    `json:"max_level"`
	Limit    int    `json:"limit"`
}

const listingColumns = `id, seller_id, seller_name, kind, item, slot, item_id, quality, item_level, strengthen, mods,
	price_solar, price_estrela, fee_solar, fee_estrela, status, buyer_id,
	extract(epoch from created_at)::bigint, extract(epoch from expires_at)::bigint, extract(epoch from closed_at)::bigint`

func scanListing(row pgx.Row) (Listing, error) {
	var l Listing
	err := row.Scan(&l.ID, &l.SellerID, &l.SellerName, &l.Kind, &l.Item, &l.Slot, &l.ItemID, &l.Quality, &l.ItemLevel, &l.Strengthen, &l.Mods,
		&l.PriceSolar, &l.PriceEstrela, &l.FeeSolar, &l.FeeEstrela, &l.Status, &l.BuyerID, &l.CreatedAt, &l.ExpiresAt, &l.ClosedAt)
	if l.Mods == nil {
		l.Mods = []string{}
	}
	return l, err
}

func collectListings(rows pgx.Rows) ([]Listing, error) {
	list, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (Listing, error) { return scanListing(row) })
	if list == nil {
		list = []Listing{}
	}
	return list, err
}

const mailColumns = `id, kind, listing_id, item_kind, item, currencies, coins, detail, extract(epoch from created_at)::bigint`

func scanMail(row pgx.Row) (Mail, error) {
	var m Mail
	err := row.Scan(&m.ID, &m.Kind, &m.ListingID, &m.ItemKind, &m.Item, &m.Currencies, &m.Coins, &m.Detail, &m.CreatedAt)
	if len(m.Item) == 0 {
		m.Item = json.RawMessage("null")
	}
	return m, err
}

// auditTx writes the audit entry inside the operation's transaction: the log always
// matches what happened.
func auditTx(ctx context.Context, tx pgx.Tx, accountID *int64, serverID, kind string, detail any) error {
	data, err := json.Marshal(detail)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO audit_log (account_id, server_id, kind, detail) VALUES ($1, $2, $3, $4)`, accountID, serverID, kind, data)
	return err
}

// runOp runs an auction operation once per op id: a repeated id (the game server
// retrying after a lost answer) gets the stored result back without running again.
func (s *Store) runOp(ctx context.Context, opID string, accountID int64, fn func(tx pgx.Tx) (any, error)) (json.RawMessage, error) {
	if stored, err := s.storedOp(ctx, opID); err != nil || stored != nil {
		return stored, err
	}
	var result json.RawMessage
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		value, err := fn(tx)
		if err != nil {
			return err
		}
		result, err = json.Marshal(value)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO auction_ops (op_id, account_id, result) VALUES ($1, $2, $3)`, opID, accountID, result)
		return err
	})
	if isUnique(err) {
		// The same op ran at the same time on another connection and won: its result.
		return s.storedOp(ctx, opID)
	}
	return result, err
}

func (s *Store) storedOp(ctx context.Context, opID string) (json.RawMessage, error) {
	var result json.RawMessage
	err := s.pool.QueryRow(ctx, `SELECT result FROM auction_ops WHERE op_id = $1`, opID).Scan(&result)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return result, err
}

// expireTx closes the listings whose time is over and mails the items back (only the
// seller's when `seller` is set).
func expireTx(ctx context.Context, tx pgx.Tx, seller *int64) (int64, error) {
	tag, err := tx.Exec(ctx, `WITH expired AS (
			UPDATE auction_listings SET status = 'expired', closed_at = now()
			WHERE status = 'active' AND expires_at <= now() AND ($1::bigint IS NULL OR seller_id = $1)
			RETURNING id, seller_id, kind, item
		), mailed AS (
			INSERT INTO mail (account_id, kind, listing_id, item_kind, item, detail)
			SELECT seller_id, 'returned', id, kind, item, '{"reason": "expired"}'::jsonb FROM expired WHERE seller_id IS NOT NULL
			RETURNING account_id, listing_id
		)
		INSERT INTO audit_log (account_id, server_id, kind, detail)
		SELECT account_id, 'api', 'auction.expire', jsonb_build_object('listing', listing_id) FROM mailed`, seller)
	return tag.RowsAffected(), err
}

// ExpireListings runs every minute (main.go) for all listings.
func (s *Store) ExpireListings(ctx context.Context) (int64, error) {
	var count int64
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var err error
		count, err = expireTx(ctx, tx, nil)
		return err
	})
	return count, err
}

func (s *Store) expireFor(ctx context.Context, accountID int64) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		_, err := expireTx(ctx, tx, &accountID)
		return err
	})
}

// CreateListing takes the item into custody: the seller's profile (without the item
// and with the listing fee paid) and the new listing are written together.
func (s *Store) CreateListing(ctx context.Context, opID, serverID string, accountID int64, profile ProfileWrite, in ListingInput, maxActive int) (json.RawMessage, error) {
	return s.runOp(ctx, opID, accountID, func(tx pgx.Tx) (any, error) {
		version, err := saveProfile(ctx, tx, accountID, profile.Name, profile.Data, profile.Version)
		if err != nil {
			return nil, err
		}
		if _, err := expireTx(ctx, tx, &accountID); err != nil {
			return nil, err
		}
		var active int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM auction_listings WHERE seller_id = $1 AND status = 'active'`, accountID).Scan(&active); err != nil {
			return nil, err
		}
		if active >= maxActive {
			return nil, ErrTooMany
		}
		name := ""
		if profile.Name != nil {
			name = *profile.Name
		}
		if in.Mods == nil {
			in.Mods = []string{}
		}
		listing, err := scanListing(tx.QueryRow(ctx, `INSERT INTO auction_listings (seller_id, seller_name, kind, item, slot, item_id, quality, item_level, strengthen, mods,
				price_solar, price_estrela, fee_solar, fee_estrela, expires_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, now() + make_interval(hours => $15))
			RETURNING `+listingColumns,
			accountID, name, in.Kind, in.Item, in.Slot, in.ItemID, in.Quality, in.ItemLevel, in.Strengthen, in.Mods,
			in.PriceSolar, in.PriceEstrela, in.FeeSolar, in.FeeEstrela, in.Hours))
		if err != nil {
			return nil, err
		}
		err = auditTx(ctx, tx, &accountID, serverID, "auction.list", map[string]any{"listing": listing.ID, "item": in.Item, "price_solar": in.PriceSolar, "price_estrela": in.PriceEstrela, "hours": in.Hours})
		return map[string]any{"version": version, "listing": listing}, err
	})
}

// BuyListing sells a listing: the buyer's profile (price paid), the listing marked sold,
// the item mailed to the buyer and the price, minus the commission, mailed to the seller.
func (s *Store) BuyListing(ctx context.Context, opID, serverID string, buyerID, listingID int64, priceSolar, priceEstrela int, profile ProfileWrite) (json.RawMessage, error) {
	return s.runOp(ctx, opID, buyerID, func(tx pgx.Tx) (any, error) {
		listing, err := scanListing(tx.QueryRow(ctx, `SELECT `+listingColumns+` FROM auction_listings WHERE id = $1 FOR UPDATE`, listingID))
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrListingGone
		}
		if err != nil {
			return nil, err
		}
		if listing.Status != "active" || listing.ExpiresAt <= time.Now().Unix() {
			return nil, ErrListingGone
		}
		if listing.SellerID != nil && *listing.SellerID == buyerID {
			return nil, ErrOwnListing
		}
		if listing.PriceSolar != priceSolar || listing.PriceEstrela != priceEstrela {
			return nil, ErrPriceChanged
		}
		version, err := saveProfile(ctx, tx, buyerID, profile.Name, profile.Data, profile.Version)
		if err != nil {
			return nil, err
		}
		if _, err := tx.Exec(ctx, `UPDATE auction_listings SET status = 'sold', buyer_id = $2, closed_at = now() WHERE id = $1`, listingID, buyerID); err != nil {
			return nil, err
		}
		buyerName := ""
		if profile.Name != nil {
			buyerName = *profile.Name
		}
		price := map[string]int{"solar": listing.PriceSolar, "estrela": listing.PriceEstrela}
		var mailID int64
		err = tx.QueryRow(ctx, `INSERT INTO mail (account_id, kind, listing_id, item_kind, item, detail) VALUES ($1, 'purchase', $2, $3, $4, $5) RETURNING id`,
			buyerID, listingID, listing.Kind, listing.Item, map[string]any{"price": price, "seller": listing.SellerName}).Scan(&mailID)
		if err != nil {
			return nil, err
		}
		if listing.SellerID != nil {
			proceeds := map[string]int{}
			if value := listing.PriceSolar - listing.FeeSolar; value > 0 {
				proceeds["solar"] = value
			}
			if value := listing.PriceEstrela - listing.FeeEstrela; value > 0 {
				proceeds["estrela"] = value
			}
			detail := map[string]any{"item_kind": listing.Kind, "item": listing.Item, "price": price, "fee": map[string]int{"solar": listing.FeeSolar, "estrela": listing.FeeEstrela}, "buyer": buyerName}
			if _, err := tx.Exec(ctx, `INSERT INTO mail (account_id, kind, listing_id, currencies, detail) VALUES ($1, 'sale', $2, $3, $4)`, *listing.SellerID, listingID, proceeds, detail); err != nil {
				return nil, err
			}
			if err := auditTx(ctx, tx, listing.SellerID, serverID, "auction.sold", map[string]any{"listing": listingID, "buyer": buyerID, "proceeds": proceeds}); err != nil {
				return nil, err
			}
		}
		if err := auditTx(ctx, tx, &buyerID, serverID, "auction.buy", map[string]any{"listing": listingID, "seller": listing.SellerID, "price": price, "item": listing.Item}); err != nil {
			return nil, err
		}
		listing.Status = "sold"
		return map[string]any{"version": version, "mail_id": mailID, "listing": listing, "seller_id": listing.SellerID}, nil
	})
}

// CancelListing closes the seller's listing and mails the item back. The listing fee
// stays paid (it is one of the currency sinks).
func (s *Store) CancelListing(ctx context.Context, opID, serverID string, accountID, listingID int64) (json.RawMessage, error) {
	return s.runOp(ctx, opID, accountID, func(tx pgx.Tx) (any, error) {
		listing, err := scanListing(tx.QueryRow(ctx, `SELECT `+listingColumns+` FROM auction_listings WHERE id = $1 FOR UPDATE`, listingID))
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrListingGone
		}
		if err != nil {
			return nil, err
		}
		if listing.SellerID == nil || *listing.SellerID != accountID {
			return nil, ErrNotYours
		}
		if listing.Status != "active" {
			return nil, ErrListingGone
		}
		status := "cancelled"
		if listing.ExpiresAt <= time.Now().Unix() {
			status = "expired"
		}
		if _, err := tx.Exec(ctx, `UPDATE auction_listings SET status = $2, closed_at = now() WHERE id = $1`, listingID, status); err != nil {
			return nil, err
		}
		var mailID int64
		err = tx.QueryRow(ctx, `INSERT INTO mail (account_id, kind, listing_id, item_kind, item, detail) VALUES ($1, 'returned', $2, $3, $4, $5) RETURNING id`,
			accountID, listingID, listing.Kind, listing.Item, map[string]string{"reason": status}).Scan(&mailID)
		if err != nil {
			return nil, err
		}
		if err := auditTx(ctx, tx, &accountID, serverID, "auction.cancel", map[string]any{"listing": listingID}); err != nil {
			return nil, err
		}
		listing.Status = status
		return map[string]any{"mail_id": mailID, "listing": listing}, nil
	})
}

func (s *Store) SearchListings(ctx context.Context, f SearchFilter) ([]Listing, int, error) {
	where := []string{"status = 'active'", "expires_at > now()"}
	args := []any{}
	add := func(clause string, value any) {
		args = append(args, value)
		where = append(where, fmt.Sprintf(clause, len(args)))
	}
	if f.Slot != "" {
		add("slot = $%d", f.Slot)
	}
	if f.ItemID != "" {
		add("item_id = $%d", f.ItemID)
	}
	if f.Quality != "" {
		add("quality = $%d", f.Quality)
	}
	if f.MinLevel > 0 {
		add("item_level >= $%d", f.MinLevel)
	}
	if f.MaxLevel > 0 {
		add("item_level <= $%d", f.MaxLevel)
	}
	if f.MinStrengthen > 0 {
		add("strengthen >= $%d", f.MinStrengthen)
	}
	if f.Mod != "" {
		add("$%d = ANY(mods)", f.Mod)
	}
	if f.MaxSolar != nil {
		add("price_solar <= $%d", *f.MaxSolar)
	}
	if f.MaxEstrela != nil {
		add("price_estrela <= $%d", *f.MaxEstrela)
	}
	order := "created_at DESC, id DESC"
	switch f.Sort {
	case "price":
		order = "price_solar ASC, price_estrela ASC, id ASC"
	case "level":
		order = "item_level DESC, strengthen DESC, id DESC"
	}
	perPage := f.PerPage
	if perPage <= 0 || perPage > 50 {
		perPage = 12
	}
	page := max(f.Page, 0)
	args = append(args, perPage, page*perPage)
	sql := fmt.Sprintf(`SELECT %s, count(*) OVER () FROM auction_listings WHERE %s ORDER BY %s LIMIT $%d OFFSET $%d`,
		listingColumns, strings.Join(where, " AND "), order, len(args)-1, len(args))
	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	list := []Listing{}
	total := 0
	for rows.Next() {
		var l Listing
		err := rows.Scan(&l.ID, &l.SellerID, &l.SellerName, &l.Kind, &l.Item, &l.Slot, &l.ItemID, &l.Quality, &l.ItemLevel, &l.Strengthen, &l.Mods,
			&l.PriceSolar, &l.PriceEstrela, &l.FeeSolar, &l.FeeEstrela, &l.Status, &l.BuyerID, &l.CreatedAt, &l.ExpiresAt, &l.ClosedAt, &total)
		if err != nil {
			return nil, 0, err
		}
		if l.Mods == nil {
			l.Mods = []string{}
		}
		list = append(list, l)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	if len(list) == 0 && page > 0 {
		// Past the last page: still report how many there are.
		err = s.pool.QueryRow(ctx, fmt.Sprintf(`SELECT count(*) FROM auction_listings WHERE %s`, strings.Join(where, " AND ")), args[:len(args)-2]...).Scan(&total)
	}
	return list, total, err
}

// MyListings: the seller's active listings and the last closed ones (sold, cancelled or
// expired), after returning whatever expired.
func (s *Store) MyListings(ctx context.Context, accountID int64) ([]Listing, []Listing, error) {
	if err := s.expireFor(ctx, accountID); err != nil {
		return nil, nil, err
	}
	rows, err := s.pool.Query(ctx, `SELECT `+listingColumns+` FROM auction_listings WHERE seller_id = $1 AND status = 'active' ORDER BY created_at DESC LIMIT 100`, accountID)
	if err != nil {
		return nil, nil, err
	}
	active, err := collectListings(rows)
	if err != nil {
		return nil, nil, err
	}
	rows, err = s.pool.Query(ctx, `SELECT `+listingColumns+` FROM auction_listings WHERE seller_id = $1 AND status <> 'active' ORDER BY closed_at DESC LIMIT 20`, accountID)
	if err != nil {
		return nil, nil, err
	}
	closed, err := collectListings(rows)
	return active, closed, err
}

// PriceHistory: the last sales of the same item (or maps of the same instance), for the
// price the players are paying.
func (s *Store) PriceHistory(ctx context.Context, q HistoryQuery) ([]Listing, error) {
	limit := q.Limit
	if limit <= 0 || limit > 20 {
		limit = 10
	}
	where := []string{"status = 'sold'", "kind = $1", "item_id = $2"}
	args := []any{q.Kind, q.ItemID}
	if q.Quality != "" {
		args = append(args, q.Quality)
		where = append(where, fmt.Sprintf("quality = $%d", len(args)))
	}
	if q.MinLevel > 0 {
		args = append(args, q.MinLevel)
		where = append(where, fmt.Sprintf("item_level >= $%d", len(args)))
	}
	if q.MaxLevel > 0 {
		args = append(args, q.MaxLevel)
		where = append(where, fmt.Sprintf("item_level <= $%d", len(args)))
	}
	args = append(args, limit)
	rows, err := s.pool.Query(ctx, fmt.Sprintf(`SELECT %s FROM auction_listings WHERE %s ORDER BY closed_at DESC LIMIT $%d`, listingColumns, strings.Join(where, " AND "), len(args)), args...)
	if err != nil {
		return nil, err
	}
	return collectListings(rows)
}

// MailList: what is waiting in the player's mail (oldest first) and how many in total.
func (s *Store) MailList(ctx context.Context, accountID int64) ([]Mail, int, error) {
	if err := s.expireFor(ctx, accountID); err != nil {
		return nil, 0, err
	}
	var total int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM mail WHERE account_id = $1 AND claimed_at IS NULL`, accountID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.pool.Query(ctx, `SELECT `+mailColumns+` FROM mail WHERE account_id = $1 AND claimed_at IS NULL ORDER BY id LIMIT 100`, accountID)
	if err != nil {
		return nil, 0, err
	}
	list, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (Mail, error) { return scanMail(row) })
	if list == nil {
		list = []Mail{}
	}
	return list, total, err
}

// ClaimMail marks mail as received and stores the profile that got its contents.
func (s *Store) ClaimMail(ctx context.Context, opID, serverID string, accountID int64, ids []int64, profile ProfileWrite) (json.RawMessage, error) {
	return s.runOp(ctx, opID, accountID, func(tx pgx.Tx) (any, error) {
		rows, err := tx.Query(ctx, `SELECT id FROM mail WHERE id = ANY($1) AND account_id = $2 AND claimed_at IS NULL FOR UPDATE`, ids, accountID)
		if err != nil {
			return nil, err
		}
		found, err := pgx.CollectRows(rows, pgx.RowTo[int64])
		if err != nil {
			return nil, err
		}
		if len(found) != len(ids) {
			return nil, ErrMailGone
		}
		version, err := saveProfile(ctx, tx, accountID, profile.Name, profile.Data, profile.Version)
		if err != nil {
			return nil, err
		}
		if _, err := tx.Exec(ctx, `UPDATE mail SET claimed_at = now() WHERE id = ANY($1)`, ids); err != nil {
			return nil, err
		}
		if err := auditTx(ctx, tx, &accountID, serverID, "mail.claim", map[string]any{"mail": ids}); err != nil {
			return nil, err
		}
		return map[string]any{"version": version, "claimed": ids}, nil
	})
}
