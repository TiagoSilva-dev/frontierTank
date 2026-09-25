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

# ---------- leilão (0.12) ----------
# The auction lives in the Go API (custody and transactions in PostgreSQL). Operations
# that change a profile send it along ({"name", "data", "version"}): the API writes it in
# the same transaction as the listing or the mail. An answer that may have been lost
# ({"error", "unsure": true}) is retried with the same `op_id`, which the API runs once.
# In memory everything below happens in this process, with the same rules.

var memory_listings: Array[Dictionary] = []
var memory_mail: Array[Dictionary] = []
var memory_ops: Dictionary = {}
var next_listing: int = 1
var next_mail: int = 1

static func unix_now() -> int:
	return int(Time.get_unix_time_from_system())

# Numbers come back from the network as floats; memory answers go through JSON too, so
# both modes give the game server the same types.
static func copy(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

# 200 → the body; anything else → {"error": code}; no answer or a server error →
# also "unsure" (the operation may have happened).
func answer(reply: Dictionary) -> Dictionary:
	var status: int = int(reply.status)
	if status == 200 and reply.body is Dictionary:
		return reply.body
	var result: Dictionary = {"error": error_code(reply)}
	if status == 0 or status >= 500:
		result.unsure = true
	return result

func auction_search(filter: Dictionary) -> Dictionary:
	if is_memory():
		return copy(memory_search(filter))
	return answer(await request_json(HTTPClient.METHOD_POST, "/internal/auction/search", filter))

func auction_create(op_id: String, account: int, profile: Dictionary, listing: Dictionary, max_active: int) -> Dictionary:
	if is_memory():
		return copy(memory_op(op_id, memory_create.bind(account, copy(profile), copy(listing), max_active)))
	return answer(await request_json(HTTPClient.METHOD_POST, "/internal/auction/listings", {"op_id": op_id, "server_id": server_id, "account_id": account, "profile": profile, "listing": listing, "max_active": max_active}))

func auction_buy(op_id: String, account: int, listing_id: int, solar: int, estrela: int, profile: Dictionary) -> Dictionary:
	if is_memory():
		return copy(memory_op(op_id, memory_buy.bind(account, listing_id, solar, estrela, copy(profile))))
	return answer(await request_json(HTTPClient.METHOD_POST, "/internal/auction/listings/%d/buy" % listing_id, {"op_id": op_id, "server_id": server_id, "account_id": account, "price_solar": solar, "price_estrela": estrela, "profile": profile}))

func auction_cancel(op_id: String, account: int, listing_id: int) -> Dictionary:
	if is_memory():
		return copy(memory_op(op_id, memory_cancel.bind(account, listing_id)))
	return answer(await request_json(HTTPClient.METHOD_POST, "/internal/auction/listings/%d/cancel" % listing_id, {"op_id": op_id, "server_id": server_id, "account_id": account}))

func auction_mine(account: int) -> Dictionary:
	if is_memory():
		memory_expire(account)
		var active: Array = memory_listings.filter(func(l: Dictionary) -> bool: return int(l.seller_id) == account and l.status == "active")
		var closed: Array = memory_listings.filter(func(l: Dictionary) -> bool: return int(l.seller_id) == account and l.status != "active")
		active.reverse()
		closed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.closed_at) > int(b.closed_at) or (int(a.closed_at) == int(b.closed_at) and int(a.id) > int(b.id)))
		return copy({"active": active, "closed": closed.slice(0, 20), "now": unix_now()})
	return answer(await request_json(HTTPClient.METHOD_GET, "/internal/auction/mine?account=%d" % account))

func auction_history(query: Dictionary) -> Dictionary:
	if is_memory():
		var sales: Array = memory_listings.filter(func(l: Dictionary) -> bool:
			return l.status == "sold" and l.kind == str(query.kind) and l.item_id == str(query.item_id) \
				and (str(query.get("quality", "")) == "" or l.quality == str(query.quality)) \
				and int(l.item_level) >= int(query.get("min_level", 0)) and (int(query.get("max_level", 0)) <= 0 or int(l.item_level) <= int(query.max_level)))
		sales.reverse()
		return copy({"sales": sales.slice(0, clampi(int(query.get("limit", 10)), 1, 20)), "now": unix_now()})
	return answer(await request_json(HTTPClient.METHOD_POST, "/internal/auction/history", query))

