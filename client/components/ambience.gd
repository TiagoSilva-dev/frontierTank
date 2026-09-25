class_name Ambience
extends Node2D

# Screen-space weather in front of the battlefield, set by the map's "ambience":
# snow in the ice hall, embers in the throne room, floating dust motes in the
# temples and pollen in the sky. Particles are 2x2 art pixels and slide a little
# against the camera so they feel part of the world.

const SCREEN: Vector2 = Vector2(1280, 720)

var kind: String = ""
var camera: Camera2D
var parts: Array[Dictionary] = []
var time: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func setup(kind_value: String, follow: Camera2D) -> void:
	kind = kind_value
	camera = follow
	rng.randomize()
	parts.clear()
	var count: int = {"snow": 90, "embers": 46, "motes": 40, "sky": 28}.get(kind, 0)
	for i in range(count):
		parts.append(spawn(true))

func spawn(anywhere: bool) -> Dictionary:
	var part: Dictionary = {"pos": Vector2(rng.randf_range(0, SCREEN.x), rng.randf_range(0, SCREEN.y)), "depth": rng.randf_range(0.15, 0.6), "phase": rng.randf_range(0, TAU), "size": 2.0 if rng.randf() < 0.7 else 4.0}
	match kind:
		"snow":
			part.vel = Vector2(rng.randf_range(-14, 6), rng.randf_range(36, 80))
			if not anywhere:
				part.pos.y = -8
		"embers":
			part.vel = Vector2(rng.randf_range(-10, 10), -rng.randf_range(30, 70))
			part.size = 2.0
			if not anywhere:
				part.pos.y = SCREEN.y + 8
		"motes":
			part.vel = Vector2(rng.randf_range(-8, 8), -rng.randf_range(4, 14))
		"sky":
			part.vel = Vector2(rng.randf_range(10, 26), rng.randf_range(-4, 6))
			part.size = 2.0
	return part

func _process(delta: float) -> void:
	if parts.is_empty():
		return
	time += delta
	for i in range(parts.size()):
		var part: Dictionary = parts[i]
		var sway: float = sin(time * 1.3 + part.phase)
		part.pos = part.pos + (part.vel + Vector2(sway * 10.0, 0)) * delta
		var p: Vector2 = part.pos
		if p.y > SCREEN.y + 12 or p.y < -12:
			parts[i] = spawn(false)
		elif p.x < -12 or p.x > SCREEN.x + 12:
			part.pos = Vector2(fposmod(p.x, SCREEN.x), p.y)
	queue_redraw()

func _draw() -> void:
	var shift: Vector2 = camera.position if camera != null else Vector2.ZERO
	for part: Dictionary in parts:
		# Parallax: nearer particles (bigger depth) slide more with the camera.
		var p: Vector2 = part.pos - shift * float(part.depth) * 0.5
		p = Vector2(fposmod(p.x, SCREEN.x), fposmod(p.y, SCREEN.y + 24.0) - 12.0).snapped(Vector2(2, 2))
		var twinkle: float = 0.5 + 0.5 * sin(time * 3.0 + float(part.phase) * 3.0)
		var s: float = part.size
		var color: Color
		match kind:
			"snow":
				color = Color(1, 1, 1, 0.55 + 0.35 * float(part.depth))
			"embers":
				color = Color(1.0, 0.55 + 0.35 * twinkle, 0.2, 0.5 + 0.5 * twinkle)
			"motes":
				color = Color(1.0, 0.93, 0.7, 0.25 + 0.5 * twinkle)
			_:
				color = Color(1.0, 1.0, 0.92, 0.2 + 0.4 * twinkle)
		draw_rect(Rect2(p, Vector2(s, s)), color)
