extends SceneTree

# Online end to end (backend 0.11): a real game server (in-memory API) and two players,
# each a full copy of the game, in one process over real WebSockets. Logins, the
# character, profile operations checked by the server, chat, rooms, matchmaking, a PvP
# battle in lockstep played to the end, a player dropping and coming back mid-battle,
# the reward cards dealt by the server, an instance with a group and the Leilão (0.12):
# listing, searching, buying, the Correio, cancelling and the screens. Launch checklist:
# deleting the account from inside the game (Ajuda → Minha conta).
# Physics runs at 480 ticks per second so battles take a fraction of the time.

const PORT: int = 7391
const URL: String = "ws://127.0.0.1:7391"

var failures: int = 0
var checks: int = 0
var server: GameServer

func _initialize() -> void:
	call_deferred("run_tests")

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

func make_app() -> Node:
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	return app

func login(app: Node, user: String) -> String:
	var code: String = await app.net.connect_to(URL, "dev:" + user)
	if code == "":
		app.go_online(app.net.welcome())
	return code

func server_profile(app: Node) -> PlayerProfile:
	return server.accounts[app.my_account()].profile

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	AuthClient.config_path = "user://test_online.cfg"
	PlayerProfile.path_override = "user://test_e2e_profile.json"
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	server = GameServer.new()
	server.configure({"port": str(PORT), "bind": "127.0.0.1", "api": "memory", "bot-fill": "2", "test-coupons": "1", "id": "t1", "name": "Teste", "report-mute": "1"})
	root.add_child(server)
	await process_frame
	check(server.listening, "the game server listens")
	await handshake_tests()
	var alice: Node = await make_app()
	var bob: Node = await make_app()
	await account_tests(alice, bob)
	await chat_tests(alice, bob)
	await pvp_tests(alice, bob)
	await drop_tests(alice, bob)
	await pve_tests(alice, bob)
	await auction_tests(alice, bob)
	await takeover_tests(alice)
	await privacy_tests(bob)
	print("NET E2E RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func handshake_tests() -> void:
	var probe: NetClient = NetClient.new()
	root.add_child(probe)
	check(await probe.connect_to(URL, "forged-token") == "unauthorized", "a forged token is refused")
	check(await probe.connect_to("ws://127.0.0.1:1", "dev:x") == "unreachable", "an unreachable server is reported")
	# An old build (other balance files or protocol) is refused.
	var raw: WebSocketPeer = WebSocketPeer.new()
	raw.connect_to_url(URL)
	await wait_until(func() -> bool:
		raw.poll()
		return raw.get_ready_state() == WebSocketPeer.STATE_OPEN, 5)
	raw.send_text(JSON.stringify({"t": "hello", "token": "dev:velho", "protocol": 1, "content": "0.9-1-abc"}))
	var answer: Array = [{}]
	await wait_until(func() -> bool:
		raw.poll()
		while raw.get_available_packet_count() > 0:
			answer[0] = JSON.parse_string(raw.get_packet().get_string_from_utf8())
		return not answer[0].is_empty(), 5)
	check(str(answer[0].get("error", "")) == "outdated", "an outdated game version is refused")
	probe.queue_free()

func account_tests(alice: Node, bob: Node) -> void:
	check(await login(alice, "alice") == "", "a player logs in")
	check(await login(bob, "bob") == "", "a second player logs in")
	check(alice.online and alice.screen_name == "city", "online, the game opens the city")
	check(alice.profile.remote and not alice.profile.created, "a new account starts with no character")
	check(server.accounts.size() == 2, "the server knows both players")
	var outcome: Dictionary = await alice.do_op("create", ["Alice", "f"])
	check(outcome.error == "" and alice.profile.player_name == "Alice", "the character is created through the server")
	check(server_profile(alice).player_name == "Alice" and server_profile(alice).created, "the server keeps the character")
	outcome = await bob.do_op("create", ["alice", "m"])
	check(outcome.error != "" and not bob.profile.created, "character names are unique")
	check((await bob.do_op("create", ["Bob", "m"])).error == "", "another name works")
	# The server decides: a doctored copy on the client changes nothing.
	alice.profile.coins = 999999
	outcome = await alice.do_op("buy", ["fogo_intenso", "normal"])
	check(outcome.error != "", "the server refuses a purchase the player cannot pay")
	check(alice.profile.coins == server_profile(alice).coins and alice.profile.coins < 1000, "the client's copy is replaced by the server's")
	check((await alice.do_op("redeem", ["PEDRAS"])).error == "", "test coupons work on a test server")
	check(server_profile(alice).stone_points() > 0 and alice.profile.stone_points() == server_profile(alice).stone_points(), "the coupon reached the server's profile")
	check((await alice.do_op("redeem", ["PEDRAS"])).error != "", "a coupon is used once online too")
	await wait_until(func() -> bool: return server.accounts.values().all(func(s: PlayerSession) -> bool: return not s.dirty and not s.saving), 5)
	var stored: Dictionary = server.api.memory_profiles.get(alice.my_account(), {})
	check(str(stored.get("name", "")) == "Alice" and int(stored.get("version", 0)) >= 1, "profiles are saved through the API")

func chat_tests(alice: Node, bob: Node) -> void:
	alice.lobby.post("Alice", "bora uma partida, porra", "Atual")
	var arrived: bool = await wait_until(func() -> bool: return not bob.lobby.history.is_empty() and str(bob.lobby.history.back().author) == "Alice", 5)
	check(arrived, "chat reaches the other player")
	check(arrived and str(bob.lobby.history.back().text) == "bora uma partida, *****", "the chat hides bad words")
	for i in range(8):
		alice.lobby.post("Alice", "spam %d" % i, "Atual")
	await wait_until(func() -> bool: return false, 0.5)
	var spam: int = bob.lobby.history.filter(func(entry: Dictionary) -> bool: return str(entry.text).begins_with("spam")).size()
	check(spam < 8, "chat flooding is limited")
	await report_tests(alice, bob)

# Launch checklist: reporting a chat line. The server keeps who wrote each line, sends
# the report with its context and mutes the author after reports from `report-mute`
# players (1 in this test, 3 by default).
func report_tests(alice: Node, bob: Node) -> void:
	await wait_until(func() -> bool: return false, 1.0)
	alice.lobby.post("Alice", "linha denunciada", "Atual")
	check(await wait_until(func() -> bool: return bob.lobby.history.any(func(entry: Dictionary) -> bool: return str(entry.text) == "linha denunciada"), 5), "the line reaches the other player")
	var line: Dictionary = bob.lobby.history.filter(func(entry: Dictionary) -> bool: return str(entry.text) == "linha denunciada").back()
	check(line.has("id") and int(line.account) == alice.my_account(), "online lines carry their id and author")
	var chat: ChatBox = bob.screen.find_children("*", "ChatBox", true, false).front() if not bob.screen.find_children("*", "ChatBox", true, false).is_empty() else null
	check(chat != null and chat.log_label.text.contains("[url=%d]Alice[/url]" % int(line.id)), "another player's name is a report link")
	var own: Dictionary = alice.lobby.history.filter(func(entry: Dictionary) -> bool: return str(entry.text) == "linha denunciada").back()
	check(not (alice.screen.find_children("*", "ChatBox", true, false).front() as ChatBox).reportable(own), "your own lines are not reportable")
	check(not (await alice.net.request("chat_report", {"id": int(line.id), "reason": "ofensa"})).ok, "the server refuses reporting your own line")
	check(not (await bob.net.request("chat_report", {"id": int(line.id), "reason": "inventado"})).ok, "a report needs a known reason")
	check(not (await bob.net.request("chat_report", {"id": 999999, "reason": "ofensa"})).ok, "an unknown line cannot be reported")
	chat.on_meta(str(line.id))
	await process_frame
	var dialog: ReportDialog = null
	for node in bob.ui.get_children():
		if node is ReportDialog:
			dialog = node
	check(dialog != null and dialog.find_child("Send", true, false).disabled, "the name opens the report dialog; sending needs a reason")
	dialog.pick("ofensa")
	dialog.note.text = "xingou, porra"
	dialog.hide_box.button_pressed = true
	await dialog.send()
	check(not is_instance_valid(dialog) or dialog.is_queued_for_deletion(), "the report is sent and the dialog closes")
	var reports: Array = server.api.memory_reports
	check(reports.size() == 1 and int(reports[0].reported_id) == alice.my_account() and int(reports[0].reporter_id) == bob.my_account() and str(reports[0].message) == "linha denunciada", "the API gets the reported line, who reported and who wrote it")
	check((reports[0].context as Array).any(func(entry: Dictionary) -> bool: return bool(entry.reported)) and (reports[0].context as Array).size() > 1, "the report carries the lines around it")
	check(str(reports[0].note) == "xingou, *****", "the note goes through the word filter")
	check(bob.lobby.ignored.has(alice.my_account()) and not chat.log_label.text.contains("linha denunciada"), "the reporter hid the author's lines")
	check(not (await bob.net.request("chat_report", {"id": int(line.id), "reason": "spam"})).ok, "the same line is reported once per player")
	check(bool(reports[0].auto_muted) and server.muted_until.has(alice.my_account()), "reports from enough players mute the author")
	var before: int = alice.lobby.history.size()
	alice.lobby.post("Alice", "ainda posso falar?", "Atual")
	check(await wait_until(func() -> bool: return alice.lobby.history.slice(before).any(func(entry: Dictionary) -> bool: return str(entry.channel) == "system" and str(entry.text).contains("silenciad")), 5), "a muted player is told and their line is not sent")
	server.muted_until.clear()
	bob.lobby.ignored.clear()

func pvp_tests(alice: Node, bob: Node) -> void:
	bob.show_hall()
	await alice.open_room("pvp")
	check(alice.screen_name == "room" and alice.room.members.size() == 1 and alice.is_owner(), "a room is created on the server")
	check(await wait_until(func() -> bool: return bob.lobby.rooms.any(func(room: Dictionary) -> bool: return int(room.id) == int(alice.room.id)), 5), "the room shows in the other player's Salão")
	await bob.open_room("pvp")
	# Both rooms search; the matchmaking pairs them (same size, close levels).
	await alice.net.request("room_start")
	await bob.net.request("room_start")
	check(await wait_until(func() -> bool: return alice.screen_name == "battle" and bob.screen_name == "battle", 10), "matchmaking puts the two rooms in one battle")
	var a: BattleScreen = alice.screen
	var b: BattleScreen = bob.screen
	check(a.online and a.match_id == b.match_id and server.hosts.has(a.match_id), "both players are in the same online battle")
	check(a.game.fighters.size() == 2 and a.game.fighters.all(func(f: TankFighter) -> bool: return f.human), "human against human")
	check(a.game.local_id != b.game.local_id, "each player controls their own fighter")
	check((await alice.do_op("buy_tool", ["hp"])).error != "", "the profile cannot change during a battle")
	a.game.set_auto_play(true)
	b.game.set_auto_play(true)
	check(await wait_until(func() -> bool: return a.game.local().auto_play and b.game.fighters[a.game.local_id].auto_play, 5), "Confiar reaches every copy as an intent")
	var ended: bool = await wait_until(func() -> bool: return a.ending_shown and b.ending_shown, 300)
	check(ended, "the battle ends for both players")
	var host_winner: int = a.game.winner_team
	check(a.game.winner_team == b.game.winner_team, "both copies agree on the winner")
	check(not a.driver.drift_reported and not b.driver.drift_reported, "no copy drifted from the server")
	check(bool(a.summary.won) != bool(b.summary.won) or host_winner < 0, "one wins and the other loses")
	check(alice.profile.matches == 1 and server_profile(alice).matches == 1, "the result is recorded by the server")
	# Reward cards: dealt and granted by the server.
	check(await wait_until(func() -> bool: return is_instance_valid(a.results), 8), "the result screen opens")
	a.results.show_cards()
	var picks: int = a.results.picks_left
	check(picks == (2 if a.summary.won else 1), "winners pick 2 cards, losers 1")
	check(a.results.rewards.all(func(card: Dictionary) -> bool: return card.is_empty()), "the cards are unknown before picking")
	for i in range(picks):
		a.results.pick(i)
	check(await wait_until(func() -> bool: return a.results.rewards.all(func(card: Dictionary) -> bool: return not card.is_empty()), 5), "after the picks every card is shown")
	check(JSON.stringify(alice.profile.to_data()) == JSON.stringify(server_profile(alice).to_data()), "the client's profile matches the server's after the cards")
	alice.return_to_room()
	bob.return_to_room()
	check(await wait_until(func() -> bool: return server.hosts.is_empty() and str(alice.room.get("state", "")) == "waiting", 5), "the rooms wait again after the battle")

func drop_tests(alice: Node, bob: Node) -> void:
	await alice.net.request("room_start")
	await bob.net.request("room_start")
	check(await wait_until(func() -> bool: return alice.screen_name == "battle" and bob.screen_name == "battle", 10), "a second battle starts")
	var a: BattleScreen = alice.screen
	a.game.set_auto_play(true)
	await wait_until(func() -> bool: return a.driver.tick > 600, 20)
	# Bob's connection drops: the AI plays for him and the battle goes on.
	var bob_account: int = bob.my_account()
	bob.net.socket.close()
	check(await wait_until(func() -> bool: return bob.screen_name == "title" and server.accounts.has(bob_account) and server.accounts[bob_account].lingering, 5), "a dropped player is kept while the battle goes on")
	await wait_until(func() -> bool: return a.driver.tick > 1500, 20)
	check(await login(bob, "bob") == "", "the player logs in again mid-battle")
	check(await wait_until(func() -> bool: return bob.screen_name == "battle", 5), "coming back reopens the battle")
	var b: BattleScreen = bob.screen
	check(b.resume.has("history"), "the server sends the battle so far")
	check(await wait_until(func() -> bool: return b.driver.behind() < 10 and b.driver.tick > 1500, 20), "the returning copy catches up")
	var ended: bool = await wait_until(func() -> bool: return a.ending_shown and b.ending_shown, 300)
	check(ended, "the battle ends for both after the return")
	check(a.game.winner_team == b.game.winner_team and not b.driver.drift_reported, "the returning copy agrees with the server")
	check(bob.profile.matches == 2, "the returning player gets the result")
	alice.return_to_room()
	bob.return_to_room()
	await wait_until(func() -> bool: return server.hosts.is_empty(), 5)

func pve_tests(alice: Node, bob: Node) -> void:
	bob.show_hall()
	alice.show_hall()
	await wait_until(func() -> bool: return alice.room.is_empty() and server.rooms.is_empty(), 5)
	await alice.open_room("pve")
	await bob.join_room({"id": alice.room.id, "playing": false, "members": [], "capacity": 4})
	check(bob.screen_name == "room" and bob.room.members.size() == 2, "a second player joins the instance room")
	var refused: Dictionary = await alice.net.request("room_start")
	check(not refused.ok, "the owner waits until everyone is ready")
	await bob.net.request("room_ready", {"on": true})
	var coins: Dictionary = {"alice": server_profile(alice).coins, "bob": server_profile(bob).coins}
	var go: Dictionary = await alice.net.request("room_start")
	check(go.ok, "the instance starts")
	check(await wait_until(func() -> bool: return alice.screen_name == "battle" and bob.screen_name == "battle", 10), "both players enter the instance")
	var a: BattleScreen = alice.screen
	var b: BattleScreen = bob.screen
	check(a.game.pve and a.game.fighters.filter(func(f: TankFighter) -> bool: return f.human).size() == 2, "the party fights together")
	a.game.set_auto_play(true)
	b.game.set_auto_play(true)
	var cleared: bool = await wait_until(func() -> bool: return a.in_phase_break() and b.in_phase_break() or (a.ending_shown and b.ending_shown), 300)
	check(cleared, "the first phase ends for both")
	check(not a.driver.drift_reported and not b.driver.drift_reported, "the party's copies stay identical")
	if a.in_phase_break():
		check(int(a.phase_report.gold) > 0 and int(b.phase_report.gold) > 0, "each player gets their own phase loot")
		check(server_profile(alice).coins > int(coins.alice) and server_profile(bob).coins > int(coins.bob), "the phase gold is in both profiles")
		var first: Array = [a.get_instance_id(), b.get_instance_id()]
		var next: bool = await wait_until(func() -> bool: return alice.screen_name == "battle" and bob.screen_name == "battle" and alice.screen.get_instance_id() != first[0] and bob.screen.get_instance_id() != first[1], 30)
		check(next, "the next phase starts for both after the transition")
		if next:
			check(int(alice.screen.game.phase.get("index", 0)) == 1, "the second phase is played")
	# Both give up: the battle stops without rewards.
	var host_count: int = server.hosts.size()
	alice.screen.forfeit()
	bob.screen.forfeit()
	check(host_count == 1 and await wait_until(func() -> bool: return server.hosts.is_empty(), 5), "when everyone leaves, the battle is closed")
	check(alice.screen_name == "hall" and bob.screen_name == "hall", "leaving goes back to the Salão")

# How many copies of an item exist, in both profiles and on sale (never more than one).
func copies(alice: Node, bob: Node, id: String, ilvl: int) -> int:
	var count: int = 0
	for app: Node in [alice, bob]:
		count += server_profile(app).inventory.filter(func(inst: Dictionary) -> bool: return inst.id == id and int(inst.get("ilvl", 0)) == ilvl).size()
	count += server.api.memory_listings.filter(func(l: Dictionary) -> bool: return l.status == "active" and l.item_id == id and int(l.item_level) == ilvl).size()
	return count

func auction_tests(alice: Node, bob: Node) -> void:
	alice.show_city()
	bob.show_city()
	# A weapon and a map that dropped for Alice (as the instance would give them).
	var seller: PlayerProfile = server_profile(alice)
	var drop: Dictionary = seller.add_instance("trovao", "verdadeira", 2, 12)
	drop.mods = Crafting.roll_mods(drop, seller.rng)
	var map: Dictionary = seller.add_map(InstanceRun.make_map("templo_sol", 6, seller.rng, 0.0, "excelente"))
	seller.coins += 500
	seller.save_profile()
	server.accounts[alice.my_account()].send({"t": "profile", "profile": seller.to_data()})
	check(await wait_until(func() -> bool: return not alice.profile.find_instance(int(drop.uid)).is_empty(), 5), "the drop reaches the player")
	var coins: int = alice.profile.coins
	var reply: Dictionary = await alice.trade("auction_list", {"kind": "item", "uid": int(drop.uid), "solar": 3, "estrela": 2, "hours": 24})
	check(reply.ok, "a dropped weapon is listed")
	check(alice.profile.find_instance(int(drop.uid)).is_empty() and seller.find_instance(int(drop.uid)).is_empty(), "the listed item leaves the Mochila")
	check(alice.profile.coins == coins - Auction.fee_for(24), "the listing fee is paid in gold")
	var stored: Dictionary = server.api.memory_profiles[alice.my_account()]
	check(not (stored.data.inventory as Array).any(func(inst: Dictionary) -> bool: return int(inst.uid) == int(drop.uid)), "the stored profile loses the item with the listing (custody)")
	check(copies(alice, bob, "trovao", 12) == 1, "the item exists once: on sale")
	reply = await alice.trade("auction_list", {"kind": "item", "uid": int(alice.profile.equipped.arma), "solar": 1, "estrela": 0, "hours": 12})
	check(not reply.ok and str(reply.error) != "", "an equipped or bound item is refused")
	reply = await alice.trade("auction_list", {"kind": "map", "uid": int(map.uid), "solar": 0, "estrela": 4, "hours": 12})
	check(reply.ok and alice.profile.find_map(int(map.uid)).is_empty(), "a map is listed")
	var map_listing: int = int(reply.listing.id)
	# Bob looks for it.
	reply = await bob.trade("auction_search", {"filter": {"slot": "arma", "quality": "verdadeira", "min_level": 10}})
	check(reply.ok and reply.listings.size() == 1 and str(reply.listings[0].seller_name) == "Alice", "the other player finds it with filters")
	var listing: Dictionary = reply.listings[0] if reply.ok and not reply.listings.is_empty() else {}
	await wait_until(func() -> bool: return false, 0.35)
	reply = await bob.trade("auction_search", {"filter": {"slot": "mapa", "max_estrela": 3}})
	check(reply.ok and reply.listings.is_empty(), "a price limit filters")
	reply = await bob.trade("auction_buy", {"id": int(listing.get("id", -1)), "solar": 3, "estrela": 2})
	check(not reply.ok, "nobody buys without the currencies")
	await bob.do_op("redeem", ["MOEDAS"])
	var solar: int = bob.profile.currency_count("solar")
	var estrela: int = bob.profile.currency_count("estrela")
	reply = await bob.trade("auction_buy", {"id": int(listing.get("id", -1)), "solar": 1, "estrela": 2})
	check(not reply.ok and str(reply.error) == tr("O preço deste anúncio mudou. Atualize a busca."), "the price must be the listed one")
	check(bob.profile.currency_count("solar") == solar, "a refused purchase costs nothing")
	reply = await bob.trade("auction_buy", {"id": int(listing.get("id", -1)), "solar": 3, "estrela": 2})
	check(reply.ok and bool(reply.get("received", false)), "the purchase goes through")
	var bought: Array = bob.profile.inventory.filter(func(inst: Dictionary) -> bool: return inst.id == "trovao" and int(inst.get("ilvl", 0)) == 12)
	check(bought.size() == 1 and int(bought[0].level) == 2 and (bought[0].mods as Array).size() == (drop.mods as Array).size(), "the item arrives in the buyer's Mochila as it was sold")
	check(bob.profile.currency_count("solar") == solar - 3 and bob.profile.currency_count("estrela") == estrela - 2, "the price leaves the buyer")
	check(copies(alice, bob, "trovao", 12) == 1, "still one copy after the sale")
	check(await wait_until(func() -> bool: return alice.mail_count == 1, 5), "the seller is told a letter arrived")
	# Alice gets paid through the Correio (3 Solares and 2 Estrelas: 5% is less than 1).
	var alice_solar: int = alice.profile.currency_count("solar")
	var alice_estrela: int = alice.profile.currency_count("estrela")
	reply = await alice.trade("mail_list")
	check(reply.ok and reply.mail.size() == 1 and str(reply.mail[0].kind) == "sale", "the sale waits in the Correio")
	reply = await alice.trade("mail_claim", {"ids": []})
	check(reply.ok and alice.profile.currency_count("solar") == alice_solar + 3 and alice.profile.currency_count("estrela") == alice_estrela + 2, "receiving the letter pays the seller")
	check(await wait_until(func() -> bool: return alice.mail_count == 0, 5), "the Correio is empty again")
	reply = await alice.trade("auction_cancel", {"id": map_listing})
	check(reply.ok and alice.profile.maps.any(func(item: Dictionary) -> bool: return item.instance == "templo_sol" and int(item.level) == 6), "cancelling brings the map back")
	# Bob sells it on; he cannot buy his own listing.
	var resale: int = int(bought[0].uid) if not bought.is_empty() else -1
	reply = await bob.trade("auction_list", {"kind": "item", "uid": resale, "solar": 1, "estrela": 0, "hours": 12})
	check(reply.ok, "a bought item can be sold again")
	var resale_id: int = int(reply.listing.id) if reply.ok else -1
	reply = await bob.trade("auction_buy", {"id": resale_id, "solar": 1, "estrela": 0})
	check(not reply.ok, "nobody buys their own listing")
	reply = await bob.trade("auction_mine")
	check(reply.ok and reply.active.size() == 1 and int(reply.max) == Auction.max_listings(), "the seller sees the listing")
	# The screens: Alice buys it back through the Leilão.
	var auction: AuctionScreen = alice.open_auction()
	check(auction != null, "the Leilão opens online")
	check(await wait_until(func() -> bool: return auction.searched and not auction.loading, 5), "the Leilão searches when it opens")
	check(await wait_until(func() -> bool: return auction.find_child("Listing_%d" % resale_id, true, false) != null, 5), "the listing is on the screen")
	auction.pick(auction.results.find(auction.results.filter(func(l: Dictionary) -> bool: return int(l.id) == resale_id).front()))
	check(await wait_until(func() -> bool: return not auction.selected.is_empty() and int(auction.selected.id) == resale_id, 5), "a listing is chosen")
	var buy_button: Button = auction.find_child("BuyButton", true, false)
	check(buy_button != null and not buy_button.disabled, "it can be bought")
	auction.confirm_buy()
	var confirm: Button = auction.find_child("ConfirmButton", true, false)
	check(confirm != null, "buying asks to confirm")
	confirm.pressed.emit()
	check(await wait_until(func() -> bool: return alice.profile.inventory.any(func(inst: Dictionary) -> bool: return inst.id == "trovao" and int(inst.get("ilvl", 0)) == 12), 5), "bought through the screen")
	check(copies(alice, bob, "trovao", 12) == 1, "one copy after the second sale")
	auction.select_tab("sell")
	check(await wait_until(func() -> bool: return auction.find_child("ListButton", true, false) != null, 5), "the Vender tab shows a tradeable item")
	auction.select_tab("mine")
	check(await wait_until(func() -> bool: return not auction.loading and auction.mine_active.is_empty() and not auction.mine_closed.is_empty(), 5), "Meus anúncios shows the closed listings")
	auction.close()
	var mail: MailScreen = bob.open_mail()
	check(await wait_until(func() -> bool: return not mail.loading and mail.letters.size() == 1, 5), "the Correio screen lists the seller's letter")
	(mail.find_child("ClaimAll", true, false) as Button).pressed.emit()
	check(await wait_until(func() -> bool: return not mail.loading and mail.letters.is_empty() and bob.profile.currency_count("solar") == solar - 3 + 1, 5), "RECEBER TUDO pays")
	mail.close()
	await wait_until(func() -> bool: return server.accounts.values().all(func(s: PlayerSession) -> bool: return not s.dirty and not s.saving and not s.busy), 5)
	for app: Node in [alice, bob]:
		check(JSON.stringify(app.profile.to_data()) == JSON.stringify(server_profile(app).to_data()), "%s's copy matches the server's after trading" % server_profile(app).player_name)
		check(JSON.stringify(ApiClient.copy(server.api.memory_profiles[app.my_account()].data)) == JSON.stringify(ApiClient.copy(server_profile(app).to_data())), "%s's stored profile matches" % server_profile(app).player_name)

func takeover_tests(alice: Node) -> void:
	# The same account logs in somewhere else: the new connection wins.
	var other: NetClient = NetClient.new()
	root.add_child(other)
	check(await other.connect_to(URL, "dev:alice") == "", "the account logs in from another place")
	check(await wait_until(func() -> bool: return not alice.online and alice.screen_name == "title", 5), "the older connection is closed")
	check(server.accounts.size() == 2, "the account is still one player on the server")
	other.disconnect_now()
	await wait_until(func() -> bool: return server.accounts.size() == 1, 5)
	check(server.accounts.size() == 1, "logging out frees the account")

func privacy_tests(bob: Node) -> void:
	# LGPD/GDPR: the player deletes the account from inside the game, with the password.
	check(bob.online, "the second player is still online")
	var old_id: int = bob.my_account()
	var reply: Dictionary = await bob.net.request("account_delete", {"password": ""})
	check(not reply.ok and server.accounts.has(old_id), "deleting needs the password")
	var screen: AccountScreen = bob.open_account()
	await process_frame
	check(screen.find_child("Delete", true, false) != null and screen.find_child("Download", true, false) != null, "Minha conta offers the copy of the data and the deletion")
	screen.ask_delete()
	var problem: Label = screen.confirm_root.find_child("DeleteProblem", true, false)
	await screen.confirm_delete("", problem)
	check(problem.text != "" and server.accounts.has(old_id), "an empty password is refused on the screen")
	server.audit(server.accounts[old_id], "chat", {"text": "fica na fila"})
	await screen.confirm_delete("minha-senha", problem)
	check(await wait_until(func() -> bool: return not bob.online and bob.screen_name == "title", 5), "after deleting, the game goes back to the title")
	check(not server.accounts.has(old_id) and not server.api.memory_profiles.has(old_id), "the account and the profile are gone from the server")
	check(server.audit_queue.all(func(entry: Dictionary) -> bool: return entry.account_id == null or int(entry.account_id) != old_id), "nothing of the deleted account is logged afterwards")
	check(not is_instance_valid(screen) or not screen.is_inside_tree(), "the account panel closes with the connection")
	check(bob.auth.token == "", "the session is forgotten on this computer")
	check(await login(bob, "bob") == "" and bob.my_account() != old_id and not bob.profile.created, "the same name starts a brand new account")
	# A ban decided by the team (a reviewed chat report) reaches the game server with
	# the next heartbeat: the player is disconnected.
	server.api.memory_banned[bob.my_account()] = true
	await server.heartbeat()
	check(await wait_until(func() -> bool: return not bob.online and bob.screen_name == "title", 5), "a banned player is disconnected at the next heartbeat")
	bob.net.disconnect_now()
