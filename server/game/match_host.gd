class_name MatchHost
extends Node

# One battle on the game server, in lockstep (see LocalMatch). Every tick the host applies
# the players' intents received since the last tick, steps its own copy of the battle
# (the authority for rewards), and every SEND_EVERY ticks sends the stamped intents to
# everyone; each player's copy applies them at the same ticks. An instance plays its
# phases one after the other in the same host.

const DT: float = 1.0 / 60.0
const SEND_EVERY: int = 2
const SUM_EVERY: int = 60
# "FASE CONCLUÍDA" (1.6 s) plus the transition screen (8 s) on the players' side.
const PHASE_PAUSE: float = 10.0
const ACTIONS: Array[String] = ["move", "aim", "charge", "release", "item", "tool", "pow", "fly", "aux", "pass", "flip", "auto"]
# Pending intents per player; more than this in one tick is flooding.
const MAX_PENDING: int = 12

var server: GameServer
var match_id: int = 0
var room: ServerRoom
var balance: Dictionary
var mode: String = "pvp"
var game: LocalMatch
var config: Dictionary = {}
var tick: int = 0
var pending: Array = []
var outbox: Array = []
var sums: Array = []
# Every intent of the current phase, for a player who comes back mid-battle.
var history: Array = []
# account -> fighter id, and account -> PlayerSession (also the ones who dropped).
var seats: Dictionary = {}
var players: Dictionary = {}
var gone: Dictionary = {}
var expedition: Expedition
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var over: bool = false
var phase_timer: float = -1.0
var next_config: Dictionary = {}
var started_at: float = 0.0

func _ready() -> void:
	rng.randomize()

# `teams`: the entries of both sides (players carry "account"); `sessions`: account ->
# PlayerSession of the players in the battle.
func begin(p_server: GameServer, p_room: ServerRoom, sessions: Dictionary, first_config: Dictionary, p_expedition: Expedition = null) -> void:
	server = p_server
	room = p_room
	balance = server.balance
	players = sessions
	expedition = p_expedition
	mode = str(first_config.get("mode", "pvp"))
	started_at = Time.get_unix_time_from_system()
	for session: PlayerSession in players.values():
		session.host = self
	start_phase(first_config)

func start_phase(phase_config: Dictionary) -> void:
	if is_instance_valid(game):
		game.queue_free()
	var prepared: Dictionary = phase_config.duplicate(true)
	prepared.seed = rng.randi()
	prepared.lockstep = true
	# Everyone (this copy included) starts from the same JSON, so numbers are the same
	# type and value on every machine.
	config = JSON.parse_string(JSON.stringify(prepared))
	tick = 0
	pending.clear()
	outbox.clear()
	sums.clear()
	history.clear()
	seats.clear()
	var teams: Array = config.teams
	for team_index in range(teams.size()):
		var offset: int = 0 if team_index == 0 else (teams[0] as Array).size()
		for i in range((teams[team_index] as Array).size()):
			var account: int = int(teams[team_index][i].get("account", 0))
			if account > 0:
				seats[account] = offset + i
	game = LocalMatch.new()
	add_child(game)
	game.start(config)
	game.finished.connect(on_finished)
	for account: int in seats:
		var session: PlayerSession = players.get(account)
		if session == null or session.lingering or gone.has(account):
			# Nobody at the controls: the AI plays this fighter from the start.
			queue_input(int(seats[account]), "leave" if gone.has(account) else "auto", {"on": true})
		else:
			send_start(session)

func send_start(session: PlayerSession, resume: bool = false) -> void:
	var own: Dictionary = config.duplicate()
	own.local = int(seats.get(session.account_id, 0))
	var message: Dictionary = {"t": "match_start", "m": match_id, "config": own, "phase": expedition != null}
	if resume:
		# Coming back: the whole phase so far, to catch up by simulating it again.
		message.history = history
		message.u = tick
	session.send(message)

func queue_input(fighter: int, action: String, data: Dictionary) -> void:
	# Applied and sent exactly as every copy will read it back (JSON numbers).
	pending.append([fighter, action, JSON.parse_string(JSON.stringify(data))])

# An intent from a player: only their own fighter, known actions and plain values.
func receive(session: PlayerSession, message: Dictionary) -> void:
	if over or not seats.has(session.account_id) or int(message.get("m", -1)) != match_id:
		return
	var action: String = str(message.get("a", ""))
	var raw: Variant = message.get("d", {})
	if not action in ACTIONS or not raw is Dictionary:
		return
	var fighter: int = int(seats[session.account_id])
	if pending.filter(func(entry: Array) -> bool: return int(entry[0]) == fighter).size() >= MAX_PENDING:
		return
	var data: Dictionary = {}
	for key: String in ["d", "angle", "power", "slot", "on", "id"]:
		if (raw as Dictionary).has(key):
			var value: Variant = raw[key]
			if value is float or value is int or value is bool:
				data[key] = value
			elif value is String and key == "id":
				data[key] = (value as String).substr(0, 32)
	queue_input(fighter, action, data)

