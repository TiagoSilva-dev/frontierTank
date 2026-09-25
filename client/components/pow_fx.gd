class_name PowFx
extends Node2D

# POW visuals in the world. "aura": while POW is armed the fighter burns with rising
# golden flames, a pulsing ring on the ground and orbiting sparks (until the shot),
# blended additively over the body so the fighter seems to glow.
# "burst": the moment of the shot: white flash, a pillar of light, two shockwaves,
# rotating sun rays and sparks flying out, over the painted PixelLab POW sprite.

const FLAME: Array[Color] = [Color("fffbe0"), Color("ffe36a"), Color("ffb02e"), Color("ff6a1f"), Color("c8300f")]

var mode: String = "aura"
var fighter: TankFighter
var tint: Color = Color("ffd04a")
var sprite_path: String = ""
var age: float = 0.0
var life: float = 1.6
var flames: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	if mode == "aura":
		z_index = 1
		var additive: CanvasItemMaterial = CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
		for i in range(34):
			flames.append({"x": rng.randf_range(-1.0, 1.0), "phase": rng.randf(), "speed": rng.randf_range(0.8, 1.4), "size": rng.randf_range(4.0, 9.0)})
		return
	z_index = 25
	for i in range(28):
		var angle: float = rng.randf_range(-PI, 0.2) if i % 3 else rng.randf_range(0, TAU)
		sparks.append({"pos": Vector2.ZERO, "vel": Vector2.from_angle(angle) * rng.randf_range(160, 420), "size": rng.randf_range(2.0, 4.5)})
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(sprite_path)
		var glow: CanvasItemMaterial = CanvasItemMaterial.new()
		glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = glow
		sprite.scale = Vector2.ONE * 1.5
		add_child(sprite)
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(sprite, "scale", Vector2.ONE * 3.2, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.9)
		tween.tween_property(sprite, "rotation", 0.8, 0.9)

func _process(delta: float) -> void:
	age += delta
	if mode == "aura":
		if not is_instance_valid(fighter) or fighter.hp <= 0:
			queue_free()
			return
	elif age >= life:
		queue_free()
		return
	for spark: Dictionary in sparks:
		spark.vel = spark.vel * (1.0 - delta * 1.6) + Vector2(0, 260) * delta
		spark.pos = spark.pos + spark.vel * delta
	queue_redraw()

func _draw() -> void:
	if mode == "aura":
		draw_aura()
	else:
		draw_burst()

func draw_aura() -> void:
	var width: float = fighter.body_size.x * 0.6 + 10.0
	var body: Vector2 = fighter.center() - fighter.position
	var pulse: float = 0.5 + 0.5 * sin(age * 7.0)
	var gold: Color = Color("ffc23a")
	# Column of heat rising from the fighter.
	for i in range(7):
		var k: float = 1.0 - i * 0.13
		var h: float = 40.0 + i * 16.0
		draw_rect(Rect2(Vector2(-width * k, body.y - h), Vector2(width * 2.0 * k, h + 18.0)), Color(gold.r, gold.g * 0.8, gold.b * 0.5, 0.06 + 0.03 * pulse))
	# Ground ring, squashed into an ellipse.
	draw_set_transform(Vector2(0, 2), 0, Vector2(1.0, 0.3))
	draw_arc(Vector2.ZERO, width + 12.0 + pulse * 5.0, 0, TAU, 40, Color(tint.r, tint.g, tint.b, 0.9), 6.0)
	draw_circle(Vector2.ZERO, width + 8.0, Color(gold.r, gold.g, gold.b, 0.22 + 0.12 * pulse))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# Flame tongues licking up over the body on a 2 px grid.
	for flame: Dictionary in flames:
		var t: float = fposmod(age * flame.speed + flame.phase, 1.0)
		var x: float = flame.x * width * (1.0 - t * 0.55) + sin(age * 5.0 + flame.phase * 9.0) * 3.0
		var p: Vector2 = Vector2(x, body.y + 14.0 - t * 84.0).snapped(Vector2(2, 2))
		var s: float = snappedf(flame.size * (1.0 - t * 0.65), 2.0)
		var c: Color = FLAME[mini(FLAME.size() - 1, int(t * FLAME.size()))]
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), Color(c.r, c.g, c.b, 0.75 * (1.0 - t)))
	# Three sparks orbiting the fighter.
	for i in range(3):
		var a: float = age * 3.2 + TAU * i / 3.0
		var p: Vector2 = body + Vector2(cos(a) * (width + 8.0), sin(a) * 10.0)
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 0.85, 0.9))

func draw_burst() -> void:
	var t: float = age / life
	if age < 0.14:
		draw_circle(Vector2.ZERO, 70.0 + age * 500.0, Color(1, 1, 0.92, 0.9 * (1.0 - age / 0.14)))
	# Pillar of light shooting up.
	var pillar: float = clampf(1.0 - age / 0.7, 0.0, 1.0)
	if pillar > 0.0:
		var w: float = 34.0 * pillar + 6.0
		draw_rect(Rect2(-w, -900, w * 2.0, 900), Color(tint.r, tint.g, tint.b, 0.35 * pillar))
		draw_rect(Rect2(-w * 0.35, -900, w * 0.7, 900), Color(1, 1, 0.95, 0.6 * pillar))
	# Rotating sun rays.
	var rays: float = clampf(1.0 - t * 1.4, 0.0, 1.0)
	for i in range(16):
		var a: float = TAU * i / 16.0 + age * 1.2
		var r: float = (150.0 if i % 2 == 0 else 105.0) * (0.6 + minf(1.0, age * 6.0) * 0.6)
		var side: Vector2 = Vector2.from_angle(a + PI / 2) * 9.0
		draw_colored_polygon(PackedVector2Array([side, -side, Vector2.from_angle(a) * r]), Color(tint.r, tint.g, tint.b, 0.4 * rays))
	# Two shockwaves.
	for k in range(2):
		var w: float = (age - k * 0.12) / 0.55
		if w > 0.0 and w < 1.0:
			draw_arc(Vector2.ZERO, 24.0 + 190.0 * w, 0, TAU, 56, Color(1, 0.95, 0.7, 1.0 - w) if k == 0 else Color(tint.r, tint.g, tint.b, 1.0 - w), 7.0 * (1.0 - w) + 1.0)
	for spark: Dictionary in sparks:
		var s: float = spark.size * (1.0 - t)
		var p: Vector2 = (spark.pos as Vector2).snapped(Vector2(2, 2))
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), Color(1, 0.9 - t * 0.4, 0.5 - t * 0.4, 1.0 - t))
