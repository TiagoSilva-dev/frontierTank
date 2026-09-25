class_name RoomScreen
extends Control

# Sala: your team (4 slots), mode, map/time info, battle tools, invite and start.

const VS_ART: String = "res://assets/room/vs_art.png"
var app: Node
var content: Control
var searching: Control
var search_time: float = -1.0
var ready_time: float = -1.0
var spin: float = 0.0

func _ready() -> void:
	size = Vector2(1280, 720)
	rebuild()

func rebuild() -> void:
	if is_instance_valid(content):
		content.queue_free()
	content = Control.new()
	content.size = size
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	move_child(content, 0)
	var room: Dictionary = app.room
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("3a1d0c")
	backdrop.size = size
	content.add_child(backdrop)
	var speaker: SpeakerBar = SpeakerBar.new()
	speaker.app = app
	content.add_child(speaker)
	build_slots(room)
	build_center(room)
	build_tools(room)
	build_buttons(room)
	var chat: ChatBox = ChatBox.new()
	chat.app = app
	chat.position = Vector2(4, 520)
	content.add_child(chat)
	var bar: BottomBar = BottomBar.new()
	bar.app = app
	bar.position = Vector2(714, 656)
	content.add_child(bar)

func build_slots(room: Dictionary) -> void:
	UiKit.panel(content, Rect2(6, 32, 454, 444), "wood")
	for i in range(4):
		var rect: Rect2 = Rect2(18 + (i % 2) * 218, 44 + (i / 2) * 212, 210, 204)
		if i < room.members.size():
			member_slot(room, i, rect)
		else:
			var empty: Button = UiKit.button(content, "", rect, func() -> void: invite(), "card_busy")
			empty.name = "Slot_%d" % i
			empty.tooltip_text = "Convide um jogador (IA)" if app.is_owner() else ""
			var ghost: TextureRect = UiKit.art(empty, PixelIcons.get_icon("team"), Rect2(55, 40, 100, 100))
			ghost.modulate = Color(1, 1, 1, 0.3)
			UiKit.label(empty, "Aguardando…", Rect2(0, 150, 210, 30), 18, Color("fff0d0"), Color("7a5a3a"), HORIZONTAL_ALIGNMENT_CENTER)

