extends SceneTree

# Touch mode (docs/MOBILE.md): the battle pads press the keyboard's keys, two thumbs work at
# once, a press beside a button lands on it, a long press shows the tooltip and a slide does
# not click. Fingers are ScreenTouch/ScreenDrag events pushed into the window.

var errors: int = 0
var checks: int = 0
var presses: int = 0
var small_presses: int = 0
var other_presses: int = 0
var toggles: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		errors += 1
		push_error(message)

func finger(index: int, point: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)

func slide(index: int, point: Vector2, relative: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = relative
	root.push_input(event, true)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://test_touch_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	# Detection: a computer is not a touch device unless asked; --touch=1 asks.
	TouchMode.forced = -1
	TouchMode.cached = -1
	check(not TouchMode.active(), "a computer with a mouse is not touch mode")
	TouchMode.setup({"touch": "1"})
	check(TouchMode.active(), "--touch=1 turns touch mode on")
	TouchMode.setup({"touch": "0"})
	check(not TouchMode.active(), "--touch=0 turns it off")
	TouchMode.setup({"touch": "1"})
	check(TouchMode.grown(Rect2(100, 100, 30, 20)).size.x >= TouchMode.MIN_TARGET and TouchMode.grown(Rect2(100, 100, 30, 20)).get_center().is_equal_approx(Rect2(100, 100, 30, 20).get_center()), "a small rect grows to a fingertip around its centre")
	var scene: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var app: Node = scene
	check(is_instance_valid(app.touch_assist) and not Input.is_emulating_mouse_from_touch(), "touch mode replaces Godot's one-finger mouse emulation")
	await assist_tests(app)
	await platform_tests(app)
	await bag_finger_tests(app)
	await battle_tests(app)
	print("TOUCH RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors > 0 else 0)

# ---------- fingers on screens ----------

func counted(button: Button) -> void:
	button.pressed.connect(func() -> void: presses += 1)

func assist_tests(app: Node) -> void:
	var assist: TouchAssist = app.touch_assist
	# A test sheet over the game: a backdrop that takes the press, two buttons and a list.
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.size = Vector2(1280, 720)
	layer.add_child(backdrop)
	var small: Button = UiKit.button(layer, "OK", Rect2(300, 300, 60, 30))
	var other: Button = UiKit.button(layer, "NO", Rect2(420, 300, 60, 30))
	small.pressed.connect(func() -> void: small_presses += 1)
	other.pressed.connect(func() -> void: other_presses += 1)
	small.tooltip_text = "Confirma a ação"
	# A press right on the button.
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(330, 315), true)
	finger(0, Vector2(330, 315), false)
	check(small_presses == 1, "a press on the button clicks it")
	# A press in the gap beside it still reaches it (a fingertip is wider than the button).
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(300 - 14, 315), true)
	finger(0, Vector2(300 - 14, 315), false)
	check(small_presses == 1, "a press 14 px beside the button lands on it")
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(300 - 60, 315), true)
	finger(0, Vector2(300 - 60, 315), false)
	check(small_presses == 0, "a press far from every button clicks nothing")
	# Between two buttons it goes to the nearer one.
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(374, 315), true)
	finger(0, Vector2(374, 315), false)
	check(small_presses == 1 and other_presses == 0, "a press between two buttons goes to the nearer")
	# A covered button is not reachable through a dialog.
	var dialog_dim: ColorRect = ColorRect.new()
	dialog_dim.size = Vector2(1280, 720)
	dialog_dim.color = Color(0, 0, 0, 0.3)
	layer.add_child(dialog_dim)
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(300 - 10, 315), true)
	finger(0, Vector2(300 - 10, 315), false)
	check(small_presses == 0, "a button under a dialog does not take a press from beside it")
	dialog_dim.queue_free()
	await process_frame
	# A slide does not click the button it began on.
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(330, 315), true)
	slide(0, Vector2(330, 360), Vector2(0, 45))
	finger(0, Vector2(330, 360), false)
	check(small_presses == 0, "a press that slid does not click")
	# Holding still shows the tooltip and the release is not a click.
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(330, 315), true)
	await wait(0.7)
	check(assist.tip_box != null and is_instance_valid(assist.tip_box), "a long press shows the tooltip")
	finger(0, Vector2(330, 315), false)
	check(small_presses == 0, "the release after a tooltip does not click")
	await wait(2.0)
	check(assist.tip_box == null, "the tooltip goes away after the finger lifts")
	# A second finger does not take the mouse from the first.
	small_presses = 0
	other_presses = 0
	finger(0, Vector2(330, 315), true)
	finger(1, Vector2(450, 315), true)
	finger(1, Vector2(450, 315), false)
	finger(0, Vector2(330, 315), false)
	check(small_presses == 1 and other_presses == 1, "a second finger taps another button while the first is down (%d, %d)" % [small_presses, other_presses])
	check(assist.pointer == -1, "and the mouse is free again when both are up")
	# A toggle flips once per tap, not once for the touch and once for the mouse made from it.
	var box: CheckBox = CheckBox.new()
	box.text = "Sim"
	box.position = Vector2(300, 400)
	box.size = Vector2(120, 40)
	box.toggled.connect(func(_on: bool) -> void: toggles += 1)
	layer.add_child(box)
	await process_frame
	toggles = 0
	finger(0, Vector2(320, 420), true)
	finger(0, Vector2(320, 420), false)
	check(toggles == 1 and box.button_pressed, "a check box flips once for one tap (%d)" % toggles)
	finger(0, Vector2(320, 420), true)
	finger(0, Vector2(320, 420), false)
	check(toggles == 2 and not box.button_pressed, "and back with the next tap (%d)" % toggles)
	var list: ScrollContainer = ScrollContainer.new()
	list.position = Vector2(700, 100)
	list.size = Vector2(300, 200)
	layer.add_child(list)
	var tall: Control = Control.new()
	tall.custom_minimum_size = Vector2(280, 1200)
	tall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(tall)
	await process_frame
	await process_frame
	finger(0, Vector2(800, 250), true)
	for step in range(1, 7):
		slide(0, Vector2(800, 250 - step * 20), Vector2(0, -20))
		await process_frame
	slide(0, Vector2(800, 120), Vector2(0, -10))
	finger(0, Vector2(800, 120), false)
	await process_frame
	var scrolled: int = list.scroll_vertical
	check(scrolled > 80, "a finger dragging a list scrolls it (%d)" % scrolled)
	# Let go in motion: the list coasts a little further, then stops.
	await wait(0.3)
	check(list.scroll_vertical > scrolled, "a flick keeps the list coasting")
	var settled: int = list.scroll_vertical
	await wait(1.5)
	check(list.scroll_vertical - settled < 400 and list.scroll_vertical >= settled, "and it comes to rest")
	check(list.scroll_deadzone > 1000, "Godot's own touch scrolling is off, so a phone does not scroll twice")
	layer.queue_free()
	await process_frame

