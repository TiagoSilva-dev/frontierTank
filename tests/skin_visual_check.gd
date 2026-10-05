extends SceneTree

# Local screenshots to review the epic skins (docs/SKINS.md, "Padrão de qualidade"). Not part of
# the suite. With a window (WSLg: --rendering-driver opengl3):
#   godot --path . --rendering-driver opengl3 --script tests/skin_visual_check.gd -- <state> [backdrop] [out]
# state: idle | aim | attack | walk | hit | victory | defeat | pow
# backdrop: sky (city) | cave (dark) | snow (light) -- the three the review asks for
# Rows: the standing avatar of each skin and, below, the lying fighter of each (men on the left,
# women on the right) with their living layer (SkinFx).

const SKINS: Array[String] = ["epica_tempestade", "epica_gelo", "epica_magma", "epica_fantasma"]
const BACKDROPS: Dictionary = {"sky": Color("86b4e0"), "cave": Color("2c2338"), "snow": Color("dfe9f2")}

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	root.size = Vector2i(1280, 720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var state: String = args[0] if args.size() > 0 else "idle"
	var backdrop: String = args[1] if args.size() > 1 else "sky"
	var out: String = args[2] if args.size() > 2 else "user://skin_check_%s_%s.png" % [state, backdrop]
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var back: ColorRect = ColorRect.new()
	back.color = BACKDROPS.get(backdrop, BACKDROPS.sky)
	back.size = Vector2(1280, 720)
	root.add_child(back)
	var ground: ColorRect = ColorRect.new()
	ground.color = back.color.darkened(0.35)
	ground.position = Vector2(0, 600)
	ground.size = Vector2(1280, 120)
	root.add_child(ground)
	var fighters: Array[TankFighter] = []
	var column: int = 0
	for gender: String in ["m", "f"]:
		for skin: String in SKINS:
			var look: Dictionary = Armory.look_for(gender, [{"id": skin, "level": 0}])
			var x: float = 110.0 + column * 205.0
			AvatarView.create(root, look, Rect2(x - 100, 40, 200, 230))
			var fighter: TankFighter = TankFighter.new()
			fighter.setup(column, {"name": "%s %s" % [skin, gender], "level": 10, "gender": gender, "look": look}, Armory.weapon_for_entry({"weapon": 0}), balance)
			fighter.position = Vector2(x, 520)
			root.add_child(fighter)
			fighters.append(fighter)
			column += 1
	await process_frame
	await process_frame
	for fighter: TankFighter in fighters:
		fighter.rig.fx_state = "aim" if state == "pow" else state
		match state:
			"pow":
				fighter.skin_pow(3.0)
			"hit":
				fighter.play_clip("hit", 3.0)
				fighter.rig.fx_event("hit")
			"victory":
				fighter.celebrate()
			"defeat":
				fighter.play_clip("defeat", 3.0)
			"attack":
				fighter.rig.fx_event("attack")
				fighter.show_animation(fighter.attack_animation)
			"walk":
				fighter.show_animation(fighter.walk_animation)
	var wait: int = 24 if state == "pow" else 60
	for i in range(wait):
		await process_frame
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png(out)
	print("saved ", out, " ", image.get_size())
	quit()
