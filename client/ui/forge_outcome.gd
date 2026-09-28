class_name ForgeOutcome
extends Control

signal completed
var item: Dictionary = {}
var success: bool = true
var age: float = 0.0
var art: Texture2D
var audio: GameAudio
var sounded: bool = false

func _ready() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	art = Armory.load_icon(item)
	if audio != null:
		audio.play("forge_charge")

func _process(delta: float) -> void:
	age += delta
	if age >= 1.05 and not sounded:
		sounded = true
		if audio != null:
			audio.play("forge_success" if success else "forge_failure")
	if age >= 3.3:
		completed.emit()
		queue_free()
	queue_redraw()

func _draw() -> void:
	var fade: float = minf(age * 5, 1.0) * clampf((3.3 - age) * 3, 0, 1)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.02, 0.055, fade * 0.9))
	var hub: Vector2 = Vector2(640, 310)
	var charge: float = clampf(age / 1.05, 0, 1)
	var burst: float = maxf(0, age - 1.05)
	var color: Color = HudPaint.GOLD if success else Color("ab99cf")
	if age < 1.05:
		HudPaint.glow(self, hub, 80 + charge * 100, Color(HudPaint.GOLD, charge))
		for i in range(32):
			var angle: float = i * TAU / 32 + age * 2
			var r: float = 270 * (1.0 - charge) + 50
			HudPaint.sparkle(self, hub + Vector2.from_angle(angle) * r, 4, Color(HudPaint.GOLD_HOT, fade))
	else:
		HudPaint.rays(self, hub, 22, 420, age * 0.15, Color(color, fade * 0.12), 0.05)
		HudPaint.glow(self, hub, 250, Color(color, fade * 0.65))
		for i in range(3):
			draw_arc(hub, 90 + burst * (100 + i * 65), 0, TAU, 96, Color(color, fade * maxf(0, 1 - burst / 1.4)), 3)
		for i in range(60):
			var direction: Vector2 = Vector2.from_angle(i * 2.399)
			var p: Vector2 = hub + direction * (35 + burst * (80 + i % 9 * 27)) + Vector2(0, burst * burst * 35)
			HudPaint.sparkle(self, p, 2 + i % 5, Color(color.lightened(0.35), fade * maxf(0, 1 - burst / 2.4)))
		HudPaint.fancy(self, Vector2(80, 497), tr("FORTALECIMENTO CONCLUÍDO") if success else tr("A FORJA NÃO DESPERTOU"), 48, color, Color("773810"), 1120, HORIZONTAL_ALIGNMENT_CENTER, 4, 10, fade)
		HudPaint.outlined(self, Vector2(160, 541), Armory.item_name(item), 28, Color(HudPaint.CREAM, fade), HudPaint.INK, 960, HORIZONTAL_ALIGNMENT_CENTER)
		if not success:
			HudPaint.outlined(self, Vector2(160, 580), tr("A pedra foi consumida. O nível do item foi preservado."), 20, Color(HudPaint.CREAM, fade), HudPaint.INK, 960, HORIZONTAL_ALIGNMENT_CENTER)
		var flash: float = maxf(0, 1.0 - burst * 7) * 0.55
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.9, 0.6, flash))
	var scale: float = 1.0 + (sin(minf(burst * 6, PI)) * 0.2 if burst > 0 else charge * 0.15)
	if art != null:
		draw_texture_rect(art, Rect2(hub - Vector2.ONE * 95 * scale, Vector2.ONE * 190 * scale), false, Color(Armory.icon_tint(item), fade))
	if burst > 0:
		HudPaint.fancy(self, Vector2(490, 175), "+%d" % int(item.get("level", 0)), 64, color, Color("773810"), 300, HORIZONTAL_ALIGNMENT_CENTER, 4, 8, fade)
