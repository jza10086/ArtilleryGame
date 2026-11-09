extends Node
## Present host-issued sound events through the blank template's scoped audio component.
@export var engine_cue: PartyAudioCue
@export var fire_cues: Array[PartyAudioCue] = []
@export var impact_cues: Array[PartyAudioCue] = []
@export var cluster_split: PartyAudioCue
@export var rain_split: PartyAudioCue
@export var bounce_cue: PartyAudioCue
@export var drill_cue: PartyAudioCue
@export var mine_arm: PartyAudioCue
@export var black_hole_cue: PartyAudioCue = preload("res://games/minigame/godot_party_default_artillery_game/audio/event_black_hole.tres")
@export var portal_cue: PartyAudioCue = preload("res://games/minigame/godot_party_default_artillery_game/audio/event_portal.tres")
@export var amplifier_cue: PartyAudioCue = preload("res://games/minigame/godot_party_default_artillery_game/audio/event_amplifier.tres")
@export var supply_cue: PartyAudioCue = preload("res://games/minigame/godot_party_default_artillery_game/audio/event_supply.tres")
@onready var mixer: PartyGameAudio = $GameAudio
@onready var engine: AudioStreamPlayer = $Engine
var last_event: int = 0
var initialized: bool = false
var enabled: bool = false
var move_left: float = 0.0
var engine_gain: float = 0.0

func _ready() -> void:
	assert(engine_cue != null and engine_cue.validate() == OK)
	assert(fire_cues.size() == 16 and impact_cues.size() == 16)
	for cue: PartyAudioCue in fire_cues + impact_cues + [cluster_split, rain_split, bounce_cue, drill_cue, mine_arm, black_hole_cue, portal_cue, amplifier_cue, supply_cue]:
		assert(cue != null and cue.validate() == OK)
	engine.stream = engine_cue.playback_stream()
	engine.pitch_scale = engine_cue.pitch_scale

func start() -> void:
	mixer.route_player(engine, PartyGameAudio.Category.SFX)
	enabled = true

func finish() -> void:
	enabled = false
	move_left = 0.0
	engine_gain = 0.0
	engine.stop()

func close() -> void:
	finish()
	mixer.close_scope()

func _process(delta: float) -> void:
	if not enabled:
		return
	move_left = maxf(0.0, move_left - delta)
	var target: float = 1.0 if move_left > 0.0 else 0.0
	engine_gain = move_toward(engine_gain, target, delta / (0.06 if target > 0.0 else 0.14))
	if engine_gain > 0.0:
		engine.volume_db = engine_cue.volume_db + linear_to_db(engine_gain)
		if not engine.playing:
			engine.play()
	elif engine.playing:
		engine.stop()

## Consume each authoritative event once. Fresh views never replay retained history.
func update_state(snapshot: Dictionary) -> Error:
	if not initialized:
		initialized = true
		if not snapshot.audio_events.is_empty():
			last_event = snapshot.audio_events.back().id
		return OK
	if snapshot.phase != "aim":
		move_left = 0.0
	for event: Dictionary in snapshot.audio_events:
		if event.id <= last_event:
			continue
		last_event = event.id
		if not enabled:
			continue
		var cue: PartyAudioCue
		match event.kind:
			"move":
				if snapshot.phase == "aim":
					move_left = 0.20
				continue
			"reset":
				move_left = 0.0
				engine_gain = 0.0
				mixer.stop_all()
				continue
			"fire":
				cue = fire_cues[event.weapon]
			"impact":
				cue = impact_cues[event.weapon]
			"split":
				cue = cluster_split if event.weapon == 3 else rain_split
			"bounce":
				cue = bounce_cue
			"drill":
				cue = drill_cue
			"arm":
				cue = mine_arm
			"black_hole":
				cue = black_hole_cue
			"portal":
				cue = portal_cue
			"amplifier":
				cue = amplifier_cue
			"supply":
				cue = supply_cue
			_:
				push_error("Unknown artillery audio event: " + event.kind)
				return ERR_INVALID_DATA
		var handle: PartyAudioHandle = mixer.play_sfx(cue)
		if handle.error != OK:
			finish()
			return handle.error
	return OK
