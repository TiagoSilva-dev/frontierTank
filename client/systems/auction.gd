class_name Auction
extends RefCounted

# Leilão (0.12): the game's rules for trading items and maps between players
# (shared/balance/items.json → auction). The game server runs them; the Go API keeps the
# listed items in custody and moves items and currencies in PostgreSQL transactions.
#   - What can be sold: gear that dropped in an instance (it has an item level) and
#     instance maps, when not bound (shop, coupons, Espelho Celeste copies, the starter
#     weapon and Super Verdadeiras that were equipped) and not equipped.
#   - Prices in Solares and/or Estrelas; 12, 24 or 48 h; buy at once (no bids yet).
#   - Currency sinks: a listing fee in gold (by duration) and a commission on the sale,
#     5% of each currency rounded down, kept by the auction.
#   - The item bought and the seller's currencies arrive by mail (Correio).
# Also the texts every screen shows: prices, names, time left and the mail lines.

const SLOTS: Array[String] = ["arma", "roupa", "chapeu", "oculos", "asas", "mapa"]
const QUALITIES: Array[String] = ["normal", "excelente", "verdadeira", "super"]
const SORTS: Array[String] = ["recent", "price", "level"]

static func rules() -> Dictionary:
	return Armory.data().auction

static func hours_options() -> Array[int]:
	var list: Array[int] = []
	for value: Variant in rules().hours:
		list.append(int(value))
	return list

# Gold to list for that many hours; -1 when it is not one of the durations.
static func fee_for(hours: int) -> int:
	var index: int = hours_options().find(hours)
	return int(rules().fee_coins[index]) if index >= 0 else -1

# Kept by the auction from each currency of the price.
static func commission(amount: int) -> int:
	return floori(maxi(0, amount) * float(rules().commission))

static func max_listings() -> int:
	return int(rules().max_listings)

static func max_price() -> int:
	return int(rules().max_price)

static func per_page() -> int:
	return int(rules().per_page)

# ---------- what can be sold ----------

# Why this piece of gear cannot be listed ("" when it can).
static func item_reason(profile: PlayerProfile, inst: Dictionary) -> String:
	if inst.is_empty():
		return Lang.t("Item não encontrado.")
	if profile.is_equipped(int(inst.uid)):
		return Lang.t("Tire o item antes de anunciar.")
	if bool(inst.get("bound", false)):
		return Lang.t("Itens vinculados não vão ao leilão.")
	if int(inst.get("ilvl", 0)) <= 0 or not Crafting.can_have_mods(str(inst.id)):
		return Lang.t("Só equipamentos que caíram nas instâncias vão ao leilão.")
	return ""

static func map_reason(item: Dictionary) -> String:
	if item.is_empty():
		return Lang.t("Mapa não encontrado.")
	if bool(item.get("bound", false)):
		return Lang.t("Mapas vinculados não vão ao leilão.")
	return ""

static func price_reason(solar: int, estrela: int) -> String:
	if solar < 0 or estrela < 0 or solar + estrela <= 0:
		return Lang.t("Defina o preço em Solares e/ou Estrelas.")
	if solar > max_price() or estrela > max_price():
		return Lang.t("O preço máximo é %d de cada moeda.") % max_price()
	return ""

# Everything a new listing needs, checked in order: the item, the price, the duration
# and the gold of the fee. "" when it can be listed.
static func listing_reason(profile: PlayerProfile, kind: String, uid: int, solar: int, estrela: int, hours: int) -> String:
	var reason: String = ""
	if kind == "item":
		reason = item_reason(profile, profile.find_instance(uid))
	elif kind == "map":
		reason = map_reason(profile.find_map(uid))
	else:
		reason = Lang.t("Item não encontrado.")
	if reason == "":
		reason = price_reason(solar, estrela)
	if reason == "" and fee_for(hours) < 0:
		reason = Lang.t("Escolha a duração do anúncio.")
	if reason == "" and profile.coins < fee_for(hours):
		reason = Lang.t("A taxa do anúncio é de %d moedas.") % fee_for(hours)
	return reason

# The fields the auction searches by, with the item itself.
static func fields(kind: String, item: Dictionary) -> Dictionary:
	var entry: Dictionary = {"kind": kind, "item": item.duplicate(true), "mods": []}
	for mod: Dictionary in item.get("mods", []):
		entry.mods.append(str(mod.id))
	if kind == "map":
		entry.merge({"slot": "mapa", "item_id": str(item.instance), "quality": str(item.quality), "item_level": int(item.level), "strengthen": 0})
	else:
		entry.merge({"slot": Armory.slot_of(str(item.id)), "item_id": str(item.id), "quality": str(item.quality), "item_level": Crafting.item_level(item), "strengthen": int(item.get("level", 0))})
	return entry

