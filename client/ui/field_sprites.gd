class_name FieldSprites
extends RefCounted

# Top-down sprites of the Caçada field (0.21 pilot). Each unit is one sheet in
# assets/field/units/<id>.png of CELL-pixel cells: row 0 holds the eight resting
# directions (DIRS order), rows 1-4 the walk cycle toward south, north, east and west
# (FRAMES columns). A species without a sheet yet is drawn from its album picture instead
# (`has` tells), so any team can walk the field.

const CELL: int = 64
const FRAMES: int = 8
const DIRS: Array = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const WALK_ROWS: Dictionary = {"south": 1, "north": 2, "east": 3, "west": 4}
const ROOT: String = "res://assets/field/units/"

static var cache: Dictionary = {}

static func sheet(id: String) -> Texture2D:
	if not cache.has(id):
		var path: String = ROOT + id + ".png"
		cache[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return cache[id]

static func has(id: String) -> bool:
	return sheet(id) != null

# The eight-way index of a direction vector (screen space, y down).
static func dir_index(direction: Vector2) -> int:
	# DIRS run south, south-east, east... (counter-clockwise on screen), so the steps from
	# "straight down" are counted backwards.
	var steps: int = int(round(fposmod(direction.angle() - PI / 2.0, TAU) / (PI / 4.0)))
	return posmod(-steps, 8)

# Region of the sheet for a unit facing `direction`: resting, or the walk frame at `phase`.
static func region(direction: Vector2, moving: bool, phase: float) -> Rect2:
	var facing: int = dir_index(direction)
	if not moving:
		return Rect2(facing * CELL, 0, CELL, CELL)
	var way: String
	if absf(direction.x) >= absf(direction.y):
		way = "east" if direction.x > 0.0 else "west"
	else:
		way = "south" if direction.y > 0.0 else "north"
	return Rect2((int(phase) % FRAMES) * CELL, int(WALK_ROWS[way]) * CELL, CELL, CELL)
