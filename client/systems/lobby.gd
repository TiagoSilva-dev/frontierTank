class_name LobbyDirectory
extends Node

# Offline stand-in for the game server: bot players, rooms and channel chat.
# Everything here is local and labeled as AI; a network adapter will replace it. The game
# server also keeps one (never added to the tree): its simulated players fill the Salão of a
# young server and the rival side of a battle (server/game/game_server.gd, docs/BOTS.md).

signal chat_added(message: Dictionary)
signal rooms_changed

const ROOM_TITLES: Array[String] = ["Guerra de equipes, diversão sem limite", "Desafie e divirta-se!", "A mais valente aventura", "Só tiro de 30 graus", "x1 valendo honra", "Treino de vento forte", "Chega mais, sala amigável"]  # i18n
const CHAT_LINES: Array[String] = [
	"V> pedra de fortalecimento lvl 5, 30 moedas cada",  # i18n
	"alguém x1 no Pátio do Templo?",  # i18n
	"C> Cristal Dourado, pago bem",  # i18n
	"procuro sociedade ativa, sou nível %d",  # i18n
	"quem vai no Templo do Sol comigo?",  # i18n
	"dica: 65 de força com vento a favor chega longe",  # i18n
	"V> Poção de Energia 12 moedas",  # i18n
	"bora sala 4x4!!",  # i18n
	"GG pessoal, boa partida",  # i18n
	"alguém sabe a força pra meia tela no ângulo 50?",  # i18n
]
# What a simulated player answers to a private message (the offline channel).
const WHISPER_REPLIES: Array[String] = [
	"oi! tudo bem?",  # i18n
	"valeu pela mensagem!",  # i18n
	"bora jogar uma partida?",  # i18n
	"agora estou em batalha, falo contigo depois",  # i18n
	"GG! foi uma boa partida",  # i18n
	"vou criar uma sala 2x2, entra lá!",  # i18n
	"tô sem moedas hoje, haha",  # i18n
]
const SPEAKER_LINES: Array[String] = [
	"Parabéns [%s] por abrir o Baú do Templo e ganhar um Ovo de Mascote!",  # i18n
	"Parabéns! [%s] ganhou [Cristal Dourado] através de Instância.",  # i18n
	"[%s] alcançou o nível %d! Que fera!",  # i18n
	"Evento: dobro de mérito no Salão de Jogos neste fim de semana!",  # i18n
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
# How many simulated players `populate` makes, and whether their levels follow a server's
# (many beginners) instead of the player's (a little above them).
var population: int = 30
var server_levels: bool = false
# The game server's battles are real (BotArena): its rooms here only wait, they never "play"
# on their own the way the offline channel's do.
var real_battles: bool = false
var bots: Array[Dictionary] = []
var rooms: Array[Dictionary] = []
var history: Array[Dictionary] = []
var speaker: String = ""
var chat_timer: float = 4.0
var room_timer: float = 9.0
var player_level: int = 1
# Players whose lines this player hid (report dialog), by account; only this session.
var ignored: Dictionary = {}
# The player a private message goes to ({"name", "account"}; empty: none picked yet) and the
# private lines that arrived while the Privado tab was not open.
var whisper_target: Dictionary = {}
var unread_private: int = 0
# This player's own name (the lines of others are the unread ones).
var my_name: String = ""

# Capture helper (--seed=): the same bots and rooms every run, so a video can be recorded twice.
static var fixed_seed: int = -1

func _ready() -> void:
	if fixed_seed >= 0:
		rng.seed = fixed_seed
	else:
		rng.randomize()
	if bots.is_empty():
		populate()

func populate() -> void:
	bots.clear()
	rooms.clear()
	for i in range(population):
		bots.append(make_bot(BotRoster.level_for(rng) if server_levels else clampi(player_level + rng.randi_range(-2, 12), 1, 40)))
	bots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
	for i in range(14):
		rooms.append(make_room())
	history.clear()
	post("Sistema", tr("Modo offline: salas, jogadores e mensagens deste canal são simulados por IA."), "system")
	speaker = tr(SPEAKER_LINES[0]) % random_bot().name

# A simulated player: look, gear, a skill that follows the level and a believable nickname,
# not yet used here (`nick` forces one).
func make_bot(level: int, nick: String = "") -> Dictionary:
	var gender: String = "f" if rng.randf() < 0.4 else "m"
	var skin: String = ""
	var skins: Array[String] = UiKit.available_skins()
	if not skins.is_empty() and rng.randf() < 0.55:
		skin = skins[rng.randi() % skins.size()]
		gender = UiKit.SKIN_GENDER.get(skin, gender)
	if nick == "":
		nick = BotRoster.make_name(rng, gender, names_in_use())
	var bot: Dictionary = {"name": nick, "level": level, "gender": gender, "human": false, "agility": 120 + level * 8 + rng.randi_range(-20, 20), "skill": BotRoster.skill_for(rng, level)}
	# Weapon, quality, strengthen level (aura) and accessories, like other DDTank players.
	var loadout: Dictionary = Armory.random_loadout(rng, level, bot.gender, skin)
	if skin == "":
		loadout.look.skin = random_outfit(bot.gender)
	bot.arma = loadout.arma
	bot.look = loadout.look
	bot.attrs = loadout.attrs
	bot.skin = loadout.look.skin
	if rng.randf() < 0.3:
		bot.aux = ["dom_de_anjo", "escudo_bugou", "dom_de_anjo_v", "escudo_barao"][rng.randi() % 4]
	return bot

# The lower-cased names of everyone in the list and in the rooms.
func names_in_use() -> Dictionary:
	var used: Dictionary = {}
	for bot: Dictionary in bots:
		used[str(bot.name).to_lower()] = true
	for room: Dictionary in rooms:
		for member: Dictionary in room.members:
			used[str(member.name).to_lower()] = true
	return used

# A player leaves the channel and another arrives (the list of a live server is never still).
func rotate_bot() -> void:
	if bots.is_empty():
		return
	var index: int = rng.randi() % bots.size()
	var level: int = BotRoster.level_for(rng) if server_levels else clampi(int(bots[index].level) + rng.randi_range(-2, 2), 1, 40)
	bots[index] = make_bot(level)
	bots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))

