class_name ChallengeResult
extends Control

# The card at the end of a daily challenge run (0.22): the score and its medal, how the run
# went, the ranking (online: the server re-runs the replay and answers with the verified
# score and the position) and the day's reward.

var app: Node
var run: Dictionary = {}
var status: Label
var reward_label: Label
var again_button: Button
var watch_button: Button
var settled: bool = false

func _ready() -> void:
	size = Vector2(1280, 720)
	UiKit.dim(self, 0.6)
	var result: Dictionary = run.result
	var rect: Rect2 = Rect2(330, 110, 620, 500)
	UiKit.panel(self, rect, "wood")
	UiKit.panel(self, Rect2(rect.position + Vector2(14, 46), rect.size - Vector2(28, 60)), "paper")
	UiKit.title(self, tr("DESAFIO DO DIA"), Rect2(rect.position + Vector2(0, 8), Vector2(rect.size.x, 34)), 26)
	var medal: int = int(result.medal)
	var color: Color = Challenge.medal_color(medal)
	var disc: Control = Control.new()
	disc.position = rect.position + Vector2(240, 66)
	disc.size = Vector2(140, 140)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.draw.connect(func() -> void:
		HudPaint.glow(disc, Vector2(70, 70), 70.0, Color(color.r, color.g, color.b, 0.12), 4)
		disc.draw_circle(Vector2(70, 70), 50.0, Color("120a04"))
		disc.draw_circle(Vector2(70, 70), 46.0, color.darkened(0.35))
		disc.draw_circle(Vector2(70, 70), 38.0, color)
		HudPaint.sparkle(disc, Vector2(70, 70), 30.0, Color(1, 1, 1, 0.7 if medal > 0 else 0.15)))
	add_child(disc)
	UiKit.label(self, Challenge.medal_name(medal).to_upper(), Rect2(rect.position + Vector2(0, 212), Vector2(rect.size.x, 30)), 22, color, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var score_label: Label = UiKit.label(self, str(int(result.score)), Rect2(rect.position + Vector2(0, 238), Vector2(rect.size.x, 64)), 54, PremiumUi.GOLD, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	score_label.name = "ChallengeScore"
	var spec: Dictionary = Challenge.spec_for(int(run.replay.meta.day))
	var detail: String
	if str(spec.kind) == "duelo":
		detail = tr("Vitória em %d turnos") % int(result.turns) if bool(result.won) else tr("O rival resistiu até o fim dos turnos")
	else:
		detail = tr("Alvos derrubados: %d/%d  ·  Turnos: %d/%d") % [int(result.down), int(result.targets), int(result.turns), int(spec.turns)]
	UiKit.label(self, detail, Rect2(rect.position + Vector2(20, 306), Vector2(rect.size.x - 40, 26)), 17, UiKit.TEXT, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	status = UiKit.wrapped(self, tr("Registrando o resultado…") if app.online else "", Rect2(rect.position + Vector2(20, 338), Vector2(rect.size.x - 40, 52)), 17, UiKit.TEXT_MUTED, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	reward_label = UiKit.label(self, "", Rect2(rect.position + Vector2(20, 394), Vector2(rect.size.x - 40, 26)), 17, UiKit.GOOD, Color.TRANSPARENT, HORIZONTAL_ALIGNMENT_CENTER)
	again_button = UiKit.button(self, tr("TENTAR DE NOVO"), Rect2(rect.position.x + 24, rect.end.y - 66, 180, 46), app.start_challenge, "button_green", 16)
	again_button.name = "ChallengeAgain"
	watch_button = UiKit.button(self, tr("ASSISTIR"), Rect2(rect.position.x + 222, rect.end.y - 66, 170, 46), watch_replay, "button_blue", 16)
	watch_button.name = "ChallengeWatch"
	UiKit.button(self, tr("SAIR"), Rect2(rect.end.x - 204, rect.end.y - 66, 180, 46), app.show_challenge, "button", 16).name = "ChallengeExit"
	settle.call_deferred()

func watch_replay() -> void:
	app.start_replay(Replay.clean(JSON.parse_string(JSON.stringify(run.replay)), true))

# Registers the run: online the server checks it, offline the profile takes it.
func settle() -> void:
	if settled:
		return
	settled = true
	var result: Dictionary = run.result
	var day: int = int(run.replay.meta.day)
	if app.online:
		var reply: Dictionary = await app.submit_challenge(run.replay)
		if not is_inside_tree():
			return
		if not reply.ok:
			status.text = app.server_text(reply.get("error", ""))
			status.add_theme_color_override("font_color", UiKit.BAD)
			return
		status.text = tr("Pontuação confirmada pelo servidor: %d.  Posição %d de %d.") % [int(reply.score), int(reply.position), int(reply.total)]
		status.add_theme_color_override("font_color", UiKit.TEXT)
		if bool(reply.get("first", false)):
			reward_label.text = tr("Recompensa do dia: %s") % Challenge.reward_text()
		elif not bool(reply.get("best", false)):
			reward_label.text = tr("O seu melhor do dia continua valendo.")
		return
	var done: Dictionary = app.profile.challenge_done(day, int(result.score), int(result.medal))
	status.text = tr("Resultado salvo neste computador. Entre num servidor para ir ao ranking.")
	if bool(done.first):
		reward_label.text = tr("Recompensa do dia: %s") % Challenge.reward_text()
	elif not bool(done.best):
		reward_label.text = tr("O seu melhor do dia é %d.") % int(done.score)
