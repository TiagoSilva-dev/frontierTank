class_name FounderImpact
extends Node2D

# Where Julgamento do Sol lands (phase 5 and 6 of docs/FOUNDER_PACK.md):
#  - the sun sigil on the ground, drawn INSIDE the real damage radius (its ray tips stop at
#    0.97 R),
#  - a narrow beam of light from the sky (0.22 R wide, it is a column, not an area),
#  - gold rings that widen on the ground and die at R exactly,
#  - stars rising inside R, a warm pulse over the whole screen and, in the sky only, three
#    faint gold waves crossing the scenery (they never touch the ground plane),
#  - and, last, a celestial feather that drifts down onto the crater.
# Only a drawing: damage, radius and hit tests are the match's (PowImpact does the same).

const LIFE: float = 1.6
const SIGIL_HALF_WIDTH: float = 80.0
const BEAM_WIDTH: float = 0.22

var radius: float = 50.0
var top: float = -600.0
var age: float = 0.0
var sigil: Sprite2D
# The huge sun symbol lives in the SKY (Jev round 3, docs/founder/jev_round3.json): about
# 8 R wide, vertical, centred 6 R above the impact, so it can never read as the damage area.
var sky_sun: Sprite2D
var sky_frames: Array[Texture2D] = []
var feather: Sprite2D
var stars: CPUParticles2D
var pulse: ColorRect
var pulse_layer: CanvasLayer
var viewport_size: Vector2 = Vector2(1280, 720)
var camera_ref: Camera2D

func _ready() -> void:
	z_index = 22
	var sigil_texture: Texture2D = FounderPack.texture("sigil/sun_sigil.png")
	if sigil_texture != null:
		sigil = Sprite2D.new()
		sigil.texture = sigil_texture
		sigil.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sigil.material = UiKit.smooth_material()
		# Ray tips at 0.97 R: the art's widest point is 80 px from the centre.
		sigil.scale = Vector2.ONE * (radius * 0.97 / SIGIL_HALF_WIDTH)
		sigil.modulate.a = 0.0
		add_child(sigil)
	sky_frames = FounderPack.frames("mandala", "mandala_")
	if not sky_frames.is_empty():
		sky_sun = Sprite2D.new()
		sky_sun.texture = sky_frames[0]
		sky_sun.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sky_sun.material = UiKit.smooth_material()
		sky_sun.scale = Vector2.ONE * (8.0 * radius / 192.0)
		sky_sun.position = Vector2(0, -6.0 * radius)
		sky_sun.z_index = -1
		sky_sun.modulate.a = 0.0
		add_child(sky_sun)
	stars = FxParticles.burst(self, Vector2(0, -2), {"amount": 26, "lifetime": 1.0, "speed": [30.0, 110.0], "direction": Vector2.UP, "spread": 55.0, "gravity": Vector2(0, -10), "size": [2.0, 3.0], "colors": ["ffffff", "fff0a8", "ffd25a"], "box": Vector2(radius * 0.8, 3), "damping": 40.0, "z": 2})
	var feather_texture: Texture2D = FounderPack.texture("feather.png")
	if feather_texture != null:
		feather = Sprite2D.new()
		feather.texture = feather_texture
		feather.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		feather.position = Vector2(0, -150)
		feather.modulate.a = 0.0
		add_child(feather)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	if sigil != null:
		var fade_in: float = clampf(age / 0.08, 0.0, 1.0)
		var fade_out: float = clampf((1.15 - age) / 0.35, 0.0, 1.0)
		sigil.modulate.a = fade_in * fade_out
	if sky_sun != null:
		sky_sun.texture = sky_frames[int(age * 10.0) % sky_frames.size()]
		sky_sun.modulate.a = 0.9 * clampf(age / 0.1, 0.0, 1.0) * clampf((0.8 - age) / 0.5, 0.0, 1.0)
	if feather != null and age > 0.75:
		# The feather sways down onto the crater and fades.
		var t: float = (age - 0.75) / (LIFE - 0.75)
		feather.position = Vector2(sin(t * 7.0) * 14.0 * (1.0 - t), lerpf(-150.0, -6.0, t * t * (3.0 - 2.0 * t)))
		feather.rotation = sin(t * 7.0 + 1.0) * 0.5
		feather.modulate.a = minf(1.0, t * 6.0) * (1.0 - clampf((t - 0.75) / 0.25, 0.0, 1.0))
	queue_redraw()

func _draw() -> void:
	# Narrow beam: white core, gold edges, widest at the first instant.
	if age < 0.75:
		var t: float = age / 0.75
		var width: float = radius * BEAM_WIDTH * (1.0 - 0.45 * t)
		var alpha: float = 1.0 - clampf((t - 0.5) / 0.5, 0.0, 1.0)
		var height: float = absf(top)
		draw_rect(Rect2(-width * 0.5, -height, width, height), Color(1.0, 0.82, 0.3, 0.35 * alpha))
		draw_rect(Rect2(-width * 0.32, -height, width * 0.64, height), Color(1.0, 0.93, 0.6, 0.65 * alpha))
		draw_rect(Rect2(-width * 0.14, -height, width * 0.28, height), Color(1.0, 1.0, 0.95, alpha))
	# Rings on the ground plane (squashed ellipses): they grow to R and stop there.
	for i in range(3):
		var start: float = 0.04 + i * 0.09
		var t: float = (age - start) / 0.45
		if t < 0.0 or t > 1.0:
			continue
		var grow: float = 1.0 - pow(1.0 - t, 2.0)
		draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, radius * grow, 0.0, TAU, 48, Color(1.0, 0.85, 0.4, 0.9 * (1.0 - t)), 2.0 + 3.0 * (1.0 - t))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Sky waves: faint gold bands far above the ground, crossing the scenery sideways.
	for i in range(3):
		var start: float = 0.1 + i * 0.12
		var t: float = (age - start) / 0.6
		if t < 0.0 or t > 1.0:
			continue
		var y: float = top + absf(top) * (0.18 + 0.08 * i)
		var reach: float = lerpf(0.0, 900.0, t)
		draw_rect(Rect2(-reach, y, reach * 2.0, 3.0), Color(1.0, 0.85, 0.4, 0.22 * (1.0 - t)))
