class_name LocalMatch
extends Node2D

# Local authority for one battle. Turn order follows DDTank's Delay rule: every
# action adds delay and the living fighter with the lowest delay plays next.

signal changed
signal finished(winner_team: int)
signal blast(point: Vector2, radius: float)
signal damage_text(point: Vector2, text: String, color: Color)
signal shot_fired(projectile: TankProjectile)
signal turn_started(fighter: TankFighter)
signal announce(text: String, color: Color)
signal special(point: Vector2, texture_path: String)
# Weapon POW visuals: beam, lightning, heal, bull, hearts, tornado, fridge.
signal effect(kind: String, point: Vector2, data: Dictionary)

enum State { WAITING_FOR_TURN, TURN_STARTED, PLAYER_MOVING, PLAYER_AIMING, PLAYER_CHARGING, PROJECTILE_FLYING, RESOLVING_DAMAGE, TURN_FINISHED, MATCH_FINISHED }

var state: State = State.WAITING_FOR_TURN
var balance: Dictionary
var terrain: DestructibleTerrain
var fighters: Array[TankFighter] = []
var projectiles: Array[TankProjectile] = []
var active_id: int = 0
var local_id: int = 0
var round_number: int = 0
var turn_seconds: float = 10.0
var remaining: float = 10.0
var energy: float = 240.0
var power: float = 0.0
var charge_pass: int = 0
var wind: float = 0.0
var resolve_time: float = 0.0
var volley_wait: float = 0.0
var running: bool = false
var paused: bool = false
var move_input: float = 0.0
var aim_input: float = 0.0
var status_message: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var mode: String = "pvp"
var pve: bool = false
var map: Dictionary = {}
var difficulty: Dictionary = {}
var boss_enraged: bool = false
var auto_play: bool = false
var turn_items: Array[String] = []
var turn_fly: bool = false
var turn_pow: bool = false
var tools_used: int = 0
var moved_distance: float = 0.0
var passed: bool = false
var skip_turn: bool = false
var shots_left: int = 0
var shot_angle: float = 45.0
var shot_effective: float = 45.0
var shot_power: float = 50.0
var shot_plan: Dictionary = {}
var ai_time: float = 0.0
var ai_think: float = 1.5
var ai_plan: Vector3 = Vector3(45, 60, INF)
var ai_planned: bool = false
var winner_team: int = -2
var last_impact: Vector2 = Vector2.ZERO

func _init() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	rng.randomize()

func start(config: Dictionary) -> void:
	for fighter in fighters:
		fighter.queue_free()
	fighters.clear()
	for projectile in projectiles:
		projectile.queue_free()
	projectiles.clear()
	if is_instance_valid(terrain):
		terrain.queue_free()
	mode = str(config.get("mode", "pvp"))
	pve = mode == "pve"
	map = find_map(str(config.get("map", "")))
	turn_seconds = float(config.get("turn_seconds", balance.turn_seconds))
	difficulty = find_difficulty(str(config.get("difficulty", "normal")))
	if config.has("seed"):
		rng.seed = int(config.seed)
	terrain = DestructibleTerrain.new()
	add_child(terrain)
	terrain.generate(map, rng.randi() % 100000)
	var teams: Array = config.get("teams", [[], []])
	for team_index in range(2):
		var entries: Array = teams[team_index]
		for i in range(entries.size()):
			var entry: Dictionary = entries[i].duplicate()
			entry.team = team_index
			spawn_fighter(entry, i, entries.size())
	local_id = 0
	for fighter in fighters:
		if fighter.human:
			local_id = fighter.player_id
			break
	for fighter in fighters:
		# Agility decides who opens the battle; a small jitter breaks ties.
		fighter.delay = rng.randf_range(0.0, 30.0) - fighter.agility * 0.1
	round_number = 0
	winner_team = -2
	boss_enraged = false
	auto_play = false
	running = true
	paused = false
	state = State.WAITING_FOR_TURN
	var opener: TankFighter = next_fighter()
	if opener != null and opener.team == fighters[local_id].team:
		announce.emit("Processo de busca sucedido! A sua equipe começará o combate!", Color("fff4a0"))
	else:
		announce.emit("Processo de busca sucedido! A equipe adversária começa.", Color("fff4a0"))
	begin_turn()

