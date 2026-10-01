extends SceneTree

# Text legibility audit: opens a screen of the real game, renders it twice (with and without
# the texts) and measures, for every Label / Button / LineEdit, how well its colour stands out
# from what is drawn behind it. An outline counts when it stands out from the text colour.
#
#   godot --path . --rendering-driver opengl3 --script tools/contrast_audit.gd -- \
#     --screen=shop --demo=1 --lang=pt_BR --profile=user://capture_profile.json --min=4.5
#
# Everything after "--" also goes to the game (main.gd), so the capture helpers work too.
# Prints one line per text under --min (default 4.5, the WCAG AA ratio), worst first.

var args: Dictionary = {}
var main: Node

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1]
	call_deferred("run")

func run() -> void:
	main = (load("res://client/scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in range(int(args.get("frames", "40"))):
		await process_frame
	var shown: Image = root.get_viewport().get_texture().get_image()
	var texts: Array[Dictionary] = collect(main.ui)
	texts = texts.filter(func(entry: Dictionary) -> bool: return not scrolled_out(entry.node))
	for entry: Dictionary in texts:
		hide_text(entry.node)
	await process_frame
	await process_frame
	var bare: Image = root.get_viewport().get_texture().get_image()
	if args.has("png"):
		shown.save_png(str(args.png))
	var minimum: float = float(args.get("min", "4.5"))
	var bad: Array[Dictionary] = []
	for entry: Dictionary in texts:
		var rect: Rect2i = Rect2i(entry.rect).intersection(Rect2i(Vector2i.ZERO, bare.get_size()))
		if rect.size.x < 2 or rect.size.y < 2:
			continue
		var background: Color = average(bare, rect)
		var ratio: float = contrast(entry.color, background)
		# A thin outline (1 px) does not separate a glyph from a bright backdrop; from 2 px on it
		# counts, like film subtitles, when it is nearly black against the text colour.
		if entry.outline_size >= 2 and entry.outline.a > 0.5:
			ratio = maxf(ratio, contrast(entry.color, entry.outline) * (0.55 if entry.outline_size >= 3 else 0.4))
		if ratio < minimum:
			entry.ratio = ratio
			entry.background = background
			bad.append(entry)
	bad.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ratio < b.ratio)
	print("== %s: %d texts, %d under %.1f" % [str(args.get("screen", "title")), texts.size(), bad.size(), minimum])
	for entry: Dictionary in bad:
		print("%.2f  \"%s\"  %s on %s  at %s  [%s]" % [entry.ratio, str(entry.text).substr(0, 40).replace("\n", " "), entry.color.to_html(false), entry.background.to_html(false), str(entry.rect), entry.path])
	main.queue_free()
	await create_timer(0.3).timeout
	quit()

func collect(node: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	gather(node, found, 1.0)
	return found

func gather(node: Node, found: Array[Dictionary], alpha: float) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
	if node is Label and (node as Label).text != "" and alpha > 0.4:
		var label: Label = node
		var color: Color = label.get_theme_color("font_color")
		var outline: Color = label.get_theme_color("font_outline_color")
		var font: Font = label.get_theme_font("font")
		var size: int = label.get_theme_font_size("font_size")
		var width: float = minf(font.get_string_size(label.text.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, label.size.x)
		var rect: Rect2 = label.get_global_rect()
		var height: float = minf(font.get_height(size) * maxi(1, label.get_line_count()), rect.size.y)
		var top: float = rect.position.y + (rect.size.y - height) / 2.0 if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER else rect.position.y
		var left: float = rect.position.x
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			left += (rect.size.x - width) / 2.0
		elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			left += rect.size.x - width
		found.append({"node": label, "text": label.text, "color": color, "outline": outline, "outline_size": label.get_theme_constant("outline_size"), "rect": Rect2(left, top, width, height), "path": str(label.get_path()).get_slice("/", 6) + "/…/" + label.name})
	elif node is Button and (node as Button).text != "" and alpha > 0.4:
		var button: Button = node
		var color: Color = button.get_theme_color("font_disabled_color" if button.disabled else "font_color")
		var font: Font = button.get_theme_font("font")
		var size: int = button.get_theme_font_size("font_size")
		var width: float = minf(font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, button.size.x)
		var rect: Rect2 = button.get_global_rect()
		var height: float = minf(font.get_height(size), rect.size.y)
		found.append({"node": button, "text": button.text, "color": color, "outline": button.get_theme_color("font_outline_color"), "outline_size": button.get_theme_constant("outline_size"), "rect": Rect2(rect.position.x + (rect.size.x - width) / 2.0, rect.position.y + (rect.size.y - height) / 2.0, width, height), "path": "Button/…/" + button.name})
	for child in node.get_children():
		gather(child, found, alpha)

# A text inside a scroll box but outside its window is not on screen.
func scrolled_out(node: Node) -> bool:
	var rect: Rect2 = (node as Control).get_global_rect()
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is ScrollContainer and not (parent as ScrollContainer).get_global_rect().intersects(rect):
			return true
		parent = parent.get_parent()
	return false

func hide_text(node: Node) -> void:
	if node is Label:
		(node as Label).visible = false
	elif node is Button:
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_outline_color"]:
			(node as Button).add_theme_color_override(key, Color.TRANSPARENT)

static func average(image: Image, rect: Rect2i) -> Color:
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0
	var step: int = maxi(1, mini(rect.size.x, rect.size.y) / 6)
	for y in range(rect.position.y, rect.end.y, step):
		for x in range(rect.position.x, rect.end.x, step):
			var c: Color = image.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			count += 1
	if count == 0:
		return Color.BLACK
	sum /= count
	return Color(sum.x, sum.y, sum.z)

static func luminance(c: Color) -> float:
	var lin: Array[float] = []
	for v: float in [c.r, c.g, c.b]:
		lin.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]

static func contrast(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
