class_name LobbyDirectory
extends Node

# Offline stand-in for the game server: bot players, rooms and channel chat.
# Everything here is local and labeled as AI; a network adapter will replace it.

signal chat_added(message: Dictionary)
signal rooms_changed

const NAMES: Array[String] = ["Scorpio", "BRZ", "TonicoXD", "Sifrao", "RealTiny", "PinkPanda", "Barkus", "Enzinho", "Lontrinha", "Mariah", "xBruna", "NeyRJ", "M4ch4do", "MagicMika", "Whinny", "Raposinha", "Kaiser", "DarkLuz", "Pipoca", "Tiroteio", "Zezinho", "Nuvem", "Canhonito", "Faisca", "Brisa", "Trovoada", "Juju", "Mestre", "Pingo", "Vulcan"]
const ROOM_TITLES: Array[String] = ["Guerra de equipes, diversão sem limite", "Desafie e divirta-se!", "A mais valente aventura", "Só tiro de 30 graus", "x1 valendo honra", "Treino de vento forte", "Chega mais, sala amigável"]
const CHAT_LINES: Array[String] = [
	"V> pedra de fortalecimento lvl 5, 30 moedas cada",
	"alguém x1 no Pátio do Templo?",
	"C> Cristal Dourado, pago bem",
	"procuro sociedade ativa, sou nível %d",
	"quem vai no Templo do Sol comigo?",
	"dica: 65 de força com vento a favor chega longe",
	"V> Poção de Energia 12 moedas",
	"bora sala 4x4!!",
	"GG pessoal, boa partida",
	"alguém sabe a força pra meia tela no ângulo 50?",
]
const SPEAKER_LINES: Array[String] = [
	"Parabéns [%s] por abrir o Baú do Templo e ganhar um Ovo de Mascote!",
	"Parabéns! [%s] ganhou [Cristal Dourado] através de Instância.",
	"[%s] alcançou o nível %d! Que fera!",
	"Evento: dobro de mérito no Salão de Jogos neste fim de semana!",
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var bots: Array[Dictionary] = []
var rooms: Array[Dictionary] = []
var history: Array[Dictionary] = []
var speaker: String = ""
var chat_timer: float = 4.0
var room_timer: float = 9.0
var player_level: int = 1

func _ready() -> void:
	rng.randomize()
	if bots.is_empty():
		populate()

func populate() -> void:
	bots.clear()
	for nick in NAMES:
		bots.append(make_bot(nick, clampi(player_level + rng.randi_range(-2, 12), 1, 40)))
	bots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) > int(b.level))
	rooms.clear()
	for i in range(14):
		rooms.append(make_room())
	history.clear()
	post("Sistema", "Modo offline: salas, jogadores e mensagens deste canal são simulados por IA.", "system")
	speaker = SPEAKER_LINES[0] % random_bot().name

func make_bot(nick: String, level: int) -> Dictionary:
	var bot: Dictionary = {"name": nick, "level": level, "gender": "f" if rng.randf() < 0.4 else "m", "human": false, "agility": 120 + level * 8 + rng.randi_range(-20, 20)}
	var skin: String = ""
	var skins: Array[String] = UiKit.available_skins()
	if not skins.is_empty() and rng.randf() < 0.55:
		skin = skins[rng.randi() % skins.size()]
		bot.gender = UiKit.SKIN_GENDER.get(skin, bot.gender)
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

func random_outfit(gender: String) -> String:
	var pool: Array[String] = []
	for def: Dictionary in Armory.data().cosmetics:
		if def.slot == "roupa" and def.gender == gender and ResourceLoader.exists(Armory.skin_path(str(def.skin), "east")):
			pool.append(str(def.skin))
	var base: String = "base_f" if gender == "f" else "base_m"
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
	var fallback: Dictionary = make_bot(NAMES[rng.randi() % NAMES.size()] + str(rng.randi_range(1, 99)), level)
	return fallback

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
	return {"id": id, "title": ROOM_TITLES[rng.randi() % ROOM_TITLES.size()], "mode": "pvp", "capacity": capacity, "members": members, "playing": rng.randf() < 0.3, "map": "", "turn_seconds": 10, "difficulty": "normal"}

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

func post(author: String, text: String, channel: String = "Atual") -> void:
	var message: Dictionary = {"author": author, "text": text, "channel": channel}
	history.append(message)
	if history.size() > 60:
		history.remove_at(0)
	chat_added.emit(message)

func _process(delta: float) -> void:
	chat_timer -= delta
	if chat_timer <= 0:
		chat_timer = rng.randf_range(5.0, 11.0)
		var line: String = CHAT_LINES[rng.randi() % CHAT_LINES.size()]
		if line.contains("%d"):
			line = line % rng.randi_range(5, 30)
		post(random_bot().name, line, "Atual" if rng.randf() < 0.8 else "alto-falante")
		if rng.randf() < 0.3:
			var shout: String = SPEAKER_LINES[rng.randi() % SPEAKER_LINES.size()]
			if shout.count("%") == 2:
				speaker = shout % [random_bot().name, rng.randi_range(10, 40)]
			elif shout.count("%") == 1:
				speaker = shout % random_bot().name
			else:
				speaker = shout
	room_timer -= delta
	if room_timer <= 0:
		room_timer = rng.randf_range(8.0, 14.0)
		# Rooms start and finish battles, and new ones open, like a live channel.
		var index: int = rng.randi() % rooms.size()
		if rooms[index].playing and rng.randf() < 0.5:
			rooms.remove_at(index)
			rooms.append(make_room())
		else:
			rooms[index].playing = not rooms[index].playing
		rooms_changed.emit()
