class_name TouchAssist
extends Node

# Touch in every screen (touch mode, docs/MOBILE.md). Godot would turn the FIRST finger into
# the mouse and nothing else; this node does it instead, so that:
#  - a second finger stays free (the left thumb holds a battle arrow while the right one taps
#    a skill: the battle pads, TouchControls, claim their own touches and are skipped here);
#  - a press that lands in the gap beside a button goes to the nearest button (a fingertip is
#    ~7 mm and many buttons are 3–4 mm), as long as nothing covers that button;
#  - holding still for a moment shows the tooltip (there is no hover on a phone) and the
#    release then does not click;
#  - a press that slid (scrolling a list, a swipe) does not click what it started on, unless
#    it carries a drag (the Mochila's drag and drop);
#  - lists (ScrollContainer, RichTextLabel) follow the finger and coast after a flick. Godot's
#    own touch scrolling only wakes on a real touch screen (and cannot be tested), so it is
#    switched off here (a huge scroll_deadzone) and this does it the same on every device.

const SNAP_RADIUS: float = 22.0
const LONG_PRESS: float = 0.45
const AWAY: Vector2 = Vector2(-10000, -10000)
const TIP_WIDTH: float = 380.0

var pointer: int = -1
var press_point: Vector2 = Vector2.ZERO
var last_point: Vector2 = Vector2.ZERO
# Where the press really went, minus where the finger was (the snap).
var offset: Vector2 = Vector2.ZERO
var held: float = 0.0
var moved: bool = false
var long_checked: bool = false
var long_fired: bool = false
var tip_layer: CanvasLayer
var tip_box: Control
var tip_left: float = -1.0
# The list under the finger, the fraction of a pixel not yet scrolled, how fast the finger
# was going (px/s) and the list that is still coasting after a flick.
var scroller: Control
var remainder: Vector2 = Vector2.ZERO
var flick: Vector2 = Vector2.ZERO
var last_move_ms: int = 0
var coasting: Control
var coast: Vector2 = Vector2.ZERO
# Three fingers down together show the FPS counter (F3 on a computer).
var fingers_down: Dictionary = {}
var counter_toggled: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_emulate_mouse_from_touch(false)
	get_tree().node_added.connect(on_node_added)
	for list: Node in get_tree().root.find_children("*", "ScrollContainer", true, false):
		on_node_added(list)

func on_node_added(node: Node) -> void:
	if node is ScrollContainer:
		node.scroll_deadzone = 1000000

func _exit_tree() -> void:
	Input.set_emulate_mouse_from_touch(true)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		track_fingers(event.index, event.pressed)
		if event.pressed:
			touch_down(event.index, event.position)
		elif event.index == pointer:
			touch_up(event.position)
	elif event is InputEventScreenDrag and event.index == pointer:
		touch_move(event.position, event.relative)

func _process(delta: float) -> void:
	if pointer != -1 and not moved and not long_checked:
		held += delta
		if held >= LONG_PRESS:
			long_checked = true
			var text: String = tip_text(control_at(last_point + offset))
			if text != "":
				long_fired = true
				show_tip(text, last_point)
	if tip_left >= 0.0:
		tip_left -= delta
		if tip_left < 0.0:
			hide_tip()
	if coast.length() > 30.0 and is_instance_valid(coasting) and coasting.is_visible_in_tree():
		scroll_by(coasting, coast * delta)
		coast *= pow(0.05, delta)
	else:
		coast = Vector2.ZERO

func track_fingers(index: int, pressed: bool) -> void:
	if pressed:
		fingers_down[index] = true
		if fingers_down.size() == 3 and not counter_toggled:
			counter_toggled = true
			var game: Node = get_parent()
			if game.get("perf") != null:
				game.perf.toggle()
	else:
		fingers_down.erase(index)
		if fingers_down.is_empty():
			counter_toggled = false

# ---------- finger -> mouse ----------

