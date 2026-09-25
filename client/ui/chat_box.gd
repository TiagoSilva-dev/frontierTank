class_name ChatBox
extends Control

# Channel chat in the classic bottom-left layout: side controls, vertical tabs, input.

var app: Node
var log_label: RichTextLabel
var input: LineEdit
var tab: String = "Atual"
var tab_buttons: Dictionary = {}

func _ready() -> void:
	size = Vector2(500, 196)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.panel(self, Rect2(0, 0, 468, 160), "glass")
	for i in range(4):
		var icon: String = ["lock", "chat", "up", "down"][i]
		var action: Callable = Callable()
		if icon == "up":
			action = func() -> void: log_label.get_v_scroll_bar().value -= 40
		elif icon == "down":
			action = func() -> void: log_label.get_v_scroll_bar().value += 40
		UiKit.panel(self, Rect2(4, 6 + i * 38, 30, 32), "slot")
		UiKit.icon_button(self, PixelIcons.get_icon(icon), Rect2(7, 9 + i * 38, 24, 24), action, ["Travar rolagem", "Canal", "Subir", "Descer"][i])
	log_label = RichTextLabel.new()
	log_label.position = Vector2(40, 6)
	log_label.size = Vector2(390, 150)
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.add_theme_font_override("normal_font", UiKit.font(true))
	log_label.add_theme_font_size_override("normal_font_size", UiKit.fs(14))
	log_label.add_theme_color_override("default_color", Color.WHITE)
	log_label.add_theme_color_override("font_outline_color", Color("140a04"))
	log_label.add_theme_constant_override("outline_size", 3)
	add_child(log_label)
	for i in range(3):
		var name_text: String = ["Atual", "Soc.", "Privado"][i]
		var button: Button = UiKit.button(self, name_text, Rect2(434, 4 + i * 52, 44, 48), func() -> void: select_tab(name_text), "tab_active" if name_text == tab else "tab", 11)
		tab_buttons[name_text] = button
	UiKit.panel(self, Rect2(0, 162, 500, 34), "dark")
	UiKit.button(self, "Atual", Rect2(4, 165, 70, 28), Callable(), "tab", 13)
	input = LineEdit.new()
	input.position = Vector2(78, 166)
	input.size = Vector2(300, 26)
	input.placeholder_text = "Escreva e pressione Enter"
	input.max_length = 80
	input.add_theme_font_override("font", UiKit.font(false))
	input.add_theme_font_size_override("font_size", UiKit.fs(14))
	input.text_submitted.connect(send)
	add_child(input)
	UiKit.button(self, "↵", Rect2(382, 165, 34, 28), func() -> void: send(input.text), "button", 16)
	UiKit.icon_button(self, PixelIcons.get_icon("male"), Rect2(420, 168, 22, 22), Callable(), "Amigos")
	UiKit.icon_button(self, PixelIcons.get_icon("chat"), Rect2(446, 168, 22, 22), Callable(), "Mensagens")
	UiKit.icon_button(self, PixelIcons.get_icon("smile"), Rect2(472, 168, 22, 22), Callable(), "Emoções")
	if app != null:
		app.lobby.chat_added.connect(_on_chat)
	refresh()

func _on_chat(_message: Dictionary) -> void:
	refresh()

func select_tab(value: String) -> void:
	tab = value
	for key: String in tab_buttons:
		var style: String = "tab_active" if key == tab else "tab"
		tab_buttons[key].add_theme_stylebox_override("normal", UiKit.frame(style))
		tab_buttons[key].add_theme_stylebox_override("hover", UiKit.frame(style))
	refresh()

func refresh() -> void:
	if app == null or not is_instance_valid(log_label):
		return
	var lines: PackedStringArray = PackedStringArray()
	for message: Dictionary in app.lobby.history:
		var channel: String = str(message.channel)
		if tab == "Soc." and channel != "Soc.":
			continue
		if tab == "Privado" and channel != "Privado":
			continue
		var text: String = str(message.text).replace("[", "(").replace("]", ")")
		if channel == "system":
			lines.append("[color=#8cff7a]%s[/color]" % text)
		elif channel == "alto-falante":
			lines.append("[color=#6fe8ff][lb]G. alto-falante[rb][lb]%s[rb]: %s[/color]" % [message.author, text])
		else:
			lines.append("[color=#ffe27a][lb]%s[rb][lb]%s[rb]:[/color] %s" % [channel, message.author, text])
	if lines.is_empty():
		lines.append("[color=#c8b89a]%s[/color]" % ("Você ainda não faz parte de uma sociedade." if tab == "Soc." else "Nenhuma mensagem privada."))
	log_label.text = "\n".join(lines)

func send(text: String) -> void:
	text = text.strip_edges()
	if text == "" or app == null:
		return
	app.lobby.post(app.profile.player_name, text, "Privado" if tab == "Privado" else "Atual")
	input.text = ""
	input.release_focus()
