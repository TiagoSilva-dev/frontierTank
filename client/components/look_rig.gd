class_name LookRig
extends Node2D

# Paper-doll layers around a character body. The owner keeps its own body sprite(s)
# and calls follow() whenever the shown texture or frame changes; the rig then places
# the rotating weapon aura, wings, the weapon carried on the back, glasses and hat
# from assets/characters/<skin>/anchors.json, and styles the body with the hair dye /
# clothes aura shader. view = "south" (standing, menus) or "prone" (battle).
# As in DDTank, auras only show outside battles and the weapon is carried on the
# back only during battles.
# Layers behind the body (aura, wings, weapon) live in `back`, which the owner adds
# before its body sprites; the rig itself (hat, glasses, sparkles) goes after them.

const LOOK_SHADER: Shader = preload("res://client/shaders/look.gdshader")

static var _anchor_cache: Dictionary = {}

var look: Dictionary = {}
var view: String = "south"
var anchors: Dictionary = {}
var points: Dictionary = {}
var back: Node2D = Node2D.new()
var aura: AuraRing
# Two separate wings pinned at the shoulder: in front view left/right, lying down near/far.
var wing_a: Sprite2D
var wing_b: Sprite2D
var wing_root: Vector2 = Vector2(100, 100)
var wing_tilt: float = 0.0
var back_weapon: Sprite2D
# Additive copy of the weapon that lights up while a POW is armed (0..1).
var weapon_glow: float = 0.0
var weapon_shine: Sprite2D
var glasses: Sprite2D
var hat: Sprite2D
var glow_color: Color = Color.TRANSPARENT
var time: float = 0.0
var flip: bool = false
var wing_dir: float = 1.0
var body_rect: Rect2 = Rect2()
# Optional: returns {"node": Sprite2D, "offset": Vector2} for the body shown this frame.
var source: Callable

static func load_anchors(skin: String) -> Dictionary:
	if not _anchor_cache.has(skin):
		var path: String = "res://assets/characters/%s/anchors.json" % skin
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
		_anchor_cache[skin] = parsed if parsed is Dictionary else {}
	return _anchor_cache[skin]

func setup(look_data: Dictionary, pose: String) -> void:
	look = look_data
	view = pose
	anchors = load_anchors(str(look.get("skin", "")))
	points = anchors.get("prone" if view == "prone" else "south", {})
	var art_view: String = "side" if view == "prone" else "front"
	var prone: bool = view == "prone"
	var level: int = int(look.get("weapon_level", 0))
	if level > 0 and not prone:
		aura = AuraRing.new()
		back.add_child(aura)
		aura.setup(Armory.aura_color(level), level, 64.0)
	var wing_path: String = Armory.cosmetic_art(str(look.get("wings", "")), "wing")
	if str(look.get("wings", "")) != "" and ResourceLoader.exists(wing_path):
		var root: Array = cosmetic_for("wings").get("root", [100, 100])
		wing_root = Vector2(float(root[0]), float(root[1]))
		# Some wings (the bat wing) hang from the shoulder and are lifted by `tilt`.
		wing_tilt = float(cosmetic_for("wings").get("tilt", 0.0))
		wing_b = make_wing(wing_path)
		wing_a = make_wing(wing_path)
	var weapon_id: String = str(look.get("weapon", ""))
	if weapon_id != "" and prone:
		back_weapon = make_layer(back, Armory.weapon_icon(weapon_id, int(look.get("weapon_level", 0))))
		if back_weapon != null:
			weapon_shine = Sprite2D.new()
			weapon_shine.texture = back_weapon.texture
			weapon_shine.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var additive: CanvasItemMaterial = CanvasItemMaterial.new()
			additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			weapon_shine.material = additive
			weapon_shine.visible = false
			back_weapon.add_child(weapon_shine)
	if str(look.get("glasses", "")) != "":
		glasses = make_layer(self, Armory.cosmetic_art(str(look.glasses), art_view))
	if str(look.get("hat", "")) != "":
		hat = make_layer(self, Armory.cosmetic_art(str(look.hat), art_view))
	glow_color = Color.TRANSPARENT if prone else Armory.aura_color(int(look.get("clothes_level", 0)))

func make_layer(parent: Node2D, path: String) -> Sprite2D:
	if not ResourceLoader.exists(path):
		return null
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.material = UiKit.smooth_material()
	parent.add_child(sprite)
	return sprite

func make_wing(path: String) -> Sprite2D:
	var sprite: Sprite2D = make_layer(back, path)
	sprite.centered = false
	return sprite

func pin_wing(wing: Sprite2D, mirrored: bool, root: Vector2, scale_value: float) -> void:
	# The wing art has its shoulder at `wing_root`; offsets keep that pixel on `root`.
	wing.flip_h = mirrored
	var w: float = wing.texture.get_width()
	wing.offset = -Vector2(w - wing_root.x if mirrored else wing_root.x, wing_root.y)
	wing.position = root
	wing.scale = Vector2(scale_value, scale_value)

