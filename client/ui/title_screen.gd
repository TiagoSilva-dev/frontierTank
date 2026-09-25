class_name TitleScreen
extends Control

# Tela de entrada, como o login do DDTank: arte PixelLab em 2x, o logotipo com um
# brilho passando, a escolha de servidor e ENTRAR, que leva à cidade. No canto, o idioma
# do jogo (português ou inglês, roadmap 4.3).
# Online (backend 0.11): a lista vem da API com os servidores de jogo no ar; a conta e a
# senha entram na API e o token abre a conexão com o servidor escolhido. "Modo offline"
# continua jogando sozinho, com salas e jogadores simulados.

const ART: String = "res://assets/title/title_bg.png"
const LOGO: String = "res://assets/title/logo.png"
const VERSION: String = NetClient.GAME_VERSION
const OFFLINE: Dictionary = {"name": "Modo offline", "state": "Sozinho", "color": "c8b8a0", "offline": true}  # i18n

var app: Node
var time: float = 0.0
var logo: TextureRect
var sparkles: Control
var chosen: int = 0
var servers: Array[Dictionary] = [OFFLINE]
var server_box: Control
var account_box: Control
var server_buttons: Array[Button] = []
var user_field: LineEdit
var password_field: LineEdit
var remember_box: CheckBox
var status_label: Label
var enter_button: Button
var busy: bool = false
var searching: bool = true

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.art(self, ART, Rect2(0, 0, 1280, 720), false)
	sparkles = Control.new()
	sparkles.size = size
	sparkles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sparkles.draw.connect(draw_sparkles)
	add_child(sparkles)
	logo = UiKit.art(self, LOGO, Rect2(384, -8, 512, 288))
	logo.name = "Logo"
	var shine: ShaderMaterial = ShaderMaterial.new()
	shine.shader = load("res://client/shaders/logo_shine.gdshader")
	logo.material = shine
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var box: Panel = UiKit.panel(self, Rect2(400, 276, 480, 436), "wood")
	box.name = "LoginBox"
	UiKit.title(box, tr("SELECIONE O SERVIDOR"), Rect2(0, 6, 480, 30), 20)
	server_box = Control.new()
	server_box.position = Vector2(12, 40)
	server_box.size = Vector2(456, 132)
	box.add_child(server_box)
	account_box = Control.new()
	account_box.position = Vector2(12, 178)
	account_box.size = Vector2(456, 150)
	box.add_child(account_box)
	status_label = UiKit.label(box, "", Rect2(12, 330, 456, 44), 15, Color("fff0c0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	status_label.name = "Status"
	UiKit.wrap(status_label, Vector2(456, 44))
	enter_button = UiKit.button(box, tr("ENTRAR"), Rect2(150, 380, 180, 46), enter, "button_green", 24)
	enter_button.name = "EnterButton"
	UiKit.label(self, tr("Frontier Tank: Nova Era %s") % VERSION, Rect2(12, 690, 400, 26), 15, Color("fff4d6"), UiKit.INK)
	var quit: Button = UiKit.button(self, tr("SAIR"), Rect2(1168, 676, 100, 34), func() -> void: app.quit_game(), "button", 15)
	quit.name = "QuitButton"
	for i in range(Lang.LOCALES.size()):
		var code: String = Lang.LOCALES[i]
		var language: Button = UiKit.button(self, Lang.LABELS[code], Rect2(1000 + i * 138, 12, 130, 36), choose_language.bind(code), "tab_active" if Lang.locale() == code else "tab", 15)
		language.name = "Lang_" + code
		language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	build_servers()
	build_account()
	refresh_servers()

func build_servers() -> void:
	for child in server_box.get_children():
		child.queue_free()
	server_buttons.clear()
	UiKit.panel(server_box, Rect2(0, 0, 456, 132), "paper")
	var shown: Array[Dictionary] = servers.slice(maxi(0, servers.size() - 3))
	for i in range(shown.size()):
		var server: Dictionary = shown[i]
		var index: int = servers.find(server)
		var row: Button = UiKit.button(server_box, "", Rect2(8, 8 + i * 40, 440, 36), pick.bind(index), "card")
		row.name = "Server_%d" % index
		UiKit.label(row, tr(str(server.name)), Rect2(12, 0, 280, 36), 17, UiKit.TEXT_DARK)
		UiKit.label(row, tr(str(server.state)), Rect2(250, 0, 178, 36), 15, Color(str(server.color)), UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		server_buttons.append(row)
	if searching:
		UiKit.label(server_box, tr("Buscando servidores…"), Rect2(8, 92, 440, 32), 15, Color("7a5a3a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	pick(clampi(chosen, 0, servers.size() - 1))

func build_account() -> void:
	for child in account_box.get_children():
		child.queue_free()
	user_field = null
	password_field = null
	UiKit.panel(account_box, Rect2(0, 0, 456, 150), "paper")
	var server: Dictionary = servers[chosen]
	if server.get("offline", false):
		var text: Label = UiKit.label(account_box, tr("Jogue sozinho: as salas e os jogadores do canal são simulados por IA e o progresso fica neste computador."), Rect2(16, 10, 424, 130), 16, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.wrap(text, Vector2(424, 130))
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return
	var auth: AuthClient = app.auth
	if auth.token != "":
		UiKit.label(account_box, tr("Conta"), Rect2(16, 16, 424, 26), 15, Color("7a5a3a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(account_box, auth.username, Rect2(16, 42, 424, 34), 24, Color("5a2408"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		var other: Button = UiKit.button(account_box, tr("Trocar de conta"), Rect2(148, 92, 160, 38), switch_account, "button", 15)
		other.name = "SwitchAccount"
		return
	UiKit.label(account_box, tr("Conta"), Rect2(14, 12, 90, 34), 16, UiKit.TEXT_DARK)
	user_field = field(Rect2(104, 12, 340, 34), tr("nome da conta"), false)
	user_field.name = "User"
	user_field.text = auth.username
	UiKit.label(account_box, tr("Senha"), Rect2(14, 54, 90, 34), 16, UiKit.TEXT_DARK)
	password_field = field(Rect2(104, 54, 340, 34), tr("sua senha"), true)
	password_field.name = "Password"
	password_field.text_submitted.connect(func(_text: String) -> void: enter())
	remember_box = CheckBox.new()
	remember_box.text = tr("Lembrar")
	remember_box.button_pressed = auth.remember
	remember_box.position = Vector2(14, 100)
	remember_box.size = Vector2(150, 36)
	remember_box.add_theme_font_override("font", UiKit.font(true))
	remember_box.add_theme_font_size_override("font_size", UiKit.fs(15))
	remember_box.add_theme_color_override("font_color", UiKit.TEXT_DARK)
	remember_box.add_theme_color_override("font_hover_color", UiKit.TEXT_DARK)
	remember_box.add_theme_color_override("font_pressed_color", UiKit.TEXT_DARK)
	remember_box.add_theme_color_override("font_hover_pressed_color", UiKit.TEXT_DARK)
	remember_box.add_theme_color_override("font_focus_color", UiKit.TEXT_DARK)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		remember_box.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	account_box.add_child(remember_box)
	var create: Button = UiKit.button(account_box, tr("CRIAR CONTA"), Rect2(254, 100, 190, 38), create_account, "button_blue", 15)
	create.name = "CreateAccount"
	if user_field.text == "":
		user_field.call_deferred("grab_focus")

func field(rect: Rect2, hint: String, secret: bool) -> LineEdit:
	var node: LineEdit = LineEdit.new()
	node.position = rect.position
	node.size = rect.size
	node.placeholder_text = hint
	node.secret = secret
	node.max_length = 64 if secret else 16
	node.add_theme_font_override("font", UiKit.font(true))
	node.add_theme_font_size_override("font_size", UiKit.fs(16))
	account_box.add_child(node)
	return node

func refresh_servers() -> void:
	var result: Dictionary = await app.auth.servers()
	if not is_inside_tree():
		return
	searching = false
	var list: Array[Dictionary] = []
	for server: Variant in result.get("servers", []):
		if server is Dictionary:
			var online: int = int(server.get("online", 0))
			var full: bool = online >= int(server.get("capacity", 1)) * 0.9
			list.append({"name": str(server.name), "url": str(server.url), "state": tr("Cheio") if full else tr("%d online") % online, "color": "ff8a6a" if full else ("8cff6a" if online > 0 else "7ad8ff")})
	list.append(OFFLINE)
	servers = list
	# The first online server is the default; alone, the offline mode.
	chosen = 0
	build_servers()
	build_account()
	if result.has("error"):
		set_status(tr("Servidores online indisponíveis agora. Você pode jogar no modo offline."))

func set_status(text: String) -> void:
	status_label.text = text

func choose_language(code: String) -> void:
	# The whole game follows; screens are rebuilt when they open, so the title is rebuilt now.
	if code == Lang.locale():
		return
	Lang.set_locale(code)
	app.audio.play("ui_click")
	app.show_title()

func pick(index: int) -> void:
	var changed: bool = index != chosen
	chosen = clampi(index, 0, servers.size() - 1)
	for button: Button in server_buttons:
		var own: int = button.name.trim_prefix("Server_").to_int()
		button.add_theme_stylebox_override("normal", UiKit.frame("card_hover" if own == chosen else "card"))
	if changed and is_instance_valid(account_box):
		set_status("")
		build_account()

func switch_account() -> void:
	await app.auth.logout()
	build_account()

func create_account() -> void:
	await login(true)

func enter() -> void:
	if busy:
		return
	var server: Dictionary = servers[chosen]
	app.audio.play("ui_confirm")
	if server.get("offline", false):
		app.lobby.post("Sistema", tr("Bem-vindo ao modo offline!"), "system")
		app.show_city()
		return
	await login(false)

func login(create: bool) -> void:
	if busy:
		return
	var server: Dictionary = servers[chosen]
	if server.get("offline", false):
		return
	var auth: AuthClient = app.auth
	busy = true
	enter_button.disabled = true
	if auth.token == "" or create:
		var user: String = user_field.text.strip_edges() if user_field != null else ""
		var password: String = password_field.text if password_field != null else ""
		if user == "" or password == "":
			finish(tr("Digite a conta e a senha."))
			return
		auth.remember = remember_box.button_pressed if remember_box != null else true
		set_status(tr("Criando a conta…") if create else tr("Entrando…"))
		var error: String = await auth.login(user, password, create)
		if error != "":
			finish(AuthClient.message_for(error))
			return
	set_status(tr("Conectando a %s…") % tr(str(server.name)))
	var code: String = await app.net.connect_to(str(server.url), auth.token)
	if code == "unauthorized":
		auth.token = ""
		auth.save_session()
		build_account()
	if code != "":
		finish(AuthClient.message_for(code))
		return
	busy = false
	app.go_online(app.net.welcome())

func finish(message: String) -> void:
	busy = false
	if is_instance_valid(enter_button):
		enter_button.disabled = false
		set_status(message)
		app.audio.play("ui_error")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		enter()

func _process(delta: float) -> void:
	time += delta
	# The logo floats a little, in whole 2x pixels.
	logo.position.y = -8.0 + roundf(sin(time * 1.6) * 2.0) * 2.0
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
