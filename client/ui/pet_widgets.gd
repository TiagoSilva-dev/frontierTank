class_name PetWidgets
extends RefCounted

# Small pieces of the Casa dos Mascotes shared by the screen and the Mochila: pet pictures
# (with a flat silhouette for species not found yet) and the order of the collection.

const SILHOUETTE: Shader = preload("res://client/shaders/silhouette.gdshader")

static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

static func species_texture(species: String) -> Texture2D:
	return texture(str(Pets.species_def(species).get("art", "")))

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

# Ordering of the collection: rarer first, then higher level, species, uid.
static func pet_before(a: Dictionary, b: Dictionary) -> bool:
	var ra: int = Pets.rarity_index(str(Pets.species_def(str(a.species)).rarity))
	var rb: int = Pets.rarity_index(str(Pets.species_def(str(b.species)).rarity))
	if ra != rb:
		return ra > rb
	if int(a.level) != int(b.level):
		return int(a.level) > int(b.level)
	if a.species != b.species:
		return str(a.species) < str(b.species)
	return int(a.uid) < int(b.uid)
