class_name PlayerMenu
extends Control

# The menu that opens on a player's name (channel list, chat lines): see the profile,
# send a private message, add or remove a friend and, for a chat line, report it.
# It closes when the player clicks anywhere else or presses Esc.

var app: Node
var person: Dictionary = {}
var line: Dictionary = {}
var origin: Vector2 = Vector2.ZERO

# `person`: {"name", "level", "gender", "account"?}; `line`: the chat line it came from.
static func open(parent: Node, app_node: Node, who: Dictionary, at: Vector2, from_line: Dictionary = {}) -> PlayerMenu:
	for old: Node in parent.get_children():
		if old is PlayerMenu:
			old.queue_free()
	var menu: PlayerMenu = PlayerMenu.new()
	menu.app = app_node
	menu.person = who
	menu.line = from_line
	menu.origin = at
	menu.name = "PlayerMenu"
	parent.add_child(menu)
	return menu

func _ready() -> void:
	size = Vector2(1280, 720)
	# A transparent sheet over the screen: a click outside the menu closes it.
	var sheet: Control = Control.new()
	sheet.size = size
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(sheet)
	var mine: bool = str(person.get("name", "")) == app.profile.player_name
	var entries: Array[Dictionary] = []
	entries.append({"id": "profile", "text": tr("Ver perfil"), "kind": "button_blue"})
	# A simulated player of an online channel (sim) has no account to message or befriend.
	if not mine and not bool(person.get("sim", false)):
		entries.append({"id": "whisper", "text": tr("Mensagem privada"), "kind": "button_green"})
		entries.append({"id": "friend", "text": tr("Remover amigo") if app.friends.has(str(person.name)) else tr("Adicionar amigo"), "kind": "button"})
		if app.online and not line.is_empty() and line.has("id") and int(line.get("account", 0)) != app.my_account():
			entries.append({"id": "report", "text": tr("Denunciar mensagem"), "kind": "button_red"})
	var width: float = 224.0
	var height: float = 62.0 + entries.size() * 40.0 + 8.0
	var rect: Rect2 = Rect2(origin, Vector2(width, height))
	rect.position.x = clampf(rect.position.x, 6.0, 1280.0 - width - 6.0)
	rect.position.y = clampf(rect.position.y, 6.0, 720.0 - height - 6.0)
	var box: Panel = UiKit.panel(self, rect, "wood_dark")
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.name = "Box"
	UiKit.level_badge(box, int(person.get("level", 1)), Rect2(10, 10, 40, 28))
	var label: Label = UiKit.clipped(box, str(person.get("name", "")), Rect2(58, 8, width - 68, 32), 18, Color.WHITE, UiKit.INK)
	label.name = "Name"
	UiKit.label(box, TankFighter.rank_for(int(person.get("level", 1))), Rect2(10, 38, width - 20, 20), 14, Color("ffe6a0"), UiKit.INK)
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var button: Button = UiKit.button(box, str(entry.text), Rect2(10, 62 + i * 40, width - 20, 34), act.bind(str(entry.id)), str(entry.kind), 16)
		button.name = "Menu_" + str(entry.id)

func act(id: String) -> void:
	app.audio.play("ui_click")
	var parent: Node = get_parent()
	match id:
		"profile":
			PlayerProfileDialog.open(parent, app, person)
		"whisper":
			start_whisper(app, person)
		"friend":
			if app.friends.has(str(person.name)):
				app.friends.remove(str(person.name))
				app.toast(tr("%s saiu da sua lista de amigos.") % str(person.name))
			else:
				var problem: String = app.friends.add(person)
				app.toast(tr(problem) if problem != "" else tr("%s agora é seu amigo!") % str(person.name))
			app.lobby.rooms_changed.emit()
		"report":
			ReportDialog.open(parent, app, line)
	queue_free()

# Picks the person as the target of the private chat and opens that tab, wherever the chat is.
static func start_whisper(app_node: Node, who: Dictionary) -> void:
	app_node.lobby.whisper_target = {"name": str(who.get("name", "")), "account": int(who.get("account", 0))}
	app_node.lobby.unread_private = 0
	app_node.lobby.chat_added.emit({})
	var stack: Array[Node] = [app_node.ui]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is ChatBox:
			(node as ChatBox).open_private()
		stack.append_array(node.get_children())

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
