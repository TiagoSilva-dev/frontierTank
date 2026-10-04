class_name Replay
extends RefCounted

# Replays (0.22). A battle is a pure function of its configuration (map, seed, fighters)
# and the intents the players sent, stamped with the tick they took effect: that is all
# that crosses the network in lockstep, so a replay is just those two things. It is saved
# on the player's computer (the last battles played online and the runs of the daily
# challenge), played back by a driver that feeds the intents to a fresh LocalMatch, and
# re-run on the server to check a challenge score without trusting the client.
#
# A replay is a Dictionary:
#   {"v": 1, "content": NetClient.content_version(), "config": the battle config, as every
#    copy ran it (seed and lockstep included), "inputs": [[tick, fighter, action, data]...],
#    "ticks": ticks the battle lasted, "winner": team (-1 draw), "meta": {...}}

const VERSION: int = 1
const DIR: String = "user://replays"
const KEEP: int = 12
const MAX_INPUTS: int = 3000
# What a player may send (MatchHost.ACTIONS); the server adds "leave" itself.
const ACTIONS: Array[String] = ["move", "aim", "charge", "release", "item", "tool", "pow", "fly", "aux", "pet", "pass", "flip", "auto", "emote"]
const KEYS: Array[String] = ["d", "angle", "power", "slot", "on", "id"]
static var dir_override: String = ""

static func folder() -> String:
	return dir_override if dir_override != "" else DIR

# Builds a replay from what a battle produced.
static func make(config: Dictionary, inputs: Array, ticks: int, winner: int, meta: Dictionary = {}) -> Dictionary:
	return {"v": VERSION, "content": NetClient.content_version(), "config": JSON.parse_string(JSON.stringify(config)), "inputs": inputs.duplicate(true), "ticks": ticks, "winner": winner, "meta": meta.duplicate(true)}

# One intent as [tick, fighter, action, data] with plain values only; [] if it is not valid.
# `from_server` lets the actions only the server stamps ("leave") through.
static func clean_input(raw: Variant, fighters: int, from_server: bool = false) -> Array:
	if not raw is Array or (raw as Array).size() < 4:
		return []
	var tick: Variant = raw[0]
	var fighter: Variant = raw[1]
	var action: Variant = raw[2]
	var data: Variant = raw[3]
	if not (tick is int or tick is float) or not (fighter is int or fighter is float) or not action is String or not data is Dictionary:
		return []
	if int(tick) < 0 or int(fighter) < 0 or int(fighter) >= fighters:
		return []
	if not (action in ACTIONS or (from_server and action == "leave")):
		return []
	var clean: Dictionary = {}
	for key: String in KEYS:
		if (data as Dictionary).has(key):
			var value: Variant = data[key]
			if value is float or value is int or value is bool:
				clean[key] = value
			elif value is String and key == "id":
				clean[key] = (value as String).substr(0, 32)
	return [int(tick), int(fighter), str(action), clean]

# A replay from outside (a file, or a submission): structure checked, intents cleaned and
# in tick order. {} when it is not usable.
static func clean(raw: Variant, from_server: bool = false) -> Dictionary:
	if not raw is Dictionary or int(raw.get("v", 0)) != VERSION or not raw.get("config") is Dictionary or not raw.get("inputs") is Array:
		return {}
	var config: Dictionary = raw.config
	var teams: Variant = config.get("teams")
	if not teams is Array or (teams as Array).size() != 2 or not config.has("seed"):
		return {}
	var fighters: int = 0
	for team: Variant in teams:
		if not team is Array:
			return {}
		fighters += (team as Array).size()
	if (raw.inputs as Array).size() > MAX_INPUTS:
		return {}
	var inputs: Array = []
	for entry: Variant in raw.inputs:
		var cleaned: Array = clean_input(entry, fighters, from_server)
		if cleaned.is_empty():
			return {}
		inputs.append(cleaned)
	inputs = sorted_by_tick(inputs)
	var meta: Variant = raw.get("meta", {})
	return {"v": VERSION, "content": str(raw.get("content", "")), "config": config, "inputs": inputs, "ticks": maxi(0, int(raw.get("ticks", 0))), "winner": int(raw.get("winner", -2)), "meta": meta if meta is Dictionary else {}}

# The intents in tick order. Several intents share a tick (aim, then charge) and their order
# matters, so the sort keeps it (GDScript's sort_custom is not stable).
static func sorted_by_tick(inputs: Array) -> Array:
	var ordered: bool = true
	for i in range(1, inputs.size()):
		if int(inputs[i][0]) < int(inputs[i - 1][0]):
			ordered = false
			break
	if ordered:
		return inputs
	var keyed: Array = []
	for i in range(inputs.size()):
		keyed.append([int(inputs[i][0]), i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return keyed.map(func(key: Array) -> Array: return inputs[key[1]])

# ---------- files ----------

static func save(replay: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder()))
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path: String = "%s/%s_%d.json" % [folder(), stamp, Time.get_ticks_msec() % 100000]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(replay))
	file.close()
	prune()
	return path

# Newest first: [{path, name, replay: meta + summary only}].
static func list() -> Array:
	var found: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder())):
		return []
	var names: PackedStringArray = DirAccess.get_files_at(folder())
	for file_name: String in names:
		if file_name.ends_with(".json"):
			found.append(file_name)
	found.sort()
	found.reverse()
	return found.map(func(file_name: String) -> String: return "%s/%s" % [folder(), file_name])

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return clean(parser.data, true)

static func prune() -> void:
	var files: Array = list()
	for i in range(KEEP, files.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(files[i])))

static func delete(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# A short line for the list: "Prata II vs Kaiser · Ilha Celeste · Vitória".
static func describe(replay: Dictionary) -> String:
	var meta: Dictionary = replay.get("meta", {})
	var parts: PackedStringArray = PackedStringArray()
	match str(meta.get("kind", "")):
		"ranked":
			parts.append(Lang.t("Ranqueada"))
		"pvp":
			parts.append(Lang.t("Combate Livre"))
		"challenge":
			parts.append(Lang.t("Desafio do Dia"))
	if meta.has("names") and meta.names is Array:
		parts.append(" vs ".join((meta.names as Array).map(func(n: Variant) -> String: return str(n))))
	var map_id: String = str(replay.config.get("map", ""))
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json")).maps:
		if str(entry.id) == map_id:
			parts.append(Lang.t(str(entry.name)))
	return "  ·  ".join(parts)
