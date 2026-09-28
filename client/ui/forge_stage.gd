class_name ForgeStage
extends Control

var item: Dictionary = {}
var age: float = 0.0
var scene_art: Texture2D
var weapon: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_art = load("res://assets/ui/forge/workshop.png")
	if not item.is_empty():
		weapon = Armory.load_icon(item)

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	var inner: Rect2 = HudPaint.frame(self, Rect2(Vector2.ZERO, size), 0.35)
	if scene_art != null:
		draw_texture_rect(scene_art, inner, false)
	HudPaint.vgradient(self, Rect2(5, 5, size.x - 10, 86), Color(0.02, 0.03, 0.08, 0.95), Color(0.02, 0.03, 0.08, 0))
	HudPaint.vgradient(self, Rect2(5, size.y - 90, size.x - 10, 85), Color(0.02, 0.03, 0.08, 0), Color(0.02, 0.03, 0.08, 0.98))
	var hub: Vector2 = Vector2(size.x * 0.5, size.y * 0.48 + sin(age * 1.7) * 5)
	var color: Color = Armory.aura_color(int(item.get("level", 0))).lightened(0.3) if int(item.get("level", 0)) > 0 else HudPaint.GOLD
	HudPaint.glow(self, hub, 116, Color(color, 0.55))
	for ring in range(2):
		draw_arc(hub, 84 + ring * 14, age * (0.4 if ring == 0 else -0.3), age * (0.4 if ring == 0 else -0.3) + PI * 1.5, 64, Color(color, 0.4), 2)
	if weapon != null:
		draw_texture_rect(weapon, Rect2(hub - Vector2(76, 76), Vector2(152, 152)), false, Armory.icon_tint(item))
	for i in range(28):
		var p: Vector2 = Vector2(18 + fmod(i * 79.0, size.x - 36), size.y - 12 - fmod(age * (14 + i % 5 * 7) + i * 31.0, size.y - 24))
		var a: float = sin(PI * (size.y - p.y) / size.y) * (0.35 + 0.3 * sin(age * 2 + i))
		HudPaint.sparkle(self, p, 2 + i % 3, Color(HudPaint.GOLD, maxf(0, a)))
	HudPaint.fancy(self, Vector2(0, size.y - 46), "+%d" % int(item.get("level", 0)), 48, color, Color("814118"), size.x, HORIZONTAL_ALIGNMENT_CENTER)
	HudPaint.outlined(self, Vector2(0, size.y - 17), tr("O próximo poder começa aqui"), 18, HudPaint.CREAM, HudPaint.INK, size.x, HORIZONTAL_ALIGNMENT_CENTER)
