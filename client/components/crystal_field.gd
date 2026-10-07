class_name CrystalField
extends Node2D

# The energy crystals floating over the battlefield and the time bombs waiting on the ground
# (0.33). It only draws what LocalMatch holds (`visible_crystals`, `bombs`); nothing here
# touches the simulation.
#   crystal  the PixelLab gem turning on a soft halo, a cone of light down to a pool of light on
#            the ground (so the player reads where it hangs), energy motes rising from it and
#            little stars orbiting it; one that comes back materialises with a flash and a ring
#   bomb     the PixelLab bomb (fuse spark, red bands that glow) squashing as it lands, its blast
#            radius dashed on the ground, a plaque with the turns left; on the last turn it
#            trembles, glows red and ticks faster

const CRYSTAL_FPS: float = 9.0
const APPEAR_TIME: float = 0.55
const LAND_TIME: float = 0.5
const BOMB_SCALE: float = 0.75
# Where the bomb's lowest opaque row sits in its 64x64 frame, and its middle column.
const BOMB_FOOT: float = 54.0
const BOMB_MIDDLE: float = 32.0

var game: LocalMatch
var time: float = 0.0
var glow: Node2D
var sprites: Node2D
# First time each crystal / bomb was drawn (keyed by position): the animations of arriving.
var born: Dictionary = {}
var landed: Dictionary = {}
# Ground under each crystal, looked up now and then (the ground changes with every crater).
var ground: Dictionary = {}
var ground_time: float = -1.0

func _ready() -> void:
	z_index = 2
	glow = Node2D.new()
	glow.show_behind_parent = true
	glow.material = AmmoArt.additive()
	glow.draw.connect(draw_glow)
	add_child(glow)
	# The bomb is drawn at 0.75x: whole art pixels at any scale, so it goes through the smoothing shader.
	sprites = Node2D.new()
	sprites.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprites.material = AmmoArt.smooth()
	sprites.draw.connect(draw_bombs)
	add_child(sprites)

func _process(delta: float) -> void:
	time += delta
	queue_redraw()
	glow.queue_redraw()
	sprites.queue_redraw()

static func bob(point: Vector2, seconds: float) -> Vector2:
	return point + Vector2(0, snappedf(sin(seconds * 2.2 + point.x * 0.013) * 5.0, 2.0))

