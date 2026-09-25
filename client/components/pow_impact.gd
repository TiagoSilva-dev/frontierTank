class_name PowImpact
extends Node2D

# Where a POW lands. Every special has its own colours, shape and particles: rubble for
# the Tijolaço, lava for the Braseiro, ice crystals for the Geladeira, double
# lightning for the Para-Raios, hearts for the Super Cupido and so on. It plays on top
# of the normal explosion (ImpactFx); the match holds still for a few frames (hit-stop)
# and the camera shakes. Drawn on the 2 px art grid, then freed.

const LIFE: float = 1.4
const STYLES: Dictionary = {
	"quebra_tijolos": {"colors": ["fff0d0", "ffb27a", "c8603a", "6a3a20"], "shape": "rocks", "smoke": "8a6a50"},
	"fogo_intenso": {"colors": ["fff26a", "ffb02e", "ff5a1f", "b8250f"], "shape": "lava", "smoke": "4a2a20"},
	"canhao_arco_iris": {"colors": ["ffffff", "ffe84a", "ff7ae0", "4ab8ff"], "shape": "prism", "smoke": "c8a8ff"},
	"vento_de_deus": {"colors": ["ffffff", "c8f4ff", "7ad8ff", "3a8acc"], "shape": "swirl", "smoke": "c8e8f0"},
	"cesto_newton": {"colors": ["fff6a0", "ffb347", "ff5a5a", "4ec23a"], "shape": "leaves", "smoke": "8a7a50"},
	"kit_medico": {"colors": ["ffffff", "b8ffc8", "5cff8a", "1f9a4a"], "shape": "crosses", "smoke": "c8ffd8"},
	"eletrodomestico": {"colors": ["ffffff", "c8f0ff", "8ad8ff", "4a8acc"], "shape": "ice", "smoke": "d8f0ff"},
	"trovao": {"colors": ["ffffff", "a8ecff", "4ab8ff", "2a5aff"], "shape": "bolts", "smoke": "5a6a8a"},
	"desentupidor": {"colors": ["ffffff", "c8ecff", "8ad0ff", "ff5a7a"], "shape": "bubbles", "smoke": "a8c8e0"},
	"cabeca_de_boi": {"colors": ["ffe0fa", "ff7ae0", "d02aa8", "7a1060"], "shape": "horns", "smoke": "5a2a4a"},
	"bumerangue_amor": {"colors": ["ffffff", "ffd0f0", "ff7ac8", "ff3a8a"], "shape": "hearts", "smoke": "ffb8e0"},
	"lanca_antiga": {"colors": ["ffffff", "e0fff0", "7affc0", "2ab87a"], "shape": "shards", "smoke": "3a6a50"},
	"boss": {"colors": ["fffbe0", "ffe36a", "ffb02e", "c8300f"], "shape": "sun", "smoke": "5a3a20"},
}

var weapon_id: String = ""
var radius: float = 50.0
var top: float = -600.0
var age: float = 0.0
var style: Dictionary = {}
var colors: Array[Color] = []
var bits: Array[Dictionary] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func style_for(id: String) -> Dictionary:
	return STYLES.get(id, STYLES.boss)

static func colors_for(id: String) -> Array[Color]:
	var list: Array[Color] = []
	for hex: String in style_for(id).colors:
		list.append(Color(hex))
	return list

