class_name ApiClient
extends Node

# The game server's link to the Go API (internal port): sessions, profiles, character
# names, audit log, heartbeat and presence. With `base_url` "memory" everything stays in
# memory instead, for tests and LAN play without Docker: any token "dev:<name>" logs in
# as that name and nothing survives a restart.

var base_url: String = "memory"
var key: String = ""
var server_id: String = "s1"
var memory_accounts: Dictionary = {}
var memory_profiles: Dictionary = {}
var memory_presence: Dictionary = {}

func is_memory() -> bool:
	return base_url == "memory"

# {"status": HTTP status (0 = no answer), "body": parsed JSON or null}
func request_json(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json", "X-Internal-Key: " + key])
	var error: int = request.request(base_url + path, headers, method, "" if body == null else JSON.stringify(body))
	if error != OK:
		request.queue_free()
		return {"status": 0, "body": null}
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": null}
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	return {"status": int(result[1]), "body": JSON.parse_string(text) if text != "" else null}

static func error_code(reply: Dictionary) -> String:
	if int(reply.status) == 0:
		return "api_unavailable"
	var body: Variant = reply.body
	return str(body.get("error", "internal")) if body is Dictionary else "internal"

# {"id", "username"} or {"error": code}
func verify(token: String) -> Dictionary:
	if is_memory():
		if not token.begins_with("dev:") or token.length() < 7:
			return {"error": "unauthorized"}
		var username: String = token.substr(4, 16)
		if not memory_accounts.has(username.to_lower()):
			memory_accounts[username.to_lower()] = memory_accounts.size() + 1
		return {"id": int(memory_accounts[username.to_lower()]), "username": username}
	var reply: Dictionary = await request_json(HTTPClient.METHOD_POST, "/internal/sessions/verify", {"token": token})
	if int(reply.status) != 200:
		return {"error": error_code(reply)}
	return {"id": int(reply.body.account.id), "username": str(reply.body.account.username)}

# {"data", "version"}, {"missing": true} for a new account, or {"error": code}
func load_profile(account: int) -> Dictionary:
	if is_memory():
		if not memory_profiles.has(account):
			return {"missing": true}
		var stored: Dictionary = memory_profiles[account]
		return {"data": JSON.parse_string(JSON.stringify(stored.data)), "version": int(stored.version)}
	var reply: Dictionary = await request_json(HTTPClient.METHOD_GET, "/internal/profiles/%d" % account)
	if int(reply.status) == 404:
		return {"missing": true}
	if int(reply.status) != 200:
		return {"error": error_code(reply)}
	return {"data": reply.body.data, "version": int(reply.body.version)}

# {"version"} or {"error": "name_taken" | "version_conflict" | ...}
func save_profile(account: int, profile_name: Variant, data: Dictionary, version: int) -> Dictionary:
	if is_memory():
		var current: int = int(memory_profiles.get(account, {}).get("version", 0))
		if current != version:
			return {"error": "version_conflict"}
		if profile_name != null:
			for other: int in memory_profiles:
				if other != account and str(memory_profiles[other].get("name", "")).to_lower() == str(profile_name).to_lower():
					return {"error": "name_taken"}
		memory_profiles[account] = {"name": profile_name, "data": JSON.parse_string(JSON.stringify(data)), "version": current + 1}
		return {"version": current + 1}
	var reply: Dictionary = await request_json(HTTPClient.METHOD_PUT, "/internal/profiles/%d" % account, {"name": profile_name, "data": data, "version": version})
	if int(reply.status) != 200:
		return {"error": error_code(reply)}
	return {"version": int(reply.body.version)}

# {"taken": bool} or {"error"}
func name_taken(profile_name: String, account: int) -> Dictionary:
	if is_memory():
		for other: int in memory_profiles:
			if other != account and str(memory_profiles[other].get("name", "")).to_lower() == profile_name.to_lower():
				return {"taken": true}
		return {"taken": false}
	var reply: Dictionary = await request_json(HTTPClient.METHOD_GET, "/internal/names/check?name=%s&account=%d" % [profile_name.uri_encode(), account])
	if int(reply.status) != 200:
		return {"error": error_code(reply)}
	return {"taken": bool(reply.body.taken) or not bool(reply.body.valid)}

# "" when this server may host the account, else the error code ("online_elsewhere").
func claim(account: int) -> String:
	if is_memory():
		memory_presence[account] = server_id
		return ""
	var reply: Dictionary = await request_json(HTTPClient.METHOD_POST, "/internal/presence/claim", {"account_id": account, "server_id": server_id})
	return "" if int(reply.status) == 204 else error_code(reply)

func release(account: int) -> void:
	if is_memory():
		memory_presence.erase(account)
		return
	await request_json(HTTPClient.METHOD_POST, "/internal/presence/release", {"account_id": account, "server_id": server_id})

func heartbeat(info: Dictionary, players: Array) -> bool:
	if is_memory():
		return true
	var reply: Dictionary = await request_json(HTTPClient.METHOD_POST, "/internal/heartbeat", {"server": info, "players": players})
	return int(reply.status) == 204

func audit(entries: Array) -> bool:
	if is_memory() or entries.is_empty():
		return true
	var reply: Dictionary = await request_json(HTTPClient.METHOD_POST, "/internal/audit", {"server_id": server_id, "entries": entries})
	return int(reply.status) == 204
