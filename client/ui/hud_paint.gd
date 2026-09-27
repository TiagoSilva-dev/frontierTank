class_name HudPaint
extends RefCounted

# Drawing kit of the battle HUD (0.16). The HUD was flat boxes next to the POW cut-in,
# the Mochila and the characters; these helpers give every piece the same look: bronze
# frames with a lit top edge and rivets, dark glass wells, glossy gauges, soft glows,
# sparkles and the layered title letters of the cut-in (shadow, ink outline, extruded
# depth, a lit top edge). Used by the force bar, dial, timer, wind, minimap, turn queue,
# skill slots (SkillSlot), POW orb (PowOrb) and the victory/defeat moment (BattleOutcome).

const INK: Color = Color("1a0c04")
const BRONZE_DARK: Color = Color("5e2d0f")
const BRONZE: Color = Color("a8642a")
const BRONZE_LIGHT: Color = Color("e3a95a")
const GOLD: Color = Color("ffd479")
const GOLD_HOT: Color = Color("fff1b0")
const WELL_TOP: Color = Color("0b111c")
const WELL_BOTTOM: Color = Color("1b2738")
const CREAM: Color = Color("fff0d0")

# ---------- shapes ----------

static func chamfer(rect: Rect2, cut: float) -> PackedVector2Array:
	# A rectangle with its corners cut at 45°: the pixel-art "rounded" corner.
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	return PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])

static func vertical_colors(points: PackedVector2Array, top_y: float, bottom_y: float, top: Color, bottom: Color) -> PackedColorArray:
	var colors: PackedColorArray = PackedColorArray()
	for point: Vector2 in points:
		colors.append(top.lerp(bottom, clampf((point.y - top_y) / maxf(1.0, bottom_y - top_y), 0.0, 1.0)))
	return colors

static func vgradient(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color, cut: float = 0.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var points: PackedVector2Array = chamfer(rect, cut) if cut > 0.0 else PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	ci.draw_polygon(points, vertical_colors(points, rect.position.y, rect.end.y, top, bottom))

static func hgradient(ci: CanvasItem, rect: Rect2, left: Color, right: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	ci.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([left, right, right, left]))

# ---------- frames ----------

static func frame(ci: CanvasItem, rect: Rect2, lit: float = 0.0, dim: float = 0.0) -> Rect2:
	# Bronze bevel: ink edge, a metal band lit from above, a gold line on its top edge
	# and an inner ink line. `lit` (hover, armed) warms it to gold; `dim` greys it.
	# Returns the inside rect for the well.
	var top: Color = BRONZE_LIGHT.lerp(GOLD_HOT, lit * 0.6).lerp(Color("6a5a4a"), dim)
	var bottom: Color = BRONZE_DARK.lerp(BRONZE, lit * 0.5).lerp(Color("2e2620"), dim)
	ci.draw_colored_polygon(chamfer(rect, 4.0), INK)
	vgradient(ci, rect.grow(-2.0), top, bottom, 3.0)
	var shine: Color = GOLD.lerp(Color.WHITE, lit * 0.5).lerp(Color("8a7a6a"), dim)
	ci.draw_rect(Rect2(rect.position.x + 5.0, rect.position.y + 2.0, rect.size.x - 10.0, 2.0), shine)
	ci.draw_rect(Rect2(rect.position.x + 2.0, rect.position.y + 5.0, 2.0, rect.size.y - 12.0), Color(shine, 0.45))
	var inner: Rect2 = rect.grow(-5.0)
	ci.draw_colored_polygon(chamfer(inner.grow(1.0), 2.0), INK)
	return inner

static func well(ci: CanvasItem, rect: Rect2, top: Color = WELL_TOP, bottom: Color = WELL_BOTTOM) -> void:
	# Dark glass inside a frame, with a shadow under its top edge.
	vgradient(ci, rect, top, bottom, 1.0)
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2.0)), Color(0, 0, 0, 0.45))
	ci.draw_rect(Rect2(rect.position.x, rect.end.y - 1.0, rect.size.x, 1.0), Color(1, 1, 1, 0.08))

static func rivet(ci: CanvasItem, at: Vector2, lit: float = 0.0) -> void:
	var p: Vector2 = at.round()
	ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), INK)
	ci.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), BRONZE.lerp(GOLD, lit))
	ci.draw_rect(Rect2(p - Vector2(2, 2), Vector2(2, 2)), GOLD_HOT)

static func plate(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color, edge: Color = INK) -> void:
	# A small tag (key badges, ribbons): ink border, gradient face, lit top line.
	ci.draw_colored_polygon(chamfer(rect, 2.0), edge)
	vgradient(ci, rect.grow(-1.0), top, bottom, 1.0)
	ci.draw_rect(Rect2(rect.position.x + 2.0, rect.position.y + 1.0, rect.size.x - 4.0, 1.0), Color(1, 1, 1, 0.35))

# ---------- light ----------

static func glow(ci: CanvasItem, center: Vector2, radius: float, color: Color, rings: int = 5) -> void:
	# A soft round glow made of stacked translucent discs.
	for k in range(rings):
		var t: float = float(k + 1) / float(rings)
		ci.draw_circle(center, radius * (1.0 - t * 0.8), Color(color, color.a * 0.35 / rings * (1.0 + t)))

