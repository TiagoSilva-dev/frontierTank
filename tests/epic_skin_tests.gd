extends SceneTree

# 0.28 (docs/SKINS.md): the first three epic skins, Tempestade Viva, Coroa de Gelo and Coração
# de Magma. Each is one item and one product for both genders (a folder of art per gender), has
# the full set of frames, a living layer of its own (SkinFx), no attributes, and is told apart
# from the others by its silhouette. The season bundle is never sold on top of owned skins.

const SKINS: Array[String] = ["epica_tempestade", "epica_gelo", "epica_magma"]
const CLIP_FRAMES: Dictionary = {"idle": 6, "crawl": 8, "shoot": 6, "hit": 4, "victory": 6, "defeat": 6, "pow": 4}

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func frames_in(folder: String) -> int:
	var count: int = 0
	while ResourceLoader.exists("%s/frame_%02d.png" % [folder, count]):
		count += 1
	return count

# Where the lying body is opaque, as a set of "x,y" cells (to compare silhouettes).
func mask(path: String) -> Dictionary:
	var image: Image = (load(path) as Texture2D).get_image()
	var cells: Dictionary = {}
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).a > 0.3:
				cells[Vector2i(x, y)] = true
	return cells

func overlap(a: Dictionary, b: Dictionary) -> float:
	var both: int = 0
	for key: Variant in a:
		if b.has(key):
			both += 1
	return float(both) / float(maxi(1, a.size() + b.size() - both))

