class_name BattleHUD
extends Control

# Classic battle HUD: portrait and log (top-left), turn queue, wind, the round timer and
# PASS (top-center), minimap (top-right), skills 1–9 (right), angle dial, the plane and
# the auxiliary item (bottom-left), force gauge, Z/X/C tools, energy, life and the POW
# orb (bottom). 0.16: everything is drawn at the level of the POW cut-in with HudPaint —
# bronze frames, glass wells, glossy gauges, the cut-in's layered digits — the skill
# buttons are SkillSlot, POW is a round orb that fills (PowOrb) and the battle ends
# with a full-screen moment (BattleOutcome). 0.16: the player's status effects sit by the
# portrait (with their turns and what they do), every portrait in the turn queue shows
# its own, the seal chains the skills, and glare hides the wind.

const FORCE_STOPS: Array[Color] = [Color("fff27a"), Color("ffc02a"), Color("ff7a1a"), Color("ff2a1a")]
const TOOL_KEYS: Array[String] = ["Z", "X", "C"]

var screen: BattleScreen
var game: LocalMatch
var log_lines: Array[Dictionary] = []
var log_label: RichTextLabel
var queue_box: Control
var clock: Control
var pass_button: Button
var minimap: Control
var dial: Control
var force: Control
var gauges: Control
var rail: Control
var medallion: Control
var item_buttons: Array[SkillSlot] = []
var tool_buttons: Array[SkillSlot] = []
var fly_button: SkillSlot
var aux_button: SkillSlot
var pow_button: PowOrb
var trust_button: Button
var used_row: HBoxContainer
var status_row: HBoxContainer
var seal_layer: Control
var status_seen: String = "-"
var banner: Control
var outcome: Control
var pause_box: Control
var portraits: Dictionary = {}
var phase_label: Label
var goal_label: Label
var time: float = 0.0
# Animation state: the timer's beat and slam, the gauges' trailing values, the force
# bar's sparks, the projectiles' trails on the minimap and the "SUA VEZ!" banner.
var seen_round: int = -1
var turn_age: float = 10.0
var last_second: int = -1
var beat: float = 10.0
var ghost_life: float = -1.0
var ghost_energy: float = -1.0
var sparks: Array[Dictionary] = []
var trails: Dictionary = {}
var was_mine: bool = false
var flash_text: String = ""
var flash_sub: String = ""
var flash_color: Color = Color.WHITE
var flash_age: float = 10.0

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func layer(rect: Rect2, painter: Callable) -> Control:
	var node: Control = Control.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(painter)
	add_child(node)
	return node

