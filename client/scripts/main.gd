extends Node2D

# Screen flow, as in DDTank: Entrada (servidor) → Cidade → Salão de Jogos → Sala → Partida →
# Resultado → Cartas → Sala.

var balance: Dictionary
var profile: PlayerProfile
var audio: GameAudio
var lobby: LobbyDirectory
var ui: Control
var screen: Control
var screen_name: String = ""
var bag: Control
var room: Dictionary = {}
var last_summary: Dictionary = {}
var args: Dictionary = {}
var capture_frames: int = -1

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	args = parse_args()
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	profile = PlayerProfile.new()
	if args.has("profile"):
		profile.save_path = str(args.profile)
	profile.load_profile()
	audio = GameAudio.new()
	add_child(audio)
	lobby = LobbyDirectory.new()
	lobby.player_level = profile.level()
	add_child(lobby)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.size = Vector2(1280, 720)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UiKit.make_theme()
	layer.add_child(ui)
	if args.has("out"):
		capture_frames = int(args.get("frames", "30"))
		profile.created = true
	if args.has("demo"):
		demo_loadout(str(args.demo))
	open_named(str(args.get("screen", "title")))

func demo_loadout(kind: String) -> void:
	# Capture helper (--demo=1): everything unlocked and a showcase set equipped.
	profile.redeem("TESTARTUDO")
	var wanted: Dictionary = {"arma": ["lanca_antiga", 12], "roupa": ["roupa_samurai" if profile.gender == "m" else "roupa_princesa", 7], "chapeu": ["chapeu_kabuto" if kind == "1" else "chapeu_coroa", 0], "asas": ["asas_anjo", 0], "oculos": ["oculos_escuros" if kind == "1" else "", 0], "cabelo": ["cabelo_dourado" if kind == "2" else "", 0], "auxiliar": ["dom_de_anjo_v", 0]}
	for slot: String in wanted:
		var id: String = wanted[slot][0]
		for inst: Dictionary in profile.inventory:
			if inst.id == id:
				inst.level = int(wanted[slot][1])
				profile.equip(int(inst.uid))
				break
	profile.add_item("strength_stone_iv", 20)

func parse_args() -> Dictionary:
	var result: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1]
	return result

func open_named(target: String) -> void:
	match target:
		"hall":
			show_hall()
		"room":
			create_room("pvp")
			for i in range(2):
				invite_bot()
			show_room()
		"pve":
			create_room("pve")
			show_room()
		"pve_battle":
			create_room("pve")
			invite_bot()
			start_battle()
		"battle", "result", "cards":
			create_room("pvp")
			room.map = str(args.get("map", ""))
			invite_bot()
			start_battle()
			if target == "battle":
				# Capture helper: open on the local player's turn (optionally auto-played).
				var opening: LocalMatch = screen.game
				for fighter in opening.fighters:
					fighter.delay = 100.0
				opening.local().delay = 0.0
				opening.begin_turn()
				opening.set_auto_play(args.get("auto", "") == "1")
				if args.has("zoom"):
					screen.camera.zoom = Vector2.ONE * float(args.zoom)
			else:
				var game: LocalMatch = screen.game
				for fighter in game.fighters:
					if fighter.team == 1:
						fighter.hp = 0
				game.fighters[game.local_id].stats.damage = 1830
				game.fighters[game.local_id].stats.kills = 2
				game.evaluate_winner()
				if target == "cards":
					screen.show_cards()
				else:
					screen.show_results()
		"bag":
			show_city()
			open_bag()
		"shop":
			show_city()
			shortcut("shop")
		"smith":
			show_city()
			shortcut("smith")
		"title":
			show_title()
		_:
			show_city()

func switch_to(node: Control, name_value: String) -> void:
	if is_instance_valid(screen):
		screen.queue_free()
	close_bag(false)
	screen = node
	screen_name = name_value
	node.set("app", self)
	ui.add_child(node)
	# Title, city, hall and rooms share the lobby theme; battles pick their own.
	if name_value == "battle":
		audio.play_music("instance" if room.get("mode", "pvp") == "pve" else "battle")
	else:
		audio.play_music("lobby")

