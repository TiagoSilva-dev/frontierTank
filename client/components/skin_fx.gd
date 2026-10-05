class_name SkinFx
extends Node2D

# The living layer of an epic skin (docs/SKINS.md, 0.28): electric arcs on the shoulders of the
# Tempestade Viva, falling flakes and frost on the Coroa de Gelo, rising embers on the Coração
# de Magma. Everything is drawn in 2 px squares on the sprite's own pixel grid, never hides the
# shot line (it stays on and around the fighter), has no attributes and costs a few dozen
# `draw_rect` calls, so it fits the web and phone builds. LookRig owns one when `look.skin_fx`
# names a theme; the owner tells it what is happening with `rig.fx_state` and `rig.fx_event`.
# It is only drawing: the time here is real time and nothing reads it back (lockstep stays safe).

const THEMES: Array[String] = ["storm", "ice", "magma", "ghost"]
const POW_SECONDS: float = 1.3

var rig: LookRig
var theme: String = "storm"
var time: float = 0.0
var flare: float = 0.0
var boost: float = 0.0
var boost_goal: float = 0.0
var pow_time: float = 0.0
var hit_blink: float = 0.0
# One cell of the layer: 2 px in battle, and the same two sprite pixels on the bigger menu avatars.
var cs: float = 2.0

func _ready() -> void:
	theme = str(rig.look.get("skin_fx", "storm"))
	if not theme in THEMES:
		theme = "storm"
	z_index = 1

func event(kind: String) -> void:
	match kind:
		"attack":
			flare = 1.0
		"hit":
			hit_blink = 0.16
		"pow":
			pow_time = POW_SECONDS
		"victory":
			boost_goal = 1.0
		"reset":
			boost_goal = 0.0

func _process(delta: float) -> void:
	time += delta
	flare = move_toward(flare, 0.0, delta * 3.5)
	pow_time = maxf(0.0, pow_time - delta)
	hit_blink = maxf(0.0, hit_blink - delta)
	boost = move_toward(boost, boost_goal, delta * 0.8)
	if rig.head_dims.x > 0.0:
		queue_redraw()

# 0..1 for how strongly the layer shows now: calm when idle, lively when aiming or celebrating,
# dim on defeat.
func energy() -> float:
	var state: String = rig.fx_state
	var base: float = 0.55
	match state:
		"walk":
			base = 0.8
		"aim":
			base = 0.9
		"attack":
			base = 1.0
		"victory":
			base = 1.0
		"pow":
			base = 1.0
		"defeat":
			base = 0.18
	return clampf(base + 0.3 * flare + 0.2 * boost + (0.4 if pow_time > 0.0 else 0.0), 0.0, 1.0)

func _draw() -> void:
	if rig == null or rig.head_dims.x <= 0.0:
		return
	cs = maxf(2.0, roundf(rig.head_dims.x / 43.0 * 2.0))
	var level: float = energy()
	if hit_blink > 0.0:
		level *= 0.4
	match theme:
		"storm":
			draw_storm(level)
		"ice":
			draw_ice(level)
		"magma":
			draw_magma(level)
		"ghost":
			draw_ghost(level)

# ---------- helpers ----------

# Pseudo-random 0..1 from a whole number: the same input always gives the same value, so the
# layer looks alike on every screen without a generator of its own.
static func noise(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + 78.233) * 43758.5453, 1.0)

# Pixel art has no half-transparent pixels: a fading cell is simply gone below 40% and solid above.
func cell(at: Vector2, color: Color, size: float = 0.0) -> void:
	if color.a < 0.4:
		return
	color.a = 1.0
	var turn: Array = rig.look.get("recolor", [])
	if turn.size() == 4 and color.s > 0.2:
		# The alternative colour of the skin turns the whole layer with it.
		color.h = fposmod(color.h + float(turn[2]) / 360.0, 1.0)
	var edge: float = size if size > 0.0 else cs
	draw_rect(Rect2((at / cs).round() * cs - Vector2(edge, edge) / 2.0, Vector2(edge, edge)), color)

func facing() -> float:
	return -1.0 if rig.flip else 1.0

func standing() -> bool:
	return rig.view != "prone"

