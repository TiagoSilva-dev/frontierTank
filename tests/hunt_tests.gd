extends SceneTree

# Caçada dos Mascotes (0.20): the fight, the encounters being a pure function of the
# seed, settling with the 2 h / 8 h cap, captures (the Lendário), tiers, the profile
# operations the server runs and the save round trip.

var checks: int = 0
var failures: int = 0

class FakeSteam:
	extends RefCounted
	var available: bool = false

class FakeApp:
	extends Node
	var profile: PlayerProfile
	var balance: Dictionary = {}
	var audio: GameAudio = GameAudio.new()
	var online: bool = false
	var steam: FakeSteam = FakeSteam.new()
	func _ready() -> void:
		add_child(audio)
	func do_op(op: String, args: Array = []) -> Dictionary:
		return profile.apply_op(op, args, balance)
	func buy_premium(_sku: String) -> String:
		return "no steam"

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
	p.coins = 1000
	p.hunt_clock = 1000000
	return p

# Gives the profile one pet of each wanted species at the level/stars and returns uids.
func add_pets(p: PlayerProfile, species: Array, level: int = 10, stars: int = 0) -> Array:
	var uids: Array = []
	for id: String in species:
		p.grant_pet(id)
		var pet: Dictionary = p.pets[p.pets.size() - 1]
		pet.level = level
		pet.stars = stars
		uids.append(int(pet.uid))
	return uids

