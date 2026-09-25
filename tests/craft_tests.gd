extends SceneTree

# 0.10: random bonus attributes on gear (tiers limited by the item level), the seven
# currencies on gear and maps, their drops, the battle effects of every bonus and the
# v5 save (bonuses, bound and mirrored items, migration of v4 drops).

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

func tier_ok(mod: Dictionary, ilvl: int) -> bool:
	var def: Dictionary = Crafting.affix_def(str(mod.id))
	var span: Array = def.values[int(mod.tier) - 1]
	return int(mod.value) >= int(span[0]) and int(mod.value) <= int(span[1]) and Crafting.allowed_tiers(ilvl).has(int(mod.tier))

func run_tests() -> void:
	PlayerProfile.path_override = "user://craft_test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026

	# --- Data
	var ids: Array = Crafting.currencies().map(func(def: Dictionary) -> String: return str(def.id))
	check(ids == ["brasa", "coroa", "estrela", "tormenta", "solar", "eclipse", "espelho"], "seven currencies with their own names")
	check(Crafting.currencies().all(func(def: Dictionary) -> bool: return ResourceLoader.exists(str(def.icon)) and str(def.en) != ""), "every currency has an icon and an English name")
	check(Crafting.rules().tiers.size() == 5 and Crafting.allowed_tiers(1) == [5] and Crafting.allowed_tiers(16) == [1, 2, 3, 4, 5], "tiers F1–F5: level 1 items only roll F5, level 13+ can roll F1")
	var weapon_ids: Array = Crafting.rules().weapon.map(func(d: Dictionary) -> String: return str(d.id))
	var armor_ids: Array = Crafting.rules().armor.map(func(d: Dictionary) -> String: return str(d.id))
	check(weapon_ids == ["ataque", "dano", "critico", "pow", "pow_inicial", "poupar"] and armor_ids == ["defesa", "vida", "agilidade", "sorte", "energia", "delay", "vento", "cura"], "bonus pools per kind of piece (weapon / outfit, hat, glasses, wings)")
	check(not (weapon_ids + armor_ids).any(func(id: String) -> bool: return id.contains("raio") or id.contains("radius") or id.contains("hit")), "no bonus changes the blast radius or the hitbox")
	check(Crafting.can_have_mods("trovao") and Crafting.can_have_mods("chapeu_kabuto") and Crafting.can_have_mods("asas_fada") and not Crafting.can_have_mods("cabelo_azul") and not Crafting.can_have_mods("dom_de_anjo"), "hair colours and auxiliary items take no bonuses")

	# --- Rolling bonuses
	var counts_ok: bool = true
	var tiers_ok: bool = true
	var pools_ok: bool = true
	var best_low: int = 5
	var best_high: int = 5
	for quality: String in ["normal", "excelente", "verdadeira", "super"]:
		for i in range(60):
			var id: String = "cabeca_de_boi" if quality == "super" else ["trovao", "chapeu_coroa", "roupa_ninja"][i % 3]
			var ilvl: int = 1 if i % 2 == 0 else 16
			var mods: Array = Crafting.roll_mods({"id": id, "quality": quality, "ilvl": ilvl}, rng)
			var span: Array = {"normal": [0, 0], "excelente": [1, 2], "verdadeira": [3, 4], "super": [4, 4]}[quality]
			var seen: Dictionary = {}
			for mod: Dictionary in mods:
				seen[mod.id] = true
				tiers_ok = tiers_ok and tier_ok(mod, ilvl)
				pools_ok = pools_ok and (weapon_ids if Armory.slot_of(id) == "arma" else armor_ids).has(mod.id)
				if ilvl == 1:
					best_low = mini(best_low, int(mod.tier))
				else:
					best_high = mini(best_high, int(mod.tier))
			counts_ok = counts_ok and mods.size() >= int(span[0]) and mods.size() <= int(span[1]) and seen.size() == mods.size()
	check(counts_ok, "bonus count by quality: Normal 0, Excelente 1–2, Verdadeira 3–4, Super 4 (never repeated)")
	check(tiers_ok and pools_ok, "values stay inside their tier and the pool of the piece")
	check(best_low == 5 and best_high <= 2, "high item levels reach the best tiers (F%d), level 1 stays at F5" % best_high)

	# --- Currencies on gear
	var profile: PlayerProfile = PlayerProfile.new()
	check(profile.redeem("MOEDAS").begins_with("30 Brasas") and profile.currency_count("brasa") == 30 and profile.currency_count("espelho") == 1, "MOEDAS coupon gives every currency")
	check(profile.redeem("MOEDAS") != "Este cupom já foi usado nesta conta." and profile.currency_count("brasa") == 60, "the MOEDAS test coupon can be used again")
	var hat: Dictionary = profile.add_instance("chapeu_viking", "normal", 0, 12)
	check(hat.quality == "normal" and hat.mods.is_empty(), "a normal drop has no bonuses")
	check(profile.craft("coroa", int(hat.uid)) != "" and profile.currency_count("coroa") == 40, "a failed craft does not spend the currency")
	check(profile.craft("brasa", int(hat.uid)) == "" and hat.quality == "excelente" and hat.mods.size() == 1 and profile.currency_count("brasa") == 59, "Brasa: Normal → Excelente with 1 bonus")
	check(Armory.quality_color(hat) == Color("7ad8ff"), "gear shows its quality colour")
	check(profile.craft("brasa", int(hat.uid)) != "", "Brasa only works on Normal items")
	check(profile.craft("estrela", int(hat.uid)) == "" and hat.mods.size() == 2 and profile.craft("estrela", int(hat.uid)) != "", "Estrela adds a bonus up to the quality limit (Excelente 2)")
	check(profile.craft("coroa", int(hat.uid)) == "" and hat.quality == "verdadeira" and hat.mods.size() == 3, "Coroa: Excelente → Verdadeira with +1 bonus")
	check(profile.craft("estrela", int(hat.uid)) == "" and hat.mods.size() == 4 and profile.craft("estrela", int(hat.uid)) != "", "Verdadeira items hold up to 4 bonuses")
	var kept: Array = hat.mods.map(func(m: Dictionary) -> String: return "%s:%d" % [m.id, int(m.tier)])
	var changed: bool = false
	for i in range(6):
		var values: Array = hat.mods.map(func(m: Dictionary) -> int: return int(m.value))
		profile.craft("solar", int(hat.uid))
		changed = changed or hat.mods.map(func(m: Dictionary) -> int: return int(m.value)) != values
	check(hat.mods.map(func(m: Dictionary) -> String: return "%s:%d" % [m.id, int(m.tier)]) == kept and changed and hat.mods.all(func(m: Dictionary) -> bool: return tier_ok(m, 12)), "Solar rerolls only the values, keeping which bonuses (and tiers)")
	check(profile.craft("eclipse", int(hat.uid)) == "" and hat.mods.size() == 3, "Eclipse removes one bonus")
	var tormenta_ok: bool = true
	for i in range(8):
		tormenta_ok = tormenta_ok and profile.craft("tormenta", int(hat.uid)) == "" and hat.mods.size() >= 3 and hat.mods.size() <= 4 and hat.mods.all(func(m: Dictionary) -> bool: return armor_ids.has(m.id) and tier_ok(m, 12))
	check(tormenta_ok, "Tormenta rerolls every bonus within the quality")
	var weapon: Dictionary = profile.add_instance("trovao", "excelente", 3, 8)
	var damage_excellent: int = int(Armory.build_weapon(weapon).damage)
	weapon.mods = []
	profile.craft("coroa", int(weapon.uid))
	check(weapon.quality == "verdadeira" and int(Armory.build_weapon({"id": "trovao", "quality": "verdadeira", "level": 3}).damage) > damage_excellent and Armory.item_name(weapon).begins_with("Verdadeiro"), "a Coroa on a weapon makes it a Verdadeira (more damage)")
	var before: int = profile.inventory.size()
	check(profile.craft("espelho", int(hat.uid)) == "" and profile.inventory.size() == before + 1 and profile.currency_count("espelho") == 1, "Espelho Celeste duplicates an item")
	var copy: Dictionary = profile.inventory[-1]
	check(copy.mirrored and copy.bound and copy.mods == hat.mods and copy.uid != hat.uid, "the copy is mirrored and bound, with the same bonuses")
	check(profile.craft("tormenta", int(copy.uid)) != "" and profile.craft("espelho", int(copy.uid)) != "", "mirrored items cannot be changed or mirrored again")
	check(profile.craft("brasa", int(profile.add_instance("cabelo_roxo").uid)) != "", "currencies do not work on hair colours")

	# --- Currencies on maps
	var map: Dictionary = profile.add_map(InstanceRun.make_map("templo_sol", 9, rng, 0.0, "normal"))
	check(profile.craft_map("brasa", int(map.uid)) == "" and map.quality == "excelente" and map.mods.size() == 1, "Brasa works on maps")
	check(profile.craft_map("coroa", int(map.uid)) == "" and map.quality == "verdadeira" and map.mods.size() == 2, "Coroa raises the map quality with +1 modifier")
	profile.craft_map("estrela", int(map.uid))
	profile.craft_map("estrela", int(map.uid))
	var mod_ids: Dictionary = {}
	for mod: Dictionary in map.mods:
		mod_ids[mod.id] = true
	check(map.mods.size() == 4 and mod_ids.size() == 4 and profile.craft_map("estrela", int(map.uid)) != "", "Estrela fills a Verdadeira map up to 4 different modifiers")
	check(profile.craft_map("eclipse", int(map.uid)) == "" and map.mods.size() == 3, "Eclipse removes a map modifier")
	check(profile.craft_map("tormenta", int(map.uid)) == "" and map.mods.size() >= 3, "Tormenta rerolls the map")
	check(profile.craft_map("espelho", int(map.uid)) != "", "the Espelho Celeste only duplicates gear")
	var ranged: Dictionary = profile.add_map({"instance": "templo_sol", "level": 3, "quality": "excelente", "mods": [{"id": "enemy_hp", "value": 20}]})
	profile.add_item("solar", 20)
	var values_seen: Dictionary = {}
	for i in range(12):
		profile.craft_map("solar", int(ranged.uid))
		values_seen[int(ranged.mods[0].value)] = true
	check(ranged.mods[0].id == "enemy_hp" and values_seen.size() > 1 and values_seen.keys().all(func(v: int) -> bool: return v >= 20 and v <= 40), "Solar rerolls the map values in range")

	# --- Attributes, strengthening and battle stats
	var sword: Dictionary = profile.add_instance("quebra_tijolos", "verdadeira", 0, 16, [{"id": "ataque", "tier": 1, "value": 60}, {"id": "dano", "tier": 1, "value": 15}])
	var plain: Dictionary = {"id": "quebra_tijolos", "quality": "verdadeira", "level": 0}
	check(int(Armory.item_attrs(sword).ataque) == int(Armory.item_attrs(plain).ataque) + 60, "flat bonuses add to the item attributes")
	check(int(Armory.build_weapon(sword).damage) == roundi(int(Armory.build_weapon(plain).damage) * 1.15), "+% dano raises the weapon damage")
	sword.level = 5
	plain.level = 5
	check(int(Armory.item_attrs(sword).ataque) - int(Armory.item_attrs(plain).ataque) == 60, "strengthening raises only the base attributes, never the bonuses")
	var coat: Dictionary = profile.add_instance("roupa_samurai", "verdadeira", 0, 16, [{"id": "vida", "tier": 1, "value": 200}, {"id": "energia", "tier": 1, "value": 30}, {"id": "vento", "tier": 1, "value": 20}, {"id": "cura", "tier": 1, "value": 30}])
	check(coat.quality == "verdadeira" and coat.mods.size() == 4, "outfits keep their quality and bonuses")
	var loose: PlayerProfile = PlayerProfile.new()
	var stats_before: Dictionary = loose.stats(balance)
	var armed: Array = [sword, coat]
	var stats_after: Dictionary = Armory.character_stats(loose.level(), armed, balance)
	var plain_stats: Dictionary = Armory.character_stats(loose.level(), [plain, {"id": "roupa_samurai", "level": 0}], balance)
	check(int(stats_after.vida) == int(plain_stats.vida) + 200 and int(stats_after.energia) == int(plain_stats.energia) + 30, "life and energy bonuses reach the character sheet")
	check(int(stats_after.bonus.vento) == 20 and int(stats_after.bonus.cura) == 30 and int(stats_after.bonus.dano) == 15 and not stats_after.bonus.has("ataque"), "battle bonuses are summed apart from the four attributes")
	check(stats_before.has("bonus") and (stats_before.bonus as Dictionary).is_empty(), "no gear bonuses, no battle bonuses")

	# --- Battle effects
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var hero: Dictionary = {"name": "Nilo", "human": true, "level": 10, "arma": {"id": "quebra_tijolos", "quality": "normal", "level": 0}, "attrs": {"sorte": 1500}, "bonus": {"pow_inicial": 40, "energia": 30, "vento": 80, "cura": 30, "delay": 50, "pow": 25, "critico": 50, "poupar": 100}}
	var rival: Dictionary = {"name": "Bot", "level": 10, "arma": {"id": "quebra_tijolos", "quality": "normal", "level": 0}}
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 7, "teams": [[hero], [rival]]})
	var me: TankFighter = game.fighters[0]
	var other: TankFighter = game.fighters[1]
	check(me.pow_gauge >= 40.0 and other.pow_gauge < 40.0, "POW inicial: the battle starts with POW in the bar")
	check(me.max_energy == int(balance.energy) + me.agility / 30 + 30, "+energia per turn raises the fighter's energy")
	check(is_equal_approx(game.wind_factor(me), 0.5) and is_equal_approx(game.wind_factor(other), 1.0), "wind resistance is capped at 50%")
	check(game.healing(me, 100) == 130 and game.healing(other, 100) == 100, "+% cura raises heals received")
	for fighter in game.fighters:
		fighter.delay = 1000.0
	me.delay = 0.0
	game.begin_turn()
	game.turn_pow = true
	var boosted: Dictionary = game.compose_plan(me)
	me.bonus.pow = 0
	game.turn_pow = true
	var normal_pow: Dictionary = game.compose_plan(me)
	check(int(boosted.damage) == roundi(int(normal_pow.damage) * 1.25), "+% dano do POW raises the POW shot")
	game.turn_pow = false
	var free_uses: int = 0
	for i in range(300):
		game.turn_items.clear()
		game.energy = 240.0
		game.apply_item(me, "dmg10")
		if is_equal_approx(game.energy, 240.0):
			free_uses += 1
	check(free_uses > 90 and free_uses < 150, "skills cost nothing about 40%% of the time at the cap (%d/300)" % free_uses)
	game.turn_items.clear()
	var delay_before: float = me.delay
	game.finish_turn()
	var with_bonus: float = me.delay - delay_before
	me.bonus.erase("delay")
	for fighter in game.fighters:
		fighter.delay = 1000.0
	me.delay = 0.0
	game.begin_turn()
	game.finish_turn()
	check(is_equal_approx(with_bonus, me.delay - 50.0), "-Delay lowers the delay added each turn")
	var damages: Dictionary = {}
	for i in range(200):
		other.hp = other.max_hp
		other.shield = 1.0
		var before_hp: int = other.hp
		game.explode(me, other.center(), 200, 40.0, false, {})
		damages[before_hp - other.hp] = true
	var values: Array = damages.keys()
	values.sort()
	check(values.size() == 2 and absf(float(values[1]) / float(values[0]) - 2.0) < 0.02, "critical hits deal x1.5 plus the +% dano crítico bonus (x2.0 with +50%)")

	# --- Drops
	var free_run: InstanceRun = InstanceRun.new(balance, "templo_sol", {}, 1, [hero], null)
	var free_ok: bool = true
	for i in range(200):
		free_ok = free_ok and Crafting.roll_currency(0, free_run.rng) == "brasa"
	check(free_ok, "the free entry only drops Brasas")
	var seen_low: Dictionary = {}
	var seen_high: Dictionary = {}
	for i in range(4000):
		seen_low[Crafting.roll_currency(4, rng)] = true
		seen_high[Crafting.roll_currency(16, rng)] = true
	check(not seen_low.has("solar") and not seen_low.has("espelho") and seen_high.has("solar") and seen_high.has("espelho"), "rare currencies only on high maps (Solar from level 5, Espelho from 10)")
	var boss_ok: bool = true
	var total: int = 0
	var run: InstanceRun = InstanceRun.new(balance, "templo_sol", {"instance": "templo_sol", "level": 8, "quality": "normal", "mods": []}, 1, [hero], null)
	for i in range(300):
		boss_ok = boss_ok and run.roll_phase_currency(2).size() >= 1
		total += run.roll_phase_currency(0).size() + run.roll_phase_currency(1).size()
	check(boss_ok and total > 300 * 0.6 and total < 300 * 1.0, "every phase may drop a currency and the boss always does")
	var female: PlayerProfile = PlayerProfile.new()
	female.gender = "f"
	var gear_run: InstanceRun = InstanceRun.new(balance, "picos_gelados", {"instance": "picos_gelados", "level": 14, "quality": "normal", "mods": []}, 1, [hero], female)
	var gear_ok: bool = true
	var weapons_ok: bool = true
	for i in range(120):
		var gear: Dictionary = gear_run.gear_card()
		var def: Dictionary = Armory.cosmetic_def(str(gear.gear))
		gear_ok = gear_ok and str(def.gender) in ["u", "f"] and int(gear.ilvl) == 14 and Crafting.can_have_mods(str(gear.gear)) and gear.mods.size() >= int(Crafting.count_range(gear.quality)[0]) and gear.mods.size() <= int(Crafting.count_range(gear.quality)[1])
		var card: Dictionary = gear_run.weapon_card()
		weapons_ok = weapons_ok and card.mods.all(func(m: Dictionary) -> bool: return weapon_ids.has(m.id) and tier_ok(m, 14)) and card.mods.size() <= int(Crafting.count_range(card.quality)[1])
	check(gear_ok, "hats, glasses, wings and outfits (of the player's gender) drop with the map level")
	check(weapons_ok, "dropped weapons roll their bonuses with the map level")
	var kinds: Dictionary = {}
	for i in range(600):
		var card: Dictionary = gear_run.roll_card()
		if card.has("currency"):
			kinds["currency"] = true
		elif card.has("gear"):
			kinds["gear"] = true
	check(kinds.has("currency") and kinds.has("gear"), "reward cards include currencies and gear")
	female.pity["picos_gelados"] = 100
	var super_drop: Dictionary = gear_run.roll_super()
	check(super_drop.mods.size() == 4, "the Super Verdadeira drops with 4 bonuses")
	check((balance.rewards.pvp_cards as Array).any(func(c: Dictionary) -> bool: return c.get("currency", "") == "brasa"), "a little currency drops in PvP")

	# --- Shop, coupons and the v5 save
	profile.coins = 5000
	profile.buy("oculos_redondos")
	check(bool(profile.inventory[-1].get("bound", false)) and profile.inventory[-1].mods.is_empty(), "shop items come without bonuses and bound")
	profile.redeem("AURAS")
	check(profile.inventory.filter(func(i: Dictionary) -> bool: return i.id == "quebra_tijolos" and int(i.level) == 12).all(func(i: Dictionary) -> bool: return bool(i.get("bound", false))), "coupon items are bound")
	profile.save_profile()
	var reloaded: PlayerProfile = PlayerProfile.new()
	reloaded.load_profile()
	var hat_back: Dictionary = reloaded.find_instance(int(hat.uid))
	var copy_back: Dictionary = reloaded.find_instance(int(copy.uid))
	check(hat_back.quality == "verdadeira" and hat_back.mods == hat.mods and int(hat_back.ilvl) == 12, "gear bonuses and quality are saved")
	check(copy_back.mirrored and copy_back.bound and reloaded.currency_count("brasa") == profile.currency_count("brasa"), "mirrored/bound flags and currencies are saved")
	var legacy: Dictionary = {"version": 4, "created": true, "name": "Velho", "inventory": [{"uid": 1, "id": "trovao", "quality": "verdadeira", "level": 2, "ilvl": 9}, {"uid": 2, "id": "fogo_intenso", "quality": "excelente", "level": 0}, {"uid": 3, "id": "cabeca_de_boi", "quality": "super", "level": 0, "ilvl": 3}], "equipped": {"arma": 1}, "next_uid": 4}
	var file: FileAccess = FileAccess.open(PlayerProfile.path_override, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var old: PlayerProfile = PlayerProfile.new()
	old.load_profile()
	check(old.find_instance(1).mods.size() >= 3 and old.find_instance(1).mods.all(func(m: Dictionary) -> bool: return tier_ok(m, 9)) and old.find_instance(3).mods.size() == 4, "v4 drops get their bonuses rolled once on load")
	check(old.find_instance(2).mods.is_empty(), "v4 shop items stay without bonuses")
	var again: PlayerProfile = PlayerProfile.new()
	again.load_profile()
	check(again.find_instance(1).mods == old.find_instance(1).mods, "the migration is saved (bonuses do not change on the next load)")

	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("CRAFT RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