func spawn_fighter(entry: Dictionary, index: int, count: int) -> void:
	var fighter: TankFighter = TankFighter.new()
	fighter.setup(fighters.size(), entry, Armory.weapon_for_entry(entry), balance)
	if entry.get("boss", false):
		var size_scale: float = 0.4 + 0.2 * maxi(1, int(entry.get("party", 1)))
		fighter.max_hp = roundi(float(balance.pve.boss_hp) * float(difficulty.get("hp", 1.0)) * size_scale)
		fighter.hp = fighter.max_hp
		fighter.agility = int(balance.pve.agility)
		fighter.setup_boss(entry, roundi(float(balance.pve.damage) * float(difficulty.get("damage", 1.0))), int(balance.pve.radius))
	var tools: Array = entry.get("tools", [])
	for tool in tools:
		fighter.tools.append(str(tool))
	var span: Array = map.spawns[int(entry.team)]
	var x: float = lerpf(float(span[0]), float(span[1]), (index + 0.5) / maxf(1, count)) + rng.randf_range(-30, 30)
	x = find_ground(x)
	fighter.position = Vector2(x, terrain.surface_y(x) - 1)
	fighter.tilt = 0.0 if fighter.is_boss else terrain.slope_degrees(fighter.position.x, fighter.position.y)
	fighter.facing = 1 if fighter.position.x < terrain.world_size.x * 0.5 else -1
	add_child(fighter)
	fighter.update_pose()
	fighters.append(fighter)

func find_ground(x: float) -> float:
	for offset in range(0, 600, 12):
		for candidate: float in [x + offset, x - offset]:
			if candidate > 30 and candidate < terrain.world_size.x - 30 and terrain.surface_y(candidate) < terrain.world_size.y - 20:
				return candidate
	return x

func find_map(id: String) -> Dictionary:
	var pool: Array = []
	for entry: Dictionary in balance.maps:
		if entry.id == id:
			return entry
		if pve == bool(entry.get("pve_only", false)):
			pool.append(entry)
	return pool[rng.randi() % pool.size()]

func find_difficulty(id: String) -> Dictionary:
	for entry: Dictionary in balance.pve.difficulties:
		if entry.id == id:
			return entry
	return balance.pve.difficulties[0]

func item_def(id: String) -> Dictionary:
	for item: Dictionary in balance.items:
		if item.id == id:
			return item
	return {}

func tool_def(id: String) -> Dictionary:
	for tool: Dictionary in balance.tools:
		if tool.id == id:
			return tool
	return {}

func active() -> TankFighter:
	return fighters[active_id]

func local() -> TankFighter:
	return fighters[local_id]

func next_fighter() -> TankFighter:
	var best: TankFighter = null
	for fighter in fighters:
		if fighter.hp > 0 and (best == null or fighter.delay < best.delay):
			best = fighter
	return best

func turn_order() -> Array[TankFighter]:
	var order: Array[TankFighter] = []
	for fighter in fighters:
		if fighter.hp > 0:
			order.append(fighter)
	order.sort_custom(func(a: TankFighter, b: TankFighter) -> bool: return a.delay < b.delay or (a.delay == b.delay and a.player_id < b.player_id))
	return order

func is_ai_controlled(fighter: TankFighter) -> bool:
	return not fighter.human or auto_play

func can_act() -> bool:
	return running and not paused and state in [State.TURN_STARTED, State.PLAYER_MOVING, State.PLAYER_AIMING] and not is_ai_controlled(active())

func begin_turn() -> void:
	if not running:
		return
	var fighter: TankFighter = next_fighter()
	if fighter == null:
		evaluate_winner()
		return
	active_id = fighter.player_id
	round_number += 1
	state = State.TURN_STARTED
	remaining = turn_seconds
	energy = fighter.max_energy
	power = 0
	charge_pass = 0
	move_input = 0
	aim_input = 0
	turn_items.clear()
	turn_fly = false
	turn_pow = false
	tools_used = 0
	moved_distance = 0
	passed = false
	skip_turn = false
	shots_left = 0
	ai_planned = false
	wind = snappedf(rng.randf_range(-float(balance.wind_max), float(balance.wind_max)), 0.1)
	fighter.pow_gauge = minf(float(balance.pow_max), fighter.pow_gauge + float(balance.pow_per_turn))
	for other in fighters:
		other.active = other == fighter
		other.update_pose()
	if fighter.frozen > 0:
		fighter.frozen -= 1
		skip_turn = true
		status_message = "%s está congelado e perde a vez!" % fighter.display_name
		announce.emit(status_message, Color("a8e8ff"))
		state = State.RESOLVING_DAMAGE
		resolve_time = 0.3
		turn_started.emit(fighter)
		changed.emit()
		return
	state = State.PLAYER_AIMING
	if fighter.player_id == local_id and not auto_play:
		status_message = "Sua vez! Segure ESPAÇO para definir a força"
	else:
		status_message = "Vez de %s" % fighter.display_name
	if is_ai_controlled(fighter):
		plan_ai(fighter)
	turn_started.emit(fighter)
	changed.emit()

