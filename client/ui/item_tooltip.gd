class_name ItemTooltip
extends PanelContainer

# The card that follows the mouse over an item (0.15): icon and name in the quality's
# colour, the kind and strengthening, base numbers (weapon damage, crater, angles, POW),
# the four attributes with what they change against the item worn in that slot, the
# random bonuses with their tiers, item level, trade flags and sale value. Maps list
# threats and rewards; currencies, stones and tools say what they are for.

const WIDTH: float = 320.0
const ICONS: Dictionary = {"ataque": "res://assets/ui/stats/ataque.png", "defesa": "res://assets/ui/stats/defesa.png", "agilidade": "res://assets/ui/stats/agilidade.png", "sorte": "res://assets/ui/stats/sorte.png"}
const UP: String = "7dff6a"
const DOWN: String = "ff7a6a"
const MUTED: String = "b8a58a"
const BONUS: String = "9ae8ff"

var box: VBoxContainer
var accent: Color = Color("d9a45a")

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	visible = false
	add_theme_stylebox_override("panel", UiKit.frame("tooltip"))
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

func _process(_delta: float) -> void:
	if visible:
		follow()

func follow() -> void:
	# Beside the mouse, flipped to the other side near the screen's edges.
	var mouse: Vector2 = get_global_mouse_position()
	var spot: Vector2 = mouse + Vector2(22, 16)
	if spot.x + size.x > 1272.0:
		spot.x = mouse.x - size.x - 16.0
	if spot.y + size.y > 712.0:
		spot.y = maxf(8.0, 712.0 - size.y)
	global_position = spot.round()

func hide_card() -> void:
	visible = false

func show_entry(entry: Dictionary, profile: PlayerProfile, balance: Dictionary) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	accent = Color("d9a45a")
	if entry.has("inst"):
		build_item(entry.inst, profile)
	elif entry.has("map"):
		build_map(entry)
	else:
		build_material(entry, profile, balance)
	visible = true
	reset_size()
	follow()

# ---------- pieces ----------

