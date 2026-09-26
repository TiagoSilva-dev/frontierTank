class_name PowBanner
extends Control

# The POW shot's screen moment. 0.15: an anime-style cut-in replaces the comic "POW!"
# balloon. A white slash crosses the screen and opens into a slanted band in the
# weapon's colours; the shooter's portrait (their real look, drawn big) slides in and
# breaks out of the band's top edge; the special's name slams in letter by letter and
# a shine runs over it; the special's own art pops in on the right; streaks and sparks
# rush along the band. At `close` the band collapses back into a slash that releases
# the shot: the match holds the shot until then (items.json visual "pow_cutin"), so
# nothing flies unseen behind the band. Freed by itself at `close` + OUTRO.

const OUTRO: float = 0.42
const CY: float = 300.0
const SLOPE: float = -0.06
const HALF: float = 108.0
const ZOOM: float = 3.0
# The avatar is drawn at 1x on this canvas (feet at the bottom) and enlarged ZOOM times.
const CANVAS: Vector2i = Vector2i(220, 190)
const PORTRAIT_X: float = 290.0
const TEXT_X: float = 760.0
const TEXT_WIDTH: float = 560.0
const ART_X: float = 1135.0
const SILHOUETTE: Shader = preload("res://client/shaders/silhouette.gdshader")

var title: String = ""
var tint: Color = Color("ffd04a")
var art: Texture2D
var look: Dictionary = {}
var shooter_name: String = ""
var weapon_name: String = ""
var close: float = 1.15
var age: float = 0.0
var streaks: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var glints: Array[Dictionary] = []
var canvas: SubViewport
var rim_layer: Control
var portrait_layer: Control
var front_layer: Control
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var title_size: int = 80
var next_glint: float = 0.3

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	close = Armory.visual("pow_cutin")
	rng.randomize()
	for i in range(44):
		streaks.append({"v": rng.randf_range(-0.92, 0.92), "len": rng.randf_range(60, 340), "speed": rng.randf_range(1600, 3200), "x0": rng.randf() * 1700.0, "w": 2.0 * rng.randi_range(1, 3), "alpha": rng.randf_range(0.18, 0.7), "white": rng.randf() < 0.3})
	for i in range(36):
		sparks.append({"v": rng.randf_range(-1.0, 1.0), "speed": rng.randf_range(700, 1500), "x0": rng.randf() * 1600.0, "size": 2.0 * rng.randi_range(1, 3), "phase": rng.randf() * TAU, "white": rng.randf() < 0.4})
	var font: Font = UiKit.font(true)
	# The pixel font is drawn on a 16 px grid: 80, 64, 48 or 32 keep its pixels square.
	while title_size > 32 and font.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > TEXT_WIDTH:
		title_size -= 16
	if not look.is_empty():
		build_portrait()
	# Drawing order: this node (dim, rays, band, streaks, top border), the portrait's
	# coloured rim, the portrait, then everything in front (bottom border, art, text).
	rim_layer = layer(draw_rim)
	portrait_layer = layer(draw_portrait)
	front_layer = layer(draw_front)
	var rim_material: ShaderMaterial = ShaderMaterial.new()
	rim_material.shader = SILHOUETTE
	rim_material.set_shader_parameter("flat_color", tint.lightened(0.55))
	rim_layer.material = rim_material

func layer(painter: Callable) -> Control:
	var node: Control = Control.new()
	node.size = size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.draw.connect(painter.bind(node))
	add_child(node)
	return node

func build_portrait() -> void:
	# The shooter's standing look (outfit, hat, glasses, wings) rendered at 1x.
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
	avatar.show_look(look)

func _process(delta: float) -> void:
	age += delta
	if age >= close + OUTRO:
		queue_free()
		return
	if age >= next_glint and age < close:
		next_glint = age + rng.randf_range(0.05, 0.1)
		var spot: Vector2 = Vector2(rng.randf_range(TEXT_X - TEXT_WIDTH / 2.0, ART_X + 60.0), center_y(TEXT_X) + rng.randf_range(-HALF, HALF * 0.8))
		glints.append({"pos": spot, "born": age, "size": rng.randf_range(8, 18)})
	queue_redraw()
	for node: Control in [rim_layer, portrait_layer, front_layer]:
		node.queue_redraw()

# ---------- timeline ----------

func center_y(x: float) -> float:
	return CY + (x - 640.0) * SLOPE

