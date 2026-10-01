class_name SmithScreen
extends Control

# Celestial forge: one matching stone per attempt, authoritative rolls and a cinematic result.

signal closed

const TABS: Array[String] = ["Fortalecer", "Transferência", "Moedas"]  # i18n
const CRAFT_PER_PAGE: int = 36

var app: Node
var tab: String = "Fortalecer"
var selected_uid: int = -1
var target_uid: int = -1
var craft_target: String = "item"
var map_uid: int = -1
var page: int = 0
var contents: Control
var busy: bool = false
var forge_page: int = 0
var message: String = ""
# 0.15: the Mochila's item card over the lists.
var card: ItemTooltip

func _ready() -> void:
	size = Vector2(1280, 720)
	if selected_uid < 0 or not Armory.can_strengthen(str(app.profile.find_instance(selected_uid).get("id", ""))):
		selected_uid = int(app.profile.equipped.get("arma", -1))
	build()

func build() -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
	contents = Control.new()
	contents.size = size
	add_child(contents)
	move_child(contents, 0)
	PremiumUi.window(contents, Rect2(24, 16, 1232, 688), tr("FORJA CELESTE"), tr("FERREIRO  /  O poder toma forma"))
	UiKit.button(contents, tr("FECHAR"), Rect2(1110, 38, 120, 40), close)
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(860, 39, 30, 30))
	UiKit.label(contents, str(app.profile.coins), Rect2(900, 35, 190, 38), 24, HudPaint.GOLD)
	for i in range(TABS.size()):
		var tab_button: Button = UiKit.button(contents, tr(TABS[i]), Rect2(44 + i * 194, 98, 184, 38), select_tab.bind(TABS[i]), "tab_active" if tab == TABS[i] else "tab", 18)
		tab_button.set_meta("active", tab == TABS[i])
	if tab == "Fortalecer":
		build_strengthen()
	else:
		forge_panel(contents, Rect2(56, 146, 520, 534))
		forge_panel(contents, Rect2(588, 146, 636, 534))
		if tab == "Moedas":
			build_craft_list()
			build_craft()
		else:
			build_item_list()
			build_transfer()
	if message != "":
		var note: Label = UiKit.label(contents, message, Rect2(620, 99, 604, 36), 16, HudPaint.GOLD_HOT, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		note.tooltip_text = message
	skin_buttons(contents)
	card = ItemTooltip.new()
	contents.add_child(card)

func with_card(slot: Control, entry: Dictionary) -> void:
	slot.mouse_entered.connect(func() -> void:
		if is_instance_valid(card):
			card.show_entry(entry, app.profile, app.balance))
	slot.mouse_exited.connect(func() -> void:
		if is_instance_valid(card):
			card.hide_card())

func eligible() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for inst: Dictionary in app.profile.inventory:
		if Armory.can_strengthen(str(inst.id)):
			list.append(inst)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level) if a.level != b.level else str(a.id) < str(b.id))
	return list

func build_item_list() -> void:
	UiKit.label(contents, tr("Escolha o item") if tab != "Transferência" else tr("Escolha a origem e depois o destino"), Rect2(72, 156, 490, 30), 17, HudPaint.CREAM)
	var list: Array[Dictionary] = eligible()
	var pages: int = maxi(1, ceili(list.size() / 36.0))
	page = clampi(page, 0, pages - 1)
	for i in range(36):
		var index: int = page * 36 + i
		if index >= list.size():
			break
		var inst: Dictionary = list[index]
		var uid: int = int(inst.uid)
		var rect: Rect2 = Rect2(70 + (i % 6) * 82, 196 + (i / 6 as int) * 70, 76, 66)
		var kind: String = "card_hover" if uid == selected_uid else ("slot_light" if uid == target_uid else "slot")
		var slot: Button = UiKit.button(contents, "", rect, pick.bind(uid), kind)
		slot.name = "Smith_%d" % uid
		with_card(slot, {"key": "uid:%d" % uid, "inst": inst, "name": Armory.item_name(inst)})
		if str(inst.get("quality", "normal")) != "normal":
			slot.add_child(BagSlot.glow_node(Rect2(6, 3, 64, 60), Armory.quality_color(inst)))
		var picture: TextureRect = UiKit.art(slot, Armory.load_icon(inst), Rect2(12, 6, 52, 52))
		picture.modulate = Armory.icon_tint(inst)
		if int(inst.level) > 0:
			UiKit.label(slot, "+%d" % int(inst.level), Rect2(2, 0, 40, 20), 14, Armory.aura_color(int(inst.level)).lightened(0.3), UiKit.INK)
		if app.profile.is_equipped(uid):
			UiKit.label(slot, "E", Rect2(60, 46, 16, 20), 13, Color("9aff7a"), UiKit.INK)
	if list.is_empty():
		UiKit.label(contents, tr("Nenhum item disponível."), Rect2(72, 200, 490, 40), 18, HudPaint.CREAM)

	UiKit.button(contents, "<", Rect2(380, 632, 40, 32), turn_page.bind(-1)).disabled = page == 0
	UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(420, 632, 80, 32), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(500, 632, 40, 32), turn_page.bind(1)).disabled = page == pages - 1