func _exit_tree() -> void:
	if is_instance_valid(back) and back.get_parent() == null:
		back.queue_free()

func style(body: Sprite2D, clip: String = "") -> void:
	# Hair dye, clothes glow and crisp scaling on one body sprite (each clip gets its
	# own material).
	var dye: String = str(look.get("hair", ""))
	var hair: Array = anchors.get("hair", [])
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = LOOK_SHADER
	var colors: PackedVector3Array = PackedVector3Array()
	var lo: float = 1.0
	var hi: float = 0.0
	for hex: String in hair.slice(0, 16):
		var c: Color = Color(hex)
		colors.append(Vector3(c.r, c.g, c.b))
		var l: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		lo = minf(lo, l)
		hi = maxf(hi, l)
	while colors.size() < 16:
		colors.append(Vector3(-1, -1, -1))
	material.set_shader_parameter("hair", colors)
	material.set_shader_parameter("hair_count", mini(hair.size(), 16) if dye != "" else 0)
	material.set_shader_parameter("hair_luma", Vector2(lo, hi))
	material.set_shader_parameter("dye", Color(dye) if dye != "" else Color(0, 0, 0, 0))
	material.set_shader_parameter("glow", Color(glow_color.r, glow_color.g, glow_color.b, 1.0) if glow_color.a > 0 else Color(0, 0, 0, 0))
	material.set_shader_parameter("head_rect", head_rect_uv(body.texture, clip))
	body.material = material

func head_rect_uv(texture: Texture2D, clip: String) -> Vector4:
	if points.is_empty() or texture == null:
		return Vector4(0, 0, 1, 1)
	var head: Array = points.head
	var size: Vector2 = texture.get_size()
	var shift: Vector2 = Vector2.ZERO
	var spread: float = 4.0
	var clip_data: Dictionary = anchors.get("clips", {}).get(clip, {})
	if not clip_data.is_empty():
		var offsets: Array = clip_data.offsets
		shift = Vector2(offsets[0][0], offsets[0][1])
		spread = 14.0
	var x0: float = float(head[0]) - float(head[2]) * 0.62 + shift.x - spread
	var x1: float = float(head[0]) + float(head[2]) * 0.62 + shift.x + spread
	var y0: float = float(head[1]) + shift.y - spread
	var y1: float = float(head[1]) + float(head[3]) * (0.8 if view == "prone" else 1.05) + shift.y + spread
	return Vector4(x0 / size.x, y0 / size.y, x1 / size.x, y1 / size.y)

func map_point(body: Sprite2D, point: Vector2) -> Vector2:
	var size: Vector2 = body.texture.get_size()
	var origin: Vector2 = Vector2.ZERO
	if body.region_enabled:
		size = body.region_rect.size
		origin = body.region_rect.position
	var rel: Vector2 = point - origin - size / 2.0
	if body.flip_h:
		rel.x = -rel.x
	return body.position + rel * body.scale

