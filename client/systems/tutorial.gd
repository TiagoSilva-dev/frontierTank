class_name Tutorial
extends RefCounted

# Training battle (0.21): a first, scripted fight against a Boneco de Treino that never
# acts, with a coach (TutorialCoach) that walks the player through moving, aiming, the
# wind, the force bar, skills 1-9 and the POW. It is always a local battle (even when the
# player is online): nothing in it touches the lockstep, only the final "tutorial" op
# reaches the server so the reward is given once.
#
# The profile keeps `tutorial` as "" (not offered yet), "skipped" or "done". Saves from
# before 0.21 that already played count as done.

const PATH: String = "res://shared/balance/tutorial.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func steps() -> Array:
	return data().steps

static func settings(balance: Dictionary) -> Dictionary:
	return balance.tutorial

# Whether the city should offer the training now: a brand-new character that never played.
static func should_offer(profile: PlayerProfile) -> bool:
	return profile.created and profile.tutorial == "" and profile.matches == 0

# The BattleScreen config: the player on the first island, the dummy on the one in front.
static func config(balance: Dictionary, profile: PlayerProfile) -> Dictionary:
	var rules: Dictionary = settings(balance)
	var me: Dictionary = profile.entry(balance)
	me.x = float(rules.player_x)
	me.tools = ["", "", ""]
	var dummy: Dictionary = {"enemy": str(rules.dummy), "name": Lang.t("Boneco de Treino"), "title": Lang.t("Alvo"), "hp": int(rules.dummy_hp), "level": 1, "x": float(rules.dummy_x)}
	return {"mode": "tutorial", "tutorial": true, "map": str(rules.map), "turn_seconds": int(rules.turn_seconds), "teams": [[me], [dummy]]}

# The reward shown on the final card ("+200 moedas, +150 EXP, ...").
static func reward_text(balance: Dictionary) -> String:
	var reward: Dictionary = settings(balance).reward
	var parts: PackedStringArray = PackedStringArray()
	if int(reward.get("coins", 0)) > 0:
		parts.append(Lang.t("%d moedas") % int(reward.coins))
	if int(reward.get("exp", 0)) > 0:
		parts.append(Lang.t("%d EXP") % int(reward.exp))
	var items: Dictionary = reward.get("items", {})
	for id: String in items:
		parts.append("%dx %s" % [int(items[id]), material_name(id)])
	return ", ".join(parts)

# Name of a counter item (stone, egg, currency) for reward lines.
static func material_name(id: String) -> String:
	if Pets.is_egg(id):
		return Pets.egg_name(id)
	var stone: Dictionary = Armory.stone_def(id)
	if not stone.is_empty():
		return Lang.t(str(stone.name))
	return Lang.t(str(Armory.definition(id).get("name", id)))

# The op "tutorial": "done" (reward, once) or "skip" (the offer is not made again).
# Returns the error text or "".
static func apply(profile: PlayerProfile, action: String, balance: Dictionary) -> String:
	if action == "skip":
		if profile.tutorial == "":
			profile.tutorial = "skipped"
		return ""
	if action != "done":
		return Lang.t("Operação desconhecida.")
	if profile.tutorial == "done":
		return ""
	profile.tutorial = "done"
	var reward: Dictionary = settings(balance).reward
	profile.coins += int(reward.get("coins", 0))
	profile.experience += int(reward.get("exp", 0))
	var items: Dictionary = reward.get("items", {})
	for id: String in items:
		profile.add_item(id, int(items[id]))
	return ""