static func glow_rect(ci: CanvasItem, rect: Rect2, color: Color, spread: float = 6.0, steps: int = 4) -> void:
	for k in range(steps):
		var grow: float = spread * (1.0 - float(k) / steps)
		ci.draw_colored_polygon(chamfer(rect.grow(grow), grow + 3.0), Color(color, color.a * 0.22))

static func rays(ci: CanvasItem, hub: Vector2, count: int, length: float, turn: float, color: Color, width: float = 0.09) -> void:
	for i in range(count):
		var a: float = TAU * i / count + turn
		var w: float = width * (1.0 if i % 2 == 0 else 0.6)
		var c: Color = Color(color, color.a * (1.0 if i % 2 == 0 else 0.55))
		ci.draw_colored_polygon(PackedVector2Array([hub, hub + Vector2.from_angle(a - w) * length, hub + Vector2.from_angle(a + w) * length]), c)

static func sparkle(ci: CanvasItem, at: Vector2, size: float, color: Color) -> void:
	# The four-point glint of the cut-in.
	if size < 0.5:
		return
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -size), at + Vector2(size * 0.22, 0), at + Vector2(0, size), at + Vector2(-size * 0.22, 0)]), color)
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-size, 0), at + Vector2(0, size * 0.22), at + Vector2(size, 0), at + Vector2(0, -size * 0.22)]), color)

# ---------- gauges ----------

static func gauge(ci: CanvasItem, rect: Rect2, fraction: float, top: Color, bottom: Color, ghost: float = -1.0, ghost_color: Color = Color(1, 1, 1, 0.7), time: float = 0.0) -> Rect2:
	# A framed glossy bar: returns the well so the caller can write on it. `ghost` is a
	# second, trailing value (the life lost a moment ago) drawn behind the fill.
	var inner: Rect2 = frame(ci, rect)
	well(ci, inner, Color("07090f"), Color("141a26"))
	var room: Rect2 = inner.grow(-1.0)
	if ghost > fraction:
		ci.draw_rect(Rect2(room.position, Vector2(roundf(room.size.x * clampf(ghost, 0.0, 1.0)), room.size.y)), ghost_color)
	var width: float = roundf(room.size.x * clampf(fraction, 0.0, 1.0))
	if width >= 1.0:
		var fill: Rect2 = Rect2(room.position, Vector2(width, room.size.y))
		vgradient(ci, fill, top, bottom)
		# Gloss on the upper third and a darker lower edge.
		ci.draw_rect(Rect2(fill.position + Vector2(0, 2), Vector2(fill.size.x, maxf(2.0, roundf(fill.size.y * 0.22)))), Color(1, 1, 1, 0.28))
		ci.draw_rect(Rect2(fill.position.x, fill.end.y - 2.0, fill.size.x, 2.0), Color(0, 0, 0, 0.22))
		# Segments every tenth, like a real gauge.
		for i in range(1, 10):
			var x: float = roundf(room.position.x + room.size.x * i / 10.0)
			if x < fill.end.x - 1.0:
				ci.draw_rect(Rect2(x, fill.position.y + 2.0, 1.0, fill.size.y - 4.0), Color(0, 0, 0, 0.18))
		# A glint that runs along the fill now and then.
		var sweep: float = fposmod(time * 0.45, 1.6) - 0.3
		var gx: float = room.position.x + sweep * room.size.x
		if gx > fill.position.x and gx < fill.end.x - 3.0:
			ci.draw_rect(Rect2(roundf(gx), fill.position.y + 1.0, 3.0, fill.size.y - 2.0), Color(1, 1, 1, 0.35))
		ci.draw_rect(Rect2(fill.end.x - 2.0, fill.position.y, 2.0, fill.size.y), Color(top.lightened(0.5), 0.8))
	return inner

# ---------- text ----------

static func fancy(ci: CanvasItem, at: Vector2, text: String, size: int, main: Color, depth_color: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, depth: int = 3, outline: int = 8, alpha: float = 1.0, highlight: Color = Color(1.0, 0.97, 0.82)) -> void:
	# The cut-in's title letters as a plain string: soft shadow, ink outline, a few
	# pixels of extruded depth, then the face with a lit top edge.
	var font: Font = UiKit.font(true)
	var shadow: Color = Color(0, 0, 0, 0.45 * alpha)
	ci.draw_string_outline(font, at + Vector2(depth + 2, depth + 3), text, align, width, size, outline, shadow)
	ci.draw_string_outline(font, at + Vector2(0, depth), text, align, width, size, outline, Color(INK, alpha))
	ci.draw_string_outline(font, at, text, align, width, size, outline, Color(INK, alpha))
	for k in range(depth, 0, -1):
		ci.draw_string(font, at + Vector2(0, k), text, align, width, size, Color(depth_color, alpha))
	if highlight.a > 0.0:
		ci.draw_string(font, at + Vector2(0, -maxi(1, size / 32)), text, align, width, size, Color(highlight, highlight.a * alpha))
	ci.draw_string(font, at, text, align, width, size, Color(main, alpha))

static func outlined(ci: CanvasItem, at: Vector2, text: String, size: int, color: Color, outline: Color = INK, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, thickness: int = 4) -> void:
	var font: Font = UiKit.font(true)
	ci.draw_string_outline(font, at, text, align, width, size, thickness, outline)
	ci.draw_string(font, at, text, align, width, size, color)

static func text_width(text: String, size: int) -> float:
	return UiKit.font(true).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

static func ease_in(t: float) -> float:
	return pow(clampf(t, 0.0, 1.0), 3.0)

static func ease_back(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x
