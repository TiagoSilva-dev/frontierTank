class_name LocalHost
extends Node

# The server's part for a lockstep battle that runs on this computer (the daily challenge):
# the intents of the local player are stamped with the current tick, applied at the start of
# that tick and recorded, exactly as MatchHost does online. The record is the battle's replay
# (see Replay), which the server can run again to check a score.

signal ended

const DT: float = 1.0 / 60.0

var game: LocalMatch
var tick: int = 0
var pending: Array = []
var history: Array = []
# Actions the run does not accept (the challenge turns the AI and emotes off).
var refused: Array[String] = []

# `game.remote` calls this with the action and its data (the intents of `game.local_id`).
func submit(action: String, data: Dictionary) -> void:
	if action in refused or game == null:
		return
	var cleaned: Array = Replay.clean_input([0, game.local_id, action, data], game.fighters.size())
	if cleaned.is_empty():
		return
	# Applied and recorded as every other copy would read it back (JSON numbers).
	pending.append([game.local_id, action, JSON.parse_string(JSON.stringify(cleaned[3]))])

func _physics_process(_delta: float) -> void:
	if game == null or not is_instance_valid(game) or not game.running or game.paused:
		return
	advance()

func advance() -> void:
	for entry: Array in pending:
		game.apply_input(int(entry[0]), str(entry[1]), entry[2])
		history.append([tick, entry[0], entry[1], entry[2]])
	pending.clear()
	game.step(DT)
	tick += 1
	if not game.running:
		ended.emit()

