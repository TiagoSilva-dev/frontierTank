class_name HuntTab
extends Control

# The "Caçada" tab of the Casa dos Mascotes (0.20), in the Forja layout: zones and the
# analyser on the left, the live arena in the middle, the team and what has piled up on
# the right, and the timer, the collect button and the Passe do Caçador at the bottom.
# The arena replays the encounter in progress from the same PetHunt functions the server
# settles with, so what is on screen is what the collect will give. Operations go
# through `app.do_op` (offline the profile applies them, online the game server does).

signal changed

const PER_PAGE: int = 24

var app: Node
var zone: String = "sol"
var tier: int = 1
var team: Array = []
var message: String = ""
var busy: bool = false

var holder: Control
var arena: HuntArena
var picker: Control
var picker_page: int = 0
var analysis: Dictionary = {}
var analysis_key: String = ""
var cache: Dictionary = {}
var shown_slot: int = -1
var clock: float = 0.0

# Live labels (updated while the tab is open).
var timer_label: Label
var gauge_box: Control
var gauge_fraction: float = 0.0
var legend_box: Control
var legend_fraction: float = 0.0
var legend_label: Label
var tally: Dictionary = {}

func setup(host_app: Node) -> void:
	app = host_app
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1280, 720)
	adopt()

# Takes the zone, tier and team of the running hunt, or sensible defaults.
func adopt() -> void:
	var hunt: Dictionary = app.profile.hunt
	zone = str(hunt.zone)
	tier = clampi(int(hunt.tier), 1, PetHunt.unlocked_tier(hunt, zone))
	team = []
	for uid: Variant in hunt.team:
		if not app.profile.find_pet(int(uid)).is_empty():
			team.append(int(uid))
	if team.is_empty():
		var list: Array[Dictionary] = app.profile.pets.duplicate()
		list.sort_custom(PetWidgets.pet_before)
		for pet: Dictionary in list.slice(0, 3):
			team.append(int(pet.uid))

func profile() -> PlayerProfile:
	return app.profile

func hunt() -> Dictionary:
	return app.profile.hunt

func running() -> bool:
	return bool(hunt().active)

func rebuild() -> void:
	if is_instance_valid(holder):
		remove_child(holder)
		holder.queue_free()
	holder = Control.new()
	holder.size = size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	arena = null
	shown_slot = -1
	picker = null
	reset_cache()
	build()
	PremiumUi.skin(holder)

# ---------- live tally ----------

func reset_cache() -> void:
	var pets: Array[Dictionary] = PetHunt.team_pets(profile(), hunt())
	cache = {"slots": 0, "report": PetHunt.empty_report(), "legend": int(hunt().legend), "units": PetHunt.team_units(pets), "n": int(hunt().n), "since": int(hunt().since)}

func catch_up(limit: int) -> void:
	if not running():
		return
	var pending: int = PetHunt.pending_slots(profile(), profile().hunt_now())
	var done: int = 0
	while int(cache.slots) < pending and done < limit:
		var result: Dictionary = PetHunt.slot(hunt(), cache.units, int(hunt().n) + int(cache.slots), int(cache.legend))
		cache.legend = int(result.legend)
		PetHunt.add_slot(cache.report, result)
		cache.slots = int(cache.slots) + 1
		done += 1

func elapsed() -> int:
	return maxi(0, profile().hunt_now() - int(hunt().since)) if running() else 0

func _process(delta: float) -> void:
	if app == null or not visible or holder == null:
		return
	clock += delta
	if running() and not (cache.units as Array).is_empty():
		catch_up(120)
		follow_arena()
	if clock >= 0.25:
		clock = 0.0
		refresh_live()