const STRONG: Array = ["fenix_dourada", "lobo_boreal", "dragao_tempestade", "rei_mascara", "lobo_fenrir"]

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	rules_tests()
	fight_tests()
	determinism_tests()
	settle_tests()
	capture_tests()
	op_tests()
	save_tests()
	await field_tests()
	await screen_tests()
	print("HUNT RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func rules_tests() -> void:
	var rules: Dictionary = PetHunt.rules()
	check(PetHunt.zones().size() == 5, "one hunting zone per element")
	check((rules.wheel as Array).size() == 5 and Pets.elements().all(func(e: Dictionary) -> bool: return (rules.wheel as Array).has(str(e.id))), "the element wheel holds all five elements")
	var wins: bool = true
	for a: Dictionary in Pets.elements():
		var beaten: int = 0
		var beats: int = 0
		for b: Dictionary in Pets.elements():
			beaten += 1 if PetHunt.wheel_edge(str(b.id), str(a.id)) > 0 else 0
			beats += 1 if PetHunt.wheel_edge(str(a.id), str(b.id)) > 0 else 0
			wins = wins and PetHunt.wheel_edge(str(a.id), str(b.id)) == -PetHunt.wheel_edge(str(b.id), str(a.id))
		wins = wins and beaten == 1 and beats == 1
	check(wins, "every element beats one and loses to one, symmetrically")
	check(PetHunt.cycle() == 12 and int(rules.cap_free) == 7200 and int(rules.cap_pass) == 28800, "12 s encounters, 2 h free cap, 8 h with the pass")
	check(Pets.species_of_element("sol").any(func(s: Dictionary) -> bool: return PetHunt.wild_species("sol", 3) == s.id and s.rarity == "lendario"), "the boss of a zone is its Lendário")
	var unit: Dictionary = PetHunt.make_unit("leao_dourado", 10, 0)
	var stronger: Dictionary = PetHunt.make_unit("leao_dourado", 20, 2)
	check(float(stronger.atk) > float(unit.atk) * 1.8 and int(stronger.hp) > int(unit.hp) * 1.8, "levels and stars make the unit stronger")
	check(PetHunt.make_unit("fenix_dourada", 10, 0).hp > PetHunt.make_unit("escaravelho_solar", 10, 0).hp, "a Lendário has more life than a Comum at the same level")
	check(PetHunt.wild_level(8) > PetHunt.wild_level(1), "the wild is stronger in higher tiers")

func fight_tests() -> void:
	var team: Array = PetHunt.team_units([{"species": "leao_dourado", "level": 14, "stars": 1}, {"species": "raposa_glacial", "level": 14, "stars": 1}])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var weak: Array = [PetHunt.make_unit("escaravelho_solar", 2, 0)]
	var easy: Dictionary = PetHunt.fight(team, weak, rng)
	check(easy.won and int(easy.alive) == 2, "a strong team crushes a level 2 Comum")
	check((easy.log as Array).any(func(e: Dictionary) -> bool: return e.k == "hit") and (easy.log as Array).any(func(e: Dictionary) -> bool: return e.k == "down"), "the log records hits and knock-outs")
	var giant: Array = [PetHunt.make_unit("fenix_dourada", 30, 5), PetHunt.make_unit("fenix_dourada", 30, 5)]
	rng.seed = 7
	var lost: Dictionary = PetHunt.fight(PetHunt.team_units([{"species": "brasinha", "level": 1, "stars": 0}]), giant, rng)
	check(not lost.won and int(lost.alive) == 0, "a level 1 Comum loses to two maxed Lendários")
	var capped: Dictionary = PetHunt.fight(PetHunt.team_units([{"species": "pinguim_cristal", "level": 30, "stars": 5}]), [PetHunt.make_unit("pinguim_cristal", 30, 5)], rng)
	check(int(capped.rounds) <= int(PetHunt.rules().rounds_max), "a fight never goes past the round limit")
	# Wheel: Sol hits Gelo harder than Gelo hits Sol.
	var hits: Array = []
	for pair: Array in [["sol", "gelo"], ["gelo", "sol"], ["sol", "sol"]]:
		var a: Dictionary = {"id": 0, "element": pair[0], "atk": 100.0, "buff": 0.0, "crit": 0.0}
		var d: Dictionary = {"id": 1, "element": pair[1], "def": 0.0, "hp": 100000}
		var log: Array = []
		rng.seed = 3
		PetHunt._strike(a, d, 1.0, rng, log, "")
		hits.append(int(log[0].dmg))
	check(hits[0] > hits[2] and hits[2] > hits[1], "the element wheel changes the damage (%s)" % str(hits))
	# Skills: Gelo heals, Runa buffs.
	var healer: Dictionary = PetHunt.make_unit("pinguim_cristal", 10, 0)
	healer.id = 0
	healer.acts = 2
	var hurt: Dictionary = PetHunt.make_unit("brasinha", 10, 0)
	hurt.id = 1
	hurt.hp = 10
	var enemy: Dictionary = PetHunt.make_unit("brasinha", 10, 0)
	enemy.id = 100
	for u: Dictionary in [healer, hurt, enemy]:
		u.buff = 0.0
		u.buff_left = 0
	var healed_log: Array = []
	PetHunt._act(healer, [healer, hurt], [enemy], rng, healed_log)
	check(int(hurt.hp) > 10 and healed_log.any(func(e: Dictionary) -> bool: return e.k == "heal"), "the Gelo skill heals the allies")
	var warrior: Dictionary = PetHunt.make_unit("corvo_runico", 10, 0)
	warrior.id = 0
	warrior.acts = 2
	warrior.buff = 0.0
	warrior.buff_left = 0
	PetHunt._act(warrior, [warrior], [enemy], rng, [])
	check(float(warrior.buff) > 0.2 and int(warrior.buff_left) == 3, "the Runa skill raises the team's attack")

func determinism_tests() -> void:
	var state: Dictionary = {"zone": "gelo", "tier": 3, "seed": 31337}
	var units: Array = PetHunt.team_units([{"species": "leao_dourado", "level": 12, "stars": 1}, {"species": "grifinho", "level": 12, "stars": 1}, {"species": "urso_berserker", "level": 12, "stars": 1}])
	var a: Dictionary = PetHunt.slot(state, units, 55, 0)
	var b: Dictionary = PetHunt.slot(state, units, 55, 0)
	check(JSON.stringify(a) == JSON.stringify(b), "the same encounter always plays out the same way")
	var c: Dictionary = PetHunt.slot(state, units, 56, 0)
	check(JSON.stringify(a.wilds) != JSON.stringify(c.wilds) or a.rounds != c.rounds, "different encounters differ")
	var whole: Dictionary = PetHunt.run(state, units, 0, 120, 0)
	var first: Dictionary = PetHunt.run(state, units, 0, 50, 0)
	var second: Dictionary = PetHunt.run(state, units, 50, 70, int(first.legend))
	var sum_wins: int = int(first.report.wins) + int(second.report.wins)
	check(sum_wins == int(whole.report.wins) and int(first.report.coins) + int(second.report.coins) == int(whole.report.coins) and int(first.report.xp) + int(second.report.xp) == int(whole.report.xp), "settling in pieces earns exactly what settling at once earns")
	var other: Dictionary = {"zone": "gelo", "tier": 3, "seed": 99}
	check(int(PetHunt.run(other, units, 0, 120, 0).report.coins) != int(whole.report.coins), "another seed gives another hunt")
	var started: int = Time.get_ticks_msec()
	PetHunt.run(state, units, 0, 2400, 0)
	var took: int = Time.get_ticks_msec() - started
	check(took < 4000, "8 hours of encounters settle fast (%d ms)" % took)
	var weak: Array = PetHunt.team_units([{"species": "escaravelho_solar", "level": 3, "stars": 0}])
	var strong: Array = PetHunt.team_units([{"species": "fenix_dourada", "level": 30, "stars": 5}, {"species": "lobo_fenrir", "level": 30, "stars": 5}])
	var weak_view: Dictionary = PetHunt.analyse(weak, "sol", 4)
	var strong_view: Dictionary = PetHunt.analyse(strong, "sol", 4)
	check(float(strong_view.win) > float(weak_view.win) and float(strong_view.win) > 0.9, "the analyser sees a strong team winning more (%.2f vs %.2f)" % [strong_view.win, weak_view.win])
	check(int(strong_view.xp) > 0 and int(strong_view.coins) > 0 and float(strong_view.eggs) > 0.0 and float(strong_view.boss) >= 0.0, "the analyser gives hourly numbers")

func settle_tests() -> void:
	var p: PlayerProfile = profile()
	var uids: Array = add_pets(p, ["leao_dourado", "raposa_glacial", "grifinho"], 5, 0)
	check(p.hunt_set("sol", 1, uids) == "", "starting a hunt works")
	var coins_before: int = p.coins
	check(PetHunt.pending_slots(p, p.hunt_now()) == 0, "nothing is pending the moment it starts")
	p.hunt_clock += 3600
	check(PetHunt.pending_slots(p, p.hunt_now()) == 300, "one hour is 300 encounters")
	p.hunt_clock += 3 * 86400
	check(PetHunt.pending_slots(p, p.hunt_now()) == 600, "days away still only add up to the 2 h cap (600 encounters)")
	check(p.hunt_collect() == "", "collecting works")
	var report: Dictionary = p.hunt.report
	check(int(report.slots) == 600 and int(report.wins) + int(report.losses) == 600, "the report counts the 600 encounters")
	check(p.coins == coins_before + int(report.coins) and int(report.coins) > 0, "the coins go to the profile")
	check(int(p.hunt.n) == 600 and int(p.hunt.since) == p.hunt_now(), "past the cap the clock restarts now")
	check(int(p.find_pet(int(uids[0])).level) > 5, "the team earns experience")
	var capped_level: bool = int(p.find_pet(int(uids[0])).level) <= Pets.cap(0)
	check(capped_level, "experience never passes the level cap")
	# Under the cap the unfinished encounter carries over.
	var start: int = p.hunt_now()
	p.hunt_clock += 125
	p.hunt_collect()
	check(int(p.hunt.report.slots) == 10 and int(p.hunt.since) == start + 120, "125 s settles 10 encounters and keeps the 5 s left over")
	# The pass: 8 hours.
	p.add_instance(str(PetHunt.rules().pass_item))
	check(PetHunt.cap_seconds(p) == 28800, "the Passe do Caçador raises the cap to 8 h")
	p.hunt_clock += 20 * 3600
	check(PetHunt.pending_slots(p, p.hunt_now()) == 2400, "with the pass 8 h are 2400 encounters")
	p.hunt_collect()
	check(int(p.hunt.report.slots) == 2400 and int(p.hunt.report.seconds) == 28800, "the long collect settles 2400 encounters")
	# A clock that went backwards never earns or crashes.
	p.hunt_clock -= 99999
	check(PetHunt.pending_slots(p, p.hunt_now()) == 0 and p.hunt_collect() == "", "a clock set back earns nothing")
	# Eggs and the tier unlock come from wins.
	var q: PlayerProfile = profile()
	var strong: Array = add_pets(q, STRONG, 30, 5)
	q.hunt_set("viking", 1, strong)
	q.hunt_clock += 28800
	q.add_instance(str(PetHunt.rules().pass_item))
	q.hunt_collect()
	var eggs: int = 0
	for id: String in q.hunt.report.eggs:
		eggs += int(q.hunt.report.eggs[id])
	check(eggs > 0 and q.egg_count("egg_viking") == eggs, "a long hunt drops eggs of the zone's element (%d)" % eggs)
	check(PetHunt.wins_at(q.hunt, "viking", 1) >= int(PetHunt.rules().unlock_wins) and PetHunt.unlocked_tier(q.hunt, "viking") >= 2, "winning opens the next tier")
	check(PetHunt.unlocked_tier(q.hunt, "sol") == 1, "other zones stay at their own tier")

func capture_tests() -> void:
	var p: PlayerProfile = profile()
	var uids: Array = add_pets(p, STRONG, 30, 5)
	p.hunt_set("gelo", 1, uids)
	p.hunt.legend = int(PetHunt.rules().boss.forced_after)
	p.hunt_clock += PetHunt.cycle() + 1
	var album_before: int = p.pet_album.size()
	var count_before: int = p.pets.size()
	p.hunt_collect()
	var report: Dictionary = p.hunt.report
	check(int(report.boss_seen) == 1 and int(report.boss_won) == 1, "the guaranteed Lendário showed up and fell")
	check(report.captured.has("lobo_boreal") and p.pets.size() == count_before + 1, "the defeated Lendário joins the pets")
	check(int(p.pets[p.pets.size() - 1].level) == 1 and p.pet_album.has("lobo_boreal") and p.pet_album.size() == album_before, "it arrives at level 1 and counts for the album")
	check(int(p.hunt.legend) == 0, "the Lendário counter restarts after a capture")
	# Lost fight: the boss flees and the counter is cut in half, no streak of losses.
	var weak: PlayerProfile = profile()
	var weak_uids: Array = add_pets(weak, ["brasinha"], 1, 0)
	weak.hunt_set("sol", 1, weak_uids)
	weak.hunt.legend = int(PetHunt.rules().boss.forced_after)
	weak.hunt_clock += PetHunt.cycle() * 3 + 1
	weak.hunt_collect()
	check(int(weak.hunt.report.boss_seen) == 1 and int(weak.hunt.report.boss_won) == 0 and weak.pets.size() == 1, "a weak team does not catch it")
	check(int(weak.hunt.report.losses) >= 1 and int(weak.hunt.report.boss_seen) == 1, "and the Lendário does not come back at once")
	# A full Casa dos Mascotes turns the capture into coins.
	var full: PlayerProfile = profile()
	var team: Array = add_pets(full, STRONG, 30, 5)
	while full.pets.size() < int(Pets.data().max_pets):
		full.grant_pet("brasinha")
	full.hunt_set("sol", 1, team)
	full.hunt.legend = int(PetHunt.rules().boss.forced_after)
	var coins: int = full.coins
	full.hunt_clock += PetHunt.cycle() + 1
	full.hunt_collect()
	check(full.pets.size() == int(Pets.data().max_pets) and bool(full.hunt.report.full) and full.coins >= coins + int(Pets.rarity_def("lendario").release), "with the house full the capture is turned into coins")
	check(full.hunt.report.captured.is_empty(), "and nothing is kept")
	# Rates of common captures stay low: a long hunt does not flood the house.
	var flood: PlayerProfile = profile()
	var squad: Array = add_pets(flood, STRONG, 30, 5)
	flood.add_instance(str(PetHunt.rules().pass_item))
	flood.hunt_set("sol", 5, squad) if PetHunt.unlocked_tier(flood.hunt, "sol") >= 5 else flood.hunt_set("sol", 1, squad)
	flood.hunt_clock += 28800
	flood.hunt_collect()
	var common: int = (flood.hunt.report.captured as Array).filter(func(id: String) -> bool: return Pets.species_def(id).rarity != "lendario").size()
	check(common <= 14, "8 hours catch a handful of common pets, not a flood (%d)" % common)

func op_tests() -> void:
	var p: PlayerProfile = profile()
	var uids: Array = add_pets(p, ["leao_dourado", "raposa_glacial", "grifinho", "cao_de_lava", "urso_berserker", "brasinha"], 5, 0)
	check(p.apply_op("hunt_set", ["zona_x", 1, uids], {}).error != "", "an unknown zone is refused")
	check(p.apply_op("hunt_set", ["sol", 2, uids], {}).error != "", "a locked tier is refused")
	check(p.apply_op("hunt_set", ["sol", 1, []], {}).error != "", "an empty team is refused")
	check(p.apply_op("hunt_set", ["sol", 1, uids], {}).error != "", "six pets are too many")
	check(p.apply_op("hunt_set", ["sol", 1, [9999, 8888]], {}).error != "", "pets the player does not own are refused")
	check(p.apply_op("hunt_set", ["sol", "x", "y"], {}).error != "", "bad argument types are refused")
	check(p.apply_op("hunt_collect", [], {}).error != "" and not bool(p.hunt.active), "collecting without a hunt is refused")
	check(p.apply_op("hunt_set", ["sol", 1, [uids[0], uids[0], uids[1]]], {}).error == "" and (p.hunt.team as Array).size() == 2, "a repeated pet counts once")
	var seed_before: int = int(p.hunt.seed)
	p.hunt_clock += 600
	check(p.apply_op("hunt_set", ["sol", 1, [uids[0], uids[1], uids[2]]], {}).error == "" and int(p.hunt.report.slots) == 50, "changing the team settles the old stretch first")
	check(int(p.hunt.seed) == seed_before, "the same zone and tier keep their seed")
	check(p.apply_op("hunt_set", ["sol", 1, [uids[0]]], {}).error == "" and p.apply_op("hunt_stop", [], {}).error == "" and not bool(p.hunt.active), "a hunt can be stopped")
	check("hunt_set" in PlayerProfile.OPS and "hunt_collect" in PlayerProfile.OPS and "hunt_stop" in PlayerProfile.OPS, "the server knows the hunt operations")
	# The released pet leaves the team on its own.
	var q: PlayerProfile = profile()
	var team: Array = add_pets(q, ["leao_dourado", "raposa_glacial"], 5, 0)
	q.hunt_set("sol", 1, team)
	q.pets.erase(q.find_pet(int(team[0])))
	q.hunt_clock += 240
	check(q.hunt_collect() == "" and int(q.hunt.report.slots) == 20, "a pet that left the house is skipped")
	# The pass can be won from the coupon and is not for sale.
	var r: PlayerProfile = profile()
	check(PetHunt.cap_seconds(r) == 7200 and r.apply_op("redeem", ["CACADA"], {}).error == "" and PetHunt.cap_seconds(r) == 28800, "the CACADA coupon gives the pass")
	var pass_uid: int = int(r.inventory.filter(func(i: Dictionary) -> bool: return i.id == "passe_cacador")[0].uid)
	check(r.apply_op("sell", [pass_uid], {}).error != "" and r.has_item("passe_cacador"), "the pass cannot be sold")
	check(Armory.definition("passe_cacador").get("premium", false) and (Armory.definition("passe_cacador").attrs as Dictionary).is_empty(), "the pass is a premium item with no attributes")
	var product: Dictionary = PremiumStore.product("passe_cacador")
	check(PremiumStore.valid(product) and int(product.prices.USD) > 0, "the pass is a valid Steam product")

func save_tests() -> void:
	var p: PlayerProfile = profile()
	var uids: Array = add_pets(p, ["leao_dourado", "grifinho"], 8, 1)
	p.hunt_set("ceu", 1, uids)
	p.hunt_clock += 1200
	p.hunt_collect()
	var data: Dictionary = JSON.parse_string(JSON.stringify(p.to_data()))
	var copy: PlayerProfile = PlayerProfile.new()
	copy.on_save = func() -> void: pass
	copy.load_data(data)
	check(int(data.version) == 10 and copy.hunt.zone == "ceu" and bool(copy.hunt.active) and (copy.hunt.team as Array).size() == 2, "the hunt survives the save")
	check(int(copy.hunt.n) == int(p.hunt.n) and int(copy.hunt.seed) == int(p.hunt.seed) and int(copy.hunt.report.slots) == int(p.hunt.report.slots), "its counters and report survive too")
	var old: Dictionary = data.duplicate(true)
	old.erase("hunt")
	old.version = 7
	var plain: PlayerProfile = PlayerProfile.new()
	plain.on_save = func() -> void: pass
	plain.load_data(old)
	check(not bool(plain.hunt.active) and (plain.hunt.team as Array).is_empty(), "a v7 save loads without a hunt")
	var bad: Dictionary = PetHunt.clean_state({"zone": "??", "tier": 99, "team": [1, 1, 2, 3, 4, 5, 6, 7], "since": -5, "n": "x", "wins": {"sol:1": -4}, "report": {"eggs": {"bogus": 3}, "captured": ["nope"]}})
	check(bad.zone == "sol" and int(bad.tier) == PetHunt.tiers() and (bad.team as Array).size() == 5 and int(bad.since) == 0 and int(bad.wins["sol:1"]) == 0, "damaged hunt data is cleaned")
	check((bad.report.eggs as Dictionary).is_empty() and (bad.report.captured as Array).is_empty(), "and so is a damaged report")

# The top-down field (0.21 pilot): the ground, the sprite sheets and a whole encounter
# replayed in it.
func field_tests() -> void:
	check(PetHunt.zones().all(func(zone: Dictionary) -> bool: return FieldMap.available(str(zone.id))) and not FieldMap.available("nowhere"), "every hunting zone has a top-down field")
	var map: FieldMap = FieldMap.for_zone("sol")
	check(map.texture != null and map.texture.get_width() == FieldMap.COLS * FieldMap.TILE and map.texture.get_height() == FieldMap.ROWS * FieldMap.TILE, "the field ground is baked at the world size")
	check(map.decor.size() > 40, "the field is dressed with trees, bushes and rocks (%d)" % map.decor.size())
	var open: Rect2 = FieldMap.clearing().grow(1.0)
	check(map.decor.all(func(item: Dictionary) -> bool: return bool(item.cover) or not open.has_point((item.foot as Vector2) / FieldMap.TILE)), "no tree or bush grows on the fighting ground")
	check(FieldMap.for_zone("sol") == map, "the map is built once")
	check(FieldSprites.dir_index(Vector2.DOWN) == 0 and FieldSprites.dir_index(Vector2.RIGHT) == 2 and FieldSprites.dir_index(Vector2.UP) == 4 and FieldSprites.dir_index(Vector2.LEFT) == 6, "directions pick the right resting picture")
	check(FieldSprites.dir_index(Vector2(1, 1)) == 1 and FieldSprites.dir_index(Vector2(-1, -1)) == 5, "and so do the diagonals")
	check(FieldSprites.region(Vector2.RIGHT, true, 3.0) == Rect2(3 * FieldSprites.CELL, 3 * FieldSprites.CELL, FieldSprites.CELL, FieldSprites.CELL), "walking east reads the east row")
	for sheet_name in ["trainer", "fenix_dourada", "leao_dourado", "chacal_ambar", "escaravelho_solar"]:
		check(FieldSprites.has(sheet_name), "the %s has its field sheet" % sheet_name)
	for fx in ["bolt", "orb", "slash"]:
		check(ResourceLoader.exists("res://assets/field/fx/%s.png" % fx), "the %s effect exists" % fx)
		for element in ["gelo", "mascara", "ceu", "viking"]:
			check(ResourceLoader.exists("res://assets/field/fx/%s_%s.png" % [fx, element]), "the %s effect has an %s version" % [fx, element])
	for sheet_name in ["pinguim_cristal", "coelho_neve", "raposa_glacial", "lobo_boreal"]:
		check(FieldSprites.has(sheet_name), "the %s has its field sheet" % sheet_name)
	var snow: FieldMap = FieldMap.for_zone("gelo")
	check(snow.texture != null and snow.decor.size() > 40, "the snow field is baked and dressed (%d)" % snow.decor.size())
	check(snow.decor.all(func(item: Dictionary) -> bool: return bool(item.cover) or not open.has_point((item.foot as Vector2) / FieldMap.TILE)), "no pine grows on the snow fighting ground")
	# Brasa, Céu and Drakkar: ruined platforms with scenery lying on them.
	for zone_id in ["mascara", "ceu", "viking"]:
		var ruin: FieldMap = FieldMap.for_zone(zone_id)
		check(ruin.ruined and ruin.texture != null and ruin.decor.size() > 40 and ruin.slabs.size() > 20, "the %s field has ruined platforms (%d slabs)" % [zone_id, ruin.slabs.size()])
		var standing: Array = ruin.decor.filter(func(item: Dictionary) -> bool: return item.has("on_stone"))
		check(standing.size() >= 8 and standing.all(func(item: Dictionary) -> bool: return ruin.slabs.has(Vector2i(((item.foot as Vector2) / FieldMap.TILE).floor()))), "%s: its columns and rubble stand on the slabs (%d)" % [zone_id, standing.size()])
		check(ruin.decor.all(func(item: Dictionary) -> bool: return bool(item.cover) or item.has("on_stone") or not open.has_point((item.foot as Vector2) / FieldMap.TILE)), "%s: nothing grows on the fighting ground" % zone_id)
	check(not FieldMap.for_zone("sol").ruined and not snow.ruined, "the sun and snow zones keep their plain platforms")
	var field: HuntField = HuntField.new()
	field.size = Vector2(580, 394)
	var host: Control = Control.new()
	root.add_child(host)
	host.add_child(field)
	field.set_zone("sol")
	var units: Array = PetHunt.team_units([{"species": "fenix_dourada", "level": 12, "stars": 1}, {"species": "leao_dourado", "level": 10, "stars": 0}, {"species": "chacal_ambar", "level": 9, "stars": 0}, {"species": "pinguim_cristal", "level": 8, "stars": 0}])
	var state: Dictionary = {"seed": 7, "zone": "sol", "tier": 3, "n": 0, "legend": 0}
	var result: Dictionary = PetHunt.slot(state, units, 5, 0)
	field.show_encounter(units, result, 0.0)
	check(field.allies.size() == 4 and field.foes.size() == (result.wilds as Array).size(), "the field stages the team and the wild group")
	check(field.allies.all(func(u: Dictionary) -> bool: return (u.home as Vector2).x < FieldMap.world_size().x * 0.5) and field.foes.all(func(u: Dictionary) -> bool: return (u.home as Vector2).x > FieldMap.world_size().x * 0.5), "the team stands on the left, the wild on the right")
	check(field.foes.all(func(u: Dictionary) -> bool: return (u.pos as Vector2).x > (u.home as Vector2).x + 100.0), "the wild group walks in from the edge")
	check(field.ambient.size() == HuntField.AMBIENT_COUNT and field.ambient.all(func(c: Dictionary) -> bool: return str(Pets.species_def(str(c.species)).element) == "sol"), "the field has wild critters of the zone's element wandering")
	check((field.trainer.pos as Vector2).x < FieldMap.world_size().x * 0.5 - 250.0, "the trainer starts at the left edge of the field")
	var start_spots: Array = field.ambient.map(func(c: Dictionary) -> Vector2: return c.pos)
	var attacks: Array = []
	field.attack_played.connect(func(style: String, element: String) -> void: attacks.append([style, element]))
	var trainer_walked: bool = false
	var launched: int = 0
	var landed: int = 0
	var frames: int = 0
	var critter_in_fight: bool = false
	while not field.ended and frames < 1200:
		await process_frame
		field._process(0.02)
		launched = maxi(launched, field.effects.size())
		trainer_walked = trainer_walked or bool(field.trainer.moving)
		if field._fight_on() and field.t > HuntField.APPROACH + 1.5:
			critter_in_fight = critter_in_fight or field.ambient.any(func(c: Dictionary) -> bool: return field._fight_area().has_point(c.pos))
		landed += 1 if not field.floaters.is_empty() else 0
		frames += 1
	check(field.ended, "the whole encounter plays through")
	check(launched > 0 and landed > 0, "attacks fly and their damage lands as numbers")
	check(not attacks.is_empty() and attacks.all(func(a: Array) -> bool: return str(a[0]) in ["bolt", "orb", "breath", "slash"]), "every move announces its style for the sound (%d)" % attacks.size())
	check(trainer_walked, "the trainer walks onto the field")
	# The result stays up (the clock stops) while the trainer walks out to the loot.
	for i in range(200):
		field._process(0.02)
	var goal: Vector2 = field._trainer_goal()
	check((field.trainer.pos as Vector2).distance_to(goal) < 8.0 and goal.x > FieldMap.world_size().x * 0.5 - 40.0 and goal.x < FieldMap.world_size().x * 0.5 + 40.0, "and ends the encounter out in the field picking up the loot")
	var moved: int = 0
	for i in range(start_spots.size()):
		if (field.ambient[i].pos as Vector2).distance_to(start_spots[i]) > 12.0:
			moved += 1
	check(moved >= field.ambient.size() / 2, "the critters wander around (%d of %d moved)" % [moved, field.ambient.size()])
	check(not critter_in_fight, "and keep out of the fight")
	check(field.impacts.size() <= 1, "no blow is left hanging")
	var expected_foes_down: int = (result.log as Array).filter(func(e: Dictionary) -> bool: return e.k == "down" and int(e.u) >= 100).size()
	check(field.foes.filter(func(u: Dictionary) -> bool: return not bool(u.alive)).size() == expected_foes_down, "the wild fall exactly as the log says")
	field.show_encounter(units, result, 9.0)
	check(field.foes.all(func(u: Dictionary) -> bool: return (u.pos as Vector2).is_equal_approx(u.home)), "arriving late puts everyone in place at once")
	var before: Vector2 = field.trainer.pos
	field.set_zone("sol")
	check((field.trainer.pos as Vector2).is_equal_approx(before), "asking for the same zone again keeps the field as it is")
	field.clear("idle")
	check(field.allies.is_empty() and field.effects.is_empty(), "clearing empties the field")
	field.set_zone("gelo")
	check(field.map == snow and field.ambient.all(func(c: Dictionary) -> bool: return str(Pets.species_def(str(c.species)).element) == "gelo"), "the snow zone brings its own critters")
	host.queue_free()
	await process_frame

func find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)

