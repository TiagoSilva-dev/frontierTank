class_name GameServer
extends Node

# The online game server (backend 0.11), the same Godot project run headless:
#   godot --headless --path . -- --server --port=7350 --api=http://api:8081 --api-key=...
# It holds the WebSocket connections, the channel (players online, chat, rooms), the
# matchmaking, the battles (MatchHost, in lockstep) and the authoritative copy of every
# connected player's profile: purchases, Ferreiro, crafting, coupons and rewards run
# here with the game's own rules (PlayerProfile.apply_op, Rewards, InstanceRun). The Go
# API keeps accounts, sessions and saved profiles in PostgreSQL. With --api=memory it
# runs alone (tests, LAN): tokens "dev:<name>" log in and nothing is saved.
# Leilão (0.12): the server checks the auction rules (Auction) and the API keeps the
# listed items and the mail, writing the player's profile in the same transaction.

const PROTOCOL: int = 1
const HELLO_SECONDS: float = 10.0
const IDLE_SECONDS: float = 45.0
const CARD_SECONDS: float = 40.0
const SAVE_SECONDS: float = 2.0
const HEARTBEAT_SECONDS: float = 10.0
const AUDIT_SECONDS: float = 5.0
const LOBBY_SECONDS: float = 0.5
const MAX_MESSAGE: int = 16384
const CHAT_KEEP: int = 50
# Words hidden in the public chat (roadmap 4.3: moderated chat).
const BLOCKED_WORDS: Array[String] = ["porra", "caralho", "merda", "puta", "fdp", "vsf", "buceta", "arrombado", "fuck", "shit", "bitch", "cunt", "asshole", "nigger", "faggot"]

var port: int = 7350
var bind_address: String = "*"
var public_url: String = "ws://localhost:7350"
var server_name: String = "S1 · Nova Era"
var server_id: String = "s1"
var capacity: int = 500
var test_coupons: bool = false
var bot_fill_seconds: float = 20.0
# Docker stop: run-game.sh creates this file on SIGTERM (Godot ignores the signal).
var stop_file: String = ""
var tcp: TCPServer = TCPServer.new()
var api: ApiClient
var balance: Dictionary
var sessions: Dictionary = {}
var accounts: Dictionary = {}
var rooms: Dictionary = {}
var hosts: Dictionary = {}
var next_peer: int = 1
var next_match: int = 1
var chat_history: Array = []
var speaker: Dictionary = {}
var audit_queue: Array = []
var lobby_dirty: bool = true
var timers: Dictionary = {"lobby": 0.0, "search": 0.0, "save": 0.0, "heartbeat": 0.0, "audit": 0.0, "stop": 1.0}
var bots: LobbyDirectory
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var chat_filter: RegEx
var listening: bool = false
# Connections being closed: [peer, when, code, reason]. The close waits a moment so the
# last message (the reason) reaches the player first.
var closing: Array = []
var shutting_down: bool = false

static func setting(args: Dictionary, key: String, env_key: String, fallback: String) -> String:
	if args.has(key):
		return str(args[key])
	var value: String = OS.get_environment(env_key)
	return value if value != "" else fallback

func configure(args: Dictionary) -> void:
	port = int(setting(args, "port", "FT_PORT", "7350"))
	bind_address = setting(args, "bind", "FT_BIND", "*")
	public_url = setting(args, "public-url", "FT_PUBLIC_URL", "ws://localhost:%d" % port)
	server_name = setting(args, "name", "FT_NAME", "S1 · Nova Era")
	server_id = setting(args, "id", "FT_ID", "s1")
	capacity = int(setting(args, "capacity", "FT_CAPACITY", "500"))
	test_coupons = setting(args, "test-coupons", "FT_TEST_COUPONS", "0") == "1"
	bot_fill_seconds = float(setting(args, "bot-fill", "FT_BOT_FILL", "20"))
	stop_file = setting(args, "stop-file", "FT_STOP_FILE", "")
	api = ApiClient.new()
	api.base_url = setting(args, "api", "FT_API", "memory").trim_suffix("/")
	api.key = setting(args, "api-key", "FT_API_KEY", "")
	api.server_id = server_id

func _ready() -> void:
	# The server speaks Portuguese (the source language); players translate on their side.
	Lang.override = "pt_BR"
	Lang.setup()
	Engine.max_fps = 60
	rng.randomize()
	if api == null:
		configure({})
	add_child(api)
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	bots = LobbyDirectory.new()
	bots.rng.randomize()
	bots.populate()
	var words: PackedStringArray = PackedStringArray()
	for word in BLOCKED_WORDS:
		words.append(word)
	chat_filter = RegEx.create_from_string("(?i)\\b(" + "|".join(words) + ")\\b")
	var error: int = tcp.listen(port, bind_address)
	listening = error == OK
	if not listening:
		push_error("GameServer: cannot listen on port %d (%s)" % [port, error_string(error)])
		return
	get_tree().auto_accept_quit = false
	log_line("listening on %s:%d as %s (%s), api=%s, test coupons %s" % [bind_address, port, server_id, server_name, api.base_url, "on" if test_coupons else "off"])

func log_line(text: String) -> void:
	print("[%s] %s" % [Time.get_datetime_string_from_system(true), text])

func now() -> float:
	return Time.get_unix_time_from_system()

# ---------- connections ----------

