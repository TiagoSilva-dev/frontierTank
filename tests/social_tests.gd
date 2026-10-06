extends SceneTree

# Player menu (0.18): the channel list, the friends list, private messages (the offline channel
# answers for the simulated players), the profile window and the chat's name links. The online
# side (the server's whisper and profile messages) is in net_e2e_tests.gd.

var errors: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		errors += 1
		push_error(message)

func rows(app: Node) -> Array:
	return app.ui.find_children("Player_*", "Button", true, false)

func row_named(app: Node, who: String) -> Button:
	return app.ui.find_child("Player_" + who, true, false)

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://test_social_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	# --- The friend book on its own
	var book: FriendBook = FriendBook.new()
	book.path = "user://test_social_friends.json"
	if FileAccess.file_exists(book.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(book.path))
	book.use_scope("offline")
	check(book.add({"name": "Zeca", "level": 5, "gender": "m"}) == "" and book.has("Zeca"), "a friend is added")
	check(book.add({"name": "Zeca"}) != "", "the same friend is not added twice")
	check(book.add({"name": ""}) != "", "a nameless player is not a friend")
	var again: FriendBook = FriendBook.new()
	again.path = book.path
	again.use_scope("offline")
	check(again.has("Zeca") and int(again.friends[0].level) == 5, "the list is kept on disk")
	again.use_scope("acc7")
	check(not again.has("Zeca"), "another account (or mode) has its own list")
	again.add({"name": "Rita"})
	book.use_scope("offline")
	check(book.has("Zeca") and not book.has("Rita"), "saving one list keeps the others")
	book.refresh([{"name": "Zeca", "level": 9, "account": 3}])
	check(int(book.friends[0].level) == 9 and int(book.friends[0].account) == 3, "a friend seen online updates the stored level")
	book.remove("Zeca")
	check(not book.has("Zeca"), "a friend is removed")
	for i in range(FriendBook.MAX_FRIENDS):
		book.add({"name": "f%d" % i})
	check(book.add({"name": "um a mais"}) != "", "the list has a limit")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(book.path))
	# --- The game: character, then the hall
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.friends.path = "user://test_social_friends.json"
	app.friends.use_scope("offline")
	app.profile.created = true
	app.profile.player_name = "Tiago"
	app.lobby.my_name = "Tiago"
	app.show_hall()
	await process_frame
	await process_frame
	var list: PlayerList = app.screen.get_node("PlayerList")
	check(list != null and rows(app).size() == app.lobby.bots.size() + 1, "the hall lists every player of the channel, with the player")
	var top_names: Array = rows(app).map(func(b: Button) -> int: return int(b.find_child("Name", true, false).text.length()))
	check(row_named(app, "Tiago") != null, "the player's own row is there")
	var levels: Array = app.lobby.bots.map(func(b: Dictionary) -> int: return int(b.level))
	check(levels == levels.duplicate() and top_names.size() > 3, "rows have names")
	# --- Clicking a name opens the menu
	var bot: Dictionary = app.lobby.bots[0]
	var bot_row: Button = row_named(app, str(bot.name))
	bot_row.pressed.emit()
	await process_frame
	var menu: PlayerMenu = app.ui.get_node_or_null("PlayerMenu")
	check(menu != null and menu.find_child("Menu_profile", true, false) != null and menu.find_child("Menu_whisper", true, false) != null and menu.find_child("Menu_friend", true, false) != null, "a name opens the menu: profile, private message, friend")
	check(menu.find_child("Menu_report", true, false) == null, "there is nothing to report offline")
	check(str(menu.find_child("Name", true, false).text) == str(bot.name), "the menu is about that player")
	var inside: Rect2 = Rect2(Vector2.ZERO, Vector2(1280, 720))
	check(inside.encloses((menu.get_node("Box") as Control).get_global_rect()), "the menu stays inside the window")
	# --- Add as a friend
	menu.find_child("Menu_friend", true, false).pressed.emit()
	await process_frame
	await process_frame
	check(app.friends.has(str(bot.name)), "the menu adds the friend")
	bot_row = row_named(app, str(bot.name))
	check(bot_row != null and bot_row.find_child("Star", true, false) != null, "a friend carries a star in the list")
	list.select_tab("friends")
	await process_frame
	await process_frame
	check(rows(app).size() == 1 and rows(app)[0].name == "Player_" + str(bot.name), "the Amigos tab lists only the friends")
	list.search.text = "zzzz"
	list.search.text_changed.emit("zzzz")
	await process_frame
	await process_frame
	check(rows(app).is_empty() and list.rows.get_node_or_null("Empty") != null, "a search with no result says so")
	list.search.text = ""
	list.search.text_changed.emit("")
	list.select_tab("all")
	await process_frame
	await process_frame
	var found: int = 0
	var needle: String = str(bot.name).substr(0, 3).to_lower()
	list.search.text_changed.emit(needle)
	await process_frame
	await process_frame
	for button: Button in rows(app):
		if str(button.name).to_lower().contains(needle):
			found += 1
	check(rows(app).size() == found and found >= 1, "the search filters by name")
	list.search.text_changed.emit("")
	await process_frame
	await process_frame
	# --- Own row: only the profile
	row_named(app, "Tiago").pressed.emit()
	await process_frame
	menu = app.ui.get_node_or_null("PlayerMenu")
	check(menu != null and menu.find_child("Menu_whisper", true, false) == null and menu.find_child("Menu_friend", true, false) == null, "your own name offers no message or friend")
	menu.queue_free()
	await process_frame
	# --- Profile window
	var other: Dictionary = app.lobby.bots[1]
	row_named(app, str(other.name)).pressed.emit()
	await process_frame
	app.ui.get_node("PlayerMenu").find_child("Menu_profile", true, false).pressed.emit()
	await process_frame
	await process_frame
	var dialog: PlayerProfileDialog = app.ui.get_node_or_null("PlayerProfile")
	check(dialog != null and dialog.find_child("Name", true, false) != null and str(dialog.find_child("Name", true, false).text) == str(other.name), "the profile window shows the player")
	check(dialog.find_child("Weapon", true, false) != null and dialog.find_child("Whisper", true, false) != null and dialog.find_child("Friend", true, false) != null, "it shows the weapon and offers message and friend")
	dialog.find_child("Friend", true, false).pressed.emit()
	await process_frame
	check(app.friends.has(str(other.name)), "a friend can be added from the profile window")
	dialog.find_child("Friend", true, false).pressed.emit()
	await process_frame
	check(not app.friends.has(str(other.name)), "and removed again")
	# --- Private message from the profile window
	dialog.find_child("Whisper", true, false).pressed.emit()
	await process_frame
	await process_frame
	var chat: ChatBox = app.screen.find_children("*", "ChatBox", true, false).front()
	check(chat.tab == "Privado" and str(app.lobby.whisper_target.name) == str(other.name), "the private chat opens aimed at that player")
	check(chat.target_button.text.contains(str(other.name)) and chat.input.placeholder_text.contains(str(other.name)), "the input says who it writes to")
	chat.send("oi, tudo bem?")
	var line: Dictionary = app.lobby.history.back()
	check(str(line.channel) == "Privado" and str(line.author) == "Tiago" and str(line.to) == str(other.name), "the message is sent to that player")
	check(chat.log_label.text.contains("Para " + str(other.name)), "the chat shows who it went to")
	var answered: bool = false
	var deadline: int = Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if app.lobby.history.back().author == other.name:
			answered = true
			break
	check(answered and str(app.lobby.history.back().channel) == "Privado" and str(app.lobby.history.back().to) == "Tiago", "the simulated player answers")
	check(app.lobby.unread_private == 0 and not chat.unread_dot.visible, "on the Privado tab nothing is left unread")
	# --- Unread dot when another tab is open
	chat.select_tab("Atual")
	app.lobby.post(str(other.name), "e aí?", "Privado", {"to": "Tiago"})
	await process_frame
	check(app.lobby.unread_private == 1 and chat.unread_dot.visible and chat.unread_dot.text == "1", "a private line on another tab lights the dot")
	chat.select_tab("Privado")
	check(app.lobby.unread_private == 0 and not chat.unread_dot.visible, "opening the Privado tab clears it")
	chat.select_tab("Atual")
	chat.send("sem alvo")
	app.lobby.whisper_target = {}
	chat.select_tab("Privado")
	var before: int = app.lobby.history.size()
	chat.send("para ninguém")
	check(app.lobby.history.size() == before + 1 and str(app.lobby.history.back().channel) == "system", "a private message without a target gets a hint")
	# --- Names in the chat are links to the menu
	chat.select_tab("Atual")
	app.lobby.post(str(bot.name), "bora jogar", "Atual")
	await process_frame
	check(chat.log_label.text.contains("]%s[/url]" % str(bot.name)), "other players' names in the chat are links")
	check(not chat.log_label.text.contains("]Tiago[/url]"), "the player's own name is not")
	chat.on_meta("m:%d" % (app.lobby.history.size() - 1))
	await process_frame
	menu = app.ui.get_node_or_null("PlayerMenu")
	check(menu != null and str(menu.find_child("Name", true, false).text) == str(bot.name), "a name in the chat opens that player's menu")
	menu.queue_free()
	# --- Friends window
	app.friends.add({"name": str(bot.name), "level": int(bot.level), "gender": str(bot.gender)})
	FriendsDialog.open(app.ui, app)
	await process_frame
	await process_frame
	var friends_window: FriendsDialog = app.ui.get_node_or_null("FriendsDialog")
	check(friends_window != null and friends_window.get_node("List").tab == "friends" and friends_window.get_node("List").rows.get_child_count() == 1, "the chat's friends button opens the friends window")
	friends_window.queue_free()
	await process_frame
	# --- A simulated player of an online channel (docs/BOTS.md): the profile only, and it says it is the game's AI
	PlayerMenu.open(app.ui, app, {"name": "Fenix_SP", "level": 9, "gender": "m", "sim": true, "account": 0}, Vector2(400, 300))
	await process_frame
	menu = app.ui.get_node_or_null("PlayerMenu")
	check(menu != null and menu.find_child("Menu_profile", true, false) != null and menu.find_child("Menu_whisper", true, false) == null and menu.find_child("Menu_friend", true, false) == null, "a simulated player of an online channel offers only the profile")
	menu.queue_free()
	await process_frame
	var ai_info: Dictionary = app.lobby.bots[2].duplicate(true)
	ai_info["ai"] = true
	PlayerProfileDialog.open(app.ui, app, ai_info)
	await process_frame
	await process_frame
	dialog = app.ui.get_node_or_null("PlayerProfile")
	check(dialog != null and dialog.find_child("AiNote", true, false) != null and dialog.find_child("Whisper", true, false) == null and dialog.find_child("Friend", true, false) == null, "its profile says it is the game's AI and offers no message or friend")
	dialog.queue_free()
	await process_frame
	# --- Dark panel for the chat (legibility): its frame is a nearly opaque dark one
	check(UiKit.FRAMES.dark.alpha >= 0.85 and UiKit.FRAMES.log.alpha >= 0.8, "the chat and the battle log sit on dark plates")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	for path in ["user://test_social_friends.json", PlayerProfile.path_override]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SOCIAL RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)
