class_name FounderPreview
extends Control

# A looping picture of Julgamento do Sol for the Founder Pack screen (3.6 s): the
# Paladino charges, the halo grows into the mandala, the lance crosses the night, and the
# sigil, the beam and the sky sun land. It draws the same art as the real sequence
# (FounderPow, FounderImpact) with the proportions of the real rules: everything on the
# ground stays inside the radius.

const LOOP: float = 3.6
const GROUND: float = 176.0
const RADIUS: float = 30.0

var time: float = 0.0
var stars: Array[Vector3] = []
var mandala: Array[Texture2D] = []
var lance: Array[Texture2D] = []
var halo: Array[Texture2D] = []
var sigil: Texture2D
var feather: Texture2D
var idle: Array[Texture2D] = []
var power: Array[Texture2D] = []
var skin_root: String = "res://assets/characters/roupa_paladino_sol/prone/"

func _ready() -> void:
	custom_minimum_size = Vector2(400, 225)
	size = Vector2(400, 225)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mandala = FounderPack.frames("mandala", "mandala_")
	lance = FounderPack.frames("lance")
	halo = FounderPack.frames("halo", "halo_")
	sigil = FounderPack.texture("sigil/sun_sigil.png")
	feather = FounderPack.texture("feather.png")
	idle = FounderPack.folder_frames(skin_root + "idle")
	power = FounderPack.folder_frames(skin_root + "pow")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 21
	for i in range(46):
		stars.append(Vector3(rng.randf() * 400.0, rng.randf() * 150.0, rng.randf() * TAU))

func _process(delta: float) -> void:
	time = fmod(time + delta, LOOP)
	queue_redraw()

func ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

