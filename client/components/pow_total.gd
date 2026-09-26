class_name PowTotal
extends Node2D

# The POW's closing number (26/09/2026): everything the special dealt, summed, slams in
# over the impact on a comic starburst, counts up, shakes and floats away. Drawn in the
# battlefield (world space) above every effect.

const LIFE: float = 1.9

var total: int = 0
var tint: Color = Color("ffd04a")
var critical: bool = false
var age: float = 0.0
var spikes: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	z_index = 60
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = total
	for i in range(20):
		spikes.append((1.0 if i % 2 == 0 else 0.58) * rng.randf_range(0.88, 1.12))
	FxParticles.burst(self, Vector2.ZERO, {"amount": 40, "lifetime": 0.9, "speed": [180.0, 460.0], "spread": 180.0, "gravity": Vector2(0, 420), "size": [3.0, 6.0], "colors": [Color.WHITE, Color("ffe36a"), tint, Color("ff6a1f")], "damping": 80.0, "z": 61})

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var slam: float = clampf(age / 0.16, 0.0, 1.0)
	var s: float = lerpf(2.6, 1.0, PowImpact.ease_out(slam))
	var alpha: float = 1.0
	var lift: float = 0.0
	if age > LIFE - 0.45:
		var u: float = (age - (LIFE - 0.45)) / 0.45
		alpha = 1.0 - u
		lift = -40.0 * u
		s *= 1.0 + 0.2 * u
	var shake: Vector2 = Vector2(sin(age * 90.0), cos(age * 77.0)) * (8.0 if age < 0.45 else 0.0)
	draw_set_transform(Vector2(0, -150 + lift) + shake, -0.06, Vector2.ONE * s)
	# Starburst: dark outline, orange body, gold core.
	var outline: PackedVector2Array = PackedVector2Array()
	var body: PackedVector2Array = PackedVector2Array()
	var core: PackedVector2Array = PackedVector2Array()
	var turn: float = age * 0.4
	for i in range(spikes.size()):
		var a: float = TAU * i / spikes.size() + turn
		var dir: Vector2 = Vector2(cos(a) * 1.6, sin(a))
		outline.append(dir * 118.0 * spikes[i] + dir.normalized() * 9.0)
		body.append(dir * 118.0 * spikes[i])
		core.append(dir * 84.0 * spikes[i])
	draw_colored_polygon(outline, Color(0.18, 0.04, 0.0, 0.92 * alpha))
	var hot: Color = Color("ff5a1a").lerp(tint, 0.25)
	draw_colored_polygon(body, Color(hot.r, hot.g, hot.b, 0.95 * alpha))
	var gold: Color = Color("ffd84a").lerp(tint, 0.15)
	draw_colored_polygon(core, Color(gold.r, gold.g, gold.b, alpha))
	# The number counts up while it slams in.
	var shown: int = roundi(total * PowImpact.ease_out(clampf(age / 0.45, 0.0, 1.0)))
	var text: String = str(shown)
	var font: Font = UiKit.font(true)
	var size: int = 76 if text.length() <= 4 else 62
	var box: float = 460.0
	draw_string_outline(font, Vector2(-box / 2.0, 26), text, HORIZONTAL_ALIGNMENT_CENTER, box, size, 18, Color(0.16, 0.03, 0.0, alpha))
	draw_string(font, Vector2(-box / 2.0, 31), text, HORIZONTAL_ALIGNMENT_CENTER, box, size, Color(0.85, 0.2, 0.02, alpha))
	draw_string(font, Vector2(-box / 2.0, 26), text, HORIZONTAL_ALIGNMENT_CENTER, box, size, Color(1.0, 0.97, 0.85, alpha))
	var label: String = tr("CRÍTICO") if critical else "POW!"
	draw_string_outline(font, Vector2(-box / 2.0, -46), label, HORIZONTAL_ALIGNMENT_CENTER, box, 26, 8, Color(0.16, 0.03, 0.0, alpha))
	draw_string(font, Vector2(-box / 2.0, -46), label, HORIZONTAL_ALIGNMENT_CENTER, box, 26, Color(1.0, 0.35, 1.0, alpha) if critical else Color(1.0, 0.9, 0.4, alpha))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
