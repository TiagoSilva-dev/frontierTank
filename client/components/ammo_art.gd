class_name AmmoArt
extends RefCounted

# The PixelLab art of the crystals and the special ammo (0.33, assets/effects/ammo/<name>/frame_NN.png)
# and the little helpers every effect of it shares: cached frames, the pixel-grid snap, a
# soft round glow texture and the additive material. Visual only.

const FOLDER: String = "res://assets/effects/ammo/"
const SMOOTH: Shader = preload("res://client/shaders/pixel_smooth.gdshader")

static var cache: Dictionary = {}
static var glow_texture: Texture2D
static var additive_material: CanvasItemMaterial
static var smooth_material: ShaderMaterial

# The frames of a folder (crystal, pickup, flare, blast, bomb, drill), loaded once.
static func frames(name: String) -> Array[Texture2D]:
	if not cache.has(name):
		cache[name] = FounderPack.folder_frames(FOLDER + name)
	return cache[name]

# One frame of a looping animation at `fps`; `ping_pong` plays it forward and back, which turns
# the crystal's half turn into a full, seamless one.
static func frame(name: String, seconds: float, fps: float, ping_pong: bool = false) -> Texture2D:
	var list: Array[Texture2D] = frames(name)
	if list.is_empty():
		return null
	var step: int = int(maxf(0.0, seconds) * fps)
	if ping_pong and list.size() > 1:
		var span: int = list.size() * 2 - 2
		var at: int = step % span
		return list[at if at < list.size() else span - at]
	return list[step % list.size()]

# One frame of a one-shot animation: `t` runs 0..1 over the whole clip.
static func clip(name: String, t: float) -> Texture2D:
	var list: Array[Texture2D] = frames(name)
	if list.is_empty():
		return null
	return list[clampi(int(t * list.size()), 0, list.size() - 1)]

# The 2x2 grid of the battlefield pixel art.
static func snap(point: Vector2) -> Vector2:
	return point.snapped(Vector2(2, 2))

# A soft round glow (white in the middle, nothing at the edge) to tint with `modulate`.
static func glow() -> Texture2D:
	if glow_texture == null:
		var gradient: Gradient = Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0)])
		var texture: GradientTexture2D = GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 128
		texture.height = 128
		glow_texture = texture
	return glow_texture

static func additive() -> CanvasItemMaterial:
	if additive_material == null:
		additive_material = CanvasItemMaterial.new()
		additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return additive_material

# Whole art pixels at any scale (see pixel_smooth.gdshader); the item must filter linearly.
static func smooth() -> ShaderMaterial:
	if smooth_material == null:
		smooth_material = ShaderMaterial.new()
		smooth_material.shader = SMOOTH
	return smooth_material

# A glow disc of `radius` world units centred on `at` (draw on an additive node).
static func draw_glow(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	canvas.draw_texture_rect(glow(), Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)

# A four-pointed sparkle (a plus with a bright middle), `size` is the arm length.
static func draw_sparkle(canvas: CanvasItem, at: Vector2, size: float, color: Color) -> void:
	var centre: Vector2 = snap(at)
	canvas.draw_rect(Rect2(centre - Vector2(1, size), Vector2(2, size * 2.0)), color)
	canvas.draw_rect(Rect2(centre - Vector2(size, 1), Vector2(size * 2.0, 2)), color)
	canvas.draw_rect(Rect2(centre - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 1, color.a))