func _physics_process(delta: float) -> void:
	if phase_timer > 0.0:
		phase_timer -= delta
		if phase_timer <= 0.0:
			start_phase(next_config)
		return
	if over or not is_instance_valid(game) or not game.running:
		return
	for entry: Array in pending:
		game.apply_input(int(entry[0]), str(entry[1]), entry[2])
		var stamped: Array = [tick, entry[0], entry[1], entry[2]]
		outbox.append(stamped)
		history.append(stamped)
	pending.clear()
	game.step(DT)
	if tick % SUM_EVERY == 0:
		sums.append([tick, game.checksum()])
	tick += 1
	if tick % SEND_EVERY == 0 or not game.running:
		flush()

func flush() -> void:
	var message: Dictionary = {"t": "ticks", "m": match_id, "u": tick, "i": outbox}
	if not sums.is_empty():
		message.s = sums
	for session: PlayerSession in players.values():
		if not session.lingering and not gone.has(session.account_id):
			session.send(message)
	outbox = []
	sums = []

func on_finished(winner: int) -> void:
	flush()
	if expedition != null and winner == 0 and expedition.has_next_phase():
		var reports: Dictionary = expedition.complete_phase(game)
		for account: int in reports:
			var session: PlayerSession = players.get(account)
			if session != null:
				session.send({"t": "phase_end", "m": match_id, "report": reports[account], "profile": session.profile.to_data()})
				server.audit(session, "phase", {"match": match_id, "phase": expedition.leader.phase_index, "gold": reports[account].gold, "maps": reports[account].maps.size(), "currency": reports[account].currency.size()})
		next_config = expedition.phase_config()
		phase_timer = PHASE_PAUSE
		return
	over = true
	call_deferred("settle", winner)

func fighter_of(account: int) -> TankFighter:
	return game.fighters[int(seats[account])]

# The battle is over: rewards for everyone who stayed, cards dealt on the server.
func settle(winner: int) -> void:
	for account: int in seats:
		var session: PlayerSession = players.get(account)
		if session == null or gone.has(account):
			continue
		# Cards of an earlier battle still unpicked are dealt now, before the new ones.
		server.auto_pick(session)
		var run: InstanceRun = expedition.run_for(account) if expedition != null else null
		var summary: Dictionary = Rewards.settle(game, fighter_of(account), balance, session.profile, run)
		var cards: Array = []
		if summary.has("loot"):
			cards = summary.loot.cards
			var visible: Dictionary = summary.loot.duplicate()
			visible.erase("cards")
			summary.loot = visible
		else:
			cards = Rewards.pvp_cards(balance, rng)
		session.result = {"match": match_id, "cards": cards, "picks": Rewards.picks(summary), "revealed": [], "at": Time.get_unix_time_from_system()}
		session.send({"t": "match_end", "m": match_id, "winner": winner, "summary": summary, "picks": session.result.picks, "profile": session.profile.to_data()})
		server.audit(session, "match", {"match": match_id, "mode": mode, "won": summary.won, "exp": summary.exp, "merit": summary.merit, "seconds": roundi(Time.get_unix_time_from_system() - started_at)})
		for drop: Dictionary in summary.get("instance", {}).get("chest", []):
			server.announce(Lang.t("Parabéns! [%s] ganhou [%s] através de Instância."), [session.profile.player_name], {"id": str(drop.get("weapon", "")), "quality": str(drop.get("quality", "super"))})
	server.match_over(self)

# A player dropped (connection lost): the AI plays for them; they may come back.
func dropped(session: PlayerSession) -> void:
	if seats.has(session.account_id) and not over:
		queue_input(int(seats[session.account_id]), "auto", {"on": true})

# A player quit the battle: the AI plays on, they get no rewards.
func left(session: PlayerSession) -> void:
	if seats.has(session.account_id) and not over:
		gone[session.account_id] = true
		queue_input(int(seats[session.account_id]), "leave", {})
	session.host = null

func resume(session: PlayerSession) -> void:
	if over or gone.has(session.account_id) or not seats.has(session.account_id):
		return
	players[session.account_id] = session
	session.host = self
	if phase_timer > 0.0:
		return
	send_start(session, true)

func connected_players() -> int:
	var count: int = 0
	for account: int in players:
		var session: PlayerSession = players[account]
		if not session.lingering and not gone.has(account):
			count += 1
	return count
