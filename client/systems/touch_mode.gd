class_name TouchMode
extends RefCounted

# Phones and tablets (docs/MOBILE.md). The game is built for a mouse and a keyboard; in touch
# mode the battle gets its own controls (TouchControls), every screen gets bigger hit areas
# and long-press replaces hover (TouchAssist).
#
# Touch mode is on in a native Android/iOS build and in a browser whose main pointer is
# coarse (a phone or a tablet; a laptop with a touch screen keeps the mouse interface).
# `--touch=1` / `?touch=1` force it on in a computer (captures, tests), `touch=0` off.

# A finger covers about 7 mm: on a phone the 1280x720 screen is ~11 cm wide, so 72
# logical px are ~6.5 mm. Buttons below this grow in touch mode.
const MIN_TARGET: float = 56.0
# Text buttons keep their look and only gain a little height (a row of them is spaced for 42).
const MIN_BUTTON: float = 48.0
# The most a press may slide before it counts as a drag, in logical px.
const TAP_SLOP: float = 20.0

static var forced: int = -1
static var cached: int = -1
# Where the finger last was (TouchAssist keeps it): the "mouse" of a phone is made by
# TouchAssist, and the window's own mouse position does not follow it.
static var finger_at: Vector2 = Vector2.ZERO

# The pointer of `node`'s screen: the finger in touch mode, the mouse otherwise. Cards that
# follow the pointer and menus that open where it was ask this, not get_global_mouse_position.
static func pointer(node: CanvasItem) -> Vector2:
	return finger_at if active() else node.get_global_mouse_position()

# Without the option the detection (or what a test set in `forced`) stays as it was.
static func setup(args: Dictionary) -> void:
	cached = -1
	if args.has("touch"):
		forced = 0 if str(args.touch) in ["0", "false", "off"] else 1

static func active() -> bool:
	if forced >= 0:
		return forced == 1
	if cached < 0:
		cached = 1 if detect() else 0
	return cached == 1

static func detect() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web"):
		# tools/web/shell_head.html: matchMedia('(pointer: coarse)').
		return bool(JavaScriptBridge.eval("window.gfTouch === true", true))
	return false

# A rect at least MIN_TARGET on each side, grown around its centre (the buttons keep their
# place; neighbours are laid out with room for it).
static func grown(rect: Rect2, minimum: float = MIN_TARGET) -> Rect2:
	if not active():
		return rect
	var extra: Vector2 = Vector2(maxf(0.0, minimum - rect.size.x), maxf(0.0, minimum - rect.size.y))
	return Rect2(rect.position - extra / 2.0, rect.size + extra)