func _ready() -> void:
	z_index = 22
	rng.randomize()
	style = style_for(weapon_id)
	colors = colors_for(weapon_id)
	var shape: String = str(style.shape)
	var count: int = {"rocks": 14, "lava": 16, "prism": 12, "swirl": 10, "leaves": 16, "crosses": 12, "ice": 9, "bolts": 2, "bubbles": 18, "horns": 7, "hearts": 14, "shards": 6, "sun": 16}.get(shape, 12)
	for i in range(count):
		var angle: float = rng.randf_range(-PI * 0.95, -PI * 0.05)
		bits.append({
			"angle": angle,
			"side": -1.0 if i % 2 == 0 else 1.0,
			"pos": Vector2.from_angle(angle) * rng.randf_range(0.0, radius * 0.4),
			"vel": Vector2.from_angle(angle) * rng.randf_range(160.0, 360.0 + radius * 2.0),
			"size": rng.randf_range(4.0, 9.0),
			"spin": rng.randf_range(-8.0, 8.0),
			"delay": rng.randf_range(0.0, 0.18),
			"x": rng.randf_range(-1.0, 1.0),
			"tone": colors[1 + rng.randi() % (colors.size() - 1)],
		})
	# Real particles: bright sparks thrown out, the weapon's own motes and smoke.
	FxParticles.burst(self, Vector2.ZERO, {"amount": 46, "lifetime": 0.7, "speed": [180.0, 460.0], "spread": 180.0, "gravity": Vector2(0, 520), "size": [2.0, 5.0], "colors": colors, "damping": 60.0, "radius": radius * 0.3})
	FxParticles.burst(self, Vector2(0, -6), {"amount": 18, "lifetime": 1.3, "speed": [20.0, 70.0], "spread": 80.0, "gravity": Vector2(0, -40), "size": [6.0, 12.0], "colors": [Color(str(style.smoke)).lightened(0.2), Color(str(style.smoke))], "additive": false, "radius": radius * 0.6, "explosiveness": 0.7})
	match shape:
		"lava":
			FxParticles.burst(self, Vector2.ZERO, {"amount": 30, "lifetime": 1.4, "speed": [40.0, 140.0], "gravity": Vector2(0, -90), "size": [2.0, 4.0], "colors": ["fff26a", "ff7a1f", "b8250f"], "box": Vector2(radius, 4), "explosiveness": 0.4})
		"ice", "swirl":
			FxParticles.burst(self, Vector2.ZERO, {"amount": 26, "lifetime": 1.2, "speed": [30.0, 120.0], "gravity": Vector2(0, 30), "size": [2.0, 3.0], "colors": ["ffffff", colors[2]], "radius": radius, "tangential": 120.0 if shape == "swirl" else 0.0})
		"bolts", "sun", "prism":
			FxParticles.burst(self, Vector2.ZERO, {"amount": 24, "lifetime": 0.5, "speed": [300.0, 560.0], "gravity": Vector2.ZERO, "size": [2.0, 3.0], "colors": ["ffffff", colors[1]], "damping": 400.0})
		"leaves", "hearts", "crosses", "bubbles":
			FxParticles.burst(self, Vector2.ZERO, {"amount": 20, "lifetime": 1.3, "speed": [40.0, 110.0], "gravity": Vector2(0, -50), "size": [2.0, 4.0], "colors": ["ffffff", colors[2]], "radius": radius * 0.8, "explosiveness": 0.5})

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	var shape: String = str(style.shape)
	for bit: Dictionary in bits:
		if age < float(bit.delay):
			continue
		var gravity: float = 700.0
		match shape:
			"leaves", "hearts", "crosses", "bubbles":
				gravity = -60.0
				bit.vel = bit.vel * (1.0 - delta * 3.2)
			"swirl", "prism", "sun", "horns", "bolts", "ice", "shards":
				gravity = 0.0
		bit.vel = bit.vel + Vector2(0, gravity * delta)
		bit.pos = bit.pos + bit.vel * delta
	queue_redraw()

func _draw() -> void:
	var t: float = age / LIFE
	var fade: float = clampf(1.0 - t, 0.0, 1.0)
	var bright: Color = colors[0]
	# Flash, then three shockwaves in the weapon's colours and a ring across the ground.
	if age < 0.12:
		var f: float = age / 0.12
		draw_circle(Vector2.ZERO, radius * (1.0 + f * 0.8), Color(bright.r, bright.g, bright.b, 0.95 * (1.0 - f)))
	for k in range(3):
		var w: float = (age - k * 0.08) / 0.55
		if w > 0.0 and w < 1.0:
			var tone: Color = colors[mini(k + 1, colors.size() - 1)]
			draw_arc(Vector2.ZERO, radius * (0.4 + 1.8 * ease_out(w)), 0, TAU, 64, Color(tone.r, tone.g, tone.b, 0.85 * (1.0 - w)), 6.0 * (1.0 - w) + 2.0)
	var ground: float = ease_out(clampf(age / 0.7, 0.0, 1.0))
	draw_set_transform(Vector2(0, 4), 0, Vector2(1.0, 0.26))
	draw_arc(Vector2.ZERO, radius * (0.8 + 2.4 * ground), 0, TAU, 48, Color(colors[1].r, colors[1].g, colors[1].b, 0.8 * fade), 10.0)
	draw_circle(Vector2.ZERO, radius * (0.6 + 1.2 * ground), Color(colors[2].r, colors[2].g, colors[2].b, 0.25 * fade))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	call("draw_" + str(style.shape), fade)

