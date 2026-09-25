class_name PlayerProfile
extends RefCounted

# Single local character. This file is never an authority for an online economy.
# v3 keeps an inventory of item instances ({uid, id, quality, level, compose}) and the
# equipped slot -> uid map; stones and crystals stay as counters in `items`.
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

func _init() -> void:
	if path_override != "":
		save_path = path_override
	ensure_starter()

func load_profile() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		return
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
			items[key] = maxi(0, int(saved_items[key]))
	inventory.clear()
	equipped.clear()
	next_uid = maxi(1, int(data.get("next_uid", 1)))
	var saved_inventory: Variant = data.get("inventory", [])
	if saved_inventory is Array:
		for raw: Variant in saved_inventory:
			if raw is Dictionary and Armory.kind_of(str(raw.get("id", ""))) != "":
				var inst: Dictionary = {"uid": int(raw.get("uid", next_uid)), "id": str(raw.id), "quality": str(raw.get("quality", "normal")), "level": clampi(int(raw.get("level", 0)), 0, 12), "compose": raw.get("compose", {})}
				inventory.append(inst)
				next_uid = maxi(next_uid, int(inst.uid) + 1)
	var saved_equipped: Variant = data.get("equipped", {})
	if saved_equipped is Dictionary:
		for slot: String in saved_equipped:
			if find_instance(int(saved_equipped[slot])).size() > 0:
				equipped[slot] = int(saved_equipped[slot])
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

func ensure_starter() -> void:
	# Every account starts with the basic look (t-shirt and shorts) and a Quebra Tijolos.
	if equipped_instance("arma").is_empty():
		var weapon: Dictionary = {}
		for inst in inventory:
			if Armory.slot_of(str(inst.id)) == "arma":
				weapon = inst
				break
		if weapon.is_empty():
			weapon = add_instance("quebra_tijolos")
		equipped["arma"] = weapon.uid

func save_profile() -> void:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": 3, "created": created, "name": player_name, "gender": gender, "experience": experience, "victories": victories, "matches": matches, "coins": coins, "merits": merits, "tools": tools, "items": items, "inventory": inventory, "equipped": equipped, "next_uid": next_uid, "coupons": coupons}))

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

func add_instance(id: String, quality: String = "normal", level: int = 0) -> Dictionary:
	if Armory.kind_of(id) != "weapon":
		quality = "normal"
	elif bool(Armory.weapon_def(id).get("super", false)):
		quality = "super"
	var inst: Dictionary = {"uid": next_uid, "id": id, "quality": quality, "level": clampi(level, 0, 12), "compose": {}}
	next_uid += 1
	inventory.append(inst)
	return inst

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
		return "Item não encontrado."
	var id: String = str(inst.id)
	if Armory.kind_of(id) == "cosmetic":
		var wanted: String = str(Armory.cosmetic_def(id).gender)
		if wanted != "u" and wanted != gender:
			return "Esta roupa é do outro gênero."
	equipped[Armory.slot_of(id)] = uid
	return ""

func unequip(slot: String) -> String:
	if slot == "arma":
		return "Você precisa ter uma arma equipada."
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

func sell(uid: int) -> int:
	var inst: Dictionary = find_instance(uid)
	if inst.is_empty() or is_equipped(uid):
		return 0
	var value: int = maxi(10, item_price(str(inst.id), str(inst.quality)) / 4)
	coins += value
	remove_instance(uid)
	return value

static func item_price(id: String, quality: String = "normal") -> int:
	var def: Dictionary = Armory.definition(id)
	var price: float = float(def.get("price", 0))
	if Armory.kind_of(id) == "weapon":
		price *= float(Armory.quality_def(quality).price)
	return roundi(price)

func buy(id: String, quality: String = "normal") -> String:
	var def: Dictionary = Armory.definition(id)
	if def.is_empty():
		return "Item desconhecido."
	if bool(def.get("super", false)) or quality == "super":
		return "Super armas só caem na Instância."
	var price: int = item_price(id, quality)
	if coins < price:
		return "Moedas insuficientes."
	coins -= price
	add_instance(id, quality)
	save_profile()
	return ""

func buy_stone(id: String, amount: int = 1) -> String:
	var stone: Dictionary = Armory.stone_def(id)
	if stone.is_empty():
		return "Item desconhecido."
	var price: int = int(stone.price) * amount
	if coins < price:
		return "Moedas insuficientes."
	coins -= price
	add_item(id, amount)
	save_profile()
	return ""

func stats(balance: Dictionary) -> Dictionary:
	return Armory.character_stats(level(), equipped_list(), balance)

func look() -> Dictionary:
	return Armory.look_for(gender, equipped_list())

func entry(balance: Dictionary) -> Dictionary:
	# Battle roster entry for this character.
	var numbers: Dictionary = stats(balance)
	var aux: Dictionary = equipped_instance("auxiliar")
	return {"name": player_name, "level": level(), "gender": gender, "human": true, "tools": tools.duplicate(), "agility": int(numbers.agilidade), "hp": int(numbers.vida), "arma": equipped_instance("arma").duplicate(), "look": look(), "attrs": numbers.extra.duplicate(), "aux": str(aux.get("id", ""))}

# ---------- Ferreiro ----------

func stone_points() -> int:
	var total: int = 0
	for stone: Dictionary in Armory.data().strengthen.stones:
		total += int(items.get(stone.id, 0)) * int(stone.points)
	return total

