class_name InstanceRun
extends RefCounted

# One trip into an instance (0.9): three phases (minions, guardian, boss) played as
# separate LocalMatch battles. The difficulty comes from the map item placed in the
# room (level 1–16, quality and random threat/reward modifiers, like PoE 2 maps) and
# from the number of players; without a map it is the free entry (level 1, low reward).
# Between phases life recovers 30%, POW is kept and the fallen come back with little
# life. Maps, currencies and gold drop as phases are won; the boss chest and the reward
# cards come at the end. Dropped weapons and gear (0.10) carry the map level as item
# level and roll their random bonuses when they drop. Offline this is local; the server
# will own every roll later.

static var _rules: Dictionary = {}

var balance: Dictionary
var instance: Dictionary
var map_item: Dictionary
var level: int = 0
var players: int = 1
var mods: Dictionary = {}
var members: Array = []
var profile: PlayerProfile
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var phase_index: int = 0
var carry: Array = []
var phases_won: int = 0
var drops: Array[Dictionary] = []
var currency_drops: Array[Dictionary] = []
var gold: int = 0
var chest: Array[Dictionary] = []
var finished: bool = false
var won: bool = false

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	return _rules

static func instance_def(id: String) -> Dictionary:
	for entry: Dictionary in rules().instances:
		if entry.id == id:
			return entry
	return rules().instances[0]

static func mod_def(id: String) -> Dictionary:
	for entry: Dictionary in rules().map_items.mods:
		if entry.id == id:
			return entry
	return {}

static func map_name(item: Dictionary) -> String:
	if item.is_empty():
		return Lang.t("Entrada livre")
	return Lang.t("Mapa: %s — Nível %d") % [Lang.t(str(instance_def(str(item.instance)).name)), int(item.level)]

static func quality_label(quality: String) -> String:
	return Armory.quality_label(quality if quality in ["excelente", "verdadeira"] else "normal")

static func quality_color(quality: String) -> Color:
	return Color({"normal": "f4ead6", "excelente": "7ad8ff", "verdadeira": "c99bff"}.get(quality, "f4ead6"))

static func mod_text(mod: Dictionary) -> String:
	var def: Dictionary = mod_def(str(mod.id))
	var text: String = Lang.t(str(def.get("text", mod.id)))
	return text % int(mod.get("value", 0)) if text.contains("%d") else text

static func map_icon(item: Dictionary) -> String:
	var path: String = "res://assets/items/maps/%s.png" % str(item.get("instance", ""))
	return path if ResourceLoader.exists(path) else "res://assets/expansion/lobby/loot_slot.png"

static func describe_map(item: Dictionary) -> Array[String]:
	# Threats first (red in the UI), then rewards.
	var lines: Array[String] = []
	for kind: String in ["threat", "reward"]:
		for mod: Dictionary in item.get("mods", []):
			if str(mod_def(str(mod.id)).get("kind", "")) == kind:
				lines.append(mod_text(mod))
	return lines

func _init(balance_data: Dictionary, instance_id: String, item: Dictionary, player_count: int, party: Array, owner: PlayerProfile = null) -> void:
	balance = balance_data
	instance = instance_def(instance_id)
	map_item = item
	level = int(item.get("level", 0))
	players = clampi(player_count, 1, 4)
	members = party.duplicate(true)
	profile = owner
	rng.randomize()
	for mod: Dictionary in item.get("mods", []):
		mods[str(mod.id)] = int(mod.get("value", 1))
	for i in range(members.size()):
		carry.append({})

# ---------- scaling ----------

func effective_level() -> int:
	return maxi(1, level)

func party(key: String) -> float:
	var list: Array = balance.party_scaling[key]
	return float(list[mini(players, list.size()) - 1])

func hp_scale() -> float:
	return pow(float(balance.map_items.hp_per_level), effective_level() - 1) * party("hp") * (1.0 + mods.get("enemy_hp", 0) / 100.0)

func damage_scale() -> float:
	return pow(float(balance.map_items.damage_per_level), effective_level() - 1) * party("damage") * (1.0 + mods.get("enemy_damage", 0) / 100.0)