static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func pixel(p: Vector2) -> Vector2:
	return p.snapped(Vector2(2, 2))

func square(p: Vector2, s: float, color: Color, outline: bool = true) -> void:
	s = snappedf(s, 2.0)
	if outline:
		draw_rect(Rect2(pixel(p) - Vector2(s, s) / 2.0 - Vector2(2, 2), Vector2(s + 4, s + 4)), Color(0.1, 0.05, 0.03, color.a))
	draw_rect(Rect2(pixel(p) - Vector2(s, s) / 2.0, Vector2(s, s)), color)

func heart(center: Vector2, s: float, color: Color) -> void:
	draw_circle(center + Vector2(-s * 0.5, 0), s * 0.6, color)
	draw_circle(center + Vector2(s * 0.5, 0), s * 0.6, color)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-s * 1.05, s * 0.2), center + Vector2(s * 1.05, s * 0.2), center + Vector2(0, s * 1.4)]), color)

func bolt(from: Vector2, to: Vector2, seed_value: float, color: Color, width: float) -> void:
	var points: PackedVector2Array = PackedVector2Array([from])
	var steps: int = 12
	for k in range(1, steps):
		var p: Vector2 = from.lerp(to, float(k) / steps)
		points.append(p + Vector2(sin(k * 12.7 + seed_value + floorf(age * 24.0) * 3.1) * 16.0, 0))
	points.append(to)
	draw_polyline(points, color, width)

# ---------- one shape per weapon ----------

func draw_rocks(fade: float) -> void:
	# Brick rubble thrown up and tumbling down.
	for bit: Dictionary in bits:
		var tone: Color = bit.tone
		square(bit.pos, bit.size + 2.0, Color(tone.r, tone.g, tone.b, fade))

func draw_lava(fade: float) -> void:
	# Molten blobs arc out and a glowing pool spreads on the ground.
	draw_set_transform(Vector2(0, 2), 0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, radius * 1.4 * ease_out(age / 0.5), Color(1.0, 0.45, 0.1, 0.55 * fade))
	draw_circle(Vector2.ZERO, radius * 0.8 * ease_out(age / 0.5), Color(1.0, 0.9, 0.4, 0.6 * fade))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for bit: Dictionary in bits:
		var p: Vector2 = pixel(bit.pos)
		var s: float = bit.size * 0.7
		draw_circle(p, s + 2.0, Color(0.72, 0.15, 0.06, fade))
		draw_circle(p, s, Color(1.0, 0.55, 0.12, fade))
		draw_circle(p + Vector2(-1, -1), s * 0.45, Color(1.0, 0.95, 0.5, fade))

func draw_prism(fade: float) -> void:
	# Rainbow halos opening one inside the other and spinning light rays.
	var rainbow: Array[Color] = [Color("ff4a4a"), Color("ffa13a"), Color("ffe84a"), Color("5ce65c"), Color("4ab8ff"), Color("8a5cff")]
	for i in range(rainbow.size()):
		var w: float = ease_out(clampf((age - i * 0.04) / 0.6, 0.0, 1.0))
		draw_arc(Vector2.ZERO, radius * (0.4 + w * 1.6) + i * 5.0, 0, TAU, 56, Color(rainbow[i].r, rainbow[i].g, rainbow[i].b, 0.85 * fade), 5.0)
	for bit: Dictionary in bits:
		var a: float = float(bit.angle) * 2.0 + age * 2.4
		var tip: Vector2 = Vector2.from_angle(a) * radius * (1.4 + ease_out(age / 0.4))
		var side: Vector2 = Vector2.from_angle(a + PI / 2) * 5.0
		draw_colored_polygon(PackedVector2Array([side, -side, tip]), Color(1, 1, 1, 0.45 * fade))

