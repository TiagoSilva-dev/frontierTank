class_name PremiumStore
extends RefCounted

# The shop paid with the Steam Wallet (launch checklist: Steam microtransactions) or, on the
# web and mobile builds, with card or Pix on a Stripe page (docs/PAGAMENTOS.md).
# shared/balance/store.json lists the products: what each one delivers (cosmetics with
# `premium` in items.json: no attributes, bound, never in the gold shop or the auction),
# the item number on the Steam order and the price per wallet currency. The game server
# reads it to open an order; the client to show the Premium tab of the shop.

const PATH: String = "res://shared/balance/store.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"products": []}
	return _data

static func products() -> Array:
	return data().get("products", [])

static func product(sku: String) -> Dictionary:
	for entry: Dictionary in products():
		if str(entry.sku) == sku:
			return entry
	return {}

# What the letters of a paid order carry: each item plain and bound.
static func mail_items(entry: Dictionary) -> Array:
	var list: Array = []
	for id: Variant in entry.get("items", []):
		list.append({"id": str(id), "quality": "normal", "level": 0, "bound": true})
	return list

# The rule of gold (0.24): the shop sells appearance, never power. Only the skin and the
# hair (appearance slots) and keepsakes ("selo": the seal, the pass, the bag tabs, the
# layers of a skin) can be sold; a power slot (weapon, shirt, hat...) never. The one
# exception is the Founder Pack's Solaris, from before the rule (docs/SKINS.md, D4): a
# weapon with no attributes that a future "weapon skin" will replace.
const LEGACY_POWER: Array[String] = [FounderPack.WEAPON]

static func sellable_slot(def: Dictionary) -> bool:
	var slot: String = str(def.get("slot", ""))
	return slot in Armory.COSMETIC_SLOTS or slot == "selo" or (str(def.get("id", "")) in LEGACY_POWER)

# Only premium cosmetics the game knows can be sold, and nothing with attributes.
static func valid(entry: Dictionary) -> bool:
	if entry.is_empty() or (entry.get("items", []) as Array).is_empty() or int(entry.get("steam_item_id", 0)) <= 0 or not entry.get("prices") is Dictionary:
		return false
	for id: Variant in entry.items:
		var def: Dictionary = Armory.definition(str(id))
		if def.is_empty() or not bool(def.get("premium", false)) or not (def.get("attrs", {}) as Dictionary).is_empty() or not sellable_slot(def):
			return false
	return true

# A limited pack (the Founder Pack) stops selling after `sale_until` (YYYY-MM-DD, empty =
# no end date yet). Players who bought it keep everything.
static func on_sale(entry: Dictionary, today: String = "") -> bool:
	var until: String = str(entry.get("sale_until", ""))
	if until == "":
		return true
	var now: String = today if today != "" else Time.get_date_string_from_system()
	return now <= until

static func owns_all(profile: PlayerProfile, entry: Dictionary) -> bool:
	for id: Variant in entry.get("items", []):
		if not profile.has_item(str(id)):
			return false
	return true

# A bundle (the season pack) is not sold on top of what the player already has: they buy the
# missing skins one by one, so nobody pays twice for the same skin.
static func overlaps(profile: PlayerProfile, entry: Dictionary) -> bool:
	if not bool(entry.get("bundle", false)):
		return false
	for id: Variant in entry.get("items", []):
		if profile.has_item(str(id)):
			return true
	return false

# The small tag on a card: what kind of product it is.
static func kind_label(entry: Dictionary) -> String:
	if str(entry.get("section", "")) != "skins":
		return Lang.t("CONVENIÊNCIA")
	var first: Dictionary = Armory.definition(str((entry.get("items", [""]) as Array)[0]))
	match str(first.get("rarity", "")):
		"lendaria":
			return Lang.t("LENDÁRIA")
		"epica":
			return Lang.t("ÉPICA")
	return Lang.t("SKIN")

# The reference price shown in the game (US dollars); Steam shows the final price in the
# player's currency before the purchase.
static func price_text(entry: Dictionary) -> String:
	var cents: int = int((entry.get("prices", {}) as Dictionary).get("USD", 0))
	var value: String = "%d.%02d" % [cents / 100, cents % 100]
	return ("US$ " + value.replace(".", ",")) if not Lang.is_english() else ("US$" + value)

# Outside Steam (web, mobile) the shop sells in reais, by card or Pix on a Stripe page.
static func price_text_brl(entry: Dictionary) -> String:
	var cents: int = int((entry.get("prices", {}) as Dictionary).get("BRL", 0))
	return "R$ %d,%02d" % [cents / 100, cents % 100]

# The price shown on a card: dollars as a reference on Steam, reais everywhere else.
static func price_label(entry: Dictionary, via_steam: bool) -> String:
	return price_text(entry) if via_steam else price_text_brl(entry)

# Anyone online can buy: with the Steam overlay on Steam, with card or Pix elsewhere.
static func can_buy(app: Object) -> bool:
	return bool(app.online)

static func buy_label(via_steam: bool) -> String:
	return Lang.t("COMPRAR NA STEAM") if via_steam else Lang.t("COMPRAR")

static func buy_hint(via_steam: bool) -> String:
	return Lang.t("Abre a janela de compra da Steam. O Passe chega pelo Correio.") if via_steam else Lang.t("Abre a página de pagamento (cartão ou Pix). O Passe chega pelo Correio.")

# The product name for the Steam order, in the player's language (the server runs in
# Portuguese, the source language).
static func description(entry: Dictionary, locale: String) -> String:
	var text: String = str(entry.get("name", entry.get("sku", "")))
	if locale.begins_with("en"):
		var english: Translation = TranslationServer.get_translation_object("en")
		if english != null and String(english.get_message(text)) != "":
			text = String(english.get_message(text))
	return text
