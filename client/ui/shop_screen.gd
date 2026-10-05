class_name ShopScreen
extends Control

# Centro Comercial / SHOP: Normal weapons, skins, shirts, trousers, hats, glasses and hair colours
# for coins; the wings (0.32) and the pets are sold for money (premium products).
# Excelente/Verdadeira/Super weapons, auxiliary items and stones are drop or auction only
# (0.21). Clicking an item tries it on the provador (preview) on the left.
# Premium (launch checklist): products paid with the Steam Wallet (PremiumStore), only
# looks, delivered by the Correio.

signal closed

const TABS: Array = [["Armas", "arma"], ["Skins", "skin"], ["Camisas", "camisa"], ["Calças", "calca"], ["Chapéus", "chapeu"], ["Óculos", "oculos"], ["Asas", "asas"], ["Joias", "joia"], ["Cabelos", "cabelo"], ["Mascotes", "pet"], ["Premium", "premium"]]  # i18n
const PER_PAGE: int = 8
# Layout of the right-hand side: the tabs wrap onto rows (a tab on a short last row grows to the
# end of the row), then the cards (4 per row, 2 rows), then the pager centred under them.
const TABS_PER_ROW: int = 6
const TAB_RECT: Rect2 = Rect2(430, 84, 128, 40)
const TAB_STEP: Vector2 = Vector2(133, 44)
const GRID_PANEL: Rect2 = Rect2(430, 172, 794, 508)
const CARD_SIZE: Vector2 = Vector2(188, 210)
const CARD_STEP: Vector2 = Vector2(194, 216)
const CARD_ORIGIN: Vector2 = Vector2(442, 180)
const PAGER_CENTER_X: float = 827.0
const PAGER_Y: float = 620.0

var app: Node
var tab: String = "arma"
var page: int = 0
var trying: Dictionary = {}
var contents: Control
var message: String = ""
# The provador can show the skin alone; it starts as the character's own choice and never
# changes it (that lives on the Mochila).
var preview_skin_only: bool = false
# The fitting stage (SkinStage): standing (turning to the four directions) or in the battle pose.
var preview_mode: String = "stand"
var preview_direction: String = "south"
# The alternative colour tried on the skin in the fitting room ("" = the original).
var preview_color: String = ""
# The pet tried beside the character in the Mascotes tab ("" = the character's own).
var trying_pet: String = ""

func _ready() -> void:
	size = Vector2(1280, 720)
	preview_skin_only = app.profile.skin_only
	build()

