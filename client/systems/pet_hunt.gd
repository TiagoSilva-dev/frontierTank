class_name PetHunt
extends RefCounted

# Caçada dos Mascotes (0.20): the pets fight on their own, like an idle game. The player
# picks a zone (one per element), a difficulty tier and a team of up to 5 pets; every
# `cycle` seconds the team meets a wild group of the zone's element. Nothing here is
# real time: the profile keeps when the hunt started counting (`since`) and the number of
# encounters already settled (`n`), and each encounter is a pure function of the hunt's
# `seed` and its number. The client replays the same encounter on screen while the
# server (or the offline profile) settles the whole stretch at once when the player
# collects, so a preview and the settlement always agree.
# Time stops adding up after `cap_free` seconds (`cap_pass` with the Passe do Caçador).
# A defeated Lendário joins the player's pets for good.
#
# Numbers are in shared/balance/pets.json ("hunt"); the state kept in the profile is
# {active, zone, tier, team: [uid], since, n, seed, legend, wins: {"zone:tier": count},
# report} (see `clean_state`).

static func rules() -> Dictionary:
	return Pets.data().hunt

static func zones() -> Array:
	return Pets.elements()

static func zone_name(zone: String) -> String:
	return Lang.t(str(rules().zones[zone].name))

static func zone_art(zone: String) -> String:
	return str(rules().zones[zone].bg)

static func cycle() -> int:
	return int(rules().cycle)

static func tiers() -> int:
	return int(rules().tiers)

static func wild_level(tier: int) -> int:
	return int(rules().wild_level.base) + int(rules().wild_level.per_tier) * (tier - 1)

# ---------- state ----------

static func empty_report() -> Dictionary:
	return {"slots": 0, "wins": 0, "losses": 0, "coins": 0, "xp": 0, "eggs": {}, "captured": [], "boss_seen": 0, "boss_won": 0, "levelups": [], "full": false, "seconds": 0, "at": 0}

static func clean_report(raw: Variant) -> Dictionary:
	var result: Dictionary = empty_report()
	if not raw is Dictionary:
		return result
	for key: String in ["slots", "wins", "losses", "coins", "xp", "boss_seen", "boss_won", "seconds", "at"]:
		result[key] = maxi(0, int(raw.get(key, 0)))
	result.full = bool(raw.get("full", false))
	var eggs: Variant = raw.get("eggs", {})
	if eggs is Dictionary:
		for id: String in eggs:
			if Pets.is_egg(id):
				result.eggs[id] = maxi(0, int(eggs[id]))
	var caught: Variant = raw.get("captured", [])
	if caught is Array:
		for id: Variant in caught:
			if not Pets.species_def(str(id)).is_empty() and result.captured.size() < 60:
				result.captured.append(str(id))
	var levels: Variant = raw.get("levelups", [])
	if levels is Array:
		for entry: Variant in levels:
			if entry is Dictionary and result.levelups.size() < 10:
				result.levelups.append({"uid": int(entry.get("uid", 0)), "species": str(entry.get("species", "")), "from": int(entry.get("from", 1)), "to": int(entry.get("to", 1))})
	return result

static func clean_state(raw: Variant) -> Dictionary:
	var state: Dictionary = {"active": false, "zone": str(zones()[0].id), "tier": 1, "team": [], "since": 0, "n": 0, "seed": 1, "legend": 0, "wins": {}, "report": empty_report()}
	if not raw is Dictionary:
		return state
	var zone: String = str(raw.get("zone", state.zone))
	if not Pets.element_def(zone).is_empty():
		state.zone = zone
	state.tier = clampi(int(raw.get("tier", 1)), 1, tiers())
	var team: Variant = raw.get("team", [])
	if team is Array:
		for uid: Variant in team:
			if (uid is int or uid is float) and not state.team.has(int(uid)) and state.team.size() < int(rules().team_max):
				state.team.append(int(uid))
	state.active = bool(raw.get("active", false)) and not state.team.is_empty()
	state.since = maxi(0, int(raw.get("since", 0)))
	state.n = maxi(0, int(raw.get("n", 0)))
	state.seed = maxi(1, int(raw.get("seed", 1)))
	state.legend = maxi(0, int(raw.get("legend", 0)))
	var wins: Variant = raw.get("wins", {})
	if wins is Dictionary:
		for key: String in wins:
			state.wins[key] = maxi(0, int(wins[key]))
	state.report = clean_report(raw.get("report", {}))
	return state

