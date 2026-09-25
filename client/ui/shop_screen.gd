class_name ShopScreen
extends Control

# Centro Comercial / SHOP: weapons in three qualities (Normal, Excelente, Verdadeira),
# outfits, hats, glasses, wings, hair colours, auxiliary items and stones. Clicking an
# item tries it on the provador (preview) on the left. Super weapons are drop-only.
# Premium (launch checklist): products paid with the Steam Wallet (PremiumStore), only
# looks, delivered by the Correio.

signal closed

const TABS: Array = [["Armas", "arma"], ["Roupas", "roupa"], ["Chapéus", "chapeu"], ["Óculos", "oculos"], ["Asas", "asas"], ["Cabelos", "cabelo"], ["Auxiliar", "auxiliar"], ["Pedras", "pedras"], ["Premium", "premium"]]  # i18n
const PER_PAGE: int = 8

var app: Node
var tab: String = "arma"
var page: int = 0
var trying: Dictionary = {}
var contents: Control
var message: String = ""

func _ready() -> void:
	size = Vector2(1280, 720)
	build()

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
	UiKit.title(contents, tr("CENTRO COMERCIAL"), Rect2(40, 30, 1200, 44), 30)
	UiKit.button(contents, tr("FECHAR"), Rect2(1086, 34, 140, 42), close)
	build_preview()
	for i in range(TABS.size()):
		var tab_button: Button = UiKit.button(contents, tr(TABS[i][0]), Rect2(432 + i * 88, 84, 85, 38), select_tab.bind(str(TABS[i][1])), "tab_active" if tab == TABS[i][1] else "tab", 14)
		tab_button.name = "Tab_" + str(TABS[i][1])
	UiKit.panel(contents, Rect2(430, 126, 794, 554), "paper")
	var list: Array = items()
	var pages: int = maxi(1, ceili(list.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = page * PER_PAGE + i
		if index >= list.size():
			break
		card(list[index], Rect2(442 + (i % 4) * 194, 136 + (i / 4 as int) * 248, 188, 240))
	UiKit.button(contents, "<", Rect2(1052, 636, 44, 36), turn_page.bind(-1), "tab", 16)
	UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(1096, 636, 80, 36), 16, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(1176, 636, 44, 36), turn_page.bind(1), "tab", 16)
	if message != "":
		var bar: Panel = UiKit.panel(contents, Rect2(442, 636, 600, 36), "dark")
		UiKit.label(bar, message, Rect2(8, 0, 584, 36), 15, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func build_preview() -> void:
	UiKit.panel(contents, Rect2(56, 84, 360, 596), "paper")
	UiKit.label(contents, tr("PROVADOR"), Rect2(56, 90, 360, 30), 20, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var look: Dictionary = app.profile.look()
	if not trying.is_empty():
		var equipped: Array = app.profile.equipped_list().filter(func(inst: Dictionary) -> bool: return Armory.slot_of(str(inst.id)) != Armory.slot_of(str(trying.id)))
		equipped.append(trying)
		look = Armory.look_for(app.profile.gender, equipped)
	var stage: Panel = UiKit.panel(contents, Rect2(70, 124, 332, 420), "dark")
	stage.clip_contents = true
	AvatarView.create(stage, look, Rect2(0, 20, 332, 390))
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(90, 556, 34, 34))
	UiKit.label(contents, str(app.profile.coins), Rect2(130, 552, 250, 40), 24, Color("a86a10"), Color.TRANSPARENT)
	var hint: String = tr("Só aparência: não muda atributos e chega pelo Correio.\nO preço na sua moeda aparece na Steam.") if tab == "premium" else tr("Clique num item para provar.\nVerdadeiras e Super armas só caem nas instâncias.")
	UiKit.label(contents, hint, Rect2(70, 596, 332, 50), 14, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, tr("CUPOM"), Rect2(160, 644, 150, 32), func() -> void: CouponDialog.open(self, app, build), "button", 14)

func items() -> Array:
	var list: Array = []
	match tab:
		"arma":
			list = Armory.data().weapons.duplicate()
		"auxiliar":
			list = Armory.data().auxiliary.duplicate()
		"pedras":
			list = Armory.data().strengthen.stones.duplicate()
		"premium":
			list = PremiumStore.products().filter(func(entry: Dictionary) -> bool: return PremiumStore.valid(entry))
		_:
			for def: Dictionary in Armory.data().cosmetics:
				if def.slot == tab and (def.gender == "u" or def.gender == app.profile.gender) and not bool(def.get("premium", false)):
					list.append(def)
	return list

func card(def: Dictionary, rect: Rect2) -> void:
	if tab == "premium":
		premium_card(def, rect)
		return
	var box: Button = UiKit.button(contents, "", rect, try_on.bind(def), "card")
	box.name = "Shop_" + str(def.id)
	var inst: Dictionary = {"id": def.id, "quality": "super" if def.get("super", false) else "normal", "level": 0}
	var icon: Texture2D = load(str(def.icon)) if tab == "pedras" else Armory.load_icon(inst)
	var picture: TextureRect = UiKit.art(box, icon, Rect2(44, 8, 100, 92))
	picture.modulate = Armory.icon_tint(inst)
	var title: Label = UiKit.label(box, tr(str(def.name)), Rect2(4, 100, 180, 44), 15, Color("fff6dc"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if tab == "arma":
		if def.get("super", false):
			UiKit.label(box, tr("SUPER VERDADEIRA\nSó no baú do chefe"), Rect2(4, 146, 180, 60), 13, Color("ffb347"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
			UiKit.label(box, tr("Você tem") if app.profile.has_item(def.id) else "", Rect2(4, 204, 180, 28), 14, Color("9aff7a"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
			return
		# 0.9: the shop sells Normal and Excelente only; Verdadeira comes from instances.
		for q in range(2):
			var quality: String = ["normal", "excelente"][q]
			var price: int = PlayerProfile.item_price(str(def.id), quality)
			var label_text: String = "%s  %d" % [Armory.quality_label(quality), price]
			var buy: Button = UiKit.button(box, label_text, Rect2(8, 146 + q * 30, 172, 28), buy_item.bind(str(def.id), quality), ["button", "button_blue"][q], 13)
			buy.disabled = app.profile.coins < price
		UiKit.label(box, tr("Verdadeira: instâncias"), Rect2(4, 208, 180, 24), 12, Color("c99bff"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var price_value: int = int(def.get("price", 0))
	UiKit.label(box, tr("%d moedas") % price_value, Rect2(4, 148, 180, 28), 16, Color("ffd46b"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	if tab == "pedras":
		UiKit.label(box, tr("%d ponto(s) • você tem %d") % [int(def.points), int(app.profile.items.get(def.id, 0))], Rect2(4, 174, 180, 24), 13, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.button(box, "x1", Rect2(8, 202, 80, 30), buy_stone.bind(str(def.id), 1), "button_green", 14)
		UiKit.button(box, "x10", Rect2(100, 202, 80, 30), buy_stone.bind(str(def.id), 10), "button_green", 14)
		return
	var owned: bool = app.profile.has_item(def.id)
	var buy_button: Button = UiKit.button(box, tr("COMPRADO") if owned and tab != "auxiliar" else tr("COMPRAR"), Rect2(24, 190, 140, 38), buy_item.bind(str(def.id), "normal"), "button_green", 16)
	buy_button.disabled = (owned and tab != "auxiliar") or app.profile.coins < price_value

# A product of the Steam shop: its first item on the card, the reference price and the
# purchase through the Steam overlay (only in the Steam build, online).
func premium_card(entry: Dictionary, rect: Rect2) -> void:
	var first: Dictionary = Armory.definition(str(entry.items[0]))
	var box: Button = UiKit.button(contents, "", rect, try_on.bind(first), "card")
	box.name = "Premium_" + str(entry.sku)
	var inst: Dictionary = {"id": first.id, "quality": "normal", "level": 0}
	var picture: TextureRect = UiKit.art(box, Armory.load_icon(inst), Rect2(44, 8, 100, 92))
	picture.modulate = Armory.icon_tint(inst)
	var title: Label = UiKit.label(box, tr(str(entry.name)), Rect2(4, 100, 180, 44), 15, Color("fff6dc"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var count: int = (entry.items as Array).size()
	UiKit.label(box, PremiumStore.price_text(entry) + ("" if count == 1 else "  •  " + tr("%d itens") % count), Rect2(4, 146, 180, 28), 15, Color("9ae8ff"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var owned: bool = PremiumStore.owns_all(app.profile, entry)
	var ready: bool = bool(app.online) and app.steam.available
	var buy: Button = UiKit.button(box, tr("VOCÊ TEM") if owned else tr("COMPRAR NA STEAM"), Rect2(14, 190, 160, 38), buy_premium.bind(str(entry.sku)), "button_blue", 14)
	buy.name = "Buy_" + str(entry.sku)
	buy.disabled = owned or not ready
	if not ready and not owned:
		buy.tooltip_text = tr("Compras só na versão Steam, com a conta ligada à Steam.")
		UiKit.label(box, tr("Só na versão Steam"), Rect2(4, 170, 180, 20), 12, Color("ffd46b"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func buy_premium(sku: String) -> void:
	message = tr("Aprove a compra na janela da Steam…")
	build()
	message = await app.buy_premium(sku)
	if is_inside_tree():
		build()

func try_on(def: Dictionary) -> void:
	if tab in ["pedras"]:
		return
	trying = {"id": def.id, "quality": "super" if def.get("super", false) else "normal", "level": 0}
	build()

func buy_item(id: String, quality: String) -> void:
	var error: String = (await app.do_op("buy", [id, quality])).error
	message = error if error != "" else tr("Comprado! Veja na Mochila.")
	app.audio.play("ui_coin" if error == "" else "ui_error")
	build()

func buy_stone(id: String, amount: int) -> void:
	var error: String = (await app.do_op("buy_stone", [id, amount])).error
	message = error if error != "" else tr("Comprado: %d pedra(s).") % amount
	app.audio.play("ui_coin" if error == "" else "ui_error")
	build()

func select_tab(value: String) -> void:
	tab = value
	page = 0
	build()

func turn_page(step: int) -> void:
	page += step
	build()

func close() -> void:
	closed.emit()
	queue_free()
