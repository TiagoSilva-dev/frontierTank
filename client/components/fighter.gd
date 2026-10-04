class_name TankFighter
extends Node2D

const TEAM_COLORS: Array[Color] = [Color("5cc8ff"), Color("ff6a5c")]

var player_id: int = 0
var team: int = 0
var display_name: String = "Nilo"
var rank_title: String = "Recruta"
var level: int = 1
var gender: String = "m"
var human: bool = false
# "Confiar": the AI plays this fighter. `left`: the player quit (online), the AI plays
# on until the end.
var auto_play: bool = false
var left: bool = false
# Online: the angle the local player is aiming at, drawn before the simulation (a little
# behind, lockstep) catches up. Only the drawing uses it.
var shown_angle: float = NAN
# PvE enemies (0.9): lacaio, guardião, chefe or totem (an objective that never acts).
var is_monster: bool = false
var rank: String = ""
var monster: Dictionary = {}
var monster_height: float = 0.0
var art_faces_left: bool = true
var always_enraged: bool = false
var base_damage: int = 0
var fury_damage: int = 0
var summon_entry: Dictionary = {}
var turns_taken: int = 0
# Monster abilities (0.14): turns left before each ability can be used again, the leap in
# progress (no gravity while it flies) and a war cry's bonus to the next attack.
var cooldowns: Dictionary = {}
var leaping: bool = false
var empower: float = 1.0
# Status effects (0.16): id -> {"turns", "stacks", "power"} (see LocalMatch.add_status)
# and, per status, the turns left of immunity after it wore off (thawed out of the ice).
var statuses: Dictionary = {}
var immune: Dictionary = {}
# PvE elites (0.16): the affix (combat.json → elites.affixes), empty for a plain enemy.
var elite: Dictionary = {}
var exploded: bool = false
var is_boss: bool:
	get:
		return rank == "boss"
var hp: int = 1000
var max_hp: int = 1000
var agility: int = 120
var max_energy: int = 240
var delay: float = 0.0
var pow_gauge: float = 0.0
var facing: int = 1
var angle: float = 45.0
var angle_range: Vector2 = Vector2(0, 90)
var tilt: float = 0.0
var velocity_y: float = 0.0
var shield: float = 1.0
# Turns the fighter is frozen for (the "congelado" status): it loses the next turn.
var frozen: int:
	get:
		return int(statuses.get("congelado", {}).get("turns", 0))
	set(value):
		if value > 0:
			statuses["congelado"] = {"turns": value, "stacks": 1, "power": 0.0}
		else:
			statuses.erase("congelado")
var fly_cooldown: int = 0
var last_power: float = -1.0
var tools: Array[String] = []
var weapon: Dictionary = {}
var look: Dictionary = {}
var attrs: Dictionary = {}
# Battle bonuses from the gear's random attributes (0.10), see Armory.character_stats.
var bonus: Dictionary = {}
var aux_id: String = ""
var aux_uses: int = 0
var rig: LookRig
var stats: Dictionary = {"damage": 0, "kills": 0, "hits": 0, "shots": 0, "taken": 0}
var active: bool = false
var settled: bool = true
var hit_radius: float = 23.0
var visual: Node2D
var body: Sprite2D
var idle_animation: PixelAnimation
var attack_animation: PixelAnimation
var walk_animation: PixelAnimation
# Premium skins (Paladino do Sol) also ship hit / victory / defeat / pow clips.
var extra_animations: Dictionary = {}
var clip_hold: float = 0.0
# A sequence (Julgamento do Sol) can pin the effects state ("pow") for its duration.
var fx_lock: String = ""
var celebrating: bool = false
var attack_time: float = 0.0
var walk_time: float = 0.0
var pulse: float = 0.0
var ghost: Sprite2D
var east_texture: Texture2D
var west_texture: Texture2D
var south_texture: Texture2D
var prone: bool = false
# Drawn over the body: the status effects (flames, roots, ice, the seal...).
var overlay: Node2D
var pixel_scale: float = 0.76
var body_size: Vector2 = Vector2(40, 72)
var front_x: float = 30.0

