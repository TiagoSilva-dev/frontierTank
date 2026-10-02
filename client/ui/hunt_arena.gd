class_name HuntArena
extends Control

# The window of the Caçada dos Mascotes (0.20): the team on the left and the wild group on
# the right fight in front of the zone's scenery. It replays one encounter exactly as
# PetHunt simulated it: `show_encounter` takes the result of `PetHunt.slot` (who showed up
# and the log of hits, heals and knock-outs) and the time already elapsed in it, then
# paces the log over the encounter's seconds: a short walk-in, the fight, and the outcome
# banner. Nothing here decides anything.

signal hit_played(critical: bool, skill: bool)
signal finished

const INTRO: float = 1.3
const OUTRO: float = 2.3

var zone: String = "sol"
var encounter: Dictionary = {}
var idle_text: String = ""
var audio: GameAudio

var t: float = 0.0
var age: float = 0.0
var allies: Array = []
var foes: Array = []
var steps: Array = []
var applied: int = 0
var interval: float = 0.5
var floaters: Array = []
var sparks: Array = []
var rings: Array = []
var banner: String = ""
var banner_color: Color = HudPaint.GOLD_HOT
var banner_age: float = 99.0
var shake: float = 0.0
var scenery: Texture2D
var textures: Dictionary = {}
var ended: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func set_zone(value: String) -> void:
	zone = value
	scenery = PetWidgets.texture(PetHunt.zone_art(zone))

func clear(text: String) -> void:
	encounter = {}
	idle_text = text
	allies = []
	foes = []

# `team` are the unit dicts the hunt fights with; `start` is how far into the encounter
# the player arrived (seconds).
func show_encounter(team: Array, result: Dictionary, start: float = 0.0) -> void:
	encounter = result
	idle_text = ""
	t = 0.0
	applied = 0
	ended = false
	floaters.clear()
	sparks.clear()
	rings.clear()
	banner = ""
	banner_age = 99.0
	allies = _units(team, 0)
	foes = _units(result.wilds, 100)
	steps = []
	for event: Dictionary in result.log:
		match str(event.k):
			"hit", "heal", "buff":
				steps.append([event])
			"down":
				if not steps.is_empty():
					(steps[steps.size() - 1] as Array).append(event)
	var fight_time: float = float(PetHunt.cycle()) - INTRO - OUTRO
	interval = minf(0.9, fight_time / maxf(1.0, float(steps.size())))
	advance(start, true)
	if bool(result.boss) and start < 0.5 and audio != null:
		audio.play("hunt_boss", -4.0)

func _units(list: Array, first_id: int) -> Array:
	var result: Array = []
	for i in range(list.size()):
		var unit: Dictionary = (list[i] as Dictionary).duplicate()
		unit.id = first_id + i
		unit.shown = float(unit.max)
		unit.hp = unit.max
		unit.alive = true
		unit.flash = 0.0
		unit.lunge = 0.0
		unit.lunge_dir = Vector2.RIGHT
		unit.fade = 1.0
		unit.phase = randf() * TAU
		if not textures.has(unit.species):
			textures[unit.species] = PetWidgets.species_texture(str(unit.species))
		result.append(unit)
	return result

func unit_by_id(id: int) -> Dictionary:
	for unit: Dictionary in allies + foes:
		if int(unit.id) == id:
			return unit
	return {}

