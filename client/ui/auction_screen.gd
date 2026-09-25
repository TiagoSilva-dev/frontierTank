class_name AuctionScreen
extends Control

# Leilão (0.12, online): players sell gear that dropped in the instances and instance
# maps to each other for Solares and/or Estrelas.
#   Comprar        search with filters (type, quality, item or map level, strengthening,
#                  bonus, price and order), the listing's details, the last sales of
#                  items like it, and buy at once.
#   Vender         pick a tradeable item or map, the price, 12/24/48 h; shows the gold fee,
#                  the commission and what arrives in the Correio when it sells.
#   Meus anúncios  the active listings (cancel) and the last closed ones.
# Everything is decided by the game server (Auction rules) and the API (custody); the
# screen only asks through app.trade and shows the answers.

signal closed

const TABS: Array = [["Comprar", "buy"], ["Vender", "sell"], ["Meus anúncios", "mine"]]  # i18n
const TYPES: Array = [["Todos", ""], ["Armas", "arma"], ["Roupas", "roupa"], ["Chapéus", "chapeu"], ["Óculos", "oculos"], ["Asas", "asas"], ["Mapas", "mapa"]]  # i18n
const QUALITY_FILTER: Array = [["Todas", ""], ["Normal", "normal"], ["Excelente", "excelente"], ["Verdadeira", "verdadeira"], ["Super Verdadeira", "super"]]  # i18n
const SORT_OPTIONS: Array = [["Mais recentes", "recent"], ["Menor preço", "price"], ["Maior nível", "level"]]  # i18n
const SELL_PER_PAGE: int = 36

var app: Node
var tab: String = "buy"
var contents: Control
var message: String = ""
var loading: bool = false
# Seconds to add to this computer's clock to get the server's (times left).
var clock_offset: int = 0
# Comprar
var filter: Dictionary = {"slot": "", "quality": "", "min_level": 0, "min_strengthen": 0, "mod": "", "max_solar": 0, "max_estrela": 0, "sort": "recent"}
var page: int = 0
var results: Array = []
var total: int = 0
var searched: bool = false
var selected: Dictionary = {}
var history: Array = []
# Vender
var sell_kind: String = "item"
var sell_uid: int = -1
var sell_page: int = 0
var price_solar: int = 1
var price_estrela: int = 0
var hours: int = 24
# Meus anúncios
var mine_active: Array = []
var mine_closed: Array = []

func _ready() -> void:
	size = Vector2(1280, 720)
	build()
	search()

func server_now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_offset

func sync_clock(reply: Dictionary) -> void:
	if reply.has("now"):
		clock_offset = int(reply.now) - int(Time.get_unix_time_from_system())

