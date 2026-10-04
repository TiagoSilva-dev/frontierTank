extends SceneTree

# Trailer director: plays one scripted scene of the game so Godot's movie writer can record
# it (tools/make_trailer.py runs it with --write-movie and then composes the vertical video).
#
#   godot --path . --write-movie out.avi --fixed-fps 30 --script tools/trailer/director.gd \
#     -- --seg=duel --len=300 --frames=1000000 --lang=en --profile=user://trailer_profile.json
#
# Everything after "--" also goes to the game's own argument parser (main.gd), so the usual
# capture helpers (--screen, --demo, --map, --instance, --level, --phase, --zoom) work here.
# The scene lasts --len frames (30 per second); the profile is a scratch one, never the
# player's save.

var main: Node
var seg: String = ""
var frames: int = 300
var frame: int = 0
var args: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1]
	seg = str(args.get("seg", ""))
	frames = int(args.get("len", "300"))
	call_deferred("run")

func run() -> void:
	main = (load("res://client/scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# The main node starts the screen on _ready; a couple of frames let the layout settle.
	await process_frame
	await process_frame
	if args.has("weapon"):
		await equip_weapon(str(args.weapon), int(args.get("wlevel", "12")))
	mute_music()
	call(seg_setup())
	while frame < frames:
		await process_frame
		frame += 1
		beat()
	await process_frame
	if args.has("taplog"):
		var log_file: FileAccess = FileAccess.open(str(args.taplog), FileAccess.WRITE)
		log_file.store_string(JSON.stringify(finger_log))
		log_file = null
	main.queue_free()
	await create_timer(0.4).timeout
	quit()

# --weapon=<id> --target=<screen>: equips that weapon on the scratch profile, then opens the
# screen (the one from --screen is only a cheap placeholder).
func equip_weapon(id: String, level: int) -> void:
	var profile: PlayerProfile = main.profile
	var found: bool = false
	for inst: Dictionary in profile.inventory:
		if inst.id == id:
			found = true
	if not found:
		profile.add_instance(id, "normal", level)
	for inst: Dictionary in profile.inventory:
		if inst.id == id:
			inst.level = level
			profile.equip(int(inst.uid))
			break
	main.open_named(str(args.get("target", "battle")))
	await process_frame
	await process_frame
	if args.has("zoom") and main.screen is BattleScreen:
		battle().camera.zoom = Vector2.ONE * float(args.zoom)
	if main.screen is BattleScreen and seg != "pilot":
		main.screen.game.set_auto_play(true)

func seg_setup() -> String:
	return "setup_" + seg

func battle() -> BattleScreen:
	return main.screen as BattleScreen

func match_game() -> LocalMatch:
	return battle().game if main.screen is BattleScreen else null

# ---------- per-scene setup and the beat that runs every frame ----------

var hook: Callable = Callable()

# The game's own music is muted on the recording (the video gets one track of its own);
# the bus is muted directly so the player's audio settings file is never written.
func mute_music() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)

func beat() -> void:
	if frame % 15 == 0:
		mute_music()
	if hook.is_valid():
		hook.call()

func setup_none() -> void:
	pass

# Trailer pacing: bots think less and the force bar fills faster, so a turn takes ~4 s.
func hurry() -> void:
	var game: LocalMatch = match_game()
	game.balance.bots.think_min = 0.25
	game.balance.bots.think_max = 0.5
	game.balance.pve.think_seconds = 0.6
	game.balance.charge_rate = float(game.balance.charge_rate) * float(args.get("charge", "2.2"))

# What the player's side does at the start of its turns: skills 1-9 and a full POW bar.
func local_turn(fighter: TankFighter) -> void:
	var game: LocalMatch = match_game()
	if fighter.player_id != game.local_id:
		return
	for id in str(args.get("items", "plus1,dmg50")).split(",", false):
		game.apply_item(fighter, id)
	if game.round_number >= int(args.get("pow_turn", "2")):
		fighter.pow_gauge = float(game.balance.pow_max)
		if not game.turn_pow and not fighter.has_status("selado"):
			game.arm_pow(fighter)

# A PvP duel (auto-played by the AI): skills, then POW from the second turn on.
func setup_duel() -> void:
	var game: LocalMatch = match_game()
	hurry()
	game.turn_started.connect(local_turn)
	local_turn(game.active())

# The instance fight: the player's AI plays the phase.
func setup_boss() -> void:
	var game: LocalMatch = match_game()
	hurry()
	game.set_auto_play(true)
	game.turn_started.connect(local_turn)
	local_turn(game.active())

func setup_screen() -> void:
	pass

# ---------- the touch pilot (the mobile trailer) ----------
# --seg=pilot --touch=1: the local player's turns are played with fingers. The pilot sends
# the same ScreenTouch events a phone sends, to the same on-screen controls (walk, aim,
# FOGO, the skill drawer, POW), so what the video shows is the real touch interface at work.
# The shot comes from the bots' own solver (EnemyAI.choose_shot): the pilot holds the aim
# pad until the angle is right and lets go of FOGO when the force is. A marker follows each
# finger (like "show touches" on a phone) and every touch is logged to --taplog for the
# tap sound of the video.
#
#   --items=plus1,dmg50   skills tapped in the drawer at the start of each turn
#   --items_from=<round>  first round with those skills (default 1)
#   --pow_turn=<round>    from this round the POW bar is full and the orb is tapped
#   --walk=<seconds>      how long the thumb holds the walk arrow (it also turns the fighter)
#   --charge=<factor>     force bar speed (1.3: about two points per frame)
#   --turn=<seconds>      turn length (the pilot is slower than a bot)

# A marker under each finger: soft disc, ring and a ripple where it lands.
class FingerLayer:
	extends Control

	var touches: Dictionary = {}
	var ripples: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(1280, 720)

	func down(index: int, at: Vector2) -> void:
		touches[index] = {"at": at, "age": 0.0}
		ripples.append({"at": at, "age": 0.0})

	func up(index: int) -> void:
		touches.erase(index)

	func _process(delta: float) -> void:
		for touch: Dictionary in touches.values():
			touch.age += delta
		for ripple: Dictionary in ripples:
			ripple.age += delta
		ripples = ripples.filter(func(ripple: Dictionary) -> bool: return ripple.age < 0.45)
		queue_redraw()

	func _draw() -> void:
		for ripple: Dictionary in ripples:
			var k: float = ripple.age / 0.45
			draw_arc(ripple.at, 34.0 + 64.0 * k, 0.0, TAU, 48, Color(1, 1, 1, 0.7 * (1.0 - k)), 4.0, true)
		for touch: Dictionary in touches.values():
			var radius: float = lerpf(46.0, 32.0, clampf(touch.age / 0.12, 0.0, 1.0))
			draw_circle(touch.at + Vector2(3, 5), radius, Color(0, 0, 0, 0.22))
			draw_circle(touch.at, radius, Color(1, 1, 1, 0.26))
			draw_arc(touch.at, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.92), 3.0, true)

