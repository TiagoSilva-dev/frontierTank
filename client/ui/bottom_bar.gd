class_name BottomBar
extends Control

# Persistent shortcut bar: SHOP · MOCHILA · PET · CORREIO · MISSÃO | AJUDA · SAIR.

var app: Node

func _ready() -> void:
	size = Vector2(560, 62)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.panel(self, Rect2(0, 14, 350, 48), "wood_dark")
	UiKit.panel(self, Rect2(436, 14, 124, 48), "wood_dark")
	var entries: Array = [["shop", "SHOP", "shop"], ["bag", "MOCHILA", "bag"], ["pet", "PET", "pet"], ["mail", "CORREIO", "mail"], ["mission", "MISSÃO", "mission"]]  # i18n
	for i in range(entries.size()):
		var entry: Array = entries[i]
		UiKit.icon_button(self, PixelIcons.get_icon(entry[0]), Rect2(10 + i * 68, 0, 60, 60), func() -> void: app.shortcut(entry[2]), tr(entry[1]).capitalize(), tr(entry[1]))
	UiKit.icon_button(self, PixelIcons.get_icon("help"), Rect2(442, 0, 56, 60), func() -> void: app.shortcut("help"), tr("Ajuda"), tr("AJUDA"))
	UiKit.icon_button(self, PixelIcons.get_icon("exit"), Rect2(500, 0, 56, 60), func() -> void: app.shortcut("exit"), tr("Sair"), tr("SAIR"))
