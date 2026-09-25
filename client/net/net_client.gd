class_name NetClient
extends Node

# The player's connection to the game server (backend 0.11): one WebSocket with JSON
# messages. `request` waits for the server's reply to a message; everything else the
# server sends arrives through `event`. Login happens on the API first (AuthClient); the
# token is then presented in "hello".

signal event(message: Dictionary)
signal closed(reason: String)

const PROTOCOL: int = 1
const GAME_VERSION: String = "0.12"
const PING_SECONDS: float = 5.0

var socket: WebSocketPeer
var state: String = "offline"
var next_rid: int = 1
var replies: Dictionary = {}
var handshake: Dictionary = {}
var ping_timer: float = 0.0
var ping_sent: Dictionary = {}
var rtt: float = 0.0
var close_reason: String = ""
var closing_on_purpose: bool = false
var account: Dictionary = {}
# While logging in, messages after the welcome wait until the game has switched to
# online mode (release_held), so none is lost (e.g. a battle to go back to).
var hold: bool = false
var held: Array = []

# Server and players must run the same rules: game version, protocol and the balance
# files (parsed and written back sorted, so line endings and spacing do not matter).
static func content_version() -> String:
	var text: String = ""
	for path: String in ["res://shared/balance/combat.json", "res://shared/balance/items.json"]:
		text += JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string(path)), "", true)
	return "%s-%d-%s" % [GAME_VERSION, PROTOCOL, text.sha256_text().substr(0, 16)]

func is_online() -> bool:
	return state == "online"

# Connects and logs in; returns "" or an error code ("unreachable", "outdated",
# "unauthorized", "online_elsewhere", "server_full", "timeout"...).
func connect_to(url: String, token: String) -> String:
	disconnect_now()
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 4 << 20
	socket.outbound_buffer_size = 1 << 16
	socket.max_queued_packets = 8192
	closing_on_purpose = false
	close_reason = ""
	handshake = {}
	hold = true
	held.clear()
	if socket.connect_to_url(url) != OK:
		return "unreachable"
	state = "connecting"
	var deadline: int = Time.get_ticks_msec() + 8000
	while socket != null and socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		disconnect_now()
		return "unreachable"
	state = "joining"
	send({"t": "hello", "token": token, "protocol": PROTOCOL, "content": content_version(), "locale": Lang.locale()})
	deadline = Time.get_ticks_msec() + 15000
	while handshake.is_empty() and Time.get_ticks_msec() < deadline and state == "joining":
		await get_tree().process_frame
	if handshake.get("t", "") != "welcome":
		var code: String = str(handshake.get("error", close_reason if close_reason != "" else "timeout"))
		disconnect_now()
		return code
	state = "online"
	account = handshake.account
	return ""

func welcome() -> Dictionary:
	return handshake

func disconnect_now() -> void:
	if socket != null and socket.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]:
		closing_on_purpose = true
		socket.close(1000, "bye")
	socket = null
	state = "offline"
	replies.clear()
	ping_sent.clear()

func send(message: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))

func send_kind(kind: String, data: Dictionary = {}) -> void:
	var message: Dictionary = data.duplicate()
	message.t = kind
	send(message)

# Sends a message and waits for the server's reply: {"ok": bool, "error": ..., ...}.
func request(kind: String, data: Dictionary = {}, timeout: float = 10.0) -> Dictionary:
	if state != "online":
		return {"ok": false, "error": "offline"}
	var rid: int = next_rid
	next_rid += 1
	var message: Dictionary = data.duplicate()
	message.t = kind
	message.rid = rid
	replies[rid] = {}
	send(message)
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000)
	while (replies.get(rid, {}) as Dictionary).is_empty():
		if state != "online" or Time.get_ticks_msec() > deadline or not replies.has(rid):
			replies.erase(rid)
			return {"ok": false, "error": "timeout" if state == "online" else "offline"}
		await get_tree().process_frame
	var reply: Dictionary = replies[rid]
	replies.erase(rid)
	return reply

func _process(delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	while socket.get_available_packet_count() > 0:
		var message: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if message is Dictionary:
			receive(message)
	if socket == null:
		return
	var ready_state: int = socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_CLOSED:
		if close_reason == "" and socket.get_close_code() >= 4000:
			# The server's reason ("unauthorized", "outdated"...) travels in the close frame too.
			close_reason = socket.get_close_reason()
		var reason: String = close_reason if close_reason != "" else ("closed" if socket.get_close_code() in [1000, 1001] else "connection_lost")
		var was_online: bool = state == "online"
		socket = null
		state = "offline"
		if was_online and not closing_on_purpose:
			closed.emit(reason)
		return
	if state == "online":
		ping_timer -= delta
		if ping_timer <= 0.0:
			ping_timer = PING_SECONDS
			var rid: int = next_rid
			next_rid += 1
			ping_sent[rid] = Time.get_ticks_msec()
			send({"t": "ping", "rid": rid})

func receive(message: Dictionary) -> void:
	var kind: String = str(message.get("t", ""))
	if kind == "reply":
		var rid: int = int(message.get("rid", 0))
		if ping_sent.has(rid):
			rtt = (Time.get_ticks_msec() - int(ping_sent[rid])) / 1000.0
			ping_sent.erase(rid)
		elif replies.has(rid):
			replies[rid] = message
		return
	if state == "joining" and kind in ["welcome", "error"]:
		handshake = message
		return
	if kind == "error":
		close_reason = str(message.get("error", ""))
	if hold:
		held.append(message)
		return
	event.emit(message)

func release_held() -> void:
	hold = false
	var pending: Array = held
	held = []
	for message: Dictionary in pending:
		event.emit(message)
