class_name PlayerList
extends Control

# The players of the channel (Salão de Jogos), highest level first, with a tab for the
# friends and a search box. Clicking a name opens the PlayerMenu: profile, private message,
# add or remove a friend. Dark names on the paper panel; friends carry a star.

const ROW_HEIGHT: float = 34.0

var app: Node
var tab: String = "all"
var query: String = ""
var scroll: ScrollContainer
var rows: VBoxContainer
var tab_buttons: Dictionary = {}
var count_label: Label
var search: LineEdit

func _ready() -> void:
	size = Vector2(368, 316)
	UiKit.panel(self, Rect2(0, 0, 368, 316), "wood")
	for i in range(2):
		var id: String = ["all", "friends"][i]
		var button: Button = UiKit.button(self, "", Rect2(10 + i * 100, 8, 94, 32), select_tab.bind(id), "tab_active" if id == tab else "tab", 15)
		button.name = "Tab_" + id
		tab_buttons[id] = button
	search = UiKit.text_field(self, Rect2(214, 8, 144, 32), tr("Buscar jogador"), false, 16, 15)
	search.name = "Search"
	search.text_changed.connect(func(text: String) -> void:
		query = text.strip_edges().to_lower()
		rebuild())
	UiKit.panel(self, Rect2(10, 46, 348, 26), "plate")
	UiKit.label(self, tr("Nível"), Rect2(18, 46, 70, 26), 15, Color("ffe6a0"), UiKit.INK)
	UiKit.label(self, tr("Jogador"), Rect2(66, 46, 150, 26), 15, Color("ffe6a0"), UiKit.INK)
	UiKit.label(self, tr("Sexo"), Rect2(280, 46, 70, 26), 15, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.panel(self, Rect2(10, 76, 348, 230), "paper")
	scroll = ScrollContainer.new()
	scroll.position = Vector2(14, 80)
	scroll.size = Vector2(340, 222)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.custom_minimum_size = Vector2(328, 0)
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)
	app.lobby.rooms_changed.connect(rebuild)
	rebuild()

func select_tab(id: String) -> void:
	tab = id
	app.audio.play("ui_click")
	rebuild()

# The players to show: everybody (with me), or the friends, filtered by the search text.
func people() -> Array[Dictionary]:
	var everyone: Array[Dictionary] = app.lobby.bots.duplicate()
	everyone.append({"name": app.profile.player_name, "level": app.profile.level(), "gender": app.profile.gender, "me": true, "founder": app.profile.is_founder(), "account": app.my_account()})
	app.friends.refresh(everyone)
	everyone.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
	if tab == "friends":
		var shown: Array[Dictionary] = []
		for friend: Dictionary in app.friends.friends:
			var online: Dictionary = {}
			for person: Dictionary in everyone:
				if person.name == friend.name:
					online = person
					break
			var entry: Dictionary = online.duplicate() if not online.is_empty() else friend.duplicate()
			entry["away"] = online.is_empty()
			shown.append(entry)
		shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (not a.away and b.away) or (a.away == b.away and int(a.level) > int(b.level)))
		everyone = shown
	if query != "":
		everyone = everyone.filter(func(person: Dictionary) -> bool: return str(person.name).to_lower().contains(query))
	return everyone

func rebuild() -> void:
	if not is_instance_valid(rows):
		return
	var kept: int = scroll.scroll_vertical
	for child in rows.get_children():
		# Out of the tree first: a row still waiting to be freed would take the name of the new one.
		rows.remove_child(child)
		child.queue_free()
	var shown: Array[Dictionary] = people()
	for person: Dictionary in shown:
		add_row(person)
	if shown.is_empty():
		var empty: Label = UiKit.label(rows, tr("Nenhum amigo ainda. Clique no nome de um jogador para adicioná-lo.") if tab == "friends" and query == "" else tr("Nenhum jogador encontrado."), Rect2(0, 0, 320, 80), 16, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		empty.custom_minimum_size = Vector2(320, 80)
		UiKit.wrap(empty, Vector2(320, 80))
		empty.name = "Empty"
	var friends_total: int = app.friends.friends.size()
	tab_buttons.all.text = tr("Todos")
	tab_buttons.friends.text = "%s %d" % [tr("Amigos"), friends_total]
	for id: String in tab_buttons:
		var style: String = "tab_active" if id == tab else "tab"
		tab_buttons[id].add_theme_stylebox_override("normal", UiKit.frame(style))
		tab_buttons[id].add_theme_stylebox_override("hover", UiKit.frame(style))
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = kept

func add_row(person: Dictionary) -> void:
	var mine: bool = bool(person.get("me", false))
	var away: bool = bool(person.get("away", false))
	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(328, ROW_HEIGHT)
	row.focus_mode = Control.FOCUS_NONE
	row.name = "Player_" + str(person.name)
	row.add_theme_stylebox_override("normal", UiKit.frame("slot_light") if mine else StyleBoxEmpty.new())
	row.add_theme_stylebox_override("hover", UiKit.frame("card_hover"))
	row.add_theme_stylebox_override("pressed", UiKit.frame("card"))
	row.tooltip_text = tr("Clique para abrir o menu do jogador")
	row.pressed.connect(func() -> void:
		app.audio.play("ui_click")
		PlayerMenu.open(app.ui, app, person, get_global_mouse_position() + Vector2(6, 6)))
	rows.add_child(row)
	var badge: Panel = UiKit.level_badge(row, int(person.level), Rect2(6, 5, 38, 24))
	badge.modulate = Color(1, 1, 1, 0.55) if away else Color.WHITE
	var x: float = 52.0
	if app.friends.has(str(person.name)):
		UiKit.art(row, PixelIcons.get_icon("star"), Rect2(x, 8, 18, 18)).name = "Star"
		x += 22.0
	if bool(person.get("founder", false)):
		FounderUi.badge(row, Rect2(x, 7, 20, 20))
		x += 24.0
	var color: Color = UiKit.GOOD_ON_LIGHT if mine else (UiKit.TEXT_MUTED if away else UiKit.TEXT_DARK)
	var name_label: Label = UiKit.clipped(row, str(person.name), Rect2(x, 3, 232 - x + 52, 28), 17, color)
	name_label.add_theme_font_override("font", UiKit.reading_font(true))
	name_label.name = "Name"
	if away:
		UiKit.label(row, tr("offline"), Rect2(200, 3, 70, 28), 13, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	var gender: TextureRect = UiKit.art(row, PixelIcons.get_icon("male" if person.gender == "m" else "female"), Rect2(288, 6, 22, 22))
	gender.modulate = Color(1, 1, 1, 0.6) if away else Color.WHITE
