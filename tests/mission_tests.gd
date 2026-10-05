extends SceneTree

# Contracts (0.22): the daily and weekly contracts are drawn from pools (the same for everybody
# on a day or week), progress comes from battle events and profile operations, rewards and
# bonuses are paid once, the starter checklist and the login streak survive the renewals.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

# A Monday 00:00 UTC (2026-10-05) and a helper to land on a given day.
const MONDAY: int = 20731

func at_day(day: int) -> int:
	return day * 86400 + 3600

func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://mission_test_profile.json"
	draw_checks()
	state_checks()
	progress_checks()
	claim_checks()
	renewal_checks()
	streak_checks()
	await screen_checks()
	MissionsBoard.clock_offset = 0
	print("MISSION RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func draw_checks() -> void:
	var data: Dictionary = MissionsBoard.data()
	var limit: int = int(data.per_category)
	var ok: bool = true
	var seen: Dictionary = {}
	for day in range(MONDAY, MONDAY + 120):
		var ids: Array = MissionsBoard.daily_for(day)
		var per: Dictionary = {}
		for id: String in ids:
			seen[id] = true
			var category: String = str(MissionsBoard.definition(id).category)
			per[category] = int(per.get(category, 0)) + 1
		var unique: Dictionary = {}
		for id: String in ids:
			unique[id] = true
		ok = ok and ids.size() == int(data.daily_count) and ids == MissionsBoard.daily_for(day) and per.values().all(func(n: int) -> bool: return n <= limit) and unique.size() == ids.size()
	check(ok, "every day draws %d different contracts, the same ones each time, at most %d of a kind" % [int(data.daily_count), limit])
	check(seen.size() >= 12, "over a few months most of the pool shows up (%d of %d)" % [seen.size(), MissionsBoard.pool("daily").size()])
	check(MissionsBoard.daily_for(MONDAY) != MissionsBoard.daily_for(MONDAY + 1) or MissionsBoard.daily_for(MONDAY) != MissionsBoard.daily_for(MONDAY + 2), "the contracts change from day to day")
	var offline_ok: bool = true
	for day in range(MONDAY, MONDAY + 60):
		offline_ok = offline_ok and MissionsBoard.daily_for(day, false).all(func(id: String) -> bool: return not bool(MissionsBoard.definition(id).get("online", false)))
		offline_ok = offline_ok and MissionsBoard.weekly_for(day, false).all(func(id: String) -> bool: return not bool(MissionsBoard.definition(id).get("online", false)))
	check(offline_ok and MissionsBoard.daily_for(MONDAY, false).size() == int(data.daily_count), "an offline profile is never given a contract that needs the online game")
	var weekly: Array = MissionsBoard.weekly_for(2962)
	check(weekly.size() == int(data.weekly_count) and weekly == MissionsBoard.weekly_for(2962), "a week draws its own contracts")
	# Weeks run Monday to Sunday (UTC).
	check(MissionsBoard.week_id(MONDAY * 86400) == 2962 and MissionsBoard.week_id((MONDAY + 6) * 86400 + 86399) == 2962 and MissionsBoard.week_id((MONDAY + 7) * 86400) == 2963 and MissionsBoard.week_id((MONDAY - 1) * 86400 + 5) == 2961, "a week starts on Monday")
	check(MissionsBoard.seconds_until_week((MONDAY + 6) * 86400 + 86400 - 60) == 60 and MissionsBoard.seconds_until_week(MONDAY * 86400) == 7 * 86400, "the clock counts down to the next Monday")
	check(MissionsBoard.kind_of("pvp_wins") == "daily" and MissionsBoard.kind_of("w_pvp_wins") == "weekly" and MissionsBoard.kind_of("s_pvp") == "starter" and MissionsBoard.kind_of("nope") == "", "every mission knows its track")
	var all_ok: bool = true
	var ids: Dictionary = {}
	for list: Array in [MissionsBoard.pool("daily"), MissionsBoard.pool("weekly"), MissionsBoard.starter_defs()]:
		for mission: Dictionary in list:
			all_ok = all_ok and not ids.has(mission.id) and int(mission.target) > 0 and mission.has("event") and mission.has("reward") and str(mission.name) != ""
			ids[mission.id] = true
	check(all_ok, "mission ids are unique and each has an event, a target and a reward")

func state_checks() -> void:
	MissionsBoard.clock_offset = 0
	var profile: PlayerProfile = PlayerProfile.new()
	var state: Dictionary = MissionsBoard.ensure(profile)
	check(state.active.size() == MissionsBoard.mission_count() and state.progress.size() == MissionsBoard.pool("daily").size() and state.claimed.is_empty(), "a new profile receives today's contracts")
	check(state.weekly.active.size() == int(MissionsBoard.data().weekly_count) and int(state.weekly.week) == MissionsBoard.week_id() and state.streak.count == 0, "and this week's, with an empty streak")
	check(state.active == MissionsBoard.daily_for(MissionsBoard.day_id(), false), "an offline profile draws the offline list")
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(copy.missions == profile.missions, "the contracts persist in the profile")
	# A save with the old daily-only shape.
	var old: Dictionary = {"version": 8, "created": true, "matches": 2, "experience": 50, "missions": {"day": MissionsBoard.day_id(), "progress": {"pvp_wins": 3, "damage": 99999, "gone": 4}, "claimed": ["damage", "gone"], "daily_bonus": false}}
	var veteran: PlayerProfile = PlayerProfile.new()
	veteran.load_data(old)
	var legacy: Dictionary = MissionsBoard.ensure(veteran)
	check(not legacy.active.is_empty() and legacy.has("weekly") and legacy.has("streak") and legacy.has("starter") and int(legacy.progress.pvp_wins) == 3 and int(legacy.progress.damage) == 10000 and not legacy.progress.has("gone"), "an older save keeps its progress and gains the new tracks")
	var junk: Dictionary = MissionsBoard.clean_state({"day": MissionsBoard.day_id(), "active": ["pvp_wins", "pvp_wins", "nope", 7], "weekly": {"week": "x", "active": ["w_pvp_wins"]}, "streak": {"last": "x", "count": -3, "best": 4}})
	check(junk.active == ["pvp_wins"] and junk.streak.count == 0 and junk.streak.best == 4 and junk.streak.last == 0, "damaged state is cleaned")

func force(profile: PlayerProfile, daily: Array, weekly: Array) -> void:
	var state: Dictionary = MissionsBoard.ensure(profile)
	state.active = daily
	state.weekly.active = weekly

func fighter_for(team: int, damage: int, kills: int) -> TankFighter:
	var fighter: TankFighter = TankFighter.new()
	fighter.player_id = 7
	fighter.team = team
	fighter.stats.damage = damage
	fighter.stats.kills = kills
	return fighter

func progress_checks() -> void:
	MissionsBoard.clock_offset = 0
	var profile: PlayerProfile = PlayerProfile.new()
	force(profile, ["pvp_wins", "damage", "pow_uses", "expedition", "boss_helio"], ["w_pvp_wins", "w_damage", "w_expedition"])
	var game: LocalMatch = LocalMatch.new()
	game.pve = false
	game.winner_team = 0
	game.pow_uses[7] = 2
	MissionsBoard.progress_match(profile, game, fighter_for(0, 2500, 3))
	var daily: Dictionary = profile.missions.progress
	var weekly: Dictionary = profile.missions.weekly.progress
	check(int(daily.pvp_wins) == 1 and int(daily.damage) == 2500 and int(daily.pow_uses) == 2, "a PvP win moves the daily contracts")
	check(int(weekly.w_pvp_wins) == 1 and int(weekly.w_damage) == 2500, "and the weekly ones that wait for the same events")
	check(int(daily.expedition) == 0 and int(daily.kills) == 0 and int(profile.missions.starter.progress.s_pvp) == 1 and int(profile.missions.starter.progress.s_win) == 1, "contracts out of play do not move, the starter checklist does (a lost match counts as played only)")
	game.winner_team = 1
	MissionsBoard.progress_match(profile, game, fighter_for(0, 100, 0))
	check(int(profile.missions.progress.pvp_wins) == 1 and int(profile.missions.progress.damage) == 2600, "a defeat adds damage but no win")
	game.pve = true
	game.winner_team = 0
	var run: InstanceRun = InstanceRun.new(InstanceRun.rules(), "templo_sol", {}, 1, [], profile)
	MissionsBoard.progress_match(profile, game, fighter_for(0, 0, 0), run)
	check(int(profile.missions.progress.expedition) == 1 and int(profile.missions.progress.boss_helio) == 1 and int(profile.missions.weekly.progress.w_expedition) == 1, "an expedition win moves the expedition and the boss contracts")
	# Ranked and bosses of any instance.
	force(profile, ["ranked_played", "boss_any", "kills"], ["w_ranked", "w_bosses", "w_hunt"])
	var ranked: LocalMatch = LocalMatch.new()
	ranked.pve = false
	ranked.ranked = true
	ranked.winner_team = 0
	MissionsBoard.progress_match(profile, ranked, fighter_for(0, 10, 4))
	check(int(profile.missions.progress.ranked_played) == 1 and int(profile.missions.weekly.progress.w_ranked) == 1 and int(profile.missions.progress.kills) == 4, "a ranked match moves the ranked contracts")
	var other: InstanceRun = InstanceRun.new(InstanceRun.rules(), "trono_mascaras", {}, 1, [], profile)
	game.pve = true
	MissionsBoard.progress_match(profile, game, fighter_for(0, 0, 0), other)
	check(int(profile.missions.progress.boss_any) == 1 and int(profile.missions.weekly.progress.w_bosses) == 1, "a boss of any instance counts for the generic boss contracts")
	# Profile operations.
	force(profile, ["hunt_collect", "strengthen", "craft", "buy"], ["w_hunt", "w_forge"])
	for op: String in ["hunt_collect", "strengthen", "craft", "craft_map", "buy_stone", "buy_tool", "buy"]:
		check(MissionsBoard.note_op(profile, op), "'%s' is an event for the contracts" % op)
	var after: Dictionary = profile.missions.progress
	check(not MissionsBoard.note_op(profile, "pet_hatch") and not MissionsBoard.note_op(profile, "pet_feed"), "hatching and feeding are gone, so they are no events")
	check(int(after.hunt_collect) == 1 and int(after.strengthen) == 1 and int(after.craft) == int(MissionsBoard.definition("craft").target) and int(after.buy) == int(MissionsBoard.definition("buy").target), "operations move their contracts up to their targets")
	check(not MissionsBoard.note_op(profile, "toggle_equip") and not MissionsBoard.note_op(profile, "sell"), "other operations are not events")
	check(int(profile.missions.weekly.progress.w_hunt) == 1 and int(profile.missions.weekly.progress.w_forge) == 1, "the weekly ones follow")
	# The operation that really ran through apply_op.
	var real: PlayerProfile = PlayerProfile.new()
	force(real, ["strengthen", "buy"], ["w_forge"])
	real.add_item("pedra_fortalecimento", 1)
	check(real.apply_op("strengthen", [int(real.equipped_instance("arma").uid)], {}).error == "" and int(real.missions.progress.strengthen) == 1 and int(real.missions.weekly.progress.w_forge) == 1, "a Ferreiro attempt through apply_op moves them")
	check(real.apply_op("buy_tool", ["hp"], JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))).error == "" and int(real.missions.progress.buy) == 1, "so does a purchase")
	# The daily challenge.
	force(real, ["challenge"], ["w_challenge"])
	real.challenge_done(Challenge.day_id(), 1000, 1)
	check(int(real.missions.progress.challenge) == 1 and int(real.missions.weekly.progress.w_challenge) == 1, "the daily challenge moves its contracts once a day")
	real.challenge_done(Challenge.day_id(), 1500, 1)
	check(int(real.missions.progress.challenge) == 1, "a second run the same day does not")

