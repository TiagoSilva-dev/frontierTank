class_name BotArena
extends RefCounted

# Battles of simulated players on the game server (docs/BOTS.md): the Salão of a young server
# shows rooms that really are in battle, PvP ones that anyone can watch (the same broadcast
# as any other room) and PvE parties on the instances, all played by the AI that plays a rival.
# They are the same people the list shows, never in two battles at once, and they fade out as
# real players arrive: from `population` of them on no battle starts, and the ones going on
# end by themselves (a few minutes). Nothing here has an account, a reward or a rating: the
# battles run with nobody at the controls, so the host settles them without paying anyone.

# A third of the battles are PvE parties.
const PVE_DIVISOR: int = 3
const MAX_BATTLES: int = 40
# A battle does not start while the server's physics frame takes longer than this (seconds,
# of a 16.7 ms frame): the real players come first.
const LOAD_LIMIT: float = 0.010
const TEAM_SIZES: Array[int] = [1, 2, 2, 3, 4, 4]
const PARTY_SIZES: Array[int] = [1, 2, 3, 3, 4]

var server: GameServer
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
# How many battles to keep going with nobody online (`0`: none).
var max_battles: int = 6
var load_limit: float = LOAD_LIMIT
# The rooms in battle (a PvP battle has two, a PvE party one), for the list of the Salão.
var rooms: Array[ServerRoom] = []
# Match id -> {"mode", "rooms"}.
var live: Dictionary = {}
var wait: float = 2.0
var started: int = 0

func _init(owner: GameServer) -> void:
	server = owner
	rng.randomize()

# How many battles of each kind the server wants with `real` players online: all of them with
# nobody, fewer as the real players take the places of the simulated ones, none from
# `population` real players on.
func wanted(real: int) -> Dictionary:
	var share: float = clampf(float(server.population - real) / float(maxi(1, server.population)), 0.0, 1.0)
	var total: int = clampi(max_battles, 0, MAX_BATTLES)
	var pve: int = total / PVE_DIVISOR
	return {"pvp": roundi(float(total - pve) * share), "pve": roundi(float(pve) * share)}

func count(mode: String) -> int:
	var total: int = 0
	for entry: Dictionary in live.values():
		if entry.mode == mode:
			total += 1
	return total

# Once a second: starts one battle when there are fewer than wanted (never many at once: a
# battle takes a moment to build, and they should not all end together).
func step(seconds: float, real: int) -> void:
	wait -= seconds
	if wait > 0.0 or max_battles <= 0:
		return
	if Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) > load_limit:
		wait = 5.0
		return
	var want: Dictionary = wanted(real)
	var short: Array[String] = []
	for mode: String in ["pvp", "pve"]:
		if count(mode) < int(want[mode]):
			short.append(mode)
	if short.is_empty():
		return
	var mode: String = short[rng.randi() % short.size()]
	wait = rng.randf_range(2.0, 8.0) if start(mode) else 3.0

func start(mode: String) -> bool:
	if server.bots.bots.is_empty():
		return false
	var level: int = int(server.bots.random_bot().level)
	return start_pvp(level) if mode == "pvp" else start_pve(level)

func start_pvp(level: int) -> bool:
	var size: int = TEAM_SIZES[rng.randi() % TEAM_SIZES.size()]
	var names: Array = busy_names()
	var teams: Array = []
	for side in range(2):
		teams.append(team_of(size, level, names))
	var joined: Array[ServerRoom] = []
	for team: Array in teams:
		joined.append(make_room("pvp", team, str(LobbyDirectory.ROOM_TITLES[rng.randi() % LobbyDirectory.ROOM_TITLES.size()]), team.size()))
	# The map is drawn by the battle's seed, as for a room that did not choose one.
	var config: Dictionary = {"mode": "pvp", "map": "", "turn_seconds": int(server.balance.turn_seconds), "crystals": true, "teams": teams}
	return begin(joined, config, null)

func start_pve(level: int) -> bool:
	var size: int = PARTY_SIZES[rng.randi() % PARTY_SIZES.size()]
	var team: Array = team_of(size, level, busy_names())
	var instances: Array = server.balance.instances
	var id: String = str(instances[rng.randi() % instances.size()].id)
	var room: ServerRoom = make_room("pve", team, str(InstanceRun.instance_def(id).name), 4)
	room.instance = id
	var item: Dictionary = {"instance": id, "level": clampi(level / 3, 1, 16), "mods": []}
	var expedition: Expedition = Expedition.new(server.balance, id, item, team, {})
	var joined: Array[ServerRoom] = [room]
	return begin(joined, expedition.phase_config(), expedition)

# `size` people of about `level`, none of them in `names` (who is busy), added to it.
func team_of(size: int, level: int, names: Array) -> Array:
	var team: Array = []
	for i in range(size):
		var bot: Dictionary = server.bots.bot_near(level, names)
		names.append(bot.name)
		team.append(bot)
	return team

# A room of the arena: the same shape as one of the server's, only it is not in `server.rooms`
# (nobody can join it), so the Salão lists it by `summary` as a room in battle.
func make_room(mode: String, team: Array, title: String, capacity: int) -> ServerRoom:
	var room: ServerRoom = ServerRoom.new()
	room.id = fresh_id()
	room.mode = mode
	room.title = title
	room.capacity = capacity
	room.turn_seconds = int(server.balance.turn_seconds)
	for bot: Dictionary in team:
		room.members.append({"bot": bot})
	rooms.append(room)
	return room

func fresh_id() -> int:
	var id: int = rng.randi_range(100, 999)
	while server.room_id_taken(id):
		id = rng.randi_range(100, 999)
	return id

func begin(joined: Array[ServerRoom], config: Dictionary, expedition: Expedition) -> bool:
	server.launch(joined, config, expedition)
	var host: MatchHost = server.hosts.get(server.next_match - 1)
	if host == null:
		for room: ServerRoom in joined:
			rooms.erase(room)
		return false
	live[host.match_id] = {"mode": str(config.mode), "rooms": joined}
	started += 1
	server.lobby_dirty = true
	return true

# The battle is over (GameServer.match_over): its rooms leave the Salão.
func ended(match_id: int) -> void:
	var entry: Dictionary = live.get(match_id, {})
	if entry.is_empty():
		return
	live.erase(match_id)
	for room: ServerRoom in entry.rooms:
		rooms.erase(room)
	wait = maxf(wait, rng.randf_range(3.0, 10.0))

func has_room(id: int) -> bool:
	for room: ServerRoom in rooms:
		if room.id == id:
			return true
	return false

# The names, as the roster spells them, of everyone in a battle.
func busy_names() -> Array:
	var names: Array = []
	for room: ServerRoom in rooms:
		for member: Dictionary in room.members:
			names.append(str(member.bot.name))
	return names