func random_outfit(gender: String) -> String:
	var pool: Array[String] = []
	for def: Dictionary in Armory.data().cosmetics:
		if def.slot == "skin" and def.gender == gender and ResourceLoader.exists(Armory.skin_path(str(def.skin), "east")):
			pool.append(str(def.skin))
	var base: String = "lani" if gender == "f" else "base_m"
	if ResourceLoader.exists(Armory.skin_path(base, "east")):
		pool.append(base)
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else base

func random_bot() -> Dictionary:
	return bots[rng.randi() % bots.size()]

func bot_near(level: int, exclude: Array = []) -> Dictionary:
	# Opponents and invitees of similar level ("seleciona equipes com níveis próximos").
	for attempt in range(40):
		var bot: Dictionary = random_bot()
		if absi(int(bot.level) - level) <= 4 + attempt / 5 and not exclude.has(bot.name):
			return bot.duplicate()
	return make_bot(level)

func make_room() -> Dictionary:
	var host: Dictionary = random_bot()
	var members: Array = [host.duplicate()]
	var capacity: int = [1, 2, 2, 3, 4, 4][rng.randi() % 6]
	var count: int = rng.randi_range(1, capacity)
	while members.size() < count:
		members.append(bot_near(int(host.level), members.map(func(m: Dictionary) -> String: return m.name)))
	var id: int = rng.randi_range(100, 999)
	while find_room(id).size() > 0:
		id = rng.randi_range(100, 999)
	var title: String = tr(ROOM_TITLES[rng.randi() % ROOM_TITLES.size()])
	return {"id": id, "title": title, "mode": "pvp", "capacity": capacity, "members": members, "playing": not real_battles and rng.randf() < 0.3, "map": "", "turn_seconds": 10}

