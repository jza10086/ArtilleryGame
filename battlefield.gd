extends Control
## Flat vector battlefield in the same 1920 × 1080 coordinate space as the shot simulation.
const Battle: Script = preload("res://games/minigame/godot_party_default_artillery_game/battle.gd")
const TankScene: PackedScene = preload("res://games/minigame/godot_party_default_artillery_game/tank_model.tscn")
const TankModel: Script = preload("res://games/minigame/godot_party_default_artillery_game/tank_model.gd")
const SKY: Color = Color("#070d1d")
const GROUND: Color = Color("#083660")
const INK: Color = Color("#e4faff")
var state: Dictionary = {}
var ground_profile: PackedFloat32Array = PackedFloat32Array()
var initial_profile: PackedFloat32Array = PackedFloat32Array()
var previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var render_viewport: Viewport
var aim_tank: int = 0
var aim_angle: float = 45.0
var aim_power: float = 60.0
var weapon: int = 0
var show_aim: bool = false
var last_impact: int = 0
var flashes: Array[Dictionary] = []
var effect_time: float = 0.0
var font: Font
@onready var world: Node2D = $World
@onready var terrain: Node2D = $World/Terrain
@onready var terrain_material: ShaderMaterial = terrain.material
@onready var foreground: Node2D = $World/Foreground
@onready var light_layer: Node2D = $World/LightLayer
@onready var aim_curve: Line2D = %AimCurve
@export var falloff: GradientTexture2D
var models: Array[TankModel] = []
var supply_positions: Dictionary[Vector2, Vector2] = {}
var last_health_feedback: int = 0
var health_numbers: Array[Dictionary] = []
@export_group("Health feedback")
@export_range(0.05, 1.0) var number_enter_seconds: float = 0.24
@export_range(0.0, 2.0) var number_hold_seconds: float = 0.75
@export_range(0.05, 1.0) var number_exit_seconds: float = 0.42

## Keep animation local to rendering; host event IDs prevent duplicate snapshot feedback.
func _receive_health_feedback() -> void:
	var grouped: Dictionary[String, Dictionary] = {}
	for event: Dictionary in state.health_feedback:
		if event.id <= last_health_feedback:
			continue
		last_health_feedback = event.id
		var key: String = "%s:%s" % [event.tank, event.amount > 0]
		if grouped.has(key):
			grouped[key].amount += event.amount
		else:
			grouped[key] = event.duplicate()
	for event: Dictionary in grouped.values():
		var origin: Vector2 = event.pos + Vector2(0, -94)
		for number: Dictionary in health_numbers:
			if number.tank == event.tank:
				origin.y = minf(origin.y, number.pos.y - 38.0)
		health_numbers.append({"tank": event.tank, "amount": event.amount,
			"pos": origin, "age": 0.0})

func _draw_health_numbers() -> void:
	for number: Dictionary in health_numbers:
		var age: float = number.age
		var rise: float = 0.0
		var opacity: float = 1.0
		if age < number_enter_seconds:
			var progress: float = age / number_enter_seconds
			rise = 26.0 * (1.0 - pow(1.0 - progress, 3.0))
			opacity = smoothstep(0.0, 0.65, progress)
		elif age < number_enter_seconds + number_hold_seconds:
			rise = 26.0
		else:
			var progress: float = clampf((age - number_enter_seconds - number_hold_seconds) / number_exit_seconds, 0.0, 1.0)
			rise = 26.0 + 34.0 * progress * progress
			opacity = 1.0 - smoothstep(0.0, 1.0, progress)
		var tint: Color = Color("#65f5a2") if number.amount > 0 else Color("#ff6475")
		tint.a = opacity
		var text: String = ("+%d" if number.amount > 0 else "%d") % number.amount
		var extent: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
		var position: Vector2 = number.pos - Vector2(extent.x * 0.5, rise)
		foreground.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, tint)

