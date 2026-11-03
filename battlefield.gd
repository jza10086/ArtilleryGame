extends Control
## Original vector battlefield. Draw coordinates use the 1920×1080 design space.
const Battle: Script = preload("res://games/minigame/godot_party_default_artillery_game/battle.gd")
var state: Dictionary = {}
var aim_angle: float = 45.0
var aim_power: float = 60.0
var weapon: int = 0
var show_aim: bool = false
var clock: float = 0.0
var last_impact: int = 0
var flashes: Array[Dictionary] = []
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()

func _process(delta: float) -> void:
	clock += delta
	for i: int in range(flashes.size() - 1, -1, -1):
		flashes[i].life -= delta
		if flashes[i].life <= 0.0:
			flashes.remove_at(i)
	queue_redraw()

func update_state(value: Dictionary) -> void:
	state = value
	for impact: Dictionary in state.impacts:
		if impact.id > last_impact:
			flashes.append({"pos": impact.pos, "radius": impact.radius, "weapon": impact.weapon, "life": 0.75})
			last_impact = impact.id

func _text(value: String, pos: Vector2, height: int, tint: Color, centered: bool = false) -> void:
	var offset: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, height).x * 0.5 if centered else 0.0
	draw_string(font, pos - Vector2(offset, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, height, tint)

func _draw() -> void:
	if font == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1920, 1080))
	for band: int in 48:
		var t: float = float(band) / 47.0
		draw_rect(Rect2(0, band * 23, 1920, 24), Color("091322").lerp(Color("274b5b"), t))
	for i: int in 65:
		var p: Vector2 = Vector2(fposmod(i * 317.5, 1920.0), 130.0 + fposmod(i * 73.7, 370.0))
		draw_circle(p, 1.3, Color(0.65, 0.85, 1.0, 0.2 + 0.12 * sin(clock + i)), true, -1, true)
	draw_circle(Vector2(1560, 260), 65.0, Color(0.5, 0.85, 0.95, 0.03), true, -1, true)
	draw_circle(Vector2(1560, 260), 49.0, Color("8cb9c5"), true, -1, true)
	draw_circle(Vector2(1579, 247), 45.0, Color("142a3c"), true, -1, true)
	for layer: int in 3:
		var mountains: PackedVector2Array = PackedVector2Array([Vector2(0, 1080)])
		for i: int in 41:
			var x: float = i * 48.0
			var y: float = 600.0 + layer * 65.0 + sin(x * (0.003 + layer * 0.001) + layer) * 70.0 + cos(x * 0.014 + layer) * 28.0
			mountains.append(Vector2(x, y))
		mountains.append(Vector2(1920, 1080))
		draw_colored_polygon(mountains, [Color("183244"), Color("1b3d4a"), Color("214a51")][layer])
	if state.is_empty():
		return
	var surface: PackedVector2Array = PackedVector2Array()
	var polygon: PackedVector2Array = PackedVector2Array([Vector2(0, 1080)])
	for i: int in state.terrain.size():
		var p: Vector2 = Vector2(i * 4.0, state.terrain[i])
		surface.append(p)
		polygon.append(p)
	polygon.append(Vector2(1920, 1080))
	draw_colored_polygon(polygon, Color("102a31"))
	for level: int in 5:
		var contour: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in surface:
			contour.append(p + Vector2(0, 25 + level * 34))
		draw_polyline(contour, Color(0.2, 0.5, 0.48, 0.14), 1.5, true)
	draw_polyline(surface, Color(0.25, 0.95, 0.74, 0.08), 15.0, true)
	draw_polyline(surface, Color(0.35, 1.0, 0.77, 0.2), 7.0, true)
	draw_polyline(surface, Color("7be4b8"), 2.5, true)
	draw_rect(Rect2(0, 970, 1920, 110), Color(0.8, 0.25, 0.28, 0.10))
	draw_line(Vector2(0, 971), Vector2(1920, 971), Color("b3616f"), 2.0, true)
	for i: int in state.tanks.size():
		_tank(i)
	if show_aim and state.phase == "aim":
		_aim()
	for shot: Dictionary in state.projectiles:
		var tint: Color = Color(Battle.WEAPONS[shot.weapon].color)
		if shot.trail.size() >= 2:
			draw_polyline(PackedVector2Array(shot.trail), Color(tint, 0.15), 9.0, true)
			draw_polyline(PackedVector2Array(shot.trail), Color(tint, 0.85), 2.5, true)
		if shot.pos.y < 125.0:
			var x: float = clampf(shot.pos.x, 30.0, 1890.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x, 125), Vector2(x - 7, 138), Vector2(x + 7, 138)]), tint)
		draw_circle(shot.pos, 12.0, Color(tint, 0.12), true, -1, true)
		draw_circle(shot.pos, 5.0, tint, true, -1, true)
		draw_circle(shot.pos - Vector2(1, 1), 2.2, Color.WHITE, true, -1, true)
	for flash: Dictionary in flashes:
		var t: float = 1.0 - flash.life / 0.75
		var tint: Color = Color(Battle.WEAPONS[flash.weapon].color)
		var radius: float = flash.radius * (0.4 + 0.7 * t)
		draw_circle(flash.pos, radius, Color(tint, (1.0 - t) * 0.18), true, -1, true)
		draw_arc(flash.pos, radius, 0, TAU, 64, Color(tint, 1.0 - t), 4.0 * (1.0 - t) + 1, true)
		draw_circle(flash.pos, radius * (1.0 - t) * 0.55, Color(1, 0.97, 0.85, (1 - t) * 0.8), true, -1, true)
		for i: int in 18:
			var ray: Vector2 = Vector2.from_angle(i * TAU / 18.0 + flash.weapon)
			var start: Vector2 = flash.pos + ray * radius * (0.7 + t)
			draw_line(start, start + ray * 12.0 * (1.0 - t), Color(tint, 1 - t), 2.0, true)
	_scoreboard()
	var mode_name: String = {"ffa": "自由混战", "teams": "团队对抗", "training": "单人试射"}[state.mode]
	_text("火炮大战  /  " + mode_name, Vector2(40, 143), 22, Color("a9c7cc"))
	var active: Dictionary = state.tanks[state.active]
	var heading: String = "%s 的回合" % active.name
	if state.phase == "flight":
		heading = "炮弹飞行中"
	elif state.phase == "settle":
		heading = "等待战场稳定"
	elif state.phase == "over":
		heading = "对局结束"
	_text(heading, Vector2(960, 166), 30, Color("edf6f5"), true)
	var wind: float = state.wind
	_text("回合 %02d   ·   风  %s %.0f   ·   %s" % [state.turn, "→" if wind >= 0 else "←", absf(wind),
		"不限时" if state.mode == "training" else "%02d 秒" % ceili(state.time)], Vector2(960, 201), 18, Color("8baeb9"), true)
	if state.mode != "training" and state.turn > state.tanks.size() * 8:
		_text("决胜阶段 · 每回合全员损失 12 生命", Vector2(960, 234), 18, Color("ffad89"), true)

