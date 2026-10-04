class_name PlayerProfileDialog
extends Control

# The profile of another player (from the channel list or the chat): character on a
# pedestal, level, record, weapon and the attributes the gear adds. The simulated players
# are known to the offline channel; the online ones are asked from the server, so only what
# the others may see travels (server/game/player_session.gd public_profile).

var app: Node
var person: Dictionary = {}
var info: Dictionary = {}
var content: Control

static func open(parent: Node, app_node: Node, who: Dictionary) -> PlayerProfileDialog:
	for old: Node in parent.get_children():
		if old is PlayerProfileDialog:
			old.queue_free()
	var dialog: PlayerProfileDialog = PlayerProfileDialog.new()
	dialog.app = app_node
	dialog.person = who
	dialog.name = "PlayerProfile"
	parent.add_child(dialog)
	return dialog

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.6)
	var rect: Rect2 = Rect2(300, 96, 680, 508)
	UiKit.panel(self, rect, "wood")
	UiKit.title(self, tr("PERFIL DO JOGADOR"), Rect2(rect.position.x, rect.position.y + 8, rect.size.x, 34), 24)
	UiKit.panel(self, Rect2(rect.position + Vector2(14, 46), rect.size - Vector2(28, 60)), "paper")
	content = Control.new()
	content.position = rect.position
	content.size = rect.size
	add_child(content)
	UiKit.button(self, tr("FECHAR"), Rect2(rect.end.x - 170, rect.end.y - 58, 140, 40), queue_free, "button", 16).name = "Close"
	UiKit.label(content, tr("Carregando…"), Rect2(14, 46, rect.size.x - 28, rect.size.y - 60), 20, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	info = await app.lobby.profile_of(person)
	if not is_inside_tree():
		return
	for child in content.get_children():
		child.queue_free()
	if info.has("error"):
		UiKit.label(content, tr(str(info.error)) if str(info.error) not in ["timeout", "offline"] else app.server_text(info.error), Rect2(14, 46, rect.size.x - 28, rect.size.y - 60), 20, UiKit.BAD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	build()

func build() -> void:
	var mine: bool = str(info.get("name", "")) == app.profile.player_name
	var level: int = int(info.get("level", 1))
	# --- left: the character on a dark stage
	var stage: Panel = UiKit.panel(content, Rect2(30, 64, 250, 330), "slot")
	stage.clip_contents = true
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("1b1530")
	backdrop.position = Vector2(4, 4)
	backdrop.size = Vector2(242, 322)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(backdrop)
	var look: Dictionary = info.get("look", {})
	if look.is_empty():
		look = Armory.look_for(str(info.get("gender", "m")), [])
	AvatarView.create(stage, look, Rect2(0, 6, 250, 318))
	# --- right: identity, record and gear
	var x: float = 304.0
	UiKit.level_badge(content, level, Rect2(x, 62, 54, 34))
	if bool(info.get("founder", false)):
		FounderUi.badge(content, Rect2(x + 62, 64, 28, 28))
		UiKit.label(content, str(info.get("name", "")), Rect2(x + 96, 60, 240, 38), 24, UiKit.TEXT).name = "Name"
	else:
		UiKit.label(content, str(info.get("name", "")), Rect2(x + 62, 60, 280, 38), 24, UiKit.TEXT).name = "Name"
	UiKit.label(content, TankFighter.rank_for(level), Rect2(x, 100, 150, 26), 17, UiKit.GOOD)
	# Ranked (0.22): the division badge and name, and the equipped season title on the stage.
	var rating: Dictionary = info.get("rating", {})
	if bool(rating.get("placed", false)):
		var mmr: int = int(rating.get("mmr", 0))
		RankBadge.create(content, Rect2(x + 150, 98, 30, 30), mmr, true).name = "RankBadge"
		UiKit.label(content, Ranked.label(mmr), Rect2(x + 184, 100, 160, 26), 16, Ranked.division(mmr).color).name = "RankName"
	var season_title: String = Ranked.title_text(str(info.get("title", "")))
	if season_title != "":
		UiKit.label(content, season_title, Rect2(34, 366, 242, 24), 14, PremiumUi.GOLD, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER).name = "Title"
	var rows: Array = [[tr("Ranking"), str(int(info.get("ranking", 0))), UiKit.BAD], [tr("Méritos"), str(int(info.get("merits", 0))), UiKit.INFO], [tr("Vitórias"), str(int(info.get("victories", 0))), UiKit.TEXT], [tr("Partidas"), str(int(info.get("matches", 0))), UiKit.TEXT]]
	for i in range(rows.size()):
		var row: Array = rows[i]
		var at: Vector2 = Vector2(x + (i % 2) * 176, 134 + (i / 2) * 30)
		UiKit.label(content, str(row[0]), Rect2(at, Vector2(90, 26)), 16, row[2])
		UiKit.label(content, str(row[1]), Rect2(at + Vector2(88, 0), Vector2(80, 26)), 17, UiKit.TEXT)
	# weapon
	var weapon: Dictionary = info.get("arma", {})
	UiKit.panel(content, Rect2(x, 204, 346, 70), "slot_light")
	if not weapon.is_empty():
		UiKit.art(content, Armory.weapon_icon(str(weapon.get("id", "")), int(weapon.get("level", 0))), Rect2(x + 8, 208, 62, 62))
		var weapon_name: Label = UiKit.clipped(content, Armory.item_name(weapon), Rect2(x + 78, 212, 262, 30), 17, UiKit.TEXT)
		weapon_name.name = "Weapon"
		UiKit.label(content, tr("Arma equipada"), Rect2(x + 78, 242, 262, 24), 14, UiKit.TEXT_MUTED)
	else:
		UiKit.label(content, tr("Sem arma equipada"), Rect2(x + 8, 204, 330, 70), 16, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	# attributes the gear adds
	var attrs: Dictionary = info.get("attrs", {})
	UiKit.label(content, tr("Atributos dos itens"), Rect2(x, 282, 346, 24), 15, UiKit.TEXT_MUTED)
	var keys: Array = [["ataque", "Ataque"], ["defesa", "Defesa"], ["agilidade", "Agilidade"], ["sorte", "Sorte"]]  # i18n
	for i in range(keys.size()):
		var at: Vector2 = Vector2(x + (i % 2) * 176, 308 + (i / 2) * 30)
		UiKit.label(content, tr(str(keys[i][1])), Rect2(at, Vector2(92, 26)), 16, UiKit.TEXT)
		UiKit.label(content, "+%d" % int(attrs.get(keys[i][0], 0)), Rect2(at + Vector2(92, 0), Vector2(70, 26)), 17, UiKit.GOLD)
	# actions
	if not mine:
		var whisper: Button = UiKit.button(content, tr("MENSAGEM"), Rect2(30, 412, 160, 40), func() -> void:
			PlayerMenu.start_whisper(app, info)
			queue_free(), "button_green", 16)
		whisper.name = "Whisper"
		var friend: Button = UiKit.button(content, tr("Remover amigo") if app.friends.has(str(info.name)) else tr("ADICIONAR AMIGO"), Rect2(200, 412, 230, 40), toggle_friend, "button_blue", 16)
		friend.name = "Friend"

func toggle_friend() -> void:
	var name_value: String = str(info.get("name", ""))
	if app.friends.has(name_value):
		app.friends.remove(name_value)
		app.toast(tr("%s saiu da sua lista de amigos.") % name_value)
	else:
		var problem: String = app.friends.add(info)
		app.toast(tr(problem) if problem != "" else tr("%s agora é seu amigo!") % name_value)
	app.lobby.rooms_changed.emit()
	var button: Button = content.get_node_or_null("Friend")
	if button != null:
		button.text = tr("Remover amigo") if app.friends.has(name_value) else tr("ADICIONAR AMIGO")

func _gui_input(_event: InputEvent) -> void:
	accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
