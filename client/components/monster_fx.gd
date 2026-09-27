class_name MonsterFx
extends Node2D

# The PvE monsters' abilities (0.14), drawn on a throwaway node on the 2 px art grid:
# the cast (a ring and motes in the ability's colour), reticles on the targets, things
# falling from the sky (PixelLab art in assets/effects/abilities/drops/<fx>.png), dust
# of a leap, claw and axe marks of a strike, the shockwave of a slam, a breath from the
# mouth to the target, and the support spells (guard, war cry, heal) on the allies.
# 0.16: a curse's rune circle closing on its victim (hex), a status effect landing (its
# icon pops over the victim and sinks in), poison bubbling, the Elixir Purificador and
# an explosive elite's death blast.

const DROPS: String = "res://assets/effects/abilities/drops/"
const PALETTES: Dictionary = {
	"fire": ["fff26a", "ffb02e", "ff5a1f", "b8250f"],
	"meteor": ["fff26a", "ffb02e", "ff5a1f", "b8250f"],
	"frost": ["ffffff", "c8f4ff", "7ad8ff", "3a8acc"],
	"ice": ["ffffff", "c8f4ff", "7ad8ff", "3a8acc"],
	"sun": ["fffbe0", "ffe36a", "ffb02e", "c87a0f"],
	"wind": ["ffffff", "e0f8ff", "a8e0ff", "5aa8d8"],
	"feather": ["ffffff", "e0f8ff", "a8e0ff", "5aa8d8"],
	"lightning": ["ffffff", "c8f0ff", "6ac8ff", "3a5aff"],
	"dark": ["e8d0ff", "a86aff", "5a2a9a", "2a1040"],
	"raven": ["c8e8ff", "5ab8ff", "2a3a5a", "10141f"],
	"rock": ["ffd0a0", "c8603a", "6a3a20", "2a1a10"],
	"axe": ["ffffff", "d8dce8", "8a8f9c", "5a3a20"],
	"rune": ["ffffff", "a8f0ff", "4ad8ff", "1a6a9a"],
	"poison": ["f0ffd0", "b8ff6a", "5ad82a", "1f6a14"],
}

var kind: String = ""
var data: Dictionary = {}
var age: float = 0.0
var life: float = 1.0
var color: Color = Color("ff8a4a")
var colors: Array[Color] = []
var art: Texture2D
var start: Vector2 = Vector2.ZERO
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func palette(fx: String, fallback: Color) -> Array[Color]:
	var list: Array[Color] = []
	if PALETTES.has(fx):
		for hex: String in PALETTES[fx]:
			list.append(Color(hex))
	else:
		list = [Color.WHITE, fallback.lightened(0.4), fallback, fallback.darkened(0.45)]
	return list

