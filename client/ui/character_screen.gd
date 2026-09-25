class_name CharacterScreen
extends Control

# Mochila / Informações Pessoais, like the DDTank profile window: equipment slots around
# the character (who wears everything equipped, with auras), attributes below and the
# inventory on the right. Single account identity: there is intentionally no roster.

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
# Five rows leave room for the item's random bonuses (0.10) in the info box.
const PER_PAGE: int = 35

var app: Node
var contents: Control
var category: String = "Todos"
var selected: String = ""
var selected_label: RichTextLabel
var equip_button: Button
var sell_button: Button
var tab_name: String = "Perfil"
var page: int = 0

func _ready() -> void:
	size = Vector2(1280, 720)
	selected = "uid:%d" % int(app.profile.equipped.get("arma", -1))
	build()

func build() -> void:
	if is_instance_valid(contents):
		remove_child(contents)
		contents.queue_free()
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
	build_profile()
	build_inventory()

# ---------- left: Informações Pessoais ----------

func build_profile() -> void:
	UiKit.panel(contents, Rect2(24, 96, 612, 612), "wood")
	UiKit.label(contents, tr("Informações Pessoais"), Rect2(44, 100, 360, 36), 24, Color("fff0c7"), UiKit.INK)
	for i in range(3):
		var name_text: String = ["Perfil", "Atributos", "Histórico"][i]  # i18n
		UiKit.button(contents, tr(name_text), Rect2(334 + i * 96, 102, 92, 32), select_tab.bind(name_text), "tab_active" if tab_name == name_text else "tab", 14)
	UiKit.panel(contents, Rect2(38, 140, 584, 554), "paper")
	var head: Panel = UiKit.panel(contents, Rect2(48, 148, 564, 40), "dark")
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
	var avatar: AvatarView = AvatarView.create(contents, app.profile.look(), Rect2(132, 196, 396, 300))
	avatar.name = "Avatar"
	for i in range(LEFT_SLOTS.size()):
		equipment_slot(LEFT_SLOTS[i], Rect2(52, 198 + i * 74, 66, 66))
	for i in range(RIGHT_SLOTS.size()):
		equipment_slot(RIGHT_SLOTS[i], Rect2(542, 198 + i * 74, 66, 66))
	var pet: Panel = UiKit.panel(contents, Rect2(542, 420, 66, 66), "slot_light")
	UiKit.art(pet, "res://assets/pets/fenix_dourada.png", Rect2(6, 4, 54, 54))
	UiKit.label(pet, tr("Mascote"), Rect2(-8, 50, 82, 16), 11, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(contents, tr("EXP"), Rect2(52, 500, 56, 22), 16, Color("563b29"))
	var exp_bar: ProgressBar = UiKit.bar(contents, Rect2(104, 503, 504, 16), Color("d99932"))
	exp_bar.value = app.profile.level_progress() * 100.0
	var next: int = PlayerProfile.exp_for_level(app.profile.level() + 1)
	UiKit.label(contents, "%.1f%%  •  %d / %d" % [app.profile.level_progress() * 100.0, app.profile.experience, next], Rect2(104, 518, 504, 20), 13, Color("634c39"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	build_stats(Rect2(48, 540, 564, 118))
	var look: Dictionary = app.profile.look()
	UiKit.label(contents, "%s  •  %s" % [aura_text(tr("Arma"), int(look.weapon_level)), aura_text(tr("Roupa"), int(look.clothes_level))], Rect2(48, 662, 564, 26), 14, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)

func aura_text(label_text: String, level: int) -> String:
	var entry: Dictionary = Armory.aura(level)
	return "%s: %s" % [label_text, "%s (+%d)" % [tr(str(entry.name)), level] if not entry.is_empty() else tr("sem aura")]

func equipment_slot(slot: String, rect: Rect2) -> void:
	var inst: Dictionary = app.profile.equipped_instance(slot)
	var key: String = "uid:%d" % int(inst.get("uid", -1)) if not inst.is_empty() else "slot:" + slot
	var button: Button = UiKit.button(contents, "", rect, select_item.bind(key), "slot_light" if selected != key else "card_hover")
	button.name = "Equip_" + slot
	button.tooltip_text = Armory.slot_name(slot)
	if inst.is_empty():
		UiKit.label(button, Armory.slot_name(slot), Rect2(0, 0, rect.size.x, rect.size.y), 13, Color("a8906c"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	item_art(button, inst, Rect2(5, 5, rect.size.x - 10, rect.size.y - 10))

func item_art(parent: Control, inst: Dictionary, rect: Rect2) -> void:
	var picture: TextureRect = UiKit.art(parent, Armory.load_icon(inst), rect)
	picture.modulate = Armory.icon_tint(inst)
	var quality: String = str(inst.get("quality", "normal"))
	if quality != "normal":
		var frame: Panel = UiKit.panel(parent, Rect2(rect.position - Vector2(3, 3), rect.size + Vector2(6, 6)), Color(0, 0, 0, 0), Armory.quality_color(inst))
		frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0), Armory.quality_color(inst), 3))
	if int(inst.get("level", 0)) > 0:
		var color: Color = Armory.aura_color(int(inst.level)).lightened(0.3)
		UiKit.label(parent, "+%d" % int(inst.level), Rect2(rect.position.x - 2, rect.position.y - 4, 40, 20), 14, color, UiKit.INK)

func build_stats(rect: Rect2) -> void:
	var numbers: Dictionary = app.profile.stats(app.balance)
	var box: Panel = UiKit.panel(contents, rect, "dark")
	var left: Array = [["Ataque", "ataque"], ["Agilidade", "agilidade"], ["Defesa", "defesa"], ["Sorte", "sorte"]]  # i18n
	for i in range(4):
		var x: float = 10 + (i % 2) * 150
		var y: float = 10 + (i / 2) * 52
		UiKit.label(box, tr(left[i][0]), Rect2(x, y, 76, 40), 15, Color("ffe6a0"), UiKit.INK)
		var value: Panel = UiKit.panel(box, Rect2(x + 74, y + 6, 66, 30), Color("fff4d6"), Color("7a5230"))
		UiKit.label(value, str(numbers[left[i][1]]), Rect2(0, 0, 66, 30), 16, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var right: Array = [["Dano", "dano", Color("ff9a2a")], ["Proteção", "protecao", Color("3a8bff")], ["Vida", "vida", Color("e0302a")], ["Força física", "energia", Color("5cc83a")]]  # i18n
	for i in range(4):
		var y: float = 6 + i * 27
		UiKit.label(box, tr(right[i][0]), Rect2(312, y, 100, 24), 14, Color("ffe6a0"), UiKit.INK)
		var bar: Panel = UiKit.panel(box, Rect2(412, y + 2, 142, 22), right[i][2], right[i][2].lightened(0.4))
		UiKit.label(bar, str(numbers[right[i][1]]), Rect2(0, -1, 142, 22), 15, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func build_attributes() -> void:
	var numbers: Dictionary = app.profile.stats(app.balance)
	var weapon: Dictionary = numbers.weapon
	UiKit.label(contents, tr("ATRIBUTOS DE COMBATE"), Rect2(60, 196, 540, 34), 22, Color("624128"))
	var extra: Dictionary = numbers.extra
	var rows: Array[String] = [
		tr("Arma: %s  •  Dano %d  •  Cratera %d") % [weapon.name, int(weapon.damage), int(weapon.radius)],
		tr("Ângulo %d° a %d°  •  POW: %s") % [int(weapon.angle[0]), int(weapon.angle[1]), weapon.pow.name],
		tr("Ataque +%d dos itens: dano x%.2f") % [int(extra.ataque), Armory.attack_scale(extra)],
		tr("Defesa +%d dos itens: dano recebido x%.2f") % [int(extra.defesa), Armory.defense_scale(extra)],
		tr("Agilidade %d: define o Delay e quem começa") % int(numbers.agilidade),
		tr("Sorte +%d dos itens: %.1f%% de acerto crítico (x1,5)") % [int(extra.sorte), Armory.crit_chance(extra) * 100.0],
		tr("Vida %d  •  Força física %d por turno") % [int(numbers.vida), int(numbers.energia)],
		tr("Avião de papel: %d de energia, recarga %d turnos") % [int(app.balance.fly.energy), int(app.balance.fly.cooldown)],
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
		var row: Panel = UiKit.panel(contents, Rect2(52, 236 + i * 50, 556, 56 if last else 44), "dark")
		var text: Label = UiKit.label(row, rows[i], Rect2(14, 0, 534, 56 if last else 44), 15, Color.WHITE, UiKit.INK)
		if last:
			# The bonus summary wraps (up to 3 lines); the tooltip lists every bonus.
			text.max_lines_visible = 3
			text.add_theme_constant_override("line_spacing", -3)
			UiKit.wrap(text, Vector2(534, 56))
			row.tooltip_text = "\n".join(parts)
			row.mouse_filter = Control.MOUSE_FILTER_PASS

func build_history() -> void:
	UiKit.label(contents, tr("SUA JORNADA"), Rect2(60, 200, 485, 41), 27, Color("67452a"))
	var ratio: float = 100.0 * app.profile.victories / maxf(1, app.profile.matches)
	UiKit.label(contents, tr("%d partidas locais\n\n%d vitórias (%d%%)\n\n%d EXP acumulada\n\n%d méritos  •  ranking %d\n\n%d itens na mochila") % [app.profile.matches, app.profile.victories, roundi(ratio), app.profile.experience, app.profile.merits, app.profile.ranking(), app.profile.inventory.size()], Rect2(62, 250, 520, 400), 20, Color("4d382d"))

# ---------- right: inventory ----------

func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for inst: Dictionary in app.profile.inventory:
		var kind: String = Armory.kind_of(str(inst.id))
		var group: String = {"weapon": "Armas", "aux": "Auxiliar", "cosmetic": "Visual"}.get(kind, "Materiais")
		if category == "Todos" or category == group:
			list.append({"key": "uid:%d" % int(inst.uid), "inst": inst, "name": Armory.item_name(inst), "sort": group + str(inst.id)})
	if category in ["Todos", "Materiais"]:
		# Currencies (0.10) first, in the order of the table, then stones and crystals.
		for def: Dictionary in Crafting.currencies():
			if app.profile.currency_count(str(def.id)) > 0:
				list.append({"key": "item:" + str(def.id), "name": Crafting.currency_name(str(def.id)), "icon": str(def.icon), "count": app.profile.currency_count(str(def.id))})
		for id: String in app.profile.items:
			if int(app.profile.items[id]) > 0 and ITEM_NAMES.has(id):
				list.append({"key": "item:" + id, "name": tr(ITEM_NAMES[id][0]), "icon": ITEM_NAMES[id][1], "count": int(app.profile.items[id]), "sort": "z" + id})
		for tool_id in app.profile.tools:
			for tool: Dictionary in app.balance.tools:
				if tool.id == tool_id:
					list.append({"key": "tool:" + tool_id, "name": tr(str(tool.name)), "icon": tool.icon, "count": 1, "sort": "zz" + tool_id})
	if category in ["Todos", "Mapas"]:
		# Instance maps (0.9): consumed when entering an instance, highest level first.
		var maps: Array[Dictionary] = app.profile.maps.duplicate()
		maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
		for item: Dictionary in maps:
			list.append({"key": "map:%d" % int(item.uid), "map": item, "name": InstanceRun.map_name(item), "icon": InstanceRun.map_icon(item), "count": 1})
	return list

func build_inventory() -> void:
	UiKit.panel(contents, Rect2(648, 96, 608, 612), "wood")
	UiKit.panel(contents, Rect2(660, 140, 584, 554), "paper")
	for i in range(CATEGORIES.size()):
		var filter: String = CATEGORIES[i]
		var tab: Button = UiKit.button(contents, tr(filter), Rect2(662 + i * 97, 100, 94, 36), filter_items.bind(filter), "tab_active" if category == filter else "tab", 15)
		tab.name = "Tab_" + filter
	var list: Array[Dictionary] = entries()
	var pages: int = maxi(1, ceili(list.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = page * PER_PAGE + i
		var rect: Rect2 = Rect2(670 + (i % 7) * 82, 150 + (i / 7 as int) * 64, 76, 58)
		if index >= list.size():
			UiKit.panel(contents, rect, "slot")
			continue
		var entry: Dictionary = list[index]
		var slot: Button = UiKit.button(contents, "", rect, select_item.bind(str(entry.key)), "slot_light" if entry.key == selected else "slot")
		slot.name = "Item_" + str(entry.key).replace(":", "_")
		slot.tooltip_text = str(entry.name)
		if entry.has("inst"):
			item_art(slot, entry.inst, Rect2(14, 4, 48, 50))
			if app.profile.is_equipped(int(entry.inst.uid)):
				UiKit.label(slot, "E", Rect2(58, 36, 16, 20), 14, Color("9aff7a"), UiKit.INK)
		elif entry.has("map"):
			UiKit.art(slot, str(entry.icon), Rect2(14, 4, 48, 50))
			var tone: Color = InstanceRun.quality_color(str(entry.map.quality))
			UiKit.label(slot, str(int(entry.map.level)), Rect2(40, 34, 34, 22), 16, tone, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			UiKit.art(slot, str(entry.icon), Rect2(14, 4, 48, 50))
			if int(entry.count) > 1:
				UiKit.label(slot, str(entry.count), Rect2(30, 36, 44, 20), 14, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.button(contents, "<", Rect2(1060, 474, 40, 30), turn_page.bind(-1), "tab", 14)
	UiKit.label(contents, "%d/%d" % [page + 1, pages], Rect2(1100, 474, 90, 30), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.button(contents, ">", Rect2(1190, 474, 40, 30), turn_page.bind(1), "tab", 14)
	UiKit.label(contents, tr("%d itens") % list.size(), Rect2(672, 474, 200, 30), 15, UiKit.TEXT_DARK)
	var info: Panel = UiKit.panel(contents, Rect2(670, 508, 564, 140), "dark")
	selected_label = RichTextLabel.new()
	selected_label.bbcode_enabled = true
	selected_label.scroll_active = false
	selected_label.position = Vector2(10, 4)
	selected_label.size = Vector2(546, 134)
	selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_label.add_theme_font_override("normal_font", UiKit.font())
	selected_label.add_theme_font_size_override("normal_font_size", UiKit.fs(14))
	selected_label.add_theme_color_override("default_color", Color.WHITE)
	info.add_child(selected_label)
	equip_button = UiKit.button(contents, tr("EQUIPAR"), Rect2(670, 654, 180, 40), equip_selected, "button_green")
	sell_button = UiKit.button(contents, tr("VENDER"), Rect2(858, 654, 130, 40), sell_selected)
	UiKit.button(contents, tr("FORTALECER"), Rect2(996, 654, 238, 40), open_smith, "button_blue")
	refresh_selection(list)

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
		for line in Crafting.describe(inst):
			text += "\n[color=#9ae8ff]%s[/color]" % line
	return text

func refresh_selection(list: Array[Dictionary]) -> void:
	selected_label.text = tr("Selecione um item da mochila ou um espaço de equipamento.")
	equip_button.disabled = true
	equip_button.text = tr("EQUIPAR")
	sell_button.disabled = true
	if selected.begins_with("slot:"):
		selected_label.text = tr("%s: nenhum item equipado.") % Armory.slot_name(selected.substr(5))
		return
	if selected.begins_with("uid:"):
		var inst: Dictionary = app.profile.find_instance(selected.substr(4).to_int())
		if inst.is_empty():
			return
		selected_label.text = describe(inst)
		var equipped: bool = app.profile.is_equipped(int(inst.uid))
		equip_button.disabled = equipped and Armory.slot_of(str(inst.id)) == "arma"
		equip_button.text = tr("REMOVER") if equipped else tr("EQUIPAR")
		sell_button.disabled = equipped
		return
	for entry: Dictionary in list:
		if entry.key == selected and entry.has("map"):
			var item: Dictionary = entry.map
			var lines: Array[String] = InstanceRun.describe_map(item)
			selected_label.text = "[color=#%s]%s[/color]  [color=#ffd46b]%s[/color]\n%s" % [InstanceRun.quality_color(str(item.quality)).to_html(false), entry.name, InstanceRun.quality_label(str(item.quality)), " • ".join(lines) if not lines.is_empty() else tr("Sem atributos. Coloque no espaço de mapa da sala da instância.")]
		elif entry.key == selected:
			selected_label.text = "%s  x%d" % [entry.name, int(entry.get("count", 1))]
			var stone: Dictionary = Armory.stone_def(selected.substr(5))
			var currency: Dictionary = Crafting.currency_def(selected.substr(5))
			if not currency.is_empty():
				selected_label.text += "\n%s\n%s" % [Crafting.currency_desc(selected.substr(5)), tr("Use no Ferreiro, aba Moedas, em equipamentos e mapas.")]
			elif not stone.is_empty():
				selected_label.text += tr("\nVale %d ponto(s) de fortalecimento no Ferreiro.") % int(stone.points)
			elif selected.begins_with("tool:"):
				selected_label.text += tr("\nFerramenta de batalha (Z/X/C).")

func select_item(key: String) -> void:
	selected = key
	build()

func turn_page(step: int) -> void:
	page += step
	build()

func equip_selected() -> void:
	if not selected.begins_with("uid:"):
		return
	var uid: int = selected.substr(4).to_int()
	var inst: Dictionary = app.profile.find_instance(uid)
	var message: String = app.profile.unequip(Armory.slot_of(str(inst.id))) if app.profile.is_equipped(uid) else app.profile.equip(uid)
	if message != "":
		UiKit.notice(self, tr("MOCHILA"), message)
		return
	app.profile.save_profile()
	app.audio.play("ui_click")
	build()

func sell_selected() -> void:
	if not selected.begins_with("uid:"):
		return
	var value: int = app.profile.sell(selected.substr(4).to_int())
	if value > 0:
		app.profile.save_profile()
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
