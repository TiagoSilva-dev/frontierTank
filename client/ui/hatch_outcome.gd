class_name HatchOutcome
extends Control

# The moment an egg opens (0.19): it rocks harder and harder, cracks, bursts in the colour
# of the pet's rarity and the pet appears with its name. Better rarities get more rays,
# rings, sparks, a flash and a shake of the screen. A click closes it after the reveal.

signal completed

const SHAKE_TIME: float = 2.0
const CRACK_AT: float = 1.15

var egg_id: String = ""
var pet: Dictionary = {}
var is_new: bool = false
var audio: GameAudio

var age: float = 0.0
var egg_texture: Texture2D
var pet_texture: Texture2D
var species: Dictionary = {}
var rarity: int = 0
var tint: Color = HudPaint.GOLD
var rarity_color: Color = Color.WHITE
var cracks: Array = []
var shards: Array = []
var crack_sounded: bool = false
var reveal_sounded: bool = false
var home: Vector2 = Vector2.ZERO
var closing: bool = false

func _ready() -> void:
	size = Vector2(1280, 720)
	home = position
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	species = Pets.species_def(str(pet.species))
	rarity = Pets.rarity_index(str(species.rarity))
	rarity_color = Pets.rarity_color(str(species.rarity))
	tint = Pets.element_color(str(species.element)) if str(Pets.egg_def(egg_id).get("element", "")) != "" else HudPaint.GOLD
	egg_texture = PetWidgets.egg_texture(egg_id)
	pet_texture = PetWidgets.species_texture(str(pet.species))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = int(pet.uid) * 7919 + 13
	for i in range(4):
		var points: PackedVector2Array = PackedVector2Array()
		var angle: float = random.randf_range(-2.6, -0.5) + i * 0.9
		var at: Vector2 = Vector2(random.randf_range(-14, 14), random.randf_range(-40, 10))
		points.append(at)
		for step in range(5):
			angle += random.randf_range(-0.7, 0.7)
			at += Vector2.from_angle(angle) * random.randf_range(14, 28)
			points.append(at)
		cracks.append(points)
	for i in range(18 + rarity * 8):
		var direction: Vector2 = Vector2.from_angle(random.randf() * TAU)
		shards.append({"v": direction * random.randf_range(260, 620) + Vector2(0, -180), "size": random.randf_range(7, 16), "spin": random.randf_range(-9, 9), "tint": tint.lerp(Color("f4ead0"), random.randf())})
	if audio != null:
		audio.play("pet_shake", 0.0, 1.0, 0)

func _process(delta: float) -> void:
	age += delta
	if age >= CRACK_AT + 0.35 and not crack_sounded:
		crack_sounded = true
		if audio != null:
			audio.play("pet_crack", 0.0, 1.0, 0)
	if age >= SHAKE_TIME and not reveal_sounded:
		reveal_sounded = true
		if audio != null:
			audio.play("pet_hatch_" + str(species.rarity), 0.0, 1.0, 0)
	# Epic and legendary hatches shake the whole window for a moment.
	var burst: float = age - SHAKE_TIME
	if burst > 0.0 and burst < 0.5 and rarity >= 2:
		position = home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (rarity - 1) * 7.0 * (1.0 - burst * 2.0)
	else:
		position = home
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if closing or age < SHAKE_TIME + 1.3:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		closing = true
		completed.emit()
		queue_free()

func _draw() -> void:
	var fade: float = minf(age * 5.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.02, 0.055, fade * 0.92))
	var hub: Vector2 = Vector2(640, 300)
	if age < SHAKE_TIME:
		draw_shake(hub)
	else:
		draw_reveal(hub, age - SHAKE_TIME)

