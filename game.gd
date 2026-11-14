extends Control

## Owners control movement and aim immediately; the host resolves shared combat outcomes.
const CombatAudio: Script = preload("res://games/minigame/gp_artillery/combat_audio.gd")
const Battle: Script = preload("res://games/minigame/gp_artillery/battle.gd")
const Battlefield: Script = preload("res://games/minigame/gp_artillery/battlefield.gd")
const ACTION: StringName = &"artillery/action"
const EVENTS: StringName = &"artillery/events"
const POSE: StringName = &"artillery/pose"
const ProjectileMotion: Script = preload("res://games/minigame/gp_artillery/projectile_motion.gd")
const POSE_FIELDS: Array[String] = ["x", "y", "tilt", "fuel", "aim"]
const FINAL: StringName = &"artillery/final"
var api: PartyAPI
var request: Dictionary
var battle: RefCounted = Battle.new()
@onready var board: Control = %Battlefield
var state: Dictionary = {}
var running: bool = false
var stopped: bool = false
var finished: bool = false
var preview: bool = false
var local_id: String = ""
var revision: int = 0
var network_time: float = 0.0
var _published_facts: Dictionary = {}
var _published_tanks: Array = []
var _published_terrain: PackedFloat32Array = PackedFloat32Array()
var _published_shots: Dictionary = {}
var _event_ids: Dictionary = {}
var _environment_id: int = 0
var _published_environment: Dictionary = {}
var _environment: Dictionary = {}
var _shots: Dictionary = {}
var _pose_sequence: int = 0
var _received_poses: Dictionary[String, int] = {}
var _last_pose: Dictionary = {}
var _pose_time: float = 0.0
var _pose_settle_left: float = 0.0
var _simulation_time: float = 0.0
var _host_moved: bool = false
var _phase_key: String = ""
var _phase_end_msec: int = 0
var last_turn: int = -1
var last_pose_epoch: int = -1
var selected: int = 0
var pending_fire: bool = false
var held_direction: int = 0
var mouse_aiming: bool = false
var display_time: float = 0.0
@onready var ammo_cards: HBoxContainer = %AmmoCards
@onready var top_status: VBoxContainer = %TopStatus
@onready var countdown: Label = %Countdown
@onready var wind_arrow: Polygon2D = %WindArrow
@onready var wind_strength: Label = %WindStrength
@onready var angle_slider: HSlider = %AngleSlider
@onready var power_slider: HSlider = %PowerSlider
@onready var angle_label: Label = %AngleLabel
@onready var power_label: Label = %PowerLabel
@onready var fuel_label: Label = %FuelLabel
@onready var weapon_button: Button = %WeaponButton
@onready var fire_button: Button = %FireButton
@onready var left_button: Button = %LeftButton
@onready var right_button: Button = %RightButton
@onready var pass_button: Button = %PassButton
@onready var reset_button: Button = %ResetButton
@onready var finish_button: Button = %FinishButton
@onready var arsenal: PanelContainer = %Arsenal
var weapon_buttons: Array[Button] = []
@onready var hud: MarginContainer = %Hud
@export var briefing: Control
@export var settlement: Control
var final_result: Dictionary = {}
@onready var combat_audio: CombatAudio = %CombatAudio

func godot_party_audio_target() -> PartyGameAudio:
	return %CombatAudio.get_node("GameAudio")

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	%CombatAudio.get_node("GameAudio").prepare_scope()
	api = value
	request = config.duplicate(true)
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)
	for player: Dictionary in api.get_players():
		if player.is_local:
			local_id = player.player_id