func _tank(index: int) -> void:
	var tank: Dictionary = state.tanks[index]
	var p: Vector2 = Vector2(tank.x, tank.y)
	var tint: Color = Color(tank.color) if state.mode != "teams" else [Color("65d8ff"), Color("ff8990")][tank.team]
	if tank.hp <= 0:
		draw_line(p + Vector2(-14, -8), p + Vector2(14, 7), Color("6a6e79"), 4.0, true)
		draw_line(p + Vector2(-14, 7), p + Vector2(14, -8), Color("6a6e79"), 4.0, true)
		return
	draw_circle(p + Vector2(0, 12), 29, Color(0, 0, 0, 0.18), true, -1, true)
	draw_style_box(_style(Color("091923"), 11, Color("4d6d76"), 1), Rect2(p + Vector2(-26, -3), Vector2(52, 20)))
	for i: int in 4:
		draw_circle(p + Vector2(-18 + i * 12, 7), 5.5, Color("789394"), true, -1, true)
		draw_circle(p + Vector2(-18 + i * 12, 7), 2.5, Color("233e48"), true, -1, true)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-26, -4), p + Vector2(-18, -15),
		p + Vector2(20, -15), p + Vector2(27, -4)]), tint.darkened(0.15))
	draw_circle(p + Vector2(0, -15), 13.0, tint, true, -1, true)
	var angle: float = deg_to_rad(aim_angle if index == state.active else (40.0 if tank.x < 960 else 140.0))
	var direction: Vector2 = Vector2(cos(angle), -sin(angle))
	draw_line(p + Vector2(0, -15), p + Vector2(0, -15) + direction * 35.0, tint.darkened(0.55), 10, true)
	draw_line(p + Vector2(0, -17), p + Vector2(0, -17) + direction * 34.0, tint.lightened(0.15), 5, true)
	if index == state.active and state.phase != "over":
		var bob: float = sin(clock * 4.0) * 3.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -73 + bob), p + Vector2(7, -73 + bob), p + Vector2(0, -63 + bob)]), tint)
	_text(String(tank.name).left(12), p + Vector2(0, -48), 18, Color("e5f2f2"), true)
	draw_rect(Rect2(p + Vector2(-27, -37), Vector2(54, 5)), Color("0b1c26"))
	draw_rect(Rect2(p + Vector2(-27, -37), Vector2(54.0 * tank.hp / 200.0, 5)), tint)

func _aim() -> void:
	var tank: Dictionary = state.tanks[state.active]
	var direction: Vector2 = Vector2(cos(deg_to_rad(aim_angle)), -sin(deg_to_rad(aim_angle)))
	var pos: Vector2 = Vector2(tank.x, tank.y - 12.0) + direction * 35.0
	var velocity: Vector2 = direction * (270.0 + aim_power * 6.0) * (0.82 if weapon == 1 else 1.0)
	for i: int in 17:
		velocity += Vector2(state.wind, Battle.GRAVITY) * 0.045
		pos += velocity * 0.045
		draw_circle(pos, 2.0, Color(0.8, 0.96, 0.95, 0.65 * (1.0 - float(i) / 17.0)), true, -1, true)

func _scoreboard() -> void:
	var count: int = state.tanks.size()
	var width: float = minf(225.0, 1824.0 / count)
	var left: float = (1920.0 - width * count) * 0.5
	for i: int in count:
		var tank: Dictionary = state.tanks[i]
		var tint: Color = Color(tank.color) if state.mode != "teams" else [Color("65d8ff"), Color("ff8990")][tank.team]
		var rect: Rect2 = Rect2(left + i * width + 3, 28, width - 6, 71)
		draw_style_box(_style(Color(0.025, 0.065, 0.1, 0.84), 8, Color(tint, 0.8 if i == state.active else 0.15), 2), rect)
		_text(String(tank.name).left(10), rect.position + Vector2(14, 25), 18, tint)
		_text("%s  ·  %d" % ["离线" if tank.withdrawn else "HP", tank.hp], rect.position + Vector2(14, 46), 14, Color("9db8c0"))
		draw_rect(Rect2(rect.position + Vector2(14, 56), Vector2((rect.size.x - 28) * tank.hp / 200.0, 4)), tint)

func _style(fill: Color, radius: int, border: Color, thickness: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(thickness)
	return style
