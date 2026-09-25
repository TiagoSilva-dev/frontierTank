class_name PlayerSession
extends RefCounted

# One logged-in player on the game server: the WebSocket, the account, the server's copy
# of the profile (the authority) and where the player is (room, battle, result cards).

var peer: WebSocketPeer
var peer_id: int = 0
var account_id: int = 0
var username: String = ""
var profile: PlayerProfile
# Version of the profile in the database; saves send it back (optimistic locking).
var version: int = 0
var dirty: bool = false
var saving: bool = false
var state: String = "handshake"
var room: ServerRoom = null
var host: MatchHost = null
var watching_lobby: bool = false
# Disconnected in the middle of a battle: kept until the battle ends so the rewards
# still reach the profile (and the player may come back).
var lingering: bool = false
var chat_times: Array[float] = []
var connected_at: float = 0.0
var last_seen: float = 0.0
# Reward cards after a battle: {"cards", "picks", "revealed"}; never sent before a pick.
var result: Dictionary = {}
# Leilão (0.12): an auction or mail operation is writing this profile through the API
# (one at a time; other profile changes wait). `discard`: the API may or may not have
# done it, so this copy is dropped unsaved and the next login reads the stored one.
var busy: bool = false
var discard: bool = false
var last_search: float = 0.0
# Attempts to delete the account (wrong passwords are limited).
var delete_tries: Array[float] = []
# The player's game language ("pt_BR" or "en"), told in hello: the Steam order text.
var locale: String = "pt_BR"

func is_open() -> bool:
	return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN

func send(message: Dictionary) -> void:
	if is_open():
		peer.send_text(JSON.stringify(message))

func display_name() -> String:
	return profile.player_name if profile != null else username

func public_info() -> Dictionary:
	return {"account": account_id, "name": display_name(), "level": profile.level() if profile != null else 1, "gender": profile.gender if profile != null else "m"}
