class_name CouponDialog
extends RefCounted

# "Resgatar cupom": a code field that grants items (TESTARTUDO unlocks every weapon,
# quality, super weapon and cosmetic for testing). Codes live in shared/balance/items.json.

static func open(parent: Node, app: Node, on_done: Callable = Callable()) -> Control:
	var root: Control = UiKit.modal(parent, Lang.t("RESGATAR CUPOM"), "", Vector2(560, 320))
	var rect: Rect2 = root.get_meta("rect")
	UiKit.label(root, Lang.t("Digite o código do cupom:"), Rect2(rect.position.x + 40, rect.position.y + 60, 480, 30), 17, UiKit.TEXT_DARK)
	var field: LineEdit = LineEdit.new()
	field.name = "CouponField"
	field.position = rect.position + Vector2(40, 94)
	field.size = Vector2(480, 42)
	field.max_length = 24
	field.placeholder_text = Lang.t("Ex.: TESTARTUDO")
	field.add_theme_font_override("font", UiKit.font())
	field.add_theme_font_size_override("font_size", UiKit.fs(22))
	root.add_child(field)
	var hint: String = Lang.t("Para testes: TESTARTUDO libera todas as armas e cosméticos; AURAS mostra as quatro auras.") if app.test_coupons() else ""
	var result: Label = UiKit.label(root, hint, Rect2(rect.position.x + 40, rect.position.y + 142, 480, 104), 14, Color("6a4a2a"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	result.name = "CouponResult"
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var redeem: Callable = func() -> void:
		var outcome: Dictionary = await app.do_op("redeem", [field.text])
		var ok: bool = outcome.error == ""
		result.text = Lang.t("Cupom resgatado! ") + outcome.message if ok else outcome.error
		result.add_theme_color_override("font_color", Color("2f7a1f") if ok else Color("b8321c"))
		app.audio.play("ui_confirm" if ok else "ui_error")
		if ok and on_done.is_valid():
			on_done.call()
	field.text_submitted.connect(func(_text: String) -> void: redeem.call())
	UiKit.button(root, Lang.t("RESGATAR"), Rect2(rect.position.x + 110, rect.end.y - 62, 160, 44), redeem, "button_green")
	UiKit.button(root, Lang.t("FECHAR"), Rect2(rect.end.x - 270, rect.end.y - 62, 160, 44), root.queue_free)
	field.grab_focus.call_deferred()
	return root
