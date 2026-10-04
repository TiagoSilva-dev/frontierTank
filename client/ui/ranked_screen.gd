class_name RankedScreen
extends Control

# The ranked ladder (0.22), online only: the player's division and progress, the queue for
# a 1v1 against another real player, the season clock, the top of the ladder and the
# cosmetic titles (claim the one a finished season gave, equip any you own).

signal closed

var app: Node
var info: Dictionary = {}
var queued: bool = false
var waiting: int = 0
var queue_clock: float = 0.0
var loading: bool = true
var message: String = ""
var asked: float = 0.0
var timer_label: Label
# The right side shows the ladder ("top") or the ranked matches going on ("live").
var right_tab: String = "top"
# Captures (--screen=ranked): made-up ladder and rating, no server.
var demo: bool = false

static func open(host: Node, game: Node) -> RankedScreen:
	var screen: RankedScreen = RankedScreen.new()
	screen.app = game
	host.add_child(screen)
	return screen

func _ready() -> void:
	size = Vector2(1280, 720)
	app.ranked_changed.connect(on_state)
	build()
	refresh()

func _exit_tree() -> void:
	if app != null and app.ranked_changed.is_connected(on_state):
		app.ranked_changed.disconnect(on_state)

# Asks the server for the season, the ladder and the queue state.
func refresh() -> void:
	if demo:
		info = demo_info()
		loading = false
		build()
		return
	loading = true
	var reply: Dictionary = await app.net.request("ranked_info", {})
	if not is_inside_tree():
		return
	loading = false
	asked = 0.0
	if reply.ok:
		info = reply
		if reply.get("profile") is Dictionary:
			app.apply_profile(reply.profile)
		set_queue(bool(reply.get("queued", false)), int(reply.get("waiting", 0)))
	else:
		message = app.server_text(reply.get("error", ""))
	build()

func demo_info() -> Dictionary:
	var rows: Array = []
	var names: Array = ["Zezinho", "NeyRJ", app.profile.player_name, "Brisa", "Lontrinha", "Scorpio", "RealTiny", "Kaiser", "Mirella", "Tiroteio"]
	for i in range(names.size()):
		rows.append({"account": i + 1 if names[i] != app.profile.player_name else -1, "name": names[i], "position": i + 1, "mmr": 1680 - i * 57, "games": 30 - i, "wins": 22 - i, "losses": 8})
	return {"season": 1, "left": 86400 * 12 + 3600 * 4, "rows": rows, "position": 3, "total": 41, "queued": false, "waiting": 0}

func set_queue(is_queued: bool, count: int) -> void:
	if is_queued and not queued:
		queue_clock = 0.0
	queued = is_queued
	waiting = count

# A queue change pushed by the server (someone joined or left, or the queue is over).
func on_state(state: Dictionary) -> void:
	set_queue(bool(state.get("queued", false)), int(state.get("waiting", 0)))
	build()

func _process(delta: float) -> void:
	asked += delta
	if queued:
		queue_clock += delta
		if is_instance_valid(timer_label):
			timer_label.text = tr("Procurando adversário…  %02d:%02d  ·  %d na fila") % [int(queue_clock) / 60, int(queue_clock) % 60, waiting]
	elif asked > 20.0 and not loading:
		refresh()

func build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var rating: Dictionary = app.profile.rating
	var season: int = int(info.get("season", rating.season))
	var left: int = int(info.get("left", 0))
	var subtitle: String = tr("Temporada %d  ·  termina em %s") % [season, left_text(left)] if left > 0 else tr("Temporada %d") % season
	PremiumUi.window(self, Rect2(110, 36, 1060, 648), tr("LIGA RANQUEADA"), subtitle, 0.94, 36)
	UiKit.button(self, tr("FECHAR"), Rect2(1004, 54, 142, 38), close).name = "CloseRanked"
	build_player(rating)
	build_ladder()

func left_text(seconds: int) -> String:
	var days: int = seconds / 86400
	var hours: int = (seconds % 86400) / 3600
	var minutes: int = (seconds % 3600) / 60
	if days > 0:
		return tr("%d d %02d h") % [days, hours]
	return tr("%d h %02d min") % [hours, minutes]

