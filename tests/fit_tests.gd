extends SceneTree

# Hats and glasses are worn, not stuck on (0.18): assets/cosmetics/fit.json says which part of
# each art is worn and where it rests; LookRig places it from the skin's head anchors. These
# checks run the real rig over several bodies in both views and test the geometry: a hat touches
# the head and is centred on it, glasses sit on the eye line, nothing is wider than a few heads.

var errors: int = 0
var checks: int = 0
const SKINS: Array[String] = ["base_m", "lani", "bot_ruivo", "roupa_samurai", "roupa_princesa", "roupa_capitao"]

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		errors += 1
		push_error(message)

func worn_rig(skin: String, view: String, hat: String, glasses: String, flipped: bool = false) -> Dictionary:
	var look: Dictionary = {"skin": skin, "hair": "", "hat": hat, "glasses": glasses, "wings": "", "weapon": "", "weapon_level": 0, "clothes_level": 0}
	var holder: Node2D = Node2D.new()
	root.add_child(holder)
	var body: Sprite2D = Sprite2D.new()
	body.texture = load("res://assets/characters/%s/%s.png" % [skin, "prone/east" if view == "prone" else "south"])
	body.scale = Vector2(2, 2)
	body.flip_h = flipped
	holder.add_child(body)
	var rig: LookRig = LookRig.new()
	rig.setup(look, view)
	holder.add_child(rig.back)
	holder.add_child(rig)
	rig.follow(body)
	var head: Array = rig.points.head
	var eyes: Vector2 = rig.map_point(body, Vector2(rig.points.eyes[0], rig.points.eyes[1]))
	var top: Vector2 = rig.map_point(body, Vector2(head[0], head[1]))
	return {"holder": holder, "rig": rig, "head_w": float(head[2]) * 2.0, "head_h": float(head[3]) * 2.0, "top": top, "eyes": eyes}

# The rectangle a worn sprite covers on screen.
func covered(sprite: Sprite2D) -> Rect2:
	var size: Vector2 = sprite.region_rect.size * sprite.scale
	return Rect2(sprite.position - size / 2.0, size)

func run_tests() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LookRig.FIT_PATH))
	check(data is Dictionary, "assets/cosmetics/fit.json loads")
	var hats: Array[String] = []
	var glasses: Array[String] = []
	for def: Dictionary in Armory.data().cosmetics:
		if def.slot == "chapeu":
			hats.append(str(def.art))
		elif def.slot == "oculos":
			glasses.append(str(def.art))
	check(hats.size() >= 6 and glasses.size() >= 4, "the game has hats and glasses to fit")
	for art in hats + glasses:
		for view: String in ["front", "side"]:
			var entry: Dictionary = (data as Dictionary).get(art, {}).get(view, {})
			var texture: Texture2D = load(Armory.cosmetic_art(art, view))
			var crop: Array = entry.get("crop", [0, 0, texture.get_width(), texture.get_height()])
			var inside: bool = crop[0] >= 0 and crop[1] >= 0 and crop[0] + crop[2] <= texture.get_width() and crop[1] + crop[3] <= texture.get_height() and crop[2] > 4 and crop[3] > 4
			check(not entry.is_empty() and inside, "%s (%s) has a fit with a crop inside its art" % [art, view])
	for view: String in ["front", "prone"]:
		for skin in SKINS:
			if not ResourceLoader.exists("res://assets/characters/%s/%s.png" % [skin, "prone/east" if view == "prone" else "south"]):
				continue
			for hat in hats:
				var w: Dictionary = worn_rig(skin, view, hat, "")
				var rig: LookRig = w.rig
				var box: Rect2 = covered(rig.hat)
				var head_center_x: float = float(w.top.x)
				var off_center: float = absf(box.get_center().x - head_center_x) / float(w.head_w)
				var bottom_in_head: float = (box.end.y - float(w.top.y)) / float(w.head_h)
				var ok: bool = off_center < 0.2 and bottom_in_head > 0.12 and bottom_in_head < 0.62 and box.size.x < float(w.head_w) * 2.0 and box.size.x > float(w.head_w) * 0.5
				check(ok, "%s on %s (%s): centred (%.2f), rests %.2f down the head, %.2f heads wide" % [hat, skin, view, off_center, bottom_in_head, box.size.x / float(w.head_w)])
				w.holder.queue_free()
			for pair in glasses:
				var w: Dictionary = worn_rig(skin, view, "", pair)
				var rig: LookRig = w.rig
				var box: Rect2 = covered(rig.glasses)
				var dy: float = absf(box.get_center().y - float(w.eyes.y)) / float(w.head_h)
				var inside_head: bool = box.size.x < float(w.head_w) * 0.95 and box.size.x > float(w.head_w) * 0.25
				check(dy < 0.12 and inside_head, "%s on %s (%s): on the eye line (%.2f), %.2f heads wide" % [pair, skin, view, dy, box.size.x / float(w.head_w)])
				w.holder.queue_free()
	# Facing left mirrors the placement.
	var right: Dictionary = worn_rig("base_m", "prone", "chapeu_viking", "oculos_escuros", false)
	var left: Dictionary = worn_rig("base_m", "prone", "chapeu_viking", "oculos_escuros", true)
	var r_hat: Rect2 = covered(right.rig.hat)
	var l_hat: Rect2 = covered(left.rig.hat)
	check(left.rig.hat.flip_h and not right.rig.hat.flip_h and right.rig.glasses.flip_h == false and left.rig.glasses.flip_h, "facing left flips the worn art")
	check(absf(r_hat.size.x - l_hat.size.x) < 0.01 and absf(r_hat.position.y - l_hat.position.y) < 0.01, "the worn hat is the same size and height either way")
	check(float(right.rig.glasses.position.x) > float(right.rig.hat.position.x) and float(left.rig.glasses.position.x) < float(left.rig.hat.position.x), "the glasses sit towards the face, whichever way it looks")
	# Defaults for art without a fit entry (a new hat before it is tuned).
	var plain: Dictionary = LookRig.fit_for("chapeu_inexistente", "front", false, load(Armory.cosmetic_art("chapeu_cartola", "front")))
	check(plain.crop.size.x > 0 and float(plain.width) > 0.0 and float(plain.span) > 0.0, "a hat without a fit entry still gets a sane default")
	print("FIT RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)