func draw_shake(hub: Vector2) -> void:
	var charge: float = clampf(age / SHAKE_TIME, 0.0, 1.0)
	HudPaint.glow(self, hub, 70 + charge * 130, Color(tint, 0.25 + charge * 0.5))
	for i in range(28):
		var angle: float = i * TAU / 28 + age * 2.2
		var r: float = 300.0 * (1.0 - charge) + 70.0
		HudPaint.sparkle(self, hub + Vector2.from_angle(angle) * r, 3 + i % 3, Color(tint.lightened(0.5), 0.3 + charge * 0.6))
	# The rocking speeds up and widens; a hard knock every time it passes the peak.
	var rate: float = 5.0 + charge * charge * 26.0
	var sway: float = sin(age * rate) * (0.04 + charge * 0.22)
	var scale: float = 1.0 + charge * 0.14
	var span: float = 210.0 * scale
	draw_set_transform(hub + Vector2(sin(age * rate * 0.5) * charge * 9.0, 0), sway, Vector2.ONE)
	if egg_texture != null:
		draw_texture_rect(egg_texture, Rect2(Vector2(-span / 2, -span / 2), Vector2(span, span)), false)
	var shown: int = 0
	if age > CRACK_AT:
		shown = ceili(clampf((age - CRACK_AT) / (SHAKE_TIME - CRACK_AT), 0.0, 1.0) * 6.0)
	for points: PackedVector2Array in cracks:
		var count: int = mini(points.size(), shown + 1)
		if count >= 2:
			draw_polyline(points.slice(0, count), Color(1, 0.96, 0.8, 0.95), 4.0)
			draw_polyline(points.slice(0, count), Color(tint.lightened(0.3), 0.8), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if age > CRACK_AT:
		var leak: float = clampf((age - CRACK_AT) / (SHAKE_TIME - CRACK_AT), 0.0, 1.0)
		HudPaint.rays(self, hub, 18, 260, age * 0.6, Color(1, 0.97, 0.8, leak * 0.3), 0.022)
	HudPaint.outlined(self, Vector2(0, 560), Pets.egg_name(egg_id), 26, HudPaint.CREAM, HudPaint.INK, 1280, HORIZONTAL_ALIGNMENT_CENTER)
	HudPaint.outlined(self, Vector2(0, 600), tr("Algo está se mexendo lá dentro..."), 20, Color("afbed1"), HudPaint.INK, 1280, HORIZONTAL_ALIGNMENT_CENTER)

func draw_reveal(hub: Vector2, burst: float) -> void:
	var glow_color: Color = rarity_color
	HudPaint.rays(self, hub, 12 + rarity * 8, 520, burst * 0.12, Color(glow_color, 0.14 + rarity * 0.03), 0.02)
	HudPaint.glow(self, hub, 190 + rarity * 30, Color(glow_color, 0.55))
	for i in range(1 + rarity):
		draw_arc(hub, 80 + burst * (110 + i * 70), 0, TAU, 96, Color(glow_color, maxf(0.0, 1.0 - burst / (1.2 + i * 0.3))), 3.0)
	for i in range(30 + rarity * 30):
		var direction: Vector2 = Vector2.from_angle(i * 2.399)
		var p: Vector2 = hub + direction * (30 + burst * (70 + i % 9 * 26)) + Vector2(0, burst * burst * 28)
		HudPaint.sparkle(self, p, 2 + i % 5, Color(glow_color.lightened(0.4), maxf(0.0, 1.0 - burst / 2.6)))
	# Pieces of the shell.
	for shard: Dictionary in shards:
		var p: Vector2 = hub + (shard.v as Vector2) * burst + Vector2(0, 700 * burst * burst)
		var angle: float = float(shard.spin) * burst
		var s: float = float(shard.size)
		var tri: PackedVector2Array = PackedVector2Array([Vector2(0, -s), Vector2(s * 0.8, s * 0.6), Vector2(-s * 0.8, s * 0.5)])
		for k in range(3):
			tri[k] = p + tri[k].rotated(angle)
		draw_colored_polygon(tri, Color(shard.tint, maxf(0.0, 1.0 - burst / 1.4)))
	var grow: float = HudPaint.ease_back(clampf(burst / 0.7, 0.0, 1.0))
	var span: float = 280.0 * grow
	var hover: float = sin(age * 2.0) * 6.0
	if pet_texture != null:
		draw_texture_rect(pet_texture, Rect2(hub + Vector2(-span / 2, -span / 2 + hover), Vector2(span, span)), false)
	var flash: float = maxf(0.0, 1.0 - burst * 6.0) * (0.45 + rarity * 0.18)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.95, 0.8, flash))
	var show_text: float = clampf((burst - 0.35) / 0.4, 0.0, 1.0)
	if show_text <= 0.0:
		return
	var banner: String = Pets.species_name(str(pet.species))
	HudPaint.fancy(self, Vector2(40, 452), banner, 50, rarity_color, HudPaint.BRONZE_DARK, 1200, HORIZONTAL_ALIGNMENT_CENTER, 4, 10, show_text)
	var line: String = "%s  •  %s" % [Pets.rarity_label(str(species.rarity)), Pets.element_name(str(species.element))]
	HudPaint.outlined(self, Vector2(0, 516), line, 24, Color(HudPaint.CREAM, show_text), HudPaint.INK, 1280, HORIZONTAL_ALIGNMENT_CENTER)
	var bonus: String = "   ".join(Pets.describe(pet).slice(0, 2))
	HudPaint.outlined(self, Vector2(0, 552), bonus, 20, Color("9fe6b5", show_text), HudPaint.INK, 1280, HORIZONTAL_ALIGNMENT_CENTER)
	var badge: String = tr("NOVO NO ÁLBUM!") if is_new else tr("Já no álbum: junte duplicatas para ganhar estrelas")
	var badge_color: Color = HudPaint.GOLD_HOT if is_new else Color("afbed1")
	HudPaint.outlined(self, Vector2(0, 590), badge, 24 if is_new else 18, Color(badge_color, show_text * (0.75 + 0.25 * sin(age * 6.0) if is_new else 1.0)), HudPaint.INK, 1280, HORIZONTAL_ALIGNMENT_CENTER)
	if burst > 1.3:
		HudPaint.outlined(self, Vector2(0, 664), tr("Clique para continuar"), 18, Color(HudPaint.CREAM, 0.55 + 0.35 * sin(age * 4.0)), HudPaint.INK, 1280, HORIZONTAL_ALIGNMENT_CENTER)