# ---------- the phone itself ----------

func platform_tests(app: Node) -> void:
	# Three fingers down together show the FPS counter (F3 on a computer), three more hide it.
	var before: bool = app.perf.shown
	for i in range(3):
		finger(i, Vector2(20 + i * 30, 20), true)
	check(app.perf.shown != before, "three fingers at once toggle the FPS counter")
	for i in range(3):
		finger(i, Vector2(20 + i * 30, 20), false)
	for i in range(3):
		finger(i, Vector2(20 + i * 30, 20), true)
	check(app.perf.shown == before, "and three again toggle it back")
	for i in range(3):
		finger(i, Vector2(20 + i * 30, 20), false)
	# Android's back button: the topmost thing closes, else the screen steps back.
	app.profile.created = true
	app.show_city()
	await process_frame
	check(app.topmost_overlay() == null, "nothing is on top of the city")
	app.go_back()
	await process_frame
	check(app.topmost_overlay() != null and app.topmost_overlay().name == "Modal", "back in the city asks whether to leave")
	app.go_back()
	await process_frame
	await process_frame
	check(app.topmost_overlay() == null and app.screen_name == "city", "back again closes the question and stays")
	app.shortcut("bag")
	await process_frame
	check(is_instance_valid(app.bag), "the bag opens")
	app.go_back()
	await process_frame
	check(app.bag == null, "back closes the bag")
	app.show_hall()
	await process_frame
	app.go_back()
	await process_frame
	await process_frame
	check(app.screen_name == "city", "back from the hall goes to the city")

