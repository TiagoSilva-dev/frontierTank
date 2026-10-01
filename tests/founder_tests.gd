extends SceneTree

# Founder Pack — Edição Paladino do Sol (docs/FOUNDER_PACK.md). The pack is cosmetic: these
# checks keep it that way (numbers inside the range of the gold shop, no attributes, same
# explosion rules) and check the pieces that make it a Founder's: items, store, profile,
# art on disk, the explosion that never draws more area than the real one, the emote that
# only a Founder can ask for, and the effects that follow the character.

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

func opaque_span(path: String, row: int) -> int:
	var image: Image = (load(path) as Texture2D).get_image()
	var first: int = -1
	var last: int = -1
	for x in range(image.get_width()):
		if image.get_pixel(x, row).a > 0.1:
			if first < 0:
				first = x
			last = x
	return 0 if first < 0 else last - first + 1

func duel(game: LocalMatch, look: Dictionary) -> void:
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 77, "turn_seconds": 10,
		"teams": [[{"name": "Fundador", "human": true, "arma": {"id": "solaris", "quality": "normal", "level": 0}, "level": 5, "look": look}], [{"name": "Rival", "arma": {"id": "trovao", "quality": "normal", "level": 0}, "level": 5}]]})
	for fighter in game.fighters:
		fighter.delay = 1000.0
	game.fighters[0].delay = 0.0
	game.begin_turn()

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	# ---- items: cosmetic only, in the range of what the gold shop sells
	var solaris: Dictionary = Armory.weapon_def("solaris")
	check(not solaris.is_empty() and bool(solaris.get("premium", false)) and (solaris.attrs as Dictionary).is_empty(), "Solaris is a premium weapon with no attributes")
	var gold_damage: Array = []
	var gold_radius: Array = []
	var gold_pow_scale: Array = []
	for weapon: Dictionary in Armory.data().weapons:
		if not bool(weapon.get("premium", false)) and not bool(weapon.get("super", false)):
			gold_damage.append(float(weapon.damage))
			gold_radius.append(float(weapon.radius))
			gold_pow_scale.append(float(weapon.pow.get("damage_scale", 1.0)))
	check(float(solaris.damage) >= gold_damage.min() and float(solaris.damage) <= gold_damage.max(), "Solaris damage (%d) is inside the gold shop range" % int(solaris.damage))
	check(float(solaris.radius) >= gold_radius.min() and float(solaris.radius) <= gold_radius.max(), "Solaris crater (%d) is inside the gold shop range" % int(solaris.radius))
	check(float(solaris.pow.damage_scale) <= gold_pow_scale.max(), "Julgamento do Sol hits no harder than the strongest shop POW (%.1f <= %.1f)" % [float(solaris.pow.damage_scale), gold_pow_scale.max()])
	var beam: Dictionary = Armory.weapon_def("canhao_arco_iris").pow
	check(float(solaris.pow.damage_scale) < float(beam.damage_scale) and float(solaris.pow.radius_scale) < float(beam.radius_scale), "and it stays below the Raio Prismático (damage and area)")
	for id: String in FounderPack.ITEMS:
		var def: Dictionary = Armory.definition(id)
		check(not def.is_empty() and bool(def.get("premium", false)) and bool(def.get("founder", false)) and (def.get("attrs", {}) as Dictionary).is_empty(), "%s is a premium Founder item without attributes" % id)
		check(int(def.get("price", 1)) == 0, "%s is not sold for gold" % id)
	check(Armory.tier_for_level(0, "solaris") == 0 and Armory.tier_for_level(5, "solaris") == 0 and Armory.tier_for_level(6, "solaris") == 1 and Armory.tier_for_level(9, "solaris") == 1 and Armory.tier_for_level(10, "solaris") == 2 and Armory.tier_for_level(12, "solaris") == 3, "Solaris evolves at +6, +10 and +12")
	check(Armory.tier_for_level(9) == 1 and Armory.tier_for_level(12) == 3, "the other weapons keep +9, +10 and +12")
	for tier in range(4):
		check(ResourceLoader.exists("res://assets/weapons/solaris/tier%d.png" % tier), "Solaris art for form %d exists" % tier)
	# ---- the store
	var entry: Dictionary = PremiumStore.product(FounderPack.SKU)
	check(PremiumStore.valid(entry), "the Founder Pack is a valid premium product")
	check(PremiumStore.on_sale(entry, "2026-10-01") and PremiumStore.on_sale({"sale_until": "2026-12-31"}, "2026-12-31") and not PremiumStore.on_sale({"sale_until": "2026-12-31"}, "2027-01-01"), "the pack stops selling after sale_until and never before")
	for id: String in FounderPack.ITEMS:
		check(entry.items.has(id), "the pack delivers %s" % id)
	# ---- profile: the seal makes a Founder, the shop never does
	var plain: PlayerProfile = PlayerProfile.new()
	plain.save_path = "user://founder_test_plain.json"
	plain.created = true
	check(not plain.is_founder() and not plain.look().has("founder"), "a normal player is not a Founder and carries no Founder look")
	var founder: PlayerProfile = PlayerProfile.new()
	founder.save_path = "user://founder_test.json"
	founder.created = true
	for id: String in FounderPack.ITEMS:
		var item: Dictionary = founder.add_instance(id)
		if id != FounderPack.SEAL:
			founder.equip(int(item.uid))
		else:
			check(founder.equip(int(item.uid)) != "", "the seal is a collectible: it cannot be equipped")
	var seal_uid: int = -1
	for inst: Dictionary in founder.inventory:
		if str(inst.id) == FounderPack.SEAL:
			seal_uid = int(inst.uid)
	check(founder.sell(seal_uid) == 0 and founder.is_founder(), "the Founder seal can never be sold off")
	check(founder.apply_op("sell", [seal_uid], JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))).error != "", "and the sell operation says so")
	check(founder.is_founder() and founder.look().founder.seal == true, "owning the seal makes a Founder (look.founder)")
	check(FounderPack.complete(founder.look()), "skin + Solaris + Asas da Aurora count as the full set")
	check(Armory.slot_of(FounderPack.SEAL) == "selo" and not "selo" in Armory.EQUIP_SLOTS, "the seal sits in no equipment slot")
	check("founder_fx" in PlayerProfile.OPS, "the Founder effects are a profile operation")
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	check(plain.apply_op("founder_fx", ["pet", false], balance).error != "", "a normal player cannot switch Founder effects")
	# ---- the test coupon
	var tester: PlayerProfile = PlayerProfile.new()
	tester.save_path = "user://founder_test_coupon.json"
	tester.created = true
	check(tester.apply_op("redeem", ["TESTARTUDO"], balance, false).error != "" and not tester.is_founder(), "TESTARTUDO needs the test coupons switched on")
	check(tester.apply_op("redeem", ["testartudo"], balance, true).error == "" and tester.is_founder(), "TESTARTUDO makes a Founder")
	for id: String in FounderPack.ITEMS:
		check(tester.has_item(id), "TESTARTUDO gives %s" % id)
	check(tester.has_item(FounderPack.WEAPON) and int(tester.find_instance(tester.inventory.filter(func(inst: Dictionary) -> bool: return str(inst.id) == FounderPack.WEAPON)[0].uid).level) == 12, "Solaris comes at +12")
	tester.apply_op("redeem", ["TESTARTUDO"], balance, true)
	check(tester.inventory.filter(func(inst: Dictionary) -> bool: return str(inst.id) == FounderPack.SEAL).size() == 1, "redeeming again never duplicates the seal")
	var toggled: Dictionary = founder.apply_op("founder_fx", ["pet", false], balance)
	check(toggled.error == "" and founder.look().founder.pet == false and founder.look().founder.aura == true, "a Founder switches one effect off, the others stay")
	check(founder.apply_op("founder_fx", ["nada", true], balance).error != "", "an unknown effect is refused")
	var saved: PlayerProfile = PlayerProfile.new()
	saved.save_path = "user://founder_test2.json"
	saved.load_data(JSON.parse_string(JSON.stringify(founder.to_data())))
	check(saved.founder_fx.pet == false and saved.is_founder(), "the Founder choices survive a save")
	check(FounderPack.clean_fx("lixo").aura == true and FounderPack.clean_fx({"foot": false}).foot == false, "bad data falls back to all effects on")
	# ---- art on disk
	for folder: Array in [["halo", "halo_", 8], ["halo", "halo_power_", 8], ["mandala", "mandala_", 12], ["aura", "aura_", 9], ["foot", "footstep_", 6], ["projectile", "frame_", 8], ["lance", "frame_", 4], ["explosion", "frame_", 5], ["emote", "frame_", 6], ["pet/fly", "frame_", 9], ["pet/happy", "frame_", 7], ["pet/scared", "frame_", 5], ["pet/victory", "frame_", 9]]:
		check(FounderPack.frames(str(folder[0]), str(folder[1])).size() >= int(folder[2]) - (1 if str(folder[0]) == "aura" else 0), "%s has its frames" % folder[0])
	for clip: String in ["idle", "crawl", "shoot", "hit", "victory", "defeat", "pow"]:
		check(ResourceLoader.exists("res://assets/characters/roupa_paladino_sol/prone/%s/frame_00.png" % clip), "the Paladino has the %s clip" % clip)
	for path: String in ["badge/badge_16.png", "badge/badge_24.png", "badge/badge_32.png", "badge/badge_64.png", "frame/founder_frame.png", "sigil/sun_sigil.png", "feather.png", "aura/aura_thin.png", "halo/glow.png"]:
		check(FounderPack.texture(path) != null, "%s exists" % path)
	# ---- the explosion never draws more area than the real one
	var boom_dir: String = "res://assets/founder/explosion/frame_%02d.png"
	var widest: int = 0
	for i in range(5):
		var image: Image = (load(boom_dir % i) as Texture2D).get_image()
		var rect: Rect2i = image.get_used_rect()
		widest = maxi(widest, rect.size.x)
		check(rect.position.x >= 0 and rect.end.x <= int(SunBlast.CANVAS.x), "explosion frame %d fits the canvas, whose half width is the real radius" % (i + 1))
	check(widest <= int(SunBlast.CANVAS.x), "no explosion frame is wider than 2R")
	check(opaque_span(boom_dir % 2, 60) <= int(SunBlast.CANVAS.x * 0.25), "the vertical pillar is narrower than a quarter of R (%d px)" % opaque_span(boom_dir % 2, 60))
	var ground_row: int = int(SunBlast.GROUND_ROW)
	check(opaque_span(boom_dir % 1, ground_row - 4) <= int(SunBlast.CANVAS.x * 0.85), "the sun sigil on the ground is drawn at about 0.8 R")
	var blast: SunBlast = SunBlast.new()
	blast.radius = 60.0
	root.add_child(blast)
	await process_frame
	check(is_equal_approx(blast.sprite.scale.x * SunBlast.CANVAS.x, 120.0), "the explosion is scaled so its width is exactly 2R")
	blast.queue_free()
	# Julgamento do Sol: ground shapes inside R, the huge sun only in the sky.
	var impact: FounderImpact = FounderImpact.new()
	impact.radius = 52.0
	impact.top = -500.0
	root.add_child(impact)
	await process_frame
	check(impact.sigil.scale.x * FounderImpact.SIGIL_HALF_WIDTH <= impact.radius, "the sigil's ray tips stop inside the real radius")
	check(FounderImpact.BEAM_WIDTH <= 0.25, "the beam is a narrow column (%.2f R)" % FounderImpact.BEAM_WIDTH)
	var sky_bottom: float = impact.sky_sun.position.y + 192.0 * impact.sky_sun.scale.y / 2.0
	check(sky_bottom < -impact.radius, "the huge sun hangs in the sky, clear of the ground (%.0f px above, R = %.0f)" % [-sky_bottom, impact.radius])
	impact.queue_free()
	# ---- the match: same numbers as any POW of that size, emote only for Founders
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var founder_look: Dictionary = founder.look()
	duel(game, founder_look)
	var me: TankFighter = game.fighters[0]
	me.pow_gauge = 100
	game.activate_pow()
	var plan: Dictionary = game.compose_plan(me)
	check(is_equal_approx(float(plan.radius), 46.0 * 1.15), "Julgamento do Sol's area is the weapon's 46 x 1.15 (%.1f)" % float(plan.radius))
	check(int(plan.damage) == roundi(255.0 * 1.3), "and its damage is 255 x 1.3 (%d)" % int(plan.damage))
	# The anime cut-in and the charge after it: the match holds the shot for both.
	check(game.hitstop >= Armory.visual("founder_cutin") - 0.001 and Armory.visual("founder_cutin") > Armory.visual("pow_cutin"), "Julgamento do Sol holds the shot for the cut-in and the charge (%.2f s)" % game.hitstop)
	check(Armory.visual("founder_cutin") >= FounderPow.FIRE_AT and Armory.visual("founder_cutin") - FounderPow.FIRE_AT < 0.25, "and releases it right after the Solaris fires")
	check(FounderPow.CHARGE_AT > Armory.visual("founder_cutin_close") - 0.15 and Armory.visual("founder_cutin_close") + FounderCutin.OUTRO <= Armory.visual("founder_cutin") + 0.5, "the charge starts as the cut-in clears, and the whole scene stays under 3 s")
	check(FounderCutin.split_title("Julgamento do Sol") == ["JULGAMENTO", "DO SOL"] and FounderCutin.split_title("Solar") == ["SOLAR"], "the title splits in two lines after the first word")
	var cutin: FounderCutin = FounderCutin.new()
	cutin.title = "Julgamento do Sol"
	cutin.look = founder_look
	cutin.shooter_name = "Fundador"
	cutin.weapon_name = "Solaris"
	cutin.close = Armory.visual("founder_cutin_close")
	root.add_child(cutin)
	await process_frame
	check(cutin.canvas != null and cutin.title_size % 16 == 0 and cutin.lines.size() == 2 and not cutin.mandala_frames.is_empty(), "the cut-in shows the Paladino, the mandala and a title on the font's pixel grid")
	cutin._process(0.5)
	check(cutin.shown() > 0.99 and cutin.portrait_state().alpha > 0.99, "the portrait has landed by 0.5 s")
	cutin.age = cutin.close + FounderCutin.OUTRO - 0.01
	cutin._process(0.1)
	await process_frame
	check(not is_instance_valid(cutin), "the cut-in frees itself after the white-out")
	var heard: Array = []
	game.emote.connect(func(fighter: TankFighter, id: String) -> void: heard.append([fighter.player_id, id]))
	game.apply_input(0, "emote", {"id": "paladino"})
	check(heard == [[0, "paladino"]], "a Founder's emote reaches everyone")
	game.apply_input(1, "emote", {"id": "paladino"})
	game.apply_input(0, "emote", {"id": "outro"})
	check(heard.size() == 1, "a player without the seal, or an unknown emote, is ignored")
	game.queue_free()
	# ---- the effects follow the character
	var rig_game: LocalMatch = LocalMatch.new()
	root.add_child(rig_game)
	rig_game.set_physics_process(false)
	duel(rig_game, founder_look)
	var fighter: TankFighter = rig_game.fighters[0]
	await process_frame
	await process_frame
	check(fighter.rig.founder_fx != null and fighter.rig.founder_fx.halo != null, "the Paladino do Sol skin carries the Halo Solar")
	check(fighter.rig.founder_fx.aura != null and fighter.rig.founder_fx.pet == null, "a Founder has the aura, and only the pet they switched off is missing")
	check(fighter.extra_animations.has("hit") and fighter.extra_animations.has("victory") and fighter.extra_animations.has("pow"), "the Paladino has hit, victory and pow clips in battle")
	var rival: TankFighter = rig_game.fighters[1]
	check(rival.rig.founder_fx == null, "other players carry none of it")
	var fx: FounderFx = fighter.rig.founder_fx
	fighter.take_damage(5)
	check(fx.hit_blink > 0.0 and fighter.clip_hold > 0.0, "a hit blinks the halo and plays the hit clip")
	fighter.animate_attack()
	check(fx.flare > 0.9, "an attack flares the halo")
	fx.begin_pow()
	await create_timer(0.55).timeout
	check(fx.pow_amount > 0.95, "Julgamento do Sol turns the halo into the mandala")
	fx.end_pow()
	fighter.celebrate()
	check(fighter.celebrating and fx.boost_goal == 1.0 and fighter.rig.fx_state == "victory", "winning swells the halo and opens the wings")
	rig_game.queue_free()
	# Footsteps: a mark every 26 px of crawling, gone in 0.4 s.
	var steps_game: LocalMatch = LocalMatch.new()
	root.add_child(steps_game)
	steps_game.set_physics_process(false)
	var walker_look: Dictionary = founder_look.duplicate(true)
	walker_look.founder.pet = true
	walker_look.founder.foot = true
	duel(steps_game, walker_look)
	var walker: TankFighter = steps_game.fighters[0]
	await process_frame
	await process_frame
	check(walker.rig.founder_fx.pet != null, "with the pet switched on it follows in battle")
	walker.walk_time = 0.5
	walker.rig.founder_fx.update_footsteps()
	walker.position.x += FounderFx.FOOT_SPACING + 2.0
	walker.rig.founder_fx.update_footsteps()
	var marks: Array = steps_game.get_children().filter(func(node: Node) -> bool: return node is FounderFx.FootMark)
	check(marks.size() == 1, "crawling leaves a solar mark")
	check(is_equal_approx(FounderFx.FOOT_LIFE, 0.4), "and it lasts 0.4 s")
	steps_game.queue_free()
	print("founder checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
