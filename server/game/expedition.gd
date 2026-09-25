class_name Expedition
extends RefCounted

# An instance played by a group on the game server. The phases, the enemies and what the
# party carries between phases are shared; the loot is personal: every player has their
# own InstanceRun with their own profile, dice, map drops, chest, Super guarantee and
# reward cards, so nobody has to split a drop.

var runs: Dictionary = {}
var leader: InstanceRun

# `team`: the players' battle entries (with "account"); `profiles`: account -> profile.
func _init(balance: Dictionary, instance_id: String, map_item: Dictionary, team: Array, profiles: Dictionary) -> void:
	var humans: int = team.filter(func(entry: Dictionary) -> bool: return entry.get("human", false)).size()
	for entry: Dictionary in team:
		var account: int = int(entry.get("account", 0))
		if account > 0 and profiles.has(account) and not runs.has(account):
			runs[account] = InstanceRun.new(balance, instance_id, map_item, humans, team, profiles[account])
	leader = runs.values()[0] if not runs.is_empty() else InstanceRun.new(balance, instance_id, map_item, humans, team)

func phase_config() -> Dictionary:
	return leader.phase_config(leader.members)

func has_next_phase() -> bool:
	return leader.has_next_phase()

func run_for(account: int) -> InstanceRun:
	return runs.get(account)

# A phase before the boss was won: every player gets their own drops (already in their
# profile) and a report for the transition screen.
func complete_phase(game: LocalMatch) -> Dictionary:
	var cleared: String = str(leader.current_phase().name)
	var reports: Dictionary = {}
	for account: int in runs:
		var run: InstanceRun = runs[account]
		var report: Dictionary = run.complete_phase(game)
		report.cleared = cleared
		report.next = run.current_phase()
		report.index = run.phase_index
		report.count = run.phase_count()
		reports[account] = report
	if runs.is_empty():
		leader.complete_phase(game)
	return reports