func _ready() -> void:
	z_index = 24
	rng.randomize()
	color = data.get("color", color)
	var fx: String = str(data.get("fx", ""))
	colors = palette(fx, color)
	match kind:
		"ability_cast":
			life = 0.9
			FxParticles.burst(self, Vector2(0, 10), {"amount": 26, "lifetime": 0.8, "speed": [40.0, 140.0], "direction": Vector2.UP, "spread": 70.0, "gravity": Vector2(0, -80), "size": [2.0, 5.0], "colors": ["ffffff", color.lightened(0.3), color]})
		"mark":
			life = float(data.get("time", 1.0)) + 0.15
		"drop":
			life = float(data.get("time", 0.55)) + (0.3 if fx == "lightning" else 0.05)
			var path: String = DROPS + fx + ".png"
			if ResourceLoader.exists(path):
				art = load(path)
			# Falls slightly slanted, from the side the light comes from.
			start = Vector2(rng.randf_range(-160.0, -60.0) * (1.0 if rng.randf() < 0.5 else -1.0), -560.0)
			if fx == "lightning":
				start = Vector2(rng.randf_range(-30.0, 30.0), -700.0)
		"leap":
			life = 0.6
			var landing: bool = bool(data.get("landing", false))
			FxParticles.burst(self, Vector2(0, -2), {"amount": 30 if landing else 18, "lifetime": 0.6, "speed": [60.0, 200.0 if landing else 130.0], "direction": Vector2.UP, "spread": 80.0, "gravity": Vector2(0, 260), "size": [3.0, 6.0], "colors": ["e8dcc8", "b8a890", "7a6a5a"], "additive": false, "box": Vector2(26, 2)})
		"strike":
			life = 0.5
			FxParticles.burst(self, Vector2.ZERO, {"amount": 30, "lifetime": 0.5, "speed": [140.0, 380.0], "spread": 180.0, "gravity": Vector2(0, 300), "size": [2.0, 5.0], "colors": ["ffffff", colors[1], colors[2]], "damping": 120.0})
		"slam":
			life = 0.9
			var radius: float = float(data.get("radius", 180))
			FxParticles.burst(self, Vector2(0, -4), {"amount": 40, "lifetime": 0.8, "speed": [80.0, 260.0], "direction": Vector2.UP, "spread": 70.0, "gravity": Vector2(0, 420), "size": [3.0, 7.0], "colors": ["e8dcc8", "b8a890", colors[2]], "additive": false, "box": Vector2(radius * 0.8, 4)})
			FxParticles.burst(self, Vector2(0, -8), {"amount": 24, "lifetime": 0.6, "speed": [200.0, 420.0], "direction": Vector2.UP, "spread": 60.0, "gravity": Vector2(0, 600), "size": [2.0, 4.0], "colors": ["ffffff", colors[1], colors[2]]})
		"breath":
			life = float(data.get("time", 0.9)) + 0.3
			var to: Vector2 = (data.get("to", global_position) as Vector2) - global_position
			var distance: float = to.length()
			var direction: Vector2 = to.normalized() if distance > 1.0 else Vector2.RIGHT
			var stream: CPUParticles2D = FxParticles.stream(self, Vector2.ZERO, {"amount": 90, "lifetime": 0.55, "speed": [distance * 1.3, distance * 1.9], "direction": direction, "spread": 9.0, "gravity": Vector2.ZERO, "size": [4.0, 10.0], "colors": ["ffffff", colors[1], colors[2], colors[3]], "damping": distance * 0.9})
			get_tree().create_timer(float(data.get("time", 0.9))).timeout.connect(func() -> void:
				if is_instance_valid(stream):
					stream.emitting = false)
		"guard", "roar", "heal_allies":
			life = 1.1
			for ally: Vector2 in data.get("allies", []):
				var local: Vector2 = ally - global_position
				var tint: Array = ["ffffff", "c8f0ff", "5ab8ff"] if kind == "guard" else (["ffffff", "ffb0a0", "ff4a3a"] if kind == "roar" else ["ffffff", "b8ffc8", "5cff8a"])
				FxParticles.burst(self, local, {"amount": 18, "lifetime": 0.9, "speed": [30.0, 90.0], "direction": Vector2.UP, "spread": 60.0, "gravity": Vector2(0, -60), "size": [2.0, 4.0], "colors": tint})
		"burn":
			life = 0.6
			FxParticles.burst(self, Vector2.ZERO, {"amount": 22, "lifetime": 0.6, "speed": [30.0, 110.0], "direction": Vector2.UP, "spread": 50.0, "gravity": Vector2(0, -160), "size": [3.0, 6.0], "colors": ["fff26a", "ffb02e", "ff5a1f"]})
		"poison":
			life = 0.7
			FxParticles.burst(self, Vector2.ZERO, {"amount": 20, "lifetime": 0.7, "speed": [20.0, 80.0], "direction": Vector2.UP, "spread": 60.0, "gravity": Vector2(0, -90), "size": [3.0, 6.0], "colors": ["e0ffb0", "8aff4a", "3aa81a"], "additive": false})
		"hex":
			life = float(data.get("time", 0.95)) + 0.35
		"status":
			life = 1.15
			art = StatusRules.icon(str(data.get("id", "")))
			FxParticles.burst(self, Vector2.ZERO, {"amount": 24, "lifetime": 0.7, "speed": [60.0, 170.0], "spread": 180.0, "gravity": Vector2(0, 120), "size": [2.0, 5.0], "colors": ["ffffff", color.lightened(0.3), color], "damping": 60.0})
		"cleanse":
			life = 1.0
			FxParticles.burst(self, Vector2(0, 10), {"amount": 36, "lifetime": 0.9, "speed": [40.0, 150.0], "direction": Vector2.UP, "spread": 80.0, "gravity": Vector2(0, -120), "size": [2.0, 5.0], "colors": ["ffffff", "fff4c0", "ffd86a"]})
		"elite_blast":
			life = 0.9
			var reach: float = float(data.get("radius", 150))
			FxParticles.burst(self, Vector2.ZERO, {"amount": 60, "lifetime": 0.8, "speed": [reach * 0.8, reach * 2.2], "spread": 180.0, "gravity": Vector2(0, 260), "size": [3.0, 8.0], "colors": ["ffffff", colors[1], colors[2], "5a3a2a"], "damping": reach})

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(age / life, 0.0, 1.0)
	var fade: float = 1.0 - t
	match kind:
		"ability_cast":
			var r: float = 20.0 + 70.0 * PowImpact.ease_out(t)
			draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(color.r, color.g, color.b, 0.9 * fade), 5.0 * fade + 1.0)
			draw_arc(Vector2.ZERO, r * 0.6, age * 5.0, age * 5.0 + PI * 1.4, 24, Color(1, 1, 1, 0.7 * fade), 3.0)
		"mark":
			draw_mark()
		"drop":
			draw_drop()
		"strike":
			draw_strike(t, fade)
		"slam":
			var radius: float = float(data.get("radius", 180))
			draw_set_transform(Vector2(0, -2), 0, Vector2(1.0, 0.28))
			for k in range(2):
				var w: float = clampf((age - k * 0.12) / 0.6, 0.0, 1.0)
				if w > 0.0 and w < 1.0:
					draw_arc(Vector2.ZERO, radius * PowImpact.ease_out(w), 0, TAU, 56, Color(colors[1].r, colors[1].g, colors[1].b, 1.0 - w), 10.0 * (1.0 - w) + 2.0)
			draw_circle(Vector2.ZERO, radius * 0.3 * fade, Color(colors[2].r, colors[2].g, colors[2].b, 0.35 * fade))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			# Cracks racing out along the ground.
			for i in range(8):
				var side: float = -1.0 if i % 2 == 0 else 1.0
				var reach: float = radius * minf(1.0, age * 3.0) * (0.5 + 0.12 * floorf(i / 2.0))
				var y: float = -2.0 + floorf(i / 2.0) * 1.5
				draw_line(Vector2(side * 10.0, y), Vector2(side * reach, y + sin(i * 2.1) * 4.0), Color(0.1, 0.06, 0.04, 0.8 * fade), 2.0)
		"breath":
			var to: Vector2 = (data.get("to", global_position) as Vector2) - global_position
			var grow: float = minf(1.0, age / 0.25)
			var shown: float = fade if age > float(data.get("time", 0.9)) else 1.0
			var side: Vector2 = to.normalized().orthogonal() if to.length() > 1.0 else Vector2.UP
			var tip: Vector2 = to * grow
			draw_colored_polygon(PackedVector2Array([side * 6.0, tip + side * 46.0, tip - side * 46.0, -side * 6.0]), Color(colors[2].r, colors[2].g, colors[2].b, 0.28 * shown))
			draw_colored_polygon(PackedVector2Array([side * 3.0, tip + side * 22.0, tip - side * 22.0, -side * 3.0]), Color(colors[1].r, colors[1].g, colors[1].b, 0.4 * shown))
		"guard":
			for ally: Vector2 in data.get("allies", []):
				var local: Vector2 = ally - global_position
				var r: float = 50.0 * PowImpact.ease_out(minf(1.0, age * 3.0))
				for k in range(6):
					var a: float = TAU * k / 6.0 + age
					draw_line(local + Vector2.from_angle(a) * r, local + Vector2.from_angle(a + TAU / 6.0) * r, Color(0.6, 0.9, 1.0, 0.9 * fade), 3.0)
				draw_circle(local, r, Color(0.4, 0.8, 1.0, 0.18 * fade))
		"roar":
			for k in range(3):
				var w: float = clampf((age - k * 0.15) / 0.7, 0.0, 1.0)
				if w > 0.0 and w < 1.0:
					draw_arc(Vector2.ZERO, 30.0 + 260.0 * w, -PI * 0.9, -PI * 0.1, 24, Color(1.0, 0.35, 0.2, 0.8 * (1.0 - w)), 5.0)
			for ally: Vector2 in data.get("allies", []):
				draw_circle(ally - global_position, 26.0 * fade + 8.0, Color(1.0, 0.3, 0.2, 0.3 * fade))
		"hex":
			draw_hex()
		"status":
			draw_status(t, fade)
		"cleanse":
			var r: float = 20.0 + 60.0 * PowImpact.ease_out(t)
			draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(1.0, 0.95, 0.7, 0.9 * fade), 4.0 * fade + 1.0)
			draw_circle(Vector2.ZERO, 30.0 * fade, Color(1.0, 1.0, 0.9, 0.35 * fade))
			for k in range(8):
				var a: float = TAU * k / 8.0 + age * 2.0
				var p: Vector2 = (Vector2.from_angle(a) * r * 0.8).snapped(Vector2(2, 2))
				draw_rect(Rect2(p - Vector2(2, 6), Vector2(4, 12)), Color(1, 1, 0.85, fade))
				draw_rect(Rect2(p - Vector2(6, 2), Vector2(12, 4)), Color(1, 1, 0.85, fade))
		"elite_blast":
			var reach: float = float(data.get("radius", 150))
			for k in range(2):
				var w: float = clampf((age - k * 0.1) / 0.55, 0.0, 1.0)
				if w > 0.0 and w < 1.0:
					draw_arc(Vector2.ZERO, reach * PowImpact.ease_out(w), 0, TAU, 56, Color(colors[1].r, colors[1].g, colors[1].b, 1.0 - w), 12.0 * (1.0 - w) + 2.0)
			draw_circle(Vector2.ZERO, reach * 0.5 * fade, Color(1.0, 0.95, 0.8, 0.5 * fade * fade))
		"heal_allies":
			for ally: Vector2 in data.get("allies", []):
				var local: Vector2 = ally - global_position + Vector2(0, -t * 60.0)
				var s: float = 7.0
				draw_rect(Rect2(local - Vector2(s, s / 3), Vector2(s * 2, s * 2 / 3)), Color(0.5, 1.0, 0.55, fade))
				draw_rect(Rect2(local - Vector2(s / 3, s), Vector2(s * 2 / 3, s * 2)), Color(0.5, 1.0, 0.55, fade))

