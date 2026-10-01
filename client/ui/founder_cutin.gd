class_name FounderCutin
extends Control

# Julgamento do Sol's anime cut-in (docs/FOUNDER_PACK.md). Same family as PowBanner (the
# match holds the shot, the shooter's real portrait, the name slamming in letter by
# letter) but its own scene: a night sky with a sun behind the Paladino, a solar mandala
# turning at his back, focus lines that flicker like hand-drawn frames, two white cuts
# that open the scene, a shockwave when he lands, and a title in two lines over a royal
# blue banner. It builds up (the lines lengthen, everything trembles), then the sun
# implodes into a white flash that hands the screen back to FounderPow, where the
# Solaris charges and fires. Freed by itself at `close` + OUTRO.

const OUTRO: float = 0.4
const ZOOM: float = 4.0
const CANVAS: Vector2i = Vector2i(220, 190)
const PORTRAIT_X: float = 330.0
const FEET_Y: float = 690.0
const HUB: Vector2 = Vector2(330.0, 330.0)
const TITLE_X: float = 915.0
const TITLE_WIDTH: float = 640.0
const NAVY: Color = Color("060a28")
const ROYAL: Color = Color("2a46c8")
const GOLD: Color = Color("ffd25a")
const PALE: Color = Color("fff0a8")
const ORANGE: Color = Color("f0a62c")
const SILHOUETTE: Shader = preload("res://client/shaders/silhouette.gdshader")
const SLAM_AT: float = 0.30

var title: String = ""
var look: Dictionary = {}
var shooter_name: String = ""
var weapon_name: String = ""
var close: float = 1.45
var age: float = 0.0
var lines: Array[String] = []
var title_size: int = 80
var canvas: SubViewport
var rim_layer: Control
var portrait_layer: Control
var front_layer: Control
var mandala_frames: Array[Texture2D] = []
var power_frames: Array[Texture2D] = []
var badge: Texture2D
var dust: Array[Dictionary] = []
var glints: Array[Dictionary] = []
var next_glint: float = 0.3
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.randomize()
	mandala_frames = FounderPack.frames("mandala", "mandala_")
	power_frames = FounderPack.frames("halo", "halo_power_")
	badge = FounderUi.badge_texture(64)
	for i in range(46):
		dust.append({"x": rng.randf() * 1280.0, "y0": rng.randf() * 900.0, "speed": rng.randf_range(60.0, 220.0), "size": 2.0 * rng.randi_range(1, 2), "phase": rng.randf() * TAU, "white": rng.randf() < 0.4})
	lines = split_title(title)
	var font: Font = UiKit.font(true)
	# The pixel font is drawn on a 16 px grid: 96, 80, 64, 48 or 32 keep its pixels square.
	title_size = 96
	while title_size > 32 and widest(font) > TITLE_WIDTH:
		title_size -= 16
	if not look.is_empty():
		build_portrait()
	rim_layer = layer(draw_rim)
	portrait_layer = layer(draw_portrait)
	front_layer = layer(draw_front)
	var rim_material: ShaderMaterial = ShaderMaterial.new()
	rim_material.shader = SILHOUETTE
	rim_material.set_shader_parameter("flat_color", PALE)
	rim_layer.material = rim_material

# "Julgamento do Sol" -> ["JULGAMENTO", "DO SOL"]; a one-word name stays on one line.
static func split_title(text: String) -> Array[String]:
	var upper: String = text.to_upper().strip_edges()
	var cut: int = upper.find(" ")
	var result: Array[String] = []
	if cut < 0:
		result.append(upper)
	else:
		result.append(upper.substr(0, cut))
		result.append(upper.substr(cut + 1))
	return result

func widest(font: Font) -> float:
	var best: float = 0.0
	for line: String in lines:
		best = maxf(best, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x)
	return best

func layer(painter: Callable) -> Control:
	var node: Control = Control.new()
	node.size = size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.draw.connect(painter.bind(node))
	add_child(node)
	return node

