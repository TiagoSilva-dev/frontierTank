class_name FounderFx
extends Node2D

# The living parts of the Founder Pack around one character (docs/FOUNDER_PACK.md):
#  - Halo Solar (the Paladino do Sol skin): behind the head and shoulders, turns slowly,
#    sheds sparks while moving, flares on an attack, dims when hit, swells on victory and
#    becomes the mandala during Julgamento do Sol.
#  - Aura do Primeiro Sol (Founders): a magic circle on the ground, a thin ring in battle
#    (the lobby shows the whole circle), larger after a win.
#  - Pet Solis (Founders, battle): follows above and behind the character, out of the way
#    of the shot line.
#  - Footstep celestial (Founders, battle): solar marks on the ground for 0.4 s.
# LookRig owns one of these for every look that has any of them (menus and battles). The
# owner tells it what is happening with `rig.fx_state` and `rig.fx_event`; all of it is
# drawing, nothing here touches the match.

const HALO_SLOTS: int = 8
const FOOT_LIFE: float = 0.4
const FOOT_SPACING: float = 26.0
const PET_CLIPS: Array[String] = ["fly", "happy", "scared", "victory"]

var rig: LookRig
var fighter: TankFighter
var time: float = 0.0
var phase: float = 0.0
var flare: float = 0.0
var hit_blink: float = 0.0
var boost: float = 0.0
var boost_goal: float = 0.0
# 0..1: how far the halo has become the mandala (set by FounderPow).
var pow_amount: float = 0.0
# 0..1: the lobby entrance (the halo grows out of nothing).
var appear: float = 1.0
var extras: Dictionary = {}
var halo: Sprite2D
var glow: Sprite2D
var mandala: Sprite2D
var halo_frames: Array[Texture2D] = []
var power_frames: Array[Texture2D] = []
var mandala_frames: Array[Texture2D] = []
var sparks: CPUParticles2D
var aura: Sprite2D
var aura_frames: Array[Texture2D] = []
var aura_thin: Texture2D
var aura_motes: CPUParticles2D
var pet: Sprite2D
var pet_clips: Dictionary = {}
var pet_clip: String = "fly"
var pet_clip_time: float = 0.0
var pet_hold: float = 0.0
var pet_offset: Vector2 = Vector2.ZERO
var last_foot: Vector2 = Vector2(INF, INF)
var foot_flip: float = 1.0

func _ready() -> void:
	extras = rig.look.get("founder", {}) if rig.look.get("founder", {}) is Dictionary else {}
	if FounderPack.wears_skin(rig.look):
		build_halo()
	if bool(extras.get("aura", false)):
		build_aura()
	if bool(extras.get("pet", false)) and rig.view == "prone":
		build_pet()

func make_sprite(texture: Texture2D, additive: bool = false) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	# The art is drawn on a pixel grid; the smooth material keeps the edges crisp while
	# the sprite is scaled by any factor and rotated in steps.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if additive:
		var material: CanvasItemMaterial = CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = material
	else:
		sprite.material = UiKit.smooth_material()
	add_child(sprite)
	return sprite

func build_halo() -> void:
	halo_frames = FounderPack.frames("halo", "halo_")
	power_frames = FounderPack.frames("halo", "halo_power_")
	mandala_frames = FounderPack.frames("mandala", "mandala_")
	if halo_frames.is_empty():
		return
	glow = make_sprite(FounderPack.texture("halo/glow.png"), true)
	halo = make_sprite(halo_frames[0])
	mandala = make_sprite(mandala_frames[0] if not mandala_frames.is_empty() else halo_frames[0])
	mandala.visible = false
	sparks = FxParticles.stream(self, Vector2.ZERO, {"amount": 14, "lifetime": 0.5, "speed": [18.0, 46.0], "spread": 180.0, "gravity": Vector2(0, -20), "size": [2.0, 3.0], "colors": ["ffffff", "fff26a", "ffb02e"], "box": Vector2(8, 8), "emitting": false, "z": 1})

