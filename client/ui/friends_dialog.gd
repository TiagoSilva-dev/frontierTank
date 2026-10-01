class_name FriendsDialog
extends Control

# The friends window of the chat box: the player list on its Amigos tab, over the screen.
# A click on a name opens the player menu (private message, profile, remove).

static func open(parent: Node, app_node: Node) -> FriendsDialog:
	for old: Node in parent.get_children():
		if old is FriendsDialog:
			old.queue_free()
	var dialog: FriendsDialog = FriendsDialog.new()
	dialog.name = "FriendsDialog"
	dialog.set_meta("app", app_node)
	parent.add_child(dialog)
	return dialog

func _ready() -> void:
	size = Vector2(1280, 720)
	var app: Node = get_meta("app")
	UiKit.dim(self, 0.5).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	var list: PlayerList = PlayerList.new()
	list.app = app
	list.tab = "friends"
	list.position = Vector2(456, 150)
	list.name = "List"
	add_child(list)
	UiKit.button(self, tr("FECHAR"), Rect2(540, 478, 200, 40), queue_free, "button", 16).name = "Close"

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
