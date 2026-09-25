class_name PixelIcons
extends RefCounted

# Small procedural pixel icons (16x16 or 24x24, auto outlined). They stand in for
# interface icons until matching PixelLab art is generated; see docs/PIXELLAB_0_4.md.

const OUTLINE: Color = Color("2a1608")
static var cache: Dictionary = {}

class Canvas:
	var size: int
	var image: Image

	func _init(canvas_size: int) -> void:
		size = canvas_size
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	func px(x: int, y: int, color: Color) -> void:
		if x >= 0 and y >= 0 and x < size and y < size:
			image.set_pixel(x, y, color)

	func rect(x: int, y: int, w: int, h: int, color: Color) -> void:
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				px(xx, yy, color)

	func circle(cx: float, cy: float, r: float, color: Color) -> void:
		for yy in range(size):
			for xx in range(size):
				if Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length() <= r:
					px(xx, yy, color)

	func ring(cx: float, cy: float, r: float, width: float, color: Color) -> void:
		for yy in range(size):
			for xx in range(size):
				var d: float = Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length()
				if d <= r and d > r - width:
					px(xx, yy, color)

	func line(x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
		var steps: int = maxi(absi(x1 - x0), absi(y1 - y0))
		for i in range(steps + 1):
			var t: float = float(i) / maxf(1.0, steps)
			px(roundi(lerpf(x0, x1, t)), roundi(lerpf(y0, y1, t)), color)

	func poly(points: PackedVector2Array, color: Color) -> void:
		for yy in range(size):
			for xx in range(size):
				if Geometry2D.is_point_in_polygon(Vector2(xx + 0.5, yy + 0.5), points):
					px(xx, yy, color)

	func outline(color: Color) -> void:
		var copy: Image = image.duplicate()
		for yy in range(size):
			for xx in range(size):
				if copy.get_pixel(xx, yy).a > 0.1:
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = xx + d.x
					var ny: int = yy + d.y
					if nx >= 0 and ny >= 0 and nx < size and ny < size and copy.get_pixel(nx, ny).a > 0.1 and copy.get_pixel(nx, ny) != color:
						image.set_pixel(xx, yy, color)
						break

static func get_icon(name: String) -> Texture2D:
	if cache.has(name):
		return cache[name]
	# PixelLab art dropped in assets/ui/icons replaces the procedural icon.
	var override: String = "res://assets/ui/icons/%s.png" % name
	if ResourceLoader.exists(override):
		cache[name] = load(override)
		return cache[name]
	var c: Canvas = Canvas.new(18)
	match name:
		"shop":
			c.rect(3, 8, 12, 7, Color("a8642a"))
			c.rect(3, 13, 12, 2, Color("6e3510"))
			for i in range(6):
				c.rect(2 + i * 2, 3, 2, 5, Color("e8402f") if i % 2 == 0 else Color("fff4d6"))
			c.rect(2, 3, 14, 1, Color("ff7a5c"))
			c.circle(9, 11, 2.2, Color("ffd04a"))
			c.px(8, 10, Color("fff4a0"))
		"bag":
			c.rect(3, 6, 12, 10, Color("b86a2a"))
			c.rect(3, 6, 12, 4, Color("8a4a1c"))
			c.rect(6, 2, 6, 2, Color("8a4a1c"))
			c.rect(6, 3, 1, 3, Color("8a4a1c"))
			c.rect(11, 3, 1, 3, Color("8a4a1c"))
			c.rect(8, 8, 2, 3, Color("ffd04a"))
			c.rect(4, 12, 10, 1, Color("d9934a"))
		"pet":
			c.circle(9, 12, 4, Color("f09a3a"))
			for p: Vector2 in [Vector2(4, 7), Vector2(7, 4.5), Vector2(11, 4.5), Vector2(14, 7)]:
				c.circle(p.x, p.y, 1.8, Color("f09a3a"))
			c.circle(8, 11, 1.2, Color("ffc27a"))
		"mail":
			c.rect(2, 5, 14, 9, Color("fff0c8"))
			c.line(2, 5, 9, 10, Color("b88a5a"))
			c.line(15, 5, 9, 10, Color("b88a5a"))
			c.circle(9, 10, 1.8, Color("e0402f"))
		"mission":
			c.rect(4, 3, 10, 12, Color("fbe3ae"))
			c.rect(3, 2, 12, 2, Color("b86a2a"))
			c.rect(3, 14, 12, 2, Color("b86a2a"))
			for i in range(4):
				c.rect(6, 6 + i * 2, 6 - (i % 2) * 2, 1, Color("c0402f"))
		"help":
			c.rect(3, 3, 12, 12, Color("3a78d8"))
			c.rect(4, 4, 10, 10, Color("5a9cf0"))
			for p: Vector2i in [Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 6), Vector2i(10, 7), Vector2i(9, 8), Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 12)]:
				c.px(p.x, p.y, Color("fff4d6"))
		"exit":
			c.rect(4, 4, 10, 12, Color("8a4a1c"))
			c.circle(9, 5, 5, Color("8a4a1c"))
			c.rect(6, 5, 6, 11, Color("c47a33"))
			c.circle(9, 5.5, 3, Color("c47a33"))
			c.circle(11, 11, 0.9, Color("ffd04a"))
		"speaker":
			c.poly(PackedVector2Array([Vector2(3, 7), Vector2(7, 7), Vector2(14, 2), Vector2(14, 16), Vector2(7, 11), Vector2(3, 11)]), Color("c8d4e6"))
			c.rect(3, 7, 4, 4, Color("8a98b0"))
			c.line(16, 6, 16, 12, Color("ffd04a"))
		"gear":
			for i in range(8):
				var p: Vector2 = Vector2(9, 9) + Vector2.from_angle(i * TAU / 8) * 6.2
				c.circle(p.x, p.y, 1.6, Color("c8d4e6"))
			c.circle(9, 9, 5.5, Color("c8d4e6"))
			c.circle(9, 9, 2.2, Color("4a5870"))
		"power":
			c.ring(9, 9.5, 6.5, 2, Color("ff5a4a"))
			c.rect(7, 2, 4, 3, Color(0, 0, 0, 0))
			c.rect(8, 2, 2, 7, Color("ff5a4a"))
		"chat":
			c.circle(9, 8, 6, Color("fff4d6"))
			c.poly(PackedVector2Array([Vector2(5, 12), Vector2(9, 13), Vector2(3, 17)]), Color("fff4d6"))
			for x: int in [6, 9, 12]:
				c.px(x, 8, Color("7a5a3a"))
		"smile":
			c.circle(9, 9, 7, Color("ffd04a"))
			c.rect(6, 6, 2, 3, OUTLINE)
			c.rect(11, 6, 2, 3, OUTLINE)
			c.line(5, 11, 7, 13, OUTLINE)
			c.line(8, 13, 10, 13, OUTLINE)
			c.line(11, 13, 13, 11, OUTLINE)
		"male", "female":
			var tone: Color = Color("4aa8ff") if name == "male" else Color("ff5a8a")
			c.circle(9, 5, 3.4, tone)
			c.poly(PackedVector2Array([Vector2(5, 16), Vector2(6, 10), Vector2(12, 10), Vector2(13, 16)]), tone)
			c.px(8, 4, tone.lightened(0.5))
		"plane":
			c.poly(PackedVector2Array([Vector2(1, 9), Vector2(17, 2), Vector2(10, 16), Vector2(8, 11)]), Color("fff8e8"))
			c.line(8, 11, 17, 2, Color("b8c4d8"))
		"lock":
			c.ring(9, 7, 4.5, 1.6, Color("c8d4e6"))
			c.rect(3, 8, 12, 8, Color("ffc94f"))
			c.rect(8, 10, 2, 3, Color("6e3510"))
		"up", "down":
			var tip: float = 4.0 if name == "up" else 14.0
			var base: float = 13.0 if name == "up" else 5.0
			c.poly(PackedVector2Array([Vector2(9, tip), Vector2(15, base), Vector2(3, base)]), Color("ffc94f"))
		"vip":
			c.poly(PackedVector2Array([Vector2(2, 4), Vector2(16, 4), Vector2(9, 16)]), Color("ffc94f"))
			c.poly(PackedVector2Array([Vector2(6, 6), Vector2(12, 6), Vector2(9, 11)]), Color("e0701a"))
		"crown":
			c.poly(PackedVector2Array([Vector2(2, 14), Vector2(3, 5), Vector2(6, 9), Vector2(9, 3), Vector2(12, 9), Vector2(15, 5), Vector2(16, 14)]), Color("ffc94f"))
			c.circle(9, 11, 1.4, Color("e0402f"))
		"pow":
			c.poly(PackedVector2Array([Vector2(10, 1), Vector2(4, 10), Vector2(9, 10), Vector2(7, 17), Vector2(14, 7), Vector2(9, 7)]), Color("ffd04a"))
		"star":
			var points: PackedVector2Array = PackedVector2Array()
			for i in range(10):
				points.append(Vector2(9, 9.5) + Vector2.from_angle(-PI / 2 + i * PI / 5) * (7.5 if i % 2 == 0 else 3.2))
			c.poly(points, Color("ffd04a"))
		"trophy":
			c.rect(5, 3, 8, 6, Color("ffc94f"))
			c.circle(9, 8, 4, Color("ffc94f"))
			c.rect(8, 11, 2, 3, Color("d98a1a"))
			c.rect(5, 14, 8, 2, Color("d98a1a"))
			c.ring(4, 6, 2.5, 1, Color("ffc94f"))
			c.ring(14, 6, 2.5, 1, Color("ffc94f"))
		"team":
			c.circle(6, 6, 3, Color("ffd9a8"))
			c.poly(PackedVector2Array([Vector2(1, 16), Vector2(2, 10), Vector2(10, 10), Vector2(11, 16)]), Color("4aa8ff"))
			c.circle(12, 5, 3, Color("ffd9a8"))
			c.poly(PackedVector2Array([Vector2(7, 16), Vector2(8, 9), Vector2(16, 9), Vector2(17, 16)]), Color("ff7a4a"))
			c.rect(4, 3, 5, 2, Color("6a3a1a"))
			c.rect(10, 2, 5, 2, Color("3a2a1a"))
		"search":
			c.ring(7, 7, 5.5, 2, Color("c8d4e6"))
			c.circle(7, 7, 3.6, Color("8fd8ff"))
			c.px(5, 5, Color.WHITE)
			for i in range(5):
				c.rect(10 + i, 10 + i, 2, 2, Color("a8642a"))
		"play":
			c.poly(PackedVector2Array([Vector2(3, 14), Vector2(11, 3), Vector2(15, 7), Vector2(6, 16)]), Color("ffc94f"))
			c.poly(PackedVector2Array([Vector2(11, 3), Vector2(16, 1), Vector2(15, 7)]), Color("ff7a4a"))
			c.circle(5, 14, 2.5, Color("8a4a1c"))
			c.px(12, 5, Color("fff4a0"))
		_:
			c.circle(9, 9, 6, Color("ff00ff"))
	c.outline(OUTLINE)
	var texture: ImageTexture = ImageTexture.create_from_image(c.image)
	cache[name] = texture
	return texture