func claim_checks() -> void:
	MissionsBoard.clock_offset = 0
	var profile: PlayerProfile = PlayerProfile.new()
	var balance: Dictionary = {}
	force(profile, ["pvp_wins", "damage", "pow_uses", "expedition", "boss_helio"], ["w_pvp_wins", "w_damage", "w_expedition"])
	check(profile.apply_op("mission_claim", ["pvp_wins"], balance).error != "" and profile.coins == 300, "an unfinished contract cannot be claimed")
	check(profile.apply_op("mission_claim", ["kills"], balance).error != "", "a contract that is not in play today cannot be claimed")
	check(profile.apply_op("mission_claim", ["w_pvp_wins"], balance).error != "" and profile.apply_op("mission_claim", ["nope"], balance).error != "", "nor an unfinished weekly one or an unknown id")
	var state: Dictionary = profile.missions
	state.progress.pvp_wins = 5
	var paid: Dictionary = profile.apply_op("mission_claim", ["pvp_wins"], balance)
	check(paid.error == "" and profile.coins == 420 and profile.experience == 120 and str(paid.message).contains("120"), "claiming pays the configured coins and experience")
	check(profile.apply_op("mission_claim", ["pvp_wins"], balance).error != "" and profile.coins == 420, "a reward is claimed once")
	for id: String in ["damage", "pow_uses", "expedition", "boss_helio"]:
		state.progress[id] = int(MissionsBoard.definition(id).target)
	for id: String in ["damage", "pow_uses", "expedition", "boss_helio"]:
		profile.apply_op("mission_claim", [id], balance)
	var bonus: Dictionary = MissionsBoard.data().daily_bonus
	var expected: int = 300 + 120 + 100 + 100 + 180 + 150 + int(bonus.coins)
	check(profile.missions.daily_bonus and profile.coins == expected, "claiming every daily contract pays the bonus once (%d coins)" % profile.coins)
	var coins: int = profile.coins
	profile.apply_op("mission_claim", ["pvp_wins"], balance)
	check(profile.coins == coins, "and not again")
	# Weekly: items and the bonus.
	var week: Dictionary = profile.missions.weekly
	for id: String in ["w_pvp_wins", "w_damage", "w_expedition"]:
		week.progress[id] = int(MissionsBoard.definition(id).target)
	var stones: int = int(profile.items.get("pedra_fortalecimento", 0))
	for id: String in ["w_pvp_wins", "w_damage", "w_expedition"]:
		profile.apply_op("mission_claim", [id], balance)
	check(int(profile.items.get("pedra_fortalecimento", 0)) == stones + 4 and not profile.items.has("egg_sol"), "weekly rewards can carry items (and no egg)")
	check(week.bonus and int(profile.items.get("strength_stone_ii", 0)) == 1, "the weekly bonus pays once, with its item")

