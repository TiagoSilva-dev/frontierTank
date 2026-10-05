class_name SkinStage
extends Control

# The shop's fitting stage (0.28, docs/SKINS.md): the character standing, turning to the four
# directions, or in the battle pose (lying down) doing what it does in a match: crawl, shoot,
# POW and the victory pose, with the skin's own living layer. Nothing here touches the
# profile or the match; it is only drawing. The shop keeps the choice of mode and direction.

const DIRECTIONS: Array[String] = ["south", "east", "north", "west"]
const BATTLE_ACTIONS: Array = [["ANDAR", "walk"], ["ATIRAR", "shoot"], ["POW", "pow"], ["VITÓRIA", "victory"]]  # i18n

var look: Dictionary = {}
var gender: String = "m"
var balance: Dictionary = {}
var weapon_entry: Dictionary = {}
var mode: String = "stand"
var direction: String = "south"
var fighter: TankFighter
var on_change: Callable
var serial: int = 0

# Builds the stage inside `parent` (the dark panel of the fitting room). `entry` is the roster
# entry of the player (their weapon goes on the back in battle), `on_change` is called with
# ("mode", value) or ("direction", value) when a button is pressed.
static func mount(parent: Control, look_data: Dictionary, entry: Dictionary, balance_data: Dictionary, picked_mode: String, picked_direction: String, change: Callable) -> SkinStage:
	var stage: SkinStage = SkinStage.new()
	stage.size = parent.size
	stage.look = look_data
	stage.gender = str(entry.get("gender", "m"))
	stage.weapon_entry = entry
	stage.balance = balance_data
	stage.mode = picked_mode
	stage.direction = picked_direction
	stage.on_change = change
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stage)
	stage.build()
	return stage

func build() -> void:
	for child in get_children():
		child.queue_free()
	var stand: Button = UiKit.button(self, tr("EM PÉ"), Rect2(8, 6, 150, 30), request.bind("mode", "stand"), "tab_active" if mode == "stand" else "tab", 14)
	stand.name = "Mode_stand"
	var battle: Button = UiKit.button(self, tr("BATALHA"), Rect2(174, 6, 150, 30), request.bind("mode", "battle"), "tab_active" if mode == "battle" else "tab", 14)
	battle.name = "Mode_battle"
	if mode == "battle":
		build_battle()
		return
	var avatar: AvatarView = AvatarView.new()
	avatar.direction = direction
	avatar.position = Vector2(0, 38)
	avatar.size = Vector2(size.x, 250)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(avatar)
	avatar.show_look(look)
	var turn_left: Button = UiKit.button(self, "<", Rect2(228, 296, 44, 34), request.bind("direction", step(-1)), "tab", 16)
	turn_left.name = "Turn_left"
	var turn_right: Button = UiKit.button(self, ">", Rect2(280, 296, 44, 34), request.bind("direction", step(1)), "tab", 16)
	turn_right.name = "Turn_right"

func step(change: int) -> String:
	return DIRECTIONS[posmod(DIRECTIONS.find(direction) + change, DIRECTIONS.size())]

func request(key: String, value: String) -> void:
	if on_change.is_valid():
		on_change.call(key, value)

func build_battle() -> void:
	var holder: Control = Control.new()
	holder.size = size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var ground: ColorRect = ColorRect.new()
	ground.color = Color("2b2338")
	ground.position = Vector2(0, 236)
	ground.size = Vector2(size.x, 26)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ground)
	var shown: Dictionary = weapon_entry.duplicate()
	shown["look"] = look
	shown["name"] = ""
	fighter = TankFighter.new()
	fighter.plate = false
	fighter.setup(0, shown, Armory.weapon_for_entry(shown), balance)
	fighter.position = Vector2(size.x / 2.0 - 10.0, 246.0)
	fighter.scale = Vector2(2.1, 2.1)
	holder.add_child(fighter)
	for i in range(BATTLE_ACTIONS.size()):
		var action: Array = BATTLE_ACTIONS[i]
		var button: Button = UiKit.button(self, tr(str(action[0])), Rect2(8 + i * 80, 266, 76, 28), play.bind(str(action[1])), "tab", 13)
		button.name = "Play_" + str(action[1])

# Plays one of the battle clips and goes back to idle, like the fighter in a match.
func play(action: String) -> void:
	if not is_instance_valid(fighter):
		return
	var seconds: float = 1.6
	fighter.celebrating = false
	fighter.rig.fx_event("reset")
	match action:
		"walk":
			fighter.show_animation(fighter.walk_animation)
			fighter.rig.fx_state = "walk"
		"shoot":
			fighter.show_animation(fighter.attack_animation)
			fighter.rig.fx_state = "attack"
			fighter.rig.fx_event("attack")
			seconds = 0.9
		"pow":
			fighter.rig.fx_state = "pow"
			if not fighter.play_clip("pow", 1.3):
				fighter.show_animation(fighter.attack_animation)
			fighter.rig.fx_event("pow")
			seconds = 1.4
		"victory":
			fighter.play_clip("victory", 99.0)
			fighter.rig.fx_state = "victory"
			fighter.rig.fx_event("victory")
			seconds = 2.4
	serial += 1
	var token: int = serial
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(fighter) and token == serial:
			fighter.show_animation(fighter.idle_animation)
			fighter.rig.fx_state = "idle"
			fighter.rig.fx_event("reset")
			fighter.clip_hold = 0.0)
