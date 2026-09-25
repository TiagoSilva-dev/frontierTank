class_name UiKit
extends RefCounted

# Shared DDTank-like widgets. Frames are generated pixel-art 9-slices drawn at 2x so
# every logical pixel stays square; replace the specs with PixelLab frames later.

const INK: Color = Color("2a1608")
const GOLD: Color = Color("ffd46b")
const CREAM: Color = Color("fff4d6")
const BROWN: Color = Color("5a2e10")
const TEXT_DARK: Color = Color("4a2a12")
const BLUE_TEAM: Color = Color("5cc8ff")
const RED_TEAM: Color = Color("ff6a5c")
const PIXEL_SCALE: int = 2

const FRAMES: Dictionary = {
	"wood": {"rings": ["2a1608", "a8642a", "ffd479", "8c4a1c", "5e2d0f"], "top": "c47a33", "bottom": "93501f", "radius": 4},
	"wood_dark": {"rings": ["1f0f05", "8a4e22", "e3a95a", "5e2d0f"], "top": "6d3a17", "bottom": "4f290f", "radius": 4},
	"paper": {"rings": ["2a1608", "e0a24a", "7a3f18"], "top": "fbe9bf", "bottom": "ecd09a", "radius": 3},
	"card": {"rings": ["3a1d0a", "fff1c4", "d98f3a"], "top": "fbe3ae", "bottom": "e3a95c", "radius": 4, "shine": true},
	"card_hover": {"rings": ["3a1d0a", "ffffff", "ffb347"], "top": "fff0c8", "bottom": "f4bf6c", "radius": 4, "shine": true},
	"card_busy": {"rings": ["2f1e12", "cdb89a", "8f7355"], "top": "d9c7a6", "bottom": "b79d78", "radius": 4},
	"dark": {"rings": ["120904", "7a5230"], "top": "2e1c10", "bottom": "1d1109", "radius": 2, "alpha": 0.9},
	"glass": {"rings": ["120904", "5a3a22"], "top": "1c120a", "bottom": "120b06", "radius": 2, "alpha": 0.62},
	"slot": {"rings": ["2a1608", "c98b45", "5a3417"], "top": "4a3220", "bottom": "2e1d10", "radius": 2},
	"slot_light": {"rings": ["3a1d0a", "fff1c4", "c98b45"], "top": "f3dcae", "bottom": "e1bd7f", "radius": 2},
	"button": {"rings": ["3a1a06", "fff0b0"], "top": "ffc94f", "bottom": "e0701a", "radius": 3, "shine": true},
	"button_hover": {"rings": ["3a1a06", "ffffff"], "top": "ffdc7a", "bottom": "f2892a", "radius": 3, "shine": true},
	"button_pressed": {"rings": ["3a1a06", "a85a16"], "top": "d06a18", "bottom": "f2a23c", "radius": 3},
	"button_disabled": {"rings": ["3a2a1e", "b0a291"], "top": "9a8d7e", "bottom": "746a5e", "radius": 3},
	"button_green": {"rings": ["0f2a06", "d8ffb0"], "top": "8ee05a", "bottom": "3f9a1f", "radius": 3, "shine": true},
	"button_blue": {"rings": ["0a1a3a", "c8ecff"], "top": "74c6ff", "bottom": "2a6fd6", "radius": 3, "shine": true},
	"plate": {"rings": ["2a1608", "f2b65a", "6e3510"], "top": "a4541c", "bottom": "7b3b12", "radius": 3},
	"tab": {"rings": ["2a1608", "c98b45"], "top": "7a4420", "bottom": "5a2e12", "radius": 2},
	"tab_active": {"rings": ["2a1608", "fff0b0"], "top": "ffc94f", "bottom": "e0701a", "radius": 2, "shine": true},
	"badge": {"rings": ["0f1a3a", "a8dcff"], "top": "4f8ff0", "bottom": "1f4fb0", "radius": 5},
	"badge_gold": {"rings": ["3a1d0a", "fff1b0"], "top": "ffd04a", "bottom": "d98a1a", "radius": 5},
	"banner": {"rings": ["3a0f08", "ffd0a0"], "top": "f06a3a", "bottom": "b8321c", "radius": 3, "alpha": 0.95},
	"mode_green": {"rings": ["0c2a10", "8cff9a", "1f7a2c"], "top": "2f6a38", "bottom": "173d1f", "radius": 3},
	"mode_gray": {"rings": ["1a1a1a", "9a9a9a", "4a4a4a"], "top": "4a4a4a", "bottom": "2c2c2c", "radius": 3},
}

static var _font: FontVariation
static var _styles: Dictionary = {}

# Pixel Operator Bold (CC0) replaced Jersey 10 for legibility: it is drawn on a 16px
# grid, so sizes below 16 are raised to 16 and the rest stay close to the request.
const FONT_PATH: String = "res://assets/fonts/PixelOperator-Bold.ttf"

static func font(_bold: bool = true) -> Font:
	if _font == null:
		var base: FontFile = load(FONT_PATH)
		base.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		base.hinting = TextServer.HINTING_NONE
		base.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font = FontVariation.new()
		_font.base_font = base
	return _font