func reward_scale() -> float:
	var value: float = (1.0 + float(balance.map_items.reward_per_level) * (effective_level() - 1)) * party("reward")
	return value * (float(balance.map_items.free_reward) if level == 0 else 1.0)

func xp_scale() -> float:
	return reward_scale() * (1.0 + mods.get("xp", 0) / 100.0)

func gold_scale() -> float:
	return reward_scale() * (1.0 + mods.get("gold", 0) / 100.0)

func threat_count() -> int:
	var count: int = 0
	for id: String in mods:
		if str(mod_def(id).get("kind", "")) == "threat":
			count += 1
	return count

func quantity() -> float:
	# Every threat also brings +10% item quantity, like PoE maps.
	return threat_count() * float(balance.map_items.threat_quantity) + mods.get("quantity", 0) / 100.0

func rarity() -> float:
	return mods.get("rarity", 0) / 100.0 + party("rarity")

func extra_minions() -> int:
	return int(party("extra_minions")) + (1 if mods.has("extra_minions") else 0)

func threats() -> Dictionary:
	var list: Dictionary = {}
	for id: String in ["strong_wind", "no_plane", "boss_enraged", "enemy_shield", "short_turn"]:
		if mods.has(id):
			list[id] = true
	if mods.has("low_energy"):
		list.low_energy = mods.low_energy
	return list

func turn_seconds(base: float) -> float:
	return base * (0.75 if mods.has("short_turn") else 1.0)

func enemy_entry(id: String) -> Dictionary:
	var def: Dictionary = {}
	for entry: Dictionary in balance.enemies:
		if entry.id == id:
			def = entry
	var entry: Dictionary = {"enemy": id, "name": Lang.t(str(def.get("name", id))), "level": effective_level(), "team": 1}
	entry.hp = roundi(float(def.get("hp", 500)) * hp_scale())
	entry.damage = roundi(float(def.get("damage", 100)) * damage_scale())
	entry.fury_damage = roundi(float(def.get("fury_damage", def.get("damage", 100))) * damage_scale())
	if mods.has("enemy_shield") and str(def.get("rank", "")) != "totem":
		entry.shield = 0.5
	if mods.has("boss_enraged") and str(def.get("rank", "")) == "boss":
		entry.enraged = true
	if def.has("summon"):
		entry.summon = enemy_entry(str(def.summon))
	return entry

# ---------- phases ----------

func phase_count() -> int:
	return instance.phases.size()

func current_phase() -> Dictionary:
	return instance.phases[phase_index]

func has_next_phase() -> bool:
	return phase_index + 1 < phase_count()

func phase_config(team: Array) -> Dictionary:
	var phase: Dictionary = current_phase()
	var waves: Array = []
	for wave: Array in phase.waves:
		var entries: Array = []
		for id: String in wave:
			entries.append(enemy_entry(id))
		waves.append(entries)
	# Party size and the "extra minions" threat add minions to every phase.
	for i in range(extra_minions()):
		waves[0].append(enemy_entry(str(instance.minion)))
	var first: Array = waves.pop_front()
	var players_team: Array = []
	for i in range(team.size()):
		var entry: Dictionary = team[i].duplicate(true)
		if mods.has("low_energy"):
			entry.energy_scale = 1.0 - mods.low_energy / 100.0
		if i < carry.size() and not (carry[i] as Dictionary).is_empty():
			entry.carry = carry[i]
			entry.tools = carry[i].get("tools", entry.get("tools", []))
		players_team.append(entry)
	var base_turn: float = float(balance.pve.get("turn_seconds", 20))
	return {
		"mode": "pve", "map": str(phase.map), "turn_seconds": turn_seconds(base_turn), "players": players, "threats": threats(),
		"phase": {"index": phase_index, "count": phase_count(), "name": Lang.t(str(phase.name)), "objective": str(phase.get("objective", "defeat")), "turns": int(phase.get("turns", 0)), "waves": waves, "level": level, "instance": Lang.t(str(instance.name))},
		"teams": [players_team, first],
	}

