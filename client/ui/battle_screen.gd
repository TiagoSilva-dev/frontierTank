class_name BattleScreen
extends Control

# Partida: the battlefield renders in a SubViewport with a following camera; the
# HUD, minimap and results sit on top in screen space. Also the battle's sound: each
# weapon's firing and impact, POW, skills being consumed, countdown and stingers.

const SKILL_SOUNDS: Dictionary = {
	"multi": "skill_multi", "power": "skill_power", "powmax": "skill_powmax", "heal": "tool_heal", "energy": "tool_energy",
	"shield": "tool_shield", "plane": "fire_plane", "angel": "aux_angel", "pow": "pow_activate",
}
const EFFECT_SOUNDS: Dictionary = {
	"lightning": "special_lightning", "beam": "special_beam", "bull": "special_bull", "heal": "special_heal",
	"hearts": "special_hearts", "tornado": "special_tornado", "summon": "pow_activate", "warp": "special_tornado",
	"wave": "battle_start",
}

var app: Node
var config: Dictionary = {}
var game: LocalMatch
var hud: BattleHUD
var viewport: SubViewport
var world: Node2D
var camera: Camera2D
var backdrop: Node2D
var background: Texture2D
var ambience: Ambience
var effects: Node2D
var manual_focus: Vector2 = Vector2.ZERO
var manual_time: float = 0.0
var shake: float = 0.0
var dragging: bool = false
var end_timer: float = -1.0
var results: ResultScreen
var summary: Dictionary = {}
var trails: ShotTrails
var pow_auras: Dictionary = {}
var skill_queue: Dictionary = {}
var alive: Dictionary = {}
var last_tick: int = -1
var kick: float = 0.0
var kick_factor: float = 1.0
var transition: PhaseTransition
# Online (backend 0.11): this copy runs in lockstep with the server (LockstepDriver); the
# local controls become intents, the end of the battle and the rewards come from the server.
var online: bool = false
var match_id: int = 0
var resume: Dictionary = {}
var driver: LockstepDriver
var server_end: Dictionary = {}
var phase_report: Dictionary = {}
var finished_here: bool = false
var ending_shown: bool = false
var end_wait: float = -1.0
var menu_open: bool = false
var sent_move: float = 0.0
var sent_aim: float = 0.0
var aim_base: float = 0.0
var aim_clock: float = 0.0
var catch_up: Label

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
	# Dashed flight lines sit behind the ground, fighters and projectiles.
	trails = ShotTrails.new()
	world.add_child(trails)
	# Weather in front of the battlefield (snow, embers, dust), under the HUD.
	var weather: CanvasLayer = CanvasLayer.new()
	weather.layer = 1
	viewport.add_child(weather)
	ambience = Ambience.new()
	weather.add_child(ambience)
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
	game.pow_impact.connect(show_pow_impact)
	# Deferred: secondary projectiles get their stage right after they are created.
	game.shot_fired.connect(func(projectile: TankProjectile) -> void: on_shot.call_deferred(projectile))
	game.skill_used.connect(on_skill)
	game.turn_started.connect(on_turn)
	game.finished.connect(on_finished)
	hud = BattleHUD.new()
	hud.screen = self
	hud.game = game
	add_child(hud)
	game.announce.connect(hud.log_line)
	game.start(config)
	if online:
		game.remote = send_intent
		driver = LockstepDriver.new()
		driver.game = game
		add_child(driver)
		driver.desynced.connect(func(tick: int) -> void: app.net.send_kind("desync", {"m": match_id, "tick": tick}))
		if resume.has("history"):
			# Back in a battle already under way: simulate it again up to now.
			driver.receive({"i": resume.history, "u": resume.u})
	background = load(str(game.map.bg))
	ambience.setup(str(game.map.get("ambience", "")), camera)
	var world_size: Vector2 = game.terrain.world_size
	camera.limit_left = 0
	camera.limit_right = int(world_size.x)
	camera.limit_top = -260
	camera.limit_bottom = int(world_size.y) + 220
	camera.position = focus_point()
	camera.reset_smoothing()
	hud.build()
	for fighter in game.fighters:
		alive[fighter.player_id] = fighter.hp > 0
	app.audio.play("battle_start", -2.0)

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
	update_sound()
	update_pow_charge()
	# POW punch: a quick zoom-in that eases back (kept on top of any external zoom).
	camera.zoom /= kick_factor
	kick = maxf(0.0, kick - delta)
	var u: float = 1.0 - kick / 0.5
	kick_factor = 1.0 + 0.09 * minf(1.0, u * 8.0) * (1.0 - u) if kick > 0.0 else 1.0
	camera.zoom *= kick_factor
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
	if online:
		online_controls(delta)
		if end_wait > 0.0:
			end_wait -= delta
			if end_wait <= 0.0 and not finished_here:
				# The server finished long ago and this copy did not: trust the server.
				finished_here = true
				driver.game = null
				settle_online()
		show_catch_up()