static func wins_at(state: Dictionary, zone: String, tier: int) -> int:
	return int(state.wins.get("%s:%d" % [zone, tier], 0))

# The highest tier open in a zone: each one opens after `unlock_wins` victories in the
# tier below it.
static func unlocked_tier(state: Dictionary, zone: String) -> int:
	var tier: int = 1
	while tier < tiers() and wins_at(state, zone, tier) >= int(rules().unlock_wins):
		tier += 1
	return tier

static func cap_seconds(profile: PlayerProfile) -> int:
	return int(rules().cap_pass if profile.has_item(str(rules().pass_item)) else rules().cap_free)

# ---------- units ----------

static func make_unit(species: String, level: int, stars: int) -> Dictionary:
	var def: Dictionary = Pets.species_def(species)
	var rarity: int = Pets.rarity_index(str(def.rarity))
	var stats: Dictionary = rules().stats
	var mod: Dictionary = rules().element_mod.get(str(def.element), {})
	var scale: float = (1.0 + float(stats.level_scale) * (level - 1)) * (1.0 + float(stats.star_scale) * stars)
	var hp: int = maxi(1, roundi(float(stats.hp[rarity]) * scale * float(mod.get("hp", 1.0))))
	return {
		"species": species, "element": str(def.element), "rarity": rarity, "level": level, "stars": stars,
		"hp": hp, "max": hp,
		"atk": float(stats.atk[rarity]) * scale * float(mod.get("atk", 1.0)),
		"def": float(stats.def[rarity]) * scale * float(mod.get("def", 1.0)),
		"spd": float(stats.spd[rarity]) * float(mod.get("spd", 1.0)),
		"crit": float(rules().crit.base) + float(mod.get("crit", 0.0)),
		"boss": false,
	}

