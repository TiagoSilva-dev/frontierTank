class_name BotRoster
extends RefCounted

# The simulated players (Salão, rooms, rivals that fill a battle): believable nicknames, so
# nobody reads "Bot 3" in the list, and a skill that grows with the level. Pure functions on
# the caller's seeded rng: the same seed gives the same people.

const MAX_LENGTH: int = 14
const NAMES_PATH: String = "res://shared/balance/bot_names.json"

# Words a nickname never carries (or reads as an AI), whatever the pieces made.
const FORBIDDEN: Array[String] = ["bot", "cpu", "npc", "robo", "robot", "autom", "sistema", "admin"]
const LEET: Dictionary = {"a": "4", "e": "3", "i": "1", "o": "0"}

# The pieces nicknames are made of (shared/balance/bot_names.json): first names and short
# nicknames of each gender, then words, prefixes and states.
static var pools: Dictionary = {}

static func pool(key: String) -> Array[String]:
	if pools.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NAMES_PATH))
		for name: String in data:
			var list: Array[String] = []
			for entry: Variant in data[name]:
				list.append(str(entry))
			pools[name] = list
	return pools[key]

# A nickname that passes the same rule as a player's (PlayerProfile.valid_name), is not in
# `taken` (lower-cased names) and does not look like a program's.
static func make_name(rng: RandomNumberGenerator, gender: String, taken: Dictionary = {}) -> String:
	for attempt in range(80):
		var nick: String = compose(rng, gender)
		if acceptable(nick) and not taken.has(nick.to_lower()):
			return nick
	# A crowded pool: a number makes it unique.
	var base: String = pick(pool("female") if gender == "f" else pool("male"), rng)
	var nick: String = base
	while taken.has(nick.to_lower()) or not acceptable(nick):
		nick = "%s%d" % [base, rng.randi_range(2, 9999)]
	return nick

static func acceptable(nick: String) -> bool:
	return nick.length() >= 3 and nick.length() <= MAX_LENGTH and PlayerProfile.valid_name(nick) and not looks_like_bot(nick)

static func looks_like_bot(nick: String) -> bool:
	var low: String = nick.to_lower()
	for word: String in FORBIDDEN:
		if low.contains(word):
			return true
	for tail: String in ["_ia", ".ia", "-ia", "_ai", ".ai", "-ai"]:
		if low.ends_with(tail):
			return true
	return false

static func pick(list: Array[String], rng: RandomNumberGenerator) -> String:
	return list[rng.randi() % list.size()]

# One piece of a nickname per roll; the number styles are the usual ones (birth year, a
# lucky number, a state).
static func compose(rng: RandomNumberGenerator, gender: String) -> String:
	var first: String = pick(pool("female") if gender == "f" else pool("male"), rng) if rng.randf() < 0.8 else pick(pool("short_female" if gender == "f" else "short_male"), rng)
	var word: String = pick(pool("words"), rng)
	var roll: float = rng.randf()
	var nick: String
	if roll < 0.10:
		nick = first
	elif roll < 0.28:
		nick = first + number(rng)
	elif roll < 0.38:
		nick = first + char(65 + rng.randi() % 26)
	elif roll < 0.48:
		nick = "%s_%s" % [first, pick(pool("states"), rng)]
	elif roll < 0.55:
		nick = ("x" if rng.randf() < 0.6 else "xX") + first
	elif roll < 0.68:
		nick = word + number(rng)
	elif roll < 0.76:
		nick = pick(pool("prefixes"), rng) + word
	elif roll < 0.84:
		nick = word + pick(pool("words"), rng)
	elif roll < 0.90:
		nick = "%s_%s" % [first, word] if rng.randf() < 0.5 else "%s.%s" % [first, pick(pool("states"), rng).to_lower()]
	elif roll < 0.95:
		nick = first.to_lower() + ("_" if rng.randf() < 0.5 else "") + str(rng.randi_range(1, 99))
	else:
		nick = word
	if rng.randf() < 0.06:
		nick = leet(nick, rng)
	return nick

static func number(rng: RandomNumberGenerator) -> String:
	var roll: float = rng.randf()
	if roll < 0.35:
		return "%02d" % rng.randi_range(0, 99)
	if roll < 0.60:
		return str(rng.randi_range(1992, 2010))
	if roll < 0.80:
		return str(rng.randi_range(1, 9))
	return ["10", "13", "22", "77", "99", "07", "666", "123", "00", "69"][rng.randi() % 10]

# One letter swapped for its look-alike digit (M4theus).
static func leet(nick: String, rng: RandomNumberGenerator) -> String:
	var spots: Array[int] = []
	for i in range(nick.length()):
		if LEET.has(nick[i].to_lower()):
			spots.append(i)
	if spots.is_empty():
		return nick
	var at: int = spots[rng.randi() % spots.size()]
	return nick.substr(0, at) + str(LEET[nick[at].to_lower()]) + nick.substr(at + 1)

# How well a simulated player aims, 0 (novice) to 1 (expert): it grows with the level, with a
# spread so two players of the same level are not equal.
static func skill_for(rng: RandomNumberGenerator, level: int) -> float:
	var base: float = lerpf(0.12, 0.85, clampf((float(level) - 1.0) / 39.0, 0.0, 1.0))
	return snappedf(clampf(base + rng.randfn(0.0, 0.12), 0.05, 0.97), 0.01)

# The level of a resident player of a new server: many beginners, few veterans.
static func level_for(rng: RandomNumberGenerator) -> int:
	return clampi(1 + int(39.0 * pow(rng.randf(), 1.8)), 1, 40)
