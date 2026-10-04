class_name Pets
extends RefCounted

# Casa dos Mascotes (0.19): eggs drop in the instances, hatch into pets of 5 elements and
# 4 rarities, and the active pet adds bonus attributes to battles. Everything is derived
# from shared/balance/pets.json; the profile only keeps {uid, species, level, xp, stars}.
# Offline the client applies these rules, online the game server does (same code).

const PATH: String = "res://shared/balance/pets.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

# ---------- catalogue ----------

static func rarities() -> Array:
	return data().rarities

static func rarity_index(id: String) -> int:
	for i in range(rarities().size()):
		if rarities()[i].id == id:
			return i
	return 0

static func rarity_def(id: String) -> Dictionary:
	return rarities()[rarity_index(id)]

static func rarity_label(id: String) -> String:
	return Lang.t(str(rarity_def(id).label))

static func rarity_color(id: String) -> Color:
	return Color(str(rarity_def(id).color))

static func elements() -> Array:
	return data().elements

static func element_def(id: String) -> Dictionary:
	for entry: Dictionary in elements():
		if entry.id == id:
			return entry
	return {}

static func element_name(id: String) -> String:
	return Lang.t(str(element_def(id).get("name", id)))

static func element_color(id: String) -> Color:
	return Color(str(element_def(id).get("color", "ffffff")))

static func species_list() -> Array:
	return data().species

static func species_def(id: String) -> Dictionary:
	for entry: Dictionary in species_list():
		if entry.id == id:
			return entry
	return {}

static func species_name(id: String) -> String:
	return Lang.t(str(species_def(id).get("name", id)))

