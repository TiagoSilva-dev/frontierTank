class_name AccountScreen
extends Control

# Ajuda → Minha conta (launch checklist, LGPD/GDPR): the account, the version of the
# texts accepted, a copy of everything stored about the account (right of access and
# portability) and deleting the account with the password. Connected to a game server,
# the deletion goes through it (it drops its copy of the profile so nothing is saved
# back); on the title screen, logged in but not connected, straight to the API.

var app: Node
var status: Label
var open_folder: Button
var busy: bool = false
var confirm_root: Control

static func open(parent: Node, app_node: Node) -> AccountScreen:
	var screen: AccountScreen = AccountScreen.new()
	screen.app = app_node
	parent.add_child(screen)
	return screen

func logged_in() -> bool:
	return bool(app.online) or str(app.auth.token) != ""

# Accounts made by the Steam login have no password: deleting is confirmed by typing
# the word and a fresh Steam ticket.
func steam_only() -> bool:
	return bool(app.auth.no_password)

func can_link() -> bool:
	return logged_in() and app.steam.available and not bool(app.auth.steam_linked)

func account_name() -> String:
	if app.online:
		return str(app.net.account.get("username", app.auth.username))
	return str(app.auth.username)

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.7)
	# The panel fits what it shows: the account lines and buttons, or the offline note.
	var height: float = 64 + 56 + 84 + 66 + ((96 if app.online else 64) + 8 + 56 + 40 if logged_in() else 120) + (56 if can_link() else 0)
	var rect: Rect2 = Rect2(330, roundf((720 - height) / 2.0), 620, height)
	UiKit.panel(self, rect, "wood")
	UiKit.title(self, tr("MINHA CONTA"), Rect2(rect.position.x, rect.position.y + 8, rect.size.x, 34), 24)
	UiKit.panel(self, Rect2(rect.position + Vector2(14, 46), rect.size - Vector2(28, 60)), "paper")
	var x: float = rect.position.x + 40
	var y: float = rect.position.y + 64
	if logged_in():
		UiKit.label(self, tr("Conta"), Rect2(x, y, 200, 28), 16, Color("7a5a3a"))
		var who: Label = UiKit.label(self, account_name(), Rect2(x + 200, y, 340, 28), 18, UiKit.TEXT_DARK)
		who.name = "AccountName"
		y += 32
		if app.online:
			UiKit.label(self, tr("Servidor"), Rect2(x, y, 200, 28), 16, Color("7a5a3a"))
			UiKit.label(self, tr(str(app.net.welcome().get("server", {}).get("name", ""))), Rect2(x + 200, y, 340, 28), 18, UiKit.TEXT_DARK)
			y += 32
		UiKit.label(self, tr("Termos aceitos"), Rect2(x, y, 200, 28), 16, Color("7a5a3a"))
		UiKit.label(self, tr("versão %s") % Legal.VERSION, Rect2(x + 200, y, 340, 28), 18, UiKit.TEXT_DARK)
		y += 40
	else:
		var offline: Label = UiKit.label(self, tr("Você está no modo offline: o progresso fica só neste computador e nada é enviado para os servidores. Para ter uma conta, escolha um servidor na tela de entrada."), Rect2(x, y, 540, 110), 16, UiKit.TEXT_DARK)
		UiKit.wrap(offline, Vector2(540, 110))
		y += 120
	var terms: Button = UiKit.button(self, Legal.title("terms"), Rect2(x, y, 262, 40), func() -> void: LegalScreen.open(self, "terms"), "button_blue", 15)
	terms.name = "Terms"
	var privacy: Button = UiKit.button(self, Legal.title("privacy"), Rect2(x + 278, y, 262, 40), func() -> void: LegalScreen.open(self, "privacy"), "button_blue", 15)
	privacy.name = "Privacy"
	y += 56
	if logged_in():
		var download: Button = UiKit.button(self, tr("Baixar meus dados"), Rect2(x, y, 262, 44), download_data, "button", 16)
		download.name = "Download"
		download.tooltip_text = tr("Um arquivo JSON com tudo o que o servidor guarda sobre a sua conta.")
		var remove: Button = UiKit.button(self, tr("Excluir conta"), Rect2(x + 278, y, 262, 44), ask_delete, "button_red", 16)
		remove.name = "Delete"
		y += 56
	if can_link():
		var link: Button = UiKit.button(self, tr("Vincular à Steam"), Rect2(x + 139, y, 262, 44), link_steam, "button_blue", 16)
		link.name = "LinkSteam"
		y += 56
	status = UiKit.label(self, "", Rect2(x, y, 540, 84), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	status.name = "Status"
	UiKit.wrap(status, Vector2(540, 84))
	open_folder = UiKit.button(self, tr("Abrir pasta"), Rect2(x + 190, y + 86, 160, 34), func() -> void: OS.shell_open(ProjectSettings.globalize_path("user://exports")), "button", 14)
	open_folder.visible = false
	var close: Button = UiKit.button(self, tr("FECHAR"), Rect2(rect.end.x - 200, rect.end.y - 60, 160, 42), queue_free)
	close.name = "Close"

func say(text: String, error: bool = false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color("b8321c") if error else Color("2f5a1f"))
	if app != null and app.get("audio") != null:
		app.audio.play("ui_error" if error else "ui_confirm")

# ---------- copy of the data ----------

func download_data() -> void:
	if busy:
		return
	busy = true
	status.text = tr("Preparando os seus dados…")
	var result: Dictionary = await app.auth.export_data()
	busy = false
	if not is_inside_tree():
		return
	if result.has("error"):
		say(AuthClient.message_for(str(result.error)), true)
		return
	var file_name: String = "frontier_tank_%s_%s.json" % [account_name(), Time.get_datetime_string_from_system().replace(":", "-")]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(str(result.text).to_utf8_buffer(), file_name, "application/json")
		say(tr("Arquivo baixado: %s") % file_name)
		return
	DirAccess.make_dir_recursive_absolute("user://exports")
	var path: String = "user://exports/" + file_name
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		say(tr("Não foi possível salvar o arquivo."), true)
		return
	file.store_string(str(result.text))
	file.close()
	say(tr("Seus dados foram salvos em:\n%s") % ProjectSettings.globalize_path(path))
	open_folder.visible = true

# ---------- deleting the account ----------

func ask_delete() -> void:
	if busy or is_instance_valid(confirm_root):
		return
	var asked: String = tr("Digite EXCLUIR para confirmar (a Steam confirma que a conta é sua).") if steam_only() else tr("Digite a sua senha para confirmar.")
	confirm_root = UiKit.modal(self, tr("EXCLUIR CONTA"), tr("Isso apaga para sempre a sua conta, o personagem, os itens, as moedas, o Correio e os anúncios do Leilão. Não dá para desfazer.") + "\n" + asked, Vector2(620, 360))
	var rect: Rect2 = confirm_root.get_meta("rect")
	var password: LineEdit = UiKit.text_field(confirm_root, Rect2(rect.position.x + 110, rect.position.y + 196, 400, 38), tr("EXCLUIR") if steam_only() else tr("sua senha"), not steam_only(), 128)
	password.name = "DeletePassword"
	var problem: Label = UiKit.label(confirm_root, "", Rect2(rect.position.x + 40, rect.position.y + 238, 540, 40), 15, Color("b8321c"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	problem.name = "DeleteProblem"
	UiKit.wrap(problem, Vector2(540, 40))
	var go: Callable = func() -> void: confirm_delete(password.text, problem)
	password.text_submitted.connect(func(_text: String) -> void: go.call())
	var confirm: Button = UiKit.button(confirm_root, tr("EXCLUIR PARA SEMPRE"), Rect2(rect.position.x + 60, rect.end.y - 62, 260, 44), go, "button_red", 16)
	confirm.name = "ConfirmDelete"
	UiKit.button(confirm_root, tr("CANCELAR"), Rect2(rect.end.x - 240, rect.end.y - 62, 180, 44), confirm_root.queue_free)
	password.grab_focus.call_deferred()

func confirm_delete(password: String, problem: Label) -> void:
	if busy:
		return
	var ticket: String = ""
	if steam_only():
		if password.strip_edges().to_upper() != tr("EXCLUIR").to_upper():
			problem.text = tr("Digite EXCLUIR para confirmar.")
			return
		busy = true
		problem.text = tr("Excluindo…")
		ticket = await app.steam.web_ticket()
		password = ""
		if ticket == "":
			busy = false
			problem.text = AuthClient.message_for("steam_unavailable")
			return
	elif password == "":
		problem.text = tr("Digite a sua senha.")
		return
	busy = true
	problem.text = tr("Excluindo…")
	var error: String = ""
	if app.online:
		var reply: Dictionary = await app.net.request("account_delete", {"password": password, "steam_ticket": ticket}, 30.0)
		error = "" if reply.ok else app.server_text(reply.get("error", ""))
		if reply.ok:
			# The server closes the connection ("account_deleted") and the game goes
			# back to the title with the notice.
			app.auth.forget()
	else:
		var code: String = await app.auth.delete_account(password, ticket)
		error = "" if code == "" else AuthClient.message_for(code)
	busy = false
	if error != "":
		if is_instance_valid(problem):
			problem.text = error
			app.audio.play("ui_error")
		return
	if not app.online and is_inside_tree():
		var host: Node = get_parent()
		queue_free()
		UiKit.notice(host, tr("CONTA EXCLUÍDA"), AuthClient.message_for("account_deleted"))
		if app.screen is TitleScreen:
			app.screen.build_account()

# ---------- Steam ----------

func link_steam() -> void:
	if busy:
		return
	busy = true
	status.text = tr("Conectando à Steam…")
	var code: String = await app.auth.link_steam(await app.steam.web_ticket())
	busy = false
	if not is_inside_tree():
		return
	if code != "":
		say(AuthClient.message_for(code), true)
		return
	say(tr("Conta ligada à Steam. Agora você pode entrar com a Steam e comprar na loja."))
	var link: Node = find_child("LinkSteam", true, false)
	if link != null:
		link.queue_free()

func _gui_input(_event: InputEvent) -> void:
	accept_event()
