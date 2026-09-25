class_name DestructibleTerrain
extends Node2D

# One RGBA mask pixel covers PIXEL x PIXEL world units. The same mask decides
# support, collision and what is drawn, so craters never desync from physics.
# As in DDTank, a map's ground is painted art: each "terrain" piece (a PixelLab
# island, 1 texel = 1 mask pixel) is stamped at its world position and its alpha is
# the collision shape. Maps without pieces fall back to procedural islands.
const PIXEL: float = 2.0
const PALETTES: Dictionary = {
	"meadow": {"top": ["d8f08a", "9ad04e", "5f9a34"], "soil": ["a8703f", "8f5c32", "774a28"], "rock": ["9a96a2", "7b7888", "5d5a6a"], "dark": "4a2e1a", "rim": "3a2418"},
	"sand": {"top": ["fff0b0", "f0cf72", "c99a44"], "soil": ["d6a868", "bf8f55", "a37644"], "rock": ["b3a08a", "968370", "7a6958"], "dark": "5e4028", "rim": "4a3020"},
	"frost": {"top": ["ffffff", "c6f0ff", "86cbe6"], "soil": ["6a8cb6", "58769e", "486286"], "rock": ["a0b4d0", "8298b8", "667c9c"], "dark": "283654", "rim": "1e2a44"},
	"obsidian": {"top": ["ffe08a", "d9a23a", "9a6a22"], "soil": ["55486a", "463c5a", "38304a"], "rock": ["756c8c", "5f5876", "4a4460"], "dark": "1e1a2a", "rim": "16121f"},
}

var width: int = 640
var height: int = 360
var mask: Image
var surface_texture: ImageTexture
var palette: Dictionary = PALETTES.meadow
var rim_color: Color = Color("3a2418")
# Colours of the ground blown away by the last crater (the explosion throws them).
var last_debris: PackedColorArray = PackedColorArray()
var world_size: Vector2 = Vector2(1280, 720)

func generate(map: Dictionary, seed_value: int = 1) -> void:
	world_size = Vector2(map.size[0], map.size[1])
	width = int(world_size.x / PIXEL)
	height = int(world_size.y / PIXEL)
	palette = PALETTES.get(str(map.get("palette", "meadow")), PALETTES.meadow)
	rim_color = Color(str(map.get("rim", palette.get("rim", "3c354a"))))
	var data: PackedByteArray = PackedByteArray()
	data.resize(width * height * 4)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.012
	var detail: FastNoiseLite = FastNoiseLite.new()
	detail.seed = seed_value + 7
	detail.frequency = 0.09
	var index: int = 0
	var islands: Array = [] if map.has("terrain") else map.islands
	for island: Array in islands:
		index += 1
		var x0: int = int(island[0] / PIXEL)
		var x1: int = int(island[1] / PIXEL)
		var base: float = island[2] / PIXEL
		var thickness: float = island[3] / PIXEL
		for x in range(maxi(0, x0), mini(width, x1)):
			var t: float = float(x - x0) / float(maxi(1, x1 - x0))
			var edge: float = pow(sin(PI * t), 0.35)
			var top: int = int(base - noise.get_noise_2d(x, index * 97.0) * 26.0 + (1.0 - edge) * 14.0)
			var bottom: int = int(top + maxf(5.0, thickness * pow(sin(PI * t), 0.7) + detail.get_noise_2d(x * 0.6, index * 31.0) * 10.0))
			for y in range(maxi(0, top), mini(height, bottom)):
				var color: Color = shade(x, y, y - top, bottom - 1 - y, detail)
				var offset: int = (y * width + x) * 4
				data[offset] = int(color.r8)
				data[offset + 1] = int(color.g8)
				data[offset + 2] = int(color.b8)
				data[offset + 3] = 255
	mask = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	for piece: Dictionary in map.get("terrain", []):
		stamp(piece)
	surface_texture = ImageTexture.create_from_image(mask)
	queue_redraw()