# Where the two shoulders are: lying down they sit behind the head, standing at its sides.
func shoulders() -> Array[Vector2]:
	var dims: Vector2 = rig.head_dims
	var head: Vector2 = rig.head_center
	if standing():
		return [head + Vector2(-dims.x * 0.78, dims.y * 0.82), head + Vector2(dims.x * 0.78, dims.y * 0.82)]
	var dir: float = facing()
	return [head + Vector2(-dir * dims.x * 0.62, dims.y * 0.5), head + Vector2(-dir * dims.x * 1.05, dims.y * 0.42)]

func scale_unit() -> float:
	return clampf(rig.head_dims.x / 36.0, 0.6, 2.2)

# ---------- Tempestade Viva ----------

const STORM_CORE: Color = Color("ffffff")
const STORM_BRIGHT: Color = Color("b8f0ff")
const STORM_GLOW: Color = Color("4cc2ff")

func draw_storm(level: float) -> void:
	var unit: float = scale_unit()
	var frame: int = int(time * 11.0)
	var anchors: Array[Vector2] = shoulders()
	for i in range(anchors.size()):
		# The arcs flicker: each one is lit on some frames only, more often with more energy.
		if noise(frame / 2 * 7 + i * 31) > 0.3 + level * 0.65:
			continue
		draw_arc_bolt(anchors[i], frame * 5 + i * 17, 7 + int(level * 2.0), 4.4 * unit, 1.0)
	# A small spark on the brow, where the eyes crackle.
	if noise(frame * 3 + 5) < 0.18 + level * 0.25:
		var brow: Vector2 = rig.head_center + Vector2(facing() * rig.head_dims.x * (0.3 if not standing() else 0.0), -rig.head_dims.y * 0.2)
		cell(brow, Color(STORM_CORE, 0.9))
		cell(brow + Vector2(cs * 2, 0), Color(STORM_BRIGHT, 0.7))
		cell(brow + Vector2(-cs * 2, 0), Color(STORM_BRIGHT, 0.7))
		cell(brow + Vector2(0, -cs * 2), Color(STORM_BRIGHT, 0.7))
	if pow_time > 0.0:
		draw_storm_pow()

# A line of cells from `a` to `b` with no gaps.
func line_cells(a: Vector2, b: Vector2, color: Color) -> void:
	var count: int = maxi(1, int(a.distance_to(b) / cs))
	for i in range(count + 1):
		cell(a.lerp(b, float(i) / float(count)), color)

# One jagged arc: a chain of short steps leaning up and out, glow underneath, white core on top.
func draw_arc_bolt(from: Vector2, seed_value: int, steps: int, step_length: float, alpha: float) -> void:
	var at: Vector2 = from
	var outward: float = -1.0 if at.x < rig.head_center.x else 1.0
	if not standing():
		outward = -facing()
	for k in range(steps):
		var angle: float = -PI / 2.0 + (noise(seed_value + k * 3) - 0.5) * 2.2 + outward * 0.5
		var next: Vector2 = at + Vector2(cos(angle), sin(angle)) * step_length
		var fade: float = 1.0 - float(k) / float(steps) * 0.5
		# A white core with a cyan edge on one side, so the arc reads on light and dark scenery.
		line_cells(at + Vector2(cs, 0), next + Vector2(cs, 0), Color(STORM_GLOW, alpha * fade))
		line_cells(at, next, Color(STORM_CORE if k % 2 == 0 else STORM_BRIGHT, alpha * fade))
		at = next
	cell(at, Color(STORM_CORE, alpha))

# The POW: one thin bolt falls from the sky onto the fighter. It stays above the head, so the
# line of the shot and the damage area are never covered.
func draw_storm_pow() -> void:
	var strength: float = pow_time / POW_SECONDS
	var flick: bool = int(time * 30.0) % 3 != 0
	if strength < 0.12 or not flick:
		return
	var top: Vector2 = rig.head_center + Vector2(0, -rig.head_dims.y * 0.8)
	var at: Vector2 = top + Vector2(0, -300.0)
	var frame: int = int(time * 24.0)
	var k: int = 0
	while at.y < top.y:
		var next: Vector2 = at + Vector2((noise(frame * 5 + k) - 0.5) * 18.0, 9.0 + noise(frame + k * 2) * 7.0)
		next.x = lerpf(next.x, top.x, 0.3)
		line_cells(at + Vector2(cs, 0), next + Vector2(cs, 0), Color(STORM_GLOW, strength))
		line_cells(at, next, Color(STORM_CORE, strength))
		at = next
		k += 1
	for j in range(8):
		var spark: Vector2 = top + Vector2((noise(frame + j * 9) - 0.5) * 60.0, (noise(frame * 2 + j) - 0.8) * 24.0)
		cell(spark, Color(STORM_BRIGHT, strength))

