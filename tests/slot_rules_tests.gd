extends SceneTree

# 0.24 (docs/SKINS.md): the rule of gold and the skin. Appearance slots (skin, hair) never
# carry attributes and are the only ones the premium shop may sell; power slots (weapon,
# shirt, trousers, hat, glasses, wings...) carry the attributes and are never sold for
# money. A v10 save with an outfit becomes a skin plus a shirt and trousers.

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func run_tests() -> void:
	PlayerProfile.path_override = "user://slot_rules_test_profile.json"
	var cosmetics: Array = Armory.data().cosmetics
	# --- the rule of gold
	var bad_cosmetic: Array = []
	var bad_power: Array = []
	for def: Dictionary in cosmetics:
		var slot: String = str(def.slot)
		if slot in Armory.COSMETIC_SLOTS and not (def.attrs as Dictionary).is_empty():
			bad_cosmetic.append(def.id)
		if slot in Armory.POWER_SLOTS and bool(def.get("premium", false)):
			bad_power.append(def.id)
	check(bad_cosmetic.is_empty(), "no skin or hair carries attributes %s" % [bad_cosmetic])
	check(bad_power.is_empty(), "no premium item takes a power slot %s" % [bad_power])
	check(Armory.COSMETIC_SLOTS == ["skin", "cabelo"] and not "roupa" in Armory.EQUIP_SLOTS, "the outfit slot is the skin now")
	for slot: String in ["skin", "camisa", "calca", "chapeu", "oculos", "cabelo", "asas", "arma", "auxiliar"]:
		check(slot in Armory.EQUIP_SLOTS, "%s is an equipment slot" % slot)
	var worn_slots: Array = Armory.COSMETIC_SLOTS + Armory.POWER_SLOTS
	check(cosmetics.all(func(def: Dictionary) -> bool: return str(def.slot) in worn_slots or str(def.slot) == "selo"), "every wearable has a known slot")
	# Every product of the store passes the stricter validation and touches no power slot.
	var products_ok: bool = true
	for entry: Dictionary in PremiumStore.products():
		products_ok = products_ok and PremiumStore.valid(entry)
		for id: Variant in entry.items:
			var def: Dictionary = Armory.definition(str(id))
			products_ok = products_ok and (str(def.get("slot", "")) in Armory.COSMETIC_SLOTS or str(def.get("slot", "")) == "selo" or str(id) in PremiumStore.LEGACY_POWER)
	check(products_ok, "the store sells only skins, hair, keepsakes and the Solaris of the Founder Pack")
	check(not PremiumStore.valid({"sku": "x", "steam_item_id": 9, "items": ["camisa_guerra"], "prices": {"USD": 99}}), "a shirt can never be sold for money")
	check(not PremiumStore.valid({"sku": "x", "steam_item_id": 9, "items": ["chapeu_coroa"], "prices": {"USD": 99}}), "a hat can never be sold for money")
	# --- shirts and trousers
	var pure: PlayerProfile = PlayerProfile.new()
	pure.coins = 5000
	check(pure.buy("camisa_guerra") == "" and pure.buy("calca_guerra") == "" and pure.buy("roupa_samurai") == "", "shirts, trousers and skins are bought with gold")
	var shirt: Dictionary = pure.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "camisa_guerra")[0]
	var trousers: Dictionary = pure.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "calca_guerra")[0]
	var skin: Dictionary = pure.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "roupa_samurai")[0]
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var naked: Dictionary = Armory.character_stats(1, pure.equipped_list(), balance)
	check(pure.equip(int(skin.uid)) == "" and pure.equip(int(shirt.uid)) == "" and pure.equip(int(trousers.uid)) == "", "skin, shirt and trousers are worn together")
	var dressed: Dictionary = Armory.character_stats(1, pure.equipped_list(), balance)
	check(int(dressed.extra.defesa) - int(naked.extra.defesa) == 50, "the shirt and the trousers give the defence (30 + 20), the skin gives none")
	check(int(Armory.item_attrs(skin).defesa) == 0 and Armory.item_attrs(skin).values().all(func(v: int) -> bool: return v == 0), "a skin has no attributes")
	check(pure.look().skin == "roupa_samurai", "the skin changes the sprite")
	check(not pure.look().has("camisa") and not pure.look().has("calca"), "shirt and trousers are not drawn on the character")
	check(Armory.can_strengthen("camisa_guerra") and Armory.can_strengthen("calca_guerra") and Armory.can_strengthen("chapeu_kabuto") and not Armory.can_strengthen("roupa_samurai"), "shirts and trousers take the Ferreiro, the skin does not")
	shirt.level = 5
	trousers.level = 5
	var stronger: Dictionary = Armory.character_stats(1, pure.equipped_list(), balance)
	check(int(stronger.vida) - int(dressed.vida) == 2 * 5 * int(Armory.data().strengthen.hp_per_level), "strengthening raises the life of the shirt and the trousers")
	check(pure.look().clothes_level == 5, "the strength glow follows the shirt")
	# --- the Founder skin carries its wings
	var founder: Dictionary = Armory.look_for("m", [{"id": "roupa_paladino_sol", "quality": "normal", "level": 0}, {"id": "asas_anjo", "quality": "normal", "level": 0}])
	check(str(founder.wings) == "asas_aurora", "the Paladino skin draws its own wings over the ones worn")
	var plain_look: Dictionary = Armory.look_for("m", [{"id": "roupa_samurai", "quality": "normal", "level": 0}, {"id": "asas_anjo", "quality": "normal", "level": 0}])
	check(str(plain_look.wings) == "asas_anjo", "an ordinary skin leaves the worn wings")
	var gift: PlayerProfile = PlayerProfile.new()
	var aurora: Dictionary = gift.add_instance("asas_aurora")
	check(gift.equip(int(aurora.uid)) != "" and PlayerProfile.is_keepsake("asas_aurora"), "the Aurora wings are a keepsake of the skin, not worn on their own")
	# --- the v10 save with outfits
	var old: Dictionary = {"version": 10, "gender": "m", "coins": 100, "next_uid": 9, "inventory": [
		{"uid": 1, "id": "quebra_tijolos", "quality": "normal", "level": 0, "bound": true},
		{"uid": 2, "id": "roupa_samurai", "quality": "verdadeira", "level": 7, "ilvl": 12, "mods": [{"id": "vida", "tier": 2, "value": 130}]},
		{"uid": 3, "id": "roupa_maga", "quality": "normal", "level": 0},
		{"uid": 4, "id": "asas_aurora", "quality": "normal", "level": 0},
		{"uid": 5, "id": "chapeu_coroa", "quality": "normal", "level": 2},
		{"uid": 8, "id": "asas_anjo", "quality": "normal", "level": 0}],
		"equipped": {"arma": 1, "roupa": 2, "asas": 4, "chapeu": 5}}
	var migrated: PlayerProfile = PlayerProfile.new()
	migrated.load_data(old)
	var uids: Dictionary = {}
	for inst: Dictionary in migrated.inventory:
		check(not uids.has(int(inst.uid)), "uid %d is unique after the migration" % int(inst.uid))
		uids[int(inst.uid)] = true
	var coat: Dictionary = migrated.find_instance(2)
	check(coat.id == "roupa_samurai" and int(coat.level) == 0 and coat.quality == "normal" and (coat.mods as Array).is_empty() and not coat.has("ilvl"), "the old outfit becomes a plain skin")
	check(int(migrated.equipped.get("skin", -1)) == 2 and not migrated.equipped.has("roupa"), "the worn outfit becomes the worn skin")
	check(not migrated.equipped.has("asas"), "wings that are now a keepsake leave the wings slot")
	check(int(migrated.equipped.get("chapeu", -1)) == 5 and int(migrated.equipped.get("arma", -1)) == 1, "other equipment stays")
	var new_shirt: Dictionary = migrated.equipped_instance("camisa")
	var new_trousers: Dictionary = migrated.equipped_instance("calca")
	check(new_shirt.id == "camisa_guerra" and int(new_shirt.level) == 7 and new_shirt.quality == "verdadeira" and int(new_shirt.ilvl) == 12 and new_shirt.mods.size() == 1, "the shirt takes the level, quality and bonuses of the old outfit")
	check(new_trousers.id == "calca_guerra" and new_trousers.quality == "verdadeira" and int(new_trousers.level) == 0, "the trousers come with the same quality")
	check(migrated.has_item("camisa_aventureiro") and migrated.has_item("calca_aventureiro"), "an unworn outfit also leaves a shirt and trousers in the bag")
	check(int(migrated.to_data().version) == 11, "saves are written as v11")
	var again: PlayerProfile = PlayerProfile.new()
	again.load_data(migrated.to_data())
	check(again.inventory.size() == migrated.inventory.size() and int(again.equipped.get("camisa", -1)) == int(new_shirt.uid), "a v11 save is read as it is, nothing is granted twice")
	# --- rings and amulet (0.26)
	for slot: String in ["anel1", "anel2", "amuleto"]:
		check(slot in Armory.EQUIP_SLOTS, "%s is an equipment slot" % slot)
	check(Armory.worn_places("anel") == ["anel1", "anel2"] and Armory.worn_places("amuleto") == ["amuleto"] and Armory.worn_places("selo").is_empty(), "a ring goes in either hand, nothing else shares a place")
	var charms: Array = cosmetics.filter(func(def: Dictionary) -> bool: return str(def.slot) == "amuleto")
	var rings: Array = cosmetics.filter(func(def: Dictionary) -> bool: return str(def.slot) == "anel")
	check(rings.size() >= 5 and charms.size() >= 4, "the game has rings and amulets")
	check(charms.all(func(def: Dictionary) -> bool: return int(def.get("hp", 0)) > 0), "every amulet gives life")
	check(rings.all(func(def: Dictionary) -> bool: return not def.has("hp") and not (def.attrs as Dictionary).is_empty()), "rings give attributes and no base life")
	check(cosmetics.all(func(def: Dictionary) -> bool: return ResourceLoader.exists(Armory.icon_path({"id": def.id}))), "every wearable has its icon")
	check(not Armory.can_strengthen("anel_bronze") and not Armory.can_strengthen("amuleto_pedra"), "rings and amulets do not go to the Ferreiro")
	check(Crafting.can_have_mods("anel_bronze") and Crafting.can_have_mods("amuleto_pedra"), "rings and amulets roll bonuses")
	var ring_ids: Array = Crafting.pool_for("anel_bronze").map(func(def: Dictionary) -> String: return str(def.id))
	var charm_ids: Array = Crafting.pool_for("amuleto_pedra").map(func(def: Dictionary) -> String: return str(def.id))
	check(ring_ids == ["ataque", "sorte", "critico", "pow"] and charm_ids == ["vida", "defesa", "energia", "delay"], "rings pull offence and amulets pull life and defence")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 26
	var rolled: Array = Crafting.roll_mods({"id": "amuleto_pedra", "quality": "super", "ilvl": 16, "mods": []}, rng)
	check(rolled.size() == 4 and rolled.all(func(mod: Dictionary) -> bool: return str(mod.id) in charm_ids), "a Super amulet rolls its four bonuses from its own list")
	var jewels: PlayerProfile = PlayerProfile.new()
	jewels.coins = 9999
	for id: String in ["anel_bronze", "anel_safira", "amuleto_pedra"]:
		check(jewels.buy(id) == "", "%s is sold for gold" % id)
	var bronze: int = int(jewels.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "anel_bronze")[0].uid)
	var sapphire: int = int(jewels.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "anel_safira")[0].uid)
	var charm: Dictionary = jewels.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "amuleto_pedra")[0]
	var bare: Dictionary = Armory.character_stats(1, jewels.equipped_list(), balance)
	check(jewels.equip(bronze) == "" and jewels.equip(sapphire) == "", "two rings are worn together")
	check(int(jewels.equipped.get("anel1", -1)) == bronze and int(jewels.equipped.get("anel2", -1)) == sapphire, "the first ring takes the first hand and the second the other")
	check(jewels.apply_op("buy", ["anel_bronze"], balance).error == "", "a second bronze ring is bought")
	var twin: int = int(jewels.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "anel_bronze" and int(inst.uid) != bronze)[0].uid)
	check(jewels.equip(twin, "anel2") != "" and int(jewels.equipped.anel2) == sapphire, "the same ring is never worn twice")
	check(jewels.equip(twin, "anel1") == "" and int(jewels.equipped.anel1) == twin, "aiming at a hand replaces the ring there")
	check(jewels.equip(bronze, "chapeu") != "", "a ring does not go in another slot")
	check(jewels.apply_op("toggle_equip", [twin], balance).error == "" and not jewels.equipped.has("anel1"), "toggling a worn ring takes it off the hand it is in")
	check(jewels.apply_op("toggle_equip", [bronze, "anel1"], balance).error == "" and int(jewels.equipped.anel1) == bronze, "the op takes the hand to wear a ring in")
	check(jewels.apply_op("toggle_equip", [int(charm.uid)], balance).error == "", "the amulet is worn")
	var jeweled: Dictionary = Armory.character_stats(1, jewels.equipped_list(), balance)
	check(int(jeweled.vida) - int(bare.vida) == 150, "an amulet adds its base life (150)")
	check(int(jeweled.extra.ataque) - int(bare.extra.ataque) == 25 and int(jeweled.extra.defesa) - int(bare.extra.defesa) == 25 + 15, "rings and amulet add their attributes")
	for pair: Array in [["normal", 150], ["excelente", 195], ["verdadeira", 240], ["super", 300]]:
		check(Armory.item_hp({"id": "amuleto_pedra", "quality": pair[0]}) == pair[1], "a %s amulet gives %d life" % pair)
	check(Armory.item_hp({"id": "anel_bronze", "quality": "super"}) == 0 and Armory.item_hp({"id": "chapeu_coroa"}) == 0, "only amulets carry base life")
	var kept: PlayerProfile = PlayerProfile.new()
	kept.load_data(jewels.to_data())
	check(int(kept.equipped.get("anel1", -1)) == bronze and int(kept.equipped.get("anel2", -1)) == sapphire and int(kept.equipped.get("amuleto", -1)) == int(charm.uid), "rings and amulet survive a save")
	var stray: PlayerProfile = PlayerProfile.new()
	var hat: Dictionary = stray.add_instance("chapeu_coroa")
	var loose: Dictionary = stray.to_data()
	loose.equipped = {"anel2": int(hat.uid)}
	var reread: PlayerProfile = PlayerProfile.new()
	reread.load_data(loose)
	check(not reread.equipped.has("anel2"), "an item in the wrong place of a save is dropped")
	check(not PremiumStore.valid({"sku": "x", "steam_item_id": 9, "items": ["anel_bronze"], "prices": {"USD": 99}}) and not PremiumStore.valid({"sku": "x", "steam_item_id": 9, "items": ["amuleto_pedra"], "prices": {"USD": 99}}), "a ring or an amulet can never be sold for money")
	# Bots wear them too.
	var worn_by_bots: int = 0
	var rolls: RandomNumberGenerator = RandomNumberGenerator.new()
	rolls.seed = 5
	for i in range(80):
		var loadout: Dictionary = Armory.random_loadout(rolls, 30, "m", "")
		worn_by_bots += 1 if int(loadout.attrs.ataque) + int(loadout.attrs.defesa) > 0 else 0
	check(worn_by_bots > 40, "high level bots wear gear with attributes")
	# --- 0.27: the skin alone, and no hair sold for money
	var dressed_up: Array = [{"id": "roupa_samurai", "quality": "normal", "level": 0}, {"id": "chapeu_coroa", "quality": "normal", "level": 0}, {"id": "oculos_redondos", "quality": "normal", "level": 0}, {"id": "asas_anjo", "quality": "normal", "level": 0}, {"id": "cabelo_azul", "quality": "normal", "level": 0}, {"id": "fogo_intenso", "quality": "normal", "level": 4}]
	var full_look: Dictionary = Armory.look_for("m", dressed_up)
	var clean_look: Dictionary = Armory.look_for("m", dressed_up, true)
	check(str(full_look.hat) != "" and str(full_look.glasses) != "" and str(full_look.wings) != "" and str(full_look.hair) != "", "by default hat, glasses, wings and hair are drawn")
	check(clean_look.hat == "" and clean_look.glasses == "" and clean_look.wings == "" and clean_look.hair == "", "skin only hides hat, glasses, wings and hair dye")
	check(clean_look.skin == full_look.skin and clean_look.weapon == full_look.weapon and int(clean_look.weapon_level) == 4, "skin only keeps the skin and the weapon")
	var paladin_clean: Dictionary = Armory.look_for("m", [{"id": "roupa_paladino_sol", "quality": "normal", "level": 0}, {"id": "asas_anjo", "quality": "normal", "level": 0}], true)
	check(str(paladin_clean.wings) == "asas_aurora", "skin only keeps what the skin itself carries (the Paladino's wings)")
	var toggled: PlayerProfile = PlayerProfile.new()
	for id: String in ["chapeu_coroa", "asas_anjo"]:
		toggled.equip(int(toggled.add_instance(id).uid))
	var with_hat: Dictionary = toggled.stats(balance)
	check("skin_only" in PlayerProfile.OPS and not toggled.skin_only and str(toggled.look().hat) != "", "the profile starts drawing everything")
	check(toggled.apply_op("skin_only", [true], balance).error == "" and toggled.skin_only and toggled.look().hat == "" and toggled.look().wings == "", "the skin_only operation hides the extras in the look")
	var without_hat: Dictionary = toggled.stats(balance)
	check(var_to_str(with_hat) == var_to_str(without_hat), "skin only never changes an attribute")
	check(toggled.entry(balance).look.hat == "", "the battle roster and the other players get the same look")
	var kept_choice: PlayerProfile = PlayerProfile.new()
	kept_choice.load_data(toggled.to_data())
	check(kept_choice.skin_only and kept_choice.look().hat == "", "the choice survives a save")
	check(toggled.apply_op("skin_only", ["sim"], balance).error == "" and not toggled.skin_only, "anything but true turns it off")
	var old_save: PlayerProfile = PlayerProfile.new()
	old_save.load_data({"version": 11, "gender": "m", "coins": 5})
	check(not old_save.skin_only, "a save from before the option reads as off")
	var hair_skus: Array = PremiumStore.products().filter(func(entry: Dictionary) -> bool: return (entry.items as Array).any(func(id: Variant) -> bool: return Armory.slot_of(str(id)) == "cabelo"))
	check(hair_skus.is_empty(), "the premium shop sells no hair")
	var gold_hair: bool = true
	for id: String in ["cabelo_rosa_neon", "cabelo_branco_gelo", "cabelo_chama", "cabelo_aurora"]:
		var def: Dictionary = Armory.definition(id)
		gold_hair = gold_hair and not bool(def.get("premium", false)) and int(def.price) > 0 and (def.attrs as Dictionary).is_empty()
	check(gold_hair, "the four old premium dyes are now sold in gold and still have no attributes")
	print("SLOT RULES RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
