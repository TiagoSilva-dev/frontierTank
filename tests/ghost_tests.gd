extends SceneTree

# A fallen fighter leaves a ghost (visual only); monsters do not.

func _init() -> void:
	var failures: int = 0
	var fighter: TankFighter = TankFighter.new()
	var balance: Dictionary = {"base_agility": 100, "agility_per_level": 2, "base_hp": 1000, "hp_per_level": 10, "energy": 200, "pow_max": 100}
	var weapon: Dictionary = {"id": "quebra_tijolos", "angle": [0, 90]}
	fighter.setup(0, {"team": 0, "name": "Teste", "level": 3}, weapon, balance)
	root.add_child(fighter)
	fighter.take_damage(10)
	if is_instance_valid(fighter.ghost):
		failures += 1
		printerr("ghost appeared while alive")
	fighter.take_damage(999999)
	if not is_instance_valid(fighter.ghost):
		failures += 1
		printerr("no ghost after death")
	fighter.take_damage(5)
	if fighter.get_children().filter(func(n: Node) -> bool: return n == fighter.ghost).size() != 1:
		failures += 1
	print("GHOST RESULT: %d failures" % failures)
	quit(1 if failures > 0 else 0)