func _ready() -> void:
	render_viewport = get_viewport()
	previous_msaa = render_viewport.msaa_2d
	render_viewport.msaa_2d = Viewport.MSAA_8X
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()
	terrain.draw.connect(_draw_terrain)
	light_layer.draw.connect(_draw_lights)
	foreground.draw.connect(_draw_foreground)
	resized.connect(_resize_world)
	_resize_world()

func _exit_tree() -> void:
	render_viewport.msaa_2d = previous_msaa

func _resize_world() -> void:
	world.scale = size / Vector2(1920, 1080)

func _process(delta: float) -> void:
	if state.is_empty():
		return
	effect_time += delta
	for i: int in range(health_numbers.size() - 1, -1, -1):
		health_numbers[i].age += delta
		if health_numbers[i].age >= number_enter_seconds + number_hold_seconds + number_exit_seconds:
			health_numbers.remove_at(i)
	for i: int in range(flashes.size() - 1, -1, -1):
		flashes[i].life -= delta
		if flashes[i].life <= 0.0:
			flashes.remove_at(i)
	for i: int in models.size():
		var tank: Dictionary = state.tanks[i]
		var degrees: float = aim_angle if i == aim_tank and show_aim and state.phase == "aim" else float(tank.aim)
		var tint: Color = Color(tank.color)
		if state.mode == "teams":
			tint = [Color("#73d9ed"), Color("#ff947d")][tank.team]
		models[i].pose(tank, degrees, tint, delta)
	for event: Dictionary in state.events:
		if event.kind == "supply":
			var key: Vector2 = Vector2(event.pos.x, event.expires)
			supply_positions[key] = supply_positions[key].lerp(event.pos, 1.0 - exp(-delta * 24.0))
	aim_curve.visible = show_aim and state.phase == "aim"
	if aim_curve.visible:
		_update_aim()
	light_layer.queue_redraw()
	foreground.queue_redraw()

func update_state(value: Dictionary) -> void:
	var first_snapshot: bool = state.is_empty()
	state = value
	# A newly opened view starts from the current state rather than replaying old hits.
	if first_snapshot and not state.health_feedback.is_empty():
		last_health_feedback = state.health_feedback.back().id
	if initial_profile != state.terrain_origin:
		health_numbers.clear()
	_receive_health_feedback()
	var next_supplies: Dictionary[Vector2, Vector2] = {}
	for event: Dictionary in state.events:
		if event.kind == "supply":
			var key: Vector2 = Vector2(event.pos.x, event.expires)
			var previous: Vector2 = supply_positions.get(key, event.pos)
			next_supplies[key] = event.pos if previous.distance_to(event.pos) > 120.0 else previous
	supply_positions = next_supplies
	if initial_profile != state.terrain_origin:
		initial_profile = state.terrain_origin.duplicate()
		var profile_image: Image = Image.create_from_data(initial_profile.size(), 1, false, Image.FORMAT_RF, initial_profile.to_byte_array())
		terrain_material.set_shader_parameter("initial_surface", ImageTexture.create_from_image(profile_image))
	if ground_profile != state.terrain:
		ground_profile = state.terrain
		terrain.queue_redraw()
	while models.size() < state.tanks.size():
		var model: TankModel = TankScene.instantiate()
		world.add_child(model)
		models.append(model)
	for impact: Dictionary in state.impacts:
		if impact.id > last_impact:
			flashes.append({"pos": impact.pos, "radius": impact.radius, "weapon": impact.weapon, "life": 0.55})
			last_impact = impact.id

func _draw_terrain() -> void:
	if state.is_empty():
		return
	var land: PackedVector2Array = PackedVector2Array([Vector2(0, 1080)])
	for i: int in state.terrain.size():
		land.append(Vector2(i * Battle.CELL, state.terrain[i]))
	land.append(Vector2(1920, 1080))
	terrain.draw_colored_polygon(land, Color.WHITE)

func _glow(point: Vector2, radius: float, tint: Color) -> void:
	var extent: Vector2 = Vector2.ONE * radius
	light_layer.draw_texture_rect(falloff, Rect2(point - extent, extent * 2.0), false, tint)

