class_name HallScreen
extends Control

# Salão de Jogos: room list (2 x 4 per page), user info, online list and quick actions.

const PER_PAGE: int = 8
var app: Node
var page: int = 0
var filter: int = 0
var grid: Control
var page_label: Label
var player_rows: VBoxContainer

func _ready() -> void:
	size = Vector2(1280, 720)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("3a1d0c")
	backdrop.size = size
	add_child(backdrop)
	var speaker: SpeakerBar = SpeakerBar.new()
	speaker.app = app
	add_child(speaker)
	UiKit.panel(self, Rect2(6, 32, 894, 476), "wood")
	UiKit.panel(self, Rect2(318, 26, 280, 46), "plate")
	UiKit.title(self, "Salão de jogos", Rect2(318, 26, 280, 46), 24)
	UiKit.label(self, "Lista de salas", Rect2(26, 78, 150, 30), 18, Color.WHITE, UiKit.INK)
	var modes: OptionButton = OptionButton.new()
	for text: String in ["Todas as modalidades", "Combate Livre", "Aguardando jogadores"]:
		modes.add_item(text)
	modes.position = Vector2(170, 78)
	modes.size = Vector2(230, 30)
	modes.focus_mode = Control.FOCUS_NONE
	modes.add_theme_font_override("font", UiKit.font(true))
	modes.add_theme_font_size_override("font_size", UiKit.fs(14))
	modes.item_selected.connect(func(index: int) -> void:
		filter = index
		page = 0
		build_rooms())
	add_child(modes)
	UiKit.label(self, "Canal atual", Rect2(690, 70, 190, 18), 13, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.panel(self, Rect2(716, 88, 140, 24), "slot")
	UiKit.label(self, "Canal 1", Rect2(716, 88, 140, 24), 14, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.panel(self, Rect2(18, 116, 870, 338), "paper")
	grid = Control.new()
	grid.position = Vector2(26, 124)
	grid.size = Vector2(856, 324)
	add_child(grid)
	UiKit.panel(self, Rect2(20, 462, 560, 34), "dark")
	page_label = UiKit.label(self, "", Rect2(30, 462, 540, 34), 14, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(self, "◀ Anterior", Rect2(600, 460, 140, 36), func() -> void: turn_page(-1), "button", 15)
	UiKit.button(self, "Próximo ▶", Rect2(748, 460, 140, 36), func() -> void: turn_page(1), "button", 15)
	build_user_info()
	build_player_list()
	build_actions()
	var chat: ChatBox = ChatBox.new()
	chat.app = app
	chat.position = Vector2(4, 520)
	add_child(chat)
	var bar: BottomBar = BottomBar.new()
	bar.app = app
	bar.position = Vector2(714, 656)
	add_child(bar)
	app.lobby.rooms_changed.connect(build_rooms)
	build_rooms()

func visible_rooms() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Dictionary in app.lobby.rooms:
		if filter == 2 and (room.playing or room.members.size() >= int(room.capacity)):
			continue
		result.append(room)
	return result

func turn_page(step: int) -> void:
	var pages: int = maxi(1, ceili(visible_rooms().size() / float(PER_PAGE)))
	page = clampi(page + step, 0, pages - 1)
	build_rooms()

func build_rooms() -> void:
	for child in grid.get_children():
		child.queue_free()
	var rooms: Array[Dictionary] = visible_rooms()
	var pages: int = maxi(1, ceili(rooms.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = page * PER_PAGE + i
		var rect: Rect2 = Rect2((i % 2) * 432, (i / 2) * 81, 424, 74)
		if index >= rooms.size():
			var empty: Panel = UiKit.panel(grid, rect, "card_busy")
			empty.modulate.a = 0.35
			continue
		room_card(rooms[index], rect)
	var waiting: int = rooms.filter(func(r: Dictionary) -> bool: return not r.playing).size()
	page_label.text = "Página %d/%d  •  %d salas aguardando  •  %d em jogo" % [page + 1, pages, waiting, rooms.size() - waiting]

func room_card(room: Dictionary, rect: Rect2) -> void:
	var full: bool = room.members.size() >= int(room.capacity)
	var busy: bool = room.playing or full
	var card: Button = UiKit.button(grid, "", rect, func() -> void: try_join(room), "card_busy" if busy else "card")
	card.name = "Room_%d" % int(room.id)
	card.tooltip_text = "Sala %d — %s" % [room.id, room.title]
	UiKit.label(card, "Desafio", Rect2(12, 2, 150, 24), 17, Color("ffd04a"), Color("6a2a08"))
	UiKit.label(card, "das Lutas", Rect2(12, 20, 150, 24), 17, Color("ffd04a"), Color("6a2a08"))
	UiKit.label(card, "#%d" % int(room.id), Rect2(128, 6, 80, 20), 13, Color("7a4a20"))
	var title: Label = UiKit.label(card, str(room.title), Rect2(12, 46, 212, 22), 13, Color("5a2e10"))
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size = Vector2(212, 22)
	UiKit.label(card, "%d/%d" % [room.members.size(), int(room.capacity)], Rect2(228, 44, 60, 24), 17, Color("3a1a06"))
	var status: String = "Em jogo" if room.playing else ("Cheia" if full else "Aberta")
	UiKit.label(card, status, Rect2(228, 8, 70, 22), 13, Color("c0402f") if busy else Color("2f8a1f"))
	UiKit.panel(card, Rect2(296, 8, 118, 58), "slot")
	UiKit.art(card, PixelIcons.get_icon("star"), Rect2(302, 12, 22, 22))
	var map_name: String = "Mapa\nAleatório" if str(room.map) == "" else str(room.map)
	UiKit.label(card, map_name, Rect2(318, 10, 94, 54), 13, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	if room.playing:
		UiKit.art(card, PixelIcons.get_icon("lock"), Rect2(386, 40, 22, 22))

func try_join(room: Dictionary) -> void:
	if room.playing:
		UiKit.notice(self, "SALA EM JOGO", "A sala %d está em batalha. Escolha outra sala ou aguarde." % int(room.id))
	elif room.members.size() >= int(room.capacity):
		UiKit.notice(self, "SALA CHEIA", "A sala %d está cheia." % int(room.id))
	else:
		app.audio.tone(620, 0.1)
		app.join_room(room)

func build_user_info() -> void:
	var box: Panel = UiKit.panel(self, Rect2(906, 32, 368, 300), "wood")
	UiKit.label(box, "Informações do usuário", Rect2(0, 6, 368, 26), 16, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.panel(box, Rect2(12, 34, 344, 256), "paper")
	UiKit.panel(box, Rect2(18, 40, 332, 28), "dark")
	UiKit.label(box, app.profile.player_name, Rect2(26, 40, 316, 28), 17, Color.WHITE, UiKit.INK)
	UiKit.label(box, "Ranking", Rect2(22, 72, 70, 22), 13, Color("c0402f"))
	UiKit.label(box, str(app.profile.ranking()), Rect2(92, 72, 70, 22), 15, UiKit.TEXT_DARK)
	UiKit.label(box, "Méritos", Rect2(186, 72, 70, 22), 13, Color("1f6fd0"))
	UiKit.label(box, str(app.profile.merits), Rect2(256, 72, 80, 22), 15, UiKit.TEXT_DARK)
	var stage: Panel = UiKit.panel(box, Rect2(60, 94, 220, 148), Color(0, 0, 0, 0))
	stage.clip_contents = true
	AvatarView.create(stage, app.profile.look(), Rect2(0, 0, 220, 148))
	UiKit.level_badge(box, app.profile.level(), Rect2(292, 100, 44, 30))
	UiKit.label(box, TankFighter.rank_for(app.profile.level()), Rect2(250, 132, 100, 22), 13, Color("2f8a1f"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var goals: Array[int] = [1, 5, 10, 25, 50, 100]
	for i in range(goals.size()):
		var slot: Panel = UiKit.panel(box, Rect2(22 + i * 54, 244, 46, 40), "slot")
		var unlocked: bool = app.profile.victories >= goals[i]
		var icon: TextureRect = UiKit.art(slot, PixelIcons.get_icon("trophy" if unlocked else "lock"), Rect2(9, 6, 28, 28))
		icon.modulate = Color.WHITE if unlocked else Color(1, 1, 1, 0.35)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.tooltip_text = "Conquista: %d vitória(s)" % goals[i]

func build_player_list() -> void:
	var box: Panel = UiKit.panel(self, Rect2(906, 336, 368, 316), "wood")
	UiKit.panel(box, Rect2(10, 8, 348, 30), "plate")
	UiKit.label(box, "Nível", Rect2(20, 8, 120, 30), 15, Color("ffe6a0"), UiKit.INK)
	UiKit.label(box, "Sexo", Rect2(270, 8, 80, 30), 15, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.panel(box, Rect2(10, 42, 348, 264), "paper")
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(14, 46)
	scroll.size = Vector2(340, 256)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	player_rows = VBoxContainer.new()
	player_rows.custom_minimum_size = Vector2(324, 0)
	player_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(player_rows)
	var everyone: Array[Dictionary] = app.lobby.bots.duplicate()
	everyone.append({"name": app.profile.player_name, "level": app.profile.level(), "gender": app.profile.gender, "me": true})
	everyone.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
	for person: Dictionary in everyone:
		var row: Control = Control.new()
		row.custom_minimum_size = Vector2(324, 30)
		var tint: ColorRect = ColorRect.new()
		tint.color = Color("fff0c0") if person.get("me", false) else Color(1, 1, 1, 0.0)
		tint.size = Vector2(324, 30)
		row.add_child(tint)
		UiKit.level_badge(row, int(person.level), Rect2(4, 3, 34, 24))
		UiKit.label(row, str(person.name), Rect2(46, 2, 200, 26), 16, Color("ffd04a") if not person.get("me", false) else Color("2f8a1f"), Color("5a2408"))
		UiKit.art(row, PixelIcons.get_icon("male" if person.gender == "m" else "female"), Rect2(282, 4, 22, 22))
		player_rows.add_child(row)

func build_actions() -> void:
	UiKit.panel(self, Rect2(512, 510, 388, 144), "wood")
	var hint: Panel = UiKit.panel(self, Rect2(522, 516, 368, 28), "banner")
	UiKit.label(hint, "Clique em \"Jogar\" para começar o combate", Rect2(0, 0, 368, 28), 13, Color("fff4a0"), Color("5a1004"), HORIZONTAL_ALIGNMENT_CENTER)
	var actions: Array = [["team", "Equipe", create_team, "Criar uma sala com a sua equipe"], ["search", "Buscar", search_room, "Entrar numa sala pelo número"], ["play", "Jogar", quick_play, "Entrar na primeira sala disponível"]]
	for i in range(3):
		var action: Array = actions[i]
		var button: Button = UiKit.icon_button(self, PixelIcons.get_icon(action[0]), Rect2(532 + i * 122, 546, 104, 104), action[2], action[3])
		button.name = "Action_" + str(action[1])
		UiKit.label(button, action[1], Rect2(-6, 72, 116, 32), 22, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		var icon: TextureRect = button.get_node("Icon")
		icon.size = Vector2(104, 74)

func create_team() -> void:
	app.audio.tone(620, 0.1)
	app.create_room("pvp")
	app.show_room()

func quick_play() -> void:
	var room: Dictionary = app.lobby.open_room()
	if room.is_empty():
		create_team()
	else:
		app.join_room(room)

func search_room() -> void:
	var dialog: Control = UiKit.modal(self, "BUSCAR SALA", "Digite o número da sala:")
	var rect: Rect2 = dialog.get_meta("rect")
	var field: LineEdit = LineEdit.new()
	field.position = rect.position + Vector2(rect.size.x / 2 - 90, 110)
	field.size = Vector2(180, 36)
	field.max_length = 3
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_override("font", UiKit.font(true))
	field.add_theme_font_size_override("font_size", UiKit.fs(20))
	dialog.add_child(field)
	var submit: Callable = func() -> void:
		var room: Dictionary = app.lobby.find_room(field.text.to_int())
		dialog.queue_free()
		if room.is_empty():
			UiKit.notice(self, "BUSCAR SALA", "Sala %s não encontrada neste canal." % field.text)
		else:
			try_join(room)
	field.text_submitted.connect(func(_text: String) -> void: submit.call())
	UiKit.button(dialog, "ENTRAR", Rect2(rect.position.x + 90, rect.end.y - 60, 150, 42), submit)
	UiKit.button(dialog, "CANCELAR", Rect2(rect.end.x - 240, rect.end.y - 60, 150, 42), dialog.queue_free)
