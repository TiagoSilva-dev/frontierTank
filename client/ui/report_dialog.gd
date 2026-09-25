class_name ReportDialog
extends Control

# Reporting a chat line (launch checklist: moderated chat). The player picks a reason
# and may add a note; the game server sends the report with the lines around it to the
# team. Hiding the author's lines works at once, only for this player.

const REASONS: Array = [
	["ofensa", "Ofensa, ameaça ou assédio"],  # i18n
	["odio", "Discurso de ódio ou discriminação"],  # i18n
	["spam", "Spam ou propaganda"],  # i18n
	["golpe", "Golpe ou venda por dinheiro"],  # i18n
	["dados", "Expõe dados pessoais"],  # i18n
	["nome", "Nome de personagem ofensivo"],  # i18n
	["outro", "Outro motivo"],  # i18n
]

var app: Node
var message: Dictionary = {}
var reason: String = ""
var reason_buttons: Dictionary = {}
var note: LineEdit
var hide_box: CheckBox
var status: Label
var send_button: Button
var sending: bool = false

static func open(parent: Node, app_node: Node, line: Dictionary) -> ReportDialog:
	var dialog: ReportDialog = ReportDialog.new()
	dialog.app = app_node
	dialog.message = line
	parent.add_child(dialog)
	return dialog

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.6)
	var rect: Rect2 = Rect2(300, 90, 680, 540)
	UiKit.panel(self, rect, "wood")
	UiKit.title(self, tr("DENUNCIAR MENSAGEM"), Rect2(rect.position.x, rect.position.y + 8, rect.size.x, 34), 24)
	UiKit.panel(self, Rect2(rect.position + Vector2(14, 46), rect.size - Vector2(28, 60)), "paper")
	var x: float = rect.position.x + 36
	var y: float = rect.position.y + 60
	UiKit.label(self, tr("Mensagem de %s:") % str(message.get("author", "")), Rect2(x, y, 600, 26), 16, Color("7a5a3a"))
	var quote: Label = UiKit.label(self, "“%s”" % str(message.get("text", "")), Rect2(x + 12, y + 28, 588, 48), 17, UiKit.TEXT_DARK)
	quote.name = "Quote"
	UiKit.wrap(quote, Vector2(588, 48))
	y += 84
	UiKit.label(self, tr("Motivo"), Rect2(x, y, 600, 26), 16, Color("7a5a3a"))
	y += 28
	for i in range(REASONS.size()):
		var id: String = REASONS[i][0]
		var button: Button = UiKit.button(self, tr(REASONS[i][1]), Rect2(x + (i % 2) * 308, y + (i / 2) * 42, 300, 36), pick.bind(id), "tab", 14)
		button.name = "Reason_" + id
		reason_buttons[id] = button
	y += 42 * ceili(REASONS.size() / 2.0) + 4
	note = UiKit.text_field(self, Rect2(x, y, 608, 36), tr("Detalhes (opcional)"), false, 200, 15)
	note.name = "Note"
	y += 44
	hide_box = UiKit.check_box(self, tr("Ocultar as mensagens deste jogador para mim"), Rect2(x, y, 608, 32))
	hide_box.name = "Hide"
	status = UiKit.label(self, "", Rect2(x, y + 34, 608, 30), 15, Color("b8321c"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	status.name = "Status"
	send_button = UiKit.button(self, tr("ENVIAR DENÚNCIA"), Rect2(rect.position.x + 110, rect.end.y - 62, 240, 44), send, "button_red", 17)
	send_button.name = "Send"
	UiKit.button(self, tr("CANCELAR"), Rect2(rect.end.x - 300, rect.end.y - 62, 180, 44), queue_free)
	refresh()

func pick(id: String) -> void:
	reason = id
	refresh()

func refresh() -> void:
	for id: String in reason_buttons:
		var style: String = "tab_active" if id == reason else "tab"
		reason_buttons[id].add_theme_stylebox_override("normal", UiKit.frame(style))
		reason_buttons[id].add_theme_stylebox_override("hover", UiKit.frame(style))
	send_button.disabled = reason == "" or sending

func send() -> void:
	if reason == "" or sending:
		return
	sending = true
	refresh()
	status.text = tr("Enviando…")
	var reply: Dictionary = await app.net.request("chat_report", {"id": int(message.get("id", 0)), "reason": reason, "note": note.text})
	sending = false
	if not is_inside_tree():
		return
	if not reply.ok:
		status.text = app.server_text(reply.get("error", ""))
		app.audio.play("ui_error")
		refresh()
		return
	if hide_box.button_pressed:
		app.lobby.ignore(int(message.get("account", 0)))
	app.audio.play("ui_confirm")
	app.toast(tr("Denúncia enviada. Obrigado!"))
	queue_free()

func _gui_input(_event: InputEvent) -> void:
	accept_event()
