extends Control
## Party scope integration. Only the host simulates; clients send logical turn actions.
const CombatAudio: Script = preload("res://games/minigame/godot_party_default_artillery_game/combat_audio.gd")
const Battle: Script = preload("res://games/minigame/godot_party_default_artillery_game/battle.gd")
const Battlefield: Script = preload("res://games/minigame/godot_party_default_artillery_game/battlefield.gd")
const ACTION: StringName = &"artillery/action"
const SNAPSHOT: StringName = &"artillery_state"
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
var snapshot_time: float = 0.0
var last_turn: int = -1
var selected: int = 0
var pending_fire: bool = false
var move_delay: float = 0.0
var held_direction: int = 0
var mouse_aiming: bool = false
var display_time: float = 0.0
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
var briefing: Control
var settlement: Control
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
	battle.setup(players, api.get_seed(), mode)
	_receive_state(battle.state.duplicate(true))
	var gate_script: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "briefing_gate"}) as Script
	if gate_script == null:
		_fail("briefing_missing", "原版协议缺少准备界面")
		return
	briefing = gate_script.new()
	var content: Dictionary = gate_script.read_content(get_script().resource_path.get_base_dir().path_join("manifest.json"), api)
	content["controls"] = [{"binding": "A / D · W / S · Q / E", "description": "按住移动 · 调整角度 · 减小 / 增大力度"},
		{"binding": "鼠标左键长按", "description": "同时调整角度与力度，使弹道靠近指针；Space / 开火按钮发射；1–8 快选弹药；Esc 菜单"}]
	briefing.configure(api, content)
	briefing.play_requested.connect(_begin)
	add_child(briefing)
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
		battle.step(delta)
		snapshot_time += delta
		if snapshot_time >= 0.08 or battle.state.phase == "over":
			snapshot_time = 0.0
			_publish()

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
		move_delay = 0.0
		held_direction = 0
		mouse_aiming = false
	board.aim_angle = angle_slider.value
	board.aim_power = power_slider.value
	board.weapon = selected
	board.show_aim = _can_act() or preview
	_sync_labels()
	if state.phase == "aim" and state.mode != "training":
		display_time = maxf(0.0, display_time - delta)
	_sync_status()

## Repeat bounded logical movement commands; the host still owns fuel and collisions.
func _apply_controls(delta: float, direction: int, angle_axis: float, power_axis: float) -> void:
	if not _can_act() or arsenal.visible:
		return
	angle_slider.value += angle_axis * 40.0 * delta
	power_slider.value += power_axis * 32.0 * delta
	if direction == 0:
		move_delay = 0.0
		held_direction = 0
		return
	if direction != held_direction:
		move_delay = 0.0
		held_direction = direction
	move_delay -= delta
	if move_delay <= 0.0 and state.fuel > 0.0:
		_send("move", {"direction": direction})
		move_delay = 0.12

func _aim_mouse(target: Vector2) -> void:
	var tank: Dictionary = state.tanks[state.active].duplicate()
	var model: Node2D = board.models[state.active]
	tank.x = model.position.x
	tank.y = model.position.y
	tank.tilt = model.rotation
	var aim: Vector2 = Battle.aim_at(state, tank, selected, target)
	angle_slider.value = aim.x
	power_slider.value = aim.y

func _sync_status() -> void:
	top_status.visible = preview or (running and not stopped and not finished)
	countdown.text = "∞" if state.mode == "training" else (str(ceili(display_time)) if state.phase == "aim" else "—")
	countdown.modulate = Color("#ff515b") if state.mode != "training" and state.phase == "aim" and display_time <= 10.0 else Color.WHITE
	wind_arrow.rotation = state.wind.angle()
	wind_strength.text = str(roundi(state.wind.length()))

func _publish() -> void:
	revision += 1
	battle.state.revision = revision
	var snapshot: Dictionary = battle.state.duplicate(true)
	_receive_state(snapshot)
	var error: Error = api.net.broadcast_stream(SNAPSHOT, {"session": api.session_id, "scope": api.scope_id, "state": snapshot}, "instance", true)
	if error != OK:
		_fail("state_send_failed", error_string(error))
		return
	if battle.state.phase == "over" and not finished:
		var result: Dictionary = battle.result(request.request_id)
		error = api.net.broadcast(FINAL, {"session": api.session_id, "scope": api.scope_id, "state": snapshot, "result": result}, true)
		if error != OK:
			_fail("result_send_failed", error_string(error))
			return
		_open_result(result)

