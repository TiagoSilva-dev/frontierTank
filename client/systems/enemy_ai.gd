class_name EnemyAI
extends RefCounted

# Bots aim by simulating the real ballistics (30 Hz) over the weapon's angle range.

static func pick_target(shooter: TankFighter, fighters: Array[TankFighter]) -> TankFighter:
	var best: TankFighter = null
	var best_score: float = INF
	for fighter in fighters:
		if fighter.team == shooter.team or fighter.hp <= 0:
			continue
		# Prefer close and weakened enemies, as players usually do.
		var score: float = absf(fighter.position.x - shooter.position.x) + fighter.hp * 0.35
		if score < best_score:
			best_score = score
			best = fighter
	return best

static func score_shot(shooter: TankFighter, relative_angle: float, power: float, target: TankFighter, terrain: DestructibleTerrain, wind_accel: float, balance: Dictionary) -> float:
	var point: Vector2 = shooter.muzzle_at(relative_angle)
	var effective: float = relative_angle + (0.0 if shooter.is_boss else shooter.tilt * shooter.facing)
	var velocity: Vector2 = Ballistics.launch_velocity(effective, power, shooter.facing, balance)
	var goal: Vector2 = target.center()
	var gravity: float = float(balance.gravity)
	var step: float = 1.0 / 30.0
	for tick in range(420):
		velocity += Ballistics.acceleration(wind_accel, gravity) * step
		var next: Vector2 = point + velocity * step
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(goal, point, next)
		if closest.distance_to(goal) < target.hit_radius:
			return 0.0
		if terrain.solid(next) or terrain.solid((point + next) * 0.5):
			return next.distance_to(goal)
		if next.y > terrain.world_size.y + 60 or next.x < -200 or next.x > terrain.world_size.x + 200:
			return INF
		point = next
	return INF

static func choose_shot(shooter: TankFighter, target: TankFighter, terrain: DestructibleTerrain, wind_accel: float, balance: Dictionary) -> Vector3:
	# Returns (angle, power, miss distance).
	var best: Vector3 = Vector3(clampf(50, shooter.angle_range.x, shooter.angle_range.y), 60, INF)
	var angle: float = shooter.angle_range.x
	while angle <= shooter.angle_range.y:
		var power: float = 20.0
		while power <= 100.0:
			var score: float = score_shot(shooter, angle, power, target, terrain, wind_accel, balance)
			if score < best.z:
				best = Vector3(angle, power, score)
			power += 6.0
		angle += 6.0
	var coarse: Vector3 = best
	for da in range(-5, 6):
		for dp in range(-5, 6):
			var a: float = clampf(coarse.x + da, shooter.angle_range.x, shooter.angle_range.y)
			var p: float = clampf(coarse.y + dp, 5, 100)
			var score: float = score_shot(shooter, a, p, target, terrain, wind_accel, balance)
			if score < best.z:
				best = Vector3(a, p, score)
			if best.z == 0.0:
				return best
	return best

# ---------- PvE monster abilities (0.14) ----------
# Monsters do not shoot: each turn they pick one of their abilities (combat.json →
# enemies[].abilities), weighted, among those that make sense where everyone stands. A
# leap needs the target within reach and ground to land beside it, a slam needs someone
# close, a heal needs a hurt ally. Fury abilities only come while enraged (and are then
# three times as likely). Uses the match's seeded rng, so every online copy picks the same.

const FALLBACK_ABILITY: Dictionary = {"id": "ataque", "kind": "sky", "damage": 0.8, "radius": 36, "fx": "meteor"}

static func abilities_of(fighter: TankFighter) -> Array:
	var list: Array = fighter.monster.get("abilities", [])
	if list.is_empty():
		var generic: Dictionary = FALLBACK_ABILITY.duplicate()
		generic.name = str(fighter.monster.get("attack", "Ataque"))
		return [generic]
	return list

static func choose_ability(game: LocalMatch, fighter: TankFighter, target: TankFighter, enraged: bool) -> Dictionary:
	var pool: Array = []
	var total: float = 0.0
	for ability: Dictionary in abilities_of(fighter):
		if not ability_ready(game, fighter, target, ability, enraged):
			continue
		var weight: float = float(ability.get("weight", 1.0))
		if enraged and bool(ability.get("fury", false)):
			weight *= 3.0
		pool.append([ability, weight])
		total += weight
	if pool.is_empty():
		# Nothing fits (everyone out of reach): the first ranged ability, or a generic one.
		for ability: Dictionary in abilities_of(fighter):
			if str(ability.get("kind", "")) == "sky" and not bool(ability.get("fury", false)):
				return ability
		var generic: Dictionary = FALLBACK_ABILITY.duplicate()
		generic.name = str(fighter.monster.get("attack", "Ataque"))
		return generic
	var roll: float = game.rng.randf() * total
	for entry: Array in pool:
		roll -= float(entry[1])
		if roll <= 0.0:
			return entry[0]
	return pool.back()[0]

static func ability_ready(game: LocalMatch, fighter: TankFighter, target: TankFighter, ability: Dictionary, enraged: bool) -> bool:
	if bool(ability.get("fury", false)) and not enraged:
		return false
	if int(fighter.cooldowns.get(str(ability.get("id", "")), 0)) > 0:
		return false
	if fighter.turns_taken < int(ability.get("from_turn", 0)):
		return false
	var radius: float = float(ability.get("radius", 40))
	match str(ability.get("kind", "sky")):
		"leap", "dive":
			return target != null and absf(target.position.x - fighter.position.x) <= float(ability.get("reach", 600)) and landing_spot(game, fighter, target) != Vector2.INF
		"slam":
			return game.fighters.any(func(f: TankFighter) -> bool: return f.team != fighter.team and f.hp > 0 and f.rank != "totem" and f.center().distance_to(fighter.position) <= radius * 0.9)
		"breath":
			return target != null and target.center().distance_to(fighter.center()) <= float(ability.get("range", 700))
		"heal":
			return allies_near(game, fighter, radius).any(func(f: TankFighter) -> bool: return f.hp < f.max_hp * 0.7)
		"guard":
			return allies_near(game, fighter, radius).any(func(f: TankFighter) -> bool: return f.shield >= 1.0)
		"roar":
			return allies_near(game, fighter, radius).any(func(f: TankFighter) -> bool: return f.empower <= 1.0)
	return true

static func allies_near(game: LocalMatch, fighter: TankFighter, radius: float) -> Array[TankFighter]:
	var list: Array[TankFighter] = []
	for other in game.fighters:
		if other.team == fighter.team and other.hp > 0 and other.rank != "totem" and other.position.distance_to(fighter.position) <= radius:
			list.append(other)
	return list

static func landing_spot(game: LocalMatch, fighter: TankFighter, target: TankFighter) -> Vector2:
	# Where a leaping monster lands to strike: beside the target, on the side it comes
	# from if there is ground there, else on the far side. INF when neither works.
	var dir: float = signf(target.position.x - fighter.position.x)
	if dir == 0.0:
		dir = float(-fighter.facing)
	var gap: float = target.hit_radius + fighter.body_size.x * 0.35 + 6.0
	var world: Vector2 = game.terrain.world_size
	for side: float in [-dir, dir]:
		var x: float = clampf(target.position.x + side * gap, 30.0, world.x - 30.0)
		var y: float = game.terrain.surface_y(x, target.position.y - 90.0)
		if y < world.y - 10.0 and absf(y - target.position.y) < 90.0 and not game.terrain.solid(Vector2(x, y - 30.0)):
			return Vector2(x, y - 1.0)
	return Vector2.INF
