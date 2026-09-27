class_name BattleOutcome
extends Control

# The end of a battle (0.16), at the level of the POW cut-in instead of a small emblem
# growing on screen.
# Victory: a white flash, the screen warms and dims, gold rays turn behind the winged
# crest (PixelLab) that pops in with a shock ring, "VITÓRIA!" slams in letter by
# letter and a shine runs over it, confetti rains and glints flicker.
# Defeat: the screen goes cold and dark, the broken shield drops and hits (the whole
# moment shakes, dust bursts), "DERROTA" falls letter by letter and settles crooked,
# ash drifts down.
# Draw: silver rays and "EMPATE". A ribbon under the title says what happened.
# The HUD hides it with itself when the results screen opens.

const EMBLEMS: Dictionary = {
	"victory": "res://assets/ui/battle/victory_emblem.png",
	"defeat": "res://assets/ui/battle/defeat_emblem.png",
}
const HUB: Vector2 = Vector2(640, 238)
const EMBLEM_SCALE: float = 2.0
const TITLE_SIZE: int = 80
const TITLE_Y: float = 452.0
const TITLE_Y_ALONE: float = 388.0
const LAND: float = 0.38

var kind: String = "victory"
var subtitle: String = ""
var age: float = 0.0
var emblem: Texture2D
var title: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var flakes: Array[Dictionary] = []
var glints: Array[Dictionary] = []
var tilts: Array[float] = []
var next_glint: float = 0.4
var title_y: float = TITLE_Y

static func create(parent: Node, outcome: String, text: String) -> BattleOutcome:
	var node: BattleOutcome = BattleOutcome.new()
	node.kind = outcome
	node.subtitle = text
	parent.add_child(node)
	return node

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.randomize()
	title = {"victory": tr("VITÓRIA!"), "defeat": tr("DERROTA"), "draw": tr("EMPATE")}[kind].to_upper()
	if EMBLEMS.has(kind):
		emblem = load(EMBLEMS[kind])
	else:
		# No emblem (a draw): the title takes the middle of the screen.
		title_y = TITLE_Y_ALONE
	for i in range(title.length()):
		tilts.append(rng.randf_range(-0.09, 0.09) if kind == "defeat" else 0.0)
	# Victory: confetti from above; defeat: slow ash; draw: a few silver motes.
	var count: int = {"victory": 110, "defeat": 70, "draw": 30}[kind]
	for i in range(count):
		flakes.append({
			"x": rng.randf_range(-40, 1320), "y": rng.randf_range(-420, -10), "vy": rng.randf_range(90, 240) if kind == "victory" else rng.randf_range(25, 70),
			"sway": rng.randf_range(10, 40), "freq": rng.randf_range(1.5, 4.0), "phase": rng.randf() * TAU,
			"spin": rng.randf_range(-7, 7), "w": 2.0 * rng.randi_range(1, 2), "h": 2.0 * rng.randi_range(2, 3),
			"color": [Color("ffd04a"), Color("ff5a3a"), Color("fff0c0"), Color("5cc8ff"), Color("8ee05a"), Color("ff8ad0")][rng.randi() % 6] if kind == "victory" else (Color(0.72, 0.72, 0.8, rng.randf_range(0.5, 0.85)) if rng.randf() < 0.8 or kind == "draw" else Color(1.0, 0.42, 0.2, 0.8)),
		})

func _process(delta: float) -> void:
	age += delta
	for flake: Dictionary in flakes:
		if age > LAND - 0.1:
			flake.y = float(flake.y) + float(flake.vy) * delta
			if float(flake.y) > 740.0:
				flake.y = rng.randf_range(-60, -10)
	if age >= next_glint and kind != "defeat":
		next_glint = age + rng.randf_range(0.06, 0.14)
		var around: Vector2 = HUB + Vector2(rng.randf_range(-230, 230), rng.randf_range(-130, 250))
		glints.append({"pos": around, "born": age, "size": rng.randf_range(7, 16)})
	queue_redraw()

# ---------- timeline ----------