func _process(delta: float) -> void:
	if not listening and not shutting_down:
		return
	while listening and tcp.is_connection_available():
		accept(tcp.take_connection())
	for session: PlayerSession in sessions.values():
		poll(session)
	for entry: Array in closing.duplicate():
		var peer: WebSocketPeer = entry[0]
		peer.poll()
		if now() >= float(entry[1]) and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.close(int(entry[2]), str(entry[3]))
		if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED or now() > float(entry[1]) + 5.0:
			closing.erase(entry)
	for key: String in timers:
		timers[key] -= delta
	if timers.lobby <= 0.0:
		timers.lobby = LOBBY_SECONDS
		if lobby_dirty:
			lobby_dirty = false
			broadcast_lobby()
	if timers.search <= 0.0:
		timers.search = 1.0
		matchmaking()
	if timers.save <= 0.0:
		timers.save = SAVE_SECONDS
		for session: PlayerSession in accounts.values():
			if session.dirty and not session.saving:
				save(session)
	if timers.heartbeat <= 0.0:
		timers.heartbeat = HEARTBEAT_SECONDS
		heartbeat()
	if timers.audit <= 0.0:
		timers.audit = AUDIT_SECONDS
		flush_audit()
	if timers.stop <= 0.0:
		timers.stop = 1.0
		if stop_file != "" and FileAccess.file_exists(stop_file):
			DirAccess.remove_absolute(stop_file)
			shutdown()

func accept(connection: StreamPeerTCP) -> void:
	var peer: WebSocketPeer = WebSocketPeer.new()
	peer.inbound_buffer_size = 65536
	peer.outbound_buffer_size = 1 << 20
	peer.max_queued_packets = 4096
	if peer.accept_stream(connection) != OK:
		return
	var session: PlayerSession = PlayerSession.new()
	session.peer = peer
	session.peer_id = next_peer
	next_peer += 1
	session.connected_at = now()
	session.last_seen = now()
	sessions[session.peer_id] = session

func poll(session: PlayerSession) -> void:
	var peer: WebSocketPeer = session.peer
	peer.poll()
	var ready_state: int = peer.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		while peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = peer.get_packet()
			if packet.size() > MAX_MESSAGE:
				peer.close(1009, "message too big")
				return
			handle(session, packet.get_string_from_utf8())
		if session.state == "handshake" and now() - session.connected_at > HELLO_SECONDS:
			peer.close(4000, "hello timeout")
		elif now() - session.last_seen > IDLE_SECONDS:
			peer.close(4001, "idle")
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		closed(session)
	elif ready_state == WebSocketPeer.STATE_CONNECTING and now() - session.connected_at > HELLO_SECONDS:
		peer.close()
		closed(session)

func reply(session: PlayerSession, request: Dictionary, data: Dictionary = {}) -> void:
	data.t = "reply"
	data.rid = request.get("rid", 0)
	data.ok = str(data.get("error", "")) == ""
	session.send(data)

func fail(session: PlayerSession, code: String) -> void:
	session.send({"t": "error", "error": code})
	session.state = "closing"
	close_later(session.peer, 4003, code)

func close_later(peer: WebSocketPeer, code: int, reason: String) -> void:
	closing.append([peer, now() + 0.3, code, reason])

