class_name LootToast
extends Control

var reward: Dictionary = {}
var age: float = 0.0

func _ready() -> void:
	add_to_group("loot_toasts")
	size = Vector2(316, 62)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	UiKit.art(self, str(reward.get("icon", "")), Rect2(8, 7, 46, 46))
	UiKit.label(self, tr("RECOMPENSA DO GRUPO") if bool(reward.get("shared", false)) else tr("SEU GOLPE FINAL"), Rect2(62, 7, 246, 20), 14, HudPaint.GOLD)
	UiKit.clipped(self, tr(str(reward.get("name", ""))), Rect2(62, 28, 246, 27), 16, HudPaint.CREAM)

func _process(delta: float) -> void:
	age += delta
	modulate.a = minf(age * 6, 1.0) * clampf(4.0 - age, 0, 1)
	if age > 4.0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	HudPaint.well(self, HudPaint.frame(self, Rect2(Vector2.ZERO, size), 0.6))
