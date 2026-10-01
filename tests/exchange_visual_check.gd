extends SceneTree
class PreviewApp extends Node:
	var profile: PlayerProfile
	var audio: GameAudio
	func trade(_kind: String, _data: Dictionary = {}) -> Dictionary:
		return {"ok": true, "offers": [{"give_unit": 1, "want_unit": 3, "remaining": 18}, {"give_unit": 2, "want_unit": 7, "remaining": 9}], "competing": [], "orders": [{"id": 42, "give_id": "brasa", "want_id": "estrela", "give_unit": 3, "want_unit": 1, "lots": 20, "remaining": 12, "status": "active"}, {"id": 39, "give_id": "strength_stone_12", "want_id": "solar", "give_unit": 1, "want_unit": 50, "lots": 2, "remaining": 0, "status": "filled"}]}
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	root.size = Vector2i(1280, 720)
	var app: PreviewApp = PreviewApp.new()
	app.profile = PlayerProfile.new()
	app.profile.on_save = func() -> void: pass
	app.profile.redeem("TESTARTUDO")
	app.audio = GameAudio.new()
	app.add_child(app.audio)
	root.add_child(app)
	var screen: ExchangeScreen = ExchangeScreen.new()
	screen.app = app
	screen.theme = UiKit.make_theme()
	app.add_child(screen)
	var mode: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "market"
	if mode == "picker":
		screen.select_asset(true)
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screens/exchange_%s.png" % mode)
	app.queue_free()
	await process_frame
	quit()
