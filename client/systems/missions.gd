class_name MissionsBoard
extends RefCounted

# Contracts (`profile.missions`), four tracks (the numbers and the lists are in
# shared/balance/missions.json):
#  * "Primeiros passos" (`starter`, 0.21): a one-time checklist for new characters that nudges
#    them through the game. It never resets and has its own bonus.
#  * Daily contracts: `daily_count` drawn from `daily_pool` for each UTC day (seeded by the
#    day, so everyone gets the same ones, with at most `per_category` of a kind). The state
#    is at the top level (`active`, `progress`, `claimed`, `daily_bonus`).
#  * Weekly contracts (`weekly`): `weekly_count` of `weekly_pool` per week (UTC, Monday to
#    Sunday), with larger targets and rewards.
#  * The login streak (`streak`, 0.22): claim once a day; consecutive days climb a ladder of
#    seven rewards (it starts over after a missed day).
# Progress comes from `progress_match` (settled battles, offline and on the server) and
# `note_op` (profile operations); both run the same code on the client and the server. A
# mission waits for an *event* ("pvp_win", "damage", "hatch"...), and the same event moves
# every track that has a mission for it.

const PATH: String = "res://shared/balance/missions.json"
static var _data: Dictionary = {}
# Tests move the clock (seconds added to the real time).
static var clock_offset: int = 0

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_offset

static func day_id(timestamp: int = -1) -> int:
	var at: int = timestamp if timestamp >= 0 else now()
	return floori(at / 86400.0)

static func seconds_until_reset(timestamp: int = -1) -> int:
	var at: int = timestamp if timestamp >= 0 else now()
	return 86400 - posmod(at, 86400)

# The week (Monday to Sunday, UTC) a day belongs to; unix day 0 was a Thursday.
static func week_id(timestamp: int = -1) -> int:
	return floori(float(day_id(timestamp) + 3) / 7.0)

static func seconds_until_week(timestamp: int = -1) -> int:
	var at: int = timestamp if timestamp >= 0 else now()
	return ((week_id(at) + 1) * 7 - 3) * 86400 - at

# ---------- definitions ----------

static func starter_defs() -> Array:
	return data().get("starter", [])

static func pool(kind: String) -> Array:
	return data().get("weekly_pool" if kind == "weekly" else "daily_pool", [])

# The missions of a track that are in play: the starter list, or the ones drawn for the
# current day or week (in the order they were drawn).
static func defs_of(state: Dictionary, kind: String) -> Array:
	if kind == "starter":
		return starter_defs()
	var active: Array = state.active if kind == "daily" else state.weekly.active
	var found: Array = []
	for id: Variant in active:
		var def: Dictionary = definition(str(id))
		if not def.is_empty():
			found.append(def)
	return found

static func definition(id: String) -> Dictionary:
	for list: Array in [pool("daily"), pool("weekly"), starter_defs()]:
		for mission: Dictionary in list:
			if str(mission.id) == id:
				return mission
	return {}

# "starter", "daily" or "weekly" ("" for an unknown id).
static func kind_of(id: String) -> String:
	for kind: String in ["daily", "weekly"]:
		if pool(kind).any(func(mission: Dictionary) -> bool: return str(mission.id) == id):
			return kind
	return "starter" if starter_defs().any(func(mission: Dictionary) -> bool: return str(mission.id) == id) else ""

static func is_starter(id: String) -> bool:
	return kind_of(id) == "starter"

# The daily contracts of the current day, for the screens and tests that need the list
# without a profile in hand (the draw does not depend on the player).
static func definitions() -> Array:
	return daily_for(day_id()).map(func(id: String) -> Dictionary: return definition(id))

static func mission_count() -> int:
	return int(data().daily_count)

# ---------- the draw ----------