func build_portrait() -> void:
	# The shooter's standing look (Paladino, wings, halo, Solaris) rendered at 1x.
	canvas = SubViewport.new()
	canvas.transparent_bg = true
	canvas.size = CANVAS
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(canvas)
	var avatar: AvatarView = AvatarView.new()
	avatar.pixel_scale = 1.0
	avatar.size = Vector2(CANVAS)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(avatar)
	# The mandala is this scene's aura: the weapon-level ring (red at +12) would clash.
	var shown_look: Dictionary = look.duplicate()
	shown_look["no_aura"] = true
	avatar.show_look(shown_look)

func _process(delta: float) -> void:
	age += delta
	if age >= close + OUTRO:
		queue_free()
		return
	if age >= next_glint and age < close:
		next_glint = age + rng.randf_range(0.04, 0.09)
		glints.append({"pos": Vector2(rng.randf_range(40.0, 1240.0), rng.randf_range(40.0, 680.0)), "born": age, "size": rng.randf_range(10.0, 26.0)})
	queue_redraw()
	for node: Control in [rim_layer, portrait_layer, front_layer]:
		node.queue_redraw()

# ---------- timeline ----------

# How much of the scene is visible: it opens in a flash and is gone under the white-out.
func shown() -> float:
	if age >= close + 0.1:
		return 0.0
	return clampf(age / 0.08, 0.0, 1.0)

# 0..1 over the last 0.3 s before the close: the build-up.
func tension() -> float:
	return clampf((age - (close - 0.3)) / 0.3, 0.0, 1.0)

# The whole scene trembles a little while it builds up (whole pixels).
func jitter() -> Vector2:
	var t: float = tension()
	if t <= 0.0:
		return Vector2.ZERO
	var step: int = int(age * 40.0)
	return Vector2(roundf(sin(step * 12.9898) * 3.0 * t), roundf(sin(step * 78.233) * 3.0 * t))

# Portrait: slides and slams in from big at SLAM_AT, then breathes.
func portrait_state() -> Dictionary:
	var u: float = clampf((age - 0.16) / (SLAM_AT - 0.16), 0.0, 1.0)
	var settle: float = PowBanner.ease_out(u)
	var bob: float = roundf(sin(age * 3.2) * 2.0) if age > SLAM_AT else 0.0
	var s: float = lerpf(1.7, 1.0, settle)
	return {"pos": Vector2(PORTRAIT_X, FEET_Y + bob) + jitter() + Vector2(0, (1.0 - settle) * 90.0), "scale": s, "alpha": clampf(u * 2.5, 0.0, 1.0) * shown(), "u": u}

# ---------- background ----------

func _draw() -> void:
	var seen: float = shown()
	if seen <= 0.0:
		return
	var shake: Vector2 = jitter()
	var hub: Vector2 = HUB + shake
	# Night sky: deep navy at the top, royal blue near the ground.
	var top: Color = Color(NAVY.r, NAVY.g, NAVY.b, 0.97 * seen)
	var low: Color = Color(0.09, 0.15, 0.46, 0.97 * seen)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)]), PackedColorArray([top, top, low, low]))
	# The sun behind the Paladino: warm discs that pulse faster as the tension builds.
	var pulse: float = 0.5 + 0.5 * sin(age * lerpf(6.0, 26.0, tension()))
	var rise: float = PowBanner.ease_out((age - 0.05) / 0.3)
	for k in range(6):
		var warm: Color = Color(1.0, 0.78 - k * 0.04, 0.3, (0.05 + k * 0.035 + pulse * 0.02) * seen)
		draw_circle(hub, (620.0 - k * 90.0) * rise, warm)
	# Rays of light turning slowly, long enough to cross the whole screen.
	for i in range(28):
		var a: float = TAU * i / 28.0 + age * 0.3
		var width: float = 0.035 + 0.02 * (i % 3)
		var ray: Color = PALE if i % 2 == 0 else GOLD
		ray.a = (0.11 if i % 2 == 0 else 0.06) * seen * rise
		draw_colored_polygon(PackedVector2Array([hub, hub + Vector2.from_angle(a - width) * 1700.0, hub + Vector2.from_angle(a + width) * 1700.0]), ray)
	draw_mandala(hub, seen, rise)
	draw_focus_lines(hub, seen)
	draw_shockwave(hub, seen)
	draw_cuts()

