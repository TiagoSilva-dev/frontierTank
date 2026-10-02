extends SceneTree

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

func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://mission_test_profile.json"
	var profile: PlayerProfile = PlayerProfile.new()
	var state: Dictionary = MissionsBoard.ensure(profile)
	check(state.progress.size() == MissionsBoard.mission_count() and state.claimed.is_empty(), "a new profile receives all daily contracts")
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(copy.missions == profile.missions, "daily progress and claims persist in the profile")
	var locked: Dictionary = profile.apply_op("mission_claim", ["pvp_wins"], {})
	check(locked.error != "" and profile.coins == 300, "incomplete missions cannot be claimed")
	var game: LocalMatch = LocalMatch.new()
	game.pve = false
	game.winner_team = 0
	var fighter: TankFighter = TankFighter.new()
	fighter.player_id = 7
	fighter.team = 0
	fighter.stats.damage = 2500
	game.pow_uses[7] = 2
	MissionsBoard.progress_match(profile, game, fighter)
	check(int(profile.missions.progress.pvp_wins) == 1 and int(profile.missions.progress.damage) == 2500 and int(profile.missions.progress.pow_uses) == 2, "PvP wins, damage and armed POWs advance their matching contracts")
	game.pve = true
	var run: InstanceRun = InstanceRun.new(InstanceRun.rules(), "templo_sol", {}, 1, [], profile)
	MissionsBoard.progress_match(profile, game, fighter, run)
	check(int(profile.missions.progress.expedition) == 1 and int(profile.missions.progress.boss_helio) == 1, "a successful expedition advances its completion and boss contracts")
	profile.missions.progress.pvp_wins = 5
	var claimed: Dictionary = profile.apply_op("mission_claim", ["pvp_wins"], {})
	check(claimed.error == "" and profile.coins == 420 and profile.experience == 120, "claim grants configured coins and experience")
	var duplicate: Dictionary = profile.apply_op("mission_claim", ["pvp_wins"], {})
	check(duplicate.error != "" and profile.coins == 420, "a mission reward cannot be claimed twice")
	profile.missions.progress.damage = 10000
	profile.missions.progress.expedition = 1
	profile.missions.progress.boss_helio = 1
	profile.missions.progress.pow_uses = 10
	for mission: Dictionary in MissionsBoard.definitions():
		if not profile.missions.claimed.has(str(mission.id)):
			profile.apply_op("mission_claim", [str(mission.id)], {})
	check(profile.missions.daily_bonus and profile.coins == 1250 and profile.experience == 900, "claiming every contract awards the daily completion bonus once")
	check(profile.to_data().version == 8 and MissionsBoard.seconds_until_reset(86400) == 86400, "profile migration and UTC reset boundary are stable")
	profile.missions.day -= 1
	profile.missions.progress.pvp_wins = 4
	profile.missions.claimed.append("pvp_wins")
	var renewed: Dictionary = MissionsBoard.ensure(profile)
	check(int(renewed.progress.pvp_wins) == 0 and renewed.claimed.is_empty() and not renewed.daily_bonus, "UTC renewal resets progress, claims and the completion bonus")
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.shortcut("mission")
	await process_frame
	check(app.ui.get_children().any(func(node: Node) -> bool: return node is MissionScreen), "the city shortcut opens the mission board")
	app.queue_free()
	await process_frame
	print("MISSION RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)