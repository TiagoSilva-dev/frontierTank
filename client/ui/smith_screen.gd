class_name SmithScreen
extends Control

# Ferreiro (DDTank): Fortalecer up to +12 with Pedras de Fortalecimento, Composição with
# Cristal Dourado, Fusão of 4 equal stones into the next level and Transferência of the
# strengthen level between two items of the same kind. Weapon art evolves at +9/+10/+12
# and the aura follows the level: +1-5 green, +6-8 blue, +9-11 purple, +12 red.

signal closed

const TABS: Array[String] = ["Fortalecer", "Composição", "Fusão", "Transferência"]

var app: Node
var tab: String = "Fortalecer"
var selected_uid: int = -1
var target_uid: int = -1
var contents: Control
var flash_time: float = 0.0
var message: String = ""

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
	UiKit.dim(contents, 0.75)
	UiKit.panel(contents, Rect2(40, 24, 1200, 672), "wood")
	UiKit.title(contents, "FERREIRO", Rect2(40, 30, 1200, 44), 32)
	UiKit.button(contents, "FECHAR", Rect2(1086, 34, 140, 42), close)
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(64, 36, 32, 32))
	UiKit.label(contents, str(app.profile.coins), Rect2(100, 32, 200, 40), 22, Color("ffd46b"), UiKit.INK)
	for i in range(TABS.size()):
		UiKit.button(contents, TABS[i], Rect2(60 + i * 180, 84, 172, 40), select_tab.bind(TABS[i]), "tab_active" if tab == TABS[i] else "tab", 16)
	UiKit.panel(contents, Rect2(56, 130, 520, 550), "paper")
	UiKit.panel(contents, Rect2(588, 130, 636, 550), "paper")
	if tab == "Fusão":
		build_fusion()
	else:
		build_item_list()
		match tab:
			"Fortalecer":
				build_strengthen()
			"Composição":
				build_compose()
			"Transferência":
				build_transfer()
	if message != "":
		var bar: Panel = UiKit.panel(contents, Rect2(600, 634, 612, 38), "dark")
		UiKit.label(bar, message, Rect2(8, 0, 596, 38), 15, Color("fff4a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func eligible() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for inst: Dictionary in app.profile.inventory:
		var id: String = str(inst.id)
		if tab == "Composição" and Armory.kind_of(id) != "aux":
			list.append(inst)
		elif Armory.can_strengthen(id):
			list.append(inst)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level) if a.level != b.level else str(a.id) < str(b.id))
	return list

func build_item_list() -> void:
	UiKit.label(contents, "Escolha o item" if tab != "Transferência" else "Escolha a origem e depois o destino", Rect2(72, 136, 490, 30), 17, UiKit.TEXT_DARK)
	var list: Array[Dictionary] = eligible()
	for i in range(mini(list.size(), 42)):
		var inst: Dictionary = list[i]
		var uid: int = int(inst.uid)
		var rect: Rect2 = Rect2(70 + (i % 6) * 82, 170 + (i / 6 as int) * 72, 76, 66)
		var kind: String = "card_hover" if uid == selected_uid else ("slot_light" if uid == target_uid else "slot")
		var slot: Button = UiKit.button(contents, "", rect, pick.bind(uid), kind)
		slot.name = "Smith_%d" % uid
		slot.tooltip_text = Armory.item_name(inst)
		var picture: TextureRect = UiKit.art(slot, Armory.load_icon(inst), Rect2(12, 6, 52, 52))
		picture.modulate = Armory.icon_tint(inst)
		if int(inst.level) > 0:
			UiKit.label(slot, "+%d" % int(inst.level), Rect2(2, 0, 40, 20), 14, Armory.aura_color(int(inst.level)).lightened(0.3), UiKit.INK)
		if app.profile.is_equipped(uid):
			UiKit.label(slot, "E", Rect2(60, 46, 16, 20), 13, Color("9aff7a"), UiKit.INK)
	if list.is_empty():
		UiKit.label(contents, "Nenhum item disponível.", Rect2(72, 200, 490, 40), 18, UiKit.TEXT_DARK)

func item_card(inst: Dictionary, rect: Rect2, level_shown: int) -> void:
	# Item with its aura ring behind, at a given strengthen level.
	var box: Panel = UiKit.panel(contents, rect, "dark")
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

