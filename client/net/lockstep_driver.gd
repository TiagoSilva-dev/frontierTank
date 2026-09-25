class_name LockstepDriver
extends Node

# Steps the player's copy of an online battle (see LocalMatch): tick by tick, only up to
# the last tick the server confirmed, applying the intents stamped for each tick first.
# When it falls behind (a slow frame, or coming back to a battle) it runs extra ticks per
# frame to catch up. The server's checksums reveal if this copy drifted.

signal desynced(tick: int)

const DT: float = 1.0 / 60.0
# Up to this many ticks behind, one tick per frame; more than that, catch up.
const SLACK: int = 6
const MAX_PER_FRAME: int = 240

var game: LocalMatch
var tick: int = 0
var confirmed: int = 0
var inputs: Dictionary = {}
var sums: Dictionary = {}
var drift_reported: bool = false

func receive(message: Dictionary) -> void:
	for entry: Variant in message.get("i", []):
		if entry is Array and (entry as Array).size() >= 4:
			var at: int = int(entry[0])
			if not inputs.has(at):
				inputs[at] = []
			inputs[at].append(entry)
	for entry: Variant in message.get("s", []):
		if entry is Array and (entry as Array).size() >= 2:
			sums[int(entry[0])] = int(entry[1])
	confirmed = maxi(confirmed, int(message.get("u", confirmed)))

func behind() -> int:
	return confirmed - tick

func catching_up() -> bool:
	return behind() > 90

func _physics_process(_delta: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	var lag: int = behind()
	var steps: int = 0
	if lag > 0:
		steps = 1 if lag <= SLACK else mini(lag - SLACK / 2, MAX_PER_FRAME)
	for i in range(steps):
		advance()

func advance() -> void:
	for entry: Array in inputs.get(tick, []):
		game.apply_input(int(entry[1]), str(entry[2]), entry[3] if entry[3] is Dictionary else {})
	inputs.erase(tick)
	game.step(DT)
	if sums.has(tick):
		if sums[tick] != game.checksum() and not drift_reported:
			push_warning("LockstepDriver: tick %d differs from the server: %s" % [tick, game.checksum_text()])
			drift_reported = true
			desynced.emit(tick)
		sums.erase(tick)
	tick += 1
