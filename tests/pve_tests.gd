extends SceneTree

# 0.9: instances of 3 phases, enemies (minions, guardians, bosses, totems), boss
# mechanics, map items (levels 1–16, qualities and modifiers), party scaling and loot.

var failures: int = 0
var checks: int = 0
var balance: Dictionary

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func hero(name: String = "Nilo", human: bool = true) -> Dictionary:
	return {"name": name, "human": human, "weapon": 0, "level": 6, "tools": ["hp", "", ""]}

func make_run(instance: String, item: Dictionary = {}, players: int = 1, profile: PlayerProfile = null) -> InstanceRun:
	var party: Array = [hero()]
	for i in range(players - 1):
		party.append(hero("Amigo%d" % i))
	return InstanceRun.new(balance, instance, item, players, party, profile)

func play_phase(game: LocalMatch, run: InstanceRun) -> void:
	var config: Dictionary = run.phase_config(run.members)
	config.seed = 321
	game.start(config)

func enemies(game: LocalMatch) -> Array[TankFighter]:
	return game.fighters.filter(func(f: TankFighter) -> bool: return f.team == 1)

func turn_of(game: LocalMatch, fighter: TankFighter) -> void:
	for other in game.fighters:
		other.delay = 1000.0
	fighter.delay = 0.0
	game.begin_turn()

func map_with(mods: Array, level: int = 1, instance: String = "templo_sol") -> Dictionary:
	return {"uid": 1, "instance": instance, "level": level, "quality": "verdadeira", "mods": mods}

func enemy(id: String) -> Dictionary:
	for def: Dictionary in balance.enemies:
		if def.id == id:
			return def
	return {}

