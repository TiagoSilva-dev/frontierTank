class_name FieldMap
extends RefCounted

# The top-down field of the Caçada (0.21 pilot). One map per zone, built once from the
# zone's Wang tilesets (assets/field/<zone>/tiles.json): a grass floor, stone ruins and a
# pond placed at the edges so the middle stays open for the fight, then trees and pillars
# scattered around. Everything is seeded by the zone id, so the field looks the same on every
# visit. `texture` is the baked ground; `decor` are the objects to draw sorted by `foot.y`.

const TILE: int = 32
const COLS: int = 48
const ROWS: int = 30
const ROOT: String = "res://assets/field/"

static var cache: Dictionary = {}

var zone: String = ""
var texture: ImageTexture
var decor: Array = []
# Multiplies the baked ground when it is drawn (tiles.json "shade"): snow would otherwise
# be as bright as the white fighters standing on it.
var shade: Color = Color.WHITE
# tiles.json "ruined": the stone platforms are broken halls (a wing, chipped corners, pits,
# worn slabs, rubble and columns lying on them) instead of plain rectangles.
var ruined: bool = false
# Cells (tile coordinates) fully inside a platform, where on_stone scenery stands.
var slabs: Array[Vector2i] = []

# Open ground in the middle of the field, in tiles (the fight happens here): trees and
# bushes stay out of it, ground cover (tufts, pebbles) does not.
static func clearing() -> Rect2:
	return Rect2(17, 11.5, 14, 7)

static func world_size() -> Vector2:
	return Vector2(COLS * TILE, ROWS * TILE)

static func available(zone_id: String) -> bool:
	return FileAccess.file_exists(ROOT + zone_id + "/tiles.json")

static func for_zone(zone_id: String) -> FieldMap:
	if not cache.has(zone_id):
		var made: FieldMap = FieldMap.new()
		made.zone = zone_id
		made.build()
		cache[zone_id] = made
	return cache[zone_id]

func build() -> void:
	var file: FileAccess = FileAccess.open(ROOT + zone + "/tiles.json", FileAccess.READ)
	if file == null:
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	var tone: Array = data.get("shade", [1.0, 1.0, 1.0])
	shade = Color(float(tone[0]), float(tone[1]), float(tone[2]))
	ruined = bool(data.get("ruined", false))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("field:" + zone)
	var image: Image = Image.create(COLS * TILE, ROWS * TILE, false, Image.FORMAT_RGBA8)
	var sets: Dictionary = data.sets
	var masks: Dictionary = {}
	for kind: String in sets:
		var empty: PackedByteArray = PackedByteArray()
		empty.resize((COLS + 1) * (ROWS + 1))
		masks[kind] = empty
	_shapes(masks, data, rng)
	var first: bool = true
	for kind: String in data.order:
		var set: Dictionary = sets[kind]
		var sheet: Image = (load(ROOT + zone + "/" + str(set.png)) as Texture2D).get_image()
		sheet.convert(Image.FORMAT_RGBA8)
		var lookup: Dictionary = {}
		for tile: Array in set.tiles:
			lookup[_key(int(tile[0]), int(tile[1]), int(tile[2]), int(tile[3]))] = Rect2i(int(tile[4]), int(tile[5]), TILE, TILE)
		var mask: PackedByteArray = masks[kind]
		for cy in range(ROWS):
			for cx in range(COLS):
				var nw: int = mask[cy * (COLS + 1) + cx]
				var ne: int = mask[cy * (COLS + 1) + cx + 1]
				var sw: int = mask[(cy + 1) * (COLS + 1) + cx]
				var se: int = mask[(cy + 1) * (COLS + 1) + cx + 1]
				if nw + ne + sw + se == 0 and not first:
					continue
				var source: Rect2i = lookup.get(_key(nw, ne, sw, se), lookup[_key(0, 0, 0, 0)])
				image.blend_rect(sheet, source, Vector2i(cx * TILE, cy * TILE))
				if ruined and kind == "stone" and nw + ne + sw + se == 4:
					slabs.append(Vector2i(cx, cy))
					_wear(image, Vector2i(cx * TILE, cy * TILE), rng)
		first = false
	texture = ImageTexture.create_from_image(image)
	_scatter(data, masks, rng)

static func _key(nw: int, ne: int, sw: int, se: int) -> int:
	return nw * 8 + ne * 4 + sw * 2 + se

# Stone platforms and the pond: vertex masks, away from the clearing.
func _shapes(masks: Dictionary, data: Dictionary, rng: RandomNumberGenerator) -> void:
	if masks.has("stone"):
		for block: Array in data.get("stone_blocks", []):
			var x0: int = int(block[0]) + rng.randi_range(-1, 1)
			var y0: int = int(block[1]) + rng.randi_range(-1, 1)
			for y in range(y0, y0 + int(block[3]) + 1):
				for x in range(x0, x0 + int(block[2]) + 1):
					_mark(masks.stone, x, y)
			if ruined:
				_break_up(masks.stone, Rect2i(x0, y0, int(block[2]), int(block[3])), rng)
	if masks.has("water"):
		for pond: Array in data.get("ponds", []):
			var center: Vector2 = Vector2(float(pond[0]), float(pond[1]))
			var radius: Vector2 = Vector2(float(pond[2]), float(pond[3]))
			for y in range(ROWS + 1):
				for x in range(COLS + 1):
					var d: Vector2 = (Vector2(x, y) - center) / radius
					if d.length() + rng.randf_range(-0.12, 0.12) < 1.0:
						_mark(masks.water, x, y)

