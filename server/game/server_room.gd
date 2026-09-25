class_name ServerRoom
extends RefCounted

# A room on the game server: players (and AI bots the owner invited), the owner, the
# battle settings and whether it is waiting, searching for rivals or playing.

var id: int = 0
var mode: String = "pvp"
var title: String = ""
var capacity: int = 4
# Each member: {"session": PlayerSession, "ready": bool} or {"bot": Dictionary}.
var members: Array[Dictionary] = []
var owner: int = 0
var map: String = ""
var turn_seconds: int = 10
var instance: String = "templo_sol"
var map_uid: int = -1
var state: String = "waiting"
var search_since: float = 0.0
var host: MatchHost = null

func humans() -> Array[PlayerSession]:
	var list: Array[PlayerSession] = []
	for member in members:
		if member.has("session"):
			list.append(member.session)
	return list

func index_of(session: PlayerSession) -> int:
	for i in range(members.size()):
		if members[i].get("session") == session:
			return i
	return -1

func owner_session() -> PlayerSession:
	if owner < members.size() and members[owner].has("session"):
		return members[owner].session
	return null

func is_full() -> bool:
	return members.size() >= capacity

func add(session: PlayerSession) -> void:
	members.append({"session": session, "ready": false})

# Removes a player; the next player becomes the owner. Returns true when no player is
# left (the room closes; bots never keep a room open).
func remove(session: PlayerSession) -> bool:
	var index: int = index_of(session)
	if index < 0:
		return humans().is_empty()
	members.remove_at(index)
	if humans().is_empty():
		return true
	if index == owner or owner >= members.size():
		for i in range(members.size()):
			if members[i].has("session"):
				owner = i
				break
	elif index < owner:
		owner -= 1
	return false

func all_ready() -> bool:
	for i in range(members.size()):
		if i != owner and members[i].has("session") and not members[i].get("ready", false):
			return false
	return true

func average_level() -> int:
	var total: int = 0
	for member in members:
		total += int(member.session.profile.level()) if member.has("session") else int(member.bot.level)
	return total / maxi(1, members.size())

func map_item() -> Dictionary:
	var session: PlayerSession = owner_session()
	if mode != "pve" or session == null:
		return {}
	return session.profile.find_map(map_uid)

# What the players see: the list in the Salão (brief) or the room itself.
func summary() -> Dictionary:
	var people: Array = []
	for member in members:
		var who: Dictionary = member.session.public_info() if member.has("session") else member.bot
		people.append({"name": str(who.name), "level": int(who.level), "human": member.has("session")})
	return {"id": id, "title": title, "mode": mode, "capacity": capacity, "members": people, "playing": state == "playing", "map": map}

func details(balance: Dictionary) -> Dictionary:
	var people: Array = []
	for i in range(members.size()):
		var member: Dictionary = members[i]
		if member.has("session"):
			var session: PlayerSession = member.session
			var entry: Dictionary = session.profile.entry(balance)
			entry.account = session.account_id
			entry.ready = bool(member.get("ready", false)) or i == owner
			people.append(entry)
		else:
			var bot: Dictionary = member.bot.duplicate()
			bot.ready = true
			people.append(bot)
	return {"id": id, "title": title, "mode": mode, "capacity": capacity, "members": people, "owner": owner, "map": map, "turn_seconds": turn_seconds, "instance": instance, "map_uid": map_uid, "map_item": map_item(), "state": state, "playing": state == "playing", "searching": state == "searching"}
