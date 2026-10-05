class_name PlayerProfile
extends RefCounted

# Single character. Offline it is saved in user://; online (backend 0.11) the game server
# keeps the authoritative copy and runs every change through `apply_op` with these same
# rules, while the client's copy is only a mirror of what the server sends.
# v3 keeps an inventory of item instances ({uid, id, quality, level}) and the
# equipped slot -> uid map; stones stay as counters in `items`.
# v4 (0.9) adds the instance maps ({uid, instance, level, quality, mods}), the item level
# (`ilvl`) of dropped weapons and the Super Verdadeira guarantee counter per instance.
# v5 (0.10) adds the random bonus attributes of gear (`mods`: {id, tier, value}), a quality
# for hats, glasses, wings and outfits, `bound` (shop, coupon and mirrored items: never
# traded) and `mirrored` (Espelho Celeste copies: never changed). Currencies are counters
# in `items` like the stones. Drops from v4 saves get their bonuses rolled once on load.
# 0.12 (Leilão): the starter weapon and equipped Super Verdadeiras are bound; items and
# maps bought or returned by the auction arrive through `receive_instance`/`receive_map`.
# Composição (Cristal Dourado) and Fusão of stones were removed: the currencies give gear
# its extra attributes. Old saves drop their `compose` bonus and crystal counter on load.
# v6 stores daily mission progress and reward claims.
# v7 (0.19, Casa dos Mascotes) adds the pets ({uid, species, level, xp, stars}), the active
# pet and the album of species ever hatched; eggs are counters in `items` and the hatch
# pity counters live in `pity`. v8 (0.20, Caçada dos Mascotes) adds `hunt` (PetHunt).
# v12 (0.30) makes the pets collectibles sold in the shop: no eggs (each one on a loaded save
# becomes coins), no stars and no pity, and one pet per species on a pre-12 save (the
# duplicates become coins, the best one stays).
# v9 (0.22) adds `tutorial` ("", "skipped" or "done"; saves that already played count as
# done) and the starter checklist inside `missions`.
# v10 (0.22, ranked ladder) adds `rating` (Ranked: season, rating, record and the log of
# the seasons that ended) and the cosmetic titles (`titles`, `title`), and `challenge` (the
# day of the daily challenge last finished and the best score of that day).
# v11 (0.24, skins) makes the old outfit slot ("roupa") the skin: appearance only, with no
# attributes, never strengthened or modified. Each outfit a v10 save owned becomes the
# skin (level and bonuses dropped) plus a shirt and trousers that carry what the outfit
# had (LEGACY_OUTFITS), so nobody loses defence in the move.
const SAVE_PATH: String = "user://profile.json"
# Old outfit -> the shirt and trousers family that replaces its attributes.
const LEGACY_OUTFITS: Dictionary = {"roupa_explorador": "algodao", "roupa_exploradora": "algodao", "roupa_ninja": "aventureiro", "roupa_marinheira": "aventureiro", "roupa_maga": "aventureiro", "roupa_samurai": "guerra", "roupa_capitao": "guerra", "roupa_princesa": "guerra"}
# Tests point this at a scratch file so they never touch the player's save.
static var path_override: String = ""
var save_path: String = SAVE_PATH
var created: bool = false
var player_name: String = "Explorador"
var gender: String = "m":
	set(value):
		gender = value
		Armory.viewer_gender = value
var experience: int = 0
var victories: int = 0
var matches: int = 0
var coins: int = 300
var merits: int = 0
var tools: Array[String] = ["", "", ""]
var items: Dictionary = {}
var inventory: Array[Dictionary] = []
var equipped: Dictionary = {}
var next_uid: int = 1
var coupons: Array[String] = []
var maps: Array[Dictionary] = []
var pity: Dictionary = {}
var missions: Dictionary = {}
var tutorial: String = ""
var rating: Dictionary = Ranked.empty_rating()
var titles: Array[String] = []
var title: String = ""
var challenge: Dictionary = {"day": -1, "best": 0, "medal": 0}
var pets: Array[Dictionary] = []
var pet_active: int = -1
var pet_album: Array[String] = []
var hunt: Dictionary = PetHunt.clean_state({})
# Tests set a fixed time for the hunt; 0 means the real clock.
var hunt_clock: int = 0
# Online mirror: how far the game server's clock is ahead of this computer's, so the
# timer on screen agrees with the one the server settles with.
var hunt_skew: int = 0
# 0.15: how the player arranged the Mochila, cell by cell ("" = empty cell). Only the
# order is kept here; CharacterScreen fits new and vanished items into it.
var bag: Array[String] = []
# Founder Pack: which of the Founder effects are on (FounderPack.FX_KEYS).
var founder_fx: Dictionary = FounderPack.clean_fx({})
# 0.27: show the skin as drawn. Hat, glasses, wings and hair dye stay on the character
# (attributes untouched) but are not drawn; what the skin itself carries still is.
var skin_only: bool = false
# 0.29: the alternative colour picked for each skin that has them ({skin item id: colour id}).
# Appearance only; the colours come with the skin.
var skin_colors: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var remote: bool = false
var on_save: Callable = Callable()

func _init() -> void:
	if path_override != "":
		save_path = path_override
	rng.randomize()
	ensure_starter()

func load_profile() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary and load_data(data):
		save_profile()

