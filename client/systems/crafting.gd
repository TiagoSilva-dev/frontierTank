class_name Crafting
extends RefCounted

# 0.10: random bonus attributes on gear and the currencies that change them, like the
# currency of PoE 2 (shared/balance/items.json → affixes, currencies). Every currency
# has a use and using it spends it, which is what keeps its value between players.
#   Brasa    Normal → Excelente with 1 bonus        Coroa   Excelente → Verdadeira, +1 bonus
#   Estrela  adds 1 bonus (up to the quality limit)  Tormenta rerolls every bonus
#   Solar    rerolls only the values                 Eclipse removes 1 bonus
#   Espelho Celeste duplicates a piece of gear (the copy is bound and cannot be changed)
# The same currencies work on instance maps (threat and reward modifiers). A bonus is
# {id, tier, value}: tier 1 (F1) is the best and only rolls on high item levels.
# Offline the rolls are local; the server will own them later.

const MAP_CURRENCIES: Array[String] = ["brasa", "coroa", "estrela", "tormenta", "solar", "eclipse"]

static func rules() -> Dictionary:
	return Armory.data().affixes

static func currencies() -> Array:
	return Armory.data().currencies

static func currency_def(id: String) -> Dictionary:
	for def: Dictionary in currencies():
		if def.id == id:
			return def
	return {}

static func is_currency(id: String) -> bool:
	return not currency_def(id).is_empty()

# ---------- bonus attributes ----------

static func can_have_mods(id: String) -> bool:
	return Armory.slot_of(id) in rules().slots

static func pool_for(id: String) -> Array:
	return rules().weapon if Armory.slot_of(id) == "arma" else rules().armor

static func affix_def(id: String) -> Dictionary:
	for list: String in ["weapon", "armor"]:
		for def: Dictionary in rules()[list]:
			if def.id == id:
				return def
	return {}

static func count_range(quality: String) -> Array:
	return rules().counts.get(quality, [0, 0])

static func max_mods(quality: String) -> int:
	return int(count_range(quality)[1])

static func item_level(inst: Dictionary) -> int:
	# Shop and coupon items have no item level: they craft like level 1 drops.
	return clampi(int(inst.get("ilvl", 1)), 1, 16)

static func allowed_tiers(ilvl: int) -> Array[int]:
	var list: Array[int] = []
	var tiers: Array = rules().tiers
	for i in range(tiers.size()):
		if ilvl >= int(tiers[i].ilvl):
			list.append(i + 1)
	return list

static func tier_name(tier: int) -> String:
	# "F" is the Portuguese faixa; English shows T1–T5 (tiers).
	return Lang.t("F%d") % tier

static func roll_value(def: Dictionary, tier: int, rng: RandomNumberGenerator) -> int:
	var span: Array = def.values[clampi(tier, 1, def.values.size()) - 1]
	return rng.randi_range(int(span[0]), int(span[1]))

static func roll_affix(inst: Dictionary, rng: RandomNumberGenerator, rarity: float = 0.0) -> Dictionary:
	# A bonus the item does not have yet; better tiers need a higher item level and
	# get likelier with the map's rarity.
	var taken: Array = (inst.get("mods", []) as Array).map(func(mod: Dictionary) -> String: return str(mod.id))
	var pool: Array = pool_for(str(inst.get("id", ""))).filter(func(def: Dictionary) -> bool: return not taken.has(def.id))
	if pool.is_empty():
		return {}
	var def: Dictionary = pool[rng.randi() % pool.size()]
	var tiers: Array = rules().tiers
	var allowed: Array[int] = allowed_tiers(item_level(inst))
	var weights: Array[float] = []
	var total: float = 0.0
	for tier in allowed:
		var weight: float = float(tiers[tier - 1].weight) * (1.0 + rarity if tier < tiers.size() else 1.0)
		weights.append(weight)
		total += weight
	var ticket: float = rng.randf() * total
	var chosen: int = allowed[-1]
	for i in range(allowed.size()):
		ticket -= weights[i]
		if ticket <= 0.0:
			chosen = allowed[i]
			break
	return {"id": str(def.id), "tier": chosen, "value": roll_value(def, chosen, rng)}