func build() -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
	contents = Control.new()
	contents.size = size
	add_child(contents)
	move_child(contents, 0)
	UiKit.dim(contents, 0.75)
	UiKit.panel(contents, Rect2(40, 24, 1200, 672), "wood")
	UiKit.title(contents, tr("LEILÃO"), Rect2(40, 30, 1200, 44), 32)
	UiKit.button(contents, tr("FECHAR"), Rect2(1086, 34, 140, 42), close)
	var mail_text: String = tr("CORREIO") if int(app.mail_count) <= 0 else tr("CORREIO (%d)") % int(app.mail_count)
	var mail: Button = UiKit.button(contents, mail_text, Rect2(900, 34, 180, 42), open_mail, "button_blue" if int(app.mail_count) <= 0 else "button_green", 16)
	mail.name = "MailButton"
	build_wallet()
	for i in range(TABS.size()):
		var tab_button: Button = UiKit.button(contents, tr(TABS[i][0]), Rect2(60 + i * 186, 84, 180, 40), select_tab.bind(str(TABS[i][1])), "tab_active" if tab == TABS[i][1] else "tab", 16)
		tab_button.name = "Tab_" + str(TABS[i][1])
	UiKit.label(contents, tr("Preços em Solares e Estrelas  •  comissão de %d%% na venda") % roundi(float(Auction.rules().commission) * 100.0), Rect2(630, 84, 590, 40), 15, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	match tab:
		"buy":
			build_buy()
		"sell":
			build_sell()
		"mine":
			build_mine()
	if message != "":
		var bar: Panel = UiKit.panel(contents, Rect2(316, 640, 908, 40), "dark")
		bar.name = "Message"
		UiKit.label(bar, message, Rect2(8, 0, 892, 40), 15, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func build_wallet() -> void:
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(60, 36, 32, 32))
	UiKit.label(contents, str(app.profile.coins), Rect2(96, 32, 120, 40), 20, Color("ffd46b"), UiKit.INK)
	var x: float = 214
	for id: String in Auction.rules().currencies:
		var icon: TextureRect = UiKit.art(contents, str(Crafting.currency_def(id).icon), Rect2(x, 34, 36, 36))
		icon.tooltip_text = Crafting.currency_name(id)
		UiKit.label(contents, str(app.profile.currency_count(id)), Rect2(x + 40, 32, 80, 40), 20, Color("fff4d6"), UiKit.INK)
		x += 124

# ---------- widgets ----------


func caption(text: String, rect: Rect2) -> Label:
	return UiKit.label(contents, text, rect, 15, UiKit.TEXT_DARK)

func option(rect: Rect2, entries: Array, current: String, on_pick: Callable) -> OptionButton:
	var node: OptionButton = OptionButton.new()
	var chosen: int = 0
	for i in range(entries.size()):
		node.add_item(str(entries[i][0]))
		if str(entries[i][1]) == current:
			chosen = i
	node.select(chosen)
	# Long bonus texts are cut instead of widening the button past the panel.
	node.fit_to_longest_item = false
	node.clip_text = true
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font", UiKit.font(true))
	node.add_theme_font_size_override("font_size", UiKit.fs(15))
	node.get_popup().add_theme_font_override("font", UiKit.font(true))
	node.item_selected.connect(func(index: int) -> void: on_pick.call(str(entries[index][1])))
	contents.add_child(node)
	node.size = rect.size
	return node

func spin(rect: Rect2, low: int, high: int, value: int, on_change: Callable) -> SpinBox:
	var node: SpinBox = SpinBox.new()
	node.min_value = low
	node.max_value = high
	node.step = 1
	node.rounded = true
	node.value = value
	node.position = rect.position
	node.size = rect.size
	node.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var field: LineEdit = node.get_line_edit()
	field.add_theme_font_override("font", UiKit.font(true))
	field.add_theme_font_size_override("font_size", UiKit.fs(16))
	node.value_changed.connect(func(number: float) -> void: on_change.call(int(number)))
	contents.add_child(node)
	return node

func item_box(kind: String, item: Dictionary, rect: Rect2) -> Panel:
	var box: Panel = UiKit.panel(contents, rect, "dark")
	box.clip_contents = true
	var picture: TextureRect = UiKit.art(box, Auction.item_icon(kind, item), Rect2(rect.size * 0.12, rect.size * 0.76))
	if kind == "item":
		picture.modulate = Armory.icon_tint(item)
		if int(item.get("level", 0)) > 0:
			UiKit.label(box, "+%d" % int(item.level), Rect2(4, 0, 50, 22), 15, Armory.aura_color(int(item.level)).lightened(0.3), UiKit.INK)
	else:
		UiKit.label(box, str(int(item.get("level", 1))), Rect2(rect.size.x - 44, rect.size.y - 26, 40, 24), 18, InstanceRun.quality_color(str(item.get("quality", "normal"))), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	var frame: Panel = Panel.new()
	frame.position = Vector2(2, 2)
	frame.size = rect.size - Vector2(4, 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0), Auction.item_color(kind, item), 3))
	box.add_child(frame)
	return box

# "Verdadeira • Nível do item 12 • 4 bônus" (gear) or "Excelente • 3 atributos" (maps).
func facts(kind: String, item: Dictionary) -> String:
	return "  •  ".join(facts_lines(kind, item))

# [quality, the rest]: the details panel shows them on two lines.
func facts_lines(kind: String, item: Dictionary) -> Array[String]:
	var count: int = (item.get("mods", []) as Array).size()
	if kind == "map":
		return [InstanceRun.quality_label(str(item.get("quality", "normal"))), tr("1 atributo") if count == 1 else tr("%d atributos") % count]
	var bonuses: String = tr("1 bônus") if count == 1 else tr("%d bônus") % count
	return [Armory.quality_label(str(item.get("quality", "normal"))), "%s  •  %s" % [tr("Nível do item %d") % Crafting.item_level(item), bonuses]]