# Takes the item out of the profile and charges the fee (the listing takes custody of
# it). Returns what `put_back` needs to undo it if the auction refuses.
static func take(profile: PlayerProfile, kind: String, uid: int, hours: int) -> Dictionary:
	var item: Dictionary = (profile.find_instance(uid) if kind == "item" else profile.find_map(uid)).duplicate(true)
	if kind == "item":
		profile.remove_instance(uid)
	else:
		profile.remove_map(uid)
	var fee: int = fee_for(hours)
	profile.coins -= fee
	return {"kind": kind, "item": item, "fee": fee}

static func put_back(profile: PlayerProfile, taken: Dictionary) -> void:
	if str(taken.kind) == "item":
		profile.inventory.append(taken.item)
	else:
		profile.maps.append(taken.item)
	profile.next_uid = maxi(profile.next_uid, int(taken.item.uid) + 1)
	profile.coins += int(taken.fee)

# ---------- mail ----------

# Puts what came by mail into the profile. Returns what `undo_mail` needs.
static func grant_mail(profile: PlayerProfile, mail: Dictionary) -> Dictionary:
	var undo: Dictionary = {"uids": [], "maps": [], "items": {}, "coins": 0}
	var item: Variant = mail.get("item")
	if item is Dictionary:
		if str(mail.get("item_kind", "")) == "map":
			var added_map: Dictionary = profile.receive_map(item)
			if not added_map.is_empty():
				undo.maps.append(int(added_map.uid))
		else:
			var added: Dictionary = profile.receive_instance(item)
			if not added.is_empty():
				undo.uids.append(int(added.uid))
	var bundle: Variant = mail.get("currencies", {})
	if bundle is Dictionary:
		for id: Variant in bundle:
			var amount: int = int(bundle[id])
			if Crafting.is_currency(str(id)) and amount > 0:
				profile.add_item(str(id), amount)
				undo.items[str(id)] = int(undo.items.get(str(id), 0)) + amount
	var coins: int = maxi(0, int(mail.get("coins", 0)))
	profile.coins += coins
	undo.coins = coins
	return undo

static func undo_mail(profile: PlayerProfile, undo: Dictionary) -> void:
	for uid: Variant in undo.uids:
		profile.remove_instance(int(uid))
	for uid: Variant in undo.maps:
		profile.remove_map(int(uid))
	for id: String in undo.items:
		profile.items[id] = maxi(0, profile.currency_count(id) - int(undo.items[id]))
	profile.coins = maxi(0, profile.coins - int(undo.coins))

# ---------- searching ----------

