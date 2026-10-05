extends SceneTree

# 0.31: the PvE gear (docs/GEAR.md) and the shop's new tabs. Six slots (shirt, trousers, hat,
# glasses, ring, amulet; the wings left the drops in 0.32, see wings_tests) in four rarities (Comum, Raro, Épico, Lendário) that only drop in
# instances; the better the map, the likelier the better rarity (never a guarantee); the art, the
# rarity glow and the shop's tabs and pager.

var failures: int = 0
var checks: int = 0
var balance: Dictionary

const SLOTS: Array[String] = ["camisa", "calca", "chapeu", "oculos", "anel", "amuleto"]
const RARITIES: Array[String] = ["comum", "raro", "epico", "lendario"]

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func total_attrs(def: Dictionary) -> int:
	var total: int = int(def.get("hp", 0)) / 10
	for key: String in def.attrs:
		total += int(def.attrs[key])
	return total

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://gear_test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	test_data()
	test_art()
	test_odds()
	test_drops()
	test_rules()
	test_glow()
	await test_shop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("GEAR RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# ---------- the items ----------

func test_data() -> void:
	check(Armory.data().rarities.map(func(r: Dictionary) -> String: return str(r.id)) == RARITIES, "four rarities: comum, raro, épico, lendário")
	check(Armory.rarity_label("lendario") == "Lendário" and Armory.rarity_color("lendario") != Armory.rarity_color("comum"), "a rarity has a name and a colour")
	var pve: Array = Armory.data().cosmetics.filter(func(def: Dictionary) -> bool: return bool(def.get("pve", false)))
	var names: Dictionary = {}
	var shape_ok: bool = true
	for def: Dictionary in pve:
		names[str(def.name)] = true
		shape_ok = shape_ok and bool(def.get("drop_only", false)) and str(def.slot) in SLOTS and str(def.gender) == "u" and RARITIES.has(str(def.get("rarity", ""))) and not bool(def.get("premium", false)) and not (def.attrs as Dictionary).is_empty()
	check(shape_ok, "every PvE piece drops only, is unisex, has a rarity, a worn slot and attributes")
	check(names.size() == pve.size(), "every PvE piece has its own name")
	# Four pieces (one per rarity) in every slot, at least: the new line.
	for slot: String in SLOTS:
		for rarity: String in RARITIES:
			var found: Array = pve.filter(func(def: Dictionary) -> bool: return str(def.slot) == slot and str(def.rarity) == rarity)
			check(not found.is_empty(), "%s has a %s piece to drop" % [slot, rarity])
	# The better the rarity, the more the piece gives (the new line in each slot).
	var newest: Array = pve.filter(func(def: Dictionary) -> bool: return not (str(def.id) in ["camisa_celeste", "calca_celeste", "anel_solar", "amuleto_celeste"]))
	for slot: String in SLOTS:
		var line: Array = RARITIES.map(func(rarity: String) -> int: return total_attrs(newest.filter(func(def: Dictionary) -> bool: return str(def.slot) == slot and str(def.rarity) == rarity)[0]))
		check(line[0] < line[1] and line[1] < line[2] and line[2] < line[3], "%s: attributes grow with the rarity %s" % [slot, str(line)])
	var prices: Array = RARITIES.map(func(rarity: String) -> int: return int(newest.filter(func(def: Dictionary) -> bool: return str(def.rarity) == rarity)[0].price))
	check(prices[0] < prices[1] and prices[1] < prices[2] and prices[2] < prices[3], "the better the rarity, the more it sells for")
	for old: String in ["camisa_celeste", "calca_celeste", "anel_solar", "amuleto_celeste"]:
		check(Armory.item_rarity(old) == "raro" and Armory.is_pve_gear(old), "%s joined the PvE pool as Raro" % old)
	check(Armory.item_rarity("camisa_algodao") == "comum" and not Armory.is_pve_gear("camisa_algodao"), "shop gear is Comum and not PvE")
	check(Armory.item_rarity("quebra_tijolos") == "" and Armory.item_rarity("roupa_samurai") == "" and Armory.item_rarity("cabelo_azul") == "" and Armory.item_rarity("dom_de_anjo") == "", "weapons, skins, hair and auxiliary items have no rarity")
	for def: Dictionary in pve.filter(func(d: Dictionary) -> bool: return str(d.slot) == "amuleto"):
		check(int(def.get("hp", 0)) > 0, "%s (amulet) gives life" % def.id)

func test_art() -> void:
	var pve: Array = Armory.data().cosmetics.filter(func(def: Dictionary) -> bool: return bool(def.get("pve", false)))
	var fit: Variant = JSON.parse_string(FileAccess.get_file_as_string(LookRig.FIT_PATH))
	var missing: Array = []
	for def: Dictionary in pve:
		var id: String = str(def.id)
		if not ResourceLoader.exists(Armory.icon_path({"id": id})):
			missing.append(id + ":icon")
		match str(def.slot):
			"chapeu", "oculos":
				for view: String in ["front", "side"]:
					if not ResourceLoader.exists(Armory.cosmetic_art(str(def.art), view)):
						missing.append("%s:%s" % [id, view])
					if (fit as Dictionary).get(str(def.art), {}).get(view, {}).is_empty():
						missing.append("%s:fit_%s" % [id, view])
	check(missing.is_empty(), "every PvE piece has its art and fit %s" % [missing])
	# Icons are drawn big enough to be pretty in the bag and the shop.
	var small: Array = []
	for def: Dictionary in pve:
		if str(def.slot) in ["camisa", "calca", "anel", "amuleto"] and not str(def.id).ends_with("_celeste") and str(def.id) != "anel_solar":
			var icon: Texture2D = load(Armory.icon_path({"id": def.id}))
			if icon.get_width() < 96 or icon.get_height() < 96:
				small.append(def.id)
	check(small.is_empty(), "jewellery and armour icons are 96x96 %s" % [small])

# ---------- the chance of each rarity by map level ----------

func test_odds() -> void:
	var loot: Dictionary = balance.map_items.loot
	var sums_ok: bool = true
	var chances: Dictionary = {}
	for level in range(1, 17):
		var odds: Dictionary = InstanceRun.gear_rarity_odds(loot, level)
		var sum: float = 0.0
		for id: String in odds:
			sum += float(odds[id])
		sums_ok = sums_ok and absf(sum - 1.0) < 0.0001 and odds.keys() == RARITIES
		chances[level] = odds
	check(sums_ok, "the four chances add up to 1 on every map level")
	var rising: bool = true
	for rarity: String in ["raro", "epico", "lendario"]:
		for level in range(2, 17):
			rising = rising and float(chances[level][rarity]) > float(chances[level - 1][rarity])
	check(rising, "the higher the map, the likelier a Raro, an Épico or a Lendário")
	var falling: bool = true
	for level in range(2, 17):
		falling = falling and float(chances[level]["comum"]) < float(chances[level - 1]["comum"])
	check(falling, "the higher the map, the less often the piece is Comum")
	check(float(chances[1]["comum"]) > 0.6 and float(chances[1]["lendario"]) < 0.01, "a level 1 map gives mostly Comum and almost never a Lendário")
	check(float(chances[16]["lendario"]) > 0.05 and float(chances[16]["lendario"]) < 0.15 and float(chances[16]["epico"]) > 0.15, "a level 16 map gives a Lendário now and then, never a sure thing")
	check(float(chances[16]["lendario"]) > 10.0 * float(chances[1]["lendario"]), "the best map makes a Lendário more than ten times likelier than the first")
	var boosted: Dictionary = InstanceRun.gear_rarity_odds(loot, 8, 0.5)
	check(float(boosted["epico"]) > float(chances[8]["epico"]) and float(boosted["comum"]) < float(chances[8]["comum"]), "a map with +50% item rarity pushes the pieces up")
	check(InstanceRun.gear_rarity_odds(loot, 0).hash() == InstanceRun.gear_rarity_odds(loot, 1).hash(), "the free entry rolls like level 1")

func make_run(level: int, gender: String = "") -> InstanceRun:
	var hero: Dictionary = {"name": "Nilo", "human": true, "level": 10, "arma": {"id": "quebra_tijolos", "quality": "normal", "level": 0}, "attrs": {}, "bonus": {}}
	var owner: PlayerProfile = PlayerProfile.new()
	owner.gender = gender if gender != "" else "m"
	return InstanceRun.new(balance, "picos_gelados", {"instance": "picos_gelados", "level": level, "quality": "normal", "mods": []}, 1, [hero], owner)

func test_drops() -> void:
	var tally: Dictionary = {}
	var all_pve: bool = true
	var faces_ok: bool = true
	var slots_seen: Dictionary = {}
	var mods_ok: bool = true
	for level: int in [1, 16]:
		var run: InstanceRun = make_run(level)
		run.rng.seed = 3100 + level
		var counts: Dictionary = {"comum": 0, "raro": 0, "epico": 0, "lendario": 0, "aux": 0}
		for i in range(4000):
			var card: Dictionary = run.gear_card()
			var id: String = str(card.gear)
			if Armory.kind_of(id) == "aux":
				counts.aux += 1
				continue
			var rarity: String = Armory.item_rarity(id)
			counts[rarity] += 1
			all_pve = all_pve and Armory.is_pve_gear(id)
			faces_ok = faces_ok and str(card.rarity) == str(Armory.RARITY_CARDS[rarity])
			slots_seen[Armory.slot_of(id)] = true
			mods_ok = mods_ok and int(card.ilvl) == level and card.mods.size() <= int(Crafting.count_range(str(card.quality))[1])
		tally[level] = counts
	check(all_pve, "instance gear is always a PvE piece (never a shop piece)")
	check(faces_ok, "the reward card shows the rarity of the piece")
	check(mods_ok, "dropped gear carries the map level as item level and valid bonuses")
	check(slots_seen.size() == SLOTS.size() and not slots_seen.has("asas"), "every one of the six slots drops, and the wings do not")
	var low: Dictionary = tally[1]
	var high: Dictionary = tally[16]
	check(int(low.comum) > int(low.raro) and int(low.raro) > int(low.epico) and int(low.epico) > int(low.lendario), "on a level 1 map the rarer, the rarer to see (%s)" % str(low))
	check(int(high.lendario) > 5 * maxi(1, int(low.lendario)) and int(high.epico) > 3 * int(low.epico) and int(high.comum) < int(low.comum), "a level 16 map drops much better gear (%s)" % str(high))
	var seen_aux: bool = int(low.aux) > 300 and int(low.aux) < 700
	check(seen_aux, "about one gear card in eight is an auxiliary item (%d of 4000)" % int(low.aux))
	# The player's gender never blocks a piece: all of them are unisex.
	var female: InstanceRun = make_run(10, "f")
	female.rng.seed = 5
	var ids: Dictionary = {}
	for i in range(1500):
		ids[str(female.gear_card().gear)] = true
	check(ids.size() >= 28, "a player gets any of the PvE pieces (%d different in 1500 cards)" % ids.size())
	# Nothing is guaranteed: even 16 level-16 cards in a row are not all Lendário (bounded, seeded).
	var run16: InstanceRun = make_run(16)
	run16.rng.seed = 99
	var legendary_in_row: int = 0
	var longest: int = 0
	for i in range(3000):
		var id: String = str(run16.gear_card().gear)
		if Armory.item_rarity(id) == "lendario":
			legendary_in_row += 1
			longest = maxi(longest, legendary_in_row)
		else:
			legendary_in_row = 0
	check(longest < 8, "no streak of Lendário: the drop is a chance, not a rule (longest run %d)" % longest)
	# Monsters drop gear too (split in items.json).
	var mob: InstanceRun = make_run(12)
	mob.rng.seed = 8
	var stub: TankFighter = TankFighter.new()
	stub.rank = "minion"
	var kinds: Dictionary = {"gear": 0, "weapon": 0, "stone": 0, "currency": 0}
	for i in range(8000):
		for entry: Dictionary in mob.roll_mob_drop(stub, false):
			if entry.has("gear"):
				kinds.gear += 1
			elif entry.has("weapon"):
				kinds.weapon += 1
			elif entry.has("currency"):
				kinds.currency += 1
			else:
				kinds.stone += 1
	stub.free()
	check(int(kinds.gear) > 20 and int(kinds.weapon) > 20 and int(kinds.stone) > int(kinds.currency), "monsters drop stones most, then currencies, and sometimes a weapon or a piece of gear %s" % str(kinds))
	check(absf(float(kinds.gear) / float(kinds.weapon) - 1.0) < 0.3, "gear and weapons drop from monsters about equally")

# ---------- rules ----------

func test_rules() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	profile.coins = 999999
	var refused: bool = true
	for id: String in ["camisa_dragao", "anel_dragao", "camisa_celeste", "chapeu_couro", "amuleto_osso"]:
		refused = refused and profile.buy(id) != "" and not profile.has_item(id)
	check(refused and profile.coins == 999999, "a PvE piece cannot be bought with gold, not even by calling the operation")
	check(profile.buy("camisa_guerra") == "" and profile.has_item("camisa_guerra"), "shop gear is still bought with gold")
	var coupon: PlayerProfile = PlayerProfile.new()
	coupon.redeem("TESTARTUDO")
	check(coupon.has_item("camisa_dragao") and coupon.has_item("anel_arcano") and coupon.has_item("amuleto_osso"), "the test coupon gives the PvE pieces")
	# They are worn like any gear, and the strongest set is much stronger than the shop's.
	var worn: PlayerProfile = PlayerProfile.new()
	for id: String in ["camisa_dragao", "calca_dragao", "chapeu_dragao", "oculos_dragao", "asas_dragao", "anel_dragao", "amuleto_dragao"]:
		var inst: Dictionary = worn.add_instance(id)
		check(worn.equip(int(inst.uid)) == "", "%s can be worn" % id)
	var bare: Dictionary = Armory.character_stats(1, [], balance)
	var legendary: Dictionary = Armory.character_stats(1, worn.equipped_list(), balance)
	check(int(legendary.vida) == int(bare.vida) + 430 and int(legendary.extra.defesa) > 200 and int(legendary.extra.ataque) > 80, "a Lendário set adds its life and attributes %s" % str(legendary.extra))
	check(int(legendary.extra.defesa) < 400 and int(legendary.extra.ataque) < 400, "and stays inside the damage and defence curves")
	# Wearing the dragon wings (appearance only since 0.32, they add nothing above) and helm shows them on the look.
	var look: Dictionary = worn.look()
	check(look.wings == "asas_dragao" and look.hat == "chapeu_dragao" and look.glasses == "oculos_dragao", "the wings, helm and goggles show on the character")
	# Bots never wear a PvE piece.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 31
	var bots_ok: bool = true
	for i in range(400):
		var loadout: Dictionary = Armory.random_loadout(rng, 10 + i % 30, "f" if i % 2 == 0 else "m", "")
		bots_ok = bots_ok and loadout.look.hat not in ["chapeu_dragao", "chapeu_couro", "chapeu_aco_azul", "chapeu_arcano"] and loadout.look.glasses not in ["oculos_aviador", "oculos_cristal", "oculos_arcano", "oculos_dragao"]
	check(bots_ok, "bots never wear PvE gear")
	# A piece keeps its rarity through the save and any quality.
	var saved: PlayerProfile = PlayerProfile.new()
	var kept: Dictionary = saved.add_instance("anel_arcano", "verdadeira", 0, 12, [{"id": "ataque", "tier": 3, "value": 30}])
	var back: PlayerProfile = PlayerProfile.new()
	back.load_data(saved.to_data())
	var again: Dictionary = back.find_instance(int(kept.uid))
	check(again.id == "anel_arcano" and again.quality == "verdadeira" and again.mods.size() == 1 and Armory.item_rarity("anel_arcano") == "epico", "a PvE ring keeps its quality and bonuses through the save")
	check(Armory.item_attrs(again).ataque == int(Armory.cosmetic_def("anel_arcano").attrs.ataque) + 30, "its base attributes and bonus add up")

func test_glow() -> void:
	var plain: Dictionary = {"id": "camisa_couro", "quality": "normal"}
	var rare: Dictionary = {"id": "camisa_aco_azul", "quality": "normal"}
	var epic_fine: Dictionary = {"id": "camisa_arcana", "quality": "excelente"}
	var legendary: Dictionary = {"id": "camisa_dragao", "quality": "normal"}
	var common_fine: Dictionary = {"id": "camisa_couro", "quality": "excelente"}
	check(Armory.glow_color(plain).a == 0.0 and Armory.glow_life(plain) == 0, "a Comum Normal piece has no glow")
	check(Armory.glow_color(rare) == Armory.rarity_color("raro") and Armory.glow_life(rare) == 0, "a Raro piece glows in its colour")
	check(Armory.glow_color(epic_fine) == Armory.rarity_color("epico") and Armory.quality_gem(epic_fine) == Armory.quality_color(epic_fine) and Armory.glow_life(epic_fine) == 1, "an Épico Excelente glows purple with a quality gem and breathes")
	check(Armory.glow_color(legendary) == Armory.rarity_color("lendario") and Armory.glow_life(legendary) == 2, "a Lendário shimmers")
	check(Armory.glow_color(common_fine) == Armory.quality_color(common_fine), "a Comum Excelente keeps the glow of its quality")
	check(Armory.name_color(plain) == Color("f4ead6") and Armory.name_color(legendary) == Armory.rarity_color("lendario"), "names take the colour of the glow")
	var weapon: Dictionary = {"id": "quebra_tijolos", "quality": "verdadeira", "level": 3}
	check(Armory.glow_color(weapon) == Armory.quality_color(weapon) and Armory.glow_life(weapon) == 0 and Armory.glow_life({"id": "cabeca_de_boi", "quality": "super"}) == 2, "weapons keep their quality glow, the Super shimmers")
	# The Mochila cell draws it.
	var cell: BagSlot = BagSlot.new()
	cell.size = Vector2(64, 64)
	cell.show_entry({"key": "uid:1", "inst": legendary})
	check(cell.rarity == Armory.rarity_color("lendario") and cell.shimmer and not cell.breathe, "the bag cell glows and shimmers for a Lendário")
	cell.show_entry({"key": "uid:2", "inst": {"id": "camisa_arcana", "quality": "normal"}})
	check(cell.breathe and not cell.shimmer, "and only breathes for an Épico")
	cell.show_entry({"key": "uid:3", "inst": plain})
	check(cell.rarity.a == 0.0, "and is plain for a Comum Normal piece")
	cell.free()
	# The tooltip names the rarity.
	var tip: ItemTooltip = ItemTooltip.new()
	root.add_child(tip)
	var owner: PlayerProfile = PlayerProfile.new()
	tip.show_entry({"key": "uid:1", "inst": {"uid": 1, "id": "anel_dragao", "quality": "excelente", "level": 0, "mods": []}}, owner, balance)
	var texts: Array[String] = []
	var stack: Array[Node] = [tip]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is RichTextLabel:
			texts.append((node as RichTextLabel).get_parsed_text())
		stack.append_array(node.get_children())
	check(texts.any(func(t: String) -> bool: return t.contains("Lendário") and t.contains("Excelente") and t.contains("Anel")), "the tooltip says Lendário • Excelente • Anel")
	# A map shows the chance of each rarity, and a better map shows better numbers.
	var seen_odds: Dictionary = {}
	for level: int in [1, 16]:
		tip.show_entry({"key": "map:1", "icon": "res://assets/expansion/lobby/loot_slot.png", "name": "Mapa", "map": {"instance": "templo_sol", "level": level, "quality": "normal", "mods": []}}, owner, balance)
		var lines: Array[String] = []
		var queue: Array[Node] = [tip]
		while not queue.is_empty():
			var node: Node = queue.pop_back()
			if node is RichTextLabel:
				lines.append((node as RichTextLabel).get_parsed_text())
			queue.append_array(node.get_children())
		seen_odds[level] = "\n".join(lines)
	check(seen_odds[1].contains("CHANCE DE EQUIPAMENTO") and seen_odds[16].contains("Lendário"), "a map tooltip lists the chance of each gear rarity")
	var map_low: Dictionary = InstanceRun.map_gear_odds({"instance": "templo_sol", "level": 1, "mods": []})
	var map_boost: Dictionary = InstanceRun.map_gear_odds({"instance": "templo_sol", "level": 1, "mods": [{"id": "rarity", "value": 50}]})
	check(float(map_boost.epico) > float(map_low.epico), "a map with the item rarity modifier shows the boosted chances")
	tip.queue_free()

# ---------- the shop ----------

func test_shop() -> void:
	AuthClient.config_path = "user://gear_test_online.cfg"
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(3):
		await process_frame
	var shop: ShopScreen = ShopScreen.new()
	shop.app = app
	app.ui.add_child(shop)
	await process_frame
	# Every tab has its button, wholly inside the window, with room for its text, none on another.
	var window: Rect2 = Rect2(40, 24, 1200, 672)
	var rects: Array[Rect2] = []
	var tabs_ok: bool = true
	var fits: bool = true
	for entry: Array in ShopScreen.TABS:
		var button: Button = shop.find_child("Tab_" + str(entry[1]), true, false)
		tabs_ok = tabs_ok and button != null
		if button == null:
			continue
		var rect: Rect2 = Rect2(button.position, button.size)
		tabs_ok = tabs_ok and window.encloses(rect)
		fits = fits and button.get_minimum_size().x <= button.size.x + 0.5 and button.size.x >= 120.0
		for other: Rect2 in rects:
			tabs_ok = tabs_ok and not other.intersects(rect)
		rects.append(rect)
	check(tabs_ok and rects.size() == ShopScreen.TABS.size(), "every shop tab is on screen and none overlaps another")
	check(fits, "every tab is wide enough for its text (no tab grew past its box)")
	var rows: Dictionary = {}
	for rect: Rect2 in rects:
		rows[snappedf(rect.position.y, 1.0)] = true
	check(rows.size() == 2 and rects.all(func(r: Rect2) -> bool: return r.size.y >= 32.0), "the tabs sit in two rows of fingertip-friendly height")
	# The cards stay inside the panel and above the pager.
	shop.select_tab("arma")
	await process_frame
	var panel: Rect2 = ShopScreen.GRID_PANEL
	var cards_ok: bool = true
	var lowest: float = 0.0
	for child in shop.contents.get_children():
		if child is Button and str(child.name).begins_with("Shop_"):
			var card_rect: Rect2 = Rect2(child.position, child.size)
			cards_ok = cards_ok and panel.encloses(card_rect)
			lowest = maxf(lowest, card_rect.end.y)
	check(cards_ok and lowest > 0.0, "the item cards stay inside the panel")
	# The pager is centred under the cards and keeps its distance from the frame and the cards.
	var back: Button = shop.find_child("PagePrev", true, false)
	var next: Button = shop.find_child("PageNext", true, false)
	var counter: Label = shop.find_child("PageCounter", true, false)
	var middle: float = (back.position.x + next.position.x + next.size.x) / 2.0
	check(absf(middle - panel.get_center().x) < 3.0, "the pager is centred under the cards (%.1f vs %.1f)" % [middle, panel.get_center().x])
	check(panel.end.x - (next.position.x + next.size.x) >= 40.0 and back.position.x - panel.position.x >= 40.0, "the pager is far from the frame")
	check(back.position.y - lowest >= 12.0 and panel.end.y - (back.position.y + back.size.y) >= 8.0, "the pager has room above and below")
	check(back.size.x >= 48.0 and next.size.x >= 48.0 and counter.text == "1/2", "the buttons are big and the weapons need two pages")
	check(back.disabled and not next.disabled, "on the first page 'previous' is greyed out")
	shop.turn_page(1)
	await process_frame
	back = shop.find_child("PagePrev", true, false)
	next = shop.find_child("PageNext", true, false)
	check(next.disabled and not back.disabled and (shop.find_child("PageCounter", true, false) as Label).text == "2/2", "on the last page 'next' is greyed out")
	# A purchase message takes the hint's place and goes away with the next click.
	shop.select_tab("chapeu")
	shop.message = "Comprado! Veja na Mochila."
	shop.build()
	await process_frame
	var seen: bool = false
	var stack: Array[Node] = [shop.contents]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label and (node as Label).text == "Comprado! Veja na Mochila.":
			seen = true
		stack.append_array(node.get_children())
	check(seen, "the purchase message shows in the fitting column")
	shop.select_tab("calca")
	check(shop.message == "", "the message goes away on the next click")
	# The shop never lists the PvE gear, on any tab.
	var listed: bool = false
	for entry: Array in ShopScreen.TABS:
		shop.tab = str(entry[1])
		for def: Dictionary in shop.items():
			if def.has("id") and Armory.is_pve_gear(str(def.id)):
				listed = true
	check(not listed, "the shop sells no PvE gear")
	app.queue_free()
	await process_frame
	if FileAccess.file_exists(AuthClient.config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthClient.config_path))
