class_name PowOrb
extends Button

# The POW button of the battle HUD (0.16), round like DDTank's: a glass orb in a bronze
# ring that fills with glowing violet liquid as the POW gauge grows (the surface waves,
# bubbles rise, the level eases up). Full, the liquid turns gold with a splash ring;
# when it can be released, rays turn behind it and it pulses. Armed for this turn it
# burns white-gold. Key B on a plate; the percentage shows while it fills.

const RADIUS: float = 44.0
const BUBBLES: int = 7

var fill: float = 0.0
var target: float = 0.0
var full: bool = false
var armed: bool = false
var time: float = 0.0
var splash: float = -1.0

static func create(parent: Node, rect: Rect2, action: Callable) -> PowOrb:
	var orb: PowOrb = PowOrb.new()
	orb.position = rect.position
	orb.size = rect.size
	orb.focus_mode = Control.FOCUS_NONE
	orb.pressed.connect(action)
	parent.add_child(orb)
	return orb

func _ready() -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= RADIUS + 3.0

func set_state(value: float, is_full: bool, is_armed: bool) -> void:
	target = clampf(value, 0.0, 1.0)
	if is_full and not full:
		splash = 0.0
	full = is_full
	armed = is_armed

func _process(delta: float) -> void:
	time += delta
	fill = move_toward(fill, target, delta * 0.9)
	if splash >= 0.0:
		splash += delta
	queue_redraw()

func liquid_colors() -> Array[Color]:
	if armed:
		return [Color("fffbe0"), Color("ffd04a"), Color("c07010")]
	if full:
		return [Color("fff0a0"), Color("ffb020"), Color("a04a08")]
	return [Color("f6c8ff"), Color("c264ff"), Color("5a18a8")]

func _draw() -> void:
	var c: Vector2 = (size / 2.0).round()
	var r: float = RADIUS - 7.0
	var can_fire: bool = full and not disabled
	var hover: bool = get_draw_mode() == DRAW_HOVER and not disabled
	var pulse: float = 0.5 + 0.5 * sin(time * (9.0 if armed else 5.0))
	var colors: Array[Color] = liquid_colors()
	# Behind: glow and turning rays while it can be released (and while armed).
	if can_fire or armed:
		HudPaint.glow(self, c, RADIUS + 24.0 + pulse * 6.0, Color(colors[1], 0.95))
		HudPaint.rays(self, c, 16, RADIUS + 30.0 + pulse * 4.0, time * (1.4 if armed else 0.6), Color(colors[0], 0.32), 0.1)
	elif full:
		HudPaint.glow(self, c, RADIUS + 12.0, Color(colors[1], 0.5))
	if splash >= 0.0 and splash < 0.6:
		var u: float = splash / 0.6
		draw_arc(c, RADIUS + u * 50.0, 0.0, TAU, 48, Color(1, 1, 0.85, 1.0 - u), 4.0 * (1.0 - u) + 1.0)
	# Bronze ring with a lit top, a shaded bottom and eight rivets.
	var lit: float = 1.0 if armed else (0.6 if hover or can_fire else 0.0)
	draw_circle(c, RADIUS + 3.0, HudPaint.INK)
	draw_circle(c, RADIUS + 1.0, HudPaint.BRONZE_DARK)
	draw_arc(c, RADIUS - 2.0, 0.0, TAU, 64, HudPaint.BRONZE.lerp(HudPaint.GOLD, lit * 0.5), 5.0)
	draw_arc(c, RADIUS - 1.0, PI * 1.08, PI * 1.92, 32, HudPaint.BRONZE_LIGHT.lerp(HudPaint.GOLD_HOT, lit * 0.7), 3.0)
	draw_arc(c, RADIUS - 2.0, PI * 0.12, PI * 0.88, 32, Color("3a1a08"), 3.0)
	for i in range(8):
		HudPaint.rivet(self, c + Vector2.from_angle(TAU * i / 8.0 + PI / 8.0) * (RADIUS - 2.0), lit)
	draw_circle(c, r + 2.0, HudPaint.INK)
	# The glass: dark inside, a soft glow of the liquid's colour at the bottom.
	draw_circle(c, r, Color("12081a"))
	draw_circle(c + Vector2(0, r * 0.3), r * 0.7, Color(colors[2], 0.35))
	draw_liquid(c, r, colors)
	# Glass reflections.
	draw_arc(c, r - 4.0, PI * 1.12, PI * 1.5, 16, Color(1, 1, 1, 0.32), 3.0)
	draw_circle(c + Vector2.from_angle(PI * 1.12) * (r - 4.0), 2.0, Color(1, 1, 1, 0.7))
	draw_arc(c, r - 3.0, PI * 0.2, PI * 0.45, 8, Color(1, 1, 1, 0.12), 2.0)
	# "POW" on the glass, and how full it is.
	var alpha: float = 1.0 if full or armed else 0.8
	var face: Color = Color("fff1b0") if armed else (Color("ffd04a") if full else Color("f0d8ff"))
	var depth: Color = Color("8a3a08") if full or armed else Color("4a1a6a")
	var y: float = c.y + (11.0 if full else 5.0)
	HudPaint.fancy(self, Vector2(c.x - r, y), tr("POW"), 32, face, depth, r * 2.0, HORIZONTAL_ALIGNMENT_CENTER, 3, 8, alpha)
	if not full:
		HudPaint.outlined(self, Vector2(c.x - r, c.y + 25.0), "%d%%" % roundi(target * 100.0), 16, Color(1, 0.94, 1, 0.9), HudPaint.INK, r * 2.0, HORIZONTAL_ALIGNMENT_CENTER)
	elif can_fire:
		for k in range(4):
			var a: float = time * 2.2 + TAU * k / 4.0
			HudPaint.sparkle(self, c + Vector2.from_angle(a) * (RADIUS + 8.0), 4.0 + 3.0 * pulse, Color(1, 1, 0.9, 0.9))
	# Key B.
	var badge: Rect2 = Rect2(c.x - RADIUS - 2.0, c.y - RADIUS - 2.0, 16, 17)
	HudPaint.plate(self, badge, Color("7a4a1c"), Color("24140a"))
	draw_rect(badge.grow(-1), Color(HudPaint.GOLD, 0.7), false, 1.0)
	HudPaint.outlined(self, Vector2(badge.position.x, badge.end.y - 3.0), "B", 16, Color("ffe6a0"), HudPaint.INK, badge.size.x, HORIZONTAL_ALIGNMENT_CENTER, 3)

