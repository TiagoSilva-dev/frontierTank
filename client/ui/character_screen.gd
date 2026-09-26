class_name CharacterScreen
extends Control

# Mochila / Informações Pessoais, like the DDTank profile window: equipment slots around
# the character, attributes below and the inventory on the right. Single account
# identity: there is intentionally no roster.
# 0.15: the character stands on a lit pedestal (HeroStage); a card with every detail
# of an item follows the mouse (ItemTooltip); the item's quality is a glow behind it
# instead of a coloured square (BagSlot); items are dragged to arrange the bag the way
# the player likes (kept in the profile, `bag_layout`), dragged onto the character or
# an equipment slot to equip, and out of a slot to take them off. Double click (or
# right click) equips too. Selecting only redraws the cells, it never rebuilds the page.

const ITEM_NAMES: Dictionary = {
	"pedra_fortalecimento": ["Pedra de Fortalecimento I", "res://assets/items/pedra_i.png"],  # i18n
	"strength_stone_ii": ["Pedra de Fortalecimento II", "res://assets/items/pedra_ii.png"],  # i18n
	"strength_stone_iii": ["Pedra de Fortalecimento III", "res://assets/items/pedra_iii.png"],  # i18n
	"strength_stone_iv": ["Pedra de Fortalecimento IV", "res://assets/items/pedra_iv.png"],  # i18n
	"golden_crystal": ["Cristal Dourado", "res://assets/expansion/items/golden_crystal.png"],  # i18n
	"pet_egg": ["Ovo de Mascote", "res://assets/expansion/items/pet_egg.png"],  # i18n
}
const CATEGORIES: Array[String] = ["Todos", "Armas", "Visual", "Auxiliar", "Materiais", "Mapas"]  # i18n
const LEFT_SLOTS: Array[String] = ["chapeu", "oculos", "cabelo", "roupa"]
const RIGHT_SLOTS: Array[String] = ["asas", "arma", "auxiliar"]
# Pale silhouettes of what goes in each empty equipment slot.
const GHOSTS: Dictionary = {
	"chapeu": "res://assets/cosmetics/chapeu_cartola/front.png",
	"oculos": "res://assets/cosmetics/oculos_redondos/front.png",
	"cabelo": "res://assets/cosmetics/cabelo/icon.png",
	"roupa": "res://assets/characters/base_m/south.png",
	"asas": "res://assets/cosmetics/asas_anjo/icon.png",
	"arma": "res://assets/weapons/canhao_explorador.png",
	"auxiliar": "res://assets/aux/dom_de_anjo.png",
}
const STAT_ICONS: String = "res://assets/ui/stats/%s.png"
const COLUMNS: int = 8
const ROWS: int = 5
const PER_PAGE: int = COLUMNS * ROWS
const CELL: float = 60.0
const GAP: float = 8.0
const GRID: Vector2 = Vector2(684, 148)
const QUALITY_RANK: Dictionary = {"super": 3, "verdadeira": 2, "excelente": 1}
const SLOT_ORDER: Array[String] = ["arma", "chapeu", "oculos", "cabelo", "roupa", "asas", "auxiliar"]

var app: Node
var contents: Control
var profile_root: Control
var grid_root: Control
var category: String = "Todos"
var selected: String = ""
var selected_label: RichTextLabel
var selected_icon: BagSlot
var equip_button: Button
var sell_button: Button
var page_label: Label
var count_label: Label
var tab_name: String = "Perfil"
var page: int = 0
var pages: int = 1
var cells_shown: Array[BagSlot] = []
var equip_cells: Dictionary = {}
var tooltip: ItemTooltip
var hover_slot: BagSlot
var hover_time: float = 0.0
var arrow_rects: Array[Rect2] = []
var flip_hold: float = 0.0

func _ready() -> void:
	size = Vector2(1280, 720)
	selected = "uid:%d" % int(app.profile.equipped.get("arma", -1))
	build()

