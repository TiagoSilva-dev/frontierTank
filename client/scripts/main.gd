extends Node2D

# Screen flow, as in DDTank: Entrada (servidor) → Cidade → Salão de Jogos → Sala → Partida →
# Resultado → Cartas → Sala.
#
# Online (backend 0.11) the title screen logs in on the API and connects to a game server;
# from then on the profile is a mirror of the server's copy (every change goes through
# `do_op`), the channel and rooms are real, and battles run in lockstep with the server.
# "Modo offline" keeps everything local, as before. With --server this same project is
# the game server instead (server/game/game_server.gd).

# The ranked queue changed on the server (0.22): the ranked screen follows it.
signal ranked_changed(state: Dictionary)

var balance: Dictionary
var profile: PlayerProfile
var audio: GameAudio
var lobby: LobbyDirectory
var ui: Control
var screen: Control
# The Founder lobby entrance plays once per session (HallScreen).
var founder_entered: bool = false
var screen_name: String = ""
var bag: Control
var room: Dictionary = {}
var run: InstanceRun
var last_summary: Dictionary = {}
var args: Dictionary = {}
var capture_frames: int = -1
var net: NetClient
var auth: AuthClient
# GodotSteam, when the game runs from Steam (launch checklist); `steam.available`.
var steam: SteamService
var online: bool = false
var offline_profile: PlayerProfile
# The friends list of the player menu (per mode: the offline channel or one online account).
var friends: FriendBook
# The next phase of an online instance, kept while the transition screen counts down.
var pending_start: Dictionary = {}
var waiting_phase: bool = false
# Letters waiting in the Correio (Leilão 0.12), told by the server.
var mail_count: int = 0
# The city offers the training once per session (a "not now" is saved in the profile).
var tutorial_offered: bool = false
# FPS counter (F3) and the battle benchmark (--bench=30, ?bench=30 on the web).
var perf: PerfProbe
# Phones and tablets: touch becomes the mouse (client/systems/touch_assist.gd).
var touch_assist: TouchAssist

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	args = parse_args()
	if args.has("server"):
		# The online game server: no screens, only the network (server/game).
		var server: GameServer = GameServer.new()
		server.configure(args)
		add_child(server)
		return
	# The game was renamed (Frontier Tank -> Gustfire): bring the old user:// folder along
	# before anything reads it (client/systems/legacy_data.gd).
	LegacyData.migrate()
	TouchMode.setup(args)
	# Language (roadmap 4.3): saved choice or the system language; --lang=en for captures.
	Lang.setup(str(args.get("lang", "")))
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	profile = PlayerProfile.new()
	if args.has("bench"):
		# Benchmark: a 4v4 battle played by the AI, on a scratch profile (the player's
		# save is never touched).
		args.merge({"screen": "battle", "auto": "1", "team": "4", "profile": "user://bench_profile.json"})
	if args.has("profile"):
		profile.save_path = str(args.profile)
	profile.load_profile()
	offline_profile = profile
	friends = FriendBook.new()
	if args.has("profile"):
		# A scratch profile (captures, tests) keeps its own friends too.
		friends.path = str(args.profile).get_basename() + "_friends.json"
	friends.use_scope("offline")
	net = NetClient.new()
	net.event.connect(on_net_event)
	net.closed.connect(on_net_closed)
	add_child(net)
	auth = AuthClient.new()
	if args.has("api"):
		auth.base_url = str(args.api)
	add_child(auth)
	steam = SteamService.new()
	add_child(steam)
	audio = GameAudio.new()
	add_child(audio)
	if args.has("seed"):
		LobbyDirectory.fixed_seed = int(args.seed)
	lobby = LobbyDirectory.new()
	lobby.player_level = profile.level()
	lobby.my_name = profile.player_name
	lobby.chat_added.connect(on_chat_line)
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
	perf = PerfProbe.new()
	perf.app = self
	perf.shown = args.has("fps")
	add_child(perf)
	if TouchMode.active():
		touch_assist = TouchAssist.new()
		add_child(touch_assist)
		if OS.has_feature("mobile"):
			# A battle waits for the player to think: the screen must not go dark.
			DisplayServer.screen_set_keep_on(true)
	if args.has("bench"):
		profile.created = true
		perf.start_bench(float(args.bench))
	if args.has("out"):
		capture_frames = int(args.get("frames", "30"))
		profile.created = true
	if args.has("demo"):
		demo_loadout(str(args.demo))
	if args.has("hunt"):
		demo_hunt(int(args.hunt))
	open_named(str(args.get("screen", "title")))

