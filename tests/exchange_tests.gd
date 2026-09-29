extends SceneTree
var checks: int = 0
var failures: int = 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
	else:
		print("PASS: " + text)
func _initialize() -> void:
	var p: PlayerProfile = PlayerProfile.new()
	p.coins = 1000
	p.items = {"brasa": 100, "strength_stone_12": 10}
	check(CurrencyExchange.assets().size() == 19, "seven currencies and twelve stones")
	check(CurrencyExchange.reason(p, "brasa", "solar", 10, 1, 2) == "", "funded order accepted")
	check(CurrencyExchange.reason(p, "strength_stone_12", "solar", 1, 20, 2) == "", "stones are exchange assets")
	check(CurrencyExchange.reason(p, "brasa", "brasa", 1, 1, 1) != "", "same asset rejected")
	check(CurrencyExchange.reason(p, "coins", "brasa", 1, 1, 1) != "", "gold is fee only")
	check(CurrencyExchange.reason(p, "brasa", "solar", -1, 1, 1) != "", "negative amounts rejected")
	check(CurrencyExchange.reason(p, "brasa", "solar", 100, 1, 2) != "", "escrow cannot exceed inventory")
	check(CurrencyExchange.reason(p, "brasa", "solar", 1000000, 1, 1000000) != "", "total limit enforced")
	p.coins = 0
	check(CurrencyExchange.reason(p, "brasa", "solar", 1, 1, 1) != "", "gold fee required")
	var before: int = p.currency_count("strength_stone_12")
	var undo: Dictionary = Auction.grant_mail(p, {"kind": "exchange_fill", "currencies": {"strength_stone_12": 3, "brasa": 9}})
	check(p.currency_count("strength_stone_12") == before + 3, "mail grants stones")
	check(p.currency_count("brasa") == 109, "mail grants currencies")
	Auction.undo_mail(p, undo)
	check(p.currency_count("strength_stone_12") == before and p.currency_count("brasa") == 100, "failed mail transaction rolls back both assets")
	check(Auction.mail_contents({"currencies": {"strength_stone_12": 3}}).contains("3"), "mail describes stone rewards")
	check(CityScreen.CITY_LAYOUT.any(func(b: Dictionary) -> bool: return b.id == "exchange"), "city opens exchange")
	check(not CityScreen.CITY_LAYOUT.any(func(b: Dictionary) -> bool: return b.id == "dating"), "dating placeholder removed")
	print("EXCHANGE RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
