package main

import (
	"crypto/rand"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
)

// What the staff can change. Every action needs a reason, goes through Store.adminDo (the
// effect and its admin_audit line are one transaction) and answers with the same error
// codes the page shows.

// preconditionError: the action cannot happen in the current state (shown to the staff).
type preconditionError string

func (e preconditionError) Error() string { return string(e) }

func (a *API) adminFail(w http.ResponseWriter, err error) {
	var precondition preconditionError
	switch {
	case errors.Is(err, ErrDuplicate):
		writeError(w, http.StatusConflict, "duplicate", "Esta ação já foi enviada (clique duplo ou repetição).")
	case errors.Is(err, ErrNotFound):
		writeError(w, http.StatusNotFound, codeNotFound, "Não encontrado.")
	case errors.As(err, &precondition):
		writeError(w, http.StatusConflict, "conflict", string(precondition))
	default:
		a.fail(w, err)
	}
}

func (a *API) adminActionRoutes(api adminRouter) {
	api("POST /admin/api/players/{id}/ban", roleAdmin, a.adminBan)
	api("POST /admin/api/players/{id}/unban", roleAdmin, a.adminUnban)
	api("POST /admin/api/players/{id}/sessions/revoke", roleAdmin, a.adminRevokeSessions)
	api("POST /admin/api/players/{id}/password", roleAdmin, a.adminResetPlayerPassword)
	api("POST /admin/api/players/{id}/notes", roleSupport, a.adminNote)
	api("POST /admin/api/players/{id}/gift", roleSupport, a.adminGift)
	api("GET /admin/api/players/{id}/export", roleOwner, a.adminExportPlayer)
	api("DELETE /admin/api/players/{id}", roleOwner, a.adminDeletePlayer)
	api("POST /admin/api/reports/{id}/review", roleSupport, a.adminReviewReport)
	api("POST /admin/api/auction/{id}/cancel", roleAdmin, a.adminCancelListing)
	api("GET /admin/api/broadcast/count", roleAdmin, a.adminBroadcastCount)
	api("POST /admin/api/broadcast", roleAdmin, a.adminBroadcast)
}

// ---------- the catalog of gifts ----------

//go:embed admin_catalog.json
var adminCatalogFile []byte

type adminAsset struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Kind string `json:"kind"`
}

// adminAssets is what a letter may carry besides coins (tools/admin_catalog.py writes it
// from shared/balance/items.json): the currencies and the strengthen stones. An id the game
// does not know would be "received" without giving anything, so nothing else goes through.
var adminAssets = func() map[string]adminAsset {
	var file struct {
		Assets []adminAsset `json:"assets"`
	}
	if err := json.Unmarshal(adminCatalogFile, &file); err != nil {
		panic(err)
	}
	assets := map[string]adminAsset{}
	for _, asset := range file.Assets {
		assets[asset.ID] = asset
	}
	return assets
}()

// giftCaps: how much one gift (or one letter of a mass sending) may carry. Support can
// settle small complaints; the rest needs an admin.
type giftCaps struct {
	Coins int `json:"coins"`
	Asset int `json:"asset"`
}

func giftCapsFor(role string) giftCaps {
	if roleRanks[role] >= roleAdmin {
		return giftCaps{Coins: 1000000, Asset: 10000}
	}
	return giftCaps{Coins: 5000, Asset: 50}
}

var broadcastCaps = giftCaps{Coins: 100000, Asset: 1000}

func (a *API) adminCatalogRoute(w http.ResponseWriter, r *http.Request, s *adminSession) {
	assets := make([]adminAsset, 0, len(adminAssets))
	for _, asset := range adminAssets {
		assets = append(assets, asset)
	}
	sort.Slice(assets, func(i, j int) bool {
		if assets[i].Kind != assets[j].Kind {
			return assets[i].Kind < assets[j].Kind
		}
		return assets[i].ID < assets[j].ID
	})
	writeJSON(w, http.StatusOK, map[string]any{"assets": assets, "gift_caps": giftCapsFor(s.Role), "broadcast_caps": broadcastCaps})
}

// ---------- shared checks ----------

var requestIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{8,64}$`)

func validReason(reason string) bool {
	length := utf8.RuneCountInString(strings.TrimSpace(reason))
	return length >= 3 && length <= 300
}

func (a *API) badInput(w http.ResponseWriter, message string) {
	writeError(w, http.StatusBadRequest, codeBadRequest, message)
}

// ---------- bans, notes, sessions, passwords ----------

func (a *API) adminBan(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Reason string `json:"reason"`
		Hours  int    `json:"hours"`
	}
	if err := readJSON(r, &body); err != nil || !validReason(body.Reason) || body.Hours < 0 || body.Hours > 24*365*5 {
		a.badInput(w, "Informe o motivo (3 a 300 letras) e a duração em horas (0 = sem prazo).")
		return
	}
	reason := strings.TrimSpace(body.Reason)
	entry := adminEntry{Action: "player.ban", TargetType: "account", TargetID: idText(id), AccountID: &id, Reason: reason, Detail: map[string]any{"hours": body.Hours}}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		tag, err := tx.Exec(r.Context(), `UPDATE accounts SET banned = true, ban_reason = $2, ban_until = CASE WHEN $3 > 0 THEN now() + make_interval(hours => $3) END, banned_at = now(), banned_by = $4 WHERE id = $1`,
			id, reason, body.Hours, s.Username)
		if err != nil {
			return nil, err
		}
		if tag.RowsAffected() == 0 {
			return nil, ErrNotFound
		}
		// The login refuses a banned account; ending the sessions also stops the ones in use.
		// A player who is online leaves within seconds (the game server checks at its heartbeat).
		_, err = tx.Exec(r.Context(), `DELETE FROM sessions WHERE account_id = $1`, id)
		return nil, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) adminUnban(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	if err := readJSON(r, &body); err != nil || !validReason(body.Reason) {
		a.badInput(w, "Informe o motivo (3 a 300 letras).")
		return
	}
	entry := adminEntry{Action: "player.unban", TargetType: "account", TargetID: idText(id), AccountID: &id, Reason: strings.TrimSpace(body.Reason)}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		tag, err := tx.Exec(r.Context(), `UPDATE accounts SET banned = false, ban_until = NULL WHERE id = $1`, id)
		if err == nil && tag.RowsAffected() == 0 {
			err = ErrNotFound
		}
		return nil, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) adminRevokeSessions(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	if err := readJSON(r, &body); err != nil || !validReason(body.Reason) {
		a.badInput(w, "Informe o motivo (3 a 300 letras).")
		return
	}
	var count int64
	entry := adminEntry{Action: "player.revoke_sessions", TargetType: "account", TargetID: idText(id), AccountID: &id, Reason: strings.TrimSpace(body.Reason)}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		tag, err := tx.Exec(r.Context(), `DELETE FROM sessions WHERE account_id = $1`, id)
		count = tag.RowsAffected()
		return map[string]any{"sessions": count}, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"sessions": count})
}

// tempPassword: 14 characters without the ones that look alike (0/O, 1/l/I).
func tempPassword() (string, error) {
	const alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	out := make([]byte, 14)
	for i := range out {
		index, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", err
		}
		out[i] = alphabet[index.Int64()]
	}
	return string(out), nil
}

// adminResetPlayerPassword sets a temporary password for a player who lost theirs (the game
// has no e-mail to recover it) and ends their sessions. The staff reads it once to the
// player, who changes it in the game. Accounts made by the Steam login have no password.
func (a *API) adminResetPlayerPassword(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	if err := readJSON(r, &body); err != nil || !validReason(body.Reason) {
		a.badInput(w, "Informe o motivo (3 a 300 letras): como você confirmou que a pessoa é a dona da conta?")
		return
	}
	password, err := tempPassword()
	if err != nil {
		a.fail(w, err)
		return
	}
	hash, err := hashPassword(password, a.cfg.PBKDF2Iterations)
	if err != nil {
		a.fail(w, err)
		return
	}
	entry := adminEntry{Action: "player.reset_password", TargetType: "account", TargetID: idText(id), AccountID: &id, Reason: strings.TrimSpace(body.Reason)}
	err = a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		var steamOnly bool
		err := tx.QueryRow(r.Context(), `SELECT password_hash = '' FROM accounts WHERE id = $1 FOR UPDATE`, id).Scan(&steamOnly)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		if steamOnly {
			return nil, preconditionError("Esta conta foi criada pela Steam e não tem senha.")
		}
		if _, err := tx.Exec(r.Context(), `UPDATE accounts SET password_hash = $2 WHERE id = $1`, id, hash); err != nil {
			return nil, err
		}
		_, err = tx.Exec(r.Context(), `DELETE FROM sessions WHERE account_id = $1`, id)
		return nil, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"password": password})
}

func (a *API) adminNote(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Note string `json:"note"`
	}
	note := ""
	if err := readJSON(r, &body); err == nil {
		note = strings.TrimSpace(body.Note)
	}
	if length := utf8.RuneCountInString(note); length < 1 || length > 500 {
		a.badInput(w, "A anotação precisa ter de 1 a 500 letras.")
		return
	}
	entry := adminEntry{Action: "player.note", TargetType: "account", TargetID: idText(id), AccountID: &id}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		tag, err := tx.Exec(r.Context(), `INSERT INTO account_notes (account_id, admin_name, note) SELECT id, $2, $3 FROM accounts WHERE id = $1`, id, s.Username, note)
		if err == nil && tag.RowsAffected() == 0 {
			err = ErrNotFound
		}
		return nil, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---------- gifts ----------

// giftBody is what a letter from the staff carries. `Note` is shown to the player in the
// Correio; `Reason` stays in the staff record.
type giftBody struct {
	Coins     int            `json:"coins"`
	Assets    map[string]int `json:"assets"`
	Note      string         `json:"note"`
	Reason    string         `json:"reason"`
	RequestID string         `json:"request_id"`
}

// check cleans the gift in place and returns what is wrong with it ("" = fine).
func (g *giftBody) check(caps giftCaps) string {
	g.Note = strings.TrimSpace(g.Note)
	g.Reason = strings.TrimSpace(g.Reason)
	clean := map[string]int{}
	for id, amount := range g.Assets {
		if amount == 0 {
			continue
		}
		if _, known := adminAssets[id]; !known {
			return "Moeda ou pedra desconhecida: " + id
		}
		if amount < 0 || amount > caps.Asset {
			return fmt.Sprintf("Cada moeda ou pedra aceita de 1 a %d por presente.", caps.Asset)
		}
		clean[id] = amount
	}
	g.Assets = clean
	switch {
	case g.Coins < 0 || g.Coins > caps.Coins:
		return fmt.Sprintf("As moedas aceitam de 0 a %d por presente.", caps.Coins)
	case g.Coins == 0 && len(g.Assets) == 0:
		return "Escolha o que enviar."
	case utf8.RuneCountInString(g.Note) < 3 || utf8.RuneCountInString(g.Note) > 80:
		return "A mensagem para o jogador precisa ter de 3 a 80 letras."
	case !validReason(g.Reason):
		return "Informe o motivo interno (3 a 300 letras)."
	case !requestIDPattern.MatchString(g.RequestID):
		return "Pedido sem identificador. Recarregue a página."
	}
	return ""
}

func (g *giftBody) detail() map[string]any {
	return map[string]any{"coins": g.Coins, "assets": g.Assets, "note": g.Note}
}

func (a *API) adminGift(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var gift giftBody
	if err := readJSON(r, &gift); err != nil {
		a.badInput(w, "Pedido inválido.")
		return
	}
	if message := gift.check(giftCapsFor(s.Role)); message != "" {
		a.badInput(w, message)
		return
	}
	entry := adminEntry{Action: "player.gift", TargetType: "account", TargetID: idText(id), AccountID: &id, Reason: gift.Reason, Detail: gift.detail(), RequestID: gift.RequestID}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		var mailID int64
		err := tx.QueryRow(r.Context(), `INSERT INTO mail (account_id, kind, coins, currencies, detail) SELECT id, 'gift', $2, $3, $4 FROM accounts WHERE id = $1 RETURNING id`,
			id, gift.Coins, gift.Assets, map[string]any{"note": gift.Note}).Scan(&mailID)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return map[string]any{"mail_id": mailID}, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// A mass sending reaches the players who have a character and are not banned.
var broadcastSegments = map[string]string{
	"all":        "TRUE",
	"active_7d":  "a.last_login > now() - interval '7 days'",
	"active_30d": "a.last_login > now() - interval '30 days'",
	"new_7d":     "a.created_at > now() - interval '7 days'",
}

func broadcastFilter(segment string) (string, bool) {
	condition, ok := broadcastSegments[segment]
	if !ok {
		return "", false
	}
	return `NOT a.banned AND EXISTS (SELECT 1 FROM profiles p WHERE p.account_id = a.id) AND ` + condition, true
}

func (a *API) adminBroadcastCount(w http.ResponseWriter, r *http.Request, s *adminSession) {
	filter, ok := broadcastFilter(r.URL.Query().Get("segment"))
	if !ok {
		a.badInput(w, "Grupo desconhecido.")
		return
	}
	var count int
	if err := a.store.pool.QueryRow(r.Context(), `SELECT count(*) FROM accounts a WHERE `+filter).Scan(&count); err != nil {
		a.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"count": count})
}

// adminBroadcast mails the same gift to a group. The page shows the number of recipients
// first and sends it back as `expect`: if the group changed meanwhile, nothing is sent.
func (a *API) adminBroadcast(w http.ResponseWriter, r *http.Request, s *adminSession) {
	var body struct {
		giftBody
		Segment string `json:"segment"`
		Expect  int    `json:"expect"`
	}
	if err := readJSON(r, &body); err != nil {
		a.badInput(w, "Pedido inválido.")
		return
	}
	filter, ok := broadcastFilter(body.Segment)
	if !ok {
		a.badInput(w, "Grupo desconhecido.")
		return
	}
	if message := body.giftBody.check(broadcastCaps); message != "" {
		a.badInput(w, message)
		return
	}
	detail := body.giftBody.detail()
	detail["segment"] = body.Segment
	detail["expected"] = body.Expect
	entry := adminEntry{Action: "broadcast.gift", TargetType: "segment", TargetID: body.Segment, Reason: body.Reason, Detail: detail, RequestID: body.RequestID}
	var sent int64
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		var count int
		if err := tx.QueryRow(r.Context(), `SELECT count(*) FROM accounts a WHERE `+filter).Scan(&count); err != nil {
			return nil, err
		}
		if count != body.Expect || count == 0 {
			return nil, preconditionError(fmt.Sprintf("O grupo mudou: agora são %d jogadores (você confirmou %d). Confira e envie de novo.", count, body.Expect))
		}
		tag, err := tx.Exec(r.Context(), `INSERT INTO mail (account_id, kind, coins, currencies, detail) SELECT a.id, 'gift', $1, $2, $3 FROM accounts a WHERE `+filter,
			body.Coins, body.Assets, map[string]any{"note": body.Note})
		sent = tag.RowsAffected()
		return map[string]any{"sent": sent}, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"sent": sent})
}

// ---------- reports and the auction ----------

func (a *API) adminReviewReport(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Status string `json:"status"`
		Note   string `json:"note"`
	}
	if err := readJSON(r, &body); err != nil || !(body.Status == "dismissed" || body.Status == "warned" || body.Status == "banned") || utf8.RuneCountInString(body.Note) > 500 {
		a.badInput(w, "Decida entre descartar, avisar ou banir (anotação de até 500 letras).")
		return
	}
	if body.Status == "banned" && roleRanks[s.Role] < roleAdmin {
		writeError(w, http.StatusForbidden, "forbidden", "Só administradores banem. Descarte, avise ou peça a um administrador.")
		return
	}
	var reported *int64
	err := a.store.pool.QueryRow(r.Context(), `SELECT reported_id FROM chat_reports WHERE id = $1`, id).Scan(&reported)
	if errors.Is(err, pgx.ErrNoRows) {
		a.adminFail(w, ErrNotFound)
		return
	}
	if err != nil {
		a.fail(w, err)
		return
	}
	note := truncate(body.Note, 500)
	entry := adminEntry{Action: "report." + body.Status, TargetType: "report", TargetID: idText(id), AccountID: reported, Reason: note}
	err = a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		return nil, reviewReportTx(r.Context(), tx, id, body.Status, s.Username, note)
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// adminCancelListing closes someone's listing and mails the item back to the seller (the
// listing fee stays paid, as when the seller cancels).
func (a *API) adminCancelListing(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	if err := readJSON(r, &body); err != nil || !validReason(body.Reason) {
		a.badInput(w, "Informe o motivo (3 a 300 letras).")
		return
	}
	entry := adminEntry{Action: "auction.cancel", TargetType: "listing", TargetID: idText(id), Reason: strings.TrimSpace(body.Reason)}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		listing, err := scanListing(tx.QueryRow(r.Context(), `SELECT `+listingColumns+` FROM auction_listings WHERE id = $1 FOR UPDATE`, id))
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		if listing.Status != "active" {
			return nil, preconditionError("Este anúncio não está mais à venda.")
		}
		if listing.SellerID == nil {
			return nil, preconditionError("O vendedor não existe mais: não há para quem devolver o item.")
		}
		if _, err := tx.Exec(r.Context(), `UPDATE auction_listings SET status = 'cancelled', closed_at = now() WHERE id = $1`, id); err != nil {
			return nil, err
		}
		if _, err := tx.Exec(r.Context(), `INSERT INTO mail (account_id, kind, listing_id, item_kind, item, detail) VALUES ($1, 'returned', $2, $3, $4, $5)`,
			*listing.SellerID, id, listing.Kind, listing.Item, map[string]string{"reason": "cancelled"}); err != nil {
			return nil, err
		}
		// In the seller's own activity record too, next to what the game server writes.
		if err := auditTx(r.Context(), tx, listing.SellerID, "admin", "auction.cancel", map[string]any{"listing": id, "by": "staff"}); err != nil {
			return nil, err
		}
		return map[string]any{"seller": *listing.SellerID}, nil
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---------- LGPD: the copy of a player's data and the deletion ----------

func (a *API) adminExportPlayer(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	reason := strings.TrimSpace(r.URL.Query().Get("reason"))
	if !validReason(reason) {
		a.badInput(w, "Informe o motivo (3 a 300 letras): qual pedido da pessoa?")
		return
	}
	entry := adminEntry{Action: "player.export", TargetType: "account", TargetID: idText(id), AccountID: &id, Reason: reason}
	if err := a.store.adminDo(r.Context(), s, entry, nil); err != nil {
		a.adminFail(w, err)
		return
	}
	data, err := a.store.ExportAccount(r.Context(), id)
	if err != nil {
		a.fail(w, err)
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="conta-`+idText(id)+`.json"`)
	writeJSON(w, http.StatusOK, data)
}

