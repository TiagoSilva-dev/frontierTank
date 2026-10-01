class_name FounderUi
extends RefCounted

# The marks of a Founder in the interface (docs/FOUNDER_PACK.md, items 15 and 16): the Sun
# badge, the title and the profile frame. They show in the profile, the lobby, the room,
# the chat and the player cards, so everyone can tell who was here from the start. For
# other players the server decides (`founder` in the chat line, `look.founder` in the room
# member); the client never grants it to anyone.

const TITLE: String = "✦ FUNDADOR ✦"
const GOLD: Color = Color("ffd25a")
const BADGE_DIR: String = "res://assets/founder/badge/"
const FRAME: String = "res://assets/founder/frame/founder_frame.png"

static func badge_texture(size_px: int = 32) -> Texture2D:
	var path: String = "%sbadge_%d.png" % [BADGE_DIR, size_px]
	return load(path) if ResourceLoader.exists(path) else null

# The Sun badge, crisp, with a tooltip that says what it means.
static func badge(parent: Node, rect: Rect2) -> TextureRect:
	var size_px: int = 16 if rect.size.y <= 20 else (24 if rect.size.y <= 28 else (32 if rect.size.y <= 40 else 64))
	var texture: Texture2D = badge_texture(size_px)
	var node: TextureRect = TextureRect.new()
	node.name = "FounderBadge"
	node.texture = texture
	node.position = rect.position
	node.size = rect.size
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.tooltip_text = Lang.t("Fundador: estava no Gustfire desde o começo.")
	parent.add_child(node)
	return node

# The Founder frame around a portrait box (drawn over it, slightly larger). The art is
# 128x104: the square border is the middle 88x88 (rows 12..100), the wings stick out.
static func frame(parent: Node, rect: Rect2) -> TextureRect:
	var node: TextureRect = TextureRect.new()
	node.name = "FounderFrame"
	var grow: float = 0.06
	var body: float = rect.size.x * (1.0 + grow * 2.0)
	var k: float = body / 88.0
	node.size = Vector2(128.0, 104.0) * k
	node.position = Vector2(rect.position.x - rect.size.x * grow - 20.0 * k, rect.position.y - rect.size.y * grow - 12.0 * k)
	node.texture = load(FRAME)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func title_label(parent: Node, rect: Rect2, font_size: int = 14, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var node: Label = UiKit.label(parent, TITLE, rect, font_size, GOLD, Color("3a2208"), align)
	node.name = "FounderTitle"
	return node

# BBCode for chat lines: the badge before the name.
static func chat_badge() -> String:
	return "[img=14x14]%sbadge_16.png[/img] " % BADGE_DIR
