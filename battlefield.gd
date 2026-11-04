extends Control
## Flat vector battlefield in the same 1920 × 1080 coordinate space as the shot simulation.
const Battle: Script = preload("res://games/minigame/godot_party_default_artillery_game/battle.gd")
const SKY: Color = Color("#505f80")
const GROUND: Color = Color("#20283d")
const INK: Color = Color("#fbf1df")
var far_ridge: PackedVector2Array = PackedVector2Array([
	Vector2(0, 515), Vector2(180, 435), Vector2(285, 466), Vector2(600, 310),
	Vector2(790, 415), Vector2(910, 390), Vector2(1130, 505), Vector2(1500, 295),
	Vector2(1710, 410), Vector2(1800, 385), Vector2(1920, 440), Vector2(1920, 1080), Vector2(0, 1080)])
var near_ridge: PackedVector2Array = PackedVector2Array([
	Vector2(0, 518), Vector2(195, 583), Vector2(435, 502), Vector2(550, 520), Vector2(715, 455),
	Vector2(925, 547), Vector2(1090, 490), Vector2(1210, 525), Vector2(1445, 445),
	Vector2(1640, 536), Vector2(1920, 480), Vector2(1920, 1080), Vector2(0, 1080)])
var state: Dictionary = {}
var aim_angle: float = 45.0
var aim_power: float = 60.0
var weapon: int = 0
var show_aim: bool = false
var last_impact: int = 0
var flashes: Array[Dictionary] = []
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()

func _process(delta: float) -> void:
	for i: int in range(flashes.size() - 1, -1, -1):
		flashes[i].life -= delta
		if flashes[i].life <= 0.0:
			flashes.remove_at(i)
	queue_redraw()

