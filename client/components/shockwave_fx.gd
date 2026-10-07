class_name ShockwaveFx
extends Node

# A ring that bends the picture as it runs out from a point of the battlefield (shockwave.gdshader).
# The point is in world units; it is turned into screen coordinates every frame because the camera
# moves while the ring grows. It frees itself. Visual only.

const SHADER: Shader = preload("res://client/shaders/shockwave.gdshader")

var viewport: SubViewport
var point: Vector2 = Vector2.ZERO
var reach: float = 0.5
var life: float = 0.7
var strength: float = 0.02
var flash: float = 0.0
var age: float = 0.0
var layer: CanvasLayer
var rect: ColorRect
var material: ShaderMaterial

# `reach` is how far the ring goes, in screen heights (1.0 = the height of the screen).
static func spawn(owner: Node, port: SubViewport, at: Vector2, spread: float, seconds: float, bend: float, glare: float, glare_color: Color = Color(1.0, 0.82, 0.55)) -> ShockwaveFx:
	var wave: ShockwaveFx = ShockwaveFx.new()
	wave.viewport = port
	wave.point = at
	wave.reach = spread
	wave.life = seconds
	wave.strength = bend
	wave.flash = glare
	owner.add_child(wave)
	wave.material.set_shader_parameter("flash_color", Vector3(glare_color.r, glare_color.g, glare_color.b))
	return wave

func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 2
	viewport.add_child(layer)
	rect = ColorRect.new()
	rect.size = Vector2(1280, 720)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("radius", 0.0)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("flash", flash)
	rect.material = material
	layer.add_child(rect)
	update_center()

func update_center() -> void:
	var screen: Vector2 = viewport.get_canvas_transform() * point
	material.set_shader_parameter("center", screen / Vector2(1280, 720))

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		finish()
		return
	var t: float = age / life
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	update_center()
	material.set_shader_parameter("radius", reach * eased)
	material.set_shader_parameter("strength", strength * (1.0 - t))
	material.set_shader_parameter("thickness", 0.05 + 0.06 * t)
	material.set_shader_parameter("flash", flash * pow(1.0 - minf(1.0, t * 4.0), 2.0))

func finish() -> void:
	if is_instance_valid(layer):
		layer.queue_free()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(layer):
		layer.queue_free()
