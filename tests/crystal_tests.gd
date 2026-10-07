extends SceneTree

# 0.33: energy crystals and special ammo (idea from Ballistic Hero). Crystals float over a PvP
# battle and any shot that flies through one takes it; crystals pay for the piercing missile,
# the time bomb and the laser. Everything runs on the fixed step with the match's rng, so two
# copies of the same battle stay identical (lockstep).

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

func duel(extra: Dictionary = {}) -> LocalMatch:
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var config: Dictionary = {"mode": "pvp", "map": "ilha_celeste", "seed": 777, "turn_seconds": 10, "crystals": true,
		"teams": [[{"name": "Nilo", "human": true, "weapon": 0, "level": 5}], [{"name": "Rival", "human": true, "weapon": 4, "level": 5}]]}
	config.merge(extra, true)
	game.start(config)
	return game

func make_turn(game: LocalMatch, fighter: TankFighter) -> void:
	for other in game.fighters:
		other.delay = 1000.0
	fighter.delay = 0.0
	game.begin_turn()

func place(game: LocalMatch, fighter: TankFighter, x: float) -> void:
	fighter.position = Vector2(x, game.terrain.surface_y(x) - 1)
	fighter.settled = true
	fighter.update_pose()

# Fires the active fighter's weapon at an angle and force; returns every position of the first
# projectile, one per frame, until the volley is over.
func shoot(game: LocalMatch, angle: float, power: float, record: bool = true) -> PackedVector2Array:
	var fighter: TankFighter = game.active()
	fighter.angle = angle
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.power = power
	game.release_shot()
	var path: PackedVector2Array = PackedVector2Array()
	for i in range(1500):
		if record and not game.projectiles.is_empty():
			path.append(game.projectiles[0].position)
		game.step(1.0 / 60)
		if game.state != LocalMatch.State.PROJECTILE_FLYING:
			break
	return path

