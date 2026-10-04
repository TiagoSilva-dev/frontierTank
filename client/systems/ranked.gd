class_name Ranked
extends RefCounted

# Ranked ladder (0.22): a rating (Elo) per season for 1v1 matches between real players,
# divisions Bronze to Mestre with three tiers each, a seasonal soft reset and cosmetic
# titles for the division reached. The numbers live in shared/balance/ranked.json.
#
# The rating lives in the profile (`rating`), and only the game server changes it (after a
# ranked match, in MatchHost.settle): no profile operation can. The rules here are pure
# functions of the rating and the clock, so the server, the screens and the tests agree.
# Titles (`titles`, `title`) are cosmetic: a name shown in the profile, the nameplate and
# the lists.

const PATH: String = "res://shared/balance/ranked.json"
const ROMAN: Array[String] = ["I", "II", "III"]
static var _data: Dictionary = {}
# Tests move the clock to see a season end (seconds added to the real time).
static var clock_offset: int = 0

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_offset

# ---------- seasons ----------

static func epoch_day() -> int:
	return floori(Time.get_unix_time_from_datetime_string(str(data().season.epoch)) / 86400.0)

static func season_days() -> int:
	return int(data().season.days)

# 1-based number of the season that contains `timestamp` (before the epoch counts as 1).
static func season_of(timestamp: int = -1) -> int:
	var at: int = timestamp if timestamp >= 0 else now()
	var day: int = floori(at / 86400.0)
	return maxi(1, 1 + floori(float(day - epoch_day()) / float(season_days())))

# Unix time at which `season` ends (the start of the next one).
static func season_end(season: int) -> int:
	return (epoch_day() + season * season_days()) * 86400

static func seconds_left(timestamp: int = -1) -> int:
	var at: int = timestamp if timestamp >= 0 else now()
	return maxi(0, season_end(season_of(at)) - at)

# ---------- divisions ----------

# The division of a rating: {index, id, name, color, tier (1 = best, `tiers` = lowest),
# tiers, from (lowest rating of this tier), next (lowest rating of the next tier, -1 at the top)}.
static func division(mmr: int) -> Dictionary:
	var list: Array = data().divisions
	var index: int = 0
	for i in range(list.size()):
		if mmr >= int(list[i].from):
			index = i
	var entry: Dictionary = list[index]
	var tiers: int = int(entry.tiers)
	var top: bool = index + 1 >= list.size()
	var width: float = 0.0 if top else float(int(list[index + 1].from) - int(entry.from)) / float(tiers)
	var step: int = mini(tiers - 1, maxi(0, floori(float(mmr - int(entry.from)) / width))) if width > 0.0 else 0
	var from: int = int(entry.from) + roundi(width * step)
	var next: int = -1
	if step + 1 < tiers:
		next = int(entry.from) + roundi(width * (step + 1))
	elif not top:
		next = int(list[index + 1].from)
	return {"index": index, "id": str(entry.id), "name": str(entry.name), "color": Color(str(entry.color)), "tier": tiers - step, "tiers": tiers, "from": from, "next": next}

# "Prata II" (the top division has no tier).
static func label(mmr: int) -> String:
	var info: Dictionary = division(mmr)
	if int(info.tiers) <= 1:
		return Lang.t(str(info.name))
	return "%s %s" % [Lang.t(str(info.name)), ROMAN[clampi(int(info.tier) - 1, 0, 2)]]

static func placed(rating: Dictionary) -> bool:
	return int(rating.get("games", 0)) >= int(data().placement_games)

# What the screens show as the rank: the division, or the placement progress.
static func rating_label(rating: Dictionary) -> String:
	if placed(rating):
		return label(int(rating.mmr))
	return Lang.t("Em avaliação (%d/%d)") % [int(rating.get("games", 0)), int(data().placement_games)]

# ---------- the rating itself ----------

static func empty_rating(season: int = 1) -> Dictionary:
	var start: int = int(data().start)
	return {"season": season, "mmr": start, "games": 0, "wins": 0, "losses": 0, "career": 0, "peak": start, "streak": 0, "log": []}

static func clean_log(raw: Variant) -> Array:
	var log: Array = []
	if not raw is Array:
		return log
	var ids: Array = data().divisions.map(func(entry: Dictionary) -> String: return str(entry.id))
	for item: Variant in raw:
		if item is Dictionary and str(item.get("division", "")) in ids and int(item.get("season", 0)) > 0:
			log.append({"season": int(item.season), "mmr": maxi(0, int(item.get("mmr", 0))), "division": str(item.division), "games": maxi(0, int(item.get("games", 0))), "wins": maxi(0, int(item.get("wins", 0))), "claimed": bool(item.get("claimed", false))})
	log.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.season) < int(b.season))
	return log.slice(maxi(0, log.size() - int(data().season.log)))