func complete_phase(game: LocalMatch) -> Dictionary:
	# Phase won: keep each player's state for the next one and roll this phase's drops.
	var report: Dictionary = {"maps": [], "gold": 0}
	var heal: float = float(balance.pve.phase_heal)
	var revive: float = float(balance.pve.revive_hp)
	var team: Array[TankFighter] = []
	for fighter in game.fighters:
		if fighter.team == 0:
			team.append(fighter)
	for i in range(mini(team.size(), carry.size())):
		var fighter: TankFighter = team[i]
		var hp: int = mini(fighter.max_hp, fighter.hp + roundi(fighter.max_hp * heal)) if fighter.hp > 0 else roundi(fighter.max_hp * revive)
		carry[i] = {"hp": hp, "pow": fighter.pow_gauge, "tools": fighter.tools.duplicate(), "aux_uses": fighter.aux_uses, "stats": fighter.stats.duplicate()}
	phases_won += 1
	var gold_list: Array = balance.pve.phase_gold
	report.gold = roundi(float(gold_list[mini(phase_index, gold_list.size() - 1)]) * gold_scale())
	gold += int(report.gold)
	report.maps = roll_phase_maps(phase_index)
	for item: Dictionary in report.maps:
		drops.append(item)
	report.currency = roll_phase_currency(phase_index)
	if profile != null:
		profile.coins += int(report.gold)
		for item: Dictionary in report.maps:
			profile.add_map(item)
		for entry: Dictionary in report.currency:
			profile.add_item(str(entry.currency))
		profile.save_profile()
	if has_next_phase():
		phase_index += 1
	return report

func roll_phase_maps(index: int) -> Array[Dictionary]:
	# Maps drop from maps: chance per phase won (the boss more), boosted by the map.
	var chances: Array = balance.map_items.drop_chance
	var chance: float = float(chances[mini(index, chances.size() - 1)]) * (1.0 + mods.get("map_chance", 0) / 100.0)
	var count: int = floori(chance) + (1 if rng.randf() < chance - floorf(chance) else 0)
	var list: Array[Dictionary] = []
	for i in range(count):
		list.append(roll_map())
	return list

func roll_phase_currency(index: int) -> Array[Dictionary]:
	# Currencies (0.10) drop from every phase won (the boss always gives one); item
	# quantity raises the count and the map level decides which ones can drop.
	var chances: Array = balance.map_items.loot.currency_chance
	var chance: float = float(chances[mini(index, chances.size() - 1)]) * (1.0 + quantity())
	var count: int = floori(chance) + (1 if rng.randf() < chance - floorf(chance) else 0)
	var list: Array[Dictionary] = []
	for i in range(count):
		var entry: Dictionary = currency_entry(Crafting.roll_currency(level, rng))
		list.append(entry)
		currency_drops.append(entry)
	return list

static func currency_entry(id: String) -> Dictionary:
	var def: Dictionary = Crafting.currency_def(id)
	return {"id": "currency_" + id, "name": Lang.t(str(def.get("name", id))), "currency": id, "amount": 1, "rarity": str(def.get("rarity", "rare")), "icon": str(def.get("icon", ""))}

func drop_level() -> int:
	if level == 0:
		return 1
	var odds: Array = balance.map_items.drop_level
	var ticket: float = rng.randf()
	var step: int = 0
	for i in range(odds.size()):
		ticket -= float(odds[i])
		if ticket <= 0.0:
			step = i
			break
	return clampi(level + step, 1, int(balance.map_items.max_level))

func roll_map(forced_level: int = -1) -> Dictionary:
	var target: String = str(instance.id)
	if rng.randf() < float(balance.map_items.other_instance):
		var pool: Array = balance.instances.map(func(entry: Dictionary) -> String: return str(entry.id))
		target = str(pool[rng.randi() % pool.size()])
	return InstanceRun.make_map(target, forced_level if forced_level > 0 else drop_level(), rng, rarity())