func draw_hex() -> void:
	# A curse: a rune circle closing on the victim, runes turning, then a flash.
	var time: float = float(data.get("time", 0.95))
	var u: float = clampf(age / time, 0.0, 1.0)
	var r: float = lerpf(96.0, 30.0, PowImpact.ease_out(u))
	var shown: float = 1.0 if age < time else 1.0 - (age - time) / (life - time)
	var tint: Color = Color(color.r, color.g, color.b, 0.9 * shown)
	draw_set_transform(Vector2(0, 8), 0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, r, Color(color.r * 0.3, color.g * 0.2, color.b * 0.4, 0.35 * shown))
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, tint, 4.0)
	draw_arc(Vector2.ZERO, r * 0.72, -age * 4.0, -age * 4.0 + TAU, 40, Color(tint, 0.6 * shown), 2.0)
	for k in range(8):
		var a: float = TAU * k / 8.0 + age * 2.5
		var p: Vector2 = (Vector2.from_angle(a) * r * 0.86).snapped(Vector2(2, 2))
		draw_rect(Rect2(p - Vector2(3, 5), Vector2(6, 10)), Color(1, 1, 1, 0.85 * shown) if k % 2 == 0 else tint)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# Chains of light rising from the circle into the victim.
	for k in range(4):
		var x: float = (k - 1.5) * r * 0.45
		draw_line(Vector2(x, 8), Vector2(x * 0.3, -30.0 * u), Color(tint, 0.5 * shown), 2.0)
	if age > time:
		var f: float = 1.0 - (age - time) / (life - time)
		draw_circle(Vector2.ZERO, 44.0 * (1.0 - f) + 10.0, Color(1, 1, 1, 0.55 * f))