func build_aura() -> void:
	aura_frames = FounderPack.frames("aura", "aura_")
	aura_thin = FounderPack.texture("aura/aura_thin.png")
	if aura_frames.is_empty():
		return
	aura = make_sprite(aura_frames[0])
	aura.z_index = -1
	var battle: bool = rig.view == "prone"
	aura_motes = FxParticles.stream(self, Vector2.ZERO, {"amount": 5 if battle else 14, "lifetime": 1.6, "speed": [8.0, 22.0], "direction": Vector2.UP, "spread": 18.0, "gravity": Vector2(0, -8), "size": [2.0, 3.0], "colors": ["fff0a8", "ffd25a", "f0a62c"], "box": Vector2(30, 3), "z": -1})

func build_pet() -> void:
	for clip: String in PET_CLIPS:
		pet_clips[clip] = FounderPack.frames("pet/" + clip)
	if pet_clips.get("fly", []).is_empty():
		return
	pet = make_sprite(pet_clips.fly[0])
	pet.z_index = 2
	pet.scale = Vector2(0.7, 0.7)

# ---------- events from the owner ----------

func event(kind: String) -> void:
	match kind:
		"attack":
			flare = 1.0
			pet_play("happy", 0.7)
		"hit":
			hit_blink = 0.14
			pet_play("scared", 1.0)
		"victory":
			boost_goal = 1.0
			pet_play("victory", 99.0)
		"reset":
			boost_goal = 0.0
			pet_hold = 0.0

func pet_play(clip: String, seconds: float) -> void:
	if pet == null or pet_clips.get(clip, []).is_empty():
		return
	pet_clip = clip
	pet_clip_time = 0.0
	pet_hold = seconds

func begin_pow() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "pow_amount", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func end_pow() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "pow_amount", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# The lobby entrance: the halo grows from nothing while the owner drops in.
func play_entrance(seconds: float = 0.9) -> void:
	appear = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "appear", 1.0, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------- drawing ----------

func _process(delta: float) -> void:
	time += delta
	flare = move_toward(flare, 0.0, delta * 4.0)
	hit_blink = maxf(0.0, hit_blink - delta)
	boost = move_toward(boost, boost_goal, delta * 0.8)
	var state: String = rig.fx_state
	if halo != null and rig.head_dims.x > 0.0:
		update_halo(delta, state)
	if aura != null and rig.head_dims.x > 0.0:
		update_aura(state)
	if pet != null and rig.head_dims.x > 0.0:
		update_pet(delta, state)
	if fighter != null and bool(extras.get("foot", false)):
		update_footsteps()

func update_halo(delta: float, state: String) -> void:
	var fps: float = 5.3
	match state:
		"walk":
			fps = 10.7
		"attack":
			fps = 9.0
		"victory":
			fps = 16.0
		"defeat":
			fps = 1.5
		"pow":
			fps = 14.0
	phase += delta * fps
	var dims: Vector2 = rig.head_dims
	var diameter: float = dims.x * 2.55 * (1.0 + 0.12 * flare + 0.55 * boost) * lerpf(0.05, 1.0, appear)
	var slot: int = int(phase) % HALO_SLOTS
	var ring_frames: Array[Texture2D] = power_frames if (state == "aim" or pow_amount > 0.0) and not power_frames.is_empty() else halo_frames
	halo.texture = ring_frames[slot % ring_frames.size()]
	var center: Vector2 = rig.head_center
	for sprite: Sprite2D in [halo, glow, mandala]:
		sprite.position = center
	halo.scale = Vector2.ONE * diameter / 128.0 * lerpf(1.0, 1.5, pow_amount)
	halo.modulate.a = (0.25 if hit_blink > 0.0 else (0.45 if state == "defeat" else 1.0)) * (1.0 - pow_amount * 0.75)
	# The glow breathes; a flare or the POW opens it up.
	var breathe: float = 0.5 + 0.5 * sin(time * 2.2)
	glow.scale = halo.scale * lerpf(1.22, 1.0, pow_amount)
	glow.modulate.a = (0.42 + 0.12 * breathe + 0.5 * flare + 0.25 * boost + 0.15 * pow_amount) * (0.35 if state == "defeat" else 1.0) * clampf(appear, 0.0, 1.0)
	if mandala != null:
		mandala.visible = pow_amount > 0.01 and not mandala_frames.is_empty()
		if mandala.visible:
			mandala.texture = mandala_frames[int(time * 9.0) % mandala_frames.size()]
			var big: float = dims.x * 7.0 * pow_amount
			mandala.scale = Vector2.ONE * big / 192.0
			mandala.modulate.a = clampf(pow_amount * 1.4, 0.0, 1.0)
	sparks.position = center + Vector2(0, dims.y * 0.2)
	sparks.emitting = state == "walk" or state == "victory" or pow_amount > 0.4

