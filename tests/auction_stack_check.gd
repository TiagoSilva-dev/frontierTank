extends SceneTree

# Checks the Leilão against the real Go API and PostgreSQL (the HTTP path that the
# in-memory tests do not cover): a game server runs in this process, connected to the
# API's internal port, and two players trade through it. A drop is put in the seller's
# profile on the server (as an instance would), listed, found, bought, paid by mail,
# cancelled, and finally read back from the database after logging in again.
# Not part of the offline suite: start PostgreSQL and the API first, then
#   godot --headless --path . --script tests/auction_stack_check.gd -- \
#     --api=http://localhost:8080 --internal=http://localhost:8081 --key=<INTERNAL_KEY>

const PORT: int = 7393

var failures: int = 0
var checks: int = 0
var server: GameServer

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

func player(api: String, user: String) -> Node:
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.auth.base_url = api
	app.auth.remember = false
	check(await app.auth.login(user, "senha-do-leilao-1", true) == "", "%s has an account" % user)
	check(await app.net.connect_to("ws://127.0.0.1:%d" % PORT, app.auth.token) == "", "%s joins the game server" % user)
	app.go_online(app.net.welcome())
	check((await app.do_op("create", [user.capitalize().substr(0, 14), "f"])).error == "", "%s creates the character" % user)
	return app

func give_drop(app: Node, id: String, ilvl: int) -> Dictionary:
	var session: PlayerSession = server.accounts[app.my_account()]
	var inst: Dictionary = session.profile.add_instance(id, "verdadeira", 1, ilvl)
	inst.mods = Crafting.roll_mods(inst, session.profile.rng)
	session.profile.coins += 300
	session.profile.save_profile()
	session.send({"t": "profile", "profile": session.profile.to_data()})
	await wait_until(func() -> bool: return not app.profile.find_instance(int(inst.uid)).is_empty(), 5)
	return inst

func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	AuthClient.config_path = "user://test_auction_stack.cfg"
	PlayerProfile.path_override = "user://test_auction_stack_profile.json"
	var api: String = "http://localhost:8080"
	var internal: String = "http://localhost:8081"
	var key: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api="):
			api = arg.substr(6)
		elif arg.begins_with("--internal="):
			internal = arg.substr(11)
		elif arg.begins_with("--key="):
			key = arg.substr(6)
	server = GameServer.new()
	server.configure({"port": str(PORT), "bind": "127.0.0.1", "api": internal, "api-key": key, "test-coupons": "1", "id": "leilao-check", "name": "Leilão check"})
	root.add_child(server)
	await process_frame
	var tag: int = int(Time.get_unix_time_from_system()) % 1000000
	var seller: Node = await player(api, "vend%d" % tag)
	var buyer: Node = await player(api, "comp%d" % tag)
	var drop: Dictionary = await give_drop(seller, "trovao", 13)
	var second: Dictionary = await give_drop(seller, "asas_fenix", 9)
	var reply: Dictionary = await seller.trade("auction_list", {"kind": "item", "uid": int(drop.uid), "solar": 2, "estrela": 20, "hours": 12})
	check(reply.ok, "the listing is stored in PostgreSQL")
	var listing_id: int = int(reply.listing.id) if reply.ok else -1
	check(reply.ok and int(reply.listing.item.ilvl) == 13, "the API keeps the item as it was")
	reply = await seller.trade("auction_list", {"kind": "item", "uid": int(second.uid), "solar": 1, "estrela": 0, "hours": 48})
	var second_id: int = int(reply.listing.id) if reply.ok else -1
	reply = await buyer.trade("auction_search", {"filter": {"slot": "arma", "item_id": "trovao", "min_level": 13}})
	check(reply.ok and reply.listings.any(func(l: Dictionary) -> bool: return int(l.id) == listing_id), "the buyer finds it through the API")
	await buyer.do_op("redeem", ["MOEDAS"])
	await buyer.do_op("redeem", ["MOEDAS"])
	var estrela: int = buyer.profile.currency_count("estrela")
	reply = await buyer.trade("auction_buy", {"id": listing_id, "solar": 2, "estrela": 20})
	check(reply.ok and bool(reply.get("received", false)), "the purchase and the mail go through the API")
	check(buyer.profile.inventory.any(func(inst: Dictionary) -> bool: return inst.id == "trovao" and int(inst.get("ilvl", 0)) == 13), "the item is in the buyer's Mochila")
	check(buyer.profile.currency_count("estrela") == estrela - 20, "the price left the buyer")
	check(await wait_until(func() -> bool: return seller.mail_count == 1, 5), "the seller hears about the sale")
	reply = await seller.trade("auction_history", {"kind": "item", "item": drop})
	check(reply.ok and reply.sales.size() >= 1, "the sale is in the price history")
	var solar: int = seller.profile.currency_count("solar")
	var stars: int = seller.profile.currency_count("estrela")
	reply = await seller.trade("mail_claim", {"ids": []})
	check(reply.ok and seller.profile.currency_count("solar") == solar + 2 and seller.profile.currency_count("estrela") == stars + 19, "the seller receives 2 Solares and 19 Estrelas (5% of 20 kept)")
	reply = await seller.trade("auction_cancel", {"id": second_id})
	check(reply.ok and seller.profile.inventory.any(func(inst: Dictionary) -> bool: return inst.id == "asas_fenix" and int(inst.get("ilvl", 0)) == 9), "a cancelled listing comes back")
	reply = await seller.trade("auction_mine")
	check(reply.ok and reply.active.is_empty() and reply.closed.size() == 2, "the seller's listings are closed")
	# Read everything back from PostgreSQL.
	var expected: Dictionary = seller.profile.to_data()
	var account: int = seller.my_account()
	seller.net.disconnect_now()
	seller.go_offline()
	# The server saves and frees the account when the player leaves.
	check(await wait_until(func() -> bool: return not server.accounts.has(account), 10), "the seller leaves the server")
	check(await seller.net.connect_to("ws://127.0.0.1:%d" % PORT, seller.auth.token) == "", "the seller logs in again")
	seller.go_online(seller.net.welcome())
	check(seller.profile.currency_count("solar") == int(expected.items.get("solar", 0)) and seller.profile.inventory.size() == (expected.inventory as Array).size(), "the stored profile has the payment and the returned item")
	check(not seller.profile.inventory.any(func(inst: Dictionary) -> bool: return inst.id == "trovao" and int(inst.get("ilvl", 0)) == 13), "and not the item it sold")
	seller.net.disconnect_now()
	buyer.net.disconnect_now()
	print("AUCTION STACK RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
