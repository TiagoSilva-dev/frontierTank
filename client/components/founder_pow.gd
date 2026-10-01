class_name FounderPow
extends Node

# Julgamento do Sol, the Founder POW (docs/FOUNDER_PACK.md): everything here is what the
# player SEES while the match holds the shot (`visual.founder_cutin`, the same on every
# copy, so lockstep stays in step).
#   0.00 activation   the anime cut-in (FounderCutin, 1.45 s) covers the screen; under it
#                     the Paladino takes the pow pose and his halo becomes the mandala
#   1.00 gold fragments rise around him
#   1.15 edge vignette fades in under the cut-in's closing flash
#   1.35 charge       the cut-in is gone: the Solaris swells, energy flows into its core
#   1.85 fire         flash at the muzzle, the lance leaves (the match releases it at 1.95 s)
# Flight, impact (FounderImpact + SunBlast) and the feather come from the shot itself.

const SHADER: Shader = preload("res://client/shaders/founder_vignette.gdshader")
const HEAT: Shader = preload("res://client/shaders/founder_heat.gdshader")
const CHARGE_AT: float = 1.35
const FIRE_AT: float = 1.85
const MAX_LIFE: float = 5.0

var screen: Node
var fighter: TankFighter
var t: float = 0.0
var stage: int = 0
var layer: CanvasLayer
var shade: ColorRect
var material: ShaderMaterial
var heat: ColorRect
var heat_material: ShaderMaterial
var embers: CPUParticles2D
var pull: CPUParticles2D
var closing: bool = false
var slammed: bool = false

func start() -> void:
	layer = CanvasLayer.new()
	layer.layer = 2
	screen.viewport.add_child(layer)
	shade = ColorRect.new()
	shade.size = Vector2(1280, 720)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("amount", 0.0)
	shade.material = material
	layer.add_child(shade)
	# Heat ripple around the lance (a small disc that follows it; see founder_heat.gdshader).
	heat = ColorRect.new()
	heat.size = Vector2(1280, 720)
	heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_material = ShaderMaterial.new()
	heat_material.shader = HEAT
	heat_material.set_shader_parameter("strength", 0.0)
	heat.material = heat_material
	layer.add_child(heat)
	screen.app.audio.duck(9.0, 1.6)
	screen.app.audio.play("pow_solaris_cutin", 0.0)
	screen.app.audio.play("pow_solaris_awaken", -4.0)
	fighter.fx_lock = "pow"
	fighter.play_clip("pow", 1.3)
	var tween: Tween = create_tween()
	# The cut-in covers the screen first; the vignette arrives as it closes.
	tween.tween_interval(1.15)
	tween.tween_property(material, "shader_parameter/amount", 0.6, 0.3).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	t += delta
	if not is_instance_valid(fighter) or t > MAX_LIFE:
		finish()
		return
	if stage == 0 and t >= 0.10:
		stage = 1
		if fighter.rig.founder_fx != null:
			fighter.rig.founder_fx.begin_pow()
	elif stage == 1 and t >= 1.0:
		stage = 2
		embers = FxParticles.stream(fighter, fighter.center() - fighter.position + Vector2(0, 14), {"amount": 30, "lifetime": 0.9, "speed": [30.0, 90.0], "direction": Vector2.UP, "spread": 20.0, "gravity": Vector2(0, -90), "size": [2.0, 4.0], "colors": ["ffffff", "fff0a8", "ffd25a", "f0a62c"], "box": Vector2(fighter.body_size.x * 0.45, 4), "z": 3})
	elif stage == 2 and t >= CHARGE_AT:
		stage = 3
		screen.app.audio.play("pow_solaris_charge", -2.0)
		fighter.rig.weapon_glow = 1.0
		var bump: Tween = create_tween()
		bump.tween_property(fighter.rig, "weapon_bump", 0.16, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pull = FxParticles.stream(screen.effects, fighter.weapon_point(), {"amount": 36, "lifetime": 0.4, "speed": [0.0, 10.0], "gravity": Vector2.ZERO, "size": [2.0, 4.0], "colors": ["ffffff", "fff0a8", "ffb02e"], "ring": [40.0, 58.0], "radial": -560.0, "tangential": 120.0, "z": 3})
	elif stage == 3 and t >= FIRE_AT:
		stage = 4
		screen.app.audio.play("pow_solaris_lance", -1.0, 1.0, 120)
		if is_instance_valid(pull):
			pull.emitting = false
		FxParticles.burst(screen.effects, fighter.muzzle(), {"amount": 26, "lifetime": 0.45, "speed": [80.0, 240.0], "direction": Vector2(fighter.facing, -0.25), "spread": 35.0, "gravity": Vector2.ZERO, "size": [2.0, 4.0], "colors": ["ffffff", "fff0a8", "ffd25a"], "z": 3})
		fighter.rig.weapon_glow = 0.0
		var settle: Tween = create_tween()
		settle.tween_property(fighter.rig, "weapon_bump", 0.0, 0.25)
	elif stage == 4 and t >= FIRE_AT + 0.3:
		stage = 5
		if fighter.rig.founder_fx != null:
			fighter.rig.founder_fx.end_pow()
		fighter.fx_lock = ""
		if is_instance_valid(embers):
			embers.emitting = false
	if not slammed and t >= FounderCutin.SLAM_AT:
		# The Paladino lands in the cut-in.
		slammed = true
		screen.shake = maxf(screen.shake, 0.4)
	if stage == 3:
		# The charge trembles the screen by 2 px, no more.
		screen.shake = maxf(screen.shake, 0.09)
	if is_instance_valid(pull):
		pull.position = fighter.weapon_point()
	update_heat()
	# Edge vignette leaves as the lance lands (or by itself if the shot never lands).
	if not closing and t >= 3.4:
		release()

# The ripple follows the lance (the first POW shot of the Solaris in the air).
func update_heat() -> void:
	var lance: TankProjectile = null
	for projectile: TankProjectile in screen.game.projectiles:
		if projectile.live and not projectile.special.is_empty() and projectile.owner_id == fighter.player_id and projectile.stage == "main":
			lance = projectile
			break
	if lance == null or closing:
		heat_material.set_shader_parameter("strength", 0.0)
		return
	var on_screen: Vector2 = screen.viewport.canvas_transform * lance.global_position
	heat_material.set_shader_parameter("center", Vector2(on_screen.x / 1280.0, on_screen.y / 720.0))
	heat_material.set_shader_parameter("strength", 1.0)

# The shot landed (FounderImpact takes over): the vignette lifts.
func release() -> void:
	if closing:
		return
	closing = true
	if is_instance_valid(fighter):
		fighter.fx_lock = ""
		if fighter.rig.founder_fx != null and stage < 5:
			fighter.rig.founder_fx.end_pow()
	var tween: Tween = create_tween()
	tween.tween_property(material, "shader_parameter/amount", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(finish)

func finish() -> void:
	if is_instance_valid(fighter):
		fighter.fx_lock = ""
		fighter.rig.weapon_glow = 0.0
		fighter.rig.weapon_bump = 0.0
	if is_instance_valid(embers):
		embers.queue_free()
	if is_instance_valid(pull):
		pull.queue_free()
	if is_instance_valid(layer):
		layer.queue_free()
	queue_free()
