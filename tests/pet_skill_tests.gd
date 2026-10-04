extends SceneTree

# The pet's skill in battle (0.22): one per battle by the pet's element, scaled by rarity and
# stars, from the owner's second turn. It is an intent like any other, so it travels in
# lockstep and in replays: a scripted battle that uses it is replayed to the same state.

var checks: int = 0
var failures: int = 0
var balance: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://pet_skill_test_profile.json"
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	data_checks()
	profile_checks()
	rule_checks()
	effect_checks()
	await lockstep_checks()
	await screen_checks()
	print("PET SKILL RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func skill(element: String, rarity: String = "comum", stars: int = 0) -> Dictionary:
	var species: String = ""
	for entry: Dictionary in Pets.data().species:
		if str(entry.element) == element and str(entry.rarity) == rarity:
			species = str(entry.id)
	return {"species": species, "element": element, "rarity": rarity, "stars": stars}

# The first pet of a profile is already active; make sure it is, whatever the rule.
func equip_first(profile: PlayerProfile) -> bool:
	if profile.pet_active != int(profile.pets[0].uid):
		profile.apply_op("pet_equip", [int(profile.pets[0].uid)], balance)
	return profile.pet_active == int(profile.pets[0].uid)

func data_checks() -> void:
	var rules: Dictionary = Pets.battle_rules()
	var kinds: Array = ["damage", "crit", "shield", "wind", "pow"]
	var ok: bool = true
	for element: Dictionary in Pets.data().elements:
		var def: Dictionary = Pets.skill_def(str(element.id))
		ok = ok and not def.is_empty() and str(def.kind) in kinds and float(def.value) > 0.0 and str(def.name) != "" and str(def.desc).contains("%d")
	check(ok, "every element has a skill with a name, a text and a known effect")
	var rarities: Array = Pets.rarities().map(func(entry: Dictionary) -> String: return str(entry.id))
	check(rarities.all(func(id: String) -> bool: return rules.scale.has(id)) and int(rules.uses) >= 1 and int(rules.from_round) >= 1, "every rarity has a strength, and the use limits are set")
	check(is_equal_approx(Pets.skill_power(skill("sol")), 1.0) and is_equal_approx(Pets.skill_power(skill("sol", "lendario")), 1.5) and is_equal_approx(Pets.skill_power(skill("sol", "comum", 5)), 1.2), "the strength follows rarity and stars")
	check(is_equal_approx(Pets.skill_value(skill("sol")), 0.25) and is_equal_approx(Pets.skill_value(skill("sol", "lendario", 5)), 0.25 * 1.5 * 1.2), "the skill's value is the base times that strength")
	check(Pets.skill_text(skill("sol")) == "O seu próximo tiro causa +25% de dano." and Pets.skill_text(skill("viking", "lendario")).contains("52%"), "the text gives the real number")
	check(Pets.skill_text({}) == "" and Pets.skill_entry({}).is_empty() and Pets.skill_entry({"species": "nope"}).is_empty(), "no pet, no skill")

func profile_checks() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	check(profile.entry(balance).pet_skill.is_empty(), "without an active pet the entry has no skill")
	check(profile.grant_pet("escaravelho_solar") and equip_first(profile), "a pet is hatched and equipped")
	var entry: Dictionary = profile.entry(balance)
	check(entry.pet_skill.element == "sol" and entry.pet_skill.rarity == "comum" and entry.pet_skill.stars == 0 and entry.pet_skill.species == "escaravelho_solar", "the entry carries what the battle needs")
	var fighter: TankFighter = TankFighter.new()
	fighter.setup(0, entry, Armory.weapon_for_entry(entry), balance)
	check(fighter.pet_skill.element == "sol" and fighter.pet_uses == int(Pets.battle_rules().uses), "the fighter starts with its uses")
	var none: TankFighter = TankFighter.new()
	none.setup(0, {"name": "Sem", "level": 3}, Armory.weapon_for_entry({"weapon": 0}), balance)
	check(none.pet_skill.is_empty() and none.pet_uses == 0, "a fighter without a pet has none")
	var broken: TankFighter = TankFighter.new()
	broken.setup(0, {"name": "Quebrado", "level": 3, "pet_skill": {"element": "fogo"}}, Armory.weapon_for_entry({"weapon": 0}), balance)
	check(broken.pet_skill.is_empty(), "an unknown element is ignored")
	fighter.free()
	none.free()
	broken.free()

func duel(pet: Dictionary) -> LocalMatch:
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var me: Dictionary = {"name": "Dono", "human": true, "level": 8, "pet_skill": pet}
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 77, "turn_seconds": 30, "teams": [[me], [{"name": "Alvo", "level": 8}]]})
	return game

