class_name PetScreen
extends Control

# Casa dos Mascotes (0.19), in the layout of the Forja Celeste: four tabs (the Caçada, 0.20,
# is HuntTab). "Chocar" opens
# the eggs (chances, guarantees and a cinematic reveal), "Mascotes" is the collection with
# level, stars, the active pet and its bonuses, and "Álbum" lists every species with a
# permanent bonus for each completed element. Offline the profile applies the operations,
# online the game server does (`app.do_op`).

signal closed

const TABS: Array[String] = ["Chocar", "Mascotes", "Álbum", "Caçada"]  # i18n
const PER_PAGE: int = 25

var app: Node
var tab: String = "Chocar"
var egg_id: String = ""
var pet_uid: int = -1
var page: int = 0
var contents: Control
var stage: PetStage
var hunt_tab: HuntTab
var busy: bool = false
var message: String = ""

static func open(host: Node, game: Node, first_tab: String = "Chocar", first_egg: String = "") -> PetScreen:
	var screen: PetScreen = PetScreen.new()
	screen.app = game
	screen.tab = first_tab
	screen.egg_id = first_egg
	host.add_child(screen)
	return screen

func _ready() -> void:
	size = Vector2(1280, 720)
	if not Pets.is_egg(egg_id):
		egg_id = first_egg_owned()
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