func show_title() -> void:
	switch_to(TitleScreen.new(), "title")

func show_city() -> void:
	switch_to(CityScreen.new(), "city")

func show_hall() -> void:
	room = {}
	switch_to(HallScreen.new(), "hall")

func show_room() -> void:
	switch_to(RoomScreen.new(), "room")

func player_entry() -> Dictionary:
	return profile.entry(balance)

func create_room(mode: String) -> void:
	room = {"id": lobby.rng.randi_range(100, 999), "title": "Guerra de equipes, diversão sem limite" if mode == "pvp" else "Expedição ao Templo do Sol", "mode": mode, "capacity": 4, "members": [player_entry()], "owner": 0, "map": "templo_sol" if mode == "pve" else "", "turn_seconds": int(balance.turn_seconds), "difficulty": "normal", "ready": true}

func join_room(source: Dictionary) -> bool:
	if source.is_empty() or source.playing or source.members.size() >= int(source.capacity):
		return false
	room = source.duplicate(true)
	room.members.append(player_entry())
	room.owner = 0
	room.ready = false
	source.members.append({"name": profile.player_name, "level": profile.level()})
	show_room()
	return true

func invite_bot() -> bool:
	if room.is_empty() or room.members.size() >= int(room.capacity):
		return false
	var names: Array = room.members.map(func(m: Dictionary) -> String: return m.name)
	room.members.append(lobby.bot_near(profile.level(), names))
	return true

func kick(index: int) -> void:
	if index > 0 and index < room.members.size() and not room.members[index].get("human", false):
		room.members.remove_at(index)

func is_owner() -> bool:
	return not room.is_empty() and bool(room.members[int(room.owner)].get("human", false))

func start_battle() -> void:
	var team: Array = []
	var level_sum: int = 0
	for member: Dictionary in room.members:
		var entry: Dictionary = player_entry() if member.get("human", false) else member.duplicate()
		team.append(entry)
		level_sum += int(entry.level)
	var rivals: Array = []
	if room.mode == "pve":
		rivals.append({"name": "Rei Hélio", "boss": true, "party": team.size(), "level": 12, "weapon": 0})
	else:
		var names: Array = team.map(func(m: Dictionary) -> String: return m.name)
		for i in range(team.size()):
			var rival: Dictionary = lobby.bot_near(level_sum / team.size(), names)
			names.append(rival.name)
			rivals.append(rival)
	var battle: BattleScreen = BattleScreen.new()
	battle.config = {"mode": room.mode, "map": room.map, "turn_seconds": room.turn_seconds, "difficulty": room.difficulty, "teams": [team, rivals]}
	switch_to(battle, "battle")

func battle_finished(game: LocalMatch) -> Dictionary:
	var me: TankFighter = game.local()
	var won: bool = game.winner_team == me.team
	var rules: Dictionary = balance.rewards
	var kill_exp: int = int(me.stats.kills) * int(rules.exp_per_kill)
	var hurt_exp: int = roundi(float(me.stats.damage) * float(rules.exp_per_damage))
	var result_exp: int = int(rules.win_exp if won else rules.loss_exp)
	var bonus_exp: int = 0
	if game.pve and won:
		bonus_exp = roundi(float(rules.pve_exp) * float(game.difficulty.get("reward", 1.0)))
	var merit: int = int(rules.merit_win if won else rules.merit_loss) + int(me.stats.kills) * int(rules.merit_per_kill)
	var level_before: int = profile.level()
	profile.tools = ["", "", ""]
	for i in range(mini(3, me.tools.size())):
		profile.tools[i] = me.tools[i]
	profile.record_match(won, kill_exp + hurt_exp + result_exp + bonus_exp, merit)
	var roster: Array = []
	for fighter in game.fighters:
		if fighter.team == me.team:
			var fighter_exp: int = int(rules.win_exp if won else rules.loss_exp) + roundi(float(fighter.stats.damage) * float(rules.exp_per_damage)) + int(fighter.stats.kills) * int(rules.exp_per_kill)
			roster.append({"name": fighter.display_name, "exp": fighter_exp, "merit": int(rules.merit_win if won else rules.merit_loss) + int(fighter.stats.kills) * int(rules.merit_per_kill)})
	last_summary = {"won": won, "draw": game.winner_team < 0, "pve": game.pve, "kill_exp": kill_exp, "hurt_exp": hurt_exp, "result_exp": result_exp, "bonus_exp": bonus_exp, "merit": merit, "exp": kill_exp + hurt_exp + result_exp + bonus_exp, "roster": roster, "level_before": level_before, "level_after": profile.level(), "damage": int(me.stats.damage), "kills": int(me.stats.kills), "difficulty": str(game.difficulty.get("id", "normal"))}
	return last_summary

