class_name PetScreen
extends Control

# Casa dos Mascotes, in the layout of the Forja Celeste. Since 0.30 the pets are collectibles
# sold in the shop: "Mascotes" is the collection (the companion that follows the character in
# battle, release), "Álbum" lists every species and the Caçada (HuntTab) is where a pet gains
# levels. Offline the profile applies the operations, online the game server does
# (`app.do_op`).

signal closed

const TABS: Array[String] = ["Mascotes", "Álbum", "Caçada"]  # i18n
const PER_PAGE: int = 25

var app: Node
var tab: String = "Mascotes"
var pet_uid: int = -1
var page: int = 0
var contents: Control
var stage: PetStage
var hunt_tab: HuntTab
var message: String = ""

static func open(host: Node, game: Node, first_tab: String = "Mascotes") -> PetScreen:
	var screen: PetScreen = PetScreen.new()
	screen.app = game
	screen.tab = first_tab
	host.add_child(screen)
	return screen

func _ready() -> void:
	size = Vector2(1280, 720)
	var chosen: Dictionary = app.profile.find_pet(pet_uid)
	if chosen.is_empty():
		var list: Array[Dictionary] = sorted_pets()
		chosen = app.profile.active_pet() if not app.profile.active_pet().is_empty() else (list[0] if not list.is_empty() else {})
	pet_uid = int(chosen.get("uid", -1))
	hunt_tab = HuntTab.new()
	add_child(hunt_tab)
	hunt_tab.setup(app)
	hunt_tab.changed.connect(build.bind(false))
	build()

func sorted_pets() -> Array[Dictionary]:
	var list: Array[Dictionary] = app.profile.pets.duplicate()
	list.sort_custom(PetWidgets.pet_before)
	return list

