class_name TouchControls
extends Control

# The battle's on-screen controls for phones and tablets (touch mode, docs/MOBILE.md).
#
# Walking, aiming and the shot are held buttons, and two thumbs press at once (walk with
# one, hold FIRE with the other), so they read the raw touches and not the mouse that
# Godot would emulate from the first finger. They press and release the SAME KEYS the
# keyboard does (A/D, W/S, SPACE): the offline match, the online intents and the lockstep
# driver cannot tell a thumb from a keyboard, and the rules stay untouched.
#
# Everything else (skills 1–9, tools, plane, auxiliary item, pet, POW, PASS) stays the
# HUD's own buttons, moved and enlarged here; the nine skills fold into a drawer.

const MOUSE_FINGER: int = -2
const PAD_REACH: float = 8.0

# Logical px of the 1280x720 screen (one finger is ~6.5 mm per 72 px on a 6" phone).
const WALK_LEFT: Rect2 = Rect2(150, 618, 92, 94)
const WALK_RIGHT: Rect2 = Rect2(250, 618, 92, 94)
const AIM_UP: Rect2 = Rect2(892, 538, 92, 84)
const AIM_DOWN: Rect2 = Rect2(892, 628, 92, 84)
const FIRE: Rect2 = Rect2(992, 536, 176, 176)
const FORCE_BAR: Rect2 = Rect2(352, 640, 430, 78)
const ROW_ORIGIN: Vector2 = Vector2(352, 556)
const ROW_SLOT: Vector2 = Vector2(72, 72)
const ROW_STEP: float = 76.0
const DRAWER_SLOT: Vector2 = Vector2(76, 76)
const DRAWER_GAP: float = 6.0
const DRAWER_PAD: float = 12.0

var hud: BattleHUD
var game: LocalMatch
var pads: Array[Pad] = []
var fingers: Dictionary = {}
var walk_left: Pad
var walk_right: Pad
var aim_up: Pad
var aim_down: Pad
var fire: Pad
var drawer_toggle: Pad
var drawer: Control
var drawer_open: bool = false
var time: float = 0.0

