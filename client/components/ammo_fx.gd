class_name AmmoFx
extends Node2D

# The one-shot effects of the crystals and the special ammo (0.33), one throwaway node each,
# placed where it happens. The animated bursts are PixelLab art (assets/effects/ammo/); around
# them code adds the light (glows, rings, rays), sparks and dust, on the 2 px grid of the rest of
# the battlefield. Visual only.
#   crystal      the gem bursts: cyan burst, rings, a cross of light, shards
#   laser_fire   the muzzle of the laser: a star flare and a spray of sparks
#   drill_fire   the muzzle of the piercing missile: hot sparks and smoke
#   laser        the beam that was just fired: layered, with pulses running along it, a flare
#                where it hit and a spray of sparks back along it
#   tunnel       one bite of the piercing missile into the ground: sparks, debris and dust
#   bomb_plant   the time bomb landing: a ring of dust and a thud
#   bomb_blast   the time bomb going off: the crimson fireball, two shock rings, flash, sparks,
#                embers and smoke

const BLAST_FRAME: float = 0.075

var kind: String = ""
var data: Dictionary = {}
var age: float = 0.0
var life: float = 0.5
var tint: Color = Color("5ae8ff")
var add: Node2D
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var scale_fit: float = 1.0
var puffs: Array[Dictionary] = []