func camera_rect() -> Rect2:
	return Rect2(camera.position - Vector2(640, 360), Vector2(1280, 720))

func draw_backdrop() -> void:
	if background == null:
		return
	var world_size: Vector2 = game.terrain.world_size
	# The painting is scaled by a whole number (2x for the 680x380 maps) so its pixels
	# stay square; the spare margin drifts with the camera in whole art pixels.
	var art: Vector2 = background.get_size()
	var k: float = maxf(ceilf(1280.0 / art.x), ceilf(720.0 / art.y))
	var cover: Vector2 = art * k
	var progress: Vector2 = Vector2(
		clampf((camera.position.x - 640) / maxf(1, world_size.x - 1280), 0, 1),
		clampf((camera.position.y + 260 - 360) / maxf(1, world_size.y + 260 - 720), 0, 1))
	var offset: Vector2 = (-(cover - Vector2(1280, 720)) * progress / k).round() * k
	backdrop.draw_texture_rect(background, Rect2(offset, cover), false)
	# Push the painting back so the ground and fighters read first ("dim" per map).
	backdrop.draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.08, 0.16, float(game.map.get("dim", 0.12))))

func update_sound() -> void:
	# Charge hum (quieter for others), countdown ticks and fighters going down.
	var charging: bool = game.running and not game.paused and game.state == LocalMatch.State.PLAYER_CHARGING
	var local_turn: bool = game.active_id == game.local_id and not game.auto_play
	app.audio.set_charge(charging, game.power, -4.0 if local_turn else -11.0)
	if game.can_act() and game.remaining < 3.5 and game.remaining > 0.0:
		var second: int = ceili(game.remaining)
		if second != last_tick:
			last_tick = second
			app.audio.play("tick", 0.0, 1.0 + (3 - second) * 0.08)
	else:
		last_tick = -1
	for fighter in game.fighters:
		if bool(alive.get(fighter.player_id, true)) and fighter.hp <= 0:
			app.audio.play("fighter_down", -2.0, 1.0, 300)
		alive[fighter.player_id] = fighter.hp > 0

func update_pow_charge() -> void:
	# POW charge phase: the armed fighter's aura grows with the force bar.
	var aura: Variant = pow_auras.get(game.active_id)
	if aura != null and is_instance_valid(aura):
		var charging: bool = game.state == LocalMatch.State.PLAYER_CHARGING and game.turn_pow
		aura.charge = clampf(game.power / 100.0, 0.05, 1.0) if charging else 0.0

func fire_sound(shooter: TankFighter, projectile: TankProjectile) -> String:
	if projectile.fly:
		return "fire_plane"
	if shooter.is_monster:
		return "fire_boss"
	var sound: String = "fire_" + str(shooter.weapon.get("id", ""))
	return sound if app.audio.has_sound(sound) else "fire_quebra_tijolos"

func on_shot(projectile: TankProjectile) -> void:
	if not is_instance_valid(projectile) or not is_instance_valid(game):
		return
	match projectile.stage:
		"drop":
			app.audio.play("drop_whistle", -3.0, 1.0, 250)
			return
		"fragment":
			app.audio.play("split_pop", -2.0, 1.0, 120)
			return
		"return":
			app.audio.play("boomerang_return")
			return
	var shooter: TankFighter = game.fighters[projectile.owner_id]
	var mine: bool = shooter.player_id == game.local_id
	var color: Color = Color.WHITE if mine else (Color("a8e0ff") if shooter.team == game.local().team else Color("ffb4a0"))
	trails.track(projectile, shooter.player_id, game.round_number, mine, color)
	# One sound per volley (three balls fire together), each weapon its own.
	app.audio.play(fire_sound(shooter, projectile), 0.0, randf_range(0.96, 1.04), 90)
	clear_pow_aura(shooter)

