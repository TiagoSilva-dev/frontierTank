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
	# Messages are checked in Portuguese, the source language.
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	var scene: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var app: Node = scene
	# Tela de entrada (servidor) e depois a cidade
	check(app.screen_name == "title" and app.screen is TitleScreen, "the game opens on the title screen")
	var title: TitleScreen = app.screen
	check(title.has_node("Logo") and title.find_child("EnterButton", true, false) != null, "title screen shows the logo and ENTRAR")
	check(app.audio.music_track == "lobby", "the title screen plays the lobby theme")
	var weapon_sounds: bool = true
	for weapon: Dictionary in Armory.data().weapons:
		weapon_sounds = weapon_sounds and app.audio.has_sound("fire_" + str(weapon.id)) and app.audio.has_sound("impact_" + str(weapon.id))
	check(weapon_sounds, "every weapon has its own firing and impact sound")
	check(app.audio.stream(GameAudio.MUSIC_DIR + "battle.ogg") != null and app.audio.stream(GameAudio.MUSIC_DIR + "instance.ogg") != null, "battle and instance music exist")
	title.pick(title.servers.size() - 1)
	title.enter()
	await process_frame
	check(app.screen_name == "city" and app.screen is CityScreen, "ENTRAR opens the city")
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
	check(not city.has_node("Building_dating") and city.has_node("Scenery_dating") and not city.buildings.any(func(b: Dictionary) -> bool: return b.id == "dating"), "Namoro is off: the chapel is only scenery")
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
	# Leilão and Correio (0.12) need the online server: offline they only explain it.
	city.enter("auction")
	await process_frame
	var auction_notice: Node = city.find_child("Modal", true, false)
	check(auction_notice != null and city.get_children().filter(func(n: Node) -> bool: return n is AuctionScreen).is_empty(), "offline, the Leilão explains it needs the server")
	auction_notice.queue_free()
	app.shortcut("mail")
	await process_frame
	var mail_notice: Node = app.ui.find_child("Modal", true, false)
	check(mail_notice != null and not app.ui.get_children().any(func(n: Node) -> bool: return n is MailScreen), "offline, the Correio explains it needs the server")
	mail_notice.queue_free()
	await process_frame
	# Salão de Jogos
	city.enter("hall")
	await process_frame
	check(app.screen is HallScreen, "Salão de Jogos opens from the city")
	var hall: HallScreen = app.screen
	await process_frame
	check(hall.grid.get_child_count() == 8, "room list shows eight cards per page")
	var open: Dictionary = app.lobby.open_room()
	if open.is_empty():
		app.lobby.rooms.append({"id": 777, "title": "teste", "mode": "pvp", "capacity": 4, "members": [app.lobby.random_bot()], "playing": false, "map": "", "turn_seconds": 10})
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
	check(app.audio.music_track == "battle", "PvP battles play the battle theme")
	game.energy = 240
	game.apply_item(game.local(), "dmg10")
	game.arm_pow(game.local())
	await process_frame
	check(battle.effects.get_children().any(func(node: Node) -> bool: return node is SkillFx and node.fighter == game.local()), "a used skill pops over the fighter's head")
	check(is_instance_valid(battle.pow_auras.get(game.local_id)), "armed POW wraps the fighter in a burning aura")
	var probe: TankProjectile = game.make_projectile(game.local(), game.local().muzzle(), Vector2(10, -200), 1, 4.0, {})
	await process_frame
	await process_frame
	check(battle.trails.has_path(game.local_id), "a fired shot draws its dashed flight line")
	game.projectiles.erase(probe)
	probe.queue_free()
	game.turn_pow = false
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
	check(app.audio.music_track == "lobby", "the lobby theme returns on the results screen")
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
	# Moedas (0.10): currencies used on gear and maps from the Ferreiro.
	app.profile.redeem("MOEDAS")
	smith.select_tab("Moedas")
	var crown: Dictionary = app.profile.inventory.filter(func(i: Dictionary) -> bool: return i.id == "chapeu_coroa").front()
	smith.pick_craft(int(crown.uid))
	await process_frame
	var brasa_button: Button = smith.find_child("Currency_brasa", true, false)
	var coroa_button: Button = smith.find_child("Currency_coroa", true, false)
	check(brasa_button != null and not brasa_button.disabled and coroa_button.disabled, "the Moedas tab only enables the currencies that fit the item")
	brasa_button.pressed.emit()
	check(crown.quality == "excelente" and crown.mods.size() == 1 and smith.message.begins_with("Usou Brasa"), "a Brasa makes a hat Excelente with one bonus")
	var loose_map: Dictionary = app.profile.add_map(InstanceRun.make_map("ilha_ruinas", 3, RandomNumberGenerator.new(), 0.0, "normal"))
	smith.select_target("map")
	smith.pick_craft(int(loose_map.uid))
	await process_frame
	check(smith.find_child("CraftMap_%d" % int(loose_map.uid), true, false) != null and smith.find_child("Currency_espelho", true, false).disabled, "maps can be crafted too (the Espelho only copies gear)")
	smith.do_craft("brasa")
	check(loose_map.quality == "excelente" and loose_map.mods.size() == 1, "a Brasa turns a map Excelente")
	smith.close()
	bag.filter_items("Materiais")
	check(bag.entries().any(func(e: Dictionary) -> bool: return e.key == "item:solar" and int(e.count) == 5), "currencies show in the Materiais tab")
	bag.select_item("item:solar")
	check(bag.selected_label.text.contains("Rerola só os valores"), "a selected currency explains its use")
	bag.select_item("uid:%d" % int(crown.uid))
	check(bag.selected_label.text.contains("Nível do item") and bag.selected_label.text.contains("F"), "the Mochila lists the item's bonuses and item level")
	bag.select_tab("Atributos")
	bag.select_tab("Histórico")
	app.close_bag()
	await process_frame
	check(not is_instance_valid(app.bag), "Mochila closes")
	# Instância (0.9): instance choice, map slot, 3 phases
	app.create_room("pve")
	app.show_room()
	await process_frame
	check(app.screen.find_child("MapSlot", true, false) != null and app.screen.find_child("Difficulty_hard", true, false) == null, "the difficulty list became a map slot")
	app.profile.redeem("MAPAS")
	app.screen.choose_instance()
	await process_frame
	var picker: Node = app.screen.find_child("Instance_picos_gelados", true, false)
	check(picker != null, "Local lists the four instances")
	picker.pressed.emit()
	await process_frame
	check(app.room.instance == "picos_gelados" and app.room.map_uid == -1, "the instance can be chosen")
	app.screen.pick_instance("templo_sol", Control.new())
	await process_frame
	var owned: Array[Dictionary] = app.profile.maps_for("templo_sol")
	check(owned.size() == 4 and int(owned[0].level) == 16, "the MAPAS coupon gives maps of levels 1 to 16")
	var chosen: Dictionary = owned[-1]
	app.screen.choose_map_item()
	await process_frame
	var slot_button: Node = app.screen.find_child("MapItem_%d" % int(chosen.uid), true, false)
	check(slot_button != null, "the map picker lists the player's maps")
	slot_button.pressed.emit()
	await process_frame
	check(int(app.room.map_uid) == int(chosen.uid), "a map is placed in the room")
	app.start_battle()
	await process_frame
	game = app.screen.game
	check(app.profile.find_map(int(chosen.uid)).is_empty(), "the map is consumed on entry")
	check(game.pve and game.phase.index == 0 and int(game.phase.level) == int(chosen.level) and game.fighters.any(func(f: TankFighter) -> bool: return f.rank == "minion"), "the Instância starts at phase 1 with minions")
	check(app.screen.hud.find_child("PhasePanel", true, false) != null, "the HUD shows the phase and its objective")
	check(app.audio.music_track == "instance", "the Instância plays its own theme")
	game.waves.clear()
	for fighter in game.fighters:
		if fighter.team == 1:
			fighter.hp = 0
	game.evaluate_winner()
	await create_timer(1.9).timeout
	var between: PhaseTransition = app.screen.transition
	check(is_instance_valid(between) and between.find_child("Advance", true, false) != null, "a transition screen follows each phase")
	between.advance()
	await process_frame
	game = app.screen.game
	check(game.phase.index == 1 and game.fighters.any(func(f: TankFighter) -> bool: return f.rank == "guardian"), "phase 2 (guardian) follows")
	app.screen.toggle_pause()
	check(game.paused, "battle can be paused")
	check(app.screen.hud.pause_box.find_child("MusicToggle", true, false) != null and app.screen.hud.pause_box.find_child("SfxToggle", true, false) != null, "pause menu switches music and effects")
	app.screen.forfeit()
	await process_frame
	check(not game.running and not app.last_summary.won, "forfeit counts as defeat")
	check(app.last_summary.has("instance") and int(app.last_summary.instance.phases) == 1, "the result keeps the phases won")
	app.screen.show_results()
	await process_frame
	check(app.screen.results.find_child("InstanceBox", true, false) != null, "the result shows the instance run")
	app.open_bag()
	await process_frame
	app.bag.filter_items("Mapas")
	await process_frame
	check(app.bag.entries().size() >= 12 and app.bag.entries().all(func(e: Dictionary) -> bool: return e.has("map")), "the Mochila has a Mapas tab")
	app.close_bag()
	app.shortcut("help")
	app.show_city()
	await process_frame
	check(app.screen is CityScreen, "back to the city")
	scene.queue_free()
	await process_frame
	# Let the audio server drop the stopped playbacks before quitting.
	await create_timer(0.3).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("UI RESULT: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)
