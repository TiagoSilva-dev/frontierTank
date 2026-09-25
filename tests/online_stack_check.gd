extends SceneTree

# Checks a running online stack (server/docker-compose.yml) from a real game client:
# creates an account on the API, lists the servers, connects, creates the character,
# plays a battle against AI rivals, picks the cards, logs out, logs in again and reads
# the saved profile back, downloads the copy of the data and deletes the account from
# Minha conta (LGPD/GDPR). Not part of the offline suite: start the stack first
# (TEST_COUPONS=1 and a short BOT_FILL_SECONDS help), then:
#   godot --headless --path . --script tests/online_stack_check.gd -- --api=http://localhost:8080

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func wait_until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()

func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	AuthClient.config_path = "user://test_online.cfg"
	PlayerProfile.path_override = "user://test_stack_profile.json"
	var api: String = "http://localhost:8080"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api="):
			api = arg.substr(6)
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.auth.base_url = api
	app.auth.remember = false
	var user: String = "t%d" % (Time.get_unix_time_from_system() as int % 100000000)
	check(await app.auth.login(user, "senha-de-teste-1", true) != "", "an account needs the accepted terms")
	check(await app.auth.login(user, "senha-de-teste-1", true, Legal.VERSION) == "", "an account is created on the API (with the consent)")
	check(await app.auth.login(user, "senha-errada-99", false) == "invalid_credentials", "a wrong password is refused")
	check(await app.auth.login(user, "senha-de-teste-1", false) == "", "the account logs in")
	var listing: Dictionary = await app.auth.servers()
	var servers: Array = listing.get("servers", [])
	check(not servers.is_empty(), "the API lists the game servers")
	if servers.is_empty():
		finish()
		return
	var url: String = str(servers[0].url)
	check(await app.net.connect_to(url, app.auth.token) == "", "the game server accepts the session")
	app.go_online(app.net.welcome())
	check(app.online and not app.profile.created, "a new account has no character yet")
	var hero: String = "Tst%d" % (randi() % 100000)
	check((await app.do_op("create", [hero, "m"])).error == "", "the character is created")
	await app.do_op("redeem", ["MOEDAS"])
	await app.open_room("pvp")
	check(app.screen_name == "room", "a room opens on the server")
	await app.net.request("room_start")
	check(await wait_until(func() -> bool: return app.screen_name == "battle", 60), "AI rivals fill in and the battle starts")
	var battle: BattleScreen = app.screen
	battle.game.set_auto_play(true)
	check(await wait_until(func() -> bool: return battle.ending_shown, 600), "the battle is played to the end")
	check(not battle.driver.drift_reported, "the client's copy matched the server's")
	check(await wait_until(func() -> bool: return is_instance_valid(battle.results), 10), "the results open")
	battle.results.show_cards()
	for i in range(battle.results.picks_left):
		battle.results.pick(i)
	check(await wait_until(func() -> bool: return battle.results.rewards.all(func(card: Dictionary) -> bool: return not card.is_empty()), 10), "the server deals and shows the cards")
	var matches: int = app.profile.matches
	var coins: int = app.profile.coins
	check(matches == 1, "the battle is on the profile")
	app.net.disconnect_now()
	app.go_offline()
	# The server saves when the player leaves; a new login reads the database copy.
	await wait_until(func() -> bool: return false, 3.0)
	check(await app.net.connect_to(url, app.auth.token) == "", "the player logs in again")
	app.go_online(app.net.welcome())
	check(app.profile.player_name == hero and app.profile.matches == matches and app.profile.coins == coins, "the profile came back from PostgreSQL")
	# LGPD/GDPR: the copy of the data and deleting the account from inside the game.
	var copy: Dictionary = await app.auth.export_data()
	var parsed: Variant = JSON.parse_string(str(copy.get("text", "")))
	check(parsed is Dictionary and str(parsed.account.username) == user and str(parsed.profile.name) == hero and not str(copy.text).contains("password"), "Minha conta: the copy of the data has the account and the character")
	var token: String = app.auth.token
	var screen: AccountScreen = app.open_account()
	await process_frame
	screen.ask_delete()
	var problem: Label = screen.confirm_root.find_child("DeleteProblem", true, false)
	await screen.confirm_delete("senha-errada-99", problem)
	check(app.online and problem.text != "", "a wrong password does not delete the account")
	await screen.confirm_delete("senha-de-teste-1", problem)
	check(await wait_until(func() -> bool: return not app.online and app.screen_name == "title", 10), "the account is deleted and the game goes back to the title")
	app.auth.token = token
	var gone: Dictionary = await app.auth.request_json(HTTPClient.METHOD_GET, "/v1/me")
	check(int(gone.status) == 401, "the deleted account's session no longer works")
	app.auth.token = ""
	check(await app.auth.login(user, "senha-de-teste-1", false) == "invalid_credentials", "the deleted account cannot log in")
	finish()

func finish() -> void:
	print("STACK RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