func finish_turn() -> void:
	var fighter: TankFighter = active()
	var delay_rules: Dictionary = balance.delay
	var added: float = float(delay_rules.base) - fighter.agility * float(delay_rules.agility)
	if skip_turn:
		added = float(delay_rules.frozen)
	else:
		if passed:
			added *= float(delay_rules.pass_scale)
		for id in turn_items:
			added += float(item_def(id).get("delay", 0))
		if turn_fly:
			added += float(balance.fly.delay)
		added += moved_distance * float(delay_rules.move_per_px) + tools_used * float(delay_rules.tool)
	fighter.delay += added
	fighter.fly_cooldown = maxi(0, fighter.fly_cooldown - 1)
	fighter.active = false
	state = State.TURN_FINISHED
	begin_turn()

# ---------- player intents ----------

func charge() -> void:
	if not can_act() or not active().settled:
		return
	state = State.PLAYER_CHARGING
	power = 0
	charge_pass = 0
	move_input = 0
	status_message = "Solte ESPAÇO para disparar"

func release_shot(from_ai: bool = false) -> void:
	if not running or paused or state != State.PLAYER_CHARGING:
		return
	if is_ai_controlled(active()) and not from_ai:
		return
	var fighter: TankFighter = active()
	shot_angle = fighter.angle
	shot_effective = fighter.effective_angle()
	shot_power = power
	fighter.last_power = power
	shot_plan = compose_plan(fighter)
	shots_left = int(shot_plan.extra)
	fire_volley()

func compose_plan(fighter: TankFighter) -> Dictionary:
	var weapon: Dictionary = fighter.weapon
	if turn_fly:
		fighter.fly_cooldown = int(balance.fly.cooldown) + 1
		return {"damage": 0, "radius": 0.0, "balls": 1, "spread": 0.0, "extra": 0, "fly": true, "freeze": false, "pow": {}}
	var scale: float = 1.0
	var bonus: float = 0.0
	var extra: int = 0
	var balls: int = 1
	var spread: float = 0.0
	var radius_scale: float = 1.0
	var freeze: bool = false
	var pow_plan: Dictionary = {}
	for id in turn_items:
		var item: Dictionary = item_def(id)
		bonus += float(item.get("damage_bonus", 0.0))
		scale *= float(item.get("damage_scale", 1.0))
		extra = maxi(extra, int(item.get("extra_shots", 0)))
		if item.has("balls"):
			balls = int(item.balls)
			spread = 4.0
	if turn_pow and weapon.has("pow"):
		var pow_rules: Dictionary = weapon.pow
		pow_plan = pow_rules
		scale *= float(pow_rules.get("damage_scale", 1.0))
		radius_scale = float(pow_rules.get("radius_scale", 1.0))
		extra += int(pow_rules.get("extra_shots", 0))
		freeze = bool(pow_rules.get("freeze", false))
		if pow_rules.has("balls"):
			balls = int(pow_rules.balls)
			spread = float(pow_rules.get("spread", 5.0))
		var heal: int = int(pow_rules.get("team_heal", 0))
		if heal > 0:
			for ally in fighters:
				if ally.team == fighter.team and ally.hp > 0:
					var recovered: int = mini(heal, ally.max_hp - ally.hp)
					ally.hp += recovered
					if recovered > 0:
						damage_text.emit(ally.center(), "+%d" % recovered, Color("9aff7a"))
		fighter.pow_gauge = 0
		announce.emit("%s usou POW: %s!" % [fighter.display_name, pow_rules.name], Color("ffd04a"))
		special.emit(fighter.center(), str(pow_rules.get("effect", "")))
	return {"damage": roundi(float(weapon.damage) * scale * (1.0 + bonus)), "base_damage": roundi(float(weapon.damage) * (1.0 + bonus) * (scale / float(pow_plan.get("damage_scale", 1.0)))), "radius": float(weapon.radius) * radius_scale, "base_radius": float(weapon.radius), "balls": balls, "spread": spread, "extra": extra, "fly": false, "freeze": freeze, "pow": pow_plan}

