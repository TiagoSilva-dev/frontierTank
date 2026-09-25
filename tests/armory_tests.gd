extends SceneTree

# Weapons, qualities, Ferreiro, coupons, looks and every weapon's POW special.

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func run_tests() -> void:
	# Messages are checked in Portuguese, the source language.
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://armory_test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	var data: Dictionary = Armory.data()
	check(data.weapons.size() == 12, "12 DDTank weapons (9 classic + 3 super)")
	check(data.weapons.filter(func(w: Dictionary) -> bool: return w.get("super", false)).size() == 3, "three drop-only Super Verdadeira weapons")
	for weapon: Dictionary in data.weapons:
		check(ResourceLoader.exists(Armory.weapon_icon(str(weapon.id), 0)) and ResourceLoader.exists("res://assets/weapons/%s/tier3.png" % weapon.id), "%s has base and +12 art" % weapon.name)
	# Tiers and auras follow the strengthen level.
	check(Armory.tier_for_level(8) == 0 and Armory.tier_for_level(9) == 1 and Armory.tier_for_level(11) == 2 and Armory.tier_for_level(12) == 3, "weapon art evolves at +9, +10 and +12")
	check(Armory.aura(3).name == "Aura Verde" and Armory.aura(7).name == "Aura Azul" and Armory.aura(10).name == "Aura Roxa" and Armory.aura(12).name == "Aura Vermelha" and Armory.aura(0).is_empty(), "aura colours: 1-5 green, 6-8 blue, 9-11 purple, 12 red")
	# Quality and strengthen raise damage.
	var normal: Dictionary = Armory.build_weapon({"id": "trovao", "quality": "normal", "level": 0})
	var true_weapon: Dictionary = Armory.build_weapon({"id": "trovao", "quality": "verdadeira", "level": 0})
	var maxed: Dictionary = Armory.build_weapon({"id": "trovao", "quality": "verdadeira", "level": 12})
	check(true_weapon.damage > normal.damage and maxed.damage > true_weapon.damage, "Verdadeira beats Normal and +12 beats +0")
	check(Armory.item_name({"id": "kit_medico", "quality": "verdadeira", "level": 5}) == "Verdadeiro Kit Médico +5", "DDTank style item names")
	# Profile: starter, shop, equip.
	var profile: PlayerProfile = PlayerProfile.new()
	check(profile.equipped_instance("arma").id == "quebra_tijolos", "new account starts with a Quebra Tijolos")
	check(profile.look().skin == "base_m" and profile.look().hat == "", "default look: t-shirt and shorts, nothing else")
	profile.coins = 10000
	check(profile.buy("kit_medico", "excelente") == "" and profile.coins == 10000 - 400 * 3, "weapons are bought by quality")
	check(profile.buy("kit_medico", "verdadeira") != "" and profile.coins == 10000 - 400 * 3, "Verdadeira weapons only drop in instances (0.9)")
	check(profile.buy("bumerangue_amor", "super") != "", "super weapons cannot be bought")
	check(profile.buy("roupa_samurai") == "", "outfits can be bought")
	var samurai: Dictionary = profile.inventory[-1]
	check(profile.equip(int(samurai.uid)) == "" and profile.look().skin == "roupa_samurai", "equipping an outfit swaps the character sprite")
	profile.gender = "f"
	check(profile.equip(int(samurai.uid)) != "", "outfits respect the character's gender")
	profile.gender = "m"
	check(profile.unequip("arma") != "", "the weapon slot is never empty")
	# Coupon grants everything once.
	var message: String = profile.redeem("testartudo")
	check(message.begins_with("Todas") and profile.has_item("cabeca_de_boi", "super") and profile.has_item("asas_fenix"), "TESTARTUDO unlocks all weapons and cosmetics")
	check(profile.redeem("TESTARTUDO").begins_with("Este cupom"), "a coupon works once per account")
	check(profile.redeem("NAOEXISTE") == "Cupom inválido.", "unknown coupons are rejected")
	profile.redeem("AURAS")
	var auras: Array = profile.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "quebra_tijolos" and inst.quality == "verdadeira" and int(inst.level) in [3, 7, 10, 12])
	check(auras.size() == 4, "AURAS coupon gives +3/+7/+10/+12 weapons")
	# Ferreiro.
	var weapon: Dictionary = profile.add_instance("fogo_intenso", "excelente")
	var points: int = profile.stone_points()
	var attack_before: int = int(Armory.item_attrs(weapon).ataque)
	var damage_before: int = int(Armory.build_weapon(weapon).damage)
	check(profile.strengthen(int(weapon.uid)) == "" and int(weapon.level) == 1 and profile.stone_points() == points - 1, "strengthen +1 spends 1 stone point")
	check(int(Armory.item_attrs(weapon).ataque) > attack_before and int(Armory.build_weapon(weapon).damage) > damage_before, "strengthening raises the weapon attributes and damage")
	for i in range(11):
		profile.strengthen(int(weapon.uid))
	check(int(weapon.level) == 12 and profile.strengthen(int(weapon.uid)) != "", "strengthen stops at +12")
	var stones_i: int = int(profile.items.pedra_fortalecimento)
	check(profile.fuse("pedra_fortalecimento") == "" and int(profile.items.pedra_fortalecimento) == stones_i - 4, "fusion turns 4 stones into the next level")
	var target: Dictionary = profile.add_instance("fogo_intenso", "verdadeira")
	check(profile.transfer(int(weapon.uid), int(target.uid)) == "" and int(target.level) == 12 and int(weapon.level) == 0, "transfer moves the strengthen level")
	check(profile.transfer(int(target.uid), int(samurai.uid)) != "", "transfer needs items of the same kind")
	check(profile.compose(int(target.uid), "ataque") == "" and int(target.compose.ataque) == 10, "composition adds attributes with a golden crystal")
	profile.equip(int(target.uid))
	var stats: Dictionary = profile.stats({"base_hp": 1500, "hp_per_level": 40, "base_agility": 120, "agility_per_level": 8, "energy": 240})
	check(int(stats.extra.ataque) > 100 and int(stats.dano) == int(Armory.build_weapon(target).damage), "equipped gear feeds the attributes")
	check(profile.look().weapon_level == 12 and Armory.aura_color(profile.look().weapon_level) == Color("ff3b3b"), "a +12 weapon shows the red aura")
	profile.save_profile()
	var reloaded: PlayerProfile = PlayerProfile.new()
	reloaded.load_profile()
	check(reloaded.inventory.size() == profile.inventory.size() and reloaded.equipped_instance("arma").level == 12, "inventory, levels and equipment are saved")
	# Auras only outside battle; the weapon on the back only in battle.
	var shown: Dictionary = {"skin": "base_m", "hair": "", "hat": "", "glasses": "", "wings": "", "weapon": "trovao", "weapon_level": 12, "clothes_level": 8}
	var menu: LookRig = LookRig.new()
	menu.setup(shown, "south")
	check(menu.aura != null and menu.back_weapon == null and menu.glow_color.a > 0, "menus show the auras but not the weapon on the back")
	var fight: LookRig = LookRig.new()
	fight.setup(shown, "prone")
	check(fight.aura == null and fight.back_weapon != null and fight.glow_color.a == 0, "battles show the weapon on the back but no auras")
	menu.back.free()
	menu.free()
	fight.back.free()
	fight.free()
	# Every weapon special runs in battle.
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	for def: Dictionary in data.weapons:
		var entry: Dictionary = {"name": "A", "human": true, "level": 10, "arma": {"id": def.id, "quality": "verdadeira" if not def.get("super", false) else "super", "level": 6}}
		game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 7, "turn_seconds": 10, "teams": [[entry], [{"name": "B", "level": 10, "weapon": 0}]]})
		var me: TankFighter = game.fighters[0]
		var rival: TankFighter = game.fighters[1]
		# Put the rival right in front so the special lands on it.
		rival.position = Vector2(me.position.x + 260, game.terrain.surface_y(me.position.x + 260) - 1)
		for fighter in game.fighters:
			fighter.delay = 1000.0
		me.delay = 0.0
		game.begin_turn()
		me.pow_gauge = 100
		var activated: bool = game.activate_pow()
		me.angle = clampf(45, me.angle_range.x, me.angle_range.y)
		var solution: Vector3 = EnemyAI.choose_shot(me, rival, game.terrain, game.wind * float(game.balance.wind_accel) * float(def.projectile.get("wind_scale", 1.0)), game.balance)
		me.angle = solution.x
		game.power = solution.y
		game.state = LocalMatch.State.PLAYER_CHARGING
		var hp_before: int = rival.hp
		game.release_shot()
		var spawned: int = 0
		for i in range(1500):
			game._physics_process(1.0 / 60)
			spawned = maxi(spawned, game.projectiles.size())
			if game.state in [LocalMatch.State.PLAYER_AIMING, LocalMatch.State.MATCH_FINISHED] and game.projectiles.is_empty():
				break
		check(activated and game.state != LocalMatch.State.PROJECTILE_FLYING and (rival.hp < hp_before or def.pow.kind == "heal" or spawned > 1), "%s POW (%s) resolves" % [def.name, def.pow.name])
	# Skill 9 (POW Máx) fills the bar so the special can fire this turn.
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 3, "turn_seconds": 10, "teams": [[{"name": "A", "human": true, "level": 5}], [{"name": "B", "level": 5}]]})
	var hero: TankFighter = game.fighters[0]
	for fighter in game.fighters:
		fighter.delay = 1000.0
	hero.delay = 0.0
	game.begin_turn()
	hero.pow_gauge = 10
	check(game.balance.items.size() == 9 and game.use_item("powmax") and hero.pow_gauge == float(game.balance.pow_max) and game.activate_pow(), "skill 9 POW Máx fills the POW bar")
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("ARMORY RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
