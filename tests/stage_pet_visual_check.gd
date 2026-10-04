extends SceneTree

# Screenshots of the Mochila stage with an animated pet (not part of the suite).

func _init() -> void:
	var holder: Control = Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	var x: float = 20.0
	for species: String in ["lobo_boreal", "dragao_tempestade", "urso_berserker"]:
		var stage: HeroStage = HeroStage.create(holder, Rect2(x, 150, 412, 326), {"pet": species})
		x += 420.0
	await create_timer(1.4).timeout
	root.get_texture().get_image().save_png("res://docs/screens/stage_pet.png")
	quit()