func screen_tests() -> void:
	var app: FakeApp = FakeApp.new()
	app.profile = profile()
	var uids: Array = add_pets(app.profile, ["leao_dourado", "raposa_glacial", "grifinho", "brasinha"], 6, 0)
	root.add_child(app)
	var host: Control = Control.new()
	host.size = Vector2(1280, 720)
	host.theme = UiKit.make_theme()
	root.add_child(host)
	var screen: PetScreen = PetScreen.open(host, app, "Caçada")
	await process_frame
	var tab: HuntTab = screen.hunt_tab
	check(tab.visible and find(screen, "HuntStart") != null and find(screen, "Zone_sol") != null and find(screen, "Zone_viking") != null, "the Caçada tab lists the zones and the start button")
	check(tab.team.size() == 3 and not (find(screen, "HuntStart") as Button).disabled, "it suggests a team of the best pets and lets you start")
	check((find(screen, "HuntCollect") as Button).disabled and (find(screen, "HuntStop") as Button).disabled, "collect and stop are off before a hunt")
	check(find(screen, "BuyPass") != null and (find(screen, "BuyPass") as Button).disabled, "the pass is offered, but only buyable on the Steam build")
	tab.pick_zone("gelo")
	check(tab.zone == "gelo" and find(screen, "Zone_gelo") != null, "picking a zone selects it")
	check((find(screen, "TierUp") as Button).disabled and (find(screen, "TierDown") as Button).disabled, "tier 1 is the only tier at first")
	tab.open_picker()
	check(find(screen, "TeamPicker") != null and find(screen, "Pick_%d" % int(uids[3])) != null, "the picker lists every pet")
	var before_team: Array = tab.team.duplicate()
	tab.toggle_member(int(uids[3]))
	check(tab.team.size() == before_team.size() + 1 and tab.team.back() == int(uids[3]), "picking a pet adds it at the end of the team")
	tab.toggle_member(int(uids[3]))
	check(tab.team == before_team, "picking it again takes it out")
	tab.toggle_member(int(uids[3]))
	tab.toggle_member(int(uids[2]))
	check(not tab.team.has(int(uids[2])) and tab.team.size() == before_team.size(), "a team member can be dropped from the picker")
	tab.close_picker()
	await tab.do_start()
	check(bool(app.profile.hunt.active) and str(app.profile.hunt.zone) == "gelo", "the start button starts the hunt in the chosen zone")
	check((find(screen, "HuntStart") as Button).disabled, "starting again with the same setup is off")
	check((find(screen, "HuntStop") as Button).text == tr("PARAR") and not (find(screen, "HuntStop") as Button).disabled, "the stop button turns on")
	check(tab.arena != null, "the arena exists")
	app.profile.hunt_clock += 1500
	tab.rebuild()
	for i in range(40):
		await process_frame
	check(int(tab.cache.slots) == 125 and int(tab.cache.report.slots) == 125, "the live tally follows the clock (125 encounters in 25 minutes)")
	check(tab.arena.encounter.size() > 0 and int(tab.arena.encounter.n) == int(app.profile.hunt.n) + 125, "the arena shows the encounter in progress")
	check(not (find(screen, "HuntCollect") as Button).disabled, "collect turns on once something piled up")
	var live_wins: int = int(tab.cache.report.wins)
	var coins_before: int = app.profile.coins
	await tab.do_collect()
	var summary: Node = find(host, "HuntReport")
	if summary == null:
		summary = find(screen, "HuntReport")
	check(summary != null, "collecting opens the summary")
	check(int(app.profile.hunt.report.wins) == live_wins and app.profile.coins == coins_before + int(app.profile.hunt.report.coins), "what the screen showed is exactly what the collect gave")
	if summary != null:
		var close: Button = find(summary, "ReportClose") as Button
		close.pressed.emit()
		await process_frame
	# Caught Lendário: the cinematic comes first, then the summary.
	app.profile.hunt.legend = int(PetHunt.rules().boss.forced_after)
	var strong: Array = add_pets(app.profile, STRONG, 30, 5)
	app.profile.hunt_set("gelo", 1, strong)
	app.profile.hunt_clock += PetHunt.cycle() + 1
	var seen: Array = [false]
	screen.child_entered_tree.connect(func(node: Node) -> void:
		if node is HatchOutcome and (node as HatchOutcome).capture:
			seen[0] = true
			await process_frame
			(node as HatchOutcome).age = HatchOutcome.SHAKE_TIME + 2.0
			await process_frame
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.pressed = true
			click.button_index = MOUSE_BUTTON_LEFT
			(node as HatchOutcome)._gui_input(click))
	tab.adopt()
	await tab.do_collect()
	check(seen[0], "a caught Lendário gets its own reveal")
	check(app.profile.pet_album.has("lobo_boreal"), "and the album records it")
	var late: Node = find(screen, "HuntReport")
	if late != null:
		late.queue_free()
	tab.do_stop()
	await process_frame
	check(not bool(app.profile.hunt.active), "stopping ends the hunt")
	for audio_name in ["hunt_hit", "hunt_skill", "hunt_win", "hunt_boss", "hunt_capture"]:
		check(ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % audio_name), "the sound %s exists" % audio_name)
	check(ResourceLoader.exists("res://assets/cosmetics/passe_cacador/icon.png"), "the pass has its icon")
	check(PetHunt.zones().all(func(z: Dictionary) -> bool: return ResourceLoader.exists(PetHunt.zone_art(str(z.id)))), "every zone has its scenery")
	screen.queue_free()
	host.queue_free()
	app.queue_free()
	await create_timer(0.3).timeout
