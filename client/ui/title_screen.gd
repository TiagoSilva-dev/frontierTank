class_name TitleScreen
extends Control

# Tela de entrada, como o login do DDTank: arte PixelLab em 2x, o logotipo com um
# brilho passando, a escolha de servidor (simulada, o jogo é offline) e ENTRAR,
# que leva à cidade. No canto, o idioma do jogo (português ou inglês, roadmap 4.3).

const ART: String = "res://assets/title/title_bg.png"
const LOGO: String = "res://assets/title/logo.png"
const VERSION: String = "0.10"
const SERVERS: Array[Dictionary] = [
	{"name": "S1 · Nova Era", "state": "Recomendado", "color": "8cff6a"},  # i18n
	{"name": "S2 · Ilha Celeste", "state": "Movimentado", "color": "ffd46b"},  # i18n
	{"name": "S3 · Templo do Sol", "state": "Novo", "color": "7ad8ff"},  # i18n
]

var app: Node
var time: float = 0.0
var logo: TextureRect
var sparkles: Control
var chosen: int = 0
var server_buttons: Array[Button] = []

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.art(self, ART, Rect2(0, 0, 1280, 720), false)
	sparkles = Control.new()
	sparkles.size = size
	sparkles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sparkles.draw.connect(draw_sparkles)
	add_child(sparkles)
	logo = UiKit.art(self, LOGO, Rect2(384, 6, 512, 288))
	logo.name = "Logo"
	var shine: ShaderMaterial = ShaderMaterial.new()
	shine.shader = load("res://client/shaders/logo_shine.gdshader")
	logo.material = shine
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var box: Panel = UiKit.panel(self, Rect2(452, 452, 376, 236), "wood")
	UiKit.panel(box, Rect2(12, 40, 352, 128), "paper")
	UiKit.title(box, tr("SELECIONE O SERVIDOR"), Rect2(0, 6, 376, 30), 20)
	for i in range(SERVERS.size()):
		var server: Dictionary = SERVERS[i]
		var row: Button = UiKit.button(box, "", Rect2(20, 48 + i * 38, 336, 34), pick.bind(i), "card")
		row.name = "Server_%d" % i
		UiKit.label(row, tr(str(server.name)), Rect2(12, 0, 200, 34), 16, UiKit.TEXT_DARK)
		UiKit.label(row, tr(str(server.state)), Rect2(196, 0, 128, 34), 15, Color(str(server.color)), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		server_buttons.append(row)
	var play: Button = UiKit.button(box, tr("ENTRAR"), Rect2(98, 178, 180, 46), enter, "button_green", 24)
	play.name = "EnterButton"
	UiKit.label(self, tr("Frontier Tank: Nova Era %s · modo offline, servidores simulados") % VERSION, Rect2(12, 690, 700, 26), 15, Color("fff4d6"), UiKit.INK)
	var quit: Button = UiKit.button(self, tr("SAIR"), Rect2(1168, 676, 100, 34), func() -> void: app.quit_game(), "button", 15)
	quit.name = "QuitButton"
	for i in range(Lang.LOCALES.size()):
		var code: String = Lang.LOCALES[i]
		var language: Button = UiKit.button(self, Lang.LABELS[code], Rect2(1000 + i * 138, 12, 130, 36), choose_language.bind(code), "tab_active" if Lang.locale() == code else "tab", 15)
		language.name = "Lang_" + code
		language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pick(0)

func choose_language(code: String) -> void:
	# The whole game follows; screens are rebuilt when they open, so the title is rebuilt now.
	if code == Lang.locale():
		return
	Lang.set_locale(code)
	app.audio.play("ui_click")
	app.show_title()

func pick(index: int) -> void:
	chosen = index
	for i in range(server_buttons.size()):
		server_buttons[i].add_theme_stylebox_override("normal", UiKit.frame("card_hover" if i == index else "card"))

func enter() -> void:
	app.audio.play("ui_confirm")
	app.lobby.post("Sistema", tr("Bem-vindo ao servidor %s!") % tr(str(SERVERS[chosen].name)), "system")
	app.show_city()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		enter()

func _process(delta: float) -> void:
	time += delta
	# The logo floats a little, in whole 2x pixels.
	logo.position.y = 6.0 + roundf(sin(time * 1.6) * 2.0) * 2.0
	sparkles.queue_redraw()

func draw_sparkles() -> void:
	# Twinkling stars in the sky and light motes rising through the sunrise.
	for i in range(18):
		var seed_x: float = fposmod(i * 73.13, 1.0)
		var seed_y: float = fposmod(i * 41.71, 1.0)
		var at: Vector2 = Vector2(40.0 + seed_x * 1200.0, 20.0 + seed_y * 380.0).snapped(Vector2(2, 2))
		var blink: float = sin(time * (2.0 + seed_y * 2.0) + i * 1.7)
		if blink > 0.35:
			var r: float = roundf(blink * 3.0) * 2.0
			var color: Color = Color(1.0, 0.97, 0.8, blink)
			sparkles.draw_rect(Rect2(at - Vector2(r, 1), Vector2(r * 2.0, 2)), color)
			sparkles.draw_rect(Rect2(at - Vector2(1, r), Vector2(2, r * 2.0)), color)
	for i in range(24):
		var phase: float = fposmod(time * 0.06 + i * 0.041, 1.0)
		var x: float = fposmod(i * 211.0 + sin(time * 0.8 + i) * 12.0, 1280.0)
		var at: Vector2 = Vector2(x, 720.0 - phase * 760.0).snapped(Vector2(2, 2))
		sparkles.draw_rect(Rect2(at, Vector2(2, 2)), Color(1.0, 0.9, 0.6, 0.6 * sin(phase * PI)))