var fingers_layer: FingerLayer
var piloting: bool = false
# [frame, 1 (down) or 0 (up)] for every touch the pilot made.
var finger_log: Array = []

func make_fingers() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 100
	root.add_child(canvas)
	fingers_layer = FingerLayer.new()
	canvas.add_child(fingers_layer)

func setup_pilot() -> void:
	var game: LocalMatch = match_game()
	hurry()
	game.turn_seconds = float(args.get("turn", "30"))
	game.remaining = game.turn_seconds
	make_fingers()
	game.turn_started.connect(pilot_turn)
	pilot_turn(game.active())

# A button by its (translated) text, anywhere in the tree.
func find_button(text: String, node: Node = null) -> BaseButton:
	if node == null:
		node = main
	if node is BaseButton and (node as BaseButton).is_visible_in_tree() and str(node.get("text")) == text:
		return node as BaseButton
	for child in node.get_children():
		var found: BaseButton = find_button(text, child)
		if found != null:
			return found
	return null

# The city: a finger taps the Casa dos Mascotes, then the Caçada tab (--screen=city).
func setup_city() -> void:
	make_fingers()
	await pause_for(float(args.get("lead", "1.0")))
	await tap(Vector2(366, 475))
	await pause_for(1.6)
	var tab: BaseButton = find_button(TranslationServer.translate("Caçada"))
	if tab != null:
		await tap(centre_of(tab))