static func make_map(instance_id: String, map_level: int, random: RandomNumberGenerator, rarity_bonus: float = 0.0, quality: String = "") -> Dictionary:
	var data: Dictionary = rules().map_items
	var chosen: Dictionary = data.qualities[0]
	if quality != "":
		for entry: Dictionary in data.qualities:
			if entry.id == quality:
				chosen = entry
	else:
		var total: float = 0.0
		for entry: Dictionary in data.qualities:
			total += float(entry.weight) * (1.0 if entry.id == "normal" else 1.0 + rarity_bonus)
		var ticket: float = random.randf() * total
		for entry: Dictionary in data.qualities:
			ticket -= float(entry.weight) * (1.0 if entry.id == "normal" else 1.0 + rarity_bonus)
			if ticket <= 0.0:
				chosen = entry
				break
	var count: int = random.randi_range(int(chosen.mods[0]), int(chosen.mods[1]))
	var pool: Array = data.mods.duplicate()
	var rolled: Array = []
	for i in range(mini(count, pool.size())):
		var def: Dictionary = pool.pop_at(random.randi() % pool.size())
		var value: int = 1
		if def.has("range"):
			value = random.randi_range(int(def.range[0]), int(def.range[1]))
		rolled.append({"id": str(def.id), "value": value})
	return {"instance": instance_id, "level": clampi(map_level, 1, int(data.max_level)), "quality": str(chosen.id), "mods": rolled}

# ---------- the end: boss chest and reward cards ----------

func finish(victory: bool) -> Dictionary:
	# Returns the loot for the result screen: the chest (granted now) and 8 cards.
	finished = true
	won = victory
	var loot: Dictionary = {"picks": 1, "cards": [], "chest": []}
	if victory:
		# The boss phase drops like the others (its map chance is the highest).
		phases_won += 1
		var gold_list: Array = balance.pve.phase_gold
		var boss_gold: int = roundi(float(gold_list[mini(phase_index, gold_list.size() - 1)]) * gold_scale())
		gold += boss_gold
		var boss_maps: Array[Dictionary] = roll_phase_maps(phase_index)
		for item: Dictionary in boss_maps:
			drops.append(item)
		var boss_currency: Array[Dictionary] = roll_phase_currency(phase_index)
		if profile != null:
			profile.coins += boss_gold
			for item: Dictionary in boss_maps:
				profile.add_map(item)
			for entry: Dictionary in boss_currency:
				profile.add_item(str(entry.currency))
		var picks: int = int(balance.map_items.loot.boss_picks) + int(party("bonus_cards"))
		if mods.has("boss_card"):
			picks += 1
		var extra: float = quantity()
		picks += floori(extra) + (1 if rng.randf() < extra - floorf(extra) else 0)
		loot.picks = picks
		var super_drop: Dictionary = roll_super()
		if not super_drop.is_empty():
			chest.append(super_drop)
			if profile != null:
				profile.add_instance(str(super_drop.weapon), "super", 0, effective_level(), super_drop.mods)
	loot.chest = chest
	for i in range(8):
		loot.cards.append(roll_card())
	if profile != null:
		profile.save_profile()
	return loot

func super_chance() -> float:
	var data: Dictionary = balance.map_items.loot
	var base: float = float(data.free_super_chance) if level == 0 else float(data.super_chance) + float(data.super_per_level) * level
	return base * (1.0 + mods.get("super_chance", 0) / 100.0)

func roll_super() -> Dictionary:
	# Super Verdadeira: only the boss drops it. A per-instance counter guarantees one
	# after `pity` boss kills without it.
	var id: String = str(instance.id)
	var counter: int = int(profile.pity.get(id, 0)) if profile != null else 0
	var limit: int = int(balance.map_items.loot.pity)
	if rng.randf() >= super_chance() and counter + 1 < limit:
		if profile != null:
			profile.pity[id] = counter + 1
		return {}
	if profile != null:
		profile.pity[id] = 0
	var weapon: String = str(instance.loot.super)
	if rng.randf() < 0.5:
		var supers: Array = Armory.data().weapons.filter(func(def: Dictionary) -> bool: return def.get("super", false))
		weapon = str(supers[rng.randi() % supers.size()].id)
	var mods: Array = Crafting.roll_mods({"id": weapon, "quality": "super", "ilvl": effective_level()}, rng, rarity())
	return {"id": "super_" + weapon, "name": Armory.item_name({"id": weapon, "quality": "super"}), "weapon": weapon, "quality": "super", "ilvl": effective_level(), "mods": mods, "rarity": "legendary", "icon": Armory.weapon_icon(weapon)}

