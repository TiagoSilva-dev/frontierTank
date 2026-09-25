class_name ResultScreen
extends Control

# End of battle: "meus result." breakdown, then the reward card draw.

var app: Node
var game: LocalMatch
var summary: Dictionary = {}
var stage: Control
var rays: Control
var time: float = 0.0
var auto_time: float = 9.0
var card_time: float = -1.0
var picks_left: int = 1
var cards: Array[Control] = []
var rewards: Array[Dictionary] = []
var revealed: Array[bool] = []
var timer_label: Label
var hint_label: Label
var continue_button: Button

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.62)
	show_results()

func clear_stage() -> void:
	if is_instance_valid(stage):
		stage.queue_free()
	stage = Control.new()
	stage.size = size
	add_child(stage)

func show_results() -> void:
	clear_stage()
	var won: bool = summary.get("won", false)
	rays = Control.new()
	rays.size = Vector2(560, 470)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.draw.connect(draw_rays.bind(rays))
	stage.add_child(rays)
	var me: TankFighter = game.local()
	if me.is_boss or me.look.is_empty():
		UiKit.art(stage, me.portrait(), Rect2(130, 60, 300, 320))
	else:
		AvatarView.create(stage, me.look, Rect2(110, 40, 340, 360))
	# Team table
	var table: Panel = UiKit.panel(stage, Rect2(24, 450, 560, 250), "wood_dark")
	UiKit.title(table, "Resultado", Rect2(0, 4, 560, 32), 22)
	var headers: Array[String] = ["Nome", "EXP", "mérito"]
	for i in range(3):
		UiKit.panel(table, Rect2(14 + i * 180, 40, 172, 30), "card")
		UiKit.label(table, headers[i], Rect2(14 + i * 180, 40, 172, 30), 15, Color("5a2e10"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	var roster: Array = summary.get("roster", [])
	for row in range(4):
		for i in range(3):
			UiKit.panel(table, Rect2(14 + i * 180, 76 + row * 42, 172, 38), "card_busy")
		if row < roster.size():
			var entry: Dictionary = roster[row]
			var values: Array[String] = [str(entry.name), "+%d" % int(entry.exp), "+%d" % int(entry.merit)]
			for i in range(3):
				UiKit.label(table, values[i], Rect2(14 + i * 180, 76 + row * 42, 172, 38), 15, Color("3a1a06"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	# Breakdown panel
	var panel: Panel = UiKit.panel(stage, Rect2(612, 16, 652, 684), "glass")
	UiKit.panel(panel, Rect2(150, 12, 340, 44), "plate")
	UiKit.label(panel, "meus result.", Rect2(150, 10, 340, 46), 30, Color("ffe6a0"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
	stamp(panel, Vector2(574, 62), won)
	var y: float = 72
	y = section(panel, y, "exp. de luta", Color("ff6a5c"), [["exp. de matar", summary.get("kill_exp", 0)], ["exp. de ferir", summary.get("hurt_exp", 0)], ["result. de luta", summary.get("result_exp", 0)], ["exp. de instância", summary.get("bonus_exp", 0)]])
	y = section(panel, y, "adição de exp.", Color("ff6a5c"), [["privil. VIP", 0], ["guerra assoc.", 0], ["equip. casal", 0], ["exp. servidor", 0], ["mest. aluno", 0], ["cart. dob. exp", 0]])
	y = section(panel, y, "mérito de luta", Color("7aff5a"), [["mérito de luta", summary.get("merit", 0)], ["cart. dob. mérito", 0], ["privil. VIP", 0], ["mérito servidor", 0]])
	UiKit.label(panel, "total", Rect2(20, 470, 200, 80), 54, Color("ffd04a"), Color("5a2408"))
	total_row(panel, Rect2(250, 470, 380, 40), "exp. total", int(summary.get("exp", 0)), Color("c0302a"))
	total_row(panel, Rect2(250, 518, 380, 40), "valor de mérito total", int(summary.get("merit", 0)), Color("2f8a1f"))
	if int(summary.get("level_after", 1)) > int(summary.get("level_before", 1)):
		var up: Label = UiKit.label(stage, "SUBIU PARA O NÍVEL %d!" % int(summary.level_after), Rect2(40, 390, 520, 50), 30, Color("9aff7a"), Color("0a2a04"), HORIZONTAL_ALIGNMENT_CENTER)
		up.add_theme_constant_override("outline_size", 10)
	continue_button = UiKit.button(stage, "Continuar ▶", Rect2(1080, 652, 170, 40), show_cards, "button_green", 17)
	continue_button.name = "Continue"

func section(parent: Control, y: float, heading: String, color: Color, rows: Array) -> float:
	UiKit.label(parent, heading, Rect2(220, y, 220, 26), 18, color, Color("1a0804"), HORIZONTAL_ALIGNMENT_CENTER)
	var total: int = 0
	for i in range(rows.size()):
		var row: Array = rows[i]
		var value: int = int(row[1])
		total += value
		var column: int = i % 2
		var line: int = i / 2
		UiKit.label(parent, str(row[0]), Rect2(24 + column * 230, y + 28 + line * 24, 220, 22), 14, Color("fff0d0") if value > 0 else Color("8a7a6a"), Color("1a0804"))
	var height: float = 28 + ceili(rows.size() / 2.0) * 24
	var value_label: Label = UiKit.label(parent, "+%d" % total, Rect2(520, y + height / 2 - 4, 110, 34), 28, color, Color("1a0804"), HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.add_theme_constant_override("outline_size", 6)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(1, 0.8, 0.5, 0.25)
	rule.position = Vector2(16, y + height + 6)
	rule.size = Vector2(620, 2)
	parent.add_child(rule)
	return y + height + 18

func total_row(parent: Control, rect: Rect2, text: String, value: int, color: Color) -> void:
	var bar: ColorRect = ColorRect.new()
	bar.color = color.darkened(0.3)
	bar.position = rect.position
	bar.size = rect.size
	parent.add_child(bar)
	UiKit.label(parent, text, Rect2(rect.position + Vector2(10, 0), Vector2(250, rect.size.y)), 17, Color.WHITE, Color("1a0804"))
	UiKit.label(parent, "+%d" % value, Rect2(rect.position + Vector2(220, -4), Vector2(150, rect.size.y + 8)), 32, Color.WHITE, color.darkened(0.6), HORIZONTAL_ALIGNMENT_RIGHT)

func stamp(parent: Control, center: Vector2, won: bool) -> void:
	var seal: Control = Control.new()
	seal.position = center - Vector2(56, 56)
	seal.size = Vector2(112, 112)
	seal.rotation = -0.15
	seal.pivot_offset = Vector2(56, 56)
	var tone: Color = Color("ffd04a") if won else Color("b8b8c0")
	seal.draw.connect(func() -> void:
		var points: PackedVector2Array = PackedVector2Array()
		for i in range(32):
			points.append(Vector2(56, 56) + Vector2.from_angle(i * TAU / 32) * (54.0 if i % 2 == 0 else 48.0))
		seal.draw_colored_polygon(points, tone.darkened(0.5))
		seal.draw_circle(Vector2(56, 56), 44, tone)
		seal.draw_arc(Vector2(56, 56), 38, 0, TAU, 32, tone.darkened(0.4), 2))
	parent.add_child(seal)
	var words: Label = UiKit.label(seal, "excelente!" if won else "esforce-se\nmais", Rect2(0, 20, 112, 72), 17, Color.WHITE, tone.darkened(0.6), HORIZONTAL_ALIGNMENT_CENTER)
	words.autowrap_mode = TextServer.AUTOWRAP_OFF

func draw_rays(canvas: Control) -> void:
	var center: Vector2 = Vector2(280, 230)
	for i in range(16):
		var a: float = i * TAU / 16 + time * 0.25
		var tip: Vector2 = center + Vector2.from_angle(a) * 420
		var side: Vector2 = center + Vector2.from_angle(a + 0.13) * 420
		canvas.draw_colored_polygon(PackedVector2Array([center, tip, side]), Color(1, 0.86, 0.4, 0.16))
	for r in [150, 110, 70]:
		canvas.draw_circle(center, r, Color(1, 0.95, 0.7, 0.07))

func _process(delta: float) -> void:
	time += delta
	if is_instance_valid(rays):
		rays.queue_redraw()
	if auto_time > 0 and cards.is_empty():
		auto_time -= delta
		if auto_time <= 0:
			show_cards()
	if card_time > 0:
		card_time -= delta
		if is_instance_valid(timer_label):
			timer_label.text = str(maxi(0, ceili(card_time)))
		if card_time <= 0:
			while picks_left > 0:
				var hidden: Array[int] = []
				for i in range(cards.size()):
					if not revealed[i]:
						hidden.append(i)
				if hidden.is_empty():
					break
				pick(hidden[randi() % hidden.size()])

# ---------- reward cards ----------

func show_cards() -> void:
	if not cards.is_empty():
		return
	auto_time = -1
	clear_stage()
	rays = null
	picks_left = 2 if summary.get("won", false) else 1
	UiKit.panel(stage, Rect2(340, 30, 600, 60), "plate")
	UiKit.title(stage, "Escolha %d carta%s!" % [picks_left, "s" if picks_left > 1 else ""], Rect2(340, 30, 600, 60), 30)
	timer_label = UiKit.label(stage, "10", Rect2(950, 30, 80, 60), 40, Color("ffb020"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
	hint_label = UiKit.label(stage, "Vencedores escolhem 2 cartas, derrotados 1.", Rect2(340, 92, 600, 26), 15, Color("fff0d0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var pool: Array = app.balance.rewards.cards
	var drop: Dictionary = super_drop()
	var drop_slot: int = randi() % 8
	for i in range(8):
		rewards.append(drop if i == drop_slot and not drop.is_empty() else roll(pool))
		revealed.append(false)
		var card: Control = Control.new()
		card.name = "Card_%d" % i
		card.size = Vector2(128, 192)
		card.position = Vector2(338 + (i % 4) * 156, 140 + (i / 4) * 218)
		card.pivot_offset = card.size / 2
		stage.add_child(card)
		var back: Button = UiKit.button(card, "", Rect2(Vector2.ZERO, card.size), pick.bind(i), "card")
		back.name = "Back"
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		UiKit.art(back, "res://assets/expansion/rewards/reward_card_back.png", Rect2(Vector2.ZERO, card.size), false)
		back.mouse_entered.connect(func() -> void: card.scale = Vector2.ONE * 1.06 if not revealed[i] else Vector2.ONE)
		back.mouse_exited.connect(func() -> void: card.scale = Vector2.ONE)
		cards.append(card)
	continue_button = UiKit.button(stage, "Continuar ▶", Rect2(1080, 652, 170, 40), app.return_to_room, "button_green", 17)
	continue_button.name = "Continue"
	continue_button.disabled = true
	card_time = 10.0

func super_drop() -> Dictionary:
	# Super Verdadeira weapons are never sold: only a won Instância can drop one,
	# more often on harder difficulties.
	if not summary.get("pve", false) or not summary.get("won", false):
		return {}
	var rules: Dictionary = Armory.data().drops
	var tier: int = maxi(0, ["normal", "hard", "heroic", "nightmare"].find(str(summary.get("difficulty", "normal"))))
	if randf() > float(rules.super_chance) + tier * float(rules.super_chance_per_difficulty):
		return {}
	var supers: Array = Armory.data().weapons.filter(func(def: Dictionary) -> bool: return def.get("super", false))
	var def: Dictionary = supers[randi() % supers.size()]
	return {"id": "super_" + str(def.id), "name": str(def.name), "weapon": str(def.id), "rarity": "legendary", "icon": Armory.weapon_icon(str(def.id))}

func roll(pool: Array) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in pool:
		total += float(entry.weight)
	var ticket: float = randf() * total
	for entry: Dictionary in pool:
		ticket -= float(entry.weight)
		if ticket <= 0:
			return entry
	return pool[0]

func pick(index: int) -> void:
	if picks_left <= 0 or revealed[index]:
		return
	picks_left -= 1
	grant(rewards[index])
	flip(index, true)
	app.audio.play("ui_card")
	if picks_left == 0:
		card_time = -1
		if is_instance_valid(timer_label):
			timer_label.text = ""
		get_tree().create_timer(0.9).timeout.connect(reveal_rest)

func reveal_rest() -> void:
	if not is_instance_valid(stage):
		return
	for i in range(cards.size()):
		if not revealed[i]:
			flip(i, false)
	continue_button.disabled = false
	hint_label.text = "Recompensas adicionadas à sua mochila."

func flip(index: int, mine: bool) -> void:
	revealed[index] = true
	var card: Control = cards[index]
	var tween: Tween = create_tween()
	tween.tween_property(card, "scale:x", 0.0, 0.14)
	tween.tween_callback(show_front.bind(index, mine))
	tween.tween_property(card, "scale:x", 1.0, 0.14)

func show_front(index: int, mine: bool) -> void:
	var card: Control = cards[index]
	var reward: Dictionary = rewards[index]
	card.get_node("Back").hide()
	var front: Control = Control.new()
	front.size = card.size
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(front)
	UiKit.art(front, "res://assets/expansion/rewards/reward_card_%s.png" % reward.rarity, Rect2(Vector2.ZERO, card.size), false)
	UiKit.art(front, str(reward.icon), Rect2(24, 36, 80, 80))
	var caption: Label = UiKit.label(front, str(reward.name), Rect2(10, 118, 108, 56), 13, Color.WHITE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not mine:
		front.modulate = Color(0.55, 0.55, 0.6)
		return
	var effect: PixelAnimation = PixelAnimation.new()
	effect.fps = 14
	effect.load_frames("res://assets/expansion/animations/card_flip_effect", 8, 220)
	effect.position += card.size / 2
	card.add_child(effect)
	get_tree().create_timer(0.6).timeout.connect(effect.queue_free)

func grant(reward: Dictionary) -> void:
	var profile: PlayerProfile = app.profile
	if reward.has("coins"):
		profile.coins += int(reward.coins)
	elif reward.has("item"):
		profile.add_item(str(reward.item))
	elif reward.has("tool"):
		if not profile.add_tool(str(reward.tool)):
			profile.coins += 30
	elif reward.has("weapon"):
		profile.add_instance(str(reward.weapon), "super")
	profile.save_profile()