# One held button. `key` is the keyboard key it presses (KEY_NONE: a plain tap button).
class Pad extends Control:
	var key: Key = KEY_NONE
	var kind: String = "dir"
	var glyph: String = ""
	var caption: String = ""
	var slides: bool = false
	var down: bool = false
	var enabled: bool = true
	var owner_controls: TouchControls

	func _ready() -> void:
		add_to_group("touch_pad")
		mouse_filter = Control.MOUSE_FILTER_STOP

	# Does a touch here belong to this button? (TouchAssist skips those touches.)
	func claims(point: Vector2) -> bool:
		return is_visible_in_tree() and enabled and get_global_rect().grow(PAD_REACH).has_point(point)

	func press() -> void:
		if down:
			return
		down = true
		if key != KEY_NONE:
			TouchControls.send_key(key, true)
		owner_controls.pad_pressed(self)
		queue_redraw()

	func release() -> void:
		if not down:
			return
		down = false
		if key != KEY_NONE:
			TouchControls.send_key(key, false)
		queue_redraw()

	func _draw() -> void:
		var rect: Rect2 = Rect2(Vector2.ZERO, size)
		var dim: float = 0.0 if enabled else 0.65
		if kind == "fire":
			draw_fire(dim)
			return
		var lit: float = 0.9 if down else (0.35 if kind == "toggle" and owner_controls.drawer_open else 0.0)
		var inner: Rect2 = HudPaint.frame(self, rect, lit, dim)
		HudPaint.well(self, inner, Color("1c130a") if down else HudPaint.WELL_TOP, Color("3a2412") if down else HudPaint.WELL_BOTTOM)
		var centre: Vector2 = rect.get_center() + (Vector2(0, 2) if down else Vector2.ZERO)
		var color: Color = HudPaint.GOLD_HOT if down else (HudPaint.GOLD if kind == "aim" else HudPaint.CREAM)
		color = color.lerp(Color("6a5a4a"), dim)
		if kind == "toggle":
			draw_grid(centre, color)
			HudPaint.outlined(self, Vector2(rect.position.x, rect.end.y - 8), caption, 16, color, HudPaint.INK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, 3)
			return
		draw_arrow(centre, color)

	func draw_arrow(centre: Vector2, color: Color) -> void:
		var reach: float = 22.0
		var back: float = 16.0
		var points: PackedVector2Array
		match glyph:
			"left":
				points = PackedVector2Array([centre + Vector2(-reach, 0), centre + Vector2(back, -reach), centre + Vector2(back, reach)])
			"right":
				points = PackedVector2Array([centre + Vector2(reach, 0), centre + Vector2(-back, -reach), centre + Vector2(-back, reach)])
			"up":
				points = PackedVector2Array([centre + Vector2(0, -reach), centre + Vector2(-reach, back), centre + Vector2(reach, back)])
			_:
				points = PackedVector2Array([centre + Vector2(0, reach), centre + Vector2(-reach, -back), centre + Vector2(reach, -back)])
		var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(points, 4.0)
		draw_colored_polygon(grown[0] if not grown.is_empty() else points, HudPaint.INK)
		draw_colored_polygon(points, color)

	# Nine small squares: the skills drawer.
	func draw_grid(centre: Vector2, color: Color) -> void:
		for row in range(3):
			for column in range(3):
				var at: Vector2 = centre + Vector2((column - 1) * 15 - 5, (row - 1) * 15 - 12)
				draw_rect(Rect2(at - Vector2(1, 1), Vector2(12, 12)), HudPaint.INK)
				draw_rect(Rect2(at, Vector2(10, 10)), color)

	func draw_fire(dim: float) -> void:
		var c: Vector2 = size / 2.0
		var r: float = size.x / 2.0
		var hud: BattleHUD = owner_controls.hud
		var force: float = clampf(hud.visible_force() / 100.0, 0.0, 1.0)
		var charging: bool = owner_controls.game.state == LocalMatch.State.PLAYER_CHARGING and hud.visible_force() > 0.0
		var top: Color = Color("ffb04a") if not down else Color("e0701a")
		var bottom: Color = Color("c8281c") if not down else Color("8a140c")
		top = top.lerp(Color("6a5a4a"), dim)
		bottom = bottom.lerp(Color("3a302a"), dim)
		if charging:
			HudPaint.glow(self, c, r + 14.0, Color(BattleHUD.force_color(force), 0.55), 3)
		draw_circle(c, r, HudPaint.INK)
		draw_circle(c, r - 3.0, HudPaint.BRONZE_DARK)
		draw_arc(c, r - 7.0, 0.0, TAU, 64, HudPaint.BRONZE.lerp(Color("6a5a4a"), dim), 8.0)
		draw_arc(c, r - 7.0, PI * 1.1, PI * 1.9, 32, HudPaint.BRONZE_LIGHT.lerp(Color("6a5a4a"), dim), 3.0)
		draw_circle(c, r - 14.0, HudPaint.INK)
		for k in range(8):
			draw_circle(c + Vector2(0, -k * 1.2 + (3.0 if down else 0.0)), r - 16.0 - k * 4.0, bottom.lerp(top, k / 7.0))
		if force > 0.0:
			draw_arc(c, r - 7.0, -PI / 2.0, -PI / 2.0 + TAU * force, 64, BattleHUD.force_color(force), 8.0)
		var text: String = caption
		var offset: float = 12.0 + (3.0 if down else 0.0)
		HudPaint.fancy(self, c + Vector2(-r, offset - 10.0), text if not charging else tr("SOLTE"), 40, HudPaint.GOLD_HOT.lerp(Color("8a7a6a"), dim), Color("6a1208"), r * 2.0, HORIZONTAL_ALIGNMENT_CENTER, 3, 8)
		if charging:
			HudPaint.outlined(self, c + Vector2(-r, 40.0), "%d%%" % roundi(force * 100.0), 24, Color.WHITE, HudPaint.INK, r * 2.0, HORIZONTAL_ALIGNMENT_CENTER, 4)

