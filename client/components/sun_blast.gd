class_name SunBlast
extends Node2D

# The Founder explosion (Solaris): five frames of drawn art played over the crater, in the
# order of the brief: a small golden flash, the sun sigil on the ground, a vertical burst
# of light, an energy ring, and small stars going out. The art is scaled so HALF THE
# CANVAS WIDTH IS THE REAL DAMAGE RADIUS: the ring ends exactly at `radius` and nothing
# that could be read as an area is drawn beyond it (tests/founder_tests.gd checks the
# frames). The match never reads this node; it is only a drawing.

const TIMES: Array[float] = [0.0, 0.06, 0.12, 0.20, 0.32]
const LIFE: float = 0.62
const CANVAS: Vector2 = Vector2(192, 140)
const GROUND_ROW: float = 120.0

var radius: float = 46.0
var age: float = 0.0
var frames: Array[Texture2D] = []
var sprite: Sprite2D

func _ready() -> void:
	frames = FounderPack.frames("explosion", "frame_")
	z_index = 20
	if frames.is_empty():
		queue_free()
		return
	sprite = Sprite2D.new()
	sprite.texture = frames[0]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.material = UiKit.smooth_material()
	var k: float = 2.0 * radius / CANVAS.x
	sprite.scale = Vector2.ONE * k
	# The ground row of the art sits on the impact point.
	sprite.position = Vector2(0, (CANVAS.y / 2.0 - GROUND_ROW) * k)
	add_child(sprite)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	var index: int = 0
	for i in range(TIMES.size()):
		if age >= TIMES[i]:
			index = i
	sprite.texture = frames[mini(index, frames.size() - 1)]
	sprite.modulate.a = 1.0 if age < LIFE - 0.15 else (LIFE - age) / 0.15
