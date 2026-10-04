extends SceneTree

# Every species has a motion style, the poses stay small and finite, and the actor builds.

func _init() -> void:
	var failures: int = 0
	for species: Dictionary in Pets.species_list():
		var id: String = str(species.id)
		if not PetMotion.STYLES.has(id):
			print("FAIL no motion style for ", id)
			failures += 1
		var actor: PetActor = PetActor.new()
		if not actor.setup(id, 80.0):
			print("FAIL actor for ", id)
			failures += 1
		actor.free()
		for step in range(400):
			var pose: Dictionary = PetMotion.sample(PetMotion.style_of(id), step * 0.05)
			var pos: Vector2 = pose.pos
			if not is_finite(pos.x) or absf(pos.x) > 14.0 or pos.y > 1.0 or pos.y < -20.0 or absf(float(pose.rot)) > 0.3:
				print("FAIL pose out of range ", id, " ", pose)
				failures += 1
				break
	print("pet_motion_tests: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures > 0 else 0)