func _process(delta: float) -> void:
	age += delta
	if not encounter.is_empty() and not ended:
		advance(delta, false)
	for unit: Dictionary in allies + foes:
		unit.shown = move_toward(float(unit.shown), float(unit.hp), maxf(float(unit.max) * 1.4, 40.0) * delta)
		unit.flash = maxf(0.0, float(unit.flash) - delta * 4.0)
		unit.lunge = maxf(0.0, float(unit.lunge) - delta * 3.2)
		if not bool(unit.alive):
			unit.fade = maxf(0.0, float(unit.fade) - delta * 1.8)
	for entry: Dictionary in floaters:
		entry.age = float(entry.age) + delta
	floaters = floaters.filter(func(entry: Dictionary) -> bool: return float(entry.age) < 1.1)
	for entry: Dictionary in sparks:
		entry.age = float(entry.age) + delta
	sparks = sparks.filter(func(entry: Dictionary) -> bool: return float(entry.age) < float(entry.life))
	for entry: Dictionary in rings:
		entry.age = float(entry.age) + delta
	rings = rings.filter(func(entry: Dictionary) -> bool: return float(entry.age) < 0.7)
	banner_age += delta
	shake = maxf(0.0, shake - delta * 14.0)
	queue_redraw()

# Moves the clock; every step whose time came is played (silently when `instant`).
func advance(seconds: float, instant: bool) -> void:
	t += seconds
	while applied < steps.size() and INTRO + applied * interval <= t:
		play_step(steps[applied], instant)
		applied += 1
	if not instant and not ended and t >= float(PetHunt.cycle()) - OUTRO:
		show_outcome()
	if t >= float(PetHunt.cycle()):
		ended = true
		finished.emit()

func play_step(step: Array, instant: bool) -> void:
	for event: Dictionary in step:
		match str(event.k):
			"hit":
				var target: Dictionary = unit_by_id(int(event.d))
				var attacker: Dictionary = unit_by_id(int(event.a))
				target.hp = int(event.hp)
				if instant:
					target.shown = target.hp
					continue
				var skill: bool = str(event.skill) != ""
				attacker.lunge = 1.0
				attacker.lunge_dir = (position_of(target) - position_of(attacker)).normalized()
				target.flash = 1.0
				var color: Color = Pets.element_color(str(attacker.element))
				var critical: bool = bool(event.crit)
				floaters.append({"text": "-%d" % int(event.dmg), "color": Color("ffd34d") if critical else Color("fff4e0"), "size": 28 if critical else 20, "at": position_of(target) + Vector2(randf_range(-12, 12), -span_of(target) * 0.62), "age": 0.0, "note": tr("Vantagem!") if int(event.el) > 0 else (tr("Resistiu") if int(event.el) < 0 else ""), "note_color": Color("9aff7a") if int(event.el) > 0 else Color("b4c2d4")})
				for i in range(8 if skill or critical else 4):
					sparks.append({"at": position_of(target), "dir": Vector2.from_angle(randf() * TAU) * randf_range(40, 130), "age": 0.0, "life": randf_range(0.3, 0.6), "color": color.lightened(0.3), "size": randf_range(2, 4)})
				if skill:
					banner = Lang.t(str(event.skill)) + "!"
					banner_color = color.lightened(0.25)
					banner_age = 0.0
					rings.append({"at": position_of(attacker), "color": color, "age": 0.0})
				shake = maxf(shake, 5.0 if critical else (3.0 if skill else 1.2))
				hit_played.emit(critical, skill)
			"down":
				var fallen: Dictionary = unit_by_id(int(event.u))
				fallen.alive = false
				if instant:
					fallen.fade = 0.0
			"heal":
				var healed: Dictionary = unit_by_id(int(event.d))
				healed.hp = int(event.hp)
				if instant:
					healed.shown = healed.hp
				elif int(event.amt) > 0:
					floaters.append({"text": "+%d" % int(event.amt), "color": Color("8dffb0"), "size": 20, "at": position_of(healed) + Vector2(0, -span_of(healed) * 0.62), "age": 0.0, "note": "", "note_color": Color.WHITE})
					rings.append({"at": position_of(healed), "color": Color("8dffb0"), "age": 0.0})
					if str(event.skill) != "" and banner_age > 0.5:
						banner = Lang.t(str(event.skill)) + "!"
						banner_color = Color("9fe6ff")
						banner_age = 0.0
			"buff":
				if instant:
					continue
				var buffed: Dictionary = unit_by_id(int(event.d))
				floaters.append({"text": tr("ATK +"), "color": Color("ffb86b"), "size": 16, "at": position_of(buffed) + Vector2(0, -span_of(buffed) * 0.62), "age": 0.0, "note": "", "note_color": Color.WHITE})
				if str(event.skill) != "" and banner_age > 0.5:
					banner = Lang.t(str(event.skill)) + "!"
					banner_color = Color("ffb86b")
					banner_age = 0.0

