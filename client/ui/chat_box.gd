class_name ChatBox
extends Control

# Channel chat in the classic bottom-left layout: side controls, vertical tabs, input.
# A player's name is a link: it opens the player menu (profile, private message, friend and,
# online, the report dialog of the launch checklist, which can also hide that player's lines).
# The Privado tab talks to the player picked in that menu (the offline channel answers for the
# simulated ones; online, the server delivers it). Light text sits on a dark panel.

var app: Node
var log_label: RichTextLabel
var input: LineEdit
var tab: String = "Atual"
var tab_buttons: Dictionary = {}
var target_button: Button
var unread_dot: Label
# Height of the log. The city uses a shorter one so the chat does not hide the Casa dos
# Mascotes (the side buttons shrink to the scroll arrows).
var log_height: float = 160.0

func _ready() -> void:
	var compact: bool = log_height < 150.0
	size = Vector2(500, log_height + 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.panel(self, Rect2(0, 0, 468, log_height), "dark")
	var icons: Array[String] = []
	icons.assign(["up", "down"] if compact else ["lock", "chat", "up", "down"])
	for i in range(icons.size()):
		var icon: String = icons[i]
		var action: Callable = Callable()
		if icon == "up":
			action = func() -> void: log_label.get_v_scroll_bar().value -= 40
		elif icon == "down":
			action = func() -> void: log_label.get_v_scroll_bar().value += 40
		var step: float = 40.0 if compact else 38.0
		UiKit.panel(self, Rect2(4, 6 + i * step, 30, 32), "slot")
		UiKit.icon_button(self, PixelIcons.get_icon(icon), Rect2(7, 9 + i * step, 24, 24), action, tr({"lock": "Travar rolagem", "chat": "Canal", "up": "Subir", "down": "Descer"}[icon]))  # i18n
	log_label = RichTextLabel.new()
	log_label.position = Vector2(40, 6)
	log_label.size = Vector2(390, log_height - 10)
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.add_theme_font_override("normal_font", UiKit.reading_font())
	log_label.add_theme_font_override("bold_font", UiKit.reading_font(true))
	log_label.add_theme_font_size_override("normal_font_size", UiKit.fs(16))
	log_label.add_theme_font_size_override("bold_font_size", UiKit.fs(16))
	log_label.add_theme_color_override("default_color", Color("f6f1e6"))
	log_label.add_theme_color_override("font_outline_color", Color("140a04"))
	log_label.add_theme_constant_override("outline_size", 2)
	log_label.add_theme_constant_override("line_separation", 3)
	log_label.meta_underlined = false
	log_label.meta_clicked.connect(on_meta)
	add_child(log_label)
	for i in range(3):
		var name_text: String = ["Atual", "Soc.", "Privado"][i]  # i18n
		var tab_step: float = (log_height - 8.0) / 3.0
		var button: Button = UiKit.button(self, tr(name_text), Rect2(434, 4 + i * tab_step, 44, tab_step - 4.0), func() -> void: select_tab(name_text), "tab_active" if name_text == tab else "tab", 11)
		tab_buttons[name_text] = button
	unread_dot = UiKit.label(self, "", Rect2(466, 4 + (log_height - 8.0) / 3.0 * 2.0 - 6.0, 24, 24), 14, Color.WHITE, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	unread_dot.add_theme_stylebox_override("normal", UiKit.frame("button_red"))
	unread_dot.name = "Unread"
	unread_dot.hide()
	var row: float = log_height + 2.0
	UiKit.panel(self, Rect2(0, row, 500, 34), "dark")
	target_button = UiKit.button(self, tr("Atual"), Rect2(4, row + 3, 92, 28), pick_target, "tab", 14)
	target_button.clip_text = true
	input = LineEdit.new()
	input.position = Vector2(100, row + 4)
	input.size = Vector2(278, 26)
	input.placeholder_text = tr("Escreva e pressione Enter")
	input.max_length = 80
	input.add_theme_font_override("font", UiKit.reading_font())
	input.add_theme_font_size_override("font_size", UiKit.fs(14))
	input.text_submitted.connect(send)
	add_child(input)
	UiKit.button(self, "↵", Rect2(382, row + 3, 34, 28), func() -> void: send(input.text), "button", 16)
	UiKit.icon_button(self, PixelIcons.get_icon("male"), Rect2(420, row + 6, 22, 22), func() -> void: FriendsDialog.open(app.ui, app), tr("Amigos"))
	UiKit.icon_button(self, PixelIcons.get_icon("chat"), Rect2(446, row + 6, 22, 22), open_private, tr("Mensagens"))
	UiKit.icon_button(self, PixelIcons.get_icon("smile"), Rect2(472, row + 6, 22, 22), Callable(), tr("Emoções"))
	if app != null:
		app.lobby.chat_added.connect(_on_chat)
	refresh()

func _on_chat(_message: Dictionary) -> void:
	refresh()

func select_tab(value: String) -> void:
	tab = value
	if tab == "Privado":
		app.lobby.unread_private = 0
	for key: String in tab_buttons:
		var style: String = "tab_active" if key == tab else "tab"
		tab_buttons[key].add_theme_stylebox_override("normal", UiKit.frame(style))
		tab_buttons[key].add_theme_stylebox_override("hover", UiKit.frame(style))
	refresh()

# Called by the player menu: the private tab, ready to write to the picked player.
func open_private() -> void:
	select_tab("Privado")
	if is_instance_valid(input):
		input.grab_focus()

# The channel/recipient button of the input row: in the Privado tab it names the target and
# opens the friends window to change it.
func pick_target() -> void:
	if tab == "Privado":
		FriendsDialog.open(app.ui, app)

func refresh() -> void:
	if app == null or not is_instance_valid(log_label):
		return
	if tab == "Privado" and app.lobby.unread_private > 0:
		app.lobby.unread_private = 0
	var lines: PackedStringArray = PackedStringArray()
	var mine: String = app.profile.player_name
	for index in range(app.lobby.history.size()):
		var message: Dictionary = app.lobby.history[index]
		var channel: String = str(message.channel)
		if tab == "Soc." and channel != "Soc.":
			continue
		if tab == "Privado" and channel != "Privado":
			continue
		if app.lobby.ignored.has(int(message.get("account", 0))):
			continue
		var text: String = str(message.text).replace("[", "(").replace("]", ")")
		var plain: String = str(message.get("author", "")).replace("[", "(").replace("]", ")")
		var author: String = plain
		if plain != mine and channel != "system":
			# Every name but the player's own opens the player menu.
			author = "[url=m:%d]%s[/url]" % [index, plain]
		if bool(message.get("founder", false)):
			author = FounderUi.chat_badge() + author
		var name_color: String = "b8ff9a" if plain == mine else "8fe3ff"
		if channel == "system":
			lines.append("[color=#8cff7a]%s[/color]" % text)
		elif channel == "alto-falante":
			lines.append("[color=#6fe8ff][lb]%s[rb][lb]%s[rb]: %s[/color]" % [tr("G. alto-falante"), message.author, text])
		elif channel == "Privado":
			var direction: String = tr("Para %s") % str(message.get("to", "")).replace("[", "(").replace("]", ")") if plain == mine else tr("De %s") % author
			lines.append("[color=#ffa8f0][lb]%s[rb][lb]%s[rb]:[/color] [color=#ffe3fb]%s[/color]" % [tr("Privado"), direction, text])
		else:
			lines.append("[color=#ffe27a][lb]%s[rb][/color][color=#%s][lb]%s[rb][/color][color=#ffe27a]:[/color] %s" % [tr(channel), name_color, author, text])
	if lines.is_empty():
		if tab == "Soc.":
			lines.append("[color=#d8c8a8]%s[/color]" % tr("Você ainda não faz parte de uma sociedade."))
		else:
			lines.append("[color=#d8c8a8]%s[/color]" % tr("Nenhuma mensagem privada. Clique no nome de um jogador na lista e escolha Mensagem privada."))
	log_label.text = "\n".join(lines)
	update_input()

# The recipient on the input row and the unread dot of the Privado tab.
func update_input() -> void:
	var target: String = str(app.lobby.whisper_target.get("name", ""))
	if tab == "Privado":
		target_button.text = ("→ " + target) if target != "" else tr("Escolher…")
		target_button.tooltip_text = tr("Para quem vai a mensagem privada. Clique para escolher um amigo.")
		input.placeholder_text = tr("Escreva para %s e pressione Enter") % target if target != "" else tr("Escolha um jogador na lista")
	else:
		target_button.text = tr("Atual")
		target_button.tooltip_text = ""
		input.placeholder_text = tr("Escreva e pressione Enter")
	var unread: int = app.lobby.unread_private
	unread_dot.visible = unread > 0 and tab != "Privado"
	unread_dot.text = str(mini(unread, 9))

# A click on a name: the player menu (and, for a line of someone else online, the report).
func on_meta(meta: Variant) -> void:
	var text: String = str(meta)
	if not text.begins_with("m:"):
		return
	var index: int = text.substr(2).to_int()
	if index < 0 or index >= app.lobby.history.size():
		return
	var message: Dictionary = app.lobby.history[index]
	var who: String = str(message.get("author", ""))
	var person: Dictionary = {"name": who, "level": 1, "gender": "m", "account": int(message.get("account", 0))}
	for known: Dictionary in app.lobby.bots:
		if known.name == who:
			person = known
			break
	PlayerMenu.open(app.ui, app, person, TouchMode.pointer(self) + Vector2(8, -120), message if reportable(message) else {})

# Online lines of other players can be reported.
func reportable(message: Dictionary) -> bool:
	return app != null and app.online and message.has("id") and int(message.get("account", 0)) != app.my_account()

func send(text: String) -> void:
	text = text.strip_edges()
	if text == "" or app == null:
		return
	if tab == "Privado":
		var target: Dictionary = app.lobby.whisper_target
		if target.is_empty():
			app.lobby.post("Sistema", tr("Escolha um jogador na lista (clique no nome) para enviar uma mensagem privada."), "system")
			return
		app.lobby.whisper(target, text, app.profile.player_name)
	else:
		app.lobby.post(app.profile.player_name, text, "Atual", {"founder": app.profile.is_founder()})
	input.text = ""
	input.release_focus()