func draw_swirl(fade: float) -> void:
	# A divine whirlwind: arcs spinning up from the crater.
	for i in range(9):
		var y: float = -i * radius * 0.28 - age * 60.0
		var r: float = radius * (0.4 + i * 0.16) * (0.6 + ease_out(age / 0.4) * 0.6)
		var start: float = age * 16.0 + i * 0.9
		var tone: Color = colors[1 + i % (colors.size() - 1)]
		draw_arc(Vector2(sin(age * 7.0 + i) * 8.0, y), r, start, start + PI * 1.2, 20, Color(tone.r, tone.g, tone.b, 0.8 * fade), 4.0)
	for bit: Dictionary in bits:
		var dir: Vector2 = Vector2.from_angle(bit.angle)
		var p: Vector2 = dir * radius * (0.8 + age * 3.0)
		draw_line(p, p + dir * 22.0, Color(1, 1, 1, 0.7 * fade), 2.0)

func draw_leaves(fade: float) -> void:
	# Leaves and splashes of juice fluttering down.
	for bit: Dictionary in bits:
		var p: Vector2 = pixel(bit.pos + Vector2(sin(age * 6.0 + float(bit.x) * 5.0) * 10.0, 0))
		var s: float = float(bit.size) * 1.6
		var a: float = age * float(bit.spin)
		var tip: Vector2 = Vector2.from_angle(a) * s
		var side: Vector2 = Vector2.from_angle(a + PI / 2) * s * 0.45
		var tone: Color = Color("4ec23a") if int(s) % 2 == 0 else bit.tone
		draw_colored_polygon(PackedVector2Array([p + tip, p + side, p - tip, p - side]), Color(tone.r, tone.g, tone.b, fade))

func draw_crosses(fade: float) -> void:
	# Green crosses rising with a soft healing ring.
	draw_arc(Vector2.ZERO, radius * 1.6 * ease_out(age / 0.5), 0, TAU, 48, Color(0.5, 1.0, 0.6, 0.6 * fade), 4.0)
	for bit: Dictionary in bits:
		var p: Vector2 = pixel(Vector2(float(bit.x) * radius * 1.3, -age * 90.0 - float(bit.delay) * 200.0))
		var s: float = snappedf(bit.size, 2.0)
		var c: Color = Color(0.55, 1.0, 0.6, fade)
		draw_rect(Rect2(p - Vector2(s, s / 3.0), Vector2(s * 2.0, s * 2.0 / 3.0)), c)
		draw_rect(Rect2(p - Vector2(s / 3.0, s), Vector2(s * 2.0 / 3.0, s * 2.0)), c)

func draw_ice(fade: float) -> void:
	# Ice crystals grow out of the ground, then shatter into shards.
	var grow: float = ease_out(clampf(age / 0.25, 0.0, 1.0))
	var shatter: float = clampf((age - 0.55) / 0.5, 0.0, 1.0)
	for i in range(bits.size()):
		var bit: Dictionary = bits[i]
		var x: float = float(bit.x) * radius * 1.3
		var h: float = (radius * 0.9 + float(bit.size) * 6.0) * grow
		var w: float = 6.0 + float(bit.size)
		var lean: float = float(bit.x) * 0.4
		var base: Vector2 = Vector2(x, 4)
		var tip: Vector2 = base + Vector2(sin(lean) * h, -cos(lean) * h)
		if shatter <= 0.0:
			draw_colored_polygon(PackedVector2Array([base + Vector2(-w, 0), tip, base + Vector2(w, 0)]), Color(0.75, 0.93, 1.0, 0.9))
			draw_line(base, tip, Color(1, 1, 1, 0.9), 2.0)
		else:
			for k in range(3):
				var p: Vector2 = base.lerp(tip, (k + 0.5) / 3.0) + Vector2.from_angle(float(bit.angle) + k) * shatter * 90.0
				var s: float = w * 0.7
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.6, 0), p + Vector2(0, s), p + Vector2(-s * 0.6, 0)]), Color(0.8, 0.95, 1.0, 1.0 - shatter))

func draw_bolts(fade: float) -> void:
	# Two lightning bolts strike from the sky, crossing on the target.
	var height: float = top - global_position.y
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		var from: Vector2 = Vector2(side * 60.0, height)
		var to: Vector2 = Vector2(-side * 10.0, 0)
		var flicker: float = 1.0 if int(age * 30.0) % 3 != 0 else 0.5
		bolt(from, to, i * 5.0, Color(0.5, 0.8, 1.0, fade * flicker), 10.0)
		bolt(from, to, i * 5.0, Color(1, 1, 1, fade * flicker), 4.0)
	draw_circle(Vector2.ZERO, radius * 0.9 * fade + 8.0, Color(0.7, 0.9, 1.0, 0.45 * fade))

