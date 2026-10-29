extends Node
## Small original synthesized sound palette. No external audio assets.
var muted := false
var sounds: Dictionary = {}

func _ready() -> void:
	for id in ["fire", "boom", "jump", "turn", "splash", "click", "win"]:
		sounds[id] = make_sound(id)

func play(id: String) -> void:
	if muted or not sounds.has(id):
		return
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.stream = sounds[id]
	p.volume_db = -9.0 if id == "boom" else -15.0
	p.finished.connect(p.queue_free)
	p.play()

func make_sound(id: String) -> AudioStreamWAV:
	var duration: float = {"fire": 0.18, "boom": 0.65, "jump": 0.16, "turn": 0.34, "splash": 0.4, "click": 0.05, "win": 0.7}[id]
	var rate := 22050
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	var phase := 0.0
	for i in int(duration * rate):
		var t := float(i) / rate
		var q := t / duration
		var freq := 180.0
		var noise := 0.0
		match id:
			"fire":
				freq = lerpf(230, 65, q)
				noise = 0.45
			"boom":
				freq = lerpf(90, 28, q)
				noise = 0.8
			"jump": freq = lerpf(220, 700, q)
			"turn": freq = 440.0 if q < 0.45 else 660.0
			"splash":
				freq = lerpf(600, 90, q)
				noise = 0.75
			"click": freq = 900.0
			"win": freq = [440.0, 550.0, 660.0, 880.0][mini(3, int(q * 4))]
		phase += TAU * freq / rate
		var sample := (sin(phase) * (1.0 - noise) + rng.randf_range(-1, 1) * noise) * pow(1.0 - q, 1.7) * minf(1.0, t * 200.0)
		var value := int(clampf(sample, -1, 1) * 26000)
		data.append(value & 255)
		data.append((value >> 8) & 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
