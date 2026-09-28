extends SceneTree

var checks: int = 0
var failures: int = 0

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
	p.coins = 1000000
	return p

func run_tests() -> void:
	var p: PlayerProfile = profile()
	var stones: Array = Armory.data().strengthen.stones
	check(stones.size() == 12 and stones.all(func(s: Dictionary) -> bool: return ResourceLoader.exists(str(s.icon))), "all twelve stones have imported artwork")
	var item: Dictionary = p.add_instance("trovao", "verdadeira")
	p.add_item(str(stones[11].id), 10)
	var original: Dictionary = p.to_data().duplicate(true)
	check(p.strengthen(int(item.uid)) != "" and p.to_data() == original, "wrong-level stone never substitutes or spends gold")
	for stone: Dictionary in stones:
		p.add_item(str(stone.id), 100)
	p.rng.seed = 31
	var before: int = int(p.items[stones[0].id])
	check(p.apply_op("strengthen", [int(item.uid)], {}).error == "" and int(item.level) == 1 and int(p.items[stones[0].id]) == before - 1, "level one succeeds and consumes exactly one matching stone")
	var rules: Dictionary = Armory.data().strengthen
	var chance: float = float(rules.success_chance[1])
	rules.success_chance[1] = 0.0
	var gold: int = p.coins
	before = int(p.items[stones[1].id])
	check(p.apply_op("strengthen", [int(item.uid)], {}).error == "" and int(item.level) == 1 and p.coins == gold - int(rules.coins[1]) and int(p.items[stones[1].id]) == before - 1, "failed attempt consumes one stone and fee while keeping level and item")
	rules.success_chance[1] = chance
	p.coins = 0
	original = p.to_data().duplicate(true)
	check(p.strengthen(int(item.uid)) != "" and p.to_data() == original, "insufficient gold never consumes a stone")
	p.coins = 1000000
	item.level = 12
	original = p.to_data().duplicate(true)
	check(p.strengthen(int(item.uid)) != "" and p.to_data() == original, "+12 cannot spend another stone")
	check(p.buy_stone(str(stones[0].id), 1) != "" and p.to_data() == original, "shop operation cannot bypass instance-only acquisition")
	var restored: PlayerProfile = profile()
	restored.load_data(p.to_data())
	check(restored.items == p.items and int(restored.find_instance(int(item.uid)).level) == 12, "all twelve stacks and the item survive a save round trip")
	var legacy: PlayerProfile = profile()
	legacy.load_data({"version": 5, "items": {"pedra_fortalecimento": 3, "strength_stone_ii": 4, "strength_stone_iii": 5, "strength_stone_iv": 6}})
	check(int(legacy.items[stones[0].id]) == 3 and int(legacy.items[stones[3].id]) == 6, "legacy stone stacks keep their quantities and map to levels one through four")
	# A statistically meaningful check of the real RNG and configured probabilities.
	var observed: int = 0
	p.rng.seed = 1234
	p.items[stones[11].id] = 2000
	p.coins = 2000000
	for i in range(1000):
		item.level = 11
		p.strengthen(int(item.uid))
		observed += int(item.level) - 11
	check(observed > 150 and observed < 250, "the +12 roll follows its 20 percent success chance")
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var team: Array = [{"account": 10, "name": "A", "human": true, "weapon": 0}, {"account": 20, "name": "B", "human": true, "weapon": 1}]
	var a: PlayerProfile = profile()
	var b: PlayerProfile = profile()
	var run: InstanceRun = InstanceRun.new(balance, "templo_sol", {}, 2, team, a)
	run.rng.seed = 92
	var low_ok: bool = true
	var high_seen: Dictionary = {}
	for i in range(500):
		low_ok = low_ok and int(run.roll_stone().stone_level) <= 2
	run.level = 16
	for i in range(10000):
		high_seen[int(run.roll_stone().stone_level)] = true
	check(low_ok and high_seen.size() == 12, "free entry drops low stones and level 16 maps can drop all twelve")
	var pvp_ok: bool = true
	var free_cards_ok: bool = true
	run.level = 0
	for i in range(200):
		for card: Dictionary in Rewards.pvp_cards(balance, run.rng):
			pvp_ok = pvp_ok and Armory.stone_def(str(card.get("item", ""))).is_empty()
		var card: Dictionary = run.roll_card()
		var stone: Dictionary = Armory.stone_def(str(card.get("item", "")))
		free_cards_ok = free_cards_ok and (stone.is_empty() or int(stone.level) <= 2)
	check(pvp_ok and free_cards_ok, "PvP has no stone drops and free-entry cards respect stone level gates")
	var expedition: Expedition = Expedition.new(balance, "templo_sol", {}, team, {10: a, 20: b})
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var config: Dictionary = expedition.phase_config()
	config.seed = 12
	game.start(config)
	var target: TankFighter = game.fighters[2]
	var drops_rules: Dictionary = rules.mob_drops
	var old_killer: float = float(drops_rules.killer_chance)
	var old_party: float = float(drops_rules.party_chance)
	drops_rules.killer_chance = 1.0
	drops_rules.party_chance = 1.0
	var reports: Dictionary = expedition.reward_monster(target, 10, [10, 20])
	check(reports[10].size() == 2 and reports[20].size() == 1 and reports[10][0] == reports[20][0] and reports[10][0].shared and not reports[10][1].shared, "both party members get the same shared item and only the killer gets personal loot")
	var b_before: Dictionary = b.to_data().duplicate(true)
	reports = expedition.reward_monster(target, 20, [10])
	check(not reports.has(20) and reports[10].size() == 1 and b.to_data() == b_before, "a player who left receives neither party nor killer rewards")
	drops_rules.killer_chance = old_killer
	drops_rules.party_chance = old_party
	target.rank = "boss"
	check(run.roll_mob_drop(target, true).size() == 1, "a boss guarantees a shared strengthening stone")
	target.rank = "minion"
	var kills: Array = []
	game.monster_defeated.connect(func(victim: TankFighter, killer: int) -> void: kills.append([victim.player_id, killer]))
	game.hit_fighter(game.fighters[1], target, target.max_hp * 100, target.center(), false, {})
	game.hit_fighter(game.fighters[0], target, 100, target.center(), false, {})
	game.evaluate_winner()
	check(kills.size() == 1 and kills[0][1] == 1, "a lethal hit credits its actual attacker exactly once")
	var poisoned: TankFighter = game.fighters[3]
	poisoned.hp = 1
	game.add_status(poisoned, "veneno", game.fighters[0])
	game.tick_statuses(poisoned)
	check(kills.size() == 2 and kills[1][1] == 0, "damage-over-time kills credit the effect's source")
	var summoned: TankFighter = game.fighters[4]
	summoned.set_meta("summoned", true)
	game.hit_fighter(game.fighters[0], summoned, summoned.max_hp * 100, summoned.center(), false, {})
	check(kills.size() == 2, "summoned monsters cannot be farmed for loot")
	var snapshot: Dictionary = a.to_data().duplicate(true)
	game.queue_free()
	await process_frame
	check(a.to_data() == snapshot, "already granted mob rewards remain after the battle ends")
	print("FORGE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