func handle(session: PlayerSession, text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not message is Dictionary:
		return
	session.last_seen = now()
	var kind: String = str(message.get("t", ""))
	if session.state == "handshake":
		if kind == "hello":
			hello(session, message)
		return
	if session.state != "lobby":
		return
	match kind:
		"ping":
			reply(session, message, {"time": now()})
		"op":
			profile_op(session, message)
		"chat":
			chat(session, message)
		"lobby":
			session.watching_lobby = bool(message.get("on", true))
			if session.watching_lobby:
				session.send(lobby_snapshot())
		"room_create":
			room_create(session, message)
		"room_join":
			room_join(session, message)
		"room_leave":
			leave_room(session)
			reply(session, message)
		"room_set":
			room_set(session, message)
		"room_ready":
			room_ready(session, message)
		"room_kick":
			room_kick(session, message)
		"room_bot":
			room_bot(session, message)
		"room_start":
			room_start(session, message)
		"room_cancel":
			room_cancel(session, message)
		"in":
			if session.host != null:
				session.host.receive(session, message)
		"match_leave":
			leave_match(session)
			reply(session, message)
		"card":
			pick_card(session, message)
		"desync":
			audit(session, "desync", {"match": int(message.get("m", 0)), "tick": int(message.get("tick", 0))})
		"auction_search":
			auction_search(session, message)
		"auction_list":
			auction_list(session, message)
		"auction_buy":
			auction_buy(session, message)
		"auction_cancel":
			auction_cancel(session, message)
		"auction_mine":
			auction_mine(session, message)
		"auction_history":
			auction_history(session, message)
		"mail_list":
			mail_list(session, message)
		"mail_claim":
			mail_claim(session, message)
		"account_delete":
			account_delete(session, message)

# ---------- login ----------

func hello(session: PlayerSession, message: Dictionary) -> void:
	session.state = "joining"
	if int(message.get("protocol", 0)) != PROTOCOL or str(message.get("content", "")) != NetClient.content_version():
		fail(session, "outdated")
		return
	if accounts.size() >= capacity:
		fail(session, "server_full")
		return
	var account: Dictionary = await api.verify(str(message.get("token", "")))
	if account.has("error"):
		fail(session, str(account.error))
		return
	if not sessions.has(session.peer_id):
		return
	var existing: PlayerSession = accounts.get(int(account.id))
	if existing != null and existing.discard:
		# Its copy of the profile is being dropped (an unconfirmed auction operation):
		# this login waits until the stored profile can be read again.
		fail(session, "profile_conflict")
		return
	if existing != null:
		# The same account again (came back, or another window): the new connection wins.
		if existing.is_open():
			existing.send({"t": "error", "error": "logged_elsewhere"})
			sessions.erase(existing.peer_id)
			close_later(existing.peer, 4004, "logged_elsewhere")
		sessions.erase(session.peer_id)
		existing.peer = session.peer
		existing.peer_id = session.peer_id
		existing.connected_at = session.connected_at
		existing.last_seen = now()
		existing.lingering = false
		existing.state = "lobby"
		sessions[existing.peer_id] = existing
		welcome(existing)
		if existing.host != null:
			existing.host.resume(existing)
		log_line("account %d came back" % existing.account_id)
		return
	var holder: String = await api.claim(int(account.id))
	if holder != "":
		fail(session, holder)
		return
	var stored: Dictionary = await api.load_profile(int(account.id))
	if stored.has("error") or not sessions.has(session.peer_id):
		await api.release(int(account.id))
		if sessions.has(session.peer_id):
			fail(session, str(stored.get("error", "api_unavailable")))
		return
	var profile: PlayerProfile = PlayerProfile.new()
	var migrated: bool = false
	if stored.has("data") and stored.data is Dictionary:
		migrated = profile.load_data(stored.data)
		session.version = int(stored.version)
	session.account_id = int(account.id)
	session.username = str(account.username)
	session.profile = profile
	profile.on_save = mark_dirty.bind(session)
	session.state = "lobby"
	accounts[session.account_id] = session
	if migrated or session.version == 0:
		session.dirty = true
	welcome(session)
	lobby_dirty = true
	log_line("account %d (%s) logged in, %d online" % [session.account_id, session.username, accounts.size()])
	notify_mail(session)

func welcome(session: PlayerSession) -> void:
	var message: Dictionary = {"t": "welcome", "account": {"id": session.account_id, "username": session.username}, "profile": session.profile.to_data(), "server": {"id": server_id, "name": server_name}, "chat": chat_history.slice(-30), "speaker": speaker, "test_coupons": test_coupons}
	if session.room != null:
		message.room = session.room.details(balance)
	session.send(message)

func closed(session: PlayerSession) -> void:
	sessions.erase(session.peer_id)
	if session.account_id == 0 or accounts.get(session.account_id) != session:
		return
	if session.host != null and not session.host.over:
		# Mid-battle: the AI plays for them; the rewards still reach the profile.
		session.lingering = true
		session.host.dropped(session)
		lobby_dirty = true
		log_line("account %d dropped mid-battle" % session.account_id)
		return
	finalize(session)

# The player is gone for good: leave the room, deal the unpicked cards, save, and free
# the account for other servers.
func finalize(session: PlayerSession) -> void:
	if accounts.get(session.account_id) != session:
		return
	if session.room != null:
		leave_room(session)
	auto_pick(session)
	accounts.erase(session.account_id)
	lobby_dirty = true
	await flush_save(session)
	await api.release(session.account_id)
	log_line("account %d left, %d online" % [session.account_id, accounts.size()])

# ---------- profiles ----------

func mark_dirty(session: PlayerSession) -> void:
	session.dirty = true

func save(session: PlayerSession) -> void:
	if session.discard:
		return
	session.saving = true
	session.dirty = false
	var profile_name: Variant = session.profile.player_name if session.profile.created else null
	var result: Dictionary = await api.save_profile(session.account_id, profile_name, session.profile.to_data(), session.version)
	session.saving = false
	if result.has("version"):
		session.version = int(result.version)
		return
	match str(result.error):
		"name_taken":
			# Two players took the same name at once: this one chooses again.
			session.profile.created = false
			session.profile.player_name = "Explorador"
			session.dirty = true
			session.send({"t": "profile", "profile": session.profile.to_data(), "notice": Lang.t("Este nome já está em uso. Escolha outro.")})
		"version_conflict":
			# Someone else wrote this profile: never overwrite it; the player reconnects
			# and gets the stored copy.
			push_error("GameServer: profile %d changed elsewhere; disconnecting" % session.account_id)
			if session.is_open():
				fail(session, "profile_conflict")
		_:
			session.dirty = true

func flush_save(session: PlayerSession) -> void:
	# An auction operation finishes first (it writes the profile itself).
	var deadline: float = now() + 60.0
	while (session.saving or session.busy) and now() < deadline:
		await get_tree().process_frame
	if session.dirty and not session.discard:
		await save(session)

func profile_op(session: PlayerSession, message: Dictionary) -> void:
	var op: String = str(message.get("op", ""))
	var args: Variant = message.get("args", [])
	if not args is Array or not op in PlayerProfile.OPS:
		reply(session, message, {"error": Lang.t("Operação desconhecida.")})
		return
	if session.host != null:
		# The battle took a copy of the equipment and tools; changing them now would let
		# the end of the battle hand the tools back twice.
		reply(session, message, {"error": Lang.t("Você está numa batalha.")})
		return
	if session.busy:
		reply(session, message, {"error": Lang.t("Aguarde a operação anterior terminar.")})
		return
	if op == "create":
		var chosen: String = PlayerProfile.arg_str(args, 0).strip_edges()
		if PlayerProfile.valid_name(chosen) and not session.profile.created:
			var check: Dictionary = await api.name_taken(chosen, session.account_id)
			if check.has("error"):
				reply(session, message, {"error": Lang.t("Servidor indisponível. Tente de novo.")})
				return
			if bool(check.taken) or name_in_use(chosen, session):
				reply(session, message, {"error": Lang.t("Este nome já está em uso. Escolha outro.")})
				return
	var result: Dictionary = session.profile.apply_op(op, args, balance, test_coupons)
	audit(session, "op." + op, {"args": args, "error": result.error, "coins": session.profile.coins})
	reply(session, message, {"error": result.error, "message": result.message, "profile": session.profile.to_data()})
	if result.error == "":
		if session.room != null:
			broadcast_room(session.room)
		lobby_dirty = true

func name_in_use(chosen: String, session: PlayerSession) -> bool:
	for other: PlayerSession in accounts.values():
		if other != session and other.profile.created and other.profile.player_name.to_lower() == chosen.to_lower():
			return true
	return false

# ---------- chat ----------

func chat(session: PlayerSession, message: Dictionary) -> void:
	var text: String = str(message.get("text", "")).strip_edges().substr(0, 80)
	if text == "" or not session.profile.created:
		return
	var moment: float = now()
	session.chat_times = session.chat_times.filter(func(at: float) -> bool: return moment - at < 10.0)
	if session.chat_times.size() >= 5 or (not session.chat_times.is_empty() and moment - session.chat_times.back() < 0.8):
		session.send({"t": "chat", "message": {"author": "Sistema", "text": Lang.t("Calma! Aguarde um pouco para falar de novo."), "channel": "system"}})
		return
	session.chat_times.append(moment)
	text = filter_text(text)
	var entry: Dictionary = {"author": session.profile.player_name, "text": text, "channel": "Atual"}
	chat_history.append(entry)
	if chat_history.size() > CHAT_KEEP:
		chat_history.remove_at(0)
	for other: PlayerSession in accounts.values():
		if not other.lingering:
			other.send({"t": "chat", "message": entry})
	audit(session, "chat", {"text": text})

func filter_text(text: String) -> String:
	for found: RegExMatch in chat_filter.search_all(text):
		text = text.replace(found.get_string(), "*".repeat(found.get_string().length()))
	return text

func announce(text: String, args: Array = [], item: Dictionary = {}) -> void:
	# The alto-falante bar (rare drops and events). `item` (a dropped weapon) is named in
	# each player's language.
	var entry: Dictionary = {"author": "Sistema", "text": text, "args": args, "channel": "alto-falante"}
	if not item.is_empty():
		entry.item = item
	speaker = entry
	chat_history.append(entry)
	if chat_history.size() > CHAT_KEEP:
		chat_history.remove_at(0)
	for other: PlayerSession in accounts.values():
		if not other.lingering:
			other.send({"t": "chat", "message": entry, "speaker": entry})

# ---------- channel (Salão) ----------

func lobby_snapshot() -> Dictionary:
	var list: Array = []
	for room: ServerRoom in rooms.values():
		list.append(room.summary())
	var people: Array = []
	for session: PlayerSession in accounts.values():
		if not session.lingering and session.profile.created:
			people.append(session.public_info())
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
	return {"t": "lobby", "rooms": list, "players": people.slice(0, 200), "online": accounts.size()}

func broadcast_lobby() -> void:
	var snapshot: Dictionary = lobby_snapshot()
	for session: PlayerSession in accounts.values():
		if session.watching_lobby and not session.lingering:
			session.send(snapshot)

# ---------- rooms ----------

func new_room_id() -> int:
	var id: int = rng.randi_range(100, 999)
	while rooms.has(id):
		id = rng.randi_range(100, 999)
	return id

func room_create(session: PlayerSession, message: Dictionary) -> void:
	if session.host != null:
		reply(session, message, {"error": Lang.t("Você está numa batalha.")})
		return
	if session.room != null:
		leave_room(session)
	var room: ServerRoom = ServerRoom.new()
	room.id = new_room_id()
	room.mode = "pve" if str(message.get("mode", "pvp")) == "pve" else "pvp"
	room.title = Lang.t("Guerra de equipes, diversão sem limite")
	room.turn_seconds = int(balance.turn_seconds)
	if room.mode == "pve":
		room.instance = str(balance.instances[0].id)
		room.title = str(InstanceRun.instance_def(room.instance).name)
		room.turn_seconds = int(balance.pve.get("turn_seconds", 20))
	room.add(session)
	rooms[room.id] = room
	session.room = room
	reply(session, message, {"room": room.details(balance)})
	lobby_dirty = true

func room_join(session: PlayerSession, message: Dictionary) -> void:
	var room: ServerRoom = rooms.get(int(message.get("id", -1)))
	var error: String = ""
	if session.host != null:
		error = Lang.t("Você está numa batalha.")
	elif room == null:
		error = Lang.t("Sala não encontrada neste canal.")
	elif room.state != "waiting":
		error = Lang.t("A sala está em batalha. Escolha outra sala ou aguarde.")
	elif room.is_full():
		error = Lang.t("A sala está cheia.")
	if error != "":
		reply(session, message, {"error": error})
		return
	if session.room != null and session.room != room:
		leave_room(session)
	if room.index_of(session) < 0:
		room.add(session)
	session.room = room
	reply(session, message, {"room": room.details(balance)})
	broadcast_room(room)
	system_message(room, Lang.t("%s entrou na sala."), [session.profile.player_name])

func leave_room(session: PlayerSession, reason: String = "") -> void:
	var room: ServerRoom = session.room
	session.room = null
	if room == null:
		return
	if room.state == "searching":
		room.state = "waiting"
	var empty: bool = room.remove(session)
	if reason != "":
		session.send({"t": "room_left", "reason": reason})
	if empty:
		rooms.erase(room.id)
	else:
		broadcast_room(room)
		system_message(room, Lang.t("%s saiu da sala."), [session.profile.player_name])
	lobby_dirty = true

func broadcast_room(room: ServerRoom) -> void:
	var details: Dictionary = room.details(balance)
	for session: PlayerSession in room.humans():
		if not session.lingering:
			session.send({"t": "room", "room": details})
	lobby_dirty = true

# System lines travel as the Portuguese key plus its arguments: each player's game
# translates them.
func system_message(room: ServerRoom, text: String, args: Array = []) -> void:
	for session: PlayerSession in room.humans():
		session.send({"t": "chat", "message": {"author": "Sistema", "text": text, "args": args, "channel": "system"}})

func owned_room(session: PlayerSession, message: Dictionary) -> ServerRoom:
	var room: ServerRoom = session.room
	if room == null or room.owner_session() != session:
		reply(session, message, {"error": Lang.t("Somente o dono da sala pode fazer isso.")})
		return null
	if room.state == "playing":
		reply(session, message, {"error": Lang.t("A sala está em batalha.")})
		return null
	return room

func room_set(session: PlayerSession, message: Dictionary) -> void:
	var room: ServerRoom = owned_room(session, message)
	if room == null:
		return
	if room.state == "searching":
		room.state = "waiting"
	if message.has("map"):
		var wanted: String = str(message.map)
		if wanted == "":
			room.map = ""
		for entry: Dictionary in balance.maps:
			if entry.id == wanted and not entry.get("pve_only", false):
				room.map = wanted
	if message.has("turn_seconds"):
		var seconds: int = int(message.turn_seconds) if message.turn_seconds is float or message.turn_seconds is int else 0
		if balance.turn_seconds_options.map(func(value: float) -> int: return int(value)).has(seconds) and room.mode == "pvp":
			room.turn_seconds = seconds
	if message.has("instance") and room.mode == "pve":
		for entry: Dictionary in balance.instances:
			if entry.id == str(message.instance):
				room.instance = str(entry.id)
				room.title = str(entry.name)
				room.map_uid = -1
	if message.has("map_uid") and room.mode == "pve":
		var uid: int = int(message.map_uid) if message.map_uid is float or message.map_uid is int else -1
		var item: Dictionary = session.profile.find_map(uid)
		room.map_uid = uid if not item.is_empty() and str(item.instance) == room.instance else -1
	reply(session, message, {"room": room.details(balance)})
	broadcast_room(room)

func room_ready(session: PlayerSession, message: Dictionary) -> void:
	var room: ServerRoom = session.room
	var index: int = room.index_of(session) if room != null else -1
	if index < 0 or room.state == "playing":
		reply(session, message, {"error": Lang.t("Você não está numa sala.")})
		return
	room.members[index].ready = bool(message.get("on", true))
	if not room.members[index].ready and room.state == "searching":
		room.state = "waiting"
	reply(session, message)
	broadcast_room(room)

func room_kick(session: PlayerSession, message: Dictionary) -> void:
	var room: ServerRoom = owned_room(session, message)
	if room == null:
		return
	var index: int = int(message.get("index", -1)) if message.get("index") is float or message.get("index") is int else -1
	if index < 0 or index >= room.members.size() or index == room.owner:
		reply(session, message, {"error": Lang.t("Jogador não encontrado.")})
		return
	var member: Dictionary = room.members[index]
	if member.has("session"):
		leave_room(member.session, "kicked")
	else:
		room.members.remove_at(index)
		if index < room.owner:
			room.owner -= 1
		broadcast_room(room)
	reply(session, message)

func room_bot(session: PlayerSession, message: Dictionary) -> void:
	var room: ServerRoom = owned_room(session, message)
	if room == null:
		return
	if room.is_full():
		reply(session, message, {"error": Lang.t("Não há vagas livres na sua equipe.")})
		return
	var names: Array = room.members.map(func(member: Dictionary) -> String: return str(member.session.profile.player_name if member.has("session") else member.bot.name))
	room.members.append({"bot": bots.bot_near(room.average_level(), names)})
	reply(session, message)
	broadcast_room(room)

func room_start(session: PlayerSession, message: Dictionary) -> void:
	var room: ServerRoom = owned_room(session, message)
	if room == null:
		return
	if not room.all_ready():
		reply(session, message, {"error": Lang.t("Todos os jogadores precisam estar preparados.")})
		return
	if room.mode == "pve":
		if session.busy:
			# The map in the slot must not change hands while the auction runs.
			reply(session, message, {"error": Lang.t("Aguarde a operação anterior terminar.")})
			return
		reply(session, message)
		start_expedition(room)
		return
	room.state = "searching"
	room.search_since = now()
	reply(session, message)
	broadcast_room(room)

func room_cancel(session: PlayerSession, message: Dictionary) -> void:
	var room: ServerRoom = session.room
	if room != null and room.state == "searching":
		room.state = "waiting"
		broadcast_room(room)
	reply(session, message)

# ---------- battles ----------

func entries(room: ServerRoom) -> Array:
	var team: Array = []
	for member: Dictionary in room.members:
		if member.has("session"):
			var entry: Dictionary = member.session.profile.entry(balance)
			entry.account = member.session.account_id
			team.append(entry)
		else:
			team.append(member.bot.duplicate(true))
	return team

# Pairs rooms that are searching: same team size and close levels (the margin grows with
# the wait); after `bot_fill_seconds` alone, AI rivals fill in, as offline.
func matchmaking() -> void:
	var searching: Array = rooms.values().filter(func(room: ServerRoom) -> bool: return room.state == "searching")
	for room: ServerRoom in searching:
		if room.state != "searching":
			continue
		var waited: float = now() - room.search_since
		for other: ServerRoom in searching:
			if other == room or other.state != "searching" or other.members.size() != room.members.size():
				continue
			if absi(other.average_level() - room.average_level()) <= 5 + int(waited / 2.0):
				start_pvp(room, other)
				break
		if room.state == "searching" and waited >= bot_fill_seconds:
			start_pvp(room, null)

func start_pvp(room: ServerRoom, rival: ServerRoom) -> void:
	var team: Array = entries(room)
	var rivals: Array = []
	if rival != null:
		rivals = entries(rival)
	else:
		var names: Array = team.map(func(entry: Dictionary) -> String: return str(entry.name))
		for i in range(team.size()):
			var bot: Dictionary = bots.bot_near(room.average_level(), names)
			names.append(bot.name)
			rivals.append(bot)
	var map: String = room.map if room.map != "" or rival == null else rival.map
	var config: Dictionary = {"mode": "pvp", "map": map, "turn_seconds": room.turn_seconds, "teams": [team, rivals]}
	var joined: Array[ServerRoom] = [room]
	if rival != null:
		joined.append(rival)
	launch(joined, config, null)

func start_expedition(room: ServerRoom) -> void:
	var owner: PlayerSession = room.owner_session()
	var item: Dictionary = owner.profile.find_map(room.map_uid).duplicate(true)
	if not item.is_empty():
		# The map is consumed on entry, as offline.
		owner.profile.remove_map(int(item.uid))
		owner.profile.save_profile()
		audit(owner, "map_used", {"map": item})
		owner.send({"t": "profile", "profile": owner.profile.to_data()})
	room.map_uid = -1
	var team: Array = entries(room)
	var profiles: Dictionary = {}
	for session: PlayerSession in room.humans():
		profiles[session.account_id] = session.profile
	var expedition: Expedition = Expedition.new(balance, room.instance, item, team, profiles)
	launch([room], expedition.phase_config(), expedition)

func launch(joined: Array[ServerRoom], config: Dictionary, expedition: Expedition) -> void:
	var host: MatchHost = MatchHost.new()
	host.match_id = next_match
	next_match += 1
	host.name = "Match_%d" % host.match_id
	add_child(host)
	hosts[host.match_id] = host
	var players: Dictionary = {}
	for room: ServerRoom in joined:
		room.state = "playing"
		room.host = host
		for session: PlayerSession in room.humans():
			players[session.account_id] = session
	host.set_meta("rooms", joined)
	host.begin(self, joined[0], players, config, expedition)
	for room: ServerRoom in joined:
		broadcast_room(room)
	log_line("match %d started: %s, %d players" % [host.match_id, str(config.get("mode", "pvp")), players.size()])

func leave_match(session: PlayerSession) -> void:
	var host: MatchHost = session.host
	if host == null:
		return
	host.left(session)
	leave_room(session)
	if host.connected_players() == 0 and not host.over:
		# Nobody is left at the controls: stop without rewards.
		host.over = true
		match_over(host)

func match_over(host: MatchHost) -> void:
	for room: ServerRoom in host.get_meta("rooms", []):
		room.host = null
		if rooms.get(room.id) == room:
			room.state = "waiting"
			for member: Dictionary in room.members:
				member.erase("ready")
			broadcast_room(room)
	for session: PlayerSession in host.players.values():
		if session.host == host:
			session.host = null
		if session.lingering:
			finalize(session)
	hosts.erase(host.match_id)
	get_tree().create_timer(CARD_SECONDS).timeout.connect(auto_pick_match.bind(host.match_id))
	host.queue_free()
	lobby_dirty = true
	log_line("match %d over" % host.match_id)

# ---------- reward cards ----------

func pick_card(session: PlayerSession, message: Dictionary) -> void:
	var result: Dictionary = session.result
	var index: int = int(message.get("i", -1)) if message.get("i") is float or message.get("i") is int else -1
	if result.is_empty() or int(result.picks) <= 0 or index < 0 or index >= (result.cards as Array).size() or (result.revealed as Array).has(index):
		reply(session, message, {"error": Lang.t("Carta indisponível.")})
		return
	var reward: Dictionary = grant_card(session, index)
	reply(session, message, {"reward": reward, "picks": int(result.picks), "profile": session.profile.to_data()})
	if int(result.picks) <= 0:
		reveal_cards(session)

func grant_card(session: PlayerSession, index: int) -> Dictionary:
	var result: Dictionary = session.result
	var reward: Dictionary = result.cards[index]
	Rewards.grant(session.profile, reward)
	result.revealed.append(index)
	result.picks = int(result.picks) - 1
	audit(session, "card", {"match": int(result.match), "reward": reward})
	return reward

func reveal_cards(session: PlayerSession) -> void:
	var result: Dictionary = session.result
	session.send({"t": "cards", "m": int(result.match), "cards": result.cards, "picked": result.revealed, "profile": session.profile.to_data()})
	session.result = {}

# Picks for whoever did not (closed the window, took too long), so no reward is lost.
func auto_pick(session: PlayerSession) -> void:
	var result: Dictionary = session.result
	if result.is_empty():
		return
	while int(result.picks) > 0:
		var hidden: Array = []
		for i in range((result.cards as Array).size()):
			if not (result.revealed as Array).has(i):
				hidden.append(i)
		if hidden.is_empty():
			break
		grant_card(session, int(hidden[rng.randi() % hidden.size()]))
	reveal_cards(session)

func auto_pick_match(match_id: int) -> void:
	for session: PlayerSession in accounts.values():
		if not session.result.is_empty() and int(session.result.get("match", -1)) == match_id:
			auto_pick(session)

# ---------- leilão (0.12) ----------

static func number(message: Dictionary, key: String, fallback: int = -1) -> int:
	var value: Variant = message.get(key)
	return int(clampf(float(value), -1.0, 1.0e9)) if value is int or value is float else fallback

func trade_guard(session: PlayerSession) -> String:
	if session.host != null:
		return Lang.t("Você está numa batalha.")
	if not session.profile.created:
		return Lang.t("Crie o seu personagem primeiro.")
	if session.busy:
		return Lang.t("Aguarde a operação anterior terminar.")
	return ""

# One auction operation at a time per player, and the periodic save waits: the
# operation writes the profile itself, with the version it read.
func begin_trade(session: PlayerSession) -> void:
	session.busy = true
	var deadline: float = now() + 30.0
	while session.saving and now() < deadline:
		await get_tree().process_frame
	session.saving = true

func end_trade(session: PlayerSession) -> void:
	session.saving = false
	session.busy = false

func new_op_id(session: PlayerSession) -> String:
	return "%s-%d-%d-%d" % [server_id, session.account_id, Time.get_ticks_usec(), rng.randi()]

# The profile as it goes to the API with the operation. Changes made from here on (a card
# picked meanwhile) mark it dirty again and are saved after, with the new version.
func profile_write(session: PlayerSession) -> Dictionary:
	session.dirty = false
	return {"name": session.profile.player_name if session.profile.created else null, "data": session.profile.to_data(), "version": session.version}

# Calls the API; an answer that may have been lost is tried again with the same op id
# (the API runs each op once). If it stays unknown, or the profile changed elsewhere,
# this copy of the profile can no longer be trusted: the player is disconnected without
# saving and the next login reads what the database has.
func trade_call(session: PlayerSession, call: Callable) -> Dictionary:
	var result: Dictionary = {}
	for attempt in range(3):
		result = await call.call()
		if not result.has("unsure"):
			break
		await get_tree().create_timer(1.0 + attempt).timeout
	if result.has("unsure") or str(result.get("error", "")) == "version_conflict":
		push_error("GameServer: auction operation of %d unconfirmed (%s); reloading the profile" % [session.account_id, str(result.get("error", ""))])
		session.discard = true
		if session.is_open():
			fail(session, "profile_conflict")
	return result

func trade_error(result: Dictionary) -> String:
	return Lang.t(Auction.error_text(str(result.get("error", ""))))

func auction_search(session: PlayerSession, message: Dictionary) -> void:
	if now() - session.last_search < 0.3:
		reply(session, message, {"error": Lang.t("Aguarde um instante para buscar de novo.")})
		return
	session.last_search = now()
	var filter: Dictionary = Auction.clean_filter(message.get("filter", {}))
	var result: Dictionary = await api.auction_search(filter)
	if result.has("error"):
		reply(session, message, {"error": trade_error(result)})
		return
	reply(session, message, {"listings": result.listings, "total": int(result.total), "now": int(result.now), "page": int(filter.page)})

func auction_list(session: PlayerSession, message: Dictionary) -> void:
	var kind: String = "map" if str(message.get("kind", "")) == "map" else "item"
	var uid: int = number(message, "uid")
	var solar: int = number(message, "solar", 0)
	var estrela: int = number(message, "estrela", 0)
	var hours: int = number(message, "hours")
	var error: String = trade_guard(session)
	if error == "":
		error = Auction.listing_reason(session.profile, kind, uid, solar, estrela, hours)
	if error != "":
		reply(session, message, {"error": error})
		return
	await begin_trade(session)
	var taken: Dictionary = Auction.take(session.profile, kind, uid, hours)
	var listing: Dictionary = Auction.fields(kind, taken.item)
	listing.merge({"price_solar": solar, "price_estrela": estrela, "fee_solar": Auction.commission(solar), "fee_estrela": Auction.commission(estrela), "hours": hours})
	var result: Dictionary = await trade_call(session, api.auction_create.bind(new_op_id(session), session.account_id, profile_write(session), listing, Auction.max_listings()))
	if result.has("error"):
		if not session.discard:
			Auction.put_back(session.profile, taken)
			session.dirty = true
		end_trade(session)
		reply(session, message, {"error": trade_error(result), "profile": session.profile.to_data()})
		return
	session.version = int(result.version)
	end_trade(session)
	log_line("account %d listed %s %s for %s" % [session.account_id, kind, str(listing.item_id), Auction.price_text(solar, estrela)])
	reply(session, message, {"listing": result.listing, "profile": session.profile.to_data()})
	after_trade(session)

func auction_buy(session: PlayerSession, message: Dictionary) -> void:
	var id: int = number(message, "id")
	var solar: int = number(message, "solar")
	var estrela: int = number(message, "estrela")
	var error: String = trade_guard(session)
	if error == "" and (id <= 0 or solar < 0 or estrela < 0 or solar + estrela <= 0):
		error = Lang.t("Este anúncio não está mais à venda.")
	if error == "" and (session.profile.currency_count("solar") < solar or session.profile.currency_count("estrela") < estrela):
		error = Lang.t("Você não tem Solares e Estrelas suficientes.")
	if error != "":
		reply(session, message, {"error": error})
		return
	await begin_trade(session)
	var profile: PlayerProfile = session.profile
	profile.items["solar"] = profile.currency_count("solar") - solar
	profile.items["estrela"] = profile.currency_count("estrela") - estrela
	var result: Dictionary = await trade_call(session, api.auction_buy.bind(new_op_id(session), session.account_id, id, solar, estrela, profile_write(session)))
	if result.has("error"):
		if not session.discard:
			profile.items["solar"] = profile.currency_count("solar") + solar
			profile.items["estrela"] = profile.currency_count("estrela") + estrela
			session.dirty = true
		end_trade(session)
		reply(session, message, {"error": trade_error(result), "profile": profile.to_data()})
		return
	session.version = int(result.version)
	log_line("account %d bought listing %d for %s" % [session.account_id, id, Auction.price_text(solar, estrela)])
	# The item came by mail: it goes into the Mochila at once.
	var received: Dictionary = await claim_mail(session, [int(result.mail_id)])
	end_trade(session)
	reply(session, message, {"listing": result.listing, "received": not received.has("error"), "profile": profile.to_data()})
	var seller: PlayerSession = accounts.get(int(result.get("seller_id", 0)) if result.get("seller_id") != null else 0)
	if seller != null:
		notify_mail(seller)
	after_trade(session)

func auction_cancel(session: PlayerSession, message: Dictionary) -> void:
	var id: int = number(message, "id")
	var error: String = trade_guard(session)
	if error != "":
		reply(session, message, {"error": error})
		return
	await begin_trade(session)
	var result: Dictionary = await trade_call(session, api.auction_cancel.bind(new_op_id(session), session.account_id, id))
	if result.has("error"):
		end_trade(session)
		reply(session, message, {"error": trade_error(result)})
		return
	var received: Dictionary = await claim_mail(session, [int(result.mail_id)])
	end_trade(session)
	reply(session, message, {"listing": result.listing, "received": not received.has("error"), "profile": session.profile.to_data()})
	after_trade(session)

func auction_mine(session: PlayerSession, message: Dictionary) -> void:
	var result: Dictionary = await api.auction_mine(session.account_id)
	if result.has("error"):
		reply(session, message, {"error": trade_error(result)})
		return
	reply(session, message, {"active": result.active, "closed": result.closed, "now": int(result.now), "max": Auction.max_listings()})

func auction_history(session: PlayerSession, message: Dictionary) -> void:
	var kind: String = "map" if str(message.get("kind", "")) == "map" else "item"
	var item: Variant = message.get("item", {})
	var clean: Dictionary = PlayerProfile.clean_map(item) if kind == "map" else PlayerProfile.clean_instance(item)
	if clean.is_empty():
		reply(session, message, {"error": Lang.t("Item não encontrado.")})
		return
	var result: Dictionary = await api.auction_history(Auction.history_query(kind, clean))
	if result.has("error"):
		reply(session, message, {"error": trade_error(result)})
		return
	reply(session, message, {"sales": result.sales, "now": int(result.now)})

func mail_list(session: PlayerSession, message: Dictionary) -> void:
	var result: Dictionary = await api.mail_list(session.account_id)
	if result.has("error"):
		reply(session, message, {"error": trade_error(result)})
		return
	reply(session, message, {"mail": result.mail, "total": int(result.total), "now": int(result.now)})

func mail_claim(session: PlayerSession, message: Dictionary) -> void:
	var error: String = trade_guard(session)
	if error != "":
		reply(session, message, {"error": error})
		return
	var ids: Array = []
	var wanted: Variant = message.get("ids", [])
	if wanted is Array:
		for value: Variant in wanted:
			if (value is int or value is float) and not ids.has(int(value)):
				ids.append(int(value))
	await begin_trade(session)
	var result: Dictionary = await claim_mail(session, ids)
	end_trade(session)
	if result.has("error"):
		reply(session, message, {"error": trade_error(result), "profile": session.profile.to_data()})
		return
	reply(session, message, {"claimed": result.claimed, "profile": session.profile.to_data()})
	after_trade(session)

# Puts mail into the profile and marks it received, together (inside a trade). No ids =
# everything waiting (up to 100 letters).
func claim_mail(session: PlayerSession, ids: Array) -> Dictionary:
	var listed: Dictionary = await api.mail_list(session.account_id)
	if listed.has("error"):
		return listed
	var chosen: Array = []
	for mail: Variant in listed.mail:
		if mail is Dictionary and (ids.is_empty() or ids.has(int(mail.id))):
			chosen.append(mail)
	if chosen.is_empty() or (not ids.is_empty() and chosen.size() != ids.size()):
		return {"error": "mail_gone"}
	var undo: Array = []
	var chosen_ids: Array = []
	for mail: Dictionary in chosen:
		undo.append(Auction.grant_mail(session.profile, mail))
		chosen_ids.append(int(mail.id))
	var result: Dictionary = await trade_call(session, api.mail_claim.bind(new_op_id(session), session.account_id, chosen_ids, profile_write(session)))
	if result.has("error"):
		if not session.discard:
			for step: Dictionary in undo:
				Auction.undo_mail(session.profile, step)
			session.dirty = true
		return result
	session.version = int(result.version)
	return {"claimed": chosen_ids}

func after_trade(session: PlayerSession) -> void:
	if session.room != null:
		broadcast_room(session.room)
	notify_mail(session)

# Tells the player how many letters wait in the Correio.
func notify_mail(session: PlayerSession) -> void:
	var result: Dictionary = await api.mail_list(session.account_id)
	if not result.has("error") and session.is_open():
		session.send({"t": "mail", "count": int(result.total)})

# ---------- privacy (LGPD/GDPR) ----------

# The player deletes the account from inside the game, with the password. The periodic
# save stops first (as in an auction operation) so the profile is never written back;
# once the API has deleted everything, this copy is dropped and the connection closes.
func account_delete(session: PlayerSession, message: Dictionary) -> void:
	var password: String = str(message.get("password", "")).substr(0, 128)
	if session.host != null:
		reply(session, message, {"error": Lang.t("Saia da batalha antes de excluir a conta.")})
		return
	if session.busy:
		reply(session, message, {"error": Lang.t("Aguarde a operação anterior terminar.")})
		return
	if password == "":
		reply(session, message, {"error": Lang.t("Digite a sua senha.")})
		return
	var moment: float = now()
	session.delete_tries = session.delete_tries.filter(func(at: float) -> bool: return moment - at < 600.0)
	if session.delete_tries.size() >= 5:
		reply(session, message, {"error": Lang.t("Muitas tentativas. Aguarde alguns minutos.")})
		return
	session.delete_tries.append(moment)
	await begin_trade(session)
	var result: Dictionary = await api.delete_account(session.account_id, password)
	if result.has("error"):
		end_trade(session)
		var wrong: bool = str(result.error) == "invalid_credentials"
		reply(session, message, {"error": Lang.t("Senha incorreta.") if wrong else Lang.t("Não foi possível excluir a conta agora. Tente de novo.")})
		return
	# Deleted: nothing of this player is saved or logged again.
	session.discard = true
	var gone: int = session.account_id
	audit_queue = audit_queue.filter(func(entry: Dictionary) -> bool: return entry.account_id == null or int(entry.account_id) != gone)
	if session.room != null:
		leave_room(session)
	session.result = {}
	accounts.erase(gone)
	lobby_dirty = true
	reply(session, message)
	session.state = "closing"
	close_later(session.peer, 4005, "account_deleted")
	log_line("account %d deleted by the player, %d online" % [gone, accounts.size()])

# ---------- API upkeep ----------

func audit(session: PlayerSession, kind: String, detail: Dictionary) -> void:
	audit_queue.append({"account_id": session.account_id if session != null and session.account_id > 0 else null, "kind": kind, "detail": detail})
	if audit_queue.size() > 5000:
		audit_queue = audit_queue.slice(-5000)

func flush_audit() -> void:
	if audit_queue.is_empty():
		return
	var batch: Array = audit_queue.slice(0, 200)
	audit_queue = audit_queue.slice(200)
	if not await api.audit(batch):
		audit_queue = batch + audit_queue

func heartbeat() -> void:
	var online: Array = []
	for account: int in accounts:
		online.append(account)
	await api.heartbeat({"id": server_id, "name": server_name, "url": public_url, "online": accounts.size(), "capacity": capacity}, online)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and listening:
		shutdown()

# Saves everyone and frees their accounts before quitting (SIGTERM / docker stop).
func shutdown() -> void:
	if shutting_down:
		return
	shutting_down = true
	listening = false
	tcp.stop()
	log_line("shutting down, saving %d profiles" % accounts.size())
	for session: PlayerSession in accounts.values():
		auto_pick(session)
		if session.is_open():
			session.send({"t": "error", "error": "server_closing"})
	for session: PlayerSession in accounts.values():
		await flush_save(session)
		await api.release(session.account_id)
	await flush_audit()
	get_tree().quit()
