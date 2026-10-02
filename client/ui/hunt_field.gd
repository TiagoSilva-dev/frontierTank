class_name HuntField
extends HuntArena

# The top-down version of the Caçada window (0.21 pilot): the trainer stands in an open
# field (FieldMap) with the team around them, the wild group wanders in from the right,
# and the pets chase their targets and attack with the element's move: a flame bolt, a sun
# orb, a breath of fire along the whole line, or a claw slash. It replays the same
# PetHunt log as HuntArena (who hits whom, damage, knock-outs), only the staging differs:
# every hit launches its effect at once and lands the damage when the effect arrives.

signal attack_played(style: String, element: String)

const SCALE: float = 1.45
# Seconds before the first blow: the wild group walks in from the edge while the team
# goes out to meet it (the album arena only needs 1.3).
const APPROACH: float = 4.2
const FX_ROOT: String = "res://assets/field/fx/"
const ENGAGED: float = 1.2
const STYLES: Dictionary = {
	"fenix_dourada": "bolt", "leao_dourado": "breath", "escaravelho_solar": "orb", "chacal_ambar": "slash",
	"brasinha": "orb", "diabrete_mascarado": "slash", "cao_de_lava": "breath", "rei_mascara": "bolt",
	"pinguim_cristal": "orb", "coelho_neve": "slash", "raposa_glacial": "bolt", "lobo_boreal": "breath",
	"nuvenzinha": "orb", "passaro_trovao": "bolt", "grifinho": "slash", "dragao_tempestade": "breath",
	"corvo_runico": "bolt", "javali_guerra": "slash", "urso_berserker": "slash", "lobo_fenrir": "breath",
}
const RANGES: Dictionary = {"bolt": 170.0, "orb": 190.0, "breath": 130.0, "slash": 34.0}
const FLIGHT: Dictionary = {"bolt": 0.26, "orb": 0.32, "breath": 0.2, "slash": 0.12}
# Every element has its own recoloured set of the three effects (assets/field/fx), so the
# tint only adds a little life on top (the sun set is the original orange).
const TINTS: Dictionary = {
	"sol": Color.WHITE, "mascara": Color(1.1, 0.95, 1.15), "gelo": Color(1.05, 1.05, 1.1),
	"ceu": Color.WHITE, "viking": Color.WHITE,
}
const FX_STYLES: Array = ["bolt", "orb", "slash"]
# The trainer walks to a spot behind the team for the fight and out into the field to
# gather the loot while the result is on; the critters wander outside the fight area.
const TRAINER_BEHIND: Vector2 = Vector2(-135, 10)
const TRAINER_LOOT: Vector2 = Vector2(18, 34)
const TRAINER_ENTRY: Vector2 = Vector2(-330, 30)
const AMBIENT_COUNT: int = 7

var zoom: float = SCALE
var map: FieldMap
var textures_fx: Dictionary = {}
var trainer: Dictionary = {"pos": Vector2.ZERO, "face": Vector2.DOWN, "moving": false, "walk": 0.0}
var ambient: Array = []
var camera: Vector2 = Vector2.ZERO
var effects: Array = []
var impacts: Array = []
var embers: Array = []

static func available(zone_id: String) -> bool:
	return FieldMap.available(zone_id)

func _ready() -> void:
	super._ready()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	camera = _middle()

# One texture per effect style: the zone's own recoloured file when there is one.
func _fx(style: String, element: String) -> Texture2D:
	var key: String = style + "_" + element
	if not textures_fx.has(key):
		var path: String = FX_ROOT + key + ".png"
		textures_fx[key] = PetWidgets.texture(path) if ResourceLoader.exists(path) else PetWidgets.texture(FX_ROOT + style + ".png")
	return textures_fx[key]

func set_zone(value: String) -> void:
	# follow_arena calls this every encounter: only a change of zone rebuilds the field.
	if zone == value and map != null:
		return
	zone = value
	map = FieldMap.for_zone(zone)
	trainer.pos = _middle() + TRAINER_ENTRY
	trainer.face = Vector2.RIGHT
	trainer.moving = false
	_spawn_ambient()

func clear(text: String) -> void:
	super.clear(text)
	effects.clear()
	impacts.clear()

static func _middle() -> Vector2:
	return FieldMap.world_size() * 0.5

# ---------- setup ----------

