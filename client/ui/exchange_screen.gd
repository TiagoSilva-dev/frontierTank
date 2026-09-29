class_name ExchangeScreen
extends Control

signal closed
var app: Node
var give: String = "brasa"
var want: String = "estrela"
var give_amount: int = 1
var want_amount: int = 1
var lots: int = 1
var book: Dictionary = {"offers": [], "competing": [], "orders": []}
var busy: bool = false
var message: String = ""
var contents: Control
var summary: Label
var submit: Button
var picker: Control
var filter_text: String = ""
var filter_kind: int = 0
var owned_only: bool = false
var giving: bool = true
var order_page: int = 0
var show_competing: bool = false

func _ready() -> void:
	size = Vector2(1280, 720)
	build()
	refresh()

func panel(parent: Node, rect: Rect2) -> Control:
	var node: Control = Control.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(func() -> void: HudPaint.well(node, HudPaint.frame(node, Rect2(Vector2.ZERO, node.size), 0.25)))
	parent.add_child(node)
	return node

func text(value: String, rect: Rect2, fs: int = 16, tint: Color = Color("e2e9ee")) -> Label:
	return UiKit.label(contents, value, rect, fs, tint)

func button(value: String, rect: Rect2, action: Callable) -> Button:
	var b: Button = UiKit.button(contents, value, rect, action, "button", 16)
	b.disabled = busy
	return b

func build() -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
	contents = Control.new()
	contents.size = size
	add_child(contents)
	UiKit.dim(contents, 0.96)
	panel(contents, Rect2(20, 16, 1240, 688))
	text(tr("CASA DE CÂMBIO"), Rect2(48, 32, 700, 48), 32, HudPaint.GOLD)
	text(tr("Moedas e pedras. Um mercado entre aventureiros."), Rect2(50, 79, 900, 24), 16)
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(957, 42, 26, 26))
	text(str(app.profile.coins), Rect2(991, 38, 95, 30), 20, HudPaint.GOLD)
	button(tr("FECHAR"), Rect2(1110, 36, 120, 40), close)
	panel(contents, Rect2(40, 120, 404, 502))
	panel(contents, Rect2(456, 120, 370, 502))
	panel(contents, Rect2(838, 120, 400, 502))
	text(tr("NOVA OFERTA"), Rect2(60, 138, 370, 32), 21, HudPaint.GOLD)
	asset_card(give, tr("EU TENHO"), Rect2(60, 186, 364, 90), true)
	asset_card(want, tr("EU QUERO"), Rect2(60, 298, 364, 90), false)
	text(tr("por lote"), Rect2(308, 278, 100, 20), 13)
	spin(give_amount, Rect2(272, 236, 132, 32), func(v: float) -> void: give_amount = int(v); update_quote())
	spin(want_amount, Rect2(272, 348, 132, 32), func(v: float) -> void: want_amount = int(v); update_quote())
	text(tr("Quantidade de lotes"), Rect2(60, 407, 226, 30))
	spin(lots, Rect2(294, 407, 110, 32), func(v: float) -> void: lots = int(v); update_quote())
	button(tr("INVERTER"), Rect2(60, 452, 150, 32), swap)
	button(tr("USAR COTAÇÃO"), Rect2(220, 452, 204, 32), use_best).disabled = busy or book.offers.is_empty()
	summary = text("", Rect2(60, 495, 362, 66), 14, HudPaint.CREAM)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	submit = button(tr("CRIAR OFERTA"), Rect2(60, 570, 364, 36), place)
	submit.name = "PlaceExchangeOrder"
	build_market()
	build_orders()
	var note: Label = text(message if message != "" else tr("A taxa em ouro não é devolvida. Trocas e cancelamentos chegam ao Correio."), Rect2(48, 638, 850, 48), 14, HudPaint.GOLD)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(tr("CORREIO"), Rect2(932, 644, 142, 34), open_mail)
	button(tr("ATUALIZAR"), Rect2(1086, 644, 142, 34), refresh)
	update_quote()
	skin(contents)

func asset_card(id: String, heading: String, rect: Rect2, is_give: bool) -> void:
	panel(contents, rect)
	UiKit.art(contents, str(CurrencyExchange.definition(id).get("icon", "")), Rect2(rect.position + Vector2(10, 18), Vector2(54, 54)))
	text(heading, Rect2(rect.position + Vector2(76, 2), Vector2(230, 22)), 13, HudPaint.GOLD)
	var b: Button = button(CurrencyExchange.title(id), Rect2(rect.position + Vector2(76, 24), Vector2(278, 28)), select_asset.bind(is_give))
	b.add_theme_font_size_override("font_size", 14)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = CurrencyExchange.title(id)
	text(tr("Saldo: %d") % app.profile.currency_count(id), Rect2(rect.position + Vector2(76, 57), Vector2(132, 24)), 14)

func spin(value: int, rect: Rect2, changed: Callable) -> void:
	var input: SpinBox = SpinBox.new()
	input.position = rect.position
	input.size = rect.size
	input.min_value = 1
	input.max_value = CurrencyExchange.MAX_AMOUNT
	input.step = 1
	input.value = value
	input.editable = not busy
	input.value_changed.connect(changed)
	contents.add_child(input)

