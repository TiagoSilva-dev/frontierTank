class_name PremiumPanel
extends Panel

# A panel painted with the premium frame (PremiumUi.paint): UiKit.panel returns one for
# the old wood/paper/card kinds. `kind` is a key of PremiumUi.PANELS' values.

var kind: String = "window"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

func _draw() -> void:
	PremiumUi.paint(self, Rect2(Vector2.ZERO, size), kind)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