# ---------- Coroa de Gelo ----------

const ICE_WHITE: Color = Color("ffffff")
const ICE_LIGHT: Color = Color("d8f6ff")
const ICE_MID: Color = Color("8fd8ff")
const ICE_DEEP: Color = Color("4aa8e6")

func draw_ice(level: float) -> void:
	var unit: float = scale_unit()
	var rect: Rect2 = rig.body_rect
	var count: int = 9 + int(level * 5.0)
	for i in range(count):
		# Flakes fall slowly past the body, swaying, and fade at both ends.
		var speed: float = 14.0 + noise(i * 11) * 14.0
		var fall: float = fposmod(time * speed * unit + noise(i * 5) * 200.0, rect.size.y + 40.0 * unit)
		var sway: float = sin(time * (0.8 + noise(i * 3)) + i * 2.1) * rect.size.x * 0.2
		var x: float = rect.get_center().x + (noise(i * 7) - 0.5) * rect.size.x * 1.7 + sway
		var y: float = rect.position.y - 24.0 * unit + fall
		var fade: float = clampf(sin(fall / (rect.size.y + 40.0 * unit) * PI) * 1.6, 0.0, 1.0)
		draw_flake(Vector2(x, y), fade * (0.45 + 0.55 * level), i % 3 == 0)
	# The crown glints now and then.
	var glint: float = fposmod(time * 0.55, 1.0)
	if glint < 0.22 and rig.fx_state != "defeat":
		var top: Vector2 = rig.head_center + Vector2(rig.head_dims.x * 0.18 * facing(), -rig.head_dims.y * 0.52)
		draw_star(top, sin(glint / 0.22 * PI))
	frost_ground(level)
	if pow_time > 0.0:
		draw_ice_pow()

func draw_flake(at: Vector2, alpha: float, big: bool) -> void:
	cell(at, Color(ICE_WHITE, alpha))
	# A darker blue on the arms of half the flakes keeps them readable on snow and pale skies.
	var color: Color = Color(ICE_MID if big else ICE_LIGHT, alpha * 0.9)
	cell(at + Vector2(cs, 0), color)
	cell(at + Vector2(-cs, 0), color)
	cell(at + Vector2(0, cs), color)
	cell(at + Vector2(0, -cs), color)
	if big:
		var tip: Color = Color(ICE_DEEP, alpha * 0.8)
		cell(at + Vector2(cs * 2, cs * 2), tip)
		cell(at + Vector2(-cs * 2, cs * 2), tip)
		cell(at + Vector2(cs * 2, -cs * 2), tip)
		cell(at + Vector2(-cs * 2, -cs * 2), tip)

func draw_star(at: Vector2, alpha: float) -> void:
	cell(at, Color(ICE_WHITE, alpha), cs * 2.0)
	for step in range(1, 4):
		var color: Color = Color(ICE_LIGHT if step < 3 else ICE_MID, alpha * (1.0 - step * 0.22))
		cell(at + Vector2(cs * 2 * step, 0), color)
		cell(at + Vector2(-cs * 2 * step, 0), color)
		cell(at + Vector2(0, cs * 2 * step), color)
		cell(at + Vector2(0, -cs * 2 * step), color)

# A thin frost on the ground under the fighter that glitters while it crawls.
func frost_ground(level: float) -> void:
	var rect: Rect2 = rig.body_rect
	var floor_y: float = rig.ground_y
	if floor_y <= 0.0:
		return
	var width: float = rect.size.x * (1.5 if rig.fx_state == "walk" else 1.1)
	var behind: float = -facing()
	for i in range(6):
		var drift: float = fposmod(time * 0.7 + noise(i * 13), 1.0)
		var x: float = rect.get_center().x + behind * (drift - 0.2) * width * 0.9 + (noise(i * 29) - 0.5) * width * 0.4
		var tw: float = 0.5 + 0.5 * sin(time * 5.0 + i * 1.7)
		cell(Vector2(x, floor_y - 1.0), Color(ICE_LIGHT, 0.55 * level * tw * (1.0 - drift)))
		cell(Vector2(x + cs, floor_y - 3.0), Color(ICE_WHITE, 0.4 * level * tw * (1.0 - drift)))