# Presses a keyboard key as the keyboard would: the match reads it with
# Input.is_physical_key_pressed and the battle's shortcuts with _unhandled_key_input.
static func send_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

static func attach(battle_hud: BattleHUD) -> TouchControls:
	var controls: TouchControls = TouchControls.new()
	controls.name = "TouchControls"
	controls.hud = battle_hud
	controls.game = battle_hud.game
	controls.size = Vector2(1280, 720)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_hud.add_child(controls)
	controls.build()
	return controls

func build() -> void:
	walk_left = make_pad(WALK_LEFT, KEY_A, "left", "dir", true)
	walk_right = make_pad(WALK_RIGHT, KEY_D, "right", "dir", true)
	aim_up = make_pad(AIM_UP, KEY_W, "up", "aim", true)
	aim_down = make_pad(AIM_DOWN, KEY_S, "down", "aim", true)
	fire = make_pad(FIRE, KEY_SPACE, "", "fire", false)
	fire.caption = tr("FOGO")
	arrange_hud()

func make_pad(rect: Rect2, key: Key, glyph: String, kind: String, slides: bool) -> Pad:
	var pad: Pad = Pad.new()
	pad.position = rect.position
	pad.size = rect.size
	pad.key = key
	pad.glyph = glyph
	pad.kind = kind
	pad.slides = slides
	pad.owner_controls = self
	add_child(pad)
	pads.append(pad)
	return pad

# The HUD of the computer, rearranged for thumbs: gauges up by the portrait, the buttons
# of the turn in one row above the force bar, the nine skills in a drawer.
func arrange_hud() -> void:
	hud.force.position = FORCE_BAR.position
	hud.force.size = FORCE_BAR.size
	hud.gauges.position = Vector2(132, 66)
	hud.used_row.position = Vector2(560, 232)
	hud.pass_button.position = Vector2(578, 178)
	hud.pass_button.size = Vector2(124, 50)
	hud.trust_button.position = Vector2(4, 284)
	hud.trust_button.size = Vector2(132, 50)
	hud.gear_button.position = Vector2(1156, 166)
	hud.gear_button.size = Vector2(56, 56)
	hud.exit_button.position = Vector2(1220, 166)
	hud.exit_button.size = Vector2(56, 56)
	for button: Button in [hud.gear_button, hud.exit_button]:
		var icon: Control = button.get_node("Icon")
		icon.position = Vector2(10, 10)
		icon.size = Vector2(36, 36)
		# They sat on the minimap with no frame of their own: over the map art they vanish.
		for state: String in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, UiKit.frame("dark" if state != "hover" else "slot_hover"))
		button.flat = false
	# The row, left to right: tools Z X C, then pet G, auxiliary V, plane F, then the drawer.
	var row: Array[SkillSlot] = []
	row.append_array(hud.tool_buttons)
	if is_instance_valid(hud.pet_button):
		row.append(hud.pet_button)
	row.append(hud.aux_button)
	row.append(hud.fly_button)
	var count: int = row.size()
	for i in range(count):
		row[i].position = ROW_ORIGIN + Vector2(i * ROW_STEP, 0)
		row[i].size = ROW_SLOT
	# Where the drawer opens from: the end of the row.
	drawer_toggle = make_pad(Rect2(ROW_ORIGIN + Vector2(count * ROW_STEP, 0), ROW_SLOT), KEY_NONE, "", "toggle", false)
	drawer_toggle.caption = tr("HAB.")
	var grid: Vector2 = Vector2(3 * DRAWER_SLOT.x + 2 * DRAWER_GAP, 3 * DRAWER_SLOT.y + 2 * DRAWER_GAP)
	var box: Rect2 = Rect2(drawer_toggle.position.x + ROW_SLOT.x - grid.x - 2 * DRAWER_PAD, ROW_ORIGIN.y - 8.0 - grid.y - 2 * DRAWER_PAD, grid.x + 2 * DRAWER_PAD, grid.y + 2 * DRAWER_PAD)
	drawer = Control.new()
	drawer.name = "SkillDrawer"
	drawer.position = box.position
	drawer.size = box.size
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.draw.connect(draw_drawer)
	drawer.visible = false
	add_child(drawer)
	for i in range(hud.item_buttons.size()):
		var slot: SkillSlot = hud.item_buttons[i]
		slot.reparent(drawer, false)
		slot.position = Vector2(DRAWER_PAD + (i % 3) * (DRAWER_SLOT.x + DRAWER_GAP), DRAWER_PAD + (i / 3) * (DRAWER_SLOT.y + DRAWER_GAP))
		slot.size = DRAWER_SLOT
	hud.rail.visible = false
	hud.seal_layer.visible = false

