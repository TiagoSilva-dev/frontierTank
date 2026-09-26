class_name PowCutIn
extends Control

# The POW activation, fighting-game style (26/09/2026): the battle freezes
# (LocalMatch.arm_pow holds the match for Armory.visual("pow_cutin") seconds), the screen
# darkens, a diagonal band slams across it with speed lines, the fighter strikes a pose
# on it and the special's name lands in big gold letters. Freed by itself after LIFE.
# A PixelLab portrait in assets/portraits/<skin>.png replaces the standing sprite.

const LIFE: float = 1.15
const PORTRAIT_DIR: String = "res://assets/portraits/"
# Band corners: top-left, top-right, bottom-right, bottom-left (it rises to the right).
const BAND: Array[Vector2] = [Vector2(-20, 262), Vector2(1300, 150), Vector2(1300, 392), Vector2(-20, 504)]
const SLOPE: float = -0.0846

var title: String = ""
var owner_name: String = ""
var tint: Color = Color("ffd04a")
var look: Dictionary = {}
var enemy: bool = false
var age: float = 0.0
var lines: Array[Dictionary] = []
var hero: Control
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func portrait_path(skin: String) -> String:
	var path: String = PORTRAIT_DIR + skin + ".png"
	return path if ResourceLoader.exists(path) else ""

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()
	for i in range(34):
		lines.append({"y": rng.randf(), "length": rng.randf_range(120, 420), "speed": rng.randf_range(1.6, 3.2), "width": rng.randf_range(2, 6), "phase": rng.randf()})
	# The fighter: PixelLab portrait when there is one, else the equipped standing look.
	var holder: Control = Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(340, 420)
	holder.pivot_offset = Vector2(170, 420)
	add_child(holder)
	hero = holder
	var art: String = portrait_path(str(look.get("skin", "")))
	if art != "":
		var picture: TextureRect = TextureRect.new()
		picture.texture = load(art)
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size = holder.size
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(picture)
	elif not look.is_empty():
		AvatarView.create(holder, look, Rect2(Vector2.ZERO, holder.size))
	if enemy:
		holder.scale.x = -1.0
	place_hero()

func place_hero() -> void:
	# Slides in from its side, then drifts slowly while the name is on screen (a rival
	# comes from the right, mirrored around the holder's centre).
	var enter: float = PowImpact.ease_out(age / 0.2)
	var leave: float = clampf((age - (LIFE - 0.16)) / 0.16, 0.0, 1.0)
	var side: float = -1.0 if enemy else 1.0
	var home: float = 80.0 if not enemy else 1280.0 - 80.0 - 340.0
	var from: float = -420.0 if not enemy else 1360.0
	var x: float = lerpf(from, home, enter) + 18.0 * side * age
	x = lerpf(x, from, leave * leave)
	hero.position = Vector2(x, 50.0)
	hero.modulate.a = 1.0 - leave

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	place_hero()
	queue_redraw()

func band_point(i: int, open: float) -> Vector2:
	# The band opens from its centre line and closes back into it.
	var middle: Vector2 = BAND[0].lerp(BAND[3], 0.5) if i in [0, 3] else BAND[1].lerp(BAND[2], 0.5)
	return middle.lerp(BAND[i], open)