func demo_loadout(kind: String) -> void:
	# Capture helper (--demo=1): everything unlocked and a showcase set equipped.
	profile.redeem("TESTARTUDO")
	var founder_demo: bool = kind == "founder"
	if founder_demo:
		# Founder Pack showcase: the pack's items (normally bought with the Steam Wallet).
		for id: String in FounderPack.ITEMS:
			if not profile.has_item(id):
				profile.add_instance(id, "normal", 0)
	var wanted: Dictionary = {"arma": ["lanca_antiga", 12], "skin": [kind if kind.begins_with("epica_") else ("roupa_samurai" if profile.gender == "m" else "roupa_princesa"), 0], "camisa": ["camisa_guerra", 7], "calca": ["calca_guerra", 0], "chapeu": ["chapeu_kabuto" if kind == "1" else "chapeu_coroa", 0], "asas": ["asas_anjo", 0], "oculos": ["oculos_escuros" if kind == "1" else "", 0], "cabelo": ["cabelo_dourado" if kind == "2" else "", 0], "auxiliar": ["dom_de_anjo_v", 0], "anel1": ["anel_esmeralda", 0], "anel2": ["anel_bronze", 0], "amuleto": ["amuleto_lobo", 0]}
	if founder_demo:
		wanted = {"arma": [FounderPack.WEAPON, int(args.get("wlevel", "12"))], "skin": [FounderPack.SKIN, 0], "auxiliar": ["dom_de_anjo_v", 0]}
	if kind.begins_with("pve"):
		# 0.31 capture helper (--demo=pve_lendario|pve_epico|pve_raro|pve_comum): a whole set of
		# instance gear of one rarity (the Lendário one by default), to see the art side by side.
		var tier: String = kind.substr(4) if kind.length() > 4 else "lendario"
		var rings: int = 0
		for def: Dictionary in Armory.data().cosmetics:
			if bool(def.get("pve", false)) and str(def.get("rarity", "")) == tier:
				var place: String = str(def.slot)
				if place == "anel":
					rings += 1
					place = "anel%d" % rings
				if wanted.has(place) and (place not in ["anel1", "anel2"] or rings <= 2):
					wanted[place] = [str(def.id), 0]
	for slot: String in wanted:
		var id: String = wanted[slot][0]
		for inst: Dictionary in profile.inventory:
			if inst.id == id:
				inst.level = int(wanted[slot][1])
				profile.equip(int(inst.uid))
				break
	profile.add_item("strength_stone_iv", 20)
	# 0.29 capture helper: --color=<id> draws the epic skin in one of its alternative colours.
	if kind.begins_with("epica_") and args.has("color"):
		profile.pick_skin_color(kind, str(args.color))
	# 0.19 showcase: a few pets of every rarity, the Fênix Dourada by your side.
	if profile.pets.is_empty():
		for entry: Array in [["fenix_dourada", 12], ["leao_dourado", 9], ["raposa_glacial", 6], ["chacal_ambar", 4], ["escaravelho_solar", 2]]:
			profile.pets.append({"uid": profile.next_uid, "species": entry[0], "level": entry[1], "xp": 0})
			profile.next_uid += 1
			profile.pet_album.append(entry[0])
		profile.pet_active = int(profile.pets[0].uid)
	# 0.10 showcase: currencies and the equipped gear as high level drops with bonuses.
	profile.redeem("MOEDAS")
	for inst: Dictionary in profile.equipped_list():
		if Crafting.can_have_mods(str(inst.id)):
			inst.ilvl = 16
			if inst.quality == "normal" and Armory.slot_of(str(inst.id)) != "arma":
				inst.quality = "verdadeira" if Armory.slot_of(str(inst.id)) in ["camisa", "calca"] else "excelente"
			inst.mods = Crafting.roll_mods(inst, profile.rng, 1.0)