func _ready() -> void:
	board.extrapolate_physics = api == null or api.is_host()
	add_to_group("party_minimal_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	weapon_button.pressed.connect(func() -> void: arsenal.visible = not arsenal.visible)
	fire_button.pressed.connect(_fire)
	pass_button.pressed.connect(_send.bind("pass"))
	reset_button.pressed.connect(_send.bind("reset"))
	finish_button.pressed.connect(_send.bind("finish"))
	weapon_buttons.assign(arsenal.get_child(0).get_children())
	for index: int in weapon_buttons.size():
		weapon_buttons[index].pressed.connect(_select.bind(index))
	if api == null:
		preview = true
		combat_audio.start()
		var sample: Array[Dictionary] = [
			{"player_id": "preview", "name": "试射坦克", "color": "71ddff"}]
		battle.setup(sample, 5930, "training")
		_receive_state(battle.state.duplicate(true))
		return
	var players: Array[Dictionary] = []
	for player: Dictionary in api.get_players():
		var appearance: Dictionary = api.get_appearance(player.player_id)
		players.append({"player_id": player.player_id, "name": player.name, "color": appearance.color})
	var mode: String = api.get_settings().mode
	if (mode == "training" and players.size() != 1) or (mode == "teams" and (players.size() % 2 != 0 or players.size() < 2)) or (mode == "ffa" and players.size() < 2):
		_fail("invalid_roster", "所选模式与参赛人数不符")
		return
	battle.setup(players, api.get_seed(), mode, api.get_settings())
	_receive_state(battle.state.duplicate(true))
	var content: Dictionary = briefing.read_content(get_script().resource_path.get_base_dir().path_join("manifest.json"), api)
	content["controls"] = [{"binding": "A / D · W / S · Q / E", "description": "按住移动 · 调整角度 · 减小 / 增大力度"},
		{"binding": "鼠标左键长按", "description": "同时调整角度与力度，使弹道靠近指针；Space / 开火按钮发射；1–8 快选弹药；Esc 菜单"}]
	briefing.configure(api, content)
	briefing.play_requested.connect(_begin)
	var error: Error = api.mark_ready()
	if error != OK:
		_fail("ready_failed", error_string(error))

func party_start() -> void:
	briefing.transport_started()

func _begin() -> void:
	combat_audio.start()
	running = true
	_sync_ui()
	if api.is_host():
		_publish()

func _physics_process(delta: float) -> void:
	if not running or stopped:
		return
	if api.is_host():
		_simulation_time += delta
		while _simulation_time >= ProjectileMotion.STEP:
			battle.step(ProjectileMotion.STEP)
			_simulation_time -= ProjectileMotion.STEP
		network_time += delta
		if network_time >= 0.05 or battle.state.phase == "over":
			network_time = 0.0
			_publish()
		else:
			# Local presentation follows physics, independently of the network send rate.
			_receive_state(battle.state.duplicate(true))

func _process(delta: float) -> void:
	if state.is_empty():
		return
	if _can_act() and not arsenal.visible:
		var move_axis: int = int(api.input.is_pressed(&"move_right") or right_button.is_pressed()) - int(api.input.is_pressed(&"move_left") or left_button.is_pressed())
		var angle_axis: float = float(api.input.is_pressed(&"artillery_angle_up")) - float(api.input.is_pressed(&"artillery_angle_down"))
		var power_axis: float = float(api.input.is_pressed(&"artillery_power_up")) - float(api.input.is_pressed(&"artillery_power_down"))
		_apply_controls(delta, move_axis, angle_axis, power_axis)
		if mouse_aiming and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_aim_mouse(board.get_local_mouse_position() * Vector2(1920, 1080) / board.size)
		else:
			mouse_aiming = false
	else:
		if held_direction != 0 and not local_id.is_empty() and Battle.can_act(state, _view_tank()):
			_flush_pose(true)
		held_direction = 0
		mouse_aiming = false
	if _can_act():
		state.tanks[_view_tank()].aim = angle_slider.value
		_pose_time += delta
		if _pose_settle_left > 0.0:
			_pose_settle_left = maxf(0.0, _pose_settle_left - delta)
			if _pose_settle_left == 0.0:
				_flush_pose(true)
		if _pose_time >= 0.05:
			_flush_pose(false)
	board.local_tank = _view_tank() if not local_id.is_empty() else -1
	board.aim_angle = angle_slider.value
	board.aim_power = power_slider.value
	board.weapon = selected
	board.aim_tank = _view_tank()
	board.show_aim = _can_act() or preview
	_sync_labels()
	if state.phase == "aim" and state.mode != "training":
		display_time = maxf(0.0, float(_phase_end_msec - api.net.host_time_msec()) / 1000.0)
	if not preview and not api.is_host():
		_animate_projectiles()
		_animate_environment()
	_sync_status()

## Input is applied locally every render frame; peers receive bounded pose samples.
func _apply_controls(delta: float, direction: int, angle_axis: float, power_axis: float) -> void:
	if not _can_act() or arsenal.visible:
		return
	angle_slider.value += angle_axis * 40.0 * delta
	power_slider.value += power_axis * 32.0 * delta
	if direction != 0:
		var before_x: float = state.tanks[_view_tank()].x
		var index: int = _view_tank()
		if api.is_host():
			_host_moved = battle.move_tank(battle.state.tanks[index], float(direction) * 100.0 * delta) or _host_moved
			state.tanks[index] = battle.state.tanks[index].duplicate(true)
		else:
			battle.state = state
			battle.move_tank(state.tanks[index], float(direction) * 100.0 * delta)
		if not is_equal_approx(before_x, float(state.tanks[index].x)):
			combat_audio.move_left = 0.2
	if direction == 0 and held_direction != 0:
		_flush_pose(true)
	held_direction = direction

func _pose_values() -> Dictionary:
	var tank: Dictionary = state.tanks[_view_tank()]
	return {"player": local_id, "turn": state.turn, "epoch": tank.pose_epoch,
		"x": float(tank.x), "fuel": float(tank.fuel), "aim": float(angle_slider.value)}

func _flush_pose(reliable: bool) -> Dictionary:
	var values: Dictionary = _pose_values()
	_pose_time = 0.0
	if not reliable and values == _last_pose:
		return {}
	_last_pose = values.duplicate()
	_pose_settle_left = 0.0 if reliable else 0.15
	_pose_sequence += 1
	values["sequence"] = _pose_sequence
	var message: Dictionary = {"session": api.session_id, "scope": api.scope_id, "pose": values}
	if api.is_host():
		_accept_pose(local_id, values)
		if _host_moved:
			_host_moved = false
			battle.movement_effects(_view_tank())
	var mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var error: Error = api.net.send_to_group(POSE, message, mode, "instance", false, 0 if reliable else 1)
	if error != OK:
		_fail("pose_send_failed", error_string(error))
	return values

func _valid_pose(value: Variant) -> bool:
	if not value is Dictionary or not value.get("player") is String or not value.get("turn") is int or not value.get("epoch") is int or not value.get("sequence") is int:
		return false
	for key: String in ["x", "fuel", "aim"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(float(value[key])):
			return false
	return value.x >= 40.0 and value.x <= Battle.WIDTH - 40.0 and value.fuel >= 0.0 and value.fuel <= 90.0 and value.aim >= 0.0 and value.aim <= 180.0

## Trust ownership, not arbitrary sender IDs. Epochs reject movement predating a fall or teleport.
func _accept_pose(actor: String, value: Dictionary) -> void:
	var snapshot: Dictionary = battle.state if api.is_host() else state
	if value.player != actor or value.turn != snapshot.turn or value.sequence <= int(_received_poses.get(actor, -1)):
		return
	for index: int in snapshot.tanks.size():
		var tank: Dictionary = snapshot.tanks[index]
		if tank.id != actor:
			continue
		if value.epoch != tank.pose_epoch or not Battle.can_act(snapshot, index):
			return
		_received_poses[actor] = value.sequence
		var moved: bool = not is_equal_approx(float(tank.x), float(value.x))
		tank.x = float(value.x)
		tank.fuel = float(value.fuel)
		tank.aim = float(value.aim)
		# All peers derive height and chassis tilt from the same terrain.
		if not api.is_host():
			battle.state = state
		battle._seat_on_ground(tank)
		if moved:
			combat_audio.move_left = 0.2
			if api.is_host():
				battle.movement_effects(index)
		return

func _sender_player(sender: Dictionary) -> String:
	for player: Dictionary in api.get_players():
		if player.connected and player.peer_id == sender.peer_id and player.player_id in sender.player_ids:
			return player.player_id
	return ""

func _aim_mouse(target: Vector2) -> void:
	var tank: Dictionary = state.tanks[_view_tank()].duplicate()
	var model: Node2D = board.models[_view_tank()]
	tank.x = model.position.x
	tank.y = model.position.y
	tank.tilt = model.rotation
	var aim: Vector2 = Battle.aim_at(state, tank, selected, target)
	angle_slider.value = aim.x
	power_slider.value = aim.y

func _sync_status() -> void:
	top_status.visible = preview or (running and not stopped and not finished)
	ammo_cards.visible = top_status.visible
	countdown.text = "∞" if state.mode == "training" else (str(ceili(display_time)) if state.phase == "aim" else "—")
	countdown.modulate = Color("#ff515b") if state.mode != "training" and state.phase == "aim" and display_time <= 10.0 else Color.WHITE
	wind_arrow.rotation = state.wind.angle()
	wind_strength.text = str(roundi(state.wind.length()))

## Publish only changed combat facts and trajectory segments; ordinary flight sends no samples.
func _publish() -> void:
	var current: Dictionary = battle.state
	var phase_key: String = "%d/%s" % [current.turn, current.phase]
	if phase_key != _phase_key:
		_phase_key = phase_key
		_phase_end_msec = api.net.host_time_msec() + roundi(float(current.time) * 1000.0)
	var facts: Dictionary = {}
	for key: String in ["mode", "turn", "round", "active_team", "active", "phase", "wind", "winner", "hazards", "notice"]:
		if not _published_facts.has(key) or _published_facts[key] != current[key]:
			facts[key] = current[key]
	if facts.has("phase") or facts.has("turn"):
		facts["end_msec"] = _phase_end_msec
	var tanks: Array[Dictionary] = []
	for index: int in current.tanks.size():
		var changes: Dictionary = {}
		var pose_changed_by_host: bool = _published_tanks.is_empty() or current.tanks[index].pose_epoch != _published_tanks[index].pose_epoch or current.tanks[index].acted != _published_tanks[index].acted
		for key: String in current.tanks[index]:
			if key in POSE_FIELDS:
				if pose_changed_by_host:
					changes[key] = current.tanks[index][key]
				continue
			if _published_tanks.is_empty() or current.tanks[index][key] != _published_tanks[index][key]:
				changes[key] = current.tanks[index][key]
		if not changes.is_empty():
			tanks.append({"index": index, "changes": changes})
	var terrain: Array = []
	if _published_terrain.is_empty():
		_published_terrain = state.terrain.duplicate()
	for index: int in current.terrain.size():
		if current.terrain[index] != _published_terrain[index]:
			terrain.append([index, current.terrain[index]])
	var environment_changes: Dictionary = _environment_changes(current.events)
	var events: Dictionary = {}
	for key: String in ["impacts", "health_feedback", "audio_events", "ammo_events"]:
		var additions: Array = []
		for event: Dictionary in current[key]:
			if event.id > int(_event_ids.get(key, 0)):
				additions.append(event)
		if not additions.is_empty():
			events[key] = additions
			_event_ids[key] = additions.back().id
	var spawned: Array[Dictionary] = []
	var removed: Array = []
	var alive: Dictionary = {}
	for shot: Dictionary in current.projectiles:
		var signature: Array = ProjectileMotion.signature(shot)
		alive[shot.id] = signature
		if not _published_shots.has(shot.id) or _published_shots[shot.id] != signature:
			spawned.append(ProjectileMotion.sample(shot, api.net.host_time_msec()))
	for id: int in _published_shots:
		if not alive.has(id):
			removed.append(id)
	if not facts.is_empty() or not tanks.is_empty() or not terrain.is_empty() or not events.is_empty() or not spawned.is_empty() or not removed.is_empty() or not environment_changes.upsert.is_empty() or not environment_changes.removed.is_empty():
		revision += 1
		var message: Dictionary = {"session": api.session_id, "scope": api.scope_id, "revision": revision,
			"facts": facts, "tanks": tanks, "terrain": terrain, "events": events, "spawned": spawned, "removed": removed, "environment": environment_changes}
		var error: Error = api.net.broadcast(EVENTS, message, MultiplayerPeer.TRANSFER_MODE_RELIABLE, false)
		if error != OK:
			_fail("events_send_failed", error_string(error))
			return
		for key: String in facts:
			if key != "end_msec":
				_published_facts[key] = current[key].duplicate(true) if current[key] is Array or current[key] is Dictionary else current[key]
		_published_tanks = current.tanks.duplicate(true)
		_published_terrain = current.terrain.duplicate()
		_published_shots = alive
	_receive_state(current.duplicate(true))
	if current.phase == "over" and not finished:
		var result: Dictionary = battle.result(request.request_id)
		var error: Error = api.net.broadcast(FINAL, {"session": api.session_id, "scope": api.scope_id, "result": result}, MultiplayerPeer.TRANSFER_MODE_RELIABLE, false)
		if error != OK:
			_fail("result_send_failed", error_string(error))
			return
		_open_result(result)

func _receive_events(payload: Dictionary) -> void:
	if not payload.get("revision") is int or payload.revision <= revision:
		return
	if not payload.get("facts") is Dictionary or not payload.get("events") is Dictionary or not payload.get("environment") is Dictionary:
		return
	for key: String in ["tanks", "terrain", "spawned", "removed"]:
		if not payload.get(key) is Array:
			return
	if not payload.environment.get("upsert") is Array or not payload.environment.get("removed") is Array:
		return
	for key: String in payload.facts:
		if key == "end_msec":
			if not payload.facts[key] is int:
				return
		elif key not in ["mode", "turn", "round", "active_team", "active", "phase", "wind", "winner", "hazards", "notice"] or typeof(payload.facts[key]) != typeof(state[key]):
			return
	for entry: Variant in payload.environment.upsert:
		if not entry is Dictionary or not entry.get("id") is int or not entry.get("pos") is Vector2 or not entry.pos.is_finite() or entry.get("kind") not in ["supply", "black_hole", "portal", "bumper", "amplifier", "drone"] or not entry.get("expires") is int:
			return
		if entry.kind == "supply" and (not entry.get("start_msec") is int or not (entry.get("land_y") is float or entry.get("land_y") is int) or not is_finite(float(entry.land_y))):
			return
	for id: Variant in payload.environment.removed:
		if not id is int:
			return
	for shot: Variant in payload.spawned:
		if not ProjectileMotion.valid(shot):
			return
	for id: Variant in payload.removed:
		if not id is int:
			return
	for key: String in payload.events:
		if key not in ["impacts", "health_feedback", "audio_events", "ammo_events"] or not payload.events[key] is Array:
			return
		for event: Variant in payload.events[key]:
			if not event is Dictionary or not event.get("id") is int:
				return
	# Messages are host-authored; array indices still cross an external boundary.
	for row: Variant in payload.tanks:
		if not row is Dictionary or not row.get("index") is int or row.index < 0 or row.index >= state.tanks.size() or not row.get("changes") is Dictionary:
			return
	for cell: Variant in payload.terrain:
		if not cell is Array or cell.size() != 2 or not cell[0] is int or cell[0] < 0 or cell[0] >= state.terrain.size() or not (cell[1] is float or cell[1] is int) or not is_finite(float(cell[1])):
			return
	for entry: Dictionary in payload.environment.upsert:
		_environment[entry.id] = entry.duplicate(true)
		if entry.kind == "supply":
			_environment[entry.id]["origin_y"] = entry.pos.y
	for id: int in payload.environment.removed:
		_environment.erase(id)
	state.events = _environment.values()
	revision = payload.revision
	if payload.facts.has("end_msec"):
		_phase_end_msec = payload.facts.end_msec
	state.merge(payload.facts, true)
	for row: Dictionary in payload.tanks:
		state.tanks[row.index].merge(row.changes, true)
	for cell: Array in payload.terrain:
		state.terrain[cell[0]] = cell[1]
	for key: String in ["impacts", "health_feedback", "audio_events", "ammo_events"]:
		if payload.events.has(key):
			state[key].append_array(payload.events[key])
			while state[key].size() > 96:
				state[key].pop_front()
	for id: int in payload.removed:
		_shots.erase(id)
	for shot: Dictionary in payload.spawned:
		shot["steps"] = 0
		_shots[shot.id] = shot
	state.projectiles = _shots.values()
	_receive_state(state)

## Every visual shot advances locally between reliable spawn/redirect/despawn events.
func _animate_projectiles() -> void:
	var visuals: Array[Dictionary] = []
	var now: int = api.net.host_time_msec()
	for shot: Dictionary in _shots.values():
		visuals.append(ProjectileMotion.render(shot, state, now))
	state.projectiles = visuals

func _receive_state(value: Dictionary) -> void:
	state = value
	display_time = state.time if preview else maxf(0.0, float(_phase_end_msec - api.net.host_time_msec()) / 1000.0)
	board.update_state(state)
	ammo_cards.update_state(state, "preview" if preview else local_id)
	var audio_error: Error = combat_audio.update_state(state)
	if audio_error != OK:
		if preview:
			push_error("Artillery audio: " + error_string(audio_error))
		else:
			_fail("audio_playback_failed", error_string(audio_error))
		return
	if last_pose_epoch != int(state.tanks[_view_tank()].pose_epoch):
		last_pose_epoch = state.tanks[_view_tank()].pose_epoch
		pending_fire = false
	if last_turn != state.turn:
		last_turn = state.turn
		pending_fire = false
		mouse_aiming = false
		held_direction = 0
		selected = 0
		angle_slider.value = state.tanks[_view_tank()].aim
	if state.phase != "aim":
		pending_fire = false
	_sync_ui()

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if stopped or not payload is Dictionary:
		return
	if payload.get("session") != api.session_id or payload.get("scope") != api.scope_id:
		return
	if topic == POSE:
		if running and not finished and _valid_pose(payload.get("pose")):
			_accept_pose(_sender_player(sender), payload.pose)
		return
	if topic == ACTION:
		if not api.is_host() or not running or finished or not _valid_action(payload):
			return
		var actor: String = _sender_player(sender)
		if actor.is_empty() or _actor_index(actor) < 0:
			return
		if not _valid_pose(payload.get("pose")) or payload.pose.player != actor:
			return
		_accept_pose(actor, payload.pose)
		if payload.pose.epoch != battle.state.tanks[_actor_index(actor)].pose_epoch:
			return
		if battle.command(actor, int(payload.turn), payload.action, payload.values):
			_publish()
		return
	# Only the framework host can publish simulation state or a final result.
	if sender.peer_id != 1 or api.is_host() or finished:
		return
	if topic == EVENTS:
		_receive_events(payload)
	elif topic == FINAL and payload.get("result") is Dictionary:
		var contract: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "contract"}) as Script
		if contract == null:
			_fail("contract_missing", "原版协议缺少结果契约")
			return
		var checked: Dictionary = contract.new().validate_result(payload.result, request, api.get_players())
		if not checked.ok:
			_fail(checked.code, checked.message)
			return
		_open_result(payload.result)