func update_state(value: Dictionary) -> void:
	state = value
	for impact: Dictionary in state.impacts:
		if impact.id > last_impact:
			flashes.append({"pos": impact.pos, "radius": impact.radius, "weapon": impact.weapon, "life": 0.55})
			last_impact = impact.id

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1920, 1080))
	draw_rect(Rect2(0, 0, 1920, 1080), SKY)
	draw_circle(Vector2(1440, 311), 108.0, Color("#ffc693"), true, -1, true)
	draw_colored_polygon(far_ridge, Color("#a18899"))
	draw_colored_polygon(PackedVector2Array([Vector2(600, 310), Vector2(790, 415), Vector2(726, 480)]), Color("#887c93"))
	draw_colored_polygon(PackedVector2Array([Vector2(1500, 295), Vector2(1710, 410), Vector2(1584, 492)]), Color("#887c93"))
	draw_colored_polygon(near_ridge, Color("#60647f"))
	if state.is_empty():
		return
	var land: PackedVector2Array = PackedVector2Array([Vector2(0, 1080)])
	for i: int in state.terrain.size():
		land.append(Vector2(i * Battle.CELL, state.terrain[i]))
	land.append(Vector2(1920, 1080))
	draw_colored_polygon(land, GROUND)
	for i: int in state.tanks.size():
		_tank(i)
	if show_aim and state.phase == "aim":
		_aim()
	for shot: Dictionary in state.projectiles:
		var tint: Color = Color(Battle.WEAPONS[shot.weapon].color)
		if shot.trail.size() >= 2:
			draw_polyline(PackedVector2Array(shot.trail), tint, 3.0, true)
		if shot.pos.y < 0.0:
			var x: float = clampf(shot.pos.x, 12.0, 1908.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x, 8), Vector2(x - 6, 18), Vector2(x + 6, 18)]), tint)
		draw_circle(shot.pos, 5.0, tint, true, -1, true)
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
	draw_string(font, Vector2(38, 57), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(font, Vector2(1740, 54), "Esc  菜单", HORIZONTAL_ALIGNMENT_RIGHT, 142, 17, INK)

func _tank(index: int) -> void:
	var tank: Dictionary = state.tanks[index]
	if tank.hp <= 0:
		return
	var p: Vector2 = Vector2(tank.x, tank.y)
	var tint: Color = Color(tank.color)
	if state.mode == "teams":
		tint = [Color("#73d9ed"), Color("#ff947d")][tank.team]
	# Only the chassis follows the ground. The barrel pivots at the simulation's muzzle origin.
	var cell: int = roundi(p.x / Battle.CELL)
	var slope: float = atan2(state.terrain[mini(cell + 4, 480)] - state.terrain[maxi(cell - 4, 0)], 8.0 * Battle.CELL)
	var track: PackedVector2Array = PackedVector2Array([Vector2(-28,-2), Vector2(27,-2), Vector2(19,12), Vector2(-18,12)])
	var hull: PackedVector2Array = PackedVector2Array([Vector2(-27,-1), Vector2(-20,-12), Vector2(17,-12), Vector2(28,-1)])
	var chassis: Transform2D = Transform2D(slope, p)
	draw_colored_polygon(chassis * track, tint.darkened(0.45))
	draw_colored_polygon(chassis * hull, tint)
	for wheel: int in 3:
		draw_circle(chassis * Vector2(-14 + wheel * 14, 5), 3.5, tint, true, -1, true)
	var pivot: Vector2 = p + Vector2(0, -12)
	var degrees: float = aim_angle if index == state.active else (40.0 if tank.x < 960 else 140.0)
	var direction: Vector2 = Vector2.from_angle(-deg_to_rad(degrees))
	draw_line(pivot, pivot + direction * 35.0, tint, 7.0, true)
	draw_circle(pivot, 10.0, tint, true, -1, true)
	if state.mode != "training":
		draw_string(font, p + Vector2(-84, -51), String(tank.name).left(12), HORIZONTAL_ALIGNMENT_CENTER, 168, 17, INK)
	if state.mode != "training" or tank.hp < 200:
		draw_rect(Rect2(p + Vector2(-23, -44), Vector2(46, 4)), GROUND)
		draw_rect(Rect2(p + Vector2(-23, -44), Vector2(46.0 * tank.hp / 200.0, 4)), tint)
	if index == state.active and state.phase == "aim":
		var marker: Vector2 = p + Vector2(0, -47 if state.mode == "training" else -80)
		draw_colored_polygon(PackedVector2Array([marker - Vector2(6, 0), marker + Vector2(6, 0), marker + Vector2(0, 7)]), INK)

func _aim() -> void:
	var tank: Dictionary = state.tanks[state.active]
	var direction: Vector2 = Vector2.from_angle(-deg_to_rad(aim_angle))
	var pos: Vector2 = Vector2(tank.x, tank.y - 12.0) + direction * 35.0
	var velocity: Vector2 = direction * (270.0 + aim_power * 6.0) * (0.82 if weapon == 1 else 1.0)
	for i: int in 15:
		velocity += Vector2(state.wind, Battle.GRAVITY) * 0.045
		pos += velocity * 0.045
		if pos.x < 0.0 or pos.x > Battle.WIDTH or pos.y >= state.terrain[roundi(pos.x / Battle.CELL)]:
			break
		draw_circle(pos, lerpf(2.8, 1.1, i / 14.0), INK, true, -1, true)

func _blast(flash: Dictionary) -> void:
	var t: float = 1.0 - flash.life / 0.55
	var tint: Color = Color(Battle.WEAPONS[flash.weapon].color)
	var radius: float = flash.radius
	var center: Vector2 = flash.pos
	draw_circle(center, radius * 0.62 * sin(PI * t), tint, true, -1, true)
	draw_circle(center, radius * 0.30 * (1.0 - t), INK, true, -1, true)
	for i: int in 8:
		var ray: Vector2 = Vector2.from_angle(TAU * i / 8.0 + flash.weapon * 0.3)
		var tip: Vector2 = center + ray * radius * (0.32 + t * 0.85)
		var tail: Vector2 = tip - ray * radius * (1.0 - t) * 0.24
		var side: Vector2 = ray.orthogonal() * (1.0 - t) * 5.5
		draw_colored_polygon(PackedVector2Array([tip, tail + side, tail - side]), tint)