func _draw_lights() -> void:
	for model: TankModel in models:
		if not model.visible:
			continue
		var optic: Vector2 = world.to_local(model.sight.global_position)
		var lamp: Color = model.turret.modulate.lerp(Color("#d6faff"), 0.42)
		_glow(optic, 13.0, Color(lamp, 0.65))
		light_layer.draw_circle(optic, 1.65, lamp, true, -1, true)
		if model.recoil_left > 0.0:
			var kick: float = model.recoil_left / TankModel.RECOIL_TIME
			var muzzle: Vector2 = world.to_local(model.muzzle.global_position)
			_glow(muzzle, 12.0 + kick * 48.0, Color(Color("#9bdfff"), kick))
	if state.is_empty():
		return
	_event_lights()
	for shot: Dictionary in state.projectiles:
		var tint: Color = Color("#8cffe0") if shot.support else Color(Battle.WEAPONS[shot.weapon].color)
		_glow(shot.pos, 39.0 * shot.boost, Color(tint, 0.92))
		for i: int in range(0, shot.trail.size(), 3):
			var strength: float = (i + 1.0) / shot.trail.size()
			_glow(shot.trail[i], 12.0 + 11.0 * strength, Color(tint, 0.32 * strength))
	for flash: Dictionary in flashes:
		var life: float = flash.life / 0.55
		var tint: Color = Color(Battle.WEAPONS[flash.weapon].color)
		_glow(flash.pos, flash.radius * (2.25 - 0.7 * life), Color(tint, 0.8 * life))
		_glow(flash.pos, flash.radius * 0.85, Color(tint.lerp(Color.WHITE, 0.65), life))

func _draw_foreground() -> void:
	if state.is_empty():
		return
	_draw_events()
	for i: int in state.tanks.size():
		_tank_label(i)
	for shot: Dictionary in state.projectiles:
		var tint: Color = Color("#8cffe0") if shot.support else Color(Battle.WEAPONS[shot.weapon].color)
		for i: int in range(1, shot.trail.size()):
			var strength: float = float(i) / (shot.trail.size() - 1)
			foreground.draw_line(shot.trail[i - 1], shot.trail[i], Color(tint, strength * 0.88), 1.0 + strength * 2.0, true)
		if shot.pos.y < 0.0:
			var x: float = clampf(shot.pos.x, 12.0, 1908.0)
			foreground.draw_colored_polygon(PackedVector2Array([Vector2(x, 8), Vector2(x - 6, 18), Vector2(x + 6, 18)]), tint)
		foreground.draw_circle(shot.pos, 5.0 * shot.boost, tint, true, -1, true)
		foreground.draw_circle(shot.pos, 2.8, tint.lerp(Color.WHITE, 0.88), true, -1, true)
		if shot.boost > 1.0:
			foreground.draw_string(font, shot.pos + Vector2(10, -10), "×%d" % int(shot.boost), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tint)
	for flash: Dictionary in flashes:
		_blast(flash)
	_draw_health_numbers()

func _tank_label(index: int) -> void:
	var tank: Dictionary = state.tanks[index]
	if tank.hp <= 0:
		return
	var p: Vector2 = models[index].position
	var tint: Color = Color(tank.color)
	if state.mode == "teams":
		tint = [Color("#73d9ed"), Color("#ff947d")][tank.team]
	if state.mode != "training":
		foreground.draw_string(font, p + Vector2(-84, -65), String(tank.name).left(12), HORIZONTAL_ALIGNMENT_CENTER, 168, 17, INK)
	if state.mode != "training" or tank.hp < 200:
		foreground.draw_rect(Rect2(p + Vector2(-23, -57), Vector2(46, 4)), GROUND)
		foreground.draw_rect(Rect2(p + Vector2(-23, -57), Vector2(46.0 * tank.hp / 200.0, 4)), tint)
	if tank.shield > 0:
		foreground.draw_arc(p + Vector2(0, -7), 40.0, PI * 1.05, TAU * 0.98, 32, Color("#76baff"), 2.0, true)
		foreground.draw_string(font, p + Vector2(-23, -39), "+%d" % tank.shield, HORIZONTAL_ALIGNMENT_CENTER, 46, 13, Color("#a1d8ff"))
	if tank.jammed:
		foreground.draw_string(font, p + Vector2(-30, 35), "EMP", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Color("#b5acff"))
	if Battle.can_act(state, index):
		var marker: Vector2 = p + Vector2(0, -63 if state.mode == "training" else -89)
		foreground.draw_colored_polygon(PackedVector2Array([marker - Vector2(6, 0), marker + Vector2(6, 0), marker + Vector2(0, 7)]), INK)