func run_tests() -> void:
	# Messages are checked in Portuguese, the source language.
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://test_pve_profile.json"
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.balance.pve.power_error = 0.0
	check(balance.instances.size() == 4 and balance.instances.all(func(i: Dictionary) -> bool: return i.phases.size() == 3), "four instances with 3 phases each")
	check(not balance.pve.has("difficulties"), "the Normal/Difícil/Heroico/Pesadelo difficulties are gone")
	var art_ok: bool = true
	for def: Dictionary in balance.enemies:
		art_ok = art_ok and ResourceLoader.exists(str(def.sprite))
		if def.rank != "totem":
			art_ok = art_ok and ResourceLoader.exists(str(def.idle) + "/frame_00.png") and ResourceLoader.exists(str(def.attack_clip) + "/frame_00.png")
	check(art_ok, "every enemy has PixelLab art (sprite, idle and attack)")
	var maps_ok: bool = true
	for instance: Dictionary in balance.instances:
		for phase: Dictionary in instance.phases:
			maps_ok = maps_ok and balance.maps.any(func(m: Dictionary) -> bool: return m.id == phase.map)
	check(maps_ok, "every phase has its battle map")

	# --- Phase 1: waves of minions (free entry)
	var run: InstanceRun = make_run("templo_sol")
	play_phase(game, run)
	var hero_fighter: TankFighter = game.fighters[0]
	check(game.pve and game.phase.index == 0 and enemies(game).size() == 2 and game.waves.size() == 1, "phase 1: two minions now, a second wave waiting")
	check(enemies(game).all(func(f: TankFighter) -> bool: return f.is_monster and f.rank == "minion" and not f.is_boss), "minions are monsters, not bosses")
	check(hero_fighter.prone and not hero_fighter.is_monster, "the hero still battles lying prone")
	check(is_equal_approx(game.turn_seconds, 20.0), "instances use 20 s turns")
	for enemy in enemies(game):
		enemy.hp = 0
	check(not game.evaluate_winner() and enemies(game).filter(func(f: TankFighter) -> bool: return f.hp > 0).size() == 2 and game.waves.is_empty(), "clearing a wave brings the next one")
	var dropped: TankFighter = enemies(game)[-1]
	check(not dropped.settled or dropped.position.y < game.terrain.surface_y(dropped.position.x), "the new wave falls from the sky")
	# Minion AI fires by itself
	turn_of(game, dropped)
	check(not game.can_act(), "players cannot act on a minion's turn")
	for i in range(600):
		game._physics_process(1.0 / 60)
		if game.state == LocalMatch.State.PROJECTILE_FLYING:
			break
	check(game.state == LocalMatch.State.PROJECTILE_FLYING, "minions calculate and fire autonomously")
	for enemy in enemies(game):
		enemy.hp = 0
	check(game.evaluate_winner() and game.winner_team == 0, "phase 1 is won when the last wave falls")

	# --- Between phases: +30% life, POW kept, the fallen come back with 20%
	hero_fighter.hp = 1000
	hero_fighter.pow_gauge = 70
	var hero_max: int = hero_fighter.max_hp
	var report: Dictionary = run.complete_phase(game)
	check(run.phase_index == 1 and run.phases_won == 1, "the run advances to phase 2")
	check(int(run.carry[0].hp) == mini(hero_max, 1000 + roundi(hero_max * 0.3)) and is_equal_approx(float(run.carry[0].pow), 70.0), "between phases life recovers 30% and POW is kept")
	check(int(report.gold) > 0 and report.has("maps"), "each phase won gives gold and may drop maps")
	play_phase(game, run)
	hero_fighter = game.fighters[0]
	# +12 POW if the hero opens the phase (every turn adds pow_per_turn).
	check(hero_fighter.hp == int(run.carry[0].hp) and hero_fighter.pow_gauge >= 70.0 and hero_fighter.pow_gauge <= 70.0 + float(balance.pow_per_turn), "phase 2 starts with the carried life and POW")
	var guardian: TankFighter = enemies(game).filter(func(f: TankFighter) -> bool: return f.rank == "guardian").front()
	check(guardian != null and guardian.idle_animation.frames.size() > 0, "phase 2: the guardian (with its animation) and minions")
	hero_fighter.hp = 0
	check(game.evaluate_winner() and game.winner_team == 1, "the party falling loses the phase")
	run.complete_phase(game)
	check(int(run.carry[0].hp) == roundi(hero_max * 0.2), "a fallen player returns with 20% life")

	# --- Phase 3: the boss
	play_phase(game, run)
	game.fighters[0].hp = game.fighters[0].max_hp
	var boss: TankFighter = enemies(game).front()
	check(boss.is_boss and boss.idle_animation.frames.size() == 5 and boss.attack_animation.frames.size() == 9, "phase 3: Rei Hélio with his PixelLab animations")
	var helio: Dictionary = enemy("rei_helio")
	check(boss.max_hp == int(helio.hp) and boss.weapon.damage == int(helio.damage), "level 1 solo boss: base life and damage")
	turn_of(game, boss)
	check(game.active_id == boss.player_id and not game.can_act(), "human actions blocked during the boss turn")
	game.charge()
	check(game.state == LocalMatch.State.PLAYER_AIMING, "human cannot charge the boss weapon")
	check(not game.use_item("dmg50"), "human cannot spend the boss energy")
	game.paused = true
	game._physics_process(5)
	check(game.ai_time == 0, "pause freezes the boss")
	game.paused = false
	for i in range(240):
		game._physics_process(1.0 / 60)
		if game.state == LocalMatch.State.PROJECTILE_FLYING:
			break
	check(game.state == LocalMatch.State.PROJECTILE_FLYING and boss.attack_animation.visible, "boss fires autonomously with its cast animation")
	var hp_before: int = game.fighters[0].hp
	for i in range(900):
		game._physics_process(1.0 / 60)
		if game.active_id != boss.player_id or not game.running:
			break
	check(game.fighters[0].hp < hp_before, "the boss hits the player using terrain and wind")
	boss.hp = boss.max_hp / 2
	turn_of(game, boss)
	check(game.boss_enraged and boss.weapon.damage == int(helio.fury_damage) and game.status_message.contains("FÚRIA"), "the boss enrages at half health")
	boss.hp = 0
	check(game.evaluate_winner() and game.winner_team == 0, "defeating the boss wins the instance")

	# --- Map level and party scaling
	var level5: InstanceRun = make_run("templo_sol", map_with([], 5))
	var entry: Dictionary = level5.enemy_entry("rei_helio")
	check(entry.hp == roundi(float(helio.hp) * pow(1.12, 4)) and entry.damage == roundi(float(helio.damage) * pow(1.07, 4)), "map level 5: life x1.12 and damage x1.07 per level")
	var level16: InstanceRun = make_run("templo_sol", map_with([], 16))
	check(absf(level16.hp_scale() - 5.47) < 0.05 and absf(level16.damage_scale() - 2.76) < 0.05 and is_equal_approx(level16.reward_scale(), 2.5), "level 16: about 5.5x life, 2.8x damage, 2.5x XP and gold")
	check(is_equal_approx(make_run("templo_sol").reward_scale(), 0.5), "the free entry has low rewards")
	var party4: InstanceRun = make_run("templo_sol", {}, 4)
	check(is_equal_approx(party4.hp_scale(), 3.2) and is_equal_approx(party4.damage_scale(), 1.3) and party4.extra_minions() == 3 and is_equal_approx(party4.party("reward"), 1.5), "4 players: 3.2x life, 1.3x damage, +3 minions, 1.5x rewards")
	var party2: InstanceRun = make_run("templo_sol", {}, 2)
	check(is_equal_approx(party2.hp_scale(), 1.8) and party2.extra_minions() == 1 and int(party2.party("bonus_cards")) == 1, "2 players: 1.8x life, +1 minion, +1 card")
	var bots_only: InstanceRun = InstanceRun.new(balance, "templo_sol", {}, 1, [hero(), hero("Bot", false), hero("Bot2", false)])
	check(is_equal_approx(bots_only.hp_scale(), 1.0), "bots in the party do not scale the instance (players only)")
	party4.phase_index = 2
	var area_config: Dictionary = party4.phase_config(party4.members)
	check(area_config.teams[1].size() == 4, "the extra minions join the boss phase")
	area_config.seed = 5
	game.start(area_config)
	boss = enemies(game).filter(func(f: TankFighter) -> bool: return f.is_boss).front()
	check(int(game.compose_plan(boss).balls) == 3, "with 3-4 players the boss adds an area attack")

	# --- Map items: quality, modifiers, threats
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var shapes_ok: bool = true
	for quality: String in ["normal", "excelente", "verdadeira"]:
		for i in range(40):
			var item: Dictionary = InstanceRun.make_map("picos_gelados", 7, rng, 0.0, quality)
			var count: int = item.mods.size()
			var seen: Dictionary = {}
			for mod: Dictionary in item.mods:
				seen[str(mod.id)] = true
			var unique: bool = seen.size() == count
			var in_range: bool = item.mods.all(func(m: Dictionary) -> bool: return not InstanceRun.mod_def(m.id).has("range") or (int(m.value) >= int(InstanceRun.mod_def(m.id).range[0]) and int(m.value) <= int(InstanceRun.mod_def(m.id).range[1])))
			var expected: Array = {"normal": [0, 0], "excelente": [1, 2], "verdadeira": [3, 4]}[quality]
			shapes_ok = shapes_ok and count >= expected[0] and count <= expected[1] and unique and in_range and item.level == 7
	check(shapes_ok, "maps: Normal 0, Excelente 1–2, Verdadeira 3–4 distinct modifiers in range")
	var threat_run: InstanceRun = make_run("templo_sol", map_with([{"id": "enemy_hp", "value": 30}, {"id": "strong_wind", "value": 1}, {"id": "no_plane", "value": 1}, {"id": "enemy_shield", "value": 1}, {"id": "boss_enraged", "value": 1}, {"id": "low_energy", "value": 20}, {"id": "short_turn", "value": 1}, {"id": "extra_minions", "value": 1}, {"id": "quantity", "value": 10}], 3))
	check(is_equal_approx(threat_run.quantity(), 0.9), "every threat adds +10% item quantity")
	check(threat_run.enemy_entry("escaravelho_solar").hp == roundi(float(enemy("escaravelho_solar").hp) * pow(1.12, 2) * 1.3), "threat: enemies with +X% life")
	threat_run.phase_index = 2
	var threat_config: Dictionary = threat_run.phase_config(threat_run.members)
	threat_config.seed = 8
	game.start(threat_config)
	boss = enemies(game).filter(func(f: TankFighter) -> bool: return f.is_boss).front()
	check(is_equal_approx(game.turn_seconds, 15.0), "threat: 15 s turns instead of 20 s")
	check(enemies(game).size() == 2 and boss.shield == 0.5, "threats: an extra minion and shielded enemies")
	check(game.fighters[0].max_energy < 240, "threat: players with less energy")
	turn_of(game, game.fighters[0])
	check(absf(game.wind) >= float(balance.wind_max) * 0.7 - 0.05, "threat: the wind is always strong")
	check(not game.toggle_fly(), "threat: no paper plane")
	turn_of(game, boss)
	check(game.boss_enraged and boss.weapon.damage == boss.fury_damage, "threat: the boss starts enraged")

	# --- Objectives and boss mechanics of the other instances
	var ice: InstanceRun = make_run("picos_gelados")
	ice.phase_index = 1
	play_phase(game, ice)
	var totems: Array[TankFighter] = enemies(game).filter(func(f: TankFighter) -> bool: return f.rank == "totem")
	check(totems.size() == 3 and game.turn_order().all(func(f: TankFighter) -> bool: return f.rank != "totem"), "Picos Gelados phase 2: three crystals that never act")
	enemies(game).filter(func(f: TankFighter) -> bool: return f.rank == "guardian").front().hp = 0
	check(not game.evaluate_winner(), "killing the golem is not enough: the crystals must break")
	for totem in totems:
		totem.hp = 0
	check(game.evaluate_winner() and game.winner_team == 0, "breaking the crystals wins the phase")
	ice.phase_index = 2
	play_phase(game, ice)
	var queen: TankFighter = enemies(game).front()
	queen.turns_taken = 1
	check(game.compose_plan(queen).freeze and not game.compose_plan(game.fighters[0]).freeze, "Rainha da Nevasca: every second attack freezes")
	var sky: InstanceRun = make_run("ilha_ruinas")
	sky.phase_index = 1
	play_phase(game, sky)
	var goal: int = int(game.phase.turns)
	for i in range(goal):
		turn_of(game, game.fighters[0])
		game.pass_turn()
		for k in range(120):
			game._physics_process(1.0 / 60)
			if not game.running or game.active_id != 0:
				break
		if not game.running:
			break
	check(not game.running and game.winner_team == 0 and game.survived == goal, "Ruínas Flutuantes: surviving %d turns wins the phase" % goal)
	sky.phase_index = 2
	play_phase(game, sky)
	var griffin: TankFighter = enemies(game).front()
	var from: float = griffin.position.x
	turn_of(game, griffin)
	game.after_pve_turn(griffin)
	check(absf(griffin.position.x - from) > 150 and not griffin.settled, "Grifo da Tempestade flies to another spot after attacking")
	var masks: InstanceRun = make_run("trono_mascaras")
	masks.phase_index = 2
	play_phase(game, masks)
	var king: TankFighter = enemies(game).front()
	king.turns_taken = 3
	var before: int = game.fighters.size()
	turn_of(game, king)
	check(game.fighters.size() == before + 1 and game.fighters[-1].rank == "minion", "Rei das Máscaras summons a mask every 3 turns")

	# --- Drops: maps from maps, levels and the boss chest
	var profile: PlayerProfile = PlayerProfile.new()
	var total: int = 0
	var levels: Dictionary = {}
	var trials: int = 3000
	var sample: InstanceRun = make_run("templo_sol", map_with([], 8))
	for t in range(trials):
		for phase in range(3):
			for item: Dictionary in sample.roll_phase_maps(phase):
				total += 1
				levels[int(item.level) - 8] = int(levels.get(int(item.level) - 8, 0)) + 1
	var mean: float = float(total) / trials
	check(mean > 0.82 and mean < 0.98, "about 0.9 maps per run without modifiers (%.2f)" % mean)
	check(absf(float(levels.get(0, 0)) / total - 0.7) < 0.04 and absf(float(levels.get(1, 0)) / total - 0.25) < 0.04 and absf(float(levels.get(2, 0)) / total - 0.05) < 0.02 and not levels.has(3), "dropped maps: same level 70%, +1 25%, +2 5%")
	var rich: InstanceRun = make_run("templo_sol", map_with([{"id": "map_chance", "value": 50}], 8))
	var rich_total: int = 0
	for t in range(trials):
		for phase in range(3):
			rich_total += rich.roll_phase_maps(phase).size()
	check(float(rich_total) / trials > 1.2, "a +map chance modifier sustains more than 1 map per run")
	var free: InstanceRun = make_run("templo_sol")
	check(free.roll_map().level == 1, "the free entry drops level 1 maps")
	var looted: InstanceRun = make_run("templo_sol", map_with([{"id": "boss_card", "value": 1}], 10), 1, profile)
	var loot: Dictionary = looted.finish(true)
	check(int(loot.picks) >= 4 and loot.cards.size() == 8, "the boss chest is bigger: 3 cards + modifiers")
	var kinds: Dictionary = {}
	var qualities: Dictionary = {}
	var ilvl_ok: bool = true
	for t in range(400):
		var card: Dictionary = looted.roll_card()
		kinds[card.get("rarity", "")] = true
		if card.has("weapon"):
			qualities[card.quality] = true
			ilvl_ok = ilvl_ok and int(card.ilvl) == 10
	check(kinds.has("map") and qualities.has("verdadeira"), "cards include maps (own rarity) and Verdadeira weapons")
	check(ilvl_ok, "instance weapons carry the item level of the map")
	check(not make_run("templo_sol", {}, 1, profile).finish(false).has("chest") or make_run("templo_sol", {}, 1, profile).finish(false).chest.is_empty(), "no chest when the party falls")
	profile.pity["picos_gelados"] = int(balance.map_items.loot.pity) - 1
	var guaranteed: InstanceRun = make_run("picos_gelados", {}, 1, profile)
	guaranteed.mods = {}
	var chest_loot: Dictionary = guaranteed.finish(true)
	check(chest_loot.chest.size() == 1 and chest_loot.chest[0].quality == "super" and int(profile.pity.picos_gelados) == 0, "the Super Verdadeira is guaranteed after %d boss kills without one" % int(balance.map_items.loot.pity))
	check(profile.inventory.any(func(i: Dictionary) -> bool: return i.quality == "super" and int(i.get("ilvl", 0)) == 1), "the chest's Super Verdadeira goes to the bag")
	# Maps live in the profile and survive a save
	var stored: Dictionary = profile.add_map(InstanceRun.make_map("ilha_ruinas", 12, rng, 0.0, "excelente"))
	profile.save_profile()
	var reloaded: PlayerProfile = PlayerProfile.new()
	reloaded.load_profile()
	check(reloaded.find_map(int(stored.uid)).level == 12 and reloaded.maps_for("ilha_ruinas").size() >= 1 and reloaded.pity.has("picos_gelados"), "maps and the guarantee counter are saved")
	check(reloaded.remove_map(int(stored.uid)) and reloaded.find_map(int(stored.uid)).is_empty(), "a map can be consumed")

	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("PVE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
