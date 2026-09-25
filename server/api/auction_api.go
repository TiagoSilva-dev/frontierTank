package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"
	"unicode/utf8"
)

// Leilão (0.12): internal routes, called only by game servers (they check the rules and
// who the player is; see auction_store.go for the transactions).

const (
	codeListingGone  = "listing_gone"
	codePriceChanged = "price_changed"
	codeOwnListing   = "own_listing"
	codeNotYours     = "not_yours"
	codeTooMany      = "too_many_listings"
	codeMailGone     = "mail_gone"
)

func (a *API) auctionRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /internal/auction/search", a.auctionSearch)
	mux.HandleFunc("POST /internal/auction/listings", a.auctionCreate)
	mux.HandleFunc("POST /internal/auction/listings/{id}/buy", a.auctionBuy)
	mux.HandleFunc("POST /internal/auction/listings/{id}/cancel", a.auctionCancel)
	mux.HandleFunc("GET /internal/auction/mine", a.auctionMine)
	mux.HandleFunc("POST /internal/auction/history", a.auctionHistory)
	mux.HandleFunc("GET /internal/mail", a.mailList)
	mux.HandleFunc("POST /internal/mail/claim", a.mailClaim)
}

// auctionFail answers the business errors with their code; anything else is internal.
func (a *API) auctionFail(w http.ResponseWriter, err error) {
	codes := []struct {
		err  error
		code string
	}{
		{ErrListingGone, codeListingGone}, {ErrPriceChanged, codePriceChanged}, {ErrOwnListing, codeOwnListing},
		{ErrNotYours, codeNotYours}, {ErrTooMany, codeTooMany}, {ErrMailGone, codeMailGone},
		{ErrConflict, codeConflict}, {ErrNameTaken, codeNameTaken},
	}
	for _, entry := range codes {
		if errors.Is(err, entry.err) {
			writeError(w, http.StatusConflict, entry.code, entry.err.Error())
			return
		}
	}
	a.fail(w, err)
}

func writeRaw(w http.ResponseWriter, data json.RawMessage) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func shortText(value string, limit int) bool {
	return value != "" && utf8.RuneCountInString(value) <= limit
}

func validOpID(value string) bool {
	return shortText(value, 100)
}

// validProfileWrite checks the profile like putProfile does.
func validProfileWrite(profile *ProfileWrite) bool {
	if len(profile.Data) == 0 || !json.Valid(profile.Data) || profile.Version < 0 {
		return false
	}
	if profile.Name != nil {
		name := normalizeName(*profile.Name)
		if !validCharacterName(name) {
			return false
		}
		profile.Name = &name
	}
	return true
}

func validListing(in ListingInput) bool {
	if in.Kind != "item" && in.Kind != "map" {
		return false
	}
	var item map[string]any
	if json.Unmarshal(in.Item, &item) != nil || item == nil {
		return false
	}
	if !shortText(in.Slot, 32) || !shortText(in.ItemID, 64) || !shortText(in.Quality, 32) || len(in.Mods) > 12 {
		return false
	}
	for _, mod := range in.Mods {
		if !shortText(mod, 32) {
			return false
		}
	}
	if in.ItemLevel < 0 || in.ItemLevel > 100 || in.Strengthen < 0 || in.Strengthen > 20 || in.Hours < 1 || in.Hours > 168 {
		return false
	}
	if in.PriceSolar < 0 || in.PriceEstrela < 0 || in.PriceSolar > 99999 || in.PriceEstrela > 99999 || in.PriceSolar+in.PriceEstrela == 0 {
		return false
	}
	return in.FeeSolar >= 0 && in.FeeEstrela >= 0 && in.FeeSolar <= in.PriceSolar && in.FeeEstrela <= in.PriceEstrela
}

func queryAccount(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.URL.Query().Get("account"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid account")
		return 0, false
	}
	return id, true
}

func (a *API) auctionSearch(w http.ResponseWriter, r *http.Request) {
	var filter SearchFilter
	if err := readJSON(r, &filter); err != nil || len(filter.Slot) > 32 || len(filter.ItemID) > 64 || len(filter.Quality) > 32 || len(filter.Mod) > 32 || filter.Page > 1000 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	list, total, err := a.store.SearchListings(r.Context(), filter)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"listings": list, "total": total, "now": time.Now().Unix()})
}

