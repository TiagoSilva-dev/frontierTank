extends SceneTree

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

func run_tests() -> void:
	PlayerProfile.path_override = "user://test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	var scene: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var app: Node = scene
	# Tela inicial
	check(app.screen_name == "city" and app.screen is CityScreen, "city is the initial screen")
	var city: CityScreen = app.screen
	check(is_instance_valid(city.creation), "first launch asks for the single character")
	city.name_input.text = "Tiago"
	city.pick_gender("f")
	city.confirm_creation()
	await process_frame
	check(app.profile.created and app.profile.player_name == "Tiago" and app.profile.gender == "f", "character is created once and saved")
	city = app.screen
	check(city.has_node("Building_hall") and city.has_node("Building_instance"), "city buildings are clickable hotspots")
	check(city.has_node("CouponButton"), "city has the coupon field button")
	city.enter("smith")
	await process_frame
	var smith_in_city: SmithScreen = city.get_children().filter(func(n: Node) -> bool: return n is SmithScreen).front()
	check(smith_in_city != null, "Ferreiro opens from the city")
	smith_in_city.close()
	await process_frame
	city = app.screen
	city.enter("mall")
	await process_frame
	var shop_in_city: ShopScreen = city.get_children().filter(func(n: Node) -> bool: return n is ShopScreen).front()
	check(shop_in_city != null and shop_in_city.has_node("Shop_quebra_tijolos") == false, "Centro Comercial opens from the city")
	app.profile.coins += 5000
	shop_in_city.buy_item("vento_de_deus", "excelente")
	check(app.profile.has_item("vento_de_deus", "excelente"), "shop sells weapons by quality")
	shop_in_city.buy_item("cabeca_de_boi", "super")
	check(not app.profile.has_item("cabeca_de_boi"), "super weapons are not sold")
	shop_in_city.close()
	await process_frame
	city = app.screen
	# Salão de Jogos
	city.enter("hall")
	await process_frame
	check(app.screen is HallScreen, "Salão de Jogos opens from the city")
	var hall: HallScreen = app.screen
	await process_frame
	check(hall.grid.get_child_count() == 8, "room list shows eight cards per page")
	var open: Dictionary = app.lobby.open_room()
	if open.is_empty():
		app.lobby.rooms.append({"id": 777, "title": "teste", "mode": "pvp", "capacity": 4, "members": [app.lobby.random_bot()], "playing": false, "map": "", "turn_seconds": 10, "difficulty": "normal"})
		open = app.lobby.rooms[-1]
	var members_before: int = open.members.size()
	hall.try_join(open)
	await process_frame
	check(app.screen is RoomScreen and not app.is_owner(), "joining a room makes the player a member")
	check(app.room.members.size() == members_before + 1, "player takes a free slot")
	var room_screen: RoomScreen = app.screen
	room_screen.press_start()
	check(app.room.ready, "member presses Preparar")
	app.show_hall()
	await process_frame
	app.screen.create_team()
	await process_frame
	check(app.screen is RoomScreen and app.is_owner(), "Equipe creates a room owned by the player")
	room_screen = app.screen
	room_screen.invite()
	check(app.room.members.size() == 2, "Convide adds a teammate")
	var coins: int = app.profile.coins
	room_screen.buy_tool("hp")
	check(app.profile.coins == coins - 60 and app.profile.tools[0] == "hp", "tools are bought into Z/X/C slots")
	room_screen.sell_tool(0)
	check(app.profile.coins == coins and app.profile.tools[0] == "", "tools can be returned before battle")
	room_screen.buy_tool("energy")
	room_screen.cycle_time()
	check(int(app.room.turn_seconds) == 15, "room owner changes the turn time")
	room_screen.choose_map()
	await process_frame
	var map_dialog: Node = room_screen.find_child("Map_patio_templo", true, false)
	check(map_dialog != null, "Local lists the maps")
	map_dialog.pressed.emit()
	await process_frame
	check(app.room.map == "patio_templo", "map choice is stored in the room")
	# Partida
	app.start_battle()
	await process_frame
	check(app.screen is BattleScreen, "Início starts the battle")
	var battle: BattleScreen = app.screen
	var game: LocalMatch = battle.game
	check(game.running and game.fighters.size() == 4, "2v2 battle against a matched team")
	check(game.map.id == "patio_templo" and is_equal_approx(game.turn_seconds, 15.0), "room settings reach the battle")
	check(game.local().tools[0] == "energy", "bought tools are carried into battle")
	check(battle.hud.item_buttons.size() == 9 and battle.hud.tool_buttons.size() == 3, "HUD shows skills 1–9 and tools Z/X/C")
	for i in range(5):
		await process_frame
	check(battle.camera.position.distance_to(battle.focus_point()) < 2000, "camera follows the action")
	var matches: int = app.profile.matches
	for fighter in game.fighters:
		if fighter.team == 1:
			fighter.hp = 0
	game.evaluate_winner()
	await process_frame
	check(app.profile.matches == matches + 1 and app.last_summary.won, "victory is recorded")
	check(int(app.last_summary.exp) > 0 and int(app.last_summary.merit) > 0, "experience and merit are awarded")
	battle.show_results()
	await process_frame
	check(is_instance_valid(battle.results), "results screen appears")
	battle.results.show_cards()
	await process_frame
	check(battle.results.cards.size() == 8 and battle.results.picks_left == 2, "winner chooses 2 of 8 cards")
	var coins_before: int = app.profile.coins
	var items_before: int = app.profile.items.values().reduce(func(a: int, b: int) -> int: return a + b, 0)
	var tools_before: int = app.profile.tools.filter(func(t: String) -> bool: return t != "").size()
	battle.results.pick(0)
	battle.results.pick(0)
	battle.results.pick(1)
	var items_after: int = app.profile.items.values().reduce(func(a: int, b: int) -> int: return a + b, 0)
	var tools_after: int = app.profile.tools.filter(func(t: String) -> bool: return t != "").size()
	check(battle.results.picks_left == 0 and (app.profile.coins > coins_before or items_after > items_before or tools_after > tools_before), "picked cards grant rewards")
	app.return_to_room()
	await process_frame
	check(app.screen is RoomScreen and app.room.members.size() == 2, "after the cards the team returns to the room")
	# Mochila
	app.open_bag()
	await process_frame
	check(is_instance_valid(app.bag), "Mochila opens over the current screen")
	var bag: CharacterScreen = app.bag
	CouponDialog.open(bag, app, bag.build)
	var dialog: Node = bag.find_child("CouponField", true, false)
	dialog.text = "testartudo"
	dialog.text_submitted.emit(dialog.text)
	check(app.profile.has_item("lanca_antiga", "super") and app.profile.has_item("asas_anjo") and app.profile.has_item("trovao", "verdadeira"), "coupon field unlocks every weapon and cosmetic")
	bag.filter_items("Armas")
	var thunder: Dictionary = {}
	for inst: Dictionary in app.profile.inventory:
		if inst.id == "trovao" and inst.quality == "verdadeira":
			thunder = inst
	bag.select_item("uid:%d" % int(thunder.uid))
	bag.equip_selected()
	check(app.profile.equipped_instance("arma").id == "trovao", "weapon can be equipped from the bag")
	for id: String in ["asas_anjo", "chapeu_coroa", "oculos_escuros", "cabelo_azul", "roupa_princesa"]:
		for inst: Dictionary in app.profile.inventory:
			if inst.id == id:
				bag.select_item("uid:%d" % int(inst.uid))
				bag.equip_selected()
	var look: Dictionary = app.profile.look()
	check(look.wings == "asas_anjo" and look.hat == "chapeu_coroa" and look.hair != "" and look.skin == "roupa_princesa", "equipped cosmetics change the character look")
	bag.open_smith()
	await process_frame
	var smith: SmithScreen = bag.get_children().filter(func(n: Node) -> bool: return n is SmithScreen).front()
	smith.selected_uid = int(thunder.uid)
	for i in range(3):
		smith.do_strengthen()
	check(int(app.profile.find_instance(int(thunder.uid)).level) == 3 and app.profile.look().weapon_level == 3, "Ferreiro strengthens the equipped weapon (green aura)")
	smith.close()
	bag.select_tab("Atributos")
	bag.select_tab("Histórico")
	app.close_bag()
	await process_frame
	check(not is_instance_valid(app.bag), "Mochila closes")
	# Instância
	app.create_room("pve")
	app.show_room()
	await process_frame
	app.screen.pick_difficulty("hard")
	check(app.room.difficulty == "hard", "instance difficulty can be chosen")
	app.start_battle()
	await process_frame
	game = app.screen.game
	check(game.pve and game.fighters[-1].is_boss and game.map.id == "templo_sol", "Instância starts the boss battle")
	app.screen.toggle_pause()
	check(game.paused, "battle can be paused")
	app.screen.forfeit()
	await process_frame
	check(not game.running and not app.last_summary.won, "forfeit counts as defeat")
	app.shortcut("help")
	app.show_city()
	await process_frame
	check(app.screen is CityScreen, "back to the city")
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("UI RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)
