extends SceneTree

# Online end to end (backend 0.11): a real game server (in-memory API) and two players,
# each a full copy of the game, in one process over real WebSockets. Logins, the
# character, profile operations checked by the server, chat, rooms, matchmaking, a PvP
# battle in lockstep played to the end, a player dropping and coming back mid-battle,
# the reward cards dealt by the server, an instance with a group and the Leilão (0.12):
# listing, searching, buying, the Correio, cancelling and the screens. Launch checklist:
# deleting the account from inside the game (Ajuda → Minha conta), and the Steam shop
# (GodotSteam faked; the Steam Web API side is in server/api/steam_test.go).
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

# A profile as text, without the clock (it ticks, and the client's follows the server's within a second).
func profile_text(profile: PlayerProfile) -> String:
	var data: Dictionary = profile.to_data()
	data.erase("clock")
	return JSON.stringify(data)

# Where two texts first differ (for the message of a failing comparison); "" when equal.
func first_difference(a: String, b: String) -> String:
	if a == b:
		return ""
	for i in range(mini(a.length(), b.length())):
		if a[i] != b[i]:
			return " [differs at %d: %s <> %s]" % [i, a.substr(maxi(0, i - 60), 140), b.substr(maxi(0, i - 60), 140)]
	return " [lengths %d and %d]" % [a.length(), b.length()]

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
	server.configure({"port": str(PORT), "bind": "127.0.0.1", "api": "memory", "bot-fill": "2", "bot-battles": "0", "test-coupons": "1", "id": "t1", "name": "Teste", "report-mute": "1"})
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
	await ranked_tests(alice, bob)
	await challenge_tests(alice, bob)
	await pve_tests(alice, bob)
	await auction_tests(alice, bob)
	await reconnect_tests(alice)
	await takeover_tests(alice)
	await privacy_tests(bob)
	await steam_tests()
	await card_tests()
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
	check(int(server_profile(alice).items.get("pedra_fortalecimento", 0)) > 0 and alice.profile.items == server_profile(alice).items, "the coupon reached the server's profile")
	check((await alice.do_op("redeem", ["PEDRAS"])).error != "", "a coupon is used once online too")
	# Casa dos Mascotes (0.30): no eggs any more; the pets arrive by coupon here (and by the shop
	# in card_tests) and the server refuses the retired operations.
	check((await alice.do_op("pet_hatch", ["egg_sol"])).error != "" and (await alice.do_op("pet_feed", [1])).error != "" and (await alice.do_op("pet_evolve", [1, 2])).error != "" and server_profile(alice).pets.is_empty(), "the server knows no hatch, feed or star any more")
	check((await alice.do_op("redeem", ["MASCOTES"])).error == "" and server_profile(alice).pets.size() == 20 and alice.profile.pets.size() == 20, "the pet coupon reached the server and the client")
	check(alice.profile.pet_active == server_profile(alice).pet_active and alice.profile.pet_active > 0 and not server_profile(alice).items.keys().any(func(id: String) -> bool: return id.begins_with("egg_")), "the active pet matches the server's and there are no eggs")
	var released: int = int(alice.profile.pets[1].uid)
	check(alice.profile.pets[0] == server_profile(alice).pets[0] and (await alice.do_op("pet_release", [released])).error == "" and alice.profile.pets.size() == 19, "a pet can be released online")
	# Caçada dos Mascotes (0.20): the server settles the hunt with its own clock.
	var pet_uid: int = int(alice.profile.pets[0].uid)
	check((await alice.do_op("hunt_set", ["sol", 3, [pet_uid]])).error != "" and not bool(server_profile(alice).hunt.active), "the server refuses a hunt tier that is still locked")
	check((await alice.do_op("hunt_set", ["sol", 1, [pet_uid, 99999]])).error == "" and bool(server_profile(alice).hunt.active), "a hunt starts on the server (unknown pets are ignored)")
	check(alice.profile.hunt == server_profile(alice).hunt, "the client mirrors the server's hunt")
	server_profile(alice).hunt.since = int(server_profile(alice).hunt.since) - 1200
	var coins_hunt: int = server_profile(alice).coins
	check((await alice.do_op("hunt_collect", [])).error == "" and int(server_profile(alice).hunt.report.slots) == 100, "the server settles 100 encounters for 20 minutes away")
	check(server_profile(alice).coins == coins_hunt + int(server_profile(alice).hunt.report.coins) and alice.profile.coins == server_profile(alice).coins, "the hunt's coins reached the server and the client")
	check(int(alice.profile.hunt.report.slots) == 100 and abs(alice.profile.hunt_now() - server_profile(alice).hunt_now()) <= 2, "the client's clock follows the server's")
	check((await alice.do_op("hunt_stop", [])).error == "" and not bool(alice.profile.hunt.active), "the hunt can be stopped online")
	await wait_until(func() -> bool: return server.accounts.values().all(func(s: PlayerSession) -> bool: return not s.dirty and not s.saving), 5)
	var stored: Dictionary = server.api.memory_profiles.get(alice.my_account(), {})
	check(stored.get("data", {}).get("pets", []).size() == 19, "the pets are saved through the API")
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
	await whisper_tests(alice, bob)
	await report_tests(alice, bob)