# The mandala: the same turning art that surrounds the Paladino during the POW, huge.
func draw_mandala(hub: Vector2, seen: float, rise: float) -> void:
	if mandala_frames.is_empty() or rise <= 0.0:
		return
	var frame: Texture2D = mandala_frames[int(age * 10.0) % mandala_frames.size()]
	var big: float = 192.0 * 3.0 * (0.3 + 0.7 * rise)
	var alpha: float = clampf(rise * 1.5, 0.0, 1.0) * seen
	draw_texture_rect(frame, Rect2(hub - Vector2(big, big) / 2.0, Vector2(big, big)), false, Color(1, 1, 1, 0.9 * alpha))
	# A second, larger copy turning against the first gives the depth of two rings.
	var outer: float = big * 1.3
	draw_set_transform(hub, -age * 0.35, Vector2.ONE)
	draw_texture_rect(frame, Rect2(-Vector2(outer, outer) / 2.0, Vector2(outer, outer)), false, Color(1, 0.92, 0.6, 0.28 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not power_frames.is_empty():
		var halo: Texture2D = power_frames[int(age * 12.0) % power_frames.size()]
		var ring: float = 128.0 * 3.5
		draw_texture_rect(halo, Rect2(hub - Vector2(ring, ring) / 2.0, Vector2(ring, ring)), false, Color(1, 1, 1, 0.55 * alpha))

# Anime focus lines: a fresh set every 1/20 s (the hand-drawn flicker), longer and
# denser while the tension builds.
func draw_focus_lines(hub: Vector2, seen: float) -> void:
	if age < 0.1:
		return
	var local: RandomNumberGenerator = RandomNumberGenerator.new()
	local.seed = 7919 + int(age * 20.0)
	var count: int = 64 + int(tension() * 40.0)
	for i in range(count):
		var a: float = local.randf() * TAU
		var from: float = local.randf_range(250.0, 430.0) - tension() * 90.0
		var to: float = from + local.randf_range(260.0, 760.0) + tension() * 300.0
		var half: float = local.randf_range(0.0035, 0.011)
		var color: Color = Color.WHITE if local.randf() < 0.4 else PALE
		color.a = local.randf_range(0.35, 0.9) * seen
		var tail: Color = Color(color.r, color.g, color.b, 0.0)
		draw_polygon(PackedVector2Array([hub + Vector2.from_angle(a - half) * from, hub + Vector2.from_angle(a + half) * from, hub + Vector2.from_angle(a) * to]), PackedColorArray([color, color, tail]))

# The shockwave when the Paladino lands.
func draw_shockwave(hub: Vector2, seen: float) -> void:
	var u: float = (age - SLAM_AT) / 0.45
	if u < 0.0 or u > 1.0:
		return
	var radius: float = 1000.0 * PowBanner.ease_out(u)
	var thick: float = lerpf(34.0, 4.0, u)
	var color: Color = PALE
	color.a = (1.0 - u) * 0.85 * seen
	draw_arc(hub, radius, 0.0, TAU, 96, color, thick, true)
	color = Color.WHITE
	color.a = (1.0 - u) * seen
	draw_arc(hub, radius, 0.0, TAU, 96, color, maxf(2.0, thick * 0.3), true)

# Two white cuts open the scene: top-left to bottom-right, then top-right to bottom-left.
func draw_cuts() -> void:
	var cuts: Array = [{"from": Vector2(-60, 30), "to": Vector2(1340, 690), "at": 0.05}, {"from": Vector2(1340, 60), "to": Vector2(-60, 650), "at": 0.14}]
	for cut: Dictionary in cuts:
		var u: float = (age - float(cut.at)) / 0.07
		if u <= 0.0:
			continue
		var fade: float = 1.0 - clampf((age - float(cut.at) - 0.08) / 0.4, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var head: Vector2 = (cut.from as Vector2).lerp(cut.to, clampf(u, 0.0, 1.0))
		var along: Vector2 = ((cut.to as Vector2) - (cut.from as Vector2)).normalized()
		var normal: Vector2 = Vector2(-along.y, along.x)
		var thick: float = lerpf(18.0, 5.0, 1.0 - fade) * shown()
		var glow: Color = GOLD
		glow.a = 0.45 * fade
		draw_colored_polygon(PackedVector2Array([cut.from + normal * thick * 2.5, head + normal * thick * 2.5, head + along * 40.0, head - normal * thick * 2.5, cut.from - normal * thick * 2.5]), glow)
		draw_colored_polygon(PackedVector2Array([cut.from + normal * thick * 0.5, head + normal * thick * 0.5, head + along * 60.0, head - normal * thick * 0.5, cut.from - normal * thick * 0.5]), Color(1, 1, 1, fade))

# ---------- portrait ----------

func paint_portrait(node: CanvasItem, color: Color, step: Vector2 = Vector2.ZERO, drift: float = 0.0) -> void:
	if canvas == null or shown() <= 0.0:
		return
	var state: Dictionary = portrait_state()
	var alpha: float = float(state.alpha) * color.a
	if alpha <= 0.0:
		return
	var zoomed: Vector2 = Vector2(CANVAS) * ZOOM
	var at: Vector2 = (state.pos as Vector2) + step + Vector2(drift, 0.0)
	var s: float = float(state.scale)
	node.draw_set_transform(at, 0.0, Vector2(s, s))
	node.draw_texture_rect(canvas.get_texture(), Rect2(Vector2(roundf(-zoomed.x / 2.0), roundf(-CANVAS.y * 0.97 * ZOOM)), zoomed), false, Color(color.r, color.g, color.b, alpha))
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_rim(node: Control) -> void:
	# A glowing outline in pale gold: the silhouette drawn around the portrait.
	var lit: float = clampf((age - SLAM_AT) / 0.1, 0.0, 1.0)
	for step: Vector2 in [Vector2(-ZOOM, 0), Vector2(ZOOM, 0), Vector2(0, -ZOOM), Vector2(0, ZOOM), Vector2(-ZOOM, -ZOOM), Vector2(ZOOM, -ZOOM), Vector2(-ZOOM, ZOOM), Vector2(ZOOM, ZOOM)]:
		paint_portrait(node, Color(1, 1, 1, lit), step)

func draw_portrait(node: Control) -> void:
	var u: float = float(portrait_state().u)
	if u < 1.0:
		# Afterimages trailing the slam.
		for k in range(3):
			var echo: Color = GOLD
			echo.a = (0.4 - k * 0.12) * (1.0 - u)
			paint_portrait(node, echo, Vector2.ZERO, -(k + 1) * 60.0 * (1.0 - u))
	paint_portrait(node, Color.WHITE)

# ---------- front: banner, title, tags, dust, flashes, white-out ----------

func band(from: float, to: float, left: float, right: float) -> PackedVector2Array:
	# A slanted slice of the title banner: its edges lean 40 px.
	return PackedVector2Array([Vector2(left + 40.0, from), Vector2(right + 40.0, from), Vector2(right, to), Vector2(left, to)])

func draw_front(node: Control) -> void:
	var seen: float = shown()
	if seen > 0.0:
		draw_banner(node, seen)
		draw_texts(node, seen)
		draw_dust(node, seen)
		draw_glints(node, seen)
	# White flashes: the opening, and the slam.
	if age < 0.1:
		node.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.9 * (1.0 - age / 0.1)))
	elif age >= SLAM_AT and age < SLAM_AT + 0.12:
		node.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 0.9, 0.5 * (1.0 - (age - SLAM_AT) / 0.12)))
	if age >= close:
		draw_whiteout(node)