func half() -> float:
	# The band opens from the slash with a little overshoot and closes back into it.
	if age < 0.07:
		return 0.0
	if age < 0.24:
		return HALF * ease_back((age - 0.07) / 0.17)
	if age < close:
		return HALF
	return HALF * (1.0 - ease_in((age - close) / 0.13))

func shown() -> float:
	# How much of the whole cut-in is visible (dim, rays).
	if age < close:
		return clampf(age / 0.1, 0.0, 1.0)
	return clampf(1.0 - (age - close) / OUTRO, 0.0, 1.0)

func portrait_x() -> float:
	var enter: float = ease_out((age - 0.1) / 0.22)
	var x: float = lerpf(-260.0, PORTRAIT_X, enter) + maxf(0.0, age - 0.32) * 16.0
	if age > close:
		x -= ease_in((age - close) / 0.2) * 560.0
	return x

func portrait_rect(x: float) -> Rect2:
	var zoomed: Vector2 = Vector2(CANVAS) * ZOOM
	# The feet sit below the band so it cuts the portrait at the hips.
	var feet: float = center_y(PORTRAIT_X) + HALF + 55.0
	return Rect2(Vector2(roundf(x - zoomed.x / 2.0), roundf(feet - CANVAS.y * 0.97 * ZOOM)), zoomed)

# ---------- background: dim, rays, band, streaks ----------

func _draw() -> void:
	var seen: float = shown()
	var h: float = half()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.01, 0.05, 0.5 * seen))
	# Vignette: the top and bottom of the screen darken more.
	var edge: Color = Color(0, 0, 0, 0.55 * seen)
	var clear: Color = Color(0, 0, 0, 0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 170), Vector2(0, 170)]), PackedColorArray([edge, edge, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, 550), Vector2(1280, 550), Vector2(1280, 720), Vector2(0, 720)]), PackedColorArray([clear, clear, edge, edge]))
	# Rays of light from behind the portrait, turning slowly.
	var hub: Vector2 = Vector2(portrait_x(), center_y(PORTRAIT_X) - 70.0)
	for i in range(18):
		var a: float = TAU * i / 18.0 + age * 0.35
		var width: float = 0.05 + 0.03 * (i % 3)
		var ray: Color = tint.lightened(0.3 if i % 2 == 0 else 0.6)
		ray.a = (0.09 if i % 2 == 0 else 0.05) * seen
		draw_colored_polygon(PackedVector2Array([hub, hub + Vector2.from_angle(a - width) * 1500.0, hub + Vector2.from_angle(a + width) * 1500.0]), ray)
	if h <= 0.5:
		draw_slash()
		return
	# The band: dark at the bottom, the weapon's colour at the top, a glow in the middle.
	var top_color: Color = Color.from_hsv(tint.h, clampf(tint.s * 1.2 + 0.15, 0.0, 1.0), 0.58, 0.97)
	var bottom_color: Color = Color.from_hsv(tint.h, clampf(tint.s * 1.1 + 0.2, 0.0, 1.0), 0.14, 0.97)
	draw_polygon(band(-h, h), PackedColorArray([top_color, top_color, bottom_color, bottom_color]))
	var glow: Color = tint.lightened(0.3)
	glow.a = 0.2
	var none: Color = Color(glow.r, glow.g, glow.b, 0.0)
	draw_polygon(band(-h, -h * 0.1), PackedColorArray([none, none, glow, glow]))
	draw_polygon(band(-h * 0.1, h * 0.6), PackedColorArray([glow, glow, none, none]))
	# Streaks rushing to the left, parallel to the band.
	for streak: Dictionary in streaks:
		var x: float = fposmod(float(streak.x0) - age * float(streak.speed), 1700.0) - 200.0
		var y: float = float(streak.v) * h
		var w: float = float(streak.w) / 2.0
		var head: Color = Color.WHITE if streak.white else tint.lightened(0.6)
		head.a = float(streak.alpha)
		var tail: Color = Color(head.r, head.g, head.b, 0.0)
		var end: float = x + float(streak.len)
		draw_polygon(PackedVector2Array([Vector2(x, center_y(x) + y - w), Vector2(end, center_y(end) + y - w), Vector2(end, center_y(end) + y + w), Vector2(x, center_y(x) + y + w)]), PackedColorArray([head, tail, tail, head]))
	# Top border (the portrait's head breaks out over it).
	border(-h, -1.0)

func band(from: float, to: float) -> PackedVector2Array:
	# A slice of the band between two offsets from its centre line, across the screen.
	return PackedVector2Array([Vector2(-40, center_y(-40) + from), Vector2(1320, center_y(1320) + from), Vector2(1320, center_y(1320) + to), Vector2(-40, center_y(-40) + to)])