static func clean_rating(raw: Variant, timestamp: int = -1) -> Dictionary:
	var clean: Dictionary = empty_rating(season_of(timestamp))
	if not raw is Dictionary:
		return clean
	var start: int = int(data().start)
	clean.season = maxi(1, int(raw.get("season", clean.season)))
	var saved_mmr: Variant = raw.get("mmr", start)
	clean.mmr = clampi(int(saved_mmr) if saved_mmr is int or saved_mmr is float else start, int(data().floor), 9999)
	for key: String in ["games", "wins", "losses", "career"]:
		clean[key] = maxi(0, int(raw.get(key, 0)))
	clean.peak = maxi(int(clean.mmr), int(raw.get("peak", clean.mmr)))
	clean.streak = clampi(int(raw.get("streak", 0)), -99, 99)
	clean.log = clean_log(raw.get("log", []))
	return clean

# Moves a rating to the season of `timestamp`: the seasons that ended are archived (when
# enough games were played, for the title) and the rating is pulled toward the anchor.
# Returns whether anything changed.
static func sync(rating: Dictionary, timestamp: int = -1) -> bool:
	var current: int = season_of(timestamp)
	if int(rating.season) >= current:
		return false
	var rules: Dictionary = data().season
	if int(rating.games) >= int(rules.min_games):
		rating.log.append({"season": int(rating.season), "mmr": int(rating.mmr), "division": str(division(int(rating.mmr)).id), "games": int(rating.games), "wins": int(rating.wins), "claimed": false})
		rating.log = clean_log(rating.log)
	var anchor: int = int(rules.anchor)
	rating.mmr = maxi(int(data().floor), anchor + roundi(float(int(rating.mmr) - anchor) * float(rules.keep)))
	rating.peak = int(rating.mmr)
	rating.games = 0
	rating.wins = 0
	rating.losses = 0
	rating.streak = 0
	rating.season = current
	return true

static func expected(mmr: int, opponent: int) -> float:
	return 1.0 / (1.0 + pow(10.0, float(opponent - mmr) / 400.0))

# Points gained or lost for `outcome` (1 win, 0 loss, 0.5 draw): Elo with a bigger K for a
# new player. A win always gives at least 1 and a loss always costs at least 1.
static func delta(rating: Dictionary, opponent: int, outcome: float) -> int:
	var k: float = float(data().k_new if int(rating.career) < int(data().new_games) else data().k)
	var points: int = roundi(k * (outcome - expected(int(rating.mmr), opponent)))
	if outcome > 0.5:
		return maxi(1, points)
	if outcome < 0.5:
		return mini(-1, points)
	return points

# Applies one finished match and returns what happened for the result screen.
static func apply_result(rating: Dictionary, opponent: int, outcome: float) -> Dictionary:
	var before: int = int(rating.mmr)
	var was_placed: bool = placed(rating)
	var change: int = delta(rating, opponent, outcome)
	rating.mmr = maxi(int(data().floor), before + change)
	rating.peak = maxi(int(rating.peak), int(rating.mmr))
	rating.games = int(rating.games) + 1
	rating.career = int(rating.career) + 1
	if outcome > 0.5:
		rating.wins = int(rating.wins) + 1
		rating.streak = maxi(1, int(rating.streak) + 1)
	elif outcome < 0.5:
		rating.losses = int(rating.losses) + 1
		rating.streak = mini(-1, int(rating.streak) - 1)
	else:
		rating.streak = 0
	var old_division: Dictionary = division(before)
	var new_division: Dictionary = division(int(rating.mmr))
	return {"delta": int(rating.mmr) - before, "before": before, "after": int(rating.mmr), "games": int(rating.games), "placed": placed(rating), "placing": not was_placed, "up": int(new_division.index) * 10 + (int(new_division.tiers) - int(new_division.tier)) > int(old_division.index) * 10 + (int(old_division.tiers) - int(old_division.tier)), "streak": int(rating.streak)}

# ---------- titles ----------

static func title_id(season: int, division_id: String) -> String:
	return "s%d_%s" % [season, division_id]

# The text of a title id ("s1_ouro" -> "Ouro · Temporada 1"); "" for an unknown id.
static func title_text(id: String) -> String:
	var parts: PackedStringArray = id.split("_", true, 1)
	if parts.size() != 2 or not parts[0].begins_with("s") or not parts[0].substr(1).is_valid_int():
		return ""
	for entry: Dictionary in data().divisions:
		if str(entry.id) == parts[1]:
			return Lang.t("%s · Temporada %d") % [Lang.t(str(entry.name)), int(parts[0].substr(1))]
	return ""

static func valid_title(id: String) -> bool:
	return title_text(id) != ""

# Seasons that ended with a title waiting to be claimed.
static func pending(rating: Dictionary) -> Array:
	return (rating.log as Array).filter(func(entry: Dictionary) -> bool: return not bool(entry.claimed))

# The ranking number shown next to a player in lists: the placement or the division.
static func short_label(rating: Dictionary) -> String:
	return label(int(rating.mmr)) if placed(rating) else ""

# What others may see of a rating (lists, profile dialogs).
static func public(rating: Dictionary) -> Dictionary:
	return {"mmr": int(rating.mmr), "placed": placed(rating), "games": int(rating.games), "wins": int(rating.wins), "losses": int(rating.losses), "peak": int(rating.peak), "season": int(rating.season)}