func header(entry: Dictionary, title: String, title_color: Color, subtitle: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(60, 60)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	var slot: BagSlot = BagSlot.new()
	slot.interactive = false
	slot.size = Vector2(60, 60)
	holder.add_child(slot)
	slot.show_entry(entry)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.custom_minimum_size = Vector2(WIDTH - 70, 60)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var name_label: Label = UiKit.label(texts, title, Rect2(), 18, title_color, UiKit.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(WIDTH - 70, 0)
	if subtitle != "":
		var sub: RichTextLabel = rich(subtitle, WIDTH - 70)
		texts.add_child(sub)
	divider(title_color)

func divider(color: Color = Color.TRANSPARENT) -> void:
	var line: ColorRect = ColorRect.new()
	line.custom_minimum_size = Vector2(WIDTH, 2)
	line.color = Color(color.r, color.g, color.b, 0.55) if color.a > 0.0 else Color(0.85, 0.64, 0.35, 0.35)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

func rich(text: String, width: float = WIDTH) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", UiKit.font())
	label.add_theme_font_override("bold_font", UiKit.font())
	label.add_theme_font_size_override("normal_font_size", UiKit.fs(14))
	label.add_theme_font_size_override("bold_font_size", UiKit.fs(14))
	label.add_theme_color_override("default_color", UiKit.CREAM)
	label.add_theme_constant_override("line_separation", 1)
	label.text = text
	return label

func section(text: String) -> void:
	if text.strip_edges() != "":
		box.add_child(rich(text))

static func paint(text: String, color: Variant) -> String:
	var hex: String = color.to_html(false) if color is Color else str(color)
	return "[color=#%s]%s[/color]" % [hex, text]

static func delta(value: int, worn: int) -> String:
	if value == worn:
		return ""
	var diff: int = value - worn
	return " " + paint("(%s%d)" % ["+" if diff > 0 else "", diff], UP if diff > 0 else DOWN)

# ---------- equipment ----------

func build_item(inst: Dictionary, profile: PlayerProfile) -> void:
	var id: String = str(inst.id)
	var kind: String = Armory.kind_of(id)
	var quality: String = str(inst.get("quality", "normal"))
	var color: Color = Armory.quality_color(inst)
	var slot: String = Armory.slot_of(id)
	var level: int = int(inst.get("level", 0))
	var equipped: bool = profile.is_equipped(int(inst.get("uid", -1)))
	# Compared with what the player wears in the same slot (nothing to compare when worn).
	var worn: Dictionary = {} if equipped else profile.equipped_instance(slot)
	var kind_text: String = Armory.slot_name(slot)
	if kind == "cosmetic":
		var gender: String = str(Armory.cosmetic_def(id).get("gender", "u"))
		kind_text += {"m": tr(" (masculino)"), "f": tr(" (feminino)")}.get(gender, "")
	var subtitle: String = paint(Armory.quality_label(quality), color) + "  •  " + kind_text
	if level > 0:
		subtitle += "  •  " + paint("+%d" % level, Armory.aura_color(level).lightened(0.3))
	header({"key": "tip", "inst": inst}, Armory.item_name(inst), color, subtitle)
	accent = color
	var lines: Array[String] = []
	if kind == "weapon":
		var weapon: Dictionary = Armory.build_weapon(inst)
		var worn_damage: int = int(Armory.build_weapon(worn).damage) if not worn.is_empty() else int(weapon.damage)
		lines.append(tr("Dano %s") % paint(str(int(weapon.damage)), "ffd46b") + delta(int(weapon.damage), worn_damage) + "   " + tr("Cratera %d") % int(weapon.radius))
		lines.append(tr("Ângulo %d°–%d°") % [int(weapon.angle[0]), int(weapon.angle[1])])
		lines.append(tr("POW: %s") % paint(tr(str(weapon.pow.name)), "ffb347"))
	elif kind == "aux":
		var def: Dictionary = Armory.aux_def(id)
		lines.append(tr(str(def.get("desc", ""))))
		if int(def.get("uses", 0)) > 0:
			lines.append(tr("Usos por batalha: %d") % int(def.uses))
	section("\n".join(lines))
	# The four attributes, with the change against the item worn in this slot.
	var attrs: Dictionary = Armory.item_attrs(inst)
	var worn_attrs: Dictionary = Armory.item_attrs(worn) if not worn.is_empty() else attrs
	var rows: Array[String] = []
	for key: String in Armory.ATTRS:
		if int(attrs[key]) == 0 and int(worn_attrs[key]) == 0:
			continue
		rows.append("[img=16x16]%s[/img] %s %s%s" % [ICONS[key], Armory.attr_name(key), paint("+%d" % int(attrs[key]), "ffffff"), delta(int(attrs[key]), int(worn_attrs[key]))])
	if not rows.is_empty():
		divider()
		section("\n".join(rows))
	if level > 0 and Armory.can_strengthen(id):
		var aura: Dictionary = Armory.aura(level)
		var aura_name: String = tr(str(aura.name)) if not aura.is_empty() else tr("sem aura")
		section(paint(tr("Fortalecido +%d  •  %s") % [level, aura_name], Armory.aura_color(level).lightened(0.35)))
	if Crafting.can_have_mods(id):
		var mods: Array[String] = Crafting.describe(inst)
		divider()
		if mods.is_empty():
			section(paint(tr("Sem bônus (use moedas no Ferreiro)"), MUTED))
		else:
			section(paint(tr("BÔNUS"), "ffd46b") + "\n" + "\n".join(mods.map(func(line: String) -> String: return paint(line, BONUS))))
	divider()
	var facts: Array[String] = []
	if Crafting.can_have_mods(id):
		facts.append(tr("Nível do item %d") % Crafting.item_level(inst))
	if bool(inst.get("mirrored", false)):
		facts.append(tr("Espelhado"))
	elif bool(inst.get("bound", false)):
		facts.append(tr("Vinculado"))
	var footer: Array[String] = []
	if not facts.is_empty():
		footer.append(paint(" • ".join(facts), MUTED))
	if equipped:
		footer.append(paint(tr("Equipado"), UP))
	else:
		footer.append(paint(tr("Vende por %d moedas") % PlayerProfile.sell_value(inst), "ffd46b"))
		footer.append(paint(tr("Clique duplo: equipar  •  Arraste: organizar"), MUTED))
	section("\n".join(footer))

# ---------- maps, currencies, stones, tools ----------

func build_map(entry: Dictionary) -> void:
	var item: Dictionary = entry.map
	var quality: String = str(item.get("quality", "normal"))
	var color: Color = InstanceRun.quality_color(quality)
	header(entry, str(entry.name), color, paint(InstanceRun.quality_label(quality), color) + "  •  " + tr("Mapa de instância"))
	var threats: Array[String] = []
	var rewards: Array[String] = []
	for mod: Dictionary in item.get("mods", []):
		var line: String = InstanceRun.mod_text(mod)
		if str(InstanceRun.mod_def(str(mod.id)).get("kind", "")) == "threat":
			threats.append(paint(line, DOWN))
		else:
			rewards.append(paint(line, UP))
	if threats.is_empty() and rewards.is_empty():
		section(paint(tr("Sem atributos."), MUTED))
	else:
		section("\n".join(threats + rewards))
	divider()
	section(paint(tr("Coloque no espaço de mapa da sala da instância. É consumido ao entrar."), MUTED))

func build_material(entry: Dictionary, profile: PlayerProfile, balance: Dictionary) -> void:
	var key: String = str(entry.get("key", ""))
	var id: String = key.substr(key.find(":") + 1)
	var subtitle: String = paint("x%d" % int(entry.get("count", 1)), "ffffff")
	var lines: Array[String] = []
	if key.begins_with("tool:"):
		subtitle = tr("Ferramenta de batalha (Z/X/C)")
		var tool_id: String = profile.tools[int(id)] if int(id) < profile.tools.size() else ""
		for tool: Dictionary in balance.get("tools", []):
			if tool.id == tool_id:
				lines.append(tr(str(tool.get("desc", ""))))
	elif Crafting.is_currency(id):
		subtitle += "  •  " + tr("Moeda")
		lines.append(Crafting.currency_desc(id))
		lines.append(paint(tr("Use no Ferreiro, aba Moedas, em equipamentos e mapas."), MUTED))
	elif not Armory.stone_def(id).is_empty():
		lines.append(tr("Vale %d ponto(s) de fortalecimento no Ferreiro.") % int(Armory.stone_def(id).points))
	header(entry, str(entry.get("name", id)), Color("ffe6a0"), subtitle)
	section("\n".join(lines))