func build() -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
	contents = Control.new()
	contents.size = size
	add_child(contents)
	move_child(contents, 0)
	PremiumUi.window(contents, Rect2(40, 24, 1200, 672), tr("CENTRO COMERCIAL"), "", 0.94, 36)
	UiKit.button(contents, tr("FECHAR"), Rect2(1086, 34, 140, 42), close)
	build_preview()
	build_tabs()
	UiKit.panel(contents, GRID_PANEL, "paper")
	var list: Array = items()
	var pages: int = maxi(1, ceili(list.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = page * PER_PAGE + i
		if index >= list.size():
			break
		card(list[index], Rect2(CARD_ORIGIN + Vector2((i % 4) * CARD_STEP.x, (i / 4 as int) * CARD_STEP.y), CARD_SIZE))
	build_pager(pages)

# The tabs in rows of TABS_PER_ROW: every tab has room for its text (a 16 px pixel font needs
# ~110 px for the longest word), and the last tab fills the rest of its row.
func build_tabs() -> void:
	for i in range(TABS.size()):
		var col: int = i % TABS_PER_ROW
		var row: int = i / TABS_PER_ROW
		var rect: Rect2 = Rect2(TAB_RECT.position + Vector2(col * TAB_STEP.x, row * TAB_STEP.y), TAB_RECT.size)
		if i == TABS.size() - 1:
			rect.size.x += (TABS_PER_ROW - 1 - col) * TAB_STEP.x
		var tab_button: Button = UiKit.button(contents, tr(TABS[i][0]), rect, select_tab.bind(str(TABS[i][1])), "tab_active" if tab == TABS[i][1] else "tab", 16)
		tab_button.name = "Tab_" + str(TABS[i][1])

# "<  1/2  >" centred under the cards, well away from the frame; the ends are greyed out.
func build_pager(pages: int) -> void:
	var back: Button = UiKit.button(contents, "<", Rect2(PAGER_CENTER_X - 50 - 12 - 52, PAGER_Y, 52, 38), turn_page.bind(-1), "tab", 26)
	back.name = "PagePrev"
	back.disabled = page <= 0
	var counter: Label = UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(PAGER_CENTER_X - 50, PAGER_Y, 100, 38), 18, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	counter.name = "PageCounter"
	var next: Button = UiKit.button(contents, ">", Rect2(PAGER_CENTER_X + 50 + 12, PAGER_Y, 52, 38), turn_page.bind(1), "tab", 26)
	next.name = "PageNext"
	next.disabled = page >= pages - 1

func build_preview() -> void:
	UiKit.panel(contents, Rect2(56, 84, 360, 596), "paper")
	UiKit.label(contents, tr("PROVADOR"), Rect2(56, 90, 360, 30), 20, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var equipped: Array = app.profile.equipped_list()
	if not trying.is_empty():
		equipped = equipped.filter(func(inst: Dictionary) -> bool: return Armory.slot_of(str(inst.id)) != Armory.slot_of(str(trying.id)))
		equipped.append(trying)
	var colors: Dictionary = app.profile.skin_colors.duplicate()
	if not trying.is_empty() and Armory.slot_of(str(trying.id)) == "skin":
		colors[str(trying.id)] = preview_color
	var look: Dictionary = app.profile.look() if trying.is_empty() and preview_skin_only == app.profile.skin_only else Armory.look_for(app.profile.gender, equipped, preview_skin_only, colors)
	if trying_pet != "":
		look = look.duplicate()
		look["pet"] = trying_pet
	var stage: Panel = UiKit.panel(contents, Rect2(70, 124, 332, 340), "dark")
	stage.clip_contents = true
	var fitting: Dictionary = app.profile.entry(app.balance).duplicate()
	SkinStage.mount(stage, look, fitting, app.balance, preview_mode, preview_direction, change_stage)
	var only: CheckBox = UiKit.check_box(stage, tr("Só a skin"), Rect2(8, 298, 200, 34), preview_skin_only, 16)
	only.name = "PreviewSkinOnly"
	only.toggled.connect(func(on: bool) -> void:
		preview_skin_only = on
		build())
	if not trying.is_empty() and Armory.slot_of(str(trying.id)) == "skin":
		SkinColors.build(stage, Vector2(10, 262), str(trying.id), preview_color, func(color_id: String) -> void:
			preview_color = color_id
			build())
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(90, 472, 34, 34))
	UiKit.label(contents, str(app.profile.coins), Rect2(130, 468, 250, 40), 24, UiKit.GOLD, Color.TRANSPARENT)
	var hint: String = hint_text()
	if message != "":
		# The result of the last purchase takes the place of the hint (the payment messages are
		# long: they wrap inside the box); the next click on a tab, page or item brings the hint back.
		var bar: Panel = UiKit.panel(contents, Rect2(70, 514, 332, 124), "dark")
		UiKit.wrapped(bar, message, Rect2(10, 4, 312, 116), 15, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		# The hint wraps inside its box (the text is long and the font never goes under 16).
		UiKit.wrapped(contents, hint, Rect2(70, 514, 332, 124), 14, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, tr("CUPOM"), Rect2(160, 644, 150, 32), func() -> void: CouponDialog.open(self, app, build), "button", 14)

func change_stage(key: String, value: String) -> void:
	if key == "mode":
		preview_mode = value
	else:
		preview_direction = value
	build()

func items() -> Array:
	var list: Array = []
	match tab:
		"arma":
			# Premium weapons (Solaris) live in the Premium tab, never in the gold shop.
			list = Armory.data().weapons.filter(func(def: Dictionary) -> bool: return not bool(def.get("premium", false)))
		"premium":
			list = PremiumStore.products().filter(func(entry: Dictionary) -> bool: return PremiumStore.valid(entry) and not PremiumStore.is_pet_product(entry) and not PremiumStore.is_wings_product(entry))
		"asas":
			list = PremiumStore.products().filter(func(entry: Dictionary) -> bool: return PremiumStore.valid(entry) and PremiumStore.is_wings_product(entry))
		"pet":
			list = PremiumStore.products().filter(func(entry: Dictionary) -> bool: return PremiumStore.valid(entry) and PremiumStore.is_pet_product(entry))
		_:
			for def: Dictionary in Armory.data().cosmetics:
				if (def.slot == tab or (tab == "joia" and def.slot in ["anel", "amuleto"])) and (def.gender == "u" or def.gender == app.profile.gender) and not bool(def.get("premium", false)) and not bool(def.get("drop_only", false)):
					list.append(def)
	return list

func card(def: Dictionary, rect: Rect2) -> void:
	if tab in PRODUCT_TABS:
		premium_card(def, rect)
		return
	var box: Button = UiKit.button(contents, "", rect, try_on.bind(def), "card")
	box.name = "Shop_" + str(def.id)
	var inst: Dictionary = {"id": def.id, "quality": "super" if def.get("super", false) else "normal", "level": 0}
	var icon: Texture2D = Armory.load_icon(inst)
	var picture: TextureRect = UiKit.art(box, icon, Rect2(44, 6, 100, 80))
	picture.modulate = Armory.icon_tint(inst)
	UiKit.wrapped(box, tr(str(def.name)), Rect2(4, 86, 180, 40), 15, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	if tab == "arma":
		if def.get("super", false):
			UiKit.label(box, tr("SUPER VERDADEIRA\nSó no baú do chefe"), Rect2(4, 130, 180, 56), 13, Color("ffb066"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
			UiKit.label(box, tr("Você tem") if app.profile.has_item(def.id) else "", Rect2(4, 184, 180, 26), 14, UiKit.GOOD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
			return
		# 0.21: the shop sells Normal only; Excelente, Verdadeira and Super come from
		# instances (or the auction).
		var price: int = PlayerProfile.item_price(str(def.id), "normal")
		var buy: Button = UiKit.button(box, "%s  %d" % [Armory.quality_label("normal"), price], Rect2(8, 130, 172, 32), buy_item.bind(str(def.id), "normal"), "button", 14)
		buy.disabled = app.profile.coins < price
		UiKit.label(box, tr("Excelente e Verdadeira:\ninstâncias e leilão"), Rect2(4, 164, 180, 44), 13, Color("c9a8ff"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var price_value: int = int(def.get("price", 0))
	UiKit.label(box, tr("%d moedas") % price_value, Rect2(4, 130, 180, 28), 16, UiKit.GOLD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var owned: bool = app.profile.has_item(def.id)
	var buy_button: Button = UiKit.button(box, tr("COMPRADO") if owned else tr("COMPRAR"), Rect2(24, 164, 140, 38), buy_item.bind(str(def.id), "normal"), "button_green", 16)
	buy_button.disabled = owned or app.profile.coins < price_value

# A product of the Steam shop: its first item on the card, the reference price and the
# purchase through the Steam overlay (only in the Steam build, online).
func premium_card(entry: Dictionary, rect: Rect2) -> void:
	var pet_product: bool = PremiumStore.is_pet_product(entry)
	var first: Dictionary = {} if pet_product else Armory.definition(str(entry.items[0]))
	var box: Button = UiKit.button(contents, "", rect, try_on_pet.bind(str(PremiumStore.pet_species(entry)[0])) if pet_product else try_on.bind(first), "card")
	box.name = "Premium_" + str(entry.sku)
	if pet_product:
		UiKit.art(box, PetWidgets.species_texture(str(PremiumStore.pet_species(entry)[0])), Rect2(34, 18, 120, 64))
	else:
		var inst: Dictionary = {"id": first.id, "quality": "normal", "level": 0}
		var picture: TextureRect = UiKit.art(box, Armory.load_icon(inst), Rect2(44, 22, 100, 60))
		picture.modulate = Armory.icon_tint(inst)
	# Long names ("Tempestade Viva — Skin Épica") wrap onto a second line inside the card.
	UiKit.wrapped(box, tr(str(entry.name)), Rect2(4, 84, 180, 40), 15, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var count: int = (entry.get("items", []) as Array).size()
	var tag: String = PremiumStore.kind_label(entry)
	var tag_color: Color = Color("c9a8ff") if tag == tr("ÉPICA") else (Color("ffd04a") if tag == tr("LENDÁRIA") else UiKit.INFO)
	if pet_product:
		tag_color = Pets.rarity_color(str(Pets.species_def(str(PremiumStore.pet_species(entry)[0])).rarity)).lightened(0.15)
	elif PremiumStore.is_wings_product(entry):
		tag_color = Armory.rarity_color(PremiumStore.wings_rarity(entry)).lightened(0.15)
	UiKit.label(box, tag, Rect2(4, 2, 180, 20), 13, tag_color, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(box, PremiumStore.price_label(entry, app.steam.available) + ("" if count <= 1 else "  •  " + tr("%d itens") % count), Rect2(4, 124, 180, 24), 15, UiKit.INFO, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var owned: bool = PremiumStore.owns_all(app.profile, entry)
	var overlap: bool = PremiumStore.overlaps(app.profile, entry)
	var ready: bool = PremiumStore.can_buy(app)
	var pending: Variant = app.get("pending_checkout")
	var waiting: bool = pending is Dictionary and str(pending.get("sku", "")) == str(entry.sku)
	var label: String = tr("VOCÊ TEM") if owned else (tr("ABRIR PAGAMENTO") if waiting else PremiumStore.buy_label(app.steam.available))
	var buy: Button = UiKit.button(box, label, Rect2(14, 166, 160, 38), (reopen_payment if waiting else buy_premium.bind(str(entry.sku))), "button_blue", 14)
	buy.name = "Buy_" + str(entry.sku)
	buy.disabled = owned or overlap or not ready
	if overlap and not owned:
		buy.tooltip_text = tr("Você já tem parte deste pacote: compre as skins que faltam, uma a uma.")
	if not ready and not owned:
		buy.tooltip_text = tr("Entre com a sua conta para comprar.")
		UiKit.label(box, tr("Só online"), Rect2(4, 146, 180, 20), 12, UiKit.GOLD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)

# The tabs of worn gear: the better pieces (Raro, Épico, Lendário) are not sold, they drop in instances.
const GEAR_TABS: Array[String] = ["camisa", "calca", "chapeu", "oculos", "joia"]
# The tabs of products paid with money (cards of `premium_card`): the wings, the pets and the rest.
const PRODUCT_TABS: Array[String] = ["premium", "pet", "asas"]

func hint_text() -> String:
	match tab:
		"pet":
			return pet_hint()
		"asas":
			return wings_hint()
		"premium":
			return premium_hint()
	if tab in GEAR_TABS:
		return gear_hint()
	return tr("Clique num item para provar.\nArmas melhores só caem nas instâncias ou vêm do leilão.")

func wings_hint() -> String:
	var how: String = tr("Pagamento pela carteira Steam.") if app.steam.available else tr("Pagamento por cartão ou Pix, em reais.")
	return tr("Asas são só aparência: não dão atributos nem poder. Clique numas asas para vê-las no personagem.") + "\n" + how

func gear_hint() -> String:
	return tr("Clique num item para provar.\nPeças Raras, Épicas e Lendárias só caem nas instâncias (quanto mais alto o mapa, melhores) ou vêm do leilão.")

func pet_hint() -> String:
	var how: String = tr("Pagamento pela carteira Steam.") if app.steam.available else tr("Pagamento por cartão ou Pix, em reais.")
	return tr("Mascotes são só aparência: não dão atributos nem poder. Clique num mascote para vê-lo ao lado do personagem.") + "\n" + how

func premium_hint() -> String:
	if app.steam.available:
		return tr("Só aparência e conveniência: não muda atributos e chega pelo Correio.\nO preço na sua moeda aparece na Steam.")
	return tr("Só aparência e conveniência: não muda atributos e chega pelo Correio.\nPagamento por cartão ou Pix, em reais.")

# The payment page again, from a click (a browser opens it only then).
func reopen_payment() -> void:
	app.open_checkout()
	message = tr("Página de pagamento aberta no navegador.")
	build()

func buy_premium(sku: String) -> void:
	message = tr("Aprove a compra na janela da Steam…") if app.steam.available else tr("Abrindo a página de pagamento…")
	build()
	message = await app.buy_premium(sku)
	if is_inside_tree():
		build()

func try_on_pet(species: String) -> void:
	trying_pet = species
	message = ""
	build()

func try_on(def: Dictionary) -> void:
	preview_color = ""
	message = ""
	trying = {"id": def.id, "quality": "super" if def.get("super", false) else "normal", "level": 0}
	build()

func buy_item(id: String, quality: String) -> void:
	var error: String = (await app.do_op("buy", [id, quality])).error
	message = error if error != "" else tr("Comprado! Veja na Mochila.")
	app.audio.play("ui_coin" if error == "" else "ui_error")
	build()

func select_tab(value: String) -> void:
	tab = value
	trying_pet = "" if value != "pet" else trying_pet
	page = 0
	message = ""
	build()

func turn_page(step: int) -> void:
	page += step
	message = ""
	build()

func close() -> void:
	closed.emit()
	queue_free()