# Capture helper (--screen=pet --tab=Caçada --hunt=<seconds already hunted> --zone= --tier=
# --boss=1): a hunt of the first pets, started that many seconds ago.
func demo_hunt(seconds: int) -> void:
	var team: Array = []
	for pet: Dictionary in profile.pets.slice(0, 4):
		team.append(int(pet.uid))
	profile.hunt_set(str(args.get("zone", "sol")), int(args.get("tier", "1")), team)
	profile.hunt.since = profile.hunt_now() - seconds
	if args.has("boss"):
		# Looks for a seed whose current encounter is the Lendário boss.
		var current: int = int(profile.hunt.n) + PetHunt.pending_slots(profile, profile.hunt_now())
		for candidate in range(2, 400000):
			if PetHunt.slot_rng({"seed": candidate}, current).randf() < float(PetHunt.rules().boss.chance):
				profile.hunt.seed = candidate
				break

func parse_args() -> Dictionary:
	var result: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1]
		elif arg.begins_with("--"):
			result[arg.substr(2)] = "1"
	if OS.has_feature("web"):
		result.merge(web_query(), true)
	return result

# On the web the options come from the page address: index.html?bench=30&lang=en&api=...
# (the server mode and screenshots make no sense in a browser).
static func web_query() -> Dictionary:
	var result: Dictionary = {}
	var query: String = str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for pair: String in query.split("&", false):
		var parts: PackedStringArray = pair.split("=", true, 1)
		var key: String = parts[0].uri_decode()
		if key in ["server", "out", "frames"]:
			continue
		result[key] = parts[1].uri_decode() if parts.size() > 1 else "1"
	return result

func open_named(target: String) -> void:
	match target:
		"hall":
			show_hall()
		"founder":
			show_city()
			FounderScreen.open(self)
		"tutorial":
			start_tutorial()
		"missions":
			show_city()
			open_missions(str(args.get("tab", "")))
		"challenge":
			show_hall()
			ChallengeScreen.open(screen, self)
		"ranked":
			show_hall()
			profile.experience = PlayerProfile.exp_for_level(5)
			profile.rating = Ranked.empty_rating()
			profile.rating.mmr = int(args.get("mmr", "1288"))
			profile.rating.games = 12
			profile.rating.wins = 8
			profile.rating.losses = 4
			profile.rating.peak = profile.rating.mmr + 12
			profile.titles = ["s1_ouro"]
			profile.title = "s1_ouro"
			var demo_screen: RankedScreen = RankedScreen.new()
			demo_screen.app = self
			demo_screen.demo = true
			screen.add_child(demo_screen)
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
			# --team=4 makes a 4v4 (the benchmark); the default is 2v2.
			for i in range(clampi(int(args.get("team", "2")) - 1, 1, 3)):
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
		"mission", "mail", "coupon":
			# Capture helpers: the quests, the post office and the coupon window over the city.
			show_city()
			shortcut(target)
		"pet":
			# Capture helper: the Casa dos Mascotes over the city (--tab=Mascotes|Álbum|Caçada).
			show_city()
			PetScreen.open(ui, self, str(args.get("tab", "Mascotes")))
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
		"legal":
			# Capture helpers (launch checklist): --kind=privacy, --mode=update.
			show_title()
			LegalScreen.open(ui, str(args.get("kind", "terms")))
		"consent":
			show_title()
			ConsentDialog.open(ui, str(args.get("mode", "create")))
		"account":
			show_city()
			if args.has("logged"):
				# --logged=1: as if logged in on the title (the account's own buttons).
				auth.token = "capture"
				auth.username = "nilo"
			open_account()
		"help":
			show_city()
			open_help()
		"report":
			show_city()
			ReportDialog.open(ui, self, {"id": 1, "account": 2, "author": "Tiroteio", "text": tr("bora sala 4x4!!")})
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
	if args.has("seed"):
		battle.config.seed = int(args.seed)
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
	if args.has("seed") and not battle.config.has("seed"):
		battle.config.seed = int(args.seed)
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

