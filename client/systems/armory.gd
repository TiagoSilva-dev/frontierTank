class_name Armory
extends RefCounted

# Catalog of weapons, qualities, auxiliary items and cosmetics (shared/balance/items.json)
# and everything derived from it: strengthened damage, aura colours, item names and the
# character attributes shown in the Mochila (Ataque, Defesa, Agilidade, Sorte...).

const PATH: String = "res://shared/balance/items.json"
# Old saves, bots and tests pick weapons by index; indexes map onto the classic arsenal.
const LEGACY_ORDER: Array[String] = ["quebra_tijolos", "fogo_intenso", "canhao_arco_iris", "vento_de_deus", "cesto_newton", "kit_medico", "eletrodomestico", "trovao", "desentupidor"]
const EQUIP_SLOTS: Array[String] = ["arma", "auxiliar", "roupa", "chapeu", "oculos", "cabelo", "asas"]
const SLOT_NAMES: Dictionary = {"arma": "Arma", "auxiliar": "Auxiliar", "roupa": "Roupa", "chapeu": "Chapéu", "oculos": "Óculos", "cabelo": "Cabelo", "asas": "Asas"}
const ATTRS: Array[String] = ["ataque", "defesa", "agilidade", "sorte"]
const ATTR_NAMES: Dictionary = {"ataque": "Ataque", "defesa": "Defesa", "agilidade": "Agilidade", "sorte": "Sorte"}

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

# Battle art sizes (0.8): projectiles and the weapon on the back are drawn bigger. Only
# the drawing changes; hit_radius, crater radius and damage never read these.
static func visual(key: String) -> float:
	return float(data().get("visual", {}).get(key, 1.0))

static func _find(list: String, id: String) -> Dictionary:
	for entry: Dictionary in data()[list]:
		if entry.id == id:
			return entry
	return {}

static func weapon_def(id: String) -> Dictionary:
	return _find("weapons", id)

static func quality_def(id: String) -> Dictionary:
	var found: Dictionary = _find("qualities", id)
	return found if not found.is_empty() else data().qualities[0]

static func aux_def(id: String) -> Dictionary:
	return _find("auxiliary", id)

static func cosmetic_def(id: String) -> Dictionary:
	return _find("cosmetics", id)

static func stone_def(id: String) -> Dictionary:
	for stone: Dictionary in data().strengthen.stones:
		if stone.id == id:
			return stone
	return {}

static func definition(id: String) -> Dictionary:
	for list: String in ["weapons", "auxiliary", "cosmetics"]:
		var found: Dictionary = _find(list, id)
		if not found.is_empty():
			return found
	return {}

static func kind_of(id: String) -> String:
	if not weapon_def(id).is_empty():
		return "weapon"
	if not aux_def(id).is_empty():
		return "aux"
	if not cosmetic_def(id).is_empty():
		return "cosmetic"
	return ""

static func slot_of(id: String) -> String:
	match kind_of(id):
		"weapon":
			return "arma"
		"aux":
			return "auxiliar"
		"cosmetic":
			return str(cosmetic_def(id).slot)
	return ""

static func can_strengthen(id: String) -> bool:
	return slot_of(id) in data().strengthen.slots

# ---------- levels, tiers and auras ----------

static func tier_for_level(level: int) -> int:
	# Weapon art evolves at +9, +10 and +12, like the DDTank icons.
	if level >= 12:
		return 3
	if level >= 10:
		return 2
	if level >= 9:
		return 1
	return 0

static func aura(level: int) -> Dictionary:
	for entry: Dictionary in data().auras:
		if level >= int(entry.from) and level <= int(entry.to):
			return entry
	return {}

static func aura_color(level: int) -> Color:
	var entry: Dictionary = aura(level)
	return Color(str(entry.color)) if not entry.is_empty() else Color.TRANSPARENT

# ---------- names and art ----------