func find_room(id: int) -> Dictionary:
	for room in rooms:
		if int(room.id) == id:
			return room
	return {}

func open_room() -> Dictionary:
	for room in rooms:
		if not room.playing and room.members.size() < int(room.capacity):
			return room
	return {}

# `extra`: online lines carry the message id and the author's account (to report them).
func post(author: String, text: String, channel: String = "Atual", extra: Dictionary = {}) -> void:
	var message: Dictionary = {"author": author, "text": text, "channel": channel}
	message.merge(extra)
	if channel == "Privado" and author != my_name and not bool(extra.get("mine", false)):
		unread_private += 1
	history.append(message)
	if history.size() > 60:
		history.remove_at(0)
	chat_added.emit(message)

# A private message from this player. The offline channel answers for the simulated ones.
func whisper(target: Dictionary, text: String, sender: String) -> void:
	post(sender, text, "Privado", {"to": str(target.get("name", "")), "mine": true})
	var reply_to: String = str(target.get("name", ""))
	if not is_inside_tree():
		return
	await get_tree().create_timer(rng.randf_range(1.4, 3.6)).timeout
	if is_inside_tree():
		post(reply_to, tr(WHISPER_REPLIES[rng.randi() % WHISPER_REPLIES.size()]), "Privado", {"to": sender})

# The public profile of a player of the list: the simulated ones are known here, the online
# ones are asked from the server (OnlineLobby).
func profile_of(person: Dictionary) -> Dictionary:
	var level: int = int(person.get("level", 1))
	var info: Dictionary = person.duplicate(true)
	info["victories"] = int(person.get("victories", level * 3 + (str(person.get("name", "")).hash() % 7)))
	info["matches"] = int(person.get("matches", int(info.victories) * 2 + 4))
	info["merits"] = int(person.get("merits", level * 11))
	info["ranking"] = int(person.get("ranking", maxi(0, int(info.victories) / 3)))
	return info

func ignore(account: int) -> void:
	ignored[account] = true
	chat_added.emit({})

func _process(delta: float) -> void:
	tick_chat(delta)
	tick_rooms(delta)

func tick_chat(delta: float) -> void:
	chat_timer -= delta
	if chat_timer <= 0:
		chat_timer = rng.randf_range(5.0, 11.0)
		# Simulated players chat in the game's language.
		var line: String = tr(CHAT_LINES[rng.randi() % CHAT_LINES.size()])
		if line.contains("%d"):
			line = line % rng.randi_range(5, 30)
		post(random_bot().name, line, "Atual" if rng.randf() < 0.8 else "alto-falante")
		if rng.randf() < 0.3:
			var shout: String = tr(SPEAKER_LINES[rng.randi() % SPEAKER_LINES.size()])
			if shout.count("%") == 2:
				speaker = shout % [random_bot().name, rng.randi_range(10, 40)]
			elif shout.count("%") == 1:
				speaker = shout % random_bot().name
			else:
				speaker = shout

# Returns whether a room changed (the server sends the list again).
func tick_rooms(delta: float) -> bool:
	room_timer -= delta
	if room_timer > 0 or rooms.is_empty():
		return false
	room_timer = rng.randf_range(8.0, 14.0)
	# Rooms start and finish battles, and new ones open, like a live channel.
	var index: int = rng.randi() % rooms.size()
	if real_battles:
		# A room closes and another opens; the battles are the arena's.
		if rng.randf() >= 0.5:
			return false
		rooms.remove_at(index)
		rooms.append(make_room())
	elif rooms[index].playing and rng.randf() < 0.5:
		rooms.remove_at(index)
		rooms.append(make_room())
	else:
		rooms[index].playing = not rooms[index].playing
	rooms_changed.emit()
	return true
