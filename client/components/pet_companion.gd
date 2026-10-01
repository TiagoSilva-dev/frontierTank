class_name PetCompanion
extends Node2D

# The active pet next to its fighter in battle (0.19): it stays behind the owner, floats,
# turns with them, hops when the owner is hit and cheers on a victory. Purely visual (the
# bonuses come from the profile), so it never touches the lockstep state.

const HEIGHT: float = 52.0

var owner_fighter: TankFighter
var sprite: Sprite2D
var age: float = 0.0
var last_hp: int = 0
var hop: float = 0.0
var offset_now: Vector2 = Vector2.ZERO

func setup(fighter: TankFighter, species: String) -> void:
	owner_fighter = fighter
	last_hp = fighter.hp
	var texture: Texture2D = PetWidgets.species_texture(species)
	if texture == null:
		queue_free()
		return
	var used: Rect2i = texture.get_image().get_used_rect()
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.region_enabled = true
	sprite.region_rect = Rect2(used)
	var fit: float = HEIGHT / maxf(1.0, float(used.size.y))
	sprite.scale = Vector2.ONE * fit
	sprite.position = Vector2(0, -float(used.size.y) * fit / 2.0)
	add_child(sprite)
	z_index = -1
	offset_now = target_offset()
	position = offset_now

func target_offset() -> Vector2:
	var reach: float = owner_fighter.body_size.x * 0.5 + 34.0
	return Vector2(-owner_fighter.facing * reach, -4.0)

func _process(delta: float) -> void:
	if not is_instance_valid(owner_fighter) or sprite == null:
		return
	age += delta
	var alive: bool = owner_fighter.hp > 0
	modulate.a = move_toward(modulate.a, 1.0 if alive else 0.0, delta * 2.0)
	if owner_fighter.hp < last_hp:
		hop = 0.45
	last_hp = owner_fighter.hp
	hop = maxf(0.0, hop - delta)
	var cheer: float = absf(sin(age * 9.0)) * 14.0 if owner_fighter.celebrating else 0.0
	var jump: float = sin(PI * (1.0 - hop / 0.45)) * 18.0 if hop > 0.0 else 0.0
	# Follow with a little lag so walking looks alive; turn when the owner turns.
	offset_now = offset_now.lerp(target_offset(), clampf(delta * 5.0, 0.0, 1.0))
	position = offset_now + Vector2(0, -jump - cheer - 3.0 - sin(age * 2.6) * 2.5)
	sprite.flip_h = owner_fighter.facing < 0
	var squash: float = 1.0 + sin(age * 5.2) * 0.025
	sprite.scale.y = absf(sprite.scale.x) * squash
