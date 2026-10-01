class_name PetStage
extends Control

# The sanctuary window of the Casa dos Mascotes (0.19): the egg or the pet on a glowing
# nest, in the colour of its element, with floating sparks. Set `picture`, `color` and
# `bob` before adding it; change them later with `show_picture`.

var picture: Texture2D
var color: Color = HudPaint.GOLD
var rarity_color: Color = Color.TRANSPARENT
var scene_art: Texture2D
var age: float = 0.0
# The pet floats; an egg rocks a little.
var egg: bool = false
var flip: bool = false
var caption: String = ""
var sub_caption: String = ""
var empty_text: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_art = PetWidgets.texture("res://assets/ui/pets/sanctuary.png")

func show_picture(texture: Texture2D, tint: Color, is_egg: bool, rarity: Color = Color.TRANSPARENT) -> void:
	picture = texture
	color = tint
	egg = is_egg
	rarity_color = rarity

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	var inner: Rect2 = HudPaint.frame(self, Rect2(Vector2.ZERO, size), 0.35)
	if scene_art != null:
		draw_texture_rect(scene_art, inner, false)
	else:
		HudPaint.vgradient(self, inner, Color("101a2e"), Color("1b1530"))
	draw_rect(inner, Color(color.r * 0.2, color.g * 0.2, color.b * 0.3, 0.28))
	HudPaint.vgradient(self, Rect2(5, 5, size.x - 10, 86), Color(0.02, 0.03, 0.08, 0.9), Color(0.02, 0.03, 0.08, 0))
	HudPaint.vgradient(self, Rect2(5, size.y - 96, size.x - 10, 91), Color(0.02, 0.03, 0.08, 0), Color(0.02, 0.03, 0.08, 0.98))
	var unit: float = minf(size.x, size.y)
	var hub: Vector2 = Vector2(size.x * 0.5, size.y * 0.57)
	# The nest: a rune circle on the floor under the picture.
	var floor_y: float = hub.y + unit * 0.27
	for i in range(3):
		var rx: float = unit * (0.24 - i * 0.06)
		var ring: PackedVector2Array = PackedVector2Array()
		for step in range(65):
			var a: float = step * TAU / 64 + age * (0.25 if i % 2 == 0 else -0.2)
			ring.append(Vector2(hub.x + cos(a) * rx, floor_y + sin(a) * rx * 0.24))
		draw_polyline(ring, Color(color, 0.55 - i * 0.12), 2.0)
	HudPaint.glow(self, hub + Vector2(0, 8), unit * 0.3, Color(color, 0.5))
	if rarity_color.a > 0.0:
		HudPaint.glow(self, hub, unit * 0.22, Color(rarity_color, 0.25))
	if picture == null:
		if empty_text != "":
			HudPaint.outlined(self, Vector2(20, hub.y - 10), empty_text, 20, HudPaint.CREAM, HudPaint.INK, size.x - 40, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var span: float = unit * (0.48 if egg else 0.56)
		var bobbing: float = sin(age * 1.9) * (3.0 if egg else 7.0)
		var rock: float = sin(age * 1.3) * 0.045 if egg else 0.0
		draw_set_transform(hub + Vector2(0, bobbing + (14 if egg else 0)), rock, Vector2(-1 if flip else 1, 1))
		# Soft contact shadow, then the picture.
		draw_texture_rect(picture, Rect2(Vector2(-span / 2, -span / 2), Vector2(span, span)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(30):
		var p: Vector2 = Vector2(20 + fmod(i * 83.0, size.x - 40), size.y - 14 - fmod(age * (12 + i % 5 * 7) + i * 37.0, size.y - 28))
		var alpha: float = sin(PI * (size.y - p.y) / size.y) * (0.35 + 0.3 * sin(age * 2 + i))
		HudPaint.sparkle(self, p, 2 + i % 3, Color(color.lightened(0.4), maxf(0, alpha)))
	if caption != "":
		HudPaint.fancy(self, Vector2(0, 12), caption, 26, rarity_color if rarity_color.a > 0.0 else HudPaint.CREAM, HudPaint.BRONZE_DARK, size.x, HORIZONTAL_ALIGNMENT_CENTER, 3, 8)
	if sub_caption != "":
		HudPaint.outlined(self, Vector2(0, size.y - 30), sub_caption, 18, HudPaint.CREAM, HudPaint.INK, size.x, HORIZONTAL_ALIGNMENT_CENTER)
