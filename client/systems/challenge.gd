class_name Challenge
extends RefCounted

# The daily challenge (0.22): the same battle for everyone on a given UTC day, with the same
# map, seed, weapon and stats (nobody's gear counts), scored by a pure function of the final
# state. The battle runs on this computer in lockstep through a LocalHost, which records the
# intents; online the server re-runs that replay on a ReplayRunner and takes the score from
# its own copy, so a score cannot be invented. The kinds and numbers are in
# shared/balance/challenge.json.

const PATH: String = "res://shared/balance/challenge.json"
static var _data: Dictionary = {}
# Tests move the clock (seconds added to the real time).
static var clock_offset: int = 0

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_offset

# Days since the epoch: the challenge's id (0 for the first day; before it also 0).
static func day_id(timestamp: int = -1) -> int:
	var at: int = timestamp if timestamp >= 0 else now()
	var epoch: int = floori(Time.get_unix_time_from_datetime_string(str(data().epoch)) / 86400.0)
	return maxi(0, floori(at / 86400.0) - epoch)

static func seconds_left(timestamp: int = -1) -> int:
	var at: int = timestamp if timestamp >= 0 else now()
	return 86400 - posmod(at, 86400)

# ---------- the day's challenge ----------

static func kind_def(id: String) -> Dictionary:
	for entry: Dictionary in data().kinds:
		if str(entry.id) == id:
			return entry
	return {}

# What defines the day: the kind, the weapon, the map and the battle's seed. Deterministic.
static func spec_for(day: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("gustfire-challenge-%d" % day)
	var kinds: Array = data().kinds
	var kind: Dictionary = kinds[day % kinds.size()]
	var weapons: Array = data().weapons
	var maps: Array = []
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json")).maps:
		if not bool(entry.get("pve_only", false)):
			maps.append(str(entry.id))
	return {"day": day, "kind": str(kind.id), "weapon": str(weapons[rng.randi() % weapons.size()]), "map": str(maps[rng.randi() % maps.size()]), "seed": rng.randi() % 1000000000, "turns": int(kind.turns), "medals": kind.medals}

static func weapon_entry(weapon: String) -> Dictionary:
	return {"id": weapon, "quality": "excelente", "level": 3}

# The battle of the day for a player (`name` and `gender` are only for the nameplate and
# the sprite): the same simulation for everybody.
static func config(day: int, player_name: String = "Jogador", gender: String = "m") -> Dictionary:
	var spec: Dictionary = spec_for(day)
	var level: int = int(data().level)
	var me: Dictionary = {"name": player_name, "gender": gender, "human": true, "level": level, "arma": weapon_entry(str(spec.weapon)), "tools": ["", "", ""]}
	var foes: Array = []
	var goal: bool = false
	var kind: Dictionary = kind_def(str(spec.kind))
	match str(spec.kind):
		"duelo":
			foes.append({"name": Lang.t("Rival do Dia"), "gender": "m", "level": level, "arma": weapon_entry(str(spec.weapon))})
		_:
			goal = true
			var number: int = 0
			for hp: Variant in kind.target_hp:
				number += 1
				foes.append({"enemy": "boneco_treino", "name": Lang.t("Alvo %d") % number, "title": Lang.t("Alvo"), "hp": int(hp), "level": 1})
	return {"mode": "challenge", "challenge": true, "day": day, "map": str(spec.map), "seed": int(spec.seed), "turn_seconds": int(data().turn_seconds), "lockstep": true, "local": 0, "max_turns": int(spec.turns), "totem_goal": goal, "teams": [[me], foes]}

# The battle as the player runs it on this computer (the same plus what is only for show).
static func local_config(day: int, profile: PlayerProfile, balance: Dictionary) -> Dictionary:
	var result: Dictionary = config(day, profile.player_name, profile.gender)
	result.hosted = true
	result.teams[0][0].look = Armory.look_for(profile.gender, [{"id": str(result.teams[0][0].arma.id), "level": 3}])
	return result

# ---------- score ----------

# The score of a finished battle: {score, won, turns, medal (0-3), detail}.
static func score(game: LocalMatch) -> Dictionary:
	var spec: Dictionary = spec_for(int(game.config_day))
	var me: TankFighter = game.fighters[0]
	var foes: Array = game.fighters.filter(func(f: TankFighter) -> bool: return f.team == 1)
	var turns: int = me.turns_started
	var cap: int = int(spec.turns)
	var foe_max: int = 0
	var foe_lost: int = 0
	var down: int = 0
	for foe: TankFighter in foes:
		foe_max += foe.max_hp
		foe_lost += foe.max_hp - maxi(0, foe.hp)
		if foe.hp <= 0:
			down += 1
	var points: int = 0
	var won: bool = game.winner_team == 0
	match str(spec.kind):
		"duelo":
			if won:
				points = 2000 + roundi(1000.0 * float(maxi(0, me.hp)) / float(maxi(1, me.max_hp))) + maxi(0, cap - turns) * 60
			else:
				points = roundi(1500.0 * float(foe_lost) / float(maxi(1, foe_max)))
		_:
			points = down * 1000 + roundi(400.0 * float(foe_lost) / float(maxi(1, foe_max)))
			if won:
				points += maxi(0, cap - turns) * 300
	var medal: int = 0
	for i in range(3):
		if points >= int(spec.medals[i]):
			medal = i + 1
	return {"score": points, "won": won, "turns": turns, "medal": medal, "down": down, "targets": foes.size()}

static func medal_name(medal: int) -> String:
	return [Lang.t("Sem medalha"), Lang.t("Bronze"), Lang.t("Prata"), Lang.t("Ouro")][clampi(medal, 0, 3)]

static func medal_color(medal: int) -> Color:
	return [Color("8a94a6"), Color("c98a4b"), Color("c8d4e0"), Color("ffd04a")][clampi(medal, 0, 3)]

# ---------- the day's reward ----------

static func reward_text() -> String:
	var reward: Dictionary = data().reward
	return Lang.t("%d moedas") % int(reward.coins) + ", " + Lang.t("%d EXP") % int(reward.exp)
