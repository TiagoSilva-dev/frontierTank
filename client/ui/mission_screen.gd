class_name MissionScreen
extends Control

signal closed

var app: Node
var message: String = ""
var loading: bool = false
var reset_label: Label
var shown_day: int = -1
var reset_refresh: float = 0.0

func _ready() -> void:
	size = Vector2(1280, 720)
	build()

func build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	UiKit.dim(self, 0.72)
	UiKit.panel(self, Rect2(140, 42, 1000, 636), "wood")
	UiKit.title(self, tr("CONTRATOS DIÁRIOS"), Rect2(160, 52, 950, 42), 28)
	var close_button: Button = UiKit.button(self, tr("FECHAR"), Rect2(974, 58, 142, 38), close)
	close_button.name = "CloseMissions"
	reset_label = UiKit.label(self, "", Rect2(166, 104, 550, 28), 15, Color("fff4a0"), UiKit.INK)
	UiKit.label(self, tr("Resgate todos os contratos para receber o bônus diário."), Rect2(166, 132, 880, 28), 15, Color("f4ead6"), UiKit.INK)
	var state: Dictionary = MissionsBoard.ensure(app.profile)
	shown_day = int(state.day)
	for i in range(MissionsBoard.definitions().size()):
		var mission: Dictionary = MissionsBoard.definitions()[i]
		mission_row(mission, state, Rect2(160, 174 + i * 82, 960, 74))
	var claimed_count: int = state.claimed.size()
	var bonus: Dictionary = MissionsBoard.data().daily_bonus
	UiKit.panel(self, Rect2(160, 594, 960, 54), "paper")
	UiKit.label(self, tr("BÔNUS DIÁRIO  ·  %d/%d contratos resgatados") % [claimed_count, MissionsBoard.mission_count()], Rect2(176, 601, 570, 36), 17, UiKit.TEXT_DARK)
	UiKit.label(self, tr("Moedas: %d   EXP: %d") % [int(bonus.coins), int(bonus.exp)], Rect2(750, 601, 348, 36), 17, Color("8b5b25"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	if message != "":
		UiKit.label(self, message, Rect2(160, 652, 960, 22), 14, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	update_reset_label()

func _process(delta: float) -> void:
	if MissionsBoard.day_id() != shown_day:
		message = ""
		build()
		return
	reset_refresh -= delta
	if reset_refresh <= 0.0:
		reset_refresh = 1.0
		update_reset_label()

func mission_row(mission: Dictionary, state: Dictionary, rect: Rect2) -> void:
	var id: String = str(mission.id)
	var target: int = int(mission.target)
	var progress: int = int(state.progress.get(id, 0))
	var claimed: bool = state.claimed.has(id)
	var complete: bool = progress >= target
	var row: Panel = UiKit.panel(self, rect, "slot_light" if not claimed else "slot")
	row.name = "Mission_" + id
	UiKit.clipped(row, tr(str(mission.name)), Rect2(14, 4, 470, 26), 17, UiKit.TEXT_DARK)
	UiKit.clipped(row, tr(str(mission.description)), Rect2(14, 34, 540, 26), 14, Color("6d5946"))
	UiKit.label(row, "%s / %s" % [format_count(progress), format_count(target)], Rect2(550, 12, 112, 22), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var bar_back: Panel = UiKit.panel(row, Rect2(554, 39, 104, 12), "dark")
	var fill_width: float = 100.0 * float(progress) / float(maxi(1, target))
	if fill_width > 0.0:
		UiKit.panel(bar_back, Rect2(2, 2, fill_width, 8), "button_green")
	var reward: Dictionary = mission.reward
	UiKit.label(row, tr("+%d moedas\n+%d EXP") % [int(reward.coins), int(reward.exp)], Rect2(672, 8, 142, 54), 14, Color("2f6a1f"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var button_text: String = tr("RESGATADA") if claimed else (tr("RESGATAR") if complete else tr("EM ANDAMENTO"))
	var claim_button: Button = UiKit.button(row, button_text, Rect2(824, 16, 122, 42), claim.bind(id), "button_green" if complete and not claimed else "button", 14)
	claim_button.name = "ClaimMission_" + id
	claim_button.disabled = loading or not complete or claimed

func format_count(value: int) -> String:
	return "%s" % value if value < 1000 else "%s.%03d" % [value / 1000, value % 1000]

func update_reset_label() -> void:
	var remaining: int = MissionsBoard.seconds_until_reset()
	var hours: int = int(remaining / 3600)
	var minutes: int = int((remaining % 3600) / 60)
	reset_label.text = tr("Renovação em %02d h %02d min (UTC)") % [hours, minutes]

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