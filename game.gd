extends Control
## Party scope integration. Only the host simulates; clients send logical turn actions.
const Battle: Script = preload("res://games/minigame/godot_party_default_artillery_game/battle.gd")
const Battlefield: Script = preload("res://games/minigame/godot_party_default_artillery_game/battlefield.gd")
const ACTION: StringName = &"artillery/action"
const SNAPSHOT: StringName = &"artillery_state"
const FINAL: StringName = &"artillery/final"
var api: PartyAPI
var request: Dictionary
var battle: RefCounted = Battle.new()
var board: Control
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
var angle_slider: HSlider
var power_slider: HSlider
var angle_label: Label
var power_label: Label
var fuel_label: Label
var weapon_button: Button
var fire_button: Button
var left_button: Button
var right_button: Button
var pass_button: Button
var reset_button: Button
var finish_button: Button
var arsenal: PanelContainer
var weapon_buttons: Array[Button] = []
var hud: MarginContainer
var briefing: Control
var settlement: Control
var final_result: Dictionary = {}

func party_setup(value: PartyAPI, config: Dictionary) -> void:
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
	board = Battlefield.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	_build_hud()
	if api == null:
		preview = true
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
	content["controls"] = [{"binding": "鼠标 / 滑条", "description": "调整角度与力度，点击开火"},
		{"binding": "A / D · 1–8", "description": "移动坦克 · 选择弹药；Esc 打开框架菜单"}]
	briefing.configure(api, content)
	briefing.play_requested.connect(_begin)
	add_child(briefing)
	var error: Error = api.mark_ready()
	if error != OK:
		_fail("ready_failed", error_string(error))

func party_start() -> void:
	briefing.transport_started()

func _begin() -> void:
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
	_sync_ui()

func _process(_delta: float) -> void:
	if not state.is_empty():
		board.aim_angle = angle_slider.value
		board.aim_power = power_slider.value
		board.weapon = selected
		board.show_aim = _can_act() or preview

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
	board.update_state(state)
	if last_turn != state.turn:
		last_turn = state.turn
		pending_fire = false
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
	final_result = result.duplicate(true)
	hud.hide()
	arsenal.hide()
	var gate_script: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "settlement_gate"}) as Script
	if gate_script == null:
		_fail("settlement_missing", "原版协议缺少结算界面")
		return
	settlement = gate_script.new()
	settlement.configure(api, {"title": "火炮大战 · 对局结果", "rows": result.rankings}, request.request_id)
	settlement.continued.connect(_submit)
	add_child(settlement)

func _submit() -> void:
	if not api.is_host() or stopped:
		return
	var error: Error = api.finish(final_result)
	if error != OK:
		_fail("result_rejected", error_string(error))

func _fail(code: String, message: String) -> void:
	stopped = true
	running = false
	api.fail(code, message)

func party_stop(_reason: StringName) -> void:
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

func _unhandled_input(event: InputEvent) -> void:
	if not _can_act():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_8:
			_select(event.physical_keycode - KEY_1)
		elif event.physical_keycode == KEY_A:
			_send("move", {"direction": -1})
		elif event.physical_keycode == KEY_D:
			_send("move", {"direction": 1})
		elif event.physical_keycode == KEY_SPACE:
			_fire()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position * Vector2(1920, 1080) / size
		var tank: Dictionary = state.tanks[state.active]
		var offset: Vector2 = p - Battle.gun_pivot(tank)
		angle_slider.value = clampf(rad_to_deg(atan2(-offset.y, offset.x)), 5.0, 175.0)

func _fire() -> void:
	_send("fire", {"weapon": selected, "angle": angle_slider.value, "power": power_slider.value})
	arsenal.hide()

func _select(index: int) -> void:
	if not _can_act() or state.tanks[state.active].ammo[index] == 0:
		return
	selected = index
	arsenal.hide()
	_sync_ui()

func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	# Preserve the Space fire shortcut after choosing ammunition with the mouse.
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(105, 46)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(callback)
	return button