func first_egg_owned() -> String:
	for def: Dictionary in Pets.eggs():
		if app.profile.egg_count(str(def.id)) > 0:
			return str(def.id)
	return str(Pets.eggs()[0].id)

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
	PremiumUi.window(contents, Rect2(24, 16, 1232, 688), tr("CASA DOS MASCOTES"), tr("MASCOTES  /  Do ovo ao companheiro lendário"))
	var close_button: Button = UiKit.button(contents, tr("FECHAR"), Rect2(1110, 38, 120, 40), close)
	close_button.name = "PetClose"
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(860, 39, 30, 30))
	UiKit.label(contents, str(app.profile.coins), Rect2(900, 35, 190, 38), 24, HudPaint.GOLD)
	for i in range(TABS.size()):
		var tab_button: Button = UiKit.button(contents, tr(TABS[i]), Rect2(44 + i * 194, 98, 184, 38), select_tab.bind(TABS[i]), "tab_active" if tab == TABS[i] else "tab", 18)
		tab_button.name = "PetTab_" + TABS[i]
		tab_button.set_meta("active", tab == TABS[i])
	stage = null
	hunt_tab.visible = tab == "Caçada"
	match tab:
		"Chocar":
			build_hatch()
		"Mascotes":
			build_pets()
		"Caçada":
			if rebuild_hunt:
				hunt_tab.adopt()
				hunt_tab.rebuild()
		_:
			build_album()
	if message != "":
		var note: Label = UiKit.label(contents, message, Rect2(620, 99, 604, 36), 16, HudPaint.GOLD_HOT, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
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

# ---------- Chocar ----------

func build_hatch() -> void:
	panel(Rect2(40, 148, 282, 394))
	panel(Rect2(930, 148, 310, 394))
	panel(Rect2(40, 556, 1200, 130))
	UiKit.label(contents, tr("SEUS OVOS"), Rect2(56, 157, 246, 28), 20, HudPaint.GOLD)
	var eggs: Array = Pets.eggs()
	for i in range(eggs.size()):
		var def: Dictionary = eggs[i]
		var id: String = str(def.id)
		var count: int = app.profile.egg_count(id)
		var tint: Color = Pets.element_color(str(def.element)) if str(def.element) != "" else HudPaint.GOLD
		var card: Button = UiKit.button(contents, "", Rect2(52 + (i % 2) * 134, 196 + (i / 2 as int) * 112, 128, 106), pick_egg.bind(id), "card_hover" if id == egg_id else "slot")
		card.name = "Egg_" + id
		card.tooltip_text = Pets.egg_name(id)
		if count > 0:
			card.add_child(BagSlot.glow_node(Rect2(4, 4, 120, 98), tint))
		var picture: TextureRect = PetWidgets.egg_art(card, id, Rect2(32, 4, 64, 64))
		picture.modulate.a = 1.0 if count > 0 else 0.35
		UiKit.clipped(card, Pets.egg_name(id), Rect2(0, 68, 128, 20), 14, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(card, "x%d" % count, Rect2(0, 86, 128, 20), 15, UiKit.GOOD if count > 0 else PremiumUi.DISABLED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var def: Dictionary = Pets.egg_def(egg_id)
	var element: String = str(def.element)
	var tint: Color = Pets.element_color(element) if element != "" else HudPaint.GOLD
	stage = PetStage.new()
	stage.position = Vector2(336, 148)
	stage.size = Vector2(580, 394)
	stage.show_picture(PetWidgets.egg_texture(egg_id), tint, true)
	stage.caption = Pets.egg_name(egg_id)
	stage.sub_caption = tr("%d em estoque") % app.profile.egg_count(egg_id)
	contents.add_child(stage)
	# Right: chances, guarantees and what can hatch.
	UiKit.label(contents, tr("CHANCES"), Rect2(946, 157, 278, 28), 20, HudPaint.GOLD)
	var odds: Array = Pets.odds(egg_id)
	var total: float = 0.0
	for value in odds:
		total += float(value)
	for i in range(odds.size()):
		var id: String = str(Pets.rarities()[i].id)
		var fraction: float = float(odds[i]) / total
		var y: float = 192 + i * 30
		UiKit.label(contents, Pets.rarity_label(id), Rect2(946, y, 100, 26), 16, Pets.rarity_color(id))
		var gauge: Control = Control.new()
		gauge.position = Vector2(1040, y + 3)
		var hue: Color = Pets.rarity_color(id)
		gauge.draw.connect(func() -> void: HudPaint.gauge(gauge, Rect2(0, 0, 130, 16), fraction, hue.lightened(0.2), hue.darkened(0.35)))
		contents.add_child(gauge)
		UiKit.label(contents, "%d%%" % roundi(fraction * 100.0), Rect2(1176, y, 48, 26), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.label(contents, tr("GARANTIAS"), Rect2(946, 318, 278, 26), 18, HudPaint.GOLD)
	for i in range(2):
		var key: String = ["epico", "lendario"][i]
		var left: int = Pets.pity_left(app.profile.pity, key)
		var text: String = tr("%s: garantido no próximo ovo") % Pets.rarity_label(key) if left <= 1 else tr("%s: garantido em %d ovos") % [Pets.rarity_label(key), left]
		var line: Label = UiKit.label(contents, text, Rect2(946, 346 + i * 24, 280, 24), 15, Pets.rarity_color(key).lightened(0.2))
		line.tooltip_text = tr("A cada ovo sem esta raridade, a garantia chega mais perto.")
	UiKit.label(contents, tr("PODE NASCER"), Rect2(946, 398, 278, 24), 18, HudPaint.GOLD)
	if element == "":
		UiKit.label(contents, tr("Qualquer elemento"), Rect2(946, 426, 278, 22), 16, HudPaint.CREAM)
		for i in range(Pets.elements().size()):
			var entry: Dictionary = Pets.elements()[i]
			var icon: TextureRect = UiKit.art(contents, str(entry.icon), Rect2(948 + i * 54, 452, 46, 46))
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.tooltip_text = Pets.element_name(str(entry.id))
	else:
		var list: Array[Dictionary] = Pets.species_of_element(element)
		for i in range(list.size()):
			var found: bool = app.profile.pet_album.has(list[i].id)
			var box: Control = panel(Rect2(948 + i * 70, 430, 64, 64))
			box.mouse_filter = Control.MOUSE_FILTER_PASS
			box.tooltip_text = Pets.species_name(str(list[i].id)) + "  (" + Pets.rarity_label(str(list[i].rarity)) + ")" if found else Pets.rarity_label(str(list[i].rarity)) + "  ???"
			if found:
				box.add_child(BagSlot.glow_node(Rect2(2, 2, 60, 60), Pets.rarity_color(str(list[i].rarity))))
			PetWidgets.art(box, str(list[i].id), Rect2(2, 2, 60, 60), found)
	var count: int = app.profile.egg_count(egg_id)
	var button: Button = UiKit.button(contents, tr("CHOCAR OVO"), Rect2(948, 498, 274, 36), do_hatch, "button_green", 22)
	button.name = "HatchButton"
	button.set_meta("active", true)
	button.disabled = count <= 0 or busy
	button.tooltip_text = tr("Ovos caem das instâncias: chefes, elites e guardiões, e nos baús de recompensa.") if count <= 0 else tr("Abre um ovo e revela o mascote.")
	# Bottom: the album by element.
	UiKit.label(contents, tr("ÁLBUM DE ELEMENTOS"), Rect2(56, 562, 420, 24), 16, HudPaint.GOLD)
	UiKit.label(contents, tr("Complete os 4 mascotes de um elemento para um bônus permanente"), Rect2(480, 562, 740, 24), 16, Color("afbed1"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in range(Pets.elements().size()):
		element_box(Rect2(54 + i * 238, 594, 230, 82), Pets.elements()[i])

func element_box(rect: Rect2, entry: Dictionary) -> void:
	var box: Control = panel(rect)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var id: String = str(entry.id)
	var list: Array[Dictionary] = Pets.species_of_element(id)
	var found: int = 0
	for species: Dictionary in list:
		if app.profile.pet_album.has(species.id):
			found += 1
	var complete: bool = found == list.size()
	var tint: Color = Pets.element_color(id)
	if complete:
		box.add_child(BagSlot.glow_node(Rect2(4, 4, rect.size.x - 8, rect.size.y - 8), tint))
	var icon: TextureRect = UiKit.art(box, str(entry.icon), Rect2(8, 14, 52, 52))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UiKit.label(box, Pets.element_name(id), Rect2(68, 6, 156, 24), 18, tint.lightened(0.25))
	UiKit.label(box, "%d / %d" % [found, list.size()], Rect2(68, 30, 156, 22), 16, HudPaint.CREAM)
	var bonus: String = ", ".join(bonus_lines(entry.album))
	var line: Label = UiKit.clipped(box, bonus, Rect2(68, 54, 156, 22), 15, UiKit.GOOD if complete else Color("7d8ca1"))
	line.tooltip_text = (tr("Bônus ativo: %s") if complete else tr("Ao completar: %s")) % bonus

# "+24 Ataque", "+150 de vida máxima" for an album bonus.
func bonus_lines(bonus: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key: String in bonus:
		if Armory.ATTRS.has(key):
			lines.append("+%d %s" % [int(bonus[key]), Armory.attr_name(key)])
		else:
			lines.append(Pets.talent_text(key, int(bonus[key])))
	return lines

func pick_egg(id: String) -> void:
	egg_id = id
	message = ""
	build()

func do_hatch() -> void:
	if busy or app.profile.egg_count(egg_id) <= 0:
		return
	busy = true
	var chosen_egg: String = egg_id
	var first_uid: int = app.profile.next_uid
	var album_before: Array[String] = app.profile.pet_album.duplicate()
	var blocker: Control = Control.new()
	blocker.size = size
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	var error: String = (await app.do_op("pet_hatch", [chosen_egg])).error
	if not is_inside_tree():
		return
	blocker.queue_free()
	if error != "":
		busy = false
		report(error, "")
		return
	var born: Dictionary = {}
	for pet: Dictionary in app.profile.pets:
		if int(pet.uid) >= first_uid:
			born = pet
	if born.is_empty():
		busy = false
		build()
		return
	var moment: HatchOutcome = HatchOutcome.new()
	moment.egg_id = chosen_egg
	moment.pet = born.duplicate(true)
	moment.is_new = not album_before.has(str(born.species))
	moment.audio = app.audio
	add_child(moment)
	await moment.completed
	busy = false
	pet_uid = int(born.uid)
	message = tr("Nasceu %s!") % Pets.species_name(str(born.species))
	build()

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
		var hint: Label = note(tr("Ovos caem das instâncias. Abra-os na aba Chocar para ganhar um companheiro de batalha."), Rect2(660, 322, 504, 70), 18, Color("afbed1"))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiKit.button(contents, tr("IR CHOCAR"), Rect2(850, 420, 200, 42), select_tab.bind("Chocar"), "button_green", 20)
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
	if int(pet.stars) > 0:
		PetWidgets.stars(slot, Vector2(6, 62), int(pet.stars), int(pet.stars), 5.0)
	if uid == int(app.profile.pet_active):
		UiKit.label(slot, "E", Rect2(76, 58, 16, 20), 13, Color("9aff7a"), UiKit.INK)

func build_detail(pet: Dictionary) -> void:
	var uid: int = int(pet.uid)
	var species: String = str(pet.species)
	var def: Dictionary = Pets.species_def(species)
	var rarity: String = str(def.rarity)
	var color: Color = Pets.rarity_color(rarity)
	var stars: int = int(pet.stars)
	var cap: int = Pets.cap(stars)
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
	var star_box: Control = PetWidgets.stars(contents, Vector2(906, 278), stars, int(Pets.data().max_stars), 11.0)
	star_box.name = "PetStars"
	star_box.tooltip_text = tr("Cada estrela aumenta os bônus e o nível máximo do mascote.")
	var spare: Array[Dictionary] = duplicates_of(pet)
	UiKit.label(contents, tr("Duplicatas: %d") % spare.size(), Rect2(1056, 278, 156, 24), 15, UiKit.GOOD if not spare.is_empty() else Color("7d8ca1"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.label(contents, tr("PODER"), Rect2(906, 312, 306, 24), 17, HudPaint.GOLD)
	var lines: Array[String] = Pets.describe(pet)
	for i in range(mini(lines.size(), 6)):
		var is_attr: bool = i < Pets.attrs(pet).size()
		UiKit.label(contents, lines[i], Rect2(906, 338 + i * 20, 306, 22), 15, HudPaint.CREAM if is_attr else Color("9ae8ff"))
	note(tr(str(def.desc)), Rect2(606, 468, 280, 60), 16, Color("c8d4e4"))
	# 0.22: the skill it lends its owner in battle (one use per battle, key G).
	var battle_skill: Dictionary = Pets.skill_entry(pet)
	if not battle_skill.is_empty():
		UiKit.label(contents, tr("HABILIDADE EM BATALHA (G)"), Rect2(606, 528, 280, 22), 15, HudPaint.GOLD)
		var skill_def: Dictionary = Pets.skill_def(str(battle_skill.element))
		note("%s: %s" % [tr(str(skill_def.name)), Pets.skill_text(battle_skill)], Rect2(606, 552, 280, 70), 14, Color(str(skill_def.color)).lightened(0.3))
	UiKit.label(contents, tr("COMO EVOLUIR"), Rect2(906, 462, 306, 24), 17, HudPaint.GOLD)
	note(tr("Alimentar: +%d XP por %d moedas.") % [int(Pets.data().xp.feed_xp), int(Pets.data().xp.feed_coins)], Rect2(906, 488, 306, 40), 15, HudPaint.CREAM)
	if stars < int(Pets.data().max_stars):
		note(tr("Estrela: 1 duplicata + %d moedas. O nível máximo sobe para %d.") % [int(Pets.data().evolve_coins[stars]), Pets.cap(stars + 1)], Rect2(906, 532, 306, 60), 15, HudPaint.CREAM)
	else:
		UiKit.label(contents, tr("Estrelas no máximo."), Rect2(906, 532, 306, 24), 15, HudPaint.GOLD)
	var equip: Button = UiKit.button(contents, tr("DESATIVAR") if active else tr("ATIVAR"), Rect2(604, 632, 140, 38), do_equip, "button_blue", 18)
	equip.name = "PetEquip"
	var feed: Button = UiKit.button(contents, tr("ALIMENTAR"), Rect2(752, 632, 150, 38), do_feed, "button_green", 18)
	feed.name = "PetFeed"
	feed.disabled = capped or app.profile.coins < int(Pets.data().xp.feed_coins)
	feed.tooltip_text = tr("Nível máximo para %d estrelas. Evolua o mascote para subir mais.") % stars if capped else tr("Gasta moedas e dá experiência ao mascote.")
	var evolve: Button = UiKit.button(contents, tr("GANHAR ESTRELA"), Rect2(910, 632, 150, 38), do_evolve.bind(spare), "button_green", 16)
	evolve.name = "PetEvolve"
	evolve.set_meta("active", true)
	var price: int = int(Pets.data().evolve_coins[stars]) if stars < int(Pets.data().max_stars) else 0
	evolve.disabled = stars >= int(Pets.data().max_stars) or spare.is_empty() or app.profile.coins < price
	evolve.tooltip_text = tr("Consome uma duplicata da mesma espécie. A metade da experiência dela passa para este mascote.")
	var release: Button = UiKit.button(contents, tr("LIBERTAR"), Rect2(1068, 632, 144, 38), do_release, "button_red", 18)
	release.name = "PetRelease"
	release.disabled = active
	release.tooltip_text = tr("Tire o mascote ativo antes de libertá-lo.") if active else tr("Liberta o mascote e devolve %d moedas.") % int(Pets.rarity_def(rarity).release)

# Other pets of the same species that can be consumed (never the active one).
func duplicates_of(pet: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for other: Dictionary in app.profile.pets:
		if int(other.uid) != int(pet.uid) and other.species == pet.species and int(other.uid) != int(app.profile.pet_active):
			list.append(other)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Pets.total_xp(a) < Pets.total_xp(b))
	return list

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

func do_feed() -> void:
	var before: int = int(app.profile.find_pet(pet_uid).get("level", 1))
	var error: String = (await app.do_op("pet_feed", [pet_uid])).error
	var after: int = int(app.profile.find_pet(pet_uid).get("level", 1))
	if error == "" and after > before:
		app.audio.play("pet_levelup")
		report("", tr("Subiu para o nível %d!") % after)
	else:
		report(error, tr("+%d XP") % int(Pets.data().xp.feed_xp))

func do_evolve(spare: Array[Dictionary]) -> void:
	if spare.is_empty():
		return
	var error: String = (await app.do_op("pet_evolve", [pet_uid, int(spare[0].uid)])).error
	if error == "":
		app.audio.play("pet_levelup")
	report(error, tr("Nova estrela! Os bônus do mascote aumentaram."))

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
	var all_bonus: String = ", ".join(bonus_lines(Pets.data().album_all))
	var done: bool = app.profile.pet_album.size() >= total
	UiKit.label(contents, (tr("Álbum completo: %s") if done else tr("Todos os elementos completos: %s")) % all_bonus, Rect2(72, 654, 1136, 22), 16, UiKit.GOOD if done else Color("afbed1"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

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
		var best: int = 0
		for pet: Dictionary in app.profile.pets:
			if pet.species == id:
				best = maxi(best, int(pet.stars))
		PetWidgets.stars(card, Vector2(84, 62), best, int(Pets.data().max_stars), 7.0)
		var sample: Dictionary = {"species": id, "level": int(Pets.data().max_level), "stars": 0, "xp": 0, "uid": 0}
		card.tooltip_text = "%s\n%s\n\n%s\n%s" % [Pets.species_name(id), tr(str(def.desc)), tr("No nível máximo, sem estrelas:"), "\n".join(Pets.describe(sample))]
	else:
		card.tooltip_text = tr("Ainda não encontrado. Choque ovos do elemento %s.") % Pets.element_name(str(def.element))

# ---------- shared ----------

func select_tab(value: String) -> void:
	tab = value
	page = 0
	message = ""
	build()

func report(error: String, success: String) -> void:
	message = error if error != "" else success
	app.audio.play("ui_error" if error != "" else "ui_confirm")
	build()

func close() -> void:
	if busy:
		return
	closed.emit()
	queue_free()