func build() -> void:
	var me: TankFighter = game.local()
	# --- top-left: identity, avatar on a medallion and the battle log
	UiKit.panel(self, Rect2(4, 4, 74, 22), "mode_green")
	UiKit.label(self, me.rank_title, Rect2(4, 4, 74, 22), 12, Color("d8ffb0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(self, me.display_name, Rect2(84, 2, 260, 26), 17, Color.WHITE, UiKit.INK)
	medallion = layer(Rect2(8, 30, 120, 120), draw_medallion)
	UiKit.art(self, me.portrait(), Rect2(12, 30, 110, 118))
	status_row = HBoxContainer.new()
	status_row.position = Vector2(134, 34)
	status_row.add_theme_constant_override("separation", 4)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_row)
	log_label = RichTextLabel.new()
	log_label.position = Vector2(8, 152)
	log_label.size = Vector2(360, 116)
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.add_theme_font_override("normal_font", UiKit.reading_font())
	log_label.add_theme_font_override("bold_font", UiKit.reading_font(true))
	log_label.add_theme_font_size_override("normal_font_size", UiKit.fs(14))
	log_label.add_theme_color_override("font_outline_color", Color("140a04"))
	log_label.add_theme_constant_override("outline_size", 1)
	add_child(log_label)
	# --- top-center: turn order, wind, the round timer and PASS
	queue_box = layer(Rect2(390, 2, 500, 62), draw_queue)
	clock = layer(Rect2(556, 62, 168, 116), draw_clock)
	clock.mouse_filter = Control.MOUSE_FILTER_PASS
	clock.tooltip_text = tr("Vento e tempo do turno.")
	pass_button = UiKit.button(self, tr("PASS"), Rect2(604, 178, 72, 26), game.pass_turn, "button_blue", 15)
	pass_button.tooltip_text = tr("Passar a vez (P). Gera menos atraso.")
	# --- top-right: minimap with the map's name, the round, settings and exit
	minimap = layer(Rect2(1032, 2, 246, 160), draw_minimap)
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.gui_input.connect(minimap_input)
	minimap.tooltip_text = tr("Clique para mover a câmera. Cada marca = 1/10 de tela.")
	UiKit.icon_button(self, PixelIcons.get_icon("gear"), Rect2(1228, 7, 20, 20), screen.toggle_pause, tr("Pausa / opções (Esc)"))
	UiKit.icon_button(self, PixelIcons.get_icon("power"), Rect2(1252, 7, 20, 20), screen.toggle_pause, tr("Sair da batalha"))
	# --- right column: skills 1–9 like DDTank (+2, x3, +1, POW 50%…10%, POW máx) in a
	# bronze rail; the plane (F) and the auxiliary item (V) sit by the angle dial
	rail = layer(Rect2(1210, 172, 68, 444), draw_rail)
	for i in range(game.balance.items.size()):
		var item: Dictionary = game.balance.items[i]
		var slot: SkillSlot = SkillSlot.create(self, Rect2(1216, 178 + i * 48, 56, 46), load(str(item.icon)), str(item.key), func() -> void: game.use_item(str(item.id)))
		slot.tag = skill_tag(item)
		slot.tag_color = skill_tag_color(item)
		slot.tooltip_text = tr("%s  (tecla %s)\n%s\nEnergia: %d") % [tr(str(item.name)), item.key, tr(str(item.desc)), int(item.energy)]
		item_buttons.append(slot)
	# Sealed (0.16): chains over the skills.
	seal_layer = layer(Rect2(1210, 172, 68, 444), draw_seal)
	fly_button = SkillSlot.create(self, Rect2(142, 590, 50, 46), load("res://assets/ui/icons/plane.png"), "F", game.toggle_fly)
	fly_button.accent = Color("8af0ff")
	fly_button.tooltip_text = tr("Avião de papel (F): voe até onde o disparo cair. %d de energia.") % int(game.balance.fly.energy)
	# Item auxiliar (V): the Bálsamo heals, the shields halve the next hit.
	var aux: Dictionary = Armory.aux_def(me.aux_id)
	aux_button = SkillSlot.create(self, Rect2(142, 540, 50, 46), load(str(aux.icon)) if not aux.is_empty() else null, "V", game.use_aux)
	aux_button.tooltip_text = tr("%s (V)\n%s") % [tr(str(aux.name)), tr(str(aux.desc))] if not aux.is_empty() else tr("Sem item auxiliar. Equipe um na Mochila (Bálsamo ou escudo).")
	# --- bottom-left: trust, angle dial
	trust_button = UiKit.button(self, tr("Confiar"), Rect2(8, 546, 112, 34), toggle_trust, "button", 15)
	trust_button.tooltip_text = tr("Confiar: a IA joga os seus turnos.")
	dial = layer(Rect2(2, 584, 134, 134), draw_dial)
	# --- bottom-center: force gauge with its ruler and last-shot marker; the skills
	# used this turn above it
	force = layer(Rect2(140, 640, 692, 78), draw_force)
	used_row = HBoxContainer.new()
	used_row.position = Vector2(216, 604)
	used_row.add_theme_constant_override("separation", 6)
	used_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(used_row)
	# --- tools Z X C
	for i in range(3):
		var tool_id: String = me.tools[i] if i < me.tools.size() else ""
		var icon: Texture2D = null
		var tip: String = tr("Sem ferramenta. Compre na sala.")
		if tool_id != "":
			var tool: Dictionary = game.tool_def(tool_id)
			icon = load(str(tool.icon))
			tip = "%s (%s)\n%s" % [tr(str(tool.name)), TOOL_KEYS[i], tr(str(tool.desc))]
		var slot: SkillSlot = SkillSlot.create(self, Rect2(838 + i * 52, 660, 50, 50), icon, TOOL_KEYS[i], func() -> void: game.use_tool(i))
		slot.accent = Color("9aff7a")
		slot.tooltip_text = tip
		tool_buttons.append(slot)
	# --- energy and life gauges, POW orb (B)
	gauges = layer(Rect2(994, 628, 184, 76), draw_gauges)
	gauges.mouse_filter = Control.MOUSE_FILTER_PASS
	gauges.tooltip_text = tr("Energia: gasta com habilidades, avião e ao andar.\nVida: chegou a zero, está fora da batalha.")
	UiKit.art(gauges, "res://assets/ui/stats/energia.png", Rect2(7, 8, 18, 18))
	UiKit.art(gauges, "res://assets/ui/stats/vida.png", Rect2(7, 44, 22, 22))
	pow_button = PowOrb.create(self, Rect2(1174, 612, 104, 104), game.activate_pow)
	pow_button.tooltip_text = tr("POW (B): %s. Enche causando e recebendo dano.") % tr(str(me.weapon.get("pow", {}).get("name", "especial")))
	if game.pve and not game.phase.is_empty():
		build_phase()
	banner = layer(Rect2(Vector2.ZERO, size), draw_banner)
	refresh_log()

func build_phase() -> void:
	# Instance progress: phase x/3, its name, the map level and the phase objective.
	var box: Panel = Panel.new()
	box.name = "PhasePanel"
	box.position = Vector2(730, 66)
	box.size = Vector2(296, 64)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	box.draw.connect(func() -> void:
		var inner: Rect2 = HudPaint.frame(box, Rect2(Vector2.ZERO, box.size))
		HudPaint.well(box, inner, Color(0.03, 0.04, 0.07, 0.88), Color(0.08, 0.1, 0.16, 0.88))
		box.draw_rect(Rect2(inner.position.x + 4, 31, inner.size.x - 8, 1), Color(1.0, 0.82, 0.4, 0.3)))
	add_child(box)
	var level: int = int(game.phase.get("level", 0))
	var level_text: String = tr("Nível %d") % level if level > 0 else tr("Entrada livre")
	phase_label = UiKit.label(box, tr("Fase %d/%d  •  %s") % [int(game.phase.index) + 1, int(game.phase.count), game.phase.name], Rect2(10, 5, 278, 26), 15, Color("ffd04a"), UiKit.INK)
	phase_label.clip_text = true
	goal_label = UiKit.label(box, "", Rect2(10, 33, 190, 26), 13, Color("fff0d0"), UiKit.INK)
	UiKit.label(box, level_text, Rect2(196, 33, 92, 26), 13, Color("c99bff") if level >= 10 else Color("9adcff"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	if game.threats.get("no_plane", false):
		fly_button.tooltip_text = tr("Sem avião de papel neste mapa.")

static func skill_tag(item: Dictionary) -> String:
	# The corner text of skills 1–9: +2, x3, +1, 50%…10%, MAX (the icons carry no text).
	if item.has("extra_shots"):
		return "+%d" % int(item.extra_shots)
	if item.has("balls"):
		return "x%d" % int(item.balls)
	if item.has("damage_bonus"):
		return "%d%%" % roundi(float(item.damage_bonus) * 100.0)
	if item.get("pow_fill", false):
		return "MAX"
	return ""

static func skill_tag_color(item: Dictionary) -> Color:
	if item.has("balls"):
		return Color("b8f0ff")
	if item.has("extra_shots"):
		return Color("ffc48a")
	if item.get("pow_fill", false):
		return Color("f0c0ff")
	return Color("ffe04a")

func phase_goal() -> String:
	match str(game.phase.get("objective", "defeat")):
		"totems":
			var totems: Array[TankFighter] = game.fighters.filter(func(f: TankFighter) -> bool: return f.rank == "totem")
			var broken: int = totems.filter(func(f: TankFighter) -> bool: return f.hp <= 0).size()
			return tr("Cristais: %d/%d") % [broken, totems.size()]
		"survive":
			return tr("Sobreviva: %d/%d turnos") % [mini(game.survived, int(game.phase.turns)), int(game.phase.turns)]
	var enemies: int = game.fighters.filter(func(f: TankFighter) -> bool: return f.team != game.local().team and f.hp > 0).size()
	var waves: int = game.waves.size()
	return tr("Inimigos: %d%s") % [enemies, tr("  (+%d onda)") % waves if waves > 0 else ""]

func log_line(text: String, color: Color) -> void:
	log_lines.append({"text": text, "color": color})
	if log_lines.size() > 30:
		log_lines.remove_at(0)
	refresh_log()

func refresh_log() -> void:
	if is_instance_valid(log_label):
		var lines: PackedStringArray = PackedStringArray()
		for line: Dictionary in log_lines:
			lines.append("[color=#%s]%s[/color]" % [line.color.to_html(false), str(line.text).replace("[", "(").replace("]", ")")])
		log_label.text = "\n".join(lines)

func flash(text: String, color: Color, sub: String = "") -> void:
	flash_text = text
	flash_sub = sub
	flash_color = color
	flash_age = 0.0
	if is_instance_valid(banner):
		banner.queue_redraw()

func pow_banner(title: String, tint: Color, art_path: String = "", look: Dictionary = {}, shooter_name: String = "", weapon_name: String = "") -> void:
	var banner_node: PowBanner = PowBanner.new()
	banner_node.title = title
	banner_node.tint = tint
	banner_node.look = look
	banner_node.shooter_name = shooter_name
	banner_node.weapon_name = weapon_name
	if art_path != "":
		banner_node.art = load(art_path)
	add_child(banner_node)
	if is_instance_valid(pause_box):
		move_child(pause_box, -1)

func toggle_trust() -> void:
	game.set_auto_play(not game.auto_play)

func show_outcome(won: bool, draw: bool) -> void:
	var kind: String = "draw" if draw else ("victory" if won else "defeat")
	var text: String = tr("Ninguém venceu desta vez.")
	if kind == "victory":
		text = tr("Instância concluída!") if game.pve else tr("Sua equipe venceu a batalha!")
	elif kind == "defeat":
		text = tr("Sua equipe foi derrotada.")
	# The turn's widgets have nothing more to say: they fade under the moment.
	for node: CanvasItem in [clock, pass_button, queue_box, used_row, banner]:
		create_tween().tween_property(node, "modulate:a", 0.0, 0.25)
	outcome = BattleOutcome.create(self, kind, text)
	if is_instance_valid(pause_box):
		move_child(pause_box, -1)

func set_paused(value: bool) -> void:
	if is_instance_valid(pause_box):
		pause_box.queue_free()
	if not value:
		return
	if screen.online:
		pause_box = UiKit.modal(self, tr("OPÇÕES"), tr("Partida online: a batalha continua. Desistir entrega o seu personagem à IA e você fica sem recompensa."), Vector2(520, 300))
	else:
		pause_box = UiKit.modal(self, tr("BATALHA PAUSADA"), tr("Partida local contra IA. Desistir conta como derrota."), Vector2(520, 300))
	var rect: Rect2 = pause_box.get_meta("rect")
	var audio: GameAudio = screen.app.audio
	var music: Button = UiKit.button(pause_box, "", Rect2(rect.position.x + 60, rect.end.y - 124, 180, 40), Callable(), "button_blue", 15)
	var sfx: Button = UiKit.button(pause_box, "", Rect2(rect.end.x - 240, rect.end.y - 124, 180, 40), Callable(), "button_blue", 15)
	music.name = "MusicToggle"
	sfx.name = "SfxToggle"
	var label_audio: Callable = func() -> void:
		music.text = tr("Música: %s") % (tr("LIGADA") if audio.music_on else tr("DESLIGADA"))
		sfx.text = tr("Efeitos: %s") % (tr("LIGADOS") if audio.enabled else tr("DESLIGADOS"))
	label_audio.call()
	music.pressed.connect(func() -> void:
		audio.set_music_on(not audio.music_on)
		label_audio.call())
	sfx.pressed.connect(func() -> void:
		audio.set_sfx_on(not audio.enabled)
		label_audio.call())
	UiKit.button(pause_box, tr("CONTINUAR"), Rect2(rect.position.x + 60, rect.end.y - 64, 180, 44), screen.toggle_pause, "button_green")
	UiKit.button(pause_box, tr("DESISTIR"), Rect2(rect.end.x - 240, rect.end.y - 64, 180, 44), screen.forfeit)

# ---------- state ----------

func _process(delta: float) -> void:
	if game == null or game.fighters.is_empty() or not is_instance_valid(clock):
		return
	time += delta
	turn_age += delta
	beat += delta
	flash_age += delta
	var me: TankFighter = game.local()
	var mine: bool = game.active_id == game.local_id and game.running
	var acting: bool = game.can_act()
	if game.round_number != seen_round:
		# A new turn: the timer slams in; on the player's own turn every skill shines.
		seen_round = game.round_number
		turn_age = 0.0
		last_second = -1
	if acting and not was_mine:
		var slots: Array = item_buttons + tool_buttons + [fly_button, aux_button]
		for i in range(slots.size()):
			slots[i].play_shine(i * 0.03)
	was_mine = acting
	var second: int = maxi(0, ceili(game.remaining))
	if second != last_second:
		last_second = second
		beat = 0.0
	pass_button.disabled = not acting
	var energy: float = game.energy if mine else float(me.max_energy)
	ghost_energy = energy if ghost_energy < energy else move_toward(ghost_energy, energy, delta * maxf(40.0, (ghost_energy - energy) * 2.5))
	ghost_life = float(me.hp) if ghost_life < me.hp else move_toward(ghost_life, float(me.hp), delta * maxf(120.0, (ghost_life - me.hp) * 1.8))
	var full_pow: bool = me.pow_gauge >= float(game.balance.pow_max)
	var sealed: bool = me.has_status("selado")
	pow_button.disabled = not acting or not full_pow or game.turn_pow or sealed
	pow_button.set_state(me.pow_gauge / float(game.balance.pow_max), full_pow, game.turn_pow and mine)
	for i in range(item_buttons.size()):
		var item: Dictionary = game.balance.items[i]
		var slot: SkillSlot = item_buttons[i]
		slot.disabled = not acting or game.energy < game.energy_cost(me, float(item.energy)) or game.turn_fly or sealed
		slot.used = game.turn_items.count(str(item.id)) if mine else 0
	fly_button.disabled = not acting or me.fly_cooldown > 0 or not game.turn_items.is_empty() or game.threats.get("no_plane", false) or me.has_status("enraizado")
	fly_button.used = 1 if game.turn_fly and mine else 0
	fly_button.count_text = str(me.fly_cooldown) if me.fly_cooldown > 0 else ""
	if is_instance_valid(goal_label):
		goal_label.text = phase_goal()
	aux_button.disabled = not acting or me.aux_uses <= 0
	aux_button.count_text = str(me.aux_uses) if me.aux_id != "" else ""
	for i in range(tool_buttons.size()):
		var empty: bool = i >= me.tools.size() or me.tools[i] == ""
		tool_buttons[i].disabled = not acting or empty
		if empty and tool_buttons[i].art != null:
			tool_buttons[i].set_art(null)
	trust_button.text = tr("Confiar ✓") if game.auto_play else tr("Confiar")
	trust_button.add_theme_stylebox_override("normal", UiKit.frame("button_green" if game.auto_play else "button"))
	refresh_used(mine)
	refresh_statuses(me)
	update_sparks(delta)
	for node: Control in [queue_box, clock, minimap, dial, force, gauges, rail, medallion, seal_layer]:
		node.queue_redraw()
	for chip: Control in status_row.get_children():
		chip.queue_redraw()
	if flash_age < 1.6:
		banner.queue_redraw()

func refresh_used(mine: bool) -> void:
	# Chips of what the player armed this turn, above the force gauge.
	var wanted: Array[String] = []
	if mine:
		for id in game.turn_items:
			wanted.append(str(game.item_def(id).icon))
		if game.turn_fly:
			wanted.append("res://assets/ui/icons/plane.png")
		if game.turn_pow:
			wanted.append("pow")
	if used_row.get_child_count() == wanted.size():
		return
	for child in used_row.get_children():
		child.queue_free()
	for i in range(wanted.size()):
		var path: String = wanted[i]
		var chip: Control = Control.new()
		chip.custom_minimum_size = Vector2(32, 32)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.draw.connect(func() -> void:
			HudPaint.glow_rect(chip, Rect2(Vector2.ZERO, chip.size), Color(1.0, 0.8, 0.3, 0.5), 3.0, 2)
			HudPaint.well(chip, HudPaint.frame(chip, Rect2(Vector2.ZERO, chip.size), 0.8)))
		used_row.add_child(chip)
		var texture: Texture2D = load(path) if path.begins_with("res://") else PixelIcons.get_icon(path)
		UiKit.art(chip, texture, Rect2(5, 5, 22, 22))
		# Pops in with a little bounce.
		chip.pivot_offset = Vector2(16, 16)
		chip.scale = Vector2.ONE * 1.6
		create_tween().tween_property(chip, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func refresh_statuses(me: TankFighter) -> void:
	# The player's status effects by the portrait: a glowing chip per effect with its
	# icon and turns left (poison: its doses); hovering tells what it does.
	var list: Array = StatusRules.listed(me) if me.hp > 0 else []
	var signature: String = ",".join(list.map(func(pair: Array) -> String: return "%s%d%d" % [pair[0], int(pair[1].turns), int(pair[1].get("stacks", 1))]))
	if signature == status_seen:
		return
	var before: Array = status_row.get_children().map(func(node: Node) -> String: return str(node.get_meta("id", "")))
	status_seen = signature
	for child in status_row.get_children():
		status_row.remove_child(child)
		child.queue_free()
	for pair: Array in list:
		var id: String = pair[0]
		var entry: Dictionary = pair[1]
		var chip: Control = Control.new()
		chip.custom_minimum_size = Vector2(36, 36)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = StatusRules.describe(id, entry)
		chip.set_meta("id", id)
		var tint: Color = StatusRules.color(id)
		var count: String = ("x%d" % int(entry.get("stacks", 1))) if id == "veneno" else str(int(entry.turns))
		chip.draw.connect(func() -> void:
			var box: Rect2 = Rect2(Vector2.ZERO, chip.size)
			HudPaint.glow_rect(chip, box, Color(tint, 0.35 + 0.25 * sin(time * 4.0)), 3.0, 2)
			var inner: Rect2 = HudPaint.frame(chip, box, 0.6)
			HudPaint.well(chip, inner, tint.darkened(0.82), tint.darkened(0.6))
			var icon: Texture2D = StatusRules.icon(id)
			if icon != null:
				chip.draw_texture_rect(icon, Rect2(5, 4, 26, 26), false)
			HudPaint.outlined(chip, Vector2(14, 35), count, 14, Color.WHITE, HudPaint.INK, 20, HORIZONTAL_ALIGNMENT_RIGHT, 4))
		status_row.add_child(chip)
		if not before.has(id):
			# A new effect pops in.
			chip.pivot_offset = Vector2(18, 18)
			chip.scale = Vector2.ONE * 1.8
			create_tween().tween_property(chip, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func draw_seal() -> void:
	# Chains and a padlock across the skills while the player is sealed.
	var me: TankFighter = game.local()
	if not me.has_status("selado") or me.hp <= 0:
		return
	var tint: Color = StatusRules.color("selado")
	var box: Rect2 = Rect2(Vector2(4, 4), seal_layer.size - Vector2(8, 8))
	seal_layer.draw_rect(box, Color(tint.r * 0.25, tint.g * 0.1, tint.b * 0.35, 0.55))
	for k in range(5):
		var y: float = box.position.y + 30.0 + k * 92.0
		var wobble: float = sin(time * 2.0 + k) * 2.0
		for side: float in [-1.0, 1.0]:
			var a: Vector2 = Vector2(box.position.x - 2, y + side * 14.0 + wobble)
			var b: Vector2 = Vector2(box.end.x + 2, y - side * 14.0 - wobble)
			seal_layer.draw_line(a, b, HudPaint.INK, 5.0)
			seal_layer.draw_line(a, b, tint.lightened(0.2), 2.0)
	var icon: Texture2D = StatusRules.icon("selado")
	if icon != null:
		var bob: float = sin(time * 3.0) * 3.0
		HudPaint.glow(seal_layer, Vector2(34, 222 + bob), 34.0, Color(tint, 0.6))
		seal_layer.draw_texture_rect(icon, Rect2(10, 198 + bob, 48, 48), false)

func portrait_for(fighter: TankFighter) -> Texture2D:
	if not portraits.has(fighter.player_id):
		portraits[fighter.player_id] = UiKit.head_crop(fighter.portrait(), (0.62 if fighter.is_boss else 0.75) if fighter.is_monster else 0.5)
	return portraits[fighter.player_id]

# ---------- top-left ----------

func draw_medallion() -> void:
	# A round glass medallion behind the avatar, ringed in bronze, with a slow rune ring
	# in the team's colour (DDTank's round portrait frame).
	var me: TankFighter = game.local()
	var c: Vector2 = Vector2(58, 64)
	var team: Color = TankFighter.TEAM_COLORS[me.team]
	HudPaint.glow(medallion, c, 70.0, Color(team, 0.5))
	medallion.draw_circle(c, 52.0, HudPaint.INK)
	medallion.draw_circle(c, 50.0, Color(0.05, 0.07, 0.12, 0.72))
	medallion.draw_circle(c + Vector2(0, 10), 36.0, Color(team.darkened(0.4), 0.3))
	for i in range(24):
		var a: float = TAU * i / 24.0 + time * 0.25
		var p: Vector2 = c + Vector2.from_angle(a) * 43.0
		medallion.draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(2, 2) if i % 3 else Vector2(3, 3)), Color(team.lightened(0.4), 0.55))
	medallion.draw_arc(c, 49.0, 0.0, TAU, 48, HudPaint.BRONZE, 3.0)
	medallion.draw_arc(c, 49.5, PI * 1.1, PI * 1.9, 24, HudPaint.GOLD, 2.0)

# ---------- top-center ----------

func draw_queue() -> void:
	var order: Array[TankFighter] = game.turn_order()
	var count: int = mini(order.size(), 8)
	var start: float = 250 - count * 27
	var pulse: float = 0.5 + 0.5 * sin(time * 5.0)
	for i in range(count):
		var fighter: TankFighter = order[i]
		var rect: Rect2 = Rect2(start + i * 54, 2, 48, 48)
		var current: bool = fighter.player_id == game.active_id and game.running
		var team: Color = TankFighter.TEAM_COLORS[fighter.team]
		if current:
			HudPaint.glow_rect(queue_box, rect, Color(1.0, 0.82, 0.3, 0.6 + 0.4 * pulse), 5.0 + 2.0 * pulse)
		var inner: Rect2 = HudPaint.frame(queue_box, rect, 1.0 if current else 0.0)
		HudPaint.vgradient(queue_box, inner, team.darkened(0.35), team.darkened(0.75))
		queue_box.draw_texture_rect(portrait_for(fighter), inner.grow(-1.0), false)
		# Life under the card, in the team's colour.
		var bar: Rect2 = Rect2(rect.position.x + 1, rect.end.y + 3, 46, 7)
		queue_box.draw_rect(bar, HudPaint.INK)
		var width: float = roundf(44.0 * clampf(float(fighter.hp) / maxf(1.0, fighter.max_hp), 0.0, 1.0))
		HudPaint.vgradient(queue_box, Rect2(bar.position + Vector2(1, 1), Vector2(width, 5)), team.lightened(0.35), team.darkened(0.25))
		if fighter.player_id == game.local_id:
			HudPaint.outlined(queue_box, rect.position + Vector2(4, 16), tr("EU"), 16, Color("ffe24a"), HudPaint.INK, -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
		# Status effects (0.16): small icons down the portrait's right edge; elites wear
		# their affix colour around the portrait.
		if not fighter.elite.is_empty():
			queue_box.draw_rect(inner.grow(-0.5), Color(str(fighter.elite.color)), false, 2.0)
		var shown: Array = StatusRules.listed(fighter)
		for k in range(mini(shown.size(), 3)):
			var icon: Texture2D = StatusRules.icon(shown[k][0])
			var spot: Rect2 = Rect2(rect.end.x - 15, rect.position.y + 2 + k * 14, 13, 13)
			queue_box.draw_rect(spot.grow(1), Color(0, 0, 0, 0.6))
			if icon != null:
				queue_box.draw_texture_rect(icon, spot, false)

func wind_chevron(at: Vector2, right: bool, color: Color) -> void:
	var s: float = 1.0 if right else -1.0
	clock.draw_colored_polygon(PackedVector2Array([at + Vector2(-3 * s, -5), at + Vector2(0, -5), at + Vector2(4 * s, 0), at + Vector2(0, 5), at + Vector2(-3 * s, 5), at + Vector2(1 * s, 0)]), color)

func draw_clock() -> void:
	# Wind: a plate with five chevrons on each side; the side the wind blows to lights
	# up (one chevron per fifth of the maximum) with a wave running along it.
	var plate: Rect2 = Rect2(0, 0, 168, 26)
	var inner: Rect2 = HudPaint.frame(clock, plate)
	HudPaint.well(clock, inner)
	var wind: float = game.wind
	var strength: float = absf(wind) / maxf(0.1, float(game.balance.wind_max))
	var lit: int = 0 if absf(wind) < 0.05 else clampi(ceili(strength * 5.0 - 0.001), 1, 5)
	var dazzled: bool = game.local().has_status("ofuscado") and game.local().hp > 0
	if dazzled:
		# Glare (0.16): the wind cannot be read.
		lit = 0
	for side: int in [-1, 1]:
		for i in range(5):
			var at: Vector2 = Vector2(84 + side * (30 + i * 10), 13)
			var on: bool = i < lit and signf(wind) == side
			var color: Color = Color("24364a")
			if on:
				var wave: float = 0.5 + 0.5 * sin(time * (6.0 + strength * 8.0) - i * 1.1)
				color = Color("5cc8ff").lerp(Color("eafaff"), wave * 0.8)
			wind_chevron(at, side > 0, color)
	if dazzled:
		HudPaint.outlined(clock, Vector2(64, 19), "??", 16, StatusRules.color("ofuscado").lerp(Color.WHITE, 0.5 + 0.5 * sin(time * 6.0)), HudPaint.INK, 40, HORIZONTAL_ALIGNMENT_CENTER, 4)
	else:
		HudPaint.outlined(clock, Vector2(64, 19), "%.1f" % absf(wind), 16, Color("bfe8ff") if lit > 0 else Color("7a8a9a"), HudPaint.INK, 40, HORIZONTAL_ALIGNMENT_CENTER, 4)
	# The round timer: a bronze medallion, a ring that empties clockwise in the colour
	# of whoever plays (gold for the player), and the seconds as the cut-in's digits.
	var c: Vector2 = Vector2(84, 72)
	var r: float = 40.0
	var running: bool = game.running
	var mine: bool = running and game.active_id == game.local_id
	var urgent: bool = mine and game.remaining < 4.0 and game.can_act()
	var frac: float = clampf(game.remaining / maxf(0.1, game.turn_seconds), 0.0, 1.0) if running else 0.0
	var ring: Color = Color("ffd04a").lerp(Color("ff7a1a"), 1.0 - frac) if mine else TankFighter.TEAM_COLORS[game.active().team]
	if urgent:
		ring = Color("ff3a1a").lerp(Color("ffd0a0"), 0.5 + 0.5 * sin(time * 18.0))
	var jolt: Vector2 = Vector2.ZERO
	if urgent and beat < 0.2:
		jolt = Vector2(sin(time * 90.0), cos(time * 70.0)) * 2.0 * (1.0 - beat / 0.2)
	c += jolt.round()
	if mine:
		HudPaint.glow(clock, c, r + 22.0 + (6.0 if urgent else 0.0), Color(ring, 0.85))
	clock.draw_circle(c, r + 3.0, HudPaint.INK)
	clock.draw_circle(c, r + 1.0, HudPaint.BRONZE_DARK)
	clock.draw_arc(c, r - 1.5, 0.0, TAU, 48, HudPaint.BRONZE, 4.0)
	clock.draw_arc(c, r - 1.0, PI * 1.08, PI * 1.92, 32, HudPaint.BRONZE_LIGHT, 3.0)
	clock.draw_arc(c, r - 1.5, PI * 0.12, PI * 0.88, 32, Color("3a1a08"), 3.0)
	clock.draw_circle(c, r - 4.0, HudPaint.INK)
	clock.draw_arc(c, r - 8.0, 0.0, TAU, 48, Color("24160c"), 6.0)
	if frac > 0.0:
		clock.draw_arc(c, r - 8.0, -PI / 2.0, -PI / 2.0 + TAU * frac, maxi(4, roundi(48 * frac)), ring, 6.0)
		var tip: Vector2 = c + Vector2.from_angle(-PI / 2.0 + TAU * frac) * (r - 8.0)
		clock.draw_circle(tip, 3.5, ring.lightened(0.6))
	for i in range(10):
		var a: float = TAU * i / 10.0 - PI / 2.0
		clock.draw_line(c + Vector2.from_angle(a) * (r - 11.0), c + Vector2.from_angle(a) * (r - 5.0), Color(0, 0, 0, 0.55), 1.0)
	clock.draw_circle(c, r - 11.0, Color("0b111c"))
	clock.draw_circle(c + Vector2(0, -3), r - 15.0, Color("131c2b"))
	# The seconds: slam in at each new turn; in the last three seconds they turn red
	# and kick on every tick.
	var text: String = str(maxi(0, ceili(game.remaining))) if running else "-"
	var s: float = lerpf(1.9, 1.0, HudPaint.ease_back(turn_age / 0.3))
	if urgent and beat < 0.25:
		s *= 1.0 + 0.35 * (1.0 - beat / 0.25)
	var face: Color = Color("ffd04a")
	var depth: Color = Color("8a3a08")
	if urgent:
		face = Color("ff6a4a")
		depth = Color("5a0a04")
	elif not mine:
		face = Color("d8ecff")
		depth = Color("1a3050")
	clock.draw_set_transform(c, 0.0, Vector2(s, s))
	HudPaint.fancy(clock, Vector2(-40, 16), text, 48, face, depth, 80, HORIZONTAL_ALIGNMENT_CENTER, 3, 8)
	clock.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_banner() -> void:
	# "SUA VEZ!", "FASE CONCLUÍDA!": the cut-in's letters slam in over a band of light.
	if flash_age >= 1.4 or flash_text == "":
		return
	var alpha: float = 1.0 - clampf((flash_age - 0.95) / 0.4, 0.0, 1.0)
	var grow: float = HudPaint.ease_out(flash_age / 0.25)
	var center: Vector2 = Vector2(640, 296)
	var band: float = 420.0 * grow
	var glow: Color = Color(flash_color, 0.3 * alpha)
	var clear: Color = Color(flash_color, 0.0)
	for side: float in [-1.0, 1.0]:
		banner.draw_polygon(PackedVector2Array([center + Vector2(0, -34), center + Vector2(side * band, -20), center + Vector2(side * band, 20), center + Vector2(0, 34)]), PackedColorArray([glow, clear, clear, glow]))
		banner.draw_polygon(PackedVector2Array([center + Vector2(0, -2), center + Vector2(side * band * 1.2, -1), center + Vector2(side * band * 1.2, 1), center + Vector2(0, 2)]), PackedColorArray([Color(1, 1, 1, 0.8 * alpha), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.8 * alpha)]))
	var s: float = lerpf(1.7, 1.0, HudPaint.ease_back(flash_age / 0.22))
	banner.draw_set_transform(center, 0.0, Vector2(s, s))
	HudPaint.fancy(banner, Vector2(-400, 22), flash_text, 64, flash_color, flash_color.darkened(0.7), 800, HORIZONTAL_ALIGNMENT_CENTER, 4, 12, alpha)
	banner.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var width: float = HudPaint.text_width(flash_text, 64) * s
	for side: float in [-1.0, 1.0]:
		HudPaint.sparkle(banner, center + Vector2(side * (width / 2.0 + 18.0), -18.0), 12.0 * sin(clampf(flash_age / 0.8, 0.0, 1.0) * PI), Color(1, 1, 0.9, alpha))
	if flash_sub != "":
		HudPaint.outlined(banner, center + Vector2(-400, 64), flash_sub, 22, Color(1.0, 0.92, 0.8, alpha), HudPaint.INK, 800, HORIZONTAL_ALIGNMENT_CENTER, 5)

# ---------- top-right ----------

func map_rect() -> Rect2:
	return Rect2(5, 27, 236, 128)

func map_transform() -> Array:
	var area: Rect2 = map_rect()
	var world: Vector2 = game.terrain.world_size
	var ratio: float = minf(area.size.x / world.x, area.size.y / world.y)
	return [area.position + (area.size - world * ratio) / 2.0, ratio]

func draw_minimap() -> void:
	var box: Rect2 = Rect2(Vector2.ZERO, minimap.size)
	var inner: Rect2 = HudPaint.frame(minimap, box)
	# Header: the map's name and the round.
	var header: Rect2 = Rect2(inner.position, Vector2(inner.size.x, 20))
	HudPaint.vgradient(minimap, header, Color("6d3a17"), Color("3a1d0a"))
	minimap.draw_rect(Rect2(header.position.x, header.position.y + 1, header.size.x, 1), Color(1, 0.85, 0.5, 0.35))
	minimap.draw_rect(Rect2(inner.position.x, header.end.y, inner.size.x, 2), HudPaint.INK)
	var round_text: String = tr("Rodada %d") % maxi(1, game.round_number)
	var round_width: float = HudPaint.text_width(round_text, 16)
	var name_width: float = 186.0 - round_width - 10.0
	var font: Font = UiKit.font(true)
	var map_name: String = tr(str(game.map.name))
	while map_name.length() > 3 and font.get_string_size(map_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > name_width:
		map_name = map_name.substr(0, map_name.length() - 2) + "…"
	HudPaint.outlined(minimap, Vector2(header.position.x + 4, header.end.y - 5), map_name, 16, Color("ffe6a0"), HudPaint.INK, -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
	HudPaint.outlined(minimap, Vector2(header.position.x + 186.0 - round_width, header.end.y - 5), round_text, 16, Color("d8ffb0"), HudPaint.INK, -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
	# The map: sky, a ruler grid of 1/10 screen, the terrain, fighters and shots.
	var area: Rect2 = map_rect()
	HudPaint.vgradient(minimap, area, Color("112640"), Color("3a78a8"))
	var mapping: Array = map_transform()
	var origin: Vector2 = mapping[0]
	var ratio: float = mapping[1]
	var world: Vector2 = game.terrain.world_size
	var tick: float = 128.0 * ratio
	var x: float = 0.0
	var index: int = 0
	while x < world.x * ratio:
		var major: bool = index % 5 == 0
		minimap.draw_rect(Rect2(roundf(origin.x + x), area.position.y, 1, area.size.y), Color(1, 1, 1, 0.12 if major else 0.05))
		minimap.draw_rect(Rect2(roundf(origin.x + x), area.end.y - (5 if major else 3), 1, 5 if major else 3), Color(1, 1, 1, 0.6))
		x += tick
		index += 1
	minimap.draw_texture_rect(game.terrain.surface_texture, Rect2(origin, world * ratio), false)
	var pulse: float = fposmod(time * 1.4, 1.0)
	for fighter in game.fighters:
		if fighter.hp <= 0:
			continue
		var point: Vector2 = (origin + fighter.position * ratio - Vector2(0, 3)).round()
		var mine: bool = fighter.player_id == game.local_id
		var color: Color = Color("ffe24a") if mine else TankFighter.TEAM_COLORS[fighter.team]
		var radius: float = 5.0 if fighter.is_boss else 3.5
		if fighter.player_id == game.active_id and game.running:
			minimap.draw_arc(point, radius + 2.0 + pulse * 7.0, 0.0, TAU, 20, Color(color, 1.0 - pulse), 2.0)
		if mine:
			var d: PackedVector2Array = PackedVector2Array([point + Vector2(0, -6), point + Vector2(5, 0), point + Vector2(0, 6), point + Vector2(-5, 0)])
			minimap.draw_colored_polygon(d, HudPaint.INK)
			minimap.draw_colored_polygon(PackedVector2Array([d[0] + Vector2(0, 2), d[1] + Vector2(-2, 0), d[2] + Vector2(0, -2), d[3] + Vector2(2, 0)]), color)
			minimap.draw_rect(Rect2(point + Vector2(-1, -3), Vector2(2, 2)), Color.WHITE)
		else:
			minimap.draw_circle(point, radius + 1.5, HudPaint.INK)
			minimap.draw_circle(point, radius, color)
			minimap.draw_rect(Rect2(point + Vector2(-1, -2), Vector2(2, 1)), Color(1, 1, 1, 0.8))
	# Shots with a short fading trail.
	var live: Dictionary = {}
	for projectile in game.projectiles:
		var id: int = projectile.get_instance_id()
		var head: Vector2 = origin + projectile.position * ratio
		var trail: Array = trails.get(id, [])
		if trail.is_empty() or trail.back().distance_to(head) >= 1.5:
			trail.append(head)
			if trail.size() > 10:
				trail.remove_at(0)
		live[id] = trail
		for k in range(1, trail.size()):
			minimap.draw_line(trail[k - 1], trail[k], Color(1, 0.95, 0.7, float(k) / trail.size() * 0.8), 2.0)
		minimap.draw_circle(head, 2.5, Color.WHITE)
	trails = live
	# The camera's view: corner brackets over a faint veil.
	var view: Rect2 = screen.camera_rect()
	var shown: Rect2 = Rect2(origin + view.position * ratio, view.size * ratio).intersection(area.grow(-1.0))
	if shown.size.x > 4.0 and shown.size.y > 4.0:
		minimap.draw_rect(shown, Color(1, 1, 1, 0.07))
		var arm: float = minf(8.0, shown.size.y / 3.0)
		for k in range(4):
			var left: bool = k == 0 or k == 3
			var top: bool = k < 2
			var corner: Vector2 = Vector2(shown.position.x if left else shown.end.x, shown.position.y if top else shown.end.y).round()
			minimap.draw_rect(Rect2(corner.x if left else corner.x - arm, corner.y if top else corner.y - 2.0, arm, 2.0), Color(1, 1, 1, 0.9))
			minimap.draw_rect(Rect2(corner.x if left else corner.x - 2.0, corner.y if top else corner.y - arm, 2.0, arm), Color(1, 1, 1, 0.9))
	minimap.draw_rect(Rect2(area.position, Vector2(area.size.x, 2)), Color(0, 0, 0, 0.4))

func minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not map_rect().has_point(event.position):
			return
		var mapping: Array = map_transform()
		screen.focus_on((event.position - mapping[0]) / float(mapping[1]), 4.0)

# ---------- right ----------

func draw_rail() -> void:
	var inner: Rect2 = HudPaint.frame(rail, Rect2(Vector2.ZERO, rail.size))
	rail.draw_rect(inner, Color(0.06, 0.04, 0.02, 0.72))
	for i in range(1, game.balance.items.size()):
		var y: float = 178 - 172 + i * 48 - 2
		rail.draw_rect(Rect2(inner.position.x + 2, y, inner.size.x - 4, 1), Color(1, 0.8, 0.5, 0.12))

# ---------- bottom ----------

func draw_dial() -> void:
	# Angle dial: bronze bezel, a night-blue face with degree ticks, the allowed range
	# in red, a gold needle with a glowing tip and the angle in the hub.
	var c: Vector2 = Vector2(67, 67)
	var fighter: TankFighter = game.active() if game.active_id == game.local_id else game.local()
	dial.draw_circle(c, 66.0, HudPaint.INK)
	dial.draw_circle(c, 64.0, HudPaint.BRONZE_DARK)
	dial.draw_arc(c, 61.0, 0.0, TAU, 64, HudPaint.BRONZE, 5.0)
	dial.draw_arc(c, 62.0, PI * 1.08, PI * 1.92, 32, HudPaint.BRONZE_LIGHT, 3.0)
	dial.draw_arc(c, 61.0, PI * 0.12, PI * 0.88, 32, Color("3a1a08"), 3.0)
	for i in range(6):
		HudPaint.rivet(dial, c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * 61.0)
	dial.draw_circle(c, 58.0, HudPaint.INK)
	for k in range(6):
		dial.draw_circle(c + Vector2(0, -k * 1.5), 57.0 - k * 7.0, Color("121b2b").lerp(Color("2c4266"), k / 5.0))
	var facing: int = fighter.facing
	var lo: float = fighter.angle_range.x
	var hi: float = fighter.angle_range.y
	var from_angle: float = -deg_to_rad(lo) if facing > 0 else PI + deg_to_rad(lo)
	var to_angle: float = -deg_to_rad(hi) if facing > 0 else PI + deg_to_rad(hi)
	var a0: float = minf(from_angle, to_angle)
	var a1: float = maxf(from_angle, to_angle)
	dial.draw_arc(c, 44.0, a0, a1, 24, Color(0.88, 0.19, 0.16, 0.85), 10.0)
	dial.draw_arc(c, 49.0, a0, a1, 24, Color("ff9a7a"), 1.0)
	dial.draw_arc(c, 39.0, a0, a1, 24, Color("6a0a08"), 1.0)
	for i in range(0, 181, 5):
		var a: float = -deg_to_rad(i)
		var major: bool = i % 15 == 0
		var length: float = 8.0 if i % 45 == 0 else (6.0 if major else 3.0)
		var color: Color = HudPaint.GOLD if i % 45 == 0 else (HudPaint.CREAM if major else Color(1, 0.94, 0.82, 0.5))
		dial.draw_line(c + Vector2.from_angle(a) * (55.0 - length), c + Vector2.from_angle(a) * 55.0, color, 2.0 if major else 1.0)
	var aim: float = -deg_to_rad(fighter.drawn_effective_angle()) if facing > 0 else PI + deg_to_rad(fighter.drawn_effective_angle())
	var dir: Vector2 = Vector2.from_angle(aim)
	var side: Vector2 = dir.orthogonal()
	var tip: Vector2 = c + dir * 52.0
	var needle: PackedVector2Array = PackedVector2Array([c + side * 4.0 - dir * 10.0, tip, c - side * 4.0 - dir * 10.0])
	HudPaint.glow(dial, tip, 12.0, Color(1.0, 0.9, 0.4, 0.9), 3)
	dial.draw_colored_polygon(needle, HudPaint.INK)
	dial.draw_colored_polygon(PackedVector2Array([c + side * 2.5 - dir * 8.0, c + dir * 49.0, c - side * 2.5 - dir * 8.0]), Color("ffd04a"))
	dial.draw_line(c - dir * 6.0, c + dir * 46.0, Color("fff6c0"), 1.0)
	dial.draw_circle(c, 23.0, HudPaint.INK)
	dial.draw_circle(c, 21.0, HudPaint.BRONZE_DARK)
	dial.draw_arc(c, 20.0, PI * 1.1, PI * 1.9, 16, HudPaint.BRONZE_LIGHT, 2.0)
	dial.draw_circle(c, 18.0, Color("0b111c"))
	HudPaint.fancy(dial, c + Vector2(-24, 11), str(roundi(fighter.drawn_angle())), 32, Color("8aff6a"), Color("1a5a0a"), 48, HORIZONTAL_ALIGNMENT_CENTER, 2, 6)
	if absf(fighter.tilt) >= 1.0:
		HudPaint.outlined(dial, c + Vector2(-30, 49), "%+d°" % roundi(fighter.tilt * fighter.facing), 16, HudPaint.CREAM, HudPaint.INK, 60, HORIZONTAL_ALIGNMENT_CENTER, 3)

static func force_color(t: float) -> Color:
	# Yellow → orange → red along the bar, like DDTank's.
	var x: float = clampf(t, 0.0, 1.0) * (FORCE_STOPS.size() - 1)
	var i: int = mini(int(x), FORCE_STOPS.size() - 2)
	return FORCE_STOPS[i].lerp(FORCE_STOPS[i + 1], x - i)

func visible_force() -> float:
	# Only the player's own force is shown: an opponent's charge stays secret (DDTank).
	return game.shown_power() if game.active_id == game.local_id else 0.0

func force_room() -> Rect2:
	return Rect2(76, 26, 610, 34)

func update_sparks(delta: float) -> void:
	# Sparks thrown off the tip of the force bar while the player charges.
	var value: float = visible_force()
	var charging: bool = game.state == LocalMatch.State.PLAYER_CHARGING and value > 0.0 and not game.paused
	var room: Rect2 = force_room()
	if charging:
		for k in range(2):
			sparks.append({"pos": Vector2(room.position.x + room.size.x * value / 100.0, room.position.y + randf_range(2, room.size.y - 2)),
				"vel": Vector2(randf_range(-60, 40), randf_range(-140, -40)), "life": randf_range(0.25, 0.5), "age": 0.0})
	for spark: Dictionary in sparks:
		spark.age = float(spark.age) + delta
		spark.pos = spark.pos + spark.vel * delta
		spark.vel = spark.vel + Vector2(0, 320) * delta
	sparks = sparks.filter(func(s: Dictionary) -> bool: return float(s.age) < float(s.life))

func draw_force() -> void:
	# The force gauge: a bronze "Força" plate, a ruler 10…100 over a long bronze frame, a
	# glossy yellow→red fill with segments, a shine running over it, a glowing tip that
	# throws sparks while charging, and the last shot's red pennant.
	var plate: Rect2 = Rect2(0, 20, 76, 46)
	var face: Rect2 = HudPaint.frame(force, plate)
	HudPaint.vgradient(force, face, Color("8a4e22"), Color("4f290f"))
	force.draw_rect(Rect2(face.position.x, face.position.y, face.size.x, 1), Color(1, 0.85, 0.5, 0.4))
	HudPaint.fancy(force, Vector2(face.position.x, face.position.y + face.size.y / 2.0 + 6.0), tr("Força"), 16, HudPaint.GOLD, Color("3a1a08"), face.size.x, HORIZONTAL_ALIGNMENT_CENTER, 2, 4)
	var inner: Rect2 = HudPaint.frame(force, Rect2(70, 20, 622, 46))
	HudPaint.well(force, inner, Color("05070c"), Color("121826"))
	var room: Rect2 = force_room()
	var x: float = room.position.x + 4.0
	while x < room.end.x:
		force.draw_rect(Rect2(x, room.position.y, 1, room.size.y), Color(1, 1, 1, 0.025))
		x += 8.0
	var mine: bool = game.active_id == game.local_id
	var value: float = visible_force()
	for i in range(1, 11):
		var tx: float = room.position.x + room.size.x * i / 10.0
		var near: bool = value > 0.0 and absf(value - i * 10.0) < 5.0
		HudPaint.outlined(force, Vector2(tx - 20, 16), str(i * 10), 16, HudPaint.GOLD_HOT if near else HudPaint.CREAM, HudPaint.INK, 40, HORIZONTAL_ALIGNMENT_CENTER, 3)
	if value > 0.0:
		var width: float = roundf(room.size.x * value / 100.0)
		var fill: Rect2 = Rect2(room.position, Vector2(width, room.size.y))
		var split: float = minf(width, roundf(room.size.x * 0.5))
		force.draw_polygon(PackedVector2Array([fill.position, fill.position + Vector2(split, 0), fill.position + Vector2(split, fill.size.y), fill.position + Vector2(0, fill.size.y)]),
			PackedColorArray([FORCE_STOPS[0], force_color(split / room.size.x), force_color(split / room.size.x), FORCE_STOPS[0]]))
		if width > split:
			var end_color: Color = force_color(width / room.size.x)
			var mid: Color = force_color(split / room.size.x)
			force.draw_polygon(PackedVector2Array([fill.position + Vector2(split, 0), Vector2(fill.end.x, fill.position.y), fill.end, fill.position + Vector2(split, fill.size.y)]), PackedColorArray([mid, end_color, end_color, mid]))
		force.draw_rect(Rect2(fill.position + Vector2(0, 2), Vector2(width, 8)), Color(1, 1, 1, 0.3))
		force.draw_rect(Rect2(fill.position.x, fill.end.y - 8, width, 8), Color(0.4, 0.05, 0.0, 0.25))
		for i in range(1, 10):
			var gx: float = roundf(room.position.x + room.size.x * i / 10.0)
			if gx < fill.end.x - 2.0:
				force.draw_rect(Rect2(gx - 1, fill.position.y, 2, fill.size.y), Color(0.25, 0.05, 0.0, 0.45))
		# A slanted shine sweeps over the fill.
		var sweep: float = fill.position.x + fposmod(time * 520.0, width + 160.0) - 60.0
		var band: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in [Vector2(sweep + 14, fill.position.y), Vector2(sweep + 34, fill.position.y), Vector2(sweep + 20, fill.end.y), Vector2(sweep, fill.end.y)]:
			band.append(Vector2(clampf(corner.x, fill.position.x, fill.end.x), corner.y))
		force.draw_colored_polygon(band, Color(1, 1, 0.9, 0.35))
		if value >= 99.5:
			force.draw_rect(fill, Color(1, 1, 1, 0.25 + 0.2 * sin(time * 30.0)))
		# The glowing tip.
		var tip: Vector2 = Vector2(fill.end.x, fill.position.y + fill.size.y / 2.0)
		HudPaint.glow(force, tip, 26.0, Color(1.0, 0.9, 0.5, 0.9), 4)
		force.draw_rect(Rect2(fill.end.x - 3, fill.position.y - 2, 3, fill.size.y + 4), Color("fffbe0"))
	for spark: Dictionary in sparks:
		var fade: float = 1.0 - float(spark.age) / float(spark.life)
		force.draw_rect(Rect2(spark.pos.round(), Vector2(2, 2)), Color(1.0, 0.9 - (1.0 - fade) * 0.5, 0.5 * fade, fade))
	# The last shot: a red pennant on the frame and a dashed line through the bar.
	var last: float = game.local().last_power
	if last >= 0.0:
		var mark: float = roundf(room.position.x + room.size.x * last / 100.0)
		var y: float = room.position.y
		while y < room.end.y:
			force.draw_rect(Rect2(mark - 1, y, 2, 3), Color(1.0, 0.35, 0.3, 0.75))
			y += 6.0
		var flag: PackedVector2Array = PackedVector2Array([Vector2(mark - 7, 16), Vector2(mark + 7, 16), Vector2(mark, 27)])
		force.draw_colored_polygon(PackedVector2Array([flag[0] + Vector2(-2, -2), flag[1] + Vector2(2, -2), flag[2] + Vector2(0, 3)]), HudPaint.INK)
		force.draw_colored_polygon(flag, Color("e0302a"))
		force.draw_rect(Rect2(mark - 5, 17, 10, 2), Color("ff9a7a"))
	if value <= 0.0:
		var tip_text: String = tr("Pressione Espaço com força total e realize um ataque") if mine else tr("Aguarde a sua vez…")
		var alpha: float = 0.8 + 0.2 * sin(time * 3.0) if mine and game.can_act() else 0.7
		HudPaint.outlined(force, Vector2(room.position.x, room.position.y + 23), tip_text, 16, Color(1.0, 0.94, 0.82, alpha), HudPaint.INK, room.size.x, HORIZONTAL_ALIGNMENT_CENTER, 4)

func draw_gauges() -> void:
	# Energy and life: framed glossy gauges with the value in the middle. What was just
	# lost stays behind the fill a moment (cyan for energy, pale gold for life).
	var me: TankFighter = game.local()
	var mine: bool = game.active_id == game.local_id and game.running
	var energy: float = game.energy if mine else float(me.max_energy)
	var max_energy: float = maxf(1.0, float(me.max_energy))
	var inner: Rect2 = HudPaint.gauge(gauges, Rect2(0, 2, 180, 30), energy / max_energy, Color("e4ff7a"), Color("4a8a10"), ghost_energy / max_energy, Color(0.55, 0.95, 1.0, 0.75), time)
	HudPaint.outlined(gauges, Vector2(inner.position.x + 20, inner.end.y - 4), str(roundi(energy)), 16, Color.WHITE, HudPaint.INK, inner.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER, 4)
	if me.has_status("exaustao") and me.hp > 0:
		# Exhausted (0.16): everything costs more; the multiplier sits on the bar.
		var scale_text: String = "x%s" % str(snappedf(float(StatusRules.def("exaustao").get("cost_scale", 1.5)), 0.1))
		HudPaint.outlined(gauges, Vector2(inner.end.x - 40, inner.end.y - 4), scale_text, 14, StatusRules.color("exaustao"), HudPaint.INK, 36, HORIZONTAL_ALIGNMENT_RIGHT, 4)
	var life: Rect2 = Rect2(0, 36, 180, 38)
	var ratio: float = float(me.hp) / maxf(1.0, float(me.max_hp))
	if ratio < 0.25 and me.hp > 0:
		HudPaint.glow_rect(gauges, life, Color(1.0, 0.2, 0.1, 0.5 + 0.5 * sin(time * 7.0)), 5.0)
	inner = HudPaint.gauge(gauges, life, ratio, Color("ff8a6a"), Color("9a0c14"), ghost_life / maxf(1.0, float(me.max_hp)), Color(1.0, 0.9, 0.6, 0.85), time + 0.7)
	HudPaint.outlined(gauges, Vector2(inner.position.x + 24, inner.end.y - 6), str(me.hp), 20, Color.WHITE, HudPaint.INK, inner.size.x - 24, HORIZONTAL_ALIGNMENT_CENTER, 5)