# Reads a save (the local file, or the copy the online server keeps in PostgreSQL).
# Returns true when v4 drops were migrated, so the caller saves again.
func load_data(data: Dictionary) -> bool:
	player_name = str(data.get("name", "Explorador")).strip_edges().substr(0, 14)
	if player_name == "":
		player_name = "Explorador"
	created = bool(data.get("created", int(data.get("version", 1)) == 1))
	gender = "f" if str(data.get("gender", "m")) == "f" else "m"
	experience = maxi(0, int(data.get("experience", 0)))
	victories = maxi(0, int(data.get("victories", 0)))
	matches = maxi(0, int(data.get("matches", 0)))
	coins = maxi(0, int(data.get("coins", 300)))
	merits = maxi(0, int(data.get("merits", 0)))
	var saved_tools: Variant = data.get("tools", [])
	tools = ["", "", ""]
	if saved_tools is Array:
		for i in range(mini(3, saved_tools.size())):
			tools[i] = str(saved_tools[i])
	var saved_items: Variant = data.get("items", {})
	items = {}
	if saved_items is Dictionary:
		for key: String in saved_items:
			if key != "golden_crystal":
				items[key] = maxi(0, int(saved_items[key]))
	inventory.clear()
	equipped.clear()
	next_uid = maxi(1, int(data.get("next_uid", 1)))
	var saved_inventory: Variant = data.get("inventory", [])
	var migrated: bool = false
	var old_save: bool = int(data.get("version", 1)) < 11
	# v10 saves: the outfits to replace (after the loop, so the new uids never collide
	# with the ones still to be read) and, once replaced, outfit uid -> its shirt and trousers.
	var outfits: Array = []
	var outfit_gear: Dictionary = {}
	if saved_inventory is Array:
		for raw: Variant in saved_inventory:
			var inst: Dictionary = clean_instance(raw)
			if not inst.is_empty():
				inst.uid = int(raw.get("uid", next_uid))
				if not raw.has("mods") and inst.has("ilvl") and inst.quality != "normal":
					# v4 drop: roll the bonuses it would have dropped with.
					inst.mods = Crafting.roll_mods(inst, rng)
					migrated = true
				inventory.append(inst)
				next_uid = maxi(next_uid, int(inst.uid) + 1)
				if old_save and LEGACY_OUTFITS.has(str(inst.id)):
					outfits.append([inst, raw])
	for pair: Array in outfits:
		outfit_gear[int(pair[0].uid)] = replace_outfit(pair[0], pair[1])
		migrated = true
	var saved_equipped: Variant = data.get("equipped", {})
	if saved_equipped is Dictionary:
		for key: String in saved_equipped:
			var slot: String = "skin" if key == "roupa" else key
			var uid: int = int(saved_equipped[key])
			var worn: Dictionary = find_instance(uid)
			# Only an item of that slot can be worn there (old saves had wings that are now
			# a layer of a skin, outfits where the skin goes).
			if worn.size() > 0 and slot in Armory.worn_places(Armory.slot_of(str(worn.id))):
				equipped[slot] = uid
				if worn.quality == "super":
					# 0.12: Super Verdadeiras bind when equipped (saves from before too).
					worn.bound = true
				if outfit_gear.has(uid):
					equipped["camisa"] = int(outfit_gear[uid].camisa)
					equipped["calca"] = int(outfit_gear[uid].calca)
	maps.clear()
	var saved_maps: Variant = data.get("maps", [])
	if saved_maps is Array:
		for raw: Variant in saved_maps:
			var item: Dictionary = clean_map(raw)
			if not item.is_empty():
				item.uid = int(raw.get("uid", next_uid))
				maps.append(item)
				next_uid = maxi(next_uid, int(item.uid) + 1)
	# No guarantee of any kind remains: the egg and Super Verdadeira counters are dropped.
	pity = {}
	# 0.30: the eggs are gone; each one a save still holds becomes coins.
	for id: String in items.keys():
		if id.begins_with("egg_") or id == "pet_egg":
			coins += int(items[id]) * Pets.egg_refund(id)
			items.erase(id)
	var saved_missions: Variant = data.get("missions", {})
	var had_starter: bool = saved_missions is Dictionary and saved_missions.has("starter")
	missions = MissionsBoard.clean_state(saved_missions)
	if data.has("tutorial"):
		tutorial = str(data.tutorial) if str(data.tutorial) in ["", "skipped", "done"] else ""
	else:
		tutorial = "done" if matches > 0 or experience > 0 else ""
	rating = Ranked.clean_rating(data.get("rating", {}))
	titles.clear()
	var saved_titles: Variant = data.get("titles", [])
	if saved_titles is Array:
		for id: Variant in saved_titles:
			if Ranked.valid_title(str(id)) and not titles.has(str(id)):
				titles.append(str(id))
	title = str(data.get("title", "")) if titles.has(str(data.get("title", ""))) else ""
	var saved_challenge: Variant = data.get("challenge", {})
	challenge = {"day": -1, "best": 0, "medal": 0}
	if saved_challenge is Dictionary:
		challenge = {"day": int(saved_challenge.get("day", -1)), "best": maxi(0, int(saved_challenge.get("best", 0))), "medal": clampi(int(saved_challenge.get("medal", 0)), 0, 3)}
	load_pets(data)
	hunt = PetHunt.clean_state(data.get("hunt", {}))
	if remote and data.has("clock"):
		hunt_skew = int(data.clock) - int(Time.get_unix_time_from_system())
	bag = fit_bag(clean_bag(data.get("bag", [])))
	founder_fx = FounderPack.clean_fx(data.get("founder_fx", {}))
	skin_only = bool(data.get("skin_only", false))
	skin_colors = clean_skin_colors(data.get("skin_colors", {}))
	var saved_coupons: Variant = data.get("coupons", [])
	coupons.clear()
	if saved_coupons is Array:
		for code: Variant in saved_coupons:
			coupons.append(str(code))
	if inventory.is_empty() and data.has("weapon"):
		# v2 save: keep the chosen slot of the old arsenal as the starting weapon.
		var inst: Dictionary = add_instance(Armory.legacy_instance(int(data.weapon)).id)
		equipped["arma"] = inst.uid
	if not had_starter and int(data.get("version", 9)) < 9:
		# A save from before the starter checklist: what the character did counts.
		MissionsBoard.credit_history(self)
		migrated = true
	ensure_starter()
	return migrated

# v11: the outfit `inst` (just read from `raw`) becomes a plain skin; the shirt takes its
# level, quality and bonuses and the trousers come with the same quality. Returns the uids
# of the new shirt and trousers.
func replace_outfit(inst: Dictionary, raw: Dictionary) -> Dictionary:
	var family: String = str(LEGACY_OUTFITS[str(inst.id)])
	var quality: String = valid_quality("camisa_" + family, str(raw.get("quality", "normal")))
	var level: int = clampi(int(raw.get("level", 0)), 0, 12)
	var ilvl: int = clampi(int(raw.get("ilvl", 0)), 0, 16)
	var shirt: Dictionary = add_instance("camisa_" + family, quality, level, ilvl, raw.get("mods", []) if raw.get("mods", []) is Array else [])
	var trousers: Dictionary = add_instance("calca_" + family, quality, 0, ilvl)
	if quality != "normal":
		trousers.mods = Crafting.roll_mods(trousers, rng)
	for gear: Dictionary in [shirt, trousers]:
		if bool(raw.get("bound", false)):
			gear.bound = true
	inst.level = 0
	inst.quality = "normal"
	inst.mods = []
	inst.erase("ilvl")
	return {"camisa": shirt.uid, "calca": trousers.uid}

