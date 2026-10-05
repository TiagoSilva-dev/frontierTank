extends SceneTree

# Unbreakable floor + destructible platforms (maps with "hard" terrain pieces) and the
# four maps that use them: China, Japan, Egypt and space.

const NEW_MAPS: Array = ["pagode_dragoes", "jardim_sakura", "vale_piramides", "estacao_orbital"]

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func start(game: LocalMatch, map: String, seed_value: int = 7, teams: int = 1) -> void:
	var left: Array = []
	var right: Array = []
	for i in range(teams):
		left.append({"name": "A%d" % i, "human": i == 0, "weapon": i % 3, "level": 10})
		right.append({"name": "B%d" % i, "weapon": (i + 1) % 3, "level": 10})
	game.start({"mode": "pvp", "map": map, "seed": seed_value, "turn_seconds": 10, "teams": [left, right]})

func solid_columns(terrain: DestructibleTerrain, y: float) -> int:
	var count: int = 0
	for x in range(0, int(terrain.world_size.x), 10):
		if terrain.solid(Vector2(x, y)):
			count += 1
	return count

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	var balance: Dictionary = game.balance
	for id: String in NEW_MAPS:
		var entry: Dictionary = game.find_map(id)
		check(entry.id == id and not entry.get("pve_only", false), "%s is a PvP map" % id)
		check(ResourceLoader.exists(str(entry.bg)) and ResourceLoader.exists("res://assets/maps/thumbs/%s.png" % id), "%s has a backdrop and a thumbnail" % id)
		start(game, id)
		var terrain: DestructibleTerrain = game.terrain
		var height: float = terrain.world_size.y
		var width: int = int(terrain.world_size.x)
		check(solid_columns(terrain, height - 30.0) == int(ceil(width / 10.0)), "%s: the floor covers the whole width (nobody falls into the void)" % id)
		var floor_y: float = terrain.surface_y(40.0, 900.0)
		var before: PackedByteArray = terrain.mask.get_data()
		var removed: int = terrain.crater(Vector2(width * 0.5, height - 40.0), 160.0)
		check(removed == 0 and terrain.mask.get_data() == before, "%s: a crater on the floor removes nothing" % id)
		# Platforms: find a column whose top is above the floor line and dig it away.
		var dug: int = 0
		var column: float = 0.0
		for x in range(0, width, 20):
			if terrain.surface_y(float(x)) < floor_y - 200.0:
				column = float(x)
				break
		check(column > 0.0, "%s has platforms above the floor" % id)
		var top: float = terrain.surface_y(column)
		dug = terrain.crater(Vector2(column, top + 20.0), 70.0)
		check(dug > 0 and terrain.surface_y(column) > top, "%s: platforms can still be destroyed" % id)
		# A blast that reaches both leaves the floor whole.
		var floor_top: float = terrain.surface_y(column, floor_y - 40.0)
		terrain.crater(Vector2(column, floor_top), 200.0)
		check(terrain.surface_y(column, floor_y - 40.0) == floor_top, "%s: the floor survives a blast on its surface" % id)
		# Everyone starts on solid ground.
		start(game, id, 11, 2)
		var grounded: bool = true
		for fighter in game.fighters:
			grounded = grounded and game.terrain.solid(fighter.position + Vector2(0, 2)) and fighter.position.x > 24 and fighter.position.x < width - 24
		check(grounded, "%s: all four fighters spawn on solid ground inside the map" % id)
	# Same seed, same map: the stamped hard mask and the match stay identical.
	start(game, "vale_piramides", 21)
	var first: PackedByteArray = game.terrain.mask.get_data()
	var first_hard: PackedByteArray = game.terrain.hard.duplicate()
	start(game, "vale_piramides", 21)
	check(first == game.terrain.mask.get_data() and first_hard == game.terrain.hard, "same seed, same map: identical terrain and bedrock")
	# Full automatic battles: they finish and the floor is intact at the end.
	for id: String in NEW_MAPS:
		start(game, id, 33)
		var floor_before: PackedByteArray = game.terrain.hard.duplicate()
		var floor_pixels: int = 0
		for value in floor_before:
			floor_pixels += value
		game.set_auto_play(true)
		var frames: int = 0
		while game.running and frames < 60 * 600:
			game._physics_process(1.0 / 60)
			frames += 1
		var intact: bool = true
		var hard: PackedByteArray = game.terrain.hard
		var mask: Image = game.terrain.mask
		for i in range(0, hard.size(), 7):
			if hard[i] != 0 and mask.get_pixel(i % game.terrain.width, i / game.terrain.width).a < 0.5:
				intact = false
				break
		check(not game.running and floor_pixels > 0 and intact, "%s: automatic battle finishes (%d turns) and the bedrock is intact" % [id, game.round_number])
	check(balance.maps.size() >= 16, "the four new maps joined the pool")
	game.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
