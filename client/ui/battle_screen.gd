class_name BattleScreen
extends Control

# Partida: the battlefield renders in a SubViewport with a following camera; the
# HUD, minimap and results sit on top in screen space.

var app: Node
var config: Dictionary = {}
var game: LocalMatch
var hud: BattleHUD
var viewport: SubViewport
var world: Node2D
var camera: Camera2D
var backdrop: Node2D
var background: Texture2D
var effects: Node2D
var manual_focus: Vector2 = Vector2.ZERO
var manual_time: float = 0.0
var shake: float = 0.0
var dragging: bool = false
var end_timer: float = -1.0
var results: ResultScreen
var summary: Dictionary = {}
var explosion: Texture2D = preload("res://assets/effects/explosao.png")

func _ready() -> void:
	size = Vector2(1280, 720)
	var container: SubViewportContainer = SubViewportContainer.new()
	container.size = size
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.handle_input_locally = false
	container.add_child(viewport)
	var sky: CanvasLayer = CanvasLayer.new()
	sky.layer = -1
	viewport.add_child(sky)
	backdrop = Node2D.new()
	backdrop.draw.connect(draw_backdrop)
	sky.add_child(backdrop)
	world = Node2D.new()
	viewport.add_child(world)
	game = LocalMatch.new()
	world.add_child(game)
	effects = Node2D.new()
	world.add_child(effects)
	camera = Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	game.blast.connect(show_blast)
	game.damage_text.connect(show_damage)
	game.special.connect(show_special)
	game.effect.connect(show_effect)
	game.shot_fired.connect(func(_projectile: TankProjectile) -> void: app.audio.tone(190, 0.22))
	game.turn_started.connect(on_turn)
	game.finished.connect(on_finished)
	hud = BattleHUD.new()
	hud.screen = self
	hud.game = game
	add_child(hud)
	game.announce.connect(hud.log_line)
	game.start(config)
	background = load(str(game.map.bg))
	var world_size: Vector2 = game.terrain.world_size
	camera.limit_left = 0
	camera.limit_right = int(world_size.x)
	camera.limit_top = -260
	camera.limit_bottom = int(world_size.y) + 220
	camera.position = focus_point()
	camera.reset_smoothing()
	hud.build()

func focus_point() -> Vector2:
	if manual_time > 0:
		return manual_focus
	if game.state == LocalMatch.State.PROJECTILE_FLYING and not game.projectiles.is_empty():
		var projectile: TankProjectile = game.projectiles[0]
		return projectile.position + projectile.velocity * 0.15
	if game.state == LocalMatch.State.RESOLVING_DAMAGE and game.last_impact != Vector2.ZERO and not game.passed:
		return game.last_impact + Vector2(0, -60)
	return game.active().position + Vector2(0, -110)

func focus_on(point: Vector2, seconds: float = 3.0) -> void:
	manual_focus = point
	manual_time = seconds

func _process(delta: float) -> void:
	if not is_instance_valid(game) or game.fighters.is_empty():
		return
	for animation in get_tree().get_nodes_in_group("pixel_animations"):
		animation.frozen = game.paused
	manual_time = maxf(0.0, manual_time - delta)
	var target: Vector2 = focus_point()
	var speed: float = 9.0 if game.state == LocalMatch.State.PROJECTILE_FLYING else 5.0
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * speed))
	var half: Vector2 = Vector2(640, 360) / camera.zoom
	camera.position.x = clampf(camera.position.x, half.x, maxf(half.x, game.terrain.world_size.x - half.x))
	# Allow some void below the map so deep craters are not hidden behind the HUD.
	camera.position.y = clampf(camera.position.y, -260 + half.y, maxf(-260 + half.y, game.terrain.world_size.y + 220 - half.y))
	if shake > 0:
		shake = maxf(0.0, shake - delta)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 22.0
	else:
		camera.offset = Vector2.ZERO
	backdrop.queue_redraw()
	if end_timer > 0:
		end_timer -= delta
		if end_timer <= 0:
			show_results()

func camera_rect() -> Rect2:
	return Rect2(camera.position - Vector2(640, 360), Vector2(1280, 720))

func draw_backdrop() -> void:
	if background == null:
		return
	var world_size: Vector2 = game.terrain.world_size
	# Cover the screen with the painting and drift it slightly with the camera.
	var cover: Vector2 = Vector2(1280, 720) * 1.18
	var progress: Vector2 = Vector2(
		clampf((camera.position.x - 640) / maxf(1, world_size.x - 1280), 0, 1),
		clampf((camera.position.y + 260 - 360) / maxf(1, world_size.y + 260 - 720), 0, 1))
	var offset: Vector2 = -(cover - Vector2(1280, 720)) * progress
	backdrop.draw_texture_rect(background, Rect2(offset, cover), false)
	backdrop.draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.08, 0.16, 0.12))