## Validate untrusted peer payloads once, before entering the simulation.
func _valid_action(payload: Dictionary) -> bool:
	if not payload.get("turn") is int or not payload.get("action") is String or not payload.get("values") is Dictionary:
		return false
	var values: Dictionary = payload.values
	match payload.action:
		"fire":
			if not values.get("weapon") is int or values.weapon < 0 or values.weapon >= Battle.WEAPONS.size():
				return false
			for key: String in ["angle", "power"]:
				var number: Variant = values.get(key)
				if not (number is float or number is int) or not is_finite(float(number)):
					return false
			return values.angle >= 0 and values.angle <= 180 and values.power >= 10 and values.power <= 100
		"pass", "reset", "finish":
			return values.is_empty()
	return false

func _send(action: String, values: Dictionary = {}) -> void:
	if not _can_act():
		return
	var pose: Dictionary = _flush_pose(true)
	if stopped:
		return
	if action == "fire":
		pending_fire = true
	var error: Error = api.net.send_to_host(ACTION, {"session": api.session_id, "scope": api.scope_id,
		"turn": state.turn, "action": action, "values": values, "pose": pose})
	if error != OK:
		_fail("action_send_failed", error_string(error))
	_sync_ui()

func _view_tank() -> int:
	for i: int in state.tanks.size():
		if state.tanks[i].id == local_id:
			return i
	return state.active

