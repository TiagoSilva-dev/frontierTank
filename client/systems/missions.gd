class_name MissionsBoard
extends RefCounted

const PATH: String = "res://shared/balance/missions.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func day_id(timestamp: int = -1) -> int:
	var now: int = timestamp if timestamp >= 0 else int(Time.get_unix_time_from_system())
	return floori(now / 86400.0)

static func seconds_until_reset(timestamp: int = -1) -> int:
	var now: int = timestamp if timestamp >= 0 else int(Time.get_unix_time_from_system())
	return 86400 - posmod(now, 86400)

static func empty_state(day: int) -> Dictionary:
	var progress: Dictionary = {}
	for mission: Dictionary in data().daily:
		progress[str(mission.id)] = 0
	return {"day": day, "progress": progress, "claimed": [], "daily_bonus": false}

static func clean_state(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var day: int = int(raw.get("day", -1))
	if day < 0:
		return {}
	var clean: Dictionary = empty_state(day)
	var saved_progress: Variant = raw.get("progress", {})
	if saved_progress is Dictionary:
		for mission: Dictionary in data().daily:
			var id: String = str(mission.id)
			clean.progress[id] = clampi(int(saved_progress.get(id, 0)), 0, int(mission.target))
	var saved_claimed: Variant = raw.get("claimed", [])
	if saved_claimed is Array:
		for id: Variant in saved_claimed:
			if clean.progress.has(str(id)) and not clean.claimed.has(str(id)):
				clean.claimed.append(str(id))
	clean.daily_bonus = bool(raw.get("daily_bonus", false))
	return clean

static func ensure(profile: PlayerProfile) -> Dictionary:
	var today: int = day_id()
	if int(profile.missions.get("day", -1)) != today:
		profile.missions = empty_state(today)
	return profile.missions

static func definitions() -> Array:
	return data().daily

static func mission_count() -> int:
	return definitions().size()

static func definition(id: String) -> Dictionary:
	for mission: Dictionary in data().daily:
		if str(mission.id) == id:
			return mission
	return {}

static func progress_match(profile: PlayerProfile, game: LocalMatch, fighter: TankFighter, run: InstanceRun = null) -> void:
	var state: Dictionary = ensure(profile)
	for mission: Dictionary in data().daily:
		var id: String = str(mission.id)
		var amount: int = 0
		match str(mission.type):
			"pvp_wins":
				amount = 1 if not game.pve and game.winner_team == fighter.team else 0
			"damage":
				amount = int(fighter.stats.damage)
			"expedition":
				amount = 1 if game.pve and run != null and game.winner_team == fighter.team else 0
			"boss":
				amount = 1 if game.pve and run != null and game.winner_team == fighter.team and str(run.instance.get("boss", "")) == str(mission.get("boss", "")) else 0
			"pow_uses":
				amount = int(game.pow_uses.get(fighter.player_id, 0))
		if amount > 0:
			state.progress[id] = mini(int(mission.target), int(state.progress.get(id, 0)) + amount)
	profile.missions = state

static func is_complete(profile: PlayerProfile, mission: Dictionary) -> bool:
	var state: Dictionary = ensure(profile)
	return int(state.progress.get(str(mission.id), 0)) >= int(mission.target)

static func claim(profile: PlayerProfile, id: String) -> Dictionary:
	var state: Dictionary = ensure(profile)
	var mission: Dictionary = definition(id)
	if mission.is_empty():
		return {"error": Lang.t("Missão inválida."), "message": ""}
	if state.claimed.has(id):
		return {"error": Lang.t("Esta missão já foi resgatada."), "message": ""}
	if not is_complete(profile, mission):
		return {"error": Lang.t("Conclua a missão antes de resgatar."), "message": ""}
	var reward: Dictionary = mission.reward
	profile.coins += int(reward.get("coins", 0))
	profile.experience += int(reward.get("exp", 0))
	state.claimed.append(id)
	var bonus: Dictionary = {}
	if state.claimed.size() == mission_count() and not bool(state.daily_bonus):
		bonus = data().daily_bonus
		profile.coins += int(bonus.get("coins", 0))
		profile.experience += int(bonus.get("exp", 0))
		state.daily_bonus = true
	profile.missions = state
	var message: String = Lang.t("Recompensa resgatada: %d moedas e %d EXP.") % [int(reward.get("coins", 0)), int(reward.get("exp", 0))]
	if not bonus.is_empty():
		message += " " + (Lang.t("Bônus diário completo: %d moedas e %d EXP.") % [int(bonus.get("coins", 0)), int(bonus.get("exp", 0))])
	return {"error": "", "message": message}