func shown() -> float:
	return clampf(age / 0.25, 0.0, 1.0)

func shake() -> Vector2:
	# Defeat: the landing shakes everything for a moment.
	if kind != "defeat" or age < LAND:
		return Vector2.ZERO
	var u: float = 1.0 - clampf((age - LAND) / 0.45, 0.0, 1.0)
	return Vector2(sin(age * 83.0), cos(age * 67.0)) * 9.0 * u * u

func emblem_scale() -> float:
	if kind == "defeat":
		return 1.0
	return lerpf(0.2, 1.0, HudPaint.ease_back((age - 0.05) / 0.33))

func emblem_center() -> Vector2:
	if kind == "defeat":
		var drop: float = HudPaint.ease_in(age / LAND)
		return Vector2(HUB.x, lerpf(-240.0, HUB.y, drop)) + Vector2(0, sin(maxf(0.0, age - LAND) * 1.6) * 3.0)
	return HUB + Vector2(0, sin(age * 2.0) * 4.0)

# ---------- drawing ----------

func _draw() -> void:
	var seen: float = shown()
	var jolt: Vector2 = shake()
	draw_set_transform(jolt, 0.0, Vector2.ONE)
	match kind:
		"victory":
			draw_rect(Rect2(-20, -20, 1320, 760), Color(0.08, 0.04, 0.0, 0.5 * seen))
		"defeat":
			draw_rect(Rect2(-20, -20, 1320, 760), Color(0.02, 0.03, 0.07, 0.64 * seen))
		_:
			draw_rect(Rect2(-20, -20, 1320, 760), Color(0.04, 0.04, 0.06, 0.52 * seen))
	vignette(seen)
	var center: Vector2 = emblem_center()
	match kind:
		"victory":
			HudPaint.rays(self, center, 22, 1100.0, age * 0.25, Color(1.0, 0.86, 0.4, 0.13 * clampf((age - 0.08) / 0.3, 0.0, 1.0)), 0.07)
			HudPaint.glow(self, center, 190.0 + sin(age * 3.0) * 8.0, Color(1.0, 0.8, 0.35, 0.9 * seen), 6)
		"draw":
			HudPaint.rays(self, Vector2(640, title_y - 30.0), 18, 900.0, age * 0.2, Color(0.85, 0.9, 1.0, 0.09 * seen), 0.07)
		"defeat":
			if age > LAND:
				HudPaint.glow(self, center + Vector2(0, 40), 170.0, Color(0.45, 0.3, 0.7, 0.55 * seen), 5)
	if age > LAND:
		shock_ring(center)
	draw_emblem(center)
	if kind == "defeat" and age > LAND:
		dust(center)
	draw_flakes()
	draw_title(jolt)
	draw_ribbon()
	for glint: Dictionary in glints:
		var life: float = (age - float(glint.born)) / 0.32
		if life < 1.0:
			HudPaint.sparkle(self, glint.pos, float(glint.size) * sin(life * PI), Color(1, 1, 0.92, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if age < 0.14 and kind != "defeat":
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.6 * (1.0 - age / 0.14)))
	elif kind == "defeat" and age >= LAND and age < LAND + 0.1:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.8, 1.0, 0.25 * (1.0 - (age - LAND) / 0.1)))

func vignette(seen: float) -> void:
	var edge: Color = Color(0, 0, 0, (0.7 if kind == "defeat" else 0.5) * seen)
	var clear: Color = Color(0, 0, 0, 0)
	draw_polygon(PackedVector2Array([Vector2(-20, -20), Vector2(1300, -20), Vector2(1300, 170), Vector2(-20, 170)]), PackedColorArray([edge, edge, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(-20, 540), Vector2(1300, 540), Vector2(1300, 740), Vector2(-20, 740)]), PackedColorArray([clear, clear, edge, edge]))

func shock_ring(center: Vector2) -> void:
	var u: float = (age - LAND) / 0.55
	if u >= 1.0:
		return
	var color: Color = Color(1.0, 0.95, 0.75) if kind == "victory" else Color(0.75, 0.75, 0.9)
	draw_arc(center, 60.0 + u * 360.0, 0.0, TAU, 64, Color(color, 0.8 * (1.0 - u)), 8.0 * (1.0 - u) + 1.0)