func rule_checks() -> void:
	var game: LocalMatch = duel(skill("sol"))
	var me: TankFighter = game.fighters[0]
	game.active_id = 0
	check(not game.apply_pet(me) and me.pet_uses == 1, "not on the owner's first turn")
	me.turns_started = 2
	game.state = LocalMatch.State.PLAYER_AIMING
	check(game.can_act() and game.use_pet() and me.pet_uses == 0 and game.turn_pet, "from the second turn it works through the local button")
	check(not game.apply_pet(me), "only once per battle")
	me.pet_uses = 1
	check(not game.apply_pet(me), "and once per turn")
	game.turn_pet = false
	game.add_status(me, "selado", null, {"turns": 2})
	check(me.has_status("selado") and not game.apply_pet(me), "a sealed fighter cannot use it")
	game.cleanse(me)
	game.turn_fly = true
	check(not game.apply_pet(me), "nor while flying with the paper plane")
	game.turn_fly = false
	var foe: TankFighter = game.fighters[1]
	check(not game.apply_pet(foe), "a fighter with no pet cannot")
	me.hp = 0
	check(not game.apply_pet(me), "a fallen one cannot")
	game.queue_free()

func effect_checks() -> void:
	# Rajada Solar: the shot hits harder.
	var game: LocalMatch = duel(skill("sol", "lendario", 5))
	var me: TankFighter = game.fighters[0]
	game.active_id = 0
	me.turns_started = 2
	var base: int = int(game.compose_plan(me).damage)
	check(game.apply_pet(me) and is_equal_approx(game.turn_pet_damage, 1.0 + 0.25 * 1.5 * 1.2), "the Rajada Solar sets its multiplier from rarity and stars")
	var boosted: int = int(game.compose_plan(me).damage)
	check(boosted > base and absf(float(boosted) / float(base) - game.turn_pet_damage) < 0.02, "and the shot deals that much more (%d -> %d)" % [base, boosted])
	game.begin_turn()
	check(game.turn_pet_damage == 1.0 and not game.turn_pet and not game.turn_pet_crit, "the effect lasts for the turn only")
	game.queue_free()
	# Truque da Máscara: a sure critical.
	var mask: LocalMatch = duel(skill("mascara"))
	var owner: TankFighter = mask.fighters[0]
	var rival: TankFighter = mask.fighters[1]
	mask.active_id = 0
	owner.turns_started = 2
	var texts: Array = []
	mask.damage_text.connect(func(_at: Vector2, text: String, _color: Color) -> void: texts.append(text))
	check(mask.apply_pet(owner) and mask.turn_pet_crit, "the Truque da Máscara arms a critical")
	mask.hit_fighter(owner, rival, 100, rival.position, false, {})
	check(texts.any(func(t: String) -> bool: return t.begins_with("CRÍTICO")), "the next hit is a critical even without Sorte")
	mask.queue_free()
	# Muralha Glacial: heals and shields.
	var ice: LocalMatch = duel(skill("gelo", "raro"))
	var holder: TankFighter = ice.fighters[0]
	ice.active_id = 0
	holder.turns_started = 2
	holder.hp = holder.max_hp - 400
	var before: int = holder.hp
	check(ice.apply_pet(holder) and holder.hp > before and holder.hp <= before + roundi(holder.max_hp * 0.18 * 1.15) + 1 and holder.shield == 0.5, "the Muralha Glacial heals and halves the next hit")
	ice.queue_free()
	# Corrente de Ar: no wind, energy back.
	var sky: LocalMatch = duel(skill("ceu"))
	var flier: TankFighter = sky.fighters[0]
	sky.active_id = 0
	flier.turns_started = 2
	sky.wind = 4.5
	sky.energy = 20.0
	check(sky.apply_pet(flier) and sky.wind == 0.0 and sky.energy > 20.0 and sky.energy <= float(flier.max_energy), "the Corrente de Ar clears the wind and gives energy back")
	sky.queue_free()
	# Selo de Runa: POW.
	var rune: LocalMatch = duel(skill("viking", "epico"))
	var seer: TankFighter = rune.fighters[0]
	rune.active_id = 0
	seer.turns_started = 2
	seer.pow_gauge = 10.0
	check(rune.apply_pet(seer) and is_equal_approx(seer.pow_gauge, 10.0 + 100.0 * 0.35 * 1.3), "the Selo de Runa fills the POW bar")
	rune.queue_free()
	var capped: LocalMatch = duel(skill("viking", "lendario", 5))
	var big: TankFighter = capped.fighters[0]
	capped.active_id = 0
	big.turns_started = 2
	big.pow_gauge = 90.0
	capped.apply_pet(big)
	check(big.pow_gauge == 100.0, "and never past the maximum")
	capped.queue_free()

