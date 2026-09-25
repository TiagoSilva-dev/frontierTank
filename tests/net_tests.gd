extends SceneTree

# Online (backend 0.11): the battle in lockstep, the profile operations the server runs
# for the players, and the rewards. The full server + clients test is net_e2e_tests.gd.

var failures: int = 0
var checks: int = 0
const DT: float = 1.0 / 60.0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func duel_config(local: int) -> Dictionary:
	return {"mode": "pvp", "map": "ilha_celeste", "seed": 777, "turn_seconds": 10, "lockstep": true, "local": local,
		"teams": [[{"name": "Nilo", "human": true, "level": 5, "tools": ["hp", "shield", "pow"], "account": 1}], [{"name": "Lia", "human": true, "level": 5, "tools": ["hp"], "account": 2}]]}

func make_copy(config: Dictionary) -> LocalMatch:
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.start(config)
	return game

# Steps every copy with the same inputs; returns false at the first tick they differ.
func run_ticks(copies: Array, ticks: int, inputs: Dictionary, start_tick: int = 0) -> bool:
	for tick in range(start_tick, start_tick + ticks):
		for game: LocalMatch in copies:
			for entry: Array in inputs.get(tick, []):
				game.apply_input(int(entry[0]), str(entry[1]), entry[2])
			game.step(DT)
		var first: int = copies[0].checksum()
		for game: LocalMatch in copies:
			if game.checksum() != first:
				print("desync at tick %d" % tick)
				return false
	return true

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	lockstep_tests()
	pve_lockstep_tests()
	profile_op_tests()
	rewards_tests()
	print("NET RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func lockstep_tests() -> void:
	# Each player's copy has its own local fighter; the server's copy has none of its own.
	var a: LocalMatch = make_copy(duel_config(0))
	var b: LocalMatch = make_copy(duel_config(1))
	var server: LocalMatch = make_copy(duel_config(0))
	var copies: Array = [server, a, b]
	check(a.local_id == 0 and b.local_id == 1, "each copy knows its own fighter")
	check(a.checksum() == b.checksum() and a.checksum() == server.checksum(), "the same config and seed start identical battles")
	check(a.lockstep and not a.can_act() or a.active_id == 0, "lockstep copies are stepped from outside")
	# Whoever plays first: move, aim to an exact angle, charge and release at 63.25.
	var shooter: int = server.active_id
	var inputs: Dictionary = {
		10: [[shooter, "move", {"d": 1}]],
		40: [[shooter, "move", {"d": 0}]],
		45: [[shooter, "aim", {"d": 1}]],
		70: [[shooter, "aim", {"d": 0, "angle": 52.5}]],
		80: [[shooter, "item", {"id": "dmg50"}]],
		90: [[shooter, "charge", {}]],
		150: [[shooter, "release", {"power": 63.25}]],
	}
	var start_x: float = server.fighters[shooter].position.x
	check(run_ticks(copies, 160, inputs), "every copy stays identical through a turn (move, aim, item, shot)")
	check(server.fighters[shooter].position.x != start_x, "the move intent moved the fighter")
	check(is_equal_approx(server.shot_angle, 52.5), "the aim intent carries the exact angle the player saw")
	check(is_equal_approx(server.shot_power, 63.25), "the release carries the exact force the player saw")
	check(server.turn_items.has("dmg50"), "skills arrive as intents")
	check(run_ticks(copies, 900, {}, 160), "the shot resolves the same on every copy")
	# Intents of a fighter whose turn it is not are ignored everywhere.
	var other: int = 1 - server.active_id
	var before: int = server.checksum()
	for game: LocalMatch in copies:
		game.apply_input(other, "pass", {})
		game.apply_input(other, "charge", {})
	check(server.checksum() == before, "intents out of turn change nothing")
	# Leaving: the AI plays that fighter on every copy until the end.
	for game: LocalMatch in copies:
		game.apply_input(0, "leave", {})
		game.apply_input(1, "auto", {"on": true})
	check(server.fighters[0].left and server.fighters[0].auto_play and a.fighters[0].auto_play, "a player who leaves is played by the AI")
	check(a.auto_play and not b.auto_play == false, "Confiar shows on the owner's copy")
	var finished: bool = false
	for chunk in range(60):
		if not run_ticks(copies, 600, {}, 1060 + chunk * 600):
			break
		if not server.running:
			finished = true
			break
	check(finished and not a.running and not b.running, "an AI-played battle finishes on every copy")
	check(a.winner_team == server.winner_team and b.winner_team == server.winner_team, "every copy agrees on the winner")
	for game: LocalMatch in copies:
		game.queue_free()
	# The local controls send intents instead of acting when `remote` is set.
	var sent: Array = []
	var client: LocalMatch = make_copy(duel_config(0))
	client.remote = func(action: String, data: Dictionary) -> void: sent.append([action, data])
	for fighter in client.fighters:
		fighter.delay = 100.0
	client.fighters[0].delay = 0.0
	client.begin_turn()
	var angle: float = client.fighters[0].angle
	client.use_item("dmg50")
	client.charge()
	check(client.state != LocalMatch.State.PLAYER_CHARGING and client.turn_items.is_empty(), "online, the local controls do not act by themselves")
	client._process(0.5)
	client.release()
	check(sent.size() == 3 and sent[0][0] == "item" and sent[1][0] == "charge" and sent[2][0] == "release", "online, the local controls send intents")
	check(float(sent[2][1].power) > 0.0 and client.predicted_power < 0.0, "the release sends the force measured locally")
	check(client.fighters[0].angle == angle, "the angle only changes when the intent comes back")
	client.queue_free()

func pve_lockstep_tests() -> void:
	# Instance phases: two players with different local fighters must count the survived
	# turns the same way (the "survive" objective).
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var team: Array = [{"name": "Nilo", "human": true, "level": 8, "account": 1}, {"name": "Lia", "human": true, "level": 8, "account": 2}]
	var run: InstanceRun = InstanceRun.new(balance, "templo_sol", {}, 2, team)
	var config: Dictionary = run.phase_config(run.members)
	config.seed = 99
	config.lockstep = true
	var copies: Array = []
	for local in [0, 1, 0]:
		var copy: Dictionary = config.duplicate(true)
		copy.local = local
		var game: LocalMatch = make_copy(copy)
		for fighter in game.fighters:
			if fighter.human:
				game.apply_auto(fighter.player_id, true)
		copies.append(game)
	var same: bool = true
	var done: bool = false
	for chunk in range(80):
		same = run_ticks(copies, 600, {}, chunk * 600)
		if not same or not copies[0].running:
			done = not copies[0].running
			break
	check(same, "an instance phase with two players stays identical on every copy")
	check(done and copies[1].winner_team == copies[0].winner_team, "the phase ends the same for everyone")
	check(copies[0].survived == copies[1].survived, "turns survived do not depend on whose copy it is")
	for game: LocalMatch in copies:
		game.queue_free()

func profile_op_tests() -> void:
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var profile: PlayerProfile = PlayerProfile.new()
	profile.remote = true
	var saves: Array = [0]
	profile.on_save = func() -> void: saves[0] += 1
	check(profile.apply_op("create", ["Ex", "f"], balance).error == "", "creating the character")
	check(profile.created and profile.player_name == "Ex" and profile.gender == "f", "the name and gender are kept")
	check(profile.apply_op("create", ["Outro", "m"], balance).error != "", "the character is created only once")
	var fresh: PlayerProfile = PlayerProfile.new()
	for bad: Variant in ["A", "nome_grande_demais", "<b>x</b>", "a\nb", 42, null]:
		check(fresh.apply_op("create", [bad, "m"], balance).error != "", "invalid names are refused: %s" % str(bad))
	check(fresh.apply_op("create", ["João Ñ", "m"], balance).error == "", "accented names are accepted")
	check(saves[0] >= 1, "changes are saved through the server's callback")
	profile.coins = 1000
	var coins: int = profile.coins
	check(profile.apply_op("buy", ["quebra_tijolos", "verdadeira"], balance).error != "", "True weapons are not sold")
	check(profile.apply_op("buy", ["cabeca_de_boi", "super"], balance).error != "", "Super weapons are not sold")
	check(profile.apply_op("buy", ["quebra_tijolos", "lendaria"], balance).error != "", "unknown qualities are refused")
	check(profile.apply_op("buy", ["nao_existe", "normal"], balance).error != "", "unknown items are refused")
	check(profile.coins == coins, "refused purchases cost nothing")
	check(profile.apply_op("buy", ["fogo_intenso", "normal"], balance).error == "", "buying a weapon")
	check(profile.coins == coins - 400 and profile.has_item("fogo_intenso"), "the price is charged")
	check(profile.apply_op("buy_stone", ["pedra_fortalecimento", 1000], balance).error != "", "absurd amounts are refused")
	check(profile.apply_op("buy_stone", ["pedra_fortalecimento", -5], balance).error != "", "negative amounts are refused")
	var uid: int = -1
	for inst: Dictionary in profile.inventory:
		if inst.id == "fogo_intenso":
			uid = int(inst.uid)
	check(profile.apply_op("toggle_equip", [uid], balance).error == "" and profile.equipped_instance("arma").id == "fogo_intenso", "equipping through an operation")
	check(profile.apply_op("toggle_equip", [uid], balance).error != "", "the weapon cannot be taken off")
	check(profile.apply_op("sell", [uid], balance).error != "", "equipped items are not sold")
	check(profile.apply_op("toggle_equip", ["x"], balance).error != "" and profile.apply_op("sell", [{}], balance).error != "", "wrong argument types are refused")
	check(profile.apply_op("buy_tool", ["hp"], balance).error == "" and profile.tools.has("hp"), "buying a room tool")
	check(profile.apply_op("sell_tool", [profile.tools.find("hp")], balance).error == "" and not profile.tools.has("hp"), "giving a tool back")
	check(profile.apply_op("sell_tool", [7], balance).error != "", "empty tool slots cannot be sold")
	check(profile.apply_op("redeem", ["TESTARTUDO"], balance, false).error != "" and profile.coins < 90000, "the test coupons are off on the online server")
	check(profile.apply_op("redeem", ["PEDRAS"], balance, true).error == "", "test coupons work when allowed")
	check(profile.apply_op("redeem", ["PEDRAS"], balance, true).error != "", "a coupon is used once")
	check(profile.apply_op("hack", [], balance).error != "", "unknown operations are refused")
	# The saved data round-trips (the server keeps it in PostgreSQL as JSON).
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(profile.to_data())))
	check(copy.to_data().hash() == profile.to_data().hash() or JSON.stringify(copy.to_data()) == JSON.stringify(profile.to_data()), "the profile round-trips through JSON")

func rewards_tests() -> void:
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var cards: Array = Rewards.pvp_cards(balance, rng)
	check(cards.size() == 8, "a PvP battle deals 8 cards")
	check(Rewards.picks({"won": true}) == 2 and Rewards.picks({"won": false}) == 1, "winners pick 2 cards, losers 1")
	check(Rewards.picks({"loot": {"picks": 4}}) == 4, "the boss chest decides the picks")
	var profile: PlayerProfile = PlayerProfile.new()
	profile.remote = true
	var coins: int = profile.coins
	Rewards.grant(profile, {"coins": 50})
	check(profile.coins == coins + 50, "a coin card pays")
	Rewards.grant(profile, {"currency": "brasa", "amount": 2})
	check(profile.currency_count("brasa") == 2, "a currency card pays")