func draw_emblem(center: Vector2) -> void:
	if emblem == null:
		return
	var s: float = emblem_scale()
	if s <= 0.0:
		return
	var half: Vector2 = emblem.get_size() * EMBLEM_SCALE * s / 2.0
	var turn: float = 0.0
	var tint: Color = Color.WHITE
	if kind == "defeat" and age > LAND:
		# Settles slightly crooked and loses some light.
		turn = -0.06 * HudPaint.ease_out((age - LAND) / 0.5)
		tint = Color(0.85, 0.85, 0.92)
	draw_set_transform(center.round() + shake(), turn, Vector2.ONE)
	draw_texture_rect(emblem, Rect2(-half.round(), (half * 2.0).round()), false, tint)
	draw_set_transform(shake(), 0.0, Vector2.ONE)

func dust(center: Vector2) -> void:
	var u: float = (age - LAND) / 0.7
	if u >= 1.0:
		return
	for k in range(9):
		var a: float = PI * (0.05 + 0.9 * k / 8.0)
		var p: Vector2 = center + Vector2(0, 110) + Vector2(cos(a) * (40.0 + u * 170.0), -sin(a) * u * 50.0)
		draw_circle(p, 16.0 * (1.0 - u) + 6.0, Color(0.55, 0.52, 0.6, 0.45 * (1.0 - u)))

func draw_flakes() -> void:
	if age < LAND - 0.1:
		return
	for flake: Dictionary in flakes:
		var x: float = float(flake.x) + sin(age * float(flake.freq) + float(flake.phase)) * float(flake.sway)
		var at: Vector2 = Vector2(roundf(x), roundf(float(flake.y)))
		var color: Color = flake.color
		if kind == "victory":
			# Confetti: little strips that flip as they fall (the width shrinks and grows).
			var flip: float = absf(cos(age * float(flake.spin) + float(flake.phase)))
			var w: float = maxf(1.0, roundf(float(flake.w) * 2.0 * flip))
			draw_rect(Rect2(at, Vector2(w, float(flake.h))), color if flip > 0.4 else color.darkened(0.3))
		else:
			draw_rect(Rect2(at, Vector2(float(flake.w), float(flake.w))), color)