static func team_pets(profile: PlayerProfile, state: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for uid: Variant in state.team:
		var pet: Dictionary = profile.find_pet(int(uid))
		if not pet.is_empty():
			list.append(pet)
	return list

static func team_units(pets: Array) -> Array:
	var units: Array = []
	for pet: Dictionary in pets:
		units.append(make_unit(str(pet.species), int(pet.level), int(pet.stars)))
	return units

# ---------- the wild ----------

static func wild_species(zone: String, rarity: int) -> String:
	var wanted: String = str(Pets.rarities()[rarity].id)
	for entry: Dictionary in Pets.species_of_element(zone):
		if entry.rarity == wanted:
			return str(entry.id)
	return str(Pets.species_of_element(zone)[0].id)

# Wild stats grow with the tier on top of the level (`wild_scale` per tier).
static func _toughen(unit: Dictionary, tier: int) -> Dictionary:
	var factor: float = 1.0 + float(rules().wild_scale) * (tier - 1)
	unit.hp = roundi(float(unit.hp) * factor)
	unit.max = unit.hp
	unit.atk = float(unit.atk) * factor
	unit.def = float(unit.def) * factor
	return unit

static func roll_group(zone: String, tier: int, rng: RandomNumberGenerator, boss: bool) -> Array:
	var level: int = wild_level(tier)
	if boss:
		var unit: Dictionary = make_unit(wild_species(zone, 3), level + int(rules().boss.level_bonus), 0)
		unit.hp = roundi(float(unit.hp) * float(rules().boss.hp))
		unit.max = unit.hp
		unit.atk = float(unit.atk) * float(rules().boss.atk)
		unit.boss = true
		return [_toughen(unit, tier)]
	var weights: Array = rules().group_weights
	var ticket: float = rng.randf() * _sum(weights)
	var count: int = weights.size()
	for i in range(weights.size()):
		ticket -= float(weights[i])
		if ticket <= 0.0:
			count = i + 1
			break
	var rarity_weights: Array = []
	for i in range((rules().wild_rarity as Array).size()):
		rarity_weights.append(maxf(0.0, float(rules().wild_rarity[i]) + float(rules().wild_rarity_per_tier[i]) * (tier - 1)))
	var group: Array = []
	for i in range(count):
		var pick: float = rng.randf() * _sum(rarity_weights)
		var rarity: int = rarity_weights.size() - 1
		for j in range(rarity_weights.size()):
			pick -= float(rarity_weights[j])
			if pick <= 0.0:
				rarity = j
				break
		group.append(_toughen(make_unit(wild_species(zone, rarity), level, 0), tier))
	return group

static func _sum(list: Array) -> float:
	var total: float = 0.0
	for value: Variant in list:
		total += float(value)
	return total

# ---------- the fight ----------

# +1 when `attacker` beats `target` on the wheel, -1 when it loses, 0 otherwise.
static func wheel_edge(attacker: String, target: String) -> int:
	var wheel: Array = rules().wheel
	var a: int = wheel.find(attacker)
	var t: int = wheel.find(target)
	if a < 0 or t < 0:
		return 0
	if (a + 1) % wheel.size() == t:
		return 1
	if (t + 1) % wheel.size() == a:
		return -1
	return 0

static func living(side: Array) -> Array:
	return side.filter(func(unit: Dictionary) -> bool: return int(unit.hp) > 0)

static func _strike(attacker: Dictionary, target: Dictionary, mult: float, rng: RandomNumberGenerator, log: Array, skill: String) -> void:
	var edge: int = wheel_edge(str(attacker.element), str(target.element))
	var element_mult: float = float(rules().wheel_bonus) if edge > 0 else (float(rules().wheel_penalty) if edge < 0 else 1.0)
	var power: float = float(attacker.atk) * (1.0 + float(attacker.buff)) * mult * element_mult * rng.randf_range(0.9, 1.1)
	var crit: bool = rng.randf() < float(attacker.crit)
	if crit:
		power *= float(rules().crit.mult)
	var damage: int = maxi(1, roundi(power - float(target.def) * 0.5))
	target.hp = maxi(0, int(target.hp) - damage)
	log.append({"k": "hit", "a": int(attacker.id), "d": int(target.id), "dmg": damage, "crit": crit, "el": edge, "hp": int(target.hp), "skill": skill})
	if int(target.hp) <= 0:
		log.append({"k": "down", "u": int(target.id)})

static func _act(unit: Dictionary, allies: Array, foes: Array, rng: RandomNumberGenerator, log: Array) -> void:
	var enemies: Array = living(foes)
	if enemies.is_empty():
		return
	unit.acts = int(unit.acts) + 1
	var skill_rules: Dictionary = rules().skill
	var element: String = str(unit.element)
	if int(unit.acts) % int(skill_rules.every) != 0:
		_strike(unit, enemies[rng.randi() % enemies.size()], 1.0, rng, log, "")
		return
	var skill: Dictionary = skill_rules[element]
	var boost: float = 1.0 + float(skill_rules.rarity_scale) * int(unit.rarity)
	var skill_name: String = str(skill.name)
	match element:
		"sol":
			_strike(unit, enemies[rng.randi() % enemies.size()], float(skill.mult) * boost, rng, log, skill_name)
		"mascara":
			for i in range(2):
				enemies = living(foes)
				if not enemies.is_empty():
					_strike(unit, enemies[rng.randi() % enemies.size()], float(skill.mult) * boost, rng, log, skill_name)
		"ceu":
			for target: Dictionary in enemies:
				_strike(unit, target, float(skill.mult) * boost, rng, log, skill_name)
		"gelo":
			for ally: Dictionary in living(allies):
				var amount: int = mini(int(ally.max) - int(ally.hp), roundi(float(ally.max) * float(skill.heal) * boost))
				ally.hp = int(ally.hp) + amount
				log.append({"k": "heal", "a": int(unit.id), "d": int(ally.id), "amt": amount, "hp": int(ally.hp), "skill": skill_name})
		_:
			for ally: Dictionary in living(allies):
				ally.buff = float(skill.buff) * boost
				ally.buff_left = int(skill.rounds)
				log.append({"k": "buff", "a": int(unit.id), "d": int(ally.id), "skill": skill_name})

# Allies come first in the result ids (0..), foes start at 100. Returns {won, rounds,
# alive (how many allies survived), log}.
static func fight(team: Array, wilds: Array, rng: RandomNumberGenerator) -> Dictionary:
	var allies: Array = []
	var foes: Array = []
	for i in range(team.size()):
		var unit: Dictionary = (team[i] as Dictionary).duplicate()
		unit.hp = unit.max
		unit.id = i
		unit.side = 0
		unit.acts = 0
		unit.buff = 0.0
		unit.buff_left = 0
		allies.append(unit)
	for i in range(wilds.size()):
		var unit: Dictionary = (wilds[i] as Dictionary).duplicate()
		unit.hp = unit.max
		unit.id = 100 + i
		unit.side = 1
		unit.acts = 0
		unit.buff = 0.0
		unit.buff_left = 0
		foes.append(unit)
	var log: Array = []
	var everyone: Array = allies + foes
	var rounds: int = 0
	while rounds < int(rules().rounds_max) and not living(allies).is_empty() and not living(foes).is_empty():
		rounds += 1
		log.append({"k": "round", "n": rounds})
		var order: Array = living(everyone)
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a.spd) != float(b.spd):
				return float(a.spd) > float(b.spd)
			if int(a.side) != int(b.side):
				return int(a.side) < int(b.side)
			return int(a.id) < int(b.id))
		for unit: Dictionary in order:
			if int(unit.hp) <= 0:
				continue
			_act(unit, allies if int(unit.side) == 0 else foes, foes if int(unit.side) == 0 else allies, rng, log)
			if living(allies).is_empty() or living(foes).is_empty():
				break
		for unit: Dictionary in everyone:
			if int(unit.buff_left) > 0:
				unit.buff_left = int(unit.buff_left) - 1
				if int(unit.buff_left) == 0:
					unit.buff = 0.0
	var won: bool = living(foes).is_empty() and not living(allies).is_empty()
	return {"won": won, "rounds": rounds, "alive": living(allies).size(), "log": log}