# The shop on its Mascotes tab (the Casa dos Mascotes links here).
func open_pet_shop() -> void:
	var shop: ShopScreen = ShopScreen.new()
	shop.app = self
	shop.tab = "pet"
	shop.closed.connect(refresh_room)
	ui.add_child(shop)

func shortcut(id: String) -> void:
	audio.play("ui_click")
	match id:
		"bag":
			open_bag()
		"help":
			open_help()
		"exit":
			if screen_name == "city":
				var dialog: Control = UiKit.modal(ui, tr("SAIR"), tr("Voltar à tela de entrada?") if OS.has_feature("web") else tr("Deseja fechar o Gustfire?"))
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
			shop.tab = str(args.get("tab", "arma"))
			# Capture helpers: --try=<item> on the fitting stage, --pet=<species> (tab pet), --view=battle, --dir=east.
			if args.has("try"):
				shop.trying = {"id": str(args.try), "quality": "normal", "level": 0}
				shop.preview_color = str(args.get("color", ""))
			if args.has("pet"):
				shop.trying_pet = str(args.pet)
			shop.preview_mode = str(args.get("view", "stand"))
			shop.preview_direction = str(args.get("dir", "south"))
			shop.closed.connect(refresh_room)
			ui.add_child(shop)
		"smith":
			var smith: SmithScreen = SmithScreen.new()
			smith.app = self
			ui.add_child(smith)
		"coupon":
			CouponDialog.open(ui, self)
		"mail":
			open_mail()
		"mission":
			open_missions()
		"pet":
			PetScreen.open(ui, self)

func open_missions(tab: String = "") -> MissionScreen:
	var missions: MissionScreen = MissionScreen.new()
	missions.app = self
	missions.tab = tab
	ui.add_child(missions)
	return missions

# ---------- daily challenge (0.22) ----------

# Plays today's challenge: a local battle in lockstep through a LocalHost that records it.
func start_challenge() -> void:
	leave_room_quietly()
	run = null
	var battle: BattleScreen = BattleScreen.new()
	battle.config = Challenge.local_config(Challenge.day_id(), profile, balance)
	switch_to(battle, "battle")

# The challenge screen over the Salão.
func show_challenge() -> ChallengeScreen:
	show_hall()
	return ChallengeScreen.open(screen, self)

# Online the server re-runs the replay and answers with the verified score and the position.
func submit_challenge(replay: Dictionary) -> Dictionary:
	var reply: Dictionary = await net.request("challenge_submit", {"day": int(replay.meta.day), "replay": replay}, 90.0)
	if reply.get("profile") is Dictionary:
		apply_profile(reply.profile)
	return reply

# ---------- replays (0.22) ----------

# Where the replay was opened from, to return there when it ends ("hall" or "city").
var replay_origin: String = "hall"

# Plays a stored replay (Replay.load_file) with no controls.
func start_replay(replay: Dictionary) -> void:
	replay_origin = screen_name if screen_name in ["hall", "city"] else "hall"
	leave_room_quietly()
	var battle: BattleScreen = BattleScreen.new()
	battle.config = localize(replay.config)
	battle.replay = replay
	switch_to(battle, "battle")