func show_encounter(team: Array, result: Dictionary, start: float = 0.0) -> void:
	effects.clear()
	impacts.clear()
	embers.clear()
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
				if str(event.k) == "hit":
					# Each fighter heads for the first one it will hit.
					var attacker: Dictionary = unit_by_id(int(event.a))
					if int(attacker.target) < 0:
						attacker.target = int(event.d)
			"down":
				if not steps.is_empty():
					(steps[steps.size() - 1] as Array).append(event)
	var fight_time: float = float(PetHunt.cycle()) - APPROACH - OUTRO
	interval = minf(0.9, fight_time / maxf(1.0, float(steps.size())))
	advance(start, true)
	if start >= APPROACH:
		for unit: Dictionary in allies + foes:
			unit.pos = unit.home
		trainer.pos = _trainer_goal()
		trainer.moving = false
	if bool(result.boss) and start < 0.5 and audio != null:
		audio.play("hunt_boss", -4.0)

# Same pacing as the album arena with the longer approach.
func advance(seconds: float, instant: bool) -> void:
	t += seconds
	while applied < steps.size() and APPROACH + applied * interval <= t:
		play_step(steps[applied], instant)
		applied += 1
	if not instant and not ended and t >= float(PetHunt.cycle()) - OUTRO:
		show_outcome()
	if t >= float(PetHunt.cycle()):
		ended = true
		finished.emit()

# World positions: the team in a loose arc behind the trainer, the wild group on the
# right (walking in from further out at the start).
func _units(list: Array, first_id: int) -> Array:
	var units: Array = super._units(list, first_id)
	var foe: bool = first_id >= 100
	var middle: Vector2 = _middle()
	for i in range(units.size()):
		var unit: Dictionary = units[i]
		var row: float = float(i) - (units.size() - 1) / 2.0
		var home: Vector2
		if foe:
			home = middle + Vector2(60 + absf(row) * 10.0 + (i % 2) * 26, row * 32 + sin(i * 2.1) * 5)
		else:
			home = middle + Vector2(-44 - absf(row) * 10.0 - (i % 2) * 30, row * 32)
		unit.home = home
		unit.pos = home + (Vector2(250, randf_range(-26, 26)) if foe else Vector2(randf_range(-6, 6), randf_range(-6, 6)))
		unit.face = Vector2.LEFT if foe else Vector2.RIGHT
		unit.walk = randf() * 8.0
		unit.moving = false
		unit.target = -1
		unit.engaged = 0.0
		unit.style = str(STYLES.get(str(unit.species), "bolt"))
	return units

func position_of(unit: Dictionary) -> Vector2:
	return unit.pos

func span_of(unit: Dictionary) -> float:
	return 100.0 if bool(unit.boss) else 62.0

func range_of(unit: Dictionary) -> float:
	return float(RANGES[str(unit.style)]) * (1.25 if bool(unit.boss) else 1.0)

func attack_tint(unit: Dictionary) -> Color:
	return TINTS.get(str(unit.element), Color.WHITE)

# ---------- the log ----------

func play_step(step: Array, instant: bool) -> void:
	for event: Dictionary in step:
		match str(event.k):
			"hit":
				var target: Dictionary = unit_by_id(int(event.d))
				var attacker: Dictionary = unit_by_id(int(event.a))
				if instant:
					target.hp = int(event.hp)
					target.shown = target.hp
					continue
				attacker.target = int(event.d)
				attacker.engaged = ENGAGED
				var flight: float = float(FLIGHT[str(attacker.style)])
				_launch(attacker, target, event, flight)
				impacts.append({"time": flight, "event": event})
			"down":
				var fallen: Dictionary = unit_by_id(int(event.u))
				if instant:
					fallen.alive = false
					fallen.fade = 0.0
				else:
					# Let the last blow land before the unit drops.
					impacts.append({"time": 0.5, "event": event})
			"heal":
				var healed: Dictionary = unit_by_id(int(event.d))
				healed.hp = int(event.hp)
				if instant:
					healed.shown = healed.hp
				elif int(event.amt) > 0:
					floaters.append({"text": "+%d" % int(event.amt), "color": Color("8dffb0"), "size": 20, "at": healed.pos + Vector2(0, -span_of(healed) * 0.9), "age": 0.0, "note": "", "note_color": Color.WHITE})
					rings.append({"at": healed.pos, "color": Color("8dffb0"), "age": 0.0})
					if str(event.skill) != "" and banner_age > 0.5:
						banner = Lang.t(str(event.skill)) + "!"
						banner_color = Color("9fe6ff")
						banner_age = 0.0
			"buff":
				if instant:
					continue
				var buffed: Dictionary = unit_by_id(int(event.d))
				floaters.append({"text": tr("ATK +"), "color": Color("ffb86b"), "size": 16, "at": buffed.pos + Vector2(0, -span_of(buffed) * 0.9), "age": 0.0, "note": "", "note_color": Color.WHITE})
				if str(event.skill) != "" and banner_age > 0.5:
					banner = Lang.t(str(event.skill)) + "!"
					banner_color = Color("ffb86b")
					banner_age = 0.0

