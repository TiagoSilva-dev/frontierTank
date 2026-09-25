class_name TankProjectile
extends Node2D

# One shot in flight. Each weapon gives it its own sprite (brick, apple, shuriken,
# plunger, TV...), a spin or nose-first flight and a trail style drawn over a soft
# glowing streak; POW specials hang extra behaviour on `special` that LocalMatch runs
# on impact, and glow gold while they fly. The dashed flight line is ShotTrails.

signal impacted(projectile: TankProjectile, point: Vector2)
signal missed(projectile: TankProjectile)

const TRAILS: Dictionary = {
	"fire": ["fff26a", "ffb02e", "ff5a1f", "b8250f"],
	"pink_fire": ["ffe0fa", "ff7ae0", "d02aa8", "7a1060"],
	"rainbow": ["ff4a4a", "ffa13a", "ffe84a", "5ce65c", "4ab8ff", "8a5cff"],
	"wind": ["ffffff", "c8f4ff", "7ad8ff"],
	"sparkle": ["ffffff", "b8ffc8", "5cff8a"],
	"hearts": ["ffd0f0", "ff7ac8", "ff3a8a"],
	"electric": ["ffffff", "a8ecff", "4ab8ff"],
	"leaves": ["9aff6a", "4ec23a", "2a7a1f"],
	"smoke": ["f0f0f0", "c0c4cc", "8a8f9c"],
	"bubbles": ["ffffff", "c8ecff", "8ad0ff"],
	"dust": ["ffd0a0", "c88a5a", "8a5a3a"],
	"jade": ["e0fff0", "7affc0", "2ab87a"],
	"plain": ["fff0c2", "edbb5b"],
}

var velocity: Vector2
var wind: float = 0.0
var gravity: float = 420.0
var terrain: DestructibleTerrain
var fighters: Array[TankFighter] = []
var owner_id: int = 0
var damage: int = 100
var radius: float = 40.0
var fly: bool = false
var freeze: bool = false
var tint: Color = Color.WHITE
var age: float = 0.0
var live: bool = true
var trail: PackedVector2Array = []
var texture: Texture2D = preload("res://assets/effects/projetil.png")
# Look
var sprite_size: float = 24.0
var spin: float = 0.0
var align: bool = false
var align_offset: float = 0.0
var trail_kind: String = "plain"
# Behaviour: "main", "fragment", "drop" (falls from the sky), "return" (boomerang)
var stage: String = "main"
var special: Dictionary = {}
var base_damage: int = 100
var base_radius: float = 40.0
var ignores_fighters_until: float = 0.25
var glow: Node2D

func _ready() -> void:
	# Additive streak under the sprite and the weapon's own trail.
	glow = Node2D.new()
	glow.show_behind_parent = true
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = additive
	glow.draw.connect(draw_glow)
	add_child(glow)

func apply_style(style: Dictionary, sprite_path: String) -> void:
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		texture = load(sprite_path)
	sprite_size = float(style.get("size", 24))
	spin = deg_to_rad(float(style.get("spin", 0)))
	align = bool(style.get("align", false))
	align_offset = deg_to_rad(float(style.get("align_offset", 0)))
	trail_kind = str(style.get("trail", "plain"))
	if not TRAILS.has(trail_kind):
		trail_kind = "plain"

func advance(delta: float) -> void:
	if not live:
		return
	age += delta
	velocity += Ballistics.acceleration(wind, gravity) * delta
	var travel: Vector2 = velocity * delta
	var steps: int = maxi(1, ceili(travel.length() / 2.0))
	for i in range(steps):
		position += travel / steps
		var hit: bool = terrain.solid(position)
		for fighter in fighters:
			if fighter.hp > 0 and (fighter.player_id != owner_id or age > ignores_fighters_until) and not fly:
				hit = hit or position.distance_to(fighter.center()) < fighter.hit_radius
		if hit:
			live = false
			impacted.emit(self, position)
			return
	trail.append(position)
	if trail.size() > 36:
		trail.remove_at(0)
	var world: Vector2 = terrain.world_size
	if position.x < -200 or position.x > world.x + 200 or position.y > world.y + 60 or age > 14.0:
		live = false
		missed.emit(self)
	queue_redraw()
	if is_instance_valid(glow):
		glow.queue_redraw()