func draw_title(jolt: Vector2) -> void:
	var font: Font = UiKit.font(true)
	var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	var left: float = roundf(640.0 - width / 2.0)
	var ascent: float = font.get_ascent(TITLE_SIZE)
	var face: Color = {"victory": Color(1.0, 0.84, 0.25), "defeat": Color(0.84, 0.86, 0.93), "draw": Color(0.9, 0.92, 1.0)}[kind]
	var depth: Color = {"victory": Color(0.72, 0.28, 0.05), "defeat": Color(0.4, 0.06, 0.08), "draw": Color(0.3, 0.34, 0.5)}[kind]
	var start: float = LAND - 0.05
	var sweep: float = lerpf(left - 120.0, left + width + 120.0, clampf((age - 1.0) / 0.5, 0.0, 1.0))
	for i in range(title.length()):
		var letter: String = title[i]
		if letter == " ":
			continue
		var p: float = clampf((age - start - i * 0.045) / (0.14 if kind != "defeat" else 0.3), 0.0, 1.0)
		if p <= 0.0:
			continue
		var x: float = left + font.get_string_size(title.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
		var w: float = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
		var pivot: Vector2 = Vector2(roundf(x + w / 2.0), roundf(title_y - ascent * 0.4))
		var s: float = 1.0
		var turn: float = 0.0
		if kind == "defeat":
			# Each letter falls, bounces and settles a little crooked.
			pivot.y -= (1.0 - bounce(p)) * 160.0
			turn = tilts[i] * clampf(p * 1.5 - 0.5, 0.0, 1.0)
		else:
			pivot.y -= (1.0 - HudPaint.ease_out(p)) * 40.0
			s = lerpf(2.4, 1.0, HudPaint.ease_out(p))
		var alpha: float = minf(1.0, p * 3.0)
		var shine: float = exp(-pow((x + w / 2.0 - sweep) / 50.0, 2.0)) if kind == "victory" else 0.0
		var at: Vector2 = Vector2(-w / 2.0, ascent * 0.4)
		draw_set_transform(pivot + jolt, turn, Vector2(s, s))
		draw_char_outline(font, at + Vector2(7, 7), letter, TITLE_SIZE, 14, Color(0, 0, 0, 0.45 * alpha))
		draw_char_outline(font, at + Vector2(0, 5), letter, TITLE_SIZE, 14, Color(HudPaint.INK, alpha))
		draw_char_outline(font, at, letter, TITLE_SIZE, 14, Color(HudPaint.INK, alpha))
		for k in range(1, 6):
			draw_char(font, at + Vector2(0, k), letter, TITLE_SIZE, Color(depth, alpha))
		draw_char(font, at + Vector2(0, -2), letter, TITLE_SIZE, Color(1.0, 0.98, 0.86, alpha))
		draw_char(font, at, letter, TITLE_SIZE, face.lerp(Color.WHITE, shine * 0.85) * Color(1, 1, 1, alpha))
	draw_set_transform(jolt, 0.0, Vector2.ONE)

func draw_ribbon() -> void:
	# A dark band under the title, fading at both ends, with the line of text.
	var u: float = HudPaint.ease_out((age - 0.85) / 0.3)
	if u <= 0.0 or subtitle == "":
		return
	var y: float = title_y + 22.0
	var half: float = 300.0 * u
	var body: Color = Color(0.1, 0.05, 0.02, 0.8) if kind == "victory" else Color(0.03, 0.04, 0.09, 0.82)
	var clear: Color = Color(body.r, body.g, body.b, 0.0)
	var line: Color = Color(1.0, 0.82, 0.4, 0.9 * u) if kind == "victory" else Color(0.6, 0.62, 0.78, 0.8 * u)
	var line_clear: Color = Color(line.r, line.g, line.b, 0.0)
	for side: float in [-1.0, 1.0]:
		var inner: float = 640.0 + side * half * 0.55
		var outer: float = 640.0 + side * half
		draw_polygon(PackedVector2Array([Vector2(inner, y), Vector2(outer, y), Vector2(outer, y + 36), Vector2(inner, y + 36)]), PackedColorArray([body, clear, clear, body]))
		draw_polygon(PackedVector2Array([Vector2(inner, y), Vector2(outer, y), Vector2(outer, y + 2), Vector2(inner, y + 2)]), PackedColorArray([line, line_clear, line_clear, line]))
		draw_polygon(PackedVector2Array([Vector2(inner, y + 34), Vector2(outer, y + 34), Vector2(outer, y + 36), Vector2(inner, y + 36)]), PackedColorArray([line, line_clear, line_clear, line]))
	draw_rect(Rect2(640.0 - half * 0.55, y, half * 1.1, 36), body)
	draw_rect(Rect2(640.0 - half * 0.55, y, half * 1.1, 2), line)
	draw_rect(Rect2(640.0 - half * 0.55, y + 34, half * 1.1, 2), line)
	var text_color: Color = Color(1.0, 0.95, 0.82, u) if kind == "victory" else Color(0.85, 0.87, 0.95, u)
	HudPaint.outlined(self, Vector2(340, y + 25), subtitle, 20, text_color, Color(HudPaint.INK, u), 600, HORIZONTAL_ALIGNMENT_CENTER, 6)

static func bounce(t: float) -> float:
	# Falls in, bounces twice, rests at 1.
	var x: float = clampf(t, 0.0, 1.0)
	if x < 0.55:
		return pow(x / 0.55, 2.0)
	if x < 0.8:
		var k: float = (x - 0.675) / 0.125
		return 1.0 - 0.12 * (1.0 - k * k)
	var q: float = (x - 0.9) / 0.1
	return 1.0 - 0.04 * (1.0 - q * q)
