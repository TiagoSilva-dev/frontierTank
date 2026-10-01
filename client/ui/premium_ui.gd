class_name PremiumUi
extends RefCounted

# The premium look of the Forja Celeste and the Casa de Câmbio, shared by every screen
# (0.18): bronze frames with dark glass wells, dark steel buttons with a bronze edge,
# gold headings. UiKit routes its old wood/paper panels and buttons here, so a screen
# only chooses a kind ("wood", "paper", "button_green"...) and gets the same look.

const TEXT: Color = Color("fff0d0")
const MUTED: Color = Color("b4c2d4")
const GOOD: Color = Color("9aff7a")
const BAD: Color = Color("ff8f7e")
const INFO: Color = Color("8ec8ff")
const GOLD: Color = Color("ffd479")
const GOLD_HOT: Color = Color("fff1b0")
const DISABLED: Color = Color("8392a7")

# Panel kinds drawn by PremiumPanel: the big frame + well, and the thin inset of rows.
const PANELS: Dictionary = {
	"wood": "window", "wood_dark": "window", "paper": "window",
	"card": "inset", "card_hover": "inset_lit", "card_busy": "inset_dim",
	"slot": "inset", "slot_hover": "inset_lit", "slot_light": "inset",
	"mode_green": "inset_green", "mode_gray": "inset_gray",
	"dark": "inset_dark", "plate": "plate", "banner": "banner",
}

# Button colours: normal, hover, edge. "active" kinds are the selected tab or card.
const BUTTONS: Dictionary = {
	"button": ["182538", "293d52", "946336"],
	"button_hover": ["293d52", "293d52", "ffd479"],
	"button_pressed": ["0f1826", "0f1826", "ffd479"],
	"button_disabled": ["141c29", "141c29", "434454"],
	"button_green": ["1d4a2c", "2b6a3f", "62b36c"],
	"button_blue": ["1d3d68", "2b5b98", "6aa8e6"],
	"button_red": ["5c201d", "84312b", "d0685a"],
	"tab": ["141f30", "263a52", "7a5430"],
	"tab_active": ["71401d", "94562a", "e3a95a"],
	"card": ["121c2c", "22344a", "6a4a2c"],
	"card_hover": ["4a3319", "5e4120", "ffd479"],
	"card_busy": ["141c29", "141c29", "434454"],
	"slot": ["121c2c", "22344a", "6a4a2c"],
	"slot_hover": ["22344a", "22344a", "ffd479"],
	"slot_light": ["1a2a40", "2c4262", "8a6338"],
}

static var _cache: Dictionary = {}

static func has_button(kind: String) -> bool:
	return BUTTONS.has(kind)

# A button box. `state` is normal, hover, pressed, disabled or focus.
static func button_style(kind: String, state: String = "normal") -> StyleBoxFlat:
	var key: String = kind + "/" + state
	if _cache.has(key):
		return _cache[key]
	var spec: Array = BUTTONS.get(kind, BUTTONS.button)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var edge: Color = Color(spec[2])
	match state:
		"hover", "focus":
			style.bg_color = Color(spec[1])
			edge = GOLD
		"pressed":
			style.bg_color = Color(spec[0]).darkened(0.25)
			edge = GOLD
		"disabled":
			style.bg_color = Color(BUTTONS.button_disabled[0])
			edge = Color(BUTTONS.button_disabled[2])
		_:
			style.bg_color = Color(spec[0])
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_cache[key] = style
	return style