# Starts the visual of one attack; the damage lands later from `impacts`.
func _launch(attacker: Dictionary, target: Dictionary, event: Dictionary, flight: float) -> void:
	var style: String = str(attacker.style)
	var skill: bool = str(event.skill) != ""
	var from: Vector2 = attacker.pos + Vector2(0, -22)
	var to: Vector2 = target.pos + Vector2(0, -22)
	var tint: Color = attack_tint(attacker)
	attack_played.emit(style, str(attacker.element))
	attacker.lunge = 1.0
	attacker.lunge_dir = (target.pos - attacker.pos).normalized()
	attacker.face = attacker.lunge_dir
	effects.append({"style": style, "from": from, "to": to, "age": 0.0, "life": flight + (0.3 if style == "breath" else 0.12), "flight": flight, "tint": tint, "element": str(attacker.element), "big": 1.5 if skill else 1.0})

func _land(event: Dictionary) -> void:
	match str(event.k):
		"hit":
			var target: Dictionary = unit_by_id(int(event.d))
			var attacker: Dictionary = unit_by_id(int(event.a))
			target.hp = int(event.hp)
			target.flash = 1.0
			var tint: Color = Pets.element_color(str(attacker.element))
			var critical: bool = bool(event.crit)
			var skill: bool = str(event.skill) != ""
			var at: Vector2 = target.pos + Vector2(0, -22)
			floaters.append({"text": "-%d" % int(event.dmg), "color": Color("ffd34d") if critical else Color("fff4e0"), "size": 28 if critical else 20, "at": at + Vector2(randf_range(-12, 12), -span_of(target) * 0.5), "age": 0.0, "note": tr("Vantagem!") if int(event.el) > 0 else (tr("Resistiu") if int(event.el) < 0 else ""), "note_color": Color("9aff7a") if int(event.el) > 0 else Color("b4c2d4")})
			for i in range(14 if skill or critical else 7):
				embers.append({"at": at, "dir": Vector2.from_angle(randf() * TAU) * randf_range(30, 120) + Vector2(0, -50), "age": 0.0, "life": randf_range(0.35, 0.75), "color": tint.lightened(randf_range(0.0, 0.5)), "size": randf_range(2, 5)})
			if skill:
				banner = Lang.t(str(event.skill)) + "!"
				banner_color = tint.lightened(0.25)
				banner_age = 0.0
				rings.append({"at": attacker.pos, "color": tint, "age": 0.0})
			rings.append({"at": at, "color": tint.lightened(0.3), "age": 0.3})
			shake = maxf(shake, 5.0 if critical else (3.0 if skill else 1.2))
			hit_played.emit(critical, skill)
		"down":
			var fallen: Dictionary = unit_by_id(int(event.u))
			fallen.alive = false

# ---------- per frame ----------

func _process(delta: float) -> void:
	super._process(delta)
	for item: Dictionary in impacts:
		item.time = float(item.time) - delta
	var due: Array = impacts.filter(func(item: Dictionary) -> bool: return float(item.time) <= 0.0)
	impacts = impacts.filter(func(item: Dictionary) -> bool: return float(item.time) > 0.0)
	for item: Dictionary in due:
		_land(item.event)
	for entry: Dictionary in effects:
		entry.age = float(entry.age) + delta
	effects = effects.filter(func(entry: Dictionary) -> bool: return float(entry.age) < float(entry.life))
	for entry: Dictionary in embers:
		entry.age = float(entry.age) + delta
	embers = embers.filter(func(entry: Dictionary) -> bool: return float(entry.age) < float(entry.life))
	_move(delta)
	_move_trainer(delta)
	_move_ambient(delta)
	_follow_camera(delta)