func renewal_checks() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	MissionsBoard.clock_offset = at_day(MONDAY) - int(Time.get_unix_time_from_system())
	var monday: Dictionary = MissionsBoard.ensure(profile)
	check(monday.active == MissionsBoard.daily_for(MONDAY, false) and int(monday.weekly.week) == 2962, "on a Monday the day and the week are drawn")
	monday.progress.damage = 777
	monday.starter.progress.s_pvp = 1
	monday.streak = {"last": MONDAY, "count": 3, "best": 5}
	monday.weekly.progress.w_damage = 4000
	var weekly_active: Array = monday.weekly.active.duplicate()
	# The next day: new daily contracts, the week goes on.
	MissionsBoard.clock_offset = at_day(MONDAY + 1) - int(Time.get_unix_time_from_system())
	var tuesday: Dictionary = MissionsBoard.ensure(profile)
	check(tuesday.active == MissionsBoard.daily_for(MONDAY + 1, false) and int(tuesday.progress.damage) == 0 and tuesday.claimed.is_empty() and not tuesday.daily_bonus, "a new day draws new contracts and clears the progress")
	check(tuesday.weekly.active == weekly_active and int(tuesday.weekly.progress.w_damage) == 4000, "the week's contracts and their progress stay")
	check(int(tuesday.starter.progress.s_pvp) == 1 and tuesday.streak.count == 3 and tuesday.streak.best == 5, "so do the starter checklist and the streak")
	# Sunday and the next Monday.
	MissionsBoard.clock_offset = at_day(MONDAY + 6) - int(Time.get_unix_time_from_system())
	var sunday: Dictionary = MissionsBoard.ensure(profile)
	check(sunday.weekly.active == weekly_active, "still the same week on Sunday")
	MissionsBoard.clock_offset = at_day(MONDAY + 7) - int(Time.get_unix_time_from_system())
	var next: Dictionary = MissionsBoard.ensure(profile)
	check(int(next.weekly.week) == 2963 and next.weekly.active == MissionsBoard.weekly_for(2963, false) and int(next.weekly.progress.w_damage) == 0 and not next.weekly.bonus and next.weekly.claimed.is_empty(), "a new week draws new weekly contracts")
	check(int(next.starter.progress.s_pvp) == 1 and next.streak.best == 5, "the starter checklist and the best streak are still there")
	# Opening the game after a long time away.
	MissionsBoard.clock_offset = at_day(MONDAY + 40) - int(Time.get_unix_time_from_system())
	var later: Dictionary = MissionsBoard.ensure(profile)
	check(later.active == MissionsBoard.daily_for(MONDAY + 40, false) and int(later.weekly.week) == MissionsBoard.week_id(at_day(MONDAY + 40)), "a long absence draws the current day and week")
	MissionsBoard.clock_offset = 0

