extends SceneTree

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func duel(game: LocalMatch, extra: Dictionary = {}) -> void:
	var config: Dictionary = {"mode": "pvp", "map": "ilha_celeste", "seed": 12345, "turn_seconds": 10,
		"teams": [[{"name": "Nilo", "human": true, "weapon": 0, "level": 5, "tools": ["hp", "shield", "pow"]}], [{"name": "Rival", "weapon": 4, "level": 5}]]}
	config.merge(extra, true)
	game.start(config)

func make_turn(game: LocalMatch, fighter: TankFighter) -> void:
	for other in game.fighters:
		other.delay = 1000.0
	fighter.delay = 0.0
	game.begin_turn()

func settle(game: LocalMatch, frames: int = 1200) -> void:
	for i in range(frames):
		game._physics_process(1.0 / 60)
		if game.state in [LocalMatch.State.PLAYER_AIMING, LocalMatch.State.MATCH_FINISHED] and game.projectiles.is_empty():
			return

func run_tests() -> void:
	# Messages are checked in Portuguese, the source language.
	Lang.override = "pt_BR"
	Lang.setup()
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	duel(game)
	var me: TankFighter = game.fighters[0]
	var rival: TankFighter = game.fighters[1]
	check(game.fighters.size() == 2 and me.team != rival.team, "two fighters on opposite teams")
	check(game.terrain.world_size.x > 1280, "maps are wider than the screen (camera needed)")
	check(game.local_id == 0 and me.human, "human fighter is the local player")
	# Ballistics
	var velocity: Vector2 = Ballistics.launch_velocity(45, 50, 1, game.balance)
	var reflected: Vector2 = Ballistics.launch_velocity(45, 50, -1, game.balance)
	check(is_equal_approx(velocity.x, -reflected.x) and is_equal_approx(velocity.y, reflected.y), "aim mirrors horizontally")
	check(Ballistics.launch_velocity(45, 100, 1, game.balance).length() > velocity.length(), "power changes launch speed")
	check(Ballistics.splash_damage(1000, 60, 50, false, 0.5) == 0, "no damage outside blast radius")
	# Terrain
	var ground: Vector2 = me.position + Vector2(0, 10)
	check(game.terrain.solid(ground), "spawn has solid terrain")
	var removed: int = game.terrain.crater(ground, 42)
	check(removed > 0 and not game.terrain.solid(ground), "crater changes the collision mask")
	var initial_y: float = me.position.y
	me.settled = false
	for i in range(90):
		me.step_fall(1.0 / 60, game.terrain, float(game.balance.gravity))
	check(me.position.y > initial_y + 15 and me.settled, "fighter falls into the crater and lands")
	# Turn order by Delay
	make_turn(game, me)
	check(game.active_id == 0 and game.can_act(), "lowest delay fighter plays and can act")
	check(game.energy == me.max_energy and me.max_energy >= 240, "turn starts with full energy (240 + agility)")
	# Items 1–8 (each use is announced so the screen can show it being consumed)
	var used: Array[Dictionary] = []
	game.skill_used.connect(func(fighter: TankFighter, info: Dictionary) -> void: used.append(info.merged({"who": fighter.player_id})))
	var before: float = game.energy
	check(game.use_item("dmg50") and game.energy == before - 80, "+50% costs 80 energy")
	check(used.size() == 1 and used[0].kind == "power" and used[0].who == 0 and ResourceLoader.exists(str(used[0].icon)), "using a skill emits skill_used with its icon")
	check(game.use_item("plus1"), "+1 attack accepted")
	check(not game.use_item("plus2") and not game.use_item("triple"), "only one multi-shot item per turn")
	check(used.size() == 2 and used[1].kind == "multi", "refused items are not shown as consumed")
	check(game.use_item("dmg20") and not game.use_item("dmg30"), "energy limits item combos")
	var plan: Dictionary = game.compose_plan(me)
	check(plan.extra == 1 and plan.damage == roundi(260 * 0.9 * 1.7), "+1 and damage bonuses stack additively")
	# Charge bar resets once at full force, then fires at the second maximum.
	game.charge()
	check(game.state == LocalMatch.State.PLAYER_CHARGING, "space starts charging")
	var resets: int = 0
	var last: float = 0.0
	for i in range(400):
		game._physics_process(1.0 / 60)
		if game.state != LocalMatch.State.PLAYER_CHARGING:
			break
		if game.power < last:
			resets += 1
		last = game.power
	check(resets == 1 and game.state == LocalMatch.State.PROJECTILE_FLYING and me.last_power == 100.0, "force bar gives one retry, then fires at 100")
	settle(game)
	check(me.stats.shots == 2, "+1 fires a second volley")
	check(me.delay > 1000.0, "acting adds delay (base + items)")
	check(game.active_id == 1 or not game.running, "turn passes to the fighter with lower delay")
	# Triple balls, POW rules
	make_turn(game, me)
	check(game.use_item("triple"), "three balls accepted")
	me.pow_gauge = 100
	check(not game.activate_pow(), "POW is incompatible with three balls")
	game.power = 60
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.release_shot()
	check(game.projectiles.size() == 3 and game.projectiles[0].damage == 130, "three balls fire three -50% projectiles")
	settle(game)
	make_turn(game, me)
	me.pow_gauge = 100
	used.clear()
	check(game.activate_pow(), "full POW bar can be activated")
	check(used.size() == 1 and used[0].kind == "pow" and used[0].icon == "pow", "arming POW is shown like a skill")
	game.power = 55
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.release_shot()
	check(me.pow_gauge == 0 and str(game.projectiles[0].special.get("kind", "")) == "split" and game.projectiles[0].damage == roundi(260 * 1.2), "Tijolaço POW (Desabamento) resets the bar")
	settle(game)
	# Paper plane
	make_turn(game, me)
	var start_x: float = me.position.x
	check(game.toggle_fly() and game.energy == me.max_energy - 100, "plane costs 100 energy")
	check(not game.use_item("dmg10"), "plane blocks other items")
	me.angle = 40
	game.power = 40
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.release_shot()
	check(game.projectiles[0].fly and game.projectiles[0].damage == 0, "plane projectile carries no damage")
	settle(game)
	check(absf(me.position.x - start_x) > 60 or me.hp == 0, "plane moves the shooter to the landing point")
	check(me.fly_cooldown > 0, "plane has a cooldown")
	# Tools Z/X/C
	if me.hp > 0:
		make_turn(game, me)
		me.hp = 300
		check(game.use_tool(0) and me.hp == 600 and me.tools[0] == "", "life potion heals 300 and is consumed")
		check(game.use_tool(1) and me.shield < 1.0, "shield tool arms damage reduction")
		check(game.use_tool(2) and me.pow_gauge == 100, "POW flask fills the bar")
		check(used.slice(-3).map(func(info: Dictionary) -> String: return info.kind) == ["heal", "shield", "powmax"], "tools are shown being consumed")
		check(not game.use_tool(0), "consumed tool cannot be reused")
		var hp_before: int = me.hp
		# Small blasts: prone fighters sit low, a big crater would drop them off the map.
		var probe: TankProjectile = TankProjectile.new()
		probe.radius = 10
		game.resolve_impact(probe, me.center())
		check(hp_before - me.hp <= 50 and me.shield == 1.0, "shield halves one hit (0-damage probe) and is spent")
		var bomb: TankProjectile = TankProjectile.new()
		bomb.owner_id = 1
		bomb.damage = 200
		bomb.radius = 10
		hp_before = me.hp
		game.resolve_impact(bomb, me.center())
		check(me.hp == hp_before - 200, "direct hit deals full damage")
		check(rival.stats.damage == 200 and me.pow_gauge == 100, "damage feeds stats and POW")
	# PASS and timeout
	make_turn(game, me)
	var delay_before: float = me.delay
	game.pass_turn()
	settle(game)
	var expected: float = (1000.0 - me.agility) * 0.55
	check(is_equal_approx(me.delay - delay_before, expected), "PASS adds reduced delay")
	make_turn(game, me)
	var round_before: int = game.round_number
	delay_before = me.delay
	game.remaining = 0.01
	settle(game)
	check(game.round_number == round_before + 1 and is_equal_approx(me.delay - delay_before, expected), "timer expiry ends the turn like a pass")
	# Freeze skips the next turn
	make_turn(game, rival)
	game.set_auto_play(false)
	rival.frozen = 1
	make_turn(game, rival)
	check(game.skip_turn and rival.frozen == 0, "frozen fighter loses the turn")
	# DDTank dashed flight line: dashes measured along the path, gaps between them
	var dashes: PackedVector2Array = ShotTrails.dash_segments(PackedVector2Array([Vector2.ZERO, Vector2(60, 0), Vector2(100, 0)]))
	check(dashes.size() % 2 == 0 and dashes.size() >= 10 and is_equal_approx(dashes[0].distance_to(dashes[1]), ShotTrails.DASH) and dashes[2].x - dashes[1].x > 0.0, "shot line is drawn as dashes along the whole path")
	# Tunneling
	var bullet: TankProjectile = TankProjectile.new()
	bullet.terrain = game.terrain
	bullet.position = Vector2(400, 300)
	bullet.velocity = Vector2(0, 25000)
	bullet.gravity = 0
	root.add_child(bullet)
	bullet.advance(1.0 / 60)
	check(not bullet.live and bullet.position.y < game.terrain.world_size.y, "fast projectile does not tunnel through ground")
	bullet.queue_free()
	# Falling out of the world and winning
	rival.position = Vector2(rival.position.x, game.terrain.world_size.y + 30)
	rival.velocity_y = 400
	rival.settled = false
	for i in range(10):
		rival.step_fall(1.0 / 60, game.terrain, float(game.balance.gravity))
	check(rival.hp == 0, "falling out of the map eliminates")
	var result: Array[int] = []
	game.finished.connect(func(winner: int) -> void: result.append(winner))
	check(game.evaluate_winner() and result == [0], "last team standing wins")
	check(not game.can_act(), "finished match rejects actions")
	# Teams: 2v2 needs both rivals down; simultaneous wipe is a draw
	game.start({"mode": "pvp", "map": "patio_templo", "seed": 7, "teams": [[{"name": "A", "human": true}, {"name": "B"}], [{"name": "C"}, {"name": "D"}]]})
	check(game.fighters.size() == 4 and game.fighters[2].team == 1, "2v2 battle spawns four fighters")
	game.fighters[2].hp = 0
	check(not game.evaluate_winner(), "one rival down is not a victory")
	for fighter in game.fighters:
		fighter.hp = 0
	result.clear()
	check(game.evaluate_winner() and result == [-1], "simultaneous wipe is a draw")
	# Full automatic battle (Confiar on the local player)
	game.start({"mode": "pvp", "map": "camara_guardiao", "seed": 99, "turn_seconds": 10, "teams": [[{"name": "A", "human": true, "weapon": 1, "level": 8}], [{"name": "B", "weapon": 2, "level": 8}]]})
	game.set_auto_play(true)
	var frames: int = 0
	var started: int = Time.get_ticks_msec()
	while game.running and frames < 60 * 600:
		game._physics_process(1.0 / 60)
		frames += 1
	check(not game.running and game.state == LocalMatch.State.MATCH_FINISHED, "automatic battle finishes (%d turns, %.1fs real)" % [game.round_number, (Time.get_ticks_msec() - started) / 1000.0])
	game.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