func _fill(color: Color, padding: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _build_hud() -> void:
	var controls_theme: Theme = Theme.new()
	controls_theme.set_stylebox("normal", "Button", _fill(Color("#34405a"), 14))
	controls_theme.set_stylebox("hover", "Button", _fill(Color("#52627c"), 14))
	controls_theme.set_stylebox("pressed", "Button", _fill(Color("#516d78"), 14))
	controls_theme.set_stylebox("disabled", "Button", _fill(Color("#30394e"), 14))
	controls_theme.set_color("font_color", "Button", Color("#fff4df"))
	controls_theme.set_color("font_disabled_color", "Button", Color("#bdc3d0"))
	var rail: StyleBoxFlat = _fill(Color("#6c758a"), 0)
	rail.content_margin_top = 2
	rail.content_margin_bottom = 2
	controls_theme.set_stylebox("slider", "HSlider", rail)
	var filled: StyleBoxFlat = rail.duplicate()
	filled.bg_color = Color("#ecd0a1")
	for style_name: String in ["grabber_area", "grabber_area_highlight"]:
		controls_theme.set_stylebox(style_name, "HSlider", filled)
	var handle: Image = Image.create_empty(10, 16, false, Image.FORMAT_RGBA8)
	handle.fill(Color("#fff4df"))
	var grip: ImageTexture = ImageTexture.create_from_image(handle)
	for icon_name: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		controls_theme.set_icon(icon_name, "HSlider", grip)
	hud = MarginContainer.new()
	hud.theme = controls_theme
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.offset_top = -88
	hud.offset_bottom = -22
	add_child(hud)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _fill(Color("#192236"), 12))
	hud.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	left_button = _button("◀", func() -> void: _send("move", {"direction": -1}))
	left_button.custom_minimum_size.x = 44
	left_button.tooltip_text = "向左移动（A）"
	row.add_child(left_button)
	fuel_label = Label.new()
	row.add_child(fuel_label)
	right_button = _button("▶", func() -> void: _send("move", {"direction": 1}))
	right_button.custom_minimum_size.x = 44
	right_button.tooltip_text = "向右移动（D）"
	row.add_child(right_button)
	var aim: VBoxContainer = VBoxContainer.new()
	aim.custom_minimum_size.x = 165
	row.add_child(aim)
	angle_label = Label.new()
	aim.add_child(angle_label)
	angle_slider = HSlider.new()
	angle_slider.min_value = 5
	angle_slider.max_value = 175
	angle_slider.value = 45
	angle_slider.step = 0.5
	aim.add_child(angle_slider)
	var power: VBoxContainer = VBoxContainer.new()
	power.custom_minimum_size.x = 165
	row.add_child(power)
	power_label = Label.new()
	power.add_child(power_label)
	power_slider = HSlider.new()
	power_slider.min_value = 10
	power_slider.max_value = 100
	power_slider.value = 60
	power_slider.step = 1
	power.add_child(power_slider)
	angle_slider.value_changed.connect(func(_value: float) -> void: _sync_labels())
	power_slider.value_changed.connect(func(_value: float) -> void: _sync_labels())
	weapon_button = _button("弹药库", func() -> void: arsenal.visible = not arsenal.visible)
	weapon_button.custom_minimum_size.x = 164
	weapon_button.tooltip_text = "选择弹药（1–8）"
	row.add_child(weapon_button)
	fire_button = _button("开火", _fire)
	fire_button.tooltip_text = "发射炮弹（Space）"
	fire_button.custom_minimum_size.x = 104
	fire_button.add_theme_stylebox_override("normal", _fill(Color("#aa5542"), 16))
	fire_button.add_theme_stylebox_override("hover", _fill(Color("#be654f"), 16))
	row.add_child(fire_button)
	pass_button = _button("结束回合", func() -> void: _send("pass"))
	row.add_child(pass_button)
	reset_button = _button("重置靶场", func() -> void: _send("reset"))
	row.add_child(reset_button)
	finish_button = _button("结束测试", func() -> void: _send("finish"))
	row.add_child(finish_button)
	arsenal = PanelContainer.new()
	arsenal.theme = controls_theme
	arsenal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	arsenal.offset_left = -605
	arsenal.offset_right = 605
	arsenal.offset_top = -235
	arsenal.offset_bottom = -100
	arsenal.add_theme_stylebox_override("panel", _fill(Color("#192236"), 10))
	add_child(arsenal)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	arsenal.add_child(grid)
	for index: int in Battle.WEAPONS.size():
		var button: Button = _button("", _select.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 52
		button.add_theme_font_size_override("font_size", 18)
		grid.add_child(button)
		weapon_buttons.append(button)
	arsenal.hide()

func _sync_labels() -> void:
	angle_label.text = "角度  %.1f°" % angle_slider.value
	power_label.text = "力度  %d%%" % power_slider.value

func _sync_ui() -> void:
	if state.is_empty():
		return
	_sync_labels()
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
	fuel_label.text = "移动 %d" % roundi(state.fuel)
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
