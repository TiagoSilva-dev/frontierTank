class_name PowFx
extends Node2D

# POW visuals around the fighter, in phases:
# "aura" (preparation and charge): from the moment POW is armed the fighter burns with
# rising flames and a ring on the ground; while the force bar charges (`charge` 0..1) the
# aura grows and particles are pulled into the weapon on the back.
# "burst" (the shot): white flash, a pillar of light, shockwaves, sun rays and sparks.
# The flight (the special's own projectile art, halo and trail) lives in TankProjectile
# and the landing, with the weapon's animated PixelLab POW art, in PowImpact (0.14; it
# used to play here, behind the "POW!" banner).

const FLAME: Array[Color] = [Color("fffbe0"), Color("ffe36a"), Color("ffb02e"), Color("ff6a1f"), Color("c8300f")]
const ART_DIR: String = "res://assets/effects/pow/"
const FALLBACK_ART: String = "res://assets/expansion/effects/celestial_pow.png"

var mode: String = "aura"
var fighter: TankFighter
var weapon_id: String = ""
var tint: Color = Color("ffd04a")
var charge: float = 0.0
var age: float = 0.0
var life: float = 1.6
var flames: Array[Dictionary] = []
var embers: CPUParticles2D
var pull: CPUParticles2D
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func projectile_art(id: String) -> String:
	var path: String = ART_DIR + "%s/projectile.png" % id
	return path if ResourceLoader.exists(path) else ""

static func art_frames(id: String) -> Array[Texture2D]:
	var list: Array[Texture2D] = []
	for i in range(24):
		var path: String = ART_DIR + "%s/frame_%02d.png" % [id, i]
		if not ResourceLoader.exists(path):
			break
		var frame: Texture2D = load(path)
		# Some generated clips have near-empty frames in the middle: skip them.
		var used: Vector2i = frame.get_image().get_used_rect().size
		if used.x * used.y >= frame.get_width() * frame.get_height() * 0.06:
			list.append(frame)
	if list.is_empty():
		var still: String = ART_DIR + id + ".png"
		list.append(load(still if ResourceLoader.exists(still) else FALLBACK_ART))
	return list

func _ready() -> void:
	rng.randomize()
	var colors: Array[Color] = PowImpact.colors_for(weapon_id)
	if mode == "aura":
		z_index = 1
		var additive: CanvasItemMaterial = CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
		for i in range(34):
			flames.append({"x": rng.randf_range(-1.0, 1.0), "phase": rng.randf(), "speed": rng.randf_range(0.8, 1.4), "size": rng.randf_range(4.0, 9.0)})
		var body: Vector2 = fighter.center() - fighter.position
		embers = FxParticles.stream(self, body + Vector2(0, 10), {"amount": 26, "lifetime": 0.9, "speed": [30.0, 80.0], "direction": Vector2.UP, "spread": 25.0, "gravity": Vector2(0, -120), "size": [2.0, 4.0], "colors": ["fffbe0", colors[1], colors[2]], "box": Vector2(fighter.body_size.x * 0.4, 6)})
		# Charge: motes spiral in from a ring and are swallowed by the weapon.
		pull = FxParticles.stream(self, fighter.weapon_point() - fighter.position, {"amount": 36, "lifetime": 0.45, "speed": [0.0, 10.0], "gravity": Vector2.ZERO, "size": [2.0, 4.0], "colors": ["ffffff", colors[1], tint], "ring": [52.0, 64.0], "radial": -620.0, "tangential": 140.0, "emitting": false, "lifetime_randomness": 0.1})
		return
	z_index = 25
	FxParticles.burst(self, Vector2.ZERO, {"amount": 40, "lifetime": 0.8, "speed": [160.0, 420.0], "direction": Vector2.UP, "spread": 110.0, "gravity": Vector2(0, 300), "size": [2.0, 5.0], "colors": ["ffffff", colors[1], tint, colors[3]], "damping": 90.0})

func _process(delta: float) -> void:
	age += delta
	if mode == "aura":
		if not is_instance_valid(fighter) or fighter.hp <= 0:
			queue_free()
			return
		if is_instance_valid(pull):
			pull.emitting = charge > 0.02
			pull.position = fighter.weapon_point() - fighter.position
			pull.speed_scale = 0.8 + charge
		if is_instance_valid(embers):
			embers.speed_scale = 1.0 + charge
	elif age >= life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if mode == "aura":
		draw_aura()
	else:
		draw_burst()

