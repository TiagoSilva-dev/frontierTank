extends SceneTree

# Load test of the game server with simulated players (docs/BOTS.md). Not part of the suite
# (the numbers depend on the machine): it reports them.
#
#   godot --headless --path . --script tests/bot_load.gd -- --pvp=20 --pve=10 --seconds=120
#
# A real GameServer (in-memory API) runs battles made only of simulated players, PvP rooms of 1 to
# 4 a side and PvE parties on the instances, the way it would run them for people. Time is
# virtual: every sweep advances every battle by one 60 Hz tick (MatchHost._physics_process, the
# same code the server runs) and the sweep's wall time is what the server's CPU would pay
# for that tick, so a sweep under 16.7 ms means the machine keeps 60 ticks a second.
# `--watchers=N` adds N spectators to every PvP battle (the messages are serialized as for real
# sockets, without the socket), to count what the players' side of a battle costs. A battle
# that ends is replaced, so the load stays the same for the whole run.
#   --pvp, --pve      battles at once (default 20 and 10)
#   --seconds         virtual seconds to play (default 120)
#   --watchers        spectators per PvP battle (default 4, at most 12)
#   --seed            seed of the people and of the maps (default 1)
#   --level           level of the simulated players (default: random 1 to 40)

const PORT: int = 7393
const DT: float = 1.0 / 60.0
const BUDGET_MS: float = 1000.0 / 60.0

# A spectator that serializes what it is sent, as the socket would.
class Spectator extends PlayerSession:
	var bytes: int = 0
	var messages: int = 0

	func send(message: Dictionary) -> void:
		bytes += JSON.stringify(message).length()
		messages += 1

var server: GameServer
var args: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var spectators: Array[Spectator] = []
var next_spectator: int = 100000
var started: Dictionary = {"pvp": 0, "pve": 0}
var finished: Dictionary = {"pvp": 0, "pve": 0}
var instance_turn: int = 0

func _initialize() -> void:
	call_deferred("run")

func option(key: String, fallback: float) -> float:
	return float(args.get(key, fallback))

func parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = raw.trim_prefix("--").split("=")
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"

func run() -> void:
	parse_args()
	Lang.override = "pt_BR"
	Lang.setup()
	rng.seed = int(option("seed", 1))
	var pvp: int = int(option("pvp", 20))
	var pve: int = int(option("pve", 10))
	var seconds: float = option("seconds", 120.0)
	var watchers: int = clampi(int(option("watchers", 4)), 0, 12)
	server = GameServer.new()
	server.configure({"port": str(PORT), "bind": "127.0.0.1", "api": "memory", "population": "0", "id": "load", "name": "Carga"})
	root.add_child(server)
	await process_frame
	server.set_process(false)
	server.bots.rng.seed = int(option("seed", 1))
	server.bots.populate()
	print("load test: %d PvP + %d PvE battles of simulated players, %d spectators each PvP, %.0f virtual seconds" % [pvp, pve, watchers, seconds])
	var target: Dictionary = {"pvp": pvp, "pve": pve}
	var nodes_before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var memory_before: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var sweeps: PackedFloat64Array = PackedFloat64Array()
	var per_mode: Dictionary = {"pvp": 0.0, "pve": 0.0}
	var mode_ticks: Dictionary = {"pvp": 0, "pve": 0}
	var running_sum: float = 0.0
	var total_ticks: int = int(seconds * 60.0)
	var setup_started: int = Time.get_ticks_msec()
	refill(target, watchers)
	print("started %d battles in %d ms" % [server.hosts.size(), Time.get_ticks_msec() - setup_started])
	var filled: Dictionary = {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "memory": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, "battles": server.hosts.size()}
	var checkpoints: Array[String] = []
	for tick in range(total_ticks):
		var sweep_started: int = Time.get_ticks_usec()
		for host: MatchHost in server.hosts.values():
			if not is_instance_valid(host):
				continue
			var host_started: int = Time.get_ticks_usec()
			host._physics_process(DT)
			per_mode[host.mode] += (Time.get_ticks_usec() - host_started) / 1000.0
			if not host.over and host.phase_timer <= 0.0:
				mode_ticks[host.mode] += 1
		sweeps.append((Time.get_ticks_usec() - sweep_started) / 1000.0)
		running_sum += server.hosts.size()
		if tick % 30 == 29:
			# Deferred work (a battle's settlement) runs between frames.
			await process_frame
			refill(target, watchers)
		if tick % 3600 == 3599:
			checkpoints.append("%ds: %d nodes, %.0f MB, %d battles" % [(tick + 1) / 60, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, server.hosts.size()])
	await process_frame
	report(sweeps, per_mode, mode_ticks, running_sum / float(total_ticks), nodes_before, seconds, memory_before, filled, checkpoints)
	for host: MatchHost in server.hosts.values():
		host.set_physics_process(false)
	server.bots.free()
	server.queue_free()
	await process_frame
	quit(0)

# Starts battles until the wanted number of each kind is running.
func refill(target: Dictionary, watchers: int) -> void:
	var live: Dictionary = {"pvp": 0, "pve": 0}
	for host: MatchHost in server.hosts.values():
		if is_instance_valid(host) and not host.over:
			live[host.mode] += 1
	finished["pvp"] = int(started["pvp"]) - int(live["pvp"])
	finished["pve"] = int(started["pve"]) - int(live["pve"])
	for i in range(int(target.pvp) - int(live.pvp)):
		start_pvp(watchers)
	for i in range(int(target.pve) - int(live.pve)):
		start_pve()

func level_for_match() -> int:
	return int(option("level", 0)) if args.has("level") else rng.randi_range(1, 40)