# The POW: a ring of shards leaves the fighter and widens (small: it is a flourish, never the
# damage area).
func draw_ice_pow() -> void:
	var t: float = 1.0 - pow_time / POW_SECONDS
	var center: Vector2 = rig.body_rect.get_center()
	var radius: float = rig.head_dims.x * (0.7 + 2.0 * t)
	var alpha: float = 1.0 - t
	for i in range(16):
		var angle: float = TAU * float(i) / 16.0 + t * 0.6
		var at: Vector2 = center + Vector2(cos(angle), sin(angle) * 0.7) * radius
		cell(at, Color(ICE_WHITE, alpha), cs * 2.0)
		cell(at + Vector2(cos(angle), sin(angle) * 0.7) * cs * 2.0, Color(ICE_MID, alpha * 0.8))

# ---------- Coração de Magma ----------

const EMBER_RAMP: Array[Color] = [Color("fff2a0"), Color("ffb02e"), Color("ff6a1a"), Color("c43b10")]

func draw_magma(level: float) -> void:
	var unit: float = scale_unit()
	var rect: Rect2 = rig.body_rect
	var center: Vector2 = rect.get_center()
	# The cracks glow: a few bright cells on the chest and back that pulse (faster and wider
	# while a shot is armed), the "rachaduras pulsam ao carregar a força".
	var pulse: float = 0.5 + 0.5 * sin(time * (2.2 + 3.0 * level))
	var spots: int = 3 + int(level * 4.0 * pulse) + (4 if pow_time > 0.0 else 0)
	for i in range(spots):
		var spot: Vector2 = center + Vector2((noise(i * 19 + 3) - 0.5) * rect.size.x * 0.5, (noise(i * 23 + 1) - 0.5) * rect.size.y * 0.6)
		cell(spot, EMBER_RAMP[0] if pulse > 0.7 else EMBER_RAMP[1])
	var count: int = 10 + int(level * 8.0)
	for i in range(count):
		var life: float = 1.1 + noise(i * 5) * 0.9
		var phase: float = fposmod(time / life + noise(i * 17), 1.0)
		var x: float = rect.position.x + noise(i * 3) * rect.size.x + sin(time * 2.0 + i * 1.3) * 3.0 * unit
		var y: float = rect.end.y - phase * rect.size.y * (1.2 + 0.4 * level)
		var color: Color = ember_color(phase)
		color.a *= sin(phase * PI) * (0.6 + 0.4 * level)
		cell(Vector2(x, y), color, cs * (2.0 if i % 4 == 0 else 1.0))
	if pow_time > 0.0:
		draw_magma_pow()

func ember_color(phase: float) -> Color:
	var scaled: float = phase * float(EMBER_RAMP.size() - 1)
	var low: int = int(scaled)
	var high: int = mini(low + 1, EMBER_RAMP.size() - 1)
	return EMBER_RAMP[low].lerp(EMBER_RAMP[high], scaled - low)

# The POW: an eruption of embers shoots up in a fan from the fighter's back.
func draw_magma_pow() -> void:
	var t: float = 1.0 - pow_time / POW_SECONDS
	var origin: Vector2 = rig.body_rect.get_center() + Vector2(-facing() * rig.head_dims.x * 0.4, -rig.head_dims.y * 0.2)
	for i in range(28):
		var spread: float = (noise(i * 7) - 0.5) * 1.5
		var speed: float = 90.0 + noise(i * 11) * 150.0
		var age: float = t * 1.3 - noise(i * 13) * 0.35
		if age < 0.0:
			continue
		var at: Vector2 = origin + Vector2(sin(spread) * speed * age, -cos(spread) * speed * age + 190.0 * age * age)
		var color: Color = ember_color(clampf(age * 0.9, 0.0, 1.0))
		color.a *= clampf(1.0 - age * 0.8, 0.0, 1.0)
		cell(at, color, cs * (2.0 if i % 3 == 0 else 1.0))

# ---------- Capitania Fantasma ----------

const GHOST_RAMP: Array[Color] = [Color("f2fffa"), Color("9ff5da"), Color("3fc9a6"), Color("1d8a86")]