func strengthen_cost(inst: Dictionary) -> Dictionary:
	var rules: Dictionary = Armory.data().strengthen
	var level: int = int(inst.get("level", 0))
	if level >= int(rules.max):
		return {}
	return {"points": int(rules.points[level]), "coins": int(rules.coins[level])}

func strengthen(uid: int) -> String:
	var inst: Dictionary = find_instance(uid)
	if inst.is_empty() or not Armory.can_strengthen(str(inst.id)):
		return "Só armas, roupas e chapéus podem ser fortalecidos."
	var cost: Dictionary = strengthen_cost(inst)
	if cost.is_empty():
		return "Este item já está no +12."
	if stone_points() < int(cost.points):
		return "Pedras insuficientes: precisa de %d pontos de pedra, você tem %d." % [int(cost.points), stone_points()]
	if coins < int(cost.coins):
		return "Moedas insuficientes."
	coins -= int(cost.coins)
	# Spend the smallest stones first; a bigger stone breaks into points when needed.
	var needed: int = int(cost.points)
	var stones: Array = Armory.data().strengthen.stones
	for stone: Dictionary in stones:
		while needed > 0 and int(items.get(stone.id, 0)) > 0 and int(stone.points) <= needed:
			items[stone.id] = int(items[stone.id]) - 1
			needed -= int(stone.points)
	for stone: Dictionary in stones:
		if needed > 0 and int(items.get(stone.id, 0)) > 0:
			items[stone.id] = int(items[stone.id]) - 1
			var change: int = int(stone.points) - needed
			needed = 0
			# Give the leftover back as level I stones.
			add_item(str(stones[0].id), change)
	inst.level = int(inst.level) + 1
	save_profile()
	return ""

func fuse(stone_id: String) -> String:
	var rules: Dictionary = Armory.data().strengthen
	var stones: Array = rules.stones
	for i in range(stones.size() - 1):
		if stones[i].id == stone_id:
			if int(items.get(stone_id, 0)) < int(rules.fusion_count):
				return "Precisa de %d pedras iguais." % int(rules.fusion_count)
			if coins < int(rules.fusion_coins):
				return "Moedas insuficientes."
			coins -= int(rules.fusion_coins)
			items[stone_id] = int(items[stone_id]) - int(rules.fusion_count)
			add_item(str(stones[i + 1].id))
			save_profile()
			return ""
	return "Esta pedra já é do nível máximo."

func transfer(source_uid: int, target_uid: int) -> String:
	var source: Dictionary = find_instance(source_uid)
	var target: Dictionary = find_instance(target_uid)
	if source.is_empty() or target.is_empty() or source_uid == target_uid:
		return "Escolha dois itens diferentes."
	if Armory.slot_of(str(source.id)) != Armory.slot_of(str(target.id)):
		return "A transferência só funciona entre itens do mesmo tipo."
	var cost: int = int(Armory.data().strengthen.transfer_coins)
	if coins < cost:
		return "Moedas insuficientes."
	coins -= cost
	var level: int = int(source.level)
	var composed: Dictionary = source.get("compose", {}).duplicate()
	source.level = int(target.level)
	source.compose = target.get("compose", {}).duplicate()
	target.level = level
	target.compose = composed
	save_profile()
	return ""

func compose(uid: int, attr: String) -> String:
	var rules: Dictionary = Armory.data().strengthen.compose
	var inst: Dictionary = find_instance(uid)
	if inst.is_empty() or not attr in Armory.ATTRS:
		return "Escolha um item e um atributo."
	var composed: Dictionary = inst.get("compose", {})
	var total: int = 0
	for key: String in composed:
		total += int(composed[key])
	if total / int(rules.amount) >= int(rules.max):
		return "Este item já recebeu %d composições." % int(rules.max)
	if int(items.get(rules.item, 0)) <= 0:
		return "Você precisa de um Cristal Dourado."
	if coins < int(rules.coins):
		return "Moedas insuficientes."
	coins -= int(rules.coins)
	items[rules.item] = int(items[rules.item]) - 1
	composed[attr] = int(composed.get(attr, 0)) + int(rules.amount)
	inst.compose = composed
	save_profile()
	return ""

# ---------- cupons ----------

func redeem(code: String) -> String:
	code = code.strip_edges().to_upper()
	var coupon: Dictionary = {}
	for entry: Dictionary in Armory.data().coupons:
		if entry.code == code:
			coupon = entry
	if coupon.is_empty():
		return "Cupom inválido."
	if coupons.has(code) and not bool(coupon.get("repeat", false)):
		return "Este cupom já foi usado nesta conta."
	coupons.append(code)
	if bool(coupon.get("all", false)):
		for def: Dictionary in Armory.data().weapons:
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
			if not has_item(def.id):
				add_instance(def.id)
	for raw: Variant in coupon.get("weapons", []):
		add_instance(str(raw[0]), str(raw[1]), int(raw[2]))
	var stones: int = int(coupon.get("stones", 0))
	if stones > 0:
		for stone: Dictionary in Armory.data().strengthen.stones:
			add_item(str(stone.id), stones)
	var crystals: int = int(coupon.get("crystals", 0))
	if crystals > 0:
		add_item(str(Armory.data().strengthen.compose.item), crystals)
	coins += int(coupon.get("coins", 0))
	save_profile()
	return str(coupon.desc)
