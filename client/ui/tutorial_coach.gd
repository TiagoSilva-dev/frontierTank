class_name TutorialCoach
extends Control

# The coach of the training battle (0.21): a card under the portrait with the current
# lesson, a pulsing frame around the HUD piece the lesson is about, and the script that
# moves on when the player does what it asks (see shared/balance/tutorial.json). The
# training is local and not lockstep, so the coach is free to touch the match: it keeps
# the turn clock from running out, gives the POW when its lesson comes and heals the
# dummy between turns until the last lesson.

var screen: BattleScreen
var game: LocalMatch
var hud: BattleHUD
var dummy: TankFighter
var me: TankFighter
var index: int = 0
var flags: Dictionary = {"moved": false, "aimed": false, "hit": false, "plus2": false, "pow": false, "done": false}
var key_pressed: bool = false
var angle_start: float = 0.0
var shots: int = 0
var shots_seen: int = 0
var misses: int = 0
var hint: String = ""
var time: float = 0.0
var card: Control
var title_label: Label
var body_label: Label
var footer_label: Label
var counter_label: Label
var next_button: Button
var done_box: Control
# The dummy may fall only from the start of a turn of the last lesson (never mid-shot of
# the lesson before it).
var floor_open: bool = false

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	game = screen.game
	hud = screen.hud
	me = game.local()
	for fighter in game.fighters:
		if fighter.rank == "totem":
			dummy = fighter
	dummy.hp_floor = 1
	angle_start = me.angle
	game.shot_fired.connect(on_shot)
	game.turn_started.connect(on_turn)
	build_card()
	if screen.app.args.has("step"):
		# Captures: start at a given lesson (--step=<n>, from 0).
		index = clampi(int(screen.app.args.step), 0, Tutorial.steps().size() - 1)
		if str(current().id) == "pow":
			me.pow_gauge = float(game.balance.pow_max)
	refresh()