# Keeps the arena on the encounter that is happening now.
func follow_arena() -> void:
	if arena == null:
		return
	var pending: int = PetHunt.pending_slots(profile(), profile().hunt_now())
	var capped: bool = elapsed() >= PetHunt.cap_seconds(profile())
	if capped:
		if shown_slot != -2:
			shown_slot = -2
			arena.clear(tr("O time descansou: o limite de tempo acabou. Colete para caçar de novo!"))
		return
	if int(cache.slots) < pending or shown_slot == pending:
		return
	var result: Dictionary = PetHunt.slot(hunt(), cache.units, int(hunt().n) + pending, int(cache.legend))
	result.tier = int(hunt().tier)
	shown_slot = pending
	var inside: float = float(elapsed() - pending * PetHunt.cycle())
	arena.set_zone(str(hunt().zone))
	arena.show_encounter(cache.units, result, inside)

func refresh_live() -> void:
	if timer_label == null:
		return
	var cap: int = PetHunt.cap_seconds(profile())
	var gone: int = mini(elapsed(), cap)
	gauge_fraction = float(gone) / float(cap) if running() else 0.0
	timer_label.text = "%s / %s" % [format_time(gone), format_time(cap)] if running() else tr("parado")
	gauge_box.queue_redraw()
	var report: Dictionary = cache.report
	var eggs: int = 0
	for id: String in report.eggs:
		eggs += int(report.eggs[id])
	var values: Dictionary = {"slots": str(report.slots), "wins": "%d / %d" % [int(report.wins), int(report.slots)], "coins": str(report.coins), "xp": str(report.xp), "eggs": str(eggs), "caught": str((report.captured as Array).size())}
	for key: String in values:
		if tally.has(key):
			(tally[key] as Label).text = values[key]
	var forced: int = int(PetHunt.rules().boss.forced_after)
	var counter: int = int(cache.legend) if running() else int(hunt().legend)
	legend_fraction = clampf(float(counter) / float(forced), 0.0, 1.0)
	legend_label.text = tr("Aparece em até %d encontros") % maxi(0, forced - counter) if counter < forced else tr("Um Lendário vai aparecer!")
	legend_box.queue_redraw()

static func format_time(seconds: int) -> String:
	return "%d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]

# ---------- building ----------

func panel(rect: Rect2) -> Control:
	return PremiumUi.panel(holder, rect)

