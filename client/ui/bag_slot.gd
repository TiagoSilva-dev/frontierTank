class_name BagSlot
extends Control

# One cell of the Mochila (0.15), also used for the equipment slots and the tooltip's
# icon. The item's quality shows as a soft glow behind it instead of a coloured square;
# strengthening (+12), stack counts and map levels sit in the corners; gold corner
# brackets mark the selected item and the frame lights up under the mouse. Cells can
# be dragged onto each other: the owner decides what a drop means (`accepts`,
# `dropped`). Click selects, double click or right click equips (`activated`).

signal clicked(slot: BagSlot)
signal activated(slot: BagSlot)
signal hovered(slot: BagSlot, inside: bool)
signal dropped(slot: BagSlot, data: Dictionary)

const SILHOUETTE: Shader = preload("res://client/shaders/silhouette.gdshader")

var key: String = ""
var cell: int = -1
var equip_slot: String = ""
var icon: Texture2D
var icon_tint: Color = Color.WHITE
var rarity: Color = Color.TRANSPARENT
var shimmer: bool = false
var level: int = 0
var count: int = 0
var corner_text: String = ""
var corner_color: Color = Color.WHITE
var equipped: bool = false
var selected: bool = false
var ghost: Texture2D
var caption: String = ""
var interactive: bool = true
var accepts: Callable = Callable()
var hover: bool = false
var drop_hover: bool = false
var dragging: bool = false
var time: float = 0.0
var picture: TextureRect
# Numbers, badges and brackets go on a child drawn above the item's picture.
var overlay: Control

static func create(parent: Node, rect: Rect2) -> BagSlot:
	var slot: BagSlot = BagSlot.new()
	slot.position = rect.position
	slot.size = rect.size
	parent.add_child(slot)
	return slot

# Fills the cell from an entry of CharacterScreen.entries() (or {} for an empty cell).
func show_entry(entry: Dictionary) -> void:
	key = str(entry.get("key", ""))
	icon = null
	icon_tint = Color.WHITE
	rarity = Color.TRANSPARENT
	shimmer = false
	level = 0
	count = 0
	corner_text = ""
	if entry.has("inst"):
		var inst: Dictionary = entry.inst
		icon = Armory.load_icon(inst)
		icon_tint = Armory.icon_tint(inst)
		level = int(inst.get("level", 0))
		var quality: String = str(inst.get("quality", "normal"))
		if quality != "normal":
			rarity = Armory.quality_color(inst)
			shimmer = quality == "super"
	elif entry.has("map"):
		icon = load(str(entry.icon))
		var quality: String = str(entry.map.get("quality", "normal"))
		if quality != "normal":
			rarity = InstanceRun.quality_color(quality)
		corner_text = str(int(entry.map.level))
		corner_color = InstanceRun.quality_color(quality)
	elif entry.has("icon"):
		var path: String = str(entry.icon)
		icon = load(path) if path.begins_with("res://") and ResourceLoader.exists(path) else PixelIcons.get_icon("bag")
		count = int(entry.get("count", 0))
	refresh_picture()
	redraw()

func refresh_picture() -> void:
	if is_instance_valid(picture):
		picture.queue_free()
		picture = null
	var margin: float = roundf(size.x * 0.12)
	var art_rect: Rect2 = Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	if icon != null:
		picture = UiKit.art(self, icon, art_rect)
		picture.modulate = icon_tint
	elif ghost != null:
		# Empty equipment slot: a pale silhouette of what goes there.
		picture = UiKit.art(self, ghost, art_rect.grow(-4))
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = SILHOUETTE
		material.set_shader_parameter("flat_color", Color(1.0, 0.88, 0.66, 0.16))
		picture.material = material
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if picture != null:
		move_child(picture, 0)

func redraw() -> void:
	queue_redraw()
	if overlay != null:
		overlay.queue_redraw()

func _ready() -> void:
	overlay = Control.new()
	overlay.size = size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_overlay)
	add_child(overlay)
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(func() -> void:
		hover = true
		hovered.emit(self, true)
		redraw())
	mouse_exited.connect(func() -> void:
		hover = false
		drop_hover = false
		hovered.emit(self, false)
		redraw())
	if picture == null:
		refresh_picture()

func _process(delta: float) -> void:
	time += delta
	if shimmer or selected:
		redraw()
	if drop_hover and not get_global_rect().has_point(get_global_mouse_position()):
		drop_hover = false
		redraw()

func _gui_input(event: InputEvent) -> void:
	if not interactive or not event is InputEventMouseButton or not event.pressed:
		return
	var button: InputEventMouseButton = event
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.double_click:
			activated.emit(self)
		else:
			clicked.emit(self)
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		clicked.emit(self)
		activated.emit(self)

func _get_drag_data(_at: Vector2) -> Variant:
	if not interactive or key == "" or icon == null:
		return null
	var preview: Control = Control.new()
	var art: TextureRect = UiKit.art(preview, icon, Rect2(-30, -30, 60, 60))
	art.modulate = Color(icon_tint.r, icon_tint.g, icon_tint.b, 0.9)
	art.rotation = -0.12
	art.pivot_offset = Vector2(30, 30)
	set_drag_preview(preview)
	dragging = true
	if picture != null:
		picture.modulate.a = 0.3
	redraw()
	return {"bag_key": key, "from_cell": cell, "equip_slot": equip_slot}

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = interactive and data is Dictionary and (data as Dictionary).has("bag_key") and accepts.is_valid() and bool(accepts.call(self, data))
	if ok != drop_hover:
		drop_hover = ok
		redraw()
	return ok

