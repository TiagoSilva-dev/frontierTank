class_name LocalMatch
extends Node2D

# One battle. Turn order follows DDTank's Delay rule: every action adds delay and the
# living fighter with the lowest delay plays next.
#
# Offline this node is the authority and steps itself. Online (backend 0.11) the battle
# runs in lockstep: the game server and every player run this same simulation from the
# same config and seed. The server stamps each player's intent with a tick and sends it
# to everyone; each copy applies the intents of a tick (apply_input) and then steps it
# (step), so every copy stays identical and only intents cross the network. The server's
# copy decides rewards; `checksum` lets the players notice if theirs drifted.

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
# A skill 1–9, tool, auxiliary item, the paper plane or POW was used. The screen shows
# the fighter consuming it (icon over the head), as in DDTank. Info: id, name, kind
# (multi, power, powmax, heal, energy, shield, plane, angel, pow) and icon (a res://
# path or a PixelIcons name).
signal skill_used(fighter: TankFighter, info: Dictionary)
# A POW shot landed (0.8): the screen plays the weapon's own impact; the match holds
# still for `hitstop` seconds.
signal pow_impact(point: Vector2, radius: float, weapon_id: String)

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
# PvE phase (0.9, built by InstanceRun): name, objective ("defeat", "totems", "survive"),
# turns to survive and the waves still to come; threats come from the map item.
var phase: Dictionary = {}
var waves: Array = []
var threats: Dictionary = {}
var players: int = 1
var survived: int = 0
var hitstop: float = 0.0
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
# Online: stepped from outside (LockstepDriver or the server's MatchHost), no keyboard
# polling, and the local player's intents go to the server through `remote`.
var lockstep: bool = false
var remote: Callable = Callable()
# The first human fighter: the same on every copy (local_id is not), so rules that
# follow "the player" (turns survived) use it.
var anchor_id: int = 0
# Online: the force bar the local player sees while charging, measured locally so the
# shot uses exactly the force they released at (the simulation runs a little behind).
var predicted_power: float = -1.0
var predicted_pass: int = 0
const ACTING: Array[State] = [State.TURN_STARTED, State.PLAYER_MOVING, State.PLAYER_AIMING]

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
	# The seed comes first: the random map is part of the seeded battle (online every
	# copy must draw the same map).
	if config.has("seed"):
		rng.seed = int(config.seed)
	map = find_map(str(config.get("map", "")))
	turn_seconds = float(config.get("turn_seconds", balance.turn_seconds))
	phase = config.get("phase", {})
	waves = phase.get("waves", []).duplicate(true)
	threats = config.get("threats", {})
	players = maxi(1, int(config.get("players", 1)))
	lockstep = bool(config.get("lockstep", false))
	predicted_power = -1.0
	survived = 0
	hitstop = 0.0
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
	anchor_id = 0
	for fighter in fighters:
		if fighter.human:
			anchor_id = fighter.player_id
			break
	# Online each player's copy knows which fighter is theirs.
	local_id = clampi(int(config.get("local", anchor_id)), 0, fighters.size() - 1)
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
	if pve and not phase.is_empty():
		announce.emit(tr("Fase %d: %s") % [int(phase.get("index", 0)) + 1, str(phase.get("name", ""))], Color("ffd04a"))
	if opener != null and opener.team == fighters[local_id].team:
		announce.emit(tr("Processo de busca sucedido! A sua equipe começará o combate!"), Color("fff4a0"))
	else:
		announce.emit(tr("Processo de busca sucedido! A equipe adversária começa."), Color("fff4a0"))
	begin_turn()