func setup(id: int, entry: Dictionary, weapon_data: Dictionary, balance: Dictionary) -> void:
	player_id = id
	team = int(entry.get("team", 0))
	display_name = str(entry.get("name", "Jogador"))
	level = int(entry.get("level", 1))
	gender = str(entry.get("gender", "m"))
	human = bool(entry.get("human", false))
	rank_title = rank_for(level)
	agility = int(entry.get("agility", int(balance.base_agility) + level * int(balance.agility_per_level)))
	max_hp = int(entry.get("hp", int(balance.base_hp) + level * int(balance.hp_per_level)))
	hp = max_hp
	bonus = entry.get("bonus", {}).duplicate()
	max_energy = int(balance.energy) + agility / 30 + int(bonus.get("energia", 0))
	pow_gauge = minf(float(balance.pow_max), float(bonus.get("pow_inicial", 0)))
	weapon = weapon_data.duplicate(true)
	var limits: Array = weapon.get("angle", [0, 90])
	angle_range = Vector2(limits[0], limits[1])
	angle = clampf(45.0, angle_range.x, angle_range.y)
	facing = 1 if team == 0 else -1
	attrs = entry.get("attrs", {})
	aux_id = str(entry.get("aux", ""))
	aux_uses = int(Armory.aux_def(aux_id).get("uses", 0)) if aux_id != "" else 0
	look = entry.get("look", {}).duplicate()
	if look.is_empty():
		look = Armory.look_for(gender, [{"id": weapon.id, "level": int(weapon.get("level", 0))}])
		if str(entry.get("skin", "")) != "":
			look.skin = str(entry.skin)
	var folder: String = UiKit.skin_for({"skin": look.get("skin", ""), "gender": gender})
	look.skin = folder
	var root: String = "res://assets/characters/%s" % folder
	south_texture = load(root + "/south.png")
	# Standing sprites set the pixel scale so every skin and pose shares one density.
	var standing: Texture2D = load(root + "/east.png")
	pixel_scale = 80.0 / standing.get_image().get_used_rect().size.y
	# DDTank fighters battle lying prone; use the PixelLab prone state when it exists.
	prone = ResourceLoader.exists(root + "/prone/east.png")
	var pose_root: String = root + "/prone" if prone else root
	east_texture = load(pose_root + "/east.png")
	west_texture = load(pose_root + "/west.png")
	var bounds: Rect2i = east_texture.get_image().get_used_rect()
	body_size = Vector2(bounds.size) * pixel_scale
	if prone:
		hit_radius = 24.0
	visual = Node2D.new()
	add_child(visual)
	body = Sprite2D.new()
	body.texture = east_texture
	body.scale = Vector2.ONE * pixel_scale
	if prone:
		# Full canvas (like the animation clips) with the belly resting on the ground;
		# west is the mirrored east so clips and sprite always line up.
		var half: float = east_texture.get_height() / 2.0
		body.position = Vector2(0, (half - bounds.end.y) * pixel_scale + 2.0)
		front_x = (bounds.end.x - east_texture.get_width() / 2.0) * pixel_scale
	else:
		# Atlas bounds avoid the padding in the generated 136px character canvases.
		body.region_enabled = true
		body.region_rect = Rect2(bounds)
		body.position = Vector2(0, -body_size.y / 2)
	visual.add_child(body)
	# PixelLab clips: <skin>/{idle,walk,attack} standing or <skin>/prone/{idle,crawl} lying.
	var clip_height: float = 136.0 * pixel_scale
	var idle_folder: String = pose_root + "/idle"
	if not prone and not ResourceLoader.exists(idle_folder + "/frame_00.png") and folder == "nilo":
		idle_folder = "res://assets/pve/hero_idle"
	idle_animation = add_animation(idle_folder, clip_height)
	idle_animation.pingpong = prone
	idle_animation.fps = 5.0 if prone else 7.0
	walk_animation = add_animation(pose_root + ("/crawl" if prone else "/walk"), clip_height)
	attack_animation = add_animation(root + "/attack" if not prone else pose_root + "/shoot", clip_height)
	if prone:
		for extra: String in ["hit", "victory", "defeat", "pow"]:
			if ResourceLoader.exists("%s/%s/frame_00.png" % [pose_root, extra]):
				var clip: PixelAnimation = add_animation("%s/%s" % [pose_root, extra], clip_height)
				clip.hide()
				clip.fps = 10.0
				clip.loop = extra == "victory"
				extra_animations[extra] = clip
	if not idle_animation.frames.is_empty():
		body.hide()
	walk_animation.hide()
	attack_animation.hide()
	# Equipment layers: weapon on the back, aura on the ground, wings, hat, glasses.
	rig = LookRig.new()
	rig.setup(look, "prone" if prone else "south")
	visual.add_child(rig.back)
	visual.move_child(rig.back, 0)
	visual.add_child(rig)
	rig.style(body)
	for clip: PixelAnimation in clips():
		if not clip.frames.is_empty():
			rig.style(clip, clip.clip)
	if rig.founder_fx != null:
		rig.founder_fx.fighter = self
	rig.source = shown_body
	if str(look.get("pet", "")) != "":
		var companion: PetCompanion = PetCompanion.new()
		add_child(companion)
		move_child(companion, 0)
		companion.setup(self, str(look.pet))
	make_overlay()
	update_pose()

func shown_body() -> Dictionary:
	# The sprite currently drawn and, for clips, how far its head moved from the static pose.
	if rig == null:
		return {}
	for clip: PixelAnimation in clips():
		if is_instance_valid(clip) and clip.visible and not clip.frames.is_empty():
			var offsets: Array = rig.anchors.get("clips", {}).get(clip.clip, {}).get("offsets", [])
			var offset: Vector2 = Vector2.ZERO
			if clip.frame_index < offsets.size():
				offset = Vector2(offsets[clip.frame_index][0], offsets[clip.frame_index][1])
			return {"node": clip, "offset": offset}
	if is_instance_valid(body) and body.visible:
		return {"node": body, "offset": Vector2.ZERO}
	return {}

func add_animation(folder: String, height: float) -> PixelAnimation:
	var animation: PixelAnimation = PixelAnimation.new()
	animation.load_frames(folder, 12, height)
	visual.add_child(animation)
	return animation

