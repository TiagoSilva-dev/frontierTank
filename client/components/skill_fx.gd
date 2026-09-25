class_name SkillFx
extends Node2D

# DDTank-style "consuming" a skill: the item icon pops out over the fighter's head in a
# burst of light, hangs there with its name, then dives into the fighter, who flashes in
# the item's colour while a ring and sparks close in on him. Follows the fighter.

const POP: float = 0.22
const DIVE: float = 0.95
const ABSORB: float = 1.3
const LIFE: float = 1.8
const ICON: float = 36.0
const COLORS: Dictionary = {
	"multi": "ffb347", "power": "ff5a3a", "powmax": "c77bff", "heal": "7aff9a", "energy": "d8ff4a",
	"shield": "7ad8ff", "plane": "e8f4ff", "angel": "fff0a0", "pow": "ffd04a",
}

var fighter: TankFighter
var icon: Texture2D
var title: String = ""
var color: Color = Color("ffd04a")
var offset_x: float = 0.0
var age: float = 0.0
var sparks: Array[Dictionary] = []
var flashed: bool = false

static func color_for(kind: String) -> Color:
	return Color(str(COLORS.get(kind, "ffd04a")))

func _ready() -> void:
	z_index = 30
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(14):
		var angle: float = TAU * i / 14.0 + rng.randf_range(-0.2, 0.2)
		sparks.append({"angle": angle, "speed": rng.randf_range(70, 150), "size": rng.randf_range(2, 4), "spin": rng.randf_range(-3, 3)})
	follow()

func follow() -> void:
	if is_instance_valid(fighter):
		position = fighter.position

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE or not is_instance_valid(fighter):
		queue_free()
		return
	follow()
	if age >= ABSORB and not flashed:
		flashed = true
		fighter.glow(color)
	queue_redraw()

func top_point() -> Vector2:
	# High enough that the name clears the turn arrow over the head.
	return Vector2(offset_x, -fighter.body_size.y - 80.0)

func body_point() -> Vector2:
	return fighter.center() - fighter.position

func _draw() -> void:
	if not is_instance_valid(fighter):
		return
	var top: Vector2 = top_point()
	var body: Vector2 = body_point()
	if age < DIVE:
		var t: float = clampf(age / POP, 0.0, 1.0)
		var s: float = back_out(t)
		var center: Vector2 = top + Vector2(0, sin(age * 7.0) * 2.0)
		draw_rays(center, 40.0 * s, 0.35 * minf(1.0, t * 2.0))
		draw_circle(center, 28.0 * s, Color(color.r, color.g, color.b, 0.3))
		draw_circle(center, 21.0 * s, Color(1, 1, 1, 0.22))
		if age < 0.5:
			var ring: float = age / 0.5
			draw_arc(center, 18.0 + 46.0 * ring, 0, TAU, 40, Color(color.r, color.g, color.b, 1.0 - ring), 3.0 * (1.0 - ring) + 1.0)
			for spark: Dictionary in sparks:
				var p: Vector2 = center + Vector2.from_angle(spark.angle) * (14.0 + spark.speed * ring * 0.45)
				draw_spark(p, spark.size * (1.0 - ring * 0.6), Color(1, 1, 0.85, 1.0 - ring))
		draw_icon(center, s, 1.0)
		draw_title(center + Vector2(0, ICON * 0.5 * s + 16.0), clampf((age - 0.1) / 0.15, 0.0, 1.0))
	elif age < ABSORB:
		var u: float = (age - DIVE) / (ABSORB - DIVE)
		var eased: float = u * u
		for ghost in range(3, 0, -1):
			var g: float = maxf(0.0, eased - ghost * 0.08)
			draw_circle(top.lerp(body, g), 10.0 * (1.0 - g * 0.6), Color(color.r, color.g, color.b, 0.25 / ghost))
		draw_icon(top.lerp(body, eased), 1.0 - 0.75 * eased, 1.0 - 0.3 * u)
		draw_title(top + Vector2(0, ICON * 0.5 + 16.0), 1.0 - u)
	else:
		# Absorbed: a ring closes on the body and sparks rush in.
		var v: float = (age - ABSORB) / (LIFE - ABSORB)
		draw_circle(body, 34.0 * (1.0 - v), Color(color.r, color.g, color.b, 0.35 * (1.0 - v)))
		draw_arc(body, 44.0 * (1.0 - v) + 6.0, 0, TAU, 36, Color(1, 1, 1, 0.9 * (1.0 - v)), 2.0)
		for spark: Dictionary in sparks:
			var p: Vector2 = body + Vector2.from_angle(spark.angle + v * spark.spin) * 56.0 * (1.0 - v)
			draw_spark(p, spark.size, Color(color.r, color.g, color.b, 1.0 - v))
		for i in range(5):
			var rise: Vector2 = body + Vector2((i - 2) * 9.0, -v * 34.0 - (i % 2) * 8.0)
			draw_plus(rise, 3.0, Color(1, 1, 0.9, (1.0 - v) * 0.9))

func draw_icon(center: Vector2, s: float, alpha: float) -> void:
	var size: float = ICON * s
	var frame: Rect2 = Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size)).grow(3.0 * s)
	draw_rect(frame.grow(2.0), Color(0.1, 0.05, 0.02, 0.85 * alpha))
	draw_rect(frame, Color(color.r, color.g, color.b, alpha))
	draw_rect(frame.grow(-2.0 * s), Color(0.16, 0.1, 0.06, alpha))
	if icon != null:
		draw_texture_rect(icon, Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size)), false, Color(1, 1, 1, alpha))

func draw_title(at: Vector2, alpha: float) -> void:
	if title == "" or alpha <= 0.0:
		return
	var font: Font = UiKit.font(true)
	var size: int = UiKit.fs(14)
	draw_string_outline(font, at + Vector2(-90, 0), title, HORIZONTAL_ALIGNMENT_CENTER, 180, size, 5, Color(0.08, 0.04, 0.02, alpha))
	draw_string(font, at + Vector2(-90, 0), title, HORIZONTAL_ALIGNMENT_CENTER, 180, size, Color(color.lightened(0.45), alpha))

func draw_rays(center: Vector2, radius: float, alpha: float) -> void:
	for i in range(12):
		var a: float = TAU * i / 12.0 + age * 1.8
		var tip: Vector2 = center + Vector2.from_angle(a) * radius * (1.6 if i % 2 == 0 else 1.2)
		var side: Vector2 = Vector2.from_angle(a + PI / 2) * radius * 0.13
		draw_colored_polygon(PackedVector2Array([center + side, center - side, tip]), Color(color.r, color.g, color.b, alpha))

func draw_spark(p: Vector2, s: float, c: Color) -> void:
	draw_rect(Rect2(p - Vector2(s, s * 0.35), Vector2(s * 2, s * 0.7)), c)
	draw_rect(Rect2(p - Vector2(s * 0.35, s), Vector2(s * 0.7, s * 2)), c)

func draw_plus(p: Vector2, s: float, c: Color) -> void:
	draw_rect(Rect2(p - Vector2(s, 1), Vector2(s * 2, 2)), c)
	draw_rect(Rect2(p - Vector2(1, s), Vector2(2, s * 2)), c)

static func back_out(t: float) -> float:
	var c: float = 2.2
	var u: float = t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u
