extends SceneTree

# The battles of simulated players on the game server (docs/BOTS.md, BotArena): the Salão shows
# rooms that really are in battle, the PvP ones can be watched, nobody is in two battles, they
# end by themselves and give way to real players. Time is virtual: the test advances every battle
# one 60 Hz tick at a time (MatchHost._physics_process, the code the server runs), and sessions
# have no socket, what the server sends is read from the fake's outbox.

const PORT: int = 7395
const DT: float = 1.0 / 60.0
# Half an hour of play: a battle that lasts longer than this is stuck.
const MAX_TICKS: int = 108000

class FakeSession extends PlayerSession:
	var sent: Array = []

	func send(message: Dictionary) -> void:
		sent.append(message)

	func last_reply() -> Dictionary:
		for i in range(sent.size() - 1, -1, -1):
			if str(sent[i].get("t", "")) == "reply":
				return sent[i]
		return {}

	func got(kind: String) -> Array:
		return sent.filter(func(message: Dictionary) -> bool: return str(message.get("t", "")) == kind)

var errors: int = 0
var checks: int = 0
var server: GameServer
var arena: BotArena
var next_account: int = 1

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		errors += 1
		push_error(message)

func real_player(who: String) -> FakeSession:
	var session: FakeSession = FakeSession.new()
	session.account_id = next_account
	next_account += 1
	session.username = who
	session.state = "lobby"
	session.profile = PlayerProfile.new()
	session.profile.player_name = who
	session.profile.created = true
	server.accounts[session.account_id] = session
	return session

# The battles go by this script's ticks, not by the engine's own physics frame.
func manual() -> void:
	for host: MatchHost in server.hosts.values():
		host.set_physics_process(false)

