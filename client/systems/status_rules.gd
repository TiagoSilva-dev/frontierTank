class_name StatusRules
extends RefCounted

# Status effects and elite monsters (0.16), read from combat.json: "statuses" (burning,
# poison, freeze, exhaustion, seal, roots, mark, glare) and "elites" (the PvE affixes).
# The rules themselves run in LocalMatch (add_status, tick_statuses, expire_statuses);
# this holds the data lookups and the icons shared by the battlefield and the HUD.

static var _rules: Dictionary = {}
static var _icons: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	return _rules

static func all() -> Array:
	return rules().get("statuses", [])

static func def(id: String) -> Dictionary:
	for entry: Dictionary in all():
		if entry.id == id:
			return entry
	return {}

static func color(id: String) -> Color:
	return Color(str(def(id).get("color", "ffffff")))

static func affix(id: String) -> Dictionary:
	for entry: Dictionary in rules().get("elites", {}).get("affixes", []):
		if entry.id == id:
			return entry
	return {}

static func icon_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _icons.has(path):
		_icons[path] = load(path)
	return _icons[path]

static func icon(id: String) -> Texture2D:
	return icon_path(str(def(id).get("icon", "")))

# The statuses of a fighter in the order of combat.json, as [id, entry] pairs.
static func listed(fighter: TankFighter) -> Array:
	var list: Array = []
	for entry: Dictionary in all():
		if fighter.statuses.has(entry.id):
			list.append([str(entry.id), fighter.statuses[entry.id]])
	return list

static func describe(id: String, entry: Dictionary) -> String:
	var info: Dictionary = def(id)
	var turns: int = int(entry.get("turns", 0))
	var head: String = Lang.t(str(info.get("name", id)))
	if int(entry.get("stacks", 1)) > 1:
		head += " x%d" % int(entry.stacks)
	var left: String = Lang.t("1 turno") if turns == 1 else Lang.t("%d turnos") % turns
	return "%s (%s)\n%s" % [head, left, Lang.t(str(info.get("desc", "")))]