func item_card(inst: Dictionary, rect: Rect2, level_shown: int) -> void:
	# Item with its aura ring behind, at a given strengthen level.
	var box: Control = forge_panel(contents, rect)
	box.clip_contents = true
	if level_shown > 0 and Armory.slot_of(str(inst.id)) == "arma":
		var ring: AuraRing = AuraRing.new()
		ring.position = rect.size / 2
		box.add_child(ring)
		ring.setup(Armory.aura_color(level_shown), level_shown, rect.size.x * 0.95)
	var shown: Dictionary = inst.duplicate()
	shown.level = level_shown
	var picture: TextureRect = UiKit.art(box, Armory.load_icon(shown), Rect2(rect.size * 0.18, rect.size * 0.64))
	picture.modulate = Armory.icon_tint(inst)
	UiKit.label(box, "+%d" % level_shown, Rect2(6, 2, 60, 28), 20, Armory.aura_color(level_shown).lightened(0.3) if level_shown > 0 else Color.WHITE, UiKit.INK)

func forge_panel(parent: Node, rect: Rect2) -> Control:
	return PremiumUi.panel(parent, rect)

func skin_buttons(parent: Node) -> void:
	PremiumUi.skin(parent)

func forge_turn_page(step: int) -> void:
	forge_page += step
	build()

