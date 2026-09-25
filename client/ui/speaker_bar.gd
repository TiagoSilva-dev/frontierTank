class_name SpeakerBar
extends Control

# "Gde alto-falante": server-wide shout line scrolling along the top edge.

var app: Node
var text_label: Label
var offset: float = 0.0

func _ready() -> void:
	size = Vector2(1280, 32)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip: ColorRect = ColorRect.new()
	strip.color = Color(0.08, 0.04, 0.02, 0.55)
	strip.size = Vector2(1280, 32)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	var clip: Control = Control.new()
	clip.clip_contents = true
	clip.position = Vector2(118, 0)
	clip.size = Vector2(1162, 32)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	text_label = UiKit.label(clip, "", Rect2(1162, 2, 1400, 28), 15, Color("6fe8ff"), Color("08131c"))
	UiKit.art(self, PixelIcons.get_icon("speaker"), Rect2(6, 3, 26, 26))
	UiKit.label(self, "Alto-falante", Rect2(36, 0, 84, 32), 12, Color("bfe8ff"), Color("08131c"))

func _process(delta: float) -> void:
	if app == null:
		return
	if text_label.text != app.lobby.speaker:
		text_label.text = app.lobby.speaker
		offset = 0
	offset += delta * 70.0
	var width: float = UiKit.font(true).get_string_size(text_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(15)).x
	text_label.position.x = 1162 - fmod(offset, 1162 + width + 40)