func fire_volley() -> void:
	var fighter: TankFighter = active()
	var pow_plan: Dictionary = shot_plan.get("pow", {})
	var style: Dictionary = fighter.weapon.get("projectile", {}).duplicate()
	if str(pow_plan.get("kind", "")) == "giant":
		style.size = float(style.get("size", 24)) * float(pow_plan.get("size_scale", 2.0))
		style.wind_scale = float(pow_plan.get("wind_scale", 0.0))
	for i in range(int(shot_plan.balls)):
		var offset: float = (i - (int(shot_plan.balls) - 1) / 2.0) * float(shot_plan.spread)
		var velocity: Vector2 = Ballistics.launch_velocity(shot_effective + offset, shot_power, fighter.facing, balance)
		var projectile: TankProjectile = make_projectile(fighter, fighter.muzzle_at(shot_angle), velocity, int(shot_plan.damage), float(shot_plan.radius), style)
		projectile.fly = bool(shot_plan.fly)
		projectile.freeze = bool(shot_plan.freeze)
		projectile.special = pow_plan
		projectile.base_damage = int(shot_plan.get("base_damage", shot_plan.damage))
		projectile.base_radius = float(shot_plan.get("base_radius", shot_plan.radius))
	fighter.stats.shots += 1
	fighter.animate_attack()
	volley_wait = 0
	state = State.PROJECTILE_FLYING
	status_message = "Projétil em voo"
	changed.emit()

func make_projectile(fighter: TankFighter, from: Vector2, velocity: Vector2, damage: int, radius: float, style: Dictionary, sprite_key: String = "") -> TankProjectile:
	var projectile: TankProjectile = TankProjectile.new()
	projectile.position = from
	projectile.velocity = velocity
	projectile.wind = wind * float(balance.wind_accel) * float(style.get("wind_scale", 1.0))
	projectile.gravity = float(balance.gravity)
	projectile.terrain = terrain
	projectile.fighters = fighters
	projectile.owner_id = fighter.player_id
	projectile.damage = damage
	projectile.radius = radius
	projectile.base_damage = damage
	projectile.base_radius = radius
	projectile.tint = Color(str(fighter.weapon.get("color", "fff0c2")))
	var key: String = sprite_key if sprite_key != "" else str(style.get("sprite", ""))
	var path: String = ""
	if key != "" and fighter.weapon.has("projectile"):
		path = Armory.projectile_path(str(fighter.weapon.id), key, int(fighter.weapon.get("level", 0)))
	projectile.apply_style(style, path)
	projectile.impacted.connect(resolve_impact)
	projectile.missed.connect(resolve_miss)
	add_child(projectile)
	projectiles.append(projectile)
	shot_fired.emit(projectile)
	return projectile

func flip_aim() -> void:
	if can_act():
		active().facing *= -1
		active().update_pose()

func use_item(id: String) -> bool:
	if not can_act():
		return false
	return apply_item(active(), id)

func apply_item(fighter: TankFighter, id: String) -> bool:
	var item: Dictionary = item_def(id)
	if item.is_empty() or turn_fly or fighter.is_boss:
		return false
	var multi: bool = item.has("extra_shots") or item.has("balls")
	if multi:
		for used in turn_items:
			var other: Dictionary = item_def(used)
			if other.has("extra_shots") or other.has("balls"):
				return false
	if id == "triple" and turn_pow:
		return false
	if energy < float(item.energy):
		return false
	var fill: bool = bool(item.get("pow_fill", false))
	if fill and (fighter.pow_gauge >= float(balance.pow_max) or turn_pow):
		return false
	energy -= float(item.energy)
	turn_items.append(id)
	if fill:
		# POW Máx (item 9): the bar fills now, so B can release the special this turn.
		fighter.pow_gauge = float(balance.pow_max)
	changed.emit()
	return true

func use_tool(slot: int) -> bool:
	if not can_act():
		return false
	var fighter: TankFighter = active()
	if slot < 0 or slot >= fighter.tools.size() or fighter.tools[slot] == "":
		return false
	var tool: Dictionary = tool_def(fighter.tools[slot])
	if tool.has("heal"):
		if fighter.hp >= fighter.max_hp:
			return false
		var recovered: int = mini(int(tool.heal), fighter.max_hp - fighter.hp)
		fighter.hp += recovered
		damage_text.emit(fighter.center(), "+%d" % recovered, Color("9aff7a"))
	elif tool.has("team_heal"):
		for ally in fighters:
			if ally.team == fighter.team and ally.hp > 0 and ally.hp < ally.max_hp:
				var healed: int = mini(int(tool.team_heal), ally.max_hp - ally.hp)
				ally.hp += healed
				damage_text.emit(ally.center(), "+%d" % healed, Color("9aff7a"))
	elif tool.has("energy"):
		energy += float(tool.energy)
	elif tool.has("pow"):
		fighter.pow_gauge = float(balance.pow_max)
	elif tool.has("shield"):
		fighter.shield = float(tool.shield)
	elif tool.has("fly_reset"):
		if fighter.fly_cooldown == 0:
			return false
		fighter.fly_cooldown = 0
	fighter.tools[slot] = ""
	tools_used += 1
	announce.emit("%s usou %s" % [fighter.display_name, tool.name], Color("c8f0ff"))
	fighter.queue_redraw()
	changed.emit()
	return true

