class_name FriendBook
extends RefCounted

# The friends list of the player menu (click a name in the channel list or in the chat).
# It lives apart from the profile, in user://friends.json: a convenience of this computer,
# kept per mode (the offline channel, or one online account), so the simulated players of
# the offline channel never show up in an online list. Names are unique in the game, so a
# friend is its name; the account and level are refreshed whenever the player is seen.

const PATH: String = "user://friends.json"
const MAX_FRIENDS: int = 100

var path: String = PATH
var scope: String = "offline"
var friends: Array[Dictionary] = []

func use_scope(value: String) -> void:
	scope = value
	load_book()

func load_book() -> void:
	friends.clear()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var rows: Variant = (parsed as Dictionary).get(scope, [])
	if not rows is Array:
		return
	for row: Variant in rows:
		if row is Dictionary and str(row.get("name", "")) != "":
			friends.append({"name": str(row.name), "account": int(row.get("account", 0)), "level": int(row.get("level", 1)), "gender": str(row.get("gender", "m"))})

func save_book() -> void:
	var all: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			all = parsed
	all[scope] = friends
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all))

func index_of(name_value: String) -> int:
	for i in range(friends.size()):
		if friends[i].name == name_value:
			return i
	return -1

func has(name_value: String) -> bool:
	return index_of(name_value) >= 0

# "" when added, otherwise the reason (Portuguese text, translated by the caller).
func add(person: Dictionary) -> String:
	var name_value: String = str(person.get("name", ""))
	if name_value == "":
		return "Jogador inválido."  # i18n
	if has(name_value):
		return "Vocês já são amigos."  # i18n
	if friends.size() >= MAX_FRIENDS:
		return "Sua lista de amigos está cheia."  # i18n
	friends.append({"name": name_value, "account": int(person.get("account", 0)), "level": int(person.get("level", 1)), "gender": str(person.get("gender", "m"))})
	save_book()
	return ""

func remove(name_value: String) -> void:
	var index: int = index_of(name_value)
	if index >= 0:
		friends.remove_at(index)
		save_book()

# Keeps the stored level/account of the friends who are on the list of players right now.
func refresh(people: Array) -> void:
	var changed: bool = false
	for person: Variant in people:
		if not person is Dictionary:
			continue
		var index: int = index_of(str(person.get("name", "")))
		if index < 0:
			continue
		var entry: Dictionary = friends[index]
		if int(entry.level) != int(person.get("level", entry.level)) or int(entry.account) != int(person.get("account", entry.account)):
			entry.level = int(person.get("level", entry.level))
			entry.account = int(person.get("account", entry.account))
			changed = true
	if changed:
		save_book()
