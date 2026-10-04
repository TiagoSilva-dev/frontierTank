class_name MissionScreen
extends Control

# Contracts (MISSÃO): the "Primeiros passos" checklist for new characters (0.21, it
# disappears once its bonus is claimed), the daily and the weekly contracts (0.22: drawn from
# a pool, so they change) and the login streak with its ladder of rewards.

signal closed

var app: Node
var tab: String = ""
var message: String = ""
var loading: bool = false
var reset_label: Label
var shown_day: int = -1
var reset_refresh: float = 0.0

func _ready() -> void:
	size = Vector2(1280, 720)
	if tab == "" or (tab == "starter" and MissionsBoard.starter_finished(app.profile)):
		tab = default_tab()
	build()

# The first tab with something to do: the checklist while it lasts, else the dailies.
func default_tab() -> String:
	return "daily" if MissionsBoard.starter_finished(app.profile) else "starter"

func tabs() -> Array:
	var state: Dictionary = MissionsBoard.ensure(app.profile)
	var list: Array = []
	if not MissionsBoard.starter_finished(app.profile):
		list.append(["starter", tr("PRIMEIROS PASSOS"), ready_count(state, "starter")])
	list.append(["daily", tr("DIÁRIOS"), ready_count(state, "daily")])
	list.append(["weekly", tr("SEMANAIS"), ready_count(state, "weekly")])
	list.append(["streak", tr("SEQUÊNCIA"), 1 if MissionsBoard.streak_ready(app.profile) else 0])
	return list

# How many contracts of a track can be claimed now.
func ready_count(state: Dictionary, kind: String) -> int:
	var track: Dictionary = state if kind == "daily" else state[kind]
	var count: int = 0
	for mission: Dictionary in MissionsBoard.defs_of(state, kind):
		if MissionsBoard.is_complete(app.profile, mission) and not track.claimed.has(str(mission.id)):
			count += 1
	return count

func build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	PremiumUi.window(self, Rect2(140, 42, 1000, 636), tr("CONTRATOS"), "", 0.94, 34, true)
	var close_button: Button = UiKit.button(self, tr("FECHAR"), Rect2(974, 58, 142, 38), close)
	close_button.name = "CloseMissions"
	if tab == "starter" and MissionsBoard.starter_finished(app.profile):
		tab = "daily"
	var state: Dictionary = MissionsBoard.ensure(app.profile)
	shown_day = int(state.day)
	var list: Array = tabs()
	for i in range(list.size()):
		var entry: Array = list[i]
		var text: String = str(entry[1]) + ("  (%d)" % int(entry[2]) if int(entry[2]) > 0 else "")
		var button: Button = UiKit.button(self, text, Rect2(160 + i * 200, 102, 192, 38), select_tab.bind(str(entry[0])), "tab_active" if tab == entry[0] else "tab", 15)
		button.name = "MissionTab_" + str(entry[0])
		button.set_meta("active", tab == entry[0])
	reset_label = UiKit.label(self, "", Rect2(166, 148, 950, 28), 15, Color("fff4a0"), UiKit.INK)
	if tab == "streak":
		build_streak(state)
	else:
		build_track(state)
	update_reset_label()