func use_aux() -> bool:
	# Item auxiliar (Dom de Anjo, escudos): limited uses per battle, key V.
	if not can_act():
		return false
	return apply_aux(active())

func apply_aux(fighter: TankFighter) -> bool:
	var def: Dictionary = Armory.aux_def(fighter.aux_id)
	if def.is_empty() or fighter.aux_uses <= 0:
		return false
	if def.has("heal_ratio"):
		if fighter.hp >= fighter.max_hp:
			return false
		heal_fighter(fighter, roundi(fighter.max_hp * float(def.heal_ratio)))
		effect.emit("heal", fighter.center(), {"radius": 60.0})
	elif def.has("shield"):
		if fighter.shield < 1.0:
			return false
		fighter.shield = float(def.shield)
	fighter.aux_uses -= 1
	tools_used += 1
	announce.emit("%s usou %s" % [fighter.display_name, def.name], Color("c8f0ff"))
	fighter.queue_redraw()
	changed.emit()
	return true

func toggle_fly() -> bool:
	if not can_act():
		return false
	var fighter: TankFighter = active()
	var cost: float = float(balance.fly.energy)
	if turn_fly:
		turn_fly = false
		energy += cost
	elif fighter.fly_cooldown == 0 and turn_items.is_empty() and not turn_pow and energy >= cost:
		turn_fly = true
		energy -= cost
	else:
		return false
	changed.emit()
	return true

func activate_pow() -> bool:
	if not can_act():
		return false
	var fighter: TankFighter = active()
	if turn_pow or turn_fly or fighter.pow_gauge < float(balance.pow_max) or "triple" in turn_items:
		return false
	turn_pow = true
	changed.emit()
	return true

func pass_turn() -> void:
	if not can_act():
		return
	passed = true
	status_message = "%s passou a vez" % active().display_name
	state = State.RESOLVING_DAMAGE
	resolve_time = 0.5
	changed.emit()

func set_auto_play(value: bool) -> void:
	auto_play = value
	if running and active_id == local_id and state in [State.PLAYER_AIMING, State.PLAYER_MOVING, State.TURN_STARTED]:
		if value:
			plan_ai(active())
		else:
			status_message = "Sua vez! Segure ESPAÇO para definir a força"
	changed.emit()

# ---------- resolution ----------

