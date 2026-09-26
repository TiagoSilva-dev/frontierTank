class_name AbilityFx
extends Node2D

# Monster abilities on screen (PvE, 26/09/2026). Monsters do not shoot: they wind up an
# ability and it lands. Two modes:
#   "cast"  the wind-up: the caster glows in the ability's colour and every target gets a
#           closing danger ring with a crosshair, so the players see what is coming.
#   "hit"   the ability landing on one target, drawn by its `fx`: sting, spear, beam,
#           ember_rain, sun/rock/ice meteor, fire_pillar, quake, claw, frost_breath,
#           ice_spikes, feathers, gust, chain_lightning/chain_fire, drain, avalanche,
#           blizzard, storm, mask_storm (anything else: a generic burst).
# A PixelLab clip in assets/effects/abilities/<fx>/frame_00.png... plays on top when it
# exists (the procedural drawing stays underneath as the glow).

const ART_DIR: String = "res://assets/effects/abilities/"

var mode: String = "hit"
var fx: String = "strike"
var color: Color = Color("ffd04a")
var targets: Array = []
var from: Vector2 = Vector2.ZERO
var time: float = 0.9
var age: float = 0.0
var life: float = 1.0
var seed_value: int = 0
var bits: Array[Dictionary] = []

static func art_frames(id: String) -> Array[Texture2D]:
	var list: Array[Texture2D] = []
	for i in range(32):
		var path: String = ART_DIR + "%s/frame_%02d.png" % [id, i]
		if not ResourceLoader.exists(path):
			break
		list.append(load(path))
	return list

func _ready() -> void:
	z_index = 20
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else hash(fx + str(position))
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if mode == "cast":
		life = time + 0.1
		material = additive
		return
	life = 1.0 if not fx in ["ember_rain", "blizzard", "storm", "mask_storm", "avalanche"] else 1.3
	for i in range(28):
		bits.append({"x": rng.randf_range(-1.0, 1.0), "y": rng.randf_range(-1.0, 1.0), "delay": rng.randf_range(0.0, 0.5), "speed": rng.randf_range(0.7, 1.3), "size": rng.randf_range(2.0, 5.0), "spin": rng.randf_range(-3.0, 3.0)})
	if fx in ["beam", "sting", "chain_lightning", "chain_fire", "drain", "drain_self", "gust", "frost_breath", "spear", "spear_fire"]:
		material = additive
	var frames: Array[Texture2D] = art_frames(fx)
	if not frames.is_empty():
		var clip: PixelAnimation = PixelAnimation.new()
		clip.frames = frames
		clip.texture = frames[0]
		clip.fps = 14.0
		clip.loop = false
		clip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		clip.position = Vector2(0, -frames[0].get_height() * 0.35)
		add_child(clip)
	var colors: Array = [Color.WHITE, color, color.darkened(0.3)]
	FxParticles.burst(self, Vector2.ZERO, {"amount": 22, "lifetime": 0.6, "speed": [80.0, 220.0], "direction": Vector2.UP, "spread": 160.0, "gravity": Vector2(0, 260), "size": [2.0, 4.0], "colors": colors, "damping": 60.0})

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if mode == "cast":
		draw_cast()
		return
	var t: float = clampf(age / life, 0.0, 1.0)
	var fade: float = 1.0 - PowImpact.ease_out(maxf(0.0, (t - 0.55) / 0.45))
	match fx:
		"sting", "feathers":
			draw_projectile_streak(t, fade, fx == "feathers")
		"spear", "spear_fire":
			draw_falling_lance(t, fade)
		"beam":
			draw_beam(t, fade)
		"sun_meteor", "rock_meteor", "ice_meteor":
			draw_meteor(t, fade)
		"fire_pillar":
			draw_pillar(t, fade)
		"quake", "avalanche":
			draw_quake(t, fade)
		"claw":
			draw_claws(t, fade)
		"frost_breath", "gust":
			draw_gust(t, fade)
		"ice_spikes":
			draw_spikes(t, fade)
		"chain_lightning", "chain_fire":
			draw_chain(t, fade)
		"drain":
			draw_drain(t, fade)
		"drain_self":
			draw_glow(t, fade)
		"ember_rain", "blizzard", "storm", "mask_storm":
			draw_rain(t, fade)
		_:
			draw_burst(t, fade)

# ---------- the wind-up ----------