func ghost_color(phase: float) -> Color:
	var scaled: float = clampf(phase, 0.0, 1.0) * float(GHOST_RAMP.size() - 1)
	var low: int = int(scaled)
	var high: int = mini(low + 1, GHOST_RAMP.size() - 1)
	return GHOST_RAMP[low].lerp(GHOST_RAMP[high], scaled - low)

# Cold flame licking up from the head, two eyes that burn in the blank face, and the hem of
# the coat coming apart into mist. It stays on the fighter and above the head: the shot line
# and the damage area are never covered.
func draw_ghost(level: float) -> void:
	var unit: float = scale_unit()
	var dims: Vector2 = rig.head_dims
	var head: Vector2 = rig.head_center
	var rect: Rect2 = rig.body_rect
	# Eyes: two bright cells standing, one lying prone (the face is in profile), blinking now and then.
	var blink: bool = fposmod(time + noise(3) * 5.0, 3.4) < 0.14 or rig.fx_state == "defeat"
	if not blink:
		# Dark on the pale face: bright eyes would vanish into it.
		var eye: Color = Color("0b4a52")
		if standing():
			cell(head + Vector2(-dims.x * 0.1, dims.y * 0.1), eye)
			cell(head + Vector2(dims.x * 0.1, dims.y * 0.1), eye)
		else:
			cell(head + Vector2(facing() * dims.x * 0.24, -dims.y * 0.02), eye)
	# Flame tongues from the sides and the back of the head: they rise, sway and thin out.
	var tongues: int = 6 + int(level * 5.0)
	for i in range(tongues):
		var life: float = 0.9 + noise(i * 7) * 0.7
		var phase: float = fposmod(time / life + noise(i * 13), 1.0)
		var side: float = (noise(i * 5 + 2) - 0.5) * 2.0
		var x: float = head.x + side * dims.x * 0.55 + sin(time * 3.0 + i * 1.7) * 2.5 * unit
		var y: float = head.y + dims.y * 0.1 - phase * dims.y * (0.9 + 0.5 * level)
		var color: Color = ghost_color(phase)
		color.a *= clampf(sin(phase * PI) * 1.8, 0.0, 1.0)
		# A tongue is a short column that thins toward the tip and leans with the sway.
		for k in range(3):
			var lick: Color = color
			lick.a *= 1.0 - 0.28 * k
			cell(Vector2(x + sin(time * 4.0 + i + k) * 0.8 * k * cs, y - k * cs * 2.0), lick, cs * (2.0 if k == 0 else 1.0))
	# The hem of the coat dissolves: pale puffs rise from the bottom of the body and fade.
	var puffs: int = 7 + int(level * 6.0)
	for i in range(puffs):
		var life: float = 1.6 + noise(i * 11) * 1.2
		var phase: float = fposmod(time / life + noise(i * 19), 1.0)
		var x: float = rect.position.x + noise(i * 3 + 1) * rect.size.x + sin(time * 1.4 + i) * 3.0 * unit
		var y: float = rect.end.y - phase * rect.size.y * 0.55
		var color: Color = ghost_color(0.15 + phase * 0.7)
		color.a *= sin(phase * PI) * 0.8
		cell(Vector2(x, y), color, cs * 2.0)
	if pow_time > 0.0:
		draw_ghost_pow()

# The POW: a ring of spirits spreads out from the body while cold flames shoot up from it.
func draw_ghost_pow() -> void:
	var t: float = 1.0 - pow_time / POW_SECONDS
	var center: Vector2 = rig.body_rect.get_center()
	var unit: float = scale_unit()
	for i in range(30):
		var angle: float = float(i) / 30.0 * TAU + t * 2.4
		var radius: float = (14.0 + 150.0 * t) * unit
		var color: Color = ghost_color(t * 0.9)
		color.a *= clampf(1.25 - t, 0.0, 1.0)
		cell(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.5), color, cs * (2.0 if i % 3 == 0 else 1.0))
	for i in range(9):
		var x: float = center.x + (float(i) - 4.0) * 12.0 * unit
		var rise: float = clampf(t * 1.6 - noise(i * 5) * 0.4, 0.0, 1.0)
		for step in range(int(rise * 9.0)):
			var color: Color = ghost_color(float(step) / 9.0)
			color.a *= clampf(1.1 - t, 0.0, 1.0)
			cell(Vector2(x + sin(time * 6.0 + step + i) * 2.0, center.y - step * cs * 2.5 * unit), color)