func spawn_fighter(entry: Dictionary, index: int, count: int, drop: bool = false) -> TankFighter:
	var fighter: TankFighter = TankFighter.new()
	var enemy: String = str(entry.get("enemy", "rei_helio" if entry.get("boss", false) else ""))
	if enemy != "":
		fighter.setup_monster(fighters.size(), entry, enemy_def(enemy), balance)
	else:
		fighter.setup(fighters.size(), entry, Armory.weapon_for_entry(entry), balance)
		# Map threat: players have less energy (move less).
		fighter.max_energy = roundi(fighter.max_energy * float(entry.get("energy_scale", 1.0)))
	var tools: Array = entry.get("tools", [])
	for tool in tools:
		fighter.tools.append(str(tool))
	apply_carry(fighter, entry.get("carry", {}))
	var span: Array = map.spawns[int(entry.team)]
	var x: float = lerpf(float(span[0]), float(span[1]), (index + 0.5) / maxf(1, count)) + rng.randf_range(-30, 30)
	x = float(entry.get("x", x))
	x = find_ground(x)
	fighter.position = Vector2(x, terrain.surface_y(x) - 1)
	if drop:
		# Reinforcements fall from the sky onto the battlefield.
		fighter.position.y = maxf(-200.0, fighter.position.y - 420.0)
		fighter.settled = false
	fighter.tilt = 0.0 if fighter.is_monster or drop else terrain.slope_degrees(fighter.position.x, fighter.position.y)
	fighter.facing = 1 if fighter.position.x < terrain.world_size.x * 0.5 else -1
	add_child(fighter)
	fighter.update_pose()
	fighters.append(fighter)
	return fighter

func apply_carry(fighter: TankFighter, carry: Dictionary) -> void:
	# State kept between the phases of an instance: life (already healed by the run),
	# POW, tools, uses of the auxiliary item and the battle statistics.
	if carry.is_empty():
		return
	fighter.hp = clampi(int(carry.get("hp", fighter.max_hp)), 1, fighter.max_hp)
	fighter.pow_gauge = float(carry.get("pow", 0.0))
	if carry.has("tools"):
		fighter.tools.clear()
		for tool: Variant in carry.tools:
			fighter.tools.append(str(tool))
	if carry.has("aux_uses"):
		fighter.aux_uses = int(carry.aux_uses)
	if carry.has("stats"):
		fighter.stats = (carry.stats as Dictionary).duplicate()

func enemy_def(id: String) -> Dictionary:
	for entry: Dictionary in balance.get("enemies", []):
		if entry.id == id:
			return entry
	return balance.enemies[0]

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
		if fighter.acts() and (best == null or fighter.delay < best.delay):
			best = fighter
	return best

func turn_order() -> Array[TankFighter]:
	var order: Array[TankFighter] = []
	for fighter in fighters:
		if fighter.acts():
			order.append(fighter)
	order.sort_custom(func(a: TankFighter, b: TankFighter) -> bool: return a.delay < b.delay or (a.delay == b.delay and a.player_id < b.player_id))
	return order

func is_ai_controlled(fighter: TankFighter) -> bool:
	return not fighter.human or fighter.auto_play

func can_act() -> bool:
	return running and not paused and state in ACTING and active_id == local_id and not is_ai_controlled(active())