func draw_cast() -> void:
	var t: float = clampf(age / maxf(0.1, time), 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(age * 18.0)
	# The caster glows: rays turning around it.
	for i in range(10):
		var a: float = TAU * i / 10.0 + age * 2.5
		var r: float = 40.0 + 30.0 * t
		var side: Vector2 = Vector2.from_angle(a + PI / 2.0) * 5.0
		draw_colored_polygon(PackedVector2Array([side, -side, Vector2.from_angle(a) * r]), Color(color.r, color.g, color.b, 0.35 * t))
	draw_circle(Vector2.ZERO, 14.0 + 10.0 * t + pulse * 4.0, Color(color.r, color.g, color.b, 0.25 + 0.2 * t))
	# Every target: a danger ring closing in and a crosshair.
	for point: Variant in targets:
		var p: Vector2 = (point as Vector2) - global_position
		var radius: float = lerpf(90.0, 30.0, PowImpact.ease_out(t))
		var danger: Color = Color(1.0, 0.25, 0.2, 0.55 + 0.35 * pulse)
		draw_arc(p, radius, 0, TAU, 40, danger, 4.0)
		draw_arc(p, radius * 0.6, age * 3.0, age * 3.0 + PI * 1.3, 20, Color(color.r, color.g, color.b, 0.8), 3.0)
		for k in range(4):
			var dir: Vector2 = Vector2.from_angle(k * PI / 2.0)
			draw_line(p + dir * (radius + 6.0), p + dir * (radius - 14.0), danger, 4.0)
		draw_circle(p, 4.0 + pulse * 2.0, Color(1, 0.9, 0.8, 0.9))

# ---------- the hits ----------

func draw_projectile_streak(t: float, fade: float, feathers: bool) -> void:
	var start: Vector2 = from - global_position
	var travel: float = clampf(t / 0.18, 0.0, 1.0)
	var head: Vector2 = start.lerp(Vector2.ZERO, PowImpact.ease_out(travel))
	if travel < 1.0:
		var count: int = 5 if feathers else 1
		for i in range(count):
			var offset: Vector2 = (start - Vector2.ZERO).orthogonal().normalized() * (i - (count - 1) / 2.0) * 10.0
			draw_line(head + offset - (head - start).normalized() * 60.0, head + offset, Color(color.r, color.g, color.b, 0.9), 5.0 if not feathers else 3.0)
			draw_circle(head + offset, 5.0, Color(1, 1, 1, 0.95))
	else:
		draw_burst(t, fade)

func draw_falling_lance(t: float, fade: float) -> void:
	var fall: float = clampf(t / 0.2, 0.0, 1.0)
	var tip: Vector2 = Vector2(0, lerpf(-520.0, 0.0, PowImpact.ease_out(fall)))
	var hot: Color = Color("ff6a1f") if fx == "spear_fire" else color
	draw_rect(Rect2(tip.x - 5, tip.y - 150, 10, 150), Color(hot.r, hot.g, hot.b, 0.8 * fade))
	draw_rect(Rect2(tip.x - 2, tip.y - 150, 4, 150), Color(1, 1, 0.95, fade))
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-12, -18), tip + Vector2(12, -18), tip + Vector2(0, 8)]), Color(1, 1, 0.9, fade))
	if fall >= 1.0:
		draw_shockwave(t, fade, hot)

func draw_beam(t: float, fade: float) -> void:
	var grow: float = PowImpact.ease_out(clampf(t / 0.15, 0.0, 1.0))
	var w: float = (26.0 + 8.0 * sin(age * 30.0)) * grow * fade
	var core: Color = color.lerp(Color.WHITE, 0.55)
	draw_rect(Rect2(-w * 1.5, -900, w * 3.0, 900), Color(color.r, color.g, color.b, 0.18 * fade))
	draw_rect(Rect2(-w, -900, w * 2.0, 900), Color(color.r, color.g, color.b, 0.4 * fade))
	draw_rect(Rect2(-w * 0.35, -900, w * 0.7, 900), Color(core.r, core.g, core.b, 0.9 * fade))
	draw_circle(Vector2.ZERO, w * 1.6, Color(color.r, color.g, color.b, 0.5 * fade))
	for bit: Dictionary in bits:
		var y: float = -fposmod(age * 400.0 * bit.speed + bit.delay * 300.0, 300.0)
		draw_rect(Rect2(Vector2(bit.x * w * 1.4, y).snapped(Vector2(2, 2)), Vector2(3, 3)), Color(1, 1, 0.8, 0.8 * fade))

func draw_meteor(t: float, fade: float) -> void:
	var fall: float = clampf(t / 0.28, 0.0, 1.0)
	var start: Vector2 = Vector2(-240, -560)
	var ball: Vector2 = start.lerp(Vector2.ZERO, fall * fall)
	var core: Color = {"sun_meteor": Color("fff2a0"), "rock_meteor": Color("8a5a3a"), "ice_meteor": Color("e8fbff")}.get(fx, color)
	if fall < 1.0:
		for i in range(8):
			var k: float = i / 8.0
			var p: Vector2 = ball.lerp(start, k * 0.35)
			draw_circle(p, (26.0 - i * 2.5), Color(color.r, color.g, color.b, 0.5 * (1.0 - k)))
		draw_circle(ball, 24.0, Color(color.r, color.g, color.b, 0.95))
		draw_circle(ball, 15.0, core)
	else:
		draw_shockwave(t, fade, color)
		draw_burst(t, fade)

