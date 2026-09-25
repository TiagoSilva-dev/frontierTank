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
