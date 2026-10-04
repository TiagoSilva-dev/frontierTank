extends SceneTree

# Daily challenge (0.22): the day's definition is the same everywhere, a scripted run is
# scored, its replay gives back the very same score on a ReplayRunner (what the server
# does), the turn limit ends it, the reward is paid once a day and the screens work.

var checks: int = 0
var failures: int = 0
var balance: Dictionary

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
	PlayerProfile.path_override = "user://challenge_test_profile.json"
	Replay.dir_override = "user://challenge_test_replays"
	for path: String in Replay.list():
		Replay.delete(path)
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	data_checks()
	spec_checks()
	await run_checks()
	profile_checks()
	await screen_checks()
	for path: String in Replay.list():
		Replay.delete(path)
	print("CHALLENGE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func data_checks() -> void:
	var data: Dictionary = Challenge.data()
	var ok: bool = true
	for kind: Dictionary in data.kinds:
		var medals: Array = kind.medals
		ok = ok and medals.size() == 3 and medals[0] < medals[1] and medals[1] < medals[2] and int(kind.turns) > 0 and str(kind.name) != "" and str(kind.description) != ""
		ok = ok and (str(kind.id) == "duelo" or (kind.target_hp as Array).size() > 0)
	check(ok and data.kinds.size() >= 3, "every kind has turns, ascending medals and its targets")
	var weapons_ok: bool = true
	for weapon: String in data.weapons:
		weapons_ok = weapons_ok and not Armory.definition(weapon).is_empty() and Armory.kind_of(weapon) == "weapon"
	check(weapons_ok, "the weapons of the day exist")
	var epoch: int = int(Time.get_unix_time_from_datetime_string(str(data.epoch)))
	check(Challenge.day_id(epoch) == 0 and Challenge.day_id(epoch + 86400) == 1 and Challenge.day_id(epoch + 86400 * 40 + 100) == 40 and Challenge.day_id(epoch - 86400 * 9) == 0, "the day id counts UTC days from the epoch")
	check(Challenge.seconds_left(epoch + 86400 - 30) == 30, "the clock counts the seconds to the next challenge")

func spec_checks() -> void:
	var seen_kinds: Dictionary = {}
	var seen_weapons: Dictionary = {}
	var maps_ok: bool = true
	var maps: Array = balance.maps.filter(func(entry: Dictionary) -> bool: return not bool(entry.get("pve_only", false))).map(func(entry: Dictionary) -> String: return str(entry.id))
	for day in range(60):
		var spec: Dictionary = Challenge.spec_for(day)
		seen_kinds[spec.kind] = true
		seen_weapons[spec.weapon] = true
		maps_ok = maps_ok and spec.map in maps and Challenge.spec_for(day) == spec
	check(maps_ok, "a day's challenge is always the same and on a PvP map")
	check(seen_kinds.size() == Challenge.data().kinds.size() and seen_weapons.size() >= 6, "kinds and weapons rotate over the days")
	check(Challenge.spec_for(3).seed != Challenge.spec_for(4).seed or Challenge.spec_for(3).map != Challenge.spec_for(4).map, "different days differ")
	var config: Dictionary = Challenge.config(0, "Nilo", "f")
	check(config.mode == "challenge" and config.lockstep and config.local == 0 and config.teams.size() == 2 and config.teams[0].size() == 1 and config.teams[0][0].human and config.max_turns > 0, "the config is a lockstep battle for one player")
	check(config.teams[0][0].arma.id == Challenge.spec_for(0).weapon and not config.has("hosted") and config.teams[0][0].name == "Nilo", "everyone gets the day's weapon")
	check(Challenge.config(0, "Outro") .seed == config.seed and Challenge.config(0, "Outro").teams[1] == config.teams[1], "the seed and the foes do not depend on the player")
	var profile: PlayerProfile = PlayerProfile.new()
	var local: Dictionary = Challenge.local_config(0, profile, balance)
	check(local.hosted and local.teams[0][0].has("look"), "the local battle adds what is only for show")

func solution(game: LocalMatch) -> Vector3:
	var me: TankFighter = game.fighters[0]
	var foe: TankFighter = null
	for fighter in game.fighters:
		if fighter.team == 1 and fighter.hp > 0 and (foe == null or fighter.position.distance_to(me.position) < foe.position.distance_to(me.position)):
			foe = fighter
	if foe == null:
		return Vector3(45, 50, 0)
	var scale: float = float(me.weapon.get("projectile", {}).get("wind_scale", 1.0))
	return EnemyAI.choose_shot(me, foe, game.terrain, game.wind * float(game.balance.wind_accel) * scale * game.wind_factor(me), game.balance)

# Plays a challenge day on a LocalHost with the shot solver (or idling when `idle`) and
# returns what came out.
func play(day: int, idle: bool = false) -> Dictionary:
	var config: Dictionary = Challenge.config(day, "Nilo")
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start(config)
	var host: LocalHost = LocalHost.new()
	host.game = game
	host.refused = ["auto", "emote"]
	game.remote = host.submit
	root.add_child(host)
	host.set_physics_process(false)
	var stage: int = 0
	var last_round: int = -1
	var power: float = 50.0
	for i in range(30000):
		if not game.running:
			break
		if game.round_number != last_round:
			last_round = game.round_number
			stage = 0
		if not idle:
			if stage == 0 and game.can_act():
				var shot: Vector3 = solution(game)
				host.submit("aim", {"d": 0.0, "angle": shot.x})
				host.submit("charge", {})
				power = shot.y
				stage = 1
			elif stage == 1 and game.active_id == game.local_id and game.state == LocalMatch.State.PLAYER_CHARGING and host.pending.is_empty():
				host.submit("release", {"power": power})
				stage = 2
		host.advance()
	var result: Dictionary = {"game": game, "host": host, "score": Challenge.score(game), "checksum": game.checksum(), "replay": Replay.make(config, host.history, host.tick, game.winner_team, {"kind": "challenge", "day": day, "names": ["Nilo"]})}
	return result

func run_checks() -> void:
	# One day of each kind (day % kinds.size()).
	for day in range(Challenge.data().kinds.size()):
		var spec: Dictionary = Challenge.spec_for(day)
		var run: Dictionary = play(day)
		var game: LocalMatch = run.game
		var info: Dictionary = run.score
		check(not game.running and info.turns <= int(spec.turns) and info.score >= 0, "%s (day %d, %s): the run ends, within %d turns (score %d, %d turns)" % [spec.kind, day, spec.weapon, int(spec.turns), int(info.score), int(info.turns)])
		print("PROBE %s day %d %s: score %d medal %d won %s down %d/%d turns %d" % [spec.kind, day, spec.weapon, int(info.score), int(info.medal), str(info.won), int(info.down), int(info.targets), int(info.turns)])
		# The server's check: the replay gives the same battle and the same score.
		var cleaned: Dictionary = Replay.clean(JSON.parse_string(JSON.stringify(run.replay)))
		check(not cleaned.is_empty(), "%s: its replay is accepted" % spec.kind)
		var runner: ReplayRunner = ReplayRunner.new()
		root.add_child(runner)
		runner.begin(cleaned)
		runner.run_all()
		var again: Dictionary = Challenge.score(runner.game)
		check(runner.game.checksum() == run.checksum and again.score == info.score and again.medal == info.medal and runner.tick == run.host.tick, "%s: the replay is scored the same (%d)" % [spec.kind, int(again.score)])
		runner.queue_free()
		game.queue_free()
		run.host.queue_free()
	# Doing nothing: the turns run out, nothing is scored and the challenger lost.
	var idle: Dictionary = play(0, true)
	var idle_game: LocalMatch = idle.game
	check(not idle_game.running and idle_game.winner_team == 1 and idle.score.score == 0 and idle.score.medal == 0 and not idle.score.won, "idling through every turn scores nothing")
	check(idle_game.fighters[0].turns_started == int(Challenge.spec_for(0).turns), "the match ends exactly at the turn limit")
	idle_game.queue_free()
	idle.host.queue_free()
	# The actions a challenge refuses never reach the record.
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start(Challenge.config(0, "Nilo"))
	var host: LocalHost = LocalHost.new()
	host.game = game
	host.refused = ["auto", "emote"]
	host.submit("auto", {"on": true})
	host.submit("emote", {"id": "paladino"})
	host.submit("teleport", {})
	host.submit("pass", {})
	check(host.pending.size() == 1 and host.pending[0][1] == "pass", "the host refuses the AI, emotes and unknown actions")
	host.free()
	game.queue_free()

func profile_checks() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	var coins: int = profile.coins
	var first: Dictionary = profile.challenge_done(5, 2100, 2)
	var reward: Dictionary = Challenge.data().reward
	check(first.first and first.best and profile.coins == coins + int(reward.coins) and profile.experience == int(reward.exp) and profile.challenge.day == 5 and profile.challenge.best == 2100, "the first result of a day pays the reward and sets the best")
	var worse: Dictionary = profile.challenge_done(5, 1500, 1)
	check(not worse.first and not worse.best and profile.challenge.best == 2100 and profile.coins == coins + int(reward.coins), "a worse run later the same day changes nothing")
	var better: Dictionary = profile.challenge_done(5, 2900, 3)
	check(not better.first and better.best and profile.challenge.best == 2900 and profile.challenge.medal == 3 and profile.coins == coins + int(reward.coins), "a better one raises the best but pays nothing more")
	var next: Dictionary = profile.challenge_done(6, 800, 0)
	check(next.first and profile.coins == coins + 2 * int(reward.coins) and profile.challenge.best == 800 and profile.challenge.day == 6, "the next day pays again")
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(copy.challenge == profile.challenge, "the challenge state survives the save")
	var old: Dictionary = profile.to_data()
	old.erase("challenge")
	old.version = 9
	var from_nine: PlayerProfile = PlayerProfile.new()
	from_nine.load_data(old)
	check(from_nine.challenge.day == -1 and from_nine.challenge.best == 0, "an older save loads with no challenge played")
	var junk: Dictionary = profile.to_data()
	junk.challenge = {"day": "x", "best": -5, "medal": 99}
	var strict: PlayerProfile = PlayerProfile.new()
	strict.load_data(junk)
	check(strict.challenge.day == 0 and strict.challenge.best == 0 and strict.challenge.medal == 3, "a damaged state is clamped")

func screen_checks() -> void:
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	PlayerProfile.path_override = "user://challenge_test_screens.json"
	if FileAccess.file_exists("user://challenge_test_screens.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://challenge_test_screens.json"))
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile.created = true
	app.show_hall()
	await process_frame
	var button: Button = app.ui.find_child("ChallengeButton", true, false)
	check(button != null, "the Salão has the challenge button")
	button.pressed.emit()
	await process_frame
	var screen: ChallengeScreen = app.ui.find_child("*", true, false) as ChallengeScreen
	for node: Node in app.screen.get_children():
		if node is ChallengeScreen:
			screen = node
	check(screen != null and screen.find_child("ChallengePlay", true, false) != null, "the screen shows today's challenge with a play button")
	for tab: String in ["top", "replays", "today"]:
		screen.find_child("ChallengeTab_" + tab, true, false).pressed.emit()
		await process_frame
	check(screen.tab == "today", "its tabs open")
	# Play it for real through the battle screen.
	var coins: int = app.profile.coins
	app.start_challenge()
	await process_frame
	await process_frame
	var battle: BattleScreen = app.screen as BattleScreen
	check(battle != null and battle.host != null and battle.game.mode == "challenge" and not battle.online and battle.game.remote.is_valid(), "the challenge opens a hosted battle")
	check(not battle.hud.trust_button.visible, "the AI button is hidden")
	var game: LocalMatch = battle.game
	var stage: int = 0
	var last_round: int = -1
	var power: float = 50.0
	var waited: int = Time.get_ticks_msec()
	while battle.challenge_run.is_empty() and Time.get_ticks_msec() - waited < 120000:
		if game.round_number != last_round:
			last_round = game.round_number
			stage = 0
		if stage == 0 and game.can_act():
			var shot: Vector3 = solution(game)
			game.send_intent("aim", {"d": 0.0, "angle": shot.x})
			game.send_intent("charge", {})
			power = shot.y
			stage = 1
		elif stage == 1 and game.active_id == game.local_id and game.state == LocalMatch.State.PLAYER_CHARGING and battle.host.pending.is_empty():
			game.send_intent("release", {"power": power})
			stage = 2
		await process_frame
	check(not battle.challenge_run.is_empty(), "the run ends and is scored")
	var info: Dictionary = battle.challenge_run.result
	check(Replay.list().size() == 1 and Replay.load_file(Replay.list()[0]).meta.score == info.score, "its replay is kept on this computer")
	waited = Time.get_ticks_msec()
	while not is_instance_valid(battle.challenge_card) and Time.get_ticks_msec() - waited < 20000:
		await process_frame
	check(is_instance_valid(battle.challenge_card) and battle.challenge_card.find_child("ChallengeScore", true, false).text == str(int(info.score)), "the result card shows the score")
	await process_frame
	await process_frame
	check(app.profile.challenge.day == Challenge.day_id() and app.profile.challenge.best == info.score and app.profile.coins == coins + int(Challenge.data().reward.coins), "offline, the profile takes the score and pays the day's reward")
	# Watching the run and leaving.
	battle.challenge_card.find_child("ChallengeWatch", true, false).pressed.emit()
	await process_frame
	await process_frame
	check((app.screen as BattleScreen).replay_driver != null and not (app.screen as BattleScreen).replay.is_empty(), "the card can play the run back")
	(app.screen as BattleScreen).leave_watching()
	await process_frame
	check(app.screen_name == "hall", "leaving the replay returns to the Salão")
	app.queue_free()
	await process_frame
