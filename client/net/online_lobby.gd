class_name OnlineLobby
extends LobbyDirectory

# The channel of a real game server, in place of the simulated LobbyDirectory: the rooms
# and players come from the server's "lobby" messages and the chat is the players'.

var net: NetClient
var my_name: String = ""

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass

func post(author: String, text: String, channel: String = "Atual") -> void:
	if author == my_name and channel in ["Atual", "Privado"]:
		# The server sends it back to everyone (us included), filtered.
		net.send_kind("chat", {"text": text})
		return
	super.post(author, text, channel)

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
	super.post(str(entry.get("author", "")), text_of(entry), str(entry.get("channel", "Atual")))

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
