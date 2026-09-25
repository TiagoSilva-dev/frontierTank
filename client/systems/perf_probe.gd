class_name PerfProbe
extends CanvasLayer

# Performance counter and battle benchmark (launch checklist: web build for closed tests).
#   F3 (or --fps=1, ?fps=1 on the web) shows FPS, frame time, script time and draw calls.
#   --bench=<seconds> (?bench=30 on the web) opens a 4v4 battle played by the AI on both
#   sides, waits WARMUP seconds and measures. The result goes to the screen, to the log as
#   one line "BENCH {json}" and, on the web, to window.ftBench (tools/web_bench.cjs reads
#   it). On desktop the game quits after the measurement.
# Frame time is measured on the wall clock (not the smoothed delta). Script time is the
# time between a marker node that runs first (priority -100000) and this node, which runs
# last, in _process and in _physics_process; the rest of the frame is the engine drawing
# and waiting for the screen.

const WARMUP: float = 3.0
const REFRESH: float = 0.5

class Marker extends Node:
	var probe: PerfProbe

	func _init() -> void:
		process_priority = -100000
		process_physics_priority = -100000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		var now: int = Time.get_ticks_usec()
		if probe.frame_begin > 0:
			probe.frame_interval = (now - probe.frame_begin) / 1000.0
		probe.frame_begin = now

	func _physics_process(_delta: float) -> void:
		probe.physics_begin = Time.get_ticks_usec()

var app: Node
var label: Label
var frame_begin: int = 0
var frame_interval: float = 0.0
var physics_begin: int = 0
var physics_usec: int = 0
var physics_steps: int = 0
var shown: bool = false
var bench_seconds: float = 0.0
var elapsed: float = 0.0
var refresh_timer: float = 0.0
var frame_ms: PackedFloat32Array = PackedFloat32Array()
var script_ms: PackedFloat32Array = PackedFloat32Array()
# Separately: the _process part of each frame and each 60 Hz physics step (a slow frame
# runs several steps, so the sum of both at 60 FPS is process + one step).
var process_ms: PackedFloat32Array = PackedFloat32Array()
var step_ms: PackedFloat32Array = PackedFloat32Array()
var draw_calls: PackedInt32Array = PackedInt32Array()
var max_nodes: int = 0
var result: Dictionary = {}
# Recent frames for the live counter.
var recent: PackedFloat32Array = PackedFloat32Array()
var recent_script: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100000
	process_physics_priority = 100000
	var marker: Marker = Marker.new()
	marker.probe = self
	add_child(marker)
	label = Label.new()
	label.position = Vector2(8, 6)
	label.add_theme_font_override("font", UiKit.font(true))
	label.add_theme_font_size_override("font_size", UiKit.fs(15))
	label.add_theme_color_override("font_color", Color("fff4d6"))
	label.add_theme_color_override("font_outline_color", UiKit.INK)
	label.add_theme_constant_override("outline_size", 6)
	var back: StyleBoxFlat = StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.04, 0.02, 0.72)
	back.set_content_margin_all(4)
	label.add_theme_stylebox_override("normal", back)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(label)
	label.visible = shown or bench_seconds > 0.0

func start_bench(seconds: float) -> void:
	bench_seconds = maxf(5.0, seconds)
	if is_instance_valid(label):
		label.visible = true

func toggle() -> void:
	shown = not shown
	label.visible = shown or bench_seconds > 0.0 or not result.is_empty()

func in_battle() -> bool:
	return app != null and str(app.get("screen_name")) == "battle"

func _physics_process(_delta: float) -> void:
	var spent: int = Time.get_ticks_usec() - physics_begin
	physics_usec += spent
	physics_steps += 1
	if bench_seconds > 0.0 and result.is_empty() and elapsed >= WARMUP and in_battle():
		step_ms.append(spent / 1000.0)

func _process(delta: float) -> void:
	var own: float = (Time.get_ticks_usec() - frame_begin) / 1000.0 if frame_begin > 0 else 0.0
	var script: float = own + physics_usec / 1000.0
	physics_usec = 0
	physics_steps = 0
	var ms: float = frame_interval if frame_interval > 0.0 else delta * 1000.0
	recent.append(ms)
	recent_script.append(script)
	if recent.size() > 120:
		recent = recent.slice(recent.size() - 120)
		recent_script = recent_script.slice(recent_script.size() - 120)
	if bench_seconds > 0.0 and result.is_empty():
		measure(ms / 1000.0, ms, script, own)
	refresh_timer -= delta
	if refresh_timer <= 0.0 and label.visible:
		refresh_timer = REFRESH
		label.text = status_text()

