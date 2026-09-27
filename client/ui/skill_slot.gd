class_name SkillSlot
extends Button

# A skill button of the battle HUD (0.16): skills 1–9, the plane (F), the auxiliary
# item (V) and the tools Z/X/C. A bronze bevel around a dark well with the icon, the
# key on a small plate that sticks out of the corner and the skill's own tag (+2, x3,
# 50%, MAX) or a count in the other corner. The frame lights up under the mouse and
# sinks when pressed; the icon turns grey while the skill cannot be used; a pulsing
# gold glow marks what is armed for this turn (with x2, x3 when stacked); a shine runs
# over every slot when the player's turn begins.

const ICON_SHADER: Shader = preload("res://client/shaders/hud_icon.gdshader")

var art: Texture2D
var key_text: String = ""
var tag: String = ""
var tag_color: Color = Color("ffe6a0")
var count_text: String = ""
var used: int = 0
var accent: Color = Color("ffd04a")
var faded: bool = false
var time: float = 0.0
var shine: float = -10.0
var picture: TextureRect
var icon_material: ShaderMaterial
var overlay: Control
var shown_state: String = ""
static var trimmed: Dictionary = {}

static func create(parent: Node, rect: Rect2, texture: Texture2D, key: String, action: Callable) -> SkillSlot:
	var slot: SkillSlot = SkillSlot.new()
	slot.art = texture
	slot.key_text = key
	slot.position = rect.position
	slot.size = rect.size
	slot.focus_mode = Control.FOCUS_NONE
	if action.is_valid():
		slot.pressed.connect(action)
	parent.add_child(slot)
	return slot

func _ready() -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var well: Rect2 = Rect2(Vector2.ZERO, size).grow(-5.0)
	picture = TextureRect.new()
	picture.name = "Icon"
	picture.texture = trim(art)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.position = well.position + Vector2(1, 1)
	picture.size = well.size - Vector2(2, 2)
	icon_material = ShaderMaterial.new()
	icon_material.shader = ICON_SHADER
	picture.material = icon_material
	add_child(picture)
	overlay = Control.new()
	overlay.size = size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_overlay)
	add_child(overlay)

func set_art(texture: Texture2D) -> void:
	art = texture
	if is_instance_valid(picture):
		picture.texture = trim(texture)

static func trim(texture: Texture2D) -> Texture2D:
	# The PixelLab icons leave a transparent margin; cut it so the art fills the well.
	if texture == null:
		return null
	var key: String = texture.resource_path if texture.resource_path != "" else str(texture.get_instance_id())
	if not trimmed.has(key):
		var image: Image = texture.get_image()
		var used: Rect2i = image.get_used_rect() if image != null else Rect2i()
		var result: Texture2D = texture
		if used.size.x > 0 and (used.size.x < texture.get_width() - 2 or used.size.y < texture.get_height() - 2):
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(used.grow(1).intersection(Rect2i(Vector2i.ZERO, image.get_size())))
			result = atlas
		trimmed[key] = result
	return trimmed[key]

func play_shine(delay: float = 0.0) -> void:
	shine = -delay

func _process(delta: float) -> void:
	time += delta
	shine += delta
	var sunk: bool = get_draw_mode() == DRAW_PRESSED
	picture.position.y = 6.0 + (1.0 if sunk else 0.0)
	var off: bool = (disabled or faded) and used == 0
	var state: String = "%s%s%d" % [off, get_draw_mode(), used]
	var animating: bool = used > 0 or (shine > -0.5 and shine < 0.6)
	if state != shown_state or animating:
		shown_state = state
		icon_material.set_shader_parameter("saturation", 0.12 if off else 1.0)
		icon_material.set_shader_parameter("brightness", 0.5 if off else (1.12 if get_draw_mode() == DRAW_HOVER else 1.0))
		queue_redraw()
		overlay.queue_redraw()

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var mode: DrawMode = get_draw_mode()
	var off: bool = (disabled or faded) and used == 0
	var lit: float = 0.0
	if used > 0:
		var pulse: float = 0.5 + 0.5 * sin(time * 6.0)
		HudPaint.glow_rect(self, rect, Color(accent, 0.55 + 0.45 * pulse), 5.0 + 2.0 * pulse)
		lit = 0.8
	elif mode == DRAW_HOVER and not off:
		HudPaint.glow_rect(self, rect, Color(1.0, 0.85, 0.45, 0.45), 4.0, 3)
		lit = 0.6
	var inner: Rect2 = HudPaint.frame(self, rect, lit, 0.55 if off else 0.0)
	if used > 0:
		HudPaint.well(self, inner, Color(accent.darkened(0.55), 0.95), Color(accent.darkened(0.8), 0.95))
	else:
		HudPaint.well(self, inner)
	if mode == DRAW_PRESSED:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, 3)), Color(0, 0, 0, 0.5))

func draw_overlay() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var inner: Rect2 = rect.grow(-5.0)
	var off: bool = (disabled or faded) and used == 0
	# The shine of a new turn: a slanted light band crossing the well.
	if shine > 0.0 and shine < 0.45:
		var x: float = lerpf(inner.position.x - 14.0, inner.end.x + 4.0, shine / 0.45)
		var points: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in [Vector2(x + 10, inner.position.y), Vector2(x + 18, inner.position.y), Vector2(x + 8, inner.end.y), Vector2(x, inner.end.y)]:
			points.append(Vector2(clampf(corner.x, inner.position.x, inner.end.x), corner.y))
		overlay.draw_colored_polygon(points, Color(1, 1, 0.9, 0.55))
	# Armed this turn: a gold rim inside the frame, and how many times when stacked.
	if used > 0:
		var pulse: float = 0.5 + 0.5 * sin(time * 6.0)
		overlay.draw_rect(inner, Color(accent.lightened(0.4), 0.55 + 0.4 * pulse), false, 2.0)
		if used > 1:
			HudPaint.outlined(overlay, Vector2(inner.end.x - 22, inner.position.y + 13), "x%d" % used, 16, Color.WHITE, HudPaint.INK, 24, HORIZONTAL_ALIGNMENT_RIGHT)
	# The skill's tag (bottom right) or a count (the auxiliary item's uses).
	var corner: String = tag if tag != "" else count_text
	if corner != "":
		var color: Color = tag_color if tag != "" else Color.WHITE
		if off:
			color = color.lerp(Color("9a8c7c"), 0.6)
		HudPaint.outlined(overlay, Vector2(0, inner.end.y + 1), corner, 16, color, HudPaint.INK, inner.end.x + 1, HORIZONTAL_ALIGNMENT_RIGHT)
	# The key on a small plate over the top-left corner.
	if key_text != "":
		var badge: Rect2 = Rect2(-3, -3, 16, 17)
		HudPaint.plate(overlay, badge, Color("4a3220") if off else Color("7a4a1c"), Color("24140a"), HudPaint.INK)
		overlay.draw_rect(badge.grow(-1), Color(HudPaint.GOLD, 0.25 if off else 0.7), false, 1.0)
		HudPaint.outlined(overlay, Vector2(badge.position.x, badge.end.y - 3), key_text, 16, Color("9a8c7c") if off else Color("ffe6a0"), HudPaint.INK, badge.size.x, HORIZONTAL_ALIGNMENT_CENTER, 3)