func team_of(size: int, level: int, names: Array) -> Array:
	var team: Array = []
	for i in range(size):
		var bot: Dictionary = server.bots.bot_near(level, names)
		names.append(bot.name)
		team.append(bot)
	return team

func manual(host: MatchHost) -> void:
	# This script advances the battle: the engine's own physics tick must not do it twice.
	host.set_physics_process(false)

func start_pvp(watchers: int) -> void:
	var level: int = level_for_match()
	var size: int = [1, 2, 2, 3, 4, 4][rng.randi() % 6]
	var names: Array = []
	var teams: Array = [team_of(size, level, names), team_of(size, level, names)]
	var maps: Array = server.balance.maps.filter(func(entry: Dictionary) -> bool: return not entry.get("pve_only", false))
	var room: ServerRoom = ServerRoom.new()
	for bot: Dictionary in teams[0]:
		room.members.append({"bot": bot})
	var config: Dictionary = {"mode": "pvp", "map": str(maps[rng.randi() % maps.size()].id), "turn_seconds": 10, "teams": teams}
	var joined: Array[ServerRoom] = [room]
	server.launch(joined, config, null)
	var host: MatchHost = server.hosts[server.next_match - 1]
	manual(host)
	started["pvp"] += 1
	for i in range(watchers):
		var watcher: Spectator = Spectator.new()
		next_spectator += 1
		watcher.account_id = next_spectator
		watcher.state = "lobby"
		if host.add_watcher(watcher):
			spectators.append(watcher)

func start_pve() -> void:
	var level: int = level_for_match()
	var size: int = [1, 2, 3, 4][rng.randi() % 4]
	var instances: Array = server.balance.instances
	var id: String = str(instances[instance_turn % instances.size()].id)
	instance_turn += 1
	var team: Array = team_of(size, level, [])
	var room: ServerRoom = ServerRoom.new()
	for bot: Dictionary in team:
		room.members.append({"bot": bot})
	var item: Dictionary = {"instance": id, "level": clampi(level / 3, 1, 16), "mods": []}
	var expedition: Expedition = Expedition.new(server.balance, id, item, team, {})
	var joined: Array[ServerRoom] = [room]
	server.launch(joined, expedition.phase_config(), expedition)
	manual(server.hosts[server.next_match - 1])
	started["pve"] += 1

func percentile(sorted: Array, share: float) -> float:
	return sorted[clampi(int(float(sorted.size()) * share), 0, sorted.size() - 1)]

func report(sweeps: PackedFloat64Array, per_mode: Dictionary, mode_ticks: Dictionary, average_battles: float, nodes_before: int, seconds: float, memory_before: float, filled: Dictionary, checkpoints: Array[String]) -> void:
	var list: Array = Array(sweeps)
	var sorted: Array = list.duplicate()
	sorted.sort()
	var sum: float = 0.0
	var over_budget: int = 0
	var over_double: int = 0
	for value: float in list:
		sum += value
		if value > BUDGET_MS:
			over_budget += 1
		if value > BUDGET_MS * 2.0:
			over_double += 1
	var average: float = sum / float(list.size())
	var bytes: int = 0
	for watcher: Spectator in spectators:
		bytes += watcher.bytes
	print("")
	print("battles at once: %.1f (started %d PvP and %d PvE; ended %d and %d)" % [average_battles, started.pvp, started.pve, finished.pvp, finished.pve])
	print("tick of all battles (ms):  average %.2f   p50 %.2f   p95 %.2f   p99 %.2f   worst %.2f   (budget %.2f)" % [average, percentile(sorted, 0.5), percentile(sorted, 0.95), percentile(sorted, 0.99), sorted[-1], BUDGET_MS])
	print("ticks over the budget: %d of %d (%.2f%%), over twice the budget: %d" % [over_budget, list.size(), 100.0 * over_budget / list.size(), over_double])
	print("one core's load at 60 Hz: %.0f%%   (%.3f ms per battle per tick)" % [100.0 * average / BUDGET_MS, average / maxf(1.0, average_battles)])
	for mode: String in ["pvp", "pve"]:
		var ticks: int = int(mode_ticks[mode])
		print("  %s: %.3f ms per battle per tick (%d battle-ticks)" % [mode, float(per_mode[mode]) / maxf(1.0, float(ticks)), ticks])
	var spare: float = BUDGET_MS * 0.7 / maxf(0.0001, average / maxf(1.0, average_battles))
	print("battles one core keeps at 70%% load: about %d" % int(spare))
	if not spectators.is_empty():
		print("spectator traffic: %.0f KB/s in %d messages/s over %d spectators (%.1f KB/s each)" % [bytes / 1024.0 / seconds, int(_messages() / seconds), spectators.size(), bytes / 1024.0 / seconds / spectators.size()])
	var memory_now: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("memory: %.0f MB before the battles, %.0f MB with %d running (%.1f MB per battle), %.0f MB at the end" % [memory_before, float(filled.memory), int(filled.battles), (float(filled.memory) - memory_before) / maxf(1.0, float(filled.battles)), memory_now])
	print("nodes: %d before, %d with the battles running, %d at the end (%d each minute: %s)" % [nodes_before, int(filled.nodes), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), checkpoints.size(), "; ".join(checkpoints)])
	var metrics: Dictionary = {"pvp": started.pvp, "pve": started.pve, "average_ms": snappedf(average, 0.01), "p95_ms": snappedf(percentile(sorted, 0.95), 0.01), "p99_ms": snappedf(percentile(sorted, 0.99), 0.01), "worst_ms": snappedf(sorted[-1], 0.01), "core_load": snappedf(average / BUDGET_MS, 0.01)}
	print("LOAD " + JSON.stringify(metrics))

func _messages() -> int:
	var count: int = 0
	for watcher: Spectator in spectators:
		count += watcher.messages
	return count