static func fs(value: int) -> int:
	if value <= 16:
		return 16
	return value + value % 2

static func make_theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = font(true)
	theme.default_font_size = fs(16)
	theme.set_color("font_color", "Label", CREAM)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var kind: String = "button" if state == "normal" else "button_" + state
		theme.set_stylebox(state, "Button", frame(kind))
		theme.set_stylebox(state, "OptionButton", frame(kind))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color("fff0c0"))
	theme.set_color("font_disabled_color", "Button", Color("e6ddd0"))
	theme.set_color("font_outline_color", "Button", INK)
	theme.set_constant("outline_size", "Button", 4)
	theme.set_color("font_color", "OptionButton", Color.WHITE)
	theme.set_color("font_outline_color", "OptionButton", INK)
	theme.set_constant("outline_size", "OptionButton", 4)
	theme.set_stylebox("panel", "TooltipPanel", frame("dark"))
	theme.set_color("font_color", "TooltipLabel", CREAM)
	theme.set_stylebox("normal", "LineEdit", frame("dark"))
	theme.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	theme.set_color("font_color", "LineEdit", CREAM)
	theme.set_stylebox("panel", "PopupMenu", frame("wood_dark"))
	return theme

static func frame(kind: String) -> StyleBoxTexture:
	if _styles.has(kind):
		return _styles[kind]
	var spec: Dictionary = FRAMES[kind]
	var rings: Array = spec.rings
	var radius: int = int(spec.radius)
	var n: int = 2 * (rings.size() + radius) + 4
	var s: int = PIXEL_SCALE
	var alpha: float = float(spec.get("alpha", 1.0))
	var top: Color = Color(spec.top)
	var bottom: Color = Color(spec.bottom)
	var image: Image = Image.create(n * s, n * s, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var level: int = -1
			for k in range(rings.size() + 1):
				if _inside(x, y, n, k, radius):
					level = k
				else:
					break
			if level < 0:
				continue
			var color: Color
			if level < rings.size():
				color = Color(rings[level])
			else:
				color = top.lerp(bottom, float(y - rings.size()) / float(maxi(1, n - 2 * rings.size() - 1)))
				if spec.get("shine", false) and y < n / 2:
					color = color.lightened(0.12)
				color.a = alpha
			image.fill_rect(Rect2i(x * s, y * s, s, s), color)
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	var margin: int = (rings.size() + radius) * s
	style.texture_margin_left = margin
	style.texture_margin_right = margin
	style.texture_margin_top = margin
	style.texture_margin_bottom = margin
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_styles[kind] = style
	return style

static func _inside(x: int, y: int, n: int, k: int, radius: int) -> bool:
	var lo: int = k
	var hi: int = n - 1 - k
	if x < lo or x > hi or y < lo or y > hi:
		return false
	var rr: int = maxi(radius - k, 0)
	if rr == 0:
		return true
	var ox: float = clampf(x, lo + rr, hi - rr)
	var oy: float = clampf(y, lo + rr, hi - rr)
	return Vector2(x - ox, y - oy).length() <= rr - 0.3

# ---------- widgets ----------

static func panel(parent: Node, rect: Rect2, color: Variant = "wood", border: Color = Color.TRANSPARENT) -> Panel:
	var node: Panel = Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if color is String:
		node.add_theme_stylebox_override("panel", frame(color))
	else:
		node.add_theme_stylebox_override("panel", box(color, border))
	parent.add_child(node)
	return node

static func box(color: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

static func label(parent: Node, text: String, rect: Rect2, font_size: int = 16, color: Color = CREAM, outline: Color = Color.TRANSPARENT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node: Label = Label.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_font_override("font", font(true))
	node.add_theme_font_size_override("font_size", fs(font_size))
	node.add_theme_color_override("font_color", color)
	if outline.a > 0:
		node.add_theme_color_override("font_outline_color", outline)
		node.add_theme_constant_override("outline_size", clampi(font_size / 5, 3, 8))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func title(parent: Node, text: String, rect: Rect2, font_size: int = 24, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	return label(parent, text, rect, font_size, GOLD, INK, align)

static func button(parent: Node, text: String, rect: Rect2, action: Callable = Callable(), kind: String = "button", font_size: int = 16) -> Button:
	var node: Button = Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font", font(true))
	node.add_theme_font_size_override("font_size", fs(font_size))
	if kind != "button":
		node.add_theme_stylebox_override("normal", frame(kind))
		var hover: String = kind + "_hover" if FRAMES.has(kind + "_hover") else kind
		node.add_theme_stylebox_override("hover", frame(hover))
		node.add_theme_stylebox_override("pressed", frame(kind))
	if action.is_valid():
		node.pressed.connect(action)
	parent.add_child(node)
	return node

static func icon_button(parent: Node, texture: Texture2D, rect: Rect2, action: Callable = Callable(), tooltip: String = "", caption: String = "") -> Button:
	var node: Button = Button.new()
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_NONE
	node.flat = true
	node.tooltip_text = tooltip
	node.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	node.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	node.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	node.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	var art_rect: Rect2 = Rect2(Vector2.ZERO, rect.size)
	if caption != "":
		art_rect.size.y -= 14
	var picture: TextureRect = art(node, texture, art_rect)
	picture.name = "Icon"
	if caption != "":
		label(node, caption, Rect2(-10, rect.size.y - 16, rect.size.x + 20, 16), 12, Color.WHITE, INK, HORIZONTAL_ALIGNMENT_CENTER)
	node.mouse_entered.connect(func() -> void: picture.modulate = Color(1.25, 1.2, 1.05))
	node.mouse_exited.connect(func() -> void: picture.modulate = Color.WHITE)
	if action.is_valid():
		node.pressed.connect(action)
	parent.add_child(node)
	return node

static func art(parent: Node, source: Variant, rect: Rect2, keep_aspect: bool = true) -> TextureRect:
	var node: TextureRect = TextureRect.new()
	node.texture = load(source) if source is String else source
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if keep_aspect else TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func bar(parent: Node, rect: Rect2, color: Color, back: Color = Color("1a0f08")) -> ProgressBar:
	var node: ProgressBar = ProgressBar.new()
	node.position = rect.position
	node.size = rect.size
	node.show_percentage = false
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = back
	background.border_color = INK
	background.set_border_width_all(2)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.border_color = color.lightened(0.35)
	fill.border_width_top = 2
	node.add_theme_stylebox_override("background", background)
	node.add_theme_stylebox_override("fill", fill)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.size = rect.size
	return node

static func level_badge(parent: Node, level: int, rect: Rect2) -> Panel:
	var node: Panel = panel(parent, rect, "badge")
	label(node, "%02d" % level, Rect2(Vector2.ZERO, rect.size), int(rect.size.y * 0.55), GOLD, INK, HORIZONTAL_ALIGNMENT_CENTER)
	return node

# Extra chibi skins generated with PixelLab live in assets/characters/<skin>/; bots pick
# from those that exist, the player keeps Nilo (m) or Lia (f).
const SKINS: Array[String] = ["bot_ruivo", "bot_pirata", "bot_maga", "bot_ninja", "bot_robo", "bot_princesa"]
const SKIN_GENDER: Dictionary = {"bot_ruivo": "m", "bot_pirata": "f", "bot_maga": "f", "bot_ninja": "m", "bot_robo": "m", "bot_princesa": "f"}

static func skin_for(entry: Dictionary) -> String:
	var skin: String = str(entry.get("look", {}).get("skin", entry.get("skin", "")))
	if skin != "" and ResourceLoader.exists("res://assets/characters/%s/east.png" % skin):
		return skin
	# Default look: plain t-shirt and shorts (base_m / base_f), else the old explorers.
	var female: bool = str(entry.get("gender", "m")) == "f"
	var base: String = "base_f" if female else "base_m"
	if ResourceLoader.exists("res://assets/characters/%s/east.png" % base):
		return base
	return "lia" if female else "nilo"

static func character_path(entry: Dictionary, direction: String = "south") -> String:
	return "res://assets/characters/%s/%s.png" % [skin_for(entry), direction]

static func available_skins() -> Array[String]:
	var found: Array[String] = []
	for skin in SKINS:
		if ResourceLoader.exists("res://assets/characters/%s/east.png" % skin):
			found.append(skin)
	return found

static func head_crop(texture: Texture2D, fraction: float = 0.52) -> AtlasTexture:
	# Chibi sprites: the upper half of the used rect is the face, used for portraits.
	var used: Rect2i = texture.get_image().get_used_rect()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(used.position.x, used.position.y, used.size.x, used.size.y * fraction)
	return atlas

static func dim(parent: Node, alpha: float = 0.6) -> ColorRect:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.02, 0.0, alpha)
	shade.position = Vector2.ZERO
	shade.size = Vector2(1280, 720)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(shade)
	return shade

static func modal(parent: Node, heading: String, body: String, size: Vector2 = Vector2(520, 260)) -> Control:
	# Returns the modal root; callers add their own buttons inside the panel region.
	var root: Control = Control.new()
	root.name = "Modal"
	root.size = Vector2(1280, 720)
	parent.add_child(root)
	dim(root, 0.55)
	var rect: Rect2 = Rect2((Vector2(1280, 720) - size) / 2, size)
	panel(root, rect, "wood")
	panel(root, Rect2(rect.position + Vector2(14, 46), rect.size - Vector2(28, 60)), "paper")
	title(root, heading, Rect2(rect.position + Vector2(0, 8), Vector2(rect.size.x, 34)), 24)
	var text: Label = label(root, body, Rect2(rect.position + Vector2(34, 58), rect.size - Vector2(68, 120)), 16, TEXT_DARK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.set_meta("rect", rect)
	return root

static func notice(parent: Node, heading: String, body: String) -> Control:
	var root: Control = modal(parent, heading, body)
	var rect: Rect2 = root.get_meta("rect")
	button(root, "OK", Rect2(rect.position.x + rect.size.x / 2 - 70, rect.end.y - 58, 140, 40), root.queue_free)
	return root