func run_tests() -> void:
	PlayerProfile.path_override = "user://epic_skin_test_profile.json"
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	# --- the items
	for id: String in SKINS:
		var def: Dictionary = Armory.definition(id)
		check(not def.is_empty() and str(def.slot) == "skin" and bool(def.get("premium", false)) and str(def.get("rarity", "")) == "epica", "%s is a premium epic skin" % id)
		check((def.attrs as Dictionary).is_empty() and int(def.price) == 0, "%s has no attributes and is not for gold" % id)
		check(str(def.gender) == "u" and str(def.get("skin_f", "")) != "" and str(def.skin) != str(def.skin_f), "%s has a folder of art for each gender" % id)
		check(str(def.fx) in SkinFx.THEMES, "%s names a living layer that exists" % id)
	# --- the art: 4 directions, the lying body and the 7 clips, anchors without hair dye
	for id: String in SKINS:
		for folder: String in [str(Armory.definition(id).skin), str(Armory.definition(id).skin_f)]:
			var root: String = "res://assets/characters/" + folder
			var directions: bool = ["south", "east", "north", "west"].all(func(d: String) -> bool: return ResourceLoader.exists("%s/%s.png" % [root, d]) and ResourceLoader.exists("%s/prone/%s.png" % [root, d]))
			check(directions, "%s has the four directions standing and lying" % folder)
			var clips_ok: bool = true
			for clip: String in CLIP_FRAMES:
				var count: int = frames_in("%s/prone/%s" % [root, clip])
				clips_ok = clips_ok and count == int(CLIP_FRAMES[clip])
				if count != int(CLIP_FRAMES[clip]):
					push_error("%s/%s has %d frames, wants %d" % [folder, clip, count, CLIP_FRAMES[clip]])
			check(clips_ok, "%s has the seven clips with their frames" % folder)
			var anchors: Dictionary = LookRig.load_anchors(folder)
			check(anchors.has("south") and anchors.has("prone") and anchors.get("hair", ["x"]).is_empty(), "%s has anchors and the hair dye never paints it" % folder)
			var east: Image = (load(root + "/prone/east.png") as Texture2D).get_image()
			var used: Rect2i = east.get_used_rect()
			var head_right: bool = false
			for y in range(used.position.y, used.position.y + used.size.y):
				for x in range(used.position.x + used.size.x * 3 / 4, used.end.x):
					if east.get_pixel(x, y).a > 0.3:
						head_right = true
			check(head_right and used.size.x > used.size.y, "%s lies facing right" % folder)
	# --- the silhouettes: each skin is told apart from the others of its gender
	for gender: String in ["skin", "skin_f"]:
		var masks: Array = []
		for id: String in SKINS:
			masks.append(mask("res://assets/characters/%s/prone/east.png" % Armory.definition(id)[gender]))
		var apart: bool = true
		for i in range(masks.size()):
			for j in range(i + 1, masks.size()):
				apart = apart and overlap(masks[i], masks[j]) < 0.85
		check(apart, "the three lying silhouettes of the %s versions differ" % ("male" if gender == "skin" else "female"))
	# --- the look picks the version of the player's gender and carries the layer
	for id: String in SKINS:
		var def: Dictionary = Armory.definition(id)
		var male: Dictionary = Armory.look_for("m", [{"id": id, "level": 0}])
		var female: Dictionary = Armory.look_for("f", [{"id": id, "level": 0}])
		check(male.skin == def.skin and female.skin == def.skin_f, "%s: him in his folder, her in hers" % id)
		check(male.skin_fx == def.fx and female.skin_fx == def.fx, "%s: the look carries its living layer" % id)
		var clean: Dictionary = Armory.look_for("m", [{"id": id, "level": 0}, {"id": "chapeu_coroa", "level": 0}], true)
		check(clean.skin_fx == def.fx and clean.hat == "", "%s: only the skin hides the hat and keeps the layer" % id)
	check(not Armory.look_for("m", []).has("skin_fx"), "no epic skin, no layer")
	Armory.viewer_gender = "f"
	check(Armory.icon_path({"id": "epica_gelo"}).contains("epica_gelo_f"), "her bag shows her version")
	Armory.viewer_gender = "m"
	check(Armory.icon_path({"id": "epica_gelo"}).contains("epica_gelo_m"), "his bag shows his version")
	# --- wearing one never changes an attribute and works for both genders
	for gender: String in ["m", "f"]:
		var player: PlayerProfile = PlayerProfile.new()
		player.gender = gender
		player.created = true
		var before: Dictionary = player.stats(balance)
		player.add_instance("epica_magma")
		var inst: Dictionary = player.inventory.filter(func(i: Dictionary) -> bool: return i.id == "epica_magma")[0]
		check(player.equip(int(inst.uid)) == "", "a %s player wears the epic skin" % gender)
		check(var_to_str(player.stats(balance)) == var_to_str(before), "a %s player's attributes do not move" % gender)
		check(player.look().skin_fx == "magma" and str(player.entry(balance).look.skin_fx) == "magma", "the battle roster carries the layer (the server builds the same look)")
	var coupon: PlayerProfile = PlayerProfile.new()
	coupon.created = true
	coupon.redeem("TESTARTUDO")
	check(SKINS.all(func(id: String) -> bool: return coupon.has_item(id)), "the test coupon hands out the epic skins")
	# --- the store
	var skus: Dictionary = {"epica_tempestade": "skin_tempestade", "epica_gelo": "skin_gelo", "epica_magma": "skin_magma"}
	var ids: Array = []
	for id: String in skus:
		var entry: Dictionary = PremiumStore.product(str(skus[id]))
		check(PremiumStore.valid(entry) and entry.items == [id] and str(entry.section) == "skins", "%s is a valid product" % skus[id])
		check(int(entry.prices.BRL) == 4490 and int(entry.prices.USD) == 899, "%s costs R$ 44,90 / US$ 8,99" % skus[id])
		check(PremiumStore.kind_label(entry) == Lang.t("ÉPICA"), "%s is tagged epic" % skus[id])
		ids.append(int(entry.steam_item_id))
	var bundle: Dictionary = PremiumStore.product("pacote_temporada_1")
	var sum: int = 0
	for sku: String in skus.values():
		sum += int(PremiumStore.product(sku).prices.BRL)
	check(PremiumStore.valid(bundle) and (bundle.items as Array).size() == 3 and bool(bundle.get("bundle", false)), "the season bundle holds the three skins")
	check(int(bundle.prices.BRL) == 10990 and int(bundle.prices.BRL) < sum, "the bundle is cheaper than the three apart")
	ids.append(int(bundle.steam_item_id))
	var seen: Dictionary = {}
	for entry: Dictionary in PremiumStore.products():
		seen[int(entry.steam_item_id)] = true
	check(seen.size() == PremiumStore.products().size(), "every product has its own Steam item number")
	var owner: PlayerProfile = PlayerProfile.new()
	owner.created = true
	check(not PremiumStore.overlaps(owner, bundle) and not PremiumStore.owns_all(owner, bundle), "a newcomer can buy the bundle")
	owner.add_instance("epica_gelo")
	check(PremiumStore.overlaps(owner, bundle), "with one skin owned the bundle is not sold twice")
	check(not PremiumStore.overlaps(owner, PremiumStore.product("skin_gelo")) and PremiumStore.owns_all(owner, PremiumStore.product("skin_gelo")), "a single skin is never an overlap, only 'owned'")
	check(not PremiumStore.overlaps(owner, PremiumStore.product("passe_cacador")), "a pass never overlaps")
	for entry: Dictionary in PremiumStore.products():
		check(str(entry.get("section", "")) in ["skins", "conveniencias"], "%s sits in a section of the showcase" % entry.sku)
	check(PremiumStore.products()[0].section == "skins", "the skins come first in the showcase")
	# --- the living layer: builds in a rig for each theme and draws without error
	for theme: String in SkinFx.THEMES:
		var host: Node2D = Node2D.new()
		root.add_child(host)
		var rig: LookRig = LookRig.new()
		rig.setup({"skin": "epica_magma_m", "skin_fx": theme, "weapon": "", "weapon_level": 0}, "prone")
		host.add_child(rig)
		check(rig.skin_fx != null and rig.skin_fx.get_parent() == rig, "the %s layer is built by the rig" % theme)
		rig.head_dims = Vector2(36, 34)
		rig.head_center = Vector2(10, -30)
		rig.body_rect = Rect2(-60, -50, 120, 50)
		rig.ground_y = 0.0
		for state: String in ["idle", "walk", "aim", "attack", "victory", "defeat", "pow"]:
			rig.fx_state = state
			rig.fx_event("pow" if state == "pow" else state)
			rig.skin_fx._process(0.2)
			rig.skin_fx.queue_redraw()
		await process_frame
		check(is_instance_valid(rig.skin_fx) and rig.skin_fx.energy() >= 0.0, "the %s layer lives through every state" % theme)
		check(SkinFx.noise(7) == SkinFx.noise(7) and SkinFx.noise(7) != SkinFx.noise(8), "the layer's randomness is a pure function (no global generator)")
		host.queue_free()
	# --- 0.29: alternative colours (a hue turn in the shader, a pick saved in the profile)
	for skin: String in SKINS:
		var colors: Array = Armory.skin_colors_of(skin)
		check(colors.size() == 2, "%s brings two alternative colours" % skin)
		var shifts: Array = colors.map(func(color: Dictionary) -> float: return float(color.shift))
		check(shifts[0] != shifts[1] and not 0.0 in shifts, "%s colours differ from each other and from the original" % skin)
		check(Armory.skin_color_turn(skin, "").is_empty() and Armory.skin_color_turn(skin, "nao_existe").is_empty(), "%s: the original and an unknown colour turn nothing" % skin)
		var turn: Array = Armory.skin_color_turn(skin, str(colors[0].id))
		check(turn.size() == 3 and float(turn[2]) == float(colors[0].shift), "%s: a colour gives [from, range, shift]" % skin)
		var worn: Dictionary = {"id": skin, "quality": "normal", "level": 0}
		var tinted: Dictionary = Armory.look_for("f", [worn], false, {skin: str(colors[0].id)})
		check(tinted.get("recolor", []) == turn and tinted.skin_color == colors[0].id, "%s: the look carries the picked colour" % skin)
		check(not Armory.look_for("m", [worn]).has("recolor") and not Armory.look_for("m", [worn], false, {skin: "nao_existe"}).has("recolor"), "%s: no pick, no turn" % skin)
		check(not Armory.look_for("m", [worn], true, {skin: str(colors[1].id)}).is_empty() and Armory.look_for("m", [worn], true, {skin: str(colors[1].id)}).has("recolor"), "%s: skin only keeps the colour (it is the skin)" % skin)
	var wearer: PlayerProfile = PlayerProfile.new()
	check("skin_color" in PlayerProfile.OPS, "skin_color is a profile operation")
	check(wearer.apply_op("skin_color", ["epica_gelo", "rosa"], {}).error != "", "a skin the player does not own cannot be coloured")
	wearer.equip(int(wearer.add_instance("epica_gelo").uid))
	check(wearer.apply_op("skin_color", ["epica_gelo", "rosa"], {}).error == "" and wearer.look().skin_color == "rosa", "an owned skin takes a colour")
	check(wearer.apply_op("skin_color", ["epica_gelo", "azul_marinho"], {}).error != "" and wearer.skin_colors.epica_gelo == "rosa", "an unknown colour is refused and the pick stays")
	var saved: PlayerProfile = PlayerProfile.new()
	saved.load_data(wearer.to_data())
	check(saved.skin_colors.get("epica_gelo", "") == "rosa" and saved.look().has("recolor"), "the colour survives a save")
	var hand_edited: PlayerProfile = PlayerProfile.new()
	hand_edited.load_data({"version": 11, "gender": "m", "skin_colors": {"epica_gelo": "feio", "nao_skin": "rosa", "epica_magma": "plasma"}})
	check(hand_edited.skin_colors == {"epica_magma": "plasma"}, "a save keeps only the colours the data knows")
	check(wearer.apply_op("skin_color", ["epica_gelo", ""], {}).error == "" and not wearer.skin_colors.has("epica_gelo") and not wearer.look().has("recolor"), "an empty colour goes back to the original")
	# The colour is the hue band of the art itself: it moves the skin's accent and nothing else.
	var south: Image = (load("res://assets/characters/epica_gelo_m/south.png") as Texture2D).get_image()
	var band: Dictionary = Armory.cosmetic_def("epica_gelo").recolor
	var inside: int = 0
	var saturated: int = 0
	for y in range(south.get_height()):
		for x in range(south.get_width()):
			var pixel: Color = south.get_pixel(x, y)
			if pixel.a > 0.5 and pixel.s > 0.3:
				saturated += 1
				if absf(wrapf(pixel.h * 360.0 - float(band.from), -180.0, 180.0)) <= float(band.range):
					inside += 1
	check(inside * 100 >= saturated * 60, "most of the saturated art of Coroa de Gelo sits inside its hue band (%d of %d)" % [inside, saturated])
	# --- the shader takes the band
	var turned: LookRig = LookRig.new()
	turned.setup(Armory.look_for("m", [{"id": "epica_gelo", "quality": "normal", "level": 0}], false, {"epica_gelo": "rosa"}), "south")
	var body: Sprite2D = Sprite2D.new()
	body.texture = load("res://assets/characters/epica_gelo_m/south.png")
	turned.style(body)
	var applied: Vector4 = (body.material as ShaderMaterial).get_shader_parameter("recolor")
	check(is_equal_approx(applied.x, 200.0 / 360.0) and is_equal_approx(applied.z, 120.0 / 360.0) and applied.w == 1.0, "the rig hands the hue band and the turn to the shader")
	turned.setup(Armory.look_for("m", [{"id": "epica_gelo", "quality": "normal", "level": 0}]), "south")
	turned.style(body)
	check((body.material as ShaderMaterial).get_shader_parameter("recolor") == Vector4(), "the original colour turns nothing")
	body.free()
	turned.free()
	var plain: LookRig = LookRig.new()
	plain.setup({"skin": "base_m", "weapon": "", "weapon_level": 0}, "prone")
	check(plain.skin_fx == null, "a plain skin has no layer")
	plain.free()
	print("EPIC SKIN RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