# One pet per species on an old save: the one with the most experience stays and the others
# become the coins of releasing them (the stars they fed are gone with the stars).
func merge_duplicate_pets() -> int:
	var best: Dictionary = {}
	for pet: Dictionary in pets:
		var key: String = str(pet.species)
		if not best.has(key) or Pets.total_xp(pet) > Pets.total_xp(best[key]):
			best[key] = pet
	var refund: int = 0
	var kept: Array[Dictionary] = []
	for pet: Dictionary in pets:
		if best[str(pet.species)] == pet:
			kept.append(pet)
		else:
			refund += int(Pets.rarity_def(str(Pets.species_def(str(pet.species)).rarity)).release)
	pets = kept
	if find_pet(pet_active).is_empty():
		pet_active = -1
	return refund

func load_pets(data: Dictionary) -> void:
	pets.clear()
	pet_album.clear()
	var saved: Variant = data.get("pets", [])
	if saved is Array:
		for raw: Variant in saved:
			var pet: Dictionary = Pets.clean_pet(raw)
			if not pet.is_empty() and pets.size() < int(Pets.data().max_pets):
				pets.append(pet)
				next_uid = maxi(next_uid, int(pet.uid) + 1)
	pet_active = int(data.get("pet_active", -1))
	if find_pet(pet_active).is_empty():
		pet_active = -1
	var seen: Variant = data.get("pet_album", [])
	if seen is Array:
		for id: Variant in seen:
			if not Pets.species_def(str(id)).is_empty() and not pet_album.has(str(id)):
				pet_album.append(str(id))
	if int(data.get("version", 1)) < 12:
		coins += merge_duplicate_pets()
	for pet: Dictionary in pets:
		if not pet_album.has(pet.species):
			pet_album.append(pet.species)

func ensure_starter() -> void:
	# Every account starts with the basic look (t-shirt and shorts) and a Tijolaço.
	if equipped_instance("arma").is_empty():
		var weapon: Dictionary = {}
		for inst in inventory:
			if Armory.slot_of(str(inst.id)) == "arma":
				weapon = inst
				break
		if weapon.is_empty():
			weapon = add_instance("quebra_tijolos")
			# Free for every account: never goes to the auction.
			weapon.bound = true
		equipped["arma"] = weapon.uid

func to_data() -> Dictionary:
	return {"version": 12, "tutorial": tutorial, "rating": rating, "titles": titles, "title": title, "challenge": challenge, "pets": pets, "pet_active": pet_active, "pet_album": pet_album, "hunt": hunt, "clock": hunt_now(), "created": created, "name": player_name, "gender": gender, "experience": experience, "victories": victories, "matches": matches, "coins": coins, "merits": merits, "tools": tools, "items": items, "inventory": inventory, "equipped": equipped, "next_uid": next_uid, "coupons": coupons, "maps": maps, "pity": pity, "missions": missions, "bag": bag, "founder_fx": founder_fx, "skin_only": skin_only, "skin_colors": skin_colors}

func save_profile() -> void:
	# Online: the server's copy is persisted through `on_save`; the client's copy is a
	# mirror of the server (`remote`) and never overwrites the offline save.
	if on_save.is_valid():
		on_save.call()
		return
	if remote:
		return
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(to_data()))

static func exp_for_level(value: int) -> int:
	return 60 * value * (value - 1)

static func level_for(total: int) -> int:
	var value: int = 1
	while value < 60 and total >= exp_for_level(value + 1):
		value += 1
	return value

func level() -> int:
	return level_for(experience)

func level_progress() -> float:
	var current: int = exp_for_level(level())
	var next: int = exp_for_level(level() + 1)
	return float(experience - current) / float(maxi(1, next - current))

func ranking() -> int:
	return victories * 3 + merits / 10

# ---------- daily challenge (0.22) ----------

# A finished daily challenge: the first one of a day pays its reward, the next ones only
# raise the best score. Not an operation: the offline game calls it for its own score and the
# online server after it checked the replay. Returns {"first": bool, "best": bool, "medal"}.
func challenge_done(day: int, score: int, medal: int) -> Dictionary:
	var first: bool = int(challenge.day) != day
	var better: bool = first or score > int(challenge.best)
	if first:
		var reward: Dictionary = Challenge.data().reward
		coins += int(reward.coins)
		experience += int(reward.exp)
		challenge.day = day
		challenge.best = 0
		MissionsBoard.note(self, "challenge")
	if better:
		challenge.best = score
		challenge.medal = medal
	save_profile()
	return {"first": first, "best": better, "medal": int(challenge.medal), "score": int(challenge.best)}

# ---------- ranked ladder and titles (0.22) ----------

# Brings the rating to the current season (the server calls it before every use). Returns
# whether it changed, so the caller saves.
func sync_rating(timestamp: int = -1) -> bool:
	return Ranked.sync(rating, timestamp)

# Equips a title the character owns ("" takes it off).
func title_set(id: String) -> String:
	if id != "" and not titles.has(id):
		return tr("Você ainda não tem este título.")
	title = id
	save_profile()
	return ""

# Claims the title of a season that ended. Returns the title id, or an error text.
func season_claim(season: int) -> String:
	sync_rating()
	for entry: Dictionary in rating.log:
		if int(entry.season) == season:
			if bool(entry.claimed):
				return tr("Esta recompensa já foi resgatada.")
			var id: String = Ranked.title_id(season, str(entry.division))
			entry.claimed = true
			if not titles.has(id):
				titles.append(id)
			if title == "":
				title = id
			save_profile()
			return id
	return tr("Não há recompensa para esta temporada.")

func add_item(id: String, amount: int = 1) -> void:
	items[id] = int(items.get(id, 0)) + amount

func add_tool(id: String) -> bool:
	for i in range(3):
		if tools[i] == "":
			tools[i] = id
			return true
	return false

func record_match(won: bool, exp_gain: int, merit_gain: int) -> void:
	matches += 1
	if won:
		victories += 1
	experience += exp_gain
	merits += merit_gain
	save_profile()

# ---------- inventory ----------

static func valid_quality(id: String, quality: String) -> String:
	# Super Verdadeira is only for the super weapons; gear that takes bonuses can be
	# Normal, Excelente or Verdadeira; everything else stays Normal.
	if Armory.kind_of(id) == "weapon" and bool(Armory.weapon_def(id).get("super", false)):
		return "super"
	if Crafting.can_have_mods(id) and quality in ["normal", "excelente", "verdadeira"]:
		return quality
	return "normal"

func add_instance(id: String, quality: String = "normal", level: int = 0, ilvl: int = 0, mods: Array = []) -> Dictionary:
	quality = valid_quality(id, quality)
	var inst: Dictionary = {"uid": next_uid, "id": id, "quality": quality, "level": clampi(level, 0, 12), "mods": Crafting.valid_mods(mods, id)}
	if ilvl > 0:
		# Item level = level of the map it dropped in: it limits the bonus tiers (0.10).
		inst.ilvl = clampi(ilvl, 1, 16)
	next_uid += 1
	inventory.append(inst)
	return inst

