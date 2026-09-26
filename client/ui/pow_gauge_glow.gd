class_name PowGaugeGlow
extends Control

# Over the HUD's POW bar (26/09/2026): the percentage while it fills; when it is full
# ("BARRA CHEIA") the bar burns gold, sparks run along it, "POW 100%" pulses and the B
# key calls for it.

var ratio: float = 0.0
var full: bool = false
var ready_to_use: bool = false
var age: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	age += delta
	if full:
		queue_redraw()

func set_state(value: float, is_full: bool, usable: bool) -> void:
	if not is_equal_approx(value, ratio) or is_full != full or usable != ready_to_use:
		ratio = value
		full = is_full
		ready_to_use = usable
		queue_redraw()

func _draw() -> void:
	var font: Font = UiKit.font(true)
	var bar: Rect2 = Rect2(Vector2(0, 22), Vector2(size.x, 14))
	if not full:
		var text: String = "%d%%" % roundi(ratio * 100.0)
		draw_string_outline(font, Vector2(0, 18), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 13, 4, UiKit.INK)
		draw_string(font, Vector2(0, 18), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 13, Color("e0b0ff"))
		return
	var pulse: float = 0.5 + 0.5 * sin(age * 7.0)
	# Gold fire over the bar and a halo around it.
	for k in range(4):
		var grow: float = 2.0 + k * 3.0 + pulse * 2.0
		draw_rect(bar.grow(grow), Color(1.0, 0.72, 0.15, (0.55 - k * 0.12) * (0.6 + 0.4 * pulse)), false, 3.0)
	# The fill turns to molten gold with a light top edge.
	draw_rect(bar.grow(-2), Color(1.0, 0.7, 0.12, 0.92))
	draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2(bar.size.x - 4, 3)), Color(1.0, 0.95, 0.6, 0.9))
	draw_rect(bar.grow(-2), Color(1.0, 1.0, 0.8, 0.25 * pulse))
	# A light running along the bar, and sparks jumping off it.
	var run: float = fposmod(age * 1.4, 1.4) / 1.2
	if run <= 1.0:
		var x: float = bar.position.x + bar.size.x * run
		draw_rect(Rect2(x - 10, bar.position.y + 1, 20, bar.size.y - 2), Color(1, 1, 0.9, 0.7))
	for i in range(7):
		var t: float = fposmod(age * 1.6 + i * 0.37, 1.0)
		var px: float = bar.position.x + fposmod(i * 29.0 + age * 40.0, bar.size.x)
		var p: Vector2 = Vector2(px, bar.position.y - t * 16.0).snapped(Vector2(2, 2))
		draw_rect(Rect2(p, Vector2(2, 2)), Color(1.0, 0.95, 0.6, 1.0 - t))
	var text: String = "POW 100%"
	var color: Color = Color("ffe36a").lerp(Color.WHITE, pulse * 0.5)
	draw_string_outline(font, Vector2(0, 19), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 17, 6, Color("3a1400"))
	draw_string(font, Vector2(0, 19), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 17, color)