static func ease_out_back(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x

func tone() -> Color:
	return Color(str(game.balance.crystals.color))

func active() -> bool:
	return is_instance_valid(game) and game.crystals_on

# How far the crystal has come in (0..1.1 with a little overshoot) and its age in seconds.
func arrival(entry: Dictionary) -> Vector2:
	var key: Vector2 = entry.pos
	if not born.has(key):
		born[key] = time
	var age: float = time - float(born[key])
	return Vector2(ease_out_back(age / APPEAR_TIME), age)

# The first ground under the crystal, refreshed four times a second.
func ground_under(point: Vector2) -> float:
	if time - ground_time > 0.25:
		ground.clear()
		ground_time = time
	if not ground.has(point):
		ground[point] = game.terrain.surface_y(point.x, point.y + 30.0)
	return ground[point]

func forget_gone(shown: Array[Dictionary]) -> void:
	var here: Dictionary = {}
	for entry: Dictionary in shown:
		here[entry.pos] = true
	for key: Vector2 in born.keys():
		if not here.has(key):
			born.erase(key)

func draw_glow() -> void:
	if not active():
		return
	var color: Color = tone()
	var shown: Array[Dictionary] = game.visible_crystals()
	forget_gone(shown)
	for entry: Dictionary in shown:
		draw_crystal_light(entry, color)
	for bomb: Dictionary in game.bombs:
		draw_bomb_light(bomb)

func draw_crystal_light(entry: Dictionary, color: Color) -> void:
	var come: Vector2 = arrival(entry)
	var grow: float = come.x
	var age: float = come.y
	var at: Vector2 = bob(entry.pos, time)
	var pulse: float = 0.5 + 0.5 * sin(time * 3.0 + at.x * 0.02)
	# The cone of light down to the ground, and the pool it makes there.
	var floor_y: float = ground_under(entry.pos)
	var drop: float = floor_y - at.y
	if drop > 30.0 and drop < 460.0:
		var fade: float = clampf(1.0 - (drop - 120.0) / 340.0, 0.35, 1.0) * clampf(grow, 0.0, 1.0)
		var cone: PackedVector2Array = PackedVector2Array([at + Vector2(-5, 10), at + Vector2(5, 10), Vector2(at.x + 30, floor_y), Vector2(at.x - 30, floor_y)])
		draw_polygon_glow(cone, PackedColorArray([Color(color.r, color.g, color.b, 0.13 * fade), Color(color.r, color.g, color.b, 0.13 * fade), Color(color.r, color.g, color.b, 0.0), Color(color.r, color.g, color.b, 0.0)]))
		var pool: float = (46.0 + 8.0 * pulse) * clampf(grow, 0.0, 1.0)
		glow.draw_set_transform(Vector2(at.x, floor_y), 0.0, Vector2(1.0, 0.22))
		AmmoArt.draw_glow(glow, Vector2.ZERO, pool, Color(color.r, color.g, color.b, 0.5 * fade))
		AmmoArt.draw_glow(glow, Vector2.ZERO, pool * 0.45, Color(0.85, 1.0, 1.0, 0.45 * fade))
		glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The halo.
	AmmoArt.draw_glow(glow, at, (74.0 + 8.0 * pulse) * clampf(grow, 0.0, 1.2), Color(color.r, color.g, color.b, 0.5))
	AmmoArt.draw_glow(glow, at, 34.0 * clampf(grow, 0.0, 1.2), Color(0.8, 1.0, 1.0, 0.28 + 0.14 * pulse))
	# Energy motes rising along the gem, each on its own phase.
	for i in range(6):
		var phase: float = fposmod(time * 0.42 + i * 0.1667 + at.x * 0.001, 1.0)
		var spot: Vector2 = at + Vector2(sin(phase * 7.0 + i * 2.3) * (10.0 + 6.0 * phase), 26.0 - phase * 78.0)
		glow.draw_rect(Rect2(AmmoArt.snap(spot) - Vector2(1, 1), Vector2(2, 2)), Color(0.75, 1.0, 1.0, sin(phase * PI) * 0.9))
	# Stars orbiting, flickering out of step.
	for i in range(3):
		var angle: float = time * 1.7 + i * TAU / 3.0 + at.x
		var star: Vector2 = at + Vector2.from_angle(angle) * Vector2(34.0, 26.0)
		var twinkle: float = 0.45 + 0.55 * sin(time * 9.0 + i * 2.1)
		AmmoArt.draw_sparkle(glow, star, 3.0 if twinkle > 0.6 else 2.0, Color(1, 1, 1, 0.35 + 0.6 * twinkle))
	# It just came (the first turn, or back after being taken): a ring and a flash.
	if age < APPEAR_TIME:
		var t: float = age / APPEAR_TIME
		glow.draw_arc(at, 12.0 + 70.0 * t, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.9 * (1.0 - t)), maxf(1.0, 5.0 * (1.0 - t)))
		AmmoArt.draw_glow(glow, at, 60.0 * (1.0 - t * 0.5), Color(1, 1, 1, 0.55 * (1.0 - t)))
		AmmoArt.draw_sparkle(glow, at, 6.0 + 30.0 * (1.0 - t), Color(1, 1, 1, 1.0 - t))

# A triangle fan with a colour per corner (the cone of light).
func draw_polygon_glow(points: PackedVector2Array, colors: PackedColorArray) -> void:
	glow.draw_polygon(points, colors)

func _draw() -> void:
	if not active():
		return
	for entry: Dictionary in game.visible_crystals():
		var come: Vector2 = arrival(entry)
		var at: Vector2 = AmmoArt.snap(bob(entry.pos, time))
		# Each crystal turns on its own phase; ping-pong makes the half turn a full one.
		var texture: Texture2D = AmmoArt.frame("crystal", time + entry.pos.x * 0.01, CRYSTAL_FPS, true)
		if texture == null:
			continue
		var scale_now: float = maxf(0.05, come.x)
		draw_texture_rect(texture, Rect2(at - Vector2(32, 32) * scale_now, Vector2(64, 64) * scale_now), false)

# ---------- bombs ----------

func bomb_alert(bomb: Dictionary) -> bool:
	return int(bomb.left) <= 1

func bomb_age(bomb: Dictionary) -> float:
	var key: Vector2 = bomb.pos
	if not landed.has(key):
		landed[key] = time
	return time - float(landed[key])

# Squash and stretch when it lands: wide and low, then a few damped wobbles.
func bomb_squash(age: float) -> Vector2:
	if age >= LAND_TIME:
		return Vector2.ONE
	var wobble: float = exp(-age * 8.0) * cos(age * 26.0)
	return Vector2(1.0 + 0.32 * wobble, 1.0 - 0.32 * wobble)

