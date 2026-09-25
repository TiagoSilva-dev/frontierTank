class_name Achievements
extends RefCounted

# Steam achievements (launch checklist). shared/balance/achievements.json says which
# profile number unlocks each one; the ids are the API names registered on Steamworks.
# SteamService unlocks them from the online profile only (the server's copy), so an
# edited offline save never unlocks anything.

const PATH: String = "res://shared/balance/achievements.json"

static var _list: Array = []

static func list() -> Array:
	if _list.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_list = parsed.get("achievements", []) if parsed is Dictionary else []
	return _list

static func stat(profile: PlayerProfile, name: String) -> int:
	match name:
		"victories":
			return profile.victories
		"matches":
			return profile.matches
		"level":
			return profile.level()
		"max_strengthen":
			var best: int = 0
			for inst: Dictionary in profile.inventory:
				best = maxi(best, int(inst.get("level", 0)))
			return best
		"true_weapons", "super_weapons":
			var quality: String = "verdadeira" if name == "true_weapons" else "super"
			return profile.inventory.filter(func(inst: Dictionary) -> bool: return Armory.kind_of(str(inst.id)) == "weapon" and str(inst.get("quality", "")) == quality).size()
		"max_map_level":
			var top: int = 0
			for item: Dictionary in profile.maps:
				top = maxi(top, int(item.get("level", 0)))
			return top
		"cosmetics":
			var ids: Dictionary = {}
			for inst: Dictionary in profile.inventory:
				if Armory.kind_of(str(inst.id)) == "cosmetic":
					ids[str(inst.id)] = true
			return ids.size()
	return 0

# The ids of the achievements this profile has reached.
static func reached(profile: PlayerProfile) -> Array[String]:
	var ids: Array[String] = []
	if profile == null or not profile.created:
		return ids
	for entry: Dictionary in list():
		if stat(profile, str(entry.stat)) >= int(entry.at_least):
			ids.append(str(entry.id))
	return ids