func solution(game: LocalMatch) -> Vector3:
	var me: TankFighter = game.local()
	var foe: TankFighter = game.fighters[1]
	var scale: float = float(me.weapon.get("projectile", {}).get("wind_scale", 1.0))
	return EnemyAI.choose_shot(me, foe, game.terrain, game.wind * float(game.balance.wind_accel) * scale * game.wind_factor(me), game.balance)

# A scripted battle in which the owner uses the skill on its second turn: the replay must
# reach the same state, and without the intent it must not.
func lockstep_checks() -> void:
	check("pet" in MatchHost.ACTIONS and "pet" in Replay.ACTIONS, "the server and the replays accept the 'pet' intent")
	var config: Dictionary = {"mode": "pvp", "map": "ilha_celeste", "seed": 31337, "turn_seconds": 15, "lockstep": true, "local": 0, "teams": [[{"name": "Dono", "human": true, "level": 8, "pet_skill": skill("sol", "lendario", 3)}], [{"name": "Robo", "level": 8}]]}
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start(config)
	var host: LocalHost = LocalHost.new()
	host.game = game
	game.remote = host.submit
	root.add_child(host)
	host.set_physics_process(false)
	var stage: int = 0
	var last_round: int = -1
	var power: float = 50.0
	var used: bool = false
	for i in range(40000):
		if not game.running:
			break
		if game.round_number != last_round:
			last_round = game.round_number
			stage = 0
		if stage == 0 and game.can_act():
			if not used and game.fighters[0].turns_started >= 2:
				host.submit("pet", {})
				used = true
			var shot: Vector3 = solution(game)
			host.submit("aim", {"d": 0.0, "angle": shot.x})
			host.submit("charge", {})
			power = shot.y
			stage = 1
		elif stage == 1 and game.active_id == game.local_id and game.state == LocalMatch.State.PLAYER_CHARGING and host.pending.is_empty():
			host.submit("release", {"power": power})
			stage = 2
		host.advance()
	var replay: Dictionary = Replay.make(config, host.history, host.tick, game.winner_team, {})
	check(used and replay.inputs.any(func(entry: Array) -> bool: return entry[2] == "pet") and game.fighters[0].pet_uses == 0, "the battle recorded the skill as an intent")
	var runner: ReplayRunner = ReplayRunner.new()
	root.add_child(runner)
	runner.begin(Replay.clean(JSON.parse_string(JSON.stringify(replay))))
	runner.run_all()
	check(runner.game.checksum() == game.checksum() and runner.tick == host.tick and runner.game.fighters[0].pet_uses == 0, "the replay reaches the very same battle, skill included")
	var without: Dictionary = Replay.clean(JSON.parse_string(JSON.stringify(replay)))
	without.inputs = without.inputs.filter(func(entry: Array) -> bool: return entry[2] != "pet")
	var other: ReplayRunner = ReplayRunner.new()
	root.add_child(other)
	other.begin(without)
	other.run_all()
	check(other.game.checksum() != game.checksum() or other.game.fighters[0].stats.damage < runner.game.fighters[0].stats.damage, "without it the battle is a different one (%d against %d damage)" % [int(other.game.fighters[0].stats.damage), int(runner.game.fighters[0].stats.damage)])
	runner.queue_free()
	other.queue_free()
	game.queue_free()
	host.queue_free()

func screen_checks() -> void:
	PlayerProfile.path_override = "user://pet_skill_test_screens.json"
	if FileAccess.file_exists("user://pet_skill_test_screens.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://pet_skill_test_screens.json"))
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile.created = true
	app.profile.grant_pet("pinguim_cristal")
	equip_first(app.profile)
	var battle: BattleScreen = BattleScreen.new()
	battle.config = {"mode": "pvp", "map": "ilha_celeste", "turn_seconds": 30, "teams": [[app.profile.entry(balance)], [{"name": "Rival", "level": 5}]]}
	app.switch_to(battle, "battle")
	await process_frame
	await process_frame
	var game: LocalMatch = battle.game
	battle.game.set_physics_process(false)
	var button: SkillSlot = battle.hud.find_child("PetSkill", true, false)
	check(button != null and button.tooltip_text.contains("Muralha Glacial") and battle.hud.pet_button == button, "the HUD has a slot for the pet's skill ")
	check(game.local().companion != null and is_instance_valid(game.local().companion), "the pet stands next to its owner")
	game.active_id = 0
	game.state = LocalMatch.State.PLAYER_AIMING
	await process_frame
	await process_frame
	check(button.disabled, "it is disabled on the first turn")
	game.local().turns_started = 2
	await process_frame
	await process_frame
	check(not button.disabled, "and ready from the second")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	battle._unhandled_key_input(key)
	await process_frame
	await process_frame
	check(game.local().pet_uses == 0 and game.turn_pet and button.disabled, "the G key uses it")
	app.queue_free()
	await process_frame