func draw_banner(node: Control, seen: float) -> void:
	var open: float = PowBanner.ease_out((age - 0.3) / 0.22)
	if open <= 0.0:
		return
	var jit: Vector2 = jitter()
	var left: float = lerpf(1360.0, 560.0, open) + jit.x
	var right: float = 1360.0 + jit.x
	var top: float = 218.0 + jit.y
	var bottom: float = 472.0 + jit.y
	var fill_top: Color = Color(0.03, 0.06, 0.26, 0.93 * seen)
	var fill_bottom: Color = Color(0.1, 0.18, 0.55, 0.93 * seen)
	node.draw_polygon(band(top, bottom, left, right), PackedColorArray([fill_top, fill_top, fill_bottom, fill_bottom]))
	# Warm glow strip through the middle and the gold double border.
	var glow: Color = Color(1.0, 0.8, 0.35, 0.14 * seen)
	node.draw_colored_polygon(band(top + 70.0, bottom - 70.0, left, right), glow)
	for edge: float in [top, bottom]:
		node.draw_colored_polygon(band(edge - 4.0, edge + 4.0, left, right), Color(GOLD.r, GOLD.g, GOLD.b, seen))
		node.draw_colored_polygon(band(edge - 1.0, edge + 1.0, left, right), Color(1, 1, 0.94, seen))
	var line: Color = ROYAL.lightened(0.5)
	line.a = 0.8 * seen
	node.draw_colored_polygon(band(top - 14.0, top - 12.0, left + 30.0, right), line)
	node.draw_colored_polygon(band(bottom + 12.0, bottom + 14.0, left, right - 30.0), line)

