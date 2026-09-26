class_name BattleHUD
extends Control

# Classic battle HUD: portrait and log (top-left), turn queue, countdown/PASS and wind
# (top-center), minimap (top-right), skills 1–9 (right), angle dial, force bar,
# Z/X/C tools, POW, energy and life (bottom).

var screen: BattleScreen
var game: LocalMatch
var log_lines: Array[Dictionary] = []
var log_label: RichTextLabel
var queue_box: Control
var countdown: Label
var pass_button: Button
var wind_label: Label
var wind_arrow: TextureRect
var minimap: Control
var dial: Control
var force: Control
var item_buttons: Array[Button] = []
var tool_buttons: Array[Button] = []
var fly_button: Button
var aux_button: Button
var aux_count: Label
var pow_button: Button
var trust_button: Button
var pow_bar: ProgressBar
var energy_bar: ProgressBar
var life_bar: ProgressBar
var energy_value: Label
var life_value: Label
var used_row: HBoxContainer
var banner: Label
var outcome: TextureRect
var pause_box: Control
var portraits: Dictionary = {}
var phase_label: Label
var goal_label: Label

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func build() -> void:
	var me: TankFighter = game.local()
	# --- top-left: identity, avatar and battle log
	UiKit.panel(self, Rect2(4, 4, 74, 22), "mode_green")
	UiKit.label(self, me.rank_title, Rect2(4, 4, 74, 22), 12, Color("d8ffb0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(self, me.display_name, Rect2(84, 2, 260, 26), 17, Color.WHITE, UiKit.INK)
	UiKit.art(self, me.portrait(), Rect2(10, 30, 110, 118))
	log_label = RichTextLabel.new()
	log_label.position = Vector2(8, 152)
	log_label.size = Vector2(360, 116)
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.add_theme_font_override("normal_font", UiKit.font(true))
	log_label.add_theme_font_size_override("normal_font_size", UiKit.fs(14))
	log_label.add_theme_color_override("font_outline_color", Color("140a04"))
	log_label.add_theme_constant_override("outline_size", 4)
	add_child(log_label)
	# --- top-center: turn order, wind, countdown and PASS
	queue_box = Control.new()
	queue_box.position = Vector2(390, 4)
	queue_box.size = Vector2(500, 60)
	queue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_box.draw.connect(draw_queue)
	add_child(queue_box)
	UiKit.panel(self, Rect2(566, 66, 148, 32), "glass")
	wind_arrow = UiKit.art(self, "res://assets/expansion/combat/wind_indicator.png", Rect2(572, 68, 56, 28))
	wind_label = UiKit.label(self, "0.0", Rect2(628, 66, 80, 32), 20, Color("9adcff"), Color("0a1a2a"), HORIZONTAL_ALIGNMENT_CENTER)
	var leaf: Control = Control.new()
	leaf.position = Vector2(580, 100)
	leaf.size = Vector2(120, 70)
	leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaf.draw.connect(func() -> void:
		var points: PackedVector2Array = PackedVector2Array()
		for i in range(24):
			var a: float = i * TAU / 24
			points.append(Vector2(60, 40) + Vector2(cos(a) * 58, sin(a) * 26 + (8.0 if cos(a) < 0 else 0.0) * sin(a)))
		leaf.draw_colored_polygon(points, Color(0.98, 0.84, 0.38, 0.9))
		leaf.draw_polyline(points + PackedVector2Array([points[0]]), Color("8a5a1a"), 3))
	add_child(leaf)
	countdown = UiKit.label(self, "10", Rect2(580, 86, 120, 80), 60, Color("ffb020"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
	countdown.add_theme_constant_override("outline_size", 10)
	pass_button = UiKit.button(self, tr("PASS"), Rect2(604, 168, 72, 28), game.pass_turn, "button_blue", 15)
	pass_button.tooltip_text = tr("Passar a vez (P). Gera menos atraso.")
	# --- top-right: minimap with settings and exit
	UiKit.panel(self, Rect2(1034, 2, 242, 24), "mode_green")
	UiKit.icon_button(self, PixelIcons.get_icon("gear"), Rect2(1214, 3, 22, 22), screen.toggle_pause, tr("Pausa / opções (Esc)"))
	UiKit.icon_button(self, PixelIcons.get_icon("power"), Rect2(1244, 3, 22, 22), screen.toggle_pause, tr("Sair da batalha"))
	UiKit.label(self, tr(str(game.map.name)), Rect2(1040, 2, 170, 24), 13, Color("d8ffb0"), UiKit.INK)
	minimap = Control.new()
	minimap.position = Vector2(1034, 26)
	minimap.size = Vector2(242, 132)
	minimap.draw.connect(draw_minimap)
	minimap.gui_input.connect(minimap_input)
	minimap.tooltip_text = tr("Clique para mover a câmera. Cada marca = 1/10 de tela.")
	add_child(minimap)
	# --- right column: skills 1–9 like DDTank (+2, x3, +1, POW 50%…10%, POW máx);
	# the plane (F) and the auxiliary item (V) sit by the angle dial
	UiKit.panel(self, Rect2(1222, 186, 54, 420), "glass")
	UiKit.panel(self, Rect2(138, 600, 54, 52), "glass")
	fly_button = slot_button(Rect2(142, 604, 46, 44), PixelIcons.get_icon("plane"), "F", game.toggle_fly)
	fly_button.tooltip_text = tr("Avião de papel (F): voe até onde o disparo cair. %d de energia.") % int(game.balance.fly.energy)
	# Item auxiliar (V): the Bálsamo heals, the shields halve the next hit.
	var aux: Dictionary = Armory.aux_def(me.aux_id)
	UiKit.panel(self, Rect2(138, 546, 54, 52), "glass")
	aux_button = slot_button(Rect2(142, 550, 46, 44), load(str(aux.icon)) if not aux.is_empty() else null, "V", game.use_aux)
	aux_button.tooltip_text = tr("%s (V)\n%s") % [tr(str(aux.name)), tr(str(aux.desc))] if not aux.is_empty() else tr("Sem item auxiliar. Equipe um na Mochila (Bálsamo ou escudo).")
	aux_count = UiKit.label(aux_button, "", Rect2(20, 26, 26, 18), 12, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in range(game.balance.items.size()):
		var item: Dictionary = game.balance.items[i]
		var button: Button = slot_button(Rect2(1226, 190 + i * 46, 46, 45), load(str(item.icon)), str(item.key), func() -> void: game.use_item(str(item.id)))
		button.tooltip_text = tr("%s  (tecla %s)\n%s\nEnergia: %d") % [tr(str(item.name)), item.key, tr(str(item.desc)), int(item.energy)]
		item_buttons.append(button)
	# --- bottom-left: trust, angle dial
	trust_button = UiKit.button(self, tr("Confiar"), Rect2(8, 546, 112, 34), toggle_trust, "button", 15)
	trust_button.tooltip_text = tr("Confiar: a IA joga os seus turnos.")
	dial = Control.new()
	dial.position = Vector2(2, 584)
	dial.size = Vector2(134, 134)
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial.draw.connect(draw_dial)
	add_child(dial)
	# --- bottom-center: force bar with tick labels and last-shot marker
	UiKit.label(self, tr("Força"), Rect2(140, 690, 70, 26), 16, Color("ffe6a0"), UiKit.INK)
	force = Control.new()
	force.position = Vector2(206, 652)
	force.size = Vector2(620, 62)
	force.mouse_filter = Control.MOUSE_FILTER_IGNORE
	force.draw.connect(draw_force)
	add_child(force)
	used_row = HBoxContainer.new()
	used_row.position = Vector2(206, 614)
	used_row.add_theme_constant_override("separation", 4)
	used_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(used_row)
	# --- tools Z X C, POW (B)
	for i in range(3):
		var tool_id: String = me.tools[i] if i < me.tools.size() else ""
		var icon: Texture2D = null
		var tip: String = tr("Sem ferramenta. Compre na sala.")
		if tool_id != "":
			var tool: Dictionary = game.tool_def(tool_id)
			icon = load(str(tool.icon))
			tip = "%s (%s)\n%s" % [tr(str(tool.name)), ["Z", "X", "C"][i], tr(str(tool.desc))]
		var button: Button = slot_button(Rect2(836 + i * 52, 664, 48, 48), icon, ["Z", "X", "C"][i], func() -> void: game.use_tool(i))
		button.tooltip_text = tip
		tool_buttons.append(button)
	pow_button = slot_button(Rect2(996, 612, 44, 44), PixelIcons.get_icon("pow"), "B", game.activate_pow)
	pow_button.tooltip_text = tr("POW (B): %s. Enche causando e recebendo dano.") % tr(str(me.weapon.get("pow", {}).get("name", "especial")))
	pow_bar = UiKit.bar(self, Rect2(1046, 628, 170, 14), Color("c060ff"))
	pow_bar.max_value = float(game.balance.pow_max)
	UiKit.label(self, tr("POW"), Rect2(1046, 606, 60, 22), 13, Color("e0b0ff"), UiKit.INK)
	# --- energy and life
	energy_bar = UiKit.bar(self, Rect2(1000, 662, 214, 22), Color("b8e030"))
	energy_value = UiKit.label(self, "240", Rect2(1000, 660, 214, 26), 16, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(self, tr("Energia"), Rect2(1216, 660, 64, 26), 14, Color("e8ff9a"), UiKit.INK)
	life_bar = UiKit.bar(self, Rect2(1000, 690, 214, 26), Color("e0302a"))
	life_value = UiKit.label(self, "0", Rect2(1000, 690, 214, 26), 18, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(self, tr("Vida"), Rect2(1216, 690, 64, 26), 16, Color("ffb0a0"), UiKit.INK)
	if game.pve and not game.phase.is_empty():
		build_phase()
	banner = UiKit.label(self, "", Rect2(340, 250, 600, 90), 56, Color("9aff7a"), Color("0a2a04"), HORIZONTAL_ALIGNMENT_CENTER)
	banner.add_theme_constant_override("outline_size", 12)
	banner.modulate.a = 0
	refresh_log()

func build_phase() -> void:
	# Instance progress: phase x/3, its name, the map level and the phase objective.
	var box: Panel = UiKit.panel(self, Rect2(722, 66, 304, 64), "glass")
	box.name = "PhasePanel"
	var level: int = int(game.phase.get("level", 0))
	var level_text: String = tr("Nível %d") % level if level > 0 else tr("Entrada livre")
	phase_label = UiKit.label(box, tr("Fase %d/%d  •  %s") % [int(game.phase.index) + 1, int(game.phase.count), game.phase.name], Rect2(8, 2, 292, 26), 15, Color("ffd04a"), UiKit.INK)
	phase_label.clip_text = true
	goal_label = UiKit.label(box, "", Rect2(8, 30, 200, 26), 13, Color("fff0d0"), UiKit.INK)
	UiKit.label(box, level_text, Rect2(200, 30, 98, 26), 13, Color("c99bff") if level >= 10 else Color("9adcff"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	if game.threats.get("no_plane", false):
		fly_button.tooltip_text = tr("Sem avião de papel neste mapa.")

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

func slot_button(rect: Rect2, icon: Texture2D, key: String, action: Callable) -> Button:
	var button: Button = UiKit.button(self, "", rect, action, "slot")
	button.add_theme_stylebox_override("disabled", UiKit.frame("slot"))
	if icon != null:
		var art: TextureRect = UiKit.art(button, icon, Rect2(5, 5, rect.size.x - 10, rect.size.y - 10))
		art.name = "Icon"
	UiKit.label(button, key, Rect2(2, -2, 20, 18), 12, Color("ffe6a0"), UiKit.INK)
	return button

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

func flash(text: String, color: Color) -> void:
	if not is_instance_valid(banner):
		return
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.modulate.a = 1.0
	banner.scale = Vector2.ONE * 1.3
	banner.pivot_offset = banner.size / 2
	var tween: Tween = create_tween()
	tween.tween_property(banner, "scale", Vector2.ONE, 0.2)
	tween.tween_interval(0.7)
	tween.tween_property(banner, "modulate:a", 0.0, 0.4)

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
	var path: String = "res://assets/expansion/ui/victory_emblem.png" if won else "res://assets/expansion/ui/defeat_emblem.png"
	outcome = UiKit.art(self, path, Rect2(384, 200, 512, 256))
	outcome.pivot_offset = Vector2(256, 128)
	outcome.scale = Vector2.ONE * 0.2
	create_tween().tween_property(outcome, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
	if draw:
		flash(tr("EMPATE"), Color("fff0c0"))

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

func _process(_delta: float) -> void:
	if game == null or game.fighters.is_empty() or not is_instance_valid(countdown):
		return
	var me: TankFighter = game.local()
	var mine: bool = game.active_id == game.local_id and game.running
	var acting: bool = game.can_act()
	countdown.text = str(maxi(0, ceili(game.remaining))) if game.running else "-"
	countdown.add_theme_color_override("font_color", Color("ff5a3a") if game.remaining < 4 and mine else Color("ffb020"))
	pass_button.disabled = not acting
	wind_label.text = "%.1f" % absf(game.wind)
	wind_arrow.flip_h = game.wind < 0
	wind_arrow.modulate.a = 0.25 if absf(game.wind) < 0.05 else 1.0
	var energy: float = game.energy if mine else float(me.max_energy)
	energy_bar.max_value = me.max_energy
	energy_bar.value = energy
	energy_value.text = str(roundi(energy))
	life_bar.max_value = me.max_hp
	life_bar.value = me.hp
	life_value.text = str(me.hp)
	pow_bar.value = me.pow_gauge
	var full_pow: bool = me.pow_gauge >= float(game.balance.pow_max)
	pow_button.disabled = not acting or not full_pow or game.turn_pow
	pow_button.modulate = Color(1.3, 1.2, 0.7) if full_pow and acting else Color.WHITE
	for i in range(item_buttons.size()):
		var item: Dictionary = game.balance.items[i]
		item_buttons[i].disabled = not acting or game.energy < float(item.energy) or game.turn_fly
	fly_button.disabled = not acting or me.fly_cooldown > 0 or not game.turn_items.is_empty() or game.threats.get("no_plane", false)
	if is_instance_valid(goal_label):
		goal_label.text = phase_goal()
	fly_button.modulate = Color(0.7, 1.3, 1.0) if game.turn_fly and mine else Color.WHITE
	aux_button.disabled = not acting or me.aux_uses <= 0
	aux_count.text = str(me.aux_uses) if me.aux_id != "" else ""
	for i in range(tool_buttons.size()):
		tool_buttons[i].disabled = not acting or i >= me.tools.size() or me.tools[i] == ""
		if tool_buttons[i].has_node("Icon") and (i >= me.tools.size() or me.tools[i] == ""):
			tool_buttons[i].get_node("Icon").modulate.a = 0.25
	trust_button.text = tr("Confiar ✓") if game.auto_play else tr("Confiar")
	trust_button.add_theme_stylebox_override("normal", UiKit.frame("button_green" if game.auto_play else "button"))
	refresh_used(mine)
	queue_box.queue_redraw()
	minimap.queue_redraw()
	dial.queue_redraw()
	force.queue_redraw()

func refresh_used(mine: bool) -> void:
	var wanted: Array[String] = []
	if mine:
		for id in game.turn_items:
			wanted.append(str(game.item_def(id).icon))
		if game.turn_fly:
			wanted.append("plane")
		if game.turn_pow:
			wanted.append("pow")
	if used_row.get_child_count() == wanted.size():
		return
	for child in used_row.get_children():
		child.queue_free()
	for path in wanted:
		var icon: TextureRect = TextureRect.new()
		icon.texture = PixelIcons.get_icon(path) if not path.begins_with("res://") else load(path)
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		used_row.add_child(icon)

func portrait_for(fighter: TankFighter) -> Texture2D:
	if not portraits.has(fighter.player_id):
		portraits[fighter.player_id] = UiKit.head_crop(fighter.portrait(), (0.62 if fighter.is_boss else 0.75) if fighter.is_monster else 0.5)
	return portraits[fighter.player_id]

func draw_queue() -> void:
	var order: Array[TankFighter] = game.turn_order()
	var count: int = mini(order.size(), 8)
	var start: float = 250 - count * 27
	var font: Font = UiKit.font(true)
	for i in range(count):
		var fighter: TankFighter = order[i]
		var rect: Rect2 = Rect2(start + i * 54, 0, 48, 48)
		var current: bool = fighter.player_id == game.active_id and game.running
		queue_box.draw_rect(rect.grow(2), Color("ffd04a") if current else Color("2a1608"))
		queue_box.draw_rect(rect, TankFighter.TEAM_COLORS[fighter.team].darkened(0.55))
		queue_box.draw_texture_rect(portrait_for(fighter), rect.grow(-2), false)
		queue_box.draw_rect(Rect2(rect.position.x, rect.end.y + 2, 48, 6), Color("1a0f08"))
		queue_box.draw_rect(Rect2(rect.position.x + 1, rect.end.y + 3, 46.0 * fighter.hp / maxf(1, fighter.max_hp), 4), TankFighter.TEAM_COLORS[fighter.team])
		if fighter.player_id == game.local_id:
			queue_box.draw_string_outline(font, rect.position + Vector2(2, 12), tr("EU"), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(11), 3, Color("2a1608"))
			queue_box.draw_string(font, rect.position + Vector2(2, 12), tr("EU"), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(11), Color("ffe24a"))

func draw_minimap() -> void:
	var box: Rect2 = Rect2(Vector2.ZERO, minimap.size)
	minimap.draw_rect(box, Color("0c1a2e"))
	var world: Vector2 = game.terrain.world_size
	var ratio: float = minf(box.size.x / world.x, box.size.y / world.y)
	var origin: Vector2 = (box.size - world * ratio) / 2
	minimap.draw_rect(Rect2(origin, world * ratio), Color("5fa8d8"))
	minimap.draw_texture_rect(game.terrain.surface_texture, Rect2(origin, world * ratio), false)
	var tick: float = 128.0 * ratio
	var x: float = 0.0
	while x < world.x * ratio:
		minimap.draw_line(origin + Vector2(x, 0), origin + Vector2(x, 4), Color(1, 1, 1, 0.5), 1)
		x += tick
	for fighter in game.fighters:
		if fighter.hp <= 0:
			continue
		var point: Vector2 = origin + fighter.position * ratio
		var color: Color = Color("ffe24a") if fighter.player_id == game.local_id else TankFighter.TEAM_COLORS[fighter.team]
		minimap.draw_rect(Rect2(point - Vector2(3, 6), Vector2(6, 6)), color)
		minimap.draw_rect(Rect2(point - Vector2(3, 6), Vector2(6, 6)), Color("10141f"), false, 1)
	for projectile in game.projectiles:
		minimap.draw_rect(Rect2(origin + projectile.position * ratio - Vector2(1.5, 1.5), Vector2(3, 3)), Color.WHITE)
	var view: Rect2 = screen.camera_rect()
	minimap.draw_rect(Rect2(origin + view.position * ratio, view.size * ratio), Color(1, 1, 1, 0.85), false, 1)
	minimap.draw_rect(box, Color("2a1608"), false, 2)

func minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world: Vector2 = game.terrain.world_size
		var ratio: float = minf(minimap.size.x / world.x, minimap.size.y / world.y)
		var origin: Vector2 = (minimap.size - world * ratio) / 2
		screen.focus_on((event.position - origin) / ratio, 4.0)

func draw_dial() -> void:
	var center: Vector2 = Vector2(67, 67)
	var fighter: TankFighter = game.active() if game.active_id == game.local_id else game.local()
	dial.draw_circle(center, 64, Color("2a1608"))
	dial.draw_circle(center, 60, Color("d8d0c0"))
	dial.draw_circle(center, 54, Color("3a4a5a"))
	var facing: int = fighter.facing
	var lo: float = fighter.angle_range.x
	var hi: float = fighter.angle_range.y
	var from_angle: float = -deg_to_rad(lo) if facing > 0 else PI + deg_to_rad(lo)
	var to_angle: float = -deg_to_rad(hi) if facing > 0 else PI + deg_to_rad(hi)
	dial.draw_arc(center, 46, minf(from_angle, to_angle), maxf(from_angle, to_angle), 24, Color("e0302a"), 8)
	for i in range(0, 181, 15):
		var a: float = -deg_to_rad(i)
		dial.draw_line(center + Vector2.from_angle(a) * 50, center + Vector2.from_angle(a) * 55, Color("fff0d0"), 2)
	var aim: float = -deg_to_rad(fighter.drawn_effective_angle()) if facing > 0 else PI + deg_to_rad(fighter.drawn_effective_angle())
	dial.draw_line(center, center + Vector2.from_angle(aim) * 50, Color("ffe24a"), 3)
	dial.draw_circle(center, 22, Color("10141f"))
	var font: Font = UiKit.font(true)
	var text: String = str(roundi(fighter.drawn_angle()))
	dial.draw_string_outline(font, center + Vector2(-22, 10), text, HORIZONTAL_ALIGNMENT_CENTER, 44, UiKit.fs(26), 5, Color("0a1a04"))
	dial.draw_string(font, center + Vector2(-22, 10), text, HORIZONTAL_ALIGNMENT_CENTER, 44, UiKit.fs(26), Color("7aff5a"))
	if absf(fighter.tilt) >= 1.0:
		var slope: String = "%+d°" % roundi(fighter.tilt * fighter.facing)
		dial.draw_string(font, center + Vector2(-22, 44), slope, HORIZONTAL_ALIGNMENT_CENTER, 44, UiKit.fs(13), Color("fff0d0"))

func draw_force() -> void:
	var font: Font = UiKit.font(true)
	var bar: Rect2 = Rect2(0, 22, 620, 32)
	for i in range(1, 11):
		var x: float = bar.size.x * i / 10.0
		force.draw_string_outline(font, Vector2(x - 20, 16), str(i * 10), HORIZONTAL_ALIGNMENT_CENTER, 24, UiKit.fs(13), 3, Color("2a1608"))
		force.draw_string(font, Vector2(x - 20, 16), str(i * 10), HORIZONTAL_ALIGNMENT_CENTER, 24, UiKit.fs(13), Color("fff0d0"))
	force.draw_rect(bar.grow(3), Color("2a1608"))
	force.draw_rect(bar, Color("3a3a3a"))
	for i in range(1, 10):
		var x: float = bar.size.x * i / 10.0
		force.draw_line(Vector2(x, bar.position.y), Vector2(x, bar.position.y + 6), Color("8a8a8a"), 2)
	var mine: bool = game.active_id == game.local_id
	var value: float = game.shown_power() if mine or game.state == LocalMatch.State.PLAYER_CHARGING else 0.0
	if value > 0:
		var width: float = bar.size.x * value / 100.0
		var steps: int = maxi(1, int(width / 8))
		for i in range(steps):
			var t: float = float(i) / 78.0
			var color: Color = Color("ffe24a").lerp(Color("ff3a1a"), clampf(t, 0, 1))
			force.draw_rect(Rect2(bar.position.x + i * 8, bar.position.y + 2, minf(8, width - i * 8), bar.size.y - 4), color)
	var last: float = game.local().last_power
	if last >= 0:
		var mark: float = bar.size.x * last / 100.0
		force.draw_colored_polygon(PackedVector2Array([Vector2(mark - 7, 12), Vector2(mark + 7, 12), Vector2(mark, 24)]), Color("e0302a"))
	if value <= 0:
		var tip: String = tr("Pressione Espaço com força total e realize um ataque") if mine else tr("Aguarde a sua vez…")
		force.draw_string_outline(font, Vector2(0, bar.position.y + 22), tip, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, UiKit.fs(15), 4, Color("10141f"))
		force.draw_string(font, Vector2(0, bar.position.y + 22), tip, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, UiKit.fs(15), Color("fff0d0"))
