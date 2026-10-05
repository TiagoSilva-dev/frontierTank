class_name SkinColors
extends RefCounted

# The colour picker of an epic skin (0.29): one round swatch for the original and one for
# each alternative colour. The same row serves the Mochila (the choice is saved with the
# profile) and the shop's fitting room (the choice is only a try-on).

const SWATCH: float = 28.0
const GAP: float = 8.0

# The colour a swatch shows: the hue the skin was drawn in, turned by the colour's shift.
static func swatch_color(skin_id: String, color_id: String) -> Color:
	var turn: Array = Armory.skin_color_turn(skin_id, color_id)
	var hue: float = float(Armory.cosmetic_def(skin_id).get("recolor", {}).get("from", 0.0))
	if not turn.is_empty():
		hue += float(turn[2])
	return Color.from_hsv(fposmod(hue, 360.0) / 360.0, 0.72, 0.95)

# Adds the row at `at` inside `parent`; `on_pick(color_id)` gets "" for the original.
# Does nothing (returns null) for a skin without alternative colours.
static func build(parent: Control, at: Vector2, skin_id: String, current: String, on_pick: Callable) -> Control:
	var colors: Array = Armory.skin_colors_of(skin_id)
	if colors.is_empty():
		return null
	var row: Control = Control.new()
	row.name = "SkinColors"
	row.position = at
	parent.add_child(row)
	var options: Array = [{"id": "", "name": Lang.t("Cor original")}]
	options.append_array(colors)
	for i in range(options.size()):
		var option: Dictionary = options[i]
		var id: String = str(option.id)
		var swatch: Button = Button.new()
		swatch.name = "Swatch_" + (id if id != "" else "original")
		swatch.size = Vector2(SWATCH, SWATCH)
		swatch.position = Vector2(i * (SWATCH + GAP), 0)
		swatch.tooltip_text = Lang.t(str(option.name))
		var picked: bool = id == current
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var box: StyleBoxFlat = StyleBoxFlat.new()
			box.bg_color = swatch_color(skin_id, id)
			box.set_corner_radius_all(int(SWATCH / 2.0))
			box.set_border_width_all(3 if picked else 1)
			box.border_color = Color.WHITE if picked else Color("2a1c30")
			if state == "hover":
				box.bg_color = box.bg_color.lightened(0.15)
			swatch.add_theme_stylebox_override(state, box)
		swatch.pressed.connect(on_pick.bind(id))
		row.add_child(swatch)
	return row