# A piece of gear read from outside the running game (the save, or the mail of the
# auction): only known items, with valid quality, level and bonuses. {}
# when it is not an item. The caller gives it a uid.
static func clean_instance(raw: Variant) -> Dictionary:
	if not raw is Dictionary or Armory.kind_of(str(raw.get("id", ""))) == "":
		return {}
	var id: String = str(raw.id)
	var inst: Dictionary = {"uid": 0, "id": id, "quality": valid_quality(id, str(raw.get("quality", "normal"))), "level": clampi(int(raw.get("level", 0)), 0, 12), "mods": Crafting.valid_mods(raw.get("mods", []), id)}
	if int(raw.get("ilvl", 0)) > 0:
		inst.ilvl = clampi(int(raw.ilvl), 1, 16)
	for flag: String in ["bound", "mirrored"]:
		if bool(raw.get(flag, false)):
			inst[flag] = true
	return inst

# An instance map read from outside (save or mail): known instance and modifiers.
static func clean_map(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not raw.has("instance"):
		return {}
	var instance: String = str(raw.instance)
	if str(InstanceRun.instance_def(instance).id) != instance:
		return {}
	var quality: String = str(raw.get("quality", "normal"))
	var item: Dictionary = {"uid": 0, "instance": instance, "level": clampi(int(raw.get("level", 1)), 1, 16), "quality": quality if quality in ["normal", "excelente", "verdadeira"] else "normal", "mods": []}
	var saved_mods: Variant = raw.get("mods", [])
	if saved_mods is Array:
		for mod: Variant in saved_mods:
			if mod is Dictionary and not InstanceRun.mod_def(str(mod.get("id", ""))).is_empty():
				item.mods.append({"id": str(mod.id), "value": int(mod.get("value", 1))})
	if bool(raw.get("bound", false)):
		item.bound = true
	return item

func find_instance(uid: int) -> Dictionary:
	for inst in inventory:
		if int(inst.uid) == uid:
			return inst
	return {}

func has_item(id: String, quality: String = "") -> bool:
	for inst in inventory:
		if inst.id == id and (quality == "" or inst.quality == quality):
			return true
	return false

func equipped_instance(slot: String) -> Dictionary:
	return find_instance(int(equipped.get(slot, -1)))

# What is worn in an item slot, for comparing: with two rings, the first one worn.
func worn_for(item_slot: String) -> Dictionary:
	for place: String in Armory.worn_places(item_slot):
		var inst: Dictionary = equipped_instance(place)
		if not inst.is_empty():
			return inst
	return {}

func equipped_list() -> Array:
	var list: Array = []
	for slot: String in Armory.EQUIP_SLOTS:
		var inst: Dictionary = equipped_instance(slot)
		if not inst.is_empty():
			list.append(inst)
	return list

func is_equipped(uid: int) -> bool:
	return equipped.values().has(uid)

# The place where an item is worn ("" if it is not).
func worn_place(uid: int) -> String:
	for slot: String in equipped:
		if int(equipped[slot]) == uid:
			return slot
	return ""

# `place` is the worn place the player aimed at (a ring slot); "" picks the first free one.
func equip(uid: int, place: String = "") -> String:
	var inst: Dictionary = find_instance(uid)
	if inst.is_empty():
		return tr("Item não encontrado.")
	var id: String = str(inst.id)
	var places: Array[String] = Armory.worn_places(Armory.slot_of(id))
	if places.is_empty():
		return tr("Este item não se equipa.")
	if Armory.kind_of(id) == "cosmetic":
		var wanted: String = str(Armory.cosmetic_def(id).gender)
		if wanted != "u" and wanted != gender:
			return tr("Esta skin é do outro gênero.")
	var target: String = place if place in places else places[0]
	if place == "" and places.size() > 1:
		# Two rings: the first empty hand, else the first one is replaced.
		for candidate: String in places:
			if equipped_instance(candidate).is_empty():
				target = candidate
				break
	if place != "" and not place in places:
		return tr("Este item não vai nesse espaço.")
	if places.size() > 1:
		# Never two of the same ring: the other hand must hold a different piece.
		for other: String in places:
			if other != target and str(equipped_instance(other).get("id", "")) == id:
				return tr("Você já usa um anel igual a este.")
	equipped[target] = uid
	if inst.quality == "super":
		# 0.12: a Super Verdadeira binds when equipped; unequipped it can still be sold.
		inst.bound = true
	return ""

func unequip(slot: String) -> String:
	if slot == "arma":
		return tr("Você precisa ter uma arma equipada.")
	equipped.erase(slot)
	return ""

func remove_instance(uid: int) -> void:
	for i in range(inventory.size()):
		if int(inventory[i].uid) == uid:
			inventory.remove_at(i)
			break
	for slot: String in equipped.keys():
		if int(equipped[slot]) == uid:
			equipped.erase(slot)
	ensure_starter()

static func is_keepsake(id: String) -> bool:
	return id == FounderPack.SEAL or id == FounderPack.WINGS or id == str(PetHunt.rules().pass_item) or id.begins_with(BAG_TAB_PREFIX)

func sell(uid: int) -> int:
	var inst: Dictionary = find_instance(uid)
	# The Founder seal and the Passe do Caçador are proofs of a purchase: never sold off.
	if inst.is_empty() or is_equipped(uid) or is_keepsake(str(inst.get("id", ""))):
		return 0
	var value: int = sell_value(inst)
	coins += value
	remove_instance(uid)
	return value

static func sell_value(inst: Dictionary) -> int:
	return maxi(10, item_price(str(inst.get("id", "")), str(inst.get("quality", "normal"))) / 4)

# ---------- Mochila layout (0.15) ----------

const BAG_CELLS: int = 480
# 0.21: the Mochila has pages ("abas") of 40 cells. Two are free; up to six more are sold in
# the Premium tab (each one is a keepsake item aba_mochila_N delivered by the Correio).
const BAG_PAGE_CELLS: int = 40
const BAG_FREE_PAGES: int = 2
const BAG_EXTRA_PAGES: int = 6
const BAG_TAB_PREFIX: String = "aba_mochila_"

static func bag_tab_id(number: int) -> String:
	return BAG_TAB_PREFIX + str(number)

func bag_pages() -> int:
	var pages: int = BAG_FREE_PAGES
	for number in range(1, BAG_EXTRA_PAGES + 1):
		if has_item(bag_tab_id(number)):
			pages += 1
	return pages

func bag_capacity() -> int:
	return bag_pages() * BAG_PAGE_CELLS

# Cells in use: every piece of gear, stack, tool and map in the Mochila (the purchase
# keepsakes do not take room).
func bag_used() -> int:
	var used: int = 0
	for inst: Dictionary in inventory:
		if not is_keepsake(str(inst.get("id", ""))):
			used += 1
	for key: Variant in items:
		if int(items[key]) > 0:
			used += 1
	for tool_id: String in tools:
		if tool_id != "":
			used += 1
	return used + maps.size()

func bag_full() -> bool:
	return bag_used() >= bag_capacity()

func bag_full_message() -> String:
	return tr("Mochila cheia! Venda itens ou compre mais abas na loja Premium.")

# Drops that find the Mochila full are sold on the spot: returns the coins, 0 if it fit.
func add_drop(id: String, quality: String = "normal", level: int = 0, ilvl: int = 0, mods: Array = []) -> int:
	if bag_full():
		var value: int = sell_value({"id": id, "quality": quality})
		coins += value
		return value
	add_instance(id, quality, level, ilvl, mods)
	return 0
const BAG_KEY: String = "^(uid|item|tool|map):[a-z0-9_]{1,32}$"

static func clean_bag(raw: Variant) -> Array[String]:
	# Cell keys from a save or from the network: known shapes only, bounded, no
	# repeats, no empty cells at the end.
	var cells: Array[String] = []
	if not raw is Array:
		return cells
	var pattern: RegEx = RegEx.create_from_string(BAG_KEY)
	var seen: Dictionary = {}
	for value: Variant in (raw as Array).slice(0, BAG_CELLS):
		var key: String = str(value) if value is String else ""
		if key != "" and (pattern.search(key) == null or seen.has(key)):
			key = ""
		seen[key] = true
		cells.append(key)
	while not cells.is_empty() and cells.back() == "":
		cells.pop_back()
	return cells

# The arrangement never reaches past the pages the player has (items left out are put in
# the first free cells by the Mochila screen).
func fit_bag(cells: Array[String]) -> Array[String]:
	var fitted: Array[String] = cells.slice(0, bag_capacity())
	while not fitted.is_empty() and fitted.back() == "":
		fitted.pop_back()
	return fitted

static func item_price(id: String, quality: String = "normal") -> int:
	var def: Dictionary = Armory.definition(id)
	var price: float = float(def.get("price", 0))
	if Armory.kind_of(id) == "weapon":
		price *= float(Armory.quality_def(quality).price)
	return roundi(price)

func buy(id: String, quality: String = "normal") -> String:
	var def: Dictionary = Armory.definition(id)
	if def.is_empty():
		return tr("Item desconhecido.")
	if bool(def.get("super", false)) or quality == "super":
		return tr("Super armas só caem do chefe das instâncias.")
	if quality == "verdadeira":
		return tr("Armas Verdadeiras só caem nas instâncias.")
	if quality == "excelente":
		return tr("Armas Excelentes só caem nas instâncias ou vêm do leilão.")
	if quality != "normal":
		return tr("Item desconhecido.")
	if Armory.kind_of(id) == "aux":
		return tr("Itens auxiliares só vêm de drops ou do leilão.")
	if bool(def.get("drop_only", false)):
		# The shop never lists these (0.31 closes the operation too, which the server also accepts).
		return tr("Este item só cai nas instâncias ou vem do leilão.")
	var price: int = item_price(id, quality)
	if price <= 0:
		return tr("Item desconhecido.")
	if coins < price:
		return tr("Moedas insuficientes.")
	if bag_full():
		return bag_full_message()
	coins -= price
	# Shop items come without bonuses and are bound (never go to the auction).
	var bought: Dictionary = add_instance(id, quality)
	bought.bound = true
	save_profile()
	return ""

func buy_stone(id: String, amount: int = 1) -> String:
	var stone: Dictionary = Armory.stone_def(id)
	if stone.is_empty() or amount < 1 or amount > 99:
		return tr("Item desconhecido.")
	if bool(stone.get("drop_only", false)):
		return tr("Pedras de fortalecimento são encontradas nas instâncias.")
	var price: int = int(stone.price) * amount
	if coins < price:
		return tr("Moedas insuficientes.")
	coins -= price
	add_item(id, amount)
	save_profile()
	return ""

# Keeps only {skin id: colour id} pairs the item data knows (a hand-edited or old save).
static func clean_skin_colors(raw: Variant) -> Dictionary:
	var clean: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return clean
	for key: Variant in raw:
		var turn: Array = Armory.skin_color_turn(str(key), str(raw[key]))
		if not turn.is_empty():
			clean[str(key)] = str(raw[key])
	return clean

# Picks the colour a skin is drawn in ("" for the original). The skin must be owned.
func pick_skin_color(skin_id: String, color_id: String) -> String:
	if not has_item(skin_id):
		return tr("Você não tem essa skin.")
	if color_id == "":
		skin_colors.erase(skin_id)
	elif Armory.skin_color_turn(skin_id, color_id).is_empty():
		return tr("Cor desconhecida.")
	else:
		skin_colors[skin_id] = color_id
	save_profile()
	return ""

func stats(balance: Dictionary) -> Dictionary:
	return Armory.character_stats(level(), equipped_list(), balance)

func look() -> Dictionary:
	var result: Dictionary = Armory.look_for(gender, equipped_list(), skin_only, skin_colors)
	if not active_pet().is_empty():
		result["pet"] = str(active_pet().species)
	if is_founder():
		result["founder"] = FounderPack.look_extras(self)
	return result

func is_founder() -> bool:
	return FounderPack.owns(self)

func entry(balance: Dictionary) -> Dictionary:
	# Battle roster entry for this character.
	var numbers: Dictionary = stats(balance)
	var aux: Dictionary = equipped_instance("auxiliar")
	return {"name": player_name, "level": level(), "gender": gender, "human": true, "tools": tools.duplicate(), "agility": int(numbers.agilidade), "hp": int(numbers.vida), "arma": equipped_instance("arma").duplicate(true), "look": look(), "attrs": numbers.extra.duplicate(), "bonus": numbers.bonus.duplicate(), "aux": str(aux.get("id", "")), "title": title}

# ---------- instance maps ----------

func add_map(item: Dictionary) -> Dictionary:
	var copy: Dictionary = item.duplicate(true)
	copy.uid = next_uid
	next_uid += 1
	maps.append(copy)
	return copy

func find_map(uid: int) -> Dictionary:
	for item in maps:
		if int(item.uid) == uid:
			return item
	return {}

func remove_map(uid: int) -> bool:
	for i in range(maps.size()):
		if int(maps[i].uid) == uid:
			maps.remove_at(i)
			return true
	return false

func maps_for(instance_id: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for item in maps:
		if item.instance == instance_id:
			list.append(item)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level) or (int(a.level) == int(b.level) and a.mods.size() > b.mods.size()))
	return list

