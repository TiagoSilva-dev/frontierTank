extends Node2D

# Screen flow, as in DDTank: Entrada (servidor) → Cidade → Salão de Jogos → Sala → Partida →
# Resultado → Cartas → Sala.
#
# Online (backend 0.11) the title screen logs in on the API and connects to a game server;
# from then on the profile is a mirror of the server's copy (every change goes through
# `do_op`), the channel and rooms are real, and battles run in lockstep with the server.
# "Modo offline" keeps everything local, as before. With --server this same project is
# the game server instead (server/game/game_server.gd).

var balance: Dictionary
var profile: PlayerProfile
var audio: GameAudio
var lobby: LobbyDirectory
var ui: Control
var screen: Control
var screen_name: String = ""
var bag: Control
var room: Dictionary = {}
var run: InstanceRun
var last_summary: Dictionary = {}
var args: Dictionary = {}
var capture_frames: int = -1
var net: NetClient
var auth: AuthClient
var online: bool = false
var offline_profile: PlayerProfile
# The next phase of an online instance, kept while the transition screen counts down.
var pending_start: Dictionary = {}
var waiting_phase: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	args = parse_args()
	if args.has("server"):
		# The online game server: no screens, only the network (server/game).
		var server: GameServer = GameServer.new()
		server.configure(args)
		add_child(server)
		return
	# Language (roadmap 4.3): saved choice or the system language; --lang=en for captures.
	Lang.setup(str(args.get("lang", "")))
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	profile = PlayerProfile.new()
	if args.has("profile"):
		profile.save_path = str(args.profile)
	profile.load_profile()
	offline_profile = profile
	net = NetClient.new()
	net.event.connect(on_net_event)
	net.closed.connect(go_offline)
	add_child(net)
	auth = AuthClient.new()
	if args.has("api"):
		auth.base_url = str(args.api)
	add_child(auth)
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
	# Every text is translated explicitly (tr/Lang.t); Godot's automatic translation of
	# Control texts is off so an English text that is also a Portuguese key is never
	# translated twice.
	ui.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	# 0.10 showcase: currencies and the equipped gear as high level drops with bonuses.
	profile.redeem("MOEDAS")
	for inst: Dictionary in profile.equipped_list():
		if Crafting.can_have_mods(str(inst.id)):
			inst.ilvl = 16
			if inst.quality == "normal" and Armory.slot_of(str(inst.id)) != "arma":
				inst.quality = "verdadeira" if Armory.slot_of(str(inst.id)) == "roupa" else "excelente"
			inst.mods = Crafting.roll_mods(inst, profile.rng, 1.0)

func parse_args() -> Dictionary:
	var result: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1]
		elif arg.begins_with("--"):
			result[arg.substr(2)] = "1"
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
			room.instance = str(args.get("instance", "templo_sol"))
			if args.has("level"):
				# Capture helper: a map of that level in the slot (--level=10).
				profile.redeem("MAPAS")
				for item: Dictionary in profile.maps_for(str(room.instance)):
					if int(item.level) == int(args.level):
						room.map_uid = int(item.uid)
			show_room()
		"pve_battle":
			create_room("pve")
			room.instance = str(args.get("instance", "templo_sol"))
			if args.has("level"):
				profile.redeem("MAPAS")
				for item: Dictionary in profile.maps_for(str(room.instance)):
					if int(item.level) == int(args.level):
						room.map_uid = int(item.uid)
			start_battle()
			if args.has("phase"):
				# Capture helper: jump to phase 2 or 3 (clears the phases before it).
				for i in range(clampi(int(args.phase) - 1, 0, 2)):
					run.complete_phase(screen.game)
				start_phase()
			if args.has("zoom"):
				screen.camera.zoom = Vector2.ONE * float(args.zoom)
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
			if args.has("tab"):
				bag.select_tab(str(args.tab))
		"shop":
			show_city()
			shortcut("shop")
		"smith":
			show_city()
			shortcut("smith")
			if args.has("tab"):
				# Capture helper: --tab=Moedas opens another Ferreiro tab.
				var smith: SmithScreen = ui.get_children().filter(func(node: Node) -> bool: return node is SmithScreen).back()
				smith.tab = str(args.tab)
				if args.has("craft"):
					# --craft=map shows the maps in the Moedas tab.
					profile.redeem("MAPAS")
					smith.craft_target = str(args.craft)
				smith.build()
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
		audio.play_music("instance" if str(node.get("config").get("mode", room.get("mode", "pvp"))) == "pve" else "battle")
	else:
		audio.play_music("lobby")

