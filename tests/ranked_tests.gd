extends SceneTree

# Ranked ladder (0.22): divisions, rating, seasons, titles, the profile operations and the
# forfeit rules of a ranked match. The queue, the match and the ladder over the network are
# in net_e2e_tests.gd.

var checks: int = 0
var failures: int = 0

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
	PlayerProfile.path_override = "user://ranked_test_profile.json"
	division_checks()
	rating_checks()
	season_checks()
	title_checks()
	profile_checks()
	forfeit_checks()
	await screen_checks()
	print("RANKED RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func division_checks() -> void:
	check(Ranked.label(1000) == "Prata III" and Ranked.label(1049) == "Prata III" and Ranked.label(1050) == "Prata II" and Ranked.label(1100) == "Prata I", "a division has three tiers, III the lowest")
	check(Ranked.label(700) == "Bronze III" and Ranked.label(999) == "Bronze I" and Ranked.label(0) == "Bronze III", "Bronze runs from the floor to 999")
	check(Ranked.label(1150) == "Ouro III" and Ranked.label(1300) == "Platina III" and Ranked.label(1450) == "Diamante III", "each division starts where the data says")
	check(Ranked.label(1600) == "Mestre" and Ranked.label(2400) == "Mestre", "Mestre has no tiers")
	var info: Dictionary = Ranked.division(1075)
	check(info.id == "prata" and info.tier == 2 and info.from == 1050 and info.next == 1100, "the tier knows where it starts and where the next one begins")
	check(Ranked.division(1149).next == 1150 and Ranked.division(1800).next == -1, "the last tier of a division leads to the next one, the top leads nowhere")
	var placed: Dictionary = Ranked.empty_rating()
	check(not Ranked.placed(placed) and Ranked.rating_label(placed) == "Em avaliação (0/5)", "a new rating is still in placement")
	placed.games = 5
	check(Ranked.placed(placed) and Ranked.rating_label(placed) == "Prata III", "after the placement games the division shows")
	var starts: Array = Ranked.data().divisions.map(func(entry: Dictionary) -> int: return int(entry.from))
	var sorted: Array = starts.duplicate()
	sorted.sort()
	check(starts == sorted and int(Ranked.data().start) >= int(starts[0]) and int(Ranked.data().floor) <= int(starts[0]), "the divisions are in order and cover the start rating")

func rating_checks() -> void:
	check(absf(Ranked.expected(1000, 1000) - 0.5) < 0.0001 and Ranked.expected(1400, 1000) > 0.9 and Ranked.expected(1000, 1400) < 0.1, "the expected score follows the rating gap")
	var fresh: Dictionary = Ranked.empty_rating()
	check(Ranked.delta(fresh, 1000, 1.0) == 24 and Ranked.delta(fresh, 1000, 0.0) == -24, "a new player moves 24 points on an even match")
	fresh.career = 10
	check(Ranked.delta(fresh, 1000, 1.0) == 16 and Ranked.delta(fresh, 1000, 0.0) == -16 and Ranked.delta(fresh, 1000, 0.5) == 0, "a veteran moves 16, a draw nothing")
	check(Ranked.delta(fresh, 1400, 1.0) > 25 and Ranked.delta(fresh, 600, 1.0) >= 1, "beating a stronger player pays more, beating a weaker one still pays")
	var rating: Dictionary = Ranked.empty_rating()
	var win: Dictionary = Ranked.apply_result(rating, 1000, 1.0)
	check(rating.mmr == 1024 and win.delta == 24 and win.before == 1000 and win.after == 1024 and rating.games == 1 and rating.wins == 1 and rating.career == 1 and rating.streak == 1 and rating.peak == 1024, "a win updates the rating and the record")
	var loss: Dictionary = Ranked.apply_result(rating, 1000, 0.0)
	check(loss.delta < 0 and rating.losses == 1 and rating.streak == -1 and rating.peak == 1024 and rating.games == 2, "a loss lowers the rating, keeps the peak and flips the streak")
	for i in range(3):
		Ranked.apply_result(rating, 1000, 1.0)
	check(Ranked.placed(rating) or rating.games == 5, "five games end the placement")
	var report: Dictionary = Ranked.apply_result(rating, 1000, 1.0)
	check(report.placed and not report.placing and int(report.games) == 6, "the report says the placement is over")
	var low: Dictionary = Ranked.empty_rating()
	low.mmr = int(Ranked.data().floor)
	Ranked.apply_result(low, 1000, 0.0)
	check(low.mmr == int(Ranked.data().floor), "the rating never drops below the floor")
	var promoted: Dictionary = Ranked.empty_rating()
	promoted.mmr = 1049
	promoted.career = 20
	var up: Dictionary = Ranked.apply_result(promoted, 1049, 1.0)
	check(up.up and Ranked.label(promoted.mmr) == "Prata II", "crossing a tier boundary is a promotion")
	var demoted: Dictionary = Ranked.empty_rating()
	demoted.mmr = 1050
	demoted.career = 20
	var down: Dictionary = Ranked.apply_result(demoted, 1050, 0.0)
	check(not down.up and Ranked.label(demoted.mmr) == "Prata III", "and falling back is not")
	var garbage: Dictionary = Ranked.clean_rating({"season": -3, "mmr": "x", "games": -4, "wins": 7, "peak": 3, "log": [{"season": 1, "division": "nope"}, 5, {"season": 2, "division": "ouro", "mmr": 1200, "games": 8}]})
	check(garbage.season >= 1 and garbage.mmr == int(Ranked.data().start) and garbage.games == 0 and garbage.peak == garbage.mmr and garbage.log.size() == 1 and garbage.log[0].division == "ouro", "a damaged rating is cleaned")
	check(Ranked.clean_rating("junk").mmr == int(Ranked.data().start), "a non-dictionary becomes a fresh rating")

func season_checks() -> void:
	var epoch: int = int(Time.get_unix_time_from_datetime_string(str(Ranked.data().season.epoch)))
	var days: int = Ranked.season_days()
	check(Ranked.season_of(epoch) == 1 and Ranked.season_of(epoch - 86400 * 40) == 1, "the first season starts at the epoch and nothing comes before it")
	check(Ranked.season_of(epoch + 86400 * days - 1) == 1 and Ranked.season_of(epoch + 86400 * days) == 2 and Ranked.season_of(epoch + 86400 * days * 3) == 4, "a new season starts every %d days" % days)
	check(Ranked.season_end(1) == epoch + 86400 * days and Ranked.seconds_left(epoch + 86400 * days - 90) == 90, "the clock counts the seconds to the end of the season")
	# Archiving and the soft reset.
	var rating: Dictionary = Ranked.empty_rating(1)
	rating.mmr = 1300
	rating.games = 12
	rating.wins = 9
	rating.losses = 3
	rating.peak = 1340
	check(not Ranked.sync(rating, epoch + 86400), "inside the season nothing changes")
	check(Ranked.sync(rating, epoch + 86400 * days + 5) and rating.season == 2, "the next season moves the rating on")
	check(rating.log.size() == 1 and rating.log[0].season == 1 and rating.log[0].division == "platina" and not rating.log[0].claimed and rating.log[0].games == 12, "the season that ended is archived with its division")
	check(rating.mmr == 1150 and rating.games == 0 and rating.wins == 0 and rating.losses == 0 and rating.peak == 1150, "the rating is pulled halfway to the anchor and the record starts over")
	check(not Ranked.sync(rating, epoch + 86400 * days + 9) and rating.log.size() == 1, "syncing again changes nothing")
	var idle: Dictionary = Ranked.empty_rating(1)
	idle.games = 3
	Ranked.sync(idle, epoch + 86400 * days)
	check(idle.log.is_empty(), "too few games earn no title")
	var away: Dictionary = Ranked.empty_rating(1)
	away.mmr = 1700
	away.games = 20
	Ranked.sync(away, epoch + 86400 * days * 4)
	check(away.season == 5 and away.log.size() == 1 and away.log[0].division == "mestre" and away.mmr == 1350, "a long absence archives once and resets once")
	var full: Dictionary = Ranked.empty_rating(1)
	for season in range(1, 20):
		full.season = season
		full.games = 6
		Ranked.sync(full, epoch + 86400 * days * season)
	check(full.log.size() == int(Ranked.data().season.log), "the log keeps the last seasons only")
	check(Ranked.pending(full).size() == full.log.size(), "every unclaimed season waits for its title")

func title_checks() -> void:
	check(Ranked.title_id(3, "ouro") == "s3_ouro" and Ranked.title_text("s3_ouro") == "Ouro · Temporada 3", "a season title has a readable name")
	check(Ranked.valid_title("s12_mestre") and not Ranked.valid_title("s3_cobre") and not Ranked.valid_title("x3_ouro") and not Ranked.valid_title("s_ouro") and not Ranked.valid_title(""), "unknown titles are refused")
	Lang.override = "en"
	Lang.setup()
	check(Ranked.title_text("s1_prata") == "Silver · Season 1" and Ranked.label(1150) == "Gold III", "titles and divisions speak English too")
	Lang.override = "pt_BR"
	Lang.setup()

func profile_checks() -> void:
	var epoch: int = int(Time.get_unix_time_from_datetime_string(str(Ranked.data().season.epoch)))
	var profile: PlayerProfile = PlayerProfile.new()
	check(profile.rating.mmr == int(Ranked.data().start) and profile.titles.is_empty() and profile.title == "", "a new profile starts unrated without titles")
	check(profile.apply_op("title_set", ["s1_ouro"], {}).error != "", "a title that is not owned cannot be equipped")
	check(profile.apply_op("season_claim", [1], {}).error != "", "there is nothing to claim yet")
	check(profile.apply_op("season_claim", ["x"], {}).error != "" and profile.apply_op("season_claim", [], {}).error != "", "a claim with the wrong arguments is refused")
	# A finished season waits to be claimed.
	profile.rating = Ranked.empty_rating(1)
	profile.rating.mmr = 1210
	profile.rating.games = 8
	check(profile.sync_rating(epoch + 86400 * Ranked.season_days() + 5) and Ranked.pending(profile.rating).size() == 1, "syncing archives the last season")
	var season: int = int(profile.rating.log[0].season)
	var claim: Dictionary = profile.apply_op("season_claim", [season], {})
	check(claim.error == "" and profile.titles == [Ranked.title_id(season, "ouro")] and profile.title == Ranked.title_id(season, "ouro") and str(claim.message).contains("Ouro"), "claiming gives the title and equips the first one")
	check(profile.apply_op("season_claim", [season], {}).error != "" and profile.titles.size() == 1 and Ranked.pending(profile.rating).is_empty(), "a season is claimed once")
	check(profile.apply_op("title_set", [""], {}).error == "" and profile.title == "" and profile.apply_op("title_set", [profile.titles[0]], {}).error == "" and profile.title == profile.titles[0], "titles go on and off")
	# The save keeps it all (v10) and the entry carries the title.
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(int(profile.to_data().version) == 11 and copy.rating == profile.rating and copy.titles == profile.titles and copy.title == profile.title, "the rating and titles survive the save")
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	check(str(profile.entry(balance).title) == profile.title, "the battle entry carries the title")
	var old: Dictionary = profile.to_data()
	old.erase("rating")
	old.erase("titles")
	old.erase("title")
	old.version = 9
	var from_nine: PlayerProfile = PlayerProfile.new()
	from_nine.load_data(old)
	check(from_nine.rating.mmr == int(Ranked.data().start) and from_nine.titles.is_empty(), "a v9 save loads unrated")
	old.titles = ["s1_ouro", "s1_ouro", "junk"]
	old.title = "s9_ouro"
	var strict: PlayerProfile = PlayerProfile.new()
	strict.load_data(old)
	check(strict.titles == ["s1_ouro"] and strict.title == "", "bad titles are dropped and the equipped one must be owned")
	check(Ranked.public(profile.rating).keys().size() == 7 and not Ranked.public(profile.rating).has("log"), "others see the rating but not the log")
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var me: Dictionary = profile.entry(balance)
	game.start({"mode": "pvp", "map": "ilha_celeste", "seed": 3, "turn_seconds": 10, "teams": [[me], [{"name": "Rival", "level": 3}]]})
	check(game.fighters[0].rank_title == Ranked.title_text(profile.title), "the nameplate shows the title instead of the military rank")
	check(game.fighters[1].rank_title == TankFighter.rank_for(3), "others keep their rank")
	game.queue_free()
	check(epoch > 0, "the epoch parses")

func ranked_match(turn_seconds: int = 2) -> LocalMatch:
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start({"mode": "pvp", "ranked": true, "map": "ilha_celeste", "seed": 11, "turn_seconds": turn_seconds, "teams": [[{"name": "Alfa", "human": true, "level": 5}], [{"name": "Beta", "human": true, "level": 5}]]})
	return game

func forfeit_checks() -> void:
	# Leaving a ranked match loses it at once; in a normal match the AI takes over.
	var game: LocalMatch = ranked_match()
	check(game.ranked and game.running, "the config marks the match as ranked")
	game.apply_input(1, "leave", {})
	check(game.state == LocalMatch.State.MATCH_FINISHED and game.winner_team == 0 and game.fighters[1].hp <= 0, "leaving a ranked match gives the win to the opponent")
	game.queue_free()
	var casual: LocalMatch = LocalMatch.new()
	root.add_child(casual)
	casual.set_physics_process(false)
	casual.start({"mode": "pvp", "map": "ilha_celeste", "seed": 11, "turn_seconds": 2, "teams": [[{"name": "Alfa", "human": true, "level": 5}], [{"name": "Beta", "human": true, "level": 5}]]})
	casual.apply_input(1, "leave", {})
	check(casual.running and casual.fighters[1].left and casual.fighters[1].hp > 0, "in a normal match the AI plays on for who left")
	casual.queue_free()
	# Three turns in a row lost to the clock forfeit.
	var idle: LocalMatch = ranked_match(2)
	var frames: int = 0
	while idle.running and frames < 4000:
		idle.step(1.0 / 60.0)
		frames += 1
	var loser: TankFighter = idle.fighters[0] if idle.fighters[0].hp <= 0 else idle.fighters[1]
	check(not idle.running and loser.timeouts >= 3 and idle.winner_team != loser.team, "three timeouts in a row lose a ranked match (%d frames)" % frames)
	idle.queue_free()
	var passer: LocalMatch = ranked_match(2)
	var first: TankFighter = passer.active()
	first.timeouts = 2
	passer.apply_pass()
	check(first.timeouts == 0, "passing a turn on purpose clears the timeouts")
	passer.queue_free()
	var shooter: LocalMatch = ranked_match(10)
	var shot_by: TankFighter = shooter.active()
	shot_by.timeouts = 2
	shooter.state = LocalMatch.State.PLAYER_CHARGING
	shooter.power = 40.0
	shooter.release_shot()
	check(shot_by.timeouts == 0, "firing clears the timeouts")
	shooter.queue_free()

func screen_checks() -> void:
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var badge: RankBadge = RankBadge.new()
	badge.size = Vector2(60, 60)
	root.add_child(badge)
	for mmr: int in [700, 1000, 1150, 1300, 1450, 1700]:
		badge.mmr = mmr
		badge.queue_redraw()
		await process_frame
	badge.placed = false
	badge.queue_redraw()
	await process_frame
	check(is_instance_valid(badge), "the emblem draws every division and the placement shield")
	badge.queue_free()
	app.queue_free()
	await process_frame