func build_card() -> void:
	card = Control.new()
	card.position = Vector2(4, 156)
	card.size = Vector2(376, 176)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.draw.connect(func() -> void:
		var inner: Rect2 = HudPaint.frame(card, Rect2(Vector2.ZERO, card.size), 0.35 + 0.15 * sin(time * 3.0))
		HudPaint.well(card, inner, Color(0.03, 0.04, 0.07, 0.92), Color(0.08, 0.1, 0.16, 0.92)))
	add_child(card)
	counter_label = UiKit.label(card, "", Rect2(286, 8, 80, 22), 14, Color("c8d8ff"), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	title_label = UiKit.label(card, "", Rect2(14, 8, 270, 26), 18, Color("ffd04a"), UiKit.INK)
	body_label = UiKit.label(card, "", Rect2(14, 38, 348, 96), 16, Color("fff0d0"), UiKit.INK)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_label = UiKit.label(card, "", Rect2(14, 142, 200, 24), 15, Color("9aff7a"), UiKit.INK)
	var skip: Button = UiKit.button(card, tr("PULAR TREINO"), Rect2(228, 138, 136, 30), screen.app.leave_tutorial, "button_blue", 14)
	skip.name = "TutorialSkip"
	skip.mouse_filter = Control.MOUSE_FILTER_STOP
	if TouchMode.active():
		# There is no ENTER on a phone: the lessons that wait for a key wait for this.
		next_button = UiKit.button(card, tr("AVANÇAR"), Rect2(14, 138, 136, 30), func() -> void: key_pressed = true, "button_green", 14)
		next_button.name = "TutorialNext"
		next_button.mouse_filter = Control.MOUSE_FILTER_STOP

func current() -> Dictionary:
	return Tutorial.steps()[mini(index, Tutorial.steps().size() - 1)]

func is_last() -> bool:
	return index >= Tutorial.steps().size() - 1

func refresh() -> void:
	var step: Dictionary = current()
	counter_label.text = "%d/%d" % [index + 1, Tutorial.steps().size()]
	title_label.text = tr(str(step.name))
	# On a phone the lessons talk about the buttons, not the keys.
	var text: String = tr(str(step.get("text_touch", step.text)) if TouchMode.active() else str(step.text))
	if str(step.id) == "shoot" and misses > 0:
		text = tr("Errou! A linha tracejada branca mostra o caminho do seu último tiro. Ajuste o ângulo ou a força e tente de novo.")
		if hint != "":
			text += "\n" + hint
	body_label.text = text
	var waiting: bool = str(step.get("wait", "")) == "key"
	footer_label.text = tr("ENTER: continuar") if waiting and not TouchMode.active() else ""
	if is_instance_valid(next_button):
		next_button.visible = waiting

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and is_instance_valid(card):
		key_pressed = true
		get_viewport().set_input_as_handled()

func on_shot(_projectile: TankProjectile) -> void:
	shots += 1
	if "plus2" in game.turn_items:
		flags.plus2 = true
	if game.turn_pow:
		flags.pow = true

func on_turn(fighter: TankFighter) -> void:
	if fighter != me:
		return
	update_flags()
	floor_open = is_last()
	var fired: bool = shots > shots_seen
	shots_seen = shots
	if fired and not flags.hit and str(current().id) == "shoot":
		misses += 1
		hint = shot_hint() if misses >= 2 else ""
		refresh()
	# Until the last lesson the dummy mends itself between turns.
	if not is_last() and dummy.hp < dummy.max_hp:
		dummy.hp = dummy.max_hp
		game.damage_text.emit(dummy.center() + Vector2(0, -40), tr("O boneco se recompõe"), Color("9aff7a"))

# The shot the AI would choose: shown after two misses.
func shot_hint() -> String:
	var scale: float = float(me.weapon.get("projectile", {}).get("wind_scale", 1.0))
	var solution: Vector3 = EnemyAI.choose_shot(me, dummy, game.terrain, game.wind * float(game.balance.wind_accel) * scale * game.wind_factor(me), game.balance)
	return tr("Dica: tente ângulo %d° e força %d%%.") % [roundi(solution.x), roundi(solution.y)]

func update_flags() -> void:
	if game.moved_distance >= 20.0:
		flags.moved = true
	if absf(me.angle - angle_start) >= 6.0:
		flags.aimed = true
	if dummy.hp < dummy.max_hp:
		flags.hit = true
	if game.state == LocalMatch.State.MATCH_FINISHED:
		flags.done = true

func _process(delta: float) -> void:
	time += delta
	if not is_instance_valid(card):
		return
	# Nobody should lose a lesson to the turn clock.
	if game.running and game.active_id == game.local_id and game.state in [LocalMatch.State.TURN_STARTED, LocalMatch.State.PLAYER_MOVING, LocalMatch.State.PLAYER_AIMING, LocalMatch.State.PLAYER_CHARGING]:
		game.remaining = maxf(game.remaining, 30.0)
	update_flags()
	dummy.hp_floor = 0 if floor_open else 1
	# Moves on through every lesson already satisfied (the player may be ahead of the coach).
	while not flags.done and not is_last():
		var step: Dictionary = current()
		var met: bool = flags.get(str(step.get("need", "")), false) if step.has("need") else key_pressed
		if not met:
			break
		advance()
	queue_redraw()
	card.queue_redraw()

func advance() -> void:
	var step: Dictionary = current()
	key_pressed = false
	if str(step.id) == "shoot":
		hud.flash(tr("ACERTOU!"), Color("9aff7a"))
		screen.app.audio.play("ui_confirm")
	elif step.has("need"):
		screen.app.audio.play("ui_confirm", -4.0)
	index += 1
	misses = 0
	hint = ""
	if str(current().id) == "pow" and not flags.pow:
		# The gauge starts empty: it is full for this lesson.
		me.pow_gauge = float(game.balance.pow_max)
	refresh()

# The pulsing frame around the HUD piece of the lesson.
func focus_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if flags.done:
		return rects
	for key: Variant in current().get("focus", []):
		var target: Control = null
		match str(key):
			"gauges":
				target = hud.gauges
			"dial":
				target = hud.dial
			"clock":
				target = hud.clock
			"force":
				target = hud.force
			"skill1":
				# On a phone the skills sit in a drawer: the lesson points at its button.
				target = hud.touch.drawer_toggle if hud.touch != null and not hud.touch.drawer_open else hud.item_buttons[0]
			"pow":
				target = hud.pow_button
		if target != null:
			rects.append(target.get_global_rect())
	return rects

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(time * 5.0)
	for rect: Rect2 in focus_rects():
		var grown: Rect2 = rect.grow(3.0 + 4.0 * pulse)
		draw_rect(grown.grow(3.0), Color(1.0, 0.82, 0.3, 0.18 + 0.12 * pulse), false, 6.0)
		draw_rect(grown, Color(1.0, 0.9, 0.5, 0.75 + 0.25 * pulse), false, 3.0)

# The match is over: the closing card with the reward.
func show_done() -> void:
	card.hide()
	if is_instance_valid(done_box):
		return
	done_box = Control.new()
	done_box.size = size
	add_child(done_box)
	UiKit.dim(done_box, 0.55)
	var rect: Rect2 = Rect2(340, 190, 600, 320)
	UiKit.panel(done_box, rect, "wood")
	UiKit.panel(done_box, Rect2(rect.position + Vector2(14, 46), rect.size - Vector2(28, 60)), "paper")
	UiKit.title(done_box, tr("TREINO CONCLUÍDO!"), Rect2(rect.position + Vector2(0, 8), Vector2(rect.size.x, 34)), 26)
	UiKit.wrapped(done_box, tr("Você já domina o básico. Veja o que fazer em seguida na aba PRIMEIROS PASSOS da MISSÃO."), Rect2(rect.position + Vector2(34, 62), Vector2(rect.size.x - 68, 80)), 17, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.wrapped(done_box, tr("Recompensa: %s") % Tutorial.reward_text(game.balance), Rect2(rect.position + Vector2(34, 150), Vector2(rect.size.x - 68, 70)), 17, UiKit.GOOD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var go: Button = UiKit.button(done_box, tr("CONTINUAR"), Rect2(rect.position.x + rect.size.x / 2 - 110, rect.end.y - 66, 220, 46), screen.app.finish_tutorial, "button_green", 20)
	go.name = "TutorialContinue"
