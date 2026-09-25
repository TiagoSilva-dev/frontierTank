class_name MailScreen
extends Control

# Correio (0.12, online): what the Leilão sends — the Solares and Estrelas of a sale
# (minus the commission), a bought item that did not go straight to the Mochila, and the
# items of cancelled or expired listings. Receiving puts them in the profile; the server
# writes the profile and marks the letter received in the same transaction.

signal closed

const PER_PAGE: int = 7

var app: Node
var contents: Control
var letters: Array = []
var total: int = 0
var page: int = 0
var loading: bool = false
var message: String = ""
var clock_offset: int = 0

func _ready() -> void:
	size = Vector2(1280, 720)
	build()
	refresh()

func server_now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_offset

func build() -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
	contents = Control.new()
	contents.size = size
	add_child(contents)
	move_child(contents, 0)
	UiKit.dim(contents, 0.7)
	UiKit.panel(contents, Rect2(190, 56, 900, 608), "wood")
	UiKit.title(contents, tr("CORREIO"), Rect2(190, 62, 900, 44), 30)
	UiKit.button(contents, tr("FECHAR"), Rect2(936, 66, 140, 40), close)
	UiKit.panel(contents, Rect2(206, 112, 868, 482), "paper")
	var heading: String = tr("Carregando...") if loading else (tr("%d cartas esperando") % total if total != 1 else tr("1 carta esperando"))
	UiKit.label(contents, heading, Rect2(222, 118, 500, 30), 18, UiKit.TEXT_DARK)
	var pages: int = maxi(1, ceili(letters.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = page * PER_PAGE + i
		if index >= letters.size():
			break
		letter_row(letters[index], Rect2(218, 152 + i * 62, 844, 58))
	if letters.is_empty() and not loading:
		UiKit.label(contents, tr("Nenhuma carta. As vendas e compras do Leilão chegam aqui."), Rect2(222, 320, 836, 40), 18, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, "<", Rect2(890, 118, 40, 28), turn_page.bind(-1), "tab", 14)
	UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(930, 118, 80, 28), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(1010, 118, 40, 28), turn_page.bind(1), "tab", 14)
	var all: Button = UiKit.button(contents, tr("RECEBER TUDO"), Rect2(540, 602, 200, 50), claim_all, "button_green", 20)
	all.name = "ClaimAll"
	all.disabled = letters.is_empty() or loading
	if message != "":
		var bar: Panel = UiKit.panel(contents, Rect2(206, 602, 320, 50), "dark")
		UiKit.label(bar, message, Rect2(8, 0, 304, 50), 14, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func letter_row(mail: Dictionary, rect: Rect2) -> void:
	var box: Panel = UiKit.panel(contents, rect, "slot_light")
	box.name = "Mail_%d" % int(mail.id)
	var icon: Texture2D = PixelIcons.get_icon("mail")
	var item: Variant = mail.get("item")
	var bundle: Dictionary = mail.get("currencies", {}) if mail.get("currencies") is Dictionary else {}
	if item is Dictionary:
		icon = Auction.item_icon(str(mail.get("item_kind", "item")), item)
	elif int(bundle.get("solar", 0)) > 0:
		icon = load(str(Crafting.currency_def("solar").icon))
	elif int(bundle.get("estrela", 0)) > 0:
		icon = load(str(Crafting.currency_def("estrela").icon))
	UiKit.art(box, icon, Rect2(8, 5, 48, 48))
	UiKit.clipped(box, Auction.mail_title(mail), Rect2(64, 2, 600, 28), 16, UiKit.TEXT_DARK)
	UiKit.clipped(box, Auction.mail_contents(mail), Rect2(64, 28, 600, 26), 14, Color("2f6a1f"))
	UiKit.label(box, Auction.time_ago(server_now() - int(mail.get("created_at", server_now()))), Rect2(600, 2, 120, 28), 13, Color("8a6a4a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	var take: Button = UiKit.button(box, tr("RECEBER"), Rect2(730, 10, 106, 38), claim.bind([int(mail.id)]), "button", 14)
	take.name = "Claim_%d" % int(mail.id)
	take.disabled = loading

func refresh() -> void:
	loading = true
	build()
	var reply: Dictionary = await app.trade("mail_list")
	if not is_inside_tree():
		return
	loading = false
	if reply.ok:
		if reply.has("now"):
			clock_offset = int(reply.now) - int(Time.get_unix_time_from_system())
		letters = reply.mail
		total = int(reply.total)
		app.mail_count = total
	else:
		message = str(reply.error)
	build()

func claim(ids: Array) -> void:
	loading = true
	build()
	var reply: Dictionary = await app.trade("mail_claim", {"ids": ids})
	if not is_inside_tree():
		return
	loading = false
	if reply.ok:
		app.audio.play("ui_coin")
		message = tr("Recebido! Veja na Mochila.")
	else:
		app.audio.play("ui_error")
		message = str(reply.error)
	refresh()

func claim_all() -> void:
	claim([])

func turn_page(step: int) -> void:
	page += step
	build()

func close() -> void:
	closed.emit()
	queue_free()