# `count` ids from the pool of `kind`, seeded by `seed_value`: shuffled, then taken in order
# while no category has more than `per_category` missions. Missions that need the online game
# are left out for an offline profile.
static func draw(kind: String, seed_value: int, allow_online: bool = true) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("gustfire-%s-%d" % [kind, seed_value])
	var candidates: Array = pool(kind).filter(func(mission: Dictionary) -> bool: return allow_online or not bool(mission.get("online", false)))
	var order: Array = []
	for i in range(candidates.size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = order[i]
		order[i] = order[j]
		order[j] = swap
	var count: int = int(data().daily_count if kind == "daily" else data().weekly_count)
	var limit: int = int(data().per_category)
	var taken: Array = []
	var per: Dictionary = {}
	for index: int in order:
		var mission: Dictionary = candidates[index]
		var category: String = str(mission.get("category", ""))
		if int(per.get(category, 0)) >= limit:
			continue
		per[category] = int(per.get(category, 0)) + 1
		taken.append(str(mission.id))
		if taken.size() >= count:
			break
	return taken

static func daily_for(day: int, allow_online: bool = true) -> Array:
	return draw("daily", day, allow_online)

static func weekly_for(week: int, allow_online: bool = true) -> Array:
	return draw("weekly", week, allow_online)

# ---------- state ----------

static func empty_track(ids: Array) -> Dictionary:
	var progress: Dictionary = {}
	for id: Variant in ids:
		progress[str(id)] = 0
	return {"progress": progress, "claimed": [], "bonus": false}

static func ids_of(kind: String) -> Array:
	return pool(kind).map(func(mission: Dictionary) -> String: return str(mission.id))

static func empty_starter() -> Dictionary:
	return empty_track(starter_defs().map(func(mission: Dictionary) -> String: return str(mission.id)))

static func empty_weekly(week: int, allow_online: bool = true) -> Dictionary:
	var track: Dictionary = empty_track(ids_of("weekly"))
	track.week = week
	track.active = weekly_for(week, allow_online)
	return track

static func empty_streak() -> Dictionary:
	return {"last": -1, "count": 0, "best": 0}

static func empty_state(day: int, allow_online: bool = true) -> Dictionary:
	var state: Dictionary = {"day": day, "active": daily_for(day, allow_online), "progress": empty_track(ids_of("daily")).progress, "claimed": [], "daily_bonus": false}
	state.weekly = empty_weekly(week_id(day * 86400), allow_online)
	state.streak = empty_streak()
	state.starter = empty_starter()
	return state

static func clean_track(raw: Variant, ids: Array) -> Dictionary:
	var clean: Dictionary = empty_track(ids)
	if not raw is Dictionary:
		return clean
	var saved_progress: Variant = raw.get("progress", {})
	if saved_progress is Dictionary:
		for id: Variant in ids:
			var mission: Dictionary = definition(str(id))
			clean.progress[str(id)] = clampi(int(saved_progress.get(str(id), 0)), 0, int(mission.target))
	var saved_claimed: Variant = raw.get("claimed", [])
	if saved_claimed is Array:
		for id: Variant in saved_claimed:
			if clean.progress.has(str(id)) and not clean.claimed.has(str(id)):
				clean.claimed.append(str(id))
	clean.bonus = bool(raw.get("bonus", false))
	return clean

static func clean_starter(raw: Variant) -> Dictionary:
	return clean_track(raw, starter_defs().map(func(mission: Dictionary) -> String: return str(mission.id)))

static func clean_ids(raw: Variant, kind: String) -> Array:
	var known: Array = ids_of(kind)
	var ids: Array = []
	if raw is Array:
		for id: Variant in raw:
			if str(id) in known and not ids.has(str(id)):
				ids.append(str(id))
	return ids

static func clean_state(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var day: int = int(raw.get("day", -1))
	if day < 0:
		return {"starter": clean_starter(raw.get("starter", {}))} if raw.has("starter") else {}
	var clean: Dictionary = empty_state(day)
	var saved: Dictionary = clean_track(raw, ids_of("daily"))
	clean.progress = saved.progress
	clean.claimed = saved.claimed
	clean.daily_bonus = bool(raw.get("daily_bonus", false))
	var active: Array = clean_ids(raw.get("active", []), "daily")
	if not active.is_empty():
		clean.active = active
	var weekly_raw: Variant = raw.get("weekly", {})
	if weekly_raw is Dictionary and int(weekly_raw.get("week", -1)) >= 0:
		var weekly: Dictionary = clean_track(weekly_raw, ids_of("weekly"))
		weekly.week = int(weekly_raw.week)
		var weekly_active: Array = clean_ids(weekly_raw.get("active", []), "weekly")
		weekly.active = weekly_active if not weekly_active.is_empty() else weekly_for(int(weekly.week))
		clean.weekly = weekly
	var streak: Variant = raw.get("streak", {})
	if streak is Dictionary:
		clean.streak = {"last": int(streak.get("last", -1)), "count": maxi(0, int(streak.get("count", 0))), "best": maxi(0, int(streak.get("best", 0)))}
	clean.starter = clean_starter(raw.get("starter", {}))
	return clean

# Whether the player may be given missions that need the online game (the server decides for
# an online profile and the local game for an offline one).
static func online_capable(profile: PlayerProfile) -> bool:
	return profile.remote or profile.on_save.is_valid()

# Brings the state to today and to this week: a new day draws new daily contracts, a new
# week new weekly ones; the starter checklist and the streak stay.
static func ensure(profile: PlayerProfile) -> Dictionary:
	var today: int = day_id()
	var allow: bool = online_capable(profile)
	if int(profile.missions.get("day", -1)) != today:
		var kept: Dictionary = profile.missions
		profile.missions = empty_state(today, allow)
		if kept.has("starter"):
			profile.missions.starter = clean_starter(kept.starter)
		if kept.has("streak"):
			profile.missions.streak = kept.streak
		if kept.has("weekly") and int(kept.weekly.get("week", -1)) == week_id():
			profile.missions.weekly = kept.weekly
	var state: Dictionary = profile.missions
	if not state.has("starter"):
		state.starter = empty_starter()
	if not state.has("streak"):
		state.streak = empty_streak()
	if not state.has("weekly") or int(state.weekly.get("week", -1)) != week_id():
		state.weekly = empty_weekly(week_id(), allow)
	if not state.has("active") or (state.active as Array).is_empty():
		state.active = daily_for(int(state.day), allow)
	return state

# Where a mission's progress and claims live: the state itself (daily), or its sub-dictionary.
static func track_for(state: Dictionary, id: String) -> Dictionary:
	match kind_of(id):
		"starter":
			return state.starter
		"weekly":
			return state.weekly
	return state

static func bonus_key(kind: String) -> String:
	return "daily_bonus" if kind == "daily" else "bonus"

# ---------- progress ----------

# A settled battle moves the missions by what the player did in it.
static func progress_match(profile: PlayerProfile, game: LocalMatch, fighter: TankFighter, run: InstanceRun = null) -> void:
	ensure(profile)
	var won: bool = game.winner_team == fighter.team
	var events: Dictionary = {"damage": int(fighter.stats.damage), "kills": int(fighter.stats.kills), "pow_uses": int(game.pow_uses.get(fighter.player_id, 0))}
	if not game.pve:
		events.pvp_played = 1
		if won:
			events.pvp_win = 1
		if game.ranked:
			events.ranked_played = 1
			if won:
				events.ranked_win = 1
	elif run != null:
		events.pve_played = 1
		if won:
			events.expedition_win = 1
			events.boss_any = 1
			events["boss:" + str(run.instance.get("boss", ""))] = 1
	for event: String in events:
		if int(events[event]) > 0:
			note(profile, event, int(events[event]))

# A profile operation that went through (Ferreiro, Loja, Casa dos Mascotes, Caçada). Returns
# whether a mission moved, so the caller saves the profile again.
static func note_op(profile: PlayerProfile, op: String) -> bool:
	var events: Dictionary = {"strengthen": "strengthen", "pet_hatch": "hatch", "hunt_set": "hunt", "hunt_collect": "hunt_collect", "pet_feed": "pet_feed", "craft": "craft", "craft_map": "craft", "buy": "buy", "buy_stone": "buy", "buy_tool": "buy"}
	if not events.has(op):
		return false
	note(profile, str(events[op]))
	return true

# Advances every mission in play (starter, today's, this week's) that waits for `event`.
static func note(profile: PlayerProfile, event: String, amount: int = 1) -> void:
	var state: Dictionary = ensure(profile)
	for kind: String in ["starter", "daily", "weekly"]:
		var track: Dictionary = state if kind == "daily" else state[kind]
		for mission: Dictionary in defs_of(state, kind):
			if str(mission.get("event", "")) == event:
				var id: String = str(mission.id)
				track.progress[id] = mini(int(mission.target), int(track.progress.get(id, 0)) + amount)

# A save from before the checklist existed: what the character already did counts.
static func credit_history(profile: PlayerProfile) -> void:
	if profile.matches > 0:
		note(profile, "pvp_played")
	if profile.victories > 0:
		note(profile, "pvp_win")
	if not profile.pets.is_empty():
		note(profile, "hatch")
	if bool(profile.hunt.get("active", false)) or int(profile.hunt.get("n", 0)) > 0:
		note(profile, "hunt")
	if profile.inventory.any(func(inst: Dictionary) -> bool: return int(inst.get("level", 0)) > 0):
		note(profile, "strengthen")

static func is_complete(profile: PlayerProfile, mission: Dictionary) -> bool:
	var track: Dictionary = track_for(ensure(profile), str(mission.id))
	return int(track.progress.get(str(mission.id), 0)) >= int(mission.target)

# ---------- the streak ----------

static func streak_rewards() -> Array:
	return data().streak.rewards

# Whether today's streak reward can be claimed.
static func streak_ready(profile: PlayerProfile) -> bool:
	return int(ensure(profile).streak.last) != day_id()

# The count the streak would have if claimed today (it starts over after a missed day).
static func streak_next(profile: PlayerProfile) -> int:
	var streak: Dictionary = ensure(profile).streak
	if int(streak.last) == day_id():
		return int(streak.count)
	return int(streak.count) + 1 if int(streak.last) == day_id() - 1 else 1

# The reward of day `count` of the streak (the ladder repeats every 7 days).
static func streak_reward(count: int) -> Dictionary:
	var ladder: Array = streak_rewards()
	return ladder[posmod(count - 1, ladder.size())]

static func streak_claim(profile: PlayerProfile) -> Dictionary:
	var state: Dictionary = ensure(profile)
	if not streak_ready(profile):
		return {"error": Lang.t("A recompensa de hoje já foi resgatada."), "message": ""}
	var count: int = streak_next(profile)
	var reward: Dictionary = streak_reward(count)
	grant(profile, reward)
	state.streak.last = day_id()
	state.streak.count = count
	state.streak.best = maxi(int(state.streak.best), count)
	profile.missions = state
	return {"error": "", "message": Lang.t("Dia %d da sequência: %s.") % [count, reward_text(reward)]}

# ---------- rewards ----------

# Contracts ready to be claimed, plus the streak reward if it is waiting (the badge on the
# MISSÃO button).
static func claimable(profile: PlayerProfile) -> int:
	var state: Dictionary = ensure(profile)
	var count: int = 0
	for kind: String in ["starter", "daily", "weekly"]:
		var track: Dictionary = state if kind == "daily" else state[kind]
		for mission: Dictionary in defs_of(state, kind):
			if is_complete(profile, mission) and not track.claimed.has(str(mission.id)):
				count += 1
	if streak_ready(profile):
		count += 1
	return count

# The starter checklist is over once its bonus was claimed.
static func starter_finished(profile: PlayerProfile) -> bool:
	return bool(ensure(profile).starter.bonus)

static func reward_text(reward: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if int(reward.get("coins", 0)) > 0:
		parts.append(Lang.t("%d moedas") % int(reward.coins))
	if int(reward.get("exp", 0)) > 0:
		parts.append(Lang.t("%d EXP") % int(reward.exp))
	var items: Dictionary = reward.get("items", {})
	for id: String in items:
		parts.append("%dx %s" % [int(items[id]), Tutorial.material_name(id)])
	return ", ".join(parts)

static func grant(profile: PlayerProfile, reward: Dictionary) -> void:
	profile.coins += int(reward.get("coins", 0))
	profile.experience += int(reward.get("exp", 0))
	var items: Dictionary = reward.get("items", {})
	for id: String in items:
		profile.add_item(id, int(items[id]))

static func claim(profile: PlayerProfile, id: String) -> Dictionary:
	var state: Dictionary = ensure(profile)
	var mission: Dictionary = definition(id)
	var kind: String = kind_of(id)
	if mission.is_empty():
		return {"error": Lang.t("Missão inválida."), "message": ""}
	if kind != "starter" and not defs_of(state, kind).any(func(entry: Dictionary) -> bool: return str(entry.id) == id):
		return {"error": Lang.t("Esta missão não está valendo agora."), "message": ""}
	var track: Dictionary = track_for(state, id)
	if track.claimed.has(id):
		return {"error": Lang.t("Esta missão já foi resgatada."), "message": ""}
	if not is_complete(profile, mission):
		return {"error": Lang.t("Conclua a missão antes de resgatar."), "message": ""}
	var reward: Dictionary = mission.reward
	grant(profile, reward)
	track.claimed.append(id)
	var message: String = Lang.t("Recompensa resgatada: %s.") % reward_text(reward)
	var total: int = defs_of(state, kind).size()
	var key: String = bonus_key(kind)
	if track.claimed.size() >= total and not bool(track.get(key, false)):
		match kind:
			"starter":
				var starter_bonus: Dictionary = data().starter_bonus
				grant(profile, starter_bonus)
				message += " " + (Lang.t("Primeiros passos completos: %s.") % reward_text(starter_bonus))
			"weekly":
				var weekly_bonus: Dictionary = data().weekly_bonus
				grant(profile, weekly_bonus)
				message += " " + (Lang.t("Bônus semanal completo: %s.") % reward_text(weekly_bonus))
			_:
				var bonus: Dictionary = data().daily_bonus
				grant(profile, bonus)
				message += " " + (Lang.t("Bônus diário completo: %d moedas e %d EXP.") % [int(bonus.get("coins", 0)), int(bonus.get("exp", 0))])
		track[key] = true
	profile.missions = state
	return {"error": "", "message": message}