static func roll_mods(inst: Dictionary, rng: RandomNumberGenerator, rarity: float = 0.0) -> Array:
	# Normal 0, Excelente 1–2, Verdadeira 3–4, Super Verdadeira always 4.
	if not can_have_mods(str(inst.get("id", ""))):
		return []
	var span: Array = count_range(str(inst.get("quality", "normal")))
	var count: int = rng.randi_range(int(span[0]), int(span[1]))
	var shaped: Dictionary = {"id": inst.get("id", ""), "ilvl": item_level(inst), "mods": []}
	for i in range(count):
		var mod: Dictionary = roll_affix(shaped, rng, rarity)
		if mod.is_empty():
			break
		shaped.mods.append(mod)
	return shaped.mods

static func currency_name(id: String) -> String:
	return Lang.t(str(currency_def(id).get("name", id)))

static func currency_desc(id: String) -> String:
	return Lang.t(str(currency_def(id).get("desc", "")))

static func mod_text(mod: Dictionary) -> String:
	var def: Dictionary = affix_def(str(mod.get("id", "")))
	var text: String = Lang.t(str(def.get("text", mod.get("id", ""))))
	return text % int(mod.get("value", 0)) if text.contains("%d") else text

static func describe(inst: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for mod: Dictionary in inst.get("mods", []):
		lines.append("%s  %s" % [tier_name(int(mod.get("tier", 5))), mod_text(mod)])
	return lines

static func item_bonus(inst: Dictionary) -> Dictionary:
	var total: Dictionary = {}
	for mod: Dictionary in inst.get("mods", []):
		total[str(mod.id)] = int(total.get(str(mod.id), 0)) + int(mod.get("value", 0))
	return total

static func valid_mods(raw: Variant, id: String) -> Array:
	# Save loading: keep only bonuses this kind of item can have.
	var list: Array = []
	if not raw is Array or not can_have_mods(id):
		return list
	var allowed: Array = pool_for(id).map(func(def: Dictionary) -> String: return str(def.id))
	for mod: Variant in raw:
		if mod is Dictionary and allowed.has(str(mod.get("id", ""))):
			list.append({"id": str(mod.id), "tier": clampi(int(mod.get("tier", 5)), 1, rules().tiers.size()), "value": int(mod.get("value", 0))})
	return list

# ---------- currencies on gear ----------

static func check(currency: String, inst: Dictionary) -> String:
	# Why this currency cannot be used on this item ("" when it can).
	var id: String = str(inst.get("id", ""))
	if inst.is_empty():
		return Lang.t("Escolha um item.")
	if not can_have_mods(id):
		return Lang.t("Só armas, roupas, chapéus, óculos e asas recebem bônus.")
	if bool(inst.get("mirrored", false)):
		return Lang.t("Itens espelhados não podem ser modificados.")
	var quality: String = str(inst.get("quality", "normal"))
	var mods: Array = inst.get("mods", [])
	match currency:
		"brasa":
			if quality != "normal":
				return Lang.t("A Brasa só funciona em itens Normais.")
		"coroa":
			if quality != "excelente":
				return Lang.t("A Coroa só funciona em itens Excelentes.")
		"estrela":
			if quality == "normal":
				return Lang.t("A Estrela precisa de um item Excelente ou melhor.")
			if mods.size() >= max_mods(quality):
				return Lang.t("Este item já tem o máximo de bônus da sua qualidade.")
		"tormenta":
			if quality == "normal":
				return Lang.t("A Tormenta precisa de um item Excelente ou melhor.")
		"solar", "eclipse":
			if mods.is_empty():
				return Lang.t("Este item não tem bônus.")
		"espelho":
			pass
		_:
			return Lang.t("Moeda desconhecida.")
	return ""

static func apply(currency: String, inst: Dictionary, rng: RandomNumberGenerator) -> String:
	# Changes the item in place (the Espelho Celeste copy is made by the profile).
	var error: String = check(currency, inst)
	if error != "":
		return error
	if not inst.has("mods"):
		inst.mods = []
	match currency:
		"brasa":
			inst.quality = "excelente"
			inst.mods = []
			inst.mods.append(roll_affix(inst, rng))
		"coroa":
			inst.quality = "verdadeira"
			inst.mods.append(roll_affix(inst, rng))
		"estrela":
			inst.mods.append(roll_affix(inst, rng))
		"tormenta":
			inst.mods = roll_mods(inst, rng)
		"solar":
			for mod: Dictionary in inst.mods:
				mod.value = roll_value(affix_def(str(mod.id)), int(mod.tier), rng)
		"eclipse":
			inst.mods.remove_at(rng.randi() % inst.mods.size())
	inst.mods = inst.mods.filter(func(mod: Dictionary) -> bool: return not mod.is_empty())
	return ""

# ---------- currencies on instance maps ----------

static func map_rules() -> Dictionary:
	return InstanceRun.rules().map_items

static func map_count(quality: String) -> Array:
	for entry: Dictionary in map_rules().qualities:
		if entry.id == quality:
			return entry.mods
	return [0, 0]

static func roll_map_mod(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var taken: Array = (item.get("mods", []) as Array).map(func(mod: Dictionary) -> String: return str(mod.id))
	var pool: Array = map_rules().mods.filter(func(def: Dictionary) -> bool: return not taken.has(def.id))
	if pool.is_empty():
		return {}
	var def: Dictionary = pool[rng.randi() % pool.size()]
	return {"id": str(def.id), "value": map_value(def, rng)}

static func map_value(def: Dictionary, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(int(def.range[0]), int(def.range[1])) if def.has("range") else 1

static func check_map(currency: String, item: Dictionary) -> String:
	if item.is_empty():
		return Lang.t("Escolha um mapa.")
	if not currency in MAP_CURRENCIES:
		return Lang.t("O Espelho Celeste só duplica equipamentos.") if currency == "espelho" else Lang.t("Moeda desconhecida.")
	var quality: String = str(item.get("quality", "normal"))
	var mods: Array = item.get("mods", [])
	match currency:
		"brasa":
			if quality != "normal":
				return Lang.t("A Brasa só funciona em mapas Normais.")
		"coroa":
			if quality != "excelente":
				return Lang.t("A Coroa só funciona em mapas Excelentes.")
		"estrela":
			if quality == "normal":
				return Lang.t("A Estrela precisa de um mapa Excelente ou melhor.")
			if mods.size() >= int(map_count(quality)[1]):
				return Lang.t("Este mapa já tem o máximo de atributos da sua qualidade.")
		"tormenta":
			if quality == "normal":
				return Lang.t("A Tormenta precisa de um mapa Excelente ou melhor.")
		"solar":
			if not mods.any(func(mod: Dictionary) -> bool: return InstanceRun.mod_def(str(mod.id)).has("range")):
				return Lang.t("Este mapa não tem valores para rerolar.")
		"eclipse":
			if mods.is_empty():
				return Lang.t("Este mapa não tem atributos.")
	return ""

static func apply_map(currency: String, item: Dictionary, rng: RandomNumberGenerator) -> String:
	var error: String = check_map(currency, item)
	if error != "":
		return error
	if not item.has("mods"):
		item.mods = []
	match currency:
		"brasa":
			item.quality = "excelente"
			item.mods = []
			item.mods.append(roll_map_mod(item, rng))
		"coroa":
			item.quality = "verdadeira"
			item.mods.append(roll_map_mod(item, rng))
		"estrela":
			item.mods.append(roll_map_mod(item, rng))
		"tormenta":
			var span: Array = map_count(str(item.quality))
			item.mods = []
			for i in range(rng.randi_range(int(span[0]), int(span[1]))):
				item.mods.append(roll_map_mod(item, rng))
		"solar":
			for mod: Dictionary in item.mods:
				mod.value = map_value(InstanceRun.mod_def(str(mod.id)), rng)
		"eclipse":
			item.mods.remove_at(rng.randi() % item.mods.size())
	item.mods = item.mods.filter(func(mod: Dictionary) -> bool: return not mod.is_empty())
	return ""

# ---------- drops ----------

static func drop_weights(map_level: int) -> Array:
	# Rare currencies only drop on high map levels (Solar from level 5, the Espelho
	# Celeste from 10) and get likelier as the level rises.
	var list: Array = []
	for def: Dictionary in currencies():
		if map_level >= int(def.min_level):
			list.append([str(def.id), float(def.weight) + float(def.per_level) * map_level])
	return list

static func roll_currency(map_level: int, rng: RandomNumberGenerator) -> String:
	var pool: Array = drop_weights(map_level)
	var total: float = 0.0
	for entry: Array in pool:
		total += float(entry[1])
	var ticket: float = rng.randf() * total
	for entry: Array in pool:
		ticket -= float(entry[1])
		if ticket <= 0.0:
			return str(entry[0])
	return str(pool[0][0])