## A native Line2D supplies smooth joins and an editable taper from barrel to tip.
func _update_aim() -> void:
	var direction: Vector2 = Vector2.from_angle(-deg_to_rad(aim_angle))
	var pos: Vector2 = world.to_local(models[aim_tank].muzzle.global_position)
	var velocity: Vector2 = direction * (270.0 + aim_power * 6.0) * (0.82 if weapon == 1 else 1.0)
	aim_curve.points = Battle.aim_path(state, pos, velocity, weapon)

func _blast(flash: Dictionary) -> void:
	var t: float = 1.0 - flash.life / 0.55
	var tint: Color = Color(Battle.WEAPONS[flash.weapon].color)
	var radius: float = flash.radius
	var center: Vector2 = flash.pos
	foreground.draw_circle(center, radius * 0.62 * sin(PI * t), tint, true, -1, true)
	foreground.draw_circle(center, radius * 0.30 * (1.0 - t), INK, true, -1, true)
	# Once narrower than a pixel the shrinking shard can collapse to a line.
	var half_width: float = (1.0 - t) * 5.5
	if half_width < 0.5:
		return
	for i: int in 8:
		var ray: Vector2 = Vector2.from_angle(TAU * i / 8.0 + flash.weapon * 0.3)
		var tip: Vector2 = center + ray * radius * (0.32 + t * 0.85)
		var tail: Vector2 = tip - ray * radius * (1.0 - t) * 0.24
		var side: Vector2 = ray.orthogonal() * half_width
		foreground.draw_colored_polygon(PackedVector2Array([tip, tail + side, tail - side]), tint)


## Emissive edges follow the official gameplay references; geometry stays vector.
func _ring_light(point: Vector2, radius: float, tint: Color) -> void:
	for layer: int in 4:
		light_layer.draw_arc(point, radius, 0.0, TAU, 96, Color(tint, 0.06 + layer * 0.025), 18.0 - layer * 4.0, true)

func _event_lights() -> void:
	for event: Dictionary in state.events:
		match event.kind:
			"black_hole":
				_glow(event.pos, 104.0, Color(0.28, 0.25, 1.0, 0.42))
				_ring_light(event.pos, Battle.BLACK_HOLE_CORE + 3.0, Color("#747fff"))
			"portal":
				_glow(event.pos, 76.0, Color(0.03, 0.47, 1.0, 0.8))
				_glow(event.exit, 76.0, Color(1.0, 0.34, 0.015, 0.8))
				_ring_light(event.pos, Battle.PORTAL_RADIUS, Color("#259dff"))
				_ring_light(event.exit, Battle.PORTAL_RADIUS, Color("#ff921f"))
			"bumper":
				_ring_light(event.pos, Battle.BUMPER_RADIUS, Color("#ff21e9"))
			"amplifier":
				var tint: Color = Color("#ff9a16") if event.factor == 3.0 else Color("#ff253c")
				_glow(event.pos, event.radius * 1.9, Color(tint, 0.36))
				_ring_light(event.pos, event.radius, Color(tint, 0.45))
			"drone":
				_glow(event.pos, 42.0, Color(0.2, 0.45, 1.0, 0.6))
			"supply":
				_glow(supply_positions[Vector2(event.pos.x, event.expires)], 35.0, Color(0.3, 1.0, 0.62, 0.2))
	for hazard: Dictionary in state.hazards:
		var p: Vector2 = Vector2(hazard.x, _surface_y(hazard.x) - 10.0)
		_glow(p, 75.0 if hazard.kind == "fire" else 25.0, Color(1, 0.3, 0.1, 0.55) if hazard.kind == "fire" else Color(1, 0.15, 0.4, 0.6))