func on_skill(fighter: TankFighter, info: Dictionary) -> void:
	# Items used together (bots pick a whole combo at once) are consumed one after another.
	var now: float = Time.get_ticks_msec() / 1000.0
	var start: float = maxf(now, float(skill_queue.get(fighter.player_id, 0.0)))
	skill_queue[fighter.player_id] = start + 0.32
	if start - now <= 0.01:
		spawn_skill(fighter, info)
	else:
		get_tree().create_timer(start - now).timeout.connect(spawn_skill.bind(fighter, info))
	if str(info.get("kind", "")) == "pow":
		show_pow_aura(fighter)

func spawn_skill(fighter: TankFighter, info: Dictionary) -> void:
	if not is_instance_valid(fighter) or not is_instance_valid(effects) or fighter.hp <= 0:
		return
	var fx: SkillFx = SkillFx.new()
	fx.fighter = fighter
	var icon: String = str(info.get("icon", ""))
	fx.icon = load(icon) if icon.begins_with("res://") and ResourceLoader.exists(icon) else PixelIcons.get_icon(icon)
	fx.title = str(info.get("name", ""))
	var kind: String = str(info.get("kind", "power"))
	fx.color = SkillFx.color_for(kind)
	# Icons still showing push the new one aside.
	var busy: int = effects.get_children().filter(func(node: Node) -> bool: return node is SkillFx and node.fighter == fighter).size()
	fx.offset_x = [0.0, 88.0, -88.0, 176.0, -176.0][busy % 5]
	effects.add_child(fx)
	app.audio.play(str(SKILL_SOUNDS.get(kind, "skill_power")), -2.0, 1.0, 60)

func show_pow_aura(fighter: TankFighter) -> void:
	clear_pow_aura(fighter)
	var aura: PowFx = PowFx.new()
	aura.mode = "aura"
	aura.fighter = fighter
	aura.weapon_id = str(fighter.weapon.get("id", ""))
	aura.tint = Color(str(fighter.weapon.get("color", "ffd04a"))).lerp(Color("ffd04a"), 0.5)
	fighter.add_child(aura)
	pow_auras[fighter.player_id] = aura

func clear_pow_aura(fighter: TankFighter) -> void:
	var aura: Variant = pow_auras.get(fighter.player_id)
	if aura != null and is_instance_valid(aura):
		aura.queue_free()
		fighter.set_pow_armed(false)
	pow_auras.erase(fighter.player_id)

func show_blast(point: Vector2, radius: float) -> void:
	var size_name: String = "explosion_small" if radius < 44.0 else ("explosion_medium" if radius < 70.0 else "explosion_big")
	app.audio.play(size_name, 0.0, randf_range(0.94, 1.05), 60)
	app.audio.play("impact_" + str(game.active().weapon.get("id", "")), -2.0, 1.0, 90)
	shake = 0.35
	var blast: ImpactFx = ImpactFx.new()
	blast.radius = radius
	blast.debris = game.terrain.last_debris.duplicate()
	blast.position = point
	effects.add_child(blast)

func show_special(point: Vector2, _path: String) -> void:
	# The POW shot: burst of light at the fighter, "POW!" banner, zoom punch and shake.
	var shooter: TankFighter = game.active()
	var tint: Color = Color(str(shooter.weapon.get("color", "ffd04a"))).lerp(Color("ffd04a"), 0.35)
	app.audio.play("pow_fire")
	hud.pow_banner(tr(str(shooter.weapon.get("pow", {}).get("name", ""))), tint)
	# The weapon's own animated POW art (assets/effects/pow/<weapon>/) bursts behind it.
	var burst: PowFx = PowFx.new()
	burst.mode = "burst"
	burst.tint = tint
	burst.weapon_id = str(shooter.weapon.get("id", ""))
	burst.position = point
	effects.add_child(burst)
	clear_pow_aura(shooter)
	# Fire: the kick of the special pushes the fighter back.
	shooter.recoil(12.0, 0.4)
	shake = 0.45
	kick = 0.5