func (a *API) auctionCreate(w http.ResponseWriter, r *http.Request) {
	var body struct {
		OpID      string       `json:"op_id"`
		ServerID  string       `json:"server_id"`
		AccountID int64        `json:"account_id"`
		Profile   ProfileWrite `json:"profile"`
		Listing   ListingInput `json:"listing"`
		MaxActive int          `json:"max_active"`
	}
	if err := readJSON(r, &body); err != nil || !validOpID(body.OpID) || body.AccountID <= 0 || !validProfileWrite(&body.Profile) || !validListing(body.Listing) || body.MaxActive < 1 || body.MaxActive > 1000 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	result, err := a.store.CreateListing(r.Context(), body.OpID, body.ServerID, body.AccountID, body.Profile, body.Listing, body.MaxActive)
	if err != nil {
		a.auctionFail(w, err)
		return
	}
	writeRaw(w, result)
}

func (a *API) auctionBuy(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		OpID         string       `json:"op_id"`
		ServerID     string       `json:"server_id"`
		AccountID    int64        `json:"account_id"`
		PriceSolar   int          `json:"price_solar"`
		PriceEstrela int          `json:"price_estrela"`
		Profile      ProfileWrite `json:"profile"`
	}
	if err := readJSON(r, &body); err != nil || !validOpID(body.OpID) || body.AccountID <= 0 || !validProfileWrite(&body.Profile) {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	result, err := a.store.BuyListing(r.Context(), body.OpID, body.ServerID, body.AccountID, id, body.PriceSolar, body.PriceEstrela, body.Profile)
	if err != nil {
		a.auctionFail(w, err)
		return
	}
	writeRaw(w, result)
}

func (a *API) auctionCancel(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		OpID      string `json:"op_id"`
		ServerID  string `json:"server_id"`
		AccountID int64  `json:"account_id"`
	}
	if err := readJSON(r, &body); err != nil || !validOpID(body.OpID) || body.AccountID <= 0 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	result, err := a.store.CancelListing(r.Context(), body.OpID, body.ServerID, body.AccountID, id)
	if err != nil {
		a.auctionFail(w, err)
		return
	}
	writeRaw(w, result)
}

func (a *API) auctionMine(w http.ResponseWriter, r *http.Request) {
	account, ok := queryAccount(w, r)
	if !ok {
		return
	}
	active, closed, err := a.store.MyListings(r.Context(), account)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"active": active, "closed": closed, "now": time.Now().Unix()})
}

func (a *API) auctionHistory(w http.ResponseWriter, r *http.Request) {
	var query HistoryQuery
	if err := readJSON(r, &query); err != nil || (query.Kind != "item" && query.Kind != "map") || !shortText(query.ItemID, 64) || len(query.Quality) > 32 {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	sales, err := a.store.PriceHistory(r.Context(), query)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sales": sales, "now": time.Now().Unix()})
}

func (a *API) mailList(w http.ResponseWriter, r *http.Request) {
	account, ok := queryAccount(w, r)
	if !ok {
		return
	}
	list, total, err := a.store.MailList(r.Context(), account)
	if err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"mail": list, "total": total, "now": time.Now().Unix()})
}

func (a *API) mailClaim(w http.ResponseWriter, r *http.Request) {
	var body struct {
		OpID      string       `json:"op_id"`
		ServerID  string       `json:"server_id"`
		AccountID int64        `json:"account_id"`
		IDs       []int64      `json:"ids"`
		Profile   ProfileWrite `json:"profile"`
	}
	if err := readJSON(r, &body); err != nil || !validOpID(body.OpID) || body.AccountID <= 0 || len(body.IDs) == 0 || len(body.IDs) > 100 || !validProfileWrite(&body.Profile) {
		writeError(w, http.StatusBadRequest, codeBadRequest, "invalid body")
		return
	}
	seen := map[int64]bool{}
	for _, id := range body.IDs {
		if id <= 0 || seen[id] {
			writeError(w, http.StatusBadRequest, codeBadRequest, "invalid mail ids")
			return
		}
		seen[id] = true
	}
	result, err := a.store.ClaimMail(r.Context(), body.OpID, body.ServerID, body.AccountID, body.IDs, body.Profile)
	if err != nil {
		a.auctionFail(w, err)
		return
	}
	writeRaw(w, result)
}