func clips() -> Array[PixelAnimation]:
	var list: Array[PixelAnimation] = [idle_animation, walk_animation, attack_animation]
	for clip: Variant in extra_animations.values():
		list.append(clip)
	return list

# One-shot clip (hit, pow) held for `seconds` and then back to idle; "victory" loops.
func play_clip(name: String, seconds: float = 0.4) -> bool:
	var clip: Variant = extra_animations.get(name)
	if not is_instance_valid(clip) or hp <= 0 and name != "defeat":
		return false
	clip.elapsed = 0.0
	clip_hold = seconds
	show_animation(clip)
	return true

# The match is won: Founder skins take the victory pose, everyone's effects swell.
func celebrate() -> void:
	if celebrating or hp <= 0:
		return
	celebrating = true
	play_clip("victory", 999.0)
	if is_instance_valid(rig):
		rig.fx_state = "victory"
		rig.fx_event("victory")

func show_animation(animation: PixelAnimation) -> void:
	# Falls back to the idle loop (or the static sprite) when a clip has no frames.
	var chosen: PixelAnimation = animation if is_instance_valid(animation) and not animation.frames.is_empty() else idle_animation
	for clip: PixelAnimation in clips():
		if is_instance_valid(clip):
			clip.visible = clip == chosen and not clip.frames.is_empty()
	body.visible = chosen == null or chosen.frames.is_empty()

func setup_monster(id: int, entry: Dictionary, def: Dictionary, balance: Dictionary) -> void:
	# A PvE enemy drawn from its PixelLab art (sprite + idle/attack clips), standing on
	# the ground instead of lying prone, with no equipment rig. Stats come already scaled
	# by the map level and party size (InstanceRun).
	player_id = id
	team = int(entry.get("team", 1))
	is_monster = true
	monster = def
	rank = str(def.get("rank", "minion"))
	display_name = str(entry.get("name", def.get("name", "Inimigo")))
	rank_title = tr({"minion": "Lacaio", "guardian": "Guardião", "boss": "Chefe", "totem": "Objetivo"}.get(rank, "Inimigo"))  # i18n
	level = int(entry.get("level", 1))
	max_hp = int(entry.get("hp", def.get("hp", 500)))
	hp = max_hp
	agility = int(def.get("agility", 80))
	max_energy = int(balance.energy)
	hit_radius = float(def.get("hit_radius", 28))
	monster_height = float(def.get("height", 80))
	art_faces_left = str(def.get("faces", "left")) == "left"
	always_enraged = bool(entry.get("enraged", false))
	shield = float(entry.get("shield", 1.0))
	elite = StatusRules.affix(str(entry.get("elite", ""))).duplicate(true)
	if not elite.is_empty():
		# Elites wear their affix instead of the rank ("Elite Vampira") and start behind
		# their armour when they have one.
		rank_title = tr(str(elite.name))
		if elite.has("shield"):
			shield = minf(shield, float(elite.shield))
	var limits: Array = def.get("angle", [25, 75])
	angle_range = Vector2(limits[0], limits[1])
	angle = clampf(45.0, angle_range.x, angle_range.y)
	facing = -1 if team == 1 else 1
	weapon = {"id": str(def.id), "name": tr(str(def.get("attack", "Ataque"))), "damage": int(entry.get("damage", def.get("damage", 100))), "radius": float(def.get("radius", 34)), "angle": limits, "color": str(def.get("color", "ffd04a"))}
	if def.has("projectile"):
		weapon.projectile = def.projectile
	base_damage = int(weapon.damage)
	fury_damage = int(entry.get("fury_damage", base_damage))
	summon_entry = entry.get("summon", {})
	visual = Node2D.new()
	add_child(visual)
	body = Sprite2D.new()
	var sprite_path: String = str(def.get("sprite", ""))
	if not ResourceLoader.exists(sprite_path):
		sprite_path = "res://assets/expansion/enemies/temple_guard.png"
	body.texture = load(sprite_path)
	var used: Rect2i = body.texture.get_image().get_used_rect()
	var k: float = monster_height / maxf(1.0, used.size.y)
	body_size = Vector2(used.size) * k
	visual.add_child(body)
	south_texture = body.texture
	# The clips share the sprite's pixel size (their canvases may be bigger); every layer
	# is scaled by the same factor with the crisp pixel shader and stands on the ground.
	idle_animation = PixelAnimation.new()
	idle_animation.load_frames(str(def.get("idle", "")), 16, monster_height)
	idle_animation.fps = float(def.get("idle_fps", 6.0))
	idle_animation.pingpong = bool(def.get("pingpong", true))
	visual.add_child(idle_animation)
	attack_animation = PixelAnimation.new()
	attack_animation.load_frames(str(def.get("attack_clip", "")), 16, monster_height)
	attack_animation.fps = float(def.get("attack_fps", 9.0))
	attack_animation.hide()
	visual.add_child(attack_animation)
	for layer: Sprite2D in [body, idle_animation, attack_animation]:
		fit_monster_layer(layer, k)
	walk_animation = null
	body.visible = idle_animation.frames.is_empty()
	if not elite.is_empty():
		visual.scale = Vector2.ONE * float(StatusRules.rules().get("elites", {}).get("scale", 1.15))
	make_overlay()
	update_pose()