func roll_card() -> Dictionary:
	var data: Dictionary = balance.map_items.loot
	var pool: Array = []
	var boost: float = 1.0 + rarity()
	for card: Dictionary in balance.rewards.cards:
		var entry: Dictionary = card.duplicate()
		if entry.has("coins"):
			entry.coins = roundi(float(entry.coins) * gold_scale())
			entry.name = Lang.t("%d Moedas") % int(entry.coins)
		entry.weight = float(card.weight) * (1.0 if str(card.rarity) == "common" else boost)
		pool.append(entry)
	pool.append({"kind": "weapon", "weight": float(data.weapon_weight) * boost})
	pool.append({"kind": "gear", "weight": float(data.gear_weight) * boost})
	pool.append({"kind": "currency", "weight": float(data.currency_weight) * boost})
	pool.append({"kind": "map", "weight": float(data.map_weight) * (1.0 + mods.get("map_chance", 0) / 100.0)})
	var total: float = 0.0
	for entry: Dictionary in pool:
		total += float(entry.weight)
	var ticket: float = rng.randf() * total
	var picked: Dictionary = pool[0]
	for entry: Dictionary in pool:
		ticket -= float(entry.weight)
		if ticket <= 0.0:
			picked = entry
			break
	match str(picked.get("kind", "")):
		"weapon":
			return weapon_card()
		"gear":
			return gear_card()
		"currency":
			return currency_entry(Crafting.roll_currency(level, rng))
		"map":
			var item: Dictionary = roll_map()
			return {"id": "map", "name": map_name(item), "map": item, "rarity": "map", "icon": map_icon(item)}
	return picked

func roll_quality() -> String:
	# Verdadeira gets likelier with the map level and rarity.
	var data: Dictionary = balance.map_items.loot
	var true_chance: float = (float(data.true_chance) + float(data.true_per_level) * level) * (1.0 + rarity())
	var roll: float = rng.randf()
	return "verdadeira" if roll < true_chance else ("excelente" if roll < true_chance + float(data.excellent_chance) else "normal")

const CARD_RARITY: Dictionary = {"normal": "rare", "excelente": "epic", "verdadeira": "legendary"}

func weapon_card() -> Dictionary:
	# Instance weapons with a quality roll and their random bonuses (0.10).
	var weapons: Array = instance.loot.weapons
	var id: String = str(weapons[rng.randi() % weapons.size()])
	var quality: String = roll_quality()
	var inst: Dictionary = {"id": id, "quality": quality, "ilvl": effective_level()}
	inst.mods = Crafting.roll_mods(inst, rng, rarity())
	return {"id": "weapon_" + id, "name": Armory.item_name(inst), "weapon": id, "quality": quality, "ilvl": effective_level(), "mods": inst.mods, "rarity": CARD_RARITY[quality], "icon": Armory.weapon_icon(id)}

func gear_card() -> Dictionary:
	# 0.10: hats, glasses, wings and outfits (of the player's gender) also drop, with the
	# map level as item level, so their bonuses can reach the best tiers.
	var gender: String = profile.gender if profile != null else ""
	var pool: Array = Armory.data().cosmetics.filter(func(def: Dictionary) -> bool: return Crafting.can_have_mods(str(def.id)) and (gender == "" or str(def.gender) in ["u", gender]))
	var id: String = str(pool[rng.randi() % pool.size()].id)
	var quality: String = roll_quality()
	var inst: Dictionary = {"id": id, "quality": quality, "ilvl": effective_level()}
	inst.mods = Crafting.roll_mods(inst, rng, rarity())
	return {"id": "gear_" + id, "name": Armory.item_name(inst), "gear": id, "quality": quality, "ilvl": effective_level(), "mods": inst.mods, "rarity": CARD_RARITY[quality], "icon": Armory.icon_path(inst)}
