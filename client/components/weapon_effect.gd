class_name WeaponEffect
extends Node2D

# Short-lived POW visuals: rainbow beam, lightning bolts, healing crosses, hearts,
# the spectral bull and the divine tornado; in instances also the boss summoning a
# minion ("summon"), the flying boss changing place ("warp") and a new wave ("wave").
# Drawn procedurally, then freed.

const RAINBOW: Array[Color] = [Color("ff4a4a"), Color("ffa13a"), Color("ffe84a"), Color("5ce65c"), Color("4ab8ff"), Color("8a5cff")]

var kind: String = ""
var data: Dictionary = {}
var top: float = -600.0
var age: float = 0.0
var life: float = 1.0
var bull: Sprite2D

func _ready() -> void:
	life = {"beam": 1.1, "lightning": 0.6, "heal": 1.2, "hearts": 1.2, "bull": 0.9, "tornado": 1.0, "summon": 0.9, "warp": 0.9, "wave": 0.1}.get(kind, 1.0)
	if kind == "summon":
		FxParticles.burst(self, Vector2(0, -10), {"amount": 30, "lifetime": 0.8, "speed": [60.0, 200.0], "direction": Vector2.UP, "spread": 60.0, "gravity": Vector2(0, -60), "size": [2.0, 4.0], "colors": ["fff26a", "ff7a1f", "b8250f"]})
	elif kind == "warp":
		FxParticles.burst(self, Vector2.ZERO, {"amount": 26, "lifetime": 0.9, "speed": [80.0, 220.0], "gravity": Vector2(0, 80), "size": [3.0, 5.0], "colors": ["ffffff", "c8f4ff", "7ad8ff"], "additive": false, "tangential": 200.0})
	if kind == "bull" and ResourceLoader.exists("res://assets/projectiles/bull_spirit.png"):
		bull = Sprite2D.new()
		bull.texture = load("res://assets/projectiles/bull_spirit.png")
		bull.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bull.flip_h = int(data.get("facing", 1)) < 0
		var material: CanvasItemMaterial = CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		bull.material = material
		add_child(bull)

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	if bull != null:
		var t: float = age / life
		var dir: float = -1.0 if bull.flip_h else 1.0
		bull.position = Vector2(dir * lerpf(-160.0, 40.0, minf(1.0, t * 1.6)), -40.0)
		bull.scale = Vector2.ONE * lerpf(1.2, 2.6, t)
		bull.modulate.a = 1.0 - t * t
	queue_redraw()

func _draw() -> void:
	var t: float = age / life
	var fade: float = 1.0 - t
	match kind:
		"beam":
			var height: float = -top + position.y
			var width: float = 46.0 * (0.4 + minf(1.0, t * 4.0)) * fade
			for i in range(RAINBOW.size()):
				var x: float = -width / 2 + width * i / RAINBOW.size()
				var c: Color = RAINBOW[i]
				draw_rect(Rect2(x, -height, width / RAINBOW.size() + 1, height), Color(c.r, c.g, c.b, 0.75 * fade))
			draw_rect(Rect2(-width * 0.15, -height, width * 0.3, height), Color(1, 1, 1, 0.6 * fade))
			for i in range(12):
				var y: float = -fposmod(age * 600.0 + i * 70.0, height)
				draw_rect(Rect2(sin(i * 2.3) * width * 0.6, y, 3, 3), Color(1, 1, 1, fade))
		"lightning":
			for target: Vector2 in data.get("targets", []):
				var end: Vector2 = target - global_position
				var start: Vector2 = Vector2(end.x + 20.0, top - global_position.y)
				var points: PackedVector2Array = PackedVector2Array([start])
				var steps: int = 10
				for k in range(1, steps):
					var p: Vector2 = start.lerp(end, float(k) / steps)
					points.append(p + Vector2(sin(k * 12.7 + floorf(age * 20.0) * 3.1) * 14.0, 0))
				points.append(end)
				draw_polyline(points, Color(0.6, 0.85, 1.0, fade), 7.0)
				draw_polyline(points, Color(1, 1, 1, fade), 3.0)
				draw_circle(end, 26.0 * fade + 6.0, Color(0.7, 0.9, 1.0, 0.5 * fade))
		"heal":
			var radius: float = float(data.get("radius", 120.0))
			draw_arc(Vector2.ZERO, radius * minf(1.0, t * 2.5), 0, TAU, 48, Color(0.4, 1.0, 0.5, 0.7 * fade), 4.0)
			for i in range(10):
				var angle: float = TAU * i / 10.0
				var p: Vector2 = Vector2.from_angle(angle) * radius * 0.5 * fposmod(i * 0.37 + 0.3, 1.0) + Vector2(0, -t * 80.0)
				var s: float = 5.0
				draw_rect(Rect2(p - Vector2(s, s / 3), Vector2(s * 2, s * 2 / 3)), Color(0.5, 1.0, 0.55, fade))
				draw_rect(Rect2(p - Vector2(s / 3, s), Vector2(s * 2 / 3, s * 2)), Color(0.5, 1.0, 0.55, fade))
		"hearts":
			for i in range(8):
				var p: Vector2 = Vector2(sin(i * 1.9 + age * 3.0) * 30.0, -t * 90.0 - i * 8.0)
				var s: float = 5.0 + (i % 3)
				var c: Color = Color(1.0, 0.4, 0.7, fade)
				draw_circle(p + Vector2(-s * 0.5, 0), s * 0.6, c)
				draw_circle(p + Vector2(s * 0.5, 0), s * 0.6, c)
				draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 1.05, s * 0.2), p + Vector2(s * 1.05, s * 0.2), p + Vector2(0, s * 1.4)]), c)
		"summon":
			draw_set_transform(Vector2(0, 2), 0, Vector2(1.0, 0.3))
			draw_arc(Vector2.ZERO, 30.0 + t * 50.0, 0, TAU, 32, Color(1.0, 0.5, 0.15, fade), 6.0)
			draw_circle(Vector2.ZERO, 26.0 + t * 30.0, Color(1.0, 0.8, 0.3, 0.3 * fade))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			draw_rect(Rect2(-14.0 * fade, -140.0, 28.0 * fade, 140.0), Color(1.0, 0.6, 0.2, 0.35 * fade))
		"warp":
			var target: Vector2 = (data.get("to", global_position) as Vector2) - global_position
			for i in range(6):
				var a: float = age * 12.0 + i * TAU / 6.0
				draw_arc(Vector2(0, -i * 10.0), 18.0 + i * 8.0, a, a + PI, 12, Color(0.85, 0.97, 1.0, 0.8 * fade), 3.0)
			draw_line(Vector2.ZERO, target, Color(0.8, 0.95, 1.0, 0.35 * fade), 6.0)
			draw_circle(target + Vector2(0, -60), 30.0 * fade + 6.0, Color(0.8, 0.95, 1.0, 0.45 * fade))
		"tornado":
			for i in range(9):
				var y: float = -i * 16.0 - t * 30.0
				var r: float = 12.0 + i * 7.0
				var start_angle: float = age * 14.0 + i
				draw_arc(Vector2(sin(age * 6.0 + i) * 6.0, y), r, start_angle, start_angle + PI * 1.3, 16, Color(0.85, 0.97, 1.0, 0.7 * fade), 3.0)