# ---------- the Mochila by finger ----------

func bag_finger_tests(app: Node) -> void:
	app.profile.created = true
	app.profile.redeem("TESTARTUDO")
	app.profile.redeem("MOEDAS")
	app.profile.redeem("MAPAS")
	for number in range(1, PlayerProfile.BAG_EXTRA_PAGES + 1):
		app.profile.add_instance(PlayerProfile.bag_tab_id(number))
	app.show_city()
	app.open_bag()
	await process_frame
	await process_frame
	var bag: CharacterScreen = app.bag
	check(is_instance_valid(bag) and bag.cells_shown.size() == CharacterScreen.PER_PAGE, "the Mochila opens")
	# A tap selects an item.
	var slot: BagSlot = bag.cells_shown[3]
	var spot: Vector2 = slot.get_global_rect().get_center()
	finger(0, spot, true)
	finger(0, spot, false)
	await process_frame
	check(slot.key != "" and slot.selected, "a tap selects an item")
	# A finger drag moves it onto another cell, as the mouse does.
	bag.refresh_grid()
	await process_frame
	var from_slot: BagSlot = bag.cells_shown[9]
	var to_slot: BagSlot = bag.cells_shown[12]
	var dragged: String = from_slot.key
	var other: String = to_slot.key
	var a: Vector2 = from_slot.get_global_rect().get_center()
	var b: Vector2 = to_slot.get_global_rect().get_center()
	finger(0, a, true)
	await process_frame
	for i in range(1, 13):
		slide(0, a.lerp(b, i / 12.0), (b - a) / 12.0)
		await process_frame
	finger(0, b, false)
	await process_frame
	await process_frame
	var cells: Array[String] = bag.layout()
	check(dragged != "" and cells[12] == dragged and cells[9] == other, "a finger dragging an item onto another cell swaps them")
	# A long press on an item says what it is.
	var assist: TouchAssist = app.touch_assist
	var held_slot: BagSlot = bag.cells_shown[2]
	var at: Vector2 = held_slot.get_global_rect().get_center()
	finger(0, at, true)
	await wait(0.5)
	check(TouchMode.pointer(bag).distance_to(at) < 2.0, "the pointer cards follow is the finger (%s vs %s)" % [TouchMode.pointer(bag), at])
	check(held_slot.key == "" or bag.tooltip.visible, "holding a finger on an item shows its card")
	finger(0, at, false)
	await process_frame
	await process_frame
	check(not bag.tooltip.visible and not is_instance_valid(bag.hover_slot), "the card goes away when the finger lifts")
	app.close_bag()
	await process_frame

# ---------- fingers in the battle ----------

func wait_for_turn(game: LocalMatch) -> void:
	var waited: int = Time.get_ticks_msec()
	while not game.can_act() and Time.get_ticks_msec() - waited < 60000:
		await process_frame

func pad_center(controls: TouchControls, pad: TouchControls.Pad) -> Vector2:
	return pad.get_global_rect().get_center()