func _receive_state(value: Dictionary) -> void:
	state = value
	display_time = state.time
	board.update_state(state)
	var audio_error: Error = combat_audio.update_state(state)
	if audio_error != OK:
		if preview:
			push_error("Artillery audio: " + error_string(audio_error))
		else:
			_fail("audio_playback_failed", error_string(audio_error))
		return
	if last_turn != state.turn:
		last_turn = state.turn
		pending_fire = false
		mouse_aiming = false
		move_delay = 0.0
		held_direction = 0
		selected = 0
		angle_slider.value = state.tanks[state.active].aim
	if state.phase != "aim":
		pending_fire = false
	_sync_ui()

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if stopped or not payload is Dictionary:
		return
	if payload.get("session") != api.session_id or payload.get("scope") != api.scope_id:
		return
	if topic == ACTION:
		if not api.is_host() or not running or finished or not _valid_action(payload):
			return
		var actor: String = ""
		for player: Dictionary in api.get_players():
			if player.connected and player.peer_id == sender.peer_id and player.player_id in sender.player_ids:
				actor = player.player_id
				break
		if actor.is_empty():
			return
		if battle.command(actor, int(payload.turn), payload.action, payload.values):
			_publish()
		return
	# Only the framework host can publish simulation state or a final result.
	if sender.peer_id != 1 or api.is_host() or finished:
		return
	if topic == SNAPSHOT:
		if not payload.get("state") is Dictionary:
			return
		var snapshot: Dictionary = payload.state
		if not snapshot.get("revision") is int or snapshot.revision <= revision:
			return
		revision = snapshot.revision
		_receive_state(snapshot)
	elif topic == FINAL and payload.get("result") is Dictionary and payload.get("state") is Dictionary:
		var contract: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "contract"}) as Script
		if contract == null:
			_fail("contract_missing", "原版协议缺少结果契约")
			return
		var checked: Dictionary = contract.new().validate_result(payload.result, request, api.get_players())
		if not checked.ok:
			_fail(checked.code, checked.message)
			return
		_receive_state(payload.state)
		_open_result(payload.result)

## Validate untrusted peer payloads once, before entering the simulation.
func _valid_action(payload: Dictionary) -> bool:
	if not payload.get("turn") is int or not payload.get("action") is String or not payload.get("values") is Dictionary:
		return false
	var values: Dictionary = payload.values
	match payload.action:
		"move":
			return values.get("direction") is int and values.direction in [-1, 1]
		"fire":
			if not values.get("weapon") is int or values.weapon < 0 or values.weapon >= Battle.WEAPONS.size():
				return false
			for key: String in ["angle", "power"]:
				var number: Variant = values.get(key)
				if not (number is float or number is int) or not is_finite(float(number)):
					return false
			return values.angle >= 5 and values.angle <= 175 and values.power >= 10 and values.power <= 100
		"pass", "reset", "finish":
			return values.is_empty()
	return false

func _send(action: String, values: Dictionary = {}) -> void:
	if not _can_act():
		return
	if action == "fire":
		pending_fire = true
	var error: Error = api.net.send_to_host(ACTION, {"session": api.session_id, "scope": api.scope_id,
		"turn": state.turn, "action": action, "values": values})
	if error != OK:
		_fail("action_send_failed", error_string(error))
	_sync_ui()

func _can_act() -> bool:
	return not preview and running and not stopped and not finished and not state.is_empty() and state.phase == "aim" and state.tanks[state.active].id == local_id and not pending_fire and not api.input.input_blocked

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
	var gate_script: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "settlement_gate"}) as Script
	if gate_script == null:
		_fail("settlement_missing", "原版协议缺少结算界面")
		return
	settlement = gate_script.new()
	settlement.configure(api, {"title": "炮火争锋 · 对局结果", "rows": result.rankings}, request.request_id)
	settlement.continued.connect(_submit)
	add_child(settlement)

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
		move_delay = 0.0

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
	if not _can_act() or state.tanks[state.active].ammo[index] == 0:
		return
	selected = index
	arsenal.hide()
	_sync_ui()

const DefaultText: Translation = preload("res://games/minigame/godot_party_default_artillery_game/i18n/zh_Hans.po")

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
	var tank: Dictionary = state.tanks[state.active]
	for button: Button in [left_button, right_button, fire_button, pass_button, reset_button, finish_button]:
		button.disabled = not can_act
	angle_slider.editable = can_act
	power_slider.editable = can_act
	left_button.disabled = not can_act or state.fuel <= 0.0
	right_button.disabled = left_button.disabled
	reset_button.visible = state.mode == "training"
	finish_button.visible = state.mode == "training"
	pass_button.visible = state.mode != "training"
	hud.visible = preview or (running and not finished and not stopped and state.phase == "aim" and tank.id == local_id)
	if not hud.visible:
		arsenal.hide()
	fuel_label.text = hud_text(&"hud.fuel", {"fuel":roundi(state.fuel)})
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