func _drop_data(_at: Vector2, data: Variant) -> void:
	drop_hover = false
	redraw()
	dropped.emit(self, data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		dragging = false
		drop_hover = false
		if picture != null:
			picture.modulate.a = 1.0
		redraw()

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(UiKit.frame("slot_hover" if (hover or drop_hover) and interactive else "slot"), rect)
	if rarity.a > 0.0:
		paint_glow(self, size, rarity, 0.5 + 0.5 * sin(time * 3.0) if shimmer else 0.5)
	if shimmer and rarity.a > 0.0:
		# Super Verdadeira: a glint sweeps across the cell now and then.
		var x: float = (fposmod(time * 0.6, 2.2) - 0.3) * size.x
		if x - 14.0 >= 4.0 and x + 8.0 <= size.x - 4.0:
			draw_colored_polygon(PackedVector2Array([Vector2(x, 4), Vector2(x + 8, 4), Vector2(x - 6, size.y - 4), Vector2(x - 14, size.y - 4)]), Color(1, 1, 0.9, 0.18))
	if hover and interactive and key != "":
		draw_rect(rect.grow(-4), Color(1, 0.95, 0.8, 0.08))

func draw_overlay() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var font: Font = UiKit.font(true)
	if level > 0:
		var color: Color = Armory.aura_color(level).lightened(0.3)
		overlay.draw_string_outline(font, Vector2(4, 17), "+%d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, UiKit.INK)
		overlay.draw_string(font, Vector2(4, 17), "+%d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	if count > 1:
		overlay.draw_string_outline(font, Vector2(0, size.y - 5), str(count), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, 4, UiKit.INK)
		overlay.draw_string(font, Vector2(0, size.y - 5), str(count), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, Color.WHITE)
	if corner_text != "":
		overlay.draw_string_outline(font, Vector2(0, size.y - 5), corner_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, 4, UiKit.INK)
		overlay.draw_string(font, Vector2(0, size.y - 5), corner_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 16, corner_color)
	if equipped:
		# Worn: a green badge with a check mark.
		var badge: Rect2 = Rect2(4, size.y - 18, 14, 14)
		overlay.draw_rect(badge, Color("1d5a14"))
		overlay.draw_rect(badge.grow(-1), Color("58c83a"))
		overlay.draw_polyline(PackedVector2Array([badge.position + Vector2(3, 7), badge.position + Vector2(6, 10), badge.position + Vector2(11, 4)]), Color.WHITE, 2.0)
	if key == "" and caption != "":
		overlay.draw_string(font, Vector2(0, size.y - 6), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1.0, 0.88, 0.66, 0.45))
	if selected:
		brackets(overlay, rect.grow(-1), Color("ffd46b").lerp(Color.WHITE, 0.25 + 0.25 * sin(time * 5.0)), 12.0, 3.0)
	if drop_hover:
		brackets(overlay, rect.grow(-1), Color.WHITE, 14.0, 3.0)

static func paint_glow(canvas: CanvasItem, area: Vector2, rarity: Color, pulse: float = 0.5) -> void:
	# Quality glow: stepped rings, brightest in the middle, like pixel-art light, and a
	# small gem of the quality's colour in the corner.
	var center: Vector2 = area / 2.0
	for i in range(7):
		var glow: Color = rarity.lerp(Color.WHITE, i * 0.05)
		glow.a = 0.07 + i * 0.012 + pulse * 0.03
		canvas.draw_circle(center, minf(area.x, area.y) * (0.46 - i * 0.05), glow)
	var gem: Vector2 = Vector2(area.x - 8.0, 8.0)
	canvas.draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -4), gem + Vector2(4, 0), gem + Vector2(0, 4), gem + Vector2(-4, 0)]), rarity.lightened(0.2))
	canvas.draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -2), gem + Vector2(2, 0), gem + Vector2(0, 0), gem + Vector2(-2, 0)]), Color(1, 1, 1, 0.8))

static func glow_node(rect: Rect2, rarity: Color) -> Control:
	# The same glow for item buttons outside the Mochila (Ferreiro); add it behind the art.
	var node: Control = Control.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(func() -> void: paint_glow(node, node.size, rarity))
	return node

func brackets(canvas: CanvasItem, rect: Rect2, color: Color, length: float, width: float) -> void:
	# Four L-shaped corners (selection and drop target), not a full box.
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p: Vector2 = rect.position + rect.size * corner
		var dx: float = length if corner.x == 0 else -length
		var dy: float = length if corner.y == 0 else -length
		var ox: float = 0.0 if corner.x == 0 else -width
		var oy: float = 0.0 if corner.y == 0 else -width
		canvas.draw_rect(Rect2(p.x + minf(0, dx), p.y + oy, absf(dx), width), color)
		canvas.draw_rect(Rect2(p.x + ox, p.y + minf(0, dy), width, absf(dy)), color)