# A search filter from the network, with only known fields and sane values.
static func clean_filter(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var filter: Dictionary = {"sort": "recent", "page": 0, "per_page": per_page()}
	var slot: String = str(source.get("slot", ""))
	if slot in SLOTS:
		filter.slot = slot
	var quality: String = str(source.get("quality", ""))
	if quality in QUALITIES:
		filter.quality = quality
	for key: String in ["item_id", "mod"]:
		var text: String = str(source.get(key, "")).substr(0, 64)
		if RegEx.create_from_string("^[a-z0-9_]+$").search(text) != null:
			filter[key] = text
	for key: String in ["min_level", "max_level", "min_strengthen", "page"]:
		var value: Variant = source.get(key, 0)
		if (value is int or value is float) and int(value) > 0:
			filter[key] = clampi(int(value), 0, 999)
	for key: String in ["max_solar", "max_estrela"]:
		var value: Variant = source.get(key)
		if (value is int or value is float) and int(value) >= 0:
			filter[key] = mini(int(value), max_price())
	if str(source.get("sort", "")) in SORTS:
		filter.sort = str(source.sort)
	return filter

# The last sales of items like this one (same item and quality, close item level; maps
# of the same instance and quality, close level).
static func history_query(kind: String, item: Dictionary) -> Dictionary:
	var entry: Dictionary = fields(kind, item)
	return {"kind": kind, "item_id": entry.item_id, "quality": entry.quality, "min_level": maxi(1, int(entry.item_level) - 2), "max_level": int(entry.item_level) + 2, "limit": 5}

# ---------- texts ----------

static func price_text(solar: int, estrela: int) -> String:
	var parts: Array[String] = []
	if solar > 0:
		parts.append((Lang.t("%d Solar") if solar == 1 else Lang.t("%d Solares")) % solar)
	if estrela > 0:
		parts.append((Lang.t("%d Estrela") if estrela == 1 else Lang.t("%d Estrelas")) % estrela)
	return " + ".join(parts) if not parts.is_empty() else "—"

static func listing_price(listing: Dictionary) -> String:
	return price_text(int(listing.get("price_solar", 0)), int(listing.get("price_estrela", 0)))

static func item_name(kind: String, item: Dictionary) -> String:
	return InstanceRun.map_name(item) if kind == "map" else Armory.item_name(item)

static func item_color(kind: String, item: Dictionary) -> Color:
	return InstanceRun.quality_color(str(item.get("quality", "normal"))) if kind == "map" else Armory.quality_color(item)

static func item_icon(kind: String, item: Dictionary) -> Texture2D:
	return load(InstanceRun.map_icon(item)) if kind == "map" else Armory.load_icon(item)

# Bonus lines (gear) or threat and reward lines (maps).
static func item_lines(kind: String, item: Dictionary) -> Array[String]:
	return InstanceRun.describe_map(item) if kind == "map" else Crafting.describe(item)

static func time_left(seconds: int) -> String:
	if seconds <= 0:
		return Lang.t("encerrado")
	if seconds >= 3600:
		return Lang.t("%d h") % int(seconds / 3600)
	return Lang.t("%d min") % maxi(1, int(seconds / 60))

static func time_ago(seconds: int) -> String:
	if seconds < 3600:
		return Lang.t("há %d min") % maxi(1, int(seconds / 60))
	if seconds < 86400:
		return Lang.t("há %d h") % int(seconds / 3600)
	return Lang.t("há %d dias") % int(seconds / 86400)

# The heading of a mail: what happened and to which item.
static func mail_title(mail: Dictionary) -> String:
	var detail: Dictionary = mail.get("detail", {}) if mail.get("detail") is Dictionary else {}
	match str(mail.get("kind", "")):
		"sale":
			var sold: Variant = detail.get("item")
			var name_text: String = item_name(str(detail.get("item_kind", "item")), sold) if sold is Dictionary else Lang.t("item")
			return Lang.t("Vendido no leilão: %s") % name_text
		"purchase":
			return Lang.t("Comprado no leilão: %s") % item_name(str(mail.get("item_kind", "item")), mail.get("item", {}))
		"returned":
			var name_text: String = item_name(str(mail.get("item_kind", "item")), mail.get("item", {}))
			return (Lang.t("Anúncio vencido: %s") if str(detail.get("reason", "")) == "expired" else Lang.t("Anúncio cancelado: %s")) % name_text
	return Lang.t("Correio")

# What a mail brings, in one line.
static func mail_contents(mail: Dictionary) -> String:
	var parts: Array[String] = []
	var bundle: Dictionary = mail.get("currencies", {}) if mail.get("currencies") is Dictionary else {}
	if int(bundle.get("solar", 0)) > 0 or int(bundle.get("estrela", 0)) > 0:
		parts.append(price_text(int(bundle.get("solar", 0)), int(bundle.get("estrela", 0))))
	if mail.get("item") is Dictionary:
		parts.append(item_name(str(mail.get("item_kind", "item")), mail.item))
	if int(mail.get("coins", 0)) > 0:
		parts.append(Lang.t("%d moedas") % int(mail.coins))
	var detail: Dictionary = mail.get("detail", {}) if mail.get("detail") is Dictionary else {}
	if str(mail.get("kind", "")) == "sale" and detail.get("fee") is Dictionary:
		var fee: Dictionary = detail.fee
		if int(fee.get("solar", 0)) + int(fee.get("estrela", 0)) > 0:
			parts.append(Lang.t("comissão %s") % price_text(int(fee.get("solar", 0)), int(fee.get("estrela", 0))))
	return "  •  ".join(parts)

# Server error codes of the auction, as texts for the player (Portuguese keys).
const ERRORS: Dictionary = {
	"listing_gone": "Este anúncio não está mais à venda.",  # i18n
	"price_changed": "O preço deste anúncio mudou. Atualize a busca.",  # i18n
	"own_listing": "Você não pode comprar o seu próprio anúncio.",  # i18n
	"not_yours": "Este anúncio não é seu.",  # i18n
	"too_many_listings": "Você chegou ao limite de anúncios ao mesmo tempo.",  # i18n
	"mail_gone": "Esta carta já foi recebida.",  # i18n
}

static func error_text(code: String) -> String:
	return str(ERRORS.get(code, "Servidor indisponível. Tente de novo."))