func draw_pillar(t: float, fade: float) -> void:
	var rise: float = PowImpact.ease_out(clampf(t / 0.25, 0.0, 1.0))
	var h: float = 220.0 * rise
	for i in range(6):
		var k: float = 1.0 - i * 0.15
		var wobble: float = sin(age * 25.0 + i) * 4.0
		draw_rect(Rect2(-22.0 * k + wobble, 10.0 - h * k, 44.0 * k, h * k), Color(1.0, 0.35 + 0.1 * i, 0.1, 0.35 * fade))
	draw_rect(Rect2(-8, 10.0 - h, 16, h), Color(1, 0.95, 0.6, 0.8 * fade))
	for bit: Dictionary in bits:
		var y: float = 10.0 - fposmod(age * 300.0 * bit.speed, h + 1.0)
		draw_rect(Rect2(Vector2(bit.x * 26.0, y).snapped(Vector2(2, 2)), Vector2(bit.size, bit.size)), Color(1.0, 0.7, 0.2, 0.8 * fade))

func draw_quake(t: float, fade: float) -> void:
	var cracks: int = 6
	for i in range(cracks):
		var dir: float = -1.0 if i % 2 == 0 else 1.0
		var p: Vector2 = Vector2(0, 16)
		var length: float = 60.0 + 30.0 * (i / 2)
		var grow: float = PowImpact.ease_out(clampf(t / 0.25, 0.0, 1.0))
		for step in range(5):
			var next: Vector2 = p + Vector2(dir * length / 5.0 * grow, sin(step * 1.7 + i) * 6.0)
			draw_line(p, next, Color(0.15, 0.08, 0.04, fade), 3.0)
			draw_line(p + Vector2(0, -1), next + Vector2(0, -1), Color(color.r, color.g, color.b, 0.6 * fade), 1.0)
			p = next
	for bit: Dictionary in bits:
		var lift: float = maxf(0.0, t - bit.delay * 0.4)
		var p: Vector2 = Vector2(bit.x * 70.0, 14.0 - sin(lift * PI * 1.6) * 90.0 * bit.speed)
		var c: Color = Color("e8f8ff") if fx == "avalanche" else Color(0.55, 0.38, 0.24)
		draw_rect(Rect2(p.snapped(Vector2(2, 2)), Vector2(bit.size + 2, bit.size + 2)), Color(c.r, c.g, c.b, fade))
	draw_circle(Vector2(0, 14), 50.0 * PowImpact.ease_out(t), Color(color.r, color.g, color.b, 0.18 * fade))

func draw_claws(t: float, fade: float) -> void:
	for i in range(3):
		var delay: float = i * 0.06
		var k: float = clampf((t - delay) / 0.15, 0.0, 1.0)
		if k <= 0.0:
			continue
		var start: Vector2 = Vector2(-40 + i * 16, -44)
		var end: Vector2 = Vector2(20 + i * 16, 36)
		draw_line(start, start.lerp(end, PowImpact.ease_out(k)), Color(1, 1, 1, fade), 5.0)
		draw_line(start + Vector2(3, 0), start.lerp(end, PowImpact.ease_out(k)) + Vector2(3, 0), Color(color.r, color.g, color.b, 0.9 * fade), 3.0)
	draw_burst(t, fade * 0.7)

func draw_gust(t: float, fade: float) -> void:
	var start: Vector2 = from - global_position
	for i in range(4):
		var k: float = clampf((t - i * 0.05) / 0.22, 0.0, 1.0)
		if k <= 0.0:
			continue
		var p: Vector2 = start.lerp(Vector2.ZERO, PowImpact.ease_out(k)) + Vector2(0, (i - 1.5) * 14.0)
		var facing: float = (Vector2.ZERO - start).angle()
		if fx == "frost_breath":
			draw_circle(p, 18.0 * (1.0 - k * 0.3), Color(color.r, color.g, color.b, 0.45 * fade))
		else:
			draw_arc(p, 22.0, facing - 1.1, facing + 1.1, 12, Color(1, 1, 1, 0.9 * fade), 4.0)
			draw_arc(p, 16.0, facing - 1.0, facing + 1.0, 10, Color(color.r, color.g, color.b, 0.9 * fade), 3.0)
	if t > 0.2:
		draw_burst(t, fade)