func update_quote() -> void:
	if not is_instance_valid(summary):
		return
	var error: String = CurrencyExchange.reason(app.profile, give, want, give_amount, want_amount, lots)
	summary.text = tr("Reservar %d · Receber %d\nTaxa: %d ouro") % [give_amount * lots, want_amount * lots, CurrencyExchange.fee(give_amount, lots)]
	if error != "":
		summary.text += "\n" + error
	submit.disabled = busy or error != ""

func build_market() -> void:
	text(tr("LIVRO DE OFERTAS"), Rect2(476, 138, 335, 30), 20, HudPaint.GOLD)
	button(tr("Disponíveis"), Rect2(476, 181, 158, 30), market_tab.bind(false)).set_meta("exchange_active", not show_competing)
	button(tr("Concorrentes"), Rect2(640, 181, 166, 30), market_tab.bind(true)).set_meta("exchange_active", show_competing)
	var rows: Array = book.competing if show_competing else book.offers
	text(tr("Melhores taxas primeiro · até 50 ofertas"), Rect2(476, 221, 330, 24), 13)
	if rows.is_empty():
		var empty: Label = text(tr("Nenhuma oferta neste par.\nDefina sua taxa e abra o mercado."), Rect2(478, 284, 322, 110), 18, Color("acbacd"))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(474, 252)
	scroll.size = Vector2(336, 350)
	contents.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for row: Dictionary in rows:
		var offer: Button = Button.new()
		var have: int = int(row.give_unit) if show_competing else int(row.want_unit)
		var wanted: int = int(row.want_unit) if show_competing else int(row.give_unit)
		offer.text = tr("%d por %d · %d lotes") % [have, wanted, int(row.remaining)]
		offer.custom_minimum_size = Vector2(300, 46)
		offer.add_theme_font_size_override("font_size", 15)
		offer.tooltip_text = tr("Selecionar esta proporção. A execução depende do saldo disponível e de lotes inteiros.")
		offer.disabled = busy or show_competing
		offer.pressed.connect(use_rate.bind(have, wanted))
		list.add_child(offer)

func build_orders() -> void:
	text(tr("MINHAS OFERTAS"), Rect2(856, 138, 360, 30), 20, HudPaint.GOLD)
	text(tr("Até 10 ativas · continuam com você offline"), Rect2(856, 176, 360, 24), 13)
	var orders: Array = book.orders
	order_page = clampi(order_page, 0, maxi(0, ceili(orders.size() / 4.0) - 1))
	if orders.is_empty():
		text(tr("Suas ofertas aparecerão aqui."), Rect2(858, 294, 352, 70), 17, Color("acbacd"))
	for i in range(order_page * 4, mini(orders.size(), order_page * 4 + 4)):
		var row: Dictionary = orders[i]
		var y: float = 215 + (i % 4) * 86
		var state: String = tr("Ativa") if row.status == "active" else tr("Concluída") if row.status == "filled" else tr("Cancelada")
		if row.status == "active" and int(row.remaining) < int(row.lots):
			state = tr("Parcial")
		text("#%d · %s" % [int(row.id), state], Rect2(858, y, 275, 22), 14, HudPaint.GOLD)
		var detail: Label = text("%d %s → %d %s" % [int(row.give_unit), CurrencyExchange.title(str(row.give_id)), int(row.want_unit), CurrencyExchange.title(str(row.want_id))], Rect2(858, y + 23, 352, 22), 13)
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.tooltip_text = detail.text
		text((tr("%d lotes devolvidos") % int(row.remaining)) if row.status == "cancelled" else tr("%d de %d lotes pendentes") % [int(row.remaining), int(row.lots)], Rect2(858, y + 47, 246, 24), 13)
		if row.status == "active":
			button(tr("CANCELAR"), Rect2(1108, y + 47, 106, 27), cancel.bind(int(row.id))).add_theme_font_size_override("font_size", 12)
	button("<", Rect2(860, 577, 46, 28), page.bind(-1))
	text("%d / %d" % [order_page + 1, maxi(1, ceili(orders.size() / 4.0))], Rect2(950, 580, 130, 28), 14)
	button(">", Rect2(1172, 577, 46, 28), page.bind(1))

func refresh() -> void:
	if busy:
		return
	busy = true
	build()
	var result: Dictionary = await app.trade("exchange_book", {"give_id": give, "want_id": want})
	if not is_inside_tree():
		return
	busy = false
	if result.ok:
		book = result
	else:
		message = str(result.error)
	build()

func place() -> void:
	if busy:
		return
	busy = true
	build()
	var result: Dictionary = await app.trade("exchange_create", {"give_id": give, "want_id": want, "give_unit": give_amount, "want_unit": want_amount, "lots": lots})
	if not is_inside_tree():
		return
	busy = false
	message = tr("Oferta criada. Resgate as trocas realizadas no Correio.") if result.ok else str(result.error)
	app.audio.play("ui_coin" if result.ok else "ui_error")
	refresh()

