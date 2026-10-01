class_name PetWidgets
extends RefCounted

# Small pieces of the Casa dos Mascotes shared by the screen, the hatching moment and the
# Mochila: pet and egg pictures (with a flat silhouette for species not found yet) and a
# row of stars.

const SILHOUETTE: Shader = preload("res://client/shaders/silhouette.gdshader")

static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

static func species_texture(species: String) -> Texture2D:
	return texture(str(Pets.species_def(species).get("art", "")))

static func egg_texture(egg_id: String) -> Texture2D:
	return texture(str(Pets.egg_def(egg_id).get("icon", "")))

# The pet's picture; `found` false paints a dark silhouette ("???" in the album).
static func art(parent: Node, species: String, rect: Rect2, found: bool = true) -> TextureRect:
	var picture: TextureRect = UiKit.art(parent, species_texture(species), rect)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not found:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = SILHOUETTE
		material.set_shader_parameter("flat_color", Color(0.02, 0.04, 0.09, 0.9))
		picture.material = material
	return picture

static func egg_art(parent: Node, egg_id: String, rect: Rect2) -> TextureRect:
	var picture: TextureRect = UiKit.art(parent, egg_texture(egg_id), rect)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return picture

static func star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(10):
		var r: float = radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2.from_angle(-PI / 2 + i * PI / 5) * r)
	return points

# Draws `total` stars, the first `filled` lit, on any canvas item.
static func draw_stars(ci: CanvasItem, at: Vector2, filled: int, total: int, radius: float, spacing: float = -1.0) -> void:
	var step: float = spacing if spacing > 0.0 else radius * 2.3
	for i in range(total):
		var center: Vector2 = at + Vector2(radius + i * step, radius)
		var lit: bool = i < filled
		ci.draw_colored_polygon(star_points(center + Vector2(0, 1), radius + 1.5), HudPaint.INK)
		ci.draw_colored_polygon(star_points(center, radius), HudPaint.GOLD if lit else Color("2a3548"))
		if lit:
			ci.draw_colored_polygon(star_points(center, radius * 0.55), HudPaint.GOLD_HOT)

static func stars(parent: Node, at: Vector2, filled: int, total: int, radius: float = 9.0) -> Control:
	var node: Control = Control.new()
	node.position = at
	node.size = Vector2(total * radius * 2.3, radius * 2 + 3)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(func() -> void: draw_stars(node, Vector2.ZERO, filled, total, radius))
	parent.add_child(node)
	return node

# Ordering of the collection: rarer first, then more stars, higher level, species, uid.
static func pet_before(a: Dictionary, b: Dictionary) -> bool:
	var ra: int = Pets.rarity_index(str(Pets.species_def(str(a.species)).rarity))
	var rb: int = Pets.rarity_index(str(Pets.species_def(str(b.species)).rarity))
	if ra != rb:
		return ra > rb
	if int(a.stars) != int(b.stars):
		return int(a.stars) > int(b.stars)
	if int(a.level) != int(b.level):
		return int(a.level) > int(b.level)
	if a.species != b.species:
		return str(a.species) < str(b.species)
	return int(a.uid) < int(b.uid)