# The rows of a track and, under them, its completion bonus.
func build_track(state: Dictionary) -> void:
	var defs: Array = MissionsBoard.defs_of(state, tab)
	var track: Dictionary = state if tab == "daily" else state[tab]
	var bonus: Dictionary
	var bonus_title: String
	match tab:
		"starter":
			bonus = MissionsBoard.data().starter_bonus
			bonus_title = tr("BÔNUS DOS PRIMEIROS PASSOS")
			reset_label.text = tr("Um roteiro para conhecer o jogo. Cada passo dá uma recompensa, e completar todos dá um bônus.")
		"weekly":
			bonus = MissionsBoard.data().weekly_bonus
			bonus_title = tr("BÔNUS SEMANAL")
		_:
			bonus = MissionsBoard.data().daily_bonus
			bonus_title = tr("BÔNUS DIÁRIO")
	for i in range(defs.size()):
		mission_row(defs[i], track, Rect2(160, 182 + i * 70, 960, 62))
	var panel_y: float = 182 + defs.size() * 70 + 4
	UiKit.panel(self, Rect2(160, panel_y, 960, 50), "paper")
	UiKit.label(self, tr("%s  ·  %d/%d resgatados") % [bonus_title, track.claimed.size(), defs.size()], Rect2(176, panel_y + 7, 560, 36), 17, UiKit.TEXT)
	var bonus_label: Label = UiKit.clipped(self, MissionsBoard.reward_text(bonus), Rect2(700, panel_y + 7, 400, 36), 16, UiKit.GOLD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	bonus_label.name = "BonusText"
	if message != "":
		UiKit.label(self, message, Rect2(160, panel_y + 54, 960, 22), 14, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func select_tab(value: String) -> void:
	tab = value
	message = ""
	build()

func _process(delta: float) -> void:
	if MissionsBoard.day_id() != shown_day:
		message = ""
		build()
		return
	reset_refresh -= delta
	if reset_refresh <= 0.0:
		reset_refresh = 1.0
		update_reset_label()

func mission_row(mission: Dictionary, track: Dictionary, rect: Rect2) -> void:
	var id: String = str(mission.id)
	var target: int = int(mission.target)
	var progress: int = int(track.progress.get(id, 0))
	var claimed: bool = track.claimed.has(id)
	var complete: bool = progress >= target
	var row: Panel = UiKit.panel(self, rect, "slot_light" if not claimed else "slot")
	row.name = "Mission_" + id
	UiKit.clipped(row, tr(str(mission.name)), Rect2(14, 3, 430, 26), 17, UiKit.TEXT)
	UiKit.clipped(row, tr(str(mission.description)), Rect2(14, 31, 430, 26), 14, UiKit.TEXT_MUTED)
	UiKit.label(row, "%s / %s" % [format_count(progress), format_count(target)], Rect2(452, 8, 100, 22), 15, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var bar_back: Panel = UiKit.panel(row, Rect2(454, 36, 96, 12), "dark")
	var fill_width: float = 92.0 * float(progress) / float(maxi(1, target))
	if fill_width > 0.0:
		UiKit.panel(bar_back, Rect2(2, 2, fill_width, 8), "button_green")
	var reward: Dictionary = mission.reward
	UiKit.clipped(row, reward_line(reward), Rect2(566, 6, 250, 24), 14, UiKit.GOOD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var items: String = reward_items(reward)
	if items != "":
		var item_label: Label = UiKit.clipped(row, items, Rect2(566, 31, 250, 24), 14, UiKit.GOLD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		item_label.mouse_filter = Control.MOUSE_FILTER_PASS
		item_label.tooltip_text = items
	var button_text: String = tr("RESGATADA") if claimed else (tr("RESGATAR") if complete else tr("EM ANDAMENTO"))
	var claim_button: Button = UiKit.button(row, button_text, Rect2(824, 10, 122, 42), claim.bind(id), "button_green" if complete and not claimed else "button", 14)
	claim_button.name = "ClaimMission_" + id
	claim_button.disabled = loading or not complete or claimed

# "+100 moedas  +80 EXP" and, below it, the items ("+2x Pedra ...").
func reward_line(reward: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if int(reward.get("coins", 0)) > 0:
		parts.append(tr("+%d moedas") % int(reward.coins))
	if int(reward.get("exp", 0)) > 0:
		parts.append(tr("+%d EXP") % int(reward.exp))
	return "  ".join(parts)

func reward_items(reward: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var items: Dictionary = reward.get("items", {})
	for id: String in items:
		parts.append("+%dx %s" % [int(items[id]), Tutorial.material_name(id)])
	return ", ".join(parts)

# ---------- the login streak ----------

func build_streak(state: Dictionary) -> void:
	var streak: Dictionary = state.streak
	var ready: bool = MissionsBoard.streak_ready(app.profile)
	var next: int = MissionsBoard.streak_next(app.profile)
	var ladder: Array = MissionsBoard.streak_rewards()
	# The step the next claim lands on (the ladder repeats every `size` days).
	var step: int = posmod(next - 1, ladder.size())
	reset_label.text = tr("Entre todo dia e resgate: dias seguidos sobem a escada de recompensas. Faltou um dia, volta ao começo.")
	UiKit.label(self, tr("Sequência atual: %d dia(s)  ·  Melhor: %d") % [int(streak.count) if int(streak.last) >= MissionsBoard.day_id() - 1 else 0, int(streak.best)], Rect2(160, 182, 960, 32), 22, PremiumUi.GOLD, UiKit.INK)
	for i in range(ladder.size()):
		var at: Vector2 = Vector2(160 + i * 138, 226)
		var done: bool = (i < step) if ready else (i <= step)
		var today: bool = ready and i == step
		var card: Panel = UiKit.panel(self, Rect2(at, Vector2(130, 240)), "slot_light" if today else ("slot" if done else "card_busy"))
		card.name = "StreakDay_%d" % (i + 1)
		UiKit.label(card, tr("DIA %d") % (i + 1), Rect2(0, 8, 130, 26), 18, PremiumUi.GOLD if today else UiKit.TEXT, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		var reward: Dictionary = ladder[i]
		UiKit.label(card, tr("%d moedas") % int(reward.get("coins", 0)), Rect2(0, 52, 130, 24), 15, UiKit.GOOD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(card, tr("%d EXP") % int(reward.get("exp", 0)), Rect2(0, 78, 130, 24), 15, UiKit.INFO, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var items: String = reward_items(reward)
		if items != "":
			UiKit.wrapped(card, items.replace("+", ""), Rect2(6, 108, 118, 76), 14, UiKit.GOLD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var mark: String = tr("✓ RESGATADO") if done and not today else (tr("HOJE") if today else "")
		UiKit.label(card, mark, Rect2(0, 200, 130, 28), 14, UiKit.GOOD if done and not today else Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var button: Button = UiKit.button(self, tr("RESGATAR A RECOMPENSA DE HOJE") if ready else tr("VOLTE AMANHÃ"), Rect2(310, 494, 660, 56), claim_streak, "button_green" if ready else "button", 22)
	button.name = "ClaimStreak"
	button.disabled = loading or not ready
	if message != "":
		UiKit.label(self, message, Rect2(160, 560, 960, 28), 16, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func claim_streak() -> void:
	if loading:
		return
	loading = true
	build()
	var result: Dictionary = await app.do_op("streak_claim", [])
	if not is_inside_tree():
		return
	loading = false
	message = str(result.message) if result.error == "" else str(result.error)
	build()

func format_count(value: int) -> String:
	return "%s" % value if value < 1000 else "%s.%03d" % [value / 1000, value % 1000]

func update_reset_label() -> void:
	if tab == "starter" or tab == "streak":
		return
	var remaining: int = MissionsBoard.seconds_until_reset() if tab == "daily" else MissionsBoard.seconds_until_week()
	var days: int = remaining / 86400
	var hours: int = (remaining % 86400) / 3600
	var minutes: int = (remaining % 3600) / 60
	if tab == "weekly":
		reset_label.text = tr("Resgate todos para receber o bônus semanal.  Renovação em %d d %02d h (segunda-feira, UTC)") % [days, hours]
	else:
		reset_label.text = tr("Resgate todos os contratos para receber o bônus diário.  Renovação em %02d h %02d min (UTC)") % [hours, minutes]

func claim(id: String) -> void:
	if loading:
		return
	loading = true
	build()
	var result: Dictionary = await app.do_op("mission_claim", [id])
	if not is_inside_tree():
		return
	loading = false
	message = str(result.message) if result.error == "" else str(result.error)
	build()

func close() -> void:
	closed.emit()
	queue_free()