func member_slot(room: Dictionary, index: int, rect: Rect2) -> void:
	var member: Dictionary = room.members[index]
	var slot: Panel = UiKit.panel(content, rect, "card")
	slot.name = "Slot_%d" % index
	slot.clip_contents = true
	# Everyone shows up dressed: outfit, hat, wings, weapon on the back and auras.
	AvatarView.create(slot, member_look(member), Rect2(10, 30, 190, 140))
	UiKit.panel(slot, Rect2(6, 6, 198, 28), "dark")
	UiKit.label(slot, str(member.name), Rect2(40, 6, 160, 28), 16, Color("ffd04a") if member.get("human", false) else Color.WHITE, UiKit.INK)
	UiKit.level_badge(slot, int(member.level), Rect2(8, 8, 30, 24))
	if index == int(room.owner):
		UiKit.panel(slot, Rect2(6, 168, 70, 30), "plate")
		UiKit.label(slot, "Dono", Rect2(6, 168, 70, 30), 16, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.art(slot, PixelIcons.get_icon("crown"), Rect2(170, 40, 28, 28))
	elif member.get("human", false) and not room.get("ready", false):
		UiKit.label(slot, "Não preparado", Rect2(6, 170, 198, 28), 15, Color("c0402f"), Color("fff0d0"), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		UiKit.art(slot, "res://assets/expansion/lobby/ready_icon.png", Rect2(8, 166, 32, 32))
		UiKit.label(slot, "Pronto", Rect2(40, 168, 80, 30), 15, Color("2f8a1f"), Color("fff0d0"))
	if app.is_owner() and not member.get("human", false):
		var kick: Button = UiKit.button(slot, "X", Rect2(172, 170, 30, 28), kick_member.bind(index), "button", 14)
		kick.tooltip_text = "Remover da sala"

func build_center(room: Dictionary) -> void:
	UiKit.panel(content, Rect2(466, 32, 384, 432), "wood_dark")
	var art_box: Panel = UiKit.panel(content, Rect2(476, 42, 364, 300), "slot")
	art_box.clip_contents = true
	if room.mode == "pve":
		UiKit.art(art_box, "res://assets/expansion/lobby/instance_preview.png", Rect2(4, 4, 356, 200), false)
		UiKit.art(art_box, "res://assets/pve/rei_sol.png", Rect2(210, 90, 150, 150))
		UiKit.title(art_box, "Templo do Sol", Rect2(0, 206, 364, 34), 24)
		UiKit.label(art_box, "Chefe: Rei Hélio  •  Fúria abaixo de 50% de vida", Rect2(0, 238, 364, 22), 13, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		var difficulties: Array = app.balance.pve.difficulties
		for i in range(difficulties.size()):
			var entry: Dictionary = difficulties[i]
			var selected: bool = entry.id == room.difficulty
			var chip: Button = UiKit.button(art_box, "", Rect2(10 + i * 88, 262, 82, 34), pick_difficulty.bind(str(entry.id)), "tab_active" if selected else "tab")
			chip.name = "Difficulty_" + str(entry.id)
			UiKit.art(chip, str(entry.icon), Rect2(4, 5, 24, 24))
			UiKit.label(chip, str(entry.name), Rect2(28, 0, 54, 34), 12, Color.WHITE, UiKit.INK)
	else:
		if ResourceLoader.exists(VS_ART):
			UiKit.art(art_box, VS_ART, Rect2(0, 0, 364, 300), false)
		else:
			var versus: Control = Control.new()
			versus.size = Vector2(364, 300)
			versus.draw.connect(func() -> void: draw_versus(versus))
			art_box.add_child(versus)
			UiKit.art(art_box, "res://assets/characters/nilo/east.png", Rect2(-6, 70, 200, 220))
			UiKit.art(art_box, "res://assets/characters/lia/west.png", Rect2(172, 70, 200, 220))
			var vs: Label = UiKit.label(art_box, "VS", Rect2(0, 40, 364, 110), 84, Color("ffd04a"), Color("b8320c"), HORIZONTAL_ALIGNMENT_CENTER)
			vs.add_theme_constant_override("outline_size", 14)
	var modes: Array = [["Combate Livre", "1. Sem limite\n2. Cenário sorteado\n3. Níveis próximos", room.mode == "pvp"], ["Guerra Soc.", "1. 2+ jogadores\n2. Mesma sociedade", false]]
	if room.mode == "pve":
		modes = [["Instância", "1. Até 4 contra o chefe\n2. Dificuldade: vida e dano\n3. Super armas no drop", true], ["Guerra Soc.", "1. 2+ jogadores\n2. Mesma sociedade", false]]
	for i in range(2):
		var mode: Array = modes[i]
		var box: Panel = UiKit.panel(content, Rect2(476 + i * 184, 348, 180, 110), "mode_green" if mode[2] else "mode_gray")
		UiKit.label(box, mode[0], Rect2(8, 2, 170, 24), 16, Color("b8ff9a") if mode[2] else Color("c8c8c8"), UiKit.INK)
		var rules: Label = UiKit.label(box, mode[1], Rect2(8, 26, 168, 80), 11, Color.WHITE if mode[2] else Color("a8a8a8"), Color("101010"))
		rules.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not mode[2]:
			box.mouse_filter = Control.MOUSE_FILTER_PASS
			box.tooltip_text = "Você ainda não participa de uma sociedade."
	var info: Panel = UiKit.panel(content, Rect2(520, 470, 290, 116), "wood")
	UiKit.label(info, "Informações", Rect2(10, 2, 200, 24), 15, Color("ffe6a0"), UiKit.INK)
	var map_box: Panel = UiKit.panel(info, Rect2(10, 28, 270, 80), "paper")
	var map_name: String = "Mapa Aleatório"
	for entry: Dictionary in app.balance.maps:
		if entry.id == room.map:
			map_name = str(entry.name)
			UiKit.art(map_box, str(entry.bg), Rect2(8, 8, 96, 64), false)
	if map_name == "Mapa Aleatório":
		UiKit.art(map_box, PixelIcons.get_icon("star"), Rect2(20, 12, 56, 56))
	UiKit.label(map_box, map_name, Rect2(108, 6, 160, 44), 17, Color("c0602f"), Color("fff0d0"), HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.label(map_box, "%d seg por turno" % int(room.turn_seconds), Rect2(108, 50, 130, 24), 14, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var gear: Button = UiKit.icon_button(map_box, PixelIcons.get_icon("gear"), Rect2(240, 46, 26, 26), cycle_time, "Tempo por turno (10/15/20 s)")
	gear.name = "TimeGear"

func draw_versus(canvas: Control) -> void:
	for i in range(14):
		var t: float = i / 13.0
		canvas.draw_rect(Rect2(0, i * 22, 364, 22), Color("2a1a4a").lerp(Color("c85a2a"), t))
	for i in range(12):
		var a: float = i * TAU / 12 + spin * 0.2
		var tip: Vector2 = Vector2(182, 96) + Vector2.from_angle(a) * 260
		var side: Vector2 = Vector2.from_angle(a + 0.12) * 260
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(182, 96), tip, Vector2(182, 96) + side]), Color(1, 0.8, 0.3, 0.12))
	var bolt: PackedVector2Array = PackedVector2Array([Vector2(196, 20), Vector2(160, 92), Vector2(190, 92), Vector2(156, 170), Vector2(222, 78), Vector2(190, 78), Vector2(214, 20)])
	canvas.draw_colored_polygon(bolt, Color("ff8a1a"))
	canvas.draw_polyline(bolt + PackedVector2Array([bolt[0]]), Color("fff4a0"), 3)

func build_tools(room: Dictionary) -> void:
	var box: Panel = UiKit.panel(content, Rect2(856, 32, 418, 380), "wood")
	UiKit.label(box, "Sala", Rect2(14, 4, 60, 40), 26, Color("fff0d0"), UiKit.INK)
	UiKit.label(box, str(room.id), Rect2(74, 4, 90, 40), 30, Color("ffd04a"), UiKit.INK)
	UiKit.label(box, "Canal 1", Rect2(300, 8, 104, 26), 15, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	var subtitle: Label = UiKit.label(box, str(room.title), Rect2(14, 42, 390, 24), 14, Color("ffe24a"), UiKit.INK)
	subtitle.clip_text = true
	UiKit.panel(box, Rect2(12, 70, 394, 300), "paper")
	UiKit.panel(box, Rect2(100, 76, 218, 26), "plate")
	UiKit.label(box, "MINHAS FERRAMENTAS", Rect2(100, 76, 218, 26), 14, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(3):
		var id: String = app.profile.tools[i]
		var slot: Button = UiKit.button(box, "", Rect2(82 + i * 90, 108, 72, 72), func() -> void: sell_tool(i), "slot")
		slot.name = "MyTool_%d" % i
		UiKit.label(slot, ["Z", "X", "C"][i], Rect2(4, 0, 20, 20), 13, Color("ffe6a0"), UiKit.INK)
		if id != "":
			var tool: Dictionary = tool_def(id)
			UiKit.art(slot, str(tool.icon), Rect2(12, 12, 48, 48))
			slot.tooltip_text = "%s\n%s\nClique para devolver (+%d moedas)" % [tool.name, tool.desc, int(tool.price)]
	UiKit.panel(box, Rect2(90, 188, 238, 26), "plate")
	UiKit.label(box, "FERRAMENTAS A COMPRAR", Rect2(90, 188, 238, 26), 14, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var tools: Array = app.balance.tools
	for i in range(8):
		var rect: Rect2 = Rect2(40 + (i % 4) * 88, 220 + (i / 4) * 74, 70, 68)
		if i >= tools.size():
			var locked: Panel = UiKit.panel(box, rect, "slot")
			UiKit.art(locked, PixelIcons.get_icon("lock"), Rect2(21, 16, 28, 28)).modulate.a = 0.5
			continue
		var tool: Dictionary = tools[i]
		var button: Button = UiKit.button(box, "", rect, func() -> void: buy_tool(str(tool.id)), "slot")
		button.name = "Shop_%s" % tool.id
		button.tooltip_text = "%s — %d moedas\n%s" % [tool.name, int(tool.price), tool.desc]
		UiKit.art(button, str(tool.icon), Rect2(15, 4, 40, 40))
		UiKit.label(button, str(int(tool.price)), Rect2(0, 44, 70, 20), 13, Color("ffd04a"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.art(box, "res://assets/items/moeda.png", Rect2(326, 78, 22, 22))
	UiKit.label(box, str(app.profile.coins), Rect2(350, 76, 56, 26), 15, Color("7a4a20"))

func build_buttons(room: Dictionary) -> void:
	UiKit.panel(content, Rect2(856, 420, 418, 232), "wood_dark")
	var hint: Panel = UiKit.panel(content, Rect2(866, 430, 398, 34), "banner")
	var start_text: String = "Início" if app.is_owner() else ("Cancelar" if room.get("ready", false) else "Preparar")
	UiKit.label(hint, "Clique em \"%s\" para começar o jogo" % start_text if start_text != "Cancelar" else "Aguardando o dono da sala…", Rect2(0, 0, 398, 34), 14, Color("fff4a0"), Color("5a1004"), HORIZONTAL_ALIGNMENT_CENTER)
	var invite_button: Button = UiKit.icon_button(content, PixelIcons.get_icon("team"), Rect2(876, 478, 110, 110), invite, "Convidar um jogador (IA) para a equipe")
	invite_button.name = "Invite"
	UiKit.label(invite_button, "Convide", Rect2(-10, 82, 130, 30), 20, Color("b8ff9a"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	invite_button.get_node("Icon").size = Vector2(110, 84)
	var map_button: Button = UiKit.icon_button(content, PixelIcons.get_icon("search"), Rect2(1000, 478, 110, 110), choose_map, "Escolher o local (mapa) da batalha")
	map_button.name = "Local"
	UiKit.label(map_button, "Local", Rect2(-10, 82, 130, 30), 20, Color("9adcff"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	map_button.get_node("Icon").size = Vector2(110, 84)
	var start_button: Button = UiKit.icon_button(content, PixelIcons.get_icon("play"), Rect2(1130, 470, 130, 124), press_start, "Começar a partida")
	start_button.name = "Start"
	UiKit.label(start_button, start_text, Rect2(-10, 90, 150, 36), 26, Color("ffd04a"), Color("8a1a04"), HORIZONTAL_ALIGNMENT_CENTER)
	start_button.get_node("Icon").size = Vector2(130, 94)
	UiKit.button(content, "Sair da sala", Rect2(876, 604, 150, 38), app.show_hall, "button", 15)

func tool_def(id: String) -> Dictionary:
	for tool: Dictionary in app.balance.tools:
		if tool.id == id:
			return tool
	return {}

func buy_tool(id: String) -> void:
	var tool: Dictionary = tool_def(id)
	if app.profile.coins < int(tool.price):
		UiKit.notice(self, "MOEDAS INSUFICIENTES", "%s custa %d moedas." % [tool.name, int(tool.price)])
		return
	if not app.profile.add_tool(id):
		UiKit.notice(self, "FERRAMENTAS", "Seus 3 espaços (Z, X, C) estão ocupados. Clique numa ferramenta para devolvê-la.")
		return
	app.profile.coins -= int(tool.price)
	app.profile.save_profile()
	app.audio.tone(760, 0.08)
	sync_player()
	rebuild()

func sell_tool(slot: int) -> void:
	var id: String = app.profile.tools[slot]
	if id == "":
		return
	app.profile.coins += int(tool_def(id).price)
	app.profile.tools[slot] = ""
	app.profile.save_profile()
	sync_player()
	rebuild()

func sync_player() -> void:
	for i in range(app.room.members.size()):
		if app.room.members[i].get("human", false):
			app.room.members[i] = app.player_entry()

func invite() -> void:
	if not app.is_owner():
		UiKit.notice(self, "CONVITE", "Somente o dono da sala pode convidar jogadores.")
		return
	if app.room.mode == "pve" or app.room.members.size() < int(app.room.capacity):
		if app.invite_bot():
			app.audio.tone(700, 0.08)
			rebuild()
			return
	UiKit.notice(self, "SALA CHEIA", "Não há vagas livres na sua equipe.")

func choose_map() -> void:
	if not app.is_owner():
		UiKit.notice(self, "LOCAL", "Somente o dono da sala escolhe o mapa.")
		return
	if app.room.mode == "pve":
		UiKit.notice(self, "LOCAL", "A instância acontece no Templo do Sol.")
		return
	var dialog: Control = UiKit.modal(self, "ESCOLHER LOCAL", "", Vector2(700, 380))
	var rect: Rect2 = dialog.get_meta("rect")
	var options: Array = [{"id": "", "name": "Mapa Aleatório", "bg": ""}]
	for entry: Dictionary in app.balance.maps:
		if not entry.get("pve_only", false):
			options.append(entry)
	for i in range(options.size()):
		var entry: Dictionary = options[i]
		var cell: Button = UiKit.button(dialog, "", Rect2(rect.position.x + 30 + (i % 3) * 216, rect.position.y + 60 + (i / 3) * 130, 204, 120), pick_map.bind(str(entry.id), dialog), "card_hover" if app.room.map == entry.id else "card")
		cell.name = "Map_" + (str(entry.id) if entry.id != "" else "random")
		if str(entry.bg) != "":
			UiKit.art(cell, str(entry.bg), Rect2(10, 8, 184, 78), false)
		else:
			UiKit.art(cell, PixelIcons.get_icon("star"), Rect2(62, 8, 80, 78))
		UiKit.label(cell, str(entry.name), Rect2(0, 88, 204, 28), 15, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func cycle_time() -> void:
	if not app.is_owner():
		return
	# JSON numbers load as floats, so compare as ints.
	var options: Array = app.balance.turn_seconds_options.map(func(value: float) -> int: return int(value))
	var index: int = (options.find(int(app.room.turn_seconds)) + 1) % options.size()
	app.room.turn_seconds = options[index]
	rebuild()

func press_start() -> void:
	if searching != null and is_instance_valid(searching):
		return
	if app.is_owner():
		begin_search()
	else:
		app.room.ready = not app.room.get("ready", false)
		ready_time = 2.0 if app.room.ready else -1.0
		rebuild()

func begin_search() -> void:
	app.audio.tone(540, 0.2)
	searching = Control.new()
	searching.size = size
	add_child(searching)
	UiKit.dim(searching, 0.55)
	UiKit.panel(searching, Rect2(440, 270, 400, 150), "wood")
	var text: String = "Entrando na instância…" if app.room.mode == "pve" else "Procurando adversários com níveis próximos…"
	var status: Label = UiKit.label(searching, text, Rect2(450, 290, 380, 60), 18, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var spinner: Control = Control.new()
	spinner.position = Vector2(640, 380)
	spinner.draw.connect(draw_spinner.bind(spinner))
	searching.add_child(spinner)
	UiKit.button(searching, "Cancelar", Rect2(700, 382, 120, 30), cancel_search, "button", 13)
	search_time = 1.0 if app.room.mode == "pve" else 2.2

func draw_spinner(spinner: Control) -> void:
	for i in range(8):
		var p: Vector2 = Vector2.from_angle(i * TAU / 8 + spin * 4.0) * 18
		spinner.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(1, 0.85, 0.3, 0.3 + i * 0.09))

func cancel_search() -> void:
	if is_instance_valid(searching):
		searching.queue_free()
	search_time = -1.0
	if not app.is_owner():
		app.room.ready = false
		rebuild()

func kick_member(index: int) -> void:
	app.kick(index)
	rebuild()

func pick_difficulty(id: String) -> void:
	if app.is_owner():
		app.room.difficulty = id
		rebuild()

func pick_map(id: String, dialog: Control) -> void:
	app.room.map = id
	dialog.queue_free()
	rebuild()

func _process(delta: float) -> void:
	spin += delta
	if is_instance_valid(searching):
		for child in searching.get_children():
			child.queue_redraw()
	if ready_time > 0:
		ready_time -= delta
		if ready_time <= 0 and app.room.get("ready", false):
			app.lobby.post(str(app.room.members[int(app.room.owner)].name), "vamos lá!", "Atual")
			begin_search()
	if search_time > 0:
		search_time -= delta
		if search_time <= 0:
			app.start_battle()

func member_look(member: Dictionary) -> Dictionary:
	if member.has("look"):
		return member.look
	var look: Dictionary = Armory.look_for(str(member.get("gender", "m")), [])
	look.skin = UiKit.skin_for(member)
	return look