func build_player(rating: Dictionary) -> void:
	UiKit.panel(self, Rect2(130, 118, 372, 548), "paper")
	var placed: bool = Ranked.placed(rating)
	var mmr: int = int(rating.mmr)
	var division: Dictionary = Ranked.division(mmr)
	var badge: RankBadge = RankBadge.create(self, Rect2(250, 126, 132, 132), mmr, placed)
	badge.name = "RankBadge"
	var headline: String = Ranked.rating_label(rating)
	UiKit.label(self, headline, Rect2(140, 258, 352, 36), 26, division.color if placed else UiKit.TEXT, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER).name = "RankName"
	if placed:
		UiKit.label(self, tr("%d pontos") % mmr, Rect2(140, 294, 352, 26), 18, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var bar_back: Panel = UiKit.panel(self, Rect2(170, 326, 292, 14), "dark")
		var next: int = int(division.next)
		var fraction: float = 1.0 if next < 0 else clampf(float(mmr - int(division.from)) / float(maxi(1, next - int(division.from))), 0.0, 1.0)
		if fraction > 0.0:
			UiKit.panel(bar_back, Rect2(2, 2, 288.0 * fraction, 10), "button_green")
		var goal: String = tr("Divisão máxima!") if next < 0 else tr("Faltam %d pontos para %s") % [next - mmr, Ranked.label(next)]
		UiKit.label(self, goal, Rect2(140, 342, 352, 22), 14, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		UiKit.wrap(UiKit.label(self, tr("Vença ou perca %d partidas para receber a sua divisão.") % int(Ranked.data().placement_games), Rect2(150, 296, 332, 44), 15, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER), Vector2(332, 44))
	UiKit.label(self, tr("Vitórias %d   Derrotas %d   Pico %d") % [int(rating.wins), int(rating.losses), int(rating.peak)], Rect2(140, 368, 352, 24), 16, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var y: float = 398.0
	var waiting_rewards: Array = Ranked.pending(rating)
	if not waiting_rewards.is_empty():
		var entry: Dictionary = waiting_rewards[0]
		var card: Panel = UiKit.panel(self, Rect2(146, y, 340, 54), "slot_light")
		card.name = "SeasonReward"
		var reward_label: Label = UiKit.wrapped(card, tr("Temporada %d: você terminou em %s.") % [int(entry.season), Ranked.label(int(entry.mmr))], Rect2(8, 3, 226, 48), 14, UiKit.TEXT)
		UiKit.button(card, tr("RESGATAR TÍTULO"), Rect2(236, 8, 98, 38), claim_season.bind(int(entry.season)), "button_green", 12).name = "ClaimSeason"
		y += 62.0
	build_queue(y)
	build_titles(y + 66.0)
	if message != "":
		UiKit.label(self, message, Rect2(140, 646, 352, 20), 13, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func build_queue(y: float) -> void:
	var minimum: int = int(Ranked.data().min_level)
	if app.profile.level() < minimum:
		var needs: Label = UiKit.wrapped(self, tr("A liga ranqueada começa no nível %d.") % minimum, Rect2(150, y, 332, 48), 16, UiKit.BAD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	if queued:
		timer_label = UiKit.label(self, "", Rect2(140, y, 352, 24), 15, Color("9aff7a"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.button(self, tr("CANCELAR"), Rect2(186, y + 28, 260, 40), toggle_queue, "button_red", 18).name = "RankedCancel"
	else:
		UiKit.button(self, tr("BUSCAR PARTIDA"), Rect2(186, y + 4, 260, 46), toggle_queue, "button_green", 20).name = "RankedFind"
		UiKit.label(self, tr("1 contra 1 contra outro jogador. Sem bots."), Rect2(140, y + 52, 352, 18), 13, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)

func build_titles(y: float) -> void:
	UiKit.label(self, tr("Títulos"), Rect2(146, y, 200, 22), 16, PremiumUi.GOLD)
	var titles: Array = app.profile.titles
	if titles.is_empty():
		UiKit.wrap(UiKit.label(self, tr("Termine uma temporada com partidas suficientes para ganhar o título da sua divisão."), Rect2(146, y + 24, 340, 60), 13, UiKit.TEXT_MUTED), Vector2(340, 60))
		return
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(146, y + 24)
	scroll.size = Vector2(340, maxf(40.0, 646.0 - y - 28.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(330, 0)
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	for id: String in titles:
		var row: Panel = UiKit.panel(box, Rect2(0, 0, 330, 34), "slot")
		row.custom_minimum_size = Vector2(330, 34)
		var equipped: bool = app.profile.title == id
		UiKit.clipped(row, Ranked.title_text(id), Rect2(8, 4, 210, 26), 14, PremiumUi.GOLD if equipped else UiKit.TEXT)
		var button: Button = UiKit.button(row, tr("TIRAR") if equipped else tr("USAR"), Rect2(222, 3, 90, 28), set_title.bind("" if equipped else id), "button" if equipped else "button_green", 13)
		button.name = "Title_" + id

func build_ladder() -> void:
	UiKit.panel(self, Rect2(518, 118, 644, 548), "paper")
	var tabs: Array = [["top", tr("MELHORES")], ["live", tr("AO VIVO")]]
	for i in range(tabs.size()):
		var button: Button = UiKit.button(self, str(tabs[i][1]), Rect2(534 + i * 160, 124, 152, 30), select_right.bind(str(tabs[i][0])), "tab_active" if right_tab == tabs[i][0] else "tab", 15)
		button.name = "RankedTab_" + str(tabs[i][0])
	if right_tab == "live":
		build_live()
		return
	var head_y: float = 160.0
	for entry: Array in [["#", 540, 40], [tr("Jogador"), 636, 190], [tr("Divisão"), 836, 130], [tr("Pontos"), 972, 70], ["V-D", 1048, 90]]:
		UiKit.label(self, str(entry[0]), Rect2(float(entry[1]), head_y, float(entry[2]), 22), 14, UiKit.TEXT_MUTED)
	var rows: Array = info.get("rows", [])
	if rows.is_empty():
		var empty: Label = UiKit.wrapped(self, tr("Ainda não há partidas ranqueadas nesta temporada. Seja o primeiro!") if not loading else tr("Carregando…"), Rect2(540, 260, 600, 60), 18, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(532, 184)
	scroll.size = Vector2(618, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(604, 0)
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)
	for row_data: Dictionary in rows:
		ladder_row(box, row_data)
	var position: int = int(info.get("position", 0))
	var total: int = int(info.get("total", 0))
	var footer: String = tr("Você está na posição %d de %d jogadores.") % [position, total] if position > 0 else tr("Jogue partidas ranqueadas para entrar na lista (%d jogadores listados).") % total
	UiKit.label(self, footer, Rect2(536, 622, 612, 26), 15, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)

func select_right(tab: String) -> void:
	right_tab = tab
	build()

# The ranked matches going on: who is playing, for how long, and a button to watch.
func build_live() -> void:
	var live: Array = info.get("live", [])
	if live.is_empty():
		var empty: Label = UiKit.wrapped(self, tr("Nenhuma partida ranqueada em andamento agora."), Rect2(540, 260, 600, 60), 18, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	for i in range(mini(live.size(), 9)):
		var entry: Dictionary = live[i]
		var row: Panel = UiKit.panel(self, Rect2(534, 168 + i * 46, 616, 40), "slot")
		row.name = "LiveRow_%d" % int(entry.m)
		UiKit.clipped(row, "  vs  ".join((entry.names as Array).map(func(n: Variant) -> String: return str(n))), Rect2(12, 7, 350, 26), 17, UiKit.TEXT)
		var seconds: int = int(entry.ticks) / 60
		UiKit.label(row, "%d:%02d" % [seconds / 60, seconds % 60], Rect2(372, 7, 70, 26), 16, UiKit.TEXT_MUTED)
		UiKit.label(row, tr("%d assistindo") % int(entry.watchers), Rect2(440, 7, 90, 26), 13, UiKit.TEXT_MUTED)
		UiKit.button(row, tr("ASSISTIR"), Rect2(520, 4, 90, 32), app.watch.bind(int(entry.m), self), "button_green", 13).name = "WatchLive_%d" % int(entry.m)

func ladder_row(box: Control, data: Dictionary) -> void:
	var mine: bool = int(data.account) == int(app.my_account())
	var row: Panel = UiKit.panel(box, Rect2(0, 0, 604, 38), "slot_light" if mine else "slot")
	row.custom_minimum_size = Vector2(604, 38)
	row.name = "LadderRow_%d" % int(data.position)
	var mmr: int = int(data.mmr)
	UiKit.label(row, str(int(data.position)), Rect2(8, 6, 40, 26), 16, PremiumUi.GOLD if int(data.position) <= 3 else UiKit.TEXT)
	RankBadge.create(row, Rect2(46, 3, 32, 32), mmr, true)
	UiKit.clipped(row, str(data.name), Rect2(90, 6, 180, 26), 16, Color.WHITE if mine else UiKit.TEXT)
	UiKit.clipped(row, Ranked.label(mmr), Rect2(296, 6, 130, 26), 15, Ranked.division(mmr).color)
	UiKit.label(row, str(mmr), Rect2(436, 6, 70, 26), 16, UiKit.TEXT)
	UiKit.label(row, "%d-%d" % [int(data.wins), int(data.losses)], Rect2(512, 6, 88, 26), 15, UiKit.TEXT_MUTED)

func toggle_queue() -> void:
	var reply: Dictionary = await app.net.request("ranked_queue", {"on": not queued})
	if not is_inside_tree():
		return
	if not reply.ok:
		message = app.server_text(reply.get("error", ""))
		build()
		return
	message = ""
	set_queue(bool(reply.get("queued", false)), int(reply.get("waiting", 0)))
	build()

func claim_season(season: int) -> void:
	var result: Dictionary = await app.do_op("season_claim", [season])
	if not is_inside_tree():
		return
	message = str(result.message) if result.error == "" else str(result.error)
	build()

func set_title(id: String) -> void:
	var result: Dictionary = await app.do_op("title_set", [id])
	if not is_inside_tree():
		return
	message = "" if result.error == "" else str(result.error)
	build()

func close() -> void:
	if queued:
		await app.net.request("ranked_queue", {"on": false})
	closed.emit()
	queue_free()