func mail_list(account: int) -> Dictionary:
	if is_memory():
		memory_expire(account)
		var waiting: Array = memory_mail.filter(func(m: Dictionary) -> bool: return int(m.account) == account and not bool(m.claimed))
		return copy({"mail": waiting.slice(0, 100), "total": waiting.size(), "now": unix_now()})
	return answer(await request_json(HTTPClient.METHOD_GET, "/internal/mail?account=%d" % account))

func mail_claim(op_id: String, account: int, ids: Array, profile: Dictionary) -> Dictionary:
	if is_memory():
		return copy(memory_op(op_id, memory_claim.bind(account, ids.duplicate(), copy(profile))))
	return answer(await request_json(HTTPClient.METHOD_POST, "/internal/mail/claim", {"op_id": op_id, "server_id": server_id, "account_id": account, "ids": ids, "profile": profile}))

# ---------- leilão em memória ----------

func memory_op(op_id: String, run: Callable) -> Dictionary:
	if memory_ops.has(op_id):
		return memory_ops[op_id]
	var result: Dictionary = run.call()
	if not result.has("error"):
		memory_ops[op_id] = result
	return result

# The version and name checks of save_profile, before anything changes.
func memory_profile_error(account: int, profile: Dictionary) -> String:
	if int(memory_profiles.get(account, {}).get("version", 0)) != int(profile.get("version", -1)):
		return "version_conflict"
	var wanted: Variant = profile.get("name")
	if wanted != null:
		for other: int in memory_profiles:
			if other != account and str(memory_profiles[other].get("name", "")).to_lower() == str(wanted).to_lower():
				return "name_taken"
	return ""

func memory_write_profile(account: int, profile: Dictionary) -> int:
	var version: int = int(memory_profiles.get(account, {}).get("version", 0)) + 1
	memory_profiles[account] = {"name": profile.get("name"), "data": profile.data, "version": version}
	return version

func memory_find(listing_id: int) -> Dictionary:
	for listing in memory_listings:
		if int(listing.id) == listing_id:
			return listing
	return {}

func memory_add_mail(account: int, kind: String, listing: Dictionary, item: Variant, currencies: Dictionary, detail: Dictionary) -> int:
	var mail: Dictionary = {"id": next_mail, "account": account, "kind": kind, "listing_id": int(listing.id), "item_kind": str(listing.kind) if item != null else "", "item": item, "currencies": currencies, "coins": 0, "detail": detail, "created_at": unix_now(), "claimed": false}
	next_mail += 1
	memory_mail.append(mail)
	return int(mail.id)

func memory_expire(seller: int = 0) -> void:
	for listing in memory_listings:
		if listing.status == "active" and int(listing.expires_at) <= unix_now() and (seller == 0 or int(listing.seller_id) == seller):
			listing.status = "expired"
			listing.closed_at = unix_now()
			memory_add_mail(int(listing.seller_id), "returned", listing, listing.item, {}, {"reason": "expired"})

func memory_search(filter: Dictionary) -> Dictionary:
	memory_expire()
	var found: Array = memory_listings.filter(func(l: Dictionary) -> bool:
		if l.status != "active" or int(l.expires_at) <= unix_now():
			return false
		for key: String in ["slot", "item_id", "quality"]:
			if filter.has(key) and str(l[key]) != str(filter[key]):
				return false
		if int(l.item_level) < int(filter.get("min_level", 0)) or (int(filter.get("max_level", 0)) > 0 and int(l.item_level) > int(filter.max_level)):
			return false
		if int(l.strengthen) < int(filter.get("min_strengthen", 0)):
			return false
		if filter.has("mod") and not (l.mods as Array).has(str(filter.mod)):
			return false
		if filter.has("max_solar") and int(l.price_solar) > int(filter.max_solar):
			return false
		return not (filter.has("max_estrela") and int(l.price_estrela) > int(filter.max_estrela)))
	match str(filter.get("sort", "recent")):
		"price":
			found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ranks_before([int(a.price_solar), int(a.price_estrela), int(a.id)], [int(b.price_solar), int(b.price_estrela), int(b.id)]))
		"level":
			found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ranks_before([int(b.item_level), int(b.strengthen), int(b.id)], [int(a.item_level), int(a.strengthen), int(a.id)]))
		_:
			found.reverse()
	var size: int = clampi(int(filter.get("per_page", 12)), 1, 50)
	var start: int = maxi(0, int(filter.get("page", 0))) * size
	return {"listings": found.slice(start, start + size), "total": found.size(), "now": unix_now()}

