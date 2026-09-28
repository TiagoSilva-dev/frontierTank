extends SceneTree

# Local screenshots with a disposable in-memory profile; never loads a real save.
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
	app.balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	app.audio = GameAudio.new()
	app.add_child(app.audio)
	root.add_child(app)
	app.profile.redeem("TESTARTUDO")
	var weapon: Dictionary = app.profile.add_instance("trovao", "verdadeira", 8)
	var smith: SmithScreen = SmithScreen.new()
	smith.app = app
	smith.selected_uid = int(weapon.uid)
	app.add_child(smith)
	var mode: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "smith"
	if mode in ["success", "failure"]:
		var fx: ForgeOutcome = ForgeOutcome.new()
		fx.item = weapon.duplicate(true)
		fx.item.level = 9 if mode == "success" else 8
		fx.success = mode == "success"
		fx.audio = app.audio
		smith.add_child(fx)
		fx.set_process(false)
		fx.age = 1.5
		fx.queue_redraw()
	elif mode == "transfer":
		smith.select_tab("Transferência")
	elif mode == "currencies":
		smith.select_tab("Moedas")
	elif mode == "empty":
		app.profile.items.clear()
		smith.build()
	elif mode == "max":
		weapon.level = 12
		smith.build()
	for i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screens/forge_%s.png" % mode)
	app.queue_free()
	await process_frame
	quit()