# Starts battles until the wanted ones are going (one per step, as the server does).
func fill(real: int) -> void:
	for i in range(80):
		arena.step(10.0, real)
		manual()

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	server = GameServer.new()
	server.configure({"port": str(PORT), "bind": "127.0.0.1", "api": "memory", "population": "20", "bot-battles": "6", "id": "a1", "name": "Arena"})
	root.add_child(server)
	await process_frame
	server.set_process(false)
	arena = server.arena
	check(server.listening and server.bot_battles == 6 and arena.max_battles == 6, "the server starts its arena with 6 battles")
	check(arena.wanted(0) == {"pvp": 4, "pve": 2}, "with nobody online: 4 PvP battles and 2 PvE parties")
	check(arena.wanted(10) == {"pvp": 2, "pve": 1}, "with half the population real: half the battles")
	check(arena.wanted(20) == {"pvp": 0, "pve": 0} and arena.wanted(300) == {"pvp": 0, "pve": 0}, "from the whole population on: none")
	# --- It never starts a battle the server cannot afford, nor for a population of nobody
	arena.load_limit = -1.0
	arena.wait = 0.0
	arena.step(1.0, 0)
	check(server.hosts.is_empty() and arena.wait > 0.0, "while the server is busy no battle starts")
	arena.load_limit = BotArena.LOAD_LIMIT
	# --- The battles
	fill(0)
	check(server.hosts.size() == 6 and arena.count("pvp") == 4 and arena.count("pve") == 2, "6 battles are going: %d PvP and %d PvE" % [arena.count("pvp"), arena.count("pve")])
	var people: Array = []
	var nobody_human: bool = true
	var seeds: Dictionary = {}
	for host: MatchHost in server.hosts.values():
		seeds[host.config.seed] = true
		nobody_human = nobody_human and host.players.is_empty() and host.seats.is_empty()
		for team: Variant in host.config.teams:
			for entry: Dictionary in team:
				# The monsters of a PvE party have names too (and repeat them): they have no skill.
				if entry.has("skill"):
					people.append(str(entry.name).to_lower())
	check(nobody_human, "nobody is at the controls: the AI plays every fighter")
	var distinct: Dictionary = {}
	for who: String in people:
		distinct[who] = true
	check(distinct.size() == people.size(), "nobody is in two battles at once (%d fighters)" % people.size())
	check(arena.busy_names().size() == people.size(), "and the arena knows who is busy")
	var believable: bool = true
	for who: String in people:
		believable = believable and not BotRoster.looks_like_bot(who)
	check(believable, "and every one of them has a believable name")
	# --- The Salão lists them as rooms in battle
	var snapshot: Dictionary = server.lobby_snapshot()
	var in_battle: Array = snapshot.rooms.filter(func(room: Dictionary) -> bool: return bool(room.playing))
	var pvp_rooms: Array = in_battle.filter(func(room: Dictionary) -> bool: return str(room.mode) == "pvp")
	var pve_rooms: Array = in_battle.filter(func(room: Dictionary) -> bool: return str(room.mode) == "pve")
	check(pvp_rooms.size() == 8 and pve_rooms.size() == 2, "the Salão shows %d PvP rooms (two a battle) and %d PvE rooms in battle" % [pvp_rooms.size(), pve_rooms.size()])
	var ids: Dictionary = {}
	for room: Dictionary in snapshot.rooms:
		ids[int(room.id)] = true
	check(ids.size() == snapshot.rooms.size(), "every room has its own number")
	var watchable: bool = true
	for room: Dictionary in pvp_rooms:
		var host: MatchHost = server.hosts.get(int(room.get("match", -1)))
		watchable = watchable and bool(room.get("sim", false)) and host != null and host.mode == "pvp" and host.ranked.is_empty()
	check(watchable, "each PvP room carries the match to watch")
	var titles: Array = server.balance.instances.map(func(instance: Dictionary) -> String: return str(instance.name))
	var party_ok: bool = true
	for room: Dictionary in pve_rooms:
		party_ok = party_ok and not room.has("match") and titles.has(str(room.title)) and (room.members as Array).size() >= 1 and bool(room.get("sim", false))
	check(party_ok, "a PvE room is named after its instance and is not offered to watch")
	var shown: bool = true
	for room: Dictionary in in_battle:
		shown = shown and (room.members as Array).all(func(member: Dictionary) -> bool: return not bool(member.get("human", false)))
	check(shown, "none of the people in them is a real player")
	var text: String = JSON.stringify(snapshot)
	check(not text.contains("skill") and not text.contains("agility") and not text.contains("\"bot\""), "the list still carries nothing of how the AI plays")
	# --- Nobody can walk into one, and a room number is never reused
	var visitor: FakeSession = real_player("Visitante")
	var battle_id: int = int(pvp_rooms[0].id)
	server.room_join(visitor, {"rid": 1, "id": battle_id})
	check(not bool(visitor.last_reply().get("ok", true)) and str(visitor.last_reply().get("error", "")).contains("batalha") and visitor.room == null, "a room in battle cannot be entered")
	var clash: bool = false
	var real_room: ServerRoom = ServerRoom.new()
	real_room.id = 500
	server.rooms[500] = real_room
	for i in range(300):
		var fresh: int = arena.fresh_id()
		clash = clash or fresh == 500 or server.new_room_id() == battle_id or not server.bots.find_room(fresh).is_empty()
	server.rooms.erase(500)
	check(not clash, "a new room never takes the number of a battle, a simulated room or a real room")
	# --- A real player can watch a PvP battle (and not a PvE one)
	var match_id: int = int(pvp_rooms[0].match)
	server.spectate(visitor, {"rid": 2, "m": match_id})
	var start: Array = visitor.got("match_start")
	check(bool(visitor.last_reply().get("ok", false)) and visitor.watching == server.hosts[match_id] and start.size() == 1 and bool(start[0].get("watch", false)), "a real player watches a PvP battle of simulated players")
	var teams_seen: Array = start[0].config.teams if not start.is_empty() else []
	check(teams_seen.size() == 2 and (teams_seen[0] as Array).size() == (teams_seen[1] as Array).size() and not (teams_seen[0] as Array).is_empty(), "and sees both teams")
	var party_match: int = -1
	for id: int in server.hosts:
		if server.hosts[id].mode == "pve":
			party_match = id
	var other: FakeSession = real_player("Curioso")
	server.spectate(other, {"rid": 3, "m": party_match})
	check(not bool(other.last_reply().get("ok", true)) and other.watching == null, "a PvE party cannot be watched")
	# --- The battles play to the end by themselves
	var first: Array = server.hosts.keys()
	var ticks: int = 0
	while not server.hosts.is_empty() and ticks < MAX_TICKS:
		for host: MatchHost in server.hosts.values():
			if is_instance_valid(host):
				host._physics_process(DT)
		ticks += 1
		if ticks % 60 == 0:
			# A battle's settlement runs between frames.
			await process_frame
	await process_frame
	check(server.hosts.is_empty() and arena.live.is_empty() and arena.rooms.is_empty(), "every battle ended by itself in %.1f minutes of play, and left the Salão" % (ticks / 3600.0))
	check(visitor.watching == null and server.lobby_snapshot().rooms.filter(func(room: Dictionary) -> bool: return bool(room.playing)).is_empty(), "the spectator is free again and no room is left in battle")
	check(visitor.got("ticks").size() > 0, "and was sent the battle's stream")
	var verdict: Dictionary = replay_of(visitor)
	check(str(verdict.error) == "" and int(verdict.checked) >= 10, "what the spectator was sent replays to the same battle, %d checksums agree%s" % [int(verdict.checked), "" if str(verdict.error) == "" else " (" + str(verdict.error) + ")"])
	var outcome: bool = true
	for id: int in first:
		outcome = outcome and not is_instance_valid(server.hosts.get(id))
	check(outcome, "no battle is left behind")
	# --- And new ones start in their place, as many as wanted
	var total: int = arena.started
	fill(0)
	check(arena.started > total and server.hosts.size() == 6, "new battles replace the ones that ended")
	# --- Real players take the places: the battles stop being started
	for host: MatchHost in server.hosts.values():
		host.set_physics_process(false)
	var crowd: Array[FakeSession] = []
	for i in range(20):
		crowd.append(real_player("Real%d" % i))
	var before: int = arena.started
	for host: MatchHost in server.hosts.values():
		host.over = true
		server.match_over(host)
	await process_frame
	fill(real_people())
	check(arena.started == before and server.hosts.is_empty(), "with the population's worth of real players, no battle starts")
	for session: FakeSession in crowd:
		server.accounts.erase(session.account_id)
	# --- Off switches
	arena.max_battles = 0
	fill(0)
	check(arena.started == before and server.hosts.is_empty(), "0 battles turns the arena off")
	arena.max_battles = 6
	server.population = 0
	server.simulate_population(1.0)
	arena.wait = 0.0
	server.simulate_population(10.0)
	check(server.hosts.is_empty() and server.lobby_snapshot().rooms.is_empty(), "population 0 turns off the battles with the rest")
	server.population = 20
	server.accounts.clear()
	server.set_process(false)
	server.bots.free()
	server.queue_free()
	await process_frame
	print("ARENA RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)

func real_people() -> int:
	return server.real_people()

# A spectator's own copy of the battle: the start and the stream it was sent (as the socket
# would carry them), played again. Every checksum the server sent must be the copy's own.
func replay_of(session: FakeSession) -> Dictionary:
	var starts: Array = session.got("match_start")
	if starts.is_empty():
		return {"error": "no match_start", "checked": 0}
	var config: Dictionary = JSON.parse_string(JSON.stringify(starts[0].config))
	var by_tick: Dictionary = {}
	var sums: Dictionary = {}
	var last: int = 0
	for raw: Dictionary in session.got("ticks"):
		var message: Dictionary = JSON.parse_string(JSON.stringify(raw))
		for entry: Array in message.i:
			if not by_tick.has(int(entry[0])):
				by_tick[int(entry[0])] = []
			by_tick[int(entry[0])].append(entry)
		for pair: Array in message.get("s", []):
			sums[int(pair[0])] = int(pair[1])
		last = maxi(last, int(message.u))
	var copy: LocalMatch = LocalMatch.new()
	root.add_child(copy)
	copy.start(config)
	var checked: int = 0
	var error: String = ""
	var tick: int = 0
	while tick < last and copy.running and error == "":
		for entry: Array in by_tick.get(tick, []):
			copy.apply_input(int(entry[1]), str(entry[2]), entry[3])
		copy.step(DT)
		if sums.has(tick):
			checked += 1
			if copy.checksum() != sums[tick]:
				error = "different at tick %d" % tick
		tick += 1
	copy.queue_free()
	return {"error": error, "checked": checked}