static func rank_for(value: int) -> String:
	var ranks: Array[String] = ["Recruta", "Soldado", "Veterano", "Sargento", "Capitão", "Major", "Coronel", "General", "Marechal"]  # i18n
	return Lang.t(ranks[clampi((value - 1) / 4, 0, ranks.size() - 1)])

func make_overlay() -> void:
	overlay = Node2D.new()
	overlay.z_index = 1
	overlay.draw.connect(draw_overlay)
	add_child(overlay)

func alive() -> bool:
	return hp > 0

func has_status(id: String) -> bool:
	return statuses.has(id)

func animate_attack() -> void:
	turns_taken += 1
	if is_instance_valid(rig):
		rig.fx_event("attack")
	if is_instance_valid(attack_animation) and not attack_animation.frames.is_empty():
		attack_time = maxf(0.8, attack_animation.frames.size() / attack_animation.fps)
		attack_animation.elapsed = 0
		show_animation(attack_animation)
	elif is_instance_valid(visual):
		var tween: Tween = create_tween()
		tween.tween_property(visual, "position:x", -facing * 5.0, 0.06)
		tween.tween_property(visual, "position:x", 0.0, 0.18)

func fit_monster_layer(layer: Sprite2D, k: float) -> void:
	if layer.texture == null:
		return
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.material = UiKit.smooth_material()
	layer.scale = Vector2.ONE * k
	var bottom: float = layer.texture.get_image().get_used_rect().end.y
	layer.position = Vector2(0, layer.texture.get_height() * k * 0.5 - bottom * k)

func weapon_point() -> Vector2:
	# Where the weapon is (on the back when lying down), in world coordinates.
	if is_instance_valid(rig) and rig.back_weapon != null and rig.back_weapon.is_inside_tree():
		return rig.back_weapon.global_position
	return muzzle()

func set_pow_armed(value: bool) -> void:
	# POW preparation: the fighter pulls back and the weapon on the back lights up.
	if is_instance_valid(rig):
		rig.weapon_glow = 1.0 if value else 0.0
	if value:
		recoil(6.0, 0.45)