func _can_act() -> bool:
	return not preview and running and not stopped and not finished and not state.is_empty() and state.phase == "aim" and Battle.can_act(state, _view_tank()) and state.tanks[_view_tank()].id == local_id and not pending_fire and not api.input.input_blocked

func _players_changed() -> void:
	if not api.is_host() or stopped or finished:
		return
	for player: Dictionary in api.get_players():
		if not player.connected:
			battle.withdraw(player.player_id)
	if running:
		_publish()

func _open_result(result: Dictionary) -> void:
	if finished:
		return
	finished = true
	running = false
	combat_audio.finish()
	final_result = result.duplicate(true)
	hud.hide()
	arsenal.hide()
	settlement.configure(api, {"title": "炮火争锋 · 对局结果", "rows": result.rankings}, request.request_id)
	settlement.continued.connect(_submit)

func _submit() -> void:
	if not api.is_host() or stopped:
		return
	var error: Error = api.finish(final_result)
	if error != OK:
		_fail("result_rejected", error_string(error))

func _fail(code: String, message: String) -> void:
	combat_audio.close()
	stopped = true
	running = false
	api.fail(code, message)

func party_stop(_reason: StringName) -> void:
	combat_audio.close()
	stopped = true
	running = false
	if briefing != null:
		briefing.stop()
	if settlement != null:
		settlement.stop()
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)
	set_physics_process(false)