func build_strengthen() -> void:
	forge_panel(contents, Rect2(40, 148, 282, 394))
	forge_panel(contents, Rect2(930, 148, 310, 394))
	forge_panel(contents, Rect2(40, 556, 1200, 130))
	UiKit.label(contents, tr("SEU ARSENAL"), Rect2(56, 157, 246, 28), 20, HudPaint.GOLD)
	var list: Array[Dictionary] = eligible()
	var pages: int = maxi(1, ceili(list.size() / 16.0))
	forge_page = clampi(forge_page, 0, pages - 1)
	for i in range(16):
		var index: int = forge_page * 16 + i
		if index >= list.size():
			break
		var entry: Dictionary = list[index]
		var chosen: bool = int(entry.uid) == selected_uid
		var slot: Button = UiKit.button(contents, "", Rect2(53 + i % 4 * 64, 198 + (i / 4 as int) * 67, 60, 62), pick.bind(int(entry.uid)))
		slot.name = "Smith_%d" % int(entry.uid)
		if chosen:
			slot.add_child(BagSlot.glow_node(Rect2(2, 2, 56, 58), HudPaint.GOLD))
		UiKit.art(slot, Armory.load_icon(entry), Rect2(5, 4, 50, 50)).modulate = Armory.icon_tint(entry)
		UiKit.label(slot, "+%d" % int(entry.level), Rect2(3, 40, 54, 20), 16, HudPaint.GOLD_HOT, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		with_card(slot, {"key": "uid:%d" % int(entry.uid), "inst": entry, "name": Armory.item_name(entry)})
	UiKit.button(contents, "<", Rect2(56, 478, 40, 38), forge_turn_page.bind(-1)).disabled = forge_page == 0
	UiKit.label(contents, "%d / %d" % [forge_page + 1, pages], Rect2(104, 478, 150, 38), 18, HudPaint.CREAM, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(266, 478, 40, 38), forge_turn_page.bind(1)).disabled = forge_page == pages - 1
	var inst: Dictionary = app.profile.find_instance(selected_uid)
	var stage: ForgeStage = ForgeStage.new()
	stage.position = Vector2(336, 148)
	stage.size = Vector2(580, 394)
	stage.item = inst
	contents.add_child(stage)
	if not inst.is_empty():
		UiKit.label(contents, Armory.item_name(inst, false), Rect2(354, 160, 544, 34), 26, Armory.quality_color(inst), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var level: int = int(inst.get("level", 0))
	var cost: Dictionary = app.profile.strengthen_cost(inst) if not inst.is_empty() else {}
	UiKit.label(contents, tr("PEDRAS DE FORTALECIMENTO"), Rect2(56, 562, 420, 24), 16, HudPaint.GOLD)
	UiKit.label(contents, tr("Instâncias mais difíceis revelam pedras mais raras"), Rect2(530, 562, 690, 24), 16, Color("afbed1"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in range(12):
		var stone: Dictionary = Armory.data().strengthen.stones[i]
		var count: int = int(app.profile.items.get(stone.id, 0))
		var box: Control = forge_panel(contents, Rect2(54 + i * 98, 594, 92, 80))
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.tooltip_text = tr(str(stone.name)) + "\n" + tr("Uma pedra: +%d → +%d. Encontrada nas instâncias.") % [i, i + 1] + "\n" + tr("Mapas de nível %d ou superior") % int(stone.min_instance_level)
		if not cost.is_empty() and i == level:
			box.add_child(BagSlot.glow_node(Rect2(4, 4, 84, 72), Color(str(stone.color))))
		var art: TextureRect = UiKit.art(box, str(stone.icon), Rect2(22, 3, 48, 48))
		art.modulate.a = 1.0 if count > 0 else 0.3
		UiKit.label(box, "%02d" % (i + 1), Rect2(6, 4, 26, 22), 14, Color(str(stone.color)))
		UiKit.label(box, "×%d" % count, Rect2(4, 51, 84, 24), 16, HudPaint.CREAM if count > 0 else Color("65758b"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	if cost.is_empty():
		UiKit.label(contents, tr("PODER MÁXIMO") if not inst.is_empty() else tr("SELECIONE UM ITEM"), Rect2(946, 228, 278, 42), 24, HudPaint.GOLD, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(contents, tr("Sua arma alcançou o +12.") if not inst.is_empty() else tr("Escolha no arsenal à esquerda."), Rect2(946, 280, 278, 60), 18, HudPaint.CREAM, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var stone: Dictionary = Armory.stone_def(str(cost.stone))
	var owned: int = int(app.profile.items.get(cost.stone, 0))
	UiKit.label(contents, tr("PRÓXIMO NÍVEL") + "  +%d" % int(cost.level), Rect2(946, 158, 278, 30), 22, HudPaint.GOLD)
	UiKit.art(contents, str(stone.icon), Rect2(948, 194, 68, 68))
	UiKit.label(contents, tr("Pedra nível %d") % int(cost.level), Rect2(1028, 196, 186, 26), 20, Color(str(stone.color)))
	UiKit.label(contents, tr("1 pedra  /  Estoque: %d") % owned, Rect2(1028, 223, 180, 38), 15, HudPaint.CREAM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.label(contents, tr("CHANCE DE SUCESSO"), Rect2(948, 266, 210, 22), 15, Color("afbed1"))
	UiKit.label(contents, "%d%%" % roundi(float(cost.chance) * 100), Rect2(1152, 258, 70, 36), 26, HudPaint.GOLD, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	var gauge: Control = Control.new()
	gauge.position = Vector2(948, 292)
	gauge.draw.connect(func() -> void: HudPaint.gauge(gauge, Rect2(0, 0, 274, 22), float(cost.chance), Color("ffda83"), Color("bf6628")))
	contents.add_child(gauge)
	UiKit.label(contents, tr("Se falhar, o nível é preservado."), Rect2(948, 315, 274, 24), 16, Color("afbed1"))
	var next: Dictionary = inst.duplicate(true)
	next.level = level + 1
	var stats: Array = []
	if Armory.slot_of(str(inst.id)) == "arma":
		stats.append([tr("Dano"), int(Armory.build_weapon(inst).damage), int(Armory.build_weapon(next).damage)])
	var now: Dictionary = Armory.item_attrs(inst)
	var after: Dictionary = Armory.item_attrs(next)
	for key: String in Armory.ATTRS:
		if int(now[key]) > 0:
			stats.append([Armory.attr_name(key), int(now[key]), int(after[key])])
	for i in range(mini(stats.size(), 5)):
		UiKit.label(contents, str(stats[i][0]), Rect2(948, 346 + i * 21, 110, 22), 16, HudPaint.CREAM)
		UiKit.label(contents, "%d → %d" % [stats[i][1], stats[i][2]], Rect2(1062, 346 + i * 21, 158, 22), 16, Color("9fe6b5"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.label(contents, tr("Custo: 1 pedra + %d moedas") % int(cost.coins), Rect2(948, 454, 274, 24), 16, HudPaint.GOLD)
	var button: Button = UiKit.button(contents, tr("FORTALECER") + "  +%d" % int(cost.level), Rect2(948, 486, 274, 42), do_strengthen, "button_green", 22)
	button.name = "StrengthenButton"
	button.set_meta("active", true)
	button.disabled = owned < 1 or app.profile.coins < int(cost.coins) or busy
	button.tooltip_text = tr("Você precisa de uma Pedra de Fortalecimento nível %d.") % int(cost.level) if owned < 1 else tr("Uma tentativa consome a pedra e as moedas.")

func build_transfer() -> void:
	var source: Dictionary = app.profile.find_instance(selected_uid)
	var target: Dictionary = app.profile.find_instance(target_uid)
	UiKit.label(contents, tr("TRANSFERÊNCIA"), Rect2(600, 158, 612, 32), 22, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var info: Label = UiKit.label(contents, tr("Troca o nível de fortalecimento entre dois itens do mesmo tipo — por exemplo, passe o +9 da sua arma Normal para a Verdadeira. Custa %d moedas.") % int(Armory.data().strengthen.transfer_coins), Rect2(620, 196, 572, 58), 15, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.wrap(info, Vector2(572, 58))
	UiKit.label(contents, tr("Origem"), Rect2(650, 264, 190, 28), 18, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(contents, tr("Destino"), Rect2(990, 264, 190, 28), 18, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	if not source.is_empty():
		item_card(source, Rect2(650, 300, 190, 190), int(source.level))
		UiKit.clipped(contents, Armory.item_name(source), Rect2(610, 496, 270, 40), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(contents, "⇄", Rect2(840, 330, 150, 80), 48, Color("a8642a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	if not target.is_empty():
		item_card(target, Rect2(990, 300, 190, 190), int(target.level))
		UiKit.clipped(contents, Armory.item_name(target), Rect2(950, 496, 270, 40), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var button: Button = UiKit.button(contents, tr("TRANSFERIR"), Rect2(806, 566, 220, 54), do_transfer, "button_green", 20)
	button.set_meta("active", true)
	button.disabled = source.is_empty() or target.is_empty() or selected_uid == target_uid or Armory.slot_of(str(source.get("id", ""))) != Armory.slot_of(str(target.get("id", ""))) or app.profile.coins < int(Armory.data().strengthen.transfer_coins)

# ---------- Moedas (0.10) ----------

func craft_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for inst: Dictionary in app.profile.inventory:
		if Crafting.can_have_mods(str(inst.id)):
			list.append(inst)
	var rank: Dictionary = {"super": 0, "verdadeira": 1, "excelente": 2, "normal": 3}
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(rank.get(a.quality, 3)) < int(rank.get(b.quality, 3)) if a.quality != b.quality else (Armory.slot_of(str(a.id)) + str(a.id) < Armory.slot_of(str(b.id)) + str(b.id)))
	return list

func craft_maps() -> Array[Dictionary]:
	var list: Array[Dictionary] = app.profile.maps.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level) if a.level != b.level else str(a.instance) < str(b.instance))
	return list

func build_craft_list() -> void:
	for i in range(2):
		var kind: String = ["item", "map"][i]
		var toggle: Button = UiKit.button(contents, tr(["Equipamentos", "Mapas"][i]), Rect2(70 + i * 170, 158, 164, 32), select_target.bind(kind), "tab_active" if craft_target == kind else "tab", 15)  # i18n
		toggle.name = "Target_" + kind
		toggle.set_meta("active", craft_target == kind)
	var list: Array[Dictionary] = craft_items() if craft_target == "item" else craft_maps()
	if craft_target == "item" and (list.is_empty() or not list.any(func(inst: Dictionary) -> bool: return int(inst.uid) == selected_uid)):
		selected_uid = int(list[0].uid) if not list.is_empty() else -1
	if craft_target == "map" and not list.any(func(item: Dictionary) -> bool: return int(item.uid) == map_uid):
		map_uid = int(list[0].uid) if not list.is_empty() else -1
	var pages: int = maxi(1, ceili(list.size() / float(CRAFT_PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(CRAFT_PER_PAGE):
		var index: int = page * CRAFT_PER_PAGE + i
		if index >= list.size():
			break
		var entry: Dictionary = list[index]
		var uid: int = int(entry.uid)
		var chosen: bool = uid == (selected_uid if craft_target == "item" else map_uid)
		var rect: Rect2 = Rect2(70 + (i % 6) * 82, 198 + (i / 6 as int) * 70, 76, 66)
		var slot: Button = UiKit.button(contents, "", rect, pick_craft.bind(uid), "card_hover" if chosen else "slot")
		if craft_target == "item":
			slot.name = "Craft_%d" % uid
			with_card(slot, {"key": "uid:%d" % uid, "inst": entry, "name": Armory.item_name(entry)})
			if str(entry.quality) != "normal":
				slot.add_child(BagSlot.glow_node(Rect2(6, 3, 64, 60), Armory.quality_color(entry)))
			var picture: TextureRect = UiKit.art(slot, Armory.load_icon(entry), Rect2(12, 6, 52, 52))
			picture.modulate = Armory.icon_tint(entry)
			if int(entry.level) > 0:
				UiKit.label(slot, "+%d" % int(entry.level), Rect2(2, 0, 40, 20), 14, Armory.aura_color(int(entry.level)).lightened(0.3), UiKit.INK)
			var mods: int = (entry.get("mods", []) as Array).size()
			if mods > 0:
				UiKit.label(slot, str(mods), Rect2(56, 44, 18, 20), 14, Color("9ae8ff"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
			if app.profile.is_equipped(uid):
				UiKit.label(slot, "E", Rect2(4, 44, 16, 20), 13, Color("9aff7a"), UiKit.INK)
		else:
			slot.name = "CraftMap_%d" % uid
			with_card(slot, {"key": "map:%d" % uid, "map": entry, "name": InstanceRun.map_name(entry), "icon": InstanceRun.map_icon(entry), "count": 1})
			if str(entry.quality) != "normal":
				slot.add_child(BagSlot.glow_node(Rect2(6, 3, 64, 60), InstanceRun.quality_color(str(entry.quality))))
			UiKit.art(slot, InstanceRun.map_icon(entry), Rect2(12, 6, 52, 52))
			UiKit.label(slot, str(int(entry.level)), Rect2(40, 42, 34, 22), 16, InstanceRun.quality_color(str(entry.quality)), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	if list.is_empty():
		UiKit.label(contents, tr("Nenhum equipamento que aceite bônus.") if craft_target == "item" else tr("Nenhum mapa na mochila."), Rect2(72, 200, 490, 40), 18, HudPaint.CREAM)
	UiKit.button(contents, "<", Rect2(380, 626, 40, 32), turn_page.bind(-1), "tab", 14)
	UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(420, 626, 80, 32), 15, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(500, 626, 40, 32), turn_page.bind(1), "tab", 14)
	UiKit.label(contents, (tr("%d itens") if craft_target == "item" else tr("%d mapas")) % list.size(), Rect2(72, 626, 200, 32), 15, HudPaint.CREAM)

func craft_subject() -> Dictionary:
	return app.profile.find_instance(selected_uid) if craft_target == "item" else app.profile.find_map(map_uid)

func build_craft() -> void:
	var subject: Dictionary = craft_subject()
	if subject.is_empty():
		UiKit.label(contents, tr("Escolha um equipamento ou um mapa."), Rect2(600, 300, 612, 40), 20, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		build_currency_buttons(subject)
		return
	var lines: Array[String] = []
	var colors: Array[Color] = []
	var box: Control = forge_panel(contents, Rect2(604, 230, 120, 120))
	box.clip_contents = true
	if craft_target == "item":
		var quality: String = str(subject.quality)
		UiKit.clipped(contents, Armory.item_name(subject), Rect2(600, 158, 612, 32), 22, Armory.quality_color(subject).lightened(0.15), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var facts: Array[String] = [Armory.quality_label(quality), tr("Nível do item %d") % Crafting.item_level(subject), tr("%d/%d bônus") % [(subject.get("mods", []) as Array).size(), Crafting.max_mods(quality)]]
		if bool(subject.get("mirrored", false)):
			facts.append(tr("Espelhado"))
		elif bool(subject.get("bound", false)):
			facts.append(tr("Vinculado"))
		UiKit.label(contents, "  •  ".join(facts), Rect2(600, 192, 612, 26), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		if quality != "normal":
			box.add_child(BagSlot.glow_node(Rect2(4, 4, 112, 112), Armory.quality_color(subject)))
		var picture: TextureRect = UiKit.art(box, Armory.load_icon(subject), Rect2(14, 14, 92, 92))
		picture.modulate = Armory.icon_tint(subject)
		lines = Crafting.describe(subject)
		for line in lines:
			colors.append(Color("9ae8ff"))
		if lines.is_empty():
			lines.append(tr("Sem bônus. Use uma Brasa para torná-lo Excelente.") if quality == "normal" else tr("Sem bônus."))
			colors.append(Color("c8b8a0"))
	else:
		UiKit.clipped(contents, InstanceRun.map_name(subject), Rect2(600, 158, 612, 32), 22, InstanceRun.quality_color(str(subject.quality)).lightened(0.15), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var count: Array = Crafting.map_count(str(subject.quality))
		UiKit.label(contents, tr("%s  •  %d/%d atributos  •  consumido ao entrar") % [InstanceRun.quality_label(str(subject.quality)), (subject.get("mods", []) as Array).size(), int(count[1])], Rect2(600, 192, 612, 26), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.art(box, InstanceRun.map_icon(subject), Rect2(14, 14, 92, 92))
		UiKit.label(box, str(int(subject.level)), Rect2(60, 80, 54, 34), 26, InstanceRun.quality_color(str(subject.quality)), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		for kind: String in ["threat", "reward"]:
			for mod: Dictionary in subject.get("mods", []):
				if str(InstanceRun.mod_def(str(mod.id)).get("kind", "")) == kind:
					lines.append(InstanceRun.mod_text(mod))
					colors.append(Color("ff8a6a") if kind == "threat" else Color("9aff7a"))
		if lines.is_empty():
			lines.append(tr("Sem atributos. Use uma Brasa para torná-lo Excelente."))
			colors.append(Color("c8b8a0"))
	var list: Control = forge_panel(contents, Rect2(736, 230, 472, 120))
	list.name = "CraftBonuses"
	for i in range(mini(lines.size(), 4)):
		UiKit.label(list, lines[i], Rect2(12, 4 + i * 28, 452, 28), 16, colors[i], UiKit.INK)
	build_currency_buttons(subject)

func build_currency_buttons(subject: Dictionary) -> void:
	UiKit.label(contents, tr("Clique numa moeda para usá-la. Usar gasta a moeda."), Rect2(600, 360, 612, 26), 16, HudPaint.GOLD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var list: Array = Crafting.currencies()
	for i in range(list.size()):
		var def: Dictionary = list[i]
		var id: String = str(def.id)
		var count: int = app.profile.currency_count(id)
		var reason: String = ""
		if subject.is_empty():
			reason = tr("Escolha um equipamento ou um mapa.")
		else:
			reason = Crafting.check(id, subject) if craft_target == "item" else Crafting.check_map(id, subject)
		if reason == "" and count <= 0:
			reason = tr("Você não tem %s.") % Crafting.currency_name(id)
		var rect: Rect2 = Rect2(606 + (i % 4) * 152, 390 + (i / 4 as int) * 132, 144, 124)
		var button: Button = UiKit.button(contents, "", rect, do_craft.bind(id), "slot_light")
		button.name = "Currency_" + id
		button.disabled = reason != ""
		button.add_theme_stylebox_override("disabled", UiKit.frame("card_busy"))
		button.tooltip_text = "%s\n%s%s" % [Crafting.currency_name(id), Crafting.currency_desc(id), "\n\n" + reason if reason != "" else ""]
		var icon: TextureRect = UiKit.art(button, str(def.icon), Rect2(44, 8, 56, 56))
		UiKit.label(button, Crafting.currency_name(id), Rect2(0, 64, 144, 26), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(button, "x%d" % count, Rect2(0, 90, 144, 26), 16, Color("8cff7a") if count > 0 else Color("b4a690"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		if button.disabled:
			icon.modulate = Color(0.55, 0.52, 0.5)

func select_target(kind: String) -> void:
	craft_target = kind
	page = 0
	message = ""
	build()

func pick_craft(uid: int) -> void:
	if craft_target == "item":
		selected_uid = uid
	else:
		map_uid = uid
	message = ""
	build()

func turn_page(step: int) -> void:
	page += step
	build()

func do_craft(currency: String) -> void:
	var def: Dictionary = Crafting.currency_def(currency)
	var outcome: Dictionary = await app.do_op("craft" if craft_target == "item" else "craft_map", [currency, selected_uid if craft_target == "item" else map_uid])
	var error: String = outcome.error
	var subject: Dictionary = craft_subject()
	var done: String = ""
	if error == "":
		if currency == "espelho":
			done = tr("Espelho Celeste usado: uma cópia vinculada de %s foi para a Mochila.") % Armory.item_name(subject)
		elif craft_target == "item":
			done = tr("Usou %s: %s agora tem %d bônus.") % [Crafting.currency_name(currency), Armory.item_name(subject), (subject.get("mods", []) as Array).size()]
		else:
			done = tr("Usou %s: o mapa agora tem %d atributos.") % [Crafting.currency_name(currency), (subject.get("mods", []) as Array).size()]
	report(error, done)

func pick(uid: int) -> void:
	if tab == "Transferência" and selected_uid >= 0 and uid != selected_uid:
		target_uid = uid
	else:
		selected_uid = uid
		target_uid = -1
	message = ""
	build()

func select_tab(value: String) -> void:
	tab = value
	target_uid = -1
	page = 0
	message = ""
	build()

func report(error: String, success: String) -> void:
	message = error if error != "" else success
	app.audio.play("ui_error" if error != "" else "ui_forge")
	build()

func do_strengthen() -> void:
	if busy:
		return
	busy = true
	var before: Dictionary = app.profile.find_instance(selected_uid).duplicate(true)
	var blocker: Control = Control.new()
	blocker.size = size
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	var error: String = (await app.do_op("strengthen", [selected_uid])).error
	if not is_inside_tree():
		return
	blocker.queue_free()
	if error != "":
		busy = false
		report(error, "")
		return
	var inst: Dictionary = app.profile.find_instance(selected_uid)
	var success: bool = int(inst.get("level", 0)) > int(before.get("level", 0))
	var moment: ForgeOutcome = ForgeOutcome.new()
	moment.item = inst.duplicate(true)
	moment.success = success
	moment.audio = app.audio
	add_child(moment)
	await moment.completed
	busy = false
	message = tr("Sucesso! %s agora é +%d.") % [Armory.item_name(before, false), int(inst.get("level", 0))] if success else tr("A pedra foi consumida. O nível do item foi preservado.")
	build()

func do_transfer() -> void:
	report((await app.do_op("transfer", [selected_uid, target_uid])).error, tr("Transferência concluída!"))

func close() -> void:
	if busy:
		return
	closed.emit()
	queue_free()