func return_to_room() -> void:
	if room.is_empty():
		show_hall()
		return
	for i in range(room.members.size()):
		if room.members[i].get("human", false):
			room.members[i] = player_entry()
	show_room()

func open_bag() -> void:
	close_bag()
	var sheet: CharacterScreen = CharacterScreen.new()
	sheet.app = self
	bag = sheet
	ui.add_child(sheet)

func close_bag(refresh: bool = true) -> void:
	if is_instance_valid(bag):
		bag.queue_free()
	bag = null
	if refresh:
		refresh_room()

func refresh_room() -> void:
	# Equipment may have changed: redress the player in the room.
	if screen_name == "room" and is_instance_valid(screen):
		for i in range(room.members.size()):
			if room.members[i].get("human", false):
				room.members[i] = player_entry()
		screen.call_deferred("rebuild")

func shortcut(id: String) -> void:
	audio.play("ui_click")
	match id:
		"bag":
			open_bag()
		"help":
			UiKit.notice(ui, "AJUDA", "← → mover (gasta energia)   ↑ ↓ ângulo\nSegure e solte ESPAÇO: força (a barra reinicia uma vez no máximo)\n1–9 habilidades (+2, x3, +1, POW 50%…10%, POW máx)   Z X C ferramentas\nB: POW com a barra cheia   F: avião de papel   V: item auxiliar\nP: passar a vez   Confiar: a IA joga por você   M: liga/desliga a música")
		"exit":
			if screen_name == "city":
				var dialog: Control = UiKit.modal(ui, "SAIR", "Deseja fechar o Frontier Tank?")
				var rect: Rect2 = dialog.get_meta("rect")
				UiKit.button(dialog, "SAIR", Rect2(rect.position.x + 90, rect.end.y - 60, 150, 42), quit_game)
				UiKit.button(dialog, "FICAR", Rect2(rect.end.x - 240, rect.end.y - 60, 150, 42), dialog.queue_free)
			elif screen_name == "room":
				show_hall()
			else:
				show_city()
		"shop":
			var shop: ShopScreen = ShopScreen.new()
			shop.app = self
			shop.closed.connect(refresh_room)
			ui.add_child(shop)
		"smith":
			var smith: SmithScreen = SmithScreen.new()
			smith.app = self
			ui.add_child(smith)
		"coupon":
			CouponDialog.open(ui, self)
		"pet", "mail", "mission":
			var names: Dictionary = {"pet": "PET", "mail": "CORREIO", "mission": "MISSÃO"}
			UiKit.notice(ui, names[id], "Este sistema ainda não foi implementado nesta versão offline.\nFerramentas de batalha podem ser compradas dentro da sala.")

func quit_game() -> void:
	audio.stop_all()
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	# M switches the music on any screen (text fields keep their own keys).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		audio.set_music_on(not audio.music_on)
		toast("Música ligada" if audio.music_on else "Música desligada")

func toast(text: String) -> void:
	var note: Label = UiKit.label(ui, text, Rect2(490, 96, 300, 36), 18, Color("fff0c0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	note.add_theme_constant_override("outline_size", 8)
	var tween: Tween = note.create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(note, "modulate:a", 0.0, 0.5)
	tween.tween_callback(note.queue_free)

func _process(_delta: float) -> void:
	if capture_frames > 0:
		capture_frames -= 1
		if capture_frames == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(args.out))
			get_tree().quit()
