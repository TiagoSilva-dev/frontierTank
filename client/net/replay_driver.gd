class_name ReplayDriver
extends Node

# Plays a replay on the screen: the intents are fed to the battle at the ticks they were
# stamped, at 1x, 2x or 4x. Pausing is the battle's own pause (`game.paused`), so animations
# freeze with it and no intent is lost while it lasts.

signal finished

const DT: float = 1.0 / 60.0

var game: LocalMatch
var inputs: Array = []
var total: int = 0
var tick: int = 0
var cursor: int = 0
var speed: float = 1.0
var budget: float = 0.0
var done: bool = false

func setup(p_game: LocalMatch, replay: Dictionary) -> void:
	game = p_game
	inputs = replay.inputs
	total = int(replay.get("ticks", 0))

func progress() -> float:
	return 1.0 if done else clampf(float(tick) / float(maxi(1, total)), 0.0, 1.0)

func _physics_process(_delta: float) -> void:
	if game == null or not is_instance_valid(game) or done or game.paused:
		return
	budget += speed
	var steps: int = int(budget)
	budget -= float(steps)
	for i in range(steps):
		if not game.running:
			break
		advance()

func advance() -> void:
	while cursor < inputs.size() and int(inputs[cursor][0]) <= tick:
		if int(inputs[cursor][0]) == tick:
			game.apply_input(int(inputs[cursor][1]), str(inputs[cursor][2]), inputs[cursor][3])
		cursor += 1
	game.step(DT)
	tick += 1
	if not game.running and not done:
		done = true
		finished.emit()
