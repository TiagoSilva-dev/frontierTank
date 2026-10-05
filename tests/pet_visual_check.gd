extends SceneTree

# Local screenshots of the Casa dos Mascotes with a disposable in-memory profile:
#   godot --path . --rendering-driver opengl3 --script tests/pet_visual_check.gd -- pets|album
class PreviewApp extends Node:
	var profile: PlayerProfile
	var balance: Dictionary
	var audio: GameAudio
	func do_op(op: String, args: Array) -> Dictionary:
		return profile.apply_op(op, args, balance)

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	root.size = Vector2i(1280, 720)
	var app: PreviewApp = PreviewApp.new()
	app.profile = PlayerProfile.new()
	app.profile.on_save = func() -> void: pass
	app.profile.coins = 123456
	app.balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	app.audio = GameAudio.new()
	app.add_child(app.audio)
	root.add_child(app)
	var roster: Array = [["fenix_dourada", 14, 2], ["leao_dourado", 9, 1], ["leao_dourado", 4, 0], ["raposa_glacial", 12, 0], ["rei_mascara", 20, 3], ["brasinha", 5, 0], ["chacal_ambar", 7, 0], ["lobo_boreal", 30, 5], ["nuvenzinha", 3, 0], ["dragao_tempestade", 1, 0], ["urso_berserker", 8, 1], ["escaravelho_solar", 2, 0], ["pinguim_cristal", 6, 0]]
	for entry: Array in roster:
		var pet: Dictionary = {"uid": app.profile.next_uid, "species": entry[0], "level": entry[1], "xp": 30}
		app.profile.next_uid += 1
		app.profile.pets.append(pet)
		if not app.profile.pet_album.has(entry[0]):
			app.profile.pet_album.append(entry[0])
	app.profile.pet_active = int(app.profile.pets[0].uid)
	var mode: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "pets"
	var host: Control = Control.new()
	host.size = Vector2(1280, 720)
	host.theme = UiKit.make_theme()
	app.add_child(host)
	var screen: PetScreen = PetScreen.open(host, app, "Mascotes" if mode == "pets" else "Álbum")
	if mode == "pets":
		screen.pet_uid = int(app.profile.pets[1].uid)
		screen.build()
	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screens/pets_%s.png" % mode)
	app.queue_free()
	await process_frame
	quit()