func battle_tests(app: Node) -> void:
	app.open_named("battle")
	await process_frame
	await process_frame
	var battle: BattleScreen = app.screen as BattleScreen
	check(battle != null and battle.hud.touch is TouchControls, "the battle gets the on-screen controls")
	var game: LocalMatch = battle.game
	var controls: TouchControls = battle.hud.touch
	await wait_for_turn(game)
	check(game.can_act(), "it is the player's turn")
	# The old buttons moved into the thumbs' reach and grew.
	check(battle.hud.pass_button.size.y >= 48.0 and battle.hud.gear_button.size.x >= 48.0, "PASS and the menu buttons are fingertip sized")
	check(battle.hud.item_buttons[0].get_parent() == controls.drawer and not controls.drawer.visible, "the nine skills wait in a closed drawer")
	for pad: TouchControls.Pad in controls.pads:
		check(pad.size.x >= 72.0 and pad.size.y >= 72.0, "the %s pad is at least 72 px" % (pad.glyph if pad.glyph != "" else pad.kind))
	# Walking: the right arrow presses D, and the fighter goes right.
	var me: TankFighter = game.local()
	var x0: float = me.position.x
	var energy0: float = game.energy
	finger(0, pad_center(controls, controls.walk_right), true)
	await wait(0.4)
	check(Input.is_physical_key_pressed(KEY_D), "the right arrow holds the D key")
	check(me.position.x > x0 + 4.0 and game.energy < energy0, "holding it walks the fighter and spends energy (%.1f px)" % (me.position.x - x0))
	# Sliding the thumb onto the left arrow turns around without lifting.
	slide(0, pad_center(controls, controls.walk_left), Vector2(-100, 0))
	await process_frame
	check(Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_D), "sliding to the other arrow switches the key")
	finger(0, pad_center(controls, controls.walk_left), false)
	await process_frame
	check(not Input.is_physical_key_pressed(KEY_A), "lifting the thumb releases the key")
	# Aiming.
	var angle0: float = me.angle
	finger(0, pad_center(controls, controls.aim_up), true)
	await wait(0.4)
	finger(0, pad_center(controls, controls.aim_up), false)
	check(me.angle > angle0 + 3.0, "the up arrow raises the angle (%.1f)" % (me.angle - angle0))
	# Two thumbs: hold an arrow, open the drawer and use a skill with the other.
	finger(0, pad_center(controls, controls.walk_left), true)
	finger(1, pad_center(controls, controls.drawer_toggle), true)
	finger(1, pad_center(controls, controls.drawer_toggle), false)
	await process_frame
	check(controls.drawer.visible and Input.is_physical_key_pressed(KEY_A), "a second thumb opens the drawer while the first keeps walking")
	var slot: SkillSlot = battle.hud.item_buttons[0]
	await process_frame
	check(not slot.disabled, "the first skill can be used")
	var at: Vector2 = slot.get_global_rect().get_center()
	finger(1, at, true)
	finger(1, at, false)
	await process_frame
	check(game.turn_items.size() == 1 and Input.is_physical_key_pressed(KEY_A), "a tap on a skill uses it, the arrow still held")
	finger(0, pad_center(controls, controls.walk_left), false)
	# The shot: hold FIRE to charge, release to shoot.
	finger(0, pad_center(controls, controls.fire), true)
	await wait(0.4)
	check(game.state == LocalMatch.State.PLAYER_CHARGING and game.power > 0.0, "holding FIRE charges the force (%.0f)" % game.power)
	check(not controls.drawer.visible, "FIRE closes the drawer")
	finger(0, pad_center(controls, controls.fire), false)
	await wait(0.3)
	check(game.state != LocalMatch.State.PLAYER_CHARGING and (not game.projectiles.is_empty() or game.state != LocalMatch.State.PLAYER_AIMING), "letting go of FIRE shoots")
	check(not Input.is_physical_key_pressed(KEY_SPACE), "no key stays held after the shot")
	# A modal over the battle (pause): the pads stop answering.
	battle.toggle_pause()
	await process_frame
	await process_frame
	check(not controls.walk_right.visible, "the pads hide behind the pause menu")
	finger(0, Vector2(1000, 600), true)
	finger(0, Vector2(1000, 600), false)
	check(not Input.is_physical_key_pressed(KEY_SPACE), "a press under the pause menu fires nothing")
	battle.toggle_pause()
	# One finger on the empty field drags the camera.
	await process_frame
	var camera_before: Vector2 = battle.camera.position
	finger(0, Vector2(640, 300), true)
	for step in range(1, 6):
		slide(0, Vector2(640 - step * 30, 300), Vector2(-30, 0))
		await process_frame
	finger(0, Vector2(490, 300), false)
	check(battle.manual_time > 0.0 and battle.manual_focus.distance_to(camera_before) > 20.0, "a finger dragged over the field pans the camera")
