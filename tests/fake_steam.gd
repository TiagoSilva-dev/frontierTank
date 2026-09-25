extends Object

# A stand-in for GodotSteam's "Steam" singleton in the tests (SteamService.override):
# the same method names and signals, with the callbacks delivered by run_callbacks()
# like the real one. `approve` plays the player answering the purchase in the overlay.

signal get_ticket_for_web_api(auth_ticket: int, result: int, ticket_size: int, ticket_buffer: Array)
signal microtransaction_auth_response(app_id: int, order_id: int, authorized: bool)

var persona: String = "Jogadora Steam"
var pending: Array[Callable] = []
var achievements: Dictionary = {}
var stored: int = 0
var tickets: int = 0
var init_args: Array = []

func steamInitEx(retrieve_stats: bool = false, app_id: int = 0, embed_callbacks: bool = false) -> Dictionary:
	init_args = [retrieve_stats, app_id, embed_callbacks]
	return {"status": 0, "verbal": "Steamworks active."}

func getPersonaName() -> String:
	return persona

func run_callbacks() -> void:
	var due: Array[Callable] = pending.duplicate()
	pending.clear()
	for call in due:
		call.call()

func getAuthTicketForWebApi(service_identity: String = "") -> int:
	tickets += 1
	var handle: int = tickets
	var bytes: Array = [0x14, 0x00, 0xAB, 0xCD, service_identity.length()]
	bytes.resize(24)
	bytes.fill(0)
	bytes[0] = 0x14
	bytes[2] = 0xAB
	bytes[3] = 0xCD
	bytes[4] = service_identity.length()
	pending.append(func() -> void: get_ticket_for_web_api.emit(handle, 1, bytes.size(), bytes))
	return handle

func approve(order_id: int, authorized: bool = true) -> void:
	pending.append(func() -> void: microtransaction_auth_response.emit(480, order_id, authorized))

func getAchievement(achievement_name: String) -> Dictionary:
	return {"ret": true, "achieved": achievements.has(achievement_name)}

func setAchievement(achievement_name: String) -> bool:
	achievements[achievement_name] = true
	return true

func storeStats() -> bool:
	stored += 1
	return true