func show_pow_impact(point: Vector2, radius: float, weapon_id: String) -> void:
	# The POW lands: each weapon's own shape, colours and particles, a heavy shake and
	# a second camera punch (the match itself holds for LocalMatch.hitstop).
	var impact: PowImpact = PowImpact.new()
	impact.weapon_id = weapon_id
	impact.radius = radius
	impact.position = point
	impact.top = camera.position.y - 420.0
	effects.add_child(impact)
	app.audio.play("explosion_big", 1.0, 0.9, 120)
	shake = 0.6
	kick = 0.4

func show_effect(kind: String, point: Vector2, data: Dictionary) -> void:
	# Weapon POW visuals; each draws itself on a throwaway node and fades out.
	var node: WeaponEffect = WeaponEffect.new()
	node.kind = kind
	node.data = data
	node.position = point
	node.top = camera.position.y - 420.0
	effects.add_child(node)
	# Dom de Anjo heals through the same effect but has its own angelic chord.
	app.audio.play("aux_angel" if data.get("aux", false) else str(EFFECT_SOUNDS.get(kind, "")), 0.0, 1.0, 120)
	match kind:
		"lightning":
			shake = 0.5
		"bull":
			shake = 0.7

func show_damage(point: Vector2, text: String, color: Color) -> void:
	if text.begins_with(tr("CRÍTICO")):
		app.audio.play("critical", -1.0, 1.0, 150)
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
	# An armed POW that was never fired (PASS, time out) is gone with the turn.
	for id in pow_auras.keys():
		clear_pow_aura(game.fighters[id])
	if game.skip_turn:
		app.audio.play("special_freeze")
	elif fighter.player_id == game.local_id and not game.auto_play:
		app.audio.play("your_turn", -3.0)
		hud.flash(tr("SUA VEZ!"), Color("9aff7a"))

func on_finished(winner: int) -> void:
	if online:
		finished_here = true
		settle_online()
		return
	if game.pve and app.run != null and winner == game.local().team and app.run.has_next_phase():
		# Instance phase won: drops now, a transition screen, then the next phase.
		var report: Dictionary = app.phase_cleared(game)
		hud.flash(tr("FASE CONCLUÍDA!"), Color("ffd04a"))
		app.audio.set_charge(false, 0.0)
		app.audio.play("victory", -4.0)
		get_tree().create_timer(1.6).timeout.connect(show_transition.bind(report))
		return
	summary = app.battle_finished(game)
	hud.show_outcome(winner == game.local().team, winner < 0)
	app.audio.set_charge(false, 0.0)
	app.audio.play_music("", 0.8)
	app.audio.play("victory" if summary.won else "defeat")
	end_timer = 2.6

func show_transition(report: Dictionary) -> void:
	if not is_instance_valid(hud) or is_instance_valid(transition):
		return
	hud.hide()
	transition = PhaseTransition.new()
	transition.app = app
	transition.report = report
	add_child(transition)

func show_results() -> void:
	end_timer = -1
	if summary.is_empty():
		summary = app.last_summary
	if is_instance_valid(results):
		return
	hud.hide()
	app.audio.play_music("lobby", 2.5)
	results = ResultScreen.new()
	results.app = app
	results.summary = summary
	results.game = game
	add_child(results)

func show_cards() -> void:
	show_results()
	results.show_cards()

func _exit_tree() -> void:
	if app != null and is_instance_valid(app.audio):
		app.audio.set_charge(false, 0.0)

func toggle_pause() -> void:
	if online:
		# No pausing online: only the options (sound, give up) open over the battle.
		menu_open = not menu_open
		hud.set_paused(menu_open)
		return
	if not game.running:
		return
	game.paused = not game.paused
	if game.paused and game.state == LocalMatch.State.PLAYER_CHARGING and not game.is_ai_controlled(game.active()):
		# Pausing cancels a charge so a released key cannot leave it stuck.
		game.state = LocalMatch.State.PLAYER_AIMING
		game.power = 0
	hud.set_paused(game.paused)

