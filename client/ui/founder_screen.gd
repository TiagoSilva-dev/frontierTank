class_name FounderScreen
extends Control

# GUSTFIRE FOUNDER PACK — Edição Paladino do Sol (docs/FOUNDER_PACK.md, item 19). The shop
# window of the limited pack: the Paladino on the left, the set in the middle, a looping
# preview of Julgamento do Sol on the right and the button to become a Founder. A Founder
# who opens it sees their set and the switches for the Founder effects instead.

const NAVY: Color = Color("0c1236")
const ROYAL: Color = Color("2a3fc0")
const GOLD: Color = Color("ffd25a")
const GOLD_DARK: Color = Color("7a4a12")
const LEVELS: Array[int] = [0, 6, 10, 12]
const CHECKS: Array[String] = [
	"Skin Paladino do Sol", "Skin de arma Solaris", "Efeito exclusivo de projétil", "Explosão exclusiva",  # i18n
	"POW Julgamento do Sol", "Aura do Primeiro Sol", "Asas da Aurora", "Pet Solis",  # i18n
	"Moldura Founder", "Badge Founder", "Título FUNDADOR", "Emote exclusivo",  # i18n
]

var app: Node
var time: float = 0.0
var weapon_level: int = 12
var weapon_art: TextureRect
var weapon_name: Label
var level_buttons: Array[Button] = []
var buy_button: Button
var status: Label
var rays: Control

static func open(app_ref: Node) -> FounderScreen:
	var screen: FounderScreen = FounderScreen.new()
	screen.app = app_ref
	screen.name = "FounderScreen"
	app_ref.ui.add_child(screen)
	app_ref.audio.play("founder_reveal", -2.0)
	return screen

func _ready() -> void:
	size = Vector2(1280, 720)
	var shade: ColorRect = ColorRect.new()
	shade.size = size
	shade.color = NAVY
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	rays = Control.new()
	rays.size = size
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.draw.connect(draw_backdrop)
	add_child(rays)
	var motes: CPUParticles2D = FxParticles.stream(self, Vector2(640, 740), {"amount": 60, "lifetime": 7.0, "speed": [12.0, 30.0], "direction": Vector2.UP, "spread": 30.0, "gravity": Vector2(0, -6), "size": [2.0, 3.0], "colors": ["fff0a8", "ffd25a", "f0a62c"], "box": Vector2(640, 4), "lifetime_randomness": 0.5})
	motes.z_index = 1
	build_header()
	build_character()
	build_set()
	build_preview()
	build_footer()
	UiKit.button(self, "X", Rect2(1226, 14, 40, 36), close, "button_red", 18)

func close() -> void:
	queue_free()

func _process(delta: float) -> void:
	time += delta
	rays.queue_redraw()

# ---------- backdrop: night gradient and slow sun rays behind the Paladino ----------

func draw_backdrop() -> void:
	for i in range(18):
		var u: float = i / 17.0
		rays.draw_rect(Rect2(0, i * 40.0, 1280, 41), Color(0.04, 0.06, 0.2).lerp(Color(0.16, 0.14, 0.42), u * u * 0.9), true)
	var center: Vector2 = Vector2(215, 330)
	for k in range(14):
		var angle: float = time * 0.05 + k * TAU / 14.0
		var width: float = 0.08 if k % 2 == 0 else 0.045
		var a: Vector2 = center + Vector2.from_angle(angle - width) * 1100.0
		var b: Vector2 = center + Vector2.from_angle(angle + width) * 1100.0
		rays.draw_colored_polygon(PackedVector2Array([center, a, b]), Color(1.0, 0.82, 0.35, 0.07 if k % 2 == 0 else 0.04))
	rays.draw_rect(Rect2(0, 640, 1280, 80), Color(0.03, 0.03, 0.1, 0.9))
	rays.draw_rect(Rect2(0, 640, 1280, 3), Color(GOLD.r, GOLD.g, GOLD.b, 0.7))

func gold_panel(rect: Rect2) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.04, 0.06, 0.2, 0.82), Color(GOLD.r, GOLD.g, GOLD.b, 0.85), 6))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel

func build_header() -> void:
	var crown: TextureRect = FounderUi.badge(self, Rect2(560, 8, 64, 64))
	crown.position = Vector2(608, 6)
	UiKit.label(self, tr("GUSTFIRE"), Rect2(0, 64, 1280, 40), 28, Color("ffb02e"), Color("3a1c08"), HORIZONTAL_ALIGNMENT_CENTER)
	var title: Label = UiKit.label(self, tr("FOUNDER PACK"), Rect2(0, 92, 1280, 58), 50, GOLD, Color("3a2208"), HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "FounderTitle"
	UiKit.panel(self, Rect2(450, 152, 380, 34), "plate")
	UiKit.label(self, tr("EDIÇÃO PALADINO DO SOL"), Rect2(450, 152, 380, 34), 20, Color("fff0c0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)

# ---------- left: the Paladino (the halo turns behind them) ----------

func build_character() -> void:
	var look: Dictionary = {"skin": FounderPack.SKIN, "hair": "", "hat": "", "glasses": "", "wings": FounderPack.WINGS, "weapon": FounderPack.WEAPON, "weapon_level": 0, "clothes_level": 0, "founder": {"seal": true, "aura": true, "pet": false, "foot": false, "lobby": false}}
	var stage: Control = AvatarView.create(self, look, Rect2(10, 150, 400, 480))
	stage.name = "FounderAvatar"
	UiKit.label(self, tr("PALADINO DO SOL"), Rect2(10, 598, 400, 34), 24, GOLD, Color("3a2208"), HORIZONTAL_ALIGNMENT_CENTER)

# ---------- center: the set and the list ----------

func build_set() -> void:
	gold_panel(Rect2(420, 196, 440, 436))
	UiKit.label(self, tr("O CONJUNTO"), Rect2(420, 202, 440, 30), 20, GOLD, Color("3a2208"), HORIZONTAL_ALIGNMENT_CENTER)
	var cards: Array = [
		[tr("Skin"), tr("Paladino do Sol"), null],
		[tr("Arma"), tr("Solaris"), null],
		[tr("Asas"), tr("Asas da Aurora"), null],
		[tr("Pet"), tr("Solis"), null],
		[tr("Aura"), tr("Primeiro Sol"), null],
	]
	for i in range(5):
		var rect: Rect2 = Rect2(430 + i * 84, 236, 80, 128)
		var card: Panel = UiKit.panel(self, rect, Color(0.08, 0.1, 0.3, 0.9), Color(GOLD.r, GOLD.g, GOLD.b, 0.6))
		card.name = "Card_%d" % i
		var art: TextureRect = UiKit.art(card, card_art(i), Rect2(6, 6, 68, 64))
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i == 1:
			weapon_art = art
		UiKit.label(card, cards[i][0], Rect2(0, 68, 80, 18), 12, Color("9ad0ff"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		var name_label: Label = UiKit.label(card, cards[i][1], Rect2(0, 84, 80, 40), 10, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.wrap(name_label, Vector2(78, 40))
		if i == 1:
			weapon_name = name_label
	# Solaris evolution: only the look changes with the level.
	UiKit.label(self, tr("Evolução visual da Solaris"), Rect2(430, 368, 420, 22), 14, Color("c4c8e4"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(LEVELS.size()):
		var level: int = LEVELS[i]
		var button: Button = UiKit.button(self, "+%d" % level, Rect2(500 + i * 74, 392, 66, 30), set_level.bind(level), "button_blue" if level == weapon_level else "button", 14)
		button.name = "Level_%d" % level
		level_buttons.append(button)
	var rows: int = 6
	for i in range(CHECKS.size()):
		var column: int = i / rows
		var row: int = i % rows
		var line: Label = UiKit.label(self, "✓  " + tr(CHECKS[i]), Rect2(440 + column * 208, 432 + row * 32, 208, 28), 15, Color("e8ebfa"), UiKit.INK)
		line.add_theme_color_override("font_color", Color("e8ebfa"))

func card_art(index: int) -> Texture2D:
	match index:
		0:
			return UiKit.head_crop(load(Armory.skin_path(FounderPack.SKIN)), 1.0)
		1:
			return load(Armory.weapon_icon(FounderPack.WEAPON, weapon_level))
		2:
			return load("res://assets/cosmetics/asas_aurora/front.png")
		3:
			return FounderPack.texture("pet/fly/frame_00.png")
		_:
			return FounderPack.texture("aura/aura_00.png")

func set_level(level: int) -> void:
	weapon_level = level
	weapon_art.texture = load(Armory.weapon_icon(FounderPack.WEAPON, level))
	weapon_name.text = tr("Solaris") + " +%d" % level
	for button: Button in level_buttons:
		var picked: bool = button.name == "Level_%d" % level
		button.add_theme_stylebox_override("normal", UiKit.frame("button_blue" if picked else "button"))
	app.audio.play("ui_click")

# ---------- right: Julgamento do Sol and the button ----------

func build_preview() -> void:
	gold_panel(Rect2(870, 196, 400, 436))
	var preview: FounderPreview = FounderPreview.new()
	preview.position = Vector2(880, 236)
	preview.scale = Vector2(0.95, 0.95)
	preview.name = "Preview"
	add_child(preview)
	UiKit.label(self, tr("POW EXCLUSIVO"), Rect2(870, 200, 400, 28), 16, Color("9ad0ff"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(self, tr("JULGAMENTO DO SOL"), Rect2(870, 458, 400, 36), 26, GOLD, Color("3a2208"), HORIZONTAL_ALIGNMENT_CENTER)
	var note: Label = UiKit.label(self, tr("Uma lança celestial cruza a tela e um feixe de luz desce sobre o alvo. Só aparência: o dano e a área são os de qualquer arma."), Rect2(886, 494, 368, 78), 14, Color("e8ebfa"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.wrap(note, Vector2(368, 78))

func build_footer() -> void:
	var entry: Dictionary = PremiumStore.product(FounderPack.SKU)
	var owned: bool = app.profile.is_founder()
	var note: Label = UiKit.label(self, tr("Itens exclusivos disponíveis somente durante o período Founder."), Rect2(0, 646, 1280, 26), 17, Color("fff0c0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	note.name = "FounderNote"
	status = UiKit.label(self, "", Rect2(0, 700, 1280, 20), 13, Color("ffb0a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	if owned:
		build_owner_switches()
		return
	var open_sale: bool = not entry.is_empty() and PremiumStore.on_sale(entry)
	var label: String = tr("TORNE-SE UM FUNDADOR") if open_sale else tr("PACOTE ENCERRADO")
	buy_button = UiKit.button(self, label, Rect2(440, 672, 400, 44), buy, "button_green" if open_sale else "button", 22)
	buy_button.name = "BuyButton"
	buy_button.disabled = not open_sale
	if not entry.is_empty():
		UiKit.label(self, PremiumStore.price_label(entry, app.steam.available), Rect2(850, 674, 200, 40), 22, GOLD, Color("3a2208"))

func build_owner_switches() -> void:
	UiKit.label(self, "✦ " + tr("VOCÊ É UM FUNDADOR") + " ✦", Rect2(20, 668, 340, 40), 22, GOLD, Color("3a2208"))
	var hint: Label = UiKit.label(self, tr("Em batalha, tecla E: Paladino Approved"), Rect2(20, 700, 360, 20), 13, Color("9ad0ff"), UiKit.INK)
	hint.name = "EmoteHint"
	for i in range(FounderPack.FX_KEYS.size()):
		var key: String = FounderPack.FX_KEYS[i]
		var box: CheckBox = UiKit.check_box(self, tr(str(FounderPack.FX_NAMES[key])), Rect2(380 + i * 220, 672, 216, 40), bool(app.profile.founder_fx.get(key, true)), 15)
		box.name = "Fx_" + key
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			box.add_theme_color_override(state, Color("fff0c0"))
		box.toggled.connect(func(on: bool) -> void: toggle_fx(key, on))

func toggle_fx(key: String, on: bool) -> void:
	app.audio.play("ui_click")
	await app.do_op("founder_fx", [key, on])

func buy() -> void:
	buy_button.disabled = true
	status.text = tr("Abrindo a compra...")
	status.text = await app.buy_premium(FounderPack.SKU)
	if is_instance_valid(buy_button):
		buy_button.disabled = false