func draw_status(t: float, fade: float) -> void:
	# The status icon pops out over the victim, hangs a moment and sinks into it.
	# Several effects landing together pop side by side.
	var order: int = int(data.get("order", 0))
	var side: float = [0.0, 44.0, -44.0, 88.0, -88.0][order % 5]
	var pop: float = PowImpact.ease_out(minf(1.0, maxf(0.0, age - order * 0.08) / 0.2))
	var sink: float = clampf((age - 0.6) / 0.45, 0.0, 1.0)
	var at: Vector2 = Vector2(side, -64.0).lerp(Vector2.ZERO, sink * sink)
	var scale: float = (0.6 + 0.9 * pop) * (1.0 - 0.55 * sink)
	var ring: float = minf(1.0, age / 0.45)
	draw_arc(at, 18.0 + 40.0 * ring, 0, TAU, 36, Color(color.r, color.g, color.b, 1.0 - ring), 4.0 * (1.0 - ring) + 1.0)
	draw_circle(at, 22.0 * scale, Color(color.r, color.g, color.b, 0.35 * (1.0 - sink)))
	if art != null:
		var size: Vector2 = Vector2(32, 32) * scale
		draw_texture_rect(art, Rect2(at - size / 2.0, size), false, Color(1, 1, 1, 1.0 - sink * 0.8))
	if sink >= 1.0:
		draw_circle(Vector2.ZERO, 26.0 * fade, Color(color.r, color.g, color.b, 0.4 * fade))