func streak_checks() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	var ladder: Array = MissionsBoard.streak_rewards()
	check(ladder.size() == 7, "the ladder has seven days")
	MissionsBoard.clock_offset = at_day(MONDAY) - int(Time.get_unix_time_from_system())
	check(MissionsBoard.streak_ready(profile) and MissionsBoard.streak_next(profile) == 1 and MissionsBoard.claimable(profile) >= 1, "a new player has day 1 waiting (and it shows on the badge)")
	var coins: int = profile.coins
	var first: Dictionary = profile.apply_op("streak_claim", [], {})
	check(first.error == "" and profile.coins == coins + int(ladder[0].coins) and profile.missions.streak.count == 1 and str(first.message).contains("1"), "claiming pays the first rung")
	check(profile.apply_op("streak_claim", [], {}).error != "" and not MissionsBoard.streak_ready(profile) and profile.coins == coins + int(ladder[0].coins), "once a day")
	# Seven days in a row climb the whole ladder.
	var total: int = int(ladder[0].coins)
	for day in range(1, 7):
		MissionsBoard.clock_offset = at_day(MONDAY + day) - int(Time.get_unix_time_from_system())
		check(MissionsBoard.streak_ready(profile) and MissionsBoard.streak_next(profile) == day + 1, "day %d of the streak is ready" % (day + 1))
		var before: int = profile.coins
		profile.apply_op("streak_claim", [], {})
		check(profile.coins == before + int(ladder[day].coins), "day %d pays rung %d" % [day + 1, day + 1])
	check(profile.missions.streak.count == 7 and int(profile.items.get("pedra_fortalecimento", 0)) >= 2 and not profile.items.has("pet_egg"), "the seventh day gives stones, no egg")
	# The ladder repeats.
	MissionsBoard.clock_offset = at_day(MONDAY + 7) - int(Time.get_unix_time_from_system())
	var again: int = profile.coins
	profile.apply_op("streak_claim", [], {})
	check(profile.missions.streak.count == 8 and profile.coins == again + int(ladder[0].coins) and profile.missions.streak.best == 8, "day 8 starts the ladder again and counts as the best")
	# A missed day starts over.
	MissionsBoard.clock_offset = at_day(MONDAY + 9) - int(Time.get_unix_time_from_system())
	check(MissionsBoard.streak_next(profile) == 1, "missing a day starts over")
	var reset: int = profile.coins
	profile.apply_op("streak_claim", [], {})
	check(profile.missions.streak.count == 1 and profile.missions.streak.best == 8 and profile.coins == reset + int(ladder[0].coins), "from day 1, keeping the best")
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(copy.missions.streak == profile.missions.streak, "the streak survives the save")
	MissionsBoard.clock_offset = 0