func _draw() -> void:
	draw_trail()
	if fly:
		var heading: float = velocity.angle()
		var nose: Vector2 = Vector2.from_angle(heading) * 12
		var side: Vector2 = Vector2.from_angle(heading + PI / 2) * 7
		draw_colored_polygon(PackedVector2Array([nose, -nose * 0.6 + side, -nose * 0.2, -nose * 0.6 - side]), Color("fff8e8"))
		draw_line(-nose * 0.2, nose, Color("9aa6bd"), 1)
		return
	var rotation_now: float = velocity.angle() + align_offset if align else age * spin
	draw_set_transform(Vector2.ZERO, rotation_now, Vector2.ONE)
	var aspect: Vector2 = texture.get_size() / maxf(texture.get_width(), texture.get_height())
	var size: Vector2 = aspect * sprite_size
	draw_texture_rect(texture, Rect2(-size / 2, size), false)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func draw_glow() -> void:
	var colors: Array = TRAILS[trail_kind]
	var base: Color = tint if trail_kind == "plain" else Color(str(colors[mini(1, colors.size() - 1)]))
	var powered: bool = not special.is_empty() and stage == "main"
	var count: int = trail.size()
	if count >= 3:
		var points: PackedVector2Array = PackedVector2Array()
		var outer: PackedColorArray = PackedColorArray()
		var inner: PackedColorArray = PackedColorArray()
		for i in range(count):
			var fade: float = float(i + 1) / count
			points.append(trail[i] - position)
			outer.append(Color(base.r, base.g, base.b, 0.24 * fade * fade))
			inner.append(Color(1, 1, 1, 0.4 * fade * fade * fade))
		points.append(Vector2.ZERO)
		outer.append(Color(base.r, base.g, base.b, 0.24))
		inner.append(Color(1, 1, 1, 0.4))
		glow.draw_polyline_colors(points, outer, sprite_size * (0.95 if powered else 0.6))
		glow.draw_polyline_colors(points, inner, maxf(2.0, sprite_size * 0.2))
	if powered:
		var pulse: float = 0.5 + 0.5 * sin(age * 18.0)
		glow.draw_circle(Vector2.ZERO, sprite_size * (0.95 + 0.2 * pulse), Color(1.0, 0.75, 0.25, 0.28))
		glow.draw_circle(Vector2.ZERO, sprite_size * 0.62, Color(1.0, 0.95, 0.7, 0.32))

func draw_trail() -> void:
	var colors: Array = TRAILS[trail_kind]
	var count: int = trail.size()
	for i in range(1, count):
		var fade: float = float(i) / count
		var p: Vector2 = trail[i] - position
		var q: Vector2 = trail[i - 1] - position
		var color: Color = Color(str(colors[(count - i) % colors.size()]))
		match trail_kind:
			"rainbow":
				var band: Color = Color(str(colors[i % colors.size()]))
				draw_line(q, p, Color(band.r, band.g, band.b, fade * 0.9), 3.0 + fade * 5.0)
			"fire", "pink_fire":
				var flicker: float = sin(age * 40.0 + i * 1.7) * 2.0
				var s: float = 2.0 + fade * 6.0
				draw_rect(Rect2(p + Vector2(flicker, -flicker) - Vector2(s, s) / 2, Vector2(s, s)), Color(color.r, color.g, color.b, fade))
			"electric":
				var jitter: Vector2 = Vector2(sin(age * 60.0 + i * 3.1), cos(age * 55.0 + i * 2.3)) * 4.0
				draw_line(q, p + jitter, Color(color.r, color.g, color.b, fade), 2.0)
			"hearts":
				if i % 4 == 0:
					draw_heart(p + Vector2(sin(i + age * 6.0) * 3.0, 0), 2.0 + fade * 2.0, Color(color.r, color.g, color.b, fade))
			"sparkle":
				if i % 3 == 0:
					var s: float = 1.0 + fade * 3.0
					draw_rect(Rect2(p - Vector2(s, 0.5), Vector2(s * 2, 1)), Color(color.r, color.g, color.b, fade))
					draw_rect(Rect2(p - Vector2(0.5, s), Vector2(1, s * 2)), Color(color.r, color.g, color.b, fade))
			"smoke", "bubbles":
				if i % 2 == 0:
					var r: float = (1.0 - fade) * 7.0 + 2.0
					if trail_kind == "bubbles":
						draw_arc(p, r * 0.6, 0, TAU, 10, Color(color.r, color.g, color.b, fade), 1.0)
					else:
						draw_circle(p, r, Color(color.r, color.g, color.b, fade * 0.45))
			"wind":
				draw_line(q, p, Color(color.r, color.g, color.b, fade * 0.7), 1.0 + fade * 2.0)
				if i % 5 == 0:
					draw_arc(p, 5.0 * fade + 2.0, age * 8.0, age * 8.0 + PI, 8, Color(1, 1, 1, fade * 0.6), 1.0)
			"leaves", "dust":
				if i % 2 == 0:
					var s: float = 2.0 + fade * 2.0
					var drift: Vector2 = Vector2(sin(i * 1.3 + age * 3.0), cos(i * 0.7)) * (1.0 - fade) * 6.0
					draw_rect(Rect2(p + drift, Vector2(s, s)), Color(color.r, color.g, color.b, fade))
			_:
				draw_line(q, p, Color(tint.r, tint.g, tint.b, fade * 0.7), 2.0 + fade * 2.0)

func draw_heart(center: Vector2, s: float, color: Color) -> void:
	draw_circle(center + Vector2(-s * 0.5, 0), s * 0.6, color)
	draw_circle(center + Vector2(s * 0.5, 0), s * 0.6, color)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-s * 1.05, s * 0.2), center + Vector2(s * 1.05, s * 0.2), center + Vector2(0, s * 1.4)]), color)
