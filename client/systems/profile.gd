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
const SAVE_PATH: String = "user://profile.json"
# Tests point this at a scratch file so they never touch the player's save.
static var path_override: String = ""
var save_path: String = SAVE_PATH
var created: bool = false
var player_name: String = "Explorador"
var gender: String = "m"
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
	var saved_equipped: Variant = data.get("equipped", {})
	if saved_equipped is Dictionary:
		for slot: String in saved_equipped:
			var worn: Dictionary = find_instance(int(saved_equipped[slot]))
			if worn.size() > 0:
				equipped[slot] = int(saved_equipped[slot])
				if worn.quality == "super":
					# 0.12: Super Verdadeiras bind when equipped (saves from before too).
					worn.bound = true
	maps.clear()
	var saved_maps: Variant = data.get("maps", [])
	if saved_maps is Array:
		for raw: Variant in saved_maps:
			var item: Dictionary = clean_map(raw)
			if not item.is_empty():
				item.uid = int(raw.get("uid", next_uid))
				maps.append(item)
				next_uid = maxi(next_uid, int(item.uid) + 1)
	var saved_pity: Variant = data.get("pity", {})
	pity = {}
	if saved_pity is Dictionary:
		for key: String in saved_pity:
			pity[key] = maxi(0, int(saved_pity[key]))
	missions = MissionsBoard.clean_state(data.get("missions", {}))
	load_pets(data)
	hunt = PetHunt.clean_state(data.get("hunt", {}))
	if remote and data.has("clock"):
		hunt_skew = int(data.clock) - int(Time.get_unix_time_from_system())
	bag = fit_bag(clean_bag(data.get("bag", [])))
	founder_fx = FounderPack.clean_fx(data.get("founder_fx", {}))
	var saved_coupons: Variant = data.get("coupons", [])
	coupons.clear()
	if saved_coupons is Array:
		for code: Variant in saved_coupons:
			coupons.append(str(code))
	if inventory.is_empty() and data.has("weapon"):
		# v2 save: keep the chosen slot of the old arsenal as the starting weapon.
		var inst: Dictionary = add_instance(Armory.legacy_instance(int(data.weapon)).id)
		equipped["arma"] = inst.uid
	ensure_starter()
	return migrated

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
	return {"version": 8, "pets": pets, "pet_active": pet_active, "pet_album": pet_album, "hunt": hunt, "clock": hunt_now(), "created": created, "name": player_name, "gender": gender, "experience": experience, "victories": victories, "matches": matches, "coins": coins, "merits": merits, "tools": tools, "items": items, "inventory": inventory, "equipped": equipped, "next_uid": next_uid, "coupons": coupons, "maps": maps, "pity": pity, "missions": missions, "bag": bag, "founder_fx": founder_fx}

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

func equipped_list() -> Array:
	var list: Array = []
	for slot: String in Armory.EQUIP_SLOTS:
		var inst: Dictionary = equipped_instance(slot)
		if not inst.is_empty():
			list.append(inst)
	return list

func is_equipped(uid: int) -> bool:
	return equipped.values().has(uid)

func equip(uid: int) -> String:
	var inst: Dictionary = find_instance(uid)
	if inst.is_empty():
		return tr("Item não encontrado.")
	var id: String = str(inst.id)
	if not Armory.slot_of(id) in Armory.EQUIP_SLOTS:
		return tr("Este item não se equipa.")
	if Armory.kind_of(id) == "cosmetic":
		var wanted: String = str(Armory.cosmetic_def(id).gender)
		if wanted != "u" and wanted != gender:
			return tr("Esta roupa é do outro gênero.")
	equipped[Armory.slot_of(id)] = uid
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
	return id == FounderPack.SEAL or id == str(PetHunt.rules().pass_item) or id.begins_with(BAG_TAB_PREFIX)

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

func stats(balance: Dictionary) -> Dictionary:
	return Armory.character_stats(level(), equipped_list(), balance, pet_bonus())

func look() -> Dictionary:
	var result: Dictionary = Armory.look_for(gender, equipped_list())
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
	return {"name": player_name, "level": level(), "gender": gender, "human": true, "tools": tools.duplicate(), "agility": int(numbers.agilidade), "hp": int(numbers.vida), "arma": equipped_instance("arma").duplicate(true), "look": look(), "attrs": numbers.extra.duplicate(), "bonus": numbers.bonus.duplicate(), "aux": str(aux.get("id", ""))}

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
		return tr("Só armas, roupas e chapéus podem ser fortalecidos.")
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
	var egg_count_each: int = int(coupon.get("eggs", 0))
	if egg_count_each > 0:
		for egg: Dictionary in Pets.eggs():
			add_item(str(egg.id), egg_count_each)
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

# ---------- pets (0.19) ----------

func find_pet(uid: int) -> Dictionary:
	for pet: Dictionary in pets:
		if int(pet.uid) == uid:
			return pet
	return {}

func active_pet() -> Dictionary:
	return find_pet(pet_active)

# What the active pet and the album add to the battle numbers (Armory.character_stats).
func pet_bonus() -> Dictionary:
	var result: Dictionary = Pets.bonus(active_pet())
	var album: Dictionary = Pets.album_bonus(pet_album)
	for key: String in album:
		result[key] = int(result.get(key, 0)) + int(album[key])
	return result

func egg_count(egg_id: String) -> int:
	return int(items.get(egg_id, 0))