func price_row(parent: Node, solar: int, estrela: int, rect: Rect2, font_size: int = 18) -> void:
	# Currency icons with the amounts, right-aligned in `rect`.
	var x: float = rect.end.x
	var y: float = rect.position.y
	for entry: Array in [["estrela", estrela], ["solar", solar]]:
		if int(entry[1]) <= 0:
			continue
		var text: String = str(int(entry[1]))
		var width: float = 12.0 * text.length() + 8.0
		x -= width
		UiKit.label(parent, text, Rect2(x, y, width, rect.size.y), font_size, Color("fff4d6"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		x -= rect.size.y
		var icon: TextureRect = UiKit.art(parent, str(Crafting.currency_def(str(entry[0])).icon), Rect2(x, y, rect.size.y, rect.size.y))
		icon.tooltip_text = Crafting.currency_name(str(entry[0]))
		x -= 8

# ---------- Comprar ----------

func mod_entries() -> Array:
	# Bonuses to filter by, for the chosen type.
	var list: Array = [[tr("Qualquer"), ""]]
	var slot: String = str(filter.slot)
	if slot == "mapa":
		for def: Dictionary in InstanceRun.rules().map_items.mods:
			list.append([template(str(def.text)), str(def.id)])
		return list
	var pools: Array = []
	if slot == "arma" or slot == "":
		pools.append(Crafting.rules().weapon)
	if slot != "arma":
		pools.append(Crafting.rules().armor)
	for pool: Array in pools:
		for def: Dictionary in pool:
			list.append([template(str(def.text)), str(def.id)])
	return list

static func template(text: String) -> String:
	# "+%d de Ataque" → "+X de Ataque", in the game language.
	return Lang.t(text).replace("%d", "X").replace("%%", "%")

func build_buy() -> void:
	UiKit.panel(contents, Rect2(56, 130, 250, 550), "paper")
	UiKit.label(contents, tr("BUSCA"), Rect2(56, 136, 250, 28), 20, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var y: float = 166
	caption(tr("Tipo"), Rect2(70, y, 220, 22))
	var types: Array = TYPES.map(func(entry: Array) -> Array: return [tr(entry[0]), entry[1]])
	option(Rect2(70, y + 22, 222, 32), types, str(filter.slot), set_type).name = "FilterType"
	y += 60
	caption(tr("Qualidade"), Rect2(70, y, 220, 22))
	var qualities: Array = QUALITY_FILTER.map(func(entry: Array) -> Array: return [tr(entry[0]), entry[1]])
	option(Rect2(70, y + 22, 222, 32), qualities, str(filter.quality), func(value: String) -> void: filter.quality = value).name = "FilterQuality"
	y += 60
	caption(tr("Nível mín.") if filter.slot != "mapa" else tr("Nível do mapa mín."), Rect2(70, y, 150, 22))
	spin(Rect2(70, y + 22, 100, 32), 0, 16, int(filter.min_level), func(value: int) -> void: filter.min_level = value).name = "FilterLevel"
	caption(tr("Fortal. mín."), Rect2(184, y, 110, 22))
	var strengthen: SpinBox = spin(Rect2(184, y + 22, 108, 32), 0, 12, int(filter.min_strengthen), func(value: int) -> void: filter.min_strengthen = value)
	strengthen.name = "FilterStrengthen"
	strengthen.editable = filter.slot != "mapa"
	y += 60
	caption(tr("Bônus"), Rect2(70, y, 220, 22))
	option(Rect2(70, y + 22, 222, 32), mod_entries(), str(filter.mod), func(value: String) -> void: filter.mod = value).name = "FilterMod"
	y += 60
	caption(tr("Preço máximo (0 = qualquer)"), Rect2(70, y, 230, 22))
	UiKit.art(contents, str(Crafting.currency_def("solar").icon), Rect2(70, y + 24, 28, 28))
	spin(Rect2(100, y + 22, 82, 32), 0, Auction.max_price(), int(filter.max_solar), func(value: int) -> void: filter.max_solar = value).name = "FilterSolar"
	UiKit.art(contents, str(Crafting.currency_def("estrela").icon), Rect2(186, y + 24, 28, 28))
	spin(Rect2(214, y + 22, 78, 32), 0, Auction.max_price(), int(filter.max_estrela), func(value: int) -> void: filter.max_estrela = value).name = "FilterEstrela"
	y += 60
	caption(tr("Ordenar por"), Rect2(70, y, 220, 22))
	var sorts: Array = SORT_OPTIONS.map(func(entry: Array) -> Array: return [tr(entry[0]), entry[1]])
	option(Rect2(70, y + 22, 222, 32), sorts, str(filter.sort), func(value: String) -> void: filter.sort = value).name = "FilterSort"
	var go: Button = UiKit.button(contents, tr("BUSCAR"), Rect2(70, 598, 130, 44), new_search, "button_green", 18)
	go.name = "SearchButton"
	UiKit.button(contents, tr("LIMPAR"), Rect2(206, 598, 86, 44), clear_filter, "tab", 14)
	build_results()
	build_details()

func build_results() -> void:
	UiKit.panel(contents, Rect2(316, 130, 520, 506), "paper")
	var heading: String = tr("Carregando...") if loading else (tr("%d anúncios") % total if searched else "")
	UiKit.label(contents, heading, Rect2(330, 134, 300, 30), 17, UiKit.TEXT_DARK)
	for i in range(results.size()):
		var listing: Dictionary = results[i]
		row(listing, Rect2(326, 166 + i * 58, 500, 54), i)
	if searched and results.is_empty() and not loading:
		UiKit.label(contents, tr("Nenhum item à venda com estes filtros."), Rect2(330, 300, 490, 40), 18, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var pages: int = maxi(1, ceili(total / float(Auction.per_page())))
	UiKit.button(contents, "<", Rect2(660, 134, 40, 28), turn_page.bind(-1), "tab", 14)
	UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(700, 134, 80, 28), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(780, 134, 40, 28), turn_page.bind(1), "tab", 14)

func row(listing: Dictionary, rect: Rect2, index: int) -> void:
	var kind: String = str(listing.kind)
	var item: Dictionary = listing.item
	var chosen: bool = not selected.is_empty() and int(selected.id) == int(listing.id)
	var box: Button = UiKit.button(contents, "", rect, pick.bind(index), "card_hover" if chosen else "slot_light")
	box.name = "Listing_%d" % int(listing.id)
	var picture: TextureRect = UiKit.art(box, Auction.item_icon(kind, item), Rect2(6, 4, 46, 46))
	if kind == "item":
		picture.modulate = Armory.icon_tint(item)
	UiKit.clipped(box, Auction.item_name(kind, item), Rect2(58, 2, 270, 26), 16, Auction.item_color(kind, item).darkened(0.45))
	var detail: String = facts(kind, item)
	if is_mine(listing):
		detail = tr("Seu anúncio")
	UiKit.clipped(box, detail, Rect2(58, 26, 364, 24), 13, Color("6a4a2a"))
	price_row(box, int(listing.price_solar), int(listing.price_estrela), Rect2(330, 4, 160, 26), 17)
	UiKit.label(box, Auction.time_left(int(listing.expires_at) - server_now()), Rect2(424, 28, 66, 22), 13, Color("6a4a2a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)

func is_mine(listing: Dictionary) -> bool:
	return listing.get("seller_id") != null and int(listing.seller_id) == int(app.my_account())

func build_details() -> void:
	UiKit.panel(contents, Rect2(846, 130, 378, 506), "paper")
	if selected.is_empty():
		UiKit.label(contents, tr("Escolha um anúncio para ver os detalhes."), Rect2(860, 300, 350, 60), 17, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var kind: String = str(selected.kind)
	var item: Dictionary = selected.item
	UiKit.clipped(contents, Auction.item_name(kind, item), Rect2(856, 136, 358, 30), 18, Auction.item_color(kind, item).darkened(0.45), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	item_box(kind, item, Rect2(862, 170, 96, 96))
	var info: Array[String] = facts_lines(kind, item)
	info.append(tr("Vendedor: %s") % str(selected.get("seller_name", "")))
	info.append(tr("Termina em %s") % Auction.time_left(int(selected.expires_at) - server_now()))
	for i in range(info.size()):
		UiKit.clipped(contents, info[i], Rect2(968, 170 + i * 24, 246, 24), 14, UiKit.TEXT_DARK)
	var lines: Array[String] = Auction.item_lines(kind, item)
	var list: Panel = UiKit.panel(contents, Rect2(858, 272, 354, 132), "dark")
	for i in range(mini(lines.size(), 4)):
		var tone: Color = Color("9ae8ff")
		if kind == "map":
			tone = Color("ff8a6a") if str(InstanceRun.mod_def(str(item.mods[i].id)).get("kind", "")) == "threat" else Color("9aff7a")
		UiKit.clipped(list, lines[i], Rect2(10, 4 + i * 31, 336, 30), 14, tone, UiKit.INK)
	if lines.is_empty():
		UiKit.label(list, tr("Sem bônus.") if kind == "item" else tr("Sem atributos."), Rect2(10, 4, 336, 30), 14, Color("c8b8a0"), UiKit.INK)
	# Last sales of items like this one.
	UiKit.label(contents, tr("Vendas recentes de itens parecidos"), Rect2(858, 408, 354, 24), 14, UiKit.TEXT_DARK)
	if history.is_empty():
		UiKit.label(contents, tr("Nenhuma venda ainda."), Rect2(868, 432, 344, 22), 13, Color("8a6a4a"))
	for i in range(mini(history.size(), 3)):
		var sale: Dictionary = history[i]
		var line: String = "%s  •  %s" % [Auction.listing_price(sale), Auction.time_ago(server_now() - int(sale.get("closed_at", server_now())))]
		UiKit.clipped(contents, line, Rect2(868, 432 + i * 22, 344, 22), 13, Color("6a4a2a"))
	var price_panel: Panel = UiKit.panel(contents, Rect2(858, 504, 354, 50), "dark")
	UiKit.label(price_panel, tr("Preço"), Rect2(12, 0, 100, 50), 18, Color("ffe6a0"), UiKit.INK)
	price_row(price_panel, int(selected.price_solar), int(selected.price_estrela), Rect2(110, 8, 234, 34), 20)
	var reason: String = buy_reason(selected)
	var buy: Button = UiKit.button(contents, tr("COMPRAR"), Rect2(930, 564, 210, 52), confirm_buy, "button_green", 22)
	buy.name = "BuyButton"
	buy.disabled = reason != "" or loading
	buy.tooltip_text = reason
	if reason != "":
		UiKit.clipped(contents, reason, Rect2(858, 614, 354, 22), 13, Color("b8321c"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)

func buy_reason(listing: Dictionary) -> String:
	if is_mine(listing):
		return tr("Este anúncio é seu.")
	if app.profile.currency_count("solar") < int(listing.price_solar) or app.profile.currency_count("estrela") < int(listing.price_estrela):
		return tr("Você não tem Solares e Estrelas suficientes.")
	return ""

func set_type(value: String) -> void:
	filter.slot = value
	filter.mod = ""
	if value == "mapa":
		filter.min_strengthen = 0
	build()

func clear_filter() -> void:
	filter = {"slot": "", "quality": "", "min_level": 0, "min_strengthen": 0, "mod": "", "max_solar": 0, "max_estrela": 0, "sort": "recent"}
	new_search()

func new_search() -> void:
	page = 0
	search()

func search_filter() -> Dictionary:
	var sent: Dictionary = {"sort": filter.sort, "page": page}
	for key: String in ["slot", "quality", "mod"]:
		if str(filter[key]) != "":
			sent[key] = filter[key]
	for key: String in ["min_level", "min_strengthen", "max_solar", "max_estrela"]:
		if int(filter[key]) > 0:
			sent[key] = int(filter[key])
	return sent

func search() -> void:
	loading = true
	build()
	var reply: Dictionary = await app.trade("auction_search", {"filter": search_filter()})
	if not is_inside_tree():
		return
	loading = false
	searched = true
	if reply.ok:
		sync_clock(reply)
		results = reply.listings
		total = int(reply.total)
		message = ""
		var still: Array = results.filter(func(listing: Dictionary) -> bool: return not selected.is_empty() and int(listing.id) == int(selected.id))
		if still.is_empty():
			selected = results[0] if not results.is_empty() else {}
			await load_history()
	else:
		message = str(reply.error)
	if is_inside_tree():
		build()

func turn_page(step: int) -> void:
	var pages: int = maxi(1, ceili(total / float(Auction.per_page())))
	var next: int = clampi(page + step, 0, pages - 1)
	if next != page:
		page = next
		search()

func pick(index: int) -> void:
	selected = results[index]
	message = ""
	build()
	await load_history()
	if is_inside_tree():
		build()

func load_history() -> void:
	history = []
	if selected.is_empty():
		return
	var reply: Dictionary = await app.trade("auction_history", {"kind": selected.kind, "item": selected.item})
	if reply.ok:
		history = reply.sales

func confirm_buy() -> void:
	var listing: Dictionary = selected
	var text: String = tr("Comprar %s por %s?\nO item vai direto para a sua Mochila.") % [Auction.item_name(str(listing.kind), listing.item), Auction.listing_price(listing)]
	var dialog: Control = UiKit.modal(self, tr("COMPRAR"), text)
	dialog.name = "ConfirmBuy"
	var rect: Rect2 = dialog.get_meta("rect")
	UiKit.button(dialog, tr("COMPRAR"), Rect2(rect.position.x + 90, rect.end.y - 60, 150, 42), func() -> void:
		dialog.queue_free()
		buy(listing), "button_green").name = "ConfirmButton"
	UiKit.button(dialog, tr("VOLTAR"), Rect2(rect.end.x - 240, rect.end.y - 60, 150, 42), dialog.queue_free)

func buy(listing: Dictionary) -> void:
	loading = true
	build()
	var reply: Dictionary = await app.trade("auction_buy", {"id": int(listing.id), "solar": int(listing.price_solar), "estrela": int(listing.price_estrela)})
	if not is_inside_tree():
		return
	loading = false
	if reply.ok:
		app.audio.play("ui_coin")
		message = tr("Comprado! %s está na sua Mochila.") % Auction.item_name(str(listing.kind), listing.item) if bool(reply.get("received", false)) else tr("Comprado! O item está no seu Correio.")
		selected = {}
	else:
		app.audio.play("ui_error")
		message = str(reply.error)
	search()

# ---------- Vender ----------

func sell_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if sell_kind == "item":
		for inst: Dictionary in app.profile.inventory:
			if Crafting.can_have_mods(str(inst.id)):
				list.append(inst)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var free_a: bool = Auction.item_reason(app.profile, a) == ""
			var free_b: bool = Auction.item_reason(app.profile, b) == ""
			if free_a != free_b:
				return free_a
			return Crafting.item_level(a) > Crafting.item_level(b) if Crafting.item_level(a) != Crafting.item_level(b) else int(a.uid) < int(b.uid))
	else:
		list = app.profile.maps.duplicate()
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level) if a.level != b.level else int(a.uid) < int(b.uid))
	return list

func sell_subject() -> Dictionary:
	return app.profile.find_instance(sell_uid) if sell_kind == "item" else app.profile.find_map(sell_uid)

func sell_reason_for(entry: Dictionary) -> String:
	return Auction.item_reason(app.profile, entry) if sell_kind == "item" else Auction.map_reason(entry)

func build_sell() -> void:
	UiKit.panel(contents, Rect2(56, 130, 520, 550), "paper")
	UiKit.panel(contents, Rect2(588, 130, 636, 506), "paper")
	for i in range(2):
		var kind: String = ["item", "map"][i]
		var toggle: Button = UiKit.button(contents, tr(["Equipamentos", "Mapas"][i]), Rect2(70 + i * 170, 136, 164, 34), select_sell_kind.bind(kind), "tab_active" if sell_kind == kind else "tab", 15)  # i18n
		toggle.name = "Sell_" + kind
	var list: Array[Dictionary] = sell_list()
	if sell_subject().is_empty() or not list.any(func(entry: Dictionary) -> bool: return int(entry.uid) == sell_uid):
		var first_free: Array = list.filter(func(entry: Dictionary) -> bool: return sell_reason_for(entry) == "")
		sell_uid = int(first_free[0].uid) if not first_free.is_empty() else (int(list[0].uid) if not list.is_empty() else -1)
	var pages: int = maxi(1, ceili(list.size() / float(SELL_PER_PAGE)))
	sell_page = clampi(sell_page, 0, pages - 1)
	for i in range(SELL_PER_PAGE):
		var index: int = sell_page * SELL_PER_PAGE + i
		if index >= list.size():
			break
		var entry: Dictionary = list[index]
		var uid: int = int(entry.uid)
		var rect: Rect2 = Rect2(70 + (i % 6) * 82, 176 + (i / 6 as int) * 72, 76, 66)
		var slot: Button = UiKit.button(contents, "", rect, pick_sell.bind(uid), "card_hover" if uid == sell_uid else "slot")
		slot.name = "SellItem_%d" % uid
		var reason: String = sell_reason_for(entry)
		slot.tooltip_text = "%s%s" % [Auction.item_name(sell_kind, entry), "\n" + reason if reason != "" else ""]
		var picture: TextureRect = UiKit.art(slot, Auction.item_icon(sell_kind, entry), Rect2(12, 6, 52, 52))
		if sell_kind == "item":
			picture.modulate = Armory.icon_tint(entry)
			if int(entry.level) > 0:
				UiKit.label(slot, "+%d" % int(entry.level), Rect2(2, 0, 40, 20), 14, Armory.aura_color(int(entry.level)).lightened(0.3), UiKit.INK)
			if app.profile.is_equipped(uid):
				UiKit.label(slot, "E", Rect2(4, 44, 16, 20), 13, Color("9aff7a"), UiKit.INK)
		else:
			UiKit.label(slot, str(int(entry.level)), Rect2(40, 42, 34, 22), 16, InstanceRun.quality_color(str(entry.quality)), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		if reason != "":
			picture.modulate = picture.modulate * Color(0.5, 0.48, 0.45)
			UiKit.label(slot, "×", Rect2(54, 40, 20, 22), 16, Color("ff8a6a"), UiKit.INK)
	if list.is_empty():
		UiKit.label(contents, tr("Nenhum equipamento que aceite bônus.") if sell_kind == "item" else tr("Nenhum mapa na mochila."), Rect2(72, 200, 490, 40), 18, UiKit.TEXT_DARK)
	UiKit.button(contents, "<", Rect2(380, 626, 40, 32), turn_sell_page.bind(-1), "tab", 14)
	UiKit.label(contents, "%d/%d" % [sell_page + 1, pages], Rect2(420, 626, 80, 32), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(500, 626, 40, 32), turn_sell_page.bind(1), "tab", 14)
	UiKit.label(contents, tr("Só vão ao leilão itens que caíram nas instâncias e mapas, sem vínculo."), Rect2(70, 586, 490, 36), 13, Color("8a3a10")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_sell_form()

func build_sell_form() -> void:
	var subject: Dictionary = sell_subject()
	if subject.is_empty():
		UiKit.label(contents, tr("Escolha um equipamento ou um mapa."), Rect2(600, 300, 612, 40), 20, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	UiKit.label(contents, Auction.item_name(sell_kind, subject), Rect2(600, 136, 612, 32), 21, Auction.item_color(sell_kind, subject).darkened(0.45), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	item_box(sell_kind, subject, Rect2(604, 172, 108, 108))
	UiKit.label(contents, facts(sell_kind, subject), Rect2(724, 170, 488, 26), 15, UiKit.TEXT_DARK)
	var lines: Array[String] = Auction.item_lines(sell_kind, subject)
	for i in range(mini(lines.size(), 3)):
		UiKit.clipped(contents, lines[i], Rect2(724, 196 + i * 26, 488, 26), 14, Color("2a6a8a"))
	var reason: String = sell_reason_for(subject)
	if reason != "":
		UiKit.label(contents, reason, Rect2(600, 300, 612, 40), 18, Color("b8321c"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	# Price, duration and what the seller gets.
	caption(tr("Preço"), Rect2(610, 292, 120, 30))
	UiKit.art(contents, str(Crafting.currency_def("solar").icon), Rect2(700, 290, 34, 34))
	spin(Rect2(738, 292, 110, 34), 0, Auction.max_price(), price_solar, set_price.bind("solar")).name = "PriceSolar"
	UiKit.art(contents, str(Crafting.currency_def("estrela").icon), Rect2(866, 290, 34, 34))
	spin(Rect2(904, 292, 110, 34), 0, Auction.max_price(), price_estrela, set_price.bind("estrela")).name = "PriceEstrela"
	caption(tr("Duração"), Rect2(610, 338, 120, 30))
	var options: Array[int] = Auction.hours_options()
	for i in range(options.size()):
		var value: int = options[i]
		var button: Button = UiKit.button(contents, tr("%d h") % value, Rect2(700 + i * 118, 336, 110, 34), set_hours.bind(value), "tab_active" if hours == value else "tab", 15)
		button.name = "Hours_%d" % value
		button.tooltip_text = tr("Taxa: %d moedas") % Auction.fee_for(value)
	var summary: Panel = UiKit.panel(contents, Rect2(604, 380, 604, 104), "dark")
	summary.name = "SellSummary"
	var fee_solar: int = Auction.commission(price_solar)
	var fee_estrela: int = Auction.commission(price_estrela)
	var rows: Array[String] = [
		tr("Taxa do anúncio: %d moedas (não volta se cancelar)") % Auction.fee_for(hours),
		tr("Comissão de %d%% na venda: %s") % [roundi(float(Auction.rules().commission) * 100.0), Auction.price_text(fee_solar, fee_estrela) if fee_solar + fee_estrela > 0 else tr("nada neste preço")],
		tr("Você recebe no Correio: %s") % Auction.price_text(price_solar - fee_solar, price_estrela - fee_estrela),
	]
	for i in range(rows.size()):
		UiKit.label(summary, rows[i], Rect2(12, 4 + i * 32, 580, 30), 15, Color("fff4d6") if i < 2 else Color("9aff7a"), UiKit.INK)
	var problem: String = Auction.listing_reason(app.profile, sell_kind, sell_uid, price_solar, price_estrela, hours)
	var list_button: Button = UiKit.button(contents, tr("ANUNCIAR"), Rect2(810, 492, 200, 50), confirm_list, "button_green", 22)
	list_button.name = "ListButton"
	list_button.disabled = problem != "" or loading
	list_button.tooltip_text = problem
	if problem != "":
		UiKit.label(contents, problem, Rect2(600, 544, 612, 26), 14, Color("b8321c"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(contents, tr("Vendas recentes de itens parecidos"), Rect2(610, 570, 300, 24), 14, UiKit.TEXT_DARK)
	var shown: Array[String] = []
	for sale: Dictionary in history.slice(0, 3):
		shown.append(Auction.listing_price(sale))
	UiKit.clipped(contents, "  •  ".join(shown) if not shown.is_empty() else tr("Nenhuma venda ainda."), Rect2(610, 594, 600, 24), 14, Color("6a4a2a"))

func set_price(value: int, currency: String) -> void:
	if currency == "solar":
		price_solar = value
	else:
		price_estrela = value
	refresh_summary()

func refresh_summary() -> void:
	# Rebuilt a moment later, so typing in the price fields is not interrupted.
	if has_meta("summary_pending"):
		return
	set_meta("summary_pending", true)
	await get_tree().create_timer(0.6).timeout
	remove_meta("summary_pending")
	if is_inside_tree() and tab == "sell":
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is LineEdit and contents.is_ancestor_of(focused):
			refresh_summary()
			return
		build()

func set_hours(value: int) -> void:
	hours = value
	build()

func select_sell_kind(kind: String) -> void:
	sell_kind = kind
	sell_uid = -1
	sell_page = 0
	message = ""
	build()
	await load_sell_history()

func pick_sell(uid: int) -> void:
	sell_uid = uid
	message = ""
	build()
	await load_sell_history()

func turn_sell_page(step: int) -> void:
	sell_page += step
	build()

func load_sell_history() -> void:
	history = []
	var subject: Dictionary = sell_subject()
	if subject.is_empty():
		return
	var reply: Dictionary = await app.trade("auction_history", {"kind": sell_kind, "item": subject})
	if reply.ok and is_inside_tree():
		sync_clock(reply)
		history = reply.sales
		if tab == "sell":
			build()

func confirm_list() -> void:
	var subject: Dictionary = sell_subject()
	var text: String = tr("Anunciar %s por %s durante %d h?\nA taxa de %d moedas é paga agora.") % [Auction.item_name(sell_kind, subject), Auction.price_text(price_solar, price_estrela), hours, Auction.fee_for(hours)]
	var dialog: Control = UiKit.modal(self, tr("ANUNCIAR"), text)
	dialog.name = "ConfirmList"
	var rect: Rect2 = dialog.get_meta("rect")
	UiKit.button(dialog, tr("ANUNCIAR"), Rect2(rect.position.x + 90, rect.end.y - 60, 150, 42), func() -> void:
		dialog.queue_free()
		list_item(), "button_green").name = "ConfirmButton"
	UiKit.button(dialog, tr("VOLTAR"), Rect2(rect.end.x - 240, rect.end.y - 60, 150, 42), dialog.queue_free)

func list_item() -> void:
	var subject: Dictionary = sell_subject()
	var name_text: String = Auction.item_name(sell_kind, subject)
	loading = true
	build()
	var reply: Dictionary = await app.trade("auction_list", {"kind": sell_kind, "uid": sell_uid, "solar": price_solar, "estrela": price_estrela, "hours": hours})
	if not is_inside_tree():
		return
	loading = false
	if reply.ok:
		app.audio.play("ui_coin")
		message = tr("%s foi anunciado por %s.") % [name_text, Auction.price_text(price_solar, price_estrela)]
		sell_uid = -1
	else:
		app.audio.play("ui_error")
		message = str(reply.error)
	build()

# ---------- Meus anúncios ----------

func build_mine() -> void:
	UiKit.panel(contents, Rect2(56, 130, 580, 506), "paper")
	UiKit.panel(contents, Rect2(646, 130, 578, 506), "paper")
	UiKit.label(contents, tr("À venda (%d/%d)") % [mine_active.size(), Auction.max_listings()], Rect2(70, 136, 400, 30), 19, UiKit.TEXT_DARK)
	UiKit.label(contents, tr("Encerrados"), Rect2(660, 136, 400, 30), 19, UiKit.TEXT_DARK)
	if loading:
		UiKit.label(contents, tr("Carregando..."), Rect2(70, 300, 550, 40), 18, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	for i in range(mini(mine_active.size(), 10)):
		var listing: Dictionary = mine_active[i]
		var rect: Rect2 = Rect2(66, 170 + i * 46, 560, 42)
		var box: Panel = UiKit.panel(contents, rect, "slot_light")
		mine_line(box, listing, Auction.time_left(int(listing.expires_at) - server_now()))
		var cancel: Button = UiKit.button(box, tr("CANCELAR"), Rect2(456, 5, 98, 32), confirm_cancel.bind(listing), "button", 13)
		cancel.name = "Cancel_%d" % int(listing.id)
	if mine_active.is_empty():
		UiKit.label(contents, tr("Nada à venda. Anuncie na aba Vender."), Rect2(70, 300, 550, 40), 17, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var status_text: Dictionary = {"sold": "Vendido", "cancelled": "Cancelado", "expired": "Vencido"}  # i18n
	for i in range(mini(mine_closed.size(), 10)):
		var listing: Dictionary = mine_closed[i]
		var rect: Rect2 = Rect2(656, 170 + i * 46, 558, 42)
		var box: Panel = UiKit.panel(contents, rect, "slot")
		var when: String = Auction.time_ago(server_now() - int(listing.closed_at)) if listing.get("closed_at") != null else ""
		mine_line(box, listing, "%s  %s" % [tr(str(status_text.get(str(listing.status), ""))), when], Color("fff4d6"))
	if mine_closed.is_empty():
		UiKit.label(contents, tr("Nenhum anúncio encerrado."), Rect2(660, 300, 550, 40), 17, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(contents, tr("Vendas e itens que voltam chegam pelo Correio."), Rect2(66, 600, 560, 30), 14, Color("8a3a10"))

func mine_line(box: Panel, listing: Dictionary, status: String, text_color: Color = UiKit.TEXT_DARK) -> void:
	var kind: String = str(listing.kind)
	var picture: TextureRect = UiKit.art(box, Auction.item_icon(kind, listing.item), Rect2(6, 3, 36, 36))
	if kind == "item":
		picture.modulate = Armory.icon_tint(listing.item)
	UiKit.clipped(box, Auction.item_name(kind, listing.item), Rect2(48, 0, 230, 42), 14, text_color)
	UiKit.clipped(box, Auction.listing_price(listing), Rect2(280, 0, 170, 22), 13, text_color)
	UiKit.clipped(box, status, Rect2(280, 20, 170, 22), 13, text_color.darkened(0.15))

func load_mine() -> void:
	loading = true
	build()
	var reply: Dictionary = await app.trade("auction_mine")
	if not is_inside_tree():
		return
	loading = false
	if reply.ok:
		sync_clock(reply)
		mine_active = reply.active
		mine_closed = reply.closed
	else:
		message = str(reply.error)
	build()

func confirm_cancel(listing: Dictionary) -> void:
	var dialog: Control = UiKit.modal(self, tr("CANCELAR"), tr("Tirar %s do leilão?\nO item volta para a Mochila; a taxa do anúncio não volta.") % Auction.item_name(str(listing.kind), listing.item))
	dialog.name = "ConfirmCancel"
	var rect: Rect2 = dialog.get_meta("rect")
	UiKit.button(dialog, tr("TIRAR"), Rect2(rect.position.x + 90, rect.end.y - 60, 150, 42), func() -> void:
		dialog.queue_free()
		cancel(listing)).name = "ConfirmButton"
	UiKit.button(dialog, tr("VOLTAR"), Rect2(rect.end.x - 240, rect.end.y - 60, 150, 42), dialog.queue_free)

func cancel(listing: Dictionary) -> void:
	var reply: Dictionary = await app.trade("auction_cancel", {"id": int(listing.id)})
	if not is_inside_tree():
		return
	if reply.ok:
		message = tr("%s voltou para a sua Mochila.") % Auction.item_name(str(listing.kind), listing.item) if bool(reply.get("received", false)) else tr("O item está no seu Correio.")
	else:
		app.audio.play("ui_error")
		message = str(reply.error)
	load_mine()

# ---------- tabs ----------

func select_tab(value: String) -> void:
	tab = value
	message = ""
	history = []
	match tab:
		"buy":
			search()
		"sell":
			build()
			await load_sell_history()
		"mine":
			load_mine()

func open_mail() -> void:
	var mail: MailScreen = app.open_mail(self)
	if mail != null:
		mail.closed.connect(build)

func close() -> void:
	closed.emit()
	queue_free()
