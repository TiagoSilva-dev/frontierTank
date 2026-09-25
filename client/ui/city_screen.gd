class_name CityScreen
extends Control

# Tela inicial: city hub with clickable buildings. Uses the PixelLab city art when
# assets/city/city_bg.png exists, otherwise the older Ilha Celeste hub.

const CITY_ART: String = "res://assets/city/city_bg.png"
# Hotspots over the old hub painting (buildings are part of the background).
const BUILDINGS: Array[Dictionary] = [
	{"id": "hall", "name": "Salão de Jogos", "rect": [245, 165, 260, 290], "label": [375, 250], "tip": "Salão de Jogos! Clique para entrar"},
	{"id": "instance", "name": "Instância", "rect": [790, 20, 250, 210], "label": [915, 70], "tip": "Instância: 4 masmorras de 3 fases e mapas de nível 1 a 16"},
	{"id": "smith", "name": "Ferreiro", "rect": [100, 300, 190, 180], "label": [196, 330], "tip": "Ferreiro: fortaleça suas armas"},
	{"id": "auction", "name": "Leilão", "rect": [1040, 60, 200, 330], "label": [1140, 175], "tip": "Leilão: compre e venda itens"},
	{"id": "mall", "name": "Centro Comercial", "rect": [900, 360, 230, 200], "label": [1010, 450], "tip": "Centro Comercial: roupas e armas"},
	{"id": "dating", "name": "Namoro", "rect": [0, 40, 165, 300], "label": [84, 130], "tip": "Namoro: encontre seu par"},
]
# Layout for the PixelLab city: a 640x360 painting shown at exactly 2x with the
# Salão on the central plaza and six paved lots around it, one 1x sprite per building.
# "rect" is the sprite, "hot" the clickable body, "label" the name's centre and "fx"
# the sprite pixels where the animated details (smoke, forge, portal...) sit.
const CITY_LAYOUT: Array[Dictionary] = [
	{"id": "hall", "name": "Salão de Jogos", "rect": [510, 238, 256, 256], "hot": [520, 241, 240, 237], "label": [640, 262], "tip": "Salão de Jogos! Clique para entrar", "fx": {"embers": [128, 104]}},
	{"id": "smith", "name": "Ferreiro", "rect": [235, 65, 192, 192], "hot": [243, 88, 175, 148], "label": [330, 92], "tip": "Ferreiro: fortaleça suas armas", "fx": {"smoke": [124, 22], "forge": [70, 96]}},
	{"id": "instance", "name": "Instância", "rect": [119, 226, 192, 192], "hot": [148, 230, 131, 180], "label": [213, 236], "tip": "Instância: 4 masmorras de 3 fases e mapas de nível 1 a 16", "fx": {"portal": [89, 110]}},
	{"id": "pet", "name": "Casa dos Mascotes", "rect": [243, 427, 192, 192], "hot": [257, 445, 165, 151], "label": [339, 450], "tip": "Casa dos Mascotes: em breve"},
	{"id": "auction", "name": "Leilão", "rect": [842, 74, 192, 192], "hot": [854, 80, 164, 164], "label": [936, 86], "tip": "Leilão: compre e venda itens", "fx": {"twinkle": true}},
	{"id": "dating", "name": "Namoro", "rect": [960, 291, 192, 192], "hot": [978, 298, 155, 168], "label": [1055, 302], "tip": "Namoro: encontre seu par", "fx": {"hearts": [78, 44]}},
	{"id": "mall", "name": "Centro Comercial", "rect": [546, 477, 192, 192], "hot": [554, 488, 173, 168], "label": [640, 494], "tip": "Centro Comercial: roupas e armas", "fx": {"twinkle": true}},
]

var app: Node
var buildings: Array[Dictionary] = BUILDINGS
var hovered: int = -1
var time: float = 0.0
var labels: Array[Label] = []
var tip_panel: Panel
var tip_label: Label
var glow: Control
var creation: Control
var fx: Control
var gulls: Array[Vector3] = []
var chosen_gender: String = "m"
var name_input: LineEdit