func draw_spikes(t: float, fade: float) -> void:
	for i in range(7):
		var k: float = PowImpact.ease_out(clampf((t - absf(i - 3) * 0.04) / 0.18, 0.0, 1.0))
		var x: float = (i - 3) * 16.0
		var h: float = (70.0 - absf(i - 3) * 14.0) * k
		draw_colored_polygon(PackedVector2Array([Vector2(x - 9, 18), Vector2(x + 9, 18), Vector2(x, 18 - h)]), Color(color.r, color.g, color.b, 0.9 * fade))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 3, 18), Vector2(x + 2, 18), Vector2(x, 18 - h * 0.9)]), Color(1, 1, 1, 0.8 * fade))

func draw_chain(t: float, fade: float) -> void:
	var start: Vector2 = from - global_position
	var flicker: int = int(age * 30.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = flicker + seed_value
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(11):
		var k: float = i / 10.0
		var jitter: Vector2 = Vector2.ZERO if i == 0 or i == 10 else Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18))
		points.append(start.lerp(Vector2.ZERO, k) + jitter)
	var alpha: float = fade * (0.6 + 0.4 * (flicker % 2))
	draw_polyline(points, Color(color.r, color.g, color.b, alpha), 7.0)
	draw_polyline(points, Color(1, 1, 1, alpha), 2.5)
	draw_circle(Vector2.ZERO, 22.0 * fade, Color(color.r, color.g, color.b, 0.5 * fade))

func draw_drain(t: float, fade: float) -> void:
	var to: Vector2 = from - global_position
	for bit: Dictionary in bits:
		var k: float = fposmod(t * 1.8 * bit.speed + bit.delay, 1.0)
		var curve: Vector2 = Vector2.ZERO.lerp(to, k) + Vector2(0, -sin(k * PI) * 60.0 * bit.y)
		draw_rect(Rect2(curve.snapped(Vector2(2, 2)), Vector2(bit.size, bit.size)), Color(color.r, color.g, color.b, 0.9 * fade))
	draw_circle(Vector2.ZERO, 26.0 * fade, Color(0.5, 0.1, 0.4, 0.35 * fade))

func draw_glow(t: float, fade: float) -> void:
	draw_circle(Vector2.ZERO, 40.0 + 30.0 * t, Color(color.r, color.g, color.b, 0.35 * fade))

func draw_rain(t: float, fade: float) -> void:
	var tint: Color = {"blizzard": Color("f4fdff"), "mask_storm": Color("ff7ae0"), "storm": Color("c8f4ff")}.get(fx, color)
	for bit: Dictionary in bits:
		var k: float = clampf((t - bit.delay) / 0.3, 0.0, 1.0)
		if k <= 0.0:
			continue
		var land: Vector2 = Vector2(bit.x * 60.0, 10.0 + bit.y * 8.0)
		var p: Vector2 = land + Vector2(-80.0, -360.0) * (1.0 - k)
		if k < 1.0:
			draw_line(p, p + Vector2(10, 40), Color(tint.r, tint.g, tint.b, 0.5 * fade), 2.0)
			draw_rect(Rect2(p.snapped(Vector2(2, 2)), Vector2(bit.size + 2, bit.size + 2)), Color(tint.r, tint.g, tint.b, fade))
		else:
			draw_circle(land, (bit.size + 4.0) * (1.0 - (t - bit.delay - 0.3)), Color(tint.r, tint.g, tint.b, 0.5 * fade))
	if fx == "storm" and int(age * 12.0) % 3 == 0:
		draw_line(Vector2(-20, -400), Vector2(10, 0), Color(1, 1, 1, 0.8 * fade), 3.0)

func draw_burst(t: float, fade: float) -> void:
	var k: float = PowImpact.ease_out(clampf(t / 0.3, 0.0, 1.0))
	for i in range(12):
		var a: float = TAU * i / 12.0 + 0.2
		var r: float = (50.0 if i % 2 == 0 else 32.0) * (0.5 + k)
		var side: Vector2 = Vector2.from_angle(a + PI / 2.0) * 6.0
		draw_colored_polygon(PackedVector2Array([side, -side, Vector2.from_angle(a) * r]), Color(color.r, color.g, color.b, 0.7 * fade))
	draw_circle(Vector2.ZERO, 18.0 * (1.0 - k * 0.5), Color(1, 1, 0.95, 0.9 * fade))

func draw_shockwave(t: float, fade: float, tint: Color) -> void:
	var w: float = clampf((t - 0.2) / 0.6, 0.0, 1.0)
	draw_set_transform(Vector2(0, 10), 0, Vector2(1.0, 0.35))
	draw_arc(Vector2.ZERO, 20.0 + 120.0 * PowImpact.ease_out(w), 0, TAU, 40, Color(tint.r, tint.g, tint.b, fade * (1.0 - w)), 8.0 * (1.0 - w) + 2.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