func _mark(mask: PackedByteArray, x: int, y: int, value: int = 1) -> void:
	if x >= 0 and y >= 0 and x <= COLS and y <= ROWS:
		mask[y * (COLS + 1) + x] = value

# Turns a marked rectangle (in tiles) into a ruin: a wing on the top or the bottom, a chamfer or a
# two-step bite out of each corner, and a pit in the middle of the big ones. The corner tiles of
# the Wang set draw the new edges, so nothing is painted by hand.
func _break_up(mask: PackedByteArray, block: Rect2i, rng: RandomNumberGenerator) -> void:
	var wing_w: int = mini(rng.randi_range(2, 4), block.size.x - 2)
	var wing_h: int = rng.randi_range(1, 2)
	var wing_x: int = block.position.x + rng.randi_range(1, maxi(1, block.size.x - wing_w - 1))
	var above: bool = rng.randf() < 0.5
	var wing_y: int = block.position.y - wing_h if above else block.position.y + block.size.y
	for y in range(wing_y, wing_y + wing_h + 1):
		for x in range(wing_x, wing_x + wing_w + 1):
			_mark(mask, x, y)
	var right: int = block.position.x + block.size.x
	var bottom: int = block.position.y + block.size.y
	for corner: Vector2i in [Vector2i(block.position.x, block.position.y), Vector2i(right, block.position.y), Vector2i(block.position.x, bottom), Vector2i(right, bottom)]:
		if rng.randf() < 0.75:
			var bite: int = rng.randi_range(1, 2)
			var step: Vector2i = Vector2i(1 if corner.x == block.position.x else -1, 1 if corner.y == block.position.y else -1)
			for dy in range(bite):
				for dx in range(bite):
					_mark(mask, corner.x + dx * step.x, corner.y + dy * step.y, 0)
	if block.size.x >= 5 and block.size.y >= 4 and rng.randf() < 0.7:
		_mark(mask, block.position.x + rng.randi_range(2, block.size.x - 2), block.position.y + 2, 0)

# Worn slab: a lighter or darker cell, and now and then a crack, so the repeating tile stops
# reading as a grid.
func _wear(image: Image, corner: Vector2i, rng: RandomNumberGenerator) -> void:
	var tone: float = rng.randf_range(-0.09, 0.07)
	if absf(tone) > 0.02:
		for y in range(TILE):
			for x in range(TILE):
				var color: Color = image.get_pixel(corner.x + x, corner.y + y)
				image.set_pixel(corner.x + x, corner.y + y, Color(clampf(color.r + tone, 0.0, 1.0), clampf(color.g + tone, 0.0, 1.0), clampf(color.b + tone, 0.0, 1.0), color.a))
	if rng.randf() < 0.3:
		var at: Vector2i = corner + Vector2i(rng.randi_range(6, 24), rng.randi_range(4, 12))
		var dir: int = 1 if rng.randf() < 0.5 else -1
		for step in range(rng.randi_range(8, 14)):
			var spot: Vector2i = Vector2i(at.x + int(step * dir * 0.5) + int(step % 3 == 0), at.y + step)
			if spot.y < corner.y + TILE - 1 and spot.x > corner.x and spot.x < corner.x + TILE - 1:
				var color: Color = image.get_pixel(spot.x, spot.y)
				image.set_pixel(spot.x, spot.y, Color(color.r * 0.45, color.g * 0.45, color.b * 0.5, color.a))

func _covered(masks: Dictionary, x: int, y: int) -> bool:
	for kind: String in masks:
		var mask: PackedByteArray = masks[kind]
		for dy in range(-1, 3):
			for dx in range(-1, 3):
				var vx: int = x + dx
				var vy: int = y + dy
				if vx >= 0 and vy >= 0 and vx <= COLS and vy <= ROWS and mask[vy * (COLS + 1) + vx] == 1:
					return true
	return false

func _scatter(data: Dictionary, masks: Dictionary, rng: RandomNumberGenerator) -> void:
	decor = []
	var open: Rect2 = clearing()
	for item: Dictionary in data.get("decor", []):
		var texture_: Texture2D = load(ROOT + zone + "/" + str(item.png)) as Texture2D
		if texture_ == null:
			continue
		var placed: int = 0
		var tries: int = 0
		if bool(item.get("on_stone", false)):
			# Lying on the platforms: one per slab, drawn in the order of their feet.
			var free: Array[Vector2i] = slabs.duplicate()
			while placed < int(item.count) and not free.is_empty():
				var cell: Vector2i = free.pop_at(rng.randi_range(0, free.size() - 1))
				var foot_: Vector2 = Vector2(cell.x * TILE + rng.randf_range(8, 24), cell.y * TILE + rng.randf_range(20, 30))
				decor.append({"foot": foot_, "texture": texture_, "scale": float(item.get("scale", 1.0)), "cover": bool(item.get("cover", false)), "on_stone": true})
				placed += 1
			continue
		while placed < int(item.count) and tries < 400:
			tries += 1
			var tx: int = rng.randi_range(1, COLS - 2)
			var ty: int = rng.randi_range(1, ROWS - 2)
			var foot: Vector2 = Vector2(tx * TILE + rng.randf_range(4, 28), ty * TILE + rng.randf_range(20, 30))
			var cover: bool = bool(item.get("cover", false))
			if (not cover and open.grow(1.0).has_point(foot / TILE)) or _covered(masks, tx, ty):
				continue
			decor.append({"foot": foot, "texture": texture_, "scale": float(item.get("scale", 1.0)), "cover": cover})
			placed += 1
