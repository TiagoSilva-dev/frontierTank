class_name EmoteFx
extends Node2D

# "Paladino Approved": the Paladino's head (confident smirk, a star twinkling) pops over a
# Founder for 1.6 s. Purely visual; the match only carries the request (LocalMatch.emote),
# and only a Founder's request is accepted.

const FRAMES_DIR: String = "emote"
const LIFE: float = 1.6

var fighter: TankFighter
var frames: Array[Texture2D] = []
var sprite: Sprite2D
var age: float = 0.0

func _ready() -> void:
	frames = FounderPack.frames(FRAMES_DIR)
	z_index = 30
	if frames.is_empty() or not is_instance_valid(fighter):
		queue_free()
		return
	sprite = Sprite2D.new()
	sprite.texture = frames[0]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ZERO
	add_child(sprite)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE or not is_instance_valid(fighter):
		queue_free()
		return
	global_position = fighter.global_position + Vector2(0, -92.0 - 10.0 * ease_out(age / 0.3))
	sprite.texture = frames[int(age * 10.0) % frames.size()]
	var pop: float = ease_out(age / 0.22)
	var squash: float = 1.0 + 0.25 * sin(clampf(age / 0.22, 0.0, 1.0) * PI)
	sprite.scale = Vector2(pop * 0.9, pop * 0.9 * squash)
	sprite.modulate.a = 1.0 if age < LIFE - 0.3 else (LIFE - age) / 0.3

func ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)
