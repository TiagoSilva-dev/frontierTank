extends SceneTree
var checks: int = 0
var failures: int = 0
var server: GameServer
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
	else:
		print("PASS: " + text)
func _initialize() -> void:
	call_deferred("run")
class Peer extends Node:
	var auth: AuthClient
	var net: NetClient
	var profile: PlayerProfile = PlayerProfile.new()
	func trade(kind: String, data: Dictionary = {}) -> Dictionary:
		var result: Dictionary = await net.request(kind, data, 40.0)
		if result.has("profile"):
			profile.load_data(result.profile)
		return result
func player(user: String, hero: String) -> Peer:
	var app: Peer = Peer.new()
	root.add_child(app)
	app.auth = AuthClient.new()
	app.auth.base_url = "http://127.0.0.1:17880"
	app.auth.remember = false
	app.auth.token = ""
	app.add_child(app.auth)
	app.net = NetClient.new()
	app.add_child(app.net)
	var login_error: String = await app.auth.login(user, "local-test-password", true, Legal.VERSION)
	check(login_error == "", "test account created: " + login_error)
	if login_error != "":
		quit(1)
		return app
	check(await app.net.connect_to("ws://127.0.0.1:7398", app.auth.token) == "", "WebSocket authenticated")
	app.profile.load_data(app.net.welcome().profile)
	app.net.release_held()
	check((await app.trade("op", {"op": "create", "args": [hero, "m"]})).ok, "character created")
	check((await app.trade("op", {"op": "redeem", "args": ["TESTARTUDO"]})).ok, "test inventory funded")
	return app
func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	AuthClient.config_path = "user://test_exchange_online.cfg"
	PlayerProfile.path_override = "user://test_exchange_profile.json"
	server = GameServer.new()
	server.configure({"port": "7398", "bind": "127.0.0.1", "api": "http://127.0.0.1:17881", "api-key": "exchange-local-key", "test-coupons": "1", "bot-battles": "0", "id": "exchange-test"})
	root.add_child(server)
	await process_frame
	var suffix: String = str(int(Time.get_unix_time_from_system()) % 1000000)
	var alice: Node = await player("exa" + suffix, "Alice" + suffix)
	var bob: Node = await player("exb" + suffix, "Bob" + suffix)
	var original: int = alice.profile.currency_count("strength_stone_12")
	var gold: int = alice.profile.coins
	var listed: Dictionary = await alice.trade("exchange_create", {"give_id": "strength_stone_12", "want_id": "solar", "give_unit": 1, "want_unit": 4, "lots": 3})
	check(listed.ok, "stone order persisted through game server")
	if not listed.ok:
		print(listed)
		quit(1)
		return
	var id: int = int(listed.order.id)
	check(alice.profile.currency_count("strength_stone_12") == original - 3, "escrow debited from live profile")
	check(alice.profile.coins == gold - CurrencyExchange.fee(1, 3), "gold listing fee deducted")
	for session: PlayerSession in server.accounts.values():
		if session.account_id == int(alice.net.account.id):
			await server.flush_save(session)
			session.profile.on_save = Callable()
	alice.net.disconnect_now()
	await create_timer(1.0).timeout
	var bought: Dictionary = await bob.trade("exchange_create", {"give_id": "solar", "want_id": "strength_stone_12", "give_unit": 5, "want_unit": 1, "lots": 2})
	check(bought.ok and bought.get("order", {}).get("status", "") == "filled", "better-price stone order fills")
	check(bob.profile.currency_count("solar") == 190, "incoming budget reserved")
	check((await bob.trade("mail_claim")).ok, "buyer receives exchange settlement")
	check(bob.profile.currency_count("strength_stone_12") == 202, "buyer receives two stones")
	check(bob.profile.currency_count("solar") == 192, "unused budget returned at maker price")
	check(await alice.net.connect_to("ws://127.0.0.1:7398", alice.auth.token) == "", "seller reconnects after offline fill")
	alice.profile.load_data(alice.net.welcome().profile)
	alice.net.release_held()
	check((await alice.trade("mail_claim")).ok, "offline seller receives proceeds")
	check(alice.profile.currency_count("solar") == 208, "seller receives eight solar")
	check((await alice.trade("exchange_cancel", {"id": id})).ok, "remaining order cancelled")
	check((await alice.trade("mail_claim")).ok, "unfilled escrow returned")
	check(alice.profile.currency_count("strength_stone_12") == original - 2, "exact conservation after partial fill and cancellation")
	check(alice.profile.coins == gold - CurrencyExchange.fee(1, 3), "cancellation does not refund gold")
	var invalid: Dictionary = await alice.trade("exchange_create", {"give_id": "solar", "want_id": "brasa", "give_unit": 999999, "want_unit": 1, "lots": 1})
	check(not invalid.ok, "insufficient funds rejected on server")
	await create_timer(0.4).timeout
	var market: Dictionary = await alice.trade("exchange_book", {"give_id": "solar", "want_id": "brasa"})
	check(market.ok and not market.orders.is_empty(), "history loaded from PostgreSQL")
	for session: PlayerSession in server.accounts.values():
		await server.flush_save(session)
		session.profile.on_save = Callable()
	alice.net.disconnect_now()
	bob.net.disconnect_now()
	await create_timer(1.0).timeout
	alice.queue_free()
	bob.queue_free()
	await server.flush_audit()
	server.bots.free()
	server.queue_free()
	await process_frame
	print("EXCHANGE ONLINE RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