func border(offset: float, side: float, canvas_item: CanvasItem = self) -> void:
	# Gold edge with a white core and a thin coloured line outside, anime style.
	canvas_item.draw_colored_polygon(band(offset - 3.0, offset + 3.0), Color("ffd66b"))
	canvas_item.draw_colored_polygon(band(offset - 1.0, offset + 1.0), Color(1, 1, 0.92))
	var line: Color = tint.lightened(0.5)
	line.a = 0.8
	canvas_item.draw_colored_polygon(band(offset + side * 10.0 - 1.0, offset + side * 10.0 + 1.0), line)

func draw_slash() -> void:
	# The white cut that opens the band (and closes it at the end).
	var x_end: float = lerpf(-40.0, 1320.0, ease_out(age / 0.09)) if age < close else 1320.0
	var thick: float = 7.0
	var alpha: float = 1.0
	if age >= close:
		var u: float = clampf((age - close - 0.12) / (OUTRO - 0.12), 0.0, 1.0)
		thick = lerpf(12.0, 0.0, u)
		alpha = 1.0 - u
	var glow: Color = Color(tint.lightened(0.6).r, tint.lightened(0.6).g, tint.lightened(0.6).b, 0.35 * alpha)
	draw_colored_polygon(PackedVector2Array([Vector2(-40, center_y(-40) - thick * 3.0), Vector2(x_end, center_y(x_end) - thick * 3.0), Vector2(x_end + 30, center_y(x_end + 30)), Vector2(x_end, center_y(x_end) + thick * 3.0), Vector2(-40, center_y(-40) + thick * 3.0)]), glow)
	draw_colored_polygon(PackedVector2Array([Vector2(-40, center_y(-40) - thick / 2.0), Vector2(x_end, center_y(x_end) - thick / 2.0), Vector2(x_end + 40, center_y(x_end + 40)), Vector2(x_end, center_y(x_end) + thick / 2.0), Vector2(-40, center_y(-40) + thick / 2.0)]), Color(1, 1, 1, alpha))

# ---------- portrait ----------

func portrait_quad(x: float) -> Array:
	# The portrait clipped at the band's bottom edge; above the band it may overflow.
	var rect: Rect2 = portrait_rect(x)
	var h: float = half()
	var overflow: float = 170.0 * h / HALF
	var points: PackedVector2Array = PackedVector2Array()
	for px: float in [rect.position.x, rect.end.x]:
		points.append(Vector2(px, maxf(rect.position.y, center_y(px) - h - overflow)))
	for px: float in [rect.end.x, rect.position.x]:
		points.append(Vector2(px, minf(rect.end.y, center_y(px) + h)))
	var uvs: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		uvs.append((point - rect.position) / rect.size)
	return [points, uvs]

func paint_portrait(node: CanvasItem, x: float, color: Color) -> void:
	if canvas == null or half() < 2.0:
		return
	var quad: Array = portrait_quad(x)
	node.draw_polygon(quad[0], PackedColorArray([color, color, color, color]), quad[1], canvas.get_texture())

func draw_rim(node: Control) -> void:
	# A glowing outline in the weapon's colour: the silhouette drawn around the portrait.
	var x: float = portrait_x()
	var alpha: float = clampf((age - 0.25) / 0.1, 0.0, 1.0) * shown()
	for step: Vector2 in [Vector2(-ZOOM, 0), Vector2(ZOOM, 0), Vector2(0, -ZOOM), Vector2(0, ZOOM), Vector2(-ZOOM, -ZOOM), Vector2(ZOOM, -ZOOM)]:
		node.draw_set_transform(step, 0.0, Vector2.ONE)
		paint_portrait(node, x, Color(1, 1, 1, alpha))
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_portrait(node: Control) -> void:
	var x: float = portrait_x()
	var enter: float = clampf((age - 0.1) / 0.22, 0.0, 1.0)
	if enter < 1.0:
		# Afterimages while it slides in.
		for k in range(2):
			var echo: Color = tint.lightened(0.3)
			echo.a = (0.35 - k * 0.15) * (1.0 - enter)
			paint_portrait(node, x - (k + 1) * 70.0 * (1.0 - enter), echo)
	paint_portrait(node, x, Color(1, 1, 1, shown()))

# ---------- front: bottom border, art, text, sparks, flashes ----------

