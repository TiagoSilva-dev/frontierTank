extends SceneTree

# 0.8: POW phases and the bigger weapon/projectile art. The regression part plays the
# same seeded shots with the visual scales at 1.0 and at the configured values and
# checks that damage, the crater and hit detection are identical.

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

func set_scales(projectile: float, pow_projectile: float, back_weapon: float) -> void:
	var visual: Dictionary = Armory.data().visual
	visual.projectile_scale = projectile
	visual.pow_projectile_scale = pow_projectile
	visual.back_weapon_scale = back_weapon

func duel(game: LocalMatch, weapon: String) -> void:
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 4242, "turn_seconds": 10,
		"teams": [[{"name": "Nilo", "human": true, "arma": {"id": weapon, "quality": "normal", "level": 0}, "level": 5}], [{"name": "Rival", "arma": {"id": "trovao", "quality": "normal", "level": 0}, "level": 5}]]})
	var me: TankFighter = game.fighters[0]
	var rival: TankFighter = game.fighters[1]
	# Face to face on the first island, no wind, the local player to act.
	me.position = Vector2(260, game.terrain.surface_y(260) - 1)
	rival.position = Vector2(520, game.terrain.surface_y(520) - 1)
	me.facing = 1
	rival.facing = -1
	for fighter in game.fighters:
		fighter.delay = 1000.0
	me.delay = 0.0
	game.begin_turn()
	game.wind = 0.0

func shoot(game: LocalMatch, use_pow: bool) -> Dictionary:
	# Aim with the bots' own solver so the shot lands, then fire and resolve it.
	var me: TankFighter = game.fighters[0]
	var rival: TankFighter = game.fighters[1]
	var plan: Vector3 = EnemyAI.choose_shot(me, rival, game.terrain, 0.0, game.balance)
	me.angle = plan.x
	if use_pow:
		me.pow_gauge = 100
		game.activate_pow()
	var sizes: Array = []
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.power = plan.y
	game.release_shot()
	sizes = [game.projectiles[0].sprite_size]
	var first_hit: Array[Vector2] = []
	game.projectiles[0].impacted.connect(func(_p: TankProjectile, point: Vector2) -> void: first_hit.append(point))
	for i in range(1500):
		game._physics_process(1.0 / 60)
		if game.state in [LocalMatch.State.PLAYER_AIMING, LocalMatch.State.MATCH_FINISHED, LocalMatch.State.TURN_STARTED] and game.projectiles.is_empty():
			break
	return {"rival_hp": rival.hp, "my_hp": me.hp, "hit": first_hit[0] if not first_hit.is_empty() else Vector2.INF, "mask": game.terrain.mask.get_data(), "size": sizes[0] if not sizes.is_empty() else 0.0, "hit_radius": rival.hit_radius, "dealt": int(me.stats.damage)}

