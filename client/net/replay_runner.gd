class_name ReplayRunner
extends Node

# Runs a replay on a fresh LocalMatch without any screen: the server uses it to check a
# challenge score, the tests to prove that a replay gives back the same battle. The work
# can be done in slices (`run_slice`) so a busy server keeps answering its players.

const DT: float = 1.0 / 60.0

var replay: Dictionary = {}
var game: LocalMatch
var tick: int = 0
var cursor: int = 0
var max_ticks: int = 0

# Starts the battle of `p_replay` (already cleaned). `limit` caps the ticks (0 = the replay's own).
func begin(p_replay: Dictionary, limit: int = 0) -> void:
	replay = p_replay
	max_ticks = limit
	var config: Dictionary = (replay.config as Dictionary).duplicate(true)
	config.lockstep = true
	game = LocalMatch.new()
	add_child(game)
	game.set_physics_process(false)
	game.start(config)

func finished() -> bool:
	return not game.running or (max_ticks > 0 and tick >= max_ticks)

# Runs up to `count` ticks; true when the battle is over (or the limit was reached).
func run_slice(count: int) -> bool:
	var inputs: Array = replay.inputs
	for i in range(count):
		if finished():
			return true
		while cursor < inputs.size() and int(inputs[cursor][0]) <= tick:
			if int(inputs[cursor][0]) == tick:
				game.apply_input(int(inputs[cursor][1]), str(inputs[cursor][2]), inputs[cursor][3])
			cursor += 1
		game.step(DT)
		tick += 1
	return finished()

func run_all() -> void:
	while not run_slice(600):
		pass