func draw_front(node: Control) -> void:
	var seen: float = shown()
	var h: float = half()
	if h > 0.5:
		border(h, 1.0, node)
		draw_art(node)
		draw_texts(node)
		for spark: Dictionary in sparks:
			var x: float = fposmod(float(spark.x0) - age * float(spark.speed), 1600.0) - 150.0
			var y: float = center_y(x) + float(spark.v) * h * 1.05 + sin(age * 8.0 + float(spark.phase)) * 4.0
			var color: Color = Color(1, 1, 0.9) if spark.white else tint.lightened(0.5)
			color.a = seen
			var s: float = float(spark.size)
			node.draw_rect(Rect2(roundf(x), roundf(y), s, s), color)
	for glint: Dictionary in glints:
		var life: float = (age - float(glint.born)) / 0.3
		if life >= 1.0:
			continue
		var s: float = float(glint.size) * sin(life * PI)
		var c: Color = Color(1, 1, 0.95, seen)
		var p: Vector2 = glint.pos
		node.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.2, 0), p + Vector2(0, s), p + Vector2(-s * 0.2, 0)]), c)
		node.draw_colored_polygon(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(0, s * 0.2), p + Vector2(s, 0), p + Vector2(0, -s * 0.2)]), c)
	if age >= close:
		draw_close_slash(node)
	if age < 0.12:
		node.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55 * (1.0 - age / 0.12)))
	elif age >= close + 0.1 and age < close + 0.22:
		node.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.3 * (1.0 - (age - close - 0.1) / 0.12)))

func draw_close_slash(node: Control) -> void:
	var u: float = clampf((age - close - 0.1) / (OUTRO - 0.1), 0.0, 1.0)
	if age < close + 0.1:
		return
	var thick: float = lerpf(12.0, 0.0, u)
	var glow: Color = tint.lightened(0.6)
	glow.a = 0.4 * (1.0 - u)
	node.draw_colored_polygon(band(-thick * 2.5, thick * 2.5), glow)
	node.draw_colored_polygon(band(-thick / 2.0, thick / 2.0), Color(1, 1, 1, 1.0 - u))