func label(text: String, rect: Rect2, font_size: int, color: Color = HudPaint.CREAM, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return UiKit.label(holder, text, rect, font_size, color, Color.TRANSPARENT, align)

func current_analysis() -> Dictionary:
	var key: String = "%s:%d:%s" % [zone, tier, str(team)]
	if key != analysis_key:
		analysis_key = key
		var pets: Array = []
		for uid: Variant in team:
			var pet: Dictionary = profile().find_pet(int(uid))
			if not pet.is_empty():
				pets.append(pet)
		analysis = PetHunt.analyse(PetHunt.team_units(pets), zone, tier) if not pets.is_empty() else {}
	return analysis

func build() -> void:
	build_zones()
	build_arena()
	build_team()
	build_bottom()
	if message != "":
		var note: Label = label(message, Rect2(620, 99, 604, 36), 16, HudPaint.GOLD_HOT, HORIZONTAL_ALIGNMENT_RIGHT)
		note.name = "HuntMessage"
		note.clip_text = true
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		note.size = Vector2(604, 36)
		note.tooltip_text = message
	refresh_live()

func build_zones() -> void:
	panel(Rect2(40, 148, 282, 394))
	label(tr("ZONAS DE CAÇA"), Rect2(56, 156, 246, 28), 20, HudPaint.GOLD)
	var zones: Array = PetHunt.zones()
	for i in range(zones.size()):
		var id: String = str(zones[i].id)
		var top: int = PetHunt.unlocked_tier(hunt(), id)
		var row: Button = UiKit.button(holder, "", Rect2(50, 186 + i * 38, 262, 34), pick_zone.bind(id), "card_hover" if id == zone else "slot")
		row.name = "Zone_" + id
		var icon: TextureRect = UiKit.art(row, str(zones[i].icon), Rect2(6, 2, 30, 30))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		UiKit.clipped(row, PetHunt.zone_name(id), Rect2(44, 0, 150, 18), 15, Pets.element_color(id).lightened(0.3))
		UiKit.label(row, tr("Nível %d de %d") % [top, PetHunt.tiers()], Rect2(44, 16, 150, 16), 12, Color("afbed1"))
		if running() and str(hunt().zone) == id:
			UiKit.label(row, tr("CAÇANDO"), Rect2(176, 8, 80, 18), 12, Color("9aff7a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
	var top_tier: int = PetHunt.unlocked_tier(hunt(), zone)
	label(tr("NÍVEL DE CAÇA"), Rect2(56, 382, 130, 24), 16, HudPaint.GOLD)
	var down: Button = UiKit.button(holder, "<", Rect2(192, 378, 34, 30), pick_tier.bind(-1))
	down.name = "TierDown"
	down.disabled = tier <= 1
	label("%d / %d" % [tier, PetHunt.tiers()], Rect2(226, 380, 52, 26), 17, HudPaint.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	var up: Button = UiKit.button(holder, ">", Rect2(278, 378, 34, 30), pick_tier.bind(1))
	up.name = "TierUp"
	up.disabled = tier >= top_tier
	if tier >= top_tier and top_tier < PetHunt.tiers():
		var need: int = int(PetHunt.rules().unlock_wins) - PetHunt.wins_at(hunt(), zone, tier)
		var hint: Label = label(tr("Faltam %d vitórias para o próximo") % maxi(0, need), Rect2(56, 412, 252, 18), 13, Color("afbed1"))
		hint.tooltip_text = tr("Cada nível abre depois de %d vitórias no nível abaixo.") % int(PetHunt.rules().unlock_wins)
	var view: Dictionary = current_analysis()
	label(tr("ESTIMATIVA DO TIME"), Rect2(56, 434, 246, 22), 16, HudPaint.GOLD)
	if view.is_empty():
		label(tr("Escolha mascotes para o time."), Rect2(56, 466, 250, 40), 14, Color("afbed1"))
		return
	var win: float = float(view.win)
	var win_color: Color = Color("9aff7a") if win >= 0.85 else (Color("ffd34d") if win >= 0.5 else Color("ff8f7e"))
	var lines: Array = [
		[tr("Selvagens nv %d  •  Vitórias: %d%%") % [int(view.level), roundi(win * 100.0)], win_color],
		[tr("Por hora: %d XP  •  %d moedas") % [int(view.xp), int(view.coins)], HudPaint.CREAM],
		[tr("Ovos por hora: %.1f") % float(view.eggs), HudPaint.CREAM],
		[tr("Contra o Lendário: ") + (tr("forte") if float(view.boss) >= 0.75 else (tr("equilibrado") if float(view.boss) >= 0.25 else tr("difícil"))), Color("9aff7a") if float(view.boss) >= 0.75 else (Color("ffd34d") if float(view.boss) >= 0.25 else Color("ff8f7e"))],
	]
	for i in range(lines.size()):
		var line: Label = UiKit.clipped(holder, str(lines[i][0]), Rect2(56, 458 + i * 18, 252, 19), 14, lines[i][1])
		line.tooltip_text = tr("Selvagens do nível da zona; o time sempre se cura entre os encontros.")

func build_arena() -> void:
	var field_zone: String = zone if not running() else str(hunt().zone)
	arena = HuntField.new() if HuntField.available(field_zone) else HuntArena.new()
	arena.position = Vector2(336, 148)
	arena.size = Vector2(580, 394)
	arena.audio = app.audio
	arena.set_zone(zone if not running() else str(hunt().zone))
	holder.add_child(arena)
	arena.hit_played.connect(on_hit)
	if arena is HuntField:
		(arena as HuntField).attack_played.connect(on_attack)
	if not running():
		arena.set_zone(zone)
		arena.clear(tr("Escolha a zona, o nível e o time, e inicie a caçada.\nOs mascotes lutam sozinhos, até com o jogo fechado."))

func on_hit(critical: bool, skill: bool) -> void:
	if app.audio == null:
		return
	app.audio.play("critical" if critical else ("hunt_skill" if skill else "hunt_hit"), -10.0 if not critical else -8.0)

# The sound of a move launched in the top-down field: claws, fire, ice or a spark.
func on_attack(style: String, element: String) -> void:
	if app.audio == null:
		return
	var sound: String = "hunt_zap"
	if style == "slash":
		sound = "hunt_claw"
	elif element == "gelo":
		sound = "hunt_ice"
	elif element == "sol":
		sound = "hunt_fire"
	app.audio.play(sound, -13.0)

func build_team() -> void:
	panel(Rect2(930, 148, 310, 394))
	var limit: int = int(PetHunt.rules().team_max)
	label(tr("TIME  %d / %d") % [team.size(), limit], Rect2(946, 156, 280, 28), 20, HudPaint.GOLD)
	for i in range(limit):
		var rect: Rect2 = Rect2(944 + i * 57, 190, 53, 66)
		if i < team.size():
			var pet: Dictionary = profile().find_pet(int(team[i]))
			var def: Dictionary = Pets.species_def(str(pet.species))
			var card: Button = UiKit.button(holder, "", rect, drop_from_team.bind(int(pet.uid)), "slot")
			card.name = "TeamSlot_%d" % i
			card.tooltip_text = "%s  (%s)\n%s" % [Pets.species_name(str(pet.species)), Pets.rarity_label(str(def.rarity)), tr("Clique para tirar do time")]
			card.add_child(BagSlot.glow_node(Rect2(3, 3, 47, 60), Pets.rarity_color(str(def.rarity))))
			PetWidgets.art(card, str(pet.species), Rect2(3, 2, 47, 47))
			UiKit.label(card, tr("Nv %d") % int(pet.level), Rect2(0, 47, 53, 16), 12, HudPaint.CREAM, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			var empty: Button = UiKit.button(holder, "+", rect, open_picker, "slot", 22)
			empty.name = "TeamAdd_%d" % i
			empty.tooltip_text = tr("Escolher mascotes")
	var choose: Button = UiKit.button(holder, tr("ESCOLHER MASCOTES"), Rect2(944, 264, 284, 32), open_picker, "button_blue", 17)
	choose.name = "TeamPick"
	choose.disabled = profile().pets.is_empty()
	label(tr("O QUE JÁ RENDEU"), Rect2(946, 306, 280, 24), 18, HudPaint.GOLD)
	tally = {}
	var rows: Array = [["slots", tr("Encontros")], ["wins", tr("Vitórias")], ["coins", tr("Moedas")], ["xp", tr("XP por mascote")], ["eggs", tr("Ovos")], ["caught", tr("Mascotes capturados")]]
	for i in range(rows.size()):
		label(str(rows[i][1]), Rect2(946, 334 + i * 24, 180, 22), 15, Color("c8d4e4"))
		tally[rows[i][0]] = label("0", Rect2(1110, 334 + i * 24, 116, 22), 16, HudPaint.CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
	label(tr("PRÓXIMO LENDÁRIO"), Rect2(946, 484, 280, 22), 15, Pets.rarity_color("lendario"))
	legend_box = Control.new()
	legend_box.position = Vector2(946, 508)
	legend_box.size = Vector2(278, 16)
	legend_box.draw.connect(func() -> void: HudPaint.gauge(legend_box, Rect2(0, 0, 278, 14), legend_fraction, Pets.rarity_color("lendario").lightened(0.2), Pets.rarity_color("lendario").darkened(0.4)))
	holder.add_child(legend_box)
	legend_label = label("", Rect2(946, 523, 284, 18), 12, Color("afbed1"))
	legend_label.tooltip_text = tr("Cada encontro aproxima o Lendário da zona. Derrote-o e ele entra para os seus mascotes.")

func build_bottom() -> void:
	panel(Rect2(40, 556, 1200, 130))
	var cap: int = PetHunt.cap_seconds(profile())
	var status: String = tr("Caçando em %s, nível %d") % [PetHunt.zone_name(str(hunt().zone)), int(hunt().tier)] if running() else tr("Nenhuma caçada em andamento")
	var heading: Label = UiKit.clipped(holder, status, Rect2(56, 562, 540, 28), 20, HudPaint.GOLD)
	heading.name = "HuntStatus"
	gauge_box = Control.new()
	gauge_box.position = Vector2(56, 596)
	gauge_box.size = Vector2(540, 22)
	gauge_box.draw.connect(func() -> void: HudPaint.gauge(gauge_box, Rect2(0, 0, 540, 20), gauge_fraction, Color("9fe6b5") if gauge_fraction < 0.9 else Color("ffd479"), Color("2d8a5a") if gauge_fraction < 0.9 else Color("a8741f")))
	holder.add_child(gauge_box)
	timer_label = label("", Rect2(56, 596, 540, 22), 15, HudPaint.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hours: int = cap / 3600
	var note: Label = label(tr("Acumula até %d h parado. O que passar do limite se perde.") % hours, Rect2(56, 622, 540, 20), 13, Color("afbed1"))
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var collect: Button = UiKit.button(holder, tr("COLETAR"), Rect2(56, 644, 170, 36), do_collect, "button_green", 20)
	collect.name = "HuntCollect"
	collect.set_meta("active", true)
	collect.disabled = busy or not running() or PetHunt.pending_slots(profile(), profile().hunt_now()) < 1
	collect.tooltip_text = tr("Recebe moedas, XP, ovos e os mascotes capturados até agora.")
	var changed_setup: bool = not running() or str(hunt().zone) != zone or int(hunt().tier) != tier or str(hunt().team) != str(team)
	var start: Button = UiKit.button(holder, tr("APLICAR E CAÇAR") if running() else tr("INICIAR CAÇADA"), Rect2(234, 644, 220, 36), do_start, "button_blue", 18)
	start.name = "HuntStart"
	start.disabled = busy or not changed_setup or team.is_empty()
	start.tooltip_text = tr("Muda a zona, o nível e o time. O que já rendeu é recolhido antes.") if running() else tr("O time começa a lutar e continua mesmo com o jogo fechado.")
	var stop: Button = UiKit.button(holder, tr("PARAR"), Rect2(462, 644, 110, 36), do_stop, "button_red", 16)
	stop.name = "HuntStop"
	stop.disabled = busy or not running()
	build_pass()

func build_pass() -> void:
	var owned: bool = profile().has_item(str(PetHunt.rules().pass_item))
	var box: Control = PremiumUi.panel(holder, Rect2(616, 566, 610, 108))
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon_path: String = "res://assets/cosmetics/passe_cacador/icon.png"
	if ResourceLoader.exists(icon_path):
		var icon: TextureRect = UiKit.art(box, load(icon_path), Rect2(10, 10, 88, 88))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UiKit.label(box, tr("PASSE DO CAÇADOR"), Rect2(110, 8, 300, 28), 21, HudPaint.GOLD_HOT)
	var copy: Label = UiKit.label(box, tr("A caçada passa a acumular até 8 horas em vez de 2: durma, trabalhe e colete tudo de manhã. Só conveniência: os mascotes não ficam mais fortes.") if not owned else tr("Passe ativo: sua caçada acumula até 8 horas. Obrigado por apoiar o jogo!"), Rect2(110, 36, 350, 66), 14, Color("c8d4e4") if not owned else Color("9aff7a"))
	copy.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	UiKit.wrap(copy, Vector2(350, 66))
	var entry: Dictionary = PremiumStore.product(str(PetHunt.rules().pass_item))
	if owned:
		UiKit.label(box, tr("VOCÊ TEM"), Rect2(470, 40, 130, 30), 20, Color("9aff7a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var ready: bool = PremiumStore.can_buy(app)
	UiKit.label(box, PremiumStore.price_label(entry, app.steam.available) if not entry.is_empty() else "", Rect2(470, 12, 130, 28), 20, UiKit.INFO, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var buy: Button = UiKit.button(box, PremiumStore.buy_label(app.steam.available), Rect2(466, 46, 136, 44), do_buy_pass, "button_blue", 14)
	buy.name = "BuyPass"
	buy.disabled = busy or not ready
	buy.tooltip_text = tr("Entre com a sua conta para comprar.") if not ready else PremiumStore.buy_hint(app.steam.available)

# ---------- choices ----------

func pick_zone(id: String) -> void:
	zone = id
	tier = clampi(tier, 1, PetHunt.unlocked_tier(hunt(), zone))
	message = ""
	rebuild()

func pick_tier(step: int) -> void:
	tier = clampi(tier + step, 1, PetHunt.unlocked_tier(hunt(), zone))
	message = ""
	rebuild()

func drop_from_team(uid: int) -> void:
	team.erase(uid)
	rebuild()

# ---------- team picker ----------

func open_picker() -> void:
	picker_page = 0
	build_picker()

func build_picker() -> void:
	if is_instance_valid(picker):
		holder.remove_child(picker)
		picker.queue_free()
	picker = Control.new()
	picker.name = "TeamPicker"
	picker.size = size
	holder.add_child(picker)
	var shade: ColorRect = UiKit.dim(picker, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var window: Control = PremiumUi.panel(picker, Rect2(110, 150, 1060, 540))
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	var limit: int = int(PetHunt.rules().team_max)
	UiKit.label(picker, tr("ESCOLHA O TIME  (%d / %d)") % [team.size(), limit], Rect2(130, 160, 600, 32), 24, HudPaint.GOLD)
	UiKit.label(picker, tr("Misture elementos: cada um vence um e perde para outro."), Rect2(130, 194, 900, 22), 15, Color("afbed1"))
	var list: Array[Dictionary] = profile().pets.duplicate()
	list.sort_custom(PetWidgets.pet_before)
	var pages: int = maxi(1, ceili(list.size() / float(PER_PAGE)))
	picker_page = clampi(picker_page, 0, pages - 1)
	for i in range(PER_PAGE):
		var index: int = picker_page * PER_PAGE + i
		if index >= list.size():
			break
		picker_card(list[index], Rect2(130 + (i % 8) * 125, 226 + (i / 8 as int) * 138, 118, 130))
	var back: Button = UiKit.button(picker, "<", Rect2(130, 644, 40, 32), turn_picker.bind(-1))
	back.disabled = picker_page == 0
	UiKit.label(picker, "%d/%d" % [picker_page + 1, pages], Rect2(170, 644, 80, 32), 16, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var forward: Button = UiKit.button(picker, ">", Rect2(250, 644, 40, 32), turn_picker.bind(1))
	forward.disabled = picker_page == pages - 1
	var done: Button = UiKit.button(picker, tr("PRONTO"), Rect2(990, 640, 170, 40), close_picker, "button_green", 20)
	done.name = "PickerDone"

func picker_card(pet: Dictionary, rect: Rect2) -> void:
	var uid: int = int(pet.uid)
	var def: Dictionary = Pets.species_def(str(pet.species))
	var chosen: bool = team.has(uid)
	var card: Button = UiKit.button(picker, "", rect, toggle_member.bind(uid), "card_hover" if chosen else "slot")
	card.name = "Pick_%d" % uid
	card.tooltip_text = "%s  (%s, %s)" % [Pets.species_name(str(pet.species)), Pets.rarity_label(str(def.rarity)), Pets.element_name(str(def.element))]
	card.add_child(BagSlot.glow_node(Rect2(4, 4, rect.size.x - 8, rect.size.y - 8), Pets.rarity_color(str(def.rarity))))
	PetWidgets.art(card, str(pet.species), Rect2(10, 4, 98, 98))
	var icon: TextureRect = UiKit.art(card, str(Pets.element_def(str(def.element)).icon), Rect2(4, 4, 24, 24))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UiKit.label(card, tr("Nv %d") % int(pet.level), Rect2(0, 106, 118, 20), 14, HudPaint.CREAM, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	if int(pet.stars) > 0:
		PetWidgets.stars(card, Vector2(6, 92), int(pet.stars), int(pet.stars), 5.0)
	if chosen:
		UiKit.label(card, str(team.find(uid) + 1), Rect2(90, 4, 24, 24), 18, Color("9aff7a"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

func toggle_member(uid: int) -> void:
	if team.has(uid):
		team.erase(uid)
	elif team.size() < int(PetHunt.rules().team_max):
		team.append(uid)
	else:
		app.audio.play("ui_error")
	build_picker()
	PremiumUi.skin(picker)

func turn_picker(step: int) -> void:
	picker_page += step
	build_picker()
	PremiumUi.skin(picker)

func close_picker() -> void:
	rebuild()

# ---------- operations ----------

func do_start() -> void:
	if busy:
		return
	var before: int = int(hunt().report.at)
	var first_uid: int = profile().next_uid
	var album_before: Array = profile().pet_album.duplicate()
	busy = true
	var error: String = (await app.do_op("hunt_set", [zone, tier, team])).error
	busy = false
	if not is_inside_tree():
		return
	if error != "":
		report_message(error, "")
		return
	adopt()
	await present(before, first_uid, album_before, tr("Caçada iniciada! O time já está lutando."))

func do_collect() -> void:
	if busy:
		return
	var before: int = int(hunt().report.at)
	var first_uid: int = profile().next_uid
	var album_before: Array = profile().pet_album.duplicate()
	busy = true
	var error: String = (await app.do_op("hunt_collect")).error
	busy = false
	if not is_inside_tree():
		return
	if error != "":
		report_message(error, "")
		return
	await present(before, first_uid, album_before, "")

func do_stop() -> void:
	if busy:
		return
	var before: int = int(hunt().report.at)
	var first_uid: int = profile().next_uid
	var album_before: Array = profile().pet_album.duplicate()
	busy = true
	var error: String = (await app.do_op("hunt_stop")).error
	busy = false
	if not is_inside_tree():
		return
	if error != "":
		report_message(error, "")
		return
	await present(before, first_uid, album_before, tr("Caçada parada."))

func do_buy_pass() -> void:
	message = tr("Aprove a compra na janela da Steam…") if app.steam.available else tr("Abrindo a página de pagamento…")
	rebuild()
	message = await app.buy_premium(str(PetHunt.rules().pass_item))
	if is_inside_tree():
		rebuild()

func report_message(error: String, success: String) -> void:
	message = error if error != "" else success
	app.audio.play("ui_error" if error != "" else "ui_confirm")
	changed.emit()
	rebuild()

# After an operation that settled the hunt: the summary, with a reveal for every pet the
# hunt caught that is epic or better.
func present(report_before: int, first_uid: int, album_before: Array, note: String) -> void:
	var report: Dictionary = hunt().report
	var settled: bool = int(report.at) != report_before and int(report.slots) > 0
	message = note
	changed.emit()
	rebuild()
	if not settled:
		app.audio.play("ui_confirm")
		return
	var born: Array[Dictionary] = []
	for pet: Dictionary in profile().pets:
		if int(pet.uid) >= first_uid:
			born.append(pet.duplicate(true))
	for pet: Dictionary in born:
		var rarity: String = str(Pets.species_def(str(pet.species)).rarity)
		if rarity == "lendario" or rarity == "epico":
			var moment: HatchOutcome = HatchOutcome.new()
			moment.capture = true
			moment.pet = pet
			moment.is_new = not album_before.has(str(pet.species))
			moment.audio = app.audio
			get_parent().add_child(moment)
			await moment.completed
			if not is_inside_tree():
				return
	show_report(report, born)

func show_report(report: Dictionary, born: Array[Dictionary]) -> void:
	var box: Control = Control.new()
	box.name = "HuntReport"
	box.size = size
	get_parent().add_child(box)
	var shade: ColorRect = UiKit.dim(box, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var window: Control = PremiumUi.panel(box, Rect2(350, 150, 580, 420))
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.label(box, tr("CAÇADA RECOLHIDA"), Rect2(370, 160, 540, 36), 28, HudPaint.GOLD_HOT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(box, tr("%s de caça  •  %d encontros") % [format_time(int(report.seconds)), int(report.slots)], Rect2(370, 198, 540, 24), 16, Color("afbed1"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var rows: Array = [
		[tr("Vitórias"), "%d  (%d %s)" % [int(report.wins), int(report.losses), tr("derrotas")]],
		[tr("Moedas"), "+%d" % int(report.coins)],
		[tr("XP por mascote"), "+%d" % int(report.xp)],
	]
	var eggs: Array[String] = []
	for id: String in report.eggs:
		eggs.append("%dx %s" % [int(report.eggs[id]), Pets.egg_name(id)])
	rows.append([tr("Ovos"), ", ".join(eggs) if not eggs.is_empty() else tr("nenhum")])
	for i in range(rows.size()):
		UiKit.label(box, str(rows[i][0]), Rect2(390, 236 + i * 28, 200, 26), 17, Color("c8d4e4"))
		var value: Label = UiKit.clipped(box, str(rows[i][1]), Rect2(580, 236 + i * 28, 330, 26), 17, HudPaint.CREAM, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_RIGHT)
		value.tooltip_text = str(rows[i][1])
	UiKit.label(box, tr("CAPTURAS"), Rect2(390, 354, 300, 24), 17, HudPaint.GOLD)
	if born.is_empty():
		var empty_text: String = tr("A Casa dos Mascotes estava cheia: a captura virou moedas.") if bool(report.full) else tr("Nenhum mascote desta vez.")
		UiKit.label(box, empty_text, Rect2(390, 382, 500, 24), 15, Color("afbed1"))
	for i in range(mini(born.size(), 8)):
		var def: Dictionary = Pets.species_def(str(born[i].species))
		var tile: Control = PremiumUi.panel(box, Rect2(390 + i * 64, 380, 58, 58))
		tile.add_child(BagSlot.glow_node(Rect2(2, 2, 54, 54), Pets.rarity_color(str(def.rarity))))
		PetWidgets.art(tile, str(born[i].species), Rect2(2, 2, 54, 54))
		tile.tooltip_text = "%s (%s)" % [Pets.species_name(str(born[i].species)), Pets.rarity_label(str(def.rarity))]
	if born.size() > 8:
		UiKit.label(box, "+%d" % (born.size() - 8), Rect2(900, 396, 30, 26), 16, HudPaint.CREAM)
	if not (report.levelups as Array).is_empty():
		var ups: Array[String] = []
		for entry: Dictionary in report.levelups:
			ups.append("%s %d→%d" % [Pets.species_name(str(entry.species)), int(entry.from), int(entry.to)])
		var up_label: Label = UiKit.label(box, tr("Subiram de nível: ") + ", ".join(ups), Rect2(390, 446, 500, 44), 14, Color("9fe6b5"))
		up_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		UiKit.wrap(up_label, Vector2(500, 44))
	var close: Button = UiKit.button(box, tr("OK"), Rect2(540, 500, 200, 44), box.queue_free, "button_green", 22)
	close.name = "ReportClose"
	PremiumUi.skin(box)
	app.audio.play("pet_levelup" if not born.is_empty() else "ui_confirm")