func touch_down(index: int, point: Vector2) -> void:
	if pointer != -1 or claimed_by_pad(point):
		return
	pointer = index
	press_point = point
	last_point = point
	held = 0.0
	moved = false
	long_checked = false
	long_fired = false
	coast = Vector2.ZERO
	remainder = Vector2.ZERO
	flick = Vector2.ZERO
	last_move_ms = Time.get_ticks_msec()
	scroller = scrolling_parent(control_at(point))
	hide_tip()
	offset = landing(point) - point
	var at: Vector2 = point + offset
	send_motion(at, Vector2.ZERO, 0)
	send_button(at, true)

func touch_move(point: Vector2, relative: Vector2) -> void:
	last_point = point
	var now: int = Time.get_ticks_msec()
	if not moved and point.distance_to(press_point) > TouchMode.TAP_SLOP:
		moved = true
		long_checked = true
		hide_tip()
		# The list catches up with the finger from where it first touched.
		if scroller != null:
			scroll_by(scroller, press_point - point)
	elif moved and scroller != null:
		scroll_by(scroller, -relative)
		var seconds: float = maxf(0.001, (now - last_move_ms) / 1000.0)
		flick = flick.lerp(-relative / seconds, 0.4)
	last_move_ms = now
	send_motion(point + offset, relative, MOUSE_BUTTON_MASK_LEFT)

func touch_up(point: Vector2) -> void:
	var at: Vector2 = point + offset
	if (long_fired and not moved) or (moved and not get_viewport().gui_is_dragging()):
		# The tooltip was the answer, or it was a scroll or a swipe: the release is not a
		# click. A button only learns the finger left it from a motion, so one goes first.
		at = AWAY
		send_motion(AWAY, Vector2.ZERO, MOUSE_BUTTON_MASK_LEFT)
	send_button(at, false)
	# No hover is left behind (a phone has no pointer to rest on a button).
	send_motion(AWAY, Vector2.ZERO, 0)
	# A flick that lets go while still moving keeps the list coasting.
	if moved and scroller != null and Time.get_ticks_msec() - last_move_ms < 90 and flick.length() > 120.0:
		coasting = scroller
		coast = flick
	scroller = null
	pointer = -1
	if tip_box != null:
		tip_left = 1.6

func send_button(at: Vector2, pressed: bool) -> void:
	if at != AWAY:
		TouchMode.finger_at = at
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(event, true)

func send_motion(at: Vector2, relative: Vector2, mask: int) -> void:
	if at != AWAY:
		TouchMode.finger_at = at
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = mask
	event.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(event, true)

# The list a finger on `control` would scroll: the first ScrollContainer or scrolling text above.
static func scrolling_parent(control: Node) -> Control:
	var node: Node = control
	while node is Control:
		if node is ScrollContainer or (node is RichTextLabel and node.scroll_active):
			return node
		node = node.get_parent()
	return null

# Scrolls a list by `amount` px of its content (positive: further down or right).
func scroll_by(list: Control, amount: Vector2) -> void:
	remainder += amount
	var step: Vector2 = Vector2(int(remainder.x), int(remainder.y))
	remainder -= step
	if list is ScrollContainer:
		list.scroll_horizontal += int(step.x)
		list.scroll_vertical += int(step.y)
	elif list is RichTextLabel:
		var bar: VScrollBar = list.get_v_scroll_bar()
		bar.value += step.y

func claimed_by_pad(point: Vector2) -> bool:
	for pad: Node in get_tree().get_nodes_in_group("touch_pad"):
		if pad.claims(point):
			return true
	return false

# ---------- hit testing (what Godot's GUI would find under a point) ----------

# The topmost Control that takes a mouse event at `point`. Later siblings draw above earlier
# ones and children above parents; a clipping container hides what lies outside it.
func control_at(point: Vector2, node: Node = null) -> Control:
	if node == null:
		node = get_tree().root
	if node is SubViewport or (node is CanvasItem and not node.visible):
		return null
	var control: Control = node as Control
	if control != null and control.clip_contents and not control.get_global_rect().has_point(point):
		return null
	var children: Array[Node] = in_draw_order(node)
	for i in range(children.size() - 1, -1, -1):
		var found: Control = control_at(point, children[i])
		if found != null:
			return found
	if control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(point):
		return control
	return null