func build_strengthen() -> void:
	var inst: Dictionary = app.profile.find_instance(selected_uid)
	if inst.is_empty():
		UiKit.label(contents, "Selecione uma arma, roupa ou chapéu.", Rect2(600, 300, 612, 40), 20, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var level: int = int(inst.level)
	var maxed: bool = level >= int(Armory.data().strengthen.max)
	UiKit.label(contents, Armory.item_name(inst), Rect2(600, 138, 612, 32), 22, Armory.quality_color(inst).darkened(0.35), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	item_card(inst, Rect2(660, 172, 150, 150), level)
	UiKit.label(contents, "►", Rect2(830, 222, 150, 50), 40, Color("a8642a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	item_card(inst, Rect2(1000, 172, 150, 150), mini(level + 1, 12))
	var cost: Dictionary = app.profile.strengthen_cost(inst)
	var next_inst: Dictionary = inst.duplicate()
	next_inst.level = mini(level + 1, 12)
	# Every level raises the item's attributes (and the weapon damage).
	var rows: Array = []
	if Armory.slot_of(str(inst.id)) == "arma":
		rows.append(["Dano", int(Armory.build_weapon(inst).damage), int(Armory.build_weapon(next_inst).damage)])
	var now: Dictionary = Armory.item_attrs(inst)
	var then: Dictionary = Armory.item_attrs(next_inst)
	for key: String in Armory.ATTRS:
		if int(now[key]) > 0 or int(then[key]) > 0:
			rows.append([Armory.ATTR_NAMES[key], int(now[key]), int(then[key])])
	if Armory.slot_of(str(inst.id)) != "arma":
		var hp: int = int(Armory.data().strengthen.hp_per_level)
		rows.append(["Vida", level * hp, next_inst.level * hp])
	var table: Panel = UiKit.panel(contents, Rect2(606, 330, 600, 118), "dark")
	for i in range(rows.size()):
		var row: Array = rows[i]
		var x: float = 14 + (i / 3 as int) * 300
		var y: float = 6 + (i % 3) * 36
		UiKit.label(table, str(row[0]), Rect2(x, y, 110, 32), 17, Color("ffe6a0"), UiKit.INK)
		var after: String = "" if maxed else "  ►  %d" % int(row[2])
		UiKit.label(table, "%d%s" % [int(row[1]), after], Rect2(x + 110, y, 180, 32), 17, Color("9aff7a") if not maxed else Color.WHITE, UiKit.INK)
	var notes: Array[String] = []
	if Armory.slot_of(str(inst.id)) == "arma" and not maxed and Armory.tier_for_level(level + 1) != Armory.tier_for_level(level):
		notes.append("No +%d a arma muda de visual!" % (level + 1))
	var next_aura: Dictionary = Armory.aura(level + 1)
	if not maxed and Armory.aura(level).get("name", "") != next_aura.get("name", ""):
		notes.append("Nova aura: %s" % next_aura.name)
	if maxed:
		notes = ["Nível máximo +12: aura vermelha!"]
	UiKit.label(contents, "   •   ".join(notes), Rect2(600, 450, 612, 26), 16, Color("8a3a10"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var stones: Array = Armory.data().strengthen.stones
	for i in range(stones.size()):
		var stone: Dictionary = stones[i]
		var slot: Panel = UiKit.panel(contents, Rect2(620 + i * 148, 478, 140, 60), "slot_light")
		UiKit.art(slot, str(stone.icon), Rect2(6, 6, 48, 48))
		UiKit.label(slot, "x%d" % int(app.profile.items.get(stone.id, 0)), Rect2(58, 2, 80, 28), 18, UiKit.TEXT_DARK)
		UiKit.label(slot, "%d pt" % int(stone.points), Rect2(58, 30, 80, 26), 14, Color("8a5a2a"))
	if not maxed:
		var enough: bool = app.profile.stone_points() >= int(cost.points)
		UiKit.label(contents, "Pedras: %d / %d pontos   •   Moedas: %d" % [app.profile.stone_points(), int(cost.points), int(cost.coins)], Rect2(600, 542, 612, 28), 17, Color("2f7a1f") if enough else Color("b8321c"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var button: Button = UiKit.button(contents, "FORTALECER", Rect2(806, 576, 220, 50), do_strengthen, "button_green", 22)
		button.name = "StrengthenButton"

func build_compose() -> void:
	var inst: Dictionary = app.profile.find_instance(selected_uid)
	var rules: Dictionary = Armory.data().strengthen.compose
	UiKit.label(contents, "COMPOSIÇÃO", Rect2(600, 138, 612, 32), 22, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(contents, "Cada Cristal Dourado soma +%d ao atributo escolhido (até %d vezes por item)." % [int(rules.amount), int(rules.max)], Rect2(610, 170, 592, 50), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if inst.is_empty():
		return
	item_card(inst, Rect2(820, 224, 170, 170), int(inst.level))
	UiKit.label(contents, Armory.item_name(inst), Rect2(600, 398, 612, 30), 19, Armory.quality_color(inst).darkened(0.35), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var composed: Dictionary = inst.get("compose", {})
	for i in range(Armory.ATTRS.size()):
		var attr: String = Armory.ATTRS[i]
		UiKit.button(contents, "%s +%d" % [Armory.ATTR_NAMES[attr], int(composed.get(attr, 0))], Rect2(612 + i * 150, 440, 142, 48), do_compose.bind(attr), "button_blue", 15)
	var slot: Panel = UiKit.panel(contents, Rect2(810, 500, 190, 64), "slot_light")
	UiKit.art(slot, "res://assets/expansion/items/golden_crystal.png", Rect2(6, 6, 52, 52))
	UiKit.label(slot, "x%d" % int(app.profile.items.get(rules.item, 0)), Rect2(64, 6, 120, 52), 20, UiKit.TEXT_DARK)
	UiKit.label(contents, "Custo: 1 cristal + %d moedas" % int(rules.coins), Rect2(600, 572, 612, 28), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)

func build_fusion() -> void:
	var rules: Dictionary = Armory.data().strengthen
	var stones: Array = rules.stones
	UiKit.label(contents, "FUSÃO DE PEDRAS", Rect2(56, 140, 520, 34), 22, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var info: Label = UiKit.label(contents, "Junte %d pedras do mesmo nível para criar uma do nível seguinte (%d moedas).\n\nAs pedras dão pontos de fortalecimento: I = 1, II = 5, III = 25, IV = 125.\nDo +1 ao +12 são necessários 1, 5, 15, 35, 70, 150, 230, 330, 450, 600, 750 e 900 pontos." % [int(rules.fusion_count), int(rules.fusion_coins)], Rect2(76, 190, 480, 300), 17, UiKit.TEXT_DARK)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in range(stones.size() - 1):
		var y: float = 160 + i * 150
		var from: Dictionary = stones[i]
		var into: Dictionary = stones[i + 1]
		var left: Panel = UiKit.panel(contents, Rect2(620, y, 150, 110), "slot_light")
		UiKit.art(left, str(from.icon), Rect2(40, 6, 70, 70))
		UiKit.label(left, "%d x %s" % [int(rules.fusion_count), from.name.get_slice(" ", 3)], Rect2(0, 76, 150, 30), 16, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(contents, "►", Rect2(772, y + 20, 80, 60), 36, Color("a8642a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var right: Panel = UiKit.panel(contents, Rect2(854, y, 150, 110), "slot_light")
		UiKit.art(right, str(into.icon), Rect2(40, 6, 70, 70))
		UiKit.label(right, "1 x %s" % into.name.get_slice(" ", 3), Rect2(0, 76, 150, 30), 16, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(contents, "Você tem %d" % int(app.profile.items.get(from.id, 0)), Rect2(1014, y + 6, 200, 30), 16, UiKit.TEXT_DARK)
		UiKit.button(contents, "FUNDIR", Rect2(1020, y + 44, 170, 48), do_fuse.bind(str(from.id)), "button_green", 18)

func build_transfer() -> void:
	var source: Dictionary = app.profile.find_instance(selected_uid)
	var target: Dictionary = app.profile.find_instance(target_uid)
	UiKit.label(contents, "TRANSFERÊNCIA", Rect2(600, 138, 612, 32), 22, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var info: Label = UiKit.label(contents, "Troca o nível de fortalecimento e a composição entre dois itens do mesmo tipo — por exemplo, passe o +9 da sua arma Normal para a Verdadeira. Custa %d moedas." % int(Armory.data().strengthen.transfer_coins), Rect2(620, 170, 572, 70), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.label(contents, "Origem", Rect2(650, 250, 190, 28), 18, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(contents, "Destino", Rect2(990, 250, 190, 28), 18, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	if not source.is_empty():
		item_card(source, Rect2(650, 282, 190, 190), int(source.level))
		UiKit.label(contents, Armory.item_name(source), Rect2(610, 476, 270, 50), 14, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.label(contents, "⇄", Rect2(840, 330, 150, 80), 48, Color("a8642a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	if not target.is_empty():
		item_card(target, Rect2(990, 282, 190, 190), int(target.level))
		UiKit.label(contents, Armory.item_name(target), Rect2(950, 476, 270, 50), 14, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.button(contents, "TRANSFERIR", Rect2(806, 560, 220, 54), do_transfer, "button_green", 20)

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
	message = ""
	build()

func report(error: String, success: String) -> void:
	message = error if error != "" else success
	app.audio.tone(200 if error != "" else 880, 0.2)
	build()

func do_strengthen() -> void:
	var before: Dictionary = app.profile.find_instance(selected_uid).duplicate()
	var error: String = app.profile.strengthen(selected_uid)
	var inst: Dictionary = app.profile.find_instance(selected_uid)
	report(error, "Sucesso! %s agora é +%d." % [Armory.item_name(before, false), int(inst.get("level", 0))])

func do_compose(attr: String) -> void:
	report(app.profile.compose(selected_uid, attr), "Composição feita: %s +%d." % [Armory.ATTR_NAMES[attr], int(Armory.data().strengthen.compose.amount)])

func do_fuse(stone_id: String) -> void:
	report(app.profile.fuse(stone_id), "Fusão concluída!")

func do_transfer() -> void:
	report(app.profile.transfer(selected_uid, target_uid), "Transferência concluída!")

func close() -> void:
	closed.emit()
	queue_free()