func _input(event: InputEvent) -> void:
	# Release must be observed even when a HUD control consumes the mouse event.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		mouse_aiming = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		mouse_aiming = false
		held_direction = 0

func _unhandled_input(event: InputEvent) -> void:
	if not _can_act() or arsenal.visible:
		return
	if api.input.event_matches(event, &"artillery_fire"):
		_fire()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_8:
			_select(event.physical_keycode - KEY_1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_aiming = true
		_aim_mouse(board.get_local_mouse_position() * Vector2(1920, 1080) / board.size)
		get_viewport().set_input_as_handled()

func _fire() -> void:
	_send("fire", {"weapon": selected, "angle": angle_slider.value, "power": power_slider.value})
	arsenal.hide()

func _select(index: int) -> void:
	if not _can_act() or state.tanks[_view_tank()].ammo[index] == 0:
		return
	selected = index
	arsenal.hide()
	_sync_ui()

const DefaultText: Translation = preload("res://games/minigame/gp_artillery/i18n/zh_Hans.po")

func hud_text(key: StringName, values: Dictionary) -> String:
	return DefaultText.get_message(key).format(values) if api == null else api.i18n.text(key, values)

func _sync_labels() -> void:
	angle_label.text = hud_text(&"hud.angle", {"angle":"%.1f" % angle_slider.value})
	power_label.text = hud_text(&"hud.power", {"power":int(power_slider.value)})

func _sync_ui() -> void:
	if state.is_empty():
		return
	_sync_labels()
	_sync_status()
	var can_act: bool = _can_act()
	var tank: Dictionary = state.tanks[_view_tank()]
	for button: Button in [left_button, right_button, fire_button, pass_button, reset_button, finish_button]:
		button.disabled = not can_act
	angle_slider.editable = can_act
	power_slider.editable = can_act
	left_button.disabled = not can_act or state.tanks[_view_tank()].fuel <= 0.0
	right_button.disabled = left_button.disabled
	reset_button.visible = state.mode == "training"
	finish_button.visible = state.mode == "training"
	pass_button.visible = state.mode != "training"
	pass_button.text = "结束回合"
	fire_button.text = "已行动" if tank.acted else "开火"
	hud.visible = preview or (running and not finished and not stopped and state.phase == "aim" and tank.id == local_id)
	if not hud.visible:
		arsenal.hide()
	fuel_label.text = hud_text(&"hud.fuel", {"fuel":roundi(state.tanks[_view_tank()].fuel)})
	var stock: int = tank.ammo[selected] if not tank.ammo.is_empty() else 0
	weapon_button.text = "%s   %s  ▾" % [Battle.WEAPONS[selected].name, "∞" if stock < 0 else str(stock)]
	for index: int in weapon_buttons.size():
		var definition: Dictionary = Battle.WEAPONS[index]
		var ammo: int = tank.ammo[index] if not tank.ammo.is_empty() else 0
		weapon_buttons[index].text = "%d   %s   %s" % [index + 1, definition.name,
			"∞" if ammo < 0 else "×%d" % ammo]
		weapon_buttons[index].tooltip_text = definition.hint
		weapon_buttons[index].modulate = Color(definition.color)
		weapon_buttons[index].disabled = not can_act or ammo == 0

## Falling supplies are a birth position, speed and landing height, never a stream of reliable positions.
func _environment_changes(objects: Array) -> Dictionary:
	var live: Dictionary = {}
	var upsert: Array = []
	for object: Dictionary in objects:
		if not object.has("id"):
			_environment_id += 1
			object["id"] = _environment_id
		var value: Dictionary = object.duplicate(true)
		if object.kind == "supply":
			var landing: float = battle.ground(object.pos.x) - 18.0
			var previous: Dictionary = _published_environment.get(object.id, {})
			if previous.is_empty() or not is_equal_approx(previous.land_y, landing):
				value["start_msec"] = api.net.host_time_msec()
				value["land_y"] = landing
			else:
				value.pos = previous.pos
				value["start_msec"] = previous.start_msec
				value["land_y"] = previous.land_y
		live[object.id] = value
		if not _published_environment.has(object.id) or _published_environment[object.id] != value:
			upsert.append(value)
	var removed: Array[int] = []
	for id: int in _published_environment:
		if not live.has(id):
			removed.append(id)
	_published_environment = live
	return {"upsert": upsert, "removed": removed}

func _animate_environment() -> void:
	var now: int = api.net.host_time_msec()
	for object: Dictionary in _environment.values():
		if object.kind == "supply":
			object.pos.y = minf(object.land_y, object.origin_y + maxf(0.0, float(now - object.start_msec) / 1000.0) * 100.0)

func _actor_index(actor: String) -> int:
	for index: int in battle.state.tanks.size():
		if battle.state.tanks[index].id == actor:
			return index
	return -1