func draw_liquid(c: Vector2, r: float, colors: Array[Color]) -> void:
	# Two-pixel columns from the waving surface down to the glass: a pixel-art liquid.
	if fill <= 0.005:
		return
	var level: float = c.y + r - 2.0 * r * fill
	var amp: float = 2.5 if fill > 0.03 and fill < 0.97 else 0.0
	var x: float = c.x - r + 1.0
	while x < c.x + r - 1.0:
		var dx: float = x + 1.0 - c.x
		var h: float = sqrt(maxf(0.0, r * r - dx * dx))
		var bottom: float = c.y + h
		var top: float = level + sin(x * 0.22 + time * 4.0) * amp + sin(x * 0.09 - time * 2.3) * amp * 0.6
		top = roundf(maxf(top, c.y - h))
		if top < bottom - 1.0:
			var span: float = 2.0 * r
			var top_color: Color = colors[1].lerp(colors[2], clampf((top - (c.y - r)) / span, 0.0, 1.0))
			var bottom_color: Color = colors[1].lerp(colors[2], clampf((bottom - (c.y - r)) / span, 0.0, 1.0) + 0.2)
			HudPaint.vgradient(self, Rect2(x, top, 2.0, bottom - top), top_color, bottom_color)
			if amp > 0.0 or fill < 0.999:
				draw_rect(Rect2(x, top, 2.0, 2.0), Color(colors[0], 0.95))
		x += 2.0
	# Bubbles rising through the liquid.
	for i in range(BUBBLES):
		var phase: float = float(i) * 1.618
		var bx: float = c.x + (fposmod(phase * 37.0, 1.0) - 0.5) * r * 1.3
		var rise: float = fposmod(time * (0.35 + fposmod(phase * 13.0, 0.3)) + fposmod(phase * 7.0, 1.0), 1.0)
		var by: float = c.y + r - 4.0 - rise * r * 2.0
		if by > level + 3.0:
			draw_circle(Vector2(roundf(bx + sin(time * 3.0 + phase) * 2.0), roundf(by)), 1.5 + fposmod(phase * 5.0, 1.2), Color(colors[0], 0.6))
