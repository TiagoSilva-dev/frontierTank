class_name CurrencyExchange
extends RefCounted

const MAX_AMOUNT: int = 1000000
const MAX_ORDERS: int = 10

static func assets() -> Array:
	return Crafting.currencies() + Armory.data().strengthen.stones

static func definition(id: String) -> Dictionary:
	var currency: Dictionary = Crafting.currency_def(id)
	return currency if not currency.is_empty() else Armory.stone_def(id)

static func valid_asset(id: String) -> bool:
	return not definition(id).is_empty()

static func title(id: String) -> String:
	return Lang.t(str(definition(id).get("name", id)))

static func fee(give: int, lots: int) -> int:
	return 5 + ceili(float(give * lots) / 100.0)

static func reason(profile: PlayerProfile, give: String, want: String, amount: int, wanted: int, lots: int) -> String:
	if not valid_asset(give) or not valid_asset(want) or give == want:
		return Lang.t("Escolha duas moedas ou pedras diferentes.")
	if amount < 1 or wanted < 1 or lots < 1 or amount > MAX_AMOUNT or wanted > MAX_AMOUNT or lots > MAX_AMOUNT or amount * lots > MAX_AMOUNT or wanted * lots > MAX_AMOUNT:
		return Lang.t("Use quantidades inteiras entre 1 e 1.000.000.")
	if profile.currency_count(give) < amount * lots:
		return Lang.t("Você não tem saldo suficiente para reservar esta oferta.")
	if profile.coins < fee(amount, lots):
		return Lang.t("Você não tem ouro suficiente para a taxa.")
	return ""