func build() -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
	hover_slot = null
	contents = Control.new()
	contents.size = size
	add_child(contents)
	# Keep dialogs (Ferreiro, Loja, Cupom) above the rebuilt page.
	move_child(contents, 0)
	UiKit.dim(contents, 0.72)
	UiKit.panel(contents, Rect2(24, 12, 1232, 76), "wood_dark")
	UiKit.label(contents, tr("MOCHILA"), Rect2(44, 18, 220, 64), 34, Color("ffd681"), UiKit.INK)
	UiKit.button(contents, tr("VOLTAR"), Rect2(290, 26, 130, 48), app.close_bag)
	UiKit.button(contents, tr("FERREIRO"), Rect2(430, 26, 150, 48), open_smith, "button_blue")
	UiKit.button(contents, tr("LOJA"), Rect2(590, 26, 120, 48), open_shop, "button_green")
	UiKit.button(contents, tr("CUPOM"), Rect2(720, 26, 130, 48), open_coupon)
	UiKit.art(contents, "res://assets/items/moeda.png", Rect2(1030, 24, 40, 40))
	UiKit.label(contents, str(app.profile.coins), Rect2(1076, 20, 170, 36), 26, Color("ffd46b"), UiKit.INK)
	UiKit.label(contents, tr("moedas"), Rect2(1078, 56, 160, 24), 15, Color("e0c89a"), UiKit.INK)
	UiKit.panel(contents, Rect2(24, 96, 612, 612), "wood")
	UiKit.label(contents, tr("Informações Pessoais"), Rect2(44, 100, 360, 36), 24, Color("fff0c7"), UiKit.INK)
	for i in range(3):
		var name_text: String = ["Perfil", "Atributos", "Histórico"][i]  # i18n
		UiKit.button(contents, tr(name_text), Rect2(334 + i * 96, 102, 92, 32), select_tab.bind(name_text), "tab_active" if tab_name == name_text else "tab", 14)
	UiKit.panel(contents, Rect2(38, 140, 584, 554), "paper")
	profile_root = layer()
	build_profile()
	build_inventory()
	tooltip = ItemTooltip.new()
	contents.add_child(tooltip)

func layer() -> Control:
	var node: Control = Control.new()
	node.size = size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(node)
	return node

# ---------- left: Informações Pessoais ----------

