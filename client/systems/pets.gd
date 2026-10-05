class_name Pets
extends RefCounted

# Casa dos Mascotes: collectible pets of 5 elements and 4 rarities. Since 0.30 they are
# looks only: sold in the shop (store.json, tab Mascotes), no attributes, no battle skill, no
# eggs. Comum and Raro can also be found (boss chest, Caçada), and the Caçada is the only
# place where a pet gains levels. Everything is derived from shared/balance/pets.json; the
# profile only keeps {uid, species, level, xp}.
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

# ---------- one pet ----------

static func clean_pet(raw: Variant) -> Dictionary:
	if not raw is Dictionary or species_def(str(raw.get("species", ""))).is_empty():
		return {}
	var level: int = clampi(int(raw.get("level", 1)), 1, cap())
	var xp: int = maxi(0, int(raw.get("xp", 0)))
	if level >= cap():
		xp = 0
	else:
		xp = mini(xp, xp_needed(level) - 1)
	return {"uid": int(raw.get("uid", 0)), "species": str(raw.species), "level": level, "xp": xp}

static func cap() -> int:
	return int(data().max_level)

static func xp_needed(level: int) -> int:
	return int(data().xp.per_level) * level

static func total_xp(pet: Dictionary) -> int:
	var sum: int = int(pet.get("xp", 0))
	for level in range(1, int(pet.get("level", 1))):
		sum += xp_needed(level)
	return sum

# Adds experience, carrying over level-ups up to the level cap. Returns the levels gained.
static func add_xp(pet: Dictionary, amount: int) -> int:
	var gained: int = 0
	var left: int = maxi(0, amount)
	var limit: int = cap()
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

# ---------- drops ----------

# The chance that a boss chest holds a pet: not guaranteed, never above `boss_max`.
static func boss_pet_chance(level: int) -> float:
	var rules: Dictionary = data().drops
	if level <= 0:
		return float(rules.free_entry)
	return minf(float(rules.boss_max), float(rules.boss_base) + float(rules.boss_per_level) * level)

# The Comum of the instance's element (the only rarity that drops from instances).
static func drop_species(instance_id: String) -> String:
	for entry: Dictionary in elements():
		if entry.instance == instance_id:
			for pet: Dictionary in species_of_element(str(entry.id)):
				if pet.rarity == "comum":
					return str(pet.id)
	return str(species_list()[0].id)

# A chest/reward card for a pet found by a run (Rewards.grant gives it to the profile).
static func drop_entry(species: String) -> Dictionary:
	return {"id": "pet_" + species, "name": Lang.t(species_name(species)), "pet": species, "amount": 1, "rarity": "rare", "icon": str(species_def(species).get("art", ""))}

# What a pre-0.30 egg is worth in coins (the old saves keep no eggs).
static func egg_refund(item_id: String) -> int:
	var table: Dictionary = data().egg_refund
	return int(table.get(item_id, table.default))
