class_name RankBadge
extends Control

# The emblem of a ranked division (0.22), drawn in code: a shield in the colour of the
# division, a star with one more point for every division and a pip for each tier. A
# character that is still being rated gets a grey shield with a question mark.

var mmr: int = 1000
var placed: bool = true
var glow: float = 0.0

static func create(parent: Node, rect: Rect2, p_mmr: int, p_placed: bool = true) -> RankBadge:
	var badge: RankBadge = RankBadge.new()
	badge.position = rect.position
	badge.size = rect.size
	badge.mmr = p_mmr
	badge.placed = p_placed
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(badge)
	return badge

func shield(center: Vector2, half: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in [Vector2(-1, -0.78), Vector2(-0.55, -1), Vector2(0.55, -1), Vector2(1, -0.78), Vector2(1, 0.15), Vector2(0.62, 0.62), Vector2(0, 1), Vector2(-0.62, 0.62), Vector2(-1, 0.15)]:
		points.append(center + Vector2(point.x * half.x, point.y * half.y))
	return points

func star(center: Vector2, outer: float, inner: float, count: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(count * 2):
		var radius: float = outer if i % 2 == 0 else inner
		var turn: float = -PI / 2.0 + PI * float(i) / float(count)
		points.append(center + Vector2(cos(turn), sin(turn)) * radius)
	return points

func _draw() -> void:
	var info: Dictionary = Ranked.division(mmr)
	var color: Color = info.color if placed else Color("7a8494")
	var half: Vector2 = Vector2(size.x * 0.46, size.y * 0.40)
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.44)
	if glow > 0.0 or (placed and int(info.index) >= 4):
		HudPaint.glow(self, center, size.x * 0.5, Color(color.r, color.g, color.b, 0.10), 4)
	var outline: PackedVector2Array = shield(center, half * 1.08)
	draw_colored_polygon(outline, Color("120a04"))
	var body: PackedVector2Array = shield(center, half)
	draw_colored_polygon(body, color.darkened(0.45))
	draw_colored_polygon(shield(center, half * 0.86), color.darkened(0.12))
	draw_colored_polygon(shield(center, half * 0.7), color.lightened(0.12))
	draw_polyline(body + PackedVector2Array([body[0]]), color.lightened(0.45), maxf(1.0, size.x / 48.0))
	if placed:
		var points: int = 3 + int(info.index)
		var emblem: PackedVector2Array = star(center + Vector2(0, -half.y * 0.04), half.x * 0.56, half.x * (0.30 if points < 6 else 0.34), points)
		draw_colored_polygon(emblem, color.darkened(0.55))
		draw_colored_polygon(star(center + Vector2(0, -half.y * 0.04), half.x * 0.46, half.x * 0.24, points), Color("fff6d8") if int(info.index) >= 2 else color.lightened(0.6))
		var tiers: int = int(info.tiers)
		if tiers > 1:
			var filled: int = tiers - int(info.tier) + 1
			var gap: float = size.x * 0.13
			for i in range(tiers):
				var at: Vector2 = Vector2(size.x * 0.5 + (float(i) - float(tiers - 1) / 2.0) * gap, size.y * 0.93)
				draw_circle(at, size.x * 0.045 + 1.0, Color("120a04"))
				draw_circle(at, size.x * 0.045, color.lightened(0.35) if i < filled else color.darkened(0.6))
	else:
		var font: Font = UiKit.font(true)
		var text: String = "?"
		var font_size: int = int(size.y * 0.5)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string_outline(font, center + Vector2(-width / 2.0, font_size * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color("120a04"))
		draw_string(font, center + Vector2(-width / 2.0, font_size * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e8eef6"))