func resolve_impact(projectile: TankProjectile, point: Vector2) -> void:
	projectiles.erase(projectile)
	last_impact = point
	var shooter: TankFighter = fighters[projectile.owner_id]
	if projectile.fly:
		var ground: float = terrain.surface_y(point.x, maxf(0, point.y - 60))
		shooter.position = Vector2(point.x, minf(ground, terrain.world_size.y + 100) - 1)
		shooter.settled = false
		projectile.queue_free()
		return
	var rules: Dictionary = projectile.special
	var kind: String = str(rules.get("kind", ""))
	match kind:
		"beam":
			effect.emit("beam", point, {})
		"bull":
			effect.emit("bull", point, {"facing": shooter.facing})
		"giant":
			effect.emit("tornado", point, {})
	var dealt: int = explode(shooter, point, projectile.damage, projectile.radius, projectile.freeze, rules)
	if rules.has("lifesteal") and dealt > 0:
		heal_fighter(shooter, roundi(dealt * float(rules.lifesteal)))
		effect.emit("hearts", shooter.center(), {})
	var style: Dictionary = shooter.weapon.get("projectile", {})
	match kind:
		"split":
			var count: int = int(rules.get("fragments", 4))
			for i in range(count):
				var angle: float = -PI / 2 + (i - (count - 1) / 2.0) * 0.55
				var fragment: TankProjectile = make_projectile(shooter, point + Vector2(0, -8), Vector2.from_angle(angle) * rng.randf_range(170, 240), roundi(projectile.base_damage * float(rules.get("fragment_scale", 0.35))), projectile.base_radius * 0.6, style)
				fragment.sprite_size *= 0.6
				fragment.stage = "fragment"
				fragment.ignores_fighters_until = 0.0
		"rain":
			var drops: int = int(rules.get("drops", 4))
			var spacing: float = float(rules.get("spacing", 42))
			var drop_style: Dictionary = style.duplicate()
			drop_style.wind_scale = 0.0
			drop_style.erase("align")
			drop_style.spin = 0 if bool(style.get("align", false)) else 300
			for i in range(drops):
				var x: float = point.x + (i - (drops - 1) / 2.0) * spacing
				var drop: TankProjectile = make_projectile(shooter, Vector2(x, point.y - 520 - i * 36), Vector2(0, 120), roundi(projectile.base_damage * float(rules.get("drop_scale", 0.5))), projectile.base_radius * 0.75, drop_style, str(rules.get("drop_sprite", "")))
				drop.stage = "drop"
				drop.ignores_fighters_until = 0.0
				if bool(style.get("align", false)):
					# Spears fall point first.
					drop.align = true
					drop.align_offset = deg_to_rad(float(style.get("align_offset", 0)))
		"drop":
			var fridge: TankProjectile = make_projectile(shooter, Vector2(point.x, point.y - 640), Vector2(0, 160), roundi(projectile.base_damage * float(rules.get("drop_damage", 1.9))), projectile.base_radius * float(rules.get("drop_radius", 1.8)), {"size": 72, "spin": 25, "trail": "smoke", "wind_scale": 0.0}, str(rules.get("drop_sprite", "fridge")))
			fridge.stage = "drop"
			fridge.ignores_fighters_until = 0.0
		"strike":
			var bolts: int = int(rules.get("bolts", 3))
			var spacing: float = float(rules.get("spacing", 70))
			var targets: Array[Vector2] = []
			for i in range(bolts):
				var x: float = clampf(point.x + (i - (bolts - 1) / 2.0) * spacing, 4, terrain.world_size.x - 4)
				var y: float = minf(terrain.surface_y(x, 0), terrain.world_size.y)
				targets.append(Vector2(x, y))
			effect.emit("lightning", point, {"targets": targets})
			for target_point in targets:
				explode(shooter, target_point, roundi(projectile.base_damage * float(rules.get("bolt_scale", 0.7))), projectile.base_radius * 0.8, false, {})
		"heal":
			effect.emit("heal", point, {"radius": float(rules.get("heal_radius", 260))})
			for ally in fighters:
				if ally.team == shooter.team and ally.hp > 0 and ally.center().distance_to(point) <= float(rules.get("heal_radius", 260)):
					heal_fighter(ally, int(rules.get("heal", 300)))
			heal_fighter(shooter, int(rules.get("self_heal", 0)))
		"boomerang":
			var back: float = -signf(projectile.velocity.x) if absf(projectile.velocity.x) > 1 else float(-shooter.facing)
			var returning: TankProjectile = make_projectile(shooter, point + Vector2(0, -12), Vector2(back * maxf(260.0, absf(projectile.velocity.x) * 0.85), -420), roundi(projectile.base_damage * float(rules.get("return_scale", 0.9))), projectile.base_radius, style)
			returning.stage = "return"
			returning.special = {"lifesteal": float(rules.get("lifesteal", 0.25))}
			returning.ignores_fighters_until = 0.15
	projectile.queue_free()