func far_away(game: LocalMatch) -> void:
	for entry: Dictionary in game.crystals:
		entry.pos = Vector2(-9000, -9000)

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	# --- only PvP battles asked for it get crystals
	var plain: LocalMatch = duel({"crystals": false})
	check(not plain.crystals_on and plain.crystals.is_empty(), "no crystals unless the battle asks for them")
	var training: LocalMatch = duel({"mode": "tutorial"})
	check(not training.crystals_on, "no crystals in the training")
	var rules: Dictionary = plain.balance.crystals
	var game: LocalMatch = duel()
	check(game.crystals_on and game.crystals.size() == int(rules.count), "a PvP battle starts with %d crystals" % int(rules.count))
	var inside: bool = true
	var apart: bool = true
	for i in range(game.crystals.size()):
		var spot: Vector2 = game.crystals[i].pos
		inside = inside and spot.x >= game.terrain.world_size.x * float(rules.x_range[0]) - 2.0 and spot.x <= game.terrain.world_size.x * float(rules.x_range[1]) + 2.0 and spot.y >= 80.0
		for j in range(i):
			apart = apart and spot.distance_to(game.crystals[j].pos) >= float(rules.min_gap) * 0.5
	check(inside, "crystals float inside the middle of the map")
	check(apart, "crystals are spread apart")
	check(game.visible_crystals().size() == game.crystals.size(), "every crystal is there at the start")
	var twin: LocalMatch = duel()
	check(twin.checksum() == game.checksum(), "the same seed draws the same crystals")
	var other: LocalMatch = duel({"seed": 778})
	check(other.checksum() != game.checksum(), "another seed draws other crystals")
	var me: TankFighter = game.fighters[0]
	var rival: TankFighter = game.fighters[1]
	place(game, me, 300.0)
	place(game, rival, 1500.0)
	far_away(game)
	make_turn(game, me)
	# --- recording a shot, then putting a crystal on its path
	var path: PackedVector2Array = shoot(game, 55.0, 70.0)
	check(path.size() > 20 and me.crystals == 0, "a shot with no crystal on its path collects nothing")
	var landed: Vector2 = game.last_impact
	var racer: LocalMatch = duel()
	var runner: TankFighter = racer.fighters[0]
	place(racer, runner, 300.0)
	place(racer, racer.fighters[1], 1500.0)
	far_away(racer)
	racer.crystals[0].pos = path[path.size() / 2] + Vector2(0, 8)
	var gauge: float = runner.pow_gauge
	make_turn(racer, runner)
	gauge = runner.pow_gauge
	var taken: Array[Dictionary] = []
	racer.effect.connect(func(kind: String, point: Vector2, data: Dictionary) -> void:
		if kind == "crystal":
			taken.append({"point": point, "data": data}))
	shoot(racer, 55.0, 70.0, false)
	check(runner.crystals == 1, "a shot flying through a crystal takes it")
	check(is_equal_approx(runner.pow_gauge, minf(float(racer.balance.pow_max), gauge + float(rules.pow_gain))), "a crystal also charges the POW")
	check(racer.last_impact.distance_to(landed) < 1.0, "the shot goes on and lands where it would have")
	check(taken.size() == 1 and int(taken[0].data.fighter) == 0, "taking a crystal is announced to the screen")
	check(racer.crystals.size() == int(rules.count) and racer.visible_crystals().size() == int(rules.count) - 1, "the taken crystal waits to come back")
	var comeback: Dictionary = racer.crystals[racer.crystals.size() - 1]
	check(int(comeback.at) == racer.round_number + int(rules.respawn_rounds), "it comes back %d turns later" % int(rules.respawn_rounds))
	racer.round_number = int(comeback.at)
	check(racer.visible_crystals().size() == int(rules.count), "and it is there again")
	# a crystal is also taken by a shot that only grazes it
	var graze: LocalMatch = duel()
	place(graze, graze.fighters[0], 300.0)
	place(graze, graze.fighters[1], 1500.0)
	far_away(graze)
	graze.crystals[0].pos = path[path.size() / 3] + Vector2(0, float(rules.radius) - 4.0)
	make_turn(graze, graze.fighters[0])
	shoot(graze, 55.0, 70.0, false)
	check(graze.fighters[0].crystals == 1, "a crystal is taken when the shot passes within its radius")
	# the charge is capped
	racer.fighters[0].crystals = int(rules.max_charge)
	racer.take_crystal(racer.fighters[0], racer.visible_crystals()[0])
	check(racer.fighters[0].crystals == int(rules.max_charge), "the crystal charge is capped")
	# --- special ammo: arming
	var ammo: LocalMatch = duel()
	var hero: TankFighter = ammo.fighters[0]
	place(ammo, hero, 300.0)
	place(ammo, ammo.fighters[1], 1500.0)
	far_away(ammo)
	make_turn(ammo, hero)
	var armed: Array[Dictionary] = []
	ammo.skill_used.connect(func(_fighter: TankFighter, info: Dictionary) -> void: armed.append(info))
	check(not ammo.use_ammo("laser"), "no crystals, no special ammo")
	hero.crystals = 3
	var energy: float = ammo.energy
	check(ammo.use_ammo("laser") and ammo.turn_ammo == "laser", "the laser is armed with 3 crystals")
	check(is_equal_approx(ammo.energy, energy - float(ammo.ammo_def("laser").energy)), "the ammo costs its energy")
	check(armed.size() == 1 and armed[0].kind == "ammo" and armed[0].icon == "ammo_laser", "arming the ammo is shown as a skill")
	check(hero.crystals == 3, "the crystals are spent when the shot leaves, not before")
	check(ammo.use_ammo("laser") and ammo.turn_ammo == "" and is_equal_approx(ammo.energy, energy), "pressing it again puts it away and gives the energy back")
	check(ammo.use_ammo("perfurante") and ammo.use_ammo("relogio") and ammo.turn_ammo == "relogio", "arming another ammo swaps it")
	check(is_equal_approx(ammo.energy, energy - float(ammo.ammo_def("relogio").energy)), "the swap refunds the first ammo's energy")
	check(not ammo.use_item("plus1") and not ammo.use_item("triple"), "no multiple shots with special ammo")
	check(ammo.use_item("dmg50"), "but damage skills still add up")
	check(not ammo.apply_pow(hero) and not ammo.toggle_fly(), "no POW and no paper plane with special ammo")
	var multi: LocalMatch = duel()
	place(multi, multi.fighters[0], 300.0)
	far_away(multi)
	make_turn(multi, multi.fighters[0])
	multi.fighters[0].crystals = 3
	multi.use_item("plus2")
	check(not multi.use_ammo("laser"), "special ammo is refused after a multiple shot")
	var plane: LocalMatch = duel()
	place(plane, plane.fighters[0], 300.0)
	far_away(plane)
	make_turn(plane, plane.fighters[0])
	plane.fighters[0].crystals = 3
	plane.toggle_fly()
	check(not plane.use_ammo("laser"), "special ammo is refused with the paper plane")
	# --- the intent works for replays and online
	var online: LocalMatch = duel()
	place(online, online.fighters[0], 300.0)
	far_away(online)
	make_turn(online, online.fighters[0])
	online.fighters[0].crystals = 2
	online.apply_input(0, "ammo", {"id": "perfurante"})
	check(online.turn_ammo == "perfurante", "the ammo intent arms the ammo")
	online.apply_input(1, "ammo", {"id": "relogio"})
	check(online.turn_ammo == "perfurante", "an intent from someone not on turn is ignored")
	check(not Replay.clean_input([3, 0, "ammo", {"id": "laser"}], 2).is_empty(), "replays and the server accept the ammo intent")
	# --- piercing missile
	var drill: LocalMatch = duel()
	place(drill, drill.fighters[0], 300.0)
	place(drill, drill.fighters[1], 1500.0)
	far_away(drill)
	make_turn(drill, drill.fighters[0])
	var dive_x: float = 180.0
	var top: float = drill.terrain.surface_y(dive_x)
	var control: TankProjectile = drill.make_projectile(drill.fighters[0], Vector2(dive_x, top - 80.0), Vector2(0, 300), 100, 30.0, {})
	drill.state = LocalMatch.State.PROJECTILE_FLYING
	for i in range(300):
		drill.step(1.0 / 60)
		if drill.projectiles.is_empty():
			break
	check(absf(drill.last_impact.y - top) < 12.0, "an ordinary shell explodes on the surface")
	var hole: LocalMatch = duel()
	place(hole, hole.fighters[0], 300.0)
	place(hole, hole.fighters[1], 1500.0)
	far_away(hole)
	make_turn(hole, hole.fighters[0])
	var tunnels: Array[Vector2] = []
	hole.effect.connect(func(kind: String, point: Vector2, _data: Dictionary) -> void:
		if kind == "tunnel":
			tunnels.append(point))
	var missile: TankProjectile = hole.make_projectile(hole.fighters[0], Vector2(dive_x, top - 80.0), Vector2(0, 300), 100, 30.0, {})
	hole.arm_ammo_shot(missile, "perfurante")
	hole.state = LocalMatch.State.PROJECTILE_FLYING
	for i in range(300):
		hole.step(1.0 / 60)
		if hole.projectiles.is_empty():
			break
	var depth: float = hole.last_impact.y - top
	check(depth > 100.0 and depth < 190.0, "the piercing missile goes about %d px into the ground before it explodes (%d)" % [int(hole.ammo_def("perfurante").pierce), int(depth)])
	check(tunnels.size() >= 6, "it digs a tunnel as it goes (%d craters)" % tunnels.size())
	check(not hole.terrain.solid(Vector2(dive_x, top + 40.0)), "the tunnel stays open")
	check(missile.pierce_left <= 0.0, "the ground used up its piercing")
	# --- time bomb
	var clock: LocalMatch = duel()
	var planter: TankFighter = clock.fighters[0]
	var victim: TankFighter = clock.fighters[1]
	place(clock, planter, 300.0)
	place(clock, victim, 1500.0)
	far_away(clock)
	make_turn(clock, planter)
	var blasts: Array[Dictionary] = []
	clock.effect.connect(func(kind: String, point: Vector2, data: Dictionary) -> void:
		if kind in ["bomb_plant", "bomb_blast"]:
			blasts.append({"kind": kind, "point": point, "data": data}))
	var spot: Vector2 = Vector2(1500.0, clock.terrain.surface_y(1500.0) - 4.0)
	var shell: TankProjectile = clock.make_projectile(planter, spot + Vector2(0, -60), Vector2(0, 300), 200, 60.0, {})
	clock.arm_ammo_shot(shell, "relogio")
	clock.state = LocalMatch.State.PROJECTILE_FLYING
	var hp: int = victim.hp
	for i in range(300):
		clock.step(1.0 / 60)
		if clock.projectiles.is_empty():
			break
	check(clock.bombs.size() == 1 and int(clock.bombs[0].left) == int(clock.ammo_def("relogio").fuse), "the time bomb sticks where it lands")
	check(victim.hp == hp, "it does no damage when it lands")
	check(blasts.size() == 1 and blasts[0].kind == "bomb_plant", "planting it is announced to the screen")
	check(not clock.tick_bombs(), "the turn that planted it does not count")
	check(not clock.tick_bombs() and int(clock.bombs[0].left) == 1, "one turn later it is still ticking")
	var dug: bool = clock.terrain.solid(clock.bombs[0].pos + Vector2(0, 14))
	check(clock.tick_bombs() and clock.bombs.is_empty(), "two turns later it goes off")
	check(victim.hp < hp, "the bomb hurts whoever stayed next to it")
	check(blasts.size() == 2 and blasts[1].kind == "bomb_blast", "the blast is announced to the screen")
	check(dug and not clock.terrain.solid(spot + Vector2(0, 14)), "and it blows a hole in the ground")
	# --- laser
	var beam: LocalMatch = duel()
	var gunner: TankFighter = beam.fighters[0]
	place(beam, gunner, 150.0)
	place(beam, beam.fighters[1], 300.0)
	far_away(beam)
	make_turn(beam, gunner)
	beam.wind = 5.0
	gunner.crystals = 3
	check(beam.use_ammo("laser"), "the laser can be armed")
	var aim: Vector2 = beam.fighters[1].center() - gunner.muzzle_at(0.0)
	var degrees: float = clampf(rad_to_deg(atan2(-aim.y, aim.x)), 0.0, 90.0)
	var rival_hp: int = beam.fighters[1].hp
	var beams: Array[Dictionary] = []
	beam.effect.connect(func(kind: String, point: Vector2, data: Dictionary) -> void:
		if kind == "laser":
			beams.append({"point": point, "data": data}))
	var bolt_path: PackedVector2Array = shoot(beam, degrees, 100.0)
	check(gunner.crystals == 0, "the laser spent its 3 crystals")
	check(bolt_path.size() >= 2, "the bolt flies")
	var straight: bool = true
	for i in range(2, bolt_path.size()):
		var a: Vector2 = (bolt_path[i] - bolt_path[i - 1]).normalized()
		var b: Vector2 = (bolt_path[1] - bolt_path[0]).normalized()
		straight = straight and a.distance_to(b) < 0.01
	check(straight, "the laser flies straight: no gravity and no wind")
	check(beam.fighters[1].hp < rival_hp, "and hits whoever is on the line")
	check(beams.size() == 1 and beams[0].data.has("from"), "the bolt is announced to the screen with where it started")
	var short: LocalMatch = duel()
	place(short, short.fighters[0], 200.0)
	place(short, short.fighters[1], 1500.0)
	far_away(short)
	make_turn(short, short.fighters[0])
	short.fighters[0].crystals = 3
	short.use_ammo("laser")
	var weak: PackedVector2Array = shoot(short, 20.0, 0.0)
	var strong: LocalMatch = duel()
	place(strong, strong.fighters[0], 200.0)
	place(strong, strong.fighters[1], 1500.0)
	far_away(strong)
	make_turn(strong, strong.fighters[0])
	strong.fighters[0].crystals = 3
	strong.use_ammo("laser")
	var long: PackedVector2Array = shoot(strong, 20.0, 100.0)
	check(weak.size() < long.size(), "the force sets the laser's range")
	check(weak[weak.size() - 1].distance_to(weak[0]) <= float(short.ammo_def("laser").range[0]) + 60.0, "the weakest bolt stops at about its minimum range")
	# --- the damage of each ammo
	var control_damage: LocalMatch = duel()
	var dmg: Dictionary = {}
	for id in ["", "perfurante", "relogio", "laser"]:
		var test: LocalMatch = duel()
		place(test, test.fighters[0], 300.0)
		place(test, test.fighters[1], 1500.0)
		far_away(test)
		make_turn(test, test.fighters[0])
		test.fighters[0].crystals = 3
		if id != "":
			test.use_ammo(id)
		dmg[id] = test.compose_plan(test.fighters[0])
	check(int(dmg["perfurante"].damage) < int(dmg[""].damage) and int(dmg["relogio"].damage) > int(dmg[""].damage) and int(dmg["laser"].damage) > int(dmg[""].damage), "each ammo trades damage as its numbers say")
	check(str(dmg["laser"].ammo) == "laser" and str(dmg[""].ammo) == "", "the plan names the ammo")
	control_damage.queue_free()
	# --- lockstep: two copies fed the same intents stay identical
	var first: LocalMatch = duel()
	var second: LocalMatch = duel()
	var same: bool = first.checksum() == second.checksum()
	for copy: LocalMatch in [first, second]:
		copy.fighters[0].crystals = 3
	for copy: LocalMatch in [first, second]:
		make_turn(copy, copy.fighters[0])
		copy.fighters[0].crystals = 3
		copy.apply_input(0, "ammo", {"id": "relogio"})
		copy.apply_input(0, "charge", {})
		copy.apply_input(0, "release", {"power": 64.0})
	for i in range(900):
		first.step(1.0 / 60)
		second.step(1.0 / 60)
		same = same and first.checksum() == second.checksum()
	check(same and first.state == second.state, "two copies of the battle stay identical (lockstep)")
	check(first.bombs.size() == second.bombs.size() and first.fighters[0].crystals == second.fighters[0].crystals, "including the bombs and the crystals held")
	# --- the art and the effects (visual only; the headless run still draws them)
	var minimum: Dictionary = {"crystal": 8, "pickup": 6, "flare": 8, "blast": 8, "bomb": 4, "drill": 4}
	var art_ok: bool = true
	for folder: String in minimum:
		art_ok = art_ok and AmmoArt.frames(folder).size() >= int(minimum[folder])
	check(art_ok, "every effect has its PixelLab frames (crystal, pickup, flare, blast, bomb, drill)")
	var icons_ok: bool = true
	for icon: String in ["ammo_pierce", "ammo_clock", "ammo_laser", "crystal", "crystal_gem"]:
		icons_ok = icons_ok and ResourceLoader.exists("res://assets/ui/icons/%s.png" % icon)
	check(icons_ok, "the three ammo and the crystal have PixelLab icons")
	check(AmmoArt.frame("crystal", 0.0, 9.0, true) != AmmoArt.frame("crystal", 0.7, 9.0, true), "the crystal turns")
	check(AmmoArt.frame("crystal", 0.0, 9.0, true) == AmmoArt.frame("crystal", 16.0 / 9.0, 9.0, true), "and its half turn loops back seamlessly (ping-pong)")
	var kinds: Array = ["crystal", "laser_fire", "drill_fire", "laser", "tunnel", "bomb_plant", "bomb_blast"]
	var drawn: Dictionary = {}
	var fx_nodes: Array[AmmoFx] = []
	for kind: String in kinds:
		var fx: AmmoFx = AmmoFx.new()
		fx.kind = kind
		fx.data = {"color": Color("ff4ad8") if kind == "laser" else "5ae8ff", "from": Vector2(-400, -60), "radius": 90.0, "angle": -0.4, "debris": PackedColorArray([Color("7a5230"), Color("a07840")])}
		fx.position = Vector2(300, 300)
		fx.draw.connect(func() -> void: drawn[kind] = int(drawn.get(kind, 0)) + 1)
		root.add_child(fx)
		fx_nodes.append(fx)
	await process_frame
	for step in range(5):
		for fx: AmmoFx in fx_nodes:
			fx.age = fx.life * (step + 1) / 6.0
		await process_frame
	var every_kind_draws: bool = true
	for kind: String in kinds:
		every_kind_draws = every_kind_draws and int(drawn.get(kind, 0)) >= 3
	check(every_kind_draws, "every crystal and ammo effect draws at several moments of its life")
	for fx: AmmoFx in fx_nodes:
		fx.age = fx.life
	await process_frame
	await process_frame
	var all_freed: bool = true
	for fx: AmmoFx in fx_nodes:
		all_freed = all_freed and not is_instance_valid(fx)
	check(all_freed, "and each frees itself when it is over")
	# The crystals and the bombs on the field draw (the bomb's last turn shakes and blinks).
	var field_game: LocalMatch = duel()
	var field: CrystalField = CrystalField.new()
	field.game = field_game
	field_game.bombs.append({"pos": Vector2(600, field_game.terrain.surface_y(600.0) - 2.0), "owner": 0, "damage": 300, "radius": 100.0, "left": 2, "fresh": false})
	var field_draws: Array = [0]
	field.draw.connect(func() -> void: field_draws[0] += 1)
	root.add_child(field)
	await process_frame
	await process_frame
	field_game.bombs[0].left = 1
	field.time += 0.4
	await process_frame
	check(int(field_draws[0]) >= 3 and field.born.size() == field_game.visible_crystals().size(), "the crystal field draws the gems and the bomb, and tracks each gem's arrival")
	var gone: Dictionary = field_game.visible_crystals()[0]
	field_game.take_crystal(field_game.fighters[0], gone)
	await process_frame
	check(not field.born.has(gone.pos), "a taken crystal is forgotten, so it materialises again when it comes back")
	# The motes of a crystal fly to the HUD meter and land one by one.
	var motes: CrystalMotes = CrystalMotes.new()
	root.add_child(motes)
	var arrived: Array = [0]
	motes.landed.connect(func() -> void: arrived[0] += 1)
	motes.launch(Vector2(400, 300), Vector2(900, 590), Color("5ae8ff"))
	await process_frame
	for i in range(40):
		motes._process(0.05)
	check(int(arrived[0]) == CrystalMotes.COUNT and motes.motes.is_empty(), "all %d motes of light land in the meter" % CrystalMotes.COUNT)
	# The shock ring ends and clears its screen layer.
	var port: SubViewport = SubViewport.new()
	root.add_child(port)
	var wave: ShockwaveFx = ShockwaveFx.spawn(root, port, Vector2(500, 300), 0.8, 0.5, 0.02, 0.5)
	await process_frame
	var ring_start: float = float(wave.material.get_shader_parameter("radius"))
	wave._process(0.2)
	var ring_mid: float = float(wave.material.get_shader_parameter("radius"))
	wave._process(0.4)
	await process_frame
	check(ring_mid > ring_start and not is_instance_valid(wave), "the shock ring grows and then frees itself")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	for node in root.get_children():
		if node is LocalMatch:
			node.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
