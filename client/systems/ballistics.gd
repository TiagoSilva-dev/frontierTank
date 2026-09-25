class_name Ballistics
extends RefCounted

static func launch_velocity(angle: float, power: float, facing: int, balance: Dictionary) -> Vector2:
	var speed: float = lerpf(float(balance.min_speed), float(balance.max_speed), clampf(power, 0.0, 100.0) / 100.0)
	var radians: float = deg_to_rad(angle)
	return Vector2(cos(radians) * speed * facing, -sin(radians) * speed)

static func acceleration(wind: float, gravity: float) -> Vector2:
	return Vector2(wind, gravity)

static func splash_damage(distance: float, radius: float, damage: int, shield: bool, multiplier: float) -> int:
	if distance > radius:
		return 0
	var falloff: float = 1.0 - 0.65 * clampf(distance / radius, 0.0, 1.0)
	return maxi(1, roundi(damage * falloff * (multiplier if shield else 1.0)))