func show_blast(point: Vector2, radius: float) -> void:
	app.audio.tone(80, 0.45, true)
	shake = 0.35
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = explosion
	sprite.position = point
	sprite.scale = Vector2.ONE * radius / 45.0
	effects.add_child(sprite)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", sprite.scale * 1.65, 0.4)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback(sprite.queue_free)

func show_special(point: Vector2, path: String) -> void:
	app.audio.tone(880, 0.3)
	hud.flash("POW!", Color("ffd04a"))
	if path == "" or not ResourceLoader.exists(path):
		return
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path)
	sprite.position = point
	sprite.scale = Vector2.ONE * 1.5
	effects.add_child(sprite)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE * 3.0, 0.7)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(sprite.queue_free)

func show_effect(kind: String, point: Vector2, data: Dictionary) -> void:
	# Weapon POW visuals; each draws itself on a throwaway node and fades out.
	var node: WeaponEffect = WeaponEffect.new()
	node.kind = kind
	node.data = data
	node.position = point
	node.top = camera.position.y - 420.0
	effects.add_child(node)
	match kind:
		"lightning":
			app.audio.tone(1200, 0.25, true)
			shake = 0.5
		"beam":
			app.audio.tone(980, 0.4)
		"bull":
			app.audio.tone(120, 0.5, true)
			shake = 0.7
		"heal", "hearts":
			app.audio.tone(1040, 0.2)

func show_damage(point: Vector2, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.position = point + Vector2(-30, -50)
	label.add_theme_font_override("font", UiKit.font(true))
	label.add_theme_font_size_override("font_size", UiKit.fs(30))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("2a0a04"))
	label.add_theme_constant_override("outline_size", 8)
	effects.add_child(label)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 64, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)

func on_turn(fighter: TankFighter) -> void:
	manual_time = 0
	if fighter.player_id == game.local_id and not game.auto_play:
		app.audio.tone(720, 0.12)
		hud.flash("SUA VEZ!", Color("9aff7a"))

func on_finished(winner: int) -> void:
	summary = app.battle_finished(game)
	hud.show_outcome(winner == game.local().team, winner < 0)
	app.audio.tone(660 if summary.won else 220, 0.75)
	end_timer = 2.6

func show_results() -> void:
	end_timer = -1
	if summary.is_empty():
		summary = app.last_summary
	if is_instance_valid(results):
		return
	hud.hide()
	results = ResultScreen.new()
	results.app = app
	results.summary = summary
	results.game = game
	add_child(results)

func show_cards() -> void:
	show_results()
	results.show_cards()

func toggle_pause() -> void:
	if not game.running:
		return
	game.paused = not game.paused
	if game.paused and game.state == LocalMatch.State.PLAYER_CHARGING and not game.is_ai_controlled(game.active()):
		# Pausing cancels a charge so a released key cannot leave it stuck.
		game.state = LocalMatch.State.PLAYER_AIMING
		game.power = 0
	hud.set_paused(game.paused)

func forfeit() -> void:
	for fighter in game.fighters:
		if fighter.team == game.local().team:
			fighter.hp = 0
			fighter.hide_body()
	game.paused = false
	hud.set_paused(false)
	game.evaluate_winner()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo or not is_instance_valid(game):
		return
	var key: Key = event.physical_keycode
	if key == KEY_ESCAPE and event.pressed:
		toggle_pause()
		return
	if key == KEY_SPACE:
		if event.pressed:
			game.charge()
		else:
			game.release_shot()
		return
	if not event.pressed:
		return
	if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < game.balance.items.size():
		game.use_item(str(game.balance.items[key - KEY_1].id))
	elif key == KEY_Z or key == KEY_X or key == KEY_C:
		game.use_tool([KEY_Z, KEY_X, KEY_C].find(key))
	elif key == KEY_B:
		game.activate_pow()
	elif key == KEY_F:
		game.toggle_fly()
	elif key == KEY_V:
		game.use_aux()
	elif key == KEY_P:
		game.pass_turn()
	elif key == KEY_Q:
		game.flip_aim()

func _gui_input(event: InputEvent) -> void:
	# Right or middle drag pans the camera across the map, like dragging the view.
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		dragging = event.pressed
		if dragging:
			focus_on(camera.position, 4.0)
	elif event is InputEventMouseMotion and dragging:
		focus_on(manual_focus - event.relative, 4.0)
