class_name Rewards
extends RefCounted

# End of a battle: EXP, mérito, the tools that are left and the reward cards. Offline the
# client settles its own player; online (backend 0.11) the game server settles every
# player of the match with this same code and only sends the result.

# Applies the battle to `profile` and returns the summary the result screen shows.
# After an instance (`run` set) the chest is opened and the 8 cards are in summary.loot.
static func settle(game: LocalMatch, me: TankFighter, balance: Dictionary, profile: PlayerProfile, run: InstanceRun = null) -> Dictionary:
	var won: bool = game.winner_team == me.team
	var rules: Dictionary = balance.rewards
	var kill_exp: int = int(me.stats.kills) * int(rules.exp_per_kill)
	var hurt_exp: int = roundi(float(me.stats.damage) * float(rules.exp_per_damage))
	var result_exp: int = int(rules.win_exp if won else rules.loss_exp)
	var bonus_exp: int = 0
	var loot: Dictionary = {}
	if game.pve and run != null:
		# Instance end (boss down or party wiped): XP scales with the map level and
		# party, the chest is opened and the reward cards rolled.
		if won:
			bonus_exp = roundi(float(balance.pve.exp) * run.xp_scale())
		kill_exp = roundi(kill_exp * run.xp_scale())
		hurt_exp = roundi(hurt_exp * run.xp_scale())
		loot = run.finish(won)
	var merit: int = int(rules.merit_win if won else rules.merit_loss) + int(me.stats.kills) * int(rules.merit_per_kill)
	var level_before: int = profile.level()
	profile.tools = ["", "", ""]
	for i in range(mini(3, me.tools.size())):
		profile.tools[i] = me.tools[i]
	profile.record_match(won, kill_exp + hurt_exp + result_exp + bonus_exp, merit)
	var roster: Array = []
	for fighter in game.fighters:
		if fighter.team == me.team:
			var fighter_exp: int = int(rules.win_exp if won else rules.loss_exp) + roundi(float(fighter.stats.damage) * float(rules.exp_per_damage)) + int(fighter.stats.kills) * int(rules.exp_per_kill)
			roster.append({"name": fighter.display_name, "exp": fighter_exp, "merit": int(rules.merit_win if won else rules.merit_loss) + int(fighter.stats.kills) * int(rules.merit_per_kill)})
	var summary: Dictionary = {"won": won, "draw": game.winner_team < 0, "pve": game.pve, "kill_exp": kill_exp, "hurt_exp": hurt_exp, "result_exp": result_exp, "bonus_exp": bonus_exp, "merit": merit, "exp": kill_exp + hurt_exp + result_exp + bonus_exp, "roster": roster, "level_before": level_before, "level_after": profile.level(), "damage": int(me.stats.damage), "kills": int(me.stats.kills)}
	if game.pve and run != null:
		summary.loot = loot
		summary.instance = {"name": Lang.t(str(run.instance.name)), "id": str(run.instance.id), "level": run.level, "map": InstanceRun.map_name(run.map_item), "phases": run.phases_won, "count": run.phase_count(), "drops": run.drops.duplicate(true), "currency": run.currency_drops.duplicate(true), "gold": run.gold, "chest": run.chest.duplicate(true)}
	return summary

# The 8 cards of a PvP battle (0.10: a little currency, Brasa and Coroa, among them).
static func pvp_cards(balance: Dictionary, rng: RandomNumberGenerator) -> Array:
	var pool: Array = balance.rewards.cards + balance.rewards.get("pvp_cards", [])
	var cards: Array = []
	for i in range(8):
		cards.append(roll(pool, rng))
	return cards

static func picks(summary: Dictionary) -> int:
	var loot: Dictionary = summary.get("loot", {})
	if not loot.is_empty():
		return int(loot.picks)
	return 2 if summary.get("won", false) else 1

static func roll(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in pool:
		total += float(entry.weight)
	var ticket: float = rng.randf() * total
	for entry: Dictionary in pool:
		ticket -= float(entry.weight)
		if ticket <= 0:
			return entry
	return pool[0]

static func grant(profile: PlayerProfile, reward: Dictionary) -> void:
	if reward.has("coins"):
		profile.coins += int(reward.coins)
	elif reward.has("item"):
		profile.add_item(str(reward.item))
	elif reward.has("tool"):
		if not profile.add_tool(str(reward.tool)):
			profile.coins += 30
	elif reward.has("currency"):
		profile.add_item(str(reward.currency), int(reward.get("amount", 1)))
	elif reward.has("weapon"):
		profile.add_instance(str(reward.weapon), str(reward.get("quality", "super")), 0, int(reward.get("ilvl", 0)), reward.get("mods", []))
	elif reward.has("gear"):
		profile.add_instance(str(reward.gear), str(reward.get("quality", "normal")), 0, int(reward.get("ilvl", 0)), reward.get("mods", []))
	elif reward.has("map"):
		profile.add_map(reward.map)
	profile.save_profile()