func _move(delta: float) -> void:
	for unit: Dictionary in allies + foes:
		var goal: Vector2 = unit.home
		var speed: float = 80.0
		var alive: bool = bool(unit.alive)
		if alive and t < APPROACH:
			# Walking in: the wild group toward its place, the team toward its first target.
			if int(unit.id) >= 100:
				speed = 62.0
			else:
				var first: Dictionary = unit_by_id(int(unit.target))
				if not first.is_empty():
					var gap: Vector2 = unit.pos - first.pos
					goal = first.pos + gap.normalized() * range_of(unit)
					speed = 52.0
		elif alive and float(unit.engaged) > 0.0:
			unit.engaged = float(unit.engaged) - delta
			var target: Dictionary = unit_by_id(int(unit.target))
			if not target.is_empty() and bool(target.alive):
				var away: Vector2 = unit.pos - target.pos
				if away.length() < 1.0:
					away = Vector2.LEFT if int(unit.id) >= 100 else Vector2.RIGHT
				goal = target.pos + away.normalized() * range_of(unit)
				speed = 190.0
		elif alive:
			goal += Vector2(cos(age * 0.8 + float(unit.phase)), sin(age * 1.1 + float(unit.phase))) * 9.0
		var to: Vector2 = goal - unit.pos
		unit.moving = alive and to.length() > 4.0
		if unit.moving:
			var step: Vector2 = to.normalized() * minf(speed * delta, to.length())
			unit.pos = unit.pos + step
			if float(unit.lunge) <= 0.0:
				unit.face = to.normalized()
			unit.walk = float(unit.walk) + delta * speed / 11.0
	_separate()

# ---------- the trainer ----------

# Where the trainer wants to be: behind the team during the fight, out in the field picking
# up the loot while the result is shown, at the entry mark when nothing is going on.
func _trainer_goal() -> Vector2:
	if encounter.is_empty():
		return _middle() + TRAINER_BEHIND
	if t >= float(PetHunt.cycle()) - OUTRO:
		return _middle() + TRAINER_LOOT
	return _middle() + TRAINER_BEHIND

func _move_trainer(delta: float) -> void:
	var to: Vector2 = _trainer_goal() - (trainer.pos as Vector2)
	var gap: float = to.length()
	trainer.moving = gap > 4.0
	if bool(trainer.moving):
		var speed: float = 74.0 if gap < 160.0 else 96.0
		trainer.pos = trainer.pos + to.normalized() * minf(speed * delta, gap)
		trainer.face = to.normalized()
		trainer.walk = float(trainer.walk) + delta * speed / 11.0
	elif not foes.is_empty() and t < float(PetHunt.cycle()) - OUTRO:
		# Standing behind the team: watch the fight.
		trainer.face = Vector2.RIGHT

# ---------- wild critters wandering around ----------

# The fight happens in this part of the field: critters keep out of it while it lasts.
func _fight_area() -> Rect2:
	var middle: Vector2 = _middle()
	return Rect2(middle + Vector2(-200, -112), Vector2(380, 224))

func _fight_on() -> bool:
	return not encounter.is_empty() and t < float(PetHunt.cycle()) - OUTRO

func _spawn_ambient() -> void:
	ambient = []
	var species: Array[Dictionary] = Pets.species_of_element(zone)
	if species.is_empty():
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("critters:" + zone)
	var weights: Array = [5, 3, 2, 1]
	var bag: Array = []
	for def: Dictionary in species:
		for i in range(int(weights[clampi(Pets.rarity_index(str(def.rarity)), 0, 3)])):
			bag.append(str(def.id))
	for i in range(AMBIENT_COUNT):
		var critter: Dictionary = {
			"species": str(bag[rng.randi() % bag.size()]),
			"level": rng.randi_range(1, 4),
			"pos": Vector2.ZERO, "face": Vector2.LEFT, "goal": Vector2.ZERO,
			"wait": rng.randf_range(0.0, 3.0), "walk": rng.randf() * 8.0, "moving": false,
		}
		critter.pos = _critter_spot(rng, false)
		critter.goal = critter.pos
		ambient.append(critter)