func show_title() -> void:
	switch_to(TitleScreen.new(), "title")

func show_city() -> void:
	if online:
		leave_room_quietly()
		net.send_kind("lobby", {"on": false})
	switch_to(CityScreen.new(), "city")

func show_hall() -> void:
	leave_room_quietly()
	switch_to(HallScreen.new(), "hall")
	if online:
		net.send_kind("lobby", {"on": true})

func leave_room_quietly() -> void:
	if online and not room.is_empty():
		net.send_kind("room_leave")
	room = {}

func show_room() -> void:
	switch_to(RoomScreen.new(), "room")

func player_entry() -> Dictionary:
	return profile.entry(balance)

func create_room(mode: String) -> void:
	room = {"id": lobby.rng.randi_range(100, 999), "title": tr("Guerra de equipes, diversão sem limite"), "mode": mode, "capacity": 4, "members": [player_entry()], "owner": 0, "map": "", "turn_seconds": int(balance.turn_seconds), "ready": true}
	if mode == "pve":
		# Instance rooms: which instance and which map item (-1 = free entry) go in.
		room.instance = "templo_sol"
		room.map_uid = -1
		room.turn_seconds = int(balance.pve.get("turn_seconds", 20))
		room.title = tr("Expedição: %s") % tr(str(InstanceRun.instance_def(room.instance).name))

# Creates a room and opens it (online the server makes it).
func open_room(mode: String) -> void:
	if not online:
		create_room(mode)
		show_room()
		return
	var reply: Dictionary = await net.request("room_create", {"mode": mode})
	if not reply.ok:
		UiKit.notice(ui, tr("SALA"), server_text(reply.error))
		return
	room = reply.room
	show_room()

func join_room(source: Dictionary) -> bool:
	if source.is_empty() or source.playing or source.members.size() >= int(source.capacity):
		return false
	if online:
		var reply: Dictionary = await net.request("room_join", {"id": int(source.id)})
		if not reply.ok:
			UiKit.notice(ui, tr("SALA"), server_text(reply.error))
			return false
		room = reply.room
		show_room()
		return true
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
	if online:
		var reply: Dictionary = await net.request("room_bot")
		return reply.ok
	var names: Array = room.members.map(func(m: Dictionary) -> String: return m.name)
	room.members.append(lobby.bot_near(profile.level(), names))
	return true

func kick(index: int) -> void:
	if online:
		net.send_kind("room_kick", {"index": index})
		return
	if index > 0 and index < room.members.size() and not room.members[index].get("human", false):
		room.members.remove_at(index)

func is_owner() -> bool:
	if room.is_empty():
		return false
	if online:
		return int(room.members[int(room.owner)].get("account", -1)) == my_account()
	return bool(room.members[int(room.owner)].get("human", false))

# The test coupons (TESTARTUDO...) work offline, and online only on test servers.
func test_coupons() -> bool:
	return not online or bool(net.welcome().get("test_coupons", false))

func my_account() -> int:
	return int(net.account.get("id", -1)) if online else -1

# Whether a room member is this player (offline: the only human).
func is_me(member: Dictionary) -> bool:
	if online:
		return int(member.get("account", -2)) == my_account()
	return bool(member.get("human", false))

# Changes the room settings (map, turn time, instance, map item).
func room_set(changes: Dictionary) -> void:
	if not online:
		room.merge(changes, true)
		return
	var reply: Dictionary = await net.request("room_set", changes)
	if reply.ok:
		room = reply.room
	elif is_instance_valid(screen):
		UiKit.notice(ui, tr("SALA"), server_text(reply.error))

func leave_room() -> void:
	show_hall()

# The map item in the room's map slot (online the server tells, it is the owner's).
func room_map_item() -> Dictionary:
	if online:
		return room.get("map_item", {})
	return profile.find_map(int(room.get("map_uid", -1)))

func team_entries() -> Array:
	var team: Array = []
	for member: Dictionary in room.members:
		team.append(player_entry() if member.get("human", false) else member.duplicate())
	return team