# Asks the server to broadcast a battle that is going on; its answer is a match_start with
# the stream, which opens the screen like any online battle.
func watch(match_id: int, host: Node = null) -> void:
	if not online:
		return
	var reply: Dictionary = await net.request("spectate", {"m": match_id})
	if not reply.ok:
		UiKit.notice(host if host != null else ui, tr("ASSISTIR"), server_text(reply.get("error", "")))

func close_replay() -> void:
	if replay_origin == "city":
		show_city()
	else:
		show_hall()

# ---------- training (0.21) ----------

# The scripted battle against the Boneco de Treino. Always local, even when online.
func start_tutorial() -> void:
	tutorial_offered = true
	leave_room_quietly()
	if online:
		net.send_kind("lobby", {"on": false})
	run = null
	var battle: BattleScreen = BattleScreen.new()
	battle.config = Tutorial.config(balance, profile)
	switch_to(battle, "battle")

# Leaves the training before the end: it is not offered again, but AJUDA keeps the button.
func leave_tutorial() -> void:
	if profile.tutorial == "":
		await do_op("tutorial", ["skip"])
	show_city()

# The dummy is down: the reward comes once, then the starter checklist opens.
func finish_tutorial() -> void:
	var result: Dictionary = await do_op("tutorial", ["done"])
	show_city()
	if result.error == "":
		toast(tr("Treino concluído!"))
		open_missions("starter")

# The controls, the legal texts and the account (launch checklist: LGPD/GDPR).
func open_help() -> Control:
	var dialog: Control = UiKit.modal(ui, tr("AJUDA"), help_text(), Vector2(760, 360))
	dialog.name = "HelpDialog"
	var rect: Rect2 = dialog.get_meta("rect")
	var row: float = rect.end.y - 62
	var terms: Button = UiKit.button(dialog, Legal.title("terms"), Rect2(rect.position.x + 30, row, 170, 42), func() -> void: LegalScreen.open(ui, "terms"), "button_blue", 14)
	terms.name = "HelpTerms"
	var privacy: Button = UiKit.button(dialog, tr("Privacidade"), Rect2(rect.position.x + 210, row, 170, 42), func() -> void: LegalScreen.open(ui, "privacy"), "button_blue", 14)
	privacy.name = "HelpPrivacy"
	var account: Button = UiKit.button(dialog, tr("Minha conta"), Rect2(rect.position.x + 390, row, 170, 42), func() -> void:
		dialog.queue_free()
		open_account(), "button_green", 14)
	account.name = "HelpAccount"
	if screen_name in ["city", "hall", "room"]:
		var training: Button = UiKit.button(dialog, tr("TREINO"), Rect2(rect.position.x + 30, row - 52, 170, 42), func() -> void:
			dialog.queue_free()
			start_tutorial(), "button_green", 16)
		training.name = "HelpTraining"
	UiKit.button(dialog, tr("FECHAR"), Rect2(rect.end.x - 190, row, 160, 42), dialog.queue_free)
	return dialog

# The controls: the keyboard of a computer, or the buttons of a phone.
func help_text() -> String:
	if TouchMode.active():
		return tr("◀ ▶ andar (gasta energia)   ↑ ↓ ângulo\nSegure FOGO e solte: força (a barra reinicia uma vez no máximo)\nHAB. abre as habilidades 1–9 (+2, x3, +1, POW 50%…10%, POW máx)\nPOW: com a barra cheia   Ferramentas, avião, item auxiliar e mascote: botões em fila\nPASS: passar a vez   Confiar: a IA joga por você\nSegure um botão para ver o que ele faz")
	return tr("← → mover (gasta energia)   ↑ ↓ ângulo\nSegure e solte ESPAÇO: força (a barra reinicia uma vez no máximo)\n1–9 habilidades (+2, x3, +1, POW 50%…10%, POW máx)   Z X C ferramentas\nB: POW com a barra cheia   F: avião de papel   V: item auxiliar\nP: passar a vez   Confiar: a IA joga por você   M: liga/desliga a música")