# A spot to wander to: anywhere near the middle of the field; outside the fight area while a
# fight is on.
func _critter_spot(rng: RandomNumberGenerator, avoid: bool) -> Vector2:
	var middle: Vector2 = _middle()
	var area: Rect2 = _fight_area()
	for tries in range(12):
		var spot: Vector2 = middle + Vector2(rng.randf_range(-340, 340), rng.randf_range(-190, 190))
		if not avoid or not area.grow(14.0).has_point(spot):
			return spot
	return middle + Vector2(330 * (1 if rng.randf() < 0.5 else -1), rng.randf_range(-150, 150))

func _move_ambient(delta: float) -> void:
	var fight: bool = _fight_on()
	var area: Rect2 = _fight_area()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for critter: Dictionary in ambient:
		var pos: Vector2 = critter.pos
		var speed: float = 26.0
		if fight and area.grow(6.0).has_point(pos):
			# Make way: head straight out of the fight area, quicker than a stroll.
			var from_middle: Vector2 = pos - area.get_center()
			var sideways: bool = absf(from_middle.x) / area.size.x >= absf(from_middle.y) / area.size.y
			var out: Vector2 = Vector2(signf(from_middle.x), 0.0) if sideways else Vector2(0.0, signf(from_middle.y))
			if out == Vector2.ZERO:
				out = Vector2.RIGHT
			critter.goal = pos + out * 80.0
			critter.wait = 0.0
			speed = 56.0
		var to: Vector2 = (critter.goal as Vector2) - pos
		if to.length() > 3.0:
			critter.moving = true
			critter.pos = pos + to.normalized() * minf(speed * delta, to.length())
			critter.face = to.normalized()
			critter.walk = float(critter.walk) + delta * speed / 9.0
		else:
			critter.moving = false
			critter.wait = float(critter.wait) - delta
			if float(critter.wait) <= 0.0:
				critter.goal = _critter_spot(rng, fight)
				critter.wait = rng.randf_range(1.5, 5.0)

# Keeps the fighters from standing on top of each other when several chase one target.
func _separate() -> void:
	var everyone: Array = allies + foes
	for i in range(everyone.size()):
		var a: Dictionary = everyone[i]
		if not bool(a.alive):
			continue
		for j in range(i + 1, everyone.size()):
			var b: Dictionary = everyone[j]
			if not bool(b.alive):
				continue
			var apart: Vector2 = a.pos - b.pos
			var gap: float = apart.length()
			if gap < 30.0:
				var push: Vector2 = (apart / gap if gap > 0.5 else Vector2.from_angle(float(i))) * (30.0 - gap) * 0.5
				a.pos = a.pos + push
				b.pos = b.pos - push

func _follow_camera(delta: float) -> void:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for unit: Dictionary in allies + foes:
		if bool(unit.alive):
			low = low.min(unit.pos)
			high = high.max(unit.pos)
	if low.x != INF:
		low = low.min(trainer.pos)
		high = high.max(trainer.pos)
	var goal: Vector2 = _middle()
	var wanted: float = SCALE
	if low.x != INF:
		goal = (low + high) * 0.5
		# Zoom out a little when the group is wider than the window (a Lendário's reach).
		wanted = clampf(minf((size.x - 90.0) / maxf(1.0, high.x - low.x + 120.0), (size.y - 170.0) / maxf(1.0, high.y - low.y + 110.0)), 1.05, SCALE)
	zoom = lerpf(zoom, wanted, clampf(delta * 1.5, 0.0, 1.0))
	# A little above the middle of the action so the title does not cover the back row.
	camera = camera.lerp(goal + Vector2(0, -30), clampf(delta * 2.5, 0.0, 1.0))

func _origin() -> Vector2:
	var half: Vector2 = size * 0.5 / zoom
	var focus: Vector2 = camera.clamp(half, FieldMap.world_size() - half)
	return size * 0.5 - focus * zoom

func _screen(point: Vector2) -> Vector2:
	return _origin() + point * zoom

# ---------- drawing ----------