func explode(shooter: TankFighter, point: Vector2, damage_value: int, radius: float, freeze: bool, rules: Dictionary) -> int:
	terrain.crater(point, radius)
	blast.emit(point, radius)
	var kind: String = str(rules.get("kind", ""))
	var dealt: int = 0
	for target in fighters:
		if target.hp <= 0:
			continue
		var distance: float = maxf(0, point.distance_to(target.center()) - target.hit_radius)
		var damage: int = Ballistics.splash_damage(distance, radius * float(balance.splash_scale), damage_value, false, 1.0)
		if damage <= 0:
			continue
		# Attributes from gear: Ataque raises, Defesa lowers, Sorte may crit.
		damage = roundi(damage * target.shield * Armory.attack_scale(shooter.attrs) * Armory.defense_scale(target.attrs))
		var critical: bool = false
		if target.team != shooter.team and float(shooter.attrs.get("sorte", 0)) > 0 and rng.randf() < Armory.crit_chance(shooter.attrs):
			damage = roundi(damage * 1.5)
			critical = true
		target.shield = 1.0
		target.take_damage(damage)
		target.pow_gauge = minf(float(balance.pow_max), target.pow_gauge + damage * float(balance.pow_per_damage_taken))
		if target.team != shooter.team:
			dealt += damage
			shooter.stats.damage += damage
			shooter.stats.hits += 1
			shooter.pow_gauge = minf(float(balance.pow_max), shooter.pow_gauge + damage * float(balance.pow_per_damage_dealt))
		if freeze:
			target.frozen = 1
		damage_text.emit(target.center(), ("CRÍTICO -%d" if critical else "-%d") % damage, Color("ff5aff") if critical else (Color("ffe95a") if target.team != shooter.team else Color("ff9a7a")))
		if target.hp > 0 and target.team != shooter.team and kind in ["pull", "bull"]:
			var away: float = signf(target.position.x - point.x)
			if away == 0:
				away = float(shooter.facing)
			var push: float = -minf(float(rules.get("pull", 40)), absf(target.position.x - point.x)) * away if kind == "pull" else float(rules.get("knockback", 70)) * away
			shove(target, push)
		if target.hp <= 0:
			if target.team != shooter.team:
				shooter.stats.kills += 1
			announce.emit("%s derrotou %s!" % [shooter.display_name, target.display_name], Color("ff8a6a"))
	return dealt

func shove(target: TankFighter, amount: float) -> void:
	var x: float = clampf(target.position.x + amount, 8, terrain.world_size.x - 8)
	var top: float = terrain.surface_y(x, target.position.y - 80)
	target.position = Vector2(x, minf(target.position.y, top - 1) if top < target.position.y + 4 else target.position.y)
	target.settled = false
	target.update_pose()

func heal_fighter(fighter: TankFighter, amount: int) -> void:
	if fighter.hp <= 0 or amount <= 0:
		return
	var recovered: int = mini(amount, fighter.max_hp - fighter.hp)
	if recovered > 0:
		fighter.hp += recovered
		damage_text.emit(fighter.center(), "+%d" % recovered, Color("9aff7a"))

func resolve_miss(projectile: TankProjectile) -> void:
	projectiles.erase(projectile)
	if projectile.fly:
		var shooter: TankFighter = fighters[projectile.owner_id]
		shooter.hp = 0
		shooter.hide_body()
		announce.emit("%s voou para fora do mapa!" % shooter.display_name, Color("ff8a6a"))
	projectile.queue_free()

func evaluate_winner() -> bool:
	var alive_teams: Dictionary = {}
	for fighter in fighters:
		if fighter.hp > 0:
			alive_teams[fighter.team] = true
	if alive_teams.size() > 1:
		return false
	winner_team = alive_teams.keys()[0] if alive_teams.size() == 1 else -1
	state = State.MATCH_FINISHED
	running = false
	for fighter in fighters:
		fighter.active = false
		fighter.queue_redraw()
	finished.emit(winner_team)
	changed.emit()
	return true

# ---------- simulation ----------

func _physics_process(delta: float) -> void:
	if not running or paused:
		return
	for fighter in fighters:
		fighter.step_fall(delta, terrain, float(balance.gravity))
	var fighter: TankFighter = active()
	match state:
		State.PROJECTILE_FLYING:
			for projectile in projectiles.duplicate():
				projectile.advance(delta)
			if projectiles.is_empty():
				volley_wait += delta
				if shots_left > 0 and volley_wait > 0.45 and fighter.hp > 0:
					shots_left -= 1
					fire_volley()
				elif shots_left <= 0 or fighter.hp <= 0:
					state = State.RESOLVING_DAMAGE
					resolve_time = 0
		State.RESOLVING_DAMAGE:
			resolve_time += delta
			if resolve_time > 1.0 and fighters.all(func(f: TankFighter) -> bool: return f.settled or f.hp <= 0):
				if evaluate_winner():
					return
				finish_turn()
		State.PLAYER_CHARGING:
			power += float(balance.charge_rate) * delta
			if is_ai_controlled(fighter):
				if power >= ai_plan.y:
					power = ai_plan.y
					release_shot(true)
			elif power >= 100.0:
				# The bar resets once at full force, giving one retry (DDT3 rule).
				if charge_pass == 0:
					charge_pass = 1
					power = 0
				else:
					power = 100
					release_shot()
			if state == State.PLAYER_CHARGING and not is_ai_controlled(fighter):
				remaining -= delta
				if remaining <= 0:
					release_shot()
		State.PLAYER_AIMING, State.PLAYER_MOVING, State.TURN_STARTED:
			if fighter.hp <= 0:
				state = State.RESOLVING_DAMAGE
				resolve_time = 0
				return
			if is_ai_controlled(fighter):
				ai_step(delta)
			else:
				human_step(delta)