func build(rebuild_hunt: bool = true) -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
	contents = Control.new()
	contents.size = size
	add_child(contents)
	move_child(contents, 0)
	PremiumUi.window(contents, Rect2(24, 16, 1232, 688), tr("CASA DOS MASCOTES"), tr("MASCOTES  /  Coleção e Caçada"))
	var close_button: Button = UiKit.button(contents, tr("FECHAR"), Rect2(1110, 38, 120, 40), close)
	close_button.name = "PetClose"
	var shop_button: Button = UiKit.button(contents, tr("LOJA DE MASCOTES"), Rect2(1000, 98, 230, 38), open_shop, "button_blue", 16)
	shop_button.name = "PetShop"
	shop_button.tooltip_text = tr("Todos os mascotes estão à venda na aba Mascotes da Loja.")
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(860, 39, 30, 30))
	UiKit.label(contents, str(app.profile.coins), Rect2(900, 35, 190, 38), 24, HudPaint.GOLD)
	for i in range(TABS.size()):
		var tab_button: Button = UiKit.button(contents, tr(TABS[i]), Rect2(44 + i * 194, 98, 184, 38), select_tab.bind(TABS[i]), "tab_active" if tab == TABS[i] else "tab", 18)
		tab_button.name = "PetTab_" + TABS[i]
		tab_button.set_meta("active", tab == TABS[i])
	stage = null
	hunt_tab.visible = tab == "Caçada"
	match tab:
		"Mascotes":
			build_pets()
		"Caçada":
			if rebuild_hunt:
				hunt_tab.adopt()
				hunt_tab.rebuild()
		_:
			build_album()
	if message != "":
		var note: Label = UiKit.label(contents, message, Rect2(640, 99, 350, 36), 16, HudPaint.GOLD_HOT, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		note.name = "PetMessage"
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		note.tooltip_text = message
	PremiumUi.skin(contents)

func panel(rect: Rect2) -> Control:
	return PremiumUi.panel(contents, rect)

# A paragraph that wraps inside its box and starts at the top.
func note(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var node: Label = UiKit.label(contents, text, rect, font_size, color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return UiKit.wrap(node, rect.size)

# ---------- Mascotes ----------

func build_pets() -> void:
	panel(Rect2(56, 146, 520, 534))
	panel(Rect2(588, 146, 636, 534))
	var list: Array[Dictionary] = sorted_pets()
	UiKit.label(contents, tr("SEUS MASCOTES"), Rect2(72, 156, 300, 28), 20, HudPaint.GOLD)
	UiKit.label(contents, "%d / %d" % [list.size(), int(Pets.data().max_pets)], Rect2(400, 158, 160, 26), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	var pages: int = maxi(1, ceili(list.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = page * PER_PAGE + i
		if index >= list.size():
			break
		pet_slot(list[index], Rect2(70 + (i % 5) * 100, 192 + (i / 5 as int) * 84, 94, 78))
	var back: Button = UiKit.button(contents, "<", Rect2(380, 636, 40, 32), turn_page.bind(-1))
	back.disabled = page == 0
	UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(420, 636, 80, 32), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var forward: Button = UiKit.button(contents, ">", Rect2(500, 636, 40, 32), turn_page.bind(1))
	forward.disabled = page == pages - 1
	var pet: Dictionary = app.profile.find_pet(pet_uid)
	if pet.is_empty():
		UiKit.label(contents, tr("Você ainda não tem mascotes."), Rect2(604, 270, 604, 40), 24, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var hint: Label = note(tr("Os mascotes são vendidos na Loja. Comuns e Raros também podem cair de chefes e ser capturados na Caçada."), Rect2(660, 322, 504, 90), 18, Color("afbed1"))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiKit.button(contents, tr("IR À LOJA"), Rect2(850, 430, 200, 42), open_shop, "button_green", 20)
		return
	build_detail(pet)

func pet_slot(pet: Dictionary, rect: Rect2) -> void:
	var uid: int = int(pet.uid)
	var def: Dictionary = Pets.species_def(str(pet.species))
	var slot: Button = UiKit.button(contents, "", rect, pick_pet.bind(uid), "card_hover" if uid == pet_uid else "slot")
	slot.name = "Pet_%d" % uid
	slot.tooltip_text = "%s  (%s)" % [Pets.species_name(str(pet.species)), Pets.rarity_label(str(def.rarity))]
	slot.add_child(BagSlot.glow_node(Rect2(4, 3, rect.size.x - 8, rect.size.y - 6), Pets.rarity_color(str(def.rarity))))
	PetWidgets.art(slot, str(pet.species), Rect2(12, 0, 70, 70))
	UiKit.label(slot, tr("Nv %d") % int(pet.level), Rect2(4, 0, 60, 20), 14, HudPaint.CREAM, UiKit.INK)
	if uid == int(app.profile.pet_active):
		UiKit.label(slot, "E", Rect2(76, 58, 16, 20), 13, Color("9aff7a"), UiKit.INK)

func build_detail(pet: Dictionary) -> void:
	var uid: int = int(pet.uid)
	var species: String = str(pet.species)
	var def: Dictionary = Pets.species_def(species)
	var rarity: String = str(def.rarity)
	var color: Color = Pets.rarity_color(rarity)
	var cap: int = Pets.cap()
	var active: bool = uid == int(app.profile.pet_active)
	stage = PetStage.new()
	stage.position = Vector2(602, 158)
	stage.size = Vector2(290, 300)
	stage.show_picture(PetWidgets.species_texture(species), Pets.element_color(str(def.element)), false, color)
	stage.sub_caption = tr("MASCOTE ATIVO") if active else ""
	contents.add_child(stage)
	var name_label: Label = UiKit.clipped(contents, Pets.species_name(species), Rect2(906, 160, 306, 32), 24, color.lightened(0.15))
	name_label.name = "PetName"
	UiKit.label(contents, "%s  •  %s" % [Pets.rarity_label(rarity), Pets.element_name(str(def.element))], Rect2(906, 194, 306, 24), 16, HudPaint.CREAM)
	UiKit.label(contents, tr("Nível %d / %d") % [int(pet.level), cap], Rect2(906, 224, 190, 24), 18, HudPaint.CREAM)
	var need: int = Pets.xp_needed(int(pet.level))
	var capped: bool = int(pet.level) >= cap
	UiKit.label(contents, tr("máximo") if capped else "%d / %d XP" % [int(pet.xp), need], Rect2(1060, 227, 152, 22), 14, Color("afbed1"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	var gauge: Control = Control.new()
	gauge.position = Vector2(906, 252)
	var fraction: float = 1.0 if capped else float(pet.xp) / float(need)
	gauge.draw.connect(func() -> void: HudPaint.gauge(gauge, Rect2(0, 0, 306, 16), fraction, Color("9fe6b5"), Color("2d8a5a")))
	contents.add_child(gauge)
	UiKit.label(contents, tr("SÓ APARÊNCIA"), Rect2(906, 290, 306, 24), 17, HudPaint.GOLD)
	note(tr("Mascotes não dão atributos nem poder em batalha: ele só acompanha o seu personagem."), Rect2(906, 316, 306, 64), 15, HudPaint.CREAM)
	note(tr(str(def.desc)), Rect2(606, 468, 280, 60), 16, Color("c8d4e4"))
	UiKit.label(contents, tr("COMO SUBIR DE NÍVEL"), Rect2(906, 396, 306, 24), 17, HudPaint.GOLD)
	note(tr("Só na Caçada: coloque o mascote no time e colete a experiência que ele ganhar."), Rect2(906, 422, 306, 64), 15, HudPaint.CREAM)
	UiKit.button(contents, tr("IR PARA A CAÇADA"), Rect2(906, 494, 306, 38), select_tab.bind("Caçada"), "button_green", 16)
	var equip: Button = UiKit.button(contents, tr("DESATIVAR") if active else tr("ATIVAR"), Rect2(604, 632, 140, 38), do_equip, "button_blue", 18)
	equip.name = "PetEquip"
	var release: Button = UiKit.button(contents, tr("LIBERTAR"), Rect2(752, 632, 144, 38), do_release, "button_red", 18)
	release.name = "PetRelease"
	release.disabled = active
	release.tooltip_text = tr("Tire o mascote ativo antes de libertá-lo.") if active else tr("Liberta o mascote e devolve %d moedas.") % int(Pets.rarity_def(rarity).release)

func pick_pet(uid: int) -> void:
	pet_uid = uid
	message = ""
	build()

func turn_page(step: int) -> void:
	page += step
	build()

func do_equip() -> void:
	var was_active: bool = pet_uid == int(app.profile.pet_active)
	var error: String = (await app.do_op("pet_equip", [pet_uid])).error
	report(error, tr("Mascote guardado.") if was_active else tr("%s agora acompanha você nas batalhas.") % Pets.species_name(str(app.profile.find_pet(pet_uid).get("species", ""))))

func do_release() -> void:
	var pet: Dictionary = app.profile.find_pet(pet_uid)
	if pet.is_empty():
		return
	var dialog: Control = UiKit.modal(self, tr("LIBERTAR MASCOTE"), tr("Libertar %s? Ele vai embora para sempre e você recebe moedas.") % Pets.species_name(str(pet.species)))
	var rect: Rect2 = dialog.get_meta("rect")
	UiKit.button(dialog, tr("LIBERTAR"), Rect2(rect.position.x + 90, rect.end.y - 60, 150, 42), func() -> void:
		dialog.queue_free()
		confirm_release(), "button_red")
	UiKit.button(dialog, tr("FICAR"), Rect2(rect.end.x - 240, rect.end.y - 60, 150, 42), dialog.queue_free)

func confirm_release() -> void:
	var gone: String = str(app.profile.find_pet(pet_uid).get("species", ""))
	var error: String = (await app.do_op("pet_release", [pet_uid])).error
	if error == "":
		pet_uid = -1
		var list: Array[Dictionary] = sorted_pets()
		pet_uid = int(list[0].uid) if not list.is_empty() else -1
	report(error, tr("%s foi libertado.") % Pets.species_name(gone))

# ---------- Álbum ----------

func build_album() -> void:
	panel(Rect2(56, 146, 1168, 534))
	var total: int = Pets.species_list().size()
	UiKit.label(contents, tr("ÁLBUM DE MASCOTES"), Rect2(72, 154, 420, 28), 20, HudPaint.GOLD)
	UiKit.label(contents, tr("%d de %d espécies encontradas") % [app.profile.pet_album.size(), total], Rect2(500, 156, 708, 26), 17, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	for column in range(Pets.elements().size()):
		var entry: Dictionary = Pets.elements()[column]
		var x: float = 68 + column * 230
		element_box(Rect2(x, 190, 222, 82), entry)
		var list: Array[Dictionary] = Pets.species_of_element(str(entry.id))
		for row in range(list.size()):
			species_card(Rect2(x, 280 + row * 94, 222, 88), list[row])
	UiKit.label(contents, tr("Todos os mascotes estão à venda na Loja. Comuns e Raros também aparecem na Caçada."), Rect2(72, 654, 1136, 22), 16, Color("afbed1"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

# One element: its icon, the name and how many of its species the player has found.
func element_box(rect: Rect2, entry: Dictionary) -> void:
	var box: Control = panel(rect)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var id: String = str(entry.id)
	var list: Array[Dictionary] = Pets.species_of_element(id)
	var found: int = 0
	for species: Dictionary in list:
		if app.profile.pet_album.has(species.id):
			found += 1
	var tint: Color = Pets.element_color(id)
	if found == list.size():
		box.add_child(BagSlot.glow_node(Rect2(4, 4, rect.size.x - 8, rect.size.y - 8), tint))
	var icon: TextureRect = UiKit.art(box, str(entry.icon), Rect2(8, 14, 52, 52))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UiKit.label(box, Pets.element_name(id), Rect2(68, 12, 156, 24), 18, tint.lightened(0.25))
	UiKit.label(box, "%d / %d" % [found, list.size()], Rect2(68, 42, 156, 22), 16, HudPaint.CREAM)

func species_card(rect: Rect2, def: Dictionary) -> void:
	var id: String = str(def.id)
	var found: bool = app.profile.pet_album.has(id)
	var card: Control = panel(rect)
	card.name = "Album_" + id
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var color: Color = Pets.rarity_color(str(def.rarity))
	if found:
		card.add_child(BagSlot.glow_node(Rect2(4, 6, 76, 76), color))
	PetWidgets.art(card, id, Rect2(4, 6, 76, 76), found)
	UiKit.clipped(card, Pets.species_name(id) if found else "???", Rect2(82, 10, 138, 24), 15, color.lightened(0.2) if found else PremiumUi.DISABLED)
	UiKit.label(card, Pets.rarity_label(str(def.rarity)), Rect2(82, 36, 138, 22), 15, color if found else PremiumUi.DISABLED)
	if found:
		card.tooltip_text = "%s\n%s" % [Pets.species_name(id), tr(str(def.desc))]
	else:
		card.tooltip_text = tr("Ainda não encontrado. Está à venda na Loja, aba Mascotes.")

# ---------- shared ----------

func select_tab(value: String) -> void:
	tab = value
	page = 0
	message = ""
	build()

func open_shop() -> void:
	app.open_pet_shop()

func report(error: String, success: String) -> void:
	message = error if error != "" else success
	app.audio.play("ui_error" if error != "" else "ui_confirm")
	build()

func close() -> void:
	closed.emit()
	queue_free()