func open_account() -> AccountScreen:
	return AccountScreen.open(ui, self)

# ---------- Leilão e Correio (0.12) ----------

# Both live on the game server (the items are in custody in the database): offline they
# only explain how to get there.
func open_auction(parent: Node = null) -> AuctionScreen:
	var host: Node = parent if parent != null else ui
	if not online:
		UiKit.notice(host, tr("LEILÃO"), tr("O Leilão só funciona online: os itens à venda ficam guardados no servidor.\nEscolha um servidor na tela de entrada."))
		return null
	var auction: AuctionScreen = AuctionScreen.new()
	auction.app = self
	host.add_child(auction)
	return auction

func open_mail(parent: Node = null) -> MailScreen:
	var host: Node = parent if parent != null else ui
	if not online:
		UiKit.notice(host, tr("CORREIO"), tr("O Correio só funciona online: ele entrega o que você compra e vende no Leilão.\nEscolha um servidor na tela de entrada."))
		return null
	var mail: MailScreen = MailScreen.new()
	mail.app = self
	host.add_child(mail)
	return mail

# A request of the Leilão or the Correio: the profile in the answer replaces ours, and
# errors come back as texts in the game language.
func trade(kind: String, data: Dictionary = {}) -> Dictionary:
	if not online:
		return {"ok": false, "error": tr("O Leilão só funciona online.")}
	var reply: Dictionary = await net.request(kind, data, 40.0)
	if reply.get("profile") is Dictionary:
		apply_profile(reply.profile)
	if not reply.ok:
		reply.error = server_text(reply.get("error", ""))
	return reply

func quit_game() -> void:
	if OS.has_feature("web"):
		# A browser tab cannot close itself: back to the title screen.
		if online:
			go_offline()
		else:
			show_title()
		return
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
	sync_achievements()

# Steam achievements come from the online profile (the server's copy) only.
func sync_achievements() -> void:
	if not online or not steam.available:
		return
	for id: String in steam.sync_achievements(profile):
		for entry: Dictionary in Achievements.list():
			if str(entry.id) == id:
				toast(tr("Conquista: %s") % tr(str(entry.name)))

# ---------- Steam shop (launch checklist) ----------

# Buys a product of the Premium tab: the server opens the order, the Steam overlay asks
# the player, and once approved the items arrive in the Correio. Returns the message for
# the shop.
func buy_premium(sku: String) -> String:
	if not online:
		return tr("Entre com a sua conta para comprar.")
	if not steam.available:
		return await buy_with_card(sku)
	var reply: Dictionary = await net.request("store_buy", {"sku": sku}, 30.0)
	if not reply.ok:
		return server_text(reply.get("error", ""))
	var order_id: int = int(reply.order_id)
	var answer: int = await steam.wait_purchase(order_id)
	if answer < 0:
		# No answer from the overlay: an approval that comes later is delivered at the
		# next login (the server reconciles open orders).
		return tr("A Steam ainda não confirmou a compra. Se você aprovar, os itens chegam ao Correio.")
	if answer == 0:
		net.send_kind("store_cancel", {"order_id": order_id})
		return tr("Compra cancelada.")
	var done: Dictionary = await net.request("store_finalize", {"order_id": order_id}, 40.0)
	if not done.ok:
		return server_text(done.get("error", ""))
	audio.play("ui_coin")
	return tr("Compra concluída! Os itens chegaram ao Correio.")

# Web and mobile (no Steam): the server opens a Stripe page (card or Pix, in reais), the
# game opens it in the browser and asks the server how the order stands until it is paid.
# The items arrive in the Correio; if the game closes meanwhile, the next login delivers.
var pending_checkout: Dictionary = {}
const CHECKOUT_FAST: float = 4.0
const CHECKOUT_SLOW: float = 10.0
const CHECKOUT_WATCH: float = 3600.0

