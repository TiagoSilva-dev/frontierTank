class_name AuthClient
extends Node

# The public API (Go): create an account, log in, log out and the list of game servers.
# The address comes from --api=..., then user://online.cfg, then DEFAULT_API; the session
# token is remembered in user://online.cfg when the player asks. On the web the default is
# the page's own address (the proxy in front sends /v1/... to the API; ?api=... overrides).

const DEFAULT_API: String = "http://localhost:8080"
# Tests point this at a scratch file so they never touch the player's saved login.
static var config_path: String = "user://online.cfg"

var base_url: String = DEFAULT_API
var token: String = ""
var username: String = ""
var remember: bool = true

func _init() -> void:
	base_url = default_api()
	var config: ConfigFile = ConfigFile.new()
	if config.load(config_path) == OK:
		base_url = str(config.get_value("online", "api", base_url))
		token = str(config.get_value("session", "token", ""))
		username = str(config.get_value("session", "username", ""))

static func default_api() -> String:
	if OS.has_feature("web"):
		var origin: String = str(JavaScriptBridge.eval("window.location.origin", true))
		if origin.begins_with("http"):
			return origin
	return DEFAULT_API

func save_session() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(config_path)
	config.set_value("online", "api", base_url)
	config.set_value("session", "token", token if remember else "")
	config.set_value("session", "username", username)
	config.save(config_path)

func request_json(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = 12.0
	add_child(request)
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	if request.request(base_url.trim_suffix("/") + path, headers, method, "" if body == null else JSON.stringify(body)) != OK:
		request.queue_free()
		return {"status": 0, "body": null}
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": null}
	return {"status": int(result[1]), "body": parse_body((result[3] as PackedByteArray).get_string_from_utf8())}

# The body as JSON, or null (a proxy or static host may answer with an HTML page).
static func parse_body(text: String) -> Variant:
	var json: JSON = JSON.new()
	return json.data if text != "" and json.parse(text) == OK else null

static func error_of(reply: Dictionary) -> String:
	if int(reply.status) == 0:
		return "api_unavailable"
	return str(reply.body.get("error", "internal")) if reply.body is Dictionary else "internal"

# "" or an error code; on success `token` and `username` are set.
func login(user: String, password: String, create: bool = false) -> String:
	var reply: Dictionary = await request_json(HTTPClient.METHOD_POST, "/v1/auth/register" if create else "/v1/auth/login", {"username": user, "password": password})
	if int(reply.status) != 200 and int(reply.status) != 201:
		return error_of(reply)
	token = str(reply.body.token)
	username = str(reply.body.account.username)
	save_session()
	return ""

func logout() -> void:
	if token != "":
		await request_json(HTTPClient.METHOD_POST, "/v1/auth/logout")
	token = ""
	save_session()

# {"servers": [...]} or {"error": code}
func servers() -> Dictionary:
	var reply: Dictionary = await request_json(HTTPClient.METHOD_GET, "/v1/servers")
	if int(reply.status) != 200:
		return {"error": error_of(reply)}
	return {"servers": reply.body.get("servers", [])}

# The player-facing text for an error code from the API or the game server.
static func message_for(code: String) -> String:
	match code:
		"api_unavailable", "unreachable":
			return Lang.t("Não foi possível conectar ao servidor. Verifique a internet e tente de novo.")
		"username_invalid":
			return Lang.t("Conta: use de 3 a 16 letras, números ou _.")
		"password_weak":
			return Lang.t("A senha precisa ter de 8 a 128 caracteres.")
		"username_taken":
			return Lang.t("Esta conta já existe. Escolha outro nome de conta.")
		"invalid_credentials":
			return Lang.t("Conta ou senha incorreta.")
		"rate_limited":
			return Lang.t("Muitas tentativas. Aguarde um minuto.")
		"banned":
			return Lang.t("Esta conta está suspensa.")
		"unauthorized":
			return Lang.t("Sua sessão expirou. Entre de novo.")
		"outdated":
			return Lang.t("Sua versão do jogo é diferente da do servidor. Atualize o jogo.")
		"online_elsewhere":
			return Lang.t("Esta conta já está conectada em outro servidor.")
		"logged_elsewhere":
			return Lang.t("Sua conta entrou em outro lugar.")
		"server_full":
			return Lang.t("O servidor está cheio. Tente outro servidor.")
		"server_closing":
			return Lang.t("O servidor está reiniciando. Entre de novo em instantes.")
		"profile_conflict":
			return Lang.t("Seu perfil mudou em outro lugar. Entre de novo.")
		"timeout":
			return Lang.t("O servidor não respondeu a tempo.")
		"connection_lost", "closed", "offline":
			return Lang.t("A conexão com o servidor caiu.")
	return Lang.t("Erro do servidor: %s") % code