func draw_mark() -> void:
	# A reticle closing in on the target until the hit.
	var time: float = float(data.get("time", 1.0))
	var u: float = clampf(age / time, 0.0, 1.0)
	var r: float = lerpf(64.0, 22.0, PowImpact.ease_out(u))
	var pulse: float = 0.5 + 0.5 * sin(age * 20.0)
	var tint: Color = Color(1.0, 0.25, 0.2, 0.55 + 0.35 * pulse)
	draw_arc(Vector2.ZERO, r, age * 3.0, age * 3.0 + TAU, 32, tint, 3.0)
	for k in range(4):
		var a: float = TAU * k / 4.0 + age * 3.0
		draw_line(Vector2.from_angle(a) * (r - 8.0), Vector2.from_angle(a) * (r + 10.0), tint, 3.0)
	draw_circle(Vector2.ZERO, 4.0, tint)
	if age > time:
		draw_circle(Vector2.ZERO, 40.0, Color(1, 1, 1, 0.6 * (1.0 - (age - time) / 0.15)))

func draw_drop() -> void:
	var fx: String = str(data.get("fx", "meteor"))
	var time: float = float(data.get("time", 0.55))
	var u: float = clampf(age / time, 0.0, 1.0)
	if fx == "lightning":
		# A thin warning line, then the bolt.
		if age < time:
			draw_line(start, Vector2.ZERO, Color(0.8, 0.95, 1.0, 0.25 + 0.3 * u), 2.0)
			return
		var f: float = 1.0 - (age - time) / 0.3
		var points: PackedVector2Array = PackedVector2Array([start])
		for k in range(1, 10):
			var p: Vector2 = start.lerp(Vector2.ZERO, k / 10.0)
			points.append(p + Vector2(sin(k * 12.7 + floorf(age * 30.0) * 3.1) * 16.0, 0))
		points.append(Vector2.ZERO)
		draw_polyline(points, Color(colors[2].r, colors[2].g, colors[2].b, f), 9.0)
		draw_polyline(points, Color(1, 1, 1, f), 3.0)
		draw_circle(Vector2.ZERO, 34.0 * f + 6.0, Color(colors[1].r, colors[1].g, colors[1].b, 0.5 * f))
		return
	# Accelerating fall with a streak behind.
	var e: float = u * u
	var p: Vector2 = start.lerp(Vector2.ZERO, e)
	var heading: Vector2 = (Vector2.ZERO - start).normalized()
	for k in range(6):
		var back: Vector2 = p - heading * (k + 1) * 14.0
		var s: float = 10.0 - k * 1.4
		var c: Color = colors[mini(colors.size() - 1, 1 + floori(k / 2.0))]
		draw_rect(Rect2(back - Vector2(s, s) / 2.0, Vector2(s, s)), Color(c.r, c.g, c.b, 0.7 - k * 0.1))
	if art != null:
		var spin: float = age * 14.0 if fx in ["axe", "rock"] else heading.angle() - PI / 2.0
		draw_set_transform(p, spin, Vector2.ONE * 1.4)
		draw_texture(art, -art.get_size() / 2.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_circle(p, 14.0, colors[2])
		draw_circle(p, 8.0, colors[0])

func draw_strike(t: float, fade: float) -> void:
	var fx: String = str(data.get("fx", "slash"))
	var facing: float = float(data.get("facing", 1))
	var grow: float = PowImpact.ease_out(minf(1.0, t * 3.0))
	var white: Color = Color(1, 1, 1, fade)
	var tint: Color = Color(colors[2].r, colors[2].g, colors[2].b, fade)
	match fx:
		"claw", "bite":
			# Three raking marks (two closing jaws for a bite).
			var marks: int = 2 if fx == "bite" else 3
			for k in range(marks):
				var off: float = (k - (marks - 1) / 2.0) * 16.0
				var a0: Vector2 = Vector2(-34.0 * facing, -30.0 + off)
				var a1: Vector2 = Vector2(34.0 * facing, 26.0 + off)
				if fx == "bite":
					a0 = Vector2(-30.0, -24.0 if k == 0 else 24.0)
					a1 = Vector2(30.0, -6.0 if k == 0 else 6.0)
				var end: Vector2 = a0.lerp(a1, grow)
				draw_line(a0, end, tint, 9.0 * fade + 2.0)
				draw_line(a0, end, white, 3.0)
		"smash", "horn":
			for k in range(10):
				var a: float = TAU * k / 10.0
				var len: float = (50.0 if k % 2 == 0 else 30.0) * grow
				draw_line(Vector2.ZERO, Vector2.from_angle(a) * len, tint, 6.0 * fade + 1.0)
			draw_circle(Vector2.ZERO, 26.0 * grow, Color(1, 1, 1, 0.6 * fade))
			draw_arc(Vector2.ZERO, 60.0 * grow, 0, TAU, 32, tint, 4.0)
		"peck":
			draw_circle(Vector2.ZERO, 20.0 * grow, Color(1, 1, 1, 0.7 * fade))
			for k in range(6):
				var a: float = TAU * k / 6.0 + 0.4
				draw_line(Vector2.from_angle(a) * 10.0, Vector2.from_angle(a) * 34.0 * grow, tint, 4.0)
		_:
			# slash: one wide arc swept in the facing direction.
			var from: float = -PI * 0.75 if facing > 0 else -PI * 0.25
			var sweep: float = PI * 1.1 * grow * facing
			draw_arc(Vector2.ZERO, 46.0, from, from + sweep, 24, tint, 12.0 * fade + 2.0)
			draw_arc(Vector2.ZERO, 46.0, from, from + sweep, 24, white, 4.0)
