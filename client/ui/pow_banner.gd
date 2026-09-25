class_name PowBanner
extends Control

# Screen-space part of the POW shot: speed lines rush to the centre, a comic starburst
# with a tilted "POW!" slams in with the special's name on a ribbon, shakes, then blows
# away. Freed by itself after LIFE seconds.

const LIFE: float = 1.45
const CENTER: Vector2 = Vector2(640, 250)

var title: String = ""
var tint: Color = Color("ffd04a")
var age: float = 0.0
var lines: Array[Dictionary] = []
var spikes: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(46):
		lines.append({"angle": rng.randf() * TAU, "inner": rng.randf_range(230, 380), "width": rng.randf_range(3, 9), "speed": rng.randf_range(0.8, 1.3)})
	for i in range(22):
		spikes.append((1.0 if i % 2 == 0 else 0.62) * rng.randf_range(0.9, 1.1))

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Dark flash and speed lines.
	var dim: float = clampf(1.0 - age / 0.6, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.02, 0.0, 0.35 * dim))
	for line: Dictionary in lines:
		var travel: float = fposmod(age * 2.4 * line.speed, 1.0)
		var dir: Vector2 = Vector2.from_angle(line.angle)
		var outer: float = 900.0 - travel * 300.0
		var inner: float = line.inner + (1.0 - travel) * 120.0
		var side: Vector2 = dir.orthogonal() * line.width
		draw_colored_polygon(PackedVector2Array([CENTER + dir * inner, CENTER + dir * outer + side, CENTER + dir * outer - side]), Color(1, 1, 0.9, 0.55 * dim))
	# Burst scale: slam in with overshoot, settle, then blow up and fade.
	var s: float
	var alpha: float = 1.0
	if age < 0.18:
		s = lerpf(2.6, 0.9, ease_out(age / 0.18))
	elif age < 0.3:
		s = lerpf(0.9, 1.0, (age - 0.18) / 0.12)
	elif age < 1.05:
		s = 1.0 + sin((age - 0.3) * 18.0) * 0.015
	else:
		var u: float = (age - 1.05) / (LIFE - 1.05)
		s = 1.0 + u * 0.35
		alpha = 1.0 - u
	var shake: Vector2 = Vector2(sin(age * 70.0), cos(age * 63.0)) * (6.0 if age < 0.4 else 1.5)
	draw_set_transform(CENTER + shake, -0.12, Vector2.ONE * s)
	var outline: PackedVector2Array = PackedVector2Array()
	var fill: PackedVector2Array = PackedVector2Array()
	var core: PackedVector2Array = PackedVector2Array()
	for i in range(spikes.size()):
		var a: float = TAU * i / spikes.size() + 0.1
		var r: float = spikes[i]
		var dir: Vector2 = Vector2(cos(a) * 1.35, sin(a))
		outline.append(dir * 150.0 * r + dir.normalized() * 10.0)
		fill.append(dir * 150.0 * r)
		core.append(dir * 110.0 * r)
	draw_colored_polygon(outline, Color(0.23, 0.07, 0.01, alpha))
	draw_colored_polygon(fill, Color(1.0, 0.5, 0.08, alpha))
	var yellow: Color = Color("ffe25a").lerp(tint, 0.2)
	draw_colored_polygon(core, Color(yellow.r, yellow.g, yellow.b, alpha))
	var font: Font = UiKit.font(true)
	var big: int = UiKit.fs(92)
	draw_string_outline(font, Vector2(-200, 32), tr("POW!"), HORIZONTAL_ALIGNMENT_CENTER, 400, big, 22, Color(0.23, 0.07, 0.01, alpha))
	draw_string(font, Vector2(-200, 32), tr("POW!"), HORIZONTAL_ALIGNMENT_CENTER, 400, big, Color(1, 1, 1, alpha))
	draw_string(font, Vector2(-200, 38), tr("POW!"), HORIZONTAL_ALIGNMENT_CENTER, 400, big, Color(1.0, 0.85, 0.2, alpha * 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# Ribbon with the special's name.
	if title != "":
		var ribbon_alpha: float = clampf((age - 0.2) / 0.15, 0.0, 1.0) * alpha
		var rect: Rect2 = Rect2(CENTER.x - 170, CENTER.y + 118, 340, 38)
		draw_colored_polygon(PackedVector2Array([rect.position + Vector2(-26, 4), rect.position, rect.position + Vector2(0, 38), rect.position + Vector2(-26, 34), rect.position + Vector2(-12, 19)]), Color(0.45, 0.06, 0.04, ribbon_alpha))
		draw_colored_polygon(PackedVector2Array([rect.end + Vector2(26, -34), rect.end + Vector2(0, -38), rect.end, rect.end + Vector2(26, -4), rect.end + Vector2(12, -19)]), Color(0.45, 0.06, 0.04, ribbon_alpha))
		draw_rect(rect, Color(0.72, 0.1, 0.06, ribbon_alpha))
		draw_rect(rect, Color(1.0, 0.82, 0.3, ribbon_alpha), false, 3.0)
		var label: String = title.to_upper()
		draw_string_outline(font, rect.position + Vector2(0, 28), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UiKit.fs(22), 6, Color(0.2, 0.03, 0.01, ribbon_alpha))
		draw_string(font, rect.position + Vector2(0, 28), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UiKit.fs(22), Color(1.0, 0.93, 0.6, ribbon_alpha))

static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