func _surface_y(x: float) -> float:
	return state.terrain[clampi(roundi(x / Battle.CELL), 0, 480)]

## Blue/orange portals are dark apertures, distinct from the spiral gravity well.
func _portal(point: Vector2, tint: Color, phase: float) -> void:
	foreground.draw_circle(point, Battle.PORTAL_RADIUS, Color("#02050c"), true, -1, true)
	foreground.draw_arc(point, Battle.PORTAL_RADIUS, 0.0, TAU, 96, tint, 1.8, true)
	for i: int in 9:
		var angle: float = i * 2.39996 + phase * 0.18
		var travel: float = fposmod(effect_time * 0.23 + i * 0.37, 1.0)
		var radius: float = Battle.PORTAL_RADIUS + 3.0 + travel * 18.0
		foreground.draw_circle(point + Vector2.from_angle(angle) * radius, 0.7 + (i % 3) * 0.35, Color(tint, (1.0 - travel) * 0.65), true, -1, true)

func _black_hole(point: Vector2) -> void:
	# Thin, uneven spiral streams leave space between the core and the outer dust.
	for arm: int in 5:
		var stream: PackedVector2Array = PackedVector2Array()
		for step: int in 49:
			var t: float = step / 48.0
			var angle: float = arm * TAU / 5.0 - effect_time * 0.32 + t * 5.4
			var radius: float = lerpf(68.0 - arm * 3.0, Battle.BLACK_HOLE_CORE + 2.0, t)
			stream.append(point + Vector2.from_angle(angle) * radius)
		foreground.draw_polyline(stream, Color(0.39 + arm * 0.035, 0.42, 0.95, 0.18 + arm * 0.045), 1.25, true)
	for i: int in 48:
		var travel: float = fposmod(i * 0.618034 + effect_time * 0.055, 1.0)
		var angle: float = i * 2.39996 - effect_time * 0.34 - travel * 3.0
		var radius: float = lerpf(87.0, 21.0, travel)
		foreground.draw_circle(point + Vector2.from_angle(angle) * radius, 0.55 + (i % 3) * 0.3, Color(0.65, 0.73, 1.0, sin(travel * PI) * 0.7), true, -1, true)
	foreground.draw_circle(point, Battle.BLACK_HOLE_CORE, Color("#01030b"), true, -1, true)
	foreground.draw_arc(point, Battle.BLACK_HOLE_CORE + 1.0, 0.0, TAU, 64, Color("#8b9aff"), 1.5, true)