func _ready() -> void:
	size = Vector2(1280, 720)
	var custom: bool = ResourceLoader.exists(CITY_ART)
	buildings = CITY_LAYOUT if custom else BUILDINGS
	var background: String = CITY_ART if custom else "res://assets/pve/hub_celeste.png"
	var backdrop: TextureRect = UiKit.art(self, background, Rect2(0, 0, 1280, 720), false)
	if custom:
		# The sea moves: water pixels ripple and sparkle (client/shaders/city_sea.gdshader).
		var sea: ShaderMaterial = ShaderMaterial.new()
		sea.shader = load("res://client/shaders/city_sea.gdshader")
		sea.set_shader_parameter("texels", backdrop.texture.get_size())
		backdrop.material = sea
		backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow = Control.new()
	glow.size = size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.draw.connect(draw_glow)
	add_child(glow)
	for i in range(buildings.size()):
		var building: Dictionary = buildings[i]
		var r: Array = building.rect
		var sprite_path: String = "res://assets/city/buildings/%s.png" % building.id
		if ResourceLoader.exists(sprite_path):
			var sprite: TextureRect = UiKit.art(self, sprite_path, Rect2(r[0], r[1], r[2], r[3]))
			sprite.name = "Sprite_" + str(building.id)
		r = building.get("hot", r)
		var hotspot: Button = Button.new()
		hotspot.flat = true
		hotspot.focus_mode = Control.FOCUS_NONE
		hotspot.position = Vector2(r[0], r[1])
		hotspot.size = Vector2(r[2], r[3])
		for state: String in ["normal", "hover", "pressed", "focus"]:
			hotspot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		hotspot.mouse_entered.connect(func() -> void: set_hover(i))
		hotspot.mouse_exited.connect(leave_hover.bind(i))
		hotspot.pressed.connect(func() -> void: enter(building.id))
		hotspot.name = "Building_" + str(building.id)
		add_child(hotspot)
	fx = Control.new()
	fx.size = size
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.draw.connect(draw_fx)
	add_child(fx)
	for i in range(4):
		gulls.append(Vector3(randf_range(0, 1280), randf_range(430, 700), randf_range(22, 40)))
	for building: Dictionary in buildings:
		var pos: Array = building.label
		var tag: Label = UiKit.label(self, building.name, Rect2(pos[0] - 130, pos[1] - 20, 260, 40), 26 if building.id == "hall" else 22, Color("fff6dc"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
		tag.add_theme_constant_override("outline_size", 8)
		labels.append(tag)
	tip_panel = UiKit.panel(self, Rect2(0, 0, 340, 40), "banner")
	tip_label = UiKit.label(tip_panel, "", Rect2(0, 0, 340, 40), 17, Color("fff4a0"), Color("5a1004"), HORIZONTAL_ALIGNMENT_CENTER)
	tip_panel.hide()
	var speaker: SpeakerBar = SpeakerBar.new()
	speaker.app = app
	add_child(speaker)
	build_player_card()
	UiKit.panel(self, Rect2(36, 452, 130, 26), "plate")
	UiKit.label(self, "Canal", Rect2(36, 452, 130, 26), 15, Color("ffe6a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var channel: OptionButton = OptionButton.new()
	for i in range(3):
		channel.add_item("Canal %d" % (i + 1))
	channel.position = Vector2(40, 480)
	channel.size = Vector2(122, 32)
	channel.focus_mode = Control.FOCUS_NONE
	channel.add_theme_font_override("font", UiKit.font(true))
	channel.item_selected.connect(func(index: int) -> void: app.lobby.post("Sistema", "Você entrou no Canal %d." % (index + 1), "system"))
	add_child(channel)
	var chat: ChatBox = ChatBox.new()
	chat.app = app
	chat.position = Vector2(4, 520)
	add_child(chat)
	var bar: BottomBar = BottomBar.new()
	bar.app = app
	bar.position = Vector2(714, 656)
	add_child(bar)
	if not app.profile.created:
		build_creation()

func build_player_card() -> void:
	var card: Panel = UiKit.panel(self, Rect2(1016, 36, 256, 86), "wood_dark")
	UiKit.panel(card, Rect2(8, 8, 70, 70), "slot_light")
	var portrait: Panel = UiKit.panel(card, Rect2(12, 12, 62, 62), Color(0, 0, 0, 0))
	portrait.clip_contents = true
	AvatarView.create(portrait, app.profile.look(), Rect2(-34, -50, 130, 190))
	UiKit.label(card, app.profile.player_name, Rect2(86, 6, 166, 26), 17, Color.WHITE, UiKit.INK)
	UiKit.level_badge(card, app.profile.level(), Rect2(86, 34, 34, 22))
	UiKit.label(card, TankFighter.rank_for(app.profile.level()), Rect2(126, 32, 126, 26), 13, Color("9aff7a"), UiKit.INK)
	UiKit.art(card, "res://assets/items/moeda.png", Rect2(86, 58, 22, 22))
	UiKit.label(card, str(app.profile.coins), Rect2(112, 58, 140, 22), 15, Color("ffd46b"), UiKit.INK)
	var coupon: Button = UiKit.button(self, "CUPOM", Rect2(1016, 126, 124, 34), func() -> void: CouponDialog.open(self, app, app.show_city), "button", 15)
	coupon.name = "CouponButton"
	coupon.tooltip_text = "Resgatar cupom (TESTARTUDO libera tudo para testes)"
	UiKit.button(self, "MOCHILA", Rect2(1146, 126, 126, 34), app.open_bag, "button_green", 15)

func set_hover(index: int) -> void:
	hovered = index
	for i in range(buildings.size()):
		var sprite: Node = get_node_or_null("Sprite_" + str(buildings[i].id))
		if sprite != null:
			sprite.modulate = Color(1.25, 1.2, 1.05) if i == index else Color.WHITE
	for i in range(labels.size()):
		labels[i].add_theme_color_override("font_color", Color("ffe24a") if i == index else Color("fff6dc"))
	if index < 0:
		tip_panel.hide()
	else:
		var building: Dictionary = buildings[index]
		tip_label.text = building.tip
		var pos: Array = building.label
		tip_panel.position = Vector2(clampf(pos[0] - 170, 8, 932), clampf(pos[1] + 40, 40, 640))
		tip_panel.show()
	glow.queue_redraw()

func leave_hover(index: int) -> void:
	if hovered == index:
		set_hover(-1)

func draw_glow() -> void:
	if hovered < 0:
		return
	var r: Array = buildings[hovered].get("hot", buildings[hovered].rect)
	var rect: Rect2 = Rect2(r[0], r[1], r[2], r[3])
	var pulse: float = 0.5 + 0.5 * sin(time * 5.0)
	for i in range(4):
		var grown: Rect2 = rect.grow(-4 + i * 4)
		glow.draw_rect(grown, Color(1, 0.85, 0.3, 0.12 + 0.08 * pulse - i * 0.03), false, 4)
	glow.draw_rect(rect, Color(1, 0.95, 0.6, 0.08 + 0.05 * pulse))

func enter(id: String) -> void:
	if is_instance_valid(creation):
		return
	app.audio.play("ui_click")
	match id:
		"hall":
			app.show_hall()
		"instance":
			app.create_room("pve")
			app.show_room()
		"smith":
			var smith: SmithScreen = SmithScreen.new()
			smith.app = app
			smith.closed.connect(app.show_city)
			add_child(smith)
		"auction":
			UiKit.notice(self, "LEILÃO", "O leilão depende do servidor online e ainda não está disponível.")
		"mall":
			var shop: ShopScreen = ShopScreen.new()
			shop.app = app
			shop.closed.connect(app.show_city)
			add_child(shop)
		"dating":
			UiKit.notice(self, "NAMORO", "Casamento e equipamentos de casal ainda não estão disponíveis.")
		"pet":
			UiKit.notice(self, "PET", "A Casa dos Mascotes ainda não está disponível nesta versão offline.")

func _process(delta: float) -> void:
	time += delta
	if hovered >= 0:
		glow.queue_redraw()
	for i in range(gulls.size()):
		var gull: Vector3 = gulls[i]
		gull.x += gull.z * delta
		if gull.x > 1320:
			gull = Vector3(-40, randf_range(430, 700), randf_range(22, 40))
		gulls[i] = gull
	if is_instance_valid(fx):
		fx.queue_redraw()

func fx_point(building: Dictionary, key: String) -> Vector2:
	var r: Array = building.rect
	var at: Array = building.fx[key]
	return Vector2(r[0] + at[0], r[1] + at[1])

func draw_fx() -> void:
	# Little living details on each building (the paintings themselves are static).
	if buildings != CITY_LAYOUT:
		return
	for building: Dictionary in buildings:
		var effects: Dictionary = building.get("fx", {})
		if effects.has("embers"):
			var arena: Vector2 = fx_point(building, "embers")
			for i in range(10):
				# Sparks rising from the arena floor.
				var phase: float = fposmod(time * 0.45 + i * 0.1, 1.0)
				var p: Vector2 = arena + Vector2(fposmod(i * 37.0, 90.0) - 45.0 + sin(time * 2.0 + i) * 6.0, -phase * 90.0)
				fx.draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(1.0, 0.75 - phase * 0.4, 0.25, 1.0 - phase))
		if effects.has("smoke"):
			var chimney: Vector2 = fx_point(building, "smoke")
			for i in range(6):
				# Smoke puffs from the forge chimney, drifting with the breeze.
				var phase: float = fposmod(time * 0.32 + i / 6.0, 1.0)
				var puff: Vector2 = chimney + Vector2(sin(time + i) * 4.0 + phase * 26.0, -phase * 80.0)
				fx.draw_circle(puff, 4.0 + phase * 11.0, Color(0.86, 0.86, 0.9, 0.6 * (1.0 - phase)))
				fx.draw_circle(puff + Vector2(-2, -2), 2.0 + phase * 6.0, Color(1, 1, 1, 0.35 * (1.0 - phase)))
		if effects.has("forge"):
			var heat: float = 0.35 + 0.25 * sin(time * 9.0) + 0.1 * sin(time * 23.0)
			fx.draw_circle(fx_point(building, "forge"), 14.0, Color(1.0, 0.55, 0.15, heat * 0.45))
		if effects.has("portal"):
			var gate: Vector2 = fx_point(building, "portal")
			var pulse: float = 0.25 + 0.15 * sin(time * 3.0)
			fx.draw_circle(gate, 22.0, Color(0.3, 0.9, 1.0, pulse))
			for i in range(8):
				# Motes spiralling out of the portal.
				var phase: float = fposmod(time * 0.5 + i * 0.125, 1.0)
				var spin: float = time * 2.0 + i * TAU / 8.0
				var spark: Vector2 = gate + Vector2(cos(spin), sin(spin)) * (8.0 + phase * 26.0) + Vector2(0, -phase * 30.0)
				fx.draw_rect(Rect2(spark.round(), Vector2(2, 2)), Color(0.6, 1.0, 1.0, 1.0 - phase))
		if effects.has("hearts"):
			var bell: Vector2 = fx_point(building, "hearts")
			for i in range(4):
				# Hearts floating from the chapel.
				var phase: float = fposmod(time * 0.3 + i * 0.25, 1.0)
				var heart: Vector2 = bell + Vector2((i - 1.5) * 14.0 + sin(time * 2.0 + i * 2.0) * 8.0, -phase * 60.0)
				draw_heart(heart, 5.0, Color(1.0, 0.45, 0.7, 1.0 - phase))
		if effects.has("twinkle"):
			var shop: Rect2 = Rect2(Vector2(building.hot[0], building.hot[1]), Vector2(building.hot[2], building.hot[3]))
			for i in range(5):
				# Twinkles on the shop fronts.
				var blink: float = sin(time * 3.0 + i * 1.9 + shop.position.x)
				if blink > 0.6:
					var star: Vector2 = (shop.position + Vector2(shop.size.x * (0.15 + fposmod(i * 0.29, 0.7)), shop.size.y * (0.25 + 0.12 * i))).round()
					var r: float = 3.0 * blink
					fx.draw_line(star - Vector2(r, 0), star + Vector2(r, 0), Color(1, 1, 0.8), 2.0)
					fx.draw_line(star - Vector2(0, r), star + Vector2(0, r), Color(1, 1, 0.8), 2.0)
	for gull: Vector3 in gulls:
		var flap: float = sin(time * 8.0 + gull.y) * 3.0
		var at: Vector2 = Vector2(gull.x, gull.y + sin(time + gull.z) * 4.0)
		fx.draw_polyline(PackedVector2Array([at + Vector2(-7, -flap), at, at + Vector2(7, -flap)]), Color("f4f4f4"), 2.0)

func draw_heart(center: Vector2, s: float, color: Color) -> void:
	fx.draw_circle(center + Vector2(-s * 0.5, 0), s * 0.6, color)
	fx.draw_circle(center + Vector2(s * 0.5, 0), s * 0.6, color)
	fx.draw_colored_polygon(PackedVector2Array([center + Vector2(-s * 1.05, s * 0.2), center + Vector2(s * 1.05, s * 0.2), center + Vector2(0, s * 1.4)]), color)

func build_creation() -> void:
	creation = Control.new()
	creation.size = size
	add_child(creation)
	UiKit.dim(creation, 0.65)
	UiKit.panel(creation, Rect2(330, 110, 620, 470), "wood")
	UiKit.panel(creation, Rect2(346, 160, 588, 404), "paper")
	UiKit.title(creation, "CRIE SEU PERSONAGEM", Rect2(330, 116, 620, 40), 26)
	UiKit.label(creation, "Uma conta, um personagem. Escolha a aparência e o nome.", Rect2(346, 168, 588, 26), 15, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(2):
		var gender: String = "m" if i == 0 else "f"
		var frame: Button = UiKit.button(creation, "", Rect2(430 + i * 230, 204, 190, 220), func() -> void: pick_gender(gender), "card")
		frame.name = "Gender_" + gender
		UiKit.art(frame, UiKit.character_path({"gender": gender}), Rect2(10, 6, 170, 180))
		UiKit.label(frame, "Masculino" if gender == "m" else "Feminino", Rect2(0, 186, 190, 28), 17, Color("fff6dc"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(creation, "Nome:", Rect2(430, 440, 80, 36), 18, UiKit.TEXT_DARK)
	name_input = LineEdit.new()
	name_input.position = Vector2(510, 440)
	name_input.size = Vector2(340, 36)
	name_input.max_length = 14
	name_input.text = app.profile.player_name
	name_input.add_theme_font_override("font", UiKit.font(true))
	name_input.add_theme_font_size_override("font_size", UiKit.fs(18))
	creation.add_child(name_input)
	UiKit.button(creation, "CRIAR PERSONAGEM", Rect2(520, 500, 240, 48), confirm_creation, "button_green", 18)
	pick_gender(app.profile.gender)

func pick_gender(gender: String) -> void:
	chosen_gender = gender
	for key: String in ["m", "f"]:
		var frame: Button = creation.get_node("Gender_" + key)
		frame.add_theme_stylebox_override("normal", UiKit.frame("card_hover" if key == gender else "card_busy"))

func confirm_creation() -> void:
	var chosen: String = name_input.text.strip_edges()
	if chosen.length() < 3:
		UiKit.notice(self, "NOME", "O nome precisa ter pelo menos 3 letras.")
		return
	app.profile.player_name = chosen
	app.profile.gender = chosen_gender
	app.profile.created = true
	app.profile.save_profile()
	app.show_city()