func _draw() -> void:
	var fade_in: float = clampf(age / 0.08, 0.0, 1.0)
	var fade_out: float = clampf((LIFE - age) / 0.18, 0.0, 1.0)
	var alpha: float = fade_in * fade_out
	# Everything else goes dark, with a white flash on the first frames.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.0, 0.04, 0.62 * alpha))
	if age < 0.09:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55 * (1.0 - age / 0.09)))
	var open: float = PowImpact.ease_out(age / 0.12) * (1.0 - PowImpact.ease_out(clampf((age - (LIFE - 0.14)) / 0.14, 0.0, 1.0)))
	var poly: PackedVector2Array = PackedVector2Array([band_point(0, open), band_point(1, open), band_point(2, open), band_point(3, open)])
	var vivid: float = clampf(tint.s * 1.4 + 0.25, 0.0, 1.0)
	var deep: Color = Color.from_hsv(tint.h, vivid, 0.3)
	var mid: Color = Color.from_hsv(tint.h, vivid, 0.72)
	draw_colored_polygon(poly, Color(deep.r, deep.g, deep.b, 0.96 * alpha))
	# Inner glow stripe along the band.
	var inner: PackedVector2Array = PackedVector2Array()
	for i in range(4):
		var c: Vector2 = poly[0].lerp(poly[3], 0.5) if i in [0, 3] else poly[1].lerp(poly[2], 0.5)
		inner.append(c.lerp(poly[i], 0.55))
	draw_colored_polygon(inner, Color(mid.r, mid.g, mid.b, 0.55 * alpha))
	draw_line(poly[0].lerp(poly[3], 0.5), poly[1].lerp(poly[2], 0.5), Color(1, 1, 1, 0.22 * alpha), 3.0)
	# Speed lines racing along the band (from right to left, the way the shot flies back).
	var dir: Vector2 = Vector2(1, 0).rotated(SLOPE)
	for line: Dictionary in lines:
		var along: float = fposmod(line.phase - age * line.speed, 1.0) * 1700.0 - 200.0
		var top: Vector2 = poly[0].lerp(poly[1], along / 1300.0)
		var bottom: Vector2 = poly[3].lerp(poly[2], along / 1300.0)
		var p: Vector2 = top.lerp(bottom, line.y)
		var c: Color = Color(1, 1, 1, 0.22 * alpha) if int(line.phase * 10) % 3 else Color(tint.r, tint.g, tint.b, 0.4 * alpha)
		draw_line(p, p + dir * line.length, c, line.width)
	# Gold trims on both edges.
	var gold: Color = Color("ffd04a").lerp(tint, 0.25)
	draw_line(poly[0], poly[1], Color(gold.r, gold.g, gold.b, alpha), 8.0)
	draw_line(poly[3], poly[2], Color(gold.r, gold.g, gold.b, alpha), 8.0)
	draw_line(poly[0] + Vector2(0, 9), poly[1] + Vector2(0, 9), Color(1, 1, 1, 0.5 * alpha), 2.0)
	draw_line(poly[3] - Vector2(0, 9), poly[2] - Vector2(0, 9), Color(1, 1, 1, 0.5 * alpha), 2.0)
	# A light sweep across the band.
	var sweep: float = (age - 0.32) / 0.3
	if sweep > 0.0 and sweep < 1.0:
		var x: float = lerpf(-200.0, 1480.0, sweep)
		var a: Vector2 = poly[0].lerp(poly[1], x / 1320.0)
		var b: Vector2 = poly[3].lerp(poly[2], (x - 90.0) / 1320.0)
		draw_colored_polygon(PackedVector2Array([a, a + Vector2(46, -4), b + Vector2(46, -4), b]), Color(1, 1, 1, 0.3 * alpha))
	# The fighter's glow behind the pose.
	var glow_at: Vector2 = hero.position + Vector2(170.0, 230.0)
	for i in range(18):
		var a: float = TAU * i / 18.0 + age * 0.9
		var side: Vector2 = Vector2.from_angle(a + PI / 2.0) * (14.0 if i % 2 == 0 else 7.0)
		var reach: float = 330.0 if i % 2 == 0 else 250.0
		var ray: Color = Color(1, 1, 0.9, 0.16 * alpha) if i % 2 == 0 else Color(mid.r, mid.g, mid.b, 0.3 * alpha)
		draw_colored_polygon(PackedVector2Array([glow_at + side, glow_at - side, glow_at + Vector2.from_angle(a) * reach]), ray)
	for k in range(4):
		draw_circle(glow_at, 170.0 - k * 36.0, Color(mid.r, mid.g, mid.b, 0.09 * alpha))
	draw_title(alpha)

func draw_title(alpha: float) -> void:
	var font: Font = UiKit.font(true)
	var slam: float = clampf((age - 0.1) / 0.14, 0.0, 1.0)
	if slam <= 0.0:
		return
	var s: float = lerpf(2.4, 1.0, PowImpact.ease_out(slam))
	var shake: Vector2 = Vector2(sin(age * 80.0), cos(age * 71.0)) * (7.0 if slam < 1.0 or age < 0.34 else 0.0)
	var centre: Vector2 = Vector2(820, 300) if not enemy else Vector2(470, 330)
	draw_set_transform(centre + shake, SLOPE, Vector2.ONE * s)
	var width: float = 900.0
	var big: int = UiKit.fs(96 if title.length() <= 10 else (78 if title.length() <= 14 else 60))
	var name_text: String = title.to_upper()
	var small: String = ("POW · " + owner_name).to_upper() if owner_name != "" else "POW"
	# Small line over the name.
	draw_string_outline(font, Vector2(-width / 2.0, -62), small, HORIZONTAL_ALIGNMENT_CENTER, width, UiKit.fs(26), 8, Color(0.08, 0.02, 0.0, alpha))
	draw_string(font, Vector2(-width / 2.0, -62), small, HORIZONTAL_ALIGNMENT_CENTER, width, UiKit.fs(26), Color(1.0, 0.95, 0.8, alpha))
	# The name: coloured halo, thick dark outline, orange bevel under a gold face.
	draw_string_outline(font, Vector2(-width / 2.0, 30), name_text, HORIZONTAL_ALIGNMENT_CENTER, width, big, 30, Color(tint.r, tint.g, tint.b, 0.35 * alpha))
	draw_string_outline(font, Vector2(-width / 2.0, 30), name_text, HORIZONTAL_ALIGNMENT_CENTER, width, big, 16, Color(0.16, 0.04, 0.0, alpha))
	draw_string(font, Vector2(-width / 2.0, 35), name_text, HORIZONTAL_ALIGNMENT_CENTER, width, big, Color(0.95, 0.42, 0.06, alpha))
	draw_string(font, Vector2(-width / 2.0, 30), name_text, HORIZONTAL_ALIGNMENT_CENTER, width, big, Color(1.0, 0.86, 0.3, alpha))
	draw_string(font, Vector2(-width / 2.0, 27), name_text, HORIZONTAL_ALIGNMENT_CENTER, width, big, Color(1.0, 0.98, 0.8, alpha * 0.45))
	# White flash on the letters as they land.
	if slam < 1.0 or age < 0.3:
		var flash: float = 1.0 - clampf((age - 0.24) / 0.1, 0.0, 1.0)
		draw_string(font, Vector2(-width / 2.0, 30), name_text, HORIZONTAL_ALIGNMENT_CENTER, width, big, Color(1, 1, 1, 0.8 * flash * alpha))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
