class_name PixelAnimation
extends Sprite2D

var frames: Array[Texture2D] = []
var clip: String = ""
var frame_index: int = 0
var fps: float = 7.0
var elapsed: float = 0.0
var frozen: bool = false
# Play forward then backward, for clips that do not loop back to their first pose.
var pingpong: bool = false
# One-shot clips (the POW burst) stop on their last frame.
var loop: bool = true

func _ready() -> void:
	add_to_group("pixel_animations")

func load_frames(folder: String, count: int, height: float) -> void:
	clip = folder.get_file()
	for i in range(count):
		var path: String = "%s/frame_%02d.png" % [folder, i]
		if ResourceLoader.exists(path):
			frames.append(load(path))
	if frames.is_empty():
		return
	texture = frames[0]
	scale = Vector2.ONE * height / texture.get_height()
	var bottom: float = texture.get_image().get_used_rect().end.y
	position.y = height * 0.5 - bottom * scale.y

func _process(delta: float) -> void:
	if frozen or frames.is_empty():
		return
	elapsed += delta
	var step: int = int(elapsed * fps)
	var count: int = frames.size()
	if pingpong and count > 2:
		var period: int = count * 2 - 2
		var k: int = step % period
		frame_index = k if k < count else period - k
	elif not loop:
		frame_index = mini(step, count - 1)
	else:
		frame_index = step % count
	texture = frames[frame_index]
