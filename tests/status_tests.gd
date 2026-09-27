extends SceneTree

# 0.16: harder instances. Status effects from the monsters (burning, poison, freeze,
# exhaustion, seal, roots, mark, glare), curses (hex), elite monsters with affixes, the
# Elixir Purificador, more monsters per phase, the same on every lockstep copy, and the
# force bar that only shows the player's own charge.

var failures: int = 0
var checks: int = 0
var balance: Dictionary
var statuses_seen: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func ability_of(enemy: String, id: String) -> Dictionary:
	for entry: Dictionary in balance.enemies:
		if entry.id == enemy:
			for ability: Dictionary in entry.get("abilities", []):
				if ability.id == id:
					return ability
	return {}

# A PvE battle on the Viking beach: heroes on the left, monsters (ids or entries) to the right.
func battle(game: LocalMatch, monsters: Array, hero_xs: Array = [300.0], seed: int = 77, tools: Array = []) -> void:
	var heroes: Array = []
	for i in range(hero_xs.size()):
		heroes.append({"name": "Nilo%d" % i, "human": true, "level": 20, "tools": tools, "arma": {"id": "trovao", "quality": "normal", "level": 0}})
	var entries: Array = []
	for monster: Variant in monsters:
		entries.append(monster if monster is Dictionary else {"enemy": str(monster)})
	game.start({"mode": "pve", "map": "praia_drakkar", "seed": seed, "turn_seconds": 20, "players": hero_xs.size(), "teams": [heroes, entries], "phase": {"name": "Teste", "objective": "defeat"}})
	for i in range(hero_xs.size()):
		place(game, game.fighters[i], float(hero_xs[i]))

func place(game: LocalMatch, fighter: TankFighter, x: float) -> void:
	fighter.position = Vector2(x, game.terrain.surface_y(x) - 1)
	fighter.settled = true
	fighter.update_pose()

func monster(game: LocalMatch, index: int = 0) -> TankFighter:
	return game.fighters.filter(func(f: TankFighter) -> bool: return f.team == 1)[index]

func turn_of(game: LocalMatch, fighter: TankFighter) -> void:
	for other in game.fighters:
		other.delay = 1000.0
	fighter.delay = 0.0
	game.begin_turn()