func _draw() -> void:
	var inner: Rect2 = HudPaint.frame(self, Rect2(Vector2.ZERO, size), 0.35)
	if map == null or map.texture == null:
		HudPaint.vgradient(self, inner, Color("101a2e"), Color("1b1530"))
		return
	var origin: Vector2 = _origin()
	var shaking: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	origin += shaking
	draw_texture_rect(map.texture, Rect2(origin, FieldMap.world_size() * zoom), false, map.shade)
	# Everything with a place on the ground, sorted by depth.
	var things: Array = []
	for item: Dictionary in map.decor:
		things.append({"y": (item.foot as Vector2).y, "kind": "decor", "data": item})
	for unit: Dictionary in allies + foes:
		things.append({"y": (unit.pos as Vector2).y, "kind": "unit", "data": unit})
	for critter: Dictionary in ambient:
		things.append({"y": (critter.pos as Vector2).y, "kind": "critter", "data": critter})
	things.append({"y": (trainer.pos as Vector2).y, "kind": "trainer", "data": trainer})
	things.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	for thing: Dictionary in things:
		match str(thing.kind):
			"decor":
				_draw_decor(thing.data, origin)
			"unit":
				_draw_unit_at(thing.data, origin)
			"critter":
				_draw_critter(thing.data, origin)
			"trainer":
				_draw_trainer(origin)
	_draw_effects(origin)
	for unit: Dictionary in allies + foes:
		_draw_plate(unit, origin)
	for entry: Dictionary in rings:
		var progress: float = float(entry.age) / 0.7
		draw_arc(origin + (entry.at as Vector2) * zoom, (14 + progress * 60) * zoom / 1.5, 0, TAU, 48, Color(entry.color, 1.0 - progress), 3.0)
	for entry: Dictionary in floaters:
		var progress: float = float(entry.age) / 1.1
		var at: Vector2 = origin + (entry.at as Vector2) * zoom + Vector2(0, -progress * 34.0)
		var alpha: float = 1.0 - progress * progress
		HudPaint.outlined(self, at - Vector2(40, 14), str(entry.text), int(entry.size), Color(entry.color, alpha), Color(0.02, 0.03, 0.08, alpha), 80, HORIZONTAL_ALIGNMENT_CENTER)
		if str(entry.note) != "":
			HudPaint.outlined(self, at - Vector2(50, -8), str(entry.note), 13, Color(entry.note_color, alpha), Color(0.02, 0.03, 0.08, alpha), 100, HORIZONTAL_ALIGNMENT_CENTER)
	# Soft vignette so the title and the outcome read over any ground.
	HudPaint.vgradient(self, Rect2(5, 5, size.x - 10, 70), Color(0.02, 0.03, 0.08, 0.85), Color(0.02, 0.03, 0.08, 0))
	HudPaint.vgradient(self, Rect2(5, size.y - 70, size.x - 10, 65), Color(0.02, 0.03, 0.08, 0), Color(0.02, 0.03, 0.08, 0.7))
	if encounter.is_empty():
		_draw_idle()
		return
	_draw_hud(bool(encounter.boss))

func _draw_decor(item: Dictionary, origin: Vector2) -> void:
	var texture_: Texture2D = item.texture
	var scale_: float = float(item.scale) * zoom
	var size_: Vector2 = texture_.get_size() * scale_
	var foot: Vector2 = origin + (item.foot as Vector2) * zoom
	draw_texture_rect(texture_, Rect2(foot - Vector2(size_.x * 0.5, size_.y * 0.88), size_), false)

