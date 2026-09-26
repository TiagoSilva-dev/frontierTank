class_name HeroStage
extends Control

# The character's showcase in the Mochila (0.15): a night-blue backdrop with a spotlight
# and twinkling lights, the PixelLab pedestal, and the character standing on it with
# everything equipped (AvatarView). Items dropped here are equipped (`dropped`).

signal dropped(data: Dictionary)

const PEDESTAL: String = "res://assets/ui/profile/pedestal.png"
# The pedestal art (200x88) is drawn 1.25x; its top face's centre is 22 px below the top.
const PEDESTAL_SCALE: float = 1.25
const PEDESTAL_TOP: float = 22.0

var look: Dictionary = {}
var avatar: AvatarView
var time: float = 0.0
var stars: Array[Dictionary] = []
var drop_hover: bool = false
var accepts: Callable = Callable()

static func create(parent: Node, rect: Rect2, look_data: Dictionary) -> HeroStage:
	var stage: HeroStage = HeroStage.new()
	stage.position = rect.position
	stage.size = rect.size
	stage.look = look_data
	parent.add_child(stage)
	return stage

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1507
	for i in range(34):
		stars.append({"pos": Vector2(rng.randf_range(8, size.x - 8), rng.randf_range(6, size.y * 0.7)), "phase": rng.randf() * TAU, "speed": rng.randf_range(1.2, 3.0), "size": rng.randi_range(1, 2) * 2.0})
	var pedestal: TextureRect = UiKit.art(self, PEDESTAL, pedestal_rect(), false)
	pedestal.name = "Pedestal"
	# The character's feet on the pedestal's top face.
	var feet: float = pedestal_rect().position.y + PEDESTAL_TOP * PEDESTAL_SCALE
	avatar = AvatarView.new()
	avatar.name = "Avatar"
	avatar.pixel_scale = 2.0
	avatar.size = Vector2(size.x, feet / 0.97)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(avatar)
	avatar.show_look(look)

func pedestal_rect() -> Rect2:
	var art: Vector2 = Vector2(200, 88) * PEDESTAL_SCALE
	return Rect2(Vector2(roundf((size.x - art.x) / 2.0), size.y - art.y + 14.0), art)

func _process(delta: float) -> void:
	time += delta
	queue_redraw()
	if drop_hover and not get_global_rect().has_point(get_global_mouse_position()):
		drop_hover = false

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	drop_hover = data is Dictionary and (data as Dictionary).has("bag_key") and accepts.is_valid() and bool(accepts.call(data))
	return drop_hover

func _drop_data(_at: Vector2, data: Variant) -> void:
	drop_hover = false
	dropped.emit(data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_hover = false

func _draw() -> void:
	# Backdrop: deep blue at the top to violet near the floor.
	var top: Color = Color("141a3a")
	var mid: Color = Color("2b1f4f")
	var low: Color = Color("3a1d44")
	var w: float = size.x
	var h: float = size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.55), Vector2(0, h * 0.55)]), PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0, h)]), PackedColorArray([mid, mid, low, low]))
	# Spotlight from above onto the pedestal, breathing slowly.
	var breath: float = 0.85 + 0.15 * sin(time * 1.3)
	var cx: float = w / 2.0
	var floor_y: float = pedestal_rect().position.y + PEDESTAL_TOP * PEDESTAL_SCALE
	for i in range(3):
		var spread: float = 70.0 + i * 38.0
		var light: Color = Color(1.0, 0.86, 0.55, (0.1 - i * 0.025) * breath)
		var none: Color = Color(light.r, light.g, light.b, 0.0)
		draw_polygon(PackedVector2Array([Vector2(cx - 26 - i * 10, 0), Vector2(cx + 26 + i * 10, 0), Vector2(cx + spread, floor_y), Vector2(cx - spread, floor_y)]), PackedColorArray([light, light, none, none]))
	# Soft glow on the floor behind the pedestal.
	for i in range(5):
		draw_set_transform(Vector2(cx, floor_y + 20), 0.0, Vector2(1.0, 0.32))
		draw_circle(Vector2.ZERO, 200.0 - i * 30.0, Color(0.55, 0.4, 1.0, 0.05 + i * 0.02))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Twinkling lights.
	for star: Dictionary in stars:
		var glow: float = 0.5 + 0.5 * sin(time * float(star.speed) + float(star.phase))
		var s: float = float(star.size)
		var p: Vector2 = (star.pos as Vector2).round()
		var c: Color = Color(1.0, 0.9, 0.6, 0.25 + 0.6 * glow)
		draw_rect(Rect2(p, Vector2(s, s)), c)
		if glow > 0.85 and s > 2.0:
			draw_rect(Rect2(p + Vector2(-s, s / 2.0 - 1.0), Vector2(s * 3.0, 2.0)), Color(c.r, c.g, c.b, 0.5))
			draw_rect(Rect2(p + Vector2(s / 2.0 - 1.0, -s), Vector2(2.0, s * 3.0)), Color(c.r, c.g, c.b, 0.5))
	# Frame shadow on the edges (the stage sits inside the paper panel).
	var edge: Color = Color(0, 0, 0, 0.35)
	var none_edge: Color = Color(0, 0, 0, 0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(18, 0), Vector2(18, h), Vector2(0, h)]), PackedColorArray([edge, none_edge, none_edge, edge]))
	draw_polygon(PackedVector2Array([Vector2(w - 18, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - 18, h)]), PackedColorArray([none_edge, edge, edge, none_edge]))
	if drop_hover:
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(1, 1, 1, 0.5), false, 3.0)