func send_intent(action: String, data: Dictionary = {}) -> bool:
	# Online: the intent goes to the server, which sends it back to everyone with a tick.
	if not remote.is_valid():
		return false
	remote.call(action, data)
	return true

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
	if threats.get("strong_wind", false):
		# Map threat: the wind never drops below 70% of the maximum.
		wind = snappedf((1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(float(balance.wind_max) * 0.7, float(balance.wind_max)), 0.1)
	fighter.pow_gauge = minf(float(balance.pow_max), fighter.pow_gauge + float(balance.pow_per_turn))
	for other in fighters:
		other.active = other == fighter
		other.update_pose()
	if fighter.frozen > 0:
		fighter.frozen -= 1
		skip_turn = true
		status_message = tr("%s está congelado e perde a vez!") % fighter.display_name
		announce.emit(status_message, Color("a8e8ff"))
		state = State.RESOLVING_DAMAGE
		resolve_time = 0.3
		turn_started.emit(fighter)
		changed.emit()
		return
	state = State.PLAYER_AIMING
	if fighter.player_id == local_id and not fighter.auto_play:
		status_message = tr("Sua vez! Segure ESPAÇO para definir a força")
	else:
		status_message = tr("Vez de %s") % fighter.display_name
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
		if fighter.bonus.has("delay"):
			# "-Delay" bonus from gear (0.10); a turn always adds some delay.
			added = maxf(100.0, added - float(fighter.bonus.delay))
	fighter.delay += added
	fighter.fly_cooldown = maxi(0, fighter.fly_cooldown - 1)
	fighter.active = false
	state = State.TURN_FINISHED
	if pve:
		after_pve_turn(fighter)
		if evaluate_winner():
			return
	begin_turn()

# ---------- player intents ----------

func charge() -> void:
	if not can_act() or not active().settled:
		return
	if send_intent("charge"):
		predicted_power = 0.0
		predicted_pass = 0
		return
	begin_charge()

func begin_charge() -> void:
	state = State.PLAYER_CHARGING
	power = 0
	charge_pass = 0
	move_input = 0
	status_message = tr("Solte ESPAÇO para disparar")

func release() -> void:
	# The player lets go of SPACE. Online the intent carries the force they saw.
	if remote.is_valid():
		if active_id == local_id and predicted_power >= 0.0:
			send_intent("release", {"power": snappedf(predicted_power, 0.01)})
			predicted_power = -1.0
		return
	release_shot()

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
	if fighter.is_monster:
		freeze = monster_freezes(fighter)
		# Groups of 3+ players: the boss adds an area attack (three shots) every round.
		if fighter.is_boss and players >= int(balance.party_scaling.get("boss_area_from", 3)):
			balls = 3
			spread = 6.0
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
		# "+% dano do POW" (0.10) also reaches the POW's fragments, drops and bolts.
		scale *= float(pow_rules.get("damage_scale", 1.0)) * (1.0 + float(fighter.bonus.get("pow", 0)) / 100.0)
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
					var recovered: int = mini(healing(ally, heal), ally.max_hp - ally.hp)
					ally.hp += recovered
					if recovered > 0:
						damage_text.emit(ally.center(), "+%d" % recovered, Color("9aff7a"))
		fighter.pow_gauge = 0
		announce.emit(tr("%s usou POW: %s!") % [fighter.display_name, tr(str(pow_rules.name))], Color("ffd04a"))
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
		if not pow_plan.is_empty():
			# 0.8: the POW shot is drawn bigger and trails its own colours (visual only).
			if str(pow_plan.get("kind", "")) != "giant":
				projectile.sprite_size *= Armory.visual("pow_projectile_scale")
			projectile.set_powered(PowImpact.colors_for(str(fighter.weapon.get("id", ""))))
		projectile.base_damage = int(shot_plan.get("base_damage", shot_plan.damage))
		projectile.base_radius = float(shot_plan.get("base_radius", shot_plan.radius))
	fighter.stats.shots += 1
	fighter.animate_attack()
	volley_wait = 0
	state = State.PROJECTILE_FLYING
	status_message = tr("Projétil em voo")
	changed.emit()

func make_projectile(fighter: TankFighter, from: Vector2, velocity: Vector2, damage: int, radius: float, style: Dictionary, sprite_key: String = "") -> TankProjectile:
	var projectile: TankProjectile = TankProjectile.new()
	projectile.position = from
	projectile.velocity = velocity
	projectile.wind = wind * float(balance.wind_accel) * float(style.get("wind_scale", 1.0)) * wind_factor(fighter)
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
	if style.has("texture"):
		path = str(style.texture)
	elif key != "" and fighter.weapon.has("projectile"):
		path = Armory.projectile_path(str(fighter.weapon.id), key, int(fighter.weapon.get("level", 0)))
	projectile.apply_style(style, path)
	# 0.8: bigger projectile art; hits still use the projectile's point against
	# fighter.hit_radius and the terrain mask, so the hitbox does not change.
	projectile.sprite_size *= Armory.visual("projectile_scale")
	projectile.impacted.connect(resolve_impact)
	projectile.missed.connect(resolve_miss)
	add_child(projectile)
	projectiles.append(projectile)
	shot_fired.emit(projectile)
	return projectile

func shown_power() -> float:
	return predicted_power if predicted_power >= 0.0 else power

func flip_aim() -> void:
	if can_act() and not send_intent("flip"):
		active().facing *= -1
		active().update_pose()

func use_item(id: String) -> bool:
	if not can_act():
		return false
	if send_intent("item", {"id": id}):
		return true
	return apply_item(active(), id)

func apply_item(fighter: TankFighter, id: String) -> bool:
	var item: Dictionary = item_def(id)
	if item.is_empty() or turn_fly or fighter.is_monster:
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
	var free: float = Armory.bonus_limit(fighter.bonus, "poupar")
	if free > 0.0 and rng.randf() < free:
		# Weapon bonus (0.10): a chance that the skill costs no energy.
		damage_text.emit(fighter.center() + Vector2(0, -26), tr("GRÁTIS!"), Color("9ae8ff"))
	else:
		energy -= float(item.energy)
	turn_items.append(id)
	if fill:
		# POW Máx (item 9): the bar fills now, so B can release the special this turn.
		fighter.pow_gauge = float(balance.pow_max)
	skill_used.emit(fighter, {"id": id, "name": tr(str(item.name)), "icon": str(item.icon), "kind": "multi" if multi else ("powmax" if fill else "power")})
	changed.emit()
	return true

func use_tool(slot: int) -> bool:
	if not can_act():
		return false
	if send_intent("tool", {"slot": slot}):
		return true
	return apply_tool(active(), slot)

func apply_tool(fighter: TankFighter, slot: int) -> bool:
	if slot < 0 or slot >= fighter.tools.size() or fighter.tools[slot] == "":
		return false
	var tool: Dictionary = tool_def(fighter.tools[slot])
	var kind: String = "heal"
	if tool.has("heal"):
		if fighter.hp >= fighter.max_hp:
			return false
		var recovered: int = mini(healing(fighter, int(tool.heal)), fighter.max_hp - fighter.hp)
		fighter.hp += recovered
		damage_text.emit(fighter.center(), "+%d" % recovered, Color("9aff7a"))
	elif tool.has("team_heal"):
		for ally in fighters:
			if ally.team == fighter.team and ally.hp > 0 and ally.hp < ally.max_hp:
				var healed: int = mini(healing(ally, int(tool.team_heal)), ally.max_hp - ally.hp)
				ally.hp += healed
				damage_text.emit(ally.center(), "+%d" % healed, Color("9aff7a"))
	elif tool.has("energy"):
		energy += float(tool.energy)
		kind = "energy"
	elif tool.has("pow"):
		fighter.pow_gauge = float(balance.pow_max)
		kind = "powmax"
	elif tool.has("shield"):
		fighter.shield = float(tool.shield)
		kind = "shield"
	elif tool.has("fly_reset"):
		if fighter.fly_cooldown == 0:
			return false
		fighter.fly_cooldown = 0
		kind = "plane"
	skill_used.emit(fighter, {"id": str(tool.id), "name": tr(str(tool.name)), "icon": str(tool.icon), "kind": kind})
	fighter.tools[slot] = ""
	tools_used += 1
	announce.emit(tr("%s usou %s") % [fighter.display_name, tr(str(tool.name))], Color("c8f0ff"))
	fighter.queue_redraw()
	changed.emit()
	return true

func use_aux() -> bool:
	# Item auxiliar (Bálsamo, escudos): limited uses per battle, key V.
	if not can_act():
		return false
	if send_intent("aux"):
		return true
	return apply_aux(active())

func apply_aux(fighter: TankFighter) -> bool:
	var def: Dictionary = Armory.aux_def(fighter.aux_id)
	if def.is_empty() or fighter.aux_uses <= 0:
		return false
	if def.has("heal_ratio"):
		if fighter.hp >= fighter.max_hp:
			return false
		heal_fighter(fighter, roundi(fighter.max_hp * float(def.heal_ratio)))
		effect.emit("heal", fighter.center(), {"radius": 60.0, "aux": true})
	elif def.has("shield"):
		if fighter.shield < 1.0:
			return false
		fighter.shield = float(def.shield)
	fighter.aux_uses -= 1
	tools_used += 1
	skill_used.emit(fighter, {"id": str(def.id), "name": tr(str(def.name)), "icon": str(def.icon), "kind": "angel" if def.has("heal_ratio") else "shield"})
	announce.emit(tr("%s usou %s") % [fighter.display_name, tr(str(def.name))], Color("c8f0ff"))
	fighter.queue_redraw()
	changed.emit()
	return true

func toggle_fly() -> bool:
	if not can_act():
		return false
	if send_intent("fly"):
		return true
	return apply_fly(active())

func apply_fly(fighter: TankFighter) -> bool:
	var cost: float = float(balance.fly.energy)
	if threats.get("no_plane", false) and not turn_fly:
		return false
	if turn_fly:
		turn_fly = false
		energy += cost
	elif fighter.fly_cooldown == 0 and turn_items.is_empty() and not turn_pow and energy >= cost:
		turn_fly = true
		energy -= cost
		skill_used.emit(fighter, {"id": "plane", "name": tr("Avião de Papel"), "icon": "plane", "kind": "plane"})
	else:
		return false
	changed.emit()
	return true

func activate_pow() -> bool:
	if not can_act():
		return false
	if send_intent("pow"):
		return true
	return apply_pow(active())

func apply_pow(fighter: TankFighter) -> bool:
	if turn_pow or turn_fly or fighter.pow_gauge < float(balance.pow_max) or "triple" in turn_items:
		return false
	arm_pow(fighter)
	changed.emit()
	return true

func arm_pow(fighter: TankFighter) -> void:
	turn_pow = true
	fighter.set_pow_armed(true)
	skill_used.emit(fighter, {"id": "pow", "name": tr(str(fighter.weapon.get("pow", {}).get("name", "POW"))), "icon": "pow", "kind": "pow"})

func pass_turn() -> void:
	if not can_act() or send_intent("pass"):
		return
	apply_pass()

func apply_pass() -> void:
	passed = true
	status_message = tr("%s passou a vez") % active().display_name
	state = State.RESOLVING_DAMAGE
	resolve_time = 0.5
	changed.emit()

func set_auto_play(value: bool) -> void:
	if send_intent("auto", {"on": value}):
		return
	apply_auto(local_id, value)

func apply_auto(id: int, value: bool) -> void:
	# "Confiar": the AI plays for this fighter (also when a player leaves or drops).
	var fighter: TankFighter = fighters[id]
	fighter.auto_play = value
	if id == local_id:
		auto_play = value
	if running and active_id == id and state in ACTING:
		if value:
			plan_ai(fighter)
		elif id == local_id:
			status_message = tr("Sua vez! Segure ESPAÇO para definir a força")
	changed.emit()

# ---------- online: intents stamped by the server ----------

static func num(data: Dictionary, key: String) -> float:
	var value: Variant = data.get(key, 0.0)
	return float(value) if value is float or value is int else 0.0

# Applies one intent on every copy of the battle, at the tick the server gave it.
# The rules are the same checks the local buttons go through.
func apply_input(id: int, action: String, data: Dictionary) -> void:
	if not running or id < 0 or id >= fighters.size():
		return
	var fighter: TankFighter = fighters[id]
	match action:
		"auto":
			if not fighter.left:
				apply_auto(id, bool(data.get("on", false)))
			return
		"leave":
			# The player left or dropped: the AI plays for them until the end.
			fighter.left = true
			apply_auto(id, true)
			return
	if id != active_id or is_ai_controlled(fighter) or paused:
		return
	if action == "release":
		if state == State.PLAYER_CHARGING:
			power = clampf(num(data, "power"), 0.0, 100.0)
			release_shot()
		return
	if not state in ACTING:
		return
	match action:
		"move":
			move_input = clampf(num(data, "d"), -1.0, 1.0)
		"aim":
			aim_input = clampf(num(data, "d"), -1.0, 1.0)
			if data.has("angle"):
				fighter.angle = clampf(num(data, "angle"), fighter.angle_range.x, fighter.angle_range.y)
				fighter.update_pose()
		"charge":
			if fighter.settled:
				begin_charge()
		"item":
			apply_item(fighter, str(data.get("id", "")))
		"tool":
			apply_tool(fighter, int(num(data, "slot")))
		"pow":
			apply_pow(fighter)
		"fly":
			apply_fly(fighter)
		"aux":
			apply_aux(fighter)
		"pass":
			apply_pass()
		"flip":
			fighter.facing *= -1
			fighter.update_pose()
	changed.emit()

# A fingerprint of the battle, compared between the server and the players.
func checksum() -> int:
	return checksum_text().hash()

func checksum_text() -> String:
	var parts: PackedStringArray = PackedStringArray([str(state), str(active_id), str(round_number), "%.2f" % wind, str(rng.state), str(fighters.size()), str(projectiles.size())])
	for fighter in fighters:
		parts.append("%d|%.1f|%.1f|%.1f|%.1f|%.1f|%d" % [fighter.hp, fighter.position.x, fighter.position.y, fighter.delay, fighter.pow_gauge, fighter.angle, fighter.facing])
	return "/".join(parts)

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
	if not rules.is_empty() and projectile.stage == "main" and rules.has("name"):
		# The POW lands: a few frames of hit-stop and the weapon's own impact.
		hitstop = maxf(hitstop, Armory.visual("pow_hitstop"))
		pow_impact.emit(point, projectile.radius, str(shooter.weapon.get("id", "")))
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
			# Critical hits deal x1.5, plus the "+% dano crítico" bonus (0.10).
			damage = roundi(damage * (1.5 + float(shooter.bonus.get("critico", 0)) / 100.0))
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
		damage_text.emit(target.center(), (tr("CRÍTICO -%d") if critical else "-%d") % damage, Color("ff5aff") if critical else (Color("ffe95a") if target.team != shooter.team else Color("ff9a7a")))
		if target.hp > 0 and target.team != shooter.team and kind in ["pull", "bull"]:
			var away: float = signf(target.position.x - point.x)
			if away == 0:
				away = float(shooter.facing)
			var push: float = -minf(float(rules.get("pull", 40)), absf(target.position.x - point.x)) * away if kind == "pull" else float(rules.get("knockback", 70)) * away
			shove(target, push)
		if target.hp <= 0:
			if target.team != shooter.team:
				shooter.stats.kills += 1
			announce.emit(tr("%s derrotou %s!") % [shooter.display_name, target.display_name], Color("ff8a6a"))
	return dealt

func shove(target: TankFighter, amount: float) -> void:
	var x: float = clampf(target.position.x + amount, 8, terrain.world_size.x - 8)
	var top: float = terrain.surface_y(x, target.position.y - 80)
	target.position = Vector2(x, minf(target.position.y, top - 1) if top < target.position.y + 4 else target.position.y)
	target.settled = false
	target.update_pose()

func healing(fighter: TankFighter, amount: int) -> int:
	# "+% cura recebida" (0.10) raises every heal the fighter receives.
	return roundi(amount * (1.0 + float(fighter.bonus.get("cura", 0)) / 100.0))

func wind_factor(fighter: TankFighter) -> float:
	# "-% efeito do vento" (0.10), capped at 50%.
	return 1.0 - Armory.bonus_limit(fighter.bonus, "vento")

func heal_fighter(fighter: TankFighter, amount: int) -> void:
	if fighter.hp <= 0 or amount <= 0:
		return
	var recovered: int = mini(healing(fighter, amount), fighter.max_hp - fighter.hp)
	if recovered > 0:
		fighter.hp += recovered
		damage_text.emit(fighter.center(), "+%d" % recovered, Color("9aff7a"))

func resolve_miss(projectile: TankProjectile) -> void:
	projectiles.erase(projectile)
	if projectile.fly:
		var shooter: TankFighter = fighters[projectile.owner_id]
		shooter.hp = 0
		shooter.hide_body()
		announce.emit(tr("%s voou para fora do mapa!") % shooter.display_name, Color("ff8a6a"))
	projectile.queue_free()

func evaluate_winner() -> bool:
	var alive_teams: Dictionary = {}
	for fighter in fighters:
		if fighter.hp > 0 and fighter.rank != "totem":
			alive_teams[fighter.team] = true
	if pve and alive_teams.has(0):
		var objective: String = str(phase.get("objective", "defeat"))
		var totems: Array[TankFighter] = fighters.filter(func(f: TankFighter) -> bool: return f.rank == "totem")
		if objective == "totems" and not totems.is_empty() and totems.all(func(f: TankFighter) -> bool: return f.hp <= 0):
			alive_teams = {0: true}
		elif objective == "survive" and survived >= int(phase.get("turns", 6)):
			alive_teams = {0: true}
		elif not alive_teams.has(1) and not waves.is_empty():
			# The next wave of minions drops in; the phase goes on.
			spawn_wave(waves.pop_front())
			return false
		elif objective == "totems" and not alive_teams.has(1):
			# Only the totems are left standing: the phase goes on until they break.
			return false
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

func _process(delta: float) -> void:
	# Online: the local force bar grows with real time (the reset at the top included).
	if predicted_power >= 0.0:
		if state != State.PLAYER_CHARGING and state != State.PLAYER_AIMING and state != State.PLAYER_MOVING and state != State.TURN_STARTED:
			predicted_power = -1.0
			return
		predicted_power += float(balance.charge_rate) * delta
		if predicted_power >= 100.0:
			if predicted_pass == 0:
				predicted_pass = 1
				predicted_power = 0.0
			else:
				predicted_power = 100.0
				release()

func _physics_process(delta: float) -> void:
	if not lockstep:
		step(delta)

func step(delta: float) -> void:
	if not running or paused:
		return
	if hitstop > 0.0:
		hitstop -= delta
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
					# Online the player's release carries the force (sent at 100 too).
					if not lockstep:
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
	var walking: float = move_input
	var aiming: float = aim_input
	if not lockstep:
		walking = clampf(move_input + keyboard_axis(KEY_A, KEY_D) + keyboard_axis(KEY_LEFT, KEY_RIGHT), -1, 1)
		aiming = clampf(aim_input + keyboard_axis(KEY_S, KEY_W) + keyboard_axis(KEY_DOWN, KEY_UP), -1, 1)
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
		status_message = tr("Tempo esgotado")
		passed = true
		state = State.RESOLVING_DAMAGE
		resolve_time = 0.5

func plan_ai(fighter: TankFighter) -> void:
	ai_time = 0
	ai_planned = true
	ai_think = float(balance.pve.think_seconds) if fighter.is_monster else rng.randf_range(float(balance.bots.think_min), float(balance.bots.think_max))
	var target: TankFighter = EnemyAI.pick_target(fighter, fighters)
	if target == null:
		ai_plan = Vector3(45, 50, INF)
		return
	fighter.facing = 1 if target.position.x > fighter.position.x else -1
	fighter.update_pose()
	if fighter.is_monster:
		plan_monster(fighter)
	var wind_scale: float = float(fighter.weapon.get("projectile", {}).get("wind_scale", 1.0))
	var solution: Vector3 = EnemyAI.choose_shot(fighter, target, terrain, wind * float(balance.wind_accel) * wind_scale * wind_factor(fighter), balance)
	var spread: float = float(balance.pve.power_error) if fighter.is_boss else float(balance.pve.get("minion_power_error", 6.0))
	if not fighter.is_monster:
		spread = 2.5 if fighter.human else rng.randf_range(float(balance.bots.power_error_min), float(balance.bots.power_error_max))
	ai_plan = Vector3(solution.x, clampf(solution.y + rng.randf_range(-spread, spread), 5, 100), solution.z)
	if not fighter.is_monster and fighter.aux_uses > 0 and fighter.hp < fighter.max_hp * 0.45:
		apply_aux(fighter)
	if not fighter.is_monster and not fighter.human and rng.randf() < float(balance.bots.item_chance):
		var combos: Array = [["plus2", "dmg50", "dmg20"], ["triple", "dmg50", "dmg20"], ["plus1", "dmg50", "dmg20"], ["dmg50", "dmg50", "dmg40"], ["plus1", "dmg30"], ["dmg50", "dmg20"], ["powmax", "dmg50"]]
		for id: String in combos[rng.randi() % combos.size()]:
			apply_item(fighter, id)
	if not fighter.is_monster and fighter.pow_gauge >= float(balance.pow_max) and not "triple" in turn_items:
		arm_pow(fighter)

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

# ---------- PvE: waves and boss mechanics ----------

func spawn_wave(entries: Array) -> void:
	var floor_delay: float = next_delay_floor()
	for i in range(entries.size()):
		var entry: Dictionary = entries[i].duplicate()
		entry.team = 1
		var fighter: TankFighter = spawn_fighter(entry, i, entries.size(), true)
		# Newcomers wait for the fighters already on the field before acting.
		fighter.delay = floor_delay + 60.0 + rng.randf_range(0.0, 40.0)
	announce.emit(tr("Uma nova onda de inimigos chegou!"), Color("ff9a5a"))
	effect.emit("wave", Vector2(terrain.world_size.x * 0.7, 0), {"count": entries.size()})

func next_delay_floor() -> float:
	var lowest: float = INF
	for fighter in fighters:
		if fighter.acts():
			lowest = minf(lowest, fighter.delay)
	return 0.0 if lowest == INF else lowest

func mechanics(fighter: TankFighter) -> Array:
	return fighter.monster.get("mechanics", [])

func plan_monster(fighter: TankFighter) -> void:
	if not fighter.is_boss and fighter.rank != "guardian":
		status_message = tr("%s prepara um ataque") % fighter.display_name
		return
	var enraged: bool = fighter.always_enraged or fighter.hp <= fighter.max_hp / 2
	if fighter.is_boss:
		boss_enraged = enraged
	if enraged and "fury" in mechanics(fighter):
		fighter.weapon.damage = fighter.fury_damage
		status_message = tr("%s prepara %s!") % [fighter.display_name, tr(str(fighter.monster.get("fury_name", "Fúria"))).to_upper()]  # i18n
	else:
		fighter.weapon.damage = fighter.base_damage
		status_message = tr("%s está calculando seu ataque…") % fighter.display_name
	# Rei das Máscaras: calls more masks every few turns (at most 3 minions alive).
	if "summon" in mechanics(fighter) and fighter.turns_taken > 0 and fighter.turns_taken % 3 == 0:
		var minions: int = fighters.filter(func(f: TankFighter) -> bool: return f.team == fighter.team and f.hp > 0 and f.rank == "minion").size()
		if minions < 3 and not fighter.summon_entry.is_empty():
			var entry: Dictionary = fighter.summon_entry.duplicate()
			entry.team = fighter.team
			entry.x = clampf(fighter.position.x - fighter.facing * rng.randf_range(90, 160), 40, terrain.world_size.x - 40)
			var minion: TankFighter = spawn_fighter(entry, 0, 1, true)
			minion.delay = fighter.delay + 50.0
			announce.emit(tr("%s invoca %s!") % [fighter.display_name, minion.display_name], Color("ff8a4a"))
			effect.emit("summon", minion.position, {})

func monster_freezes(fighter: TankFighter) -> bool:
	# Rainha da Nevasca: every second attack freezes whoever it hits (they lose a turn).
	return "freeze" in mechanics(fighter) and fighter.turns_taken % 2 == 1

func after_pve_turn(fighter: TankFighter) -> void:
	if fighter.team == 0 and fighter.player_id == anchor_id:
		survived += 1
	# Grifo da Tempestade: flies to another spot after every attack.
	if fighter.is_monster and fighter.hp > 0 and "teleport" in mechanics(fighter) and not skip_turn and not passed:
		var old: Vector2 = fighter.position
		var span: Array = map.spawns[fighter.team]
		var x: float = old.x
		for attempt in range(8):
			x = find_ground(rng.randf_range(float(span[0]), float(span[1])))
			if absf(x - old.x) > 160:
				break
		fighter.position = Vector2(x, maxf(-200.0, terrain.surface_y(x) - 260.0))
		fighter.settled = false
		effect.emit("warp", old + Vector2(0, -fighter.monster_height * 0.5), {"to": fighter.position})
		announce.emit(tr("%s voa para outra posição!") % fighter.display_name, Color("a8e8ff"))

func keyboard_axis(negative: Key, positive: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))