# ---------- Ferreiro ----------

func strengthen_cost(inst: Dictionary) -> Dictionary:
	var rules: Dictionary = Armory.data().strengthen
	var level: int = int(inst.get("level", 0))
	if level >= int(rules.max):
		return {}
	var stone: Dictionary = rules.stones[level]
	return {"stone": str(stone.id), "level": level + 1, "amount": 1, "coins": int(rules.coins[level]), "chance": float(rules.success_chance[level])}

func strengthen(uid: int) -> String:
	var inst: Dictionary = find_instance(uid)
	if inst.is_empty() or not Armory.can_strengthen(str(inst.id)):
		return tr("Só armas, camisas, calças e chapéus podem ser fortalecidos.")
	var cost: Dictionary = strengthen_cost(inst)
	if cost.is_empty():
		return tr("Este item já está no +12.")
	if int(items.get(cost.stone, 0)) < 1:
		return tr("Você precisa de uma Pedra de Fortalecimento nível %d.") % int(cost.level)
	if coins < int(cost.coins):
		return tr("Moedas insuficientes.")
	coins -= int(cost.coins)
	items[cost.stone] = int(items[cost.stone]) - 1
	# The authority rolls once; a failed attempt spends the stone and fee but keeps the item.
	if rng.randf() < float(cost.chance):
		inst.level = int(inst.level) + 1
	save_profile()
	return ""

