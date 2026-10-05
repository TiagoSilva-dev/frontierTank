extends SceneTree

# 0.32: the wings (docs/GEAR.md, "Asas") are sold for money. The eight pairs are premium
# appearance: no attributes, no bonuses, never dropped, never bought with coins, delivered by the
# Correio. The slot joined skin and hair among the appearance slots, so the rule of gold covers it.

const WINGS: Array[String] = ["asas_pardal", "asas_anjo", "asas_fada", "asas_demonio", "asas_cristal", "asas_fenix", "asas_arcanas", "asas_dragao"]
const RARITY: Dictionary = {"asas_pardal": "comum", "asas_anjo": "raro", "asas_fada": "raro", "asas_demonio": "raro", "asas_cristal": "raro", "asas_fenix": "epico", "asas_arcanas": "epico", "asas_dragao": "lendario"}
const PRICES_BRL: Dictionary = {"comum": 1490, "raro": 2490, "epico": 3990, "lendario": 5990}

var failures: int = 0
var checks: int = 0
var balance: Dictionary

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://wings_test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	test_items()
	test_rule_of_gold()
	test_store()
	test_no_drops()
	test_profile()
	test_bots()
	await test_shop()
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("WINGS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# ---------- the items ----------

func test_items() -> void:
	var found: Array = Armory.data().cosmetics.filter(func(def: Dictionary) -> bool: return str(def.slot) == "asas")
	var ids: Array = found.map(func(def: Dictionary) -> String: return str(def.id))
	ids.sort()
	var expected: Array = WINGS.duplicate()
	expected.sort()
	check(ids == expected, "the game has these eight pairs of wings to wear (the Aurora wings are a keepsake of the skin)")
	var shape: bool = true
	var art: Array = []
	for def: Dictionary in found:
		var id: String = str(def.id)
		shape = shape and bool(def.get("premium", false)) and (def.attrs as Dictionary).is_empty() and not def.has("drop_only") and not def.has("pve") and str(def.gender) == "u" and int(def.price) == 0 and str(def.get("rarity", "")) == str(RARITY[id])
		for view: String in ["wing", "front", "side", "icon"]:
			if not ResourceLoader.exists(Armory.cosmetic_art(str(def.art), view)):
				art.append("%s:%s" % [id, view])
		var root: Array = def.get("root", [])
		var wing: Texture2D = load(Armory.cosmetic_art(str(def.art), "wing"))
		if wing == null or root.size() != 2 or float(root[0]) < 0.0 or float(root[0]) > wing.get_width() or float(root[1]) < 0.0 or float(root[1]) > wing.get_height():
			art.append(id + ":root")
	check(shape, "every pair is premium, unisex, free of attributes, not a drop, and keeps the rarity of its art")
	check(art.is_empty(), "every pair has its art and the root of the wing inside the picture %s" % [art])
	check(Armory.item_rarity("asas_dragao") == "lendario" and Armory.item_rarity("asas_pardal") == "comum" and Armory.item_rarity("roupa_samurai") == "", "wings keep their rarity (name colour, glow, tag); skins still have none")

func test_rule_of_gold() -> void:
	check("asas" in Armory.COSMETIC_SLOTS and not "asas" in Armory.POWER_SLOTS, "the wings slot is an appearance slot")
	var power_free: bool = true
	var zero: bool = true
	for id: String in WINGS:
		power_free = power_free and not Crafting.can_have_mods(id) and not Armory.can_strengthen(id)
		var attrs: Dictionary = Armory.item_attrs({"id": id, "quality": "verdadeira", "level": 9, "mods": []})
		zero = zero and attrs.values().all(func(value: Variant) -> bool: return int(value) == 0) and Armory.item_hp({"id": id}) == 0
	check(power_free, "wings take no bonuses and no strengthening")
	check(zero, "wings give no attribute, at any quality or level")
	check(not "asas" in (Armory.data().affixes.slots as Array) and not "asas" in (Armory.data().strengthen.slots as Array), "the Ferreiro and the coins skip them")
	check(Auction.clean_filter({"slot": "asas"}).get("slot", "") == "", "the auction no longer has a wings filter")

# ---------- the store ----------

func test_store() -> void:
	var products: Array = PremiumStore.products().filter(func(entry: Dictionary) -> bool: return PremiumStore.is_wings_product(entry))
	check(products.size() == WINGS.size(), "every pair of wings is on sale (%d)" % products.size())
	var ids: Dictionary = {}
	var numbers: Dictionary = {}
	var shape: bool = true
	var prices: bool = true
	var tiers: bool = true
	for entry: Dictionary in products:
		var id: String = str((entry.items as Array)[0])
		ids[id] = true
		numbers[int(entry.steam_item_id)] = true
		shape = shape and PremiumStore.valid(entry) and not PremiumStore.is_pet_product(entry) and (entry.items as Array).size() == 1 and str(entry.sku) == id and str(entry.name) == str(Armory.definition(id).name)
		prices = prices and int(entry.prices.BRL) == int(PRICES_BRL[str(RARITY[id])])
		# The other currencies follow the table of the pets with the same price in reais.
		var twin: Array = PremiumStore.products().filter(func(other: Dictionary) -> bool: return PremiumStore.is_pet_product(other) and int(other.prices.BRL) == int(entry.prices.BRL))
		tiers = tiers and not twin.is_empty() and var_to_str(entry.prices) == var_to_str(twin[0].prices)
		check(PremiumStore.kind_label(entry) == Armory.rarity_label(str(RARITY[id])).to_upper(), "%s shows its rarity on the card" % id)
	check(shape, "every pair is a valid product of its own, named after the item")
	check(ids.size() == WINGS.size() and ids.keys().all(func(id: Variant) -> bool: return WINGS.has(str(id))), "one product per pair")
	var all_numbers: Dictionary = {}
	for entry: Dictionary in PremiumStore.products():
		all_numbers[int(entry.steam_item_id)] = true
	check(numbers.size() == products.size() and all_numbers.size() == PremiumStore.products().size(), "every product keeps a Steam number of its own")
	check(prices, "a pair costs the price of its rarity: R$ 14,90 / 24,90 / 39,90 / 59,90")
	check(tiers, "and every wallet currency follows the same table as the pets")
	# Paid, bound, delivered by the Correio, and the profile says it owns them.
	var dragon: Dictionary = PremiumStore.product("asas_dragao")
	var mail: Array = PremiumStore.mail_items(dragon)
	check(mail.size() == 1 and str(mail[0].id) == "asas_dragao" and bool(mail[0].bound), "the order delivers one bound pair")
	var profile: PlayerProfile = PlayerProfile.new()
	profile.created = true
	check(not PremiumStore.owns_all(profile, dragon), "a newcomer can buy them")
	var undo: Dictionary = Auction.grant_mail(profile, {"kind": "store", "item_kind": "item", "item": mail[0], "detail": {"provider": "stripe"}})
	check(profile.has_item("asas_dragao") and PremiumStore.owns_all(profile, dragon), "the claimed wings are in the bag and the shop says so")
	var inst: Dictionary = profile.inventory.filter(func(entry: Dictionary) -> bool: return entry.id == "asas_dragao")[0]
	check(bool(inst.get("bound", false)) and profile.equip(int(inst.uid)) == "" and profile.look().wings == "asas_dragao", "they are bound, can be worn and show on the character")
	Auction.undo_mail(profile, undo)
	check(not profile.has_item("asas_dragao"), "undoing a claim takes them back")

# ---------- drops ----------

func test_no_drops() -> void:
	check(not "asas" in (balance.map_items.loot.gear_slots as Array) and (balance.map_items.loot.gear_slots as Array).size() == 6, "the chest rolls six slots, none of them wings")
	var any_pool: bool = false
	for rarity: String in ["comum", "raro", "epico", "lendario"]:
		any_pool = any_pool or not InstanceRun.gear_pool(rarity, "asas", "").is_empty() or InstanceRun.gear_pool(rarity, "", "").any(func(def: Dictionary) -> bool: return str(def.slot) == "asas")
	check(not any_pool, "no wings sit in the pool of PvE pieces")
	var hero: Dictionary = {"name": "Nilo", "human": true, "level": 10, "arma": {"id": "quebra_tijolos", "quality": "normal", "level": 0}, "attrs": {}, "bonus": {}}
	var owner: PlayerProfile = PlayerProfile.new()
	var seen: Dictionary = {}
	for level: int in [1, 16]:
		var run: InstanceRun = InstanceRun.new(balance, "picos_gelados", {"instance": "picos_gelados", "level": level, "quality": "normal", "mods": []}, 1, [hero], owner)
		run.rng.seed = 3200 + level
		for i in range(3000):
			var card: Dictionary = run.gear_card()
			seen[Armory.slot_of(str(card.gear))] = true
	check(not seen.has("asas") and seen.has("anel") and seen.has("camisa"), "3,000 chest cards on two maps never held wings (and the other slots still do)")

# ---------- the profile ----------

func test_profile() -> void:
	var gold: PlayerProfile = PlayerProfile.new()
	gold.coins = 999999
	var refused: bool = true
	for id: String in WINGS:
		refused = refused and gold.buy(id) != "" and not gold.has_item(id)
	check(refused and gold.coins == 999999, "no wings can be bought with coins, not even the four of the old shop")
	var coupon: PlayerProfile = PlayerProfile.new()
	coupon.redeem("TESTARTUDO")
	check(WINGS.all(func(id: String) -> bool: return coupon.has_item(id)), "the test coupon gives the eight pairs")
	# Every pair worn changes no attribute.
	var bare: Dictionary = Armory.character_stats(10, [], balance)
	var unchanged: bool = true
	for id: String in WINGS:
		unchanged = unchanged and var_to_str(Armory.character_stats(10, [{"id": id, "quality": "normal", "level": 0}], balance)) == var_to_str(bare)
	check(unchanged, "wearing wings changes no attribute, life or energy")
	# A save from before: strengthened, crafted and quality-rolled wings read back plain.
	var old: PlayerProfile = PlayerProfile.new()
	old.load_data({"version": 12, "name": "Antigo", "created": true, "next_uid": 5, "coins": 10,
		"inventory": [{"uid": 1, "id": "asas_fenix", "quality": "verdadeira", "level": 7, "ilvl": 12, "mods": [{"id": "agilidade", "tier": 1, "value": 30}]}],
		"equipped": {"asas": 1}})
	var kept: Dictionary = old.find_instance(1)
	check(str(kept.quality) == "normal" and (kept.mods as Array).is_empty(), "an old save reads wings as Normal and without bonuses")
	check(old.equipped.get("asas", -1) == 1 and old.look().wings == "asas_fenix", "and they stay worn and drawn")
	var extra: Dictionary = Armory.character_stats(10, [kept], balance).extra
	check(extra.values().all(func(value: Variant) -> bool: return int(value) == 0), "with nothing left of the old attributes %s" % str(extra))

# ---------- bots ----------

func test_bots() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 32
	var worn: int = 0
	var valid: bool = true
	for i in range(600):
		var loadout: Dictionary = Armory.random_loadout(rng, 10 + i % 30, "f" if i % 2 == 0 else "m", "")
		var wings: String = str(loadout.look.wings)
		if wings != "":
			worn += 1
			valid = valid and WINGS.has(wings)
	check(worn > 100 and valid, "bots still wear wings (%d of 600) and only the shop's" % worn)

# ---------- the shop ----------

func test_shop() -> void:
	AuthClient.config_path = "user://wings_test_online.cfg"
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(3):
		await process_frame
	var shop: ShopScreen = ShopScreen.new()
	shop.app = app
	app.ui.add_child(shop)
	await process_frame
	shop.select_tab("asas")
	await process_frame
	var listed: Array = shop.items()
	check(listed.size() == WINGS.size() and listed.all(func(entry: Dictionary) -> bool: return PremiumStore.is_wings_product(entry)), "the Asas tab lists the eight products")
	check(listed.size() <= ShopScreen.PER_PAGE, "all of them fit on one page")
	var card: Node = shop.find_child("Premium_asas_pardal", true, false)
	var buy: Button = shop.find_child("Buy_asas_pardal", true, false)
	check(card != null and buy != null, "each pair has a card with its buy button")
	var other: Array = []
	for tab: String in ["premium", "pet"]:
		shop.tab = tab
		other.append_array(shop.items().filter(func(entry: Dictionary) -> bool: return PremiumStore.is_wings_product(entry)))
	check(other.is_empty(), "the Premium and Mascotes tabs hold no wings")
	var gold: bool = false
	for entry: Array in ShopScreen.TABS:
		shop.tab = str(entry[1])
		for def: Dictionary in shop.items():
			if def.has("id") and str(def.get("slot", "")) == "asas":
				gold = true
	check(not gold, "no tab sells wings for coins")
	shop.tab = "asas"
	check(shop.hint_text() == shop.wings_hint() and shop.wings_hint().contains("aparência"), "the Asas tab explains they are appearance only")
	app.queue_free()
	await process_frame
	if FileAccess.file_exists(AuthClient.config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthClient.config_path))