static func item_name(inst: Dictionary, with_level: bool = true) -> String:
	var id: String = str(inst.get("id", ""))
	var def: Dictionary = definition(id)
	var text: String = str(def.get("name", id))
	if kind_of(id) == "weapon":
		match str(inst.get("quality", "normal")):
			"excelente":
				text += " Excelente"
			"verdadeira":
				text = "Verdadeiro " + text
	var level: int = int(inst.get("level", 0))
	if with_level and level > 0:
		text += " +%d" % level
	return text

static func quality_color(inst: Dictionary) -> Color:
	# 0.10: gear (hats, glasses, wings, outfits) has qualities too, set by the Brasa and
	# the Coroa; only weapons scale their damage and attributes with it.
	if kind_of(str(inst.get("id", ""))) == "":
		return Color("f4ead6")
	return Color(str(quality_def(str(inst.get("quality", "normal"))).color))

static func weapon_icon(id: String, level: int = 0) -> String:
	for tier in range(tier_for_level(level), -1, -1):
		var path: String = "res://assets/weapons/%s/tier%d.png" % [id, tier]
		if ResourceLoader.exists(path):
			return path
	return "res://assets/weapons/canhao_explorador.png"

static func projectile_path(weapon_id: String, key: String, level: int = 0) -> String:
	if key != "icon":
		var path: String = "res://assets/projectiles/%s.png" % key
		if ResourceLoader.exists(path):
			return path
	return weapon_icon(weapon_id, level)

static func skin_path(skin: String, direction: String = "south") -> String:
	return "res://assets/characters/%s/%s.png" % [skin, direction]

static func cosmetic_art(art: String, view: String) -> String:
	# view: "front" (menus) or "side" (prone battle pose).
	return "res://assets/cosmetics/%s/%s.png" % [art, view]

static func icon_path(inst: Dictionary) -> String:
	var id: String = str(inst.get("id", ""))
	match kind_of(id):
		"weapon":
			return weapon_icon(id, int(inst.get("level", 0)))
		"aux":
			return str(aux_def(id).icon)
		"cosmetic":
			var def: Dictionary = cosmetic_def(id)
			match str(def.slot):
				"roupa":
					return skin_path(str(def.skin))
				"cabelo":
					return "res://assets/cosmetics/cabelo/icon.png"
				_:
					var art: String = cosmetic_art(str(def.art), "icon")
					return art if ResourceLoader.exists(art) else cosmetic_art(str(def.art), "front")
	return ""

static func icon_tint(inst: Dictionary) -> Color:
	var def: Dictionary = cosmetic_def(str(inst.get("id", "")))
	if def.get("slot", "") == "cabelo":
		return Color(str(def.dye))
	return Color.WHITE

static func load_icon(inst: Dictionary) -> Texture2D:
	var path: String = icon_path(inst)
	if path == "" or not ResourceLoader.exists(path):
		return PixelIcons.get_icon("bag")
	var texture: Texture2D = load(path)
	if cosmetic_def(str(inst.get("id", ""))).get("slot", "") == "roupa":
		return UiKit.head_crop(texture, 1.0)
	return texture

# ---------- battle numbers ----------

static func legacy_instance(index: int) -> Dictionary:
	return {"id": LEGACY_ORDER[posmod(index, LEGACY_ORDER.size())], "quality": "normal", "level": 0}

static func build_weapon(inst: Dictionary) -> Dictionary:
	var def: Dictionary = weapon_def(str(inst.get("id", "")))
	if def.is_empty():
		def = weapon_def(LEGACY_ORDER[0])
		inst = {"id": def.id, "quality": "normal", "level": 0}
	var quality: Dictionary = quality_def(str(inst.get("quality", "normal")))
	var level: int = clampi(int(inst.get("level", 0)), 0, int(data().strengthen.max))
	var weapon: Dictionary = def.duplicate(true)
	var bonus: float = float(data().strengthen.damage_bonus[level])
	# The "+% dano" bonus (0.10) multiplies on top; strengthening never changes bonuses.
	var extra: float = float(Crafting.item_bonus(inst).get("dano", 0)) / 100.0
	weapon.damage = roundi(float(def.damage) * float(quality.damage) * (1.0 + bonus) * (1.0 + extra))
	weapon.base_name = def.name
	weapon.name = item_name(inst)
	weapon.level = level
	weapon.quality = quality.id
	weapon.tier = tier_for_level(level)
	return weapon