func transfer(source_uid: int, target_uid: int) -> String:
	var source: Dictionary = find_instance(source_uid)
	var target: Dictionary = find_instance(target_uid)
	if source.is_empty() or target.is_empty() or source_uid == target_uid:
		return tr("Escolha dois itens diferentes.")
	if Armory.slot_of(str(source.id)) != Armory.slot_of(str(target.id)):
		return tr("A transferência só funciona entre itens do mesmo tipo.")
	var cost: int = int(Armory.data().strengthen.transfer_coins)
	if coins < cost:
		return tr("Moedas insuficientes.")
	coins -= cost
	var level: int = int(source.level)
	source.level = int(target.level)
	target.level = level
	save_profile()
	return ""

# ---------- moedas (0.10) ----------

func currency_count(id: String) -> int:
	return int(items.get(id, 0))

func craft(currency: String, uid: int) -> String:
	# Uses one currency on a piece of gear; the Espelho Celeste adds a bound copy.
	var inst: Dictionary = find_instance(uid)
	if not Crafting.is_currency(currency):
		return tr("Moeda desconhecida.")
	var error: String = Crafting.check(currency, inst)
	if error != "":
		return error
	if currency_count(currency) <= 0:
		return tr("Você não tem %s.") % Crafting.currency_name(currency)
	if currency == "espelho":
		var copy: Dictionary = inst.duplicate(true)
		copy.uid = next_uid
		next_uid += 1
		copy.mirrored = true
		copy.bound = true
		inventory.append(copy)
	else:
		error = Crafting.apply(currency, inst, rng)
		if error != "":
			return error
	items[currency] = currency_count(currency) - 1
	save_profile()
	return ""

func craft_map(currency: String, uid: int) -> String:
	var item: Dictionary = find_map(uid)
	if not Crafting.is_currency(currency):
		return tr("Moeda desconhecida.")
	var error: String = Crafting.check_map(currency, item)
	if error != "":
		return error
	if currency_count(currency) <= 0:
		return tr("Você não tem %s.") % Crafting.currency_name(currency)
	error = Crafting.apply_map(currency, item, rng)
	if error != "":
		return error
	items[currency] = currency_count(currency) - 1
	save_profile()
	return ""

# ---------- leilão (0.12) ----------

# An item or a map that came by mail (bought, or back from a listing): cleaned like a
# save and given a new uid. {} when it is not valid.
func receive_instance(raw: Variant) -> Dictionary:
	var inst: Dictionary = clean_instance(raw)
	if inst.is_empty():
		return {}
	inst.uid = next_uid
	next_uid += 1
	inventory.append(inst)
	return inst

func receive_map(raw: Variant) -> Dictionary:
	var item: Dictionary = clean_map(raw)
	return {} if item.is_empty() else add_map(item)

# ---------- cupons ----------

func redeem(code: String) -> String:
	code = code.strip_edges().to_upper()
	var coupon: Dictionary = {}
	for entry: Dictionary in Armory.data().coupons:
		if entry.code == code:
			coupon = entry
	if coupon.is_empty():
		return tr("Cupom inválido.")
	if coupons.has(code) and not bool(coupon.get("repeat", false)):
		return tr("Este cupom já foi usado nesta conta.")
	coupons.append(code)
	var before: int = next_uid
	if bool(coupon.get("all", false)):
		for def: Dictionary in Armory.data().weapons:
			if bool(def.get("founder", false)):
				continue  # the Founder Pack comes with the "founder" flag below
			if bool(def.get("super", false)):
				if not has_item(def.id):
					add_instance(def.id, "super")
			else:
				for quality: String in ["normal", "excelente", "verdadeira"]:
					if not has_item(def.id, quality):
						add_instance(def.id, quality)
		for def: Dictionary in Armory.data().auxiliary:
			if not has_item(def.id):
				add_instance(def.id)
		for def: Dictionary in Armory.data().cosmetics:
			# Premium cosmetics only come from the Steam shop.
			if not has_item(def.id) and not bool(def.get("premium", false)):
				add_instance(def.id)
	if bool(coupon.get("hunt_pass", false)) and not has_item(str(PetHunt.rules().pass_item)):
		add_instance(str(PetHunt.rules().pass_item))
	if bool(coupon.get("epicas", false)):
		# The epic skins of the shop (0.28), for testing: premium cosmetics of rarity "epica".
		for def: Dictionary in Armory.data().cosmetics:
			if str(def.get("rarity", "")) == "epica" and not has_item(def.id):
				add_instance(def.id)
	if bool(coupon.get("asas", false)):
		# The wings of the shop (0.32, premium), for testing.
		for def: Dictionary in Armory.data().cosmetics:
			if str(def.slot) == "asas" and not has_item(def.id):
				add_instance(def.id)
	if bool(coupon.get("founder", false)):
		# The whole Founder Pack for testing; Solaris comes at +12 to show every form.
		for id: String in FounderPack.ITEMS:
			if not has_item(id):
				add_instance(id, "normal", 12 if id == FounderPack.WEAPON else 0)
	for raw: Variant in coupon.get("weapons", []):
		add_instance(str(raw[0]), str(raw[1]), int(raw[2]))
	var stones: int = int(coupon.get("stones", 0))
	if stones > 0:
		for stone: Dictionary in Armory.data().strengthen.stones:
			add_item(str(stone.id), stones)
	var map_levels: Array = coupon.get("maps", [])
	if not map_levels.is_empty():
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.randomize()
		var qualities: Array[String] = ["normal", "excelente", "verdadeira", "verdadeira"]
		for instance: Dictionary in InstanceRun.rules().instances:
			for i in range(map_levels.size()):
				add_map(InstanceRun.make_map(str(instance.id), int(map_levels[i]), random, 0.0, qualities[i % qualities.size()]))
	if bool(coupon.get("pets", false)):
		for species: Dictionary in Pets.species_list():
			if not owns_species(str(species.id)):
				grant_pet(str(species.id), true)
	var bundle: Dictionary = coupon.get("currencies", {})
	for id: String in bundle:
		add_item(id, int(bundle[id]))
	# Coupon items are bound: they never go to the auction.
	for inst in inventory:
		if int(inst.uid) >= before:
			inst.bound = true
	for item in maps:
		if int(item.uid) >= before:
			item.bound = true
	coins += int(coupon.get("coins", 0))
	save_profile()
	return tr(str(coupon.desc))

