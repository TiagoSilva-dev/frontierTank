extends SceneTree

# Simulated players (docs/BOTS.md): believable nicknames, a skill that follows the level, and an
# AI that aims better the higher its skill, in lockstep (the same entry plays the same battle
# on every copy). The server's side (the Salão, rooms, rivals) is in population_tests.gd.

var errors: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		errors += 1
		push_error(message)

# A 1v1 between two AIs of the given skills (-1: the old flat AI) played to the end; the winner.
func duel(seed_value: int, skill_a: float, skill_b: float, map: String) -> int:
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var winner: Array = [-2]
	game.finished.connect(func(who: int) -> void: winner[0] = who)
	var a: Dictionary = {"name": "A", "weapon": 0, "level": 10}
	var b: Dictionary = {"name": "B", "weapon": 0, "level": 10}
	if skill_a >= 0.0:
		a.skill = skill_a
	if skill_b >= 0.0:
		b.skill = skill_b
	game.start({"mode": "pvp", "map": map, "seed": seed_value, "turn_seconds": 10, "teams": [[a], [b]]})
	var ticks: int = 0
	while winner[0] == -2 and ticks < 60 * 60 * 12:
		game.step(1.0 / 60.0)
		ticks += 1
	game.queue_free()
	return int(winner[0])