static func weapon_for_entry(entry: Dictionary) -> Dictionary:
	var inst: Variant = entry.get("arma", {})
	if not inst is Dictionary or (inst as Dictionary).is_empty():
		inst = legacy_instance(int(entry.get("weapon", 0)))
	return build_weapon(inst)

static func item_attrs(inst: Dictionary) -> Dictionary:
	var id: String = str(inst.get("id", ""))
	var def: Dictionary = definition(id)
	var result: Dictionary = {"ataque": 0, "defesa": 0, "agilidade": 0, "sorte": 0}
	var scale: float = 1.0
	if kind_of(id) == "weapon":
		scale = float(quality_def(str(inst.get("quality", "normal"))).attrs)
	# Strengthening makes the item stronger: +10% of its attributes per level.
	if can_strengthen(id):
		scale *= 1.0 + float(data().strengthen.attr_per_level) * int(inst.get("level", 0))
	var base: Dictionary = def.get("attrs", {})
	for key: String in base:
		result[key] += roundi(float(base[key]) * scale)
	var composed: Dictionary = inst.get("compose", {})
	for key: String in composed:
		if result.has(key):
			result[key] += int(composed[key])
	# Flat bonus attributes (0.10) are added after strengthening, which only scales the base.
	var mods: Dictionary = Crafting.item_bonus(inst)
	for key: String in mods:
		if result.has(key):
			result[key] += int(mods[key])
	if slot_of(id) in ["roupa", "chapeu"]:
		result.defesa += int(inst.get("level", 0)) * int(data().strengthen.defense_per_level)
	return result

static func character_stats(level: int, equipped: Array, balance: Dictionary) -> Dictionary:
	# Level gives the base; items add the "extra" part that battles use.
	var extra: Dictionary = {"ataque": 0, "defesa": 0, "agilidade": 0, "sorte": 0}
	var bonus_hp: int = 0
	var weapon_inst: Dictionary = {}
	# Battle bonuses from the random attributes (0.10): % damage, critical and POW
	# damage, starting POW, skills that may cost nothing, life, energy, delay, wind, heal.
	var bonus: Dictionary = {}
	for inst: Dictionary in equipped:
		var attrs: Dictionary = item_attrs(inst)
		for key: String in attrs:
			extra[key] += int(attrs[key])
		var mods: Dictionary = Crafting.item_bonus(inst)
		for key: String in mods:
			if not extra.has(key):
				bonus[key] = int(bonus.get(key, 0)) + int(mods[key])
		if slot_of(str(inst.id)) in ["roupa", "chapeu"]:
			bonus_hp += int(inst.get("level", 0)) * int(data().strengthen.hp_per_level)
		if slot_of(str(inst.id)) == "arma":
			weapon_inst = inst
	var weapon: Dictionary = build_weapon(weapon_inst)
	var agility: int = int(balance.base_agility) + level * int(balance.agility_per_level) + extra.agilidade / 2
	return {
		"ataque": 100 + level * 6 + int(extra.ataque),
		"defesa": 100 + level * 6 + int(extra.defesa),
		"agilidade": agility,
		"sorte": 100 + level * 6 + int(extra.sorte),
		"dano": int(weapon.damage),
		"protecao": int(extra.defesa),
		"vida": int(balance.base_hp) + level * int(balance.hp_per_level) + bonus_hp + int(bonus.get("vida", 0)),
		"energia": int(balance.energy) + agility / 30 + int(bonus.get("energia", 0)),
		"extra": extra,
		"bonus": bonus,
		"weapon": weapon,
	}