func update_aura(state: String) -> void:
	var battle: bool = rig.view == "prone"
	var dims: Vector2 = rig.head_dims
	var width: float = dims.x * (4.4 if battle else 3.0) * (1.0 + 0.8 * boost) * lerpf(0.3, 1.0, appear)
	aura.position = Vector2(rig.body_rect.get_center().x, rig.ground_y + (2.0 if battle else -3.0))
	if battle:
		aura.texture = aura_thin
		aura.modulate.a = 0.35 + 0.4 * boost + 0.12 * pow_amount
		# The ring stays put; only the motes move.
	else:
		aura.texture = aura_frames[int(time * 5.3) % aura_frames.size()]
		aura.modulate.a = 0.9 * appear
	aura.scale = Vector2.ONE * width / 96.0
	aura_motes.position = aura.position + Vector2(0, -2)
	aura_motes.emission_rect_extents = Vector2(width * 0.35, 3)
	aura_motes.amount = (5 if battle else 14) + int(10 * boost)

func update_pet(delta: float, state: String) -> void:
	var dir: float = -1.0 if rig.flip else 1.0
	# Above and behind the character, clear of the firing line in front of it.
	var goal: Vector2 = rig.head_center + Vector2(-dir * rig.head_dims.x * 1.35, -rig.head_dims.y * 1.15)
	if pet_offset == Vector2.ZERO:
		pet_offset = goal
	pet_offset = pet_offset.lerp(goal, clampf(delta * 4.0, 0.0, 1.0))
	pet.position = pet_offset + Vector2(0, sin(time * 3.0) * 3.0)
	pet.flip_h = dir < 0.0
	if pet_hold > 0.0:
		pet_hold -= delta
		if pet_hold <= 0.0 and pet_clip != "victory":
			pet_clip = "fly"
	elif pet_clip != "fly" and state != "victory":
		pet_clip = "fly"
	pet_clip_time += delta
	var frames: Array = pet_clips.get(pet_clip, [])
	if frames.is_empty():
		frames = pet_clips.fly
	pet.texture = frames[int(pet_clip_time * 9.0) % frames.size()]
	pet.modulate.a = 0.78 if rig.view == "prone" else 1.0

func update_footsteps() -> void:
	# A mark every FOOT_SPACING px of crawling, on the ground where the belly was.
	if not is_instance_valid(fighter) or fighter.hp <= 0 or fighter.walk_time <= 0.0:
		last_foot = Vector2(INF, INF)
		return
	var at: Vector2 = fighter.global_position
	if last_foot.x == INF:
		last_foot = at
		return
	if at.distance_to(last_foot) >= FOOT_SPACING:
		last_foot = at
		spawn_footstep(at)

func spawn_footstep(at: Vector2) -> void:
	var frames: Array[Texture2D] = FounderPack.frames("foot", "footstep_")
	var world: Node = fighter.get_parent()
	if frames.is_empty() or world == null:
		return
	var mark: FootMark = FootMark.new()
	mark.frames = frames
	mark.global_position = at + Vector2(-fighter.facing * 4.0, 1.0)
	mark.z_index = -1
	world.add_child(mark)

# One solar mark on the ground: it surges, flares and fades in FOOT_LIFE seconds.
class FootMark extends Sprite2D:
	var frames: Array[Texture2D] = []
	var age: float = 0.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture = frames[0]

	func _process(delta: float) -> void:
		age += delta
		var t: float = age / FounderFx.FOOT_LIFE
		if t >= 1.0:
			queue_free()
			return
		texture = frames[mini(int(t * frames.size()), frames.size() - 1)]
		modulate.a = 1.0 if t < 0.55 else 1.0 - (t - 0.55) / 0.45
