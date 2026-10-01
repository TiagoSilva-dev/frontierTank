class_name AvatarView
extends Control

# Standing character with everything equipped (Sala, Salão, Mochila, cidade): the
# outfit sprite plus the LookRig layers — weapon aura behind, wings, the weapon on
# the back, glasses, hat, hair dye and the clothes aura glow.

var look: Dictionary = {}
# Fixed art scale (the POW cut-in draws the avatar at 1x and enlarges it); 0 = fit.
var pixel_scale: float = 0.0
var body: Sprite2D
var rig: LookRig

static func create(parent: Node, look_data: Dictionary, rect: Rect2) -> AvatarView:
	var view: AvatarView = AvatarView.new()
	view.position = rect.position
	view.size = rect.size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)
	view.show_look(look_data)
	return view

func show_look(look_data: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	look = look_data
	var path: String = Armory.skin_path(str(look.get("skin", "base_m")))
	if not ResourceLoader.exists(path):
		return
	var stage: Node2D = Node2D.new()
	add_child(stage)
	body = Sprite2D.new()
	body.texture = load(path)
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var used: Rect2i = body.texture.get_image().get_used_rect()
	var tex: Vector2 = body.texture.get_size()
	# Leave room above for hats and around for wings.
	var k: float = minf(size.y * 0.8 / used.size.y, size.x * 0.62 / used.size.x)
	k = maxf(0.5, floorf(k * 4.0) / 4.0) if k >= 1.0 else k
	if pixel_scale > 0.0:
		k = pixel_scale
	body.scale = Vector2(k, k)
	body.position = Vector2(size.x / 2.0 - (used.get_center().x - tex.x / 2.0) * k, size.y * 0.97 - (used.end.y - tex.y / 2.0) * k)
	rig = LookRig.new()
	rig.setup(look, "south")
	stage.add_child(rig.back)
	stage.add_child(body)
	stage.add_child(rig)
	rig.style(body)
	rig.follow(body)

# The Founder entrance (docs/FOUNDER_PACK.md, item 18, 1.4 s): the halo opens, solar
# particles rise, the character drops in and lands, the wings fold shut. Once per session
# (the caller decides), and only for the full Founder set.
func play_entrance(app: Node) -> void:
	if body == null or rig == null or not is_instance_valid(body):
		return
	var rest: Vector2 = body.position
	rig.source = func() -> Dictionary: return {"node": body, "offset": Vector2.ZERO}
	body.position = rest + Vector2(0, -size.y * 0.5)
	body.modulate.a = 0.0
	rig.wing_open = 1.0
	if rig.founder_fx != null:
		rig.founder_fx.play_entrance(0.9)
	var feet: Vector2 = Vector2(rest.x, rest.y + body.texture.get_height() * 0.3)
	FxParticles.burst(self, Vector2(size.x / 2.0, size.y * 0.5), {"amount": 36, "lifetime": 1.0, "speed": [20.0, 90.0], "direction": Vector2.UP, "spread": 180.0, "gravity": Vector2(0, -30), "size": [2.0, 4.0], "colors": ["ffffff", "fff0a8", "ffd25a"], "radius": size.x * 0.2, "z": 5})
	var tween: Tween = create_tween()
	tween.tween_property(body, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(body, "position", rest, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		FxParticles.burst(self, Vector2(size.x / 2.0, size.y * 0.95), {"amount": 22, "lifetime": 0.5, "speed": [40.0, 130.0], "direction": Vector2.UP, "spread": 80.0, "gravity": Vector2(0, 220), "size": [2.0, 4.0], "colors": ["fff0a8", "ffd25a", "f0a62c"], "box": Vector2(size.x * 0.2, 3), "z": 5})
		if is_instance_valid(app) and is_instance_valid(app.audio):
			app.audio.play("founder_reveal", -3.0))
	tween.tween_property(body, "position:y", rest.y - 7.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(body, "position:y", rest.y, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: rig.source = Callable())
