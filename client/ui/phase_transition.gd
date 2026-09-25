class_name PhaseTransition
extends Control

# Between two phases of an instance: what was cleared, what dropped (maps and gold, kept
# even if the party falls later), the rules of the pause (life +30%, POW kept, the fallen
# come back with little life) and the next phase. Advances by itself after a countdown.

const WAIT: float = 8.0

var app: Node
var report: Dictionary = {}
var left: float = WAIT
var time: float = 0.0
var countdown: Label
var rays: Control

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.7)
	rays = Control.new()
	rays.size = size
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.draw.connect(draw_rays)
	add_child(rays)
	var index: int = int(report.get("index", 1))
	var count: int = int(report.get("count", 3))
	var next: Dictionary = report.get("next", {})
	var banner: Label = UiKit.label(self, tr("FASE %d CONCLUÍDA!") % index, Rect2(0, 40, 1280, 80), 56, Color("ffd04a"), Color("5a2408"), HORIZONTAL_ALIGNMENT_CENTER)
	banner.add_theme_constant_override("outline_size", 14)
	banner.name = "Banner"
	UiKit.label(self, tr(str(report.get("cleared", ""))), Rect2(0, 114, 1280, 32), 22, Color("fff0d0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	# Next phase card
	var card: Panel = UiKit.panel(self, Rect2(170, 170, 520, 400), "wood")
	UiKit.panel(card, Rect2(14, 14, 492, 372), "paper")
	UiKit.title(card, tr("PRÓXIMA: FASE %d DE %d") % [index + 1, count], Rect2(0, 22, 520, 34), 24)
	var thumb: String = "res://assets/maps/thumbs/%s.png" % str(next.get("map", ""))
	var frame: Panel = UiKit.panel(card, Rect2(40, 64, 440, 190), "slot")
	frame.clip_contents = true
	if ResourceLoader.exists(thumb):
		UiKit.art(frame, thumb, Rect2(4, 4, 432, 182), false).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var boss_phase: bool = index + 1 == count
	UiKit.label(card, tr(str(next.get("name", ""))), Rect2(0, 262, 520, 40), 30, Color("c0402f") if boss_phase else Color("5a2e10"), Color("fff0d0"), HORIZONTAL_ALIGNMENT_CENTER)
	var goal: String = tr("Chefão! Derrote-o para abrir o baú.") if boss_phase else tr("Derrote o guardião e os lacaios.")
	match str(next.get("objective", "defeat")):
		"totems":
			goal = tr("Objetivo: destrua os cristais.")
		"survive":
			goal = tr("Objetivo: sobreviva %d turnos.") % int(next.get("turns", 5))
	UiKit.label(card, goal, Rect2(20, 302, 480, 30), 18, UiKit.TEXT_DARK, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.label(card, tr("Vida +%d%%  •  POW mantido  •  Quem caiu volta com %d%% de vida") % [roundi(float(app.balance.pve.phase_heal) * 100.0), roundi(float(app.balance.pve.revive_hp) * 100.0)], Rect2(20, 336, 480, 30), 14, Color("2f6a1f"), Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	# Drops of this phase
	var loot: Panel = UiKit.panel(self, Rect2(716, 170, 400, 400), "wood_dark")
	UiKit.title(loot, tr("ENCONTRADO"), Rect2(0, 12, 400, 34), 24)
	UiKit.art(loot, "res://assets/items/moeda.png", Rect2(40, 62, 40, 40))
	UiKit.label(loot, tr("+%d moedas") % int(report.get("gold", 0)), Rect2(90, 62, 280, 40), 24, Color("ffd46b"), UiKit.INK)
	var maps: Array = report.get("maps", [])
	if maps.is_empty():
		UiKit.label(loot, tr("Nenhum mapa caiu nesta fase."), Rect2(20, 130, 360, 30), 16, Color("c8b8a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(mini(maps.size(), 4)):
		var item: Dictionary = maps[i]
		var row: Panel = UiKit.panel(loot, Rect2(20, 116 + i * 66, 360, 60), "dark")
		row.name = "Drop_%d" % i
		UiKit.art(row, InstanceRun.map_icon(item), Rect2(6, 6, 48, 48))
		UiKit.label(row, InstanceRun.map_name(item), Rect2(60, 4, 296, 28), 15, InstanceRun.quality_color(str(item.quality)), UiKit.INK)
		UiKit.label(row, tr("%s  •  %d atributo(s)") % [InstanceRun.quality_label(str(item.quality)), item.mods.size()], Rect2(60, 30, 296, 24), 13, Color("e0d0b0"), UiKit.INK)
		row.tooltip_text = "\n".join(InstanceRun.describe_map(item))
	UiKit.label(loot, tr("Os mapas já estão na Mochila (aba Mapas)."), Rect2(10, 360, 380, 28), 13, Color("c8b8a0"), UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var go: Button = UiKit.button(self, tr("AVANÇAR ▶"), Rect2(540, 600, 200, 52), advance, "button_green", 22)
	go.name = "Advance"
	countdown = UiKit.label(self, "", Rect2(750, 606, 80, 40), 22, Color("fff0d0"), UiKit.INK)

func draw_rays() -> void:
	var center: Vector2 = Vector2(640, 80)
	for i in range(18):
		var a: float = i * TAU / 18 + time * 0.3
		rays.draw_colored_polygon(PackedVector2Array([center, center + Vector2.from_angle(a) * 900, center + Vector2.from_angle(a + 0.12) * 900]), Color(1, 0.85, 0.35, 0.07))

func _process(delta: float) -> void:
	time += delta
	rays.queue_redraw()
	left -= delta
	countdown.text = str(maxi(0, ceili(left)))
	if left <= 0.0:
		advance()

func advance() -> void:
	if left < -100.0:
		return
	left = -1000.0
	app.audio.play("ui_confirm")
	app.start_phase()
