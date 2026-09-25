class_name BottomBar
extends Control

# Persistent shortcut bar: SHOP · MOCHILA · PET · CORREIO · MISSÃO | AJUDA · SAIR.
# CORREIO shows how many letters wait (Leilão 0.12).

var app: Node
var mail_badge: Panel
var mail_label: Label
var shown_mail: int = -1

func _ready() -> void:
	size = Vector2(560, 62)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.panel(self, Rect2(0, 14, 350, 48), "wood_dark")
	UiKit.panel(self, Rect2(436, 14, 124, 48), "wood_dark")
	var entries: Array = [["shop", "SHOP", "shop"], ["bag", "MOCHILA", "bag"], ["pet", "PET", "pet"], ["mail", "CORREIO", "mail"], ["mission", "MISSÃO", "mission"]]  # i18n
	for i in range(entries.size()):
		var entry: Array = entries[i]
		var button: Button = UiKit.icon_button(self, PixelIcons.get_icon(entry[0]), Rect2(10 + i * 68, 0, 60, 60), func() -> void: app.shortcut(entry[2]), tr(entry[1]).capitalize(), tr(entry[1]))
		button.name = "Shortcut_" + str(entry[0])
	UiKit.icon_button(self, PixelIcons.get_icon("help"), Rect2(442, 0, 56, 60), func() -> void: app.shortcut("help"), tr("Ajuda"), tr("AJUDA"))
	UiKit.icon_button(self, PixelIcons.get_icon("exit"), Rect2(500, 0, 56, 60), func() -> void: app.shortcut("exit"), tr("Sair"), tr("SAIR"))
	mail_badge = UiKit.panel(self, Rect2(10 + 3 * 68 + 38, -4, 26, 22), "banner")
	mail_badge.name = "MailBadge"
	mail_label = UiKit.label(mail_badge, "", Rect2(0, -1, 26, 22), 14, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	refresh_mail()

func refresh_mail() -> void:
	var count: int = int(app.get("mail_count")) if app != null and app.get("mail_count") != null else 0
	shown_mail = count
	mail_badge.visible = count > 0
	mail_label.text = str(count) if count < 100 else "99+"

func _process(_delta: float) -> void:
	if app != null and app.get("mail_count") != null and int(app.mail_count) != shown_mail:
		refresh_mail()
