extends SceneTree

# Local screenshots of the Caçada dos Mascotes with a disposable in-memory profile:
#   godot --path . --rendering-driver opengl3 --script tests/hunt_visual_check.gd -- fight|boss|picker|report|capture|idle
#   ... -- field|fieldboss [zone]     six moments of the top-down field (sol by default)
class SteamStub:
	extends RefCounted
	var available: bool = false

class PreviewApp extends Node:
	var profile: PlayerProfile
	var balance: Dictionary
	var audio: GameAudio
	var online: bool = false
	var steam: SteamStub = SteamStub.new()
	func do_op(op: String, args: Array) -> Dictionary:
		return profile.apply_op(op, args, balance)
	func buy_premium(_sku: String) -> String:
		return ""

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	root.size = Vector2i(1280, 720)
	var mode: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "fight"
	var app: PreviewApp = PreviewApp.new()
	app.profile = PlayerProfile.new()
	app.profile.on_save = func() -> void: pass
	app.profile.coins = 123456
	app.profile.hunt_clock = 2000000
	app.balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	app.audio = GameAudio.new()
	app.add_child(app.audio)
	root.add_child(app)
	var roster: Array = [["fenix_dourada", 14, 2], ["leao_dourado", 9, 1], ["pinguim_cristal", 12, 0], ["raposa_glacial", 12, 0], ["rei_mascara", 20, 3], ["brasinha", 5, 0], ["chacal_ambar", 7, 0], ["lobo_boreal", 30, 5], ["nuvenzinha", 3, 0], ["dragao_tempestade", 1, 0], ["urso_berserker", 8, 1], ["escaravelho_solar", 2, 0]]
	for entry: Array in roster:
		app.profile.grant_pet(entry[0])
		var pet: Dictionary = app.profile.pets[app.profile.pets.size() - 1]
		pet.level = entry[1]
	app.profile.add_instance(str(PetHunt.rules().pass_item))
	var host: Control = Control.new()
	host.size = Vector2(1280, 720)
	host.theme = UiKit.make_theme()
	app.add_child(host)
	var screen: PetScreen = PetScreen.open(host, app, "Caçada")
	await process_frame
	var tab: HuntTab = screen.hunt_tab
	var pets: Array = app.profile.pets
	var field_zone: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "sol"
	tab.zone = {"fight": "ceu", "boss": "mascara", "capture": "gelo", "field": field_zone, "fieldboss": field_zone}.get(mode, "gelo")
	tab.team = [int(pets[0].uid), int(pets[1].uid), int(pets[2].uid), int(pets[3].uid), int(pets[4].uid)]
	if mode in ["field", "fieldboss"]:
		tab.team = [int(pets[0].uid), int(pets[1].uid), int(pets[6].uid), int(pets[11].uid), int(pets[5].uid)]
		# Indices into `roster` above, so each zone shows its own look next to other elements.
		var teams: Dictionary = {"gelo": [2, 3, 7, 6, 5], "mascara": [4, 5, 2, 7, 9], "ceu": [8, 9, 0, 10, 4], "viking": [10, 7, 1, 8, 6]}
		if teams.has(field_zone):
			tab.team = (teams[field_zone] as Array).map(func(index: int) -> int: return int(pets[index].uid))
	if mode != "idle":
		app.profile.hunt_set(tab.zone, 1, tab.team)
		app.profile.hunt.since = app.profile.hunt_now() - 12 * 40 - (3 if mode == "boss" else (0 if mode in ["field", "fieldboss"] else 5))
		if mode in ["boss", "fieldboss"]:
			# A seed whose current encounter is the Lendário boss.
			app.profile.hunt.since = app.profile.hunt_now() - 3
			for candidate in range(2, 400000):
				if PetHunt.slot_rng({"seed": candidate}, int(app.profile.hunt.n)).randf() < float(PetHunt.rules().boss.chance):
					app.profile.hunt.seed = candidate
					break
		tab.rebuild()
	else:
		tab.rebuild()
	match mode:
		"picker":
			tab.open_picker()
		"report":
			var before: int = int(app.profile.hunt.report.at)
			app.profile.hunt.since = app.profile.hunt_now() - 7200
			app.profile.hunt_collect()
			var born: Array[Dictionary] = []
			tab.show_report(app.profile.hunt.report, born)
	var frames: int = 300 if mode in ["fight"] else 40
	if mode in ["field", "fieldboss"]:
		# Six moments of the same encounter (seconds into it).
		var moments: Array = [1.5, 3.0, 4.6, 5.3, 6.2, 8.0]
		for shot in range(moments.size()):
			var field: HuntArena = tab.arena
			while field.t < float(moments[shot]):
				await process_frame
			await RenderingServer.frame_post_draw
			print("shot ", shot, " t=", snappedf(field.t, 0.01), " steps=", field.steps.size(), " applied=", field.applied, " foes=", field.foes.size())
			root.get_texture().get_image().save_png("res://docs/screens/hunt_%s%s_%d.png" % [mode, "" if field_zone == "sol" else "_" + field_zone, shot])
		app.queue_free()
		await process_frame
		quit()
		return
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screens/hunt_%s.png" % mode)
	app.queue_free()
	await process_frame
	quit()