func _draw_events() -> void:
	for event: Dictionary in state.events:
		var p: Vector2 = supply_positions[Vector2(event.pos.x, event.expires)] if event.kind == "supply" else event.pos
		match event.kind:
			"black_hole":
				_black_hole(p)
			"portal":
				_portal(p, Color("#60baff"), effect_time)
				_portal(event.exit, Color("#ffb45c"), -effect_time)
			"bumper":
				foreground.draw_arc(p, Battle.BUMPER_RADIUS, 0.0, TAU, 96, Color("#ff65ee"), 3.2, true)
				foreground.draw_arc(p, Battle.BUMPER_RADIUS, 0.0, TAU, 96, Color("#fff2ff"), 1.2, true)
			"amplifier":
				var tint: Color = Color("#ff9a16") if event.factor == 3.0 else Color("#ff253c")
				foreground.draw_circle(p, event.radius, Color(tint, 0.16), true, -1, true)
				for segment: int in 8:
					var angle: float = segment * TAU / 8.0 + effect_time * 0.12
					foreground.draw_arc(p, event.radius, angle, angle + TAU / 8.0 - 0.10, 12, Color(tint, 0.85), 2.5, true)
				for i: int in 5:
					var angle: float = i * 2.39996 + effect_time * 0.15
					var radius: float = event.radius + 9.0 + 9.0 * sin(effect_time + i * 1.7)
					foreground.draw_circle(p + Vector2.from_angle(angle) * radius, 1.6, Color(tint, 0.7), true, -1, true)
				foreground.draw_string(font, p + Vector2(-55, 9 if event.factor == 3.0 else 7), "×%d" % int(event.factor), HORIZONTAL_ALIGNMENT_CENTER, 110, 30 if event.factor == 3.0 else 38, Color("#fff6ed"))
				if event.factor == 2.0:
					foreground.draw_string(font, p + Vector2(-55, 26), "增伤", HORIZONTAL_ALIGNMENT_CENTER, 110, 13, Color("#ff969c"))
			"drone":
				foreground.draw_colored_polygon(PackedVector2Array([p + Vector2(-29, -10), p + Vector2(-12, -5), p + Vector2(12, -5), p + Vector2(29, -10), p + Vector2(23, 4), p + Vector2(-23, 4)]), Color("#849ac7"))
				foreground.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -17), p + Vector2(14, -4), p + Vector2(9, 12), p + Vector2(0, 19), p + Vector2(-9, 12), p + Vector2(-14, -4)]), Color("#c3e4ff"))
				foreground.draw_circle(p, 8.0, Color("#3c8bff"), true, -1, true)
				foreground.draw_circle(p, 4.0, Color("#a5f0ff"), true, -1, true)
				for side: int in [-1, 1]:
					var rotor: Vector2 = p + Vector2(side * 26, -14)
					foreground.draw_set_transform(rotor, 0.0, Vector2(1.0, 0.18))
					foreground.draw_circle(Vector2.ZERO, 14.0 + sin(effect_time * 24.0) * 1.5, Color("#e2efff"), true, -1, true)
					foreground.draw_set_transform(Vector2.ZERO)
			"supply":
				if p.y < _surface_y(p.x) - 19.0:
					var canopy: PackedVector2Array = PackedVector2Array()
					for step: int in 17:
						canopy.append(p + Vector2.from_angle(PI + step * PI / 16.0) * 26.0 + Vector2(0, -48))
					foreground.draw_colored_polygon(canopy, Color("#94d6c5"))
					foreground.draw_line(p + Vector2(-24, -48), p + Vector2(-10, -14), Color("#8db9c6"), 1.5, true)
					foreground.draw_line(p + Vector2(24, -48), p + Vector2(10, -14), Color("#8db9c6"), 1.5, true)
				foreground.draw_rect(Rect2(p - Vector2(16, 14), Vector2(32, 28)), Color("#438c78"))
				foreground.draw_rect(Rect2(p - Vector2(3, 8), Vector2(6, 16)), Color("#d9ffee"))
				foreground.draw_rect(Rect2(p - Vector2(8, 3), Vector2(16, 6)), Color("#d9ffee"))
	for hazard: Dictionary in state.hazards:
		var p: Vector2 = Vector2(hazard.x, _surface_y(hazard.x))
		if hazard.kind == "fire":
			for index: int in 11:
				var x: float = p.x + (index - 5) * 10.0
				var base: Vector2 = Vector2(x, _surface_y(x))
				var height: float = 12.0 + (sin(effect_time * 7.0 + index * 1.7) + 1.0) * 12.0
				foreground.draw_colored_polygon(PackedVector2Array([base - Vector2(5, 0), base + Vector2(3, -height), base + Vector2(6, 0)]), Color("#ff9b48"))
		else:
			foreground.draw_circle(p - Vector2(0, 4), 8.0, Color("#823652"), true, -1, true)
			foreground.draw_circle(p - Vector2(0, 7), 3.0, Color("#ff99c2"), true, -1, true)
			foreground.draw_string(font, p + Vector2(-40, 24), "地雷", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("#ffa3c3"))