func start_battle() -> void:
	if room.mode == "pve":
		start_instance()
		return
	var team: Array = team_entries()
	var level_sum: int = 0
	for entry: Dictionary in team:
		level_sum += int(entry.level)
	var rivals: Array = []
	var names: Array = team.map(func(m: Dictionary) -> String: return m.name)
	for i in range(team.size()):
		var rival: Dictionary = lobby.bot_near(level_sum / team.size(), names)
		names.append(rival.name)
		rivals.append(rival)
	run = null
	var battle: BattleScreen = BattleScreen.new()
	battle.config = {"mode": room.mode, "map": room.map, "turn_seconds": room.turn_seconds, "teams": [team, rivals]}
	switch_to(battle, "battle")

func start_instance() -> void:
	# The map item is consumed on entry; without one it is the free entry (level 1).
	var item: Dictionary = profile.find_map(int(room.get("map_uid", -1)))
	if not item.is_empty():
		item = item.duplicate(true)
		profile.remove_map(int(item.uid))
		profile.save_profile()
	room.map_uid = -1
	var team: Array = team_entries()
	# Party scaling counts players only (bots are ignored for now).
	var humans: int = team.filter(func(entry: Dictionary) -> bool: return entry.get("human", false)).size()
	run = InstanceRun.new(balance, str(room.get("instance", "templo_sol")), item, humans, team, profile)
	start_phase()

func start_phase() -> void:
	if online:
		# The server starts the next phase; its message may already be here.
		if pending_start.is_empty():
			waiting_phase = true
		else:
			var message: Dictionary = pending_start
			pending_start = {}
			start_online_battle(message)
		return
	var battle: BattleScreen = BattleScreen.new()
	battle.config = run.phase_config(run.members)
	switch_to(battle, "battle")

func battle_finished(game: LocalMatch) -> Dictionary:
	last_summary = Rewards.settle(game, game.local(), balance, profile, run)
	return last_summary

func phase_cleared(game: LocalMatch) -> Dictionary:
	# A phase before the boss was won: drops are kept even if the party falls later.
	var cleared: Dictionary = run.current_phase()
	var report: Dictionary = run.complete_phase(game)
	report.cleared = tr(str(cleared.name))
	report.next = run.current_phase()
	report.index = run.phase_index
	report.count = run.phase_count()
	return report

func return_to_room() -> void:
	if room.is_empty():
		show_hall()
		return
	run = null
	if online:
		if room.has("members"):
			show_room()
		else:
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
			UiKit.notice(ui, tr("AJUDA"), tr("← → mover (gasta energia)   ↑ ↓ ângulo\nSegure e solte ESPAÇO: força (a barra reinicia uma vez no máximo)\n1–9 habilidades (+2, x3, +1, POW 50%…10%, POW máx)   Z X C ferramentas\nB: POW com a barra cheia   F: avião de papel   V: item auxiliar\nP: passar a vez   Confiar: a IA joga por você   M: liga/desliga a música"))
		"exit":
			if screen_name == "city":
				var dialog: Control = UiKit.modal(ui, tr("SAIR"), tr("Deseja fechar o Frontier Tank?"))
				var rect: Rect2 = dialog.get_meta("rect")
				UiKit.button(dialog, tr("SAIR"), Rect2(rect.position.x + 90, rect.end.y - 60, 150, 42), quit_game)
				UiKit.button(dialog, tr("FICAR"), Rect2(rect.end.x - 240, rect.end.y - 60, 150, 42), dialog.queue_free)
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
			var names: Dictionary = {"pet": "PET", "mail": "CORREIO", "mission": "MISSÃO"}  # i18n
			UiKit.notice(ui, tr(names[id]), tr("Este sistema ainda não foi implementado nesta versão offline.\nFerramentas de batalha podem ser compradas dentro da sala."))

func quit_game() -> void:
	audio.stop_all()
	net.disconnect_now()
	get_tree().quit()

# ---------- profile changes ----------

# Every change the player makes to the profile: offline it happens here, online the
# server applies it and sends the new profile back. {"error": "", "message": ""}
func do_op(op: String, op_args: Array = []) -> Dictionary:
	if not online:
		return profile.apply_op(op, op_args, balance)
	var reply: Dictionary = await net.request("op", {"op": op, "args": op_args})
	if reply.get("profile") is Dictionary:
		apply_profile(reply.profile)
	if not reply.ok:
		return {"error": server_text(reply.get("error", "")), "message": ""}
	return {"error": "", "message": tr(str(reply.get("message", "")))}

# Texts from the server are Portuguese keys (or error codes): shown in the game language.
func server_text(value: Variant) -> String:
	var text: String = str(value)
	if text in ["timeout", "offline"]:
		return AuthClient.message_for(text)
	return tr(text)