func _ready() -> void:
	z_index = 6
	rng.randomize()
	# The colour is a hex string from the balance, or already a Color (the laser's own).
	var raw: Variant = data.get("color", "5ae8ff")
	tint = raw if raw is Color else Color(str(raw))
	add = Node2D.new()
	add.material = AmmoArt.additive()
	add.draw.connect(draw_add)
	add_child(add)
	match kind:
		"crystal":
			life = 0.75
			FxParticles.burst(self, Vector2.ZERO, {"amount": 30, "lifetime": 0.75, "speed": [110.0, 340.0], "gravity": Vector2(0, 220), "size": [2.0, 5.0], "colors": ["ffffff", tint, "1a6cff"], "radius": 8.0, "z": 1})
			FxParticles.burst(self, Vector2.ZERO, {"amount": 12, "lifetime": 1.0, "speed": [20.0, 80.0], "gravity": Vector2(0, -60), "size": [2.0, 3.0], "colors": ["ffffff", "bff6ff"], "radius": 30.0, "z": 1, "damping": 1.0})
		"laser_fire":
			life = 0.4
			FxParticles.burst(self, Vector2.ZERO, {"amount": 18, "lifetime": 0.35, "speed": [80.0, 300.0], "direction": Vector2.from_angle(float(data.get("angle", 0.0))), "spread": 38.0, "gravity": Vector2(0, 80), "size": [2.0, 4.0], "colors": ["ffffff", tint, "7a1060"], "radius": 3.0, "z": 1})
		"drill_fire":
			life = 0.45
			FxParticles.burst(self, Vector2.ZERO, {"amount": 16, "lifetime": 0.4, "speed": [70.0, 260.0], "direction": Vector2.from_angle(float(data.get("angle", 0.0))), "spread": 32.0, "gravity": Vector2(0, 260), "size": [2.0, 4.0], "colors": ["fff4c0", "ffb04a", "b8250f"], "radius": 3.0, "z": 1})
			FxParticles.burst(self, Vector2.ZERO, {"amount": 6, "lifetime": 0.55, "speed": [20.0, 70.0], "direction": Vector2.UP, "spread": 50.0, "gravity": Vector2(0, -30), "size": [4.0, 7.0], "colors": ["c8c8d0", "7a7a86"], "radius": 3.0, "additive": false, "z": 0})
		"laser":
			life = 0.55
			var back: Vector2 = (to_local(data.get("from", global_position)) - Vector2.ZERO).normalized()
			FxParticles.burst(self, Vector2.ZERO, {"amount": 26, "lifetime": 0.5, "speed": [70.0, 300.0], "direction": back, "spread": 62.0, "gravity": Vector2(0, 160), "size": [2.0, 4.0], "colors": ["ffffff", tint, "7a1060"], "radius": 3.0, "z": 1})
		"tunnel":
			life = 1.2
			var colors: Array = []
			for pixel: Color in data.get("debris", PackedColorArray()):
				colors.append(pixel)
			if colors.size() < 2:
				colors = ["d8b080", "8a5a3a"]
			FxParticles.burst(self, Vector2.ZERO, {"amount": 12, "lifetime": 0.5, "speed": [50.0, 190.0], "gravity": Vector2(0, 460), "size": [2.0, 4.0], "colors": colors, "radius": 6.0, "additive": false, "z": 1})
			FxParticles.burst(self, Vector2.ZERO, {"amount": 22, "lifetime": 0.45, "speed": [90.0, 340.0], "gravity": Vector2(0, 320), "size": [2.0, 4.0], "colors": ["ffffff", "ffd070", "ff7a1a"], "radius": 4.0, "z": 2})
			FxParticles.burst(self, Vector2.ZERO, {"amount": 5, "lifetime": 0.7, "speed": [10.0, 40.0], "gravity": Vector2(0, -26), "size": [5.0, 9.0], "colors": [Color(0.6, 0.55, 0.5, 0.5), Color(0.4, 0.38, 0.36, 0.3)], "radius": 6.0, "additive": false, "z": 0})
		"bomb_plant":
			life = 0.65
			FxParticles.burst(self, Vector2(0, -4), {"amount": 14, "lifetime": 0.6, "speed": [40.0, 150.0], "direction": Vector2.UP, "spread": 75.0, "gravity": Vector2(0, 220), "size": [3.0, 6.0], "colors": [Color(0.78, 0.68, 0.54, 0.8), Color(0.5, 0.42, 0.34, 0.5)], "radius": 8.0, "additive": false, "z": 1})
			FxParticles.burst(self, Vector2(0, -8), {"amount": 8, "lifetime": 0.4, "speed": [50.0, 170.0], "direction": Vector2.UP, "spread": 60.0, "gravity": Vector2(0, 300), "size": [2.0, 3.0], "colors": ["fff0a0", tint, "6a1010"], "radius": 4.0, "z": 2})
		"bomb_blast":
			life = 1.15
			var radius: float = float(data.get("radius", 80.0))
			# The fireball frames hold the blast in about 120 of 128 px: scale to the real radius.
			scale_fit = clampf(roundf(radius * 2.7 / 128.0 * 2.0) / 2.0, 1.0, 3.5)
			FxParticles.burst(self, Vector2.ZERO, {"amount": 46, "lifetime": 0.8, "speed": [180.0, 560.0], "gravity": Vector2(0, 420), "size": [2.0, 6.0], "colors": ["ffffff", "ffd070", "ff5a1f", "7a1010"], "radius": 10.0, "z": 3})
			FxParticles.burst(self, Vector2.ZERO, {"amount": 22, "lifetime": 1.1, "speed": [40.0, 220.0], "direction": Vector2.UP, "spread": 120.0, "gravity": Vector2(0, 120), "size": [2.0, 4.0], "colors": ["ffd070", "ff7a1a", "5a1008"], "radius": radius * 0.4, "z": 3, "damping": 0.6})
			for i in range(clampi(int(radius / 9.0), 5, 10)):
				var angle: float = rng.randf_range(-PI, 0.0)
				puffs.append({"pos": Vector2.from_angle(angle) * rng.randf_range(radius * 0.2, radius * 0.8), "vel": Vector2(rng.randf_range(-22, 22), rng.randf_range(-56, -24)), "r": rng.randf_range(radius * 0.26, radius * 0.46), "delay": rng.randf_range(0.1, 0.35), "shade": rng.randf_range(0.2, 0.4)})

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	for puff: Dictionary in puffs:
		if age > float(puff.delay):
			puff.pos = puff.pos + puff.vel * delta
	queue_redraw()
	add.queue_redraw()

func t_now() -> float:
	return clampf(age / life, 0.0, 1.0)

# A sprite frame centred on the origin, `size` px wide, on the node that draws it.
func put(canvas: CanvasItem, texture: Texture2D, size: float, color: Color = Color.WHITE) -> void:
	if texture == null:
		return
	var box: Vector2 = Vector2(size, size * float(texture.get_height()) / float(texture.get_width()))
	canvas.draw_texture_rect(texture, Rect2(-box / 2.0, box), false, color)

# ---------- normal blending: the dark smoke and fire, the dust ----------

