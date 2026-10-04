class_name ReplayBar
extends Control

# The strip of a replay or a live spectator (0.22): replaces the battle log under the
# portrait. A replay has pause, 1x/2x/4x and a progress bar; a spectator only says what is
# going on (the broadcast runs a few seconds behind the battle) and has the way out.

var screen: BattleScreen
var live: bool = false
var card: Control
var title_label: Label
var bar: Panel
var fill: Panel
var play_button: Button
var speed_buttons: Array[Button] = []

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card = Control.new()
	card.position = Vector2(4, 156)
	card.size = Vector2(376, 118 if not live else 86)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.draw.connect(func() -> void:
		var inner: Rect2 = HudPaint.frame(card, Rect2(Vector2.ZERO, card.size), 0.25)
		HudPaint.well(card, inner, Color(0.03, 0.04, 0.07, 0.92), Color(0.08, 0.1, 0.16, 0.92)))
	add_child(card)
	title_label = UiKit.label(card, tr("AO VIVO") if live else tr("REPLAY"), Rect2(14, 8, 250, 26), 18, Color("ff7a6a") if live else Color("ffd04a"), UiKit.INK)
	var exit: Button = UiKit.button(card, tr("SAIR"), Rect2(280, 8, 84, 30), screen.leave_watching, "button_red", 14)
	exit.name = "WatchExit"
	exit.mouse_filter = Control.MOUSE_FILTER_STOP
	if live:
		var note: Label = UiKit.wrapped(card, tr("A transmissão tem alguns segundos de atraso."), Rect2(14, 40, 350, 40), 14, Color("c8d8ff"), UiKit.INK)
		return
	bar = UiKit.panel(card, Rect2(14, 44, 348, 14), "dark")
	fill = UiKit.panel(bar, Rect2(2, 2, 1, 10), "button_green")
	play_button = UiKit.button(card, tr("PAUSAR"), Rect2(14, 72, 110, 32), toggle_pause, "button_blue", 14)
	play_button.name = "ReplayPause"
	play_button.mouse_filter = Control.MOUSE_FILTER_STOP
	for i in range(3):
		var factor: float = [1.0, 2.0, 4.0][i]
		var button: Button = UiKit.button(card, "%dx" % int(factor), Rect2(138 + i * 56, 72, 50, 32), set_speed.bind(factor), "button", 14)
		button.name = "Speed%d" % int(factor)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		speed_buttons.append(button)

func toggle_pause() -> void:
	screen.game.paused = not screen.game.paused
	play_button.text = tr("CONTINUAR") if screen.game.paused else tr("PAUSAR")

func set_speed(factor: float) -> void:
	screen.replay_driver.speed = factor

func _process(_delta: float) -> void:
	if live or not is_instance_valid(screen.replay_driver) or not is_instance_valid(fill):
		return
	fill.size.x = maxf(1.0, 344.0 * screen.replay_driver.progress())
	for i in range(speed_buttons.size()):
		speed_buttons[i].add_theme_stylebox_override("normal", UiKit.frame("button_green" if absf(screen.replay_driver.speed - [1.0, 2.0, 4.0][i]) < 0.01 else "button"))