func _draw_sprite(id: String, species: String, point: Vector2, face: Vector2, moving: bool, phase: float, span: float, tone: Color, lift: float) -> void:
	var feet: Vector2 = point
	var shadow: float = span * 0.34
	draw_set_transform(feet + Vector2(0, 2), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, shadow, Color(0, 0, 0, 0.32 * tone.a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if FieldSprites.has(id):
		var region: Rect2 = FieldSprites.region(face, moving, phase)
		draw_texture_rect_region(FieldSprites.sheet(id), Rect2(feet + Vector2(-span / 2.0, -span * 0.86 - lift), Vector2(span, span)), region, tone)
	else:
		var fallback: Texture2D = textures.get(species)
		if fallback == null:
			fallback = PetWidgets.species_texture(species)
			textures[species] = fallback
		if fallback != null:
			var hop: float = absf(sin(phase * 0.8)) * 5.0 if moving else 0.0
			var flip: float = -1.0 if face.x < 0.0 else 1.0
			draw_set_transform(feet + Vector2(0, -span * 0.45 - hop - lift), 0.0, Vector2(flip, 1.0))
			draw_texture_rect(fallback, Rect2(Vector2(-span / 2.0, -span / 2.0), Vector2(span, span)), false, tone)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_unit_at(unit: Dictionary, origin: Vector2) -> void:
	var foe: bool = int(unit.id) >= 100
	var alive: bool = bool(unit.alive)
	var fade: float = float(unit.fade)
	if not alive and foe and fade <= 0.0:
		return
	var flash: float = float(unit.flash)
	var tone: Color = Color(1.0, 1.0 - flash * 0.55, 1.0 - flash * 0.55, fade if foe else 1.0)
	if not alive and not foe:
		tone = Color(0.5, 0.5, 0.55, 0.5)
	var lunge: float = float(unit.lunge)
	var push: Vector2 = (unit.lunge_dir as Vector2) * 14.0 * sin(PI * (1.0 - lunge)) if lunge > 0.0 else Vector2.ZERO
	var span: float = span_of(unit) * zoom
	var point: Vector2 = origin + ((unit.pos as Vector2) + push) * zoom
	if bool(unit.boss) and alive:
		HudPaint.glow(self, point + Vector2(0, -span * 0.4), span * 0.7, Color(HudPaint.GOLD, 0.30), 4)
	var bob: float = 0.0 if bool(unit.moving) or not alive else sin(age * 2.6 + float(unit.phase)) * 1.5
	_draw_sprite(str(unit.species), str(unit.species), point, unit.face, bool(unit.moving), float(unit.walk), span, tone, -bob + (0.0 if alive else -4.0))

func _draw_trainer(origin: Vector2) -> void:
	if not FieldSprites.has("trainer"):
		return
	var span: float = 64.0 * zoom
	var point: Vector2 = origin + (trainer.pos as Vector2) * zoom
	var moving: bool = bool(trainer.moving)
	_draw_sprite("trainer", "", point, trainer.face, moving, float(trainer.walk), span, Color.WHITE, 0.0 if moving else -sin(age * 2.0) * 1.0)

# A wandering wild creature: smaller than the fighters, with a small name and level.
func _draw_critter(critter: Dictionary, origin: Vector2) -> void:
	var span: float = 46.0 * zoom
	var point: Vector2 = origin + (critter.pos as Vector2) * zoom
	var moving: bool = bool(critter.moving)
	_draw_sprite(str(critter.species), str(critter.species), point, critter.face, moving, float(critter.walk), span, Color(1, 1, 1, 0.97), 0.0 if moving else -sin(age * 2.0 + float(critter.walk)) * 1.0)
	var title: String = "%s  %s" % [Pets.species_name(str(critter.species)), tr("Nv %d") % int(critter.level)]
	var top: float = point.y - span * 0.98
	# Dimmer than the fighters' plates and without a bar: they are scenery, not targets.
	HudPaint.outlined(self, Vector2(point.x - 70, top - 4), title, 10, Color(0.9, 0.86, 0.79, 0.8), Color(0.02, 0.03, 0.08, 0.8), 140, HORIZONTAL_ALIGNMENT_CENTER, 3)

func _draw_plate(unit: Dictionary, origin: Vector2) -> void:
	var alive: bool = bool(unit.alive)
	if not alive:
		return
	var boss: bool = bool(unit.boss)
	var point: Vector2 = origin + (unit.pos as Vector2) * zoom
	var span: float = span_of(unit) * zoom
	var width: float = 64.0 if not boss else 110.0
	var top: float = point.y - span * 0.98
	var title: String = Pets.species_name(str(unit.species))
	var foe: bool = int(unit.id) >= 100
	var label: String = "%s  %s" % [title, tr("Nv %d") % int(unit.level)]
	if not foe:
		# Five plates side by side would pile up: the team shows only the level.
		label = tr("Nv %d") % int(unit.level)
	if boss:
		label = tr("LENDÁRIO") + "  " + label
	HudPaint.outlined(self, Vector2(point.x - 80, top - 16), label, 12, HudPaint.GOLD_HOT if boss else (Color("ffd9c4") if foe else Color("d8f2ff")), Color(0.02, 0.03, 0.08), 160, HORIZONTAL_ALIGNMENT_CENTER, 3)
	var bar: Rect2 = Rect2(point.x - width / 2.0, top, width, 6)
	draw_rect(Rect2(bar.position - Vector2(1, 1), bar.size + Vector2(2, 2)), Color(0.02, 0.03, 0.08, 0.9))
	var fraction: float = clampf(float(unit.shown) / float(unit.max), 0.0, 1.0)
	var hue: Color = Color("5fdc7a") if fraction > 0.5 else (Color("ffd34d") if fraction > 0.25 else Color("ff6a5a"))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), hue)