func follow(body: Sprite2D, offset: Vector2 = Vector2.ZERO) -> void:
	if points.is_empty() or body == null or body.texture == null:
		return
	flip = body.flip_h
	var dir: float = -1.0 if flip else 1.0
	var k: float = body.scale.x
	var head: Array = points.head
	var head_w: float = float(head[2]) * k
	var head_h: float = float(head[3]) * k
	var top: Vector2 = map_point(body, Vector2(head[0], head[1]) + offset)
	var eyes: Vector2 = map_point(body, Vector2(points.eyes[0], points.eyes[1]) + offset)
	var back: Vector2 = map_point(body, Vector2(points.back[0], points.back[1]) + offset)
	var bottom: float = map_point(body, Vector2(0, float(points.bottom)) + offset).y
	var prone: bool = view == "prone"
	if hat != null:
		var def: Dictionary = cosmetic_for("hat")
		var width: float = head_w * float(def.get("scale", 1.0 if not prone else 0.86))
		var s: float = width / hat.texture.get_width()
		hat.scale = Vector2(s, s)
		hat.flip_h = flip
		var sink: float = float(def.get("sink", 0.34 if not prone else 0.24))
		hat.position = top + Vector2(-dir * head_w * (0.04 if prone else 0.0), head_h * sink - hat.texture.get_height() * s / 2.0)
	if glasses != null:
		var width: float = head_w * (0.74 if not prone else 0.42)
		var s: float = width / glasses.texture.get_width()
		glasses.scale = Vector2(s, s)
		glasses.flip_h = flip
		glasses.position = eyes + Vector2(dir * head_w * (0.06 if prone else 0.0), -head_h * (0.08 if prone else 0.0))
	if wing_a != null:
		wing_dir = dir
		if prone:
			# Lying down: both wings rise from the back; the far one sits a little
			# forward, higher and darker.
			var s: float = head_w * 1.05 / wing_root.x
			pin_wing(wing_a, flip, back + Vector2(-dir * head_w * 0.12, -head_w * 0.04), s)
			pin_wing(wing_b, flip, back + Vector2(dir * head_w * 0.12, -head_w * 0.1), s * 0.9)
			wing_b.modulate = Color(0.72, 0.72, 0.8)
		else:
			var s: float = head_w * 1.2 / wing_root.x
			var shoulder: Vector2 = back + Vector2(0, -head_h * 0.3)
			pin_wing(wing_a, false, shoulder + Vector2(-head_w * 0.1, 0), s)
			pin_wing(wing_b, true, shoulder + Vector2(head_w * 0.1, 0), s)
	if back_weapon != null:
		# In battle the weapon is drawn bigger (0.8: `back_weapon_scale`); it is only art,
		# the hitbox stays the fighter's hit_radius. The extra size grows away from the
		# head so it never covers the face or the name plate below the fighter.
		var grow: float = Armory.visual("back_weapon_scale") if prone else 1.0
		var size: float = head_w * (1.15 if not prone else 0.95) * grow
		var s: float = size / maxf(back_weapon.texture.get_width(), back_weapon.texture.get_height())
		back_weapon.scale = Vector2(s, s)
		back_weapon.flip_h = flip
		back_weapon.rotation = -dir * 0.35
		# Along the back, behind the wings' shoulders.
		back_weapon.position = back + Vector2(-dir * head_w * (0.85 + (grow - 1.0) * 0.3), -head_w * (0.12 + (grow - 1.0) * 0.9))
		if weapon_shine != null:
			weapon_shine.flip_h = flip
			weapon_shine.visible = weapon_glow > 0.0
			weapon_shine.scale = Vector2.ONE * (1.08 + 0.06 * sin(time * 12.0))
			weapon_shine.modulate = Color(1.0, 0.9, 0.55, weapon_glow * (0.65 + 0.35 * sin(time * 9.0)))
	body_rect = Rect2(Vector2(top.x - head_w, top.y), Vector2(head_w * 2.0, bottom - top.y))
	if aura != null:
		# Like the DDTank profile: the circle sits behind the head and shoulders.
		var diameter: float = head_w * 2.5
		aura.scale = Vector2.ONE * diameter / AuraRing.SIZE
		aura.position = Vector2(top.x, top.y + head_h * 0.62)
	queue_redraw()

func cosmetic_for(key: String) -> Dictionary:
	var art: String = str(look.get(key, ""))
	for def: Dictionary in Armory.data().cosmetics:
		if def.get("art", "") == art:
			return def
	return {}

func _process(delta: float) -> void:
	time += delta
	if source.is_valid():
		var shown: Dictionary = source.call()
		if not shown.is_empty():
			follow(shown.node, shown.offset)
	if wing_a != null:
		# Flapping: each wing turns around its shoulder, the two in opposite directions.
		var flap: float = 0.13 * sin(time * 3.4) - 0.03
		var lift: float = flap + wing_tilt
		if view == "prone":
			wing_a.rotation = wing_dir * lift
			wing_b.rotation = wing_dir * (lift * 0.8 + 0.28)
		else:
			wing_a.rotation = lift
			wing_b.rotation = -lift
	if glow_color.a > 0.0:
		queue_redraw()

func _draw() -> void:
	# Clothes aura: sparks and soft orbs spiralling up around the character.
	if glow_color.a <= 0.0 or body_rect.size.y <= 0:
		return
	var light: Color = glow_color.lightened(0.6)
	var center_x: float = body_rect.position.x + body_rect.size.x / 2.0
	for i in range(14):
		var phase: float = fposmod(time * 0.38 + i * 0.0714, 1.0)
		var side: float = sin(phase * TAU * 1.5 + i * 2.4)
		var x: float = center_x + side * body_rect.size.x * (0.42 + 0.12 * fposmod(i * 0.37, 1.0))
		var y: float = body_rect.end.y - phase * body_rect.size.y * 1.05
		var fade: float = sin(phase * PI)
		var size: float = 3.5 + 4.0 * fposmod(i * 0.61, 1.0) + 1.5 * sin(time * 5.0 + i)
		if i % 3 == 0:
			draw_circle(Vector2(x, y), size * 1.3, Color(glow_color.r, glow_color.g, glow_color.b, 0.35 * fade))
			draw_circle(Vector2(x, y), size * 0.6, Color(light.r, light.g, light.b, 0.8 * fade))
		else:
			var c: Color = Color(light.r, light.g, light.b, 0.9 * fade)
			draw_colored_polygon(PackedVector2Array([Vector2(x, y - size), Vector2(x + size * 0.25, y), Vector2(x, y + size), Vector2(x - size * 0.25, y)]), c)
			draw_colored_polygon(PackedVector2Array([Vector2(x - size, y), Vector2(x, y + size * 0.25), Vector2(x + size, y), Vector2(x, y - size * 0.25)]), c)