static func species_of_element(element: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for entry: Dictionary in species_list():
		if entry.element == element:
			list.append(entry)
	return list

static func eggs() -> Array:
	return data().eggs

static func egg_def(id: String) -> Dictionary:
	for entry: Dictionary in eggs():
		if entry.id == id:
			return entry
	return {}

static func is_egg(id: String) -> bool:
	return not egg_def(id).is_empty()

static func egg_name(id: String) -> String:
	return Lang.t(str(egg_def(id).get("name", id)))

static func egg_for_instance(instance_id: String) -> String:
	for entry: Dictionary in elements():
		if entry.instance == instance_id:
			return str(entry.egg)
	return "pet_egg"

# ---------- one pet ----------

static func clean_pet(raw: Variant) -> Dictionary:
	if not raw is Dictionary or species_def(str(raw.get("species", ""))).is_empty():
		return {}
	var stars: int = clampi(int(raw.get("stars", 0)), 0, int(data().max_stars))
	var level: int = clampi(int(raw.get("level", 1)), 1, cap(stars))
	var xp: int = maxi(0, int(raw.get("xp", 0)))
	if level >= cap(stars):
		xp = 0
	else:
		xp = mini(xp, xp_needed(level) - 1)
	return {"uid": int(raw.get("uid", 0)), "species": str(raw.species), "level": level, "xp": xp, "stars": stars}

static func cap(stars: int) -> int:
	return mini(int(data().max_level), int(data().base_cap) + int(data().cap_per_star) * stars)

static func xp_needed(level: int) -> int:
	return int(data().xp.per_level) * level

static func total_xp(pet: Dictionary) -> int:
	var sum: int = int(pet.get("xp", 0))
	for level in range(1, int(pet.get("level", 1))):
		sum += xp_needed(level)
	return sum

# Adds experience, carrying over level-ups up to the cap of the pet's stars. Returns the
# levels gained.
static func add_xp(pet: Dictionary, amount: int) -> int:
	var gained: int = 0
	var left: int = maxi(0, amount)
	var limit: int = cap(int(pet.stars))
	while left > 0 and int(pet.level) < limit:
		var need: int = xp_needed(int(pet.level)) - int(pet.xp)
		if left >= need:
			left -= need
			pet.level = int(pet.level) + 1
			pet.xp = 0
			gained += 1
		else:
			pet.xp = int(pet.xp) + left
			left = 0
	if int(pet.level) >= limit:
		pet.xp = 0
	return gained

static func power(level: int) -> float:
	var floor_value: float = float(data().power.floor)
	return floor_value + (1.0 - floor_value) * float(level - 1) / float(int(data().max_level) - 1)

static func talent_keys(pet: Dictionary) -> Array[String]:
	var def: Dictionary = species_def(str(pet.species))
	var count: int = int(rarity_def(str(def.rarity)).talents)
	var list: Array[String] = []
	var pool: Array = element_def(str(def.element)).talents
	for i in range(mini(count, pool.size())):
		list.append(str(pool[i]))
	return list

# {attribute: value} for ataque/defesa/agilidade/sorte.
static func attrs(pet: Dictionary) -> Dictionary:
	var def: Dictionary = species_def(str(pet.species))
	var rarity: Dictionary = rarity_def(str(def.rarity))
	var scale: float = power(int(pet.level)) * (1.0 + float(data().power.attr_per_star) * int(pet.stars))
	var result: Dictionary = {}
	for pair: Array in element_def(str(def.element)).attrs:
		result[str(pair[0])] = roundi(float(rarity.attr) * float(pair[1]) * scale)
	return result

# The talents as [{key, value}].
static func talents(pet: Dictionary) -> Array[Dictionary]:
	var def: Dictionary = species_def(str(pet.species))
	var rarity: Dictionary = rarity_def(str(def.rarity))
	var scale: float = power(int(pet.level)) * (1.0 + float(data().power.talent_per_star) * int(pet.stars))
	var list: Array[Dictionary] = []
	for key in talent_keys(pet):
		var value: int = maxi(1, roundi(float(data().talent_max[key]) * float(rarity.talent) * scale))
		list.append({"key": key, "value": value})
	return list

# Everything the pet adds to the battle numbers, flattened: attributes and talents by key.
static func bonus(pet: Dictionary) -> Dictionary:
	if pet.is_empty():
		return {}
	var result: Dictionary = attrs(pet)
	for entry: Dictionary in talents(pet):
		result[entry.key] = int(result.get(entry.key, 0)) + int(entry.value)
	return result

static func talent_text(key: String, value: int) -> String:
	return Lang.t(str(data().talent_text[key])) % value

static func describe(pet: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var numbers: Dictionary = attrs(pet)
	for key: String in Armory.ATTRS:
		if numbers.has(key):
			lines.append("%s +%d" % [Armory.attr_name(key), int(numbers[key])])
	for entry: Dictionary in talents(pet):
		lines.append(talent_text(str(entry.key), int(entry.value)))
	return lines

# ---------- battle skill (0.22) ----------
# The active pet gives its owner one skill per battle, by its element (pets.json -> battle).
# The pet only carries {element, rarity, stars, species} into the battle; the numbers are
# worked out here so every copy of the match agrees.

static func battle_rules() -> Dictionary:
	return data().battle

# What the entry of a fighter carries for the skill ({} without an active pet).
static func skill_entry(pet: Dictionary) -> Dictionary:
	if pet.is_empty():
		return {}
	var def: Dictionary = species_def(str(pet.species))
	if def.is_empty():
		return {}
	return {"species": str(pet.species), "element": str(def.element), "rarity": str(def.rarity), "stars": int(pet.get("stars", 0))}

static func skill_def(element: String) -> Dictionary:
	return battle_rules().abilities.get(element, {})

# How strong the skill is: the pet's rarity and its stars.
static func skill_power(skill: Dictionary) -> float:
	var rules: Dictionary = battle_rules()
	return float(rules.scale.get(str(skill.get("rarity", "comum")), 1.0)) * (1.0 + float(rules.star_scale) * float(skill.get("stars", 0)))

# The skill's value after scaling (0.25 for the Rajada Solar of a common pet = +25%).
static func skill_value(skill: Dictionary) -> float:
	return float(skill_def(str(skill.get("element", ""))).get("value", 0.0)) * skill_power(skill)

static func skill_text(skill: Dictionary) -> String:
	var def: Dictionary = skill_def(str(skill.get("element", "")))
	if def.is_empty():
		return ""
	return Lang.t(str(def.desc)) % roundi(skill_value(skill) * 100.0)

# ---------- album ----------

static func element_complete(album: Array, element: String) -> bool:
	for entry in species_of_element(element):
		if not album.has(entry.id):
			return false
	return true

static func album_bonus(album: Array) -> Dictionary:
	var result: Dictionary = {}
	var complete: int = 0
	for entry: Dictionary in elements():
		if element_complete(album, str(entry.id)):
			complete += 1
			for key: String in entry.album:
				result[key] = int(result.get(key, 0)) + int(entry.album[key])
	if complete == elements().size():
		for key: String in data().album_all:
			result[key] = int(result.get(key, 0)) + int(data().album_all[key])
	return result

# ---------- hatching ----------

static func odds(egg_id: String) -> Array:
	return egg_def(egg_id).get("odds", [100, 0, 0, 0])

# Pity: after `pity.epico` eggs without an Épico or better one is guaranteed (and a
# Lendário after `pity.lendario`). Counters live in profile.pity.
static func pity_left(pity: Dictionary, rarity: String) -> int:
	return maxi(0, int(data().pity[rarity]) - int(pity.get("egg_" + rarity, 0)))

static func roll_rarity(egg_id: String, pity: Dictionary, rng: RandomNumberGenerator) -> int:
	var list: Array = odds(egg_id)
	var total: float = 0.0
	for value in list:
		total += float(value)
	var ticket: float = rng.randf() * total
	var result: int = 0
	for i in range(list.size()):
		ticket -= float(list[i])
		if ticket <= 0.0:
			result = i
			break
	if pity_left(pity, "lendario") <= 1:
		result = 3
	elif pity_left(pity, "epico") <= 1:
		result = maxi(result, 2)
	return result

static func roll_species(egg_id: String, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	var element: String = str(egg_def(egg_id).get("element", ""))
	if element == "":
		element = str(elements()[rng.randi() % elements().size()].id)
	var rarity_id: String = str(rarities()[rarity].id)
	for entry in species_of_element(element):
		if entry.rarity == rarity_id:
			return entry
	return species_of_element(element)[0]

# ---------- drops ----------

static func boss_egg_chance(level: int) -> float:
	var rules: Dictionary = data().drops
	if level <= 0:
		return float(rules.free_entry)
	return minf(float(rules.boss_max), float(rules.boss_base) + float(rules.boss_per_level) * level)

static func egg_entry(egg_id: String) -> Dictionary:
	var def: Dictionary = egg_def(egg_id)
	return {"id": "egg_" + egg_id, "name": Lang.t(str(def.get("name", egg_id))), "item": egg_id, "amount": 1, "rarity": "legendary" if egg_id == "pet_egg" else "epic", "icon": str(def.get("icon", ""))}