func _draw_effects(origin: Vector2) -> void:
	for entry: Dictionary in effects:
		var age_: float = float(entry.age)
		var flight: float = float(entry.flight)
		var from: Vector2 = origin + (entry.from as Vector2) * zoom
		var to: Vector2 = origin + (entry.to as Vector2) * zoom
		var tint: Color = entry.tint
		var big: float = float(entry.big)
		var angle: float = (to - from).angle()
		match str(entry.style):
			"bolt", "orb":
				var progress: float = clampf(age_ / flight, 0.0, 1.0)
				var head: Vector2 = from.lerp(to, progress)
				var fx: Texture2D = _fx("bolt" if str(entry.style) == "bolt" else "orb", str(entry.element))
				if fx != null and age_ < flight:
					if str(entry.style) == "bolt":
						var length: float = minf(128.0, (head - from).length() + 40.0) * zoom * 0.62 * big
						var height: float = 48.0 * zoom * 0.62 * big
						draw_set_transform(head, angle, Vector2.ONE)
						draw_texture_rect(fx, Rect2(Vector2(-length * 0.9, -height / 2.0), Vector2(length, height)), false, tint)
					else:
						var edge: float = 32.0 * zoom * 0.85 * big
						draw_set_transform(head, age_ * 9.0, Vector2.ONE)
						draw_texture_rect(fx, Rect2(Vector2(-edge / 2.0, -edge / 2.0), Vector2(edge, edge)), false, tint)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					HudPaint.glow(self, head, 18.0 * big, Color(tint.r, tint.g * 0.8, tint.b * 0.5, 0.35), 3)
			"breath":
				# One flame stretched from the mouth to the target, flickering while it lasts.
				var fx: Texture2D = _fx("bolt", str(entry.element))
				var life: float = float(entry.life)
				var alpha: float = clampf(minf(age_ / 0.08, (life - age_) / 0.18), 0.0, 1.0)
				var reach: float = minf(1.0, age_ / 0.12) * (to - from).length()
				if fx != null:
					var wobble: float = 1.0 + 0.12 * sin(age_ * 50.0)
					draw_set_transform(from, angle, Vector2.ONE)
					draw_texture_rect(fx, Rect2(Vector2(0, -26.0 * zoom * 0.62 * big * wobble), Vector2(reach * 1.1, 52.0 * zoom * 0.62 * big * wobble)), false, Color(tint, alpha))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for i in range(6):
					var along: float = fposmod(age_ * 2.2 + i * 0.17, 1.0)
					var spot: Vector2 = from.lerp(to, along) + Vector2(0, sin(age_ * 18.0 + i * 2.0) * 9.0)
					HudPaint.sparkle(self, spot, 3.5 + (1.0 - along) * 3.0, Color(Color("ffb340").lerp(tint, 0.3), alpha * 0.8))
			"slash":
				if age_ >= float(entry.flight) * 0.5:
					var fx: Texture2D = _fx("slash", str(entry.element))
					var local: float = clampf((age_ - float(entry.flight) * 0.5) / 0.24, 0.0, 1.0)
					if fx != null and local < 1.0:
						var edge: float = 64.0 * zoom * (0.7 + 0.5 * local) * big * 0.8
						draw_set_transform(to, angle + 0.6 - local * 1.2, Vector2.ONE)
						draw_texture_rect(fx, Rect2(Vector2(-edge / 2.0, -edge / 2.0), Vector2(edge, edge)), false, Color(tint, 1.0 - local * local))
						draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for entry: Dictionary in embers:
		var progress: float = float(entry.age) / float(entry.life)
		var spot: Vector2 = origin + (entry.at as Vector2) * zoom + (entry.dir as Vector2) * float(entry.age) * zoom * 0.6
		HudPaint.sparkle(self, spot, float(entry.size), Color(entry.color, 1.0 - progress))