func human_step(delta: float) -> void:
	var fighter: TankFighter = active()
	remaining -= delta
	var walking: float = clampf(move_input + keyboard_axis(KEY_A, KEY_D) + keyboard_axis(KEY_LEFT, KEY_RIGHT), -1, 1)
	var aiming: float = clampf(aim_input + keyboard_axis(KEY_S, KEY_W) + keyboard_axis(KEY_DOWN, KEY_UP), -1, 1)
	fighter.angle = clampf(fighter.angle + aiming * 30 * delta, fighter.angle_range.x, fighter.angle_range.y)
	if walking != 0:
		var cost: float = float(balance.move_energy_per_px)
		var amount: float = minf(float(balance.move_speed) * delta, energy / cost)
		if amount > 0.01 and fighter.move_ground(amount * walking, terrain):
			energy -= amount * cost
			moved_distance += amount
		elif fighter.facing != int(signf(walking)):
			fighter.facing = int(signf(walking))
		state = State.PLAYER_MOVING
	else:
		state = State.PLAYER_AIMING
	fighter.update_pose()
	if remaining <= 0:
		status_message = "Tempo esgotado"
		passed = true
		state = State.RESOLVING_DAMAGE
		resolve_time = 0.5

func plan_ai(fighter: TankFighter) -> void:
	ai_time = 0
	ai_planned = true
	ai_think = float(balance.pve.think_seconds) if fighter.is_boss else rng.randf_range(float(balance.bots.think_min), float(balance.bots.think_max))
	var target: TankFighter = EnemyAI.pick_target(fighter, fighters)
	if target == null:
		ai_plan = Vector3(45, 50, INF)
		return
	fighter.facing = 1 if target.position.x > fighter.position.x else -1
	fighter.update_pose()
	if fighter.is_boss:
		boss_enraged = fighter.hp <= fighter.max_hp / 2
		var base: float = float(balance.pve.enraged_damage if boss_enraged else balance.pve.damage)
		fighter.weapon.damage = roundi(base * float(difficulty.get("damage", 1.0)))
		status_message = "%s prepara FÚRIA SOLAR!" % fighter.display_name if boss_enraged else "%s está calculando seu ataque…" % fighter.display_name
	var wind_scale: float = float(fighter.weapon.get("projectile", {}).get("wind_scale", 1.0))
	var solution: Vector3 = EnemyAI.choose_shot(fighter, target, terrain, wind * float(balance.wind_accel) * wind_scale, balance)
	var spread: float = float(balance.pve.power_error)
	if not fighter.is_boss:
		spread = 2.5 if fighter.human else rng.randf_range(float(balance.bots.power_error_min), float(balance.bots.power_error_max))
	ai_plan = Vector3(solution.x, clampf(solution.y + rng.randf_range(-spread, spread), 5, 100), solution.z)
	if not fighter.is_boss and fighter.aux_uses > 0 and fighter.hp < fighter.max_hp * 0.45:
		apply_aux(fighter)
	if not fighter.is_boss and not fighter.human and rng.randf() < float(balance.bots.item_chance):
		var combos: Array = [["plus2", "dmg50", "dmg20"], ["triple", "dmg50", "dmg20"], ["plus1", "dmg50", "dmg20"], ["dmg50", "dmg50", "dmg40"], ["plus1", "dmg30"], ["dmg50", "dmg20"], ["powmax", "dmg50"]]
		for id: String in combos[rng.randi() % combos.size()]:
			apply_item(fighter, id)
	if not fighter.is_boss and fighter.pow_gauge >= float(balance.pow_max) and not "triple" in turn_items:
		turn_pow = true

func ai_step(delta: float) -> void:
	var fighter: TankFighter = active()
	if not ai_planned:
		plan_ai(fighter)
	ai_time += delta
	remaining = maxf(0.0, remaining - delta)
	fighter.angle = move_toward(fighter.angle, ai_plan.x, 40 * delta)
	fighter.update_pose()
	if ai_time >= ai_think and fighter.settled and absf(fighter.angle - ai_plan.x) < 0.01:
		state = State.PLAYER_CHARGING
		power = 0
		charge_pass = 0

func keyboard_axis(negative: Key, positive: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))
