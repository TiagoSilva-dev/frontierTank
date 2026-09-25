class_name AuraRing
extends Node2D

# Weapon aura: a glowing magic circle behind the character's head and shoulders (only
# outside battles), coloured by the weapon's strengthen level: +1-5 green, +6-8 blue,
# +9-11 purple, +12 red. Layers come from tools/aura_textures.py: the disc pulses, the
# rays and the rune ring turn one way, the star the other, and sparks orbit around it.

const SIZE: int = 256
const COLOR_NAMES: Array = [[12, "vermelha"], [9, "roxa"], [6, "azul"], [1, "verde"]]

var color: Color = Color.WHITE
var level: int = 0
var disc: Sprite2D
var rays: Sprite2D
var ring: Sprite2D
var star: Sprite2D
var sparkle: Node2D
var sparks: Array[Vector4] = []
var time: float = 0.0

static func color_name(strengthen_level: int) -> String:
	for entry: Array in COLOR_NAMES:
		if strengthen_level >= int(entry[0]):
			return str(entry[1])
	return "verde"

func setup(aura_color: Color, strengthen_level: int, diameter: float) -> void:
	color = aura_color
	level = strengthen_level
	var tint: String = color_name(level)
	disc = layer(tint, "disc")
	rays = layer(tint, "rays")
	star = layer(tint, "star")
	ring = layer(tint, "ring")
	sparkle = Node2D.new()
	sparkle.draw.connect(draw_sparks)
	add_child(sparkle)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7 + level
	for i in range(16):
		# angle, orbit radius, angular speed, twinkle phase
		sparks.append(Vector4(rng.randf() * TAU, rng.randf_range(58.0, 134.0), rng.randf_range(0.25, 0.8) * (1.0 if i % 2 == 0 else -1.0), rng.randf() * TAU))
	scale = Vector2.ONE * diameter / SIZE

func layer(tint: String, part: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load("res://assets/effects/aura/%s_%s.png" % [tint, part])
	# Smooth glow: linear filtering keeps the turning circle free of jagged edges.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(sprite)
	return sprite

func _process(delta: float) -> void:
	time += delta
	# The +12 red aura turns faster, like the top-tier effect in DDTank.
	var speed: float = 1.5 if level >= 12 else 1.0
	rays.rotation = time * 0.12 * speed
	ring.rotation = time * 0.3 * speed
	star.rotation = -time * 0.5 * speed
	var pulse: float = 0.5 + 0.5 * sin(time * 2.4)
	disc.scale = Vector2.ONE * (0.97 + 0.03 * pulse)
	disc.modulate.a = 0.82 + 0.18 * pulse
	rays.modulate.a = 0.45 + 0.55 * pulse
	star.modulate.a = 0.85 + 0.15 * sin(time * 3.1)
	sparkle.queue_redraw()

func draw_sparks() -> void:
	var light: Color = color.lightened(0.65)
	for spark: Vector4 in sparks:
		var at: Vector2 = Vector2.from_angle(spark.x + time * spark.z) * spark.y
		var twinkle: float = 0.5 + 0.5 * sin(time * 4.0 + spark.w)
		var size: float = 3.0 + 6.0 * twinkle
		var c: Color = Color(light.r, light.g, light.b, 0.25 + 0.75 * twinkle)
		sparkle.draw_circle(at, size * 0.9, Color(color.r, color.g, color.b, 0.18 * twinkle))
		sparkle.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -size), at + Vector2(size * 0.22, 0), at + Vector2(0, size), at + Vector2(-size * 0.22, 0)]), c)
		sparkle.draw_colored_polygon(PackedVector2Array([at + Vector2(-size, 0), at + Vector2(0, size * 0.22), at + Vector2(size, 0), at + Vector2(0, -size * 0.22)]), c)