# Children bottom to top. A CanvasLayer draws by its own `layer`, the rest on layer 0; within
# a layer the tree order stands.
static func in_draw_order(node: Node) -> Array[Node]:
	var children: Array[Node] = node.get_children()
	var layered: bool = false
	for child: Node in children:
		if child is CanvasLayer:
			layered = true
			break
	if not layered:
		return children
	var keyed: Array = []
	for i in range(children.size()):
		keyed.append([(children[i] as CanvasLayer).layer if children[i] is CanvasLayer else 0, i, children[i]])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var ordered: Array[Node] = []
	for entry: Array in keyed:
		ordered.append(entry[2])
	return ordered

# A Control that only sits there: a press on it may be moved to a button nearby.
static func is_backdrop(control: Control) -> bool:
	if control is BaseButton or control is LineEdit or control is TextEdit or control is Range or control is ScrollContainer or control is ItemList or control is Tree or control is TabBar:
		return false
	if control.has_method("_gui_input") or control.has_method("_get_drag_data") or control.gui_input.get_connections().size() > 0:
		return false
	return true

# Where a press at `point` should land: itself, or the nearest uncovered button within reach.
func landing(point: Vector2) -> Vector2:
	var hit: Control = control_at(point)
	if hit != null and not is_backdrop(hit):
		return point
	var buttons: Array[BaseButton] = []
	collect_buttons(get_tree().root, point, buttons)
	var best: Vector2 = point
	var best_distance: float = SNAP_RADIUS + 0.001
	for button: BaseButton in buttons:
		var rect: Rect2 = button.get_global_rect()
		var nearest: Vector2 = Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
		var distance: float = point.distance_to(nearest)
		if distance >= best_distance:
			continue
		# A hair inside the button, and nothing on top of it there (a dialog over the screen).
		var inside: Vector2 = nearest + (rect.get_center() - nearest).limit_length(2.0)
		var top: Control = control_at(inside)
		if top == button or (top != null and button.is_ancestor_of(top)):
			best_distance = distance
			best = inside
	return best

func collect_buttons(node: Node, point: Vector2, found: Array[BaseButton]) -> void:
	if node is SubViewport or (node is CanvasItem and not node.visible):
		return
	var control: Control = node as Control
	if control != null and control.clip_contents and not control.get_global_rect().grow(SNAP_RADIUS).has_point(point):
		return
	if node is BaseButton and not node.disabled and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		found.append(node)
	for child: Node in node.get_children():
		collect_buttons(child, point, found)

# ---------- tooltips ----------

static func tip_text(control: Control) -> String:
	var node: Node = control
	while node is Control:
		if str(node.tooltip_text) != "":
			return str(node.tooltip_text)
		node = node.get_parent()
	return ""

func show_tip(text: String, at: Vector2) -> void:
	hide_tip()
	if tip_layer == null:
		tip_layer = CanvasLayer.new()
		tip_layer.layer = 110
		add_child(tip_layer)
	# Measured as a paragraph: a wrapping Label only knows its height after a layout pass.
	var paragraph: TextParagraph = TextParagraph.new()
	paragraph.add_string(text, UiKit.reading_font(), UiKit.fs(16))
	paragraph.width = TIP_WIDTH
	var text_size: Vector2 = paragraph.get_size().ceil()
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UiKit.reading_font())
	label.add_theme_font_size_override("font_size", UiKit.fs(16))
	label.add_theme_color_override("font_color", UiKit.CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(12, 8)
	label.size = Vector2(text_size.x + 2.0, text_size.y)
	var box: Panel = Panel.new()
	box.add_theme_stylebox_override("panel", UiKit.frame("tooltip"))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	tip_layer.add_child(box)
	box.size = text_size + Vector2(26, 16)
	# Above the finger, or below it at the top of the screen; always inside the screen.
	var place: Vector2 = Vector2(at.x - box.size.x / 2.0, at.y - box.size.y - 56.0)
	if place.y < 8.0:
		place.y = at.y + 56.0
	place.x = clampf(place.x, 8.0, 1272.0 - box.size.x)
	place.y = clampf(place.y, 8.0, 712.0 - box.size.y)
	box.position = place
	tip_box = box
	tip_left = -1.0

func hide_tip() -> void:
	if is_instance_valid(tip_box):
		tip_box.queue_free()
	tip_box = null
	tip_left = -1.0