# The battle's state after `ticks` steps, as text (checksums of the same config must agree).
func play(config: Dictionary, ticks: int) -> String:
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start(JSON.parse_string(JSON.stringify(config)))
	for i in range(ticks):
		game.step(1.0 / 60.0)
	var text: String = game.checksum_text()
	game.queue_free()
	return text

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	# --- Nicknames: a player's rule, nothing that reads as a program, nothing the chat hides.
	var taken: Dictionary = {}
	var odd: Array[String] = []
	var banned: Array[String] = []
	for i in range(600):
		var nick: String = BotRoster.make_name(rng, "f" if i % 2 == 0 else "m", taken)
		if not PlayerProfile.valid_name(nick) or nick.length() < 3 or BotRoster.looks_like_bot(nick):
			odd.append(nick)
		for word: String in GameServer.BLOCKED_WORDS:
			if nick.to_lower().contains(word):
				banned.append(nick)
		taken[nick.to_lower()] = true
	check(odd.is_empty(), "600 nicknames pass the player's rule and none reads as a program %s" % str(odd.slice(0, 5)))
	check(banned.is_empty(), "no nickname holds a word the chat hides %s" % str(banned.slice(0, 5)))
	check(taken.size() == 600, "the nicknames of one list are all different (%d of 600)" % taken.size())
	var loose: Dictionary = {}
	for i in range(400):
		loose[BotRoster.make_name(rng, "m").to_lower()] = true
	check(loose.size() > 330, "nicknames vary even with no list to avoid (%d different in 400)" % loose.size())
	check(BotRoster.looks_like_bot("Bot_77") and BotRoster.looks_like_bot("LoBot") and BotRoster.looks_like_bot("CPU1") and BotRoster.looks_like_bot("pedro_ia") and not BotRoster.looks_like_bot("Pedro") and not BotRoster.looks_like_bot("Mariana_SP"), "what reads as a program is caught")
	var fenix: String = BotRoster.make_name(rng, "m", {"fênix": true})
	check(fenix.to_lower() != "fênix", "a name already taken is not made again")
	# A crowded pool still ends in a free name.
	var crowded: Dictionary = {}
	for first: String in BotRoster.pool("male"):
		crowded[first.to_lower()] = true
	var after: String = BotRoster.make_name(rng, "m", crowded)
	check(not crowded.has(after.to_lower()) and BotRoster.acceptable(after), "a crowded list still gets a free name")
	# --- Skill and level
	var low_sum: float = 0.0
	var high_sum: float = 0.0
	var in_range: bool = true
	var levels: Array[int] = []
	for i in range(300):
		var weak: float = BotRoster.skill_for(rng, 2)
		var strong: float = BotRoster.skill_for(rng, 38)
		low_sum += weak
		high_sum += strong
		in_range = in_range and weak >= 0.05 and strong <= 0.97
		levels.append(BotRoster.level_for(rng))
	check(in_range and low_sum / 300.0 < 0.3 and high_sum / 300.0 > 0.7, "skill grows with the level (%.2f at level 2, %.2f at 38)" % [low_sum / 300.0, high_sum / 300.0])
	levels.sort()
	check(levels[0] >= 1 and levels[-1] <= 40 and levels[150] <= 16, "a new server's players are mostly beginners (median level %d)" % levels[150])
	# --- The directory: every simulated player is complete, named like a person, listed once
	var lobby: LobbyDirectory = LobbyDirectory.new()
	lobby.rng.seed = 11
	lobby.population = 50
	lobby.server_levels = true
	lobby.populate()
	var names: Dictionary = {}
	var complete: bool = true
	for bot: Dictionary in lobby.bots:
		names[str(bot.name).to_lower()] = true
		complete = complete and bot.has("skill") and float(bot.skill) >= 0.0 and float(bot.skill) <= 1.0 and bot.has("arma") and bot.has("look") and not bool(bot.human) and not BotRoster.looks_like_bot(str(bot.name))
	check(lobby.bots.size() == 50 and names.size() == 50 and complete, "the directory makes 50 different players, each with a skill, gear and a look")
	var rooms_ok: bool = lobby.rooms.size() == 14
	for room: Dictionary in lobby.rooms:
		for member: Dictionary in room.members:
			rooms_ok = rooms_ok and member.has("skill") and not BotRoster.looks_like_bot(str(member.name))
	check(rooms_ok, "the rooms are filled with the same kind of player")
	for i in range(40):
		lobby.rotate_bot()
	var after_names: Dictionary = {}
	for bot: Dictionary in lobby.bots:
		after_names[str(bot.name).to_lower()] = true
	check(lobby.bots.size() == 50 and after_names.size() == 50, "players come and go and the list keeps its size and its different names")
	var nearby: Dictionary = lobby.bot_near(1)
	check(not nearby.is_empty() and absi(int(nearby.level) - 1) <= 12 and not BotRoster.looks_like_bot(str(nearby.name)), "a rival of a beginner's level is found, named like a person")
	var far: Dictionary = lobby.bot_near(40, [])
	check(not far.is_empty() and far.has("skill"), "a rival of a veteran's level is found too")
	lobby.free()
	# --- The AI: a fighter takes its skill from the entry; without one it plays as before
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 5, "turn_seconds": 10, "teams": [[{"name": "A", "weapon": 0, "level": 5, "skill": 0.8}], [{"name": "B", "weapon": 0, "level": 5}]]})
	check(is_equal_approx(game.fighters[0].skill, 0.8) and game.fighters[1].skill < 0.0, "a fighter's skill comes from its entry (-1 plays the old way)")
	var novice_think: Vector2 = Vector2.ZERO
	var expert_think: Vector2 = Vector2.ZERO
	game.fighters[0].skill = 0.0
	novice_think = game.bot_skill_range(game.fighters[0], "think")
	game.fighters[0].skill = 1.0
	expert_think = game.bot_skill_range(game.fighters[0], "think")
	check(expert_think.x < novice_think.x and expert_think.y < novice_think.y, "an expert thinks faster than a novice")
	check(game.bot_skill(game.fighters[0], "wind_misread") < 0.05 and game.bot_skill(game.fighters[0], "blunder") < 0.05, "an expert reads the wind and picks the prey")
	game.queue_free()
	# Skill matters: the expert wins most duels against a novice, on both sides of the map.
	var wins: int = 0
	var played: int = 0
	var maps: Array[String] = ["ilha_celeste", "patio_templo", "camara_guardiao", "trono_mascaras"]
	for i in range(8):
		for swapped: bool in [false, true]:
			var winner: int = duel(1000 + i, 0.9 if not swapped else 0.1, 0.1 if not swapped else 0.9, maps[i % 4])
			played += 1
			if winner == (1 if swapped else 0):
				wins += 1
	check(wins >= int(played * 0.7), "a skill 0.9 bot beats a skill 0.1 bot in most duels (%d of %d)" % [wins, played])
	var flat: int = duel(77, -1.0, -1.0, "ilha_celeste")
	check(flat == 0 or flat == 1, "the old flat AI still plays a battle to the end")
	# Lockstep: the same entries and seed give the same battle, whoever runs it.
	var config: Dictionary = {"mode": "pvp", "map": "patio_templo", "seed": 424242, "turn_seconds": 10, "lockstep": true, "teams": [[{"name": "A", "weapon": 2, "level": 12, "skill": 0.35}, {"name": "B", "weapon": 4, "level": 12, "skill": 0.9}], [{"name": "C", "weapon": 1, "level": 12, "skill": 0.6}, {"name": "D", "weapon": 6, "level": 12, "skill": 0.05}]]}
	var first: String = play(config, 2400)
	var second: String = play(config, 2400)
	check(first == second and first.length() > 20, "two copies of a battle of simulated players stay identical")
	var other: Dictionary = config.duplicate(true)
	other.teams[1][1].skill = 0.95
	check(play(other, 2400) != first, "a different skill plays a different battle")
	print("BOT RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)
