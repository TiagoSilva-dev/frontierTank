extends SceneTree

# Contact sheet of the hats and glasses worn by several bodies, drawn by the real LookRig,
# to tune assets/cosmetics/fit.json by eye.
#
#   godot --path . --rendering-driver opengl3 --script tools/cosmetic_sheet.gd -- \
#     --set=hats|glasses|mixed|pve_hats|pve_glasses --view=front|prone --scale=2 --out=sheet.png [--bodies=base_m,lani]
#
# Rows are bodies, columns the pieces of headwear (the first column is bare, for reference).

var args: Dictionary = {}

const HATS: Array[String] = ["", "chapeu_kabuto", "chapeu_cartola", "chapeu_coroa", "chapeu_coelho", "chapeu_pirata", "chapeu_viking"]
const GLASSES: Array[String] = ["", "oculos_escuros", "oculos_redondos", "oculos_coracao", "oculos_heroi"]
# The PvE gear (0.31): four rarities of each, Comum to Lendário.
const PVE_HATS: Array[String] = ["", "chapeu_couro", "chapeu_aco_azul", "chapeu_arcano", "chapeu_dragao"]
const PVE_GLASSES: Array[String] = ["", "oculos_aviador", "oculos_cristal", "oculos_arcano", "oculos_dragao"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1]
	call_deferred("run")

func run() -> void:
	var main: Node = (load("res://client/scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	var kind: String = str(args.get("set", "hats"))
	var view: String = str(args.get("view", "front"))
	var zoom: float = float(args.get("scale", "2"))
	var bodies: PackedStringArray = str(args.get("bodies", "base_m,lani,bot_ruivo")).split(",")
	var columns: Array = []
	match kind:
		"hats":
			for hat: String in HATS:
				columns.append({"hat": hat, "glasses": ""})
		"glasses":
			for glasses: String in GLASSES:
				columns.append({"hat": "", "glasses": glasses})
		"pve_hats":
			for hat: String in PVE_HATS:
				columns.append({"hat": hat, "glasses": ""})
		"pve_glasses":
			for glasses: String in PVE_GLASSES:
				columns.append({"hat": "", "glasses": glasses})
		_:
			for hat: String in HATS.slice(1):
				columns.append({"hat": hat, "glasses": GLASSES[1 + columns.size() % (GLASSES.size() - 1)]})
	var sheet: Control = Control.new()
	sheet.size = Vector2(1280, 720)
	main.ui.add_child(sheet)
	var back: ColorRect = ColorRect.new()
	back.color = Color("3a4a78")
	back.size = Vector2(1280, 720)
	sheet.add_child(back)
	var cell: Vector2 = Vector2(1280.0 / columns.size(), 720.0 / bodies.size())
	for row in range(bodies.size()):
		for col in range(columns.size()):
			var skin: String = bodies[row]
			var look: Dictionary = Armory.look_for("f" if skin in ["lani", "bot_maga", "roupa_princesa"] else "m", [])
			look.skin = skin
			look.hat = columns[col].hat
			look.glasses = columns[col].glasses
			look.weapon = ""
			var at: Vector2 = Vector2(col * cell.x, row * cell.y)
			if view == "prone":
				draw_prone(sheet, look, Rect2(at, cell), zoom)
			else:
				var avatar: AvatarView = AvatarView.new()
				avatar.pixel_scale = zoom
				avatar.position = at
				avatar.size = cell
				sheet.add_child(avatar)
				avatar.show_look(look)
	for i in range(4):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(str(args.get("out", "sheet.png")))
	main.queue_free()
	await create_timer(0.3).timeout
	quit()

func draw_prone(parent: Control, look: Dictionary, rect: Rect2, zoom: float) -> void:
	var path: String = "res://assets/characters/%s/prone/east.png" % look.skin
	if not ResourceLoader.exists(path):
		return
	var stage: Node2D = Node2D.new()
	stage.position = rect.position
	parent.add_child(stage)
	var body: Sprite2D = Sprite2D.new()
	body.texture = load(path)
	body.scale = Vector2(zoom, zoom)
	body.position = rect.size / 2.0
	var rig: LookRig = LookRig.new()
	rig.setup(look, "prone")
	stage.add_child(rig.back)
	stage.add_child(body)
	stage.add_child(rig)
	rig.style(body)
	rig.follow(body)