func stamp(piece: Dictionary) -> void:
	var art: Image = load(str(piece.art)).get_image()
	if art.is_compressed():
		art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	if piece.get("flip", false):
		art.flip_x()
	var at: Vector2i = Vector2i(roundi(float(piece.x) / PIXEL), roundi(float(piece.y) / PIXEL))
	mask.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), at)

func shade(x: int, y: int, depth: int, from_bottom: int, detail: FastNoiseLite) -> Color:
	var tops: Array = palette.top
	var soils: Array = palette.soil
	var rocks: Array = palette.rock
	var grass_depth: int = 5 + int((detail.get_noise_2d(x * 3.0, 11.0) + 1.0) * 2.0)
	if from_bottom < 2:
		return Color(palette.dark)
	if depth == 0:
		return Color(tops[0])
	if depth < 3:
		return Color(tops[1])
	if depth < grass_depth:
		return Color(tops[2]) if (x + y) % 2 == 0 or depth < grass_depth - 1 else Color(soils[0])
	var rock: float = detail.get_noise_2d(x * 0.9, y * 0.9)
	if rock > 0.42:
		var tone: int = 0 if rock > 0.62 else 1
		if detail.get_noise_2d(x * 0.9 - 1.5, y * 0.9 - 1.5) < 0.42:
			tone = 0
		return Color(rocks[tone]) if detail.get_noise_2d(x * 0.9 + 1.2, y * 0.9 + 1.2) > 0.38 else Color(rocks[2])
	var band: float = detail.get_noise_2d(x * 0.35, y * 0.7)
	var soil: int = 0 if band > 0.25 else (1 if band > -0.2 else 2)
	if from_bottom < 7 and soil < 2:
		soil += 1
	if (x * 7 + y * 13) % 29 == 0:
		soil = mini(2, soil + 1)
	return Color(soils[soil])

func solid(point: Vector2) -> bool:
	var x: int = floori(point.x / PIXEL)
	var y: int = floori(point.y / PIXEL)
	return x >= 0 and x < width and y >= 0 and y < height and mask.get_pixel(x, y).a > 0.5

func surface_y(x: float, start: float = 0.0) -> float:
	for y in range(maxi(0, floori(start / PIXEL)), height):
		if solid(Vector2(x, y * PIXEL)):
			return y * PIXEL
	return world_size.y + 200.0

func slope_degrees(x: float, y: float) -> float:
	# Ground angle under the feet; positive when the ground rises to the right.
	var left: float = surface_y(x - 12.0, y - 24.0)
	var right: float = surface_y(x + 12.0, y - 24.0)
	if left > world_size.y or right > world_size.y:
		return 0.0
	return clampf(rad_to_deg(atan2(left - right, 24.0)), -22.0, 22.0)

func crater(center: Vector2, radius: float) -> int:
	var removed: int = 0
	var c: Vector2 = center / PIXEL
	var r: float = radius / PIXEL
	var rim: Color = rim_color
	# The hole gets a dark burnt lip and a softer scorch fading into the painting.
	var reach: float = r + 8.0
	last_debris.clear()
	for y in range(maxi(0, floori(c.y - reach)), mini(height, ceili(c.y + reach) + 1)):
		for x in range(maxi(0, floori(c.x - reach)), mini(width, ceili(c.x + reach) + 1)):
			var dist: float = Vector2(x, y).distance_to(c)
			var pixel: Color = mask.get_pixel(x, y)
			if pixel.a <= 0.0 or dist > reach:
				continue
			if dist <= r:
				if removed % 7 == 0 and last_debris.size() < 32:
					last_debris.append(pixel)
				mask.set_pixel(x, y, Color.TRANSPARENT)
				removed += 1
			elif dist < r + 2.5:
				mask.set_pixel(x, y, pixel.lerp(rim, 0.75))
			else:
				mask.set_pixel(x, y, pixel.lerp(rim, 0.4 * (reach - dist) / 5.5))
	surface_texture.update(mask)
	queue_redraw()
	return removed

func _draw() -> void:
	if surface_texture != null:
		draw_texture_rect(surface_texture, Rect2(Vector2.ZERO, world_size), false)
