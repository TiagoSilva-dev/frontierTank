class_name GameAudio
extends Node

var enabled: bool = true

func tone(frequency: float, duration: float, noisy: bool = false) -> void:
	if not enabled:
		return
	var sample_rate: int = 22050
	var count: int = int(duration * sample_rate)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = 17
	for i in range(count):
		var t: float = float(i) / sample_rate
		var envelope: float = pow(1.0 - float(i) / count, 2)
		var sample: float = sin(TAU * frequency * t * (1.0 - t * 0.7))
		if noisy:
			sample = sample * 0.3 + noise.randf_range(-1, 1) * 0.7
		bytes.encode_s16(i * 2, int(sample * envelope * 11000))
	var wave: AudioStreamWAV = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = sample_rate
	wave.data = bytes
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = wave
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