func cancel(id: int) -> void:
	if busy:
		return
	busy = true
	build()
	var result: Dictionary = await app.trade("exchange_cancel", {"id": id})
	if not is_inside_tree():
		return
	busy = false
	message = tr("Oferta cancelada. O saldo não negociado está no Correio.") if result.ok else str(result.error)
	refresh()

func use_best() -> void:
	if not book.offers.is_empty():
		use_rate(int(book.offers[0].want_unit), int(book.offers[0].give_unit))

func use_rate(have: int, wanted: int) -> void:
	give_amount = have
	want_amount = wanted
	lots = 1
	build()

func swap() -> void:
	var previous: String = give
	give = want
	want = previous
	var amount: int = give_amount
	give_amount = want_amount
	want_amount = amount
	refresh()

func market_tab(competing: bool) -> void:
	show_competing = competing
	build()

func page(step: int) -> void:
	order_page += step
	build()

func open_mail() -> void:
	var mail: MailScreen = app.open_mail(self)
	if mail != null:
		mail.closed.connect(refresh)

func select_asset(is_give: bool) -> void:
	giving = is_give
	filter_text = ""
	filter_kind = 0
	owned_only = is_give
	build_picker()

func build_picker() -> void:
	if is_instance_valid(picker):
		remove_child(picker)
		picker.queue_free()
	picker = Control.new()
	picker.size = size
	add_child(picker)
	UiKit.dim(picker, 0.90)
	panel(picker, Rect2(244, 65, 792, 590))
	UiKit.label(picker, tr("ESCOLHA UMA MOEDA OU PEDRA"), Rect2(270, 82, 650, 38), 23, HudPaint.GOLD)
	UiKit.button(picker, "×", Rect2(964, 82, 44, 36), func() -> void: picker.queue_free())
	var search: LineEdit = LineEdit.new()
	search.position = Vector2(270, 137)
	search.size = Vector2(300, 36)
	search.placeholder_text = tr("Buscar pelo nome")
	search.text = filter_text
	picker.add_child(search)
	var kind: OptionButton = OptionButton.new()
	kind.position = Vector2(585, 137)
	kind.size = Vector2(190, 36)
	for label: String in [tr("Tudo"), tr("Moedas"), tr("Pedras")]:
		kind.add_item(label)
	kind.select(filter_kind)
	picker.add_child(kind)
	var owned: CheckButton = CheckButton.new()
	owned.position = Vector2(789, 137)
	owned.text = tr("Tenho saldo")
	owned.button_pressed = owned_only
	picker.add_child(owned)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(270, 193)
	scroll.size = Vector2(738, 438)
	picker.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	scroll.add_child(grid)
	var populate: Callable = func() -> void:
		for child: Node in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
		for asset: Dictionary in CurrencyExchange.assets():
			var id: String = str(asset.id)
			if id == (want if giving else give):
				continue
			if owned_only and app.profile.currency_count(id) <= 0:
				continue
			var stone: bool = not Armory.stone_def(id).is_empty()
			if (filter_kind == 1 and stone) or (filter_kind == 2 and not stone):
				continue
			if filter_text != "" and not CurrencyExchange.title(id).to_lower().contains(filter_text.to_lower()):
				continue
			var choice: Button = Button.new()
			choice.custom_minimum_size = Vector2(354, 70)
			choice.icon = load(str(asset.icon))
			choice.expand_icon = true
			choice.add_theme_constant_override("icon_max_width", 44)
			choice.text = CurrencyExchange.title(id) + "\n" + tr("Saldo: %d") % app.profile.currency_count(id)
			choice.add_theme_font_size_override("font_size", 14)
			choice.pressed.connect(func() -> void:
				if giving:
					give = id
				else:
					want = id
				picker.queue_free()
				refresh())
			grid.add_child(choice)
		if grid.get_child_count() == 0:
			var empty: Label = Label.new()
			empty.text = tr("Nenhum item neste filtro. Desative Tenho saldo para ver todos.")
			empty.custom_minimum_size = Vector2(690, 70)
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(empty)
		skin(grid)
	search.text_changed.connect(func(value: String) -> void: filter_text = value; populate.call())
	kind.item_selected.connect(func(value: int) -> void: filter_kind = value; populate.call())
	owned.toggled.connect(func(value: bool) -> void: owned_only = value; populate.call())
	populate.call()
	skin(picker)

func skin(root: Node) -> void:
	for node: Node in root.get_children():
		if node is Button:
			for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
				var style: StyleBoxFlat = StyleBoxFlat.new()
				style.bg_color = Color("192b3c") if state == "normal" else Color("304b60")
				if node.get_meta("exchange_active", false):
					style.bg_color = Color("61421f") if state == "normal" else Color("79562f")
				if state == "disabled":
					style.bg_color = Color("192029")
				style.border_color = HudPaint.GOLD if state in ["hover", "focus"] else Color("886744")
				style.set_border_width_all(2)
				style.set_corner_radius_all(4)
				node.add_theme_stylebox_override(state, style)
			node.add_theme_color_override("font_color", Color("f5e5bf"))
		skin(node)

func close() -> void:
	if busy:
		return
	closed.emit()
	queue_free()