# Text fields (LineEdit, SpinBox): a dark well with a bronze edge, gold when focused.
static func field_style(focused: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("0c141f")
	style.border_color = GOLD if focused else Color("7a5430")
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

# Marks the selected buttons below `root`: one with the meta "active" gets the tab_active
# look. (Plain Button.new() ones already take the premium theme from UiKit.make_theme.)
static func skin(root: Node) -> void:
	for node: Node in root.get_children():
		if node is Button and node.get_meta("active", false):
			for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
				node.add_theme_stylebox_override(state, button_style("tab_active", state))
		skin(node)

# The tick box of CheckBox and CheckButton: a dark well with a bronze edge and a gold tick.
static func check_icon(checked: bool) -> Texture2D:
	var key: String = "check/%s" % checked
	if _cache.has(key):
		return _cache[key]
	var cells: int = 11
	var scale: int = 2
	var image: Image = Image.create(cells * scale, cells * scale, false, Image.FORMAT_RGBA8)
	var tick: Array = [Vector2i(2, 5), Vector2i(3, 6), Vector2i(4, 7), Vector2i(5, 6), Vector2i(6, 5), Vector2i(7, 4), Vector2i(8, 3)]
	for y in range(cells):
		for x in range(cells):
			var color: Color = Color("0c141f")
			if x == 0 or y == 0 or x == cells - 1 or y == cells - 1:
				color = HudPaint.INK
			elif x == 1 or y == 1 or x == cells - 2 or y == cells - 2:
				color = GOLD if checked else Color("8a6338")
			image.fill_rect(Rect2i(x * scale, y * scale, scale, scale), color)
	if checked:
		for cell: Vector2i in tick:
			for dy in range(2):
				image.fill_rect(Rect2i(cell.x * scale, (cell.y + dy - 1) * scale, scale, scale), GOLD_HOT if dy == 0 else GOLD)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

# ---------- drawing ----------

static func paint(ci: CanvasItem, rect: Rect2, kind: String) -> void:
	match kind:
		"window":
			HudPaint.well(ci, HudPaint.frame(ci, rect, 0.25))
		"inset", "inset_lit", "inset_dim", "inset_dark", "inset_green", "inset_gray":
			inset(ci, rect, kind)
		"plate":
			HudPaint.vgradient(ci, HudPaint.frame(ci, rect, 0.1), Color("9a5a24"), Color("5e3010"), 1.0)
		"banner":
			HudPaint.vgradient(ci, HudPaint.frame(ci, rect, 0.0), Color("a8431f"), Color("6a2112"), 1.0)

# A thin bronze-edged glass slot: rows, cards and the little boxes inside a window.
static func inset(ci: CanvasItem, rect: Rect2, kind: String = "inset") -> void:
	var edge: Color = Color("7a5430")
	var top: Color = Color("1a2a40")
	var bottom: Color = Color("0f1826")
	if kind == "inset_lit":
		edge = GOLD
		top = Color("4a3319")
		bottom = Color("2a1d0e")
	elif kind == "inset_dark":
		edge = Color("5a3a22")
		top = Color("0e1622")
		bottom = Color("0a1019")
	elif kind == "inset_green":
		edge = Color("62b36c")
		top = Color("24603a")
		bottom = Color("163a24")
	elif kind == "inset_gray":
		edge = Color("5a6270")
		top = Color("262c36")
		bottom = Color("1a1f28")
	elif kind == "inset_dim":
		edge = Color("434454")
		top = Color("1b2230")
		bottom = Color("141a24")
	ci.draw_colored_polygon(HudPaint.chamfer(rect, 3.0), HudPaint.INK)
	ci.draw_colored_polygon(HudPaint.chamfer(rect.grow(-1.0), 2.0), edge)
	HudPaint.vgradient(ci, rect.grow(-3.0), top, bottom, 1.0)
	ci.draw_rect(Rect2(rect.position.x + 4.0, rect.position.y + 3.0, rect.size.x - 8.0, 1.0), Color(1, 1, 1, 0.07))

# ---------- windows ----------

# The dark steel-blue backdrop of the full-page screens (hall, room): the well colours of
# the frames, so the bronze panels stand out of it.
static func backdrop(parent: Node) -> Control:
	var node: Control = Control.new()
	node.name = "Backdrop"
	node.size = Vector2(1280, 720)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(func() -> void:
		HudPaint.vgradient(node, Rect2(Vector2.ZERO, node.size), Color("0a101a"), Color("152133"))
		HudPaint.glow_rect(node, Rect2(Vector2.ZERO, node.size).grow(-24.0), Color(0.5, 0.35, 0.15, 0.05), 40.0, 3))
	parent.add_child(node)
	return node

# A full-screen window: the dimmed backdrop, the bronze frame with its dark well, and the
# heading with its small subtitle. Returns the root so the caller can add to it.
static func window(parent: Node, rect: Rect2, heading: String, subtitle: String = "", dim: float = 0.94, size: int = 40, centered: bool = false) -> Control:
	var root: Control = Control.new()
	root.name = "Window"
	root.size = Vector2(1280, 720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	UiKit.dim(root, dim)
	var frame: Control = panel(root, rect)
	frame.name = "Frame"
	if centered:
		title(root, rect.position + Vector2(0, 47), heading, size, subtitle, rect.size.x)
	else:
		title(root, rect.position + Vector2(28, 47), heading, size, subtitle)
	return root

# The layered gold heading of the forge; `at` is the baseline of its left edge.
static func title(parent: Node, at: Vector2, heading: String, size: int = 40, subtitle: String = "", width: float = -1.0) -> Control:
	var node: Control = Control.new()
	node.name = "Heading"
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(func() -> void:
		var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER if width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
		HudPaint.fancy(node, at, heading, size, GOLD, Color("783814"), width, align)
		if subtitle != "":
			HudPaint.outlined(node, at + Vector2(0 if width > 0.0 else 2, 22), subtitle, 16, Color("afbed1"), HudPaint.INK, width, align))
	parent.add_child(node)
	return node

# A frame with a glass well, as the forge builds it.
static func panel(parent: Node, rect: Rect2) -> Control:
	var node: PremiumPanel = PremiumPanel.new()
	node.position = rect.position
	node.size = rect.size
	parent.add_child(node)
	return node

# The coins of the player, top right of the windows.
static func coins(parent: Node, at: Vector2, amount: int) -> void:
	UiKit.art(parent, "res://assets/items/moeda.png", Rect2(at, Vector2(30, 30)))
	UiKit.label(parent, str(amount), Rect2(at + Vector2(40, -4), Vector2(190, 38)), 24, GOLD)
