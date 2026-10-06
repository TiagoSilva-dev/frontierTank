class_name OnlineLobby
extends LobbyDirectory

# The channel of a real game server, in place of the simulated LobbyDirectory: the rooms
# and players come from the server's "lobby" messages and the chat is the players'.

var net: NetClient

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass

func post(author: String, text: String, channel: String = "Atual", extra: Dictionary = {}) -> void:
	if author == my_name and channel == "Atual" and not extra.has("id"):
		# The server sends it back to everyone (us included), filtered. (Lines that came from
		# the server carry their id; the badge flag of the chat box does not make it local.)
		net.send_kind("chat", {"text": text})
		return
	super.post(author, text, channel, extra)

func whisper(target: Dictionary, text: String, _my_name: String) -> void:
	# The server sends the line back to both players (it carries the receiver's name).
	net.send_kind("whisper", {"account": int(target.get("account", 0)), "name": str(target.get("name", "")), "text": text})

# The profile window of a player online: the server tells what the others may see.
func profile_of(person: Dictionary) -> Dictionary:
	# A simulated player has no account: the server finds it by name.
	var reply: Dictionary = await net.request("player_profile", {"account": int(person.get("account", 0)), "name": str(person.get("name", ""))})
	if reply.get("info") is Dictionary:
		return reply.info
	return {"error": str(reply.get("error", "offline"))}

# Lines from the server itself (joins, drops, the alto-falante) come as a Portuguese key
# with arguments and are translated here; what players write is shown as written.
static func text_of(entry: Dictionary) -> String:
	var text: String = str(entry.get("text", ""))
	if str(entry.get("author", "")) != "Sistema":
		return text
	var args: Array = (entry.get("args", []) as Array).duplicate()
	if entry.get("item") is Dictionary:
		args.append(Armory.item_name(entry.item))
	text = Lang.t(text)
	return text % args if not args.is_empty() and text.count("%s") + text.count("%d") == args.size() else text

func add(entry: Dictionary) -> void:
	var extra: Dictionary = {}
	if entry.has("id") and entry.has("account"):
		extra = {"id": int(entry.id), "account": int(entry.account)}
	if entry.has("to"):
		extra["to"] = str(entry.to)
	super.post(str(entry.get("author", "")), text_of(entry), str(entry.get("channel", "Atual")), extra)

func receive(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"chat":
			add(message.get("message", {}))
			if message.get("speaker") is Dictionary:
				speaker = text_of(message.speaker)
		"lobby":
			rooms.clear()
			for room: Variant in message.get("rooms", []):
				if room is Dictionary:
					rooms.append(room)
			bots.clear()
			for person: Variant in message.get("players", []):
				if person is Dictionary and int(person.get("account", 0)) != int(net.account.get("id", -1)):
					bots.append(person)
			rooms_changed.emit()
