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
var lit_surface: ArrayMesh = ArrayMesh.new()
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
@onready var foreground: Node2D = $World/Foreground
@onready var light_layer: Node2D = $World/LightLayer
@export var falloff: GradientTexture2D
var models: Array[TankModel] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()
	terrain.draw.connect(_draw_terrain)
	light_layer.draw.connect(_draw_lights)
	foreground.draw.connect(_draw_foreground)
	resized.connect(_resize_world)
	_resize_world()

func _resize_world() -> void:
	world.scale = size / Vector2(1920, 1080)

func _process(delta: float) -> void:
	effect_time += delta
	for i: int in range(flashes.size() - 1, -1, -1):
		flashes[i].life -= delta
		if flashes[i].life <= 0.0:
			flashes.remove_at(i)
	for i: int in models.size():
		var tank: Dictionary = state.tanks[i]
		var degrees: float = aim_angle if i == state.active and show_aim and state.phase == "aim" else float(tank.aim)
		var tint: Color = Color(tank.color)
		if state.mode == "teams":
			tint = [Color("#73d9ed"), Color("#ff947d")][tank.team]
		models[i].pose(tank, degrees, tint, delta)
	light_layer.queue_redraw()
	foreground.queue_redraw()

func update_state(value: Dictionary) -> void:
	state = value
	if ground_profile != state.terrain:
		ground_profile = state.terrain
		_rebuild_surface_light()
	while models.size() < state.tanks.size():
		var model: TankModel = TankScene.instantiate()
		world.add_child(model)
		models.append(model)
	terrain.queue_redraw()
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
	terrain.draw_colored_polygon(land, GROUND)
	terrain.draw_mesh(lit_surface, null)

