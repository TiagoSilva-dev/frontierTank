extends SceneTree

# The premium look shared by every screen (client/ui/premium_ui.gd) and the city layout:
# each building has its own sprite and stands on the middle of its paved lot.

var errors: int = 0
var checks: int = 0

# Centre of each paved lot of assets/city/city_bg.png, in screen pixels (measured from the
# stone mask of the 640x360 painting shown at 2x).
const LOTS: Dictionary = {
	"smith": Vector2(356, 166), "auction": Vector2(930, 172), "instance": Vector2(252, 348),
	"exchange": Vector2(1027, 382), "pet": Vector2(366, 515), "mall": Vector2(642, 584),
}

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		errors += 1
		push_error(message)

func luminance(color: Color) -> float:
	var channel: Callable = func(value: float) -> float: return value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4)
	return 0.2126 * channel.call(color.r) + 0.7152 * channel.call(color.g) + 0.0722 * channel.call(color.b)

func ratio(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

func base_center(path: String) -> Vector2:
	# Middle of the bottom third of the sprite: where the building touches the ground.
	var image: Image = (load(path) as Texture2D).get_image()
	var used: Rect2i = image.get_used_rect()
	var band_top: int = used.end.y - int(used.size.y * 0.35)
	var left: int = 100000
	var right: int = -1
	for y in range(band_top, used.end.y):
		for x in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				right = maxi(right, x)
	return Vector2((left + right) / 2.0, used.end.y - (used.end.y - band_top) / 2.0)

func run_tests() -> void:
	# City: one sprite per building and the Casa de Câmbio no longer borrows the Leilão's.
	for entry: Dictionary in CityScreen.CITY_LAYOUT:
		check(ResourceLoader.exists("res://assets/city/buildings/%s.png" % entry.id), "%s has its own sprite" % entry.id)
	var exchange: Image = (load("res://assets/city/buildings/exchange.png") as Texture2D).get_image()
	var auction: Image = (load("res://assets/city/buildings/auction.png") as Texture2D).get_image()
	check(exchange.get_data() != auction.get_data(), "the Casa de Câmbio has a different building from the Leilão")
	for entry: Dictionary in CityScreen.CITY_LAYOUT:
		if not LOTS.has(entry.id):
			continue
		var rect: Array = entry.rect
		var base: Vector2 = Vector2(rect[0], rect[1]) + base_center("res://assets/city/buildings/%s.png" % entry.id)
		var lot: Vector2 = LOTS[entry.id]
		check(absf(base.x - lot.x) <= 10.0, "%s is centred on its lot (x %.0f vs %.0f)" % [entry.id, base.x, lot.x])
		check(base.y - lot.y >= 0.0 and base.y - lot.y <= 60.0, "%s stands in the lower half of its lot (y %.0f vs %.0f)" % [entry.id, base.y, lot.y])
	# The old wood and paper panels are the premium frames now.
	var host: Control = Control.new()
	root.add_child(host)
	host.theme = UiKit.make_theme()
	for kind: String in ["wood", "wood_dark", "paper", "card", "slot", "dark", "plate"]:
		check(UiKit.panel(host, Rect2(0, 0, 100, 60), kind) is PremiumPanel, "UiKit.panel(\"%s\") draws the premium frame" % kind)
	for kind: String in ["button", "button_green", "button_blue", "button_red", "tab", "tab_active", "card", "card_hover", "slot"]:
		var button: Button = UiKit.button(host, "x", Rect2(0, 0, 100, 40), Callable(), kind)
		check(button.get_theme_stylebox("normal") is StyleBoxFlat, "UiKit.button(\"%s\") is a premium steel box" % kind)
	check(host.get_theme_stylebox("normal", "Button") is StyleBoxFlat, "plain buttons take the premium theme")
	check(host.get_theme_stylebox("normal", "LineEdit") is StyleBoxFlat, "text fields take the premium theme")
	check(host.get_theme_icon("checked", "CheckBox").get_width() > 0, "check boxes have their own icons")
	# Text colours stand out from the wells they are written on (WCAG AA, 4.5:1).
	var wells: Array[Color] = [HudPaint.WELL_TOP, HudPaint.WELL_BOTTOM, Color("0c141f"), Color("1a2a40")]
	for color: Color in [UiKit.TEXT, UiKit.TEXT_MUTED, UiKit.GOOD, UiKit.BAD, UiKit.INFO, PremiumUi.GOLD, PremiumUi.DISABLED]:
		for well: Color in wells:
			check(ratio(color, well) >= 4.5, "text %s on well %s is legible (%.1f:1)" % [color.to_html(false), well.to_html(false), ratio(color, well)])
	for kind: String in PremiumUi.BUTTONS:
		var spec: Array = PremiumUi.BUTTONS[kind]
		for index in range(2):
			var face: Color = Color(spec[index])
			check(ratio(PremiumUi.TEXT, face) >= 4.5, "button text on %s (%s) is legible (%.1f:1)" % [kind, face.to_html(false), ratio(PremiumUi.TEXT, face)])
	host.queue_free()
	await process_frame
	print("PREMIUM RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors > 0 else 0)