func _draw() -> void:
	match kind:
		"bomb_plant":
			# Two rings of dust running out along the ground.
			for ring in range(2):
				var u: float = clampf((age - ring * 0.07) / (life * 0.8), 0.0, 1.0)
				if u > 0.0 and u < 1.0:
					draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.28))
					draw_arc(Vector2.ZERO, 10.0 + 70.0 * u, 0.0, TAU, 36, Color(0.8, 0.7, 0.56, 0.55 * (1.0 - u)), maxf(1.0, 8.0 * (1.0 - u)))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"bomb_blast":
			var index: int = int(age / BLAST_FRAME)
			var art: Array[Texture2D] = AmmoArt.frames("blast")
			if not art.is_empty() and index < art.size():
				# The last frames of the art are burnt black spikes: the fire dissolves into the smoke instead.
				put(self, art[index], 128.0 * scale_fit, Color(1, 1, 1, clampf(1.0 - float(index - 5) / 4.0, 0.0, 1.0)))
			for puff: Dictionary in puffs:
				if age <= float(puff.delay):
					continue
				var u: float = clampf((age - float(puff.delay)) / (life - float(puff.delay)), 0.0, 1.0)
				var r: float = snappedf(float(puff.r) * (0.6 + u * 0.9), 2.0)
				var shade: float = puff.shade
				var at: Vector2 = AmmoArt.snap(puff.pos)
				draw_circle(at, r, Color(shade, shade * 0.93, shade * 0.9, 0.6 * (1.0 - u)))
				draw_circle(at + Vector2(-r * 0.3, -r * 0.3), r * 0.55, Color(shade + 0.18, shade + 0.15, shade + 0.12, 0.4 * (1.0 - u)))

# ---------- additive: light ----------

func draw_add() -> void:
	var t: float = t_now()
	match kind:
		"crystal":
			AmmoArt.draw_glow(add, Vector2.ZERO, 90.0 * (0.6 + 0.6 * t), Color(tint.r, tint.g, tint.b, 0.42 * (1.0 - t)))
			put(add, AmmoArt.clip("pickup", minf(1.0, age / 0.5)), 150.0, Color(1, 1, 1, 1.0 - smoothstep(0.5, 1.0, t)))
			for ring in range(2):
				var u: float = clampf((age - ring * 0.08) / (life * 0.85), 0.0, 1.0)
				if u > 0.0 and u < 1.0:
					var eased: float = 1.0 - pow(1.0 - u, 3.0)
					add.draw_arc(Vector2.ZERO, 14.0 + (96.0 - ring * 26.0) * eased, 0.0, TAU, 44, Color(tint.r, tint.g, tint.b, 1.0 - u) if ring == 0 else Color(1, 1, 1, 0.8 * (1.0 - u)), maxf(1.0, (6.0 - ring * 2.0) * (1.0 - u)))
			var cross: float = 1.0 - minf(1.0, t * 2.4)
			if cross > 0.0:
				AmmoArt.draw_sparkle(add, Vector2.ZERO, 10.0 + 54.0 * cross, Color(1, 1, 1, cross))
		"laser_fire":
			AmmoArt.draw_glow(add, Vector2.ZERO, 54.0 * (1.0 - t * 0.4), Color(tint.r, tint.g, tint.b, 0.7 * (1.0 - t)))
			put(add, AmmoArt.frame("flare", age, 22.0), 84.0 * (1.0 - 0.35 * t), Color(1, 1, 1, 1.0 - smoothstep(0.55, 1.0, t)))
		"drill_fire":
			AmmoArt.draw_glow(add, Vector2.ZERO, 40.0 * (1.0 - t * 0.5), Color(1.0, 0.62, 0.2, 0.7 * (1.0 - t)))
			AmmoArt.draw_sparkle(add, Vector2.ZERO, 6.0 + 16.0 * (1.0 - t), Color(1, 0.95, 0.7, 1.0 - t))
		"laser":
			draw_beam(t)
		"tunnel":
			# A flash as the drill bites, then the molten wall of the hole glowing as it cools.
			var burn: float = 1.0 - minf(1.0, t * 5.0)
			var ember: float = pow(1.0 - t, 1.8)
			AmmoArt.draw_glow(add, Vector2.ZERO, 40.0 * (0.7 + burn * 0.6), Color(1.0, 0.7, 0.3, 0.85 * burn))
			AmmoArt.draw_glow(add, Vector2.ZERO, 26.0, Color(1.0, 0.38, 0.1, 0.5 * ember))
			AmmoArt.draw_sparkle(add, Vector2.ZERO, 4.0 + 16.0 * burn, Color(1.0, 0.95, 0.8, burn))
		"bomb_plant":
			AmmoArt.draw_glow(add, Vector2(0, -10), 46.0 * (1.0 - t * 0.5), Color(tint.r, tint.g, tint.b, 0.55 * (1.0 - t)))
		"bomb_blast":
			draw_blast_light(t)