func _draw() -> void:
	var t: float = time
	# Night sky in bands and stars.
	for i in range(15):
		var u: float = i / 14.0
		draw_rect(Rect2(0, i * 12.0, 400, 13), Color(0.05, 0.07, 0.2).lerp(Color(0.22, 0.2, 0.5), u * u))
	for star: Vector3 in stars:
		var twinkle: float = 0.5 + 0.5 * sin(t * 3.0 + star.z)
		draw_rect(Rect2(star.x, star.y, 2, 2), Color(1, 0.95, 0.8, 0.25 + 0.6 * twinkle))
	draw_rect(Rect2(0, GROUND, 400, 49), Color("1c1830"))
	draw_rect(Rect2(0, GROUND, 400, 3), Color("5a4a7a"))
	# Paladino: charging pose, the pow clip in the middle of the loop.
	var head: Vector2 = Vector2(104, 138)
	var charge: float = clampf((t - 0.1) / 0.7, 0.0, 1.0)
	var frames: Array[Texture2D] = power if (t > 0.1 and t < 1.7 and not power.is_empty()) else idle
	if not frames.is_empty():
		var picture: Texture2D = frames[int(t * 8.0) % frames.size()]
		draw_texture_rect(picture, Rect2(Vector2(36, GROUND - 98), Vector2(136, 136) * 0.72), false)
	# Halo (small) turning into the mandala (big) and back.
	var growth: float = ease_out(charge) * (1.0 - clampf((t - 2.6) / 0.6, 0.0, 1.0))
	if not halo.is_empty():
		var ring: float = 62.0 * (1.0 - growth * 0.4)
		draw_texture_rect(halo[int(t * 6.0) % halo.size()], Rect2(head - Vector2(ring, ring) / 2.0, Vector2(ring, ring)), false, Color(1, 1, 1, 1.0 - growth))
	if not mandala.is_empty() and growth > 0.01:
		var big: float = 190.0 * growth
		draw_texture_rect(mandala[int(t * 9.0) % mandala.size()], Rect2(head - Vector2(big, big) / 2.0, Vector2(big, big)), false, Color(1, 1, 1, minf(1.0, growth * 1.3)))
	# Charge: motes pulled into the weapon on the back.
	if t > 0.7 and t < 1.15:
		var core: Vector2 = Vector2(62, 150)
		for i in range(14):
			var angle: float = i * TAU / 14.0 + t * 3.0
			var pull: float = 1.0 - fposmod((t - 0.7) * 2.6 + i * 0.07, 1.0)
			var spot: Vector2 = core + Vector2.from_angle(angle) * 34.0 * pull
			draw_rect(Rect2(spot - Vector2(1, 1), Vector2(2, 2)), Color(1, 0.93, 0.6, 1.0 - pull * 0.5))
	# The lance.
	var fly: float = (t - 1.15) / 0.8
	var impact_at: Vector2 = Vector2(318, GROUND)
	if fly >= 0.0 and fly <= 1.0 and not lance.is_empty():
		var start: Vector2 = Vector2(150, 132)
		var spot: Vector2 = start.lerp(impact_at, fly) + Vector2(0, -78.0 * sin(PI * fly))
		var ahead: float = minf(1.0, fly + 0.02)
		var next: Vector2 = start.lerp(impact_at, ahead) + Vector2(0, -78.0 * sin(PI * ahead))
		var heading: float = (next - spot).angle()
		for i in range(1, 9):
			var back: float = maxf(0.0, fly - i * 0.035)
			var trail: Vector2 = start.lerp(impact_at, back) + Vector2(0, -78.0 * sin(PI * back))
			draw_rect(Rect2(trail - Vector2(2, 1), Vector2(4 - i * 0.3, 2)), Color(1.0, 0.85, 0.35, 0.8 - i * 0.09))
			if i % 3 == 0:
				draw_set_transform(trail, heading, Vector2(0.35, 1.0))
				draw_arc(Vector2.ZERO, 3.0 + i * 1.2, 0.0, TAU, 14, Color(1.0, 0.85, 0.4, 0.7 - i * 0.07), 1.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_set_transform(spot, heading, Vector2.ONE)
		draw_texture_rect(lance[int(t * 14.0) % lance.size()], Rect2(Vector2(-34, -10.5), Vector2(68, 21)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Impact: sigil inside the radius, a narrow beam, rings that stop at the radius, the sky sun.
	var hit: float = t - 1.95
	if hit >= 0.0 and hit < 1.5:
		if sigil != null:
			var fade: float = clampf(hit / 0.08, 0.0, 1.0) * clampf((1.1 - hit) / 0.35, 0.0, 1.0)
			var width: float = RADIUS * 0.97 * 2.0 / 80.0 * 160.0
			draw_texture_rect(sigil, Rect2(impact_at + Vector2(-width / 2.0, -width * 0.2 - 1), Vector2(width, width * 0.4)), false, Color(1, 1, 1, fade))
		if hit < 0.7:
			var beam: float = RADIUS * 0.22 * (1.0 - 0.45 * hit / 0.7)
			var alpha: float = 1.0 - clampf((hit / 0.7 - 0.5) / 0.5, 0.0, 1.0)
			draw_rect(Rect2(impact_at.x - beam / 2.0, 0, beam, GROUND), Color(1.0, 0.82, 0.3, 0.45 * alpha))
			draw_rect(Rect2(impact_at.x - beam * 0.18, 0, beam * 0.36, GROUND), Color(1, 1, 0.92, alpha))
			if not mandala.is_empty():
				var sun: float = 8.0 * RADIUS
				var sun_alpha: float = 0.9 * clampf(hit / 0.1, 0.0, 1.0) * clampf((0.8 - hit) / 0.5, 0.0, 1.0)
				draw_texture_rect(mandala[int(t * 10.0) % mandala.size()], Rect2(Vector2(impact_at.x - sun / 2.0, GROUND - 6.0 * RADIUS - sun / 2.0), Vector2(sun, sun)), false, Color(1, 1, 1, sun_alpha))
		for i in range(3):
			var u: float = (hit - 0.04 - i * 0.09) / 0.45
			if u >= 0.0 and u <= 1.0:
				draw_set_transform(impact_at, 0.0, Vector2(1.0, 0.3))
				draw_arc(Vector2.ZERO, RADIUS * (1.0 - pow(1.0 - u, 2.0)), 0.0, TAU, 36, Color(1.0, 0.85, 0.4, 0.9 * (1.0 - u)), 2.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if feather != null and hit > 0.75:
			var f: float = (hit - 0.75) / 0.75
			draw_texture(feather, impact_at + Vector2(sin(f * 7.0) * 9.0 * (1.0 - f) - 8.0, lerpf(-110.0, -22.0, f * f * (3.0 - 2.0 * f))), Color(1, 1, 1, 1.0 - clampf((f - 0.75) / 0.25, 0.0, 1.0)))
		if hit < 0.2:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.95, 0.75, 0.35 * (1.0 - hit / 0.2)))
	# Edge vignette while the sequence runs (never the middle).
	var shade: float = clampf(t / 0.35, 0.0, 1.0) * (1.0 - clampf((t - 2.4) / 0.5, 0.0, 1.0)) * 0.55
	if shade > 0.0:
		for i in range(5):
			var w: float = 18.0 + i * 12.0
			var a: float = shade * (1.0 - i / 5.0) * 0.5
			draw_rect(Rect2(0, 0, w, 225), Color(0.03, 0.02, 0.1, a))
			draw_rect(Rect2(400 - w, 0, w, 225), Color(0.03, 0.02, 0.1, a))
