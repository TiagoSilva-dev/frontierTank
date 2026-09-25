class_name FxParticles
extends RefCounted

# CPUParticles2D presets for embers, sparks, dust and motes. CPU particles run on the
# Compatibility renderer and in the web export. With no texture each particle is a
# square of `scale_amount` pixels, which keeps the pixel-art look.

# One-shot burst that frees itself. cfg keys (all optional): amount, lifetime, speed
# [min, max], direction, spread (degrees), gravity, size [min, max], colors (hex
# strings or Colors, first = birth), additive, radius (emission sphere), damping,
# radial (radial acceleration; negative pulls in), tangential, z.
static func burst(parent: Node, at: Vector2, cfg: Dictionary) -> CPUParticles2D:
	var particles: CPUParticles2D = make(cfg)
	particles.position = at
	particles.one_shot = true
	particles.explosiveness = float(cfg.get("explosiveness", 0.92))
	parent.add_child(particles)
	particles.emitting = true
	# The timer lives on the particles, so nothing dangles if the screen closes first.
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.autostart = true
	timer.wait_time = particles.lifetime * (1.0 + particles.lifetime_randomness) + 0.2
	timer.timeout.connect(particles.queue_free)
	particles.add_child(timer)
	return particles

# Continuous emitter; the caller toggles `emitting` and frees it.
static func stream(parent: Node, at: Vector2, cfg: Dictionary) -> CPUParticles2D:
	var particles: CPUParticles2D = make(cfg)
	particles.position = at
	particles.explosiveness = float(cfg.get("explosiveness", 0.0))
	parent.add_child(particles)
	particles.emitting = bool(cfg.get("emitting", true))
	return particles

static func make(cfg: Dictionary) -> CPUParticles2D:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.amount = int(cfg.get("amount", 24))
	particles.lifetime = float(cfg.get("lifetime", 0.8))
	particles.lifetime_randomness = float(cfg.get("lifetime_randomness", 0.35))
	particles.local_coords = bool(cfg.get("local", false))
	particles.z_index = int(cfg.get("z", 0))
	var speed: Array = cfg.get("speed", [80.0, 220.0])
	particles.initial_velocity_min = float(speed[0])
	particles.initial_velocity_max = float(speed[1])
	particles.direction = cfg.get("direction", Vector2.UP)
	particles.spread = float(cfg.get("spread", 180.0))
	particles.gravity = cfg.get("gravity", Vector2(0, 240))
	var size: Array = cfg.get("size", [2.0, 4.0])
	particles.scale_amount_min = float(size[0])
	particles.scale_amount_max = float(size[1])
	# Particles shrink as they die.
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1, 0.15))
	particles.scale_amount_curve = curve
	var damping: float = float(cfg.get("damping", 0.0))
	particles.damping_min = damping * 0.7
	particles.damping_max = damping
	var radial: float = float(cfg.get("radial", 0.0))
	particles.radial_accel_min = radial
	particles.radial_accel_max = radial * 0.8
	var tangential: float = float(cfg.get("tangential", 0.0))
	particles.tangential_accel_min = tangential * 0.6
	particles.tangential_accel_max = tangential
	var radius: float = float(cfg.get("radius", 0.0))
	if cfg.has("ring"):
		var ring: Array = cfg.ring
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
		particles.emission_ring_radius = float(ring[1])
		particles.emission_ring_inner_radius = float(ring[0])
	elif cfg.has("box"):
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		particles.emission_rect_extents = cfg.box
	elif radius > 0.0:
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = radius
	particles.color_ramp = ramp(cfg.get("colors", ["ffffff", "ffd04a"]))
	if bool(cfg.get("additive", true)):
		var additive: CanvasItemMaterial = CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particles.material = additive
	return particles

static func ramp(colors: Array) -> Gradient:
	# The colours spread over the first 80% of the life, then the particle fades out.
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var tones: PackedColorArray = PackedColorArray()
	for i in range(colors.size()):
		var c: Color = colors[i] if colors[i] is Color else Color(str(colors[i]))
		offsets.append(0.8 * i / maxf(1, colors.size() - 1))
		tones.append(c)
	var last: Color = tones[tones.size() - 1]
	offsets.append(1.0)
	tones.append(Color(last.r, last.g, last.b, 0.0))
	var gradient: Gradient = Gradient.new()
	gradient.offsets = offsets
	gradient.colors = tones
	return gradient
