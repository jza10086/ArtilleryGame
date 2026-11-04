extends Control
## Flat vector battlefield in the same 1920 × 1080 coordinate space as the shot simulation.
const Battle: Script = preload("res://games/minigame/godot_party_default_artillery_game/battle.gd")
const TankScene: PackedScene = preload("res://games/minigame/godot_party_default_artillery_game/tank_model.tscn")
const TankModel: Script = preload("res://games/minigame/godot_party_default_artillery_game/tank_model.gd")
const SKY: Color = Color("#070d1d")
const GROUND: Color = Color("#083660")
const INK: Color = Color("#e4faff")
var far_ridge: PackedVector2Array = PackedVector2Array([
	Vector2(0, 515), Vector2(180, 435), Vector2(285, 466), Vector2(600, 310),
	Vector2(790, 415), Vector2(910, 390), Vector2(1130, 505), Vector2(1500, 295),
	Vector2(1710, 410), Vector2(1800, 385), Vector2(1920, 440), Vector2(1920, 1080), Vector2(0, 1080)])
var near_ridge: PackedVector2Array = PackedVector2Array([
	Vector2(0, 518), Vector2(195, 583), Vector2(435, 502), Vector2(550, 520), Vector2(715, 455),
	Vector2(925, 547), Vector2(1090, 490), Vector2(1210, 525), Vector2(1445, 445),
	Vector2(1640, 536), Vector2(1920, 480), Vector2(1920, 1080), Vector2(0, 1080)])
var state: Dictionary = {}
var ground_profile: PackedFloat32Array = PackedFloat32Array()
var lit_surface: ArrayMesh = ArrayMesh.new()
var aim_angle: float = 45.0
var aim_power: float = 60.0
var weapon: int = 0
var show_aim: bool = false
var last_impact: int = 0
var flashes: Array[Dictionary] = []
var font: Font
var world: Node2D = Node2D.new()
var foreground: Node2D = Node2D.new()
var light_layer: Node2D = Node2D.new()
var falloff: GradientTexture2D = GradientTexture2D.new()
var models: Array[TankModel] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()
	add_child(world)
	# All light sprites share a smooth radial mask. Only this layer adds light;
	# solid silhouettes and the HUD keep their original opacity and contrast.
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.46, 0.76, 1.0])
	ramp.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.73), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.045), Color(1, 1, 1, 0)])
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	falloff.gradient = ramp
	falloff.width = 256
	falloff.height = 256
	falloff.fill = GradientTexture2D.FILL_RADIAL
	falloff.fill_from = Vector2(0.5, 0.5)
	falloff.fill_to = Vector2(1, 0.5)
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light_layer.material = additive
	light_layer.z_index = 1
	world.add_child(light_layer)
	light_layer.draw.connect(_draw_lights)
	world.add_child(foreground)
	foreground.z_index = 2
	foreground.draw.connect(_draw_foreground)
	resized.connect(_resize_world)
	_resize_world()

func _resize_world() -> void:
	world.scale = size / Vector2(1920, 1080)

func _process(delta: float) -> void:
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
	queue_redraw()
	for impact: Dictionary in state.impacts:
		if impact.id > last_impact:
			flashes.append({"pos": impact.pos, "radius": impact.radius, "weapon": impact.weapon, "life": 0.55})
			last_impact = impact.id

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1920, 1080))
	draw_rect(Rect2(0, 0, 1920, 1080), SKY)
	draw_texture_rect(falloff, Rect2(-310, -100, 1420, 1020), false, Color("#42226879"))
	draw_texture_rect(falloff, Rect2(830, -160, 1260, 1060), false, Color("#1266a290"))
	for i: int in 56:
		var star: Vector2 = Vector2(fposmod(i * 641.3 + i * i * 23.9, 1920.0), fposmod(i * 153.1 + i * i * 17.7, 510.0))
		draw_circle(star, 0.8 + (i % 3) * 0.24, Color("#a2c9ea66"), true, -1, true)
	var moon: Vector2 = Vector2(1460, 293)
	draw_texture_rect(falloff, Rect2(moon - Vector2(182, 182), Vector2(364, 364)), false, Color("#337cd1a8"))
	draw_circle(moon, 61.0, Color("#80caff"), true, -1, true)
	draw_circle(moon + Vector2(-12, 5), 56.0, Color("#21365b"), true, -1, true)
	draw_colored_polygon(far_ridge, Color("#202c4c"))
	draw_colored_polygon(PackedVector2Array([Vector2(600, 310), Vector2(790, 415), Vector2(726, 480)]), Color("#17233e"))
	draw_colored_polygon(PackedVector2Array([Vector2(1500, 295), Vector2(1710, 410), Vector2(1584, 492)]), Color("#17233e"))
	draw_colored_polygon(near_ridge, Color("#10334d"))
	if state.is_empty():
		return
	var land: PackedVector2Array = PackedVector2Array([Vector2(0, 1080)])
	for i: int in state.terrain.size():
		land.append(Vector2(i * Battle.CELL, state.terrain[i]))
	land.append(Vector2(1920, 1080))
	draw_colored_polygon(land, GROUND)
	draw_mesh(lit_surface, null)

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
	for shot: Dictionary in state.projectiles:
		var tint: Color = Color(Battle.WEAPONS[shot.weapon].color)
		_glow(shot.pos, 39.0, Color(tint, 0.92))
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
	for i: int in state.tanks.size():
		_tank_label(i)
	if show_aim and state.phase == "aim":
		_aim()
	for shot: Dictionary in state.projectiles:
		var tint: Color = Color(Battle.WEAPONS[shot.weapon].color)
		for i: int in range(1, shot.trail.size()):
			var strength: float = float(i) / (shot.trail.size() - 1)
			foreground.draw_line(shot.trail[i - 1], shot.trail[i], Color(tint, strength * 0.88), 1.0 + strength * 2.0, true)
		if shot.pos.y < 0.0:
			var x: float = clampf(shot.pos.x, 12.0, 1908.0)
			foreground.draw_colored_polygon(PackedVector2Array([Vector2(x, 8), Vector2(x - 6, 18), Vector2(x + 6, 18)]), tint)
		foreground.draw_circle(shot.pos, 5.0, tint, true, -1, true)
		foreground.draw_circle(shot.pos, 2.8, tint.lerp(Color.WHITE, 0.88), true, -1, true)
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
	if index == state.active and state.phase == "aim":
		var marker: Vector2 = p + Vector2(0, -63 if state.mode == "training" else -89)
		foreground.draw_colored_polygon(PackedVector2Array([marker - Vector2(6, 0), marker + Vector2(6, 0), marker + Vector2(0, 7)]), INK)

func _aim() -> void:
	var direction: Vector2 = Vector2.from_angle(-deg_to_rad(aim_angle))
	var pos: Vector2 = world.to_local(models[state.active].muzzle.global_position)
	var velocity: Vector2 = direction * (270.0 + aim_power * 6.0) * (0.82 if weapon == 1 else 1.0)
	for i: int in 15:
		velocity += Vector2(state.wind, Battle.GRAVITY) * 0.045
		pos += velocity * 0.045
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