func show_outcome() -> void:
	ended = true
	if bool(encounter.won):
		banner = tr("LENDÁRIO DERROTADO!") if bool(encounter.boss) else tr("VITÓRIA!")
		banner_color = HudPaint.GOLD_HOT if bool(encounter.boss) else Color("9aff7a")
	else:
		banner = tr("O LENDÁRIO FUGIU!") if bool(encounter.boss) else tr("O TIME RECUOU")
		banner_color = Color("ff9a8a")
	banner_age = 0.0
	if audio != null and bool(encounter.won):
		audio.play("hunt_capture" if bool(encounter.boss) else "hunt_win", -6.0)
	finished.emit()

# ---------- layout ----------

func ground_rect() -> Rect2:
	return Rect2(18, 108, size.x - 36, size.y - 180)

# Two units per column, the first column closest to the middle; the columns step back
# and stagger so five pets still read as a formation.
func slot_position(index: int, count: int, foe: bool) -> Vector2:
	var ground: Rect2 = ground_rect()
	var column: int = index / 2
	var row: int = index % 2
	var in_column: int = mini(2, count - column * 2)
	var x: float = ground.position.x + 190.0 - column * 74.0
	var y: float = ground.position.y + ground.size.y * 0.5 + (row - (in_column - 1) / 2.0) * 104.0 + (column % 2) * 16.0
	if foe:
		x = size.x - x
	return Vector2(x, y)

func span_of(unit: Dictionary) -> float:
	var count: int = (foes if int(unit.id) >= 100 else allies).size()
	return 176.0 if bool(unit.boss) else (112.0 if count <= 2 else 96.0)

func position_of(unit: Dictionary) -> Vector2:
	var foe: bool = int(unit.id) >= 100
	var list: Array = foes if foe else allies
	var index: int = int(unit.id) - (100 if foe else 0)
	var point: Vector2 = slot_position(index, list.size(), foe)
	if foe:
		var walk: float = HudPaint.ease_out(clampf(t / INTRO, 0.0, 1.0))
		point.x += (1.0 - walk) * 150.0
	return point

# ---------- drawing ----------