func buy_with_card(sku: String) -> String:
	var reply: Dictionary = await net.request("store_checkout", {"sku": sku}, 30.0)
	if not reply.ok:
		return server_text(reply.get("error", ""))
	pending_checkout = {"sku": sku, "order_id": int(reply.order_id), "url": str(reply.url)}
	open_checkout()
	watch_checkout(int(reply.order_id))
	return tr("Página de pagamento aberta no navegador (cartão ou Pix). Os itens chegam ao Correio quando o pagamento for confirmado.")

# Only an https address from the server is opened. Called straight from a click too (the
# shop's ABRIR PAGAMENTO), because browsers block a window opened long after the click.
func open_checkout() -> void:
	var url: String = str(pending_checkout.get("url", ""))
	if url.begins_with("https://"):
		OS.shell_open(url)

func watch_checkout(order_id: int) -> void:
	var waited: float = 0.0
	var failures: int = 0
	while is_inside_tree() and online and waited < CHECKOUT_WATCH and int(pending_checkout.get("order_id", 0)) == order_id:
		var step: float = CHECKOUT_FAST if waited < 120.0 else CHECKOUT_SLOW
		await get_tree().create_timer(step).timeout
		waited += step
		var answer: Dictionary = await net.request("store_status", {"order_id": order_id}, 20.0)
		if not answer.ok:
			failures += 1
			if failures >= 5:
				break
			continue
		failures = 0
		match str(answer.get("status", "")):
			"paid":
				pending_checkout = {}
				audio.play("ui_coin")
				toast(tr("Compra confirmada! Os itens chegaram ao Correio."))
				return
			"cancelled", "failed", "refunded":
				pending_checkout = {}
				toast(tr("O pagamento não foi concluído."))
				return
	if int(pending_checkout.get("order_id", 0)) == order_id:
		pending_checkout = {}

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
	friends.use_scope("acc%d" % int(welcome.get("account", {}).get("id", 0)))
	lobby = channel
	lobby.chat_added.connect(on_chat_line)
	add_child(lobby)
	for entry: Variant in welcome.get("chat", []):
		if entry is Dictionary:
			channel.add(entry)
	sync_achievements()
	if welcome.get("speaker") is Dictionary and not welcome.speaker.is_empty():
		channel.speaker = OnlineLobby.text_of(welcome.speaker)
	channel.post("Sistema", tr("Bem-vindo ao servidor %s!") % str(welcome.server.name), "system")
	room = welcome.get("room", {})
	pending_start = {}
	waiting_phase = false
	mail_count = 0
	# Back in a room that is waiting: open it (a battle under way reopens by itself).
	if not room.is_empty() and str(room.get("state", "")) == "waiting":
		show_room()
	else:
		switch_to(CityScreen.new(), "city")
	net.release_held()

# A connection that dies with no word from the server (a phone in the background, a lost
# signal) gets a few quiet tries to come back before the player is sent to the title. The
# server hands a battle under way back with its history, so it reopens by itself.
var reconnecting: bool = false
const RECONNECT_TRIES: int = 8
# Close reasons that retrying cannot fix: the server told us why.
const NO_RECONNECT: Array[String] = ["unauthorized", "outdated", "online_elsewhere", "terms_required", "banned", "server_full"]

func on_net_closed(reason: String) -> void:
	if reason == "connection_lost" and online and TouchMode.active() and not reconnecting and net.last_url != "" and net.last_token != "":
		reconnect()
		return
	go_offline(reason)

