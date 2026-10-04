class_name PetActor
extends Node2D

# One animated pet: the species portrait standing on its feet at the node's origin, moved
# every frame by its PetMotion style. Used beside the fighter in battle and on the Mochila
# stage. `facing` flips it, `tempo` speeds the motion up (cheering).

var species: String = ""
var style: String = PetMotion.DEFAULT_STYLE
var height: float = 0.0
var width: float = 0.0
var facing: int = 1
var tempo: float = 1.0
var age: float = 0.0
var rig: Node2D
var sprite: Sprite2D

func setup(species_id: String, pet_height: float) -> bool:
	var texture: Texture2D = PetWidgets.species_texture(species_id)
	if texture == null:
		return false
	species = species_id
	style = PetMotion.style_of(species_id)
	age = PetMotion.phase_of(species_id)
	var used: Rect2i = texture.get_image().get_used_rect()
	var fit: float = pet_height / maxf(1.0, float(used.size.y))
	height = pet_height
	width = float(used.size.x) * fit
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.region_enabled = true
	sprite.region_rect = Rect2(used)
	sprite.scale = Vector2.ONE * fit
	sprite.position = Vector2(0, -pet_height / 2.0)
	rig = Node2D.new()
	add_child(rig)
	rig.add_child(sprite)
	return true

func _process(delta: float) -> void:
	if rig == null:
		return
	age += delta * tempo
	var pose: Dictionary = PetMotion.sample(style, age)
	var pos: Vector2 = pose.pos
	rig.position = Vector2(pos.x * facing, pos.y)
	rig.rotation = float(pose.rot) * facing
	rig.scale = pose.scale
	sprite.flip_h = facing < 0
