extends SceneTree

# 0.30: pets are sold for money in the shop (tab Mascotes), by rarity, and arrive by the
# Correio as pets of the Casa dos Mascotes. They are collectibles: the product carries
# nothing but the species, and a paid pet is never refused for lack of room.

const PRICES_BRL: Dictionary = {"comum": 1490, "raro": 2490, "epico": 3990, "lendario": 5990}

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func run_tests() -> void:
	var products: Array = PremiumStore.products().filter(func(entry: Dictionary) -> bool: return PremiumStore.is_pet_product(entry))
	check(products.size() == Pets.species_list().size(), "every species is on sale (%d)" % products.size())
	var ids: Dictionary = {}
	var steam: Dictionary = {}
	for entry: Dictionary in products:
		var species: Dictionary = Pets.species_def(str(PremiumStore.pet_species(entry)[0]))
		ids[str(species.id)] = true
		steam[int(entry.steam_item_id)] = true
		if not PremiumStore.valid(entry) or str(entry.section) != "mascotes" or (entry.get("items", []) as Array).size() != 0:
			check(false, "%s is a valid, pets-only product" % entry.sku)
		if int(entry.prices.BRL) != int(PRICES_BRL[str(species.rarity)]):
			check(false, "%s costs the price of its rarity" % entry.sku)
		for currency: String in ["USD", "EUR", "GBP", "BRL", "CAD", "AUD", "MXN", "PLN"]:
			if int(entry.prices.get(currency, 0)) <= 0:
				check(false, "%s has a price in %s" % [entry.sku, currency])
	check(ids.size() == products.size() and steam.size() == products.size(), "one product per species, each with its own Steam number")
	var all_ids: Dictionary = {}
	for entry: Dictionary in PremiumStore.products():
		all_ids[int(entry.steam_item_id)] = true
	check(all_ids.size() == PremiumStore.products().size(), "no Steam number repeats across the whole store")
	var legendary: Dictionary = PremiumStore.product("pet_fenix_dourada")
	var common: Dictionary = PremiumStore.product("pet_escaravelho_solar")
	check(int(legendary.prices.BRL) == 5990 and int(common.prices.BRL) == 1490, "a legendary costs R$ 59,90 and a common R$ 14,90")
	check(PremiumStore.kind_label(legendary) == Lang.t("Lendário").to_upper() and PremiumStore.kind_label(common) == Lang.t("Comum").to_upper(), "the card tag is the rarity")
	check(not PremiumStore.valid({"sku": "x", "steam_item_id": 9, "pets": ["nao_existe"], "prices": {"USD": 99}}), "an unknown species cannot be sold")

	# --- what the order delivers
	var mail: Array = PremiumStore.mail_items(legendary)
	check(mail.size() == 1 and str(mail[0].pet) == "fenix_dourada" and bool(mail[0].bound), "the order delivers one bound pet")
	check(Auction.item_name("item", mail[0]) == Pets.species_name("fenix_dourada"), "the Correio names the pet")
	check(Auction.item_icon("item", mail[0]) != null, "the Correio shows the pet's picture")
	check(Auction.item_color("item", mail[0]) == Pets.rarity_color("lendario"), "the Correio colours it by rarity")

	# --- the claim
	var profile: PlayerProfile = PlayerProfile.new()
	profile.created = true
	check(not PremiumStore.owns_all(profile, legendary), "a newcomer can buy the pet")
	var coins: int = profile.coins
	var undo: Dictionary = Auction.grant_mail(profile, {"kind": "store", "item_kind": "item", "item": mail[0], "detail": {"provider": "stripe"}})
	check(profile.owns_species("fenix_dourada") and PremiumStore.owns_all(profile, legendary), "the claimed pet is in the Casa dos Mascotes and the shop says so")
	var pet: Dictionary = profile.pets[0]
	check(int(pet.level) == 1 and not pet.has("stars") and profile.coins == coins, "it arrives at level 1 and costs nothing else")
	var roster: Dictionary = profile.entry({"base_hp": 1500, "hp_per_level": 40, "base_agility": 120, "agility_per_level": 8, "energy": 240})
	check(roster.look.get("pet", "") == "fenix_dourada", "the first pet is the companion in battle")
	Auction.undo_mail(profile, undo)
	check(profile.pets.is_empty() and profile.pet_active == -1, "undoing a claim takes the pet back")

	# --- paid pets are never refused
	var full: PlayerProfile = PlayerProfile.new()
	full.created = true
	for i in range(int(Pets.data().max_pets)):
		full.pets.append({"uid": 1000 + i, "species": "escaravelho_solar", "level": 1, "xp": 0, "stars": 0})
	full.next_uid = 5000
	check(not full.grant_pet("lobo_boreal"), "a free pet is refused when the Casa is full")
	var undo_full: Dictionary = Auction.grant_mail(full, {"kind": "store", "item_kind": "item", "item": {"pet": "lobo_boreal", "bound": true}})
	check(full.owns_species("lobo_boreal") and (undo_full.pets as Array).size() == 1, "a bought pet is delivered even then")

	# --- the same profile reads back
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(profile.to_data())
	check(copy.pets.size() == profile.pets.size(), "a save keeps the pets")
	print("PET SHOP RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