// adminDeletePlayer erases an account on the player's request (LGPD) when they cannot do it
// in the game. It must be confirmed by typing the username, and the player must be offline:
// the game server keeps a copy of the profile of whoever is playing and would write it back.
func (a *API) adminDeletePlayer(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Reason  string `json:"reason"`
		Confirm string `json:"confirm"`
	}
	if err := readJSON(r, &body); err != nil || !validReason(body.Reason) {
		a.badInput(w, "Informe o motivo (3 a 300 letras): qual pedido da pessoa?")
		return
	}
	entry := adminEntry{Action: "player.delete", TargetType: "account", TargetID: idText(id), AccountID: &id, Reason: strings.TrimSpace(body.Reason)}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		var username string
		var online bool
		err := tx.QueryRow(r.Context(), `SELECT username, EXISTS (SELECT 1 FROM presence WHERE account_id = $1 AND expires_at > now()) FROM accounts WHERE id = $1 FOR UPDATE`, id).Scan(&username, &online)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		if !strings.EqualFold(strings.TrimSpace(body.Confirm), username) {
			return nil, preconditionError("Digite o nome de usuário da conta para confirmar a exclusão.")
		}
		if online {
			return nil, preconditionError("O jogador está online. Suspenda a conta (ela é desconectada em segundos) e tente de novo.")
		}
		if err := deleteAccountTx(r.Context(), tx, id); err != nil {
			return nil, err
		}
		return map[string]any{"username": username}, nil
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