# ---------- ferramentas da sala ----------

func buy_tool(id: String, balance: Dictionary) -> String:
	var tool: Dictionary = {}
	for entry: Dictionary in balance.get("tools", []):
		if entry.id == id:
			tool = entry
	if tool.is_empty():
		return tr("Item desconhecido.")
	if coins < int(tool.price):
		return tr("%s custa %d moedas.") % [tr(str(tool.name)), int(tool.price)]
	if not add_tool(id):
		return tr("Seus 3 espaços (Z, X, C) estão ocupados. Clique numa ferramenta para devolvê-la.")
	coins -= int(tool.price)
	save_profile()
	return ""

func sell_tool(slot: int, balance: Dictionary) -> String:
	if slot < 0 or slot >= tools.size() or tools[slot] == "":
		return tr("Item não encontrado.")
	for entry: Dictionary in balance.get("tools", []):
		if entry.id == tools[slot]:
			coins += int(entry.price)
	tools[slot] = ""
	save_profile()
	return ""

# ---------- pets (0.19, collectibles since 0.30) ----------

func find_pet(uid: int) -> Dictionary:
	for pet: Dictionary in pets:
		if int(pet.uid) == uid:
			return pet
	return {}

func active_pet() -> Dictionary:
	return find_pet(pet_active)

# A new level 1 pet of `species` (caught on a hunt, found in a chest, or bought in the
# shop). False when the Casa dos Mascotes is full; `paid` ignores the limit.
func grant_pet(species: String, paid: bool = false) -> bool:
	# A pet that was paid for (shop, via the Correio) is never refused for lack of room.
	if (pets.size() >= int(Pets.data().max_pets) and not paid) or Pets.species_def(species).is_empty():
		return false
	var pet: Dictionary = {"uid": next_uid, "species": species, "level": 1, "xp": 0}
	next_uid += 1
	pets.append(pet)
	if not pet_album.has(species):
		pet_album.append(species)
	if pet_active < 0:
		pet_active = int(pet.uid)
	return true

# A pet found by a run: it joins the Casa, or turns into the coins of releasing it when the
# Casa is full. Returns true when the pet was kept.
func receive_pet_drop(species: String) -> bool:
	if grant_pet(species):
		return true
	coins += int(Pets.rarity_def(str(Pets.species_def(species).get("rarity", "comum"))).release)
	return false

func owns_species(species: String) -> bool:
	for pet: Dictionary in pets:
		if str(pet.species) == species:
			return true
	return false

# Takes back a pet granted by `grant_pet` (a mail claim that has to be undone).
func remove_pet(uid: int) -> void:
	var pet: Dictionary = find_pet(uid)
	if pet.is_empty():
		return
	pets.erase(pet)
	if pet_active == uid:
		pet_active = -1

# The companion that follows the character in battle (looks only).
func pet_equip(uid: int) -> String:
	if find_pet(uid).is_empty():
		return tr("Mascote não encontrado.")
	pet_active = -1 if pet_active == uid else uid
	return ""

func pet_release(uid: int) -> String:
	var pet: Dictionary = find_pet(uid)
	if pet.is_empty():
		return tr("Mascote não encontrado.")
	if uid == pet_active:
		return tr("Tire o mascote ativo antes de libertá-lo.")
	coins += int(Pets.rarity_def(str(Pets.species_def(str(pet.species)).rarity)).release)
	pets.erase(pet)
	save_profile()
	return ""

# ---------- Caçada dos Mascotes (0.20) ----------

func hunt_now() -> int:
	return hunt_clock if hunt_clock > 0 else int(Time.get_unix_time_from_system()) + hunt_skew

# Starts (or changes) the hunt. What the old setup earned is settled first, so changing
# the team never loses time. `team` are pet uids (1 to PetHunt team_max).
func hunt_set(zone: String, tier: int, team: Array) -> String:
	if Pets.element_def(zone).is_empty():
		return tr("Zona desconhecida.")
	if tier < 1 or tier > PetHunt.unlocked_tier(hunt, zone):
		return tr("Este nível de caça ainda está bloqueado.")
	var uids: Array = []
	for raw: Variant in team:
		if (raw is int or raw is float) and not find_pet(int(raw)).is_empty() and not uids.has(int(raw)):
			uids.append(int(raw))
	if uids.is_empty():
		return tr("Escolha pelo menos um mascote para o time.")
	if uids.size() > int(PetHunt.rules().team_max):
		return tr("O time tem no máximo %d mascotes.") % int(PetHunt.rules().team_max)
	var now: int = hunt_now()
	if bool(hunt.active):
		PetHunt.settle(self, now)
	var changed: bool = str(hunt.zone) != zone or int(hunt.tier) != tier
	hunt.zone = zone
	hunt.tier = tier
	hunt.team = uids
	hunt.active = true
	hunt.since = now
	if changed or int(hunt.seed) <= 1:
		hunt.seed = rng.randi_range(2, 2000000000)
	save_profile()
	return ""

func hunt_collect() -> String:
	if not bool(hunt.active):
		return tr("Nenhuma caçada em andamento.")
	PetHunt.settle(self, hunt_now())
	save_profile()
	return ""

