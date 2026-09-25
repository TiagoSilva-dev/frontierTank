extends SceneTree

# Leilão (0.12): what can be sold, fees and commission, the search fields, taking an item
# into custody and putting it back, the mail entering a profile (and leaving it again),
# Super Verdadeiras binding on equip, and the in-memory auction of the game server's
# ApiClient (the same answers as the Go API: custody, sale, mail, cancel, expiry, op ids).

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func run_tests() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://test_auction_profile.json"
	rules_tests()
	custody_tests()
	mail_tests()
	await memory_api_tests()
	print("AUCTION RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func dropped(profile: PlayerProfile, id: String, quality: String = "verdadeira", ilvl: int = 12) -> Dictionary:
	var inst: Dictionary = profile.add_instance(id, quality, 3, ilvl)
	inst.mods = Crafting.roll_mods(inst, profile.rng)
	return inst

func rules_tests() -> void:
	check(Auction.hours_options() == [12, 24, 48], "listings last 12, 24 or 48 hours")
	check(Auction.fee_for(12) > 0 and Auction.fee_for(48) > Auction.fee_for(12) and Auction.fee_for(7) == -1, "the gold fee grows with the duration")
	check(Auction.commission(20) == 1 and Auction.commission(19) == 0 and Auction.commission(100) == 5, "5% commission, rounded down")
	var profile: PlayerProfile = PlayerProfile.new()
	var starter: Dictionary = profile.equipped_instance("arma")
	check(bool(starter.get("bound", false)), "the starter weapon is bound")
	var drop: Dictionary = dropped(profile, "trovao")
	check(Auction.item_reason(profile, drop) == "", "a dropped weapon can be sold")
	check(Auction.item_reason(profile, starter) != "", "the equipped (and bound) starter weapon cannot")
	profile.equip(int(drop.uid))
	check(Auction.item_reason(profile, drop) != "", "an equipped item cannot be listed")
	profile.equip(int(starter.uid))
	check(Auction.item_reason(profile, drop) == "" and not drop.has("bound"), "unequipping a normal weapon keeps it tradeable")
	var shop: Dictionary = profile.add_instance("fogo_intenso", "excelente")
	shop.bound = true
	check(Auction.item_reason(profile, shop) != "", "shop items are bound")
	var legacy: Dictionary = profile.add_instance("vento_de_deus")
	check(Auction.item_reason(profile, legacy) != "", "items that never dropped (no item level) are not sold")
	var hair: Dictionary = profile.add_instance("cabelo_azul")
	hair.ilvl = 5
	check(Auction.item_reason(profile, hair) != "", "only gear with bonuses is traded")
	var hat: Dictionary = dropped(profile, "chapeu_viking", "excelente", 7)
	check(Auction.item_reason(profile, hat) == "", "dropped hats are traded too")
	# Super Verdadeira: binds when equipped (roadmap 3.3 proposal).
	var super_weapon: Dictionary = profile.add_instance("lanca_antiga", "super", 0, 14)
	check(Auction.item_reason(profile, super_weapon) == "", "a Super Verdadeira nobody equipped can be sold")
	profile.equip(int(super_weapon.uid))
	profile.equip(int(starter.uid))
	check(bool(super_weapon.get("bound", false)) and Auction.item_reason(profile, super_weapon) != "", "equipping a Super Verdadeira binds it")
	var reloaded: PlayerProfile = PlayerProfile.new()
	var data: Dictionary = profile.to_data()
	var old_super: Dictionary = {"uid": 900, "id": "cabeca_de_boi", "quality": "super", "level": 0, "compose": {}, "mods": [], "ilvl": 9}
	data.inventory.append(old_super)
	data.equipped.arma = 900
	reloaded.load_data(JSON.parse_string(JSON.stringify(data)))
	check(bool(reloaded.find_instance(900).get("bound", false)), "a Super Verdadeira already equipped in an old save is bound on load")
	# Maps.
	var map: Dictionary = profile.add_map(InstanceRun.make_map("templo_sol", 8, profile.rng, 0.0, "excelente"))
	check(Auction.map_reason(map) == "", "dropped maps can be sold")
	map.bound = true
	check(Auction.map_reason(map) != "", "coupon maps are bound")
	map.erase("bound")
	# The whole listing.
	profile.coins = 1000
	check(Auction.listing_reason(profile, "item", int(drop.uid), 3, 0, 24) == "", "a priced listing is valid")
	check(Auction.listing_reason(profile, "item", int(drop.uid), 0, 0, 24) != "", "a listing needs a price")
	check(Auction.listing_reason(profile, "item", int(drop.uid), Auction.max_price() + 1, 0, 24) != "", "prices have a ceiling")
	check(Auction.listing_reason(profile, "item", int(drop.uid), 3, 2, 36) != "", "only the offered durations")
	check(Auction.listing_reason(profile, "map", int(map.uid), 0, 7, 12) == "", "maps are priced the same way")
	check(Auction.listing_reason(profile, "item", 99999, 1, 0, 12) != "", "a missing item cannot be listed")
	profile.coins = Auction.fee_for(48) - 1
	check(Auction.listing_reason(profile, "item", int(drop.uid), 1, 0, 48) != "", "the fee must be paid in gold")
	# Search fields.
	var fields: Dictionary = Auction.fields("item", drop)
	check(fields.slot == "arma" and fields.item_id == "trovao" and fields.quality == "verdadeira" and int(fields.item_level) == 12 and int(fields.strengthen) == 3, "gear is searched by slot, item, quality, item level and strengthening")
	check((fields.mods as Array).size() == (drop.mods as Array).size() and (fields.mods as Array).all(func(id: Variant) -> bool: return id is String), "and by its bonuses")
	var map_fields: Dictionary = Auction.fields("map", map)
	check(map_fields.slot == "mapa" and map_fields.item_id == "templo_sol" and int(map_fields.item_level) == 8, "maps are searched by instance and level")
	var filter: Dictionary = Auction.clean_filter({"slot": "arma", "quality": "hack", "mod": "dano; DROP", "min_level": 5, "max_solar": 9999, "sort": "price", "page": -3})
	check(filter.slot == "arma" and not filter.has("quality") and not filter.has("mod") and int(filter.min_level) == 5 and int(filter.max_solar) == Auction.max_price() and filter.sort == "price" and int(filter.page) == 0, "search filters from the network are cleaned")
	check(Auction.clean_filter({"max_estrela": 0}).max_estrela == 0 and not Auction.clean_filter({}).has("max_solar"), "a price limit of 0 is kept, no limit is left out")
	check(Auction.price_text(3, 0) == "3 Solares" and Auction.price_text(1, 12) == "1 Solar + 12 Estrelas", "prices read short")

func custody_tests() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	profile.coins = 500
	var drop: Dictionary = dropped(profile, "canhao_arco_iris")
	var uid: int = int(drop.uid)
	var before: String = JSON.stringify(profile.to_data())
	var taken: Dictionary = Auction.take(profile, "item", uid, 24)
	check(profile.find_instance(uid).is_empty() and profile.coins == 500 - Auction.fee_for(24), "listing takes the item and the fee")
	Auction.put_back(profile, taken)
	check(JSON.stringify(profile.to_data()) == before, "a refused listing puts everything back")
	var map: Dictionary = profile.add_map(InstanceRun.make_map("picos_gelados", 4, profile.rng))
	taken = Auction.take(profile, "map", int(map.uid), 12)
	check(profile.find_map(int(map.uid)).is_empty(), "a listed map leaves the Mochila")
	Auction.put_back(profile, taken)
	check(not profile.find_map(int(map.uid)).is_empty(), "and comes back if refused")

func mail_tests() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	var item: Dictionary = {"uid": 77, "id": "trovao", "quality": "verdadeira", "level": 5, "ilvl": 13, "compose": {"ataque": 20, "hack": 99}, "mods": [{"id": "dano", "tier": 1, "value": 15}, {"id": "vida", "tier": 1, "value": 999}]}
	var coins: int = profile.coins
	var mail: Dictionary = JSON.parse_string(JSON.stringify({"id": 1, "kind": "purchase", "item_kind": "item", "item": item, "currencies": {}, "coins": 0}))
	var undo: Dictionary = Auction.grant_mail(profile, mail)
	var got: Dictionary = profile.find_instance(int(undo.uids[0]))
	check(not got.is_empty() and int(got.uid) != 77 and got.id == "trovao" and int(got.level) == 5 and int(got.ilvl) == 13, "a bought item arrives with a new uid, its level and item level")
	check(got.compose == {"ataque": 20} and (got.mods as Array).size() == 1, "and only valid composition and bonuses")
	var sale: Dictionary = {"id": 2, "kind": "sale", "currencies": {"solar": 19, "estrela": 4, "ouro_falso": 50}, "coins": 0}
	var second: Dictionary = Auction.grant_mail(profile, sale)
	check(profile.currency_count("solar") == 19 and profile.currency_count("estrela") == 4 and profile.currency_count("ouro_falso") == 0, "a sale pays known currencies only")
	var returned: Dictionary = {"id": 3, "kind": "returned", "item_kind": "map", "item": {"instance": "trono_mascaras", "level": 20, "quality": "verdadeira", "mods": [{"id": "nada", "value": 1}]}}
	var third: Dictionary = Auction.grant_mail(profile, returned)
	var back: Dictionary = profile.find_map(int(third.maps[0]))
	check(not back.is_empty() and int(back.level) == 16 and (back.mods as Array).is_empty(), "a returned map is cleaned too")
	for step: Dictionary in [third, second, undo]:
		Auction.undo_mail(profile, step)
	check(profile.find_instance(int(undo.uids[0])).is_empty() and profile.maps.is_empty() and profile.currency_count("solar") == 0 and profile.coins == coins, "a refused claim takes everything out again")
	check(PlayerProfile.clean_instance({"id": "nao_existe"}).is_empty() and PlayerProfile.clean_map({"instance": "nenhuma"}).is_empty(), "unknown items and instances are refused")
	check(Auction.mail_title({"kind": "sale", "detail": {"item_kind": "item", "item": item}}).contains("Verdadeiro Trovão"), "the mail says what was sold")

func memory_api_tests() -> void:
	var api: ApiClient = ApiClient.new()
	root.add_child(api)
	# Two accounts with stored profiles.
	check(not (await api.save_profile(1, "Sol", {"n": 1}, 0)).has("error") and not (await api.save_profile(2, "Lua", {"n": 1}, 0)).has("error"), "two profiles are stored")
	var seller: Dictionary = {"name": "Sol", "data": {"n": 2}, "version": 1}
	var listing: Dictionary = {"kind": "item", "item": {"id": "trovao", "quality": "verdadeira", "ilvl": 12}, "slot": "arma", "item_id": "trovao", "quality": "verdadeira", "item_level": 12, "strengthen": 3, "mods": ["dano"], "price_solar": 20, "price_estrela": 0, "fee_solar": 1, "fee_estrela": 0, "hours": 24}
	var created: Dictionary = await api.auction_create("op-1", 1, seller, listing, 1)
	check(int(created.get("version", 0)) == 2 and int(created.listing.id) == 1, "a listing is created with the seller's profile")
	check(int((await api.auction_create("op-1", 1, seller, listing, 1)).listing.id) == 1 and api.memory_listings.size() == 1, "a repeated op id lists nothing new")
	check((await api.auction_create("op-2", 1, {"name": "Sol", "data": {}, "version": 2}, listing, 1)).get("error") == "too_many_listings", "the listing limit holds")
	check((await api.auction_create("op-3", 1, seller, listing, 5)).get("error") == "version_conflict", "a stale profile lists nothing")
	check((await api.auction_search({"slot": "arma", "mod": "dano", "max_solar": 20})).listings.size() == 1, "search finds it")
	check((await api.auction_search({"max_solar": 19})).listings.is_empty() and (await api.auction_search({"slot": "mapa"})).listings.is_empty(), "search filters")
	var buyer: Dictionary = {"name": "Lua", "data": {"n": 2}, "version": 1}
	check((await api.auction_buy("op-b0", 1, 1, 20, 0, {"name": "Sol", "data": {}, "version": 2})).get("error") == "own_listing", "nobody buys their own listing")
	check((await api.auction_buy("op-b1", 2, 1, 10, 0, buyer)).get("error") == "price_changed", "the price must match")
	var bought: Dictionary = await api.auction_buy("op-b2", 2, 1, 20, 0, buyer)
	check(int(bought.get("version", 0)) == 2 and int(bought.seller_id) == 1, "a sale")
	check((await api.auction_buy("op-b3", 2, 1, 20, 0, {"name": "Lua", "data": {}, "version": 2})).get("error") == "listing_gone", "sold once")
	var buyer_mail: Array = (await api.mail_list(2)).mail
	var seller_mail: Array = (await api.mail_list(1)).mail
	check(buyer_mail.size() == 1 and buyer_mail[0].kind == "purchase" and buyer_mail[0].item.id == "trovao", "the item waits in the buyer's mail")
	check(seller_mail.size() == 1 and int(seller_mail[0].currencies.solar) == 19, "the seller gets the price minus the commission")
	var claim: Dictionary = await api.mail_claim("op-c1", 2, [int(buyer_mail[0].id)], {"name": "Lua", "data": {"n": 3}, "version": 2})
	check(int(claim.get("version", 0)) == 3 and (await api.mail_list(2)).mail.is_empty(), "mail is received with the profile")
	check((await api.mail_claim("op-c2", 2, [int(buyer_mail[0].id)], {"name": "Lua", "data": {}, "version": 3})).get("error") == "mail_gone", "once")
	check((await api.auction_history({"kind": "item", "item_id": "trovao", "quality": "verdadeira"})).sales.size() == 1, "the sale is in the price history")
	# Cancel and expiry.
	var second: Dictionary = await api.auction_create("op-4", 1, {"name": "Sol", "data": {}, "version": 2}, listing, 5)
	check((await api.auction_cancel("op-x", 2, int(second.listing.id))).get("error") == "not_yours", "only the seller cancels")
	check(not (await api.auction_cancel("op-5", 1, int(second.listing.id))).has("error"), "the seller cancels")
	var third: Dictionary = await api.auction_create("op-6", 1, {"name": "Sol", "data": {}, "version": 3}, listing, 5)
	api.memory_find(int(third.listing.id)).expires_at = ApiClient.unix_now() - 5
	check((await api.auction_search({})).listings.is_empty(), "expired listings leave the search")
	var mine: Dictionary = await api.auction_mine(1)
	check(mine.active.is_empty() and mine.closed.size() == 3, "the seller sees the sold, cancelled and expired listings")
	var kinds: Array = (await api.mail_list(1)).mail.map(func(mail: Dictionary) -> String: return "%s:%s" % [mail.kind, str(mail.detail.get("reason", ""))])
	check(kinds == ["sale:", "returned:cancelled", "returned:expired"], "cancelled and expired items come back by mail")
	api.queue_free()