# ---------- one encounter ----------

static func slot_rng(state: Dictionary, n: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (int(state.seed) * 1000003 + n * 7919 + 17) & 0x7fffffffffff
	return rng

static func capture_chance(rarity: int, tier: int, boss: bool) -> float:
	if boss:
		return 1.0
	var table: Dictionary = rules().capture
	return float(table[str(Pets.rarities()[rarity].id)]) * (1.0 + float(table.per_tier) * (tier - 1))

# The whole result of encounter `n`: who showed up, whether the team won, the rewards and
# the log to replay. `legend` is the count of encounters since the last Lendário.
static func slot(state: Dictionary, units: Array, n: int, legend: int) -> Dictionary:
	var rng: RandomNumberGenerator = slot_rng(state, n)
	var boss_rules: Dictionary = rules().boss
	var roll: float = rng.randf()
	var boss: bool = legend >= int(boss_rules.forced_after) or roll < float(boss_rules.chance)
	var wilds: Array = roll_group(str(state.zone), int(state.tier), rng, boss)
	var result: Dictionary = fight(units, wilds, rng)
	var out: Dictionary = {"n": n, "boss": boss, "won": bool(result.won), "wilds": wilds, "rounds": int(result.rounds), "alive": int(result.alive), "log": result.log, "coins": 0, "xp": 0, "egg": "", "captured": [], "legend": legend + 1}
	if not out.won:
		if boss:
			# The Lendário fled: it comes back after half the wait, so a team that cannot
			# beat it loses one encounter now and then, never a streak.
			out.legend = int(boss_rules.forced_after) / 2
		return out
	var reward: Dictionary = rules().reward
	var tier: int = int(state.tier)
	var xp: float = 0.0
	var coins: float = 0.0
	for wild: Dictionary in wilds:
		var rarity: int = int(wild.rarity)
		xp += (float(reward.xp_base) + float(reward.xp_per_level) * int(wild.level)) * float(reward.xp_rarity[rarity])
		coins += float(reward.coin_per_level) * int(wild.level) * float(reward.coin_rarity[rarity])
		if rng.randf() < capture_chance(rarity, tier, bool(wild.boss)):
			out.captured.append(str(wild.species))
	out.xp = roundi(xp)
	out.coins = roundi(coins)
	if rng.randf() < float(reward.egg_chance) * (1.0 + float(reward.egg_per_tier) * (tier - 1)):
		out.egg = str(Pets.element_def(str(state.zone)).egg)
	if boss:
		out.legend = 0
	return out

# ---------- a stretch of encounters ----------

static func add_slot(report: Dictionary, result: Dictionary) -> void:
	report.slots = int(report.slots) + 1
	if bool(result.boss):
		report.boss_seen = int(report.boss_seen) + 1
	if not bool(result.won):
		report.losses = int(report.losses) + 1
		return
	report.wins = int(report.wins) + 1
	report.coins = int(report.coins) + int(result.coins)
	report.xp = int(report.xp) + int(result.xp)
	if result.egg != "":
		report.eggs[result.egg] = int(report.eggs.get(result.egg, 0)) + 1
	for species: Variant in result.captured:
		report.captured.append(str(species))
		if Pets.species_def(str(species)).rarity == "lendario":
			report.boss_won = int(report.boss_won) + 1

# Encounters first..first+count-1. Returns {report, legend}.
static func run(state: Dictionary, units: Array, first: int, count: int, legend: int) -> Dictionary:
	var report: Dictionary = empty_report()
	for i in range(count):
		var result: Dictionary = slot(state, units, first + i, legend)
		legend = int(result.legend)
		add_slot(report, result)
	return {"report": report, "legend": legend}

# How many encounters the time since the hunt started adds up to (limited by the cap).
static func pending_slots(profile: PlayerProfile, now: int) -> int:
	var state: Dictionary = profile.hunt
	if not bool(state.active):
		return 0
	return mini(maxi(0, now - int(state.since)), cap_seconds(profile)) / cycle()

# Applies everything the hunt earned up to `now` to the profile and returns the report
# (also kept in profile.hunt.report). Time beyond the cap is lost; the rest of an
# unfinished encounter carries over.
static func settle(profile: PlayerProfile, now: int) -> Dictionary:
	var state: Dictionary = profile.hunt
	if not bool(state.active):
		return empty_report()
	var elapsed: int = maxi(0, now - int(state.since))
	var cap: int = cap_seconds(profile)
	var slots: int = mini(elapsed, cap) / cycle()
	var pets: Array[Dictionary] = team_pets(profile, state)
	var report: Dictionary = empty_report()
	if not pets.is_empty() and slots > 0:
		var stretch: Dictionary = run(state, team_units(pets), int(state.n), slots, int(state.legend))
		report = stretch.report
		state.legend = int(stretch.legend)
		profile.coins += int(report.coins)
		for id: String in report.eggs:
			profile.add_item(id, int(report.eggs[id]))
		for pet: Dictionary in pets:
			var before: int = int(pet.level)
			Pets.add_xp(pet, int(report.xp))
			if int(pet.level) > before:
				(report.levelups as Array).append({"uid": int(pet.uid), "species": str(pet.species), "from": before, "to": int(pet.level)})
		var kept: Array = []
		for species: Variant in report.captured:
			if profile.grant_pet(str(species)):
				kept.append(str(species))
			else:
				profile.coins += int(Pets.rarity_def(str(Pets.species_def(str(species)).rarity)).release)
				report.full = true
		report.captured = kept
		var key: String = "%s:%d" % [state.zone, state.tier]
		state.wins[key] = int(state.wins.get(key, 0)) + int(report.wins)
	state.n = int(state.n) + slots
	state.since = now if elapsed >= cap else int(state.since) + slots * cycle()
	report.seconds = mini(elapsed, cap)
	report.at = now
	state.report = report
	return report

# ---------- the analyser ----------

# What a team would do in a zone and tier: the share of encounters it wins and the
# income per hour, from `analyser_trials` fixed encounters (the same on every call).
static func analyse(units: Array, zone: String, tier: int) -> Dictionary:
	var state: Dictionary = {"zone": zone, "tier": tier, "seed": 4242}
	var trials: int = int(rules().analyser_trials)
	var wins: int = 0
	var xp: int = 0
	var coins: int = 0
	for i in range(trials):
		var result: Dictionary = slot(state, units, i, 0)
		if bool(result.won):
			wins += 1
			xp += int(result.xp)
			coins += int(result.coins)
	var boss_wins: int = 0
	for i in range(8):
		var rng: RandomNumberGenerator = slot_rng(state, 5000 + i)
		if bool(fight(units, roll_group(zone, tier, rng, true), rng).won):
			boss_wins += 1
	var per_hour: float = 3600.0 / float(cycle()) / maxf(1.0, float(trials))
	var win_rate: float = float(wins) / maxf(1.0, float(trials))
	var egg_chance: float = float(rules().reward.egg_chance) * (1.0 + float(rules().reward.egg_per_tier) * (tier - 1))
	return {"win": win_rate, "xp": roundi(xp * per_hour), "coins": roundi(coins * per_hour), "eggs": win_rate * egg_chance * 3600.0 / float(cycle()), "level": wild_level(tier), "boss": float(boss_wins) / 8.0}