static func bonus_limit(bonus: Dictionary, key: String) -> float:
	# Summed bonuses with a cap (wind resistance, free skills) as a 0–1 fraction.
	var cap: float = float(Crafting.rules().get("limits", {}).get(key, 100))
	return minf(cap, float(bonus.get(key, 0))) / 100.0

static func attack_scale(extra: Dictionary) -> float:
	return 1.0 + float(extra.get("ataque", 0)) / 1000.0

static func defense_scale(extra: Dictionary) -> float:
	var defense: float = float(extra.get("defesa", 0))
	return 1.0 - defense / (defense + 800.0)

static func crit_chance(extra: Dictionary) -> float:
	return minf(0.25, float(extra.get("sorte", 0)) / 1500.0)

# ---------- looks ----------

static func look_for(gender: String, equipped: Array) -> Dictionary:
	var look: Dictionary = {"skin": "base_f" if gender == "f" else "base_m", "hair": "", "hat": "", "glasses": "", "wings": "", "weapon": LEGACY_ORDER[0], "weapon_level": 0, "clothes_level": 0}
	for inst: Dictionary in equipped:
		var id: String = str(inst.id)
		var level: int = int(inst.get("level", 0))
		match slot_of(id):
			"arma":
				look.weapon = id
				look.weapon_level = level
			"roupa":
				var skin: String = str(cosmetic_def(id).skin)
				if ResourceLoader.exists(skin_path(skin)):
					look.skin = skin
				look.clothes_level = level
			"chapeu":
				look.hat = str(cosmetic_def(id).art)
			"oculos":
				look.glasses = str(cosmetic_def(id).art)
			"asas":
				look.wings = str(cosmetic_def(id).art)
			"cabelo":
				look.hair = str(cosmetic_def(id).dye)
	if not ResourceLoader.exists(skin_path(str(look.skin))):
		look.skin = "lia" if gender == "f" else "nilo"
	return look

static func random_loadout(rng: RandomNumberGenerator, level: int, gender: String, skin: String) -> Dictionary:
	# Bots carry a DDTank-like mix of gear: stronger bots show higher auras.
	var weapon: Dictionary = {"id": LEGACY_ORDER[rng.randi() % LEGACY_ORDER.size()], "quality": ["normal", "excelente", "verdadeira"][mini(2, rng.randi() % (1 + level / 8))], "level": clampi(rng.randi_range(level / 3 - 2, level / 2 + 1), 0, 12)}
	if level >= 20 and rng.randf() < 0.15:
		weapon = {"id": ["cabeca_de_boi", "bumerangue_amor", "lanca_antiga"][rng.randi() % 3], "quality": "super", "level": clampi(level / 3, 0, 12)}
	var equipped: Array = [weapon]
	for slot: String in ["chapeu", "oculos", "asas"]:
		# Bot skins drawn with their own headwear do not get a second hat.
		if slot == "chapeu" and skin in ["bot_pirata", "bot_maga", "bot_robo", "bot_princesa", "bot_ninja"]:
			continue
		if rng.randf() < 0.3 + level * 0.01:
			var pool: Array = []
			for def: Dictionary in data().cosmetics:
				if def.slot == slot:
					pool.append(def.id)
			equipped.append({"id": pool[rng.randi() % pool.size()], "level": 0})
	var look: Dictionary = look_for(gender, equipped)
	look.skin = skin if skin != "" else look.skin
	if rng.randf() < 0.35:
		look.clothes_level = clampi(rng.randi_range(level / 4, level / 2), 1, 12)
	var extra: Dictionary = {"ataque": 0, "defesa": 0, "agilidade": 0, "sorte": 0}
	for inst: Dictionary in equipped:
		var attrs: Dictionary = item_attrs(inst)
		for key: String in attrs:
			extra[key] += int(attrs[key])
	return {"arma": weapon, "look": look, "attrs": extra}
