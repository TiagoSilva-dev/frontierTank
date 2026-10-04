class_name PetCompanion
extends Node2D

# The active pet next to its fighter in battle (0.19): it stands right beside the owner,
# plays its species' idle animation (PetActor), turns with them, hops when the owner is hit
# and cheers on a victory. Purely visual (the bonuses come from the profile), so it never
# touches the lockstep state.

const HEIGHT: float = 84.0

var owner_fighter: TankFighter
var actor: PetActor
var age: float = 0.0
var last_hp: int = 0
var hop: float = 0.0
var offset_now: Vector2 = Vector2.ZERO

func setup(fighter: TankFighter, species: String) -> void:
	owner_fighter = fighter
	last_hp = fighter.hp
	actor = PetActor.new()
	if not actor.setup(species, HEIGHT):
		actor.free()
		queue_free()
		return
	add_child(actor)
	z_index = -1
	offset_now = target_offset()
	position = offset_now

# The pet shows off when its skill is used: a long hop.
func perk() -> void:
	hop = 0.45

func target_offset() -> Vector2:
	# Beside the owner, a hair behind so it never covers the barrel.
	var reach: float = owner_fighter.body_size.x * 0.5 + actor.width * 0.5 + 2.0
	return Vector2(-owner_fighter.facing * reach, -4.0)

func _process(delta: float) -> void:
	if not is_instance_valid(owner_fighter) or actor == null:
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
	actor.facing = owner_fighter.facing
	actor.tempo = 2.2 if owner_fighter.celebrating or hop > 0.0 else 1.0