func recoil(amount: float, seconds: float = 0.3) -> void:
	if not is_instance_valid(visual):
		return
	var tween: Tween = create_tween()
	tween.tween_property(visual, "position:x", -facing * amount, seconds * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "position:x", 0.0, seconds * 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func acts() -> bool:
	# Totems are objectives: they never take a turn.
	return hp > 0 and rank != "totem"

func effective_angle() -> float:
	return angle + tilt * facing

func drawn_angle() -> float:
	return angle if is_nan(shown_angle) else shown_angle

func drawn_effective_angle() -> float:
	return drawn_angle() + tilt * facing

func update_pose() -> void:
	if body == null:
		return
	visual.rotation = 0.0 if is_monster else -deg_to_rad(tilt)
	if is_monster:
		var mirrored: bool = (facing > 0) == art_faces_left
		for clip: Sprite2D in [body, idle_animation, attack_animation]:
			if is_instance_valid(clip):
				clip.flip_h = mirrored
		modulate = Color("b8e8ff") if frozen > 0 else Color.WHITE
		redraw()
		return
	for clip: PixelAnimation in clips():
		if is_instance_valid(clip):
			clip.flip_h = facing < 0
	if prone:
		body.flip_h = facing < 0
	else:
		body.texture = east_texture if facing == 1 else west_texture
		body.region_rect = Rect2(body.texture.get_image().get_used_rect())
		body.position.y = -body_size.y / 2 + (sin(pulse * 3.0) * 1.0 if gender == "f" else 0.0)
	modulate = Color("b8e8ff") if frozen > 0 else Color.WHITE
	redraw()

func redraw() -> void:
	queue_redraw()
	if is_instance_valid(overlay):
		overlay.queue_redraw()

func hands() -> Vector2:
	# Where the weapon is held, in the unrotated local frame.
	if prone:
		return Vector2(facing * (front_x + 2), -9)
	return Vector2(facing * 14, -28)

func pivot() -> Vector2:
	if is_monster:
		return Vector2(facing * body_size.x * 0.3, -monster_height * 0.55)
	if prone:
		return hands().rotated(-deg_to_rad(tilt))
	return Vector2(0, -30).rotated(-deg_to_rad(tilt))

func muzzle_at(relative_angle: float) -> Vector2:
	if is_monster:
		return position + pivot()
	var a: float = deg_to_rad(relative_angle)
	var local: Vector2 = Vector2(facing * (16.0 + cos(a) * 22.0), -30.0 - sin(a) * 22.0)
	if prone:
		local = hands() + Vector2(facing * cos(a), -sin(a)) * 24.0
	return position + local.rotated(-deg_to_rad(tilt))

func muzzle() -> Vector2:
	return muzzle_at(angle)

func center() -> Vector2:
	if is_monster:
		return position + Vector2(0, -monster_height * 0.45)
	return position + Vector2(0, -18 if prone else -32)

func step_fall(delta: float, terrain: DestructibleTerrain, gravity: float) -> void:
	pulse += delta
	if clip_hold > 0.0 and not celebrating:
		clip_hold -= delta
		if clip_hold <= 0.0:
			show_animation(idle_animation)
	if is_instance_valid(rig) and not celebrating:
		rig.fx_state = fx_lock if fx_lock != "" else "attack" if attack_time > 0.0 else ("walk" if walk_time > 0.0 else ("aim" if active and hp > 0 else "idle"))
	if attack_time > 0:
		attack_time -= delta
		if attack_time <= 0:
			show_animation(idle_animation)
	elif walk_time > 0:
		walk_time -= delta
		if walk_time <= 0:
			show_animation(idle_animation)
	if hp <= 0 or leaping:
		return
	if terrain.solid(position + Vector2(0, 2)):
		velocity_y = 0
		if not settled:
			settled = true
			tilt = 0.0 if is_monster else terrain.slope_degrees(position.x, position.y)
	else:
		settled = false
		velocity_y += gravity * delta
		var travel: float = velocity_y * delta
		var steps: int = maxi(1, ceili(travel / 2.0))
		for i in range(steps):
			if terrain.solid(position + Vector2(0, travel / steps + 1)):
				velocity_y = 0
				settled = true
				tilt = 0.0 if is_monster else terrain.slope_degrees(position.x, position.y)
				break
			position.y += travel / steps
	if position.y > terrain.world_size.y + 40:
		hp = 0
		hide_body()
	update_pose()

func move_ground(amount: float, terrain: DestructibleTerrain) -> bool:
	if not settled or hp <= 0:
		return false
	facing = 1 if amount > 0 else -1
	var next_x: float = clampf(position.x + amount, 24, terrain.world_size.x - 24)
	if is_equal_approx(next_x, position.x):
		update_pose()
		return false
	# Climb small pixel steps but never teleport onto the far side of a crater.
	var top: float = terrain.surface_y(next_x, position.y - 10)
	if terrain.solid(Vector2(next_x, position.y - 12)):
		update_pose()
		return false
	position.x = next_x
	if top <= position.y + 6:
		position.y = top - 1
	if walk_time <= 0 and attack_time <= 0 and clip_hold <= 0.0 and is_instance_valid(walk_animation) and not walk_animation.frames.is_empty():
		show_animation(walk_animation)
	walk_time = 0.15
	tilt = terrain.slope_degrees(position.x, position.y)
	update_pose()
	return true

func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	stats.taken += amount
	if amount > 0 and is_instance_valid(rig):
		rig.fx_event("hit")
	if amount > 0 and hp > 0:
		play_clip("hit", 0.35)
	if amount > 0 and is_instance_valid(visual):
		visual.modulate = Color("ff877a")
		create_tween().tween_property(visual, "modulate", Color.WHITE, 0.4)
	if hp <= 0:
		hide_body()

func glow(color: Color) -> void:
	# A consumed skill lights the fighter up in its colour for a moment.
	if hp <= 0 or not is_instance_valid(visual):
		return
	visual.modulate = Color(1.0 + color.r * 0.9, 1.0 + color.g * 0.9, 1.0 + color.b * 0.9)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_SINE)

func hide_body() -> void:
	if is_instance_valid(visual):
		visual.hide()
	spawn_ghost()
	redraw()

