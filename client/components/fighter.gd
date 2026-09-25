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
var frozen: int = 0
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
var attack_time: float = 0.0
var walk_time: float = 0.0
var pulse: float = 0.0
var east_texture: Texture2D
var west_texture: Texture2D
var south_texture: Texture2D
var prone: bool = false
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
	for clip: PixelAnimation in [idle_animation, walk_animation, attack_animation]:
		if not clip.frames.is_empty():
			rig.style(clip, clip.clip)
	rig.source = shown_body
	update_pose()

func shown_body() -> Dictionary:
	# The sprite currently drawn and, for clips, how far its head moved from the static pose.
	if rig == null:
		return {}
	for clip: PixelAnimation in [idle_animation, walk_animation, attack_animation]:
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

func show_animation(animation: PixelAnimation) -> void:
	# Falls back to the idle loop (or the static sprite) when a clip has no frames.
	var chosen: PixelAnimation = animation if is_instance_valid(animation) and not animation.frames.is_empty() else idle_animation
	for clip: PixelAnimation in [idle_animation, walk_animation, attack_animation]:
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
	update_pose()

static func rank_for(value: int) -> String:
	var ranks: Array[String] = ["Recruta", "Soldado", "Veterano", "Sargento", "Capitão", "Major", "Coronel", "General", "Marechal"]  # i18n
	return Lang.t(ranks[clampi((value - 1) / 4, 0, ranks.size() - 1)])

func alive() -> bool:
	return hp > 0

func animate_attack() -> void:
	turns_taken += 1
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
		queue_redraw()
		return
	for clip: PixelAnimation in [idle_animation, walk_animation, attack_animation]:
		if is_instance_valid(clip):
			clip.flip_h = facing < 0
	if prone:
		body.flip_h = facing < 0
	else:
		body.texture = east_texture if facing == 1 else west_texture
		body.region_rect = Rect2(body.texture.get_image().get_used_rect())
		body.position.y = -body_size.y / 2 + (sin(pulse * 3.0) * 1.0 if gender == "f" else 0.0)
	modulate = Color("b8e8ff") if frozen > 0 else Color.WHITE
	queue_redraw()

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
	if attack_time > 0:
		attack_time -= delta
		if attack_time <= 0:
			show_animation(idle_animation)
	elif walk_time > 0:
		walk_time -= delta
		if walk_time <= 0:
			show_animation(idle_animation)
	if hp <= 0:
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
	if walk_time <= 0 and attack_time <= 0 and is_instance_valid(walk_animation) and not walk_animation.frames.is_empty():
		show_animation(walk_animation)
	walk_time = 0.15
	tilt = terrain.slope_degrees(position.x, position.y)
	update_pose()
	return true

func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	stats.taken += amount
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
	queue_redraw()

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
	if active and not is_monster:
		var origin: Vector2 = pivot()
		var lo: float = angle_range.x + tilt * facing
		var hi: float = angle_range.y + tilt * facing
		var start: float = -deg_to_rad(lo) if facing > 0 else PI + deg_to_rad(lo)
		var finish: float = -deg_to_rad(hi) if facing > 0 else PI + deg_to_rad(hi)
		draw_arc(origin, 46, minf(start, finish), maxf(start, finish), 24, Color(0.95, 0.15, 0.1, 0.8), 3)
		var aim: float = -deg_to_rad(drawn_effective_angle()) if facing > 0 else PI + deg_to_rad(drawn_effective_angle())
		for i in range(2, 12):
			if i % 2 == 0:
				draw_line(origin + Vector2.from_angle(aim) * (i * 6), origin + Vector2.from_angle(aim) * (i * 6 + 5), Color("ffe95a"), 2)
	if active:
		var top: float = -monster_height - 20.0 if is_monster else -body_size.y - 18.0
		var bob: float = sin(pulse * 5.0) * 3.0
		draw_colored_polygon(PackedVector2Array([Vector2(-8, top + bob), Vector2(8, top + bob), Vector2(0, top + 10 + bob)]), Color("4aa8ff"))
		draw_polyline(PackedVector2Array([Vector2(-8, top + bob), Vector2(8, top + bob), Vector2(0, top + 10 + bob), Vector2(-8, top + bob)]), Color("0f2a5a"), 2)
	if shield < 1.0:
		draw_arc(Vector2(0, -body_size.y / 2), maxf(body_size.x, body_size.y) / 2 + 8, 0, TAU, 40, Color(0.4, 0.85, 1.0, 0.8), 3)
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
	draw_string(font, Vector2(-18, y + 35), rank_title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.fs(11), Color("9aff7a"))
