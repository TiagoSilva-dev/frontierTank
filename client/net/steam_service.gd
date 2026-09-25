class_name SteamService
extends Node

# Steam through GodotSteam (launch checklist, roadmap item 4): login with a ticket for the
# Web API, the approval of purchases in the Steam overlay and the achievements.
# GodotSteam is optional: it is a GDExtension installed in addons/godotsteam only for the
# Steam builds (see docs/STEAM.md). Without it (web, tests, a plain build) `available` is
# false and the game keeps accounts and passwords. Everything is called by name on the
# "Steam" singleton, so the project also runs where the extension is missing.

signal purchase_answered(order_id: int, authorized: bool)

# 0: Steam decides (the game was launched by Steam, or steam_appid.txt sits next to the
# executable while developing). Put the real app id here once Valve assigns it.
const APP_ID: int = 0
# The same text as STEAM_IDENTITY in the API: tickets are made for this service.
const TICKET_IDENTITY: String = "frontiertank"
const RESULT_OK: int = 1

# Tests put a fake object here, with the same methods and signals as GodotSteam's.
static var override: Object = null

var steam: Object = null
var available: bool = false
var persona: String = ""
var init_error: String = ""
var unlocked: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if override != null:
		steam = override
	elif not OS.has_feature("web") and Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")
	if steam == null:
		return
	var result: Dictionary = init_steam()
	available = int(result.get("status", 1)) == 0
	if not available:
		init_error = str(result.get("verbal", ""))
		push_warning("Steam: %s" % init_error)
		return
	persona = str(steam.call("getPersonaName"))
	steam.connect("microtransaction_auth_response", _on_microtransaction)

# GodotSteam changed the order of steamInitEx's arguments between versions: ask for the
# names before calling. Callbacks are run by this node (not embedded).
func init_steam() -> Dictionary:
	var names: Array = []
	for method: Dictionary in steam.get_method_list():
		if str(method.name) == "steamInitEx":
			names = (method.args as Array).map(func(arg: Dictionary) -> String: return str(arg.name))
	var result: Variant
	if not names.is_empty() and names[0] == "retrieve_stats":
		result = steam.call("steamInitEx", false, APP_ID, false)
	else:
		result = steam.call("steamInitEx", APP_ID, false)
	if result is Dictionary:
		return result
	return {"status": 0 if result == true else 1, "verbal": str(result)}

func _process(_delta: float) -> void:
	if available:
		steam.call("run_callbacks")

# A ticket for the API (hex), or "" when Steam is not there or did not answer.
func web_ticket(seconds: float = 10.0) -> String:
	if not available:
		return ""
	var answer: Array = []
	var catch: Callable = func(_handle: int, result: int, _size: int, buffer: Variant) -> void:
		answer.append([result, buffer])
	steam.connect("get_ticket_for_web_api", catch)
	steam.call("getAuthTicketForWebApi", TICKET_IDENTITY)
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while answer.is_empty() and Time.get_ticks_msec() < deadline and is_inside_tree():
		await get_tree().process_frame
	steam.disconnect("get_ticket_for_web_api", catch)
	if answer.is_empty() or int(answer[0][0]) != RESULT_OK:
		return ""
	var buffer: Variant = answer[0][1]
	var bytes: PackedByteArray = buffer if buffer is PackedByteArray else PackedByteArray(buffer)
	return bytes.hex_encode()

func _on_microtransaction(_app_id: int, order_id: int, authorized: bool) -> void:
	purchase_answered.emit(order_id, authorized)

# Waits for the player's answer in the overlay: 1 approved, 0 refused, -1 no answer.
func wait_purchase(order_id: int, seconds: float = 600.0) -> int:
	var state: Array = [-1]
	var catch: Callable = func(id: int, authorized: bool) -> void:
		if id == order_id:
			state[0] = 1 if authorized else 0
	purchase_answered.connect(catch)
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while state[0] < 0 and Time.get_ticks_msec() < deadline and is_inside_tree():
		await get_tree().process_frame
	purchase_answered.disconnect(catch)
	return state[0]

# Unlocks the achievements the online profile reached; returns the new ones.
func sync_achievements(profile: PlayerProfile) -> Array[String]:
	var fresh: Array[String] = []
	if not available:
		return fresh
	for id: String in Achievements.reached(profile):
		if unlocked.has(id):
			continue
		var state: Variant = steam.call("getAchievement", id)
		if state is Dictionary and bool(state.get("achieved", false)):
			unlocked[id] = true
			continue
		if bool(steam.call("setAchievement", id)):
			unlocked[id] = true
			fresh.append(id)
	if not fresh.is_empty():
		steam.call("storeStats")
	return fresh