func spawn_ghost() -> void:
	# A fallen fighter leaves a pale, translucent ghost that rises from the tombstone and
	# keeps floating there. Purely visual (monsters just vanish).
	if is_monster or is_instance_valid(ghost) or south_texture == null:
		return
	ghost = Sprite2D.new()
	ghost.texture = south_texture
	ghost.region_enabled = true
	ghost.region_rect = Rect2(south_texture.get_image().get_used_rect())
	ghost.scale = Vector2.ONE * pixel_scale * 0.8
	ghost.z_index = 2
	ghost.modulate = Color(0.75, 0.9, 1.0, 0.0)
	var rest: float = -body_size.y - 30.0
	ghost.position = Vector2(0, -body_size.y * 0.5)
	add_child(ghost)
	var rise: Tween = ghost.create_tween().set_parallel(true)
	rise.tween_property(ghost, "position:y", rest, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rise.tween_property(ghost, "modulate:a", 0.6, 0.8)
	var bob: Tween = ghost.create_tween().set_loops()
	bob.tween_interval(1.2)
	bob.tween_property(ghost, "position:x", 6.0, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(ghost, "position:x", -6.0, 1.1).set_trans(Tween.TRANS_SINE)

func portrait() -> Texture2D:
	return south_texture

func _draw() -> void:
	var font: Font = UiKit.font(true)
	if hp <= 0:
		# Tombstone marks where the fighter fell, like the classic ghost marker.
		draw_rect(Rect2(-10, -26, 20, 26), Color("8f96a8"))
		draw_rect(Rect2(-12, -2, 24, 4), Color("5d6272"))
		draw_rect(Rect2(-2, -22, 4, 14), Color("5d6272"))
		draw_rect(Rect2(-6, -18, 12, 4), Color("5d6272"))
		return
	var color: Color = TEAM_COLORS[team]
	if not elite.is_empty():
		draw_elite_aura()
	if active and not is_monster:
		var origin: Vector2 = pivot()
		var lo: float = angle_range.x + tilt * facing
		var hi: float = angle_range.y + tilt * facing
		var start: float = -deg_to_rad(lo) if facing > 0 else PI + deg_to_rad(lo)
		var finish: float = -deg_to_rad(hi) if facing > 0 else PI + deg_to_rad(hi)
		draw_arc(origin, 46, minf(start, finish), maxf(start, finish), 24, Color(0.95, 0.15, 0.1, 0.8), 3)
		# Glare (0.16): a dazzled fighter does not see its aim line.
		var aim: float = -deg_to_rad(drawn_effective_angle()) if facing > 0 else PI + deg_to_rad(drawn_effective_angle())
		for i in range(2, 12):
			if i % 2 == 0 and not has_status("ofuscado"):
				draw_line(origin + Vector2.from_angle(aim) * (i * 6), origin + Vector2.from_angle(aim) * (i * 6 + 5), Color("ffe95a"), 2)
	if active:
		var top: float = -monster_height - 20.0 if is_monster else -body_size.y - 18.0
		var bob: float = sin(pulse * 5.0) * 3.0
		draw_colored_polygon(PackedVector2Array([Vector2(-8, top + bob), Vector2(8, top + bob), Vector2(0, top + 10 + bob)]), Color("4aa8ff"))
		draw_polyline(PackedVector2Array([Vector2(-8, top + bob), Vector2(8, top + bob), Vector2(0, top + 10 + bob), Vector2(-8, top + bob)]), Color("0f2a5a"), 2)
	if shield < 1.0:
		var guard_center: Vector2 = Vector2(0, -monster_height * 0.5) if is_monster else Vector2(0, -body_size.y / 2)
		draw_arc(guard_center, maxf(body_size.x, body_size.y) / 2 + 8, 0, TAU, 40, Color(0.4, 0.85, 1.0, 0.8), 3)
	if empower > 1.0:
		# War cry: a red pulse around the feet until the next attack.
		var beat: float = 0.5 + 0.5 * sin(pulse * 8.0)
		draw_set_transform(Vector2(0, -2), 0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, body_size.x * 0.6 + 10.0 + beat * 4.0, 0, TAU, 32, Color(1.0, 0.3, 0.2, 0.8), 4.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var y: float = 6.0
	draw_rect(Rect2(-26, y, 52, 6), Color("1a0f08"))
	draw_rect(Rect2(-25, y + 1, 50.0 * hp / maxf(1, max_hp), 4), color)
	var badge: String = "%02d" % level
	draw_rect(Rect2(-40, y + 9, 20, 15), Color("1f4fb0"))
	draw_rect(Rect2(-40, y + 9, 20, 15), Color("a8dcff"), false, 1)
	draw_string_outline(font, Vector2(-39, y + 21), badge, HORIZONTAL_ALIGNMENT_CENTER, 18, UiKit.fs(12), 3, Color("0f1a3a"))
	draw_string(font, Vector2(-39, y + 21), badge, HORIZONTAL_ALIGNMENT_CENTER, 18, UiKit.fs(12), Color("ffd46b"))
	draw_string_outline(font, Vector2(-18, y + 21), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(13), 4, Color("10141f"))
	draw_string(font, Vector2(-18, y + 21), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(13), color.lightened(0.3))
	draw_string_outline(font, Vector2(-18, y + 35), rank_title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(11), 3, Color("10141f"))
	draw_string(font, Vector2(-18, y + 35), rank_title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(11), Color(str(elite.color)).lightened(0.25) if not elite.is_empty() else Color("9aff7a"))
	if not elite.is_empty():
		var badge_icon: Texture2D = StatusRules.icon_path(str(elite.get("icon", "")))
		if badge_icon != null:
			draw_texture_rect(badge_icon, Rect2(-38, y + 25, 14, 14), false)
	draw_status_row(font, y + 40)

# ---------- status effects and elites (0.16) ----------

func shown_size() -> Vector2:
	# The body as drawn (elites are drawn bigger).
	var scale: Vector2 = visual.scale if is_instance_valid(visual) else Vector2.ONE
	return Vector2(body_size.x, monster_height if is_monster else body_size.y) * scale

func draw_status_row(font: Font, y: float) -> void:
	# Small icons under the name with the turns left (and the poison doses).
	var list: Array = StatusRules.listed(self)
	if list.is_empty():
		return
	var step: float = 17.0
	var x: float = -list.size() * step / 2.0
	for pair: Array in list:
		var id: String = pair[0]
		var entry: Dictionary = pair[1]
		var rect: Rect2 = Rect2(x, y, 16, 16)
		draw_rect(rect.grow(1), Color(0.05, 0.03, 0.02, 0.75))
		var texture: Texture2D = StatusRules.icon(id)
		if texture != null:
			draw_texture_rect(texture, rect, false)
		else:
			draw_rect(rect.grow(-3), StatusRules.color(id))
		var count: int = int(entry.get("stacks", 1)) if id == "veneno" else int(entry.get("turns", 0))
		if count > 1:
			draw_string_outline(font, Vector2(x + 9, y + 18), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(10), 3, Color("10141f"))
			draw_string(font, Vector2(x + 9, y + 18), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(10), Color.WHITE)
		x += step

func draw_elite_aura() -> void:
	# An elite glows in its affix colour: a throbbing ring on the ground and motes rising.
	var tint: Color = Color(str(elite.get("color", "ffd04a")))
	var size: Vector2 = shown_size()
	var beat: float = 0.5 + 0.5 * sin(pulse * 4.0)
	var radius: float = size.x * 0.6 + 10.0
	draw_set_transform(Vector2(0, -2), 0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, radius + 6.0, Color(tint, 0.14 + 0.08 * beat))
	draw_arc(Vector2.ZERO, radius + beat * 4.0, 0, TAU, 40, Color(tint, 0.9), 4.0)
	draw_arc(Vector2.ZERO, radius * 0.7, pulse * 1.5, pulse * 1.5 + PI * 1.3, 24, Color(tint.lightened(0.4), 0.6), 3.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for i in range(8):
		var t: float = fposmod(pulse * 0.6 + i / 8.0, 1.0)
		var p: Vector2 = Vector2(sin(i * 2.3 + pulse * 0.8) * size.x * 0.55, -size.y * 1.05 * t).snapped(Vector2(2, 2))
		draw_rect(Rect2(p, Vector2(2, 2) if i % 3 else Vector2(4, 4)), Color(tint.lightened(0.35), 0.9 * (1.0 - t)))

func draw_overlay() -> void:
	# Each status effect over the body, on the 2 px art grid.
	if hp <= 0 or not is_instance_valid(visual) or not visual.visible:
		return
	var size: Vector2 = shown_size()
	var w: float = size.x
	var h: float = size.y
	for pair: Array in StatusRules.listed(self):
		var id: String = pair[0]
		var tint: Color = StatusRules.color(id)
		match id:
			"queimacao":
				# Flames licking up over the body.
				for i in range(6):
					var t: float = fposmod(pulse * 1.6 + i * 0.19, 1.0)
					var fx: float = (i - 2.5) * w * 0.14 + sin(pulse * 6.0 + i) * 2.0
					var p: Vector2 = Vector2(fx, -h * (0.15 + 0.7 * t)).snapped(Vector2(2, 2))
					var s: float = snappedf(6.0 * (1.0 - t) + 2.0, 2.0)
					overlay.draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), Color(1.0, 0.55 + 0.4 * (1.0 - t), 0.15, 0.85 * (1.0 - t)))
			"veneno":
				# Green bubbles rising and popping, more with every dose, and a sick tint
				# pulsing over the body.
				var doses: int = int(statuses[id].get("stacks", 1))
				for i in range(4 + doses * 2):
					var t: float = fposmod(pulse * 0.8 + i * 0.19, 1.0)
					var p: Vector2 = Vector2(sin(i * 1.9) * w * 0.42 + sin(pulse * 3.0 + i) * 3.0, -h * (0.1 + 1.0 * t) - 4.0).snapped(Vector2(2, 2))
					var r: float = 4.0 if t < 0.6 else 6.0
					overlay.draw_rect(Rect2(p - Vector2(r, r) / 2.0 - Vector2(1, 1), Vector2(r + 2, r + 2)), Color(0.05, 0.2, 0.02, 0.6 * (1.0 - t)))
					overlay.draw_rect(Rect2(p - Vector2(r, r) / 2.0, Vector2(r, r)), Color(tint.r, tint.g, tint.b, 0.95 * (1.0 - t * 0.5)))
					overlay.draw_rect(Rect2(p - Vector2(r, r) / 2.0, Vector2(2, 2)), Color(0.9, 1.0, 0.8, 0.9 * (1.0 - t)))
					if t > 0.9:
						for dx: float in [-6.0, 4.0]:
							overlay.draw_rect(Rect2(p + Vector2(dx, -2), Vector2(2, 2)), Color(tint.lightened(0.4), 0.8))
			"congelado":
				# Encased in a faceted crystal of ice, with shards spiking out of the top.
				var tall: float = maxf(h, 46.0) * 1.05
				var half: float = maxf(w * 0.6 + 6.0, 24.0)
				var crystal: PackedVector2Array = PackedVector2Array()
				var corners: Array[Vector2] = [Vector2(-1.0, 0.0), Vector2(-1.08, -0.45), Vector2(-0.78, -0.9), Vector2(-0.35, -1.12), Vector2(0.1, -0.98), Vector2(0.45, -1.18), Vector2(0.86, -0.85), Vector2(1.06, -0.4), Vector2(0.98, 0.0)]
				for corner: Vector2 in corners:
					crystal.append(Vector2(corner.x * half, corner.y * tall + 2.0).snapped(Vector2(2, 2)))
				# Snapping can flatten a corner: only fill what still triangulates.
				if not Geometry2D.triangulate_polygon(crystal).is_empty():
					overlay.draw_colored_polygon(crystal, Color(0.62, 0.88, 1.0, 0.32))
				overlay.draw_polyline(crystal + PackedVector2Array([crystal[0]]), Color("1a3a5a"), 4.0)
				overlay.draw_polyline(crystal + PackedVector2Array([crystal[0]]), Color(0.86, 0.97, 1.0, 0.95), 2.0)
				# Facets from a bright core.
				var core: Vector2 = Vector2(-half * 0.15, -tall * 0.55).snapped(Vector2(2, 2))
				for k: int in [1, 3, 5, 7]:
					overlay.draw_line(core, crystal[k], Color(1, 1, 1, 0.45), 2.0)
				var facet: PackedVector2Array = PackedVector2Array([crystal[2], crystal[3], core])
				if not Geometry2D.triangulate_polygon(facet).is_empty():
					overlay.draw_colored_polygon(facet, Color(1, 1, 1, 0.18))
				for k in range(3):
					var shine: Vector2 = Vector2(sin(pulse * 1.3 + k * 2.1) * half * 0.6, -tall * (0.3 + 0.2 * k)).snapped(Vector2(2, 2))
					overlay.draw_rect(Rect2(shine, Vector2(2, 2)), Color(1, 1, 1, 0.5 + 0.5 * sin(pulse * 5.0 + k)))
			"exaustao":
				# Big sweat drops flying off the head.
				for i in range(4):
					var t: float = fposmod(pulse * 1.0 + i * 0.25, 1.0)
					var side: float = -1.0 if i % 2 == 0 else 1.0
					var p: Vector2 = Vector2(side * (w * 0.2 + t * 14.0), -h - 8.0 - sin(t * PI) * 10.0 + t * 12.0).snapped(Vector2(2, 2))
					var fade: float = 1.0 - t
					overlay.draw_rect(Rect2(p + Vector2(-1, -1), Vector2(6, 8)), Color(0.05, 0.1, 0.2, 0.6 * fade))
					overlay.draw_rect(Rect2(p + Vector2(0, 2), Vector2(4, 4)), Color(0.55, 0.8, 1.0, fade))
					overlay.draw_rect(Rect2(p + Vector2(1, 0), Vector2(2, 2)), Color(0.7, 0.9, 1.0, fade))
					overlay.draw_rect(Rect2(p + Vector2(0, 2), Vector2(2, 2)), Color(1, 1, 1, fade))
			"selado":
				# A rune ring turning over the head.
				var c: Vector2 = Vector2(0, -maxf(h, 40.0) - 18.0)
				overlay.draw_set_transform(c, 0, Vector2(1.0, 0.4))
				overlay.draw_arc(Vector2.ZERO, 16.0, 0, TAU, 28, Color(tint, 0.9), 2.0)
				overlay.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				for i in range(6):
					var a: float = pulse * 2.0 + TAU * i / 6.0
					var p: Vector2 = (c + Vector2(cos(a) * 16.0, sin(a) * 6.4)).snapped(Vector2(2, 2))
					overlay.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), tint.lightened(0.3))
			"enraizado":
				# Roots grown up around the feet.
				for i in range(7):
					var x: float = snappedf((i - 3) * w * 0.17, 2.0)
					var tall: float = 8.0 + float((i * 5) % 4) * 3.0 + sin(pulse * 2.0 + i) * 1.5
					var bend: float = 3.0 if i % 2 == 0 else -3.0
					var points: PackedVector2Array = PackedVector2Array([Vector2(x, 2), Vector2(x + bend, -tall * 0.5), Vector2(x - bend * 0.5, -tall)])
					overlay.draw_polyline(points, Color("5a3a1a"), 4.0)
					overlay.draw_polyline(points, tint, 2.0)
					if i % 3 == 0:
						overlay.draw_rect(Rect2(Vector2(x - bend * 0.5, -tall).snapped(Vector2(2, 2)) + Vector2(0, -2), Vector2(4, 2)), Color("6ac84a"))
			"marcado":
				# A red crosshair locked on the body.
				var c: Vector2 = Vector2(0, -h * 0.5)
				var r: float = maxf(12.0, minf(w, h) * 0.45) + 2.0 * sin(pulse * 6.0)
				overlay.draw_arc(c, r, 0, TAU, 32, Color(tint, 0.85), 2.0)
				for k in range(4):
					var dir: Vector2 = Vector2.from_angle(pulse * 0.8 + k * PI / 2.0)
					overlay.draw_line(c + dir * (r - 5.0), c + dir * (r + 6.0), tint, 2.0)
			"ofuscado":
				# Sparkles of glare around the head.
				for i in range(4):
					var t: float = fposmod(pulse * 1.3 + i * 0.25, 1.0)
					var p: Vector2 = Vector2(cos(i * 1.7 + pulse) * w * 0.4, -h * 0.9 + sin(i * 2.1 + pulse) * 8.0).snapped(Vector2(2, 2))
					var s: float = snappedf(2.0 + 6.0 * sin(t * PI), 2.0)
					overlay.draw_rect(Rect2(p - Vector2(s, 2) / 2.0, Vector2(s, 2)), Color(tint, 0.95))
					overlay.draw_rect(Rect2(p - Vector2(2, s) / 2.0, Vector2(2, s)), Color(tint, 0.95))