func measure(delta: float, ms: float, script: float, own: float) -> void:
	# Only the battle counts; if it ends early the result uses what was measured.
	if not in_battle():
		if elapsed > WARMUP and frame_ms.size() > 30:
			finish()
		return
	elapsed += delta
	if elapsed < WARMUP:
		return
	frame_ms.append(ms)
	script_ms.append(script)
	process_ms.append(own)
	draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	max_nodes = maxi(max_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	if elapsed >= WARMUP + bench_seconds:
		finish()

static func percentile(values: PackedFloat32Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = Array(values)
	sorted.sort()
	return float(sorted[clampi(int(ceil(fraction * sorted.size())) - 1, 0, sorted.size() - 1)])

static func average(values: Variant) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: Variant in values:
		total += float(value)
	return total / values.size()

func finish() -> void:
	var total_ms: float = 0.0
	for value: float in frame_ms:
		total_ms += value
	var frames: int = frame_ms.size()
	var game: Variant = app.screen.get("game") if in_battle() and is_instance_valid(app.screen) else null
	result = {
		"version": NetClient.GAME_VERSION,
		"platform": OS.get_name(),
		"web": OS.has_feature("web"),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"seconds": snappedf(total_ms / 1000.0, 0.01),
		"frames": frames,
		"fps_avg": snappedf(frames * 1000.0 / maxf(total_ms, 1.0), 0.1),
		"fps_1_low": snappedf(1000.0 / maxf(percentile(frame_ms, 0.99), 0.001), 0.1),
		"frame_ms_avg": snappedf(total_ms / maxi(frames, 1), 0.01),
		"frame_ms_p50": snappedf(percentile(frame_ms, 0.5), 0.01),
		"frame_ms_p95": snappedf(percentile(frame_ms, 0.95), 0.01),
		"frame_ms_p99": snappedf(percentile(frame_ms, 0.99), 0.01),
		"frame_ms_max": snappedf(percentile(frame_ms, 1.0), 0.01),
		"script_ms_avg": snappedf(average(script_ms), 0.01),
		"script_ms_p95": snappedf(percentile(script_ms, 0.95), 0.01),
		# The rest of the frame: the engine drawing (on the CPU with SwiftShader) and
		# waiting for the screen.
		"engine_ms_avg": snappedf(total_ms / maxi(frames, 1) - average(script_ms), 0.01),
		"process_ms_avg": snappedf(average(process_ms), 0.01),
		"physics_step_ms_avg": snappedf(average(step_ms), 0.01),
		"physics_steps_per_frame": snappedf(step_ms.size() / float(maxi(frames, 1)), 0.01),
		# What the game code would cost per frame at 60 FPS (one physics step per frame):
		# the budget is 16.7 ms.
		"script_ms_at_60fps": snappedf(average(process_ms) + average(step_ms), 0.01),
		"script_ms_at_60fps_p95": snappedf(percentile(process_ms, 0.95) + percentile(step_ms, 0.95), 0.01),
		"draw_calls_avg": snappedf(average(draw_calls), 0.1),
		"nodes_max": max_nodes,
		"fighters": game.fighters.size() if game != null else 0,
	}
	var line: String = JSON.stringify(result)
	print("BENCH " + line)
	label.text = status_text()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.ftBench = %s;" % line, true)
	elif app != null and app.get("args") is Dictionary and app.args.has("bench"):
		get_tree().quit()

func status_text() -> String:
	if not result.is_empty():
		return tr("Teste de desempenho: %s FPS de média, 1%% mais lentos: %s FPS\nQuadro: %s ms (95%%: %s ms)   Scripts a 60 FPS: %s ms   Desenhos: %s\n%s") % [result.fps_avg, result.fps_1_low, result.frame_ms_avg, result.frame_ms_p95, result.script_ms_at_60fps, result.draw_calls_avg, result.adapter]
	var fps: float = 1000.0 / maxf(average(recent), 0.001)
	var text: String = "FPS %d   %.1f ms   %s %.1f ms   %s %d" % [roundi(fps), average(recent), tr("scripts"), average(recent_script), tr("desenhos"), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
	if bench_seconds > 0.0:
		if elapsed < WARMUP:
			text += "\n" + tr("Teste de desempenho: preparando…")
		else:
			text += "\n" + tr("Teste de desempenho: medindo… %d s") % ceili(WARMUP + bench_seconds - elapsed)
	return text
