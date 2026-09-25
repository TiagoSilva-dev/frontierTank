extends SceneTree

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func expedition(game: LocalMatch, difficulty: String = "normal", party: int = 1) -> void:
	var team: Array = [{"name": "Nilo", "human": true, "weapon": 0, "level": 6}]
	for i in range(party - 1):
		team.append({"name": "Aliado%d" % i, "weapon": 2, "level": 6})
	game.start({"mode": "pve", "map": "templo_sol", "seed": 123, "difficulty": difficulty, "teams": [team, [{"name": "Rei Hélio", "boss": true, "party": party}]]})

func run_tests() -> void:
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	# Remove intentional aim dispersion to verify the solver independently.
	game.balance.pve.power_error = 0.0
	expedition(game)
	var hero: TankFighter = game.fighters[0]
	var boss: TankFighter = game.fighters[1]
	check(game.pve and boss.is_boss and boss.team == 1, "PvE creates the boss on the rival team")
	check(game.terrain.solid(Vector2(800, 520)), "temple has continuous destructible floor")
	check(hero.prone and hero.body_size.x > hero.body_size.y, "hero battles lying prone (PixelLab prone state)")
	check(boss.idle_animation.frames.size() == 5, "boss PixelLab idle frames loaded")
	check(boss.attack_animation.frames.size() == 9, "boss PixelLab attack frames loaded")
	check(boss.max_hp == roundi(4200 * 0.6), "solo party scales boss life")
	for fighter in game.fighters:
		fighter.delay = 1000.0
	boss.delay = 0.0
	game.begin_turn()
	check(game.active_id == 1 and not game.can_act(), "human actions blocked during boss turn")
	game.charge()
	check(game.state == LocalMatch.State.PLAYER_AIMING, "human cannot charge the boss weapon")
	check(not game.use_item("dmg50"), "human cannot spend the boss energy")
	game.paused = true
	game._physics_process(5)
	check(game.ai_time == 0, "pause freezes the boss")
	game.paused = false
	for i in range(240):
		game._physics_process(1.0 / 60)
		if game.state == LocalMatch.State.PROJECTILE_FLYING:
			break
	check(game.state == LocalMatch.State.PROJECTILE_FLYING, "boss calculates and fires autonomously")
	check(boss.attack_animation.visible, "boss cast animation triggered by the attack")
	var hp_before: int = hero.hp
	for i in range(900):
		game._physics_process(1.0 / 60)
		if game.active_id == 0 or not game.running:
			break
	check(game.active_id == 0, "boss attack resolves back to the player")
	check(hero.hp < hp_before, "boss hits the player using terrain and wind")
	boss.hp = boss.max_hp / 2
	for fighter in game.fighters:
		fighter.delay = 1000.0
	boss.delay = 0.0
	game.begin_turn()
	check(game.boss_enraged and boss.weapon.damage == 320, "boss enrages at half health")
	check(game.status_message.contains("FÚRIA"), "strong attack is announced")
	boss.hp = 0
	check(game.evaluate_winner() and game.winner_team == 0, "defeating the boss wins the expedition")
	expedition(game, "nightmare", 4)
	check(game.fighters.size() == 5 and not game.boss_enraged, "retry resets the phase with a party of four")
	check(game.fighters[4].max_hp == roundi(4200 * 2.6 * 1.2), "difficulty and party size scale the boss")
	check(game.fighters[4].weapon.damage == roundi(230 * 1.7), "difficulty scales boss damage")
	game.queue_free()
	await process_frame
	print("PVE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