func forfeit() -> void:
	if online:
		app.net.send_kind("match_leave")
		app.room = {}
		app.show_hall()
		return
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
			game.release()
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

# ---------- online (backend 0.11) ----------

func send_intent(action: String, data: Dictionary) -> void:
	app.net.send_kind("in", {"m": match_id, "a": action, "d": data})

func on_net(message: Dictionary) -> void:
	if int(message.get("m", -1)) != match_id:
		return
	match str(message.get("t", "")):
		"ticks":
			driver.receive(message)
		"phase_end":
			app.apply_profile(message.profile)
			phase_report = message.report
			settle_online()
		"match_end":
			app.apply_profile(message.profile)
			server_end = message
			settle_online()
		"cards":
			if is_instance_valid(results):
				results.reveal_online(message)

func in_phase_break() -> bool:
	return not phase_report.is_empty()

# Both the server's word and this copy's end are needed; whichever comes second shows
# the phase transition or the outcome.
func settle_online() -> void:
	if not finished_here:
		if (not server_end.is_empty() or not phase_report.is_empty()) and end_wait < 0.0:
			end_wait = 8.0
		return
	if ending_shown or (server_end.is_empty() and phase_report.is_empty()):
		return
	ending_shown = true
	app.audio.set_charge(false, 0.0)
	if not phase_report.is_empty():
		hud.flash(tr("FASE CONCLUÍDA!"), Color("ffd04a"))
		app.audio.play("victory", -4.0)
		get_tree().create_timer(1.6).timeout.connect(show_transition.bind(phase_report))
		return
	summary = server_end.summary
	app.last_summary = summary
	hud.show_outcome(bool(summary.get("won", false)), bool(summary.get("draw", false)))
	app.audio.play_music("", 0.8)
	app.audio.play("victory" if summary.get("won", false) else "defeat")
	end_timer = 2.6

static func axis(negative: Key, positive: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))

# Arrow keys online: sent as intents when they change. The aim is predicted here so the
# dial and the aim line answer at once, and each change carries the exact angle seen.
func online_controls(delta: float) -> void:
	if not is_instance_valid(game) or game.fighters.is_empty():
		return
	var me: TankFighter = game.local()
	var focus: Control = get_viewport().gui_get_focus_owner()
	var mine: bool = game.can_act() and not (focus is LineEdit) and not menu_open
	var walk: float = clampf(axis(KEY_A, KEY_D) + axis(KEY_LEFT, KEY_RIGHT), -1.0, 1.0) if mine else 0.0
	var aim: float = clampf(axis(KEY_S, KEY_W) + axis(KEY_DOWN, KEY_UP), -1.0, 1.0) if mine else 0.0
	if not mine:
		sent_move = 0.0
		sent_aim = 0.0
		if not is_nan(me.shown_angle) and (game.active_id != game.local_id or game.aim_input == 0.0):
			me.shown_angle = NAN
			me.queue_redraw()
		return
	if walk != sent_move:
		sent_move = walk
		game.send_intent("move", {"d": walk})
	if aim != sent_aim:
		var seen: float = snappedf(me.drawn_angle(), 0.01)
		game.send_intent("aim", {"d": aim, "angle": seen})
		sent_aim = aim
		aim_base = seen
		aim_clock = 0.0
		me.shown_angle = seen
	if aim != 0.0:
		aim_clock += delta
		me.shown_angle = clampf(aim_base + aim * 30.0 * aim_clock, me.angle_range.x, me.angle_range.y)
		me.queue_redraw()
	elif not is_nan(me.shown_angle) and game.aim_input == 0.0 and absf(me.angle - me.shown_angle) < 0.02:
		me.shown_angle = NAN
		me.queue_redraw()

func show_catch_up() -> void:
	# Coming back to a battle (or a long hiccup): the copy is replaying to catch up.
	var catching: bool = driver != null and driver.catching_up()
	if catching and not is_instance_valid(catch_up):
		catch_up = UiKit.label(self, tr("Sincronizando a batalha…"), Rect2(390, 300, 500, 60), 28, Color("fff0c0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	elif not catching and is_instance_valid(catch_up):
		catch_up.queue_free()