func apply_profile(data: Dictionary) -> void:
	profile.load_data(data)
	if lobby is OnlineLobby:
		lobby.my_name = profile.player_name

# ---------- online (backend 0.11) ----------

func go_online(welcome: Dictionary) -> void:
	online = true
	profile = PlayerProfile.new()
	profile.remote = true
	profile.load_data(welcome.profile)
	lobby.queue_free()
	var channel: OnlineLobby = OnlineLobby.new()
	channel.net = net
	channel.my_name = profile.player_name
	lobby = channel
	add_child(lobby)
	for entry: Variant in welcome.get("chat", []):
		if entry is Dictionary:
			channel.add(entry)
	if welcome.get("speaker") is Dictionary and not welcome.speaker.is_empty():
		channel.speaker = OnlineLobby.text_of(welcome.speaker)
	channel.post("Sistema", tr("Bem-vindo ao servidor %s!") % str(welcome.server.name), "system")
	room = welcome.get("room", {})
	pending_start = {}
	waiting_phase = false
	# Back in a room that is waiting: open it (a battle under way reopens by itself).
	if not room.is_empty() and str(room.get("state", "")) == "waiting":
		show_room()
	else:
		switch_to(CityScreen.new(), "city")
	net.release_held()

func go_offline(reason: String = "") -> void:
	var was_online: bool = online
	online = false
	net.disconnect_now()
	profile = offline_profile
	room = {}
	run = null
	pending_start = {}
	waiting_phase = false
	if was_online:
		lobby.queue_free()
		lobby = LobbyDirectory.new()
		lobby.player_level = profile.level()
		add_child(lobby)
	show_title()
	if reason != "":
		UiKit.notice(ui, tr("CONEXÃO"), AuthClient.message_for(reason))

func on_net_event(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"chat", "lobby":
			if lobby is OnlineLobby:
				lobby.receive(message)
		"profile":
			apply_profile(message.profile)
			if message.has("notice"):
				UiKit.notice(ui, tr("AVISO"), tr(str(message.notice)))
			if screen_name == "city" and not profile.created and is_instance_valid(screen):
				show_city()
		"room":
			room = message.room
			if screen_name == "room" and is_instance_valid(screen):
				screen.call_deferred("rebuild")
		"room_left":
			room = {}
			if screen_name == "room":
				switch_to(HallScreen.new(), "hall")
				net.send_kind("lobby", {"on": true})
			if str(message.get("reason", "")) == "kicked":
				UiKit.notice(ui, tr("SALA"), tr("Você foi removido da sala."))
		"match_start":
			on_match_start(message)
		"ticks", "phase_end", "match_end", "cards":
			if message.get("profile") is Dictionary:
				apply_profile(message.profile)
			if screen_name == "battle" and is_instance_valid(screen):
				screen.on_net(message)

func on_match_start(message: Dictionary) -> void:
	var busy: bool = screen_name == "battle" and is_instance_valid(screen) and screen.online and screen.in_phase_break()
	if busy and not waiting_phase and not message.has("history"):
		pending_start = message
		return
	waiting_phase = false
	pending_start = {}
	start_online_battle(message)

func start_online_battle(message: Dictionary) -> void:
	var config: Dictionary = localize(message.config)
	var battle: BattleScreen = BattleScreen.new()
	battle.config = config
	battle.online = true
	battle.match_id = int(message.get("m", 0))
	battle.resume = message
	switch_to(battle, "battle")

# Names in a battle sent by the server are Portuguese keys: show them in the game language.
func localize(config: Dictionary) -> Dictionary:
	var copy: Dictionary = config.duplicate(true)
	var phase: Dictionary = copy.get("phase", {})
	for key: String in ["name", "instance"]:
		if phase.has(key):
			phase[key] = tr(str(phase[key]))
	var groups: Array = copy.get("teams", []).duplicate()
	groups.append_array(phase.get("waves", []))
	for group: Variant in groups:
		for entry: Variant in group:
			if entry is Dictionary and entry.has("enemy"):
				entry.name = tr(str(entry.name))
				if entry.get("summon") is Dictionary:
					entry.summon.name = tr(str(entry.summon.name))
	return copy

func _unhandled_key_input(event: InputEvent) -> void:
	# M switches the music on any screen (text fields keep their own keys).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		audio.set_music_on(not audio.music_on)
		toast(tr("Música ligada") if audio.music_on else tr("Música desligada"))

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
