extends SceneTree

# Casa dos Mascotes (0.19, collectibles since 0.30): the catalogue, levels, release, no power
# in battle, the chest drop of a Comum, the old-save migration (eggs to coins, one pet per
# species) and the screens.

var checks: int = 0
var failures: int = 0

class FakeApp:
	extends Node
	var profile: PlayerProfile
	var balance: Dictionary = {}
	var audio: GameAudio = GameAudio.new()
	func _ready() -> void:
		add_child(audio)
	func do_op(op: String, args: Array = []) -> Dictionary:
		return profile.apply_op(op, args, balance)

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func profile() -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.new()
	p.on_save = func() -> void: pass
	p.coins = 100000
	return p

func add_pet(p: PlayerProfile, species: String, level: int = 1) -> int:
	var uid: int = p.next_uid
	p.pets.append({"uid": uid, "species": species, "level": level, "xp": 0})
	p.next_uid += 1
	if not p.pet_album.has(species):
		p.pet_album.append(species)
	return uid

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	catalogue_tests()
	growth_tests()
	no_power_tests()
	drop_tests()
	save_tests()
	await screen_tests()
	print("PETS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func catalogue_tests() -> void:
	var elements: Array = Pets.elements()
	var species: Array = Pets.species_list()
	check(elements.size() == 5 and species.size() == 20, "five elements and twenty species")
	check(species.all(func(s: Dictionary) -> bool: return ResourceLoader.exists(str(s.art))), "every species has imported art")
	check(elements.all(func(e: Dictionary) -> bool: return ResourceLoader.exists(str(e.icon)) and Pets.species_of_element(str(e.id)).size() == 4), "every element has an icon and four species")
	var ok: bool = true
	for entry: Dictionary in elements:
		var seen: Array = Pets.species_of_element(str(entry.id)).map(func(s: Dictionary) -> String: return str(s.rarity))
		ok = ok and seen == ["comum", "raro", "epico", "lendario"]
	check(ok, "each element has one species per rarity")
	var ids: Array = species.map(func(s: Dictionary) -> String: return str(s.id))
	check(ids.size() == (ids as Array).filter(func(i: String) -> bool: return ids.count(i) == 1).size(), "species ids are unique")
	var data: Dictionary = Pets.data()
	check(not data.has("eggs") and not data.has("pity") and not data.has("battle") and not data.has("talent_max") and not data.has("album_all"), "the data has no eggs, pity, battle skill, talents or album bonus")
	check(elements.all(func(e: Dictionary) -> bool: return not e.has("attrs") and not e.has("talents") and not e.has("album") and not e.has("egg")), "elements carry no attributes, talents, album bonus or egg")
	check((data.rarities as Array).all(func(r: Dictionary) -> bool: return not r.has("attr") and not r.has("talent")), "rarities carry no attributes")

func growth_tests() -> void:
	var pet: Dictionary = {"uid": 1, "species": "leao_dourado", "level": 1, "xp": 0}
	check(Pets.add_xp(pet, Pets.xp_needed(1)) == 1 and pet.level == 2 and pet.xp == 0, "exact experience levels up")
	Pets.add_xp(pet, 100000000)
	check(int(pet.level) == Pets.cap() and int(pet.xp) == 0 and Pets.cap() == 30, "levels stop at the cap (%d)" % Pets.cap())
	var cleaned: Dictionary = Pets.clean_pet({"uid": 5, "species": "brasinha", "level": 999, "xp": 50, "stars": 4})
	check(int(cleaned.level) == 30 and not cleaned.has("stars") and cleaned.size() == 4, "a pet is {uid, species, level, xp}: stars are gone")
	var p: PlayerProfile = profile()
	var a: int = add_pet(p, "brasinha")
	var b: int = add_pet(p, "escaravelho_solar")
	check(p.grant_pet("coelho_neve") and p.owns_species("coelho_neve") and int(p.pets[p.pets.size() - 1].level) == 1, "granting a pet adds it at level 1")
	check(p.pet_equip(a) == "" and p.pet_active == a and p.pet_equip(a) == "" and p.pet_active == -1, "equip toggles the companion")
	check(p.pet_equip(9999) != "", "equipping a pet that does not exist fails")
	p.pet_active = b
	check(p.pet_release(b) != "" and not p.find_pet(b).is_empty(), "the companion cannot be released")
	var coins: int = p.coins
	check(p.pet_release(a) == "" and p.find_pet(a).is_empty() and p.coins == coins + int(Pets.rarity_def("comum").release), "releasing returns the coins of its rarity")
	for op: String in ["pet_hatch", "pet_feed", "pet_evolve"]:
		check(not (op in PlayerProfile.OPS) and p.apply_op(op, [1, 2], {}).error != "", "%s no longer exists" % op)
	check("pet_equip" in PlayerProfile.OPS and "pet_release" in PlayerProfile.OPS and "hunt_set" in PlayerProfile.OPS, "equip, release and the hunt stay whitelisted for the server")
	var full: PlayerProfile = profile()
	for i in range(int(Pets.data().max_pets)):
		add_pet(full, "brasinha")
	check(not full.grant_pet("coelho_neve") and full.grant_pet("coelho_neve", true), "a full house refuses a free pet and takes a paid one")
	var coins_full: int = full.coins
	check(not full.receive_pet_drop("brasinha") and full.coins == coins_full + int(Pets.rarity_def("comum").release), "a found pet with no room becomes coins")
	check(full.owns_species("coelho_neve") and not profile().owns_species("coelho_neve"), "owns_species tells what the collection holds")

func no_power_tests() -> void:
	var balance: Dictionary = {"base_hp": 1500, "hp_per_level": 40, "base_agility": 120, "agility_per_level": 8, "energy": 240}
	var p: PlayerProfile = profile()
	var plain: Dictionary = p.stats(balance)
	var uid: int = add_pet(p, "fenix_dourada", 30)
	p.pet_active = uid
	var with_pet: Dictionary = p.stats(balance)
	check(var_to_str(with_pet) == var_to_str(plain), "an active Lendário of level 30 changes no attribute and no battle bonus")
	check(p.look().get("pet", "") == "fenix_dourada", "the look carries the companion for the battle")
	var entry: Dictionary = p.entry(balance)
	check(not entry.has("pet_skill") and str(entry.look.pet) == "fenix_dourada", "the battle entry has the look but no pet skill")
	p.pet_active = -1
	check(not p.look().has("pet"), "no companion, no pet in the look")
	var fighter: TankFighter = TankFighter.new()
	check(not ("pet_skill" in fighter) and not ("pet_uses" in fighter), "fighters have no pet skill state")
	fighter.free()

func drop_tests() -> void:
	var low: float = Pets.boss_pet_chance(1)
	var high: float = Pets.boss_pet_chance(16)
	check(Pets.boss_pet_chance(0) > 0.0 and low < high and high <= float(Pets.data().drops.boss_max) and high <= 0.06, "the boss pet chance grows with the map level and stays small (%.1f%% at level 16)" % (high * 100.0))
	var drops_ok: bool = true
	for entry: Dictionary in Pets.elements():
		var species: String = Pets.drop_species(str(entry.instance))
		drops_ok = drops_ok and Pets.species_def(species).rarity == "comum" and Pets.species_def(species).element == entry.id
	check(drops_ok, "every instance drops the Comum of its own element")
	var entry: Dictionary = Pets.drop_entry("nuvenzinha")
	var p: PlayerProfile = profile()
	Rewards.grant(p, entry)
	check(p.owns_species("nuvenzinha") and ResourceLoader.exists(str(entry.icon)) and not entry.has("item"), "a pet reward lands in the collection and has art")
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	check(not (balance.rewards.cards as Array).any(func(card: Dictionary) -> bool: return str(card.get("item", "")) == "pet_egg"), "the reward cards no longer hold an egg")
	var found: int = 0
	var mob_pets: int = 0
	var shown: bool = false
	for seed_value in range(200):
		var run: InstanceRun = InstanceRun.new(balance, "ilha_ruinas", {"instance": "ilha_ruinas", "level": 16, "quality": "normal", "mods": []}, 1, [], profile())
		run.rng.seed = seed_value
		var loot: Dictionary = run.finish(true)
		if run.profile.owns_species("nuvenzinha"):
			found += 1
			shown = shown or (loot.chest as Array).any(func(d: Dictionary) -> bool: return str(d.get("pet", "")) == "nuvenzinha")
		for i in range(40):
			var drop: Array[Dictionary] = run.roll_mob_drop(boss_stub(), true)
			if not drop.is_empty() and (drop[0].has("pet") or str(drop[0].get("item", "")).begins_with("egg_")):
				mob_pets += 1
	check(found > 2 and found < 40, "the boss of the Ilha Celeste sometimes drops its Comum, never always (%d/200)" % found)
	check(shown, "the pet shows in the boss chest list")
	check(mob_pets == 0, "monsters drop no pets and no eggs")

func boss_stub() -> TankFighter:
	var stub: TankFighter = TankFighter.new()
	stub.rank = "guardian"
	return stub

func save_tests() -> void:
	var p: PlayerProfile = profile()
	add_pet(p, "brasinha", 9)
	add_pet(p, "lobo_boreal", 4)
	p.pet_active = int(p.pets[0].uid)
	var data: Dictionary = p.to_data()
	check(int(data.version) == 12 and (data.pets as Array).size() == 2, "saves are version 12 and keep the pets")
	var again: PlayerProfile = profile()
	again.load_data(JSON.parse_string(JSON.stringify(data)))
	check(again.pets.size() == 2 and again.pet_active == p.pet_active and again.pet_album == p.pet_album and int(again.pets[0].level) == 9, "pets, the companion and the album survive a save round trip")
	check(again.next_uid >= p.next_uid, "the uid counter never goes back")
	var old: PlayerProfile = profile()
	old.load_data({"version": 6, "coins": 50})
	check(old.pets.is_empty() and old.pet_active == -1 and old.pet_album.is_empty() and old.coins == 50, "a v6 save loads with no pets")
	var dirty: PlayerProfile = profile()
	dirty.load_data({"version": 12, "pets": [{"uid": 5, "species": "nao_existe"}, {"uid": 6, "species": "brasinha", "level": 999, "stars": 99, "xp": -4}, "lixo"], "pet_active": 5, "pet_album": ["fantasma", "brasinha"]})
	check(dirty.pets.size() == 1 and int(dirty.pets[0].level) == Pets.cap() and not dirty.pets[0].has("stars") and dirty.pet_active == -1 and dirty.pet_album == ["brasinha"], "bad pets, levels and album entries are cleaned on load")
	# Migration of a pre-0.30 save: eggs become coins, duplicates too, the best pet stays.
	var legacy: PlayerProfile = profile()
	legacy.load_data({"version": 11, "coins": 1000, "items": {"egg_sol": 2, "egg_viking": 1, "pet_egg": 1, "pedra_fortalecimento": 4},
		"pity": {"egg_epico": 7, "egg_lendario": 30},
		"pets": [{"uid": 1, "species": "leao_dourado", "level": 3, "xp": 10, "stars": 1}, {"uid": 2, "species": "leao_dourado", "level": 9, "xp": 5, "stars": 2}, {"uid": 3, "species": "brasinha", "level": 1, "xp": 0, "stars": 0}], "pet_active": 1})
	var refund: int = 2 * Pets.egg_refund("egg_sol") + Pets.egg_refund("egg_viking") + Pets.egg_refund("pet_egg") + int(Pets.rarity_def("epico").release)
	check(legacy.items.keys() == ["pedra_fortalecimento"] and legacy.coins == 1000 + refund, "old eggs and a duplicate become coins (+%d)" % refund)
	check(legacy.pets.size() == 2 and legacy.pets.any(func(x: Dictionary) -> bool: return int(x.uid) == 2) and not legacy.pets.any(func(x: Dictionary) -> bool: return int(x.uid) == 1), "the better of two duplicates stays")
	check(legacy.pet_active == -1 and legacy.pity.is_empty(), "a companion that was merged away and the pity counters are cleared")
	var twice: PlayerProfile = profile()
	twice.load_data(legacy.to_data())
	check(twice.coins == legacy.coins and twice.pets.size() == 2, "reading the migrated save again changes nothing")
	check(Pets.egg_refund("egg_gelo") == 150 and Pets.egg_refund("pet_egg") == 220, "eggs are refunded at 150 coins, the generic one at 220")
	var coupon: PlayerProfile = profile()
	coupon.redeem("MASCOTES")
	check(coupon.pets.size() == 20 and coupon.owns_species("fenix_dourada"), "the test coupon hands out one of each species")

func screen_tests() -> void:
	var app: FakeApp = FakeApp.new()
	app.profile = profile()
	for id in ["leao_dourado", "brasinha", "dragao_tempestade"]:
		add_pet(app.profile, id, 3)
	app.profile.pet_active = int(app.profile.pets[0].uid)
	root.add_child(app)
	var host: Control = Control.new()
	host.size = Vector2(1280, 720)
	host.theme = UiKit.make_theme()
	root.add_child(host)
	var screen: PetScreen = PetScreen.open(host, app)
	await process_frame
	check(screen.find_child("PetTab_Chocar", true, false) == null and screen.find_child("PetTab_Mascotes", true, false) != null and screen.find_child("PetTab_Caçada", true, false) != null, "there is no Chocar tab any more")
	check(screen.find_child("HatchButton", true, false) == null, "and no hatch button")
	check(screen.find_child("Pet_%d" % int(app.profile.pets[0].uid), true, false) != null, "the collection lists the pets")
	check(screen.find_child("PetName", true, false) != null and (screen.find_child("PetEquip", true, false) as Button).text == tr("DESATIVAR"), "the companion shows its card with the deactivate button")
	check(screen.find_child("PetFeed", true, false) == null and screen.find_child("PetEvolve", true, false) == null and screen.find_child("PetStars", true, false) == null, "no feed, no star and no star row")
	check((screen.find_child("PetRelease", true, false) as Button).disabled, "the companion cannot be released from the screen")
	check(screen.find_child("PetShop", true, false) != null, "a button leads to the shop")
	await screen.do_equip()
	check(app.profile.pet_active == -1, "the equip button deactivates the pet")
	screen.select_tab("Álbum")
	await process_frame
	check(screen.find_child("Album_leao_dourado", true, false) != null and screen.find_child("Album_fenix_dourada", true, false) != null, "the album shows every species")
	screen.select_tab("Mascotes")
	app.profile.pets.clear()
	screen.pet_uid = -1
	screen.build()
	await process_frame
	check(screen.find_child("PetName", true, false) == null, "an empty collection shows the invitation instead of a card")
	screen.queue_free()
	host.queue_free()
	app.queue_free()
	await create_timer(0.3).timeout