func draw_aura() -> void:
	var grow: float = 1.0 + 0.6 * charge
	var width: float = (fighter.body_size.x * 0.6 + 10.0) * grow
	var body: Vector2 = fighter.center() - fighter.position
	var pulse: float = 0.5 + 0.5 * sin(age * (7.0 + charge * 10.0))
	var gold: Color = Color("ffc23a")
	# Preparation: the aura swells in over the first moments.
	var rise: float = PowImpact.ease_out(age / 0.35)
	# Column of heat rising from the fighter.
	for i in range(7):
		var k: float = 1.0 - i * 0.13
		var h: float = (40.0 + i * 16.0) * grow * rise
		draw_rect(Rect2(Vector2(-width * k, body.y - h), Vector2(width * 2.0 * k, h + 18.0)), Color(gold.r, gold.g * 0.8, gold.b * 0.5, (0.06 + 0.03 * pulse) * (1.0 + charge)))
	# Ground ring, squashed into an ellipse.
	draw_set_transform(Vector2(0, 2), 0, Vector2(1.0, 0.3))
	draw_arc(Vector2.ZERO, (width + 12.0 + pulse * 5.0) * rise, 0, TAU, 40, Color(tint.r, tint.g, tint.b, 0.9), 6.0 + charge * 4.0)
	draw_circle(Vector2.ZERO, (width + 8.0) * rise, Color(gold.r, gold.g, gold.b, 0.22 + 0.12 * pulse + 0.2 * charge))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# Flame tongues licking up over the body on a 2 px grid.
	for flame: Dictionary in flames:
		var t: float = fposmod(age * flame.speed * (1.0 + charge) + flame.phase, 1.0)
		var x: float = flame.x * width * (1.0 - t * 0.55) + sin(age * 5.0 + flame.phase * 9.0) * 3.0
		var p: Vector2 = Vector2(x, body.y + 14.0 - t * 84.0 * grow).snapped(Vector2(2, 2))
		var s: float = snappedf(flame.size * (1.0 - t * 0.65) * grow, 2.0)
		var c: Color = FLAME[mini(FLAME.size() - 1, int(t * FLAME.size()))]
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), Color(c.r, c.g, c.b, 0.75 * (1.0 - t)))
	# Charging: the weapon glows hotter and a ring closes in on it.
	if charge > 0.02:
		var weapon: Vector2 = fighter.weapon_point() - fighter.position
		draw_circle(weapon, 10.0 + 14.0 * charge + pulse * 3.0, Color(1.0, 0.9, 0.5, 0.35 + 0.3 * charge))
		draw_arc(weapon, 64.0 * (1.0 - fposmod(age * 2.2, 1.0)) + 8.0, 0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.7 * charge), 3.0)

func draw_burst() -> void:
	var t: float = age / life
	if age < 0.14:
		draw_circle(Vector2.ZERO, 70.0 + age * 500.0, Color(1, 1, 0.92, 0.9 * (1.0 - age / 0.14)))
	# Pillar of light shooting up.
	var pillar: float = clampf(1.0 - age / 0.7, 0.0, 1.0)
	if pillar > 0.0:
		var w: float = 34.0 * PowImpact.ease_out(pillar) + 6.0
		draw_rect(Rect2(-w, -900, w * 2.0, 900), Color(tint.r, tint.g, tint.b, 0.35 * pillar))
		draw_rect(Rect2(-w * 0.35, -900, w * 0.7, 900), Color(1, 1, 0.95, 0.6 * pillar))
	# Rotating sun rays.
	var rays: float = clampf(1.0 - t * 1.4, 0.0, 1.0)
	for i in range(16):
		var a: float = TAU * i / 16.0 + age * 1.2
		var r: float = (150.0 if i % 2 == 0 else 105.0) * (0.6 + PowImpact.ease_out(age * 6.0) * 0.6)
		var side: Vector2 = Vector2.from_angle(a + PI / 2) * 9.0
		draw_colored_polygon(PackedVector2Array([side, -side, Vector2.from_angle(a) * r]), Color(tint.r, tint.g, tint.b, 0.4 * rays))
	# Two shockwaves.
	for k in range(2):
		var w: float = (age - k * 0.12) / 0.55
		if w > 0.0 and w < 1.0:
			draw_arc(Vector2.ZERO, 24.0 + 190.0 * PowImpact.ease_out(w), 0, TAU, 56, Color(1, 0.95, 0.7, 1.0 - w) if k == 0 else Color(tint.r, tint.g, tint.b, 1.0 - w), 7.0 * (1.0 - w) + 1.0)
