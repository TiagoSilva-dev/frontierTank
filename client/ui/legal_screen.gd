class_name LegalScreen
extends Control

# The Terms of Use and the Privacy Policy (launch checklist, LGPD/GDPR), in the game
# language, over any screen: the title (before creating the account), the consent
# dialog and Ajuda → Minha conta.

var kind: String = "terms"
var text_view: RichTextLabel
var tabs: Dictionary = {}

static func open(parent: Node, which: String = "terms") -> LegalScreen:
	var screen: LegalScreen = LegalScreen.new()
	screen.kind = which
	parent.add_child(screen)
	return screen

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.72)
	UiKit.panel(self, Rect2(170, 40, 940, 640), "wood")
	for i in range(Legal.KINDS.size()):
		var which: String = Legal.KINDS[i]
		var tab: Button = UiKit.button(self, Legal.title(which), Rect2(190 + i * 262, 52, 250, 40), show_kind.bind(which), "tab_active" if which == kind else "tab", 17)
		tab.name = "Tab_" + which
		tabs[which] = tab
	var close: Button = UiKit.button(self, tr("FECHAR"), Rect2(950, 52, 140, 40), queue_free)
	close.name = "Close"
	UiKit.panel(self, Rect2(186, 100, 908, 564), "paper")
	text_view = RichTextLabel.new()
	text_view.name = "Text"
	text_view.position = Vector2(206, 110)
	text_view.size = Vector2(868, 544)
	text_view.bbcode_enabled = true
	text_view.selection_enabled = true
	text_view.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text_view.add_theme_font_override("normal_font", UiKit.font(false))
	text_view.add_theme_font_override("bold_font", UiKit.font(true))
	text_view.add_theme_font_size_override("normal_font_size", UiKit.fs(16))
	text_view.add_theme_font_size_override("bold_font_size", UiKit.fs(16))
	text_view.add_theme_color_override("default_color", UiKit.TEXT_DARK)
	text_view.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	add_child(text_view)
	show_kind(kind)

func show_kind(which: String) -> void:
	kind = which
	for key: String in tabs:
		var style: String = "tab_active" if key == kind else "tab"
		tabs[key].add_theme_stylebox_override("normal", UiKit.frame(style))
		tabs[key].add_theme_stylebox_override("hover", UiKit.frame(style))
	text_view.text = Legal.to_bbcode(Legal.text(kind))
	text_view.scroll_to_line(0)

func _gui_input(_event: InputEvent) -> void:
	accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
