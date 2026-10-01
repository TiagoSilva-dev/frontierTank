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
	if main.screen is BattleScreen:
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
