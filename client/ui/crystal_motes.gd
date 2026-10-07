class_name CrystalMotes
extends Control

# When the local player takes a crystal, motes of its light fly from where it was (a point on
# the screen) along curved paths into the gem that lights up in the HUD meter. Each mote leaves
# a comet tail; when it lands the gem kicks and a ring runs out of it. Visual only: the count in
# the meter is already the match's.

signal landed

const COUNT: int = 8

var motes: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = AmmoArt.additive()
	z_index = 20
	rng.randomize()

# `from` and `to` are screen points.
func launch(from: Vector2, to: Vector2, color: Color) -> void:
	for i in range(COUNT):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var bend: Vector2 = Vector2(0, -1).rotated(rng.randf_range(-1.2, 1.2)) * rng.randf_range(70.0, 190.0)
		motes.append({
			"from": from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 18.0),
			"to": to,
			"bend": (from + to) * 0.5 + bend + Vector2(side * 40.0, 0),
			"delay": i * 0.045 + rng.randf_range(0.0, 0.05),
			"time": rng.randf_range(0.55, 0.8),
			"age": 0.0,
			"color": color,
			"done": false,
		})
	set_process(true)

static func curve(a: Vector2, control: Vector2, b: Vector2, u: float) -> Vector2:
	var near: Vector2 = a.lerp(control, u)
	var far: Vector2 = control.lerp(b, u)
	return near.lerp(far, u)

func _process(delta: float) -> void:
	for mote: Dictionary in motes:
		mote.age = float(mote.age) + delta
		if not bool(mote.done) and float(mote.age) >= float(mote.delay) + float(mote.time):
			mote.done = true
			rings.append({"at": mote.to, "age": 0.0, "color": mote.color})
			landed.emit()
	for ring: Dictionary in rings:
		ring.age = float(ring.age) + delta
	motes = motes.filter(func(mote: Dictionary) -> bool: return not bool(mote.done))
	rings = rings.filter(func(ring: Dictionary) -> bool: return float(ring.age) < 0.4)
	queue_redraw()

func _draw() -> void:
	for mote: Dictionary in motes:
		var run: float = float(mote.age) - float(mote.delay)
		if run < 0.0:
			continue
		var color: Color = mote.color
		var u: float = clampf(run / float(mote.time), 0.0, 1.0)
		# Eases in (it hangs a moment, then goes), like being pulled.
		var pull: float = u * u * (3.0 - 2.0 * u)
		var head: Vector2 = AmmoArt.snap(curve(mote.from, mote.bend, mote.to, pull))
		for k in range(10):
			var back: float = clampf(pull - k * 0.022, 0.0, 1.0)
			var spot: Vector2 = AmmoArt.snap(curve(mote.from, mote.bend, mote.to, back))
			var fade: float = 1.0 - float(k) / 10.0
			var s: float = maxf(2.0, 6.0 * fade)
			draw_rect(Rect2(spot - Vector2(s, s) / 2.0, Vector2(s, s)), Color(color.r, color.g, color.b, 0.55 * fade))
		AmmoArt.draw_glow(self, head, 18.0, Color(color.r, color.g, color.b, 0.7))
		draw_rect(Rect2(head - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 1, 1))
	for ring: Dictionary in rings:
		var t: float = float(ring.age) / 0.4
		var color: Color = ring.color
		draw_arc(ring.at, 8.0 + 22.0 * t, 0.0, TAU, 24, Color(color.r, color.g, color.b, 1.0 - t), maxf(1.0, 3.0 * (1.0 - t)))
		AmmoArt.draw_glow(self, ring.at, 22.0 * (1.0 - t * 0.4), Color(1, 1, 1, 0.5 * (1.0 - t)))