func run_tests() -> void:
	# Messages are checked in Portuguese, the source language.
	Lang.override = "pt_BR"
	Lang.setup()
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var configured: Dictionary = Armory.data().visual.duplicate()
	check(float(configured.projectile_scale) > 1.0 and float(configured.back_weapon_scale) > 1.0 and float(configured.pow_projectile_scale) > 1.0, "0.8 draws projectiles and the weapon on the back bigger")
	# --- regression: same shots before and after the visual increase
	for use_pow: bool in [false, true]:
		for weapon: String in ["quebra_tijolos", "fogo_intenso", "eletrodomestico"]:
			set_scales(1.0, 1.0, 1.0)
			duel(game, weapon)
			var before: Dictionary = shoot(game, use_pow)
			set_scales(float(configured.projectile_scale), float(configured.pow_projectile_scale), float(configured.back_weapon_scale))
			duel(game, weapon)
			var after: Dictionary = shoot(game, use_pow)
			var label: String = "%s%s" % [weapon, " POW" if use_pow else ""]
			check(before.dealt > 0 and before.dealt == after.dealt and before.rival_hp == after.rival_hp and before.my_hp == after.my_hp, "%s: same damage with bigger art (%d)" % [label, before.dealt])
			check(before.hit == after.hit, "%s: the projectile hits the same point" % label)
			check(before.mask == after.mask, "%s: the crater is identical" % label)
			check(before.hit_radius == after.hit_radius, "%s: hit radius unchanged" % label)
			var expected: float = float(configured.projectile_scale) * (float(configured.pow_projectile_scale) if use_pow else 1.0)
			check(is_equal_approx(after.size, before.size * expected), "%s: sprite drawn %.2fx bigger" % [label, expected])
	# --- POW phases
	set_scales(float(configured.projectile_scale), float(configured.pow_projectile_scale), float(configured.back_weapon_scale))
	duel(game, "trovao")
	var me: TankFighter = game.fighters[0]
	var impacts: Array = []
	game.pow_impact.connect(func(point: Vector2, radius: float, id: String) -> void: impacts.append([point, radius, id]))
	var base_x: float = me.visual.position.x
	me.pow_gauge = 100
	var clock: float = game.remaining
	game.activate_pow()
	check(me.rig.weapon_glow == 1.0, "preparation: the weapon on the back lights up when POW is armed")
	check(is_equal_approx(game.hitstop, float(configured.pow_cutin)), "activation: the battle holds for the cut-in")
	for i in range(30):
		game._physics_process(1.0 / 60)
	check(is_equal_approx(game.remaining, clock), "... and the turn clock stops meanwhile")
	game.hitstop = 0.0
	# The frames before were long (battle setup): let the tween start, then look.
	await process_frame
	await process_frame
	await create_timer(0.06).timeout
	check(me.visual.position.x < base_x, "preparation: the fighter pulls back")
	check(me.weapon_point().distance_to(me.center()) < 80.0, "the charge pulls particles to the weapon on the fighter")
	var plan: Vector3 = EnemyAI.choose_shot(me, game.fighters[1], game.terrain, 0.0, game.balance)
	me.angle = plan.x
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.power = plan.y
	game.release_shot()
	var powered: TankProjectile = game.projectiles[0]
	check(not powered.pow_colors.is_empty() and is_instance_valid(powered.sparks), "flight: the POW shot trails particles in its weapon's colours")
	for i in range(1500):
		game._physics_process(1.0 / 60)
		if not impacts.is_empty():
			break
	check(impacts.size() == 1 and impacts[0][2] == "trovao", "impact: the POW landing is announced with the weapon id")
	check(game.hitstop > 0.1 and game.hitstop <= 0.2, "impact: 100–200 ms of hit-stop")
	var waited: float = game.volley_wait
	var held: float = game.hitstop
	game._physics_process(1.0 / 60)
	check(game.volley_wait == waited and game.hitstop < held, "hit-stop freezes the battle for a moment")
	# Back weapon grows by back_weapon_scale and stays behind the head.
	var rig: LookRig = me.rig
	rig.follow(me.body)
	var grown: float = rig.back_weapon.scale.x
	set_scales(1.0, 1.0, 1.0)
	rig.follow(me.body)
	var plain: float = rig.back_weapon.scale.x
	check(is_equal_approx(grown / plain, float(configured.back_weapon_scale)), "the weapon on the back is drawn %.1fx bigger in battle" % float(configured.back_weapon_scale))
	set_scales(float(configured.projectile_scale), float(configured.pow_projectile_scale), float(configured.back_weapon_scale))
	rig.follow(me.body)
	var head_x: float = rig.map_point(me.body, Vector2(rig.points.head[0], rig.points.head[1])).x
	check((rig.back_weapon.position.x - head_x) * me.facing < 0.0, "the bigger weapon sits behind the head (back side)")
	# One impact per weapon: every weapon has its own shape and colours, and its POW art.
	var shapes: Dictionary = {}
	var art_ok: bool = true
	for def: Dictionary in Armory.data().weapons:
		var style: Dictionary = PowImpact.style_for(str(def.id))
		shapes[style.shape] = true
		art_ok = art_ok and PowFx.art_frames(str(def.id)).size() >= 6
	check(shapes.size() == Armory.data().weapons.size(), "each of the 12 POWs lands with its own shape (%d)" % shapes.size())
	check(art_ok, "each POW has its own animated PixelLab art (6+ frames)")
	var impact: PowImpact = PowImpact.new()
	impact.weapon_id = "fogo_intenso"
	root.add_child(impact)
	await process_frame
	check(impact.get_children().any(func(n: Node) -> bool: return n is CPUParticles2D), "impacts use CPUParticles2D (works on Compatibility and web)")
	impact.queue_free()
	game.queue_free()
	await process_frame
	print("POW RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
