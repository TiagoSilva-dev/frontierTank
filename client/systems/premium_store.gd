class_name PremiumStore
extends RefCounted

# The shop paid with the Steam Wallet (launch checklist: Steam microtransactions).
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

# Only premium cosmetics the game knows can be sold, and nothing with attributes.
static func valid(entry: Dictionary) -> bool:
	if entry.is_empty() or (entry.get("items", []) as Array).is_empty() or int(entry.get("steam_item_id", 0)) <= 0 or not entry.get("prices") is Dictionary:
		return false
	for id: Variant in entry.items:
		var def: Dictionary = Armory.definition(str(id))
		if def.is_empty() or not bool(def.get("premium", false)) or not (def.get("attrs", {}) as Dictionary).is_empty():
			return false
	return true

static func owns_all(profile: PlayerProfile, entry: Dictionary) -> bool:
	for id: Variant in entry.get("items", []):
		if not profile.has_item(str(id)):
			return false
	return true

# The reference price shown in the game (US dollars); Steam shows the final price in the
# player's currency before the purchase.
static func price_text(entry: Dictionary) -> String:
	var cents: int = int((entry.get("prices", {}) as Dictionary).get("USD", 0))
	var value: String = "%d.%02d" % [cents / 100, cents % 100]
	return ("US$ " + value.replace(".", ",")) if not Lang.is_english() else ("US$" + value)

# The product name for the Steam order, in the player's language (the server runs in
# Portuguese, the source language).
static func description(entry: Dictionary, locale: String) -> String:
	var text: String = str(entry.get("name", entry.get("sku", "")))
	if locale.begins_with("en"):
		var english: Translation = TranslationServer.get_translation_object("en")
		if english != null and String(english.get_message(text)) != "":
			text = String(english.get_message(text))
	return text
