class_name ConsentDialog
extends Control

# Consent before creating an account, and again when the Terms of Use or the Privacy
# Policy change (LGPD/GDPR). The player can read both texts from here; the button only
# works with the boxes ticked. `decided` says whether the player accepted.

signal decided(accepted: bool)

# "create": new account (terms + age); "update": the texts changed since the last time.
var mode: String = "create"
var accept_box: CheckBox
var age_box: CheckBox
var confirm: Button

static func open(parent: Node, which: String = "create") -> ConsentDialog:
	var dialog: ConsentDialog = ConsentDialog.new()
	dialog.mode = which
	parent.add_child(dialog)
	return dialog

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.66)
	var rect: Rect2 = Rect2(250, 120, 780, 480)
	UiKit.panel(self, rect, "wood")
	UiKit.title(self, tr("CRIAR CONTA") if mode == "create" else tr("TERMOS ATUALIZADOS"), Rect2(rect.position.x, rect.position.y + 8, rect.size.x, 34), 24)
	UiKit.panel(self, Rect2(rect.position + Vector2(14, 46), rect.size - Vector2(28, 60)), "paper")
	var summary: String = tr("Para jogar online, leia e aceite os Termos de Uso e a Política de Privacidade.\nResumo: guardamos o nome da conta, a senha protegida, o seu personagem e o que acontece no jogo (compras, partidas e chat), para o jogo funcionar e para a segurança. Não vendemos dados nem mostramos anúncios. Você pode baixar os seus dados ou excluir a conta quando quiser em Ajuda → Minha conta.")
	if mode == "update":
		summary = tr("Os Termos de Uso e a Política de Privacidade mudaram (versão %s). Para continuar jogando online, leia e aceite os textos novos.") % Legal.VERSION
	var text: Label = UiKit.label(self, summary, Rect2(rect.position.x + 34, rect.position.y + 60, rect.size.x - 68, 170), 16, UiKit.TEXT_DARK)
	UiKit.wrap(text, Vector2(rect.size.x - 68, 170))
	var terms: Button = UiKit.button(self, tr("Ler os Termos de Uso"), Rect2(rect.position.x + 110, rect.position.y + 236, 270, 38), func() -> void: LegalScreen.open(self, "terms"), "button_blue", 15)
	terms.name = "ReadTerms"
	var privacy: Button = UiKit.button(self, tr("Ler a Política de Privacidade"), Rect2(rect.position.x + 400, rect.position.y + 236, 270, 38), func() -> void: LegalScreen.open(self, "privacy"), "button_blue", 15)
	privacy.name = "ReadPrivacy"
	accept_box = UiKit.check_box(self, tr("Li e aceito os Termos de Uso e a Política de Privacidade."), Rect2(rect.position.x + 40, rect.position.y + 286, rect.size.x - 80, 34))
	accept_box.name = "Accept"
	accept_box.toggled.connect(func(_on: bool) -> void: refresh())
	if mode == "create":
		age_box = UiKit.check_box(self, tr("Tenho 13 anos ou mais; se tenho menos de 18, meu responsável concorda."), Rect2(rect.position.x + 40, rect.position.y + 326, rect.size.x - 80, 34))
		age_box.name = "Age"
		age_box.toggled.connect(func(_on: bool) -> void: refresh())
	confirm = UiKit.button(self, tr("ACEITAR E CRIAR") if mode == "create" else tr("ACEITAR"), Rect2(rect.position.x + 170, rect.end.y - 66, 220, 46), finish.bind(true), "button_green", 18)
	confirm.name = "Confirm"
	var cancel: Button = UiKit.button(self, tr("CANCELAR"), Rect2(rect.end.x - 350, rect.end.y - 66, 180, 46), finish.bind(false))
	cancel.name = "Cancel"
	refresh()

func refresh() -> void:
	confirm.disabled = not accept_box.button_pressed or (age_box != null and not age_box.button_pressed)

func finish(accepted: bool) -> void:
	if accepted and confirm.disabled:
		return
	decided.emit(accepted)
	queue_free()

func _gui_input(_event: InputEvent) -> void:
	accept_event()