## Pair each surface vertex with the one directly underneath it. An impact can
## change the silhouette without changing the direction the light falls into the soil.
func _rebuild_surface_light() -> void:
	var vertices: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	for i: int in ground_profile.size():
		var surface: Vector2 = Vector2(i * Battle.CELL, ground_profile[i])
		var light: float = 0.5 + 0.5 * cos(surface.x / 510.0)
		vertices.append(surface)
		colors.append(Color("#168de7").lerp(Color("#38dbf1"), light))
		vertices.append(surface + Vector2(0, 179))
		colors.append(GROUND)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	lit_surface.clear_surfaces()
	lit_surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)

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
	if show_aim and state.phase == "aim":
		_aim()
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
	if state.phase == "over":
		return
	var wind: float = state.wind
	var info: String = "风  %s %d" % ["→" if wind >= 0 else "←", roundi(absf(wind))]
	if state.mode != "training":
		info = "%s 的回合     %s" % [state.tanks[state.active].name, info]
		if state.phase == "aim":
			info += "     %d 秒" % ceili(state.time)
		if state.turn > state.tanks.size() * 8:
			info += "     决胜阶段 · 每回合损失 12 生命"
	foreground.draw_string(font, Vector2(38, 57), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	if state.notice_left > 0.0:
		foreground.draw_string(font, Vector2(38, 90), state.notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#91c6dc"))
	foreground.draw_string(font, Vector2(1740, 54), "Esc  菜单", HORIZONTAL_ALIGNMENT_RIGHT, 142, 17, INK)

func _tank_label(index: int) -> void:
	var tank: Dictionary = state.tanks[index]
	if tank.hp <= 0:
		return
	var p: Vector2 = Vector2(tank.x, tank.y)
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
	if index == state.active and state.phase == "aim":
		var marker: Vector2 = p + Vector2(0, -63 if state.mode == "training" else -89)
		foreground.draw_colored_polygon(PackedVector2Array([marker - Vector2(6, 0), marker + Vector2(6, 0), marker + Vector2(0, 7)]), INK)

func _aim() -> void:
	var direction: Vector2 = Vector2.from_angle(-deg_to_rad(aim_angle))
	var pos: Vector2 = world.to_local(models[state.active].muzzle.global_position)
	var velocity: Vector2 = direction * (270.0 + aim_power * 6.0) * (0.82 if weapon == 1 else 1.0)
	for i: int in 15:
		velocity += Battle.projectile_acceleration(state, pos) * 0.045
		pos += velocity * 0.045
		var obstacle: bool = false
		for event: Dictionary in state.events:
			if event.kind == "portal":
				obstacle = obstacle or pos.distance_to(event.pos) < Battle.PORTAL_RADIUS or pos.distance_to(event.exit) < Battle.PORTAL_RADIUS
			elif event.kind == "bumper":
				obstacle = obstacle or pos.distance_to(event.pos) < Battle.BUMPER_RADIUS
			elif event.kind == "black_hole":
				obstacle = obstacle or pos.distance_to(event.pos) < Battle.BLACK_HOLE_CORE
		if obstacle:
			break
		if pos.x < 0.0 or pos.x > Battle.WIDTH or pos.y >= state.terrain[roundi(pos.x / Battle.CELL)]:
			break
		foreground.draw_circle(pos, lerpf(2.8, 1.1, i / 14.0), INK, true, -1, true)

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


## Events use a few solid shapes. Small halos separate them from the backdrop.
func _event_lights() -> void:
	for event: Dictionary in state.events:
		match event.kind:
			"black_hole":
				_glow(event.pos, 64.0, Color(0.48, 0.36, 0.85, 0.18))
			"portal":
				_glow(event.pos, 48.0, Color(0.2, 0.8, 1.0, 0.18))
				_glow(event.exit, 48.0, Color(1.0, 0.55, 0.3, 0.18))
			"amplifier":
				_glow(event.pos, event.radius * 1.5, Color(0.65, 1, 0.3, 0.14))
			"supply":
				_glow(event.pos, 35.0, Color(0.3, 1.0, 0.62, 0.2))
	for hazard: Dictionary in state.hazards:
		var p: Vector2 = Vector2(hazard.x, _surface_y(hazard.x) - 10.0)
		_glow(p, 75.0 if hazard.kind == "fire" else 25.0, Color(1, 0.3, 0.1, 0.55) if hazard.kind == "fire" else Color(1, 0.15, 0.4, 0.6))

func _surface_y(x: float) -> float:
	return state.terrain[clampi(roundi(x / Battle.CELL), 0, 480)]

func _event_caption(point: Vector2, text: String, color: Color) -> void:
	foreground.draw_string(font, point + Vector2(-110, 64), text, HORIZONTAL_ALIGNMENT_CENTER, 220, 15, color)

func _portal(point: Vector2, tint: Color, phase: float) -> void:
	foreground.draw_circle(point, Battle.PORTAL_RADIUS - 5.0, Color("#0c1930"), true, -1, true)
	for half: int in 2:
		var band: PackedVector2Array = PackedVector2Array()
		for i: int in 25:
			var a: float = phase + half * PI + i * PI * 0.83 / 24.0
			band.append(point + Vector2.from_angle(a) * Battle.PORTAL_RADIUS)
		for i: int in range(24, -1, -1):
			var a: float = phase + half * PI + i * PI * 0.83 / 24.0
			band.append(point + Vector2.from_angle(a) * (Battle.PORTAL_RADIUS - 6.0))
		foreground.draw_colored_polygon(band, tint)
	foreground.draw_circle(point, 4.0, tint, true, -1, true)

func _draw_events() -> void:
	for event: Dictionary in state.events:
		var p: Vector2 = event.pos
		var remaining: int = event.expires - state.turn + 1
		match event.kind:
			"black_hole":
				for arm: int in 3:
					var ribbon: PackedVector2Array = PackedVector2Array()
					for step: int in 25:
						var t: float = step / 24.0
						var a: float = arm * TAU / 3.0 - effect_time * 0.65 + t * 1.8
						ribbon.append(p + Vector2.from_angle(a) * lerpf(47.0, 21.0, t))
					for step: int in range(24, -1, -1):
						var t: float = step / 24.0
						var a: float = arm * TAU / 3.0 - effect_time * 0.65 + t * 1.8
						ribbon.append(p + Vector2.from_angle(a) * lerpf(40.0, 13.0, t))
					foreground.draw_colored_polygon(ribbon, [Color("#9e88d5"), Color("#7966b6"), Color("#b0a4e2")][arm])
				foreground.draw_circle(p, Battle.BLACK_HOLE_CORE, Color("#040812"), true, -1, true)
				_event_caption(p, "黑洞 · %d 回合" % remaining, Color("#b7abd9"))
			"portal":
				_portal(p, Color("#65dafa"), effect_time * 0.6)
				_portal(event.exit, Color("#ffa76c"), -effect_time * 0.6)
				_event_caption(p, "传送 A ↔ B · %d" % remaining, Color("#94ddee"))
				_event_caption(event.exit, "传送 B ↔ A · %d" % remaining, Color("#f2b78f"))
			"bumper":
				foreground.draw_circle(p, Battle.BUMPER_RADIUS, Color("#3288d2"), true, -1, true)
				foreground.draw_colored_polygon(PackedVector2Array([p + Vector2(-16, 5), p + Vector2(0, -12), p + Vector2(16, 5), p + Vector2(0, -2)]), Color("#caeeff"))
				_event_caption(p, "反弹 · %d 回合" % remaining, Color("#8cc8f6"))
			"amplifier":
				var tint: Color = Color("#e6b0ff") if event.factor == 3.0 else Color("#b8ed76")
				foreground.draw_circle(p, event.radius, Color(tint, 0.1), true, -1, true)
				foreground.draw_string(font, p + Vector2(-55, 12), "×%d" % int(event.factor), HORIZONTAL_ALIGNMENT_CENTER, 110, 30 if event.factor == 3.0 else 40, tint)
				_event_caption(p, "增伤 · %d 回合" % remaining, tint)
			"drone":
				var body: PackedVector2Array = PackedVector2Array([p + Vector2(-24, 0), p + Vector2(-10, -10), p + Vector2(10, -10), p + Vector2(24, 0), p + Vector2(7, 8), p + Vector2(-7, 8)])
				foreground.draw_colored_polygon(body, Color("#74bcae"))
				foreground.draw_rect(Rect2(p + Vector2(-34, -15), Vector2(22, 4)), Color("#b7e6da"))
				foreground.draw_rect(Rect2(p + Vector2(12, -15), Vector2(22, 4)), Color("#b7e6da"))
				foreground.draw_circle(p, 4.0, Color("#ddfff0"), true, -1, true)
				_event_caption(p, "无人机 · 射中支援 · %d" % remaining, Color("#a3d4c5"))
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
				foreground.draw_string(font, p + Vector2(-90, 38), "补给", HORIZONTAL_ALIGNMENT_CENTER, 180, 15, Color("#97d7b8"))
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
