extends SceneTree

# The game server's simulated players (docs/BOTS.md): the Salão of a young server is not empty,
# the simulated give way as real players arrive, a real player can walk into a simulated room
# and play on, the rivals that fill a battle come from the same people, and nothing a client
# needs to tell them apart is a bot's name. Sessions here have no socket: what the server
# sends is read from the fake's outbox.

const PORT: int = 7392

class FakeSession extends PlayerSession:
	var sent: Array = []

	func send(message: Dictionary) -> void:
		sent.append(message)

	func last_reply() -> Dictionary:
		for i in range(sent.size() - 1, -1, -1):
			if str(sent[i].get("t", "")) == "reply":
				return sent[i]
		return {}

var errors: int = 0
var checks: int = 0
var server: GameServer
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

func drop_players() -> void:
	for session: PlayerSession in server.accounts.values():
		if session.room != null:
			server.leave_room(session)
	server.accounts.clear()
	server.rooms.clear()

func simulated(snapshot: Dictionary) -> Array:
	return snapshot.players.filter(func(person: Dictionary) -> bool: return bool(person.get("sim", false)))

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	server = GameServer.new()
	server.configure({"port": str(PORT), "bind": "127.0.0.1", "api": "memory", "bot-fill": "2", "population": "20", "bot-battles": "0", "id": "p1", "name": "Pop"})
	root.add_child(server)
	await process_frame
	check(server.listening and server.population == 20 and server.bots.bots.size() >= GameServer.ROSTER_SIZE, "the server starts with a roster of simulated players")
	# --- An empty server still shows a live channel
	var snapshot: Dictionary = server.lobby_snapshot()
	var names: Dictionary = {}
	for person: Dictionary in snapshot.players:
		names[str(person.name).to_lower()] = true
	check(snapshot.players.size() == 20 and simulated(snapshot).size() == 20 and names.size() == 20, "with nobody online the Salão lists 20 different players")
	check(int(snapshot.online) == 0, "the online count stays the real one")
	var rooms_sim: bool = not snapshot.rooms.is_empty() and snapshot.rooms.all(func(room: Dictionary) -> bool: return bool(room.get("sim", false)) and not room.has("match"))
	check(rooms_sim and snapshot.rooms.size() >= 5, "and %d rooms, none of them a battle to watch" % snapshot.rooms.size())
	var text: String = JSON.stringify(snapshot)
	check(not text.contains("skill") and not text.contains("agility") and not text.contains("\"bot\""), "the list carries nothing of how the AI plays, and no word that names one")
	var levels: Array = snapshot.players.map(func(person: Dictionary) -> int: return int(person.level))
	check(levels.min() >= 1 and levels.max() <= 40 and levels.min() < 8, "beginners and veterans are both there")
	# --- They give way to real players
	var first_name: String = str(snapshot.players[0].name)
	var real: Array[FakeSession] = []
	for i in range(5):
		real.append(real_player("Real%d" % i))
	real[0].profile.player_name = first_name.to_upper()
	snapshot = server.lobby_snapshot()
	var same: int = snapshot.players.filter(func(person: Dictionary) -> bool: return str(person.name).to_lower() == first_name.to_lower()).size()
	check(snapshot.players.size() == 20 and simulated(snapshot).size() == 15 and same == 1, "5 real players make 15 simulated ones, and a real player's name is never repeated")
	for i in range(5, 25):
		real.append(real_player("Real%d" % i))
	snapshot = server.lobby_snapshot()
	check(snapshot.players.size() == 25 and simulated(snapshot).is_empty() and snapshot.rooms.is_empty(), "from 20 real players on there are no simulated ones, in the list or in the rooms")
	drop_players()
	real.clear()
	server.population = 0
	snapshot = server.lobby_snapshot()
	check(snapshot.players.is_empty() and snapshot.rooms.is_empty(), "population 0 shows nobody")
	server.population = 20
	# --- Room numbers never collide
	var taken_ids: bool = false
	for i in range(300):
		if not server.bots.find_room(server.new_room_id()).is_empty():
			taken_ids = true
	check(not taken_ids, "a new room never takes the number of a simulated room")
	server.rooms[int(server.bots.rooms[0].id)] = ServerRoom.new()
	var clash: int = int(server.bots.rooms[0].id)
	server.bots.room_timer = 0.0
	server.simulate_population(1.0)
	check(server.bots.rooms.all(func(room: Dictionary) -> bool: return not server.rooms.has(int(room.id))) and clash > 0, "a simulated room is renumbered when a real one has its number")
	server.rooms.clear()
	# --- A real player walks into a simulated room
	var player: FakeSession = real_player("Visitante")
	var open: Dictionary = {}
	for room: Dictionary in server.bots.rooms:
		if not room.playing and room.members.size() < int(room.capacity):
			open = room
			break
	check(not open.is_empty(), "the Salão has a room with a free place")
	var id: int = int(open.id)
	var members: int = open.members.size()
	var teammates: Array = open.members.map(func(member: Dictionary) -> String: return str(member.name))
	server.room_join(player, {"rid": 1, "id": id})
	var joined: Dictionary = player.last_reply()
	var room: ServerRoom = server.rooms.get(id)
	check(bool(joined.get("ok", false)) and room != null and player.room == room, "joining a simulated room puts the player in a real one")
	check(room != null and room.members.size() == members + 1 and room.owner_session() == player, "with the same players, and the newcomer as its owner")
	var shown: Array = (joined.room.members as Array).map(func(member: Dictionary) -> String: return str(member.name))
	check(shown.has("Visitante") and teammates.all(func(who: String) -> bool: return shown.has(who)), "the room shows the same names the Salão did")
	check(server.bots.find_room(id).is_empty() and server.bots.rooms.size() == 14, "the Salão gets a new simulated room in its place")
	server.room_ready(player, {"rid": 2, "on": true})
	server.room_start(player, {"rid": 3})
	check(room.state == "searching", "the owner can start the search")
	# --- And is matched with rivals that come from the same people
	room.search_since = server.now() - 10.0
	server.matchmaking()
	check(room.state == "playing" and server.hosts.size() == 1, "after the wait the battle starts")
	if not server.hosts.is_empty():
		var host: MatchHost = server.hosts.values()[0]
		var teams: Array = host.config.teams
		var rivals_ok: bool = teams[1].size() == teams[0].size()
		var all_names: Dictionary = {}
		for team: Array in teams:
			for entry: Dictionary in team:
				all_names[str(entry.name).to_lower()] = true
		for entry: Dictionary in teams[1]:
			rivals_ok = rivals_ok and entry.has("skill") and not bool(entry.get("human", false)) and not BotRoster.looks_like_bot(str(entry.name))
		check(rivals_ok and all_names.size() == teams[0].size() + teams[1].size(), "the rivals are as many as the team, different, with a skill and a believable name")
		var skilled: bool = true
		for entry: Dictionary in teams[0]:
			if not bool(entry.get("human", false)):
				skilled = skilled and entry.has("skill")
		check(skilled, "so are the simulated teammates")
	server.leave_match(player)
	# --- A simulated room in battle cannot be entered, and an unknown one is not found
	var busy: Dictionary = {}
	for sim: Dictionary in server.bots.rooms:
		if bool(sim.playing):
			busy = sim
			break
	if busy.is_empty():
		server.bots.rooms[0].playing = true
		busy = server.bots.rooms[0]
	var other: FakeSession = real_player("Curioso")
	server.room_join(other, {"rid": 4, "id": int(busy.id)})
	check(not bool(other.last_reply().get("ok", true)) and other.room == null and not server.rooms.has(int(busy.id)), "a simulated room in battle cannot be entered")
	server.room_join(other, {"rid": 5, "id": 1})
	check(not bool(other.last_reply().get("ok", true)), "a room that does not exist is not found")
	# --- The profile window
	var famous: Dictionary = server.bots.bots[0]
	server.player_profile(other, {"rid": 6, "account": 0, "name": str(famous.name)})
	var info: Dictionary = other.last_reply().get("info", {})
	check(bool(info.get("ai", false)) and str(info.get("name", "")) == str(famous.name) and info.has("look") and info.has("arma") and int(info.get("matches", 0)) > 0, "a simulated player's profile opens, marked as the game's AI")
	check(not info.has("skill") and not info.has("agility") and not info.has("account"), "and shows nothing of how it plays")
	server.player_profile(other, {"rid": 7, "account": 0, "name": "NaoExiste"})
	check(not bool(other.last_reply().get("ok", true)), "an unknown name has no profile")
	server.player_profile(other, {"rid": 8, "account": other.account_id})
	check(not bool(other.last_reply().get("info", {}).get("ai", false)) and other.last_reply().has("info"), "a real player's profile is not marked")
	# --- Time passes: players come and go
	var before: Dictionary = {}
	for bot: Dictionary in server.bots.bots:
		before[str(bot.name)] = true
	server.rotation_wait = 0.1
	var size_before: int = server.bots.bots.size()
	server.simulate_population(1.0)
	var changed: int = 0
	for bot: Dictionary in server.bots.bots:
		if not before.has(str(bot.name)):
			changed += 1
	check(changed == 1 and server.bots.bots.size() == size_before and server.lobby_dirty, "one player left and another arrived, and the list is sent again")
	drop_players()
	server.set_process(false)
	server.bots.free()
	server.queue_free()
	await process_frame
	print("POPULATION RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)