func draw_drawer() -> void:
	var inner: Rect2 = HudPaint.frame(drawer, Rect2(Vector2.ZERO, drawer.size))
	drawer.draw_rect(inner, Color(0.06, 0.04, 0.02, 0.9))

func set_drawer(open: bool) -> void:
	drawer_open = open
	drawer.visible = open
	drawer_toggle.queue_redraw()

# ---------- touches ----------

func pad_pressed(pad: Pad) -> void:
	if pad == drawer_toggle:
		set_drawer(not drawer_open)
		pad.down = false
	elif pad == fire:
		# The skills are chosen before the shot.
		set_drawer(false)

func blocked() -> bool:
	return hud.screen.menu_open or is_instance_valid(hud.pause_box) or is_instance_valid(hud.outcome) or game.paused or not game.running

func pad_at(point: Vector2, only_sliding: bool = false) -> Pad:
	var best: Pad = null
	var best_distance: float = INF
	for pad: Pad in pads:
		if not pad.claims(point) or (only_sliding and not pad.slides):
			continue
		var distance: float = point.distance_to(pad.get_global_rect().get_center())
		if distance < best_distance:
			best_distance = distance
			best = pad
	return best

func finger_down(index: int, point: Vector2) -> void:
	var pad: Pad = pad_at(point)
	if pad == null:
		return
	fingers[index] = pad
	pad.press()
	get_viewport().set_input_as_handled()

func finger_moved(index: int, point: Vector2) -> void:
	var pad: Pad = fingers.get(index)
	if pad == null:
		return
	# The thumb may slide from one arrow to the next without lifting.
	if pad.slides:
		var over: Pad = pad_at(point, true)
		if over != null and over != pad:
			pad.release()
			fingers[index] = over
			over.press()
	get_viewport().set_input_as_handled()

func finger_up(index: int) -> void:
	var pad: Pad = fingers.get(index)
	if pad == null:
		return
	pad.release()
	fingers.erase(index)
	get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			finger_down(event.index, event.position)
		else:
			finger_up(event.index)
	elif event is InputEventScreenDrag:
		finger_moved(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		# A computer with --touch=1: the mouse is one finger.
		if event.pressed:
			finger_down(MOUSE_FINGER, event.position)
		else:
			finger_up(MOUSE_FINGER)
	elif event is InputEventMouseMotion and fingers.has(MOUSE_FINGER):
		finger_moved(MOUSE_FINGER, event.position)

func release_all() -> void:
	for pad: Pad in pads:
		pad.release()
	fingers.clear()

func _process(delta: float) -> void:
	time += delta
	if game == null or game.fighters.is_empty():
		return
	var blocking: bool = blocked()
	var acting: bool = game.can_act()
	for pad: Pad in pads:
		pad.visible = not blocking
		if pad.enabled != acting and pad != drawer_toggle:
			pad.enabled = acting
			pad.queue_redraw()
		if pad == fire:
			pad.queue_redraw()
	drawer_toggle.enabled = acting
	if blocking or not acting:
		if not fingers.is_empty() and blocking:
			release_all()
		if drawer_open:
			set_drawer(false)
		drawer_toggle.queue_redraw()

func _notification(what: int) -> void:
	# A key left pressed (the app went to the background, the screen closed) would walk on.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		release_all()