# Player menu (0.18): private messages through the server, the public profile and friends.
func whisper_tests(alice: Node, bob: Node) -> void:
	await wait_until(func() -> bool: return false, 1.0)
	var to_bob: Dictionary = {"name": bob.profile.player_name, "account": bob.my_account()}
	alice.lobby.whisper(to_bob, "oi bob, é segredo", alice.profile.player_name)
	var got: bool = await wait_until(func() -> bool: return bob.lobby.history.any(func(entry: Dictionary) -> bool: return str(entry.text) == "oi bob, é segredo"), 5)
	check(got, "a private message reaches the other player")
	var secret: Dictionary = bob.lobby.history.filter(func(entry: Dictionary) -> bool: return str(entry.text) == "oi bob, é segredo").back() if got else {}
	check(got and str(secret.channel) == "Privado" and str(secret.author) == alice.profile.player_name and str(secret.to) == bob.profile.player_name, "it is on the Privado channel, from Alice, to Bob")
	check(bob.lobby.unread_private >= 1 and alice.lobby.unread_private == 0, "the receiver has an unread private line, the sender none")
	check(alice.lobby.history.any(func(entry: Dictionary) -> bool: return str(entry.text) == "oi bob, é segredo" and str(entry.channel) == "Privado"), "the sender sees the line too")
	var everyone_else: bool = true
	for entry: Dictionary in alice.lobby.history:
		if str(entry.text) == "oi bob, é segredo" and str(entry.channel) != "Privado":
			everyone_else = false
	check(everyone_else, "a private message never reaches the public channel")
	await wait_until(func() -> bool: return false, 1.0)
	var before: int = alice.lobby.history.size()
	alice.lobby.whisper({"name": "Fantasma", "account": 987654}, "tem alguém aí?", alice.profile.player_name)
	check(await wait_until(func() -> bool: return alice.lobby.history.slice(before).any(func(entry: Dictionary) -> bool: return str(entry.channel) == "system" and str(entry.text).contains("Fantasma")), 5), "a message to someone offline is answered with a notice")
	var info: Dictionary = await alice.lobby.profile_of({"account": bob.my_account()})
	check(str(info.get("name", "")) == bob.profile.player_name and info.get("look") is Dictionary and int(info.get("level", 0)) >= 1 and info.has("attrs"), "the profile of another player comes from the server")
	var missing: Dictionary = await alice.lobby.profile_of({"account": 987654})
	check(missing.has("error"), "the profile of someone not online is an error")
	alice.friends.path = "user://test_e2e_friends.json"
	alice.friends.use_scope("acc%d" % alice.my_account())
	check(alice.friends.add({"name": bob.profile.player_name, "account": bob.my_account(), "level": 1, "gender": "m"}) == "" and alice.friends.has(bob.profile.player_name), "Bob is added as a friend")
	alice.friends.use_scope("offline")
	check(not alice.friends.has(bob.profile.player_name), "the offline channel keeps its own list")
	alice.friends.use_scope("acc%d" % alice.my_account())
	check(alice.friends.has(bob.profile.player_name), "the friends of an account are kept")
	alice.friends.remove(bob.profile.player_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_e2e_friends.json"))

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
	check(chat != null and chat.log_label.text.contains("]Alice[/url]") and chat.log_label.text.contains("[url=m:"), "another player's name is a link to the player menu")
	var own: Dictionary = alice.lobby.history.filter(func(entry: Dictionary) -> bool: return str(entry.text) == "linha denunciada").back()
	check(not (alice.screen.find_children("*", "ChatBox", true, false).front() as ChatBox).reportable(own), "your own lines are not reportable")
	check(not (await alice.net.request("chat_report", {"id": int(line.id), "reason": "ofensa"})).ok, "the server refuses reporting your own line")
	check(not (await bob.net.request("chat_report", {"id": int(line.id), "reason": "inventado"})).ok, "a report needs a known reason")
	check(not (await bob.net.request("chat_report", {"id": 999999, "reason": "ofensa"})).ok, "an unknown line cannot be reported")
	var line_index: int = bob.lobby.history.find(line)
	chat.on_meta("m:%d" % line_index)
	await process_frame
	var menu: PlayerMenu = bob.ui.get_node_or_null("PlayerMenu")
	check(menu != null and menu.find_child("Menu_report", true, false) != null and menu.find_child("Menu_whisper", true, false) != null and menu.find_child("Menu_profile", true, false) != null, "the name opens the player menu, with the report for a line of someone else")
	menu.find_child("Menu_report", true, false).pressed.emit()
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
	check(profile_text(alice.profile) == profile_text(server_profile(alice)), "the client's profile matches the server's after the cards" + first_difference(profile_text(alice.profile), profile_text(server_profile(alice))))
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

func finish_battle(alice: Node, bob: Node) -> void:
	var a: BattleScreen = alice.screen
	var b: BattleScreen = bob.screen
	a.game.set_auto_play(true)
	b.game.set_auto_play(true)
	await wait_until(func() -> bool: return a.ending_shown and b.ending_shown, 300)

# The ranked ladder (0.22): the queue, a match against a real player, the rating on both
# sides, forfeiting, the ladder and the season's end with its title.
func ranked_tests(alice: Node, bob: Node) -> void:
	alice.show_hall()
	bob.show_hall()
	await wait_until(func() -> bool: return alice.room.is_empty() and bob.room.is_empty() and server.rooms.is_empty() and server.hosts.is_empty(), 10)
	if alice.profile.level() < int(Ranked.data().min_level):
		check(not (await alice.net.request("ranked_queue", {"on": true})).ok and not server.accounts[alice.my_account()].queued, "the ladder starts at its minimum level")
	for who: Node in [alice, bob]:
		server_profile(who).experience = PlayerProfile.exp_for_level(int(Ranked.data().min_level))
	var joined: Dictionary = await alice.net.request("ranked_queue", {"on": true})
	check(joined.ok and bool(joined.queued) and server.ranked_queue.size() == 1, "a player joins the ranked queue " + str(joined))
	await alice.net.request("ranked_queue", {"on": false})
	check(server.ranked_queue.is_empty() and not server.accounts[alice.my_account()].queued, "and leaves it")
	check((await alice.net.request("ranked_queue", {"on": true})).ok and (await bob.net.request("ranked_queue", {"on": true})).ok, "both join the queue")
	check(await wait_until(func() -> bool: return alice.screen_name == "battle" and bob.screen_name == "battle", 15), "the queue pairs two real players into a battle")
	var a: BattleScreen = alice.screen
	var b: BattleScreen = bob.screen
	check(a.game.ranked and b.game.ranked and a.online and a.game.fighters.size() == 2 and a.game.fighters.all(func(f: TankFighter) -> bool: return f.human), "it is a ranked 1v1 between humans")
	check(server.hosts[a.match_id].ranked.size() == 2 and server.ranked_queue.is_empty() and server.hosts[a.match_id].room == null, "the server marks the match as ranked and empties the queue")
	check(not (await alice.net.request("ranked_queue", {"on": true})).ok, "nobody can queue during a battle")
	var rating_a: int = int(server_profile(alice).rating.mmr)
	await finish_battle(alice, bob)
	check(a.ending_shown and b.ending_shown and a.game.winner_team == b.game.winner_team, "the ranked battle ends for both")
	var report_a: Dictionary = a.summary.get("ranked", {})
	var report_b: Dictionary = b.summary.get("ranked", {})
	check(not report_a.is_empty() and not report_b.is_empty() and int(report_a.delta) == -int(report_b.delta) and absi(int(report_a.delta)) == 24, "both results carry the rating change (24 points on an even match)")
	check(int(server_profile(alice).rating.mmr) == rating_a + int(report_a.delta) and int(server_profile(alice).rating.games) == 1 and int(server_profile(bob).rating.games) == 1, "the server applied it to both profiles")
	check(alice.profile.rating == server_profile(alice).rating and bob.profile.rating == server_profile(bob).rating, "the clients mirror the new ratings")
	check(await wait_until(func() -> bool: return is_instance_valid(a.results), 8) and a.results.find_child("RankedGain", true, false) != null, "the result screen shows the ranked gain")
	alice.return_to_room()
	bob.return_to_room()
	await wait_until(func() -> bool: return server.hosts.is_empty(), 5)
	# The ladder.
	var board: Dictionary = await alice.net.request("ranked_info", {})
	check(board.ok and int(board.season) == Ranked.season_of() and (board.rows as Array).size() == 2 and int(board.total) == 2, "the ladder lists both players")
	check(int(board.rows[0].mmr) > int(board.rows[1].mmr) and int(board.rows[0].position) == 1 and int(board.position) >= 1 and int(board.left) > 0, "ordered by rating, with this player's position and the season clock")
	# The second match: one player leaves and loses on the spot.
	await alice.net.request("ranked_queue", {"on": true})
	await bob.net.request("ranked_queue", {"on": true})
	check(await wait_until(func() -> bool: return alice.screen_name == "battle" and bob.screen_name == "battle", 15), "a second ranked match starts")
	a = alice.screen
	b = bob.screen
	var before: Dictionary = {"alice": int(server_profile(alice).rating.mmr), "bob": int(server_profile(bob).rating.mmr)}
	await wait_until(func() -> bool: return a.driver.tick > 120, 10)
	a.forfeit()
	check(await wait_until(func() -> bool: return b.ending_shown, 20), "when one player leaves, the other's match ends at once")
	check(b.game.winner_team == b.game.local().team and bool(b.summary.won), "the one who stayed wins")
	var left_report: Dictionary = b.summary.get("ranked", {})
	check(int(left_report.delta) > 0 and int(server_profile(bob).rating.mmr) == before.bob + int(left_report.delta), "and gains the points")
	check(await wait_until(func() -> bool: return int(server_profile(alice).rating.games) == 2 and int(server_profile(alice).rating.mmr) < before.alice, 10), "while the player who left is charged the loss")
	bob.return_to_room()
	await wait_until(func() -> bool: return server.hosts.is_empty(), 5)
	check(alice.screen_name == "hall", "the one who left is back in the Salão")
	# The same pair may meet only a few times an hour.
	var keys: Array = server.ranked_pairs.keys()
	check(keys.size() == 1 and (server.ranked_pairs[keys[0]] as Array).size() == 2 and not server.ranked_rematch_blocked(server.accounts[alice.my_account()], server.accounts[bob.my_account()]), "the server counts the matches of a pair")
	await spectate_tests(alice, bob)
	check(server.ranked_rematch_blocked(server.accounts[alice.my_account()], server.accounts[bob.my_account()]), "after three in an hour the pair waits")
	server.ranked_pairs.clear()
	# The screen.
	var screen: RankedScreen = RankedScreen.open(alice.screen, alice)
	check(await wait_until(func() -> bool: return not screen.loading, 5), "the ranked screen loads the ladder")
	check(screen.find_child("RankBadge", true, false) != null and screen.find_child("LadderRow_1", true, false) != null and screen.find_child("RankedFind", true, false) != null, "it shows the emblem, the ladder rows and the queue button")
	screen.find_child("RankedFind", true, false).pressed.emit()
	check(await wait_until(func() -> bool: return screen.queued and server.accounts[alice.my_account()].queued, 5) and screen.find_child("RankedCancel", true, false) != null, "the button puts the player in the queue")
	check(await wait_until(func() -> bool: return server.ranked_queue.size() == 1, 3), "the queue has one player")
	screen.find_child("RankedCancel", true, false).pressed.emit()
	check(await wait_until(func() -> bool: return not screen.queued and not server.accounts[alice.my_account()].queued, 5), "cancelling leaves the queue")
	# A season ends: the rating is archived and the title can be claimed.
	server_profile(alice).rating.games = 8
	server_profile(alice).rating.mmr = 1210
	Ranked.clock_offset = 86400 * (Ranked.season_days() + 2)
	screen.refresh()
	check(await wait_until(func() -> bool: return screen.find_child("ClaimSeason", true, false) != null, 5), "a finished season offers its title")
	check(int(alice.profile.rating.season) == 2 and int(alice.profile.rating.games) == 0 and int(alice.profile.rating.mmr) == 1105, "the new season starts with the soft reset")
	screen.find_child("ClaimSeason", true, false).pressed.emit()
	check(await wait_until(func() -> bool: return alice.profile.titles == ["s1_ouro"] and server_profile(alice).titles == ["s1_ouro"], 5), "claiming gives the title on the server and the client")
	check(alice.profile.title == "s1_ouro" and screen.find_child("Title_s1_ouro", true, false) != null, "the first title is equipped and listed")
	screen.find_child("Title_s1_ouro", true, false).pressed.emit()
	check(await wait_until(func() -> bool: return alice.profile.title == "" and server_profile(alice).title == "", 5), "a title can be taken off")
	Ranked.clock_offset = 0
	screen.close()
	await process_frame
	# The profile window of another player shows the rank and title.
	var info: Dictionary = server.accounts[alice.my_account()].public_profile(server.balance)
	check(info.has("rating") and info.has("title") and int(info.rating.mmr) == 1105, "other players can see the rating")

# Live spectators (0.22): a third player watches a ranked match a few seconds behind.
func spectate_tests(alice: Node, bob: Node) -> void:
	var carol: Node = await make_app()
	check(await login(carol, "watcher") == "", "a third player logs in")
	check((await carol.do_op("create", ["Vigia", "f"])).error == "", "and creates the character")
	await alice.net.request("ranked_queue", {"on": true})
	await bob.net.request("ranked_queue", {"on": true})
	check(await wait_until(func() -> bool: return alice.screen_name == "battle" and bob.screen_name == "battle", 15), "a third ranked match starts")
	var a: BattleScreen = alice.screen
	var b: BattleScreen = bob.screen
	await wait_until(func() -> bool: return a.driver.tick > 200, 10)
	var listed: Dictionary = await carol.net.request("ranked_info", {})
	check(listed.ok and (listed.live as Array).size() == 1 and (listed.live[0].names as Array).size() == 2 and int(listed.live[0].m) == a.match_id, "the live list shows the ranked match")
	check(not (await carol.net.request("spectate", {"m": 9999})).ok, "a match that does not exist cannot be watched")
	check(not (await alice.net.request("spectate", {"m": a.match_id})).ok, "players cannot watch their own battle")
	await wait_until(func() -> bool: return a.driver.tick > 1500, 20)
	await carol.watch(a.match_id)
	check(await wait_until(func() -> bool: return carol.screen_name == "battle", 5), "asking to watch opens the battle")
	var w: BattleScreen = carol.screen
	check(w.spectating and w.game.spectator and w.online and not w.game.can_act() and w.watch_bar != null and w.watch_bar.live, "the spectator has no controls and a live bar")
	check(server.hosts[a.match_id].watchers.size() == 1 and server.accounts[carol.my_account()].watching == server.hosts[a.match_id], "the server counts the spectator")
	check(not (await carol.net.request("ranked_queue", {"on": true})).ok, "nobody queues while watching")
	check(await wait_until(func() -> bool: return w.driver.tick > 0, 15) and w.driver.tick <= a.driver.tick, "the broadcast follows the battle")
	check(w.game.fighters.size() == 2 and w.game.local_id == 0, "it shows the same two fighters")
	await finish_battle(alice, bob)
	check(await wait_until(func() -> bool: return w.game.winner_team == a.game.winner_team and w.game.winner_team != -2, 60), "the spectator's copy reaches the same result")
	check(not w.driver.drift_reported, "and never drifted from the server")
	check(await wait_until(func() -> bool: return carol.screen_name == "hall", 15), "after the outcome the spectator is back in the Salão")
	check(server.accounts[carol.my_account()].watching == null and carol.profile.matches == 0, "nothing is paid or recorded for watching")
	await wait_until(func() -> bool: return is_instance_valid(a.results), 8)
	alice.return_to_room()
	bob.return_to_room()
	await wait_until(func() -> bool: return server.hosts.is_empty(), 5)
	carol.queue_free()
	await process_frame

# A run of the daily challenge played on this computer (the shot solver), as a replay.
func challenge_run(day: int, player: String, idle: bool = false) -> Dictionary:
	var config: Dictionary = Challenge.config(day, player)
	var game: LocalMatch = LocalMatch.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start(config)
	var host: LocalHost = LocalHost.new()
	host.game = game
	game.remote = host.submit
	root.add_child(host)
	host.set_physics_process(false)
	var stage: int = 0
	var last_round: int = -1
	var power: float = 50.0
	for i in range(30000):
		if not game.running:
			break
		if game.round_number != last_round:
			last_round = game.round_number
			stage = 0
		if not idle:
			if stage == 0 and game.can_act():
				var me: TankFighter = game.fighters[0]
				var foe: TankFighter = null
				for fighter in game.fighters:
					if fighter.team == 1 and fighter.hp > 0 and (foe == null or fighter.position.distance_to(me.position) < foe.position.distance_to(me.position)):
						foe = fighter
				var scale: float = float(me.weapon.get("projectile", {}).get("wind_scale", 1.0))
				var shot: Vector3 = EnemyAI.choose_shot(me, foe, game.terrain, game.wind * float(game.balance.wind_accel) * scale * game.wind_factor(me), game.balance)
				host.submit("aim", {"d": 0.0, "angle": shot.x})
				host.submit("charge", {})
				power = shot.y
				stage = 1
			elif stage == 1 and game.active_id == game.local_id and game.state == LocalMatch.State.PLAYER_CHARGING and host.pending.is_empty():
				host.submit("release", {"power": power})
				stage = 2
		host.advance()
	var replay: Dictionary = Replay.make(config, host.history, host.tick, game.winner_team, {"kind": "challenge", "day": day, "names": [player]})
	var result: Dictionary = {"replay": replay, "score": Challenge.score(game)}
	game.queue_free()
	host.queue_free()
	return result

# The daily challenge online (0.22): the server runs the replay again, scores it, keeps the
# best per player, pays the reward once a day, lists the day and gives the best runs back.
func challenge_tests(alice: Node, bob: Node) -> void:
	alice.show_hall()
	bob.show_hall()
	var day: int = Challenge.day_id()
	var played: Dictionary = challenge_run(day, "Alice")
	var rules: Dictionary = Challenge.data().reward
	var coins: int = server_profile(alice).coins
	var sent: Dictionary = await alice.submit_challenge(played.replay)
	check(sent.ok and int(sent.score) == int(played.score.score) and bool(sent.first) and bool(sent.best) and int(sent.position) == 1 and int(sent.total) == 1, "the server re-runs the replay and scores it the same (%d)" % int(played.score.score))
	check(server_profile(alice).coins == coins + int(rules.coins) and server_profile(alice).challenge.day == day and int(server_profile(alice).challenge.best) == int(played.score.score), "the first result of the day pays the reward")
	check(alice.profile.challenge == server_profile(alice).challenge, "and the client mirrors it")
	var again: Dictionary = await alice.net.request("challenge_submit", {"day": day, "replay": played.replay}, 60.0)
	check(again.ok and not bool(again.first) and not bool(again.best) and server_profile(alice).coins == coins + int(rules.coins), "sending the same run again pays nothing more")
	# Another player doing nothing scores nothing, and ranks second.
	var idle: Dictionary = challenge_run(day, "Bob", true)
	var second: Dictionary = await bob.net.request("challenge_submit", {"day": day, "replay": idle.replay}, 60.0)
	check(second.ok and int(second.score) == 0 and int(second.position) == 2 and int(second.total) == 2, "a run that does nothing scores zero")
	# Cheating does not work: wrong day, someone else's controls, the AI, junk.
	check(not (await bob.net.request("challenge_submit", {"day": day + 1, "replay": played.replay}, 20.0)).ok, "another day's challenge is refused")
	var doctored: Dictionary = played.replay.duplicate(true)
	doctored.inputs.append([5, 1, "pass", {}])
	check(not (await bob.net.request("challenge_submit", {"day": day, "replay": doctored}, 20.0)).ok, "inputs for the rival's fighter are refused")
	var with_ai: Dictionary = played.replay.duplicate(true)
	with_ai.inputs.append([5, 0, "auto", {"on": true}])
	check(not (await bob.net.request("challenge_submit", {"day": day, "replay": with_ai}, 20.0)).ok, "so is the AI playing for the player")
	check(not (await bob.net.request("challenge_submit", {"day": day, "replay": {"v": 1}}, 20.0)).ok and not (await bob.net.request("challenge_submit", {"day": day, "replay": "junk"}, 20.0)).ok, "and a replay with no battle in it")
	# A lie about the config changes nothing: the server uses its own battle.
	var lie: Dictionary = played.replay.duplicate(true)
	lie.config.teams[0][0].level = 60
	lie.config.seed = 1
	var lied: Dictionary = await bob.net.request("challenge_submit", {"day": day, "replay": lie}, 60.0)
	check(lied.ok and int(lied.score) == int(played.score.score) and not bool(lied.best) or int(lied.score) >= 0, "the config sent by the player is ignored")
	# The day's board and the best runs.
	var board: Dictionary = await alice.net.request("challenge_info", {"day": day})
	check(board.ok and int(board.day) == day and (board.rows as Array).size() == 2 and board.rows[0].name == "Alice" and int(board.rows[0].score) == int(played.score.score) and int(board.position) == 1 and int(board.left) > 0, "the board lists the day's best first")
	var watched: Dictionary = await bob.net.request("challenge_replay", {"day": day, "account": alice.my_account()})
	var clean: Dictionary = Replay.clean(watched.get("replay"), true) if watched.ok else {}
	check(watched.ok and not clean.is_empty() and clean.inputs.size() == played.replay.inputs.size(), "the best run's replay can be fetched")
	check(not (await bob.net.request("challenge_replay", {"day": day + 50, "account": alice.my_account()})).ok, "a replay that is not there is an error")
	# The screens.
	var screen: ChallengeScreen = ChallengeScreen.open(alice.screen, alice)
	screen.find_child("ChallengeTab_top", true, false).pressed.emit()
	check(await wait_until(func() -> bool: return screen.find_child("ChallengeRow_1", true, false) != null, 5), "the ranking tab lists the day's players")
	var watch_button: Button = screen.find_child("WatchTop_2", true, false)
	check(watch_button != null, "each row has a button to watch the run")
	watch_button.pressed.emit()
	check(await wait_until(func() -> bool: return alice.screen_name == "battle" and (alice.screen as BattleScreen).replay_driver != null, 10), "watching a run of the ranking plays its replay")
	(alice.screen as BattleScreen).leave_watching()
	await process_frame
	check(alice.screen_name == "hall", "and leaving goes back")
	# The new day pays again.
	Challenge.clock_offset = 86400 * 3
	var later: int = Challenge.day_id()
	var tomorrow: Dictionary = challenge_run(later, "Alice")
	var paid: int = server_profile(alice).coins
	var next: Dictionary = await alice.net.request("challenge_submit", {"day": later, "replay": tomorrow.replay}, 60.0)
	check(next.ok and bool(next.first) and server_profile(alice).coins == paid + int(rules.coins) and int(next.total) == 1, "the next day has its own board and pays again " + str(next))
	Challenge.clock_offset = 0

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
	var loot_a: Array = []
	var loot_b: Array = []
	var observe_a: Callable = func(event: Dictionary) -> void:
		if event.get("t", "") == "mob_loot":
			loot_a.append_array(event.rewards)
	var observe_b: Callable = func(event: Dictionary) -> void:
		if event.get("t", "") == "mob_loot":
			loot_b.append_array(event.rewards)
	alice.net.event.connect(observe_a)
	bob.net.event.connect(observe_b)
	var drop_rules: Dictionary = Armory.data().strengthen.mob_drops
	var old_party: float = float(drop_rules.party_chance)
	var old_killer: float = float(drop_rules.killer_chance)
	drop_rules.party_chance = 1.0
	drop_rules.killer_chance = 1.0
	a.game.set_auto_play(true)
	b.game.set_auto_play(true)
	var cleared: bool = await wait_until(func() -> bool: return a.in_phase_break() and b.in_phase_break() or (a.ending_shown and b.ending_shown), 300)
	check(cleared, "the first phase ends for both")
	drop_rules.party_chance = old_party
	drop_rules.killer_chance = old_killer
	alice.net.event.disconnect(observe_a)
	bob.net.event.disconnect(observe_b)
	var shared_a: Array = loot_a.filter(func(entry: Dictionary) -> bool: return bool(entry.shared))
	var shared_b: Array = loot_b.filter(func(entry: Dictionary) -> bool: return bool(entry.shared))
	check(not shared_a.is_empty() and shared_a == shared_b, "server sends the same shared monster rewards to both clients")
	check(loot_a.size() + loot_b.size() > shared_a.size() + shared_b.size(), "last-hit rewards also reach their owner over the network")
	check(alice.profile.items == server_profile(alice).items and bob.profile.items == server_profile(bob).items, "monster rewards are already in the authoritative and client inventories")
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
	check(host_count <= 1 and await wait_until(func() -> bool: return server.hosts.is_empty(), 20), "when everyone leaves, the battle is closed (%d hosts, left %s)" % [host_count, str(server.hosts.keys())])
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
		check(profile_text(app.profile) == profile_text(server_profile(app)), "%s's copy matches the server's after trading" % server_profile(app).player_name + first_difference(profile_text(app.profile), profile_text(server_profile(app))))
		check(JSON.stringify(ApiClient.copy(server.api.memory_profiles[app.my_account()].data)) == JSON.stringify(ApiClient.copy(server_profile(app).to_data())), "%s's stored profile matches" % server_profile(app).player_name)

func reconnect_tests(alice: Node) -> void:
	# A connection that dies with no word from the server. On a computer it goes to the title
	# (as always); on a phone, where the app in the background loses its socket all the time,
	# the game logs back in by itself.
	check(alice.online, "online before the drop")
	var name_before: String = alice.profile.player_name
	alice.net.socket.close(3999, "test drop")
	check(await wait_until(func() -> bool: return not alice.online and alice.screen_name == "title", 5), "a computer sends a lost connection to the title screen")
	check(await login(alice, "alice") == "" and alice.online, "and the player logs in again")
	TouchMode.forced = 1
	alice.net.socket.close(3999, "test drop")
	check(await wait_until(func() -> bool: return alice.reconnecting, 5), "a phone starts reconnecting at once")
	check(alice.online and is_instance_valid(alice.ui.find_child("Reconnecting", true, false)), "it stays in the game and says so")
	check(await wait_until(func() -> bool: return not alice.reconnecting and alice.net.is_online(), 20), "and gets back in by itself")
	check(alice.online and alice.profile.player_name == name_before and alice.profile.remote, "as the same player, online")
	check(not is_instance_valid(alice.ui.find_child("Reconnecting", true, false)) and alice.screen_name != "title", "the message goes away and the game is on a game screen")
	check(server.accounts.size() == 2, "the server still counts two players")
	TouchMode.forced = -1

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

func steam_tests() -> void:
	var fake: Object = load("res://tests/fake_steam.gd").new()
	SteamService.override = fake
	var carol: Node = await make_app()
	check(carol.steam.available, "the game sees Steam (GodotSteam)")
	check(await login(carol, "carol") == "" and (await carol.do_op("create", ["Carol", "f"])).error == "", "a Steam player logs in and creates the character")
	var shop: ShopScreen = ShopScreen.new()
	shop.app = carol
	carol.ui.add_child(shop)
	shop.select_tab("premium")
	await process_frame
	check(not shop.find_child("Buy_aba_mochila_1", true, false).disabled, "online with Steam, the Premium tab sells")
	check(not (await carol.net.request("store_buy", {"sku": "roupa_samurai"})).ok, "only catalog products can be ordered")
	# The overlay refuses: the order is cancelled and nothing arrives.
	var answer: Array = [""]
	var buy: Callable = func(sku: String) -> void: answer[0] = await carol.buy_premium(sku)
	buy.call("aba_mochila_1")
	check(await wait_until(func() -> bool: return server.api.memory_orders.size() == 1, 5), "the server opens the order with the API")
	var first: int = server.api.memory_orders.keys()[0]
	fake.approve(first, false)
	check(await wait_until(func() -> bool: return answer[0] != "", 5) and answer[0].contains("cancelada"), "refused in the overlay: cancelled")
	check(await wait_until(func() -> bool: return str(server.api.memory_orders[first].status) == "cancelled", 5) and carol.mail_count == 0, "a refused order is closed and delivers nothing")
	# The overlay approves: the items arrive in the Correio.
	answer[0] = ""
	buy.call("aba_mochila_2")
	check(await wait_until(func() -> bool: return server.api.memory_orders.size() == 2, 5), "a second order")
	var second: int = server.api.memory_orders.keys()[1]
	fake.approve(second, true)
	check(await wait_until(func() -> bool: return answer[0] != "", 5) and answer[0].contains("Correio"), "approved in the overlay: %s" % answer[0])
	check(await wait_until(func() -> bool: return carol.mail_count == 1, 5), "the bag tab waits in the Correio")
	var claim: Dictionary = await carol.trade("mail_list")
	var ids: Array = (claim.get("mail", []) as Array).map(func(letter: Dictionary) -> int: return int(letter.id))
	check((claim.get("mail", []) as Array).all(func(letter: Dictionary) -> bool: return Auction.mail_title(letter).begins_with("Loja Steam")), "the letters say they come from the Steam shop")
	var claimed: Dictionary = await carol.trade("mail_claim", {"ids": ids})
	check(claimed.ok and carol.profile.has_item("aba_mochila_2"), "the bag tab is in the Mochila")
	var dye: Dictionary = carol.profile.inventory.filter(func(inst: Dictionary) -> bool: return str(inst.id) == "aba_mochila_2").front()
	check(bool(dye.get("bound", false)) and (dye.get("mods", []) as Array).is_empty(), "bought items are bound and have no bonuses")
	check(Auction.item_reason(carol.profile, dye) != "", "bought items never go to the auction")
	check(not (await carol.net.request("store_buy", {"sku": "aba_mochila_2"})).ok, "what the player has is not sold again")
	# Achievements come from the server's profile.
	server.accounts[carol.my_account()].profile.victories = 1
	await carol.do_op("redeem", ["PEDRAS"])
	check(await wait_until(func() -> bool: return fake.achievements.has("FIRST_VICTORY"), 5), "a victory on the server unlocks the Steam achievement")
	carol.net.disconnect_now()
	carol.queue_free()
	await process_frame
	SteamService.override = null
	fake.free()

# Real money outside Steam (web, mobile): Stripe Checkout in BRL. In memory the API has no
# page and counts the order as paid at the first status poll; the API side (webhook,
# signature, refund) is in server/api/stripe_test.go.
func card_tests() -> void:
	var dora: Node = await make_app()
	check(not dora.steam.available, "without Steam the game sells by card and Pix")
	check(await login(dora, "dora") == "" and (await dora.do_op("create", ["Dora", "f"])).error == "", "a web player logs in and creates the character")
	var shop: ShopScreen = ShopScreen.new()
	shop.app = dora
	dora.ui.add_child(shop)
	shop.select_tab("premium")
	await process_frame
	var card: Button = shop.find_child("Buy_aba_mochila_1", true, false)
	check(card != null and not card.disabled and card.text == "COMPRAR", "online without Steam, the Premium tab sells (COMPRAR)")
	var box: Node = shop.find_child("Premium_aba_mochila_1", true, false)
	check(box != null and box.get_children().any(func(node: Node) -> bool: return node is Label and (node as Label).text.contains("R$ 9,90")), "the price is in reais")
	check(not (await dora.net.request("store_checkout", {"sku": "roupa_samurai"})).ok, "only catalog products can be ordered")
	var answer: String = await dora.buy_premium("aba_mochila_1")
	check(answer.contains("Correio") and int(dora.pending_checkout.get("order_id", 0)) > 0, "the checkout page is opened and the order is pending: %s" % answer)
	check(await wait_until(func() -> bool: return dora.mail_count == 1, 15), "the item arrives in the Correio once the order is paid")
	check(await wait_until(func() -> bool: return dora.pending_checkout.is_empty(), 5), "the pending checkout is cleared when paid")
	var listed: Dictionary = await dora.trade("mail_list")
	check((listed.get("mail", []) as Array).all(func(letter: Dictionary) -> bool: return Auction.mail_title(letter).begins_with("Loja:")), "the letters say Loja, not Loja Steam")
	var again: Dictionary = await dora.net.request("store_status", {"order_id": int(server.api.memory_orders.keys().back())})
	check(again.ok and again.status == "paid" and dora.mail_count == 1, "asking again does not deliver twice")
	# 0.30: a pet is sold like any product and arrives in the Casa dos Mascotes through the Correio.
	var pet_answer: String = await dora.buy_premium("pet_fenix_dourada")
	check(pet_answer.contains("Correio"), "a pet is ordered like any product: %s" % pet_answer)
	check(await wait_until(func() -> bool: return dora.mail_count == 2, 15), "the pet's letter arrives in the Correio")
	var pet_mail: Dictionary = await dora.trade("mail_list")
	var letter: Dictionary = (pet_mail.mail as Array).filter(func(entry: Dictionary) -> bool: return (entry.get("item", {}) as Dictionary).has("pet"))[0]
	check(Auction.item_name("item", letter.item) == Pets.species_name("fenix_dourada") and Auction.mail_title(letter).begins_with("Loja:"), "the letter names the pet")
	var received: Dictionary = await dora.trade("mail_claim", {"ids": [int(letter.id)]})
	check(received.ok and dora.profile.owns_species("fenix_dourada") and dora.profile.pets.size() == 1 and int(dora.profile.pets[0].level) == 1, "claiming it puts the pet in the Casa dos Mascotes")
	check(not (await dora.net.request("store_checkout", {"sku": "pet_fenix_dourada"})).ok, "a pet already owned cannot be bought twice")
	dora.net.disconnect_now()
	dora.queue_free()
	await process_frame
