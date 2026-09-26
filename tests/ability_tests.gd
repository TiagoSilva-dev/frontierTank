extends SceneTree

# 0.14: PvE monsters use abilities instead of shooting (leap, dive, slam, sky, breath,
# guard, war cry, heal; burning and freezing), picked by what makes sense where everyone
# stands and identical on every online copy; the specials (POW) fly with their own art
# and explode with their weapon's animation; the Viking instance.

var failures: int = 0
var checks: int = 0
var balance: Dictionary
var shots_seen: bool = false

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func def_of(id: String) -> Dictionary:
	for entry: Dictionary in balance.enemies:
		if entry.id == id:
			return entry
	return {}

func ability_of(enemy: String, id: String) -> Dictionary:
	for ability: Dictionary in def_of(enemy).get("abilities", []):
		if ability.id == id:
			return ability
	return {}

# A PvE battle on the Viking beach: heroes on the left island, monsters where asked.
func battle(game: LocalMatch, monsters: Array, hero_xs: Array = [300.0], seed: int = 77) -> void:
	var heroes: Array = []
	for i in range(hero_xs.size()):
		heroes.append({"name": "Nilo%d" % i, "human": true, "level": 20, "arma": {"id": "trovao", "quality": "normal", "level": 0}})
	var entries: Array = []
	for id: String in monsters:
		entries.append({"enemy": id})
	game.start({"mode": "pve", "map": "praia_drakkar", "seed": seed, "turn_seconds": 20, "players": hero_xs.size(), "teams": [heroes, entries], "phase": {"name": "Teste", "objective": "defeat"}})
	for i in range(hero_xs.size()):
		place(game, game.fighters[i], float(hero_xs[i]))

func place(game: LocalMatch, fighter: TankFighter, x: float) -> void:
	fighter.position = Vector2(x, game.terrain.surface_y(x) - 1)
	fighter.settled = true
	fighter.update_pose()

func monster(game: LocalMatch, index: int = 0) -> TankFighter:
	return game.fighters.filter(func(f: TankFighter) -> bool: return f.team == 1)[index]