func screen_checks() -> void:
	MissionsBoard.clock_offset = 0
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile.created = true
	app.shortcut("mission")
	await process_frame
	var screen: MissionScreen = null
	for node: Node in app.ui.get_children():
		if node is MissionScreen:
			screen = node
	check(screen != null, "the city shortcut opens the contracts")
	for tab: String in ["starter", "daily", "weekly", "streak"]:
		check(screen.find_child("MissionTab_" + tab, true, false) != null, "the %s tab exists" % tab)
	screen.select_tab("daily")
	await process_frame
	var state: Dictionary = MissionsBoard.ensure(app.profile)
	check(state.active.all(func(id: String) -> bool: return screen.find_child("Mission_" + id, true, false) != null), "the daily tab shows today's contracts")
	screen.select_tab("weekly")
	await process_frame
	check(state.weekly.active.all(func(id: String) -> bool: return screen.find_child("Mission_" + id, true, false) != null), "the weekly tab shows the week's contracts")
	state.weekly.progress[state.weekly.active[0]] = int(MissionsBoard.definition(state.weekly.active[0]).target)
	screen.select_tab("weekly")
	await process_frame
	var coins: int = app.profile.coins
	var claim: Button = screen.find_child("ClaimMission_" + str(state.weekly.active[0]), true, false)
	check(claim != null and not claim.disabled, "a finished weekly contract can be claimed")
	claim.pressed.emit()
	await process_frame
	await process_frame
	check(app.profile.coins > coins and screen.find_child("ClaimMission_" + str(state.weekly.active[0]), true, false).disabled, "and is paid")
	screen.select_tab("streak")
	await process_frame
	var streak_button: Button = screen.find_child("ClaimStreak", true, false)
	check(streak_button != null and not streak_button.disabled and screen.find_child("StreakDay_7", true, false) != null, "the streak tab has the ladder and a claim button")
	coins = app.profile.coins
	streak_button.pressed.emit()
	await process_frame
	await process_frame
	check(app.profile.coins > coins and app.profile.missions.streak.count == 1 and screen.find_child("ClaimStreak", true, false).disabled, "claiming the streak pays and waits for tomorrow")
	var bar: BottomBar = BottomBar.new()
	bar.app = app
	root.add_child(bar)
	check(bar.claimable() == MissionsBoard.claimable(app.profile), "the badge counts what is ready")
	bar.queue_free()
	app.queue_free()
	await process_frame