func reconnect() -> void:
	reconnecting = true
	var banner: Label = UiKit.label(ui, tr("Reconectando…"), Rect2(440, 8, 400, 40), 22, Color("fff0c0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	banner.name = "Reconnecting"
	var code: String = "unreachable"
	for attempt in range(RECONNECT_TRIES):
		code = await net.connect_to(net.last_url, net.last_token)
		if code == "" or code in NO_RECONNECT:
			break
		await get_tree().create_timer(2.0).timeout
	if is_instance_valid(banner):
		banner.queue_free()
	reconnecting = false
	if code == "":
		go_online(net.welcome())
	else:
		go_offline(code)

func go_offline(reason: String = "") -> void:
	var was_online: bool = online
	online = false
	net.disconnect_now()
	profile = offline_profile
	friends.use_scope("offline")
	room = {}
	run = null
	pending_start = {}
	waiting_phase = false
	mail_count = 0
	# The Leilão, the Correio and the account panel belong to the connection.
	for node: Node in ui.get_children():
		if node is AuctionScreen or node is MailScreen or node is AccountScreen or node.name == "HelpDialog":
			node.queue_free()
	if was_online:
		lobby.queue_free()
		lobby = LobbyDirectory.new()
		lobby.player_level = profile.level()
		lobby.my_name = profile.player_name
		lobby.chat_added.connect(on_chat_line)
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
		"mail":
			mail_count = maxi(0, int(message.get("count", 0)))
		"ranked_state":
			ranked_changed.emit(message)
		"ticks", "phase_end", "match_end", "cards", "mob_loot":
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
	if bool(message.get("watch", false)):
		# A live broadcast of someone else's battle (0.22).
		config.spectate = true
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

# Android's back button (project.godot keeps quit_on_go_back off): what is on top closes, as
# ESC does on a computer; with nothing on top the screen goes back one step, as SAIR does.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and ui != null:
		go_back()

func go_back() -> void:
	var overlay: Control = topmost_overlay()
	if overlay != null:
		if overlay == bag:
			close_bag()
		elif overlay.has_method("close"):
			overlay.call("close")
		else:
			overlay.queue_free()
		return
	match screen_name:
		"battle":
			# The battle's own ESC: pause (or leave a replay).
			TouchControls.send_key(KEY_ESCAPE, true)
			TouchControls.send_key(KEY_ESCAPE, false)
		"title":
			if not OS.has_feature("web"):
				quit_game()
		_:
			shortcut("exit")

# The window or dialog drawn above everything else: over the screens (shop, bag, help...), then
# over the current screen (a dialog it opened). Toasts and banners are Labels: they are not it.
func topmost_overlay() -> Control:
	for host: Node in [ui, screen]:
		if not is_instance_valid(host):
			continue
		for i in range(host.get_child_count() - 1, -1, -1):
			var node: Node = host.get_child(i)
			if node == screen or not (node is Control) or node is Label or not (node as Control).visible:
				continue
			if host == ui or node.name == "Modal" or node.has_method("close"):
				return node
	return null

func _unhandled_key_input(event: InputEvent) -> void:
	# M switches the music on any screen (text fields keep their own keys); F3 shows the
	# FPS counter.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		audio.set_music_on(not audio.music_on)
		toast(tr("Música ligada") if audio.music_on else tr("Música desligada"))
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		perf.toggle()

# A private message from someone else tells itself with a toast, unless the Privado tab of a
# chat on screen is already showing it (the battle has no chat: the toast is the only sign).
func on_chat_line(message: Dictionary) -> void:
	if str(message.get("channel", "")) != "Privado" or bool(message.get("mine", false)) or str(message.get("author", "")) in [profile.player_name, lobby.my_name]:
		return
	var stack: Array[Node] = [ui]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is ChatBox and (node as ChatBox).tab == "Privado":
			return
		stack.append_array(node.get_children())
	audio.play("ui_click")
	toast(tr("Mensagem privada de %s") % str(message.get("author", "")))

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

func open_exchange(parent: Node = null) -> ExchangeScreen:
	var host: Node = parent if parent != null else ui
	if not online:
		UiKit.notice(host, tr("CASA DE CÂMBIO"), tr("Entre em um servidor online para trocar moedas e pedras com outros jogadores."))
		return null
	var exchange: ExchangeScreen = ExchangeScreen.new()
	exchange.app = self
	host.add_child(exchange)
	return exchange