# Plays one whole monster turn with the given ability (or its own choice with "").
func monster_turn(game: LocalMatch, fighter: TankFighter, ability_id: String = "") -> void:
	for other in game.fighters:
		other.delay = 1000.0
	fighter.delay = 0.0
	game.begin_turn()
	var round: int = game.round_number
	if ability_id != "":
		game.ability = ability_of(str(fighter.monster.id), ability_id)
	for i in range(60 * 12):
		game._physics_process(1.0 / 60)
		if not game.projectiles.is_empty():
			shots_seen = true
		if game.round_number != round or not game.running:
			break

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)

	# --- Data: every monster that acts has abilities, and one it can use from afar
	var kinds: Array[String] = ["leap", "dive", "slam", "sky", "breath", "heal", "guard", "roar"]
	var data_ok: bool = true
	var ranged_ok: bool = true
	var icons_ok: bool = true
	for def: Dictionary in balance.enemies:
		if def.rank == "totem":
			continue
		var list: Array = def.get("abilities", [])
		data_ok = data_ok and not list.is_empty() and list.all(func(a: Dictionary) -> bool: return str(a.get("kind", "")) in kinds and str(a.get("name", "")) != "" and str(a.get("id", "")) != "")
		ranged_ok = ranged_ok and list.any(func(a: Dictionary) -> bool: return a.kind == "sky" and not a.get("fury", false))
		for a: Dictionary in list:
			icons_ok = icons_ok and ResourceLoader.exists("res://assets/effects/abilities/icons/%s.png" % a.kind)
			if a.kind == "sky" and str(a.get("fx", "")) != "lightning":
				icons_ok = icons_ok and ResourceLoader.exists("res://assets/effects/abilities/drops/%s.png" % str(a.get("fx", "")))
	check(data_ok, "every monster has abilities of known kinds, with names")
	check(ranged_ok, "every monster has a ranged ability for targets out of reach")
	check(icons_ok, "every ability kind has its icon and every falling thing its PixelLab art")

	# --- Leap: the raider jumps beside the hero, strikes and jumps back; no shot
	battle(game, ["saqueador_viking"], [300.0])
	var raider: TankFighter = monster(game)
	place(game, raider, 640.0)
	var hero: TankFighter = game.fighters[0]
	var hp: int = hero.hp
	var closest: Array = [INF]
	var watch: Callable = func(kind: String, _p: Vector2, _d: Dictionary) -> void:
		if kind == "strike":
			closest[0] = absf(raider.position.x - hero.position.x)
	game.effect.connect(watch)
	monster_turn(game, raider, "machadada")
	game.effect.disconnect(watch)
	check(hero.hp < hp and float(closest[0]) < 90.0 and absf(raider.position.x - 640.0) < 4.0 and not raider.leaping, "leap: the raider jumps beside the hero, strikes and jumps back")
	check(not shots_seen, "monsters never fire a projectile")

	# --- Dive: the raven strikes and flies back to where it was
	battle(game, ["corvo_runico"], [300.0])
	var raven: TankFighter = monster(game)
	place(game, raven, 700.0)
	hero = game.fighters[0]
	hp = hero.hp
	var home: Vector2 = raven.position
	monster_turn(game, raven, "bicada_runica")
	check(hero.hp < hp and raven.position.distance_to(home) < 4.0, "dive: the raven pecks and returns home")

	# --- Slam: only the heroes inside the shockwave are hit
	battle(game, ["berserker_urso"], [300.0, 1700.0])
	var berserker: TankFighter = monster(game)
	place(game, berserker, 420.0)
	var near_hp: int = game.fighters[0].hp
	var far_hp: int = game.fighters[1].hp
	monster_turn(game, berserker, "machados_giratorios")
	check(game.fighters[0].hp < near_hp and game.fighters[1].hp == far_hp, "slam: the shockwave hits only who is close")

	# --- Sky: the Jarl's lightning falls on the hero and breaks the ground
	battle(game, ["jarl_barba_ferro"], [300.0])
	var jarl: TankFighter = monster(game)
	place(game, jarl, 1900.0)
	hero = game.fighters[0]
	hp = hero.hp
	var mask_before: PackedByteArray = game.terrain.mask.get_data()
	monster_turn(game, jarl, "martelo_do_trovao")
	check(hero.hp < hp and game.terrain.mask.get_data() == mask_before, "sky: the Jarl's hammer calls lightning on the hero (spells do not dig wells)")
	jarl.hp = jarl.max_hp / 3
	hp = hero.hp
	monster_turn(game, jarl, "ira_de_valhalla")
	check(hero.hp < hp and game.terrain.mask.get_data() != mask_before, "the Jarl's fury spell breaks the ground")
	# A fury spell hits the whole party; bosses spread single-target spells from 3 players.
	battle(game, ["jarl_barba_ferro"], [200.0, 420.0, 1700.0])
	jarl = monster(game)
	place(game, jarl, 1100.0)
	var before: Array = game.fighters.slice(0, 3).map(func(f: TankFighter) -> int: return f.hp)
	monster_turn(game, jarl, "martelo_do_trovao")
	check(range(3).all(func(i: int) -> bool: return game.fighters[i].hp < int(before[i])), "with 3 players the boss's spell falls on everyone")

	# --- Guard and cooldown
	battle(game, ["jarl_barba_ferro", "saqueador_viking"], [300.0])
	jarl = monster(game, 0)
	raider = monster(game, 1)
	place(game, jarl, 1800.0)
	place(game, raider, 1700.0)
	monster_turn(game, jarl, "muralha_de_escudos")
	check(jarl.shield < 1.0 and raider.shield < 1.0 and int(jarl.cooldowns.get("muralha_de_escudos", 0)) == 4, "guard: the shield wall covers the Jarl and his raider, then waits 4 turns")
	check(not EnemyAI.ability_ready(game, jarl, game.fighters[0], ability_of("jarl_barba_ferro", "muralha_de_escudos"), false), "an ability on cooldown is not chosen")

	# --- War cry: the next attack of the allies is 30% stronger
	battle(game, ["saqueador_viking", "saqueador_viking"], [300.0])
	var first: TankFighter = monster(game, 0)
	var second: TankFighter = monster(game, 1)
	place(game, first, 1700.0)
	place(game, second, 1800.0)
	monster_turn(game, first, "grito_de_guerra")
	check(is_equal_approx(first.empower, 1.3) and is_equal_approx(second.empower, 1.3), "war cry: allies nearby are empowered")
	game.ability = ability_of("saqueador_viking", "machadada")
	game.ability_run = {"empower": second.empower}
	var plain: float = float(second.weapon.damage) * float(balance.pve.ability_damage)
	check(game.ability_damage(second) == roundi(plain * 1.3), "an empowered attack deals 30% more")

	# --- Heal: the rune raven restores its hurt allies
	battle(game, ["corvo_runico", "saqueador_viking"], [300.0])
	raven = monster(game, 0)
	raider = monster(game, 1)
	place(game, raven, 1800.0)
	place(game, raider, 1700.0)
	raider.hp = raider.max_hp / 2
	var hurt: int = raider.hp
	check(EnemyAI.ability_ready(game, raven, game.fighters[0], ability_of("corvo_runico", "runa_restauradora"), false), "a hurt ally makes the healing rune available")
	monster_turn(game, raven, "runa_restauradora")
	check(raider.hp == hurt + roundi(raider.max_hp * 0.2), "the rune raven heals its allies 20%")

	# --- Burning: the heat wave keeps hurting at the start of the next turns
	battle(game, ["rei_helio"], [300.0])
	var helio: TankFighter = monster(game)
	place(game, helio, 420.0)
	hero = game.fighters[0]
	monster_turn(game, helio, "onda_de_calor")
	check(hero.burn_turns == 2 and hero.burn_damage > 0, "the heat wave sets the hero on fire for 2 turns")
	hp = hero.hp
	for other in game.fighters:
		other.delay = 1000.0
	hero.delay = 0.0
	game.begin_turn()
	check(hero.hp == hp - hero.burn_damage and hero.burn_turns == 1, "burning hurts at the start of the hero's turn")

	# --- Freeze: the Snow Queen's breath freezes on every second attack
	battle(game, ["rainha_nevasca"], [300.0])
	var queen: TankFighter = monster(game)
	place(game, queen, 1100.0)
	hero = game.fighters[0]
	monster_turn(game, queen, "sopro_glacial")
	var frozen_first: int = hero.frozen
	hero.frozen = 0
	monster_turn(game, queen, "sopro_glacial")
	check(frozen_first == 0 and hero.frozen == 1, "the Snow Queen's breath freezes on her second attack")

	# --- Choice: nobody leaps at a target out of reach; fury only while enraged
	battle(game, ["saqueador_viking"], [300.0])
	raider = monster(game)
	place(game, raider, 2200.0)
	var leaps: int = 0
	for i in range(40):
		if EnemyAI.choose_ability(game, raider, game.fighters[0], false).kind == "leap":
			leaps += 1
	check(leaps == 0, "a target out of reach gets a ranged ability, never a leap")
	battle(game, ["berserker_urso"], [300.0])
	berserker = monster(game)
	place(game, berserker, 700.0)
	var calm_fury: int = 0
	var angry_fury: int = 0
	for i in range(60):
		if bool(EnemyAI.choose_ability(game, berserker, game.fighters[0], false).get("fury", false)):
			calm_fury += 1
		if bool(EnemyAI.choose_ability(game, berserker, game.fighters[0], true).get("fury", false)):
			angry_fury += 1
	check(calm_fury == 0 and angry_fury > 10, "fury abilities come only while enraged")

	# --- Lockstep: two copies with the same seed play the same monster turns
	var copies: Array[LocalMatch] = []
	var acted: bool = false
	for k in range(2):
		var copy: LocalMatch = LocalMatch.new()
		root.add_child(copy)
		copy.set_physics_process(false)
		copy.start({"mode": "pve", "map": "aldeia_hidromel", "seed": 4040, "turn_seconds": 20, "players": 1, "lockstep": true,
			"teams": [[{"name": "Nilo", "human": true, "level": 20, "arma": {"id": "trovao", "quality": "normal", "level": 0}}], [{"enemy": "berserker_urso"}, {"enemy": "saqueador_viking"}, {"enemy": "corvo_runico"}]],
			"phase": {"name": "Teste", "objective": "defeat"}})
		copy.apply_auto(0, true)
		copies.append(copy)
	for i in range(60 * 90):
		for copy in copies:
			copy.step(1.0 / 60)
		acted = acted or copies[0].state == LocalMatch.State.MONSTER_ACTING
	check(acted and copies[0].checksum_text() == copies[1].checksum_text(), "monster abilities play identically on every copy (lockstep)")

	# --- Specials: own projectile art and the weapon's animation where they land
	var art_ok: bool = true
	for weapon: Dictionary in Armory.data().weapons:
		art_ok = art_ok and PowFx.projectile_art(str(weapon.id)) != "" and not PowFx.art_frames(str(weapon.id)).is_empty()
	check(art_ok, "every special has its own projectile art and impact animation")
	check(PowFx.art_frames("canhao_arco_iris").size() < 8, "near-empty frames of a special's animation are skipped")
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 9, "turn_seconds": 10,
		"teams": [[{"name": "Nilo", "human": true, "arma": {"id": "fogo_intenso", "quality": "normal", "level": 0}, "level": 5}], [{"name": "Rival", "arma": {"id": "trovao", "quality": "normal", "level": 0}, "level": 5}]]})
	var shooter: TankFighter = game.fighters[0]
	for other in game.fighters:
		other.delay = 1000.0
	shooter.delay = 0.0
	game.begin_turn()
	shooter.pow_gauge = 100
	game.activate_pow()
	game.state = LocalMatch.State.PLAYER_CHARGING
	game.power = 60
	game.release_shot()
	var pow_art: String = PowFx.projectile_art("fogo_intenso")
	check(game.projectiles.size() == 3 and game.projectiles.all(func(p: TankProjectile) -> bool: return p.texture.resource_path == pow_art and p.align), "the Rajada Infernal flies as three blazing comets, nose first")

	# --- The Viking instance
	var viking: Dictionary = InstanceRun.instance_def("fiorde_viking")
	check(not viking.is_empty() and viking.phases.size() == 3 and viking.boss == "jarl_barba_ferro", "Fiorde dos Vikings: 3 phases up to the Jarl")
	var maps_ok: bool = true
	for phase: Dictionary in viking.phases:
		var map: Dictionary = game.find_map(str(phase.map))
		maps_ok = maps_ok and map.id == phase.map and ResourceLoader.exists(str(map.bg)) and map.terrain.all(func(t: Dictionary) -> bool: return ResourceLoader.exists(str(t.art)))
	check(maps_ok, "its three maps have PixelLab backdrops and painted ground")
	var art_viking: bool = true
	for id: String in ["saqueador_viking", "corvo_runico", "berserker_urso", "jarl_barba_ferro"]:
		var def: Dictionary = def_of(id)
		art_viking = art_viking and ResourceLoader.exists(str(def.sprite)) and ResourceLoader.exists(str(def.idle) + "/frame_04.png") and ResourceLoader.exists(str(def.attack_clip) + "/frame_08.png")
	check(art_viking, "the four Viking enemies have sprite, idle and attack art")
	check(InstanceRun.map_icon({"instance": "fiorde_viking"}) == "res://assets/items/maps/fiorde_viking.png", "Viking map items have their own scroll icon")
	var run: InstanceRun = InstanceRun.new(balance, "fiorde_viking", {}, 1, [{"name": "Nilo", "human": true, "weapon": 0, "level": 6}])
	var config: Dictionary = run.phase_config(run.members)
	config.seed = 5
	game.start(config)
	var first_wave: Array = game.fighters.filter(func(f: TankFighter) -> bool: return f.team == 1).map(func(f: TankFighter) -> String: return str(f.monster.id))
	check(first_wave.has("saqueador_viking") and first_wave.has("corvo_runico") and game.map.id == "praia_drakkar", "phase 1: raiders and rune ravens on the longship beach")

	print("ABILITY RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