func draw_beam(t: float) -> void:
	var from: Vector2 = to_local(data.get("from", global_position))
	var length: float = from.length()
	if length < 2.0:
		return
	var along: Vector2 = -from / length
	var fade: float = pow(1.0 - t, 0.7)
	var thin: float = 0.2 + 0.8 * pow(1.0 - t, 1.6)
	# Layered beam, wide soft glow to white core; the widths collapse as it fades.
	var layers: Array = [[26.0, 0.16, tint.darkened(0.4)], [16.0, 0.32, tint], [9.0, 0.7, tint.lightened(0.35)], [4.0, 1.0, Color.WHITE]]
	for layer: Array in layers:
		var width: float = maxf(2.0, snappedf(float(layer[0]) * thin, 2.0))
		var color: Color = layer[2]
		add.draw_line(from, Vector2.ZERO, Color(color.r, color.g, color.b, float(layer[1]) * fade), width)
	# Pulses of energy running along the beam towards the impact.
	var spacing: float = 110.0
	var pulses: int = int(length / spacing) + 1
	for i in range(pulses):
		var offset: float = fposmod(i * spacing + age * 1900.0, length)
		var head: Vector2 = from + along * offset
		var tail: Vector2 = head - along * minf(offset, 34.0)
		add.draw_line(tail, head, Color(1, 1, 1, 0.9 * fade), maxf(2.0, snappedf(6.0 * thin, 2.0)))
	# The flare where it hit, a glow and a ring of scorch.
	AmmoArt.draw_glow(add, Vector2.ZERO, 60.0 * (1.0 - 0.4 * t), Color(tint.r, tint.g, tint.b, 0.8 * fade))
	put(add, AmmoArt.frame("flare", age, 20.0), 116.0 * (1.0 - 0.4 * t), Color(1, 1, 1, fade))
	add.draw_arc(Vector2.ZERO, 8.0 + 40.0 * (1.0 - pow(1.0 - t, 3.0)), 0.0, TAU, 28, Color(1, 0.8, 1, 0.8 * (1.0 - t)), maxf(1.0, 4.0 * (1.0 - t)))

func draw_blast_light(t: float) -> void:
	var radius: float = float(data.get("radius", 80.0))
	if t < 0.2:
		var flash: float = 1.0 - t / 0.2
		AmmoArt.draw_glow(add, Vector2.ZERO, radius * 1.7, Color(1.0, 0.9, 0.7, 0.95 * flash))
		AmmoArt.draw_sparkle(add, Vector2.ZERO, radius * 0.6 * flash + 10.0, Color(1, 1, 1, flash))
	AmmoArt.draw_glow(add, Vector2.ZERO, radius * 1.5, Color(1.0, 0.4, 0.15, 0.5 * (1.0 - t) * (1.0 - t)))
	# Two shock rings: a thick fiery one and a thin white one just behind it.
	var first: float = clampf(age / 0.55, 0.0, 1.0)
	if first < 1.0:
		var eased: float = 1.0 - pow(1.0 - first, 3.0)
		add.draw_arc(Vector2.ZERO, radius * (0.4 + 1.5 * eased), 0.0, TAU, 56, Color(1.0, 0.5, 0.2, 0.85 * (1.0 - first)), maxf(1.0, 12.0 * (1.0 - first)))
	var second: float = clampf((age - 0.07) / 0.5, 0.0, 1.0)
	if second > 0.0 and second < 1.0:
		var eased: float = 1.0 - pow(1.0 - second, 3.0)
		add.draw_arc(Vector2.ZERO, radius * (0.35 + 1.5 * eased), 0.0, TAU, 56, Color(1, 0.95, 0.85, 0.7 * (1.0 - second)), maxf(1.0, 4.0 * (1.0 - second)))