# Plays one whole monster turn with the given ability (an id of its own or a dictionary).
func monster_turn(game: LocalMatch, fighter: TankFighter, ability: Variant = "") -> void:
	turn_of(game, fighter)
	var round: int = game.round_number
	if ability is Dictionary:
		game.ability = ability
	elif str(ability) != "":
		game.ability = ability_of(str(fighter.monster.id), str(ability))
	for i in range(60 * 12):
		game._physics_process(1.0 / 60)
		if game.round_number != round or not game.running:
			break

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.effect.connect(func(kind: String, _point: Vector2, _data: Dictionary) -> void:
		if kind == "status":
			statuses_seen += 1)

	# --- Data: every status and affix is complete and every ability names real statuses
	var ids: Array = StatusRules.all().map(func(s: Dictionary) -> String: return str(s.id))
	check(ids.size() == 8 and ["queimacao", "veneno", "congelado", "exaustao", "selado", "enraizado", "marcado", "ofuscado"].all(func(id: String) -> bool: return id in ids), "eight status effects: burning, poison, freeze, exhaustion, seal, roots, mark, glare")
	check(StatusRules.all().all(func(s: Dictionary) -> bool: return ResourceLoader.exists(str(s.icon)) and str(s.name) != "" and str(s.label) != "" and str(s.desc) != ""), "every status has its PixelLab icon, name, label and description")
	var known: bool = true
	var carriers: int = 0
	var hexes: int = 0
	for def: Dictionary in balance.enemies:
		for ability: Dictionary in def.get("abilities", []):
			if ability.has("status"):
				carriers += 1
				known = known and (ability.status as Array).all(func(e: Dictionary) -> bool: return str(e.id) in ids)
			if ability.kind == "hex":
				hexes += 1
			known = known and not ability.has("burn")
	check(known and carriers >= 25 and hexes >= 4, "monster abilities carry known status effects (%d abilities, %d curses)" % [carriers, hexes])
	var affixes: Array = balance.elites.affixes
	check(affixes.size() == 7 and affixes.all(func(a: Dictionary) -> bool: return ResourceLoader.exists(str(a.icon)) and (a.get("status", []) as Array).all(func(e: Dictionary) -> bool: return str(e.id) in ids)), "seven elite affixes, each with its icon")
	var cleanse_tool: Dictionary = game.tool_def("cleanse")
	check(not cleanse_tool.is_empty() and ResourceLoader.exists(str(cleanse_tool.icon)), "the Elixir Purificador is sold with the other tools")
	var more: bool = true
	for instance: Dictionary in balance.instances:
		var first: int = 0
		for wave: Array in instance.phases[0].waves:
			first += wave.size()
		more = more and first >= 5 and (instance.phases[2].waves[0] as Array).size() >= 2
	check(more, "every instance: 5+ minions in phase 1 and the boss comes with minions")

	# --- Poison: doses stack to 3, hurt 3% of max life each at the start of the turn, halve heals
	battle(game, ["escaravelho_solar"])
	var hero: TankFighter = game.fighters[0]
	var scarab: TankFighter = monster(game)
	for i in range(4):
		game.add_status(hero, "veneno", scarab)
	check(int(hero.statuses.veneno.stacks) == 3, "poison stacks up to 3 doses")
	var hp: int = hero.hp
	turn_of(game, hero)
	var dose: float = float(StatusRules.def("veneno").per_stack)
	check(hero.hp == hp - roundi(hero.max_hp * dose * 3), "poison: %d%% of max life per dose at the start of the turn" % roundi(dose * 100.0))
	check(game.healing(hero, 100) == 50, "poison halves the healing received")
	game.finish_turn()
	check(int(hero.statuses.veneno.turns) == 2, "poison counts down when the turn ends")

	# --- Freeze: the turn is lost, then one turn of immunity
	battle(game, ["lobo_nevasca"])
	hero = game.fighters[0]
	var wolf: TankFighter = monster(game)
	check(game.add_status(hero, "congelado", wolf) and hero.frozen == 1, "freeze lands")
	turn_of(game, hero)
	check(game.skip_turn and hero.frozen == 0 and hero.immune.has("congelado"), "the frozen hero loses the turn and thaws, immune to ice")
	check(not game.add_status(hero, "congelado", wolf), "a thawed hero cannot be frozen again right away")
	game.finish_turn()
	check(hero.immune.has("congelado"), "the lost turn does not spend the immunity")
	turn_of(game, hero)
	check(not game.skip_turn, "the hero plays the next turn")
	game.finish_turn()
	check(not hero.immune.has("congelado") and game.add_status(hero, "congelado", wolf), "after a turn played, ice can freeze again")

	# --- Exhaustion: skills, the plane and walking cost 50% more
	battle(game, ["lobo_nevasca"])
	hero = game.fighters[0]
	turn_of(game, hero)
	game.add_status(hero, "exaustao", monster(game))
	check(is_equal_approx(game.energy_cost(hero, 80.0), 120.0), "exhaustion: +50% energy for everything")
	game.energy = 100.0
	check(not game.apply_item(hero, "dmg50") and is_equal_approx(game.energy, 100.0), "exhausted, +50% (80) needs 120 energy")
	game.energy = 240.0
	check(game.apply_item(hero, "dmg50") and is_equal_approx(game.energy, 120.0), "and costs 120 when there is enough")

	# --- Seal: no skills 1–9 nor POW; it wears off when the turn ends
	battle(game, ["corvo_runico"], [300.0], 77, ["energy", "", ""])
	hero = game.fighters[0]
	turn_of(game, hero)
	game.add_status(hero, "selado", monster(game))
	hero.pow_gauge = 100.0
	check(not game.apply_item(hero, "dmg50") and not game.apply_pow(hero), "sealed: no skills and no POW")
	check(game.apply_tool(hero, 0), "tools still work while sealed")
	game.finish_turn()
	check(not hero.has_status("selado"), "a one-turn seal is gone when the turn ends")

	# --- Roots: no walking and no plane, but the hero can turn around
	battle(game, ["sentinela_obsidiana"])
	hero = game.fighters[0]
	turn_of(game, hero)
	game.add_status(hero, "enraizado", monster(game))
	var x0: float = hero.position.x
	var energy0: float = game.energy
	game.move_input = -1.0
	for i in range(40):
		game.human_step(1.0 / 60)
	check(is_equal_approx(hero.position.x, x0) and is_equal_approx(game.energy, energy0) and hero.facing == -1, "rooted: turns around but does not walk")
	check(not game.apply_fly(hero), "rooted: no paper plane")
	game.move_input = 0.0

	# --- Mark: 30% more damage from enemies; monsters go for marked prey
	battle(game, ["saqueador_viking"], [300.0, 520.0])
	var near: TankFighter = game.fighters[1]
	var far: TankFighter = game.fighters[0]
	var raider: TankFighter = monster(game)
	place(game, raider, 1500.0)
	hp = far.hp
	game.hit_fighter(raider, far, 100, far.center(), false, {})
	var plain: int = hp - far.hp
	game.add_status(far, "marcado", raider)
	hp = far.hp
	game.hit_fighter(raider, far, 100, far.center(), false, {})
	check(hp - far.hp == roundi(plain * 1.3), "marked: +30% damage taken")
	check(EnemyAI.pick_target(raider, game.fighters) == far, "monsters go for the marked prey")
	near.statuses.clear()

	# --- Curse (hex): the Temple Guardian's Julgamento Solar marks for 2 turns
	battle(game, ["guardiao_templo"])
	hero = game.fighters[0]
	var guardian: TankFighter = monster(game)
	place(game, guardian, 1100.0)
	check(EnemyAI.ability_ready(game, guardian, hero, ability_of("guardiao_templo", "julgamento_solar"), false), "the curse is ready on an unmarked hero")
	monster_turn(game, guardian, "julgamento_solar")
	check(int(hero.statuses.get("marcado", {}).get("turns", 0)) == 2, "Julgamento Solar marks the hero for 2 turns")
	check(not EnemyAI.ability_ready(game, guardian, hero, ability_of("guardiao_templo", "julgamento_solar"), false), "no curse on a hero who already carries it")

	# --- A volley of drops poisons once, not once per drop
	battle(game, ["escaravelho_solar"])
	hero = game.fighters[0]
	scarab = monster(game)
	place(game, scarab, 1100.0)
	var volley: Dictionary = ability_of("escaravelho_solar", "ferrao_solar").duplicate(true)
	volley.count = 3
	volley.spacing = 1.0
	volley.status = [{"id": "veneno"}]
	monster_turn(game, scarab, volley)
	check(int(hero.statuses.get("veneno", {}).get("stacks", 0)) == 1, "one ability applies its poison once, however many drops hit")

	# --- Map threat: effects last one turn more
	battle(game, ["corvo_runico"])
	hero = game.fighters[0]
	game.threats = {"long_status": true}
	game.add_status(hero, "selado", monster(game))
	check(int(hero.statuses.selado.turns) == 2, "threat: negative effects last +1 turn")
	game.threats = {}

	# --- Elixir Purificador: clears every effect; the AI drinks it when afflictions pile up
	battle(game, ["lobo_nevasca"], [300.0], 77, ["cleanse", "cleanse", ""])
	hero = game.fighters[0]
	turn_of(game, hero)
	check(not game.apply_tool(hero, 0), "nothing to cleanse: the elixir is not wasted")
	game.add_status(hero, "exaustao", monster(game))
	game.add_status(hero, "marcado", monster(game))
	check(game.apply_tool(hero, 0) and hero.statuses.is_empty() and hero.tools[0] == "", "the Elixir Purificador removes every effect")
	game.add_status(hero, "selado", monster(game))
	game.add_status(hero, "veneno", monster(game))
	game.apply_auto(hero.player_id, true)
	check(hero.statuses.is_empty() and hero.tools[1] == "", "the AI (Confiar) drinks the elixir when sealed and poisoned")

	# --- Elites: chance by level, stats, looks and affixes
	var run: InstanceRun = InstanceRun.new(balance, "templo_sol", {}, 1, [{"name": "Nilo", "human": true, "weapon": 0, "level": 6}])
	var run10: InstanceRun = InstanceRun.new(balance, "templo_sol", {"uid": 1, "instance": "templo_sol", "level": 10, "quality": "normal", "mods": [{"id": "elite_monsters", "value": 50}]}, 1, run.members)
	var rules: Dictionary = balance.elites
	var base_chance: float = float(rules.chance)
	check(is_equal_approx(run.elite_chance("minion"), base_chance) and run.elite_chance("boss") == 0.0 and is_equal_approx(run.elite_chance("guardian"), base_chance * float(rules.guardian_scale)), "elites: %d%% of minions at the free entry, fewer guardians, never bosses" % roundi(base_chance * 100.0))
	check(is_equal_approx(run10.elite_chance("minion"), (base_chance + float(rules.per_level) * 10) * 1.5), "elites: more with every map level and with the elites threat")
	var entry: Dictionary = run.enemy_entry("escaravelho_solar")
	var plain_hp: int = int(entry.hp)
	run.make_elite(entry, "vampira")
	check(entry.elite == "vampira" and entry.hp == roundi(plain_hp * float(rules.hp)), "an elite has +%d%% life" % roundi((float(rules.hp) - 1.0) * 100.0))
	var total: int = 0
	var elites: int = 0
	for i in range(40):
		var config: Dictionary = run10.phase_config(run10.members)
		for wave: Array in [config.teams[1]] + config.phase.waves:
			for e: Dictionary in wave:
				total += 1
				elites += 1 if e.has("elite") else 0
	check(elites > total * 0.15 and elites < total * 0.6, "level 10 with the elites threat: many elites (%d of %d)" % [elites, total])

	var vampire_entry: Dictionary = run.enemy_entry("escaravelho_solar")
	run.make_elite(vampire_entry, "vampira")
	var armour_entry: Dictionary = run.enemy_entry("escaravelho_solar")
	run.make_elite(armour_entry, "couraca")
	battle(game, [vampire_entry, armour_entry])
	var vampire: TankFighter = monster(game, 0)
	var armoured: TankFighter = monster(game, 1)
	check(vampire.rank_title == "Elite Vampira" and is_equal_approx(vampire.visual.scale.x, 1.15), "an elite wears its affix as title and is drawn bigger")
	check(is_equal_approx(armoured.shield, 0.5), "the armoured elite starts behind its shield")
	hero = game.fighters[0]
	place(game, vampire, 700.0)
	place(game, armoured, 1600.0)
	vampire.hp = vampire.max_hp / 2
	var drained: int = vampire.hp
	hp = hero.hp
	monster_turn(game, vampire, "investida_solar")
	check(hero.hp < hp and vampire.hp == drained + roundi((hp - hero.hp) * 0.35), "the vampire elite heals 35% of the damage it deals")
	armoured.shield = 1.0
	armoured.turns_taken = 2
	turn_of(game, armoured)
	check(is_equal_approx(armoured.shield, 0.5), "the armoured elite raises its shield again every 2 turns")

	var bomb_entry: Dictionary = run.enemy_entry("escaravelho_solar")
	run.make_elite(bomb_entry, "explosiva")
	var swift_entry: Dictionary = run.enemy_entry("escaravelho_solar")
	run.make_elite(swift_entry, "veloz")
	battle(game, [bomb_entry, swift_entry, {"enemy": "escaravelho_solar"}])
	hero = game.fighters[0]
	var bomb: TankFighter = monster(game, 0)
	place(game, bomb, 360.0)
	bomb.hp = 1
	hp = hero.hp
	game.hit_fighter(hero, bomb, 50, bomb.center(), false, {})
	check(bomb.hp == 0 and bomb.exploded and hero.hp < hp, "the explosive elite blows up when it falls and hurts whoever is near")
	var swift: TankFighter = monster(game, 1)
	var plain_scarab: TankFighter = monster(game, 2)
	place(game, swift, 1500.0)
	place(game, plain_scarab, 1650.0)
	monster_turn(game, plain_scarab, "ferrao_solar")
	var plain_delay: float = plain_scarab.delay
	monster_turn(game, swift, "ferrao_solar")
	check(swift.delay < plain_delay * 0.7, "the swift elite comes back sooner (%.0f vs %.0f)" % [swift.delay, plain_delay])

	# --- Lockstep: statuses, curses and elites play identically on every copy
	var copies: Array[LocalMatch] = []
	statuses_seen = 0
	for k in range(2):
		var copy: LocalMatch = LocalMatch.new()
		root.add_child(copy)
		copy.set_physics_process(false)
		copy.effect.connect(func(kind: String, _point: Vector2, _data: Dictionary) -> void:
			if kind == "status":
				statuses_seen += 1)
		copy.start({"mode": "pve", "map": "aldeia_hidromel", "seed": 5150, "turn_seconds": 20, "players": 1, "lockstep": true,
			"teams": [[{"name": "Nilo", "human": true, "level": 20, "arma": {"id": "trovao", "quality": "normal", "level": 0}}],
				[{"enemy": "corvo_runico", "elite": "veneno"}, {"enemy": "berserker_urso"}, {"enemy": "saqueador_viking", "elite": "gelo"}, {"enemy": "jarl_barba_ferro"}]],
			"phase": {"name": "Teste", "objective": "defeat"}})
		copy.apply_auto(0, true)
		copies.append(copy)
	for i in range(60 * 120):
		for copy in copies:
			copy.step(1.0 / 60)
		if not copies[0].running:
			break
	check(statuses_seen > 0 and copies[0].checksum_text() == copies[1].checksum_text(), "status effects and elites play identically on every copy (lockstep, %d effects)" % statuses_seen)

	# --- The force bar only shows the player's own charge
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 9, "turn_seconds": 10,
		"teams": [[{"name": "Nilo", "human": true, "arma": {"id": "trovao", "quality": "normal", "level": 0}, "level": 5}], [{"name": "Rival", "arma": {"id": "trovao", "quality": "normal", "level": 0}, "level": 5}]]})
	var hud: BattleHUD = BattleHUD.new()
	hud.game = game
	game.active_id = 1
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.power = 64.0
	check(hud.visible_force() == 0.0, "an opponent charging: the force bar stays empty")
	game.active_id = game.local_id
	check(is_equal_approx(hud.visible_force(), 64.0), "the player's own charge fills the force bar")
	hud.free()

	print("STATUS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
