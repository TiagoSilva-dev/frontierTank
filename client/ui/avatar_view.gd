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
