extends SceneTree

# Replays (0.22): a battle is its configuration plus the intents stamped by tick. A scripted
# duel is played on a LocalHost (the daily challenge's host), its replay is run again by the
# ReplayRunner (what the server does to check a score) and by the on-screen driver, and both
# must end in the very same battle.

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
	Replay.dir_override = "user://replay_test_files"
	clear_files()
	input_checks()
	var duel: Dictionary = await scripted_duel()
	replay_checks(duel)
	file_checks(duel)
	await screen_checks(duel)
	clear_files()
	print("REPLAY RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func clear_files() -> void:
	for path: String in Replay.list():
		Replay.delete(path)

func input_checks() -> void:
	check(Replay.clean_input([12, 1, "aim", {"d": 1, "angle": 41.5}], 2) == [12, 1, "aim", {"d": 1, "angle": 41.5}], "a valid intent passes")
	check(Replay.clean_input([12.0, 0.0, "release", {"power": 60.25}], 2) == [12, 0, "release", {"power": 60.25}], "numbers from JSON become integers where they are ticks and fighters")
	check(Replay.clean_input([1, 0, "teleport", {}], 2).is_empty(), "unknown actions are refused")
	check(Replay.clean_input([1, 0, "leave", {}], 2).is_empty() and not Replay.clean_input([1, 0, "leave", {}], 2, true).is_empty(), "'leave' is only for the server's own stamps")
	check(Replay.clean_input([1, 5, "pass", {}], 2).is_empty() and Replay.clean_input([-1, 0, "pass", {}], 2).is_empty(), "a fighter or tick out of range is refused")
	check(Replay.clean_input(["x", 0, "pass", {}], 2).is_empty() and Replay.clean_input([1, 0, "pass", 3], 2).is_empty() and Replay.clean_input([1, 0], 2).is_empty() and Replay.clean_input("junk", 2).is_empty(), "wrong types are refused")
	var data: Array = Replay.clean_input([1, 0, "item", {"id": "plus2_but_a_very_long_name_that_goes_on_and_on", "evil": {"x": 1}, "power": "high"}], 2)
	check(str(data[3].id).length() == 32 and not data[3].has("evil") and not data[3].has("power"), "data keeps plain values from the known keys only")
	var config: Dictionary = {"mode": "pvp", "seed": 5, "teams": [[{"name": "A"}], [{"name": "B"}]]}
	var raw: Dictionary = {"v": 1, "config": config, "inputs": [[9, 0, "pass", {}], [3, 0, "move", {"d": 1}]], "ticks": 20, "winner": 0}
	var cleaned: Dictionary = Replay.clean(raw)
	check(not cleaned.is_empty() and cleaned.inputs[0][0] == 3 and cleaned.inputs[1][0] == 9, "a replay's intents are sorted by tick")
	var shuffled: Dictionary = Replay.clean({"v": 1, "config": config, "inputs": [[7, 0, "aim", {"d": 0}], [2, 0, "move", {"d": 1}], [7, 0, "charge", {}], [7, 0, "release", {"power": 5}], [2, 0, "pass", {}]]})
	check(shuffled.inputs.map(func(e: Array) -> String: return "%d%s" % [e[0], e[2]]) == ["2move", "2pass", "7aim", "7charge", "7release"], "intents of one tick keep the order they were sent in")
	check(Replay.clean({"v": 2, "config": config, "inputs": []}).is_empty() and Replay.clean({"v": 1, "config": {"teams": [[], []]}, "inputs": []}).is_empty() and Replay.clean({"v": 1, "config": config, "inputs": [[1, 0, "nope", {}]]}).is_empty(), "another version, a missing seed or a bad intent make it unusable")
	var many: Array = []
	for i in range(Replay.MAX_INPUTS + 1):
		many.append([i, 0, "move", {"d": 0}])
	check(Replay.clean({"v": 1, "config": config, "inputs": many}).is_empty(), "a replay cannot carry an endless list of intents")

func solution(game: LocalMatch) -> Vector3:
	var me: TankFighter = game.local()
	var foe: TankFighter = game.fighters[1]
	var scale: float = float(me.weapon.get("projectile", {}).get("wind_scale", 1.0))
	return EnemyAI.choose_shot(me, foe, game.terrain, game.wind * float(game.balance.wind_accel) * scale * game.wind_factor(me), game.balance)

# Plays the local fighter with the shot solver (aim, charge, release) on a LocalHost until the
# battle ends. Returns the replay and the final checksum.
func scripted_duel() -> Dictionary:
	var config: Dictionary = {"mode": "pvp", "map": "ilha_celeste", "seed": 4242, "turn_seconds": 15, "lockstep": true, "local": 0, "teams": [[{"name": "Alfa", "human": true, "level": 8}], [{"name": "Robo", "level": 8}]]}
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start(config)
	var host: LocalHost = LocalHost.new()
	host.game = game
	game.remote = host.submit
	root.add_child(host)
	host.set_physics_process(false)
	var stage: int = 0
	var last_round: int = -1
	var power: float = 50.0
	for i in range(60000):
		if not game.running:
			break
		if game.round_number != last_round:
			last_round = game.round_number
			stage = 0
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
	var replay: Dictionary = Replay.make(config, host.history, host.tick, game.winner_team, {"kind": "pvp", "names": ["Alfa", "Robo"], "at": 1})
	var result: Dictionary = {"replay": replay, "checksum": game.checksum(), "text": game.checksum_text(), "ticks": host.tick, "winner": game.winner_team, "running": game.running}
	game.queue_free()
	host.queue_free()
	return result

func replay_checks(duel: Dictionary) -> void:
	var replay: Dictionary = duel.replay
	check(not (replay.inputs as Array).is_empty() and (replay.inputs as Array).any(func(entry: Array) -> bool: return entry[2] == "release"), "the host recorded the shots (%d intents, %d ticks)" % [replay.inputs.size(), duel.ticks])
	check(duel.winner >= 0 or duel.running, "the scripted battle reached a result or the cap (winner %d)" % duel.winner)
	var cleaned: Dictionary = Replay.clean(JSON.parse_string(JSON.stringify(replay)), true)
	check(not cleaned.is_empty() and cleaned.inputs.size() == replay.inputs.size() and cleaned.ticks == replay.ticks, "the replay survives JSON and the cleaning")
	var runner: ReplayRunner = ReplayRunner.new()
	root.add_child(runner)
	runner.begin(cleaned)
	runner.run_all()
	check(runner.tick == duel.ticks and runner.game.checksum() == duel.checksum and runner.game.winner_team == duel.winner, "running it again gives the same battle, tick for tick")
	check(runner.game.checksum_text() == duel.text, "down to every position and every point of life")
	runner.queue_free()
	# A doctored shot is a different battle.
	var doctored: Dictionary = cleaned.duplicate(true)
	for entry: Array in doctored.inputs:
		if entry[2] == "release":
			entry[3].power = float(entry[3].power) * 0.5
			break
	var other: ReplayRunner = ReplayRunner.new()
	root.add_child(other)
	other.begin(doctored)
	other.run_all()
	check(other.game.checksum() != duel.checksum, "changing one shot changes the battle")
	other.queue_free()
	# The limit stops a run that would go on.
	var capped: ReplayRunner = ReplayRunner.new()
	root.add_child(capped)
	capped.begin(cleaned, 300)
	capped.run_all()
	check(capped.tick == 300 and capped.game.running, "a run can be capped at a number of ticks")
	var sliced: ReplayRunner = ReplayRunner.new()
	root.add_child(sliced)
	sliced.begin(cleaned)
	var slices: int = 0
	while not sliced.run_slice(200):
		slices += 1
	check(slices > 1 and sliced.game.checksum() == duel.checksum, "slices of 200 ticks give the same result (%d slices)" % slices)
	capped.queue_free()
	sliced.queue_free()

func file_checks(duel: Dictionary) -> void:
	var path: String = Replay.save(duel.replay)
	check(path != "" and FileAccess.file_exists(path), "a replay is saved on the computer")
	var loaded: Dictionary = Replay.load_file(path)
	check(not loaded.is_empty() and loaded.ticks == duel.replay.ticks and loaded.inputs.size() == duel.replay.inputs.size() and loaded.config.seed == 4242, "and read back")
	check(Replay.describe(loaded).contains("Alfa vs Robo") and Replay.describe(loaded).contains("Combate Livre") and Replay.describe(loaded).contains("Ilha Celeste"), "its line in the list names the players, the kind and the map")
	for i in range(Replay.KEEP + 3):
		await_ms(2)
		Replay.save(duel.replay)
	check(Replay.list().size() == Replay.KEEP, "only the last %d are kept" % Replay.KEEP)
	var broken: FileAccess = FileAccess.open(Replay.folder() + "/zz_broken.json", FileAccess.WRITE)
	broken.store_string("{not json")
	broken.close()
	check(Replay.load_file(Replay.folder() + "/zz_broken.json").is_empty(), "a damaged file is just refused")
	check(Replay.load_file(Replay.folder() + "/missing.json").is_empty(), "so is a missing one")
	clear_files()

func await_ms(ms: int) -> void:
	# Names carry the clock: keep two saves from landing on the same name.
	OS.delay_msec(ms)

func screen_checks(duel: Dictionary) -> void:
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.show_hall()
	await process_frame
	app.start_replay(Replay.clean(JSON.parse_string(JSON.stringify(duel.replay)), true))
	await process_frame
	await process_frame
	var screen: BattleScreen = app.screen as BattleScreen
	check(screen != null and app.screen_name == "battle" and not screen.replay.is_empty() and screen.replay_driver != null and screen.watch_bar != null, "the replay opens a battle with its own driver and bar")
	check(screen.game.spectator and not screen.game.can_act() and not screen.online, "it has no controls")
	screen.game.local().angle = 12.0
	screen.game.use_item("plus2")
	check(screen.game.turn_items.is_empty(), "keys do nothing in a replay")
	var bar: ReplayBar = screen.watch_bar
	bar.find_child("Speed4", true, false).pressed.emit()
	check(is_equal_approx(screen.replay_driver.speed, 4.0), "the 4x button speeds it up")
	bar.find_child("ReplayPause", true, false).pressed.emit()
	var held: int = screen.replay_driver.tick
	for i in range(20):
		await process_frame
	check(screen.game.paused and screen.replay_driver.tick == held, "pausing stops the replay")
	bar.find_child("ReplayPause", true, false).pressed.emit()
	var ended: bool = true
	var waited: int = Time.get_ticks_msec()
	while not screen.replay_driver.done and Time.get_ticks_msec() - waited < 90000:
		await process_frame
	ended = screen.replay_driver.done
	check(ended and screen.replay_driver.tick == duel.ticks, "it plays to the end at the recorded tick")
	check(screen.game.checksum() == duel.checksum and screen.game.checksum_text() == duel.text, "and arrives at exactly the same battle")
	check(screen.replay_driver.progress() == 1.0, "the progress bar fills")
	# The outcome shows, then the screen goes back.
	var back: bool = false
	waited = Time.get_ticks_msec()
	while Time.get_ticks_msec() - waited < 15000:
		if app.screen_name == "hall":
			back = true
			break
		await process_frame
	check(back, "after the outcome it returns to the Salão")
	check(app.profile.matches == 0 and app.profile.coins == 300, "watching a replay pays and records nothing")
	app.queue_free()
	await process_frame