func build_profile() -> void:
	var head: Panel = UiKit.panel(profile_root, Rect2(48, 148, 564, 40), "dark")
	UiKit.level_badge(head, app.profile.level(), Rect2(6, 5, 40, 30))
	UiKit.label(head, app.profile.player_name, Rect2(54, 0, 260, 40), 22, Color.WHITE, UiKit.INK)
	UiKit.label(head, TankFighter.rank_for(app.profile.level()), Rect2(320, 0, 130, 40), 16, Color("9aff7a"), UiKit.INK)
	UiKit.label(head, tr("Ranking %d") % app.profile.ranking(), Rect2(440, 0, 118, 40), 16, Color("ffb0a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	if tab_name == "Perfil":
		build_equipment()
	elif tab_name == "Atributos":
		build_attributes()
	else:
		build_history()

func build_equipment() -> void:
	equip_cells.clear()
	# Experience: a slim bar under the name with the numbers inside.
	var exp_bar: ProgressBar = UiKit.bar(profile_root, Rect2(48, 192, 564, 16), Color("d99932"))
	exp_bar.value = app.profile.level_progress() * 100.0
	var next: int = PlayerProfile.exp_for_level(app.profile.level() + 1)
	UiKit.label(exp_bar, tr("EXP  %.1f%%  •  %d / %d") % [app.profile.level_progress() * 100.0, app.profile.experience, next], Rect2(0, -3, 564, 20), 13, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var stage: HeroStage = HeroStage.create(profile_root, Rect2(124, 212, 412, 326), app.profile.look())
	stage.name = "Stage"
	stage.accepts = func(data: Dictionary) -> bool: return can_equip_key(str(data.bag_key))
	stage.dropped.connect(func(data: Dictionary) -> void: equip_key(str(data.bag_key)))
	for i in range(LEFT_SLOTS.size()):
		equipment_slot(LEFT_SLOTS[i], Rect2(50, 222 + i * 78, 64, 64))
	for i in range(RIGHT_SLOTS.size()):
		equipment_slot(RIGHT_SLOTS[i], Rect2(546, 222 + i * 78, 64, 64))
	var pet: BagSlot = BagSlot.new()
	pet.interactive = false
	pet.icon = load("res://assets/pets/fenix_dourada.png")
	pet.position = Vector2(546, 456)
	pet.size = Vector2(64, 64)
	profile_root.add_child(pet)
	UiKit.label(profile_root, tr("Mascote"), Rect2(538, 518, 80, 18), 12, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	build_stats(Rect2(48, 544, 564, 144))

func equipment_slot(slot: String, rect: Rect2) -> void:
	var inst: Dictionary = app.profile.equipped_instance(slot)
	var cell: BagSlot = BagSlot.new()
	cell.equip_slot = slot
	cell.position = rect.position
	cell.size = rect.size
	cell.name = "Equip_" + slot
	cell.ghost = load(str(GHOSTS[slot])) if ResourceLoader.exists(str(GHOSTS[slot])) else null
	cell.caption = Armory.slot_name(slot)
	profile_root.add_child(cell)
	var key: String = "uid:%d" % int(inst.uid) if not inst.is_empty() else "slot:" + slot
	cell.show_entry({"key": key, "inst": inst} if not inst.is_empty() else {})
	cell.selected = selected == key
	cell.accepts = func(target: BagSlot, data: Dictionary) -> bool: return str(data.equip_slot) == "" and can_equip_key(str(data.bag_key), target.equip_slot)
	cell.clicked.connect(func(target: BagSlot) -> void: select_item(target.key if target.key != "" else "slot:" + target.equip_slot))
	cell.activated.connect(func(target: BagSlot) -> void:
		if target.key != "":
			toggle_key(target.key))
	cell.hovered.connect(on_hover)
	cell.dropped.connect(func(_target: BagSlot, data: Dictionary) -> void: equip_key(str(data.bag_key)))
	equip_cells[slot] = cell

func aura_text(label_text: String, level: int) -> String:
	var entry: Dictionary = Armory.aura(level)
	return "%s: %s" % [label_text, "%s (+%d)" % [tr(str(entry.name)), level] if not entry.is_empty() else tr("sem aura")]

func build_stats(rect: Rect2) -> void:
	var numbers: Dictionary = app.profile.stats(app.balance)
	var box: Panel = UiKit.panel(profile_root, rect, "dark")
	var left: Array = [["Ataque", "ataque"], ["Defesa", "defesa"], ["Agilidade", "agilidade"], ["Sorte", "sorte"]]  # i18n
	for i in range(4):
		var y: float = 8 + i * 33
		UiKit.art(box, STAT_ICONS % left[i][1], Rect2(10, y, 28, 28))
		UiKit.label(box, tr(left[i][0]), Rect2(44, y, 120, 28), 15, Color("ffe6a0"), UiKit.INK)
		var value: Panel = UiKit.panel(box, Rect2(170, y + 1, 92, 26), Color("fff4d6"), Color("7a5230"))
		UiKit.label(value, str(numbers[left[i][1]]), Rect2(0, -1, 92, 26), 16, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var right: Array = [["Dano", "dano", Color("ff9a2a")], ["Proteção", "protecao", Color("3a8bff")], ["Vida", "vida", Color("e0302a")], ["Força física", "energia", Color("5cc83a")]]  # i18n
	for i in range(4):
		var y: float = 8 + i * 33
		UiKit.art(box, STAT_ICONS % right[i][1], Rect2(282, y, 28, 28))
		UiKit.label(box, tr(right[i][0]), Rect2(316, y, 110, 28), 15, Color("ffe6a0"), UiKit.INK)
		var bar: Panel = UiKit.panel(box, Rect2(424, y + 2, 130, 24), right[i][2], right[i][2].lightened(0.4))
		UiKit.label(bar, str(numbers[right[i][1]]), Rect2(0, -1, 130, 24), 15, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func build_attributes() -> void:
	var numbers: Dictionary = app.profile.stats(app.balance)
	var weapon: Dictionary = numbers.weapon
	UiKit.label(profile_root, tr("ATRIBUTOS DE COMBATE"), Rect2(60, 192, 540, 34), 22, Color("624128"))
	var extra: Dictionary = numbers.extra
	var look: Dictionary = app.profile.look()
	var rows: Array[String] = [
		tr("Arma: %s  •  Dano %d  •  Cratera %d") % [weapon.name, int(weapon.damage), int(weapon.radius)],
		tr("Ângulo %d° a %d°  •  POW: %s") % [int(weapon.angle[0]), int(weapon.angle[1]), weapon.pow.name],
		tr("Ataque +%d dos itens: dano x%.2f") % [int(extra.ataque), Armory.attack_scale(extra)],
		tr("Defesa +%d dos itens: dano recebido x%.2f") % [int(extra.defesa), Armory.defense_scale(extra)],
		tr("Agilidade %d: define o Delay e quem começa") % int(numbers.agilidade),
		tr("Sorte +%d dos itens: %.1f%% de acerto crítico (x1,5)") % [int(extra.sorte), Armory.crit_chance(extra) * 100.0],
		tr("Vida %d  •  Força física %d por turno") % [int(numbers.vida), int(numbers.energia)],
		"%s  •  %s" % [aura_text(tr("Arma"), int(look.weapon_level)), aura_text(tr("Roupa"), int(look.clothes_level))],
	]
	# Battle bonuses from the random attributes (0.10), summed over the equipment.
	var bonus: Dictionary = numbers.bonus
	var parts: Array[String] = []
	for key: String in ["dano", "critico", "pow", "pow_inicial", "poupar", "vida", "energia", "delay", "vento", "cura"]:
		if int(bonus.get(key, 0)) > 0:
			parts.append(Crafting.mod_text({"id": key, "value": int(bonus[key])}))
	rows.append(tr("Bônus: %s") % (" • ".join(parts) if not parts.is_empty() else tr("nenhum (use moedas no Ferreiro)")))
	for i in range(rows.size()):
		var last: bool = i == rows.size() - 1
		var row: Panel = UiKit.panel(profile_root, Rect2(52, 230 + i * 48, 556, 56 if last else 42), "dark")
		var text: Label = UiKit.label(row, rows[i], Rect2(14, 0, 534, 56 if last else 42), 15, Color.WHITE, UiKit.INK)
		if last:
			# The bonus summary wraps (up to 3 lines); the tooltip lists every bonus.
			text.max_lines_visible = 3
			text.add_theme_constant_override("line_spacing", -3)
			UiKit.wrap(text, Vector2(534, 56))
			row.tooltip_text = "\n".join(parts)
			row.mouse_filter = Control.MOUSE_FILTER_PASS

func build_history() -> void:
	UiKit.label(profile_root, tr("SUA JORNADA"), Rect2(60, 200, 485, 41), 27, Color("67452a"))
	var ratio: float = 100.0 * app.profile.victories / maxf(1, app.profile.matches)
	UiKit.label(profile_root, tr("%d partidas locais\n\n%d vitórias (%d%%)\n\n%d EXP acumulada\n\n%d méritos  •  ranking %d\n\n%d itens na mochila") % [app.profile.matches, app.profile.victories, roundi(ratio), app.profile.experience, app.profile.merits, app.profile.ranking(), app.profile.inventory.size()], Rect2(62, 250, 520, 400), 20, Color("4d382d"))

# ---------- right: inventory ----------

func all_entries() -> Array[Dictionary]:
	# Everything in the bag, in the default order ("Organizar"): weapons, gear by slot,
	# auxiliary items (worn first, then better quality and higher strengthening),
	# currencies, stones, tools and maps (highest level first).
	var gear: Array[Dictionary] = []
	for inst: Dictionary in app.profile.inventory:
		gear.append({"key": "uid:%d" % int(inst.uid), "inst": inst, "name": Armory.item_name(inst)})
	gear.sort_custom(gear_before)
	var list: Array[Dictionary] = gear
	for def: Dictionary in Crafting.currencies():
		if app.profile.currency_count(str(def.id)) > 0:
			list.append({"key": "item:" + str(def.id), "name": Crafting.currency_name(str(def.id)), "icon": str(def.icon), "count": app.profile.currency_count(str(def.id))})
	for id: String in ITEM_NAMES:
		if int(app.profile.items.get(id, 0)) > 0:
			list.append({"key": "item:" + id, "name": tr(ITEM_NAMES[id][0]), "icon": ITEM_NAMES[id][1], "count": int(app.profile.items[id])})
	for i in range(app.profile.tools.size()):
		var tool_id: String = app.profile.tools[i]
		for tool: Dictionary in app.balance.tools:
			if tool_id != "" and tool.id == tool_id:
				list.append({"key": "tool:%d" % i, "name": tr(str(tool.name)), "icon": tool.icon, "count": 1})
	# Instance maps (0.9): consumed when entering an instance.
	var maps: Array[Dictionary] = app.profile.maps.duplicate()
	maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
	for item: Dictionary in maps:
		list.append({"key": "map:%d" % int(item.uid), "map": item, "name": InstanceRun.map_name(item), "icon": InstanceRun.map_icon(item), "count": 1})
	return list

func gear_before(a: Dictionary, b: Dictionary) -> bool:
	var ia: Dictionary = a.inst
	var ib: Dictionary = b.inst
	var sa: int = SLOT_ORDER.find(Armory.slot_of(str(ia.id)))
	var sb: int = SLOT_ORDER.find(Armory.slot_of(str(ib.id)))
	if sa != sb:
		return sa < sb
	var wa: bool = app.profile.is_equipped(int(ia.uid))
	var wb: bool = app.profile.is_equipped(int(ib.uid))
	if wa != wb:
		return wa
	var qa: int = int(QUALITY_RANK.get(str(ia.get("quality", "normal")), 0))
	var qb: int = int(QUALITY_RANK.get(str(ib.get("quality", "normal")), 0))
	if qa != qb:
		return qa > qb
	if int(ia.get("level", 0)) != int(ib.get("level", 0)):
		return int(ia.get("level", 0)) > int(ib.get("level", 0))
	if str(ia.id) != str(ib.id):
		return str(ia.id) < str(ib.id)
	return int(ia.uid) < int(ib.uid)

func group_of(entry: Dictionary) -> String:
	if entry.has("map"):
		return "Mapas"
	if entry.has("inst"):
		return {"weapon": "Armas", "aux": "Auxiliar", "cosmetic": "Visual"}.get(Armory.kind_of(str(entry.inst.id)), "Materiais")
	return "Materiais"

func layout() -> Array[String]:
	# The player's arrangement (profile.bag) with sold or used items left as empty cells
	# and new items put in the first empty cells, then at the end.
	var everything: Array[Dictionary] = all_entries()
	var known: Dictionary = {}
	for entry: Dictionary in everything:
		known[entry.key] = true
	var cells: Array[String] = []
	var placed: Dictionary = {}
	for key: String in app.profile.bag:
		if key != "" and known.has(key) and not placed.has(key):
			cells.append(key)
			placed[key] = true
		else:
			cells.append("")
	var gap: int = 0
	for entry: Dictionary in everything:
		if placed.has(entry.key):
			continue
		while gap < cells.size() and cells[gap] != "":
			gap += 1
		if gap < cells.size():
			cells[gap] = entry.key
		else:
			cells.append(entry.key)
		placed[entry.key] = true
	while not cells.is_empty() and cells.back() == "":
		cells.pop_back()
	return cells

func entry_map() -> Dictionary:
	var found: Dictionary = {}
	for entry: Dictionary in all_entries():
		found[entry.key] = entry
	return found

func shown_keys() -> Array[String]:
	# "Todos" keeps the empty cells; the other tabs list their items in bag order.
	var cells: Array[String] = layout()
	if category == "Todos":
		return cells
	var by_key: Dictionary = entry_map()
	var keys: Array[String] = []
	for key: String in cells:
		if key != "" and group_of(by_key[key]) == category:
			keys.append(key)
	return keys

func entries() -> Array[Dictionary]:
	var by_key: Dictionary = entry_map()
	var list: Array[Dictionary] = []
	for key: String in shown_keys():
		if key != "":
			list.append(by_key[key])
	return list

func build_inventory() -> void:
	UiKit.panel(contents, Rect2(648, 96, 608, 612), "wood")
	UiKit.panel(contents, Rect2(660, 140, 584, 554), "paper")
	for i in range(CATEGORIES.size()):
		var filter: String = CATEGORIES[i]
		var tab: Button = UiKit.button(contents, tr(filter), Rect2(662 + i * 97, 100, 94, 36), filter_items.bind(filter), "tab_active" if category == filter else "tab", 15)
		tab.name = "Tab_" + filter
	grid_root = layer()
	count_label = UiKit.label(contents, "", Rect2(684, 478, 130, 28), 15, UiKit.TEXT_DARK)
	var sort_button: Button = UiKit.button(contents, tr("ORGANIZAR"), Rect2(820, 478, 130, 28), sort_bag, "tab", 14)
	sort_button.name = "SortBag"
	sort_button.tooltip_text = tr("Arruma a mochila por tipo, qualidade e fortalecimento.")
	var back: Button = UiKit.button(contents, "<", Rect2(1080, 478, 36, 28), turn_page.bind(-1), "tab", 14)
	page_label = UiKit.label(contents, "", Rect2(1116, 478, 70, 28), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var forward: Button = UiKit.button(contents, ">", Rect2(1186, 478, 36, 28), turn_page.bind(1), "tab", 14)
	# Holding an item over an arrow turns the page (see _process); dropping there is a no-op.
	arrow_rects = [back.get_rect(), forward.get_rect()]
	for arrow: Button in [back, forward]:
		arrow.set_drag_forwarding(Callable(), func(_at: Vector2, data: Variant) -> bool: return data is Dictionary and (data as Dictionary).has("bag_key"), func(_at: Vector2, _data: Variant) -> void: pass)
	var info: Panel = UiKit.panel(contents, Rect2(670, 512, 564, 136), "dark")
	selected_icon = BagSlot.new()
	selected_icon.interactive = false
	selected_icon.position = Vector2(10, 10)
	selected_icon.size = Vector2(72, 72)
	info.add_child(selected_icon)
	selected_label = RichTextLabel.new()
	selected_label.bbcode_enabled = true
	selected_label.scroll_active = false
	selected_label.position = Vector2(92, 4)
	selected_label.size = Vector2(466, 128)
	selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_label.add_theme_font_override("normal_font", UiKit.font())
	selected_label.add_theme_font_size_override("normal_font_size", UiKit.fs(14))
	selected_label.add_theme_color_override("default_color", Color.WHITE)
	selected_label.add_theme_constant_override("line_separation", -2)
	info.add_child(selected_label)
	equip_button = UiKit.button(contents, tr("EQUIPAR"), Rect2(670, 654, 180, 40), equip_selected, "button_green")
	sell_button = UiKit.button(contents, tr("VENDER"), Rect2(858, 654, 130, 40), sell_selected)
	UiKit.button(contents, tr("FORTALECER"), Rect2(996, 654, 238, 40), open_smith, "button_blue")
	refresh_grid()

func refresh_grid() -> void:
	if not is_instance_valid(grid_root):
		return
	for child in grid_root.get_children():
		grid_root.remove_child(child)
		child.queue_free()
	cells_shown.clear()
	var keys: Array[String] = shown_keys()
	var by_key: Dictionary = entry_map()
	var items: int = keys.filter(func(key: String) -> bool: return key != "").size()
	# "Todos" always leaves room for one more empty cell to drop into.
	pages = maxi(1, ceili((keys.size() + (1 if category == "Todos" else 0)) / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = page * PER_PAGE + i
		var rect: Rect2 = Rect2(GRID + Vector2((i % COLUMNS) * (CELL + GAP), (i / COLUMNS) * (CELL + GAP)), Vector2(CELL, CELL))
		var key: String = keys[index] if index < keys.size() else ""
		var slot: BagSlot = BagSlot.create(grid_root, rect)
		slot.cell = index
		slot.name = ("Item_" + key.replace(":", "_")) if key != "" else "Cell_%d" % index
		var entry: Dictionary = by_key.get(key, {}) if key != "" else {}
		slot.show_entry(entry)
		slot.equipped = entry.has("inst") and app.profile.is_equipped(int(entry.inst.uid))
		slot.selected = key != "" and key == selected
		slot.accepts = func(target: BagSlot, data: Dictionary) -> bool: return str(data.bag_key) != target.key
		slot.clicked.connect(func(target: BagSlot) -> void:
			if target.key != "":
				select_item(target.key))
		slot.activated.connect(func(target: BagSlot) -> void:
			if target.key != "":
				toggle_key(target.key))
		slot.hovered.connect(on_hover)
		slot.dropped.connect(drop_on_cell)
		cells_shown.append(slot)
	count_label.text = tr("%d itens") % items
	page_label.text = "%d/%d" % [page + 1, pages]
	refresh_selection()

func describe(inst: Dictionary) -> String:
	var id: String = str(inst.id)
	var color: String = Armory.quality_color(inst).to_html(false)
	var text: String = "[color=#%s]%s[/color]" % [color, Armory.item_name(inst)]
	var attrs: Dictionary = Armory.item_attrs(inst)
	var parts: Array[String] = []
	for key: String in Armory.ATTRS:
		if int(attrs[key]) > 0:
			parts.append("%s +%d" % [Armory.attr_name(key), int(attrs[key])])
	match Armory.kind_of(id):
		"weapon":
			var weapon: Dictionary = Armory.build_weapon(inst)
			text += tr("  [color=#ffd46b]%s[/color]\nDano %d • Cratera %d • Ângulo %d°–%d° • POW: %s\n%s") % [Armory.quality_label(str(inst.quality)), int(weapon.damage), int(weapon.radius), int(weapon.angle[0]), int(weapon.angle[1]), tr(str(weapon.pow.name)), " • ".join(parts)]
		"aux":
			text += "\n%s" % tr(str(Armory.aux_def(id).desc))
		"cosmetic":
			var def: Dictionary = Armory.cosmetic_def(id)
			var gender: String = {"m": tr(" (masculino)"), "f": tr(" (feminino)")}.get(str(def.gender), "")
			var quality: String = "" if str(inst.get("quality", "normal")) == "normal" else " %s" % Armory.quality_label(str(inst.quality))
			text += "  [color=#ffd46b]%s%s%s[/color]\n%s" % [Armory.slot_name(str(def.slot)), quality, gender, " • ".join(parts)]
	if Crafting.can_have_mods(id):
		# Random bonuses (0.10) with their tier, the item level and the trade flags.
		var facts: Array[String] = [tr("Nível do item %d") % Crafting.item_level(inst)]
		if bool(inst.get("mirrored", false)):
			facts.append(tr("Espelhado"))
		elif bool(inst.get("bound", false)):
			facts.append(tr("Vinculado"))
		text += "\n[color=#c8b8a0]%s[/color]" % " • ".join(facts)
		var lines: Array[String] = Crafting.describe(inst)
		if not lines.is_empty():
			text += "\n[color=#9ae8ff]%s[/color]" % "  •  ".join(lines)
	return text

func refresh_selection() -> void:
	if not is_instance_valid(selected_label):
		return
	selected_label.text = tr("Selecione um item da mochila ou um espaço de equipamento.")
	selected_icon.equipped = false
	selected_icon.show_entry({})
	equip_button.disabled = true
	equip_button.text = tr("EQUIPAR")
	sell_button.disabled = true
	if selected.begins_with("slot:"):
		selected_label.text = tr("%s: nenhum item equipado.") % Armory.slot_name(selected.substr(5))
		return
	var by_key: Dictionary = entry_map()
	var entry: Dictionary = by_key.get(selected, {})
	if entry.is_empty():
		return
	selected_icon.show_entry(entry)
	if entry.has("inst"):
		var inst: Dictionary = entry.inst
		selected_label.text = describe(inst)
		var equipped: bool = app.profile.is_equipped(int(inst.uid))
		selected_icon.equipped = equipped
		equip_button.disabled = equipped and Armory.slot_of(str(inst.id)) == "arma"
		equip_button.text = tr("REMOVER") if equipped else tr("EQUIPAR")
		sell_button.disabled = equipped
	elif entry.has("map"):
		var item: Dictionary = entry.map
		var lines: Array[String] = InstanceRun.describe_map(item)
		selected_label.text = "[color=#%s]%s[/color]  [color=#ffd46b]%s[/color]\n%s" % [InstanceRun.quality_color(str(item.quality)).to_html(false), entry.name, InstanceRun.quality_label(str(item.quality)), " • ".join(lines) if not lines.is_empty() else tr("Sem atributos. Coloque no espaço de mapa da sala da instância.")]
	else:
		selected_label.text = "%s  x%d" % [entry.name, int(entry.get("count", 1))]
		var id: String = selected.substr(5)
		var stone: Dictionary = Armory.stone_def(id)
		if Crafting.is_currency(id) and selected.begins_with("item:"):
			selected_label.text += "\n%s\n%s" % [Crafting.currency_desc(id), tr("Use no Ferreiro, aba Moedas, em equipamentos e mapas.")]
		elif not stone.is_empty():
			selected_label.text += tr("\nVale %d ponto(s) de fortalecimento no Ferreiro.") % int(stone.points)
		elif selected.begins_with("tool:"):
			selected_label.text += tr("\nFerramenta de batalha (Z/X/C).")

# ---------- selection, equipment and dragging ----------

func select_item(key: String) -> void:
	selected = key
	var every: Array = cells_shown.duplicate()
	every.append_array(equip_cells.values())
	for slot: BagSlot in every:
		if is_instance_valid(slot):
			var slot_key: String = slot.key if slot.key != "" or slot.equip_slot == "" else "slot:" + slot.equip_slot
			var mark: bool = slot_key != "" and slot_key == key
			if slot.selected != mark:
				slot.selected = mark
				slot.redraw()
	refresh_selection()

func instance_for(key: String) -> Dictionary:
	return app.profile.find_instance(key.substr(4).to_int()) if key.begins_with("uid:") else {}

func can_equip_key(key: String, slot: String = "") -> bool:
	var inst: Dictionary = instance_for(key)
	if inst.is_empty() or app.profile.is_equipped(int(inst.uid)):
		return false
	var wanted: String = Armory.slot_of(str(inst.id))
	return wanted != "" and (slot == "" or slot == wanted)

func equip_key(key: String) -> void:
	if can_equip_key(key):
		select_item(key)
		equip_selected()

func toggle_key(key: String) -> void:
	if key.begins_with("uid:"):
		select_item(key)
		equip_selected()

func drop_on_cell(target: BagSlot, data: Dictionary) -> void:
	var key: String = str(data.bag_key)
	# The cells are rebuilt below (equipping rebuilds the page): keep what we need.
	var target_cell: int = target.cell
	var target_key: String = target.key
	if str(data.equip_slot) != "":
		# Out of an equipment slot: take it off (it is already in the bag).
		select_item(key)
		var inst: Dictionary = instance_for(key)
		if not inst.is_empty() and app.profile.is_equipped(int(inst.uid)):
			await equip_selected()
		if not is_instance_valid(grid_root):
			return
	var cells: Array[String] = layout()
	var from: int = cells.find(key)
	if from < 0:
		return
	var to: int = target_cell
	if category != "Todos":
		# Filtered tabs: swap with the item dropped on, or go after the tab's last item.
		if target_key != "":
			to = cells.find(target_key)
		else:
			var shown: Array[String] = shown_keys()
			to = cells.find(shown.back()) + 1 if not shown.is_empty() else 0
			while to < cells.size() and cells[to] != "":
				to += 1
	if to < 0 or to == from:
		return
	while cells.size() <= to:
		cells.append("")
	var other: String = cells[to]
	cells[to] = key
	cells[from] = other
	save_layout(cells)
	app.audio.play("ui_click")

func save_layout(cells: Array[String]) -> void:
	# The new order shows at once; online the server keeps it in the profile.
	while not cells.is_empty() and cells.back() == "":
		cells.pop_back()
	app.profile.bag = cells.duplicate()
	refresh_grid.call_deferred()
	var outcome: Dictionary = await app.do_op("bag_layout", [cells])
	if outcome.error != "" and is_instance_valid(grid_root):
		refresh_grid()

func sort_bag() -> void:
	app.profile.bag.clear()
	page = 0
	refresh_grid()
	app.audio.play("ui_confirm")
	await app.do_op("bag_layout", [[]])

func on_hover(slot: BagSlot, inside: bool) -> void:
	if inside and slot.key != "":
		hover_slot = slot
		hover_time = 0.0
	elif hover_slot == slot:
		hover_slot = null
		if is_instance_valid(tooltip):
			tooltip.hide_card()

func _process(delta: float) -> void:
	if not is_instance_valid(tooltip):
		return
	var dragging: bool = get_viewport().gui_is_dragging()
	if dragging or not is_instance_valid(hover_slot) or not hover_slot.is_visible_in_tree():
		tooltip.hide_card()
		if not is_instance_valid(hover_slot):
			hover_slot = null
	elif not tooltip.visible:
		hover_time += delta
		if hover_time > 0.12:
			var entry: Dictionary = entry_map().get(hover_slot.key, {})
			if not entry.is_empty():
				tooltip.show_entry(entry, app.profile, app.balance)
	# Holding a dragged item over a page arrow turns the page.
	var step: int = 0
	if dragging and arrow_rects.size() == 2:
		var mouse: Vector2 = get_global_mouse_position()
		step = -1 if arrow_rects[0].has_point(mouse) else (1 if arrow_rects[1].has_point(mouse) else 0)
	if step == 0:
		flip_hold = 0.0
	else:
		flip_hold += delta
		if flip_hold > 0.5:
			flip_hold = 0.0
			turn_page(step)

func turn_page(step: int) -> void:
	var before: int = page
	page = clampi(page + step, 0, pages - 1)
	if page != before:
		refresh_grid()

func equip_selected() -> void:
	if not selected.begins_with("uid:"):
		return
	var uid: int = selected.substr(4).to_int()
	var message: String = (await app.do_op("toggle_equip", [uid])).error
	if message != "":
		UiKit.notice(self, tr("MOCHILA"), message)
		return
	app.audio.play("ui_click")
	build()

func sell_selected() -> void:
	if not selected.begins_with("uid:"):
		return
	var outcome: Dictionary = await app.do_op("sell", [selected.substr(4).to_int()])
	if outcome.error == "":
		app.audio.play("ui_coin")
		selected = ""
		build()

func filter_items(filter: String) -> void:
	category = filter
	page = 0
	build()

func select_tab(value: String) -> void:
	tab_name = value
	build()

func open_smith() -> void:
	var smith: SmithScreen = SmithScreen.new()
	smith.app = app
	if selected.begins_with("uid:"):
		smith.selected_uid = selected.substr(4).to_int()
	smith.closed.connect(build)
	add_child(smith)

func open_shop() -> void:
	var shop: ShopScreen = ShopScreen.new()
	shop.app = app
	shop.closed.connect(build)
	add_child(shop)

func open_coupon() -> void:
	CouponDialog.open(self, app, build)