func draw_art(node: Control) -> void:
	if art == null:
		return
	var pop: float = (age - 0.24) / 0.2
	if pop <= 0.0:
		return
	var s: float = 190.0 / maxf(art.get_width(), art.get_height()) * ease_back(pop)
	var spot: Vector2 = Vector2(ART_X + sin(age * 3.0) * 4.0, center_y(ART_X) - 6.0 + sin(age * 5.0) * 5.0)
	var alpha: float = 1.0
	if age > close:
		var out: float = ease_in((age - close) / 0.22)
		spot.x += out * 380.0
		s *= 1.0 + out * 0.5
		alpha = 1.0 - out
	var pulse: float = 0.5 + 0.5 * sin(age * 14.0)
	for k in range(10):
		var a: float = TAU * k / 10.0 - age * 1.2
		var ray: Color = tint.lightened(0.5)
		ray.a = 0.22 * alpha
		node.draw_colored_polygon(PackedVector2Array([spot, spot + Vector2.from_angle(a - 0.12) * 150.0, spot + Vector2.from_angle(a + 0.12) * 150.0]), ray)
	for k in range(3):
		var halo: Color = tint.lightened(0.25 + k * 0.2)
		halo.a = (0.2 + k * 0.12) * alpha
		node.draw_circle(spot, 100.0 - k * 26.0 + pulse * 6.0, halo)
	var half_size: Vector2 = art.get_size() * s / 2.0
	node.draw_set_transform(spot, sin(age * 4.0) * 0.08, Vector2.ONE)
	node.draw_texture_rect(art, Rect2(-half_size, half_size * 2.0), false, Color(1, 1, 1, alpha))
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_texts(node: Control) -> void:
	var font: Font = UiKit.font(true)
	var text: String = title.to_upper()
	var baseline: float = roundf(center_y(TEXT_X) + title_size * 0.36)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var left: float = roundf(TEXT_X - width / 2.0)
	var ascent: float = font.get_ascent(title_size)
	# Caption: a "POW" tag and the shooter's name slide in from the right.
	var caption: float = ease_out((age - 0.18) / 0.18)
	if caption > 0.0:
		var alpha: float = minf(1.0, caption * 2.0) * shown() * (1.0 - clampf((age - close) / 0.12, 0.0, 1.0))
		var tag_x: float = roundf(left + (1.0 - caption) * 140.0)
		var tag_y: float = baseline - ascent - 44.0
		var tag: PackedVector2Array = PackedVector2Array([Vector2(tag_x + 8, tag_y), Vector2(tag_x + 84, tag_y), Vector2(tag_x + 76, tag_y + 30), Vector2(tag_x, tag_y + 30)])
		node.draw_colored_polygon(tag, Color(0.55, 0.05, 0.03, alpha))
		node.draw_polyline(PackedVector2Array([tag[0], tag[1], tag[2], tag[3], tag[0]]), Color(1.0, 0.84, 0.35, alpha), 2.0)
		node.draw_string_outline(font, Vector2(tag_x + 4, tag_y + 23), tr("POW!"), HORIZONTAL_ALIGNMENT_CENTER, 80, UiKit.fs(20), 5, Color(0.16, 0.02, 0.0, alpha))
		node.draw_string(font, Vector2(tag_x + 4, tag_y + 23), tr("POW!"), HORIZONTAL_ALIGNMENT_CENTER, 80, UiKit.fs(20), Color(1.0, 0.95, 0.7, alpha))
		if shooter_name != "":
			node.draw_string_outline(font, Vector2(tag_x + 96, tag_y + 24), shooter_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(22), 6, Color(tint.darkened(0.75), alpha))
			node.draw_string(font, Vector2(tag_x + 96, tag_y + 24), shooter_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(22), Color(1, 1, 1, alpha))
	# The special's name, letter by letter: each slams down from big to its size.
	var sweep: float = lerpf(left - 120.0, left + width + 120.0, clampf((age - 0.55) / 0.4, 0.0, 1.0))
	for i in range(text.length()):
		var letter: String = text[i]
		if letter == " ":
			continue
		var p: float = clampf((age - 0.22 - i * 0.022) / 0.12, 0.0, 1.0)
		if p <= 0.0:
			continue
		var alpha: float = minf(1.0, p * 3.0) * shown()
		var x: float = left + font.get_string_size(text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		var w: float = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		var pivot: Vector2 = Vector2(roundf(x + w / 2.0), roundf(baseline - ascent * 0.4 - (1.0 - ease_out(p)) * 40.0))
		if age > close:
			var q: float = ease_in(clampf((age - close - i * 0.01) / 0.18, 0.0, 1.0))
			pivot.x += q * 420.0
			alpha *= 1.0 - q
		var s: float = lerpf(2.4, 1.0, ease_out(p))
		var shine: float = exp(-pow((x + w / 2.0 - sweep) / 50.0, 2.0))
		var at: Vector2 = Vector2(-w / 2.0, ascent * 0.4)
		node.draw_set_transform(pivot, 0.0, Vector2(s, s))
		node.draw_char_outline(font, at + Vector2(6, 6), letter, title_size, 14, Color(tint.darkened(0.8), 0.8 * alpha))
		node.draw_char_outline(font, at + Vector2(0, 4), letter, title_size, 14, Color(UiKit.INK, alpha))
		node.draw_char_outline(font, at, letter, title_size, 14, Color(UiKit.INK, alpha))
		for k in range(1, 5):
			node.draw_char(font, at + Vector2(0, k), letter, title_size, Color(0.72, 0.28, 0.05, alpha))
		node.draw_char(font, at + Vector2(0, -2), letter, title_size, Color(1.0, 0.97, 0.78, alpha))
		node.draw_char(font, at, letter, title_size, Color(1.0, 0.84, 0.25).lerp(Color.WHITE, shine * 0.85) * Color(1, 1, 1, alpha))
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The weapon, under the name.
	var sub: float = ease_out((age - 0.38) / 0.16)
	if weapon_name != "" and sub > 0.0:
		var alpha: float = sub * shown()
		if age > close:
			alpha *= 1.0 - clampf((age - close) / 0.15, 0.0, 1.0)
		var pos: Vector2 = Vector2(roundf(TEXT_X - 300.0 + (1.0 - sub) * 60.0), baseline + 36.0)
		node.draw_string_outline(font, pos, weapon_name, HORIZONTAL_ALIGNMENT_CENTER, 600, UiKit.fs(20), 6, Color(tint.darkened(0.8), alpha))
		node.draw_string(font, pos, weapon_name, HORIZONTAL_ALIGNMENT_CENTER, 600, UiKit.fs(20), Color(1.0, 0.94, 0.78, alpha))

static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

static func ease_in(t: float) -> float:
	return pow(clampf(t, 0.0, 1.0), 3.0)

static func ease_back(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x