# Opens one egg. The new pet is the one with the highest uid afterwards (the client reads
# it from the profile the server sends back). Returns the error, "" when it hatched.
func hatch(egg_id: String, forced: RandomNumberGenerator = null) -> String:
	if not Pets.is_egg(egg_id) or egg_count(egg_id) <= 0:
		return tr("Você não tem este ovo.")
	if pets.size() >= int(Pets.data().max_pets):
		return tr("A Casa dos Mascotes está cheia. Liberte algum mascote.")
	var random: RandomNumberGenerator = forced if forced != null else rng
	var rarity: int = Pets.roll_rarity(egg_id, pity, random)
	var species: Dictionary = Pets.roll_species(egg_id, rarity, random)
	items[egg_id] = egg_count(egg_id) - 1
	if egg_count(egg_id) <= 0:
		items.erase(egg_id)
	pity["egg_epico"] = 0 if rarity >= 2 else int(pity.get("egg_epico", 0)) + 1
	pity["egg_lendario"] = 0 if rarity >= 3 else int(pity.get("egg_lendario", 0)) + 1
	grant_pet(str(species.id))
	save_profile()
	return ""

# A new level 1 pet of `species` (hatched, or caught on a hunt). False when the Casa dos
# Mascotes is full.
func grant_pet(species: String) -> bool:
	if pets.size() >= int(Pets.data().max_pets) or Pets.species_def(species).is_empty():
		return false
	var pet: Dictionary = {"uid": next_uid, "species": species, "level": 1, "xp": 0, "stars": 0}
	next_uid += 1
	pets.append(pet)
	if not pet_album.has(species):
		pet_album.append(species)
	if pet_active < 0:
		pet_active = int(pet.uid)
	return true

func pet_equip(uid: int) -> String:
	if find_pet(uid).is_empty():
		return tr("Mascote não encontrado.")
	pet_active = -1 if pet_active == uid else uid
	return ""

func pet_feed(uid: int) -> String:
	var pet: Dictionary = find_pet(uid)
	if pet.is_empty():
		return tr("Mascote não encontrado.")
	if int(pet.level) >= Pets.cap(int(pet.stars)):
		return tr("Nível máximo para %d estrelas. Evolua o mascote para subir mais.") % int(pet.stars)
	var price: int = int(Pets.data().xp.feed_coins)
	if coins < price:
		return tr("Moedas insuficientes.")
	coins -= price
	Pets.add_xp(pet, int(Pets.data().xp.feed_xp))
	save_profile()
	return ""

# One more star: consumes another pet of the same species and some coins; half of the
# experience of the consumed pet carries over.
func pet_evolve(uid: int, fodder_uid: int) -> String:
	var pet: Dictionary = find_pet(uid)
	var fodder: Dictionary = find_pet(fodder_uid)
	if pet.is_empty() or fodder.is_empty() or uid == fodder_uid:
		return tr("Mascote não encontrado.")
	if pet.species != fodder.species:
		return tr("O mascote consumido precisa ser da mesma espécie.")
	if int(pet.stars) >= int(Pets.data().max_stars):
		return tr("Este mascote já está com 5 estrelas.")
	if fodder_uid == pet_active:
		return tr("Tire o mascote ativo antes de consumi-lo.")
	var price: int = int(Pets.data().evolve_coins[int(pet.stars)])
	if coins < price:
		return tr("Moedas insuficientes.")
	coins -= price
	var carried: int = Pets.total_xp(fodder) / 2
	pets.erase(fodder)
	pet.stars = int(pet.stars) + 1
	Pets.add_xp(pet, carried)
	save_profile()
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

# After a battle the active pet earns experience from what the player earned.
func pet_battle_xp(exp_gain: int, pve: bool) -> Dictionary:
	var pet: Dictionary = active_pet()
	if pet.is_empty():
		return {}
	var rules: Dictionary = Pets.data().xp
	var amount: int = int(rules.battle_base) + roundi(float(exp_gain) * float(rules.battle_exp_share))
	if pve:
		amount = roundi(amount * float(rules.pve_scale))
	var before: int = int(pet.level)
	Pets.add_xp(pet, amount)
	return {"uid": int(pet.uid), "species": str(pet.species), "xp": amount, "level_before": before, "level_after": int(pet.level), "capped": int(pet.level) >= Pets.cap(int(pet.stars))}

# ---------- operações (online) ----------

# Everything a player can change in the profile goes through here. Offline the client
# calls it directly; online the server calls it for the player and sends the new profile
# back. Arguments come from the network, so their types are checked.
const OPS: Array[String] = ["toggle_equip", "sell", "buy", "buy_stone", "strengthen", "transfer", "craft", "craft_map", "redeem", "buy_tool", "sell_tool", "create", "bag_layout", "mission_claim", "founder_fx", "pet_hatch", "pet_equip", "pet_feed", "pet_evolve", "pet_release", "hunt_set", "hunt_collect", "hunt_stop"]

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
				error = unequip(Armory.slot_of(str(inst.id))) if is_equipped(uid) else equip(uid)
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
		"pet_hatch":
			error = hatch(arg_str(args, 0))
		"pet_equip":
			error = pet_equip(arg_int(args, 0))
		"pet_feed":
			error = pet_feed(arg_int(args, 0))
		"pet_evolve":
			error = pet_evolve(arg_int(args, 0), arg_int(args, 1))
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
	if error == "" and op in ["toggle_equip", "sell", "mission_claim", "pet_equip"]:
		save_profile()
	return {"error": error, "message": message}
