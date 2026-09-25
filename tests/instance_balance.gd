extends SceneTree

# Balance report (not a pass/fail test): plays whole instances with the AI on both
# sides, the hero using the +50/+40/+30% skills every turn like a real player, and
# prints wins, phases cleared and rounds per run for two heroes and map levels 0/5/10.
# Takes several minutes: godot --headless --path . --script tests/instance_balance.gd
func _initialize() -> void:
	call_deferred("go")

func go() -> void:
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	# Players use the damage skills almost every turn: +50%, +40%, +30% (195 energy).
	game.turn_started.connect(func(fighter: TankFighter) -> void:
		if fighter.human:
			for id: String in ["dmg50", "dmg40", "dmg30"]:
				game.apply_item(fighter, id))
	var heroes: Array = [
		{"label": "nv6 Normal", "entry": {"name": "Nilo", "human": true, "level": 6, "arma": {"id": "quebra_tijolos", "quality": "normal", "level": 0}}},
		{"label": "nv15 Exc+6", "entry": {"name": "Nilo", "human": true, "level": 15, "arma": {"id": "trovao", "quality": "excelente", "level": 6}, "attrs": {"ataque": 90, "defesa": 120, "agilidade": 40, "sorte": 60}}},
	]
	for hero: Dictionary in heroes:
		for instance: Dictionary in balance.instances:
			for level: int in [0, 5, 10]:
				var wins: int = 0
				var phases_total: int = 0
				var rounds_total: int = 0
				var trials: int = 4
				for t in range(trials):
					var item: Dictionary = {} if level == 0 else {"uid": 1, "instance": instance.id, "level": level, "quality": "normal", "mods": []}
					var run: InstanceRun = InstanceRun.new(balance, str(instance.id), item, 1, [hero.entry], null)
					var alive: bool = true
					while alive:
						var config: Dictionary = run.phase_config(run.members)
						config.seed = 1000 + t * 17 + run.phase_index
						game.start(config)
						game.set_auto_play(true)
						var frames: int = 0
						while game.running and frames < 60 * 900:
							game._physics_process(1.0 / 60)
							frames += 1
						rounds_total += game.round_number
						if game.winner_team != 0:
							alive = false
							break
						phases_total += 1
						if not run.has_next_phase():
							wins += 1
							break
						run.complete_phase(game)
				print("%-11s %-24s L%-2d wins %d/%d  phases %.1f  rounds/run %.0f" % [hero.label, instance.name, level, wins, trials, float(phases_total) / trials, float(rounds_total) / trials])
	quit()
