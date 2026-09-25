extends Object

# Newer GodotSteam: steamInitEx(app_id, embed_callbacks), without retrieve_stats.

signal microtransaction_auth_response(app_id: int, order_id: int, authorized: bool)

var init_args: Array = []

func steamInitEx(app_id: int = 0, embed_callbacks: bool = false) -> Dictionary:
	init_args = [app_id, embed_callbacks]
	return {"status": 0, "verbal": "Steamworks active."}

func getPersonaName() -> String:
	return "Nova API"

func run_callbacks() -> void:
	pass