func draw_texts(node: Control, seen: float) -> void:
	var font: Font = UiKit.font(true)
	var jit: Vector2 = jitter()
	var ascent: float = font.get_ascent(title_size)
	var line_height: float = title_size * 1.12
	var block: float = line_height * lines.size()
	var first_baseline: float = roundf(345.0 - block / 2.0 + ascent * 0.9) + jit.y
	var sweep: float = lerpf(TITLE_X - TITLE_WIDTH / 2.0 - 140.0, TITLE_X + TITLE_WIDTH / 2.0 + 140.0, clampf((age - 0.85) / 0.45, 0.0, 1.0))
	var index: int = 0
	for row in range(lines.size()):
		var text: String = lines[row]
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		var left: float = roundf(TITLE_X - width / 2.0 + 40.0)
		var baseline: float = first_baseline + row * line_height
		for i in range(text.length()):
			var letter: String = text[i]
			index += 1
			if letter == " ":
				continue
			var p: float = clampf((age - 0.38 - index * 0.022) / 0.14, 0.0, 1.0)
			if p <= 0.0:
				continue
			var alpha: float = minf(1.0, p * 3.0) * seen
			var x: float = left + font.get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
			var w: float = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
			var pivot: Vector2 = Vector2(roundf(x + w / 2.0) + jit.x, roundf(baseline - ascent * 0.4 - (1.0 - PowBanner.ease_out(p)) * 70.0))
			var s: float = lerpf(2.8, 1.0, PowBanner.ease_out(p))
			var shine: float = exp(-pow((x + w / 2.0 - sweep) / 55.0, 2.0))
			var at: Vector2 = Vector2(-w / 2.0, ascent * 0.4)
			node.draw_set_transform(pivot, 0.0, Vector2(s, s))
			node.draw_char_outline(font, at + Vector2(7, 7), letter, title_size, 16, Color(0.0, 0.02, 0.15, 0.85 * alpha))
			node.draw_char_outline(font, at + Vector2(0, 4), letter, title_size, 16, Color(UiKit.INK, alpha))
			node.draw_char_outline(font, at, letter, title_size, 16, Color(UiKit.INK, alpha))
			for k in range(1, 6):
				node.draw_char(font, at + Vector2(0, k), letter, title_size, Color(0.78, 0.34, 0.06, alpha))
			node.draw_char(font, at + Vector2(0, -2), letter, title_size, Color(1.0, 0.98, 0.82, alpha))
			node.draw_char(font, at, letter, title_size, Color(1.0, 0.82, 0.22).lerp(Color.WHITE, shine * 0.9) * Color(1, 1, 1, alpha))
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Above the banner: the Founder badge and the shooter's name.
	var tag: float = PowBanner.ease_out((age - 0.5) / 0.2)
	if tag > 0.0:
		var alpha: float = tag * seen
		var x: float = roundf(600.0 + (1.0 - tag) * 120.0) + jit.x
		var y: float = 168.0 + jit.y
		if badge != null:
			node.draw_texture_rect(badge, Rect2(Vector2(x, y - 22.0), Vector2(44, 44)), false, Color(1, 1, 1, alpha))
		var label: String = tr("FUNDADOR")
		if shooter_name != "":
			label += "  ·  " + shooter_name
		node.draw_string_outline(font, Vector2(x + 56.0, y + 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, 640, UiKit.fs(32), 7, Color(0.0, 0.02, 0.15, alpha))
		node.draw_string(font, Vector2(x + 56.0, y + 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, 640, UiKit.fs(32), Color(1.0, 0.94, 0.6, alpha))
	# Under the banner: the weapon's name.
	var sub: float = PowBanner.ease_out((age - 0.62) / 0.2)
	if weapon_name != "" and sub > 0.0:
		var alpha: float = sub * seen
		var pos: Vector2 = Vector2(roundf(600.0 + (1.0 - sub) * 100.0) + jit.x, 520.0 + jit.y)
		node.draw_string_outline(font, pos, "✦ " + weapon_name.to_upper() + " ✦", HORIZONTAL_ALIGNMENT_LEFT, 640, UiKit.fs(32), 7, Color(0.0, 0.02, 0.15, alpha))
		node.draw_string(font, pos, "✦ " + weapon_name.to_upper() + " ✦", HORIZONTAL_ALIGNMENT_LEFT, 640, UiKit.fs(32), Color(1.0, 0.94, 0.7, alpha))

# Gold dust rising through the whole scene.
func draw_dust(node: Control, seen: float) -> void:
	for mote: Dictionary in dust:
		var y: float = 780.0 - fposmod(float(mote.y0) + age * float(mote.speed), 900.0)
		var x: float = float(mote.x) + sin(age * 2.0 + float(mote.phase)) * 14.0
		var color: Color = Color.WHITE if mote.white else GOLD
		color.a = seen * 0.9
		var s: float = float(mote.size)
		node.draw_rect(Rect2(roundf(x / 2.0) * 2.0, roundf(y / 2.0) * 2.0, s, s), color)

func draw_glints(node: Control, seen: float) -> void:
	for glint: Dictionary in glints:
		var life: float = (age - float(glint.born)) / 0.3
		if life >= 1.0:
			continue
		var s: float = float(glint.size) * sin(life * PI)
		if s < 0.5:
			continue
		var c: Color = Color(1, 1, 0.95, seen)
		var p: Vector2 = glint.pos
		node.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.2, 0), p + Vector2(0, s), p + Vector2(-s * 0.2, 0)]), c)
		node.draw_colored_polygon(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(0, s * 0.2), p + Vector2(s, 0), p + Vector2(0, -s * 0.2)]), c)

# The sun implodes into a white disc that fills the screen, then fades to give the
# world back (FounderPow has the Solaris charging under it).
func draw_whiteout(node: Control) -> void:
	var u: float = age - close
	var radius: float = 1700.0 * PowBanner.ease_out(u / 0.14)
	var alpha: float = 1.0 if u < 0.16 else 1.0 - clampf((u - 0.16) / (OUTRO - 0.16), 0.0, 1.0)
	node.draw_circle(HUB, radius, Color(1, 1, 0.94, alpha))
	if u < 0.12:
		var ring: Color = GOLD
		ring.a = 1.0 - u / 0.12
		node.draw_arc(HUB, radius, 0.0, TAU, 96, ring, 14.0, true)
