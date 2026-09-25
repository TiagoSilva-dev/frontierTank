class_name ImpactFx
extends Node2D

# One explosion: the animated PixelLab fireball (assets/effects/explosion/frame_*.png)
# over a white flash and a shockwave ring, smoke puffs drifting up, and chunks of the
# ground that was blown away (colours sampled from the crater) flying out and falling.
# Chunks and puffs are drawn on the 2x2 art-pixel grid of the terrain.

const FRAMES_DIR: String = "res://assets/effects/explosion/"
const FALLBACK: String = "res://assets/effects/explosao.png"
const FRAME_TIME: float = 0.055
const GRAVITY: float = 900.0

static var _frames: Array[Texture2D] = []

var radius: float = 40.0
var debris: PackedColorArray = PackedColorArray()
var age: float = 0.0
var life: float = 1.2
var chunks: Array[Dictionary] = []
var puffs: Array[Dictionary] = []
var fire: Sprite2D

static func frames() -> Array[Texture2D]:
	if _frames.is_empty():
		for i in range(32):
			var path: String = FRAMES_DIR + "frame_%02d.png" % i
			if not ResourceLoader.exists(path):
				break
			_frames.append(load(path))
		if _frames.is_empty():
			_frames.append(load(FALLBACK))
	return _frames

func _ready() -> void:
	var art: Array[Texture2D] = frames()
	fire = Sprite2D.new()
	fire.texture = art[0]
	fire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Snap the fireball to whole art-pixel multiples so its pixels stay square.
	var fit: float = radius * 3.0 / float(art[0].get_width())
	fire.scale = Vector2.ONE * maxf(1.0, roundf(fit * 2.0) / 2.0)
	fire.z_index = 1
	add_child(fire)
	life = maxf(0.9, art.size() * FRAME_TIME + 0.25) if art.size() > 1 else 0.8
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var count: int = clampi(int(radius / 2.5), 10, 28)
	for i in range(count):
		var angle: float = rng.randf_range(-PI * 0.95, -PI * 0.05)
		var color: Color = debris[rng.randi() % debris.size()] if debris.size() > 0 else Color("7a5230")
		chunks.append({"pos": Vector2.from_angle(angle) * rng.randf_range(0.0, radius * 0.5), "vel": Vector2.from_angle(angle) * rng.randf_range(180.0, 420.0 + radius * 2.0), "color": color, "size": [2.0, 4.0, 4.0, 6.0][rng.randi() % 4]})
	for i in range(clampi(int(radius / 8.0), 4, 9)):
		var angle: float = rng.randf_range(-PI, 0.0)
		puffs.append({"pos": Vector2.from_angle(angle) * rng.randf_range(radius * 0.2, radius * 0.8), "vel": Vector2(rng.randf_range(-18, 18), rng.randf_range(-46, -20)), "r": rng.randf_range(radius * 0.25, radius * 0.45), "delay": rng.randf_range(0.05, 0.25), "shade": rng.randf_range(0.28, 0.5)})

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	var art: Array[Texture2D] = frames()
	if art.size() > 1:
		var index: int = int(age / FRAME_TIME)
		fire.visible = index < art.size()
		if fire.visible:
			fire.texture = art[index]
	else:
		# Single painted frame: grow and fade like before.
		var t: float = age / life
		fire.modulate.a = 1.0 - t
		fire.scale = Vector2.ONE * radius / 45.0 * (1.0 + t * 0.65)
	for chunk: Dictionary in chunks:
		chunk.vel = chunk.vel + Vector2(0, GRAVITY * delta)
		chunk.pos = chunk.pos + chunk.vel * delta
	for puff: Dictionary in puffs:
		if age > puff.delay:
			puff.pos = puff.pos + puff.vel * delta
	queue_redraw()

func _draw() -> void:
	if age < 0.14:
		var t: float = age / 0.14
		draw_circle(Vector2.ZERO, radius * (0.9 + t * 0.7), Color(1.0, 0.97, 0.8, 0.85 * (1.0 - t)))
	var wave: float = age / 0.38
	if wave < 1.0:
		draw_arc(Vector2.ZERO, radius * (0.7 + 1.5 * wave), PI, TAU, 36, Color(1.0, 0.92, 0.65, 0.7 * (1.0 - wave)), 2.0 + 4.0 * (1.0 - wave))
	for puff: Dictionary in puffs:
		var t: float = clampf((age - puff.delay) / (life - puff.delay), 0.0, 1.0)
		if age <= puff.delay:
			continue
		var r: float = snappedf(puff.r * (0.6 + t * 0.9), 2.0)
		var shade: float = puff.shade
		var p: Vector2 = puff.pos.snapped(Vector2(2, 2))
		draw_circle(p, r, Color(shade, shade * 0.95, shade * 0.92, 0.55 * (1.0 - t)))
		draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.55, Color(shade + 0.2, shade + 0.18, shade + 0.15, 0.4 * (1.0 - t)))
	var fade: float = clampf((life - age) / 0.3, 0.0, 1.0)
	for chunk: Dictionary in chunks:
		var s: float = chunk.size
		var p: Vector2 = (chunk.pos as Vector2).snapped(Vector2(2, 2))
		var color: Color = chunk.color
		draw_rect(Rect2(p - Vector2(s, s) / 2.0 - Vector2(1, 1), Vector2(s + 2, s + 2)), Color(0.1, 0.06, 0.04, fade))
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), Color(color.r, color.g, color.b, fade))