func bomb_sprite_rect(bomb: Dictionary, shake: Vector2) -> Rect2:
	var squash: Vector2 = bomb_squash(bomb_age(bomb))
	var size: Vector2 = Vector2(64, 64) * BOMB_SCALE * squash
	# The foot of the sprite stays on the ground whatever the squash does.
	var foot: Vector2 = (bomb.pos as Vector2) + Vector2(0, 2) + shake
	return Rect2(Vector2(foot.x - BOMB_MIDDLE * BOMB_SCALE * squash.x, foot.y - BOMB_FOOT * BOMB_SCALE * squash.y), size)

func bomb_shake(bomb: Dictionary) -> Vector2:
	if not bomb_alert(bomb):
		return Vector2.ZERO
	return Vector2(snappedf(sin(time * 61.0), 1.0), 0.0)

func draw_bombs() -> void:
	if not active():
		return
	for bomb: Dictionary in game.bombs:
		var alert: bool = bomb_alert(bomb)
		var texture: Texture2D = AmmoArt.frame("bomb", time + bomb.pos.x * 0.013, 12.0 if alert else 6.0)
		if texture == null:
			continue
		var rect: Rect2 = bomb_sprite_rect(bomb, bomb_shake(bomb))
		var heat: float = 0.5 + 0.5 * sin(time * 14.0)
		sprites.draw_texture_rect(texture, rect, false, Color(1.0, 1.0 - 0.18 * heat, 1.0 - 0.22 * heat) if alert else Color.WHITE)
		draw_plaque(bomb, rect, alert)

# The turns left, on a small plaque over the bomb.
func draw_plaque(bomb: Dictionary, rect: Rect2, alert: bool) -> void:
	var middle: Vector2 = AmmoArt.snap(Vector2(rect.get_center().x, rect.position.y - 14.0 + (snappedf(sin(time * 12.0), 1.0) if alert else 0.0)))
	var box: Rect2 = Rect2(middle - Vector2(14, 12), Vector2(28, 24))
	var edge: Color = Color("ff5a5a") if alert else Color("c8a060")
	sprites.draw_rect(Rect2(box.position - Vector2(2, 2), box.size + Vector2(4, 4)), Color("1a0a08"))
	sprites.draw_rect(box, edge)
	sprites.draw_rect(Rect2(box.position + Vector2(2, 2), box.size - Vector2(4, 4)), Color("3a0e0c") if alert else Color("2a1e14"))
	var font: Font = UiKit.font(true)
	var label: String = str(bomb.left)
	sprites.draw_string_outline(font, middle + Vector2(-14, 8), label, HORIZONTAL_ALIGNMENT_CENTER, 28.0, 22, 6, Color("1a0404"))
	sprites.draw_string(font, middle + Vector2(-14, 8), label, HORIZONTAL_ALIGNMENT_CENTER, 28.0, 22, Color("ffffff") if alert else Color("ffe6a0"))

func draw_bomb_light(bomb: Dictionary) -> void:
	var alert: bool = bomb_alert(bomb)
	var at: Vector2 = bomb.pos
	var blink: float = 0.5 + 0.5 * sin(time * (14.0 if alert else 6.0))
	var rect: Rect2 = bomb_sprite_rect(bomb, bomb_shake(bomb))
	# The blast radius on the ground, dashed and slowly turning; filled and throbbing on the last turn.
	var radius: float = float(bomb.radius)
	var danger: Color = Color(1.0, 0.3, 0.22)
	if alert:
		AmmoArt.draw_glow(glow, at, radius * 1.05, Color(danger.r, danger.g, danger.b, 0.06 + 0.07 * blink))
	var dashes: int = 28
	for i in range(dashes):
		var from: float = time * 0.25 + i * TAU / dashes
		glow.draw_arc(at, radius, from, from + TAU / dashes * 0.55, 6, Color(danger.r, danger.g, danger.b, (0.5 + 0.3 * blink) if alert else 0.26), 2.0)
	# The fuse: a hot spark flickering at the tip, and a glow in the bomb's own red.
	var tip: Vector2 = rect.position + Vector2(52.0, 8.0) * BOMB_SCALE
	AmmoArt.draw_glow(glow, tip, 16.0 + 6.0 * blink, Color(1.0, 0.62, 0.18, 0.55))
	AmmoArt.draw_sparkle(glow, tip + Vector2(snappedf(sin(time * 31.0) * 3.0, 1.0), snappedf(cos(time * 27.0) * 3.0, 1.0)), 3.0, Color(1.0, 0.9, 0.5, 0.5 + 0.5 * blink))
	AmmoArt.draw_glow(glow, rect.get_center() + Vector2(0, 4), 30.0 + (10.0 if alert else 0.0) * blink, Color(danger.r, danger.g, danger.b, (0.34 if alert else 0.12) * (0.6 + 0.4 * blink)))
