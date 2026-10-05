extends SceneTree

# Training battle (0.21): the data, the profile state and operation, the starter
# checklist and a scripted run of the whole lesson (coach steps, misses and hint, the
# dummy mending itself, skill, POW, the dummy falling and the reward).

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
	PlayerProfile.path_override = "user://tutorial_test_profile.json"
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	data_checks()
	profile_checks()
	starter_checks()
	await battle_checks()
	await city_checks()
	print("TUTORIAL RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func data_checks() -> void:
	var ids: Array = Tutorial.steps().map(func(step: Dictionary) -> String: return str(step.id))
	check(ids.size() == 8, "the lesson has 8 steps")
	var unique: Dictionary = {}
	for id: String in ids:
		unique[id] = true
	check(unique.size() == ids.size(), "step ids are unique")
	var known: Array = ["moved", "aimed", "hit", "plus2", "pow", "done"]
	var ok: bool = true
	for step: Dictionary in Tutorial.steps():
		ok = ok and (step.has("wait") != step.has("need")) and (not step.has("need") or str(step.need) in known) and str(step.name) != "" and str(step.text) != ""
	check(ok, "every step waits for a key or for a known action and has its texts")
	check(str(Tutorial.steps().back().need) == "done", "the last step waits for the dummy to fall")
	var dummy: Dictionary = {}
	for entry: Dictionary in balance.enemies:
		if entry.id == Tutorial.settings(balance).dummy:
			dummy = entry
	check(not dummy.is_empty() and dummy.rank == "totem" and ResourceLoader.exists(str(dummy.sprite)), "the dummy is a totem with its own sprite")
	var rules: Dictionary = Tutorial.settings(balance)
	var map: Dictionary = {}
	for entry: Dictionary in balance.maps:
		if entry.id == rules.map:
			map = entry
	check(not map.is_empty() and float(rules.dummy_x) - float(rules.player_x) > 300, "the dummy stands well away from the player")
	var reward_ok: bool = true
	for id: String in rules.reward.items:
		reward_ok = reward_ok and (Pets.is_egg(id) or not Armory.stone_def(id).is_empty())
	check(reward_ok, "the reward items exist")
	check(Tutorial.reward_text(balance).contains("200") and Tutorial.reward_text(balance).contains("3x"), "the reward line names coins, EXP and items")

func profile_checks() -> void:
	fresh("user://tutorial_test_profile.json")
	var profile: PlayerProfile = PlayerProfile.new()
	profile.created = true
	check(profile.tutorial == "" and Tutorial.should_offer(profile), "a new character is offered the training")
	var config: Dictionary = Tutorial.config(balance, profile)
	check(config.mode == "tutorial" and config.teams.size() == 2 and config.teams[1][0].enemy == "boneco_treino" and config.teams[0][0].human, "the training config puts the player against the dummy")
	check(config.teams[0][0].tools == ["", "", ""], "the training starts without tools")
	var coins: int = profile.coins
	check(profile.apply_op("tutorial", ["skip"], balance).error == "" and profile.tutorial == "skipped" and not Tutorial.should_offer(profile), "'not now' is remembered and not offered again")
	check(profile.apply_op("tutorial", ["fly"], balance).error != "" and profile.apply_op("tutorial", [], balance).error != "", "unknown actions are refused")
	check(profile.apply_op("tutorial", ["done"], balance).error == "" and profile.tutorial == "done", "finishing marks the training done (even after skipping)")
	var rules: Dictionary = Tutorial.settings(balance).reward
	check(profile.coins == coins + int(rules.coins) and profile.experience == int(rules.exp) and int(profile.items.get("pedra_fortalecimento", 0)) == 3 and int(profile.items.get("pet_egg", 0)) == 1, "the reward arrives")
	profile.apply_op("tutorial", ["done"], balance)
	check(profile.coins == coins + int(rules.coins) and int(profile.items.get("pet_egg", 0)) == 1, "the reward is paid once")
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(copy.tutorial == "done" and int(profile.to_data().version) == 11, "the state survives the save (version 11)")
	# Saves from before 0.21: veterans are not offered the training, newcomers are.
	var old: Dictionary = profile.to_data()
	old.erase("tutorial")
	old.version = 8
	old.matches = 12
	var veteran: PlayerProfile = PlayerProfile.new()
	veteran.load_data(old)
	check(veteran.tutorial == "done" and not Tutorial.should_offer(veteran), "a save that already played counts as trained")
	old.matches = 0
	old.experience = 0
	var fresh: PlayerProfile = PlayerProfile.new()
	fresh.load_data(old)
	check(fresh.tutorial == "" and Tutorial.should_offer(fresh), "a save that never played is still offered the training")
	var played: PlayerProfile = PlayerProfile.new()
	played.created = true
	played.matches = 1
	check(not Tutorial.should_offer(played), "someone who already played a match is not interrupted")

func starter_checks() -> void:
	fresh("user://tutorial_test_starter.json")
	var profile: PlayerProfile = PlayerProfile.new()
	var state: Dictionary = MissionsBoard.ensure(profile)
	check(state.starter.progress.size() == MissionsBoard.starter_defs().size() and state.starter.claimed.is_empty(), "a new profile has the starter checklist")
	check(MissionsBoard.claimable(profile) == 1 and MissionsBoard.streak_ready(profile), "only the first day of the streak waits at first")
	check(profile.apply_op("mission_claim", ["s_pvp"], balance).error != "", "an unfinished starter mission cannot be claimed")
	# Events from battles.
	var game: LocalMatch = LocalMatch.new()
	game.pve = false
	game.winner_team = 1
	var fighter: TankFighter = TankFighter.new()
	fighter.team = 0
	MissionsBoard.progress_match(profile, game, fighter)
	check(int(profile.missions.starter.progress.s_pvp) == 1 and int(profile.missions.starter.progress.s_win) == 0, "losing a PvP match counts as played, not as a win")
	game.winner_team = 0
	MissionsBoard.progress_match(profile, game, fighter)
	check(int(profile.missions.starter.progress.s_win) == 1, "winning counts for the first victory")
	game.pve = true
	MissionsBoard.progress_match(profile, game, fighter, null)
	check(int(profile.missions.starter.progress.s_instance) == 0, "an instance only counts with its expedition")
	var run: InstanceRun = InstanceRun.new(InstanceRun.rules(), "templo_sol", {}, 1, [], profile)
	MissionsBoard.progress_match(profile, game, fighter, run)
	check(int(profile.missions.starter.progress.s_instance) == 1, "finishing an expedition counts")
	check(MissionsBoard.claimable(profile) >= 3, "finished starter missions are ready to claim")
	# Events from operations.
	profile.add_item("pedra_fortalecimento", 1)
	var weapon: Dictionary = profile.equipped_instance("arma")
	check(profile.apply_op("strengthen", [int(weapon.uid)], balance).error == "" and int(profile.missions.starter.progress.s_strengthen) == 1, "trying the Ferreiro advances its mission")
	profile.add_item("egg_sol", 1)
	check(profile.apply_op("pet_hatch", ["egg_sol"], balance).error == "" and int(profile.missions.starter.progress.s_hatch) == 1, "hatching an egg advances its mission")
	var pets: Array = profile.pets.duplicate(true)
	check(profile.apply_op("hunt_set", ["sol", 1, [int(pets[0].uid)]], balance).error == "" and int(profile.missions.starter.progress.s_hunt) == 1, "starting a hunt advances its mission")
	# Claiming.
	var coins: int = profile.coins
	var claim: Dictionary = profile.apply_op("mission_claim", ["s_win"], balance)
	check(claim.error == "" and profile.coins == coins + 150 and int(profile.items.get("pedra_fortalecimento", 0)) == 2, "the claim pays coins and items")
	check(profile.apply_op("mission_claim", ["s_win"], balance).error != "", "a starter reward is claimed once")
	for mission: Dictionary in MissionsBoard.starter_defs():
		profile.apply_op("mission_claim", [str(mission.id)], balance)
	check(MissionsBoard.starter_finished(profile) and profile.missions.starter.claimed.size() == MissionsBoard.starter_defs().size(), "claiming every step ends the checklist with its bonus")
	var bonus_coins: int = profile.coins
	profile.apply_op("mission_claim", ["s_pvp"], balance)
	check(profile.coins == bonus_coins, "the bonus is paid once")
	# A new UTC day renews the dailies and keeps the checklist.
	profile.missions.day -= 1
	profile.missions.progress.pvp_wins = 3
	var renewed: Dictionary = MissionsBoard.ensure(profile)
	check(int(renewed.progress.pvp_wins) == 0 and renewed.starter.claimed.size() == MissionsBoard.starter_defs().size(), "the daily renewal keeps the starter progress")
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(copy.missions == profile.missions, "the checklist survives the save")
	# Saves from before: what the character did counts.
	var old: Dictionary = {"version": 8, "created": true, "matches": 6, "victories": 3, "experience": 900, "missions": {"day": 1, "progress": {}, "claimed": [], "daily_bonus": false}}
	var veteran: PlayerProfile = PlayerProfile.new()
	veteran.load_data(old)
	check(int(veteran.missions.starter.progress.s_pvp) == 1 and int(veteran.missions.starter.progress.s_win) == 1 and int(veteran.missions.starter.progress.s_hatch) == 0, "a veteran's past matches and wins are credited")

func press_enter(coach: TutorialCoach) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	coach._unhandled_key_input(event)

# Steps the match (and the coach) until the player's next turn begins.
func next_turn(screen: BattleScreen, limit: int = 4000) -> void:
	var game: LocalMatch = screen.game
	var round_before: int = game.round_number
	for i in range(limit):
		game._physics_process(1.0 / 60)
		screen.coach._process(1.0 / 60)
		if game.state == LocalMatch.State.MATCH_FINISHED:
			return
		if game.round_number > round_before and game.state == LocalMatch.State.PLAYER_AIMING:
			return

func solution(game: LocalMatch) -> Vector3:
	var me: TankFighter = game.local()
	var dummy: TankFighter = game.fighters[1]
	var scale: float = float(me.weapon.get("projectile", {}).get("wind_scale", 1.0))
	return EnemyAI.choose_shot(me, dummy, game.terrain, game.wind * float(game.balance.wind_accel) * scale * game.wind_factor(me), game.balance)

func fire(game: LocalMatch, angle: float, power: float) -> void:
	game.local().angle = clampf(angle, game.local().angle_range.x, game.local().angle_range.y)
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.power = power
	game.release_shot()

func fire_at_dummy(screen: BattleScreen) -> void:
	var shot: Vector3 = solution(screen.game)
	fire(screen.game, shot.x, shot.y)
	next_turn(screen)

# The test profiles live in user://; start each part from nothing.
func fresh(path: String) -> void:
	PlayerProfile.path_override = path
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func battle_checks() -> void:
	fresh("user://tutorial_test_battle.json")
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile.created = true
	app.show_city()
	await process_frame
	var offer: Control = app.ui.find_child("TutorialOffer", true, false)
	check(offer != null, "the city offers the training to a new character")
	app.start_tutorial()
	await process_frame
	await process_frame
	var screen: BattleScreen = app.screen as BattleScreen
	check(screen != null and screen.coach != null and app.screen_name == "battle", "the training opens a battle with a coach")
	var game: LocalMatch = screen.game
	game.set_physics_process(false)
	screen.coach.set_process(false)
	var coach: TutorialCoach = screen.coach
	var me: TankFighter = game.local()
	var dummy: TankFighter = game.fighters[1]
	check(game.mode == "tutorial" and not game.pve and not game.terrain.destructible, "the training is a local battle on solid ground")
	check(dummy.rank == "totem" and not dummy.acts() and dummy.team != me.team and dummy.rank_title == "Alvo", "the dummy never takes a turn")
	check(dummy.position.x - me.position.x > 300 and dummy.max_hp == int(Tutorial.settings(game.balance).dummy_hp), "the dummy stands across the gap with its life")
	check(game.state == LocalMatch.State.PLAYER_AIMING and game.active_id == game.local_id, "the player opens the battle")
	check(not screen.hud.log_panel.visible, "the coach's card replaces the battle log")
	# 0 welcome -> 1 move
	coach._process(1.0 / 60)
	check(coach.index == 0, "the coach starts with the welcome")
	press_enter(coach)
	coach._process(1.0 / 60)
	check(coach.index == 1, "ENTER moves past the welcome")
	game.moved_distance = 25.0
	coach._process(1.0 / 60)
	check(coach.index == 2, "walking moves to the aiming lesson")
	me.angle += 10.0
	coach._process(1.0 / 60)
	check(coach.index == 3, "changing the angle moves to the wind lesson")
	press_enter(coach)
	coach._process(1.0 / 60)
	check(coach.index == 4 and str(coach.current().id) == "shoot", "ENTER moves to the shooting lesson")
	# The turn clock never runs out during the lesson.
	game.remaining = 0.5
	coach._process(1.0 / 60)
	check(game.remaining >= 30.0, "the coach keeps the turn clock from running out")
	# Two misses: the hint appears.
	fire(game, 45.0, 8.0)
	next_turn(screen)
	check(coach.misses == 1 and coach.hint == "" and coach.index == 4, "a miss keeps the lesson and says to try again")
	check(coach.body_label.text.begins_with("Errou!"), "the card explains the miss")
	fire(game, 45.0, 8.0)
	next_turn(screen)
	check(coach.misses == 2 and coach.hint.begins_with("Dica:") and coach.body_label.text.contains("Dica:"), "after two misses the card suggests angle and force")
	check(dummy.hp == dummy.max_hp, "a miss leaves the dummy untouched")
	# A hit.
	fire_at_dummy(screen)
	check(dummy.max_hp > dummy.hp or coach.flags.hit, "a good shot hits the dummy")
	check(coach.index == 5 and str(coach.current().id) == "skill", "the hit moves to the skills lesson")
	check(dummy.hp == dummy.max_hp, "the dummy mends itself between turns")
	# Skill: +2 attacks.
	check(game.use_item("plus2") and "plus2" in game.turn_items, "skill 1 is used on the player's turn")
	fire_at_dummy(screen)
	check(coach.index == 6 and str(coach.current().id) == "pow", "using +2 attacks moves to the POW lesson")
	check(me.pow_gauge >= float(game.balance.pow_max) - 0.01, "the POW gauge is full for its lesson")
	check(dummy.hp == dummy.max_hp and dummy.hp_floor == 1, "the dummy cannot fall before the last lesson")
	# POW.
	check(game.activate_pow() and game.turn_pow, "the POW is armed")
	fire_at_dummy(screen)
	check(coach.index == 7 and coach.is_last(), "firing the POW moves to the last lesson")
	check(dummy.hp >= 1 and dummy.hp_floor == 0, "from the last lesson's first turn on the dummy can fall")
	# Knock it down.
	var turns: int = 0
	while game.state != LocalMatch.State.MATCH_FINISHED and turns < 25:
		fire_at_dummy(screen)
		turns += 1
	check(game.state == LocalMatch.State.MATCH_FINISHED and game.winner_team == me.team and dummy.hp <= 0, "knocking the dummy down wins the training (%d shots)" % turns)
	check(coach.flags.done and screen.end_timer > 0.0 and not is_instance_valid(coach.done_box), "the victory moment plays before the card")
	screen.show_results()
	check(is_instance_valid(coach.done_box) and not coach.card.visible, "the closing card replaces the lesson")
	# Closing the card pays the reward once and opens the checklist.
	var coins: int = app.profile.coins
	await app.finish_tutorial()
	await process_frame
	check(app.profile.tutorial == "done" and app.profile.coins == coins + int(Tutorial.settings(balance).reward.coins), "closing the card pays the reward")
	check(app.screen_name == "city" and app.ui.get_children().any(func(node: Node) -> bool: return node is MissionScreen and node.tab == "starter"), "the city opens on the first steps checklist")
	check(app.profile.matches == 0 and app.profile.victories == 0, "the training does not count as a ranked match")
	app.queue_free()
	await process_frame

func city_checks() -> void:
	fresh("user://tutorial_test_city.json")
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile.created = true
	app.show_city()
	await process_frame
	var later: Button = app.ui.find_child("TutorialLater", true, false)
	check(later != null, "the offer has a 'not now' button")
	later.pressed.emit()
	await process_frame
	check(app.profile.tutorial == "skipped" and app.ui.find_child("TutorialOffer", true, false) == null, "'not now' closes the offer and remembers it")
	app.show_city()
	await process_frame
	check(app.ui.find_child("TutorialOffer", true, false) == null, "the offer does not come back")
	app.open_help()
	await process_frame
	var training: Button = app.ui.find_child("HelpTraining", true, false)
	check(training != null, "AJUDA keeps a button to repeat the training")
	training.pressed.emit()
	await process_frame
	await process_frame
	check(app.screen_name == "battle" and (app.screen as BattleScreen).coach != null, "the help button starts the training again")
	var bar: Control = null
	app.show_city()
	await process_frame
	app.profile.apply_op("streak_claim", [], app.balance)
	app.show_city()
	await process_frame
	bar = app.ui.find_child("MissionBadge", true, false)
	check(bar != null and not bar.visible, "the quest badge is hidden while nothing can be claimed")
	app.profile.missions = {}
	MissionsBoard.note(app.profile, "pvp_played")
	await process_frame
	await process_frame
	check(bar.visible, "the quest badge shows when a contract is ready")
	app.queue_free()
	await process_frame
