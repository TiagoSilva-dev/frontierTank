class_name ShotTrails
extends Node2D

# DDTank's "tracejado": every fired shot leaves a dashed line along its whole flight.
# The local player's last volley stays on the map until they fire again, so the next
# shot can be corrected against it; everyone else's lines fade out after landing.
# Secondary projectiles (fragments, drops from the sky) draw no line.

const DASH: float = 10.0
const GAP: float = 7.0
const STEP: float = 3.0
const FADE_AFTER: float = 2.2
const FADE_TIME: float = 0.9

var paths: Array[Dictionary] = []
var clock: float = 0.0

func track(projectile: TankProjectile, owner_id: int, turn: int, mine: bool, color: Color) -> void:
	# Lines from an earlier turn of the same fighter are replaced; a +2 or three-ball
	# volley keeps every line of this turn.
	paths = paths.filter(func(path: Dictionary) -> bool: return path.owner != owner_id or path.turn == turn)
	paths.append({"projectile": projectile, "points": PackedVector2Array([projectile.position]), "owner": owner_id, "turn": turn, "mine": mine, "color": color, "landed": -1.0})

func has_path(owner_id: int) -> bool:
	return paths.any(func(path: Dictionary) -> bool: return path.owner == owner_id)

func _process(delta: float) -> void:
	clock += delta
	var kept: Array[Dictionary] = []
	for path: Dictionary in paths:
		var projectile: TankProjectile = path.projectile if is_instance_valid(path.projectile) else null
		if path.landed < 0.0:
			if projectile != null:
				var points: PackedVector2Array = path.points
				if points[points.size() - 1].distance_to(projectile.position) >= STEP:
					points.append(projectile.position)
					path.points = points
			if projectile == null or not projectile.live:
				path.landed = clock
		if path.mine or path.landed < 0.0 or clock - path.landed < FADE_AFTER + FADE_TIME:
			kept.append(path)
	paths = kept
	queue_redraw()

func _draw() -> void:
	for path: Dictionary in paths:
		var alpha: float = 1.0
		if not path.mine and path.landed >= 0.0:
			alpha = clampf(1.0 - (clock - path.landed - FADE_AFTER) / FADE_TIME, 0.0, 1.0)
		elif path.mine and path.landed >= 0.0:
			alpha = 0.85
		if alpha <= 0.0:
			continue
		# Landed lines never change again, so their dashes are measured once.
		var dashes: PackedVector2Array = path.get("dashes", PackedVector2Array())
		if dashes.is_empty():
			dashes = dash_segments(path.points)
			if path.landed >= 0.0:
				path.dashes = dashes
		if dashes.is_empty():
			continue
		var color: Color = path.color
		draw_multiline(dashes, Color(0.06, 0.04, 0.1, 0.45 * alpha), 4.0)
		draw_multiline(dashes, Color(color.r, color.g, color.b, 0.95 * alpha), 2.0)
		if path.mine and path.landed >= 0.0:
			var end: Vector2 = path.points[path.points.size() - 1]
			draw_arc(end, 7.0, 0, TAU, 16, Color(0.06, 0.04, 0.1, 0.5 * alpha), 4.0)
			draw_arc(end, 7.0, 0, TAU, 16, Color(color.r, color.g, color.b, alpha), 2.0)

static func dash_segments(points: PackedVector2Array) -> PackedVector2Array:
	# Pairs of points for draw_multiline, measured along the path so the dashes stay
	# put while the line grows behind the projectile.
	var result: PackedVector2Array = PackedVector2Array()
	var period: float = DASH + GAP
	var walked: float = 0.0
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var length: float = a.distance_to(b)
		if length <= 0.0:
			continue
		var t: float = 0.0
		while t < length:
			var phase: float = fposmod(walked + t, period)
			if phase < DASH:
				var span: float = minf(DASH - phase, length - t)
				result.append(a.lerp(b, t / length))
				result.append(a.lerp(b, (t + span) / length))
				t += span
			else:
				t += period - phase
		walked += length
	return result