func hunt_stop() -> String:
	if not bool(hunt.active):
		return ""
	PetHunt.settle(self, hunt_now())
	hunt.active = false
	save_profile()
	return ""

# ---------- operações (online) ----------

# Everything a player can change in the profile goes through here. Offline the client
# calls it directly; online the server calls it for the player and sends the new profile
# back. Arguments come from the network, so their types are checked.
const OPS: Array[String] = ["toggle_equip", "sell", "buy", "buy_stone", "strengthen", "transfer", "craft", "craft_map", "redeem", "buy_tool", "sell_tool", "create", "bag_layout", "mission_claim", "streak_claim", "tutorial", "title_set", "season_claim", "founder_fx", "pet_equip", "pet_release", "hunt_set", "hunt_collect", "hunt_stop", "skin_only", "skin_color"]

static func arg_int(args: Array, index: int) -> int:
	if index >= args.size() or not (args[index] is int or args[index] is float):
		return -1
	return int(clampf(float(args[index]), -1.0, 1.0e12))

static func arg_str(args: Array, index: int) -> String:
	if index >= args.size() or not args[index] is String:
		return ""
	return (args[index] as String).substr(0, 64)

static func valid_name(value: String) -> bool:
	# 2–14 letters (accents allowed), digits, spaces, "_", "-" and "." (same rule as the API).
	if value.length() < 2 or value.length() > 14 or value.strip_edges() != value:
		return false
	var pattern: RegEx = RegEx.create_from_string("^[\\p{L}\\p{N} _.-]+$")
	return pattern.search(value) != null

# Result: {"error": "" or the reason, "message": text for the player}. `balance` is
# combat.json (tools); `test_coupons` lets the test coupons work (always offline).
func apply_op(op: String, args: Array, balance: Dictionary, test_coupons: bool = true) -> Dictionary:
	var error: String = ""
	var message: String = ""
	match op:
		"toggle_equip":
			var uid: int = arg_int(args, 0)
			var inst: Dictionary = find_instance(uid)
			if inst.is_empty():
				error = tr("Item não encontrado.")
			else:
				error = unequip(worn_place(uid)) if is_equipped(uid) else equip(uid, arg_str(args, 1))
		"sell":
			var value: int = sell(arg_int(args, 0))
			if is_keepsake(str(find_instance(arg_int(args, 0)).get("id", ""))):
				error = tr("Este item é a prova de uma compra e não pode ser vendido.")
			elif value <= 0:
				error = tr("Item não encontrado.")
			else:
				message = tr("+%d moedas") % value
		"buy":
			error = buy(arg_str(args, 0), arg_str(args, 1) if arg_str(args, 1) != "" else "normal")
		"buy_stone":
			error = buy_stone(arg_str(args, 0), arg_int(args, 1))
		"strengthen":
			error = strengthen(arg_int(args, 0))
		"transfer":
			error = transfer(arg_int(args, 0), arg_int(args, 1))
		"craft":
			error = craft(arg_str(args, 0), arg_int(args, 1))
		"craft_map":
			error = craft_map(arg_str(args, 0), arg_int(args, 1))
		"redeem":
			var code: String = arg_str(args, 0).strip_edges().to_upper()
			var coupon: Dictionary = {}
			for entry: Dictionary in Armory.data().coupons:
				if entry.code == code:
					coupon = entry
			if coupon.is_empty() or (bool(coupon.get("test", false)) and not test_coupons):
				error = tr("Cupom inválido.")
			elif coupons.has(code) and not bool(coupon.get("repeat", false)):
				error = tr("Este cupom já foi usado nesta conta.")
			else:
				message = redeem(code)
		"bag_layout":
			# Cosmetic only: the new arrangement of the Mochila (an empty list sorts it).
			bag = fit_bag(clean_bag(args[0] if not args.is_empty() else []))
			save_profile()
		"founder_fx":
			# Cosmetic only: turn one Founder effect on or off (Founders only).
			var key: String = arg_str(args, 0)
			if not is_founder():
				error = tr("Só Fundadores têm efeitos do Founder Pack.")
			elif not key in FounderPack.FX_KEYS:
				error = tr("Efeito desconhecido.")
			else:
				founder_fx[key] = args.size() > 1 and args[1] == true
				save_profile()
		"skin_only":
			# Cosmetic only: draw the skin alone (no hat, glasses, wings or hair dye).
			skin_only = not args.is_empty() and typeof(args[0]) == TYPE_BOOL and args[0]
			save_profile()
		"skin_color":
			error = pick_skin_color(arg_str(args, 0), arg_str(args, 1))
		"pet_equip":
			error = pet_equip(arg_int(args, 0))
		"pet_release":
			error = pet_release(arg_int(args, 0))
		"hunt_set":
			error = hunt_set(arg_str(args, 0), arg_int(args, 1), (args[2] as Array).slice(0, 10) if args.size() > 2 and args[2] is Array else [])
		"hunt_collect":
			error = hunt_collect()
		"hunt_stop":
			error = hunt_stop()
		"mission_claim":
			var result: Dictionary = MissionsBoard.claim(self, arg_str(args, 0))
			error = str(result.error)
			message = str(result.message)
		"streak_claim":
			var streak_result: Dictionary = MissionsBoard.streak_claim(self)
			error = str(streak_result.error)
			message = str(streak_result.message)
		"tutorial":
			error = Tutorial.apply(self, arg_str(args, 0), balance)
			if error == "":
				save_profile()
		"title_set":
			error = title_set(arg_str(args, 0))
		"season_claim":
			var claimed_title: String = season_claim(arg_int(args, 0))
			if Ranked.valid_title(claimed_title):
				message = tr("Título conquistado: %s") % Ranked.title_text(claimed_title)
			else:
				error = claimed_title
		"buy_tool":
			error = buy_tool(arg_str(args, 0), balance)
		"sell_tool":
			error = sell_tool(arg_int(args, 0), balance)
		"create":
			var chosen: String = arg_str(args, 0).strip_edges()
			if created:
				error = tr("O personagem já foi criado.")
			elif not valid_name(chosen):
				error = tr("Nome inválido: use de 2 a 14 letras ou números.")
			else:
				player_name = chosen
				gender = "f" if arg_str(args, 1) == "f" else "m"
				created = true
				save_profile()
		_:
			error = tr("Operação desconhecida.")
	if error == "" and (MissionsBoard.note_op(self, op) or op in ["toggle_equip", "sell", "mission_claim", "streak_claim", "pet_equip"]):
		save_profile()
	return {"error": error, "message": message}