# Compares [first, second, ...] keys in order (the ORDER BY of the API).
static func ranks_before(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false

func memory_create(account: int, profile: Dictionary, input: Dictionary, max_active: int) -> Dictionary:
	var error: String = memory_profile_error(account, profile)
	if error != "":
		return {"error": error}
	memory_expire(account)
	if memory_listings.filter(func(l: Dictionary) -> bool: return int(l.seller_id) == account and l.status == "active").size() >= max_active:
		return {"error": "too_many_listings"}
	var version: int = memory_write_profile(account, profile)
	var listing: Dictionary = input.duplicate(true)
	var hours: int = int(listing.hours)
	listing.erase("hours")
	listing.merge({"id": next_listing, "seller_id": account, "seller_name": str(profile.get("name", "")) if profile.get("name") != null else "", "status": "active", "buyer_id": null, "created_at": unix_now(), "expires_at": unix_now() + hours * 3600, "closed_at": null})
	next_listing += 1
	memory_listings.append(listing)
	return {"version": version, "listing": listing}

func memory_buy(account: int, listing_id: int, solar: int, estrela: int, profile: Dictionary) -> Dictionary:
	var listing: Dictionary = memory_find(listing_id)
	if listing.is_empty() or listing.status != "active" or int(listing.expires_at) <= unix_now():
		return {"error": "listing_gone"}
	if int(listing.seller_id) == account:
		return {"error": "own_listing"}
	if int(listing.price_solar) != solar or int(listing.price_estrela) != estrela:
		return {"error": "price_changed"}
	var error: String = memory_profile_error(account, profile)
	if error != "":
		return {"error": error}
	var version: int = memory_write_profile(account, profile)
	listing.status = "sold"
	listing.buyer_id = account
	listing.closed_at = unix_now()
	var price: Dictionary = {"solar": int(listing.price_solar), "estrela": int(listing.price_estrela)}
	var mail_id: int = memory_add_mail(account, "purchase", listing, listing.item, {}, {"price": price, "seller": listing.seller_name})
	var proceeds: Dictionary = {}
	for key: String in ["solar", "estrela"]:
		var value: int = int(listing["price_" + key]) - int(listing["fee_" + key])
		if value > 0:
			proceeds[key] = value
	var buyer_name: String = str(profile.get("name", "")) if profile.get("name") != null else ""
	memory_add_mail(int(listing.seller_id), "sale", listing, null, proceeds, {"item_kind": listing.kind, "item": listing.item, "price": price, "fee": {"solar": int(listing.fee_solar), "estrela": int(listing.fee_estrela)}, "buyer": buyer_name})
	return {"version": version, "mail_id": mail_id, "listing": listing, "seller_id": listing.seller_id}

func memory_cancel(account: int, listing_id: int) -> Dictionary:
	var listing: Dictionary = memory_find(listing_id)
	if listing.is_empty():
		return {"error": "listing_gone"}
	if int(listing.seller_id) != account:
		return {"error": "not_yours"}
	if listing.status != "active":
		return {"error": "listing_gone"}
	listing.status = "expired" if int(listing.expires_at) <= unix_now() else "cancelled"
	listing.closed_at = unix_now()
	var mail_id: int = memory_add_mail(account, "returned", listing, listing.item, {}, {"reason": listing.status})
	return {"mail_id": mail_id, "listing": listing}

func memory_claim(account: int, ids: Array, profile: Dictionary) -> Dictionary:
	var chosen: Array[Dictionary] = []
	for mail in memory_mail:
		if ids.has(int(mail.id)) and int(mail.account) == account and not bool(mail.claimed):
			chosen.append(mail)
	if chosen.size() != ids.size():
		return {"error": "mail_gone"}
	var error: String = memory_profile_error(account, profile)
	if error != "":
		return {"error": error}
	var version: int = memory_write_profile(account, profile)
	for mail in chosen:
		mail.claimed = true
	return {"version": version, "claimed": ids}