func alive() -> bool:
	return frame < frames and is_instance_valid(main)

# Waits that many seconds of the recording; false when the scene ended meanwhile.
func pause_for(seconds: float) -> bool:
	for i in range(maxi(1, roundi(seconds * 30.0))):
		await process_frame
		if not alive():
			return false
	return true

func finger(index: int, point: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)
	if pressed:
		fingers_layer.down(index, point)
	else:
		fingers_layer.up(index)
	finger_log.append([frame, 1 if pressed else 0])

func centre_of(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func tap(point: Vector2, hold: float = 0.14) -> void:
	finger(0, point, true)
	await pause_for(hold)
	finger(0, point, false)

func hold_pad(pad: Control, seconds: float) -> void:
	finger(0, centre_of(pad), true)
	await pause_for(seconds)
	finger(0, centre_of(pad), false)

func item_index(game: LocalMatch, id: String) -> int:
	var items: Array = game.balance.items
	for i in range(items.size()):
		if str(items[i].id) == id:
			return i
	return -1

func pilot_turn(fighter: TankFighter) -> void:
	var game: LocalMatch = match_game()
	if game == null or fighter.player_id != game.local_id or piloting:
		return
	piloting = true
	await play_turn(game, fighter)
	piloting = false

func play_turn(game: LocalMatch, fighter: TankFighter) -> void:
	var hud: BattleHUD = battle().hud
	var touch: TouchControls = hud.touch
	if not await pause_for(float(args.get("lead", "0.7"))):
		return
	# The skills, from the drawer at the end of the row.
	var wanted: PackedStringArray = str(args.get("items", "")).split(",", false)
	if not wanted.is_empty() and game.round_number >= int(args.get("items_from", "1")):
		await tap(centre_of(touch.drawer_toggle))
		await pause_for(0.45)
		for id in wanted:
			var index: int = item_index(game, id)
			if index >= 0:
				await tap(centre_of(hud.item_buttons[index]))
				await pause_for(0.4)
		await tap(centre_of(touch.drawer_toggle))
		await pause_for(0.35)
	# POW: a full bar, then the orb.
	if game.round_number >= int(args.get("pow_turn", "99")) and not game.turn_pow:
		fighter.pow_gauge = float(game.balance.pow_max)
		await pause_for(0.25)
		await tap(centre_of(hud.pow_button))
		await pause_for(0.5)
	# A thumb turns the fighter around by walking towards the target.
	var target: TankFighter = EnemyAI.pick_target(fighter, game.fighters, null)
	if target == null:
		return
	await hold_pad(touch.walk_right if target.position.x > fighter.position.x else touch.walk_left, float(args.get("walk", "0.4")))
	for i in range(30):
		if fighter.settled or not await pause_for(1.0 / 30.0):
			break
	var wind_scale: float = float(fighter.weapon.get("projectile", {}).get("wind_scale", 1.0))
	var accel: float = game.wind * float(game.balance.wind_accel) * wind_scale * game.wind_factor(fighter)
	var solution: Vector3 = EnemyAI.choose_shot(fighter, target, game.terrain, accel, game.balance)
	# Aim: hold the arrow until the angle is the solver's.
	var raise: bool = solution.x > fighter.angle
	var arrow: Control = touch.aim_up if raise else touch.aim_down
	if absf(solution.x - fighter.angle) > 0.6:
		finger(0, centre_of(arrow), true)
		while absf(solution.x - fighter.angle) > 0.6 and (solution.x > fighter.angle) == raise:
			if not await pause_for(1.0 / 30.0):
				break
		finger(0, centre_of(arrow), false)
	await pause_for(0.3)
	# FOGO: hold to charge the force, let go at the right one.
	finger(0, centre_of(touch.fire), true)
	for i in range(300):
		if not await pause_for(1.0 / 30.0):
			break
		if game.state == LocalMatch.State.PLAYER_CHARGING and game.power >= solution.y - 1.1:
			break
	finger(0, centre_of(touch.fire), false)
