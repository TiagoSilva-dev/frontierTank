extends SceneTree

# Casa dos Mascotes (0.19): the catalogue, hatching with pity, levels, stars, release, the
# bonuses in battle, the drops, the save round trip and the screens.

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

func species_rarity(p: Dictionary) -> int:
	return Pets.rarity_index(str(Pets.species_def(str(p.species)).rarity))

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	catalogue_tests()
	hatch_tests()
	growth_tests()
	bonus_tests()
	drop_tests()
	save_tests()
	screen_tests()
	print("PETS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func catalogue_tests() -> void:
	var elements: Array = Pets.elements()
	var species: Array = Pets.species_list()
	check(elements.size() == 5 and species.size() == 20, "five elements and twenty species")
	check(species.all(func(s: Dictionary) -> bool: return ResourceLoader.exists(str(s.art))), "every species has imported art")
	check(Pets.eggs().all(func(e: Dictionary) -> bool: return ResourceLoader.exists(str(e.icon)) and (e.odds as Array).size() == 4), "every egg has art and four odds")
	check(elements.all(func(e: Dictionary) -> bool: return ResourceLoader.exists(str(e.icon)) and Pets.species_of_element(str(e.id)).size() == 4), "every element has an icon and four species")
	var ok: bool = true
	for entry: Dictionary in elements:
		var seen: Array = Pets.species_of_element(str(entry.id)).map(func(s: Dictionary) -> String: return str(s.rarity))
		ok = ok and seen == ["comum", "raro", "epico", "lendario"] and Pets.egg_def(str(entry.egg)).element == entry.id and Pets.egg_for_instance(str(entry.instance)) == entry.egg
	check(ok, "each element has one species per rarity, its egg and its instance")
	check(Pets.egg_for_instance("nenhuma") == "pet_egg", "unknown instances drop the generic egg")
	var ids: Array = species.map(func(s: Dictionary) -> String: return str(s.id))
	check(ids.size() == (ids as Array).filter(func(i: String) -> bool: return ids.count(i) == 1).size(), "species ids are unique")

func hatch_tests() -> void:
	var p: PlayerProfile = profile()
	check(p.hatch("egg_sol") != "", "no egg, no hatch")
	check(p.hatch("not_an_egg") != "", "unknown egg id is refused")
	p.add_item("egg_sol", 3)
	p.rng.seed = 5
	check(p.hatch("egg_sol") == "" and p.pets.size() == 1 and p.egg_count("egg_sol") == 2, "hatching spends one egg and adds one pet")
	var first: Dictionary = p.pets[0]
	check(Pets.species_def(str(first.species)).element == "sol", "a Solar egg hatches a Sol pet")
	check(p.pet_active == int(first.uid) and p.pet_album.has(first.species), "the first pet becomes active and joins the album")
	check(int(first.level) == 1 and int(first.stars) == 0 and int(first.xp) == 0, "a newborn is level 1 with no stars")
	p.hatch("egg_sol")
	p.hatch("egg_sol")
	check(p.egg_count("egg_sol") == 0 and not p.items.has("egg_sol"), "an empty egg stack leaves the counters")
	check(int(p.pets[2].uid) > int(p.pets[1].uid) and int(p.pets[1].uid) > int(first.uid), "new pets get increasing uids")
	# Pity: the 10th egg without an Épico is one, the 40th without a Lendário is one.
	var always: bool = true
	for seed_value in range(40):
		var q: PlayerProfile = profile()
		q.add_item("egg_gelo", 1)
		q.pity["egg_epico"] = 9
		q.rng.seed = seed_value
		q.hatch("egg_gelo")
		always = always and species_rarity(q.pets[0]) >= 2
	check(always, "an Épico or better is guaranteed after 9 eggs without one")
	always = true
	for seed_value in range(40):
		var q: PlayerProfile = profile()
		q.add_item("egg_ceu", 1)
		q.pity["egg_lendario"] = 39
		q.rng.seed = seed_value
		q.hatch("egg_ceu")
		always = always and species_rarity(q.pets[0]) == 3
	check(always, "a Lendário is guaranteed after 39 eggs without one")
	var counters: PlayerProfile = profile()
	counters.add_item("egg_viking", 1)
	counters.pity["egg_epico"] = 9
	counters.hatch("egg_viking")
	check(int(counters.pity["egg_epico"]) == 0 and int(counters.pity["egg_lendario"]) in [1, 0], "the pity counter resets on an Épico and the other one advances")
	# Odds: 400 hatches of a Solar egg stay near 58 / 28 / 11 / 3 without pity forcing too much.
	var tally: Array[int] = [0, 0, 0, 0]
	var sim: PlayerProfile = profile()
	sim.rng.seed = 99
	sim.add_item("egg_sol", 600)
	for i in range(600):
		sim.pity = {}
		sim.hatch("egg_sol")
		tally[species_rarity(sim.pets[sim.pets.size() - 1])] += 1
		if sim.pets.size() > 100:
			sim.pets.clear()
	check(abs(tally[0] / 600.0 - 0.58) < 0.07 and abs(tally[1] / 600.0 - 0.28) < 0.07 and tally[3] < 60, "600 hatches follow the configured odds (%s)" % str(tally))
	var mystery: PlayerProfile = profile()
	mystery.add_item("pet_egg", 200)
	var elements: Dictionary = {}
	for i in range(100):
		mystery.pets.clear()
		mystery.hatch("pet_egg")
		elements[Pets.species_def(str(mystery.pets[0].species)).element] = true
	check(elements.size() == 5, "the generic egg hatches every element")
	var full: PlayerProfile = profile()
	for i in range(int(Pets.data().max_pets)):
		full.pets.append({"uid": 1000 + i, "species": "brasinha", "level": 1, "xp": 0, "stars": 0})
	full.add_item("egg_sol", 1)
	check(full.hatch("egg_sol") != "" and full.egg_count("egg_sol") == 1, "a full house keeps the egg")
	var net: PlayerProfile = profile()
	net.add_item("egg_mascara", 1)
	check(net.apply_op("pet_hatch", ["egg_mascara"], {}).error == "" and net.pets.size() == 1, "the pet_hatch operation works")
	check(net.apply_op("pet_hatch", [123], {}).error != "" and net.apply_op("pet_hatch", [], {}).error != "", "bad arguments never hatch")
	check("pet_hatch" in PlayerProfile.OPS and "pet_evolve" in PlayerProfile.OPS and "pet_release" in PlayerProfile.OPS, "the pet operations are whitelisted for the server")

func growth_tests() -> void:
	var pet: Dictionary = {"uid": 1, "species": "leao_dourado", "level": 1, "xp": 0, "stars": 0}
	check(Pets.add_xp(pet, Pets.xp_needed(1)) == 1 and pet.level == 2 and pet.xp == 0, "exact experience levels up")
	Pets.add_xp(pet, 1000000)
	check(int(pet.level) == Pets.cap(0) and int(pet.xp) == 0, "levels stop at the cap of the stars (%d)" % Pets.cap(0))
	check(Pets.cap(5) == 30 and Pets.cap(1) == 14, "each star raises the cap by four, up to 30")
	check(Pets.power(1) < Pets.power(15) and Pets.power(15) < Pets.power(30) and is_equal_approx(Pets.power(30), 1.0), "power grows with the level")
	var p: PlayerProfile = profile()
	p.pets.append({"uid": 10, "species": "grifinho", "level": 1, "xp": 0, "stars": 0})
	p.pets.append({"uid": 11, "species": "grifinho", "level": 3, "xp": 40, "stars": 0})
	p.pets.append({"uid": 12, "species": "brasinha", "level": 1, "xp": 0, "stars": 0})
	p.next_uid = 13
	var coins: int = p.coins
	check(p.pet_feed(10) == "" and p.coins == coins - int(Pets.data().xp.feed_coins) and int(p.find_pet(10).level) == 2, "feeding costs coins and gives experience")
	p.pets[0].level = Pets.cap(0)
	check(p.pet_feed(10) != "", "a pet at its cap refuses food")
	p.coins = 0
	check(p.pet_feed(11) != "" and p.pet_evolve(10, 11) != "", "no coins, no food and no star")
	p.coins = 100000
	check(p.pet_evolve(10, 12) != "", "only the same species can be consumed")
	check(p.pet_evolve(10, 10) != "", "a pet cannot consume itself")
	p.pet_active = 11
	check(p.pet_evolve(10, 11) != "" and p.find_pet(11).size() > 0, "the active pet cannot be consumed")
	p.pet_active = -1
	var before_xp: int = Pets.total_xp(p.find_pet(10))
	var carried: int = Pets.total_xp(p.find_pet(11)) / 2
	var price: int = int(Pets.data().evolve_coins[0])
	coins = p.coins
	check(p.pet_evolve(10, 11) == "" and int(p.find_pet(10).stars) == 1 and p.find_pet(11).is_empty() and p.coins == coins - price, "a star consumes the duplicate and the coins")
	check(Pets.total_xp(p.find_pet(10)) >= before_xp + carried - 1 or int(p.find_pet(10).level) == Pets.cap(1), "half of the consumed pet's experience carries over")
	for i in range(5):
		p.pets.append({"uid": 50 + i, "species": "grifinho", "level": 1, "xp": 0, "stars": 0})
		p.pet_evolve(10, 50 + i)
	check(int(p.find_pet(10).stars) == 5 and p.pet_evolve(10, 54) != "", "stars stop at five")
	check(p.pet_release(10) == "" and p.find_pet(10).is_empty() and p.coins > 0, "releasing returns coins")
	p.pet_active = 12
	check(p.pet_release(12) != "" and not p.find_pet(12).is_empty(), "the active pet cannot be released")
	check(p.pet_equip(12) == "" and p.pet_active == -1 and p.pet_equip(12) == "" and p.pet_active == 12, "equip toggles the active pet")
	check(p.pet_equip(9999) != "", "equipping a pet that does not exist fails")
	var xp: Dictionary = p.pet_battle_xp(500, true)
	check(int(xp.xp) > 0 and int(p.find_pet(12).level) >= 1 and str(xp.species) == "brasinha", "the active pet earns experience from battles")
	check(int(p.pet_battle_xp(500, true).xp) > int(p.pet_battle_xp(500, false).xp), "instances give more pet experience than duels")
	p.pet_active = -1
	check(p.pet_battle_xp(500, true).is_empty(), "no active pet, no experience")

func bonus_tests() -> void:
	var p: PlayerProfile = profile()
	var balance: Dictionary = {"base_hp": 1500, "hp_per_level": 40, "base_agility": 120, "agility_per_level": 8, "energy": 240}
	var plain: Dictionary = p.stats(balance)
	p.pets.append({"uid": 1, "species": "fenix_dourada", "level": 30, "xp": 0, "stars": 0})
	p.pet_active = 1
	var boosted: Dictionary = p.stats(balance)
	var numbers: Dictionary = Pets.attrs(p.pets[0])
	check(int(boosted.ataque) - int(plain.ataque) == int(numbers.ataque) and int(numbers.ataque) > 0, "an active pet adds its attributes (+%d Ataque)" % int(numbers.ataque))
	check(int(boosted.bonus.get("dano", 0)) > 0 and int(boosted.bonus.get("pow_inicial", 0)) > 0, "a Lendário of Sol adds its three talents to the battle bonuses")
	check(p.look().get("pet", "") == "fenix_dourada", "the look carries the active pet for the battle")
	p.pet_active = -1
	check(p.stats(balance).ataque == plain.ataque and not p.look().has("pet"), "no active pet, no bonus and no companion")
	var common: Dictionary = {"uid": 2, "species": "escaravelho_solar", "level": 30, "xp": 0, "stars": 0}
	check(Pets.talents(common).is_empty() and int(Pets.attrs(common).ataque) < int(numbers.ataque), "a Comum has no talents and less power than a Lendário")
	var starred: Dictionary = common.duplicate()
	starred.stars = 5
	check(int(Pets.attrs(starred).ataque) > int(Pets.attrs(common).ataque), "stars raise the attributes")
	var legend: Dictionary = {"uid": 3, "species": "fenix_dourada", "level": 30, "xp": 0, "stars": 5}
	check(int(Pets.attrs(legend).ataque) < 200 and int(Pets.bonus(legend).dano) <= 25, "a maxed Lendário stays within bounds (%d Ataque, %d%% dano)" % [int(Pets.attrs(legend).ataque), int(Pets.bonus(legend).dano)])
	# Album: completing an element gives its bonus; all of them give the final one.
	var album: Array = Pets.species_of_element("gelo").map(func(s: Dictionary) -> String: return str(s.id))
	check(Pets.album_bonus(album).get("defesa", 0) == 24 and Pets.album_bonus(album.slice(0, 3)).is_empty(), "a complete element gives its bonus, an incomplete one nothing")
	var everything: Array = Pets.species_list().map(func(s: Dictionary) -> String: return str(s.id))
	check(int(Pets.album_bonus(everything).get("dano", 0)) == 5 and int(Pets.album_bonus(everything).get("vida", 0)) == 150, "the whole album adds the final bonus")
	p.pet_album.assign(album)
	check(int(p.stats(balance).defesa) - int(plain.defesa) == 24, "the album bonus reaches the character stats")

func drop_tests() -> void:
	var low: float = Pets.boss_egg_chance(1)
	var high: float = Pets.boss_egg_chance(16)
	check(Pets.boss_egg_chance(0) > 0.0 and low < high and high <= float(Pets.data().drops.boss_max), "boss egg chance grows with the map level and is capped")
	var entry: Dictionary = Pets.egg_entry("egg_ceu")
	var p: PlayerProfile = profile()
	Rewards.grant(p, entry)
	check(p.egg_count("egg_ceu") == 1 and ResourceLoader.exists(str(entry.icon)), "an egg reward lands in the bag as a counter")
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var cards: Array = balance.rewards.cards
	var legacy: Dictionary = {}
	for card: Dictionary in cards:
		if card.get("item", "") == "pet_egg":
			legacy = card
	Rewards.grant(p, legacy)
	check(p.egg_count("pet_egg") == 1, "the old Ovo de Mascote card still grants the generic egg")
	# The boss chest and the mob drops of a run reach the profile.
	var found: int = 0
	var mob_found: int = 0
	for seed_value in range(120):
		var run: InstanceRun = InstanceRun.new(balance, "ilha_ruinas", {"instance": "ilha_ruinas", "level": 10, "quality": "normal", "mods": []}, 1, [], profile())
		run.rng.seed = seed_value
		var loot: Dictionary = run.finish(true)
		if run.profile.egg_count("egg_ceu") > 0:
			found += 1
			check_chest(loot)
		for i in range(40):
			var drop: Array[Dictionary] = run.roll_mob_drop(boss_stub(), true)
			if not drop.is_empty() and str(drop[0].get("item", "")) == "egg_ceu":
				mob_found += 1
	check(found > 3 and found < 60, "the boss of the Ilha Celeste drops its egg now and then (%d/120)" % found)
	check(mob_found > 0, "elite and boss kills can drop the element egg too (%d)" % mob_found)

var chest_checked: bool = false

func check_chest(loot: Dictionary) -> void:
	if chest_checked:
		return
	chest_checked = true
	var egg: Variant = (loot.chest as Array).filter(func(d: Dictionary) -> bool: return str(d.get("item", "")).begins_with("egg_"))
	check(not (egg as Array).is_empty() and str(egg[0].item) == "egg_ceu", "the egg shows in the boss chest list")

func boss_stub() -> TankFighter:
	var stub: TankFighter = TankFighter.new()
	stub.rank = "guardian"
	return stub

func save_tests() -> void:
	var p: PlayerProfile = profile()
	p.add_item("egg_gelo", 2)
	p.hatch("egg_gelo")
	p.hatch("egg_gelo")
	p.pets[0].stars = 2
	p.pets[0].level = 9
	var data: Dictionary = p.to_data()
	check(int(data.version) == 8 and (data.pets as Array).size() == 2, "saves are version 8 and keep the pets")
	var again: PlayerProfile = profile()
	again.load_data(JSON.parse_string(JSON.stringify(data)))
	check(again.pets.size() == 2 and again.pet_active == p.pet_active and again.pet_album == p.pet_album and int(again.pets[0].stars) == 2 and int(again.pets[0].level) == 9, "pets, the active pet and the album survive a save round trip")
	check(again.next_uid >= p.next_uid, "the uid counter never goes back")
	var old: PlayerProfile = profile()
	old.load_data({"version": 6, "coins": 50})
	check(old.pets.is_empty() and old.pet_active == -1 and old.pet_album.is_empty(), "a v6 save loads with no pets")
	var dirty: PlayerProfile = profile()
	dirty.load_data({"pets": [{"uid": 5, "species": "nao_existe"}, {"uid": 6, "species": "brasinha", "level": 999, "stars": 99, "xp": -4}, "lixo"], "pet_active": 5, "pet_album": ["fantasma", "brasinha"]})
	check(dirty.pets.size() == 1 and int(dirty.pets[0].level) == Pets.cap(5) and int(dirty.pets[0].stars) == 5 and dirty.pet_active == -1 and dirty.pet_album == ["brasinha"], "bad pets, levels, stars and album entries are cleaned on load")

func screen_tests() -> void:
	var app: FakeApp = FakeApp.new()
	app.profile = profile()
	app.profile.add_item("egg_sol", 2)
	app.profile.add_item("pet_egg", 1)
	for id in ["leao_dourado", "leao_dourado", "brasinha", "dragao_tempestade"]:
		app.profile.pets.append({"uid": app.profile.next_uid, "species": id, "level": 3, "xp": 10, "stars": 0})
		app.profile.next_uid += 1
		app.profile.pet_album.append(id)
	app.profile.pet_active = int(app.profile.pets[0].uid)
	root.add_child(app)
	var host: Control = Control.new()
	host.size = Vector2(1280, 720)
	host.theme = UiKit.make_theme()
	root.add_child(host)
	var screen: PetScreen = PetScreen.open(host, app)
	await process_frame
	check(screen.find_child("HatchButton", true, false) != null and not (screen.find_child("HatchButton", true, false) as Button).disabled, "the Chocar tab has a hatch button, enabled with eggs")
	check(screen.find_child("Egg_pet_egg", true, false) != null and screen.find_child("Egg_egg_viking", true, false) != null, "every egg is listed, owned or not")
	screen.egg_id = "egg_viking"
	screen.build()
	check((screen.find_child("HatchButton", true, false) as Button).disabled, "an egg you do not have cannot be hatched")
	screen.select_tab("Mascotes")
	await process_frame
	check(screen.find_child("Pet_%d" % int(app.profile.pets[0].uid), true, false) != null, "the collection lists the pets")
	check(screen.find_child("PetName", true, false) != null and (screen.find_child("PetEquip", true, false) as Button).text == tr("DESATIVAR"), "the active pet shows its card with the deactivate button")
	check(not (screen.find_child("PetEvolve", true, false) as Button).disabled, "two pets of one species allow a star")
	check((screen.find_child("PetRelease", true, false) as Button).disabled, "the active pet cannot be released from the screen")
	await screen.do_equip()
	check(app.profile.pet_active == -1, "the equip button deactivates the pet")
	var spare: Array[Dictionary] = screen.duplicates_of(app.profile.pets[0])
	await screen.do_evolve(spare)
	check(int(app.profile.pets[0].stars) == 1, "the star button consumes the duplicate")
	await screen.do_feed()
	screen.select_tab("Álbum")
	await process_frame
	check(screen.find_child("Album_leao_dourado", true, false) != null and screen.find_child("Album_fenix_dourada", true, false) != null, "the album shows every species")
	screen.pet_uid = -1
	screen.select_tab("Mascotes")
	app.profile.pets.clear()
	screen.pet_uid = -1
	screen.build()
	await process_frame
	check(screen.find_child("PetName", true, false) == null, "an empty collection shows the invitation instead of a card")
	# The hatching moment builds and plays without errors, for every rarity.
	for species in ["escaravelho_solar", "chacal_ambar", "leao_dourado", "fenix_dourada"]:
		var moment: HatchOutcome = HatchOutcome.new()
		moment.egg_id = "egg_sol"
		moment.pet = {"uid": 77, "species": species, "level": 1, "xp": 0, "stars": 0}
		moment.is_new = species == "fenix_dourada"
		moment.audio = app.audio
		host.add_child(moment)
		for i in range(4):
			await process_frame
		moment.age = HatchOutcome.SHAKE_TIME + 1.0
		await process_frame
		check(is_instance_valid(moment), "the hatch reveal of %s draws" % species)
		moment.queue_free()
	var done: Array = [false]
	var closer: HatchOutcome = HatchOutcome.new()
	closer.egg_id = "pet_egg"
	closer.pet = {"uid": 78, "species": "brasinha", "level": 1, "xp": 0, "stars": 0}
	closer.completed.connect(func() -> void: done[0] = true)
	host.add_child(closer)
	closer.age = HatchOutcome.SHAKE_TIME + 2.0
	await process_frame
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	closer._gui_input(click)
	check(done[0], "a click after the reveal closes the hatch moment")
	for audio_name in ["pet_shake", "pet_crack", "pet_hatch_comum", "pet_hatch_raro", "pet_hatch_epico", "pet_hatch_lendario", "pet_levelup"]:
		check(ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % audio_name), "the sound %s exists" % audio_name)
	screen.queue_free()
	host.queue_free()
	app.queue_free()
	await create_timer(0.3).timeout
