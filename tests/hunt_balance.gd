extends SceneTree

# Balance probe for the Caçada dos Mascotes: win rate and hourly income of typical teams
# in every zone and tier. Run: godot --headless --path . --script tests/hunt_balance.gd

func _initialize() -> void:
	call_deferred("run")

func team(level: int, stars: int, species: Array) -> Array:
	var units: Array = []
	for id: String in species:
		units.append(PetHunt.make_unit(id, level, stars))
	return units

func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	var teams: Dictionary = {
		"3x comum lv10": team(10, 0, ["escaravelho_solar", "pinguim_cristal", "brasinha"]),
		"3x raro lv10": team(10, 0, ["chacal_ambar", "coelho_neve", "diabrete_mascarado"]),
		"5x epico lv14 1*": team(14, 1, ["leao_dourado", "raposa_glacial", "grifinho", "cao_de_lava", "urso_berserker"]),
		"5x epico lv22 3*": team(22, 3, ["leao_dourado", "raposa_glacial", "grifinho", "cao_de_lava", "urso_berserker"]),
		"5x lend lv30 5*": team(30, 5, ["fenix_dourada", "lobo_boreal", "dragao_tempestade", "rei_mascara", "lobo_fenrir"]),
	}
	for label: String in teams:
		print("== ", label)
		for tier in range(1, 9):
			var line: String = "  tier %d (wild lv %d):" % [tier, PetHunt.wild_level(tier)]
			for zone: String in ["sol", "gelo", "viking"]:
				var a: Dictionary = PetHunt.analyse(teams[label], zone, tier)
				line += "  %s win %3d%% xp/h %5d coins/h %5d eggs/h %.2f |" % [zone, roundi(a.win * 100.0), a.xp, a.coins, a.eggs]
			print(line)
	# Boss: how often is it won?
	for label: String in teams:
		for tier in [1, 3, 5, 7]:
			var state: Dictionary = {"zone": "sol", "tier": tier, "seed": 99}
			var won: int = 0
			for i in range(40):
				var wilds: Array = PetHunt.roll_group("sol", tier, PetHunt.slot_rng(state, i), true)
				if PetHunt.fight(teams[label], wilds, PetHunt.slot_rng(state, i + 1000)).won:
					won += 1
			print("boss tier %d vs %s: %d/40" % [tier, label, won])
	# Timing of the simulation.
	var started: int = Time.get_ticks_msec()
	var state2: Dictionary = {"zone": "sol", "tier": 3, "seed": 5, "legend": 0}
	PetHunt.run(state2, teams["5x epico lv14 1*"], 0, 2400, 0)
	print("2400 encounters took %d ms" % (Time.get_ticks_msec() - started))
	quit()
