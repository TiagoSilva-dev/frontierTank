class_name ChallengeScreen
extends Control

# The daily challenge (0.22): today's battle (the same for everyone), its medals, the best
# of the day, the ranking of the day (online, the replays of the best runs can be watched)
# and the replays kept on this computer.

signal closed

var app: Node
var tab: String = "today"
var board: Dictionary = {}
var loading: bool = false
var message: String = ""
var tick: float = 0.0

static func open(host: Node, game: Node) -> ChallengeScreen:
	var screen: ChallengeScreen = ChallengeScreen.new()
	screen.app = game
	host.add_child(screen)
	return screen

func _ready() -> void:
	size = Vector2(1280, 720)
	build()

func day() -> int:
	return Challenge.day_id()

func build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	PremiumUi.window(self, Rect2(110, 36, 1060, 648), tr("DESAFIO DO DIA"), tr("O mesmo duelo para todos, todo dia. Renova em %s.") % time_left(), 0.94, 36)
	UiKit.button(self, tr("FECHAR"), Rect2(1004, 54, 142, 38), close).name = "CloseChallenge"
	var tabs: Array = [["today", tr("HOJE")], ["top", tr("RANKING DO DIA")], ["replays", tr("REPLAYS")]]
	for i in range(tabs.size()):
		var button: Button = UiKit.button(self, str(tabs[i][1]), Rect2(130 + i * 214, 112, 206, 32), select_tab.bind(str(tabs[i][0])), "tab_active" if tab == tabs[i][0] else "tab", 16)
		button.name = "ChallengeTab_" + str(tabs[i][0])
	match tab:
		"today":
			build_today()
		"top":
			build_top()
		"replays":
			build_replays()
	if message != "":
		UiKit.label(self, message, Rect2(130, 654, 1020, 22), 14, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func time_left() -> String:
	var seconds: int = Challenge.seconds_left()
	return "%d h %02d min" % [seconds / 3600, (seconds % 3600) / 60]

func select_tab(value: String) -> void:
	tab = value
	message = ""
	build()
	if value == "top":
		load_board()

func map_name(id: String) -> String:
	for entry: Dictionary in app.balance.maps:
		if str(entry.id) == id:
			return tr(str(entry.name))
	return id

func build_today() -> void:
	var spec: Dictionary = Challenge.spec_for(day())
	var kind: Dictionary = Challenge.kind_def(str(spec.kind))
	UiKit.panel(self, Rect2(130, 148, 560, 510), "paper")
	UiKit.label(self, tr(str(kind.name)), Rect2(150, 156, 520, 36), 28, PremiumUi.GOLD, UiKit.INK)
	var about: Label = UiKit.wrapped(self, tr(str(kind.description)), Rect2(150, 196, 520, 50), 16, UiKit.TEXT)
	UiKit.panel(self, Rect2(150, 256, 520, 86), "slot_light")
	var weapon_item: Dictionary = Challenge.weapon_entry(str(spec.weapon))
	UiKit.art(self, Armory.weapon_icon(str(spec.weapon), 3), Rect2(158, 262, 74, 74))
	UiKit.label(self, tr("Arma do dia (igual para todos)"), Rect2(244, 262, 420, 22), 14, UiKit.TEXT_MUTED)
	UiKit.label(self, Armory.item_name(weapon_item), Rect2(244, 284, 420, 28), 20, UiKit.TEXT)
	UiKit.label(self, tr("Mapa: %s  ·  %d turnos") % [map_name(str(spec.map)), int(spec.turns)], Rect2(244, 312, 420, 24), 15, UiKit.TEXT_MUTED)
	UiKit.label(self, tr("Medalhas"), Rect2(150, 354, 200, 24), 16, PremiumUi.GOLD)
	for i in range(3):
		var at: Vector2 = Vector2(150 + i * 176, 382)
		var chip: Panel = UiKit.panel(self, Rect2(at, Vector2(166, 46)), "slot")
		var dot: Control = Control.new()
		dot.position = at + Vector2(8, 8)
		dot.size = Vector2(30, 30)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color: Color = Challenge.medal_color(i + 1)
		dot.draw.connect(func() -> void:
			dot.draw_circle(Vector2(15, 15), 14.0, Color("120a04"))
			dot.draw_circle(Vector2(15, 15), 11.0, color))
		add_child(dot)
		UiKit.label(chip, "%s  %d" % [Challenge.medal_name(i + 1), int(spec.medals[i])], Rect2(44, 10, 118, 26), 15, UiKit.TEXT)
	var mine: bool = int(app.profile.challenge.day) == day()
	UiKit.label(self, tr("Seu melhor hoje"), Rect2(150, 444, 300, 24), 16, PremiumUi.GOLD)
	if mine:
		UiKit.label(self, "%d  ·  %s" % [int(app.profile.challenge.best), Challenge.medal_name(int(app.profile.challenge.medal))], Rect2(150, 470, 520, 36), 26, Challenge.medal_color(int(app.profile.challenge.medal)), UiKit.INK)
		UiKit.label(self, tr("A recompensa do dia já foi recebida."), Rect2(150, 508, 520, 24), 15, UiKit.GOOD)
	else:
		UiKit.label(self, tr("Ainda não jogou hoje."), Rect2(150, 472, 520, 30), 18, UiKit.TEXT_MUTED)
		UiKit.label(self, tr("Recompensa do primeiro resultado do dia: %s") % Challenge.reward_text(), Rect2(150, 508, 520, 24), 15, UiKit.GOOD)
	UiKit.button(self, tr("JOGAR"), Rect2(210, 560, 400, 56), app.start_challenge, "button_green", 28).name = "ChallengePlay"
	UiKit.panel(self, Rect2(706, 148, 456, 510), "paper")
	UiKit.label(self, tr("Como funciona"), Rect2(726, 158, 420, 28), 20, PremiumUi.GOLD)
	var rules: Label = UiKit.wrapped(self, tr("Todos jogam o mesmo mapa, com a mesma arma e os mesmos atributos: o equipamento de ninguém conta.\n\nSe quiser, tente quantas vezes quiser; vale o melhor resultado do dia.\n\nOnline, o servidor refaz a sua partida a partir da gravação e confere a pontuação antes de ela entrar no ranking.\n\nA gravação fica no seu computador: veja em REPLAYS."), Rect2(726, 192, 416, 440), 16, UiKit.TEXT)
	rules.vertical_alignment = VERTICAL_ALIGNMENT_TOP

func load_board() -> void:
	if not app.online:
		return
	loading = true
	var reply: Dictionary = await app.net.request("challenge_info", {"day": day()})
	if not is_inside_tree() or tab != "top":
		return
	loading = false
	board = reply if reply.ok else {}
	if not reply.ok:
		message = app.server_text(reply.get("error", ""))
	build()

func build_top() -> void:
	UiKit.panel(self, Rect2(130, 148, 1032, 510), "paper")
	if not app.online:
		UiKit.label(self, tr("O ranking do dia só existe online. Escolha um servidor na tela de entrada."), Rect2(150, 280, 992, 60), 20, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var rows: Array = board.get("rows", [])
	if rows.is_empty():
		UiKit.label(self, tr("Carregando…") if loading else tr("Ninguém terminou o desafio de hoje ainda. Seja o primeiro!"), Rect2(150, 280, 992, 60), 20, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var spec: Dictionary = Challenge.spec_for(day())
	for entry: Array in [["#", 156, 40], [tr("Jogador"), 210, 280], [tr("Pontos"), 520, 90], [tr("Medalha"), 640, 140]]:
		UiKit.label(self, str(entry[0]), Rect2(float(entry[1]), 156, float(entry[2]), 22), 14, UiKit.TEXT_MUTED)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(146, 182)
	scroll.size = Vector2(1000, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(984, 0)
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)
	for entry: Dictionary in rows:
		var mine: bool = int(entry.account) == int(app.my_account())
		var row: Panel = UiKit.panel(box, Rect2(0, 0, 984, 38), "slot_light" if mine else "slot")
		row.custom_minimum_size = Vector2(984, 38)
		row.name = "ChallengeRow_%d" % int(entry.position)
		var score: int = int(entry.score)
		var medal: int = 0
		for i in range(3):
			if score >= int(spec.medals[i]):
				medal = i + 1
		UiKit.label(row, str(int(entry.position)), Rect2(10, 6, 40, 26), 16, PremiumUi.GOLD if int(entry.position) <= 3 else UiKit.TEXT)
		UiKit.clipped(row, str(entry.name), Rect2(64, 6, 280, 26), 16, Color.WHITE if mine else UiKit.TEXT)
		UiKit.label(row, str(score), Rect2(374, 6, 90, 26), 17, UiKit.TEXT)
		UiKit.label(row, Challenge.medal_name(medal), Rect2(494, 6, 140, 26), 15, Challenge.medal_color(medal))
		UiKit.button(row, tr("ASSISTIR"), Rect2(860, 3, 112, 32), watch_top.bind(int(entry.account)), "button_green", 13).name = "WatchTop_%d" % int(entry.position)
	var position: int = int(board.get("position", 0))
	var footer: String = tr("Você está na posição %d de %d jogadores.") % [position, int(board.get("total", 0))] if position > 0 else tr("Termine o desafio de hoje para entrar na lista (%d jogadores).") % int(board.get("total", 0))
	UiKit.label(self, footer, Rect2(150, 622, 992, 26), 16, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)

func watch_top(account: int) -> void:
	var reply: Dictionary = await app.net.request("challenge_replay", {"day": day(), "account": account}, 30.0)
	if not is_inside_tree():
		return
	if not reply.ok:
		message = app.server_text(reply.get("error", ""))
		build()
		return
	var clean: Dictionary = Replay.clean(reply.replay, true)
	if clean.is_empty():
		message = tr("A gravação não pôde ser lida.")
		build()
		return
	app.start_replay(clean)

func build_replays() -> void:
	UiKit.panel(self, Rect2(130, 148, 1032, 510), "paper")
	var files: Array = Replay.list()
	if files.is_empty():
		var empty: Label = UiKit.wrapped(self, tr("Nenhuma gravação ainda. As partidas online e os desafios que você joga ficam aqui (as %d últimas).") % Replay.KEEP, Rect2(170, 270, 952, 80), 20, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	for i in range(mini(files.size(), 10)):
		var path: String = str(files[i])
		var replay: Dictionary = Replay.load_file(path)
		var row: Panel = UiKit.panel(self, Rect2(146, 158 + i * 48, 1000, 42), "slot")
		row.name = "ReplayRow_%d" % i
		if replay.is_empty():
			UiKit.label(row, tr("Gravação ilegível"), Rect2(14, 8, 600, 26), 16, UiKit.BAD)
			UiKit.button(row, tr("APAGAR"), Rect2(890, 5, 100, 32), delete_replay.bind(path), "button_red", 13)
			continue
		var meta: Dictionary = replay.meta
		var seconds: int = int(replay.ticks) / 60
		UiKit.clipped(row, Replay.describe(replay), Rect2(14, 8, 560, 26), 16, UiKit.TEXT)
		var result_text: String = ""
		if str(meta.get("kind", "")) == "challenge":
			result_text = tr("%d pontos") % int(meta.get("score", 0))
		elif meta.has("won"):
			result_text = tr("Vitória") if bool(meta.won) else tr("Derrota")
		UiKit.label(row, result_text, Rect2(590, 8, 130, 26), 16, UiKit.GOOD if bool(meta.get("won", false)) or str(meta.get("kind", "")) == "challenge" else UiKit.BAD)
		UiKit.label(row, "%d:%02d" % [seconds / 60, seconds % 60], Rect2(730, 8, 70, 26), 15, UiKit.TEXT_MUTED)
		UiKit.button(row, tr("ASSISTIR"), Rect2(800, 5, 100, 32), app.start_replay.bind(replay), "button_green", 13).name = "WatchReplay_%d" % i
		UiKit.button(row, tr("APAGAR"), Rect2(906, 5, 84, 32), delete_replay.bind(path), "button", 13)

func delete_replay(path: String) -> void:
	Replay.delete(path)
	build()

func close() -> void:
	closed.emit()
	queue_free()