func draw_bubbles(fade: float) -> void:
	# Bubbles rise and pop into little rings.
	for bit: Dictionary in bits:
		var life: float = 0.4 + float(bit.delay) * 3.0
		var p: Vector2 = pixel(bit.pos * 0.5 + Vector2(sin(age * 5.0 + float(bit.x) * 7.0) * 6.0, -age * 70.0))
		var r: float = float(bit.size) * 0.8
		if age < life:
			draw_arc(p, r, 0, TAU, 14, Color(0.85, 0.95, 1.0, 0.9), 2.0)
			draw_rect(Rect2(p + Vector2(-r * 0.5, -r * 0.5), Vector2(2, 2)), Color.WHITE)
		elif age < life + 0.18:
			var pop: float = (age - life) / 0.18
			draw_arc(p, r * (1.0 + pop * 1.4), 0, TAU, 14, Color(1, 1, 1, 1.0 - pop), 1.0)

func draw_horns(fade: float) -> void:
	# Two pink-flame horns sweep out of the blast and the ground cracks.
	var sweep: float = ease_out(clampf(age / 0.35, 0.0, 1.0))
	for side: float in [-1.0, 1.0]:
		# A quarter circle that runs out sideways first and then curls up, like a horn.
		var points: PackedVector2Array = PackedVector2Array()
		var reach: float = radius * 1.3
		for k in range(12):
			var theta: float = PI * 0.5 * sweep * k / 11.0
			points.append(Vector2(side * (radius * 0.3 + reach * sin(theta)), -reach * (1.0 - cos(theta)) - 6.0))
		draw_polyline(points, Color(colors[2].r, colors[2].g, colors[2].b, fade), 12.0 * fade + 2.0)
		draw_polyline(points, Color(1, 0.85, 0.97, fade), 4.0)
	for bit: Dictionary in bits:
		var dir: Vector2 = Vector2(float(bit.x), 0).normalized() if absf(float(bit.x)) > 0.1 else Vector2.RIGHT
		var length: float = radius * (0.8 + absf(float(bit.x))) * ease_out(age / 0.3)
		var mid: Vector2 = dir * length * 0.5 + Vector2(0, 3)
		draw_polyline(PackedVector2Array([Vector2(0, 2), mid, dir * length + Vector2(0, 1)]), Color(0.3, 0.05, 0.2, fade), 3.0)

func draw_hearts(fade: float) -> void:
	# Hearts burst out and float up.
	for bit: Dictionary in bits:
		var tone: Color = bit.tone
		heart(pixel(bit.pos), float(bit.size) * 0.9, Color(tone.r, tone.g, tone.b, fade))

func draw_shards(fade: float) -> void:
	# Jade crescent slashes cross the blast.
	for i in range(bits.size()):
		var bit: Dictionary = bits[i]
		var w: float = clampf((age - i * 0.05) / 0.3, 0.0, 1.0)
		if w <= 0.0:
			continue
		var a: float = float(bit.angle) + PI * 0.5
		var r: float = radius * (1.0 + i * 0.12)
		var tone: Color = colors[2]
		draw_arc(Vector2.ZERO, r, a - 0.9 * w, a + 0.9 * w, 18, Color(tone.r, tone.g, tone.b, fade), 6.0 * (1.0 - w * 0.5))
		draw_arc(Vector2.ZERO, r, a - 0.7 * w, a + 0.7 * w, 18, Color(1, 1, 1, fade), 2.0)

func draw_sun(fade: float) -> void:
	for bit: Dictionary in bits:
		var a: float = float(bit.angle) * 2.0 + age
		var tip: Vector2 = Vector2.from_angle(a) * radius * (1.2 + ease_out(age / 0.3))
		var side: Vector2 = Vector2.from_angle(a + PI / 2) * 7.0
		draw_colored_polygon(PackedVector2Array([side, -side, tip]), Color(1, 0.85, 0.3, 0.5 * fade))