func _draw() -> void:
	var inner: Rect2 = HudPaint.frame(self, Rect2(Vector2.ZERO, size), 0.35)
	if scenery != null:
		draw_texture_rect(scenery, inner, false)
	else:
		HudPaint.vgradient(self, inner, Color("101a2e"), Color("1b1530"))
	var tint: Color = Pets.element_color(zone)
	draw_rect(inner, Color(tint.r * 0.18, tint.g * 0.18, tint.b * 0.25, 0.30))
	HudPaint.vgradient(self, Rect2(5, 5, size.x - 10, 70), Color(0.02, 0.03, 0.08, 0.92), Color(0.02, 0.03, 0.08, 0))
	HudPaint.vgradient(self, Rect2(5, size.y - 92, size.x - 10, 87), Color(0.02, 0.03, 0.08, 0), Color(0.02, 0.03, 0.08, 0.97))
	if encounter.is_empty():
		_draw_idle()
		return
	var offset: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	draw_set_transform(offset, 0.0, Vector2.ONE)
	var boss: bool = bool(encounter.boss)
	if boss:
		HudPaint.rays(self, Vector2(size.x * 0.72, 220), 14, 380, age * 0.2, Color(HudPaint.GOLD, 0.10), 0.02)
		draw_rect(inner, Color(0.35, 0.05, 0.02, 0.12 + 0.05 * sin(age * 3.0)))
	var everyone: Array = allies + foes
	everyone.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return position_of(a).y < position_of(b).y)
	for unit: Dictionary in everyone:
		_draw_unit(unit)
	for entry: Dictionary in rings:
		var progress: float = float(entry.age) / 0.7
		draw_arc(entry.at, 14 + progress * 70, 0, TAU, 48, Color(entry.color, 1.0 - progress), 3.0)
	for entry: Dictionary in sparks:
		var progress: float = float(entry.age) / float(entry.life)
		HudPaint.sparkle(self, (entry.at as Vector2) + (entry.dir as Vector2) * float(entry.age), float(entry.size), Color(entry.color, 1.0 - progress))
	for entry: Dictionary in floaters:
		var progress: float = float(entry.age) / 1.1
		var at: Vector2 = (entry.at as Vector2) + Vector2(0, -progress * 34.0)
		var alpha: float = 1.0 - progress * progress
		HudPaint.outlined(self, at - Vector2(40, 14), str(entry.text), int(entry.size), Color(entry.color, alpha), Color(0.02, 0.03, 0.08, alpha), 80, HORIZONTAL_ALIGNMENT_CENTER)
		if str(entry.note) != "":
			HudPaint.outlined(self, at - Vector2(50, -8), str(entry.note), 13, Color(entry.note_color, alpha), Color(0.02, 0.03, 0.08, alpha), 100, HORIZONTAL_ALIGNMENT_CENTER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud(boss)

func _draw_idle() -> void:
	HudPaint.outlined(self, Vector2(20, size.y * 0.42), idle_text, 20, HudPaint.CREAM, HudPaint.INK, size.x - 40, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(24):
		var p: Vector2 = Vector2(20 + fmod(i * 83.0, size.x - 40), size.y - 14 - fmod(age * (10 + i % 5 * 6) + i * 37.0, size.y - 28))
		HudPaint.sparkle(self, p, 2 + i % 3, Color(Pets.element_color(zone).lightened(0.4), maxf(0.0, 0.3 * sin(PI * (size.y - p.y) / size.y))))

func _draw_unit(unit: Dictionary) -> void:
	var texture: Texture2D = textures.get(unit.species)
	if texture == null:
		return
	var foe: bool = int(unit.id) >= 100
	var boss: bool = bool(unit.boss)
	var point: Vector2 = position_of(unit)
	var lunge: float = float(unit.lunge)
	point += (unit.lunge_dir as Vector2) * 46.0 * sin(PI * (1.0 - lunge)) * (1.0 if lunge > 0.0 else 0.0)
	var span: float = span_of(unit)
	var fade: float = float(unit.fade)
	var alive: bool = bool(unit.alive)
	var bob: float = sin(age * 2.6 + float(unit.phase)) * 3.0 if alive else 0.0
	HudPaint.glow(self, point + Vector2(0, span * 0.38), span * 0.45, Color(0, 0, 0, 0.35 * fade), 3)
	if boss and alive:
		HudPaint.glow(self, point, span * 0.7, Color(HudPaint.GOLD, 0.35), 4)
	var flash: float = float(unit.flash)
	var color: Color = Color(1.0, 1.0 - flash * 0.55, 1.0 - flash * 0.55, fade if foe else (1.0 if alive else 0.4))
	if not alive and not foe:
		color = Color(0.5, 0.5, 0.55, 0.45)
	var tilt: float = 0.0 if alive else (0.5 if foe else 1.2)
	draw_set_transform(point + Vector2(0, bob) + (Vector2(0, 8) if not alive else Vector2.ZERO), tilt * (-1.0 if foe else 1.0), Vector2(-1 if foe else 1, 1))
	draw_texture_rect(texture, Rect2(Vector2(-span / 2, -span / 2), Vector2(span, span)), false, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not alive and foe and fade <= 0.0:
		return
	if alive:
		var width: float = 70.0 if not boss else 120.0
		var bar: Rect2 = Rect2(point.x - width / 2, point.y - span / 2 + 2, width, 8)
		draw_rect(Rect2(bar.position - Vector2(1, 1), bar.size + Vector2(2, 2)), Color(0.02, 0.03, 0.08, 0.9))
		var fraction: float = clampf(float(unit.shown) / float(unit.max), 0.0, 1.0)
		var hue: Color = Color("5fdc7a") if fraction > 0.5 else (Color("ffd34d") if fraction > 0.25 else Color("ff6a5a"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), hue)
		var label: String = tr("Nv %d") % int(unit.level)
		if boss:
			label = tr("LENDÁRIO") + "  " + label
		HudPaint.outlined(self, Vector2(bar.position.x - 10, bar.position.y - 4), label, 13, HudPaint.GOLD_HOT if boss else HudPaint.CREAM, Color(0.02, 0.03, 0.08), width + 20, HORIZONTAL_ALIGNMENT_CENTER, 3)

func _draw_hud(boss: bool) -> void:
	HudPaint.fancy(self, Vector2(0, 36), PetHunt.zone_name(zone), 26, HudPaint.CREAM, HudPaint.BRONZE_DARK, size.x, HORIZONTAL_ALIGNMENT_CENTER, 3, 8)
	var tier_text: String = tr("Nível de caça %d") % int(encounter.get("tier", 1)) if encounter.has("tier") else ""
	if tier_text != "":
		HudPaint.outlined(self, Vector2(0, 58), tier_text, 15, Color("afbed1"), HudPaint.INK, size.x, HORIZONTAL_ALIGNMENT_CENTER, 3)
	if boss and t < INTRO + 1.6:
		var pulse: float = 0.65 + 0.35 * sin(age * 8.0)
		HudPaint.fancy(self, Vector2(0, 98), tr("UM LENDÁRIO APARECEU!"), 30, Color(HudPaint.GOLD_HOT, pulse), HudPaint.BRONZE_DARK, size.x, HORIZONTAL_ALIGNMENT_CENTER, 3, 8)
	if banner != "" and banner_age < 1.6:
		var grow: float = HudPaint.ease_back(clampf(banner_age / 0.25, 0.0, 1.0))
		var alpha: float = clampf((1.6 - banner_age) / 0.4, 0.0, 1.0) if not ended else 1.0
		HudPaint.fancy(self, Vector2(0, 98 + (1.0 - grow) * 10.0), banner, int(30 + grow * 8), banner_color, HudPaint.BRONZE_DARK, size.x, HORIZONTAL_ALIGNMENT_CENTER, 3, 8, alpha)
	if ended and bool(encounter.won) and banner_age < 99.0:
		var loot: String = "+%d %s   +%d XP" % [int(encounter.coins), tr("moedas"), int(encounter.xp)]
		HudPaint.outlined(self, Vector2(0, 124), loot, 20, Color(HudPaint.CREAM, clampf(banner_age * 3.0, 0.0, 1.0)), HudPaint.INK, size.x, HORIZONTAL_ALIGNMENT_CENTER)
		if str(encounter.egg) != "":
			HudPaint.outlined(self, Vector2(0, 150), tr("Achou um ovo: %s!") % Pets.egg_name(str(encounter.egg)), 20, Color("9fe6b5", clampf(banner_age * 3.0, 0.0, 1.0)), HudPaint.INK, size.x, HORIZONTAL_ALIGNMENT_CENTER)
		for i in range((encounter.captured as Array).size()):
			var species: String = str(encounter.captured[i])
			HudPaint.outlined(self, Vector2(0, 176 + i * 26), tr("Capturou %s!") % Pets.species_name(species), 22, Color(Pets.rarity_color(str(Pets.species_def(species).rarity)).lightened(0.2), clampf(banner_age * 3.0, 0.0, 1.0)), HudPaint.INK, size.x, HORIZONTAL_ALIGNMENT_CENTER)
