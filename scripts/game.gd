extends Node2D
## Original fixed-step artillery simulation. Rendering is independent of terrain collision.
const TerrainScript = preload("res://scripts/terrain.gd")
const OverlayScript = preload("res://scripts/overlay.gd")
const SoundScript = preload("res://scripts/sound.gd")
const W := 1440.0
const H := 900.0
const WATER := 790.0
const GRAVITY := 510.0
const TURN_SECONDS := 35.0
const INK := Color("183e4a")
const CREAM := Color("fff2d4")
const MUTED := Color("a9d4cf")
const TEAM_COLORS := [Color("f68068"), Color("73d7bc")]
const TEAM_NAMES := ["CORAL CREW", "MINT BRIGADE"]
const WEAPON_NAMES := ["SHELL", "BOUNCER", "SPLIT SHOT"]
const WEAPON_DESC := ["A clean, classic blast", "Bounces · 2.6 second fuse", "Three shells at the apex"]
const NAMES := ["PIP", "MISO", "DOT", "BEAN", "NORI", "TOTO"]
var terrain: Node2D
var overlay: Node2D
var sound: Node
var background: Texture2D
var tank_textures: Array[Texture2D] = []
var font: Font
var bold: Font
var rng := RandomNumberGenerator.new()
var units: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var team := 0
var active := 0
var roster := [0, 0]
var ammunition := [[-1, 2, 2], [-1, 2, 2]]
var weapon := 0
var turn := 1
var phase := "aim"
var turn_left := TURN_SECONDS
var phase_time := 0.0
var stable_time := 0.0
var angle := -0.65
var charge := 0.0
var charging := false
var fuel := 210.0
var wind := 0.0
var elapsed := 0.0
var shake := 0.0
var menu := true
var paused := false
var help_open := false
var confirm_restart := false
var winner := -2
var status := ""
var status_time := 0.0
var hovered := ""
var match_seed := 0
var aim_mouse := false
var pointer := Vector2.ZERO
var shots_fired := 0
var auto_demo := false
var demo_timer := 0.0
var demo_stage := 0

func _ready() -> void:
	font = load("res://assets/ui.ttf")
	bold = load("res://assets/ui_bold.ttf")
	if ResourceLoader.exists("res://assets/background.svg"):
		background = load("res://assets/background.svg")
	for path in ["res://assets/tank_coral.svg", "res://assets/tank_mint.svg"]:
		tank_textures.append(load(path) if ResourceLoader.exists(path) else null)
	terrain = TerrainScript.new()
	add_child(terrain)
	overlay = Node2D.new()
	overlay.set_script(OverlayScript)
	add_child(overlay)
	sound = SoundScript.new()
	add_child(sound)
	rng.randomize()
	begin_match(54672)
	menu = true
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			auto_demo = true
			menu = false
			phase = "aim"
	queue_redraw()

func begin_match(seed_value: int = 0) -> void:
	match_seed = seed_value if seed_value != 0 else randi_range(1, 999999)
	rng.seed = match_seed
	terrain.generate(match_seed)
	units.clear()
	projectiles.clear()
	particles.clear()
	popups.clear()
	rings.clear()
	ammunition = [[-1, 2, 2], [-1, 2, 2]]
	roster = [0, 0]
	var positions := [180.0, 330.0, 490.0, 950.0, 1110.0, 1260.0]
	for i in 6:
		var x: float = positions[i]
		units.append({"pos": Vector2(x, terrain.surface_y(x) - 16), "vel": Vector2.ZERO,
			"hp": 100, "team": 0 if i < 3 else 1, "name": NAMES[i], "grounded": true,
			"facing": 1.0 if i < 3 else -1.0, "angle": -0.65 if i < 3 else -PI + 0.65,
			"hurt": 0.0, "step": 0.0})
	team = 0
	active = 0
	turn = 1
	winner = -2
	shots_fired = 0
	menu = false
	paused = false
	help_open = false
	confirm_restart = false
	start_turn()

func start_turn() -> void:
	weapon = 0
	fuel = 210.0
	turn_left = TURN_SECONDS
	phase = "handoff"
	phase_time = 1.65
	stable_time = 0.0
	charging = false
	charge = 0.0
	angle = units[active].angle
	wind = rng.randf_range(-32.0, 32.0)
	status = ""
	sound.play("turn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = get_global_mouse_position()
		aim_mouse = true
		hovered = button_at(pointer)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			sound.muted = not sound.muted
			return
		if event.keycode == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if event.keycode == KEY_ESCAPE:
			if help_open:
				help_open = false
			elif confirm_restart:
				confirm_restart = false
			elif not menu and phase != "over":
				paused = not paused
			charging = false
			return
		if event.keycode == KEY_H or event.keycode == KEY_F1:
			help_open = not help_open
			charging = false
			return
		if help_open or confirm_restart:
			return
		if menu and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
			menu = false
			start_turn()
			return
		if phase == "over" and event.keycode == KEY_ENTER:
			begin_match()
			return
		if event.keycode == KEY_R and not menu:
			confirm_restart = true
			charging = false
			return
		if interactive():
			if event.keycode == KEY_1: select_weapon(0)
			if event.keycode == KEY_2: select_weapon(1)
			if event.keycode == KEY_3: select_weapon(2)
			if event.keycode == KEY_W: jump_active()
			if event.keycode == KEY_Q:
				phase = "settle"
				phase_time = 0.0
				charging = false
			if event.keycode == KEY_SPACE:
				charging = true
				charge = 0.0
			if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
				aim_mouse = false
	if event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE:
		if charging and interactive(): fire_shot(charge)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = get_global_mouse_position()
		if event.pressed:
			var button := button_at(pointer)
			if button != "":
				click_button(button)
			elif interactive() and pointer.y >= 112 and pointer.y < WATER:
				aim_mouse = true
				update_mouse_aim()
				charging = true
				charge = 0.0
		elif charging and interactive():
			fire_shot(charge)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		charging = false
		charge = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not menu and phase != "over":
		charging = false
		charge = 0.0
		paused = true

func interactive() -> bool:
	return not menu and not paused and not help_open and not confirm_restart and phase == "aim" and units[active].hp > 0

func select_weapon(index: int) -> void:
	if ammunition[team][index] == 0:
		show_status("Out of ammunition", 1.4)
		return
	weapon = index
	charging = false
	charge = 0.0
	sound.play("click")

func _physics_process(dt: float) -> void:
	elapsed += dt
	update_effects(dt)
	shake = maxf(0.0, shake - dt * 24.0)
	status_time = maxf(0.0, status_time - dt)
	if menu or paused or help_open or confirm_restart:
		overlay.queue_redraw()
		return
	terrain.update_settling(dt)
	update_units(dt)
	if interactive():
		turn_left = maxf(0.0, turn_left - dt)
		if aim_mouse and not charging:
			update_mouse_aim()
		var aim_delta := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		aim_delta += float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
		if aim_delta != 0:
			angle = wrapf(angle + aim_delta * dt * 1.0, -PI, PI)
			units[active].angle = angle
			units[active].facing = 1.0 if cos(angle) >= 0 else -1.0
		if charging:
			charge = minf(1.0, charge + dt / 1.35)
		if turn_left <= 0:
			if charging:
				fire_shot(charge)
			else:
				phase = "settle"
				phase_time = 0.0
				show_status("Time's up!", 1.8)
	elif phase == "flight":
		update_projectiles(dt)
		if projectiles.is_empty():
			phase = "settle"
			phase_time = 0.0
			stable_time = 0.0
	elif phase == "settle":
		phase_time += dt
		var moving: bool = terrain.is_settling()
		for u in units:
			if u.hp > 0 and (u.vel.length() > 4.0 or not u.grounded): moving = true
		stable_time = 0.0 if moving else stable_time + dt
		if phase_time >= 1.0 and stable_time >= 0.65:
			finish_turn()
	elif phase == "handoff":
		phase_time -= dt
		if phase_time <= 0:
			phase = "aim"
	# A survivor may still be falling into the sea. Victory belongs to the
	# settled outcome, not the first frame in which the other crew reaches zero.
	if phase in ["aim", "handoff"] and (team_hp(0) == 0 or team_hp(1) == 0):
		phase = "settle"
		phase_time = 0.0
		stable_time = 0.0
		charging = false
	if auto_demo:
		update_demo(dt)
	overlay.queue_redraw()

func update_mouse_aim() -> void:
	if pointer.y > 800 or pointer.y < 112:
		return
	var offset: Vector2 = pointer - (units[active].pos + Vector2(0, -12))
	if offset.length() > 35:
		angle = offset.angle()
		units[active].angle = angle
		units[active].facing = 1.0 if cos(angle) >= 0 else -1.0

func jump_active() -> void:
	var u: Dictionary = units[active]
	if u.grounded and fuel >= 25 and not charging:
		u.vel.y = -240.0
		u.grounded = false
		fuel -= 25
		sound.play("jump")
		emit_dust(u.pos + Vector2(0, 12), 7)

func update_units(dt: float) -> void:
	for i in units.size():
		var u: Dictionary = units[i]
		if u.hp <= 0: continue
		u.hurt = maxf(0.0, u.hurt - dt)
		var movement := 0.0
		if i == active and interactive() and not charging and fuel > 0:
			movement = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		if movement != 0:
			var distance := movement * 78.0 * dt
			if move_horizontal(u, distance, true):
				fuel = maxf(0.0, fuel - absf(distance))
				u.step += dt * 10
				u.facing = movement
				if rng.randf() < dt * 12 and u.grounded: emit_dust(u.pos + Vector2(-movement * 12, 14), 1)
		if absf(u.vel.x) > 0.5:
			if not move_horizontal(u, u.vel.x * dt, false):
				u.vel.x *= -0.2
			u.vel.x = move_toward(u.vel.x, 0.0, dt * (180.0 if u.grounded else 28.0))
		var foot: bool = terrain.solid_at(u.pos + Vector2(0, 16)) or terrain.solid_at(u.pos + Vector2(-8, 16)) or terrain.solid_at(u.pos + Vector2(8, 16))
		if foot and u.vel.y >= 0:
			# A frame may begin exactly at the surface: preserve impact speed here
			# as well as in the swept-contact path below.
			if not u.grounded and u.vel.y > 340:
				apply_damage(i, int((u.vel.y - 320) * 0.16), "FALL")
				emit_dust(u.pos + Vector2(0, 14), 8)
			u.grounded = true
			u.vel.y = 0.0
		else:
			u.grounded = false
			u.vel.y = minf(820.0, u.vel.y + GRAVITY * dt)
			var dy: float = u.vel.y * dt
			var steps := maxi(1, int(ceil(absf(dy) / 3.0)))
			for step in steps:
				var next: Vector2 = u.pos + Vector2(0, dy / steps)
				var probe := 15.0 if dy >= 0 else -14.0
				if terrain.solid_at(next + Vector2(-8, probe)) or terrain.solid_at(next + Vector2(0, probe)) or terrain.solid_at(next + Vector2(8, probe)):
					if dy >= 0:
						u.grounded = true
						if u.vel.y > 340:
							apply_damage(i, int((u.vel.y - 320) * 0.16), "FALL")
							emit_dust(u.pos + Vector2(0, 14), 8)
					u.vel.y = 0.0
					break
				u.pos = next
		if u.pos.y > WATER + 9 or u.pos.x < -25 or u.pos.x > W + 25:
			kill_unit(i, true)

func move_horizontal(u: Dictionary, dx: float, allow_step: bool) -> bool:
	var dest: Vector2 = u.pos + Vector2(dx, 0)
	var side := 13.0 if dx > 0 else -13.0
	if not terrain.solid_at(dest + Vector2(side, 8)) and not terrain.solid_at(dest + Vector2(side, -5)):
		u.pos = dest
		return true
	if allow_step and u.grounded:
		for rise in range(3, 13, 3):
			var lifted := dest - Vector2(0, rise)
			if not terrain.solid_at(lifted + Vector2(side, 10)) and not terrain.solid_at(lifted + Vector2(side, -8)) and not terrain.solid_at(lifted + Vector2(0, -13)):
				u.pos = lifted
				return true
	return false

func fire_shot(power: float) -> void:
	if not interactive(): return
	charging = false
	power = clampf(power, 0.12, 1.0)
	charge = 0.0
	var u: Dictionary = units[active]
	var direction := Vector2.from_angle(angle)
	var speed := 290.0 + power * 490.0
	if weapon == 1: speed *= 0.82
	var muzzle: Vector2 = u.pos + Vector2(0, -12) + direction * 31.0
	projectiles.append({"pos": muzzle, "prev": muzzle, "vel": direction * speed, "age": 0.0,
		"kind": weapon, "owner": active, "trail": [], "bounces": 0})
	if ammunition[team][weapon] > 0: ammunition[team][weapon] -= 1
	phase = "flight"
	phase_time = 0.0
	shots_fired += 1
	shake = 2.5
	emit_sparks(muzzle, CREAM, 8, 80)
	sound.play("fire")

func update_projectiles(dt: float) -> void:
	var spawned: Array[Dictionary] = []
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p.age += dt
		p.prev = p.pos
		p.vel += Vector2(wind, 400.0) * dt
		if p.kind == 2 and p.vel.y >= 0 and p.age > 0.25:
			for offset in [-0.24, 0.0, 0.24]:
				var velocity: Vector2 = p.vel.rotated(offset) + Vector2(offset * 100, 40)
				spawned.append({"pos": p.pos, "prev": p.pos, "vel": velocity, "age": 0.3,
					"kind": 3, "owner": p.owner, "trail": [], "bounces": 0})
			emit_sparks(p.pos, Color("ffe0a1"), 12, 100)
			sound.play("fire")
			projectiles.remove_at(i)
			continue
		var displacement: Vector2 = p.vel * dt
		var steps := maxi(1, int(ceil(displacement.length() / 4.0)))
		var hit := false
		var bounced := false
		for s in steps:
			var next: Vector2 = p.pos + displacement / steps
			if terrain.solid_at(next):
				if p.kind == 1 and p.bounces < 8:
					var nx := float(terrain.solid_at(next + Vector2(-5, 0))) - float(terrain.solid_at(next + Vector2(5, 0)))
					var ny := float(terrain.solid_at(next + Vector2(0, -5))) - float(terrain.solid_at(next + Vector2(0, 5)))
					var normal := Vector2(nx, ny).normalized()
					if normal.length_squared() < 0.1: normal = -p.vel.normalized()
					p.vel = p.vel.bounce(normal) * 0.55
					p.pos += normal * 4.0
					p.bounces += 1
					bounced = true
					emit_dust(p.pos, 4)
				else: hit = true
				break
			p.pos = next
			for j in units.size():
				if units[j].hp <= 0 or (j == p.owner and p.age < 0.2): continue
				if p.pos.distance_to(units[j].pos) < 18:
					hit = true
					break
			if hit: break
		p.trail.append(p.pos)
		if p.trail.size() > 30: p.trail.pop_front()
		if p.kind == 1 and p.age >= 2.6: hit = true
		if p.pos.y >= WATER:
			emit_splash(Vector2(p.pos.x, WATER))
			sound.play("splash")
			projectiles.remove_at(i)
		elif hit:
			var radius := 65.0
			var damage := 64.0
			if p.kind == 1:
				radius = 83.0
				damage = 78.0
			elif p.kind == 3:
				radius = 43.0
				damage = 38.0
			explode(p.pos, radius, damage)
			projectiles.remove_at(i)
		elif p.pos.x < -100 or p.pos.x > W + 100 or p.pos.y < -900 or p.age > 12.0:
			show_status("Into the blue...", 1.6)
			projectiles.remove_at(i)
		elif not bounced and rng.randf() < 0.55:
			particles.append({"pos": p.pos, "vel": Vector2(rng.randf_range(-8, 8), -15), "life": 0.45, "max": 0.45, "size": 4.0, "color": Color("f8ebc4"), "gravity": -10.0})
	projectiles.append_array(spawned)

func explode(pos: Vector2, radius: float, damage: float) -> void:
	terrain.carve(pos, radius)
	shake = minf(9.0, radius * 0.12)
	rings.append({"pos": pos, "radius": radius, "life": 0.45, "max": 0.45})
	emit_sparks(pos, Color("ffc467"), 28, 230)
	emit_sparks(pos, Color("c18453"), 24, 180)
	sound.play("boom")
	for i in units.size():
		var u: Dictionary = units[i]
		if u.hp <= 0: continue
		var offset: Vector2 = u.pos - pos
		var distance: float = offset.length()
		if distance < radius + 26:
			var fraction := clampf(1.0 - distance / (radius + 26), 0.0, 1.0)
			apply_damage(i, maxi(1, int(damage * pow(fraction, 0.65))), "")
			if u.hp > 0:
				var direction := (offset.normalized() + Vector2(0, -0.65)).normalized()
				u.vel += direction * (90.0 + fraction * 280.0)
				u.grounded = false

func apply_damage(index: int, amount: int, _reason: String = "") -> void:
	if amount <= 0 or units[index].hp <= 0: return
	var u: Dictionary = units[index]
	var actual := mini(u.hp, amount)
	u.hp = maxi(0, u.hp - amount)
	u.hurt = 0.3
	popups.append({"pos": u.pos + Vector2(0, -38), "text": "−%d" % actual, "life": 1.5, "color": CREAM})
	if u.hp == 0: kill_unit(index, false)

func kill_unit(index: int, water_death: bool) -> void:
	var u: Dictionary = units[index]
	if u.get("dead", false): return
	u.hp = 0
	u.dead = true
	u.vel = Vector2.ZERO
	if water_death:
		emit_splash(Vector2(clampf(u.pos.x, 0, W), WATER))
		sound.play("splash")
		popups.append({"pos": Vector2(clampf(u.pos.x, 40, W - 40), WATER - 28), "text": "SPLASH!", "life": 1.6, "color": CREAM})
	else:
		emit_sparks(u.pos, TEAM_COLORS[u.team], 24, 170)
	if index == active and phase == "aim":
		charging = false
		phase = "settle"
		phase_time = 0.0

func check_winner() -> bool:
	var alive := [0, 0]
	for u in units:
		if u.hp > 0: alive[u.team] += 1
	if alive[0] > 0 and alive[1] > 0: return false
	winner = 0 if alive[0] > 0 else (1 if alive[1] > 0 else -1)
	if phase != "over":
		phase = "over"
		charging = false
		sound.play("win")
		if winner >= 0:
			for i in 5: emit_sparks(Vector2(350 + i * 185, 260), TEAM_COLORS[winner], 20, 210)
	return true

func finish_turn() -> void:
	if check_winner(): return
	team = 1 - team
	roster[team] = (roster[team] + (1 if turn > 1 or team == 0 else 0)) % 3
	for tries in 3:
		active = team * 3 + roster[team]
		if units[active].hp > 0: break
		roster[team] = (roster[team] + 1) % 3
	turn += 1
	start_turn()

func emit_sparks(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		var lifetime := rng.randf_range(0.35, 0.9)
		particles.append({"pos": pos, "vel": Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(speed * 0.2, speed),
			"life": lifetime, "max": lifetime, "size": rng.randf_range(3, 8), "color": color, "gravity": 300.0})

func emit_dust(pos: Vector2, count: int) -> void:
	for i in count:
		particles.append({"pos": pos, "vel": Vector2(rng.randf_range(-24, 24), rng.randf_range(-40, -10)),
			"life": 0.5, "max": 0.5, "size": rng.randf_range(3, 7), "color": Color("ead097"), "gravity": -15.0})

func emit_splash(pos: Vector2) -> void:
	emit_sparks(pos, Color("b8eee3"), 25, 160)
	rings.append({"pos": pos, "radius": 45.0, "life": 0.5, "max": 0.5})

func update_effects(dt: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= dt
		if p.life <= 0:
			particles.remove_at(i)
			continue
		p.vel.y += p.gravity * dt
		p.pos += p.vel * dt
	for i in range(popups.size() - 1, -1, -1):
		popups[i].life -= dt
		popups[i].pos.y -= dt * 35.0
		if popups[i].life <= 0: popups.remove_at(i)
	for i in range(rings.size() - 1, -1, -1):
		rings[i].life -= dt
		if rings[i].life <= 0: rings.remove_at(i)

func show_status(text: String, duration: float) -> void:
	status = text
	status_time = duration

func team_hp(index: int) -> int:
	var health := 0
	for u in units:
		if u.team == index: health += u.hp
	return health

func _draw() -> void:
	if background:
		draw_texture_rect(background, Rect2(0, 0, W, H), false)
	else:
		draw_rect(Rect2(0, 0, W, H), Color("80bfc1"))
		draw_circle(Vector2(1120, 185), 90, Color("f9d598"))

func draw_overlay(d: Node2D) -> void:
	var offset := Vector2(sin(elapsed * 85), cos(elapsed * 61)) * shake
	d.draw_set_transform(offset)
	if not menu and phase == "aim" and not paused and not help_open and not confirm_restart:
		draw_aim(d)
	for i in units.size():
		if units[i].hp > 0: draw_tank(d, i)
	for p in projectiles:
		for t in range(1, p.trail.size()):
			var alpha: float = float(t) / p.trail.size() * 0.65
			d.draw_line(p.trail[t - 1], p.trail[t], Color(CREAM, alpha), 3.5, true)
		d.draw_circle(p.pos + Vector2(1, 2), 7, INK)
		d.draw_circle(p.pos, 5.0 if p.kind == 3 else 6.0, Color("ffcf6b"))
		if p.kind == 1:
			d.draw_arc(p.pos, 10, -PI / 2, -PI / 2 + TAU * (1 - minf(1, p.age / 2.6)), 24, CREAM, 2, true)
		if p.pos.y < 12:
			var marker := Vector2(clampf(p.pos.x, 20, W - 20), 126)
			d.draw_colored_polygon(PackedVector2Array([marker + Vector2(-7, 9), marker + Vector2(0, -3), marker + Vector2(7, 9)]), CREAM)
			label(d, "%dm" % int(absf(p.pos.y) / 8), marker + Vector2(0, 29), 12, INK, true)
	for r in rings:
		var progress: float = 1.0 - r.life / r.max
		d.draw_circle(r.pos, r.radius * (0.25 + progress * 0.75), Color("fff1c9", r.life / r.max * 0.42))
		d.draw_arc(r.pos, r.radius * (0.35 + progress * 0.8), 0, TAU, 48, Color("fff3cf", r.life / r.max), 5.0 * (1.0 - progress) + 1.0, true)
	for p in particles:
		d.draw_circle(p.pos, p.size * (0.45 + p.life / p.max * 0.55), Color(p.color, p.life / p.max))
	for p in popups:
		label(d, p.text, p.pos + Vector2(1, 2), 23, INK, true, true)
		label(d, p.text, p.pos, 23, Color(p.color, minf(1, p.life * 2)), true, true)
	d.draw_set_transform(Vector2.ZERO)
	draw_water(d)
	if menu:
		draw_menu(d)
	else:
		draw_hud(d)
		if phase == "handoff" and not paused:
			var alpha := minf(1, phase_time * 2)
			panel(d, Rect2(493, 191, 454, 83), Color(INK, alpha * 0.92), 18)
			label(d, "%s'S TURN" % units[active].name, Vector2(720, 225), 25, Color(TEAM_COLORS[team], alpha), true, true)
			label(d, "Pass the keyboard to %s" % TEAM_NAMES[team].to_lower(), Vector2(720, 253), 15, Color(CREAM, alpha), true)
		if phase == "over": draw_victory(d)
	if paused or help_open or confirm_restart:
		draw_modal(d)

func draw_tank(d: Node2D, index: int) -> void:
	var u: Dictionary = units[index]
	var pos: Vector2 = u.pos
	var color: Color = TEAM_COLORS[u.team]
	var is_active := index == active and not menu and phase != "over"
	if is_active:
		d.draw_arc(pos + Vector2(0, 13), 27, 0.05, PI - 0.05, 24, Color(color, 0.8), 3, true)
		var lift := sin(elapsed * 3.8) * 3
		var marker: Vector2 = pos + Vector2(0, -64 + lift)
		d.draw_colored_polygon(PackedVector2Array([marker + Vector2(-7, -4), marker + Vector2(7, -4), marker + Vector2(0, 5)]), color)
	var rot: float = u.angle
	var pivot := pos + Vector2(0, -12)
	var muzzle := pivot + Vector2.from_angle(rot) * 29
	d.draw_line(pivot + Vector2(0, 1), muzzle + Vector2(0, 1), INK, 12, true)
	d.draw_line(pivot, muzzle, color.lightened(0.08), 7, true)
	d.draw_circle(muzzle, 5, INK)
	d.draw_circle(muzzle, 2, color.darkened(0.3))
	if tank_textures.size() > u.team and tank_textures[u.team] != null:
		d.draw_texture_rect(tank_textures[u.team], Rect2(pos - Vector2(34, 28), Vector2(68, 49)), false, Color.WHITE if u.hurt <= 0 else Color("fff4cf"))
	else:
		panel(d, Rect2(pos.x - 24, pos.y + 2, 48, 18), INK, 9)
		for x in [-15, 0, 15]:
			d.draw_circle(pos + Vector2(x, 11), 5, Color("627b75"))
		panel(d, Rect2(pos.x - 23, pos.y - 10, 46, 21), color, 8)
		panel(d, Rect2(pos.x - 14, pos.y - 23, 28, 20), color.lightened(0.15), 9)
		d.draw_circle(pos + Vector2(u.facing * 7, -16), 3, INK)
	# Keep names readable when blast knockback gathers tanks in one crater.
	var name_y := pos.y - 45
	for j in index:
		if units[j].hp > 0 and absf(units[j].pos.x - pos.x) < 74 and absf(units[j].pos.y - pos.y) < 36:
			name_y = minf(name_y, units[j].pos.y - 67)
	var health_y := name_y + 6
	panel(d, Rect2(pos.x - 24, health_y, 48, 5), Color(INK, 0.45), 2)
	panel(d, Rect2(pos.x - 24, health_y, 48 * u.hp / 100.0, 5), color, 2)
	label(d, "%s  %d" % [u.name, u.hp], Vector2(pos.x, name_y), 12, INK, true, true)
	if charging and is_active:
		panel(d, Rect2(pos.x - 31, pos.y + 30, 62, 9), INK, 4)
		panel(d, Rect2(pos.x - 28, pos.y + 33, 56 * charge, 3), Color("ffd27d"), 2)

func draw_aim(d: Node2D) -> void:
	var u: Dictionary = units[active]
	var direction := Vector2.from_angle(angle)
	var muzzle: Vector2 = u.pos + Vector2(0, -12) + direction * 34
	var p := muzzle
	var power := maxf(0.12, charge) if charging else 0.55
	var velocity := direction * (290 + power * 490) * (0.82 if weapon == 1 else 1.0)
	for i in 17:
		velocity += Vector2(wind, 400) * 0.07
		p += velocity * 0.07
		if p.y > WATER or terrain.solid_at(p): break
		var alpha := (1.0 - float(i) / 18) * (0.8 if charging else 0.48)
		d.draw_circle(p, 2.2 if i % 3 != 0 else 3.0, Color(CREAM, alpha))
	var sight := muzzle + direction * 42
	d.draw_arc(sight, 8, 0, TAU, 16, Color(INK, 0.5), 1.3, true)
	d.draw_line(sight - Vector2(0, 12), sight + Vector2(0, 12), Color(INK, 0.32), 1, true)
	d.draw_line(sight - Vector2(12, 0), sight + Vector2(12, 0), Color(INK, 0.32), 1, true)

func draw_water(d: Node2D) -> void:
	d.draw_rect(Rect2(0, WATER, W, H - WATER), Color("287480", 0.94))
	var points := PackedVector2Array()
	for x in range(0, 1445, 8):
		points.append(Vector2(x, WATER + sin(x * 0.018 + elapsed * 1.3) * 2.2 + sin(x * 0.045 - elapsed) * 1.2))
	d.draw_polyline(points, Color("a7dacf", 0.75), 3, true)
	for i in 24:
		var x := fmod(i * 67.0 + elapsed * (4 + i % 3), W)
		var y := WATER + 17 + (i * 17) % 90
		d.draw_line(Vector2(x, y), Vector2(x + 19 + i % 5 * 4, y), Color("9bcfc7", 0.14), 2, true)

func draw_hud(d: Node2D) -> void:
	for t in 2:
		var x := 32.0 if t == 0 else 1128.0
		panel(d, Rect2(x, 28, 280, 76), Color(INK, 0.88), 17)
		d.draw_circle(Vector2(x + 25, 52), 6, TEAM_COLORS[t])
		label(d, TEAM_NAMES[t], Vector2(x + 41, 59), 15, CREAM, false, true)
		label(d, "%d" % team_hp(t), Vector2(x + 254, 60), 19, TEAM_COLORS[t], true, true)
		for j in 3:
			panel(d, Rect2(x + 18 + j * 82, 77, 74, 7), Color("41626a"), 3)
			panel(d, Rect2(x + 18 + j * 82, 77, 74 * units[t * 3 + j].hp / 100.0, 7), TEAM_COLORS[t], 3)
	panel(d, Rect2(568, 26, 304, 76), Color(INK, 0.88), 17)
	var heading: String = "%s · TURN %02d" % [units[active].name, turn]
	if phase == "flight": heading = "MAKE SOME WAVES"
	if phase == "settle": heading = "LET THE DUST SETTLE"
	if phase == "over": heading = "SKIRMISH COMPLETE"
	label(d, heading, Vector2(720, 54), 14, TEAM_COLORS[team], true, true)
	label(d, "%02d" % ceili(turn_left), Vector2(720, 84), 27, CREAM if turn_left > 8 else Color("ff997d"), true, true)
	var timer_width := 98.0 * turn_left / TURN_SECONDS
	panel(d, Rect2(583, 70, 98, 5), Color("41626a"), 3)
	panel(d, Rect2(583, 70, timer_width, 5), TEAM_COLORS[team], 3)
	panel(d, Rect2(759, 70, 98, 5), Color("41626a"), 3)
	panel(d, Rect2(857 - timer_width, 70, timer_width, 5), TEAM_COLORS[team], 3)
	for i in 3:
		var r := weapon_rect(i)
		var selected := weapon == i
		var exhausted: bool = ammunition[team][i] == 0
		panel(d, r, Color("fff0d0") if selected else Color(INK, 0.6 if not exhausted else 0.3), 12)
		if hovered == "weapon%d" % i and interactive(): panel(d, r.grow(2), Color(CREAM, 0.12), 13)
		var fg := INK if selected else CREAM
		if exhausted: fg = Color("79a4a7")
		label(d, str(i + 1), r.position + Vector2(18, 30), 18, fg, true, true)
		label(d, WEAPON_NAMES[i], r.position + Vector2(35, 24), 13, fg, false, true)
		var ammo_text := "UNLIMITED" if ammunition[team][i] < 0 else "%d LEFT" % ammunition[team][i]
		label(d, ammo_text, r.position + Vector2(35, 43), 10, Color(fg, 0.65))
	label(d, "A D  MOVE     W  JUMP     ← →  AIM     HOLD SPACE / LMB  FIRE", Vector2(36, 887), 11, Color(CREAM, 0.7))
	var fuel_color: Color = TEAM_COLORS[team]
	label(d, "MOVE", Vector2(630, 839), 10, MUTED, false, true)
	panel(d, Rect2(630, 849, 88, 5), Color(INK, 0.6), 3)
	panel(d, Rect2(630, 849, 88 * fuel / 210.0, 5), fuel_color, 3)
	var wx := 798.0
	label(d, "WIND", Vector2(wx, 839), 10, MUTED, false, true)
	var sign_x := 1.0 if wind >= 0 else -1.0
	var arrow_start := Vector2(wx + 5 if wind >= 0 else wx + 50, 852)
	var arrow_end := arrow_start + Vector2(sign_x * (18 + absf(wind) * 0.7), 0)
	d.draw_line(arrow_start, arrow_end, CREAM, 2, true)
	d.draw_line(arrow_end, arrow_end + Vector2(-sign_x * 5, -4), CREAM, 2, true)
	d.draw_line(arrow_end, arrow_end + Vector2(-sign_x * 5, 4), CREAM, 2, true)
	label(d, "%d" % int(absf(wind)), Vector2(wx + 65, 857), 14, CREAM)
	label(d, "TINY BARRAGE", Vector2(1041, 841), 15, CREAM, false, true)
	label(d, "a little island. a big disagreement.", Vector2(1041, 860), 10, MUTED)
	button(d, Rect2(1311, 818, 45, 44), "?", "help", false, 18)
	button(d, Rect2(1365, 818, 43, 44), "Ⅱ", "pause", false, 18)
	if status_time > 0:
		panel(d, Rect2(520, 722, 400, 42), Color(INK, 0.86), 13)
		label(d, status, Vector2(720, 750), 16, CREAM, true)
	elif phase == "aim" and charging:
		label(d, "RELEASE TO FIRE  ·  %d%%" % int(charge * 100), Vector2(720, 761), 14, CREAM, true, true)

func draw_menu(d: Node2D) -> void:
	label(d, "A SMALL-SCALE, BIG-BLAST SKIRMISH", Vector2(720, 136), 13, INK, true, true)
	label(d, "TINY", Vector2(720, 222), 74, INK, true, true)
	label(d, "BARRAGE", Vector2(723, 308), 91, Color("f4aa76"), true, true)
	label(d, "BARRAGE", Vector2(720, 302), 91, CREAM, true, true)
	label(d, "Six tiny tanks. Two rival crews. One very fragile island.", Vector2(720, 343), 18, INK, true)
	button(d, Rect2(551, 369, 338, 61), "START SKIRMISH  →", "start", true, 21)
	label(d, "2 PLAYERS · SAME KEYBOARD · 3 TANKS EACH", Vector2(720, 455), 11, INK, true, true)
	button(d, Rect2(586, 819, 268, 45), "HOW TO PLAY", "help", false, 14)
	label(d, "Original island artillery · Godot 4", Vector2(32, 869), 12, Color(CREAM, 0.65))
	label(d, "ENTER  START     M  SOUND     F11  FULLSCREEN", Vector2(1408, 869), 11, Color(CREAM, 0.65), false, false, true)

func draw_victory(d: Node2D) -> void:
	d.draw_rect(Rect2(0, 110, W, 680), Color(INK, 0.23))
	panel(d, Rect2(420, 210, 600, 320), Color(INK, 0.96), 26)
	label(d, "ISLAND CHAMPIONS", Vector2(720, 259), 13, MUTED, true, true)
	var title: String = TEAM_NAMES[winner] if winner >= 0 else "A PERFECT DRAW"
	label(d, title, Vector2(720, 317), 34, TEAM_COLORS[winner] if winner >= 0 else CREAM, true, true)
	label(d, "Small tanks. Legendary splash damage.", Vector2(720, 354), 17, CREAM, true)
	label(d, "%d TURNS   ·   %d SHOTS   ·   %d HEALTH LEFT" % [turn, shots_fired, team_hp(winner) if winner >= 0 else 0], Vector2(720, 393), 12, MUTED, true)
	button(d, Rect2(554, 431, 332, 59), "ANOTHER ROUND  →", "restart", true, 18)

func draw_modal(d: Node2D) -> void:
	d.draw_rect(Rect2(0, 0, W, H), Color(INK, 0.6))
	if confirm_restart:
		panel(d, Rect2(440, 270, 560, 270), Color("173e4b"), 24)
		label(d, "FRESH ISLAND?", Vector2(720, 328), 28, CREAM, true, true)
		label(d, "This skirmish will be replaced with a new one.", Vector2(720, 372), 16, MUTED, true)
		button(d, Rect2(480, 424, 220, 61), "KEEP PLAYING", "cancel_restart", false, 15)
		button(d, Rect2(724, 424, 236, 61), "NEW SKIRMISH", "restart", true, 15)
	elif help_open:
		panel(d, Rect2(378, 150, 684, 600), Color("173e4b"), 26)
		label(d, "A LITTLE FIELD GUIDE", Vector2(720, 209), 27, CREAM, true, true)
		label(d, "Last crew standing wins. Mind the water.", Vector2(720, 244), 17, MUTED, true)
		var rows := [["A / D", "Roll left / right — movement is limited each turn"], ["W", "Hop over a crater (uses some movement)"], ["MOUSE / ← →", "Aim the cannon; dots preview a short arc"], ["SPACE / LEFT CLICK", "Hold to charge, release to fire"], ["1 / 2 / 3", "Shell · Bouncer · Split shot (two special shots each)"], ["Q / RIGHT CLICK", "End turn / cancel a charging shot"], ["ESC / M / F11", "Pause · sound toggle · fullscreen"]]
		for i in rows.size():
			label(d, rows[i][0], Vector2(418, 296 + i * 43), 12, Color("ffbd8c"), false, true)
			label(d, rows[i][1], Vector2(418, 314 + i * 43), 13, CREAM)
		label(d, "35 seconds per turn. Blasts carve real holes; loose ground falls.", Vector2(720, 625), 13, MUTED, true)
		label(d, "Friendly fire, knockback and hard landings all count.", Vector2(720, 648), 13, MUTED, true)
		button(d, Rect2(579, 677, 282, 49), "GOT IT", "close_help", true, 16)
	else:
		panel(d, Rect2(475, 245, 490, 365), Color("173e4b"), 26)
		label(d, "TAKE A BREATHER", Vector2(720, 305), 27, CREAM, true, true)
		label(d, "The island can wait.", Vector2(720, 342), 17, MUTED, true)
		button(d, Rect2(534, 376, 372, 57), "BACK TO THE BARRAGE", "resume", true, 17)
		button(d, Rect2(534, 447, 181, 49), "FIELD GUIDE", "help", false, 13)
		button(d, Rect2(725, 447, 181, 49), "NEW ISLAND", "ask_restart", false, 13)
		button(d, Rect2(534, 512, 372, 46), "SOUND  " + ("OFF" if sound.muted else "ON"), "sound", false, 13)

func weapon_rect(i: int) -> Rect2:
	return Rect2(32 + i * 190, 814, 178, 53)

func button_at(pos: Vector2) -> String:
	if confirm_restart:
		if Rect2(480, 424, 220, 61).has_point(pos): return "cancel_restart"
		if Rect2(724, 424, 236, 61).has_point(pos): return "restart"
		return ""
	if help_open:
		return "close_help" if Rect2(579, 677, 282, 49).has_point(pos) else ""
	if paused:
		if Rect2(534, 376, 372, 57).has_point(pos): return "resume"
		if Rect2(534, 447, 181, 49).has_point(pos): return "help"
		if Rect2(725, 447, 181, 49).has_point(pos): return "ask_restart"
		if Rect2(534, 512, 372, 46).has_point(pos): return "sound"
		return ""
	if menu:
		if Rect2(551, 369, 338, 61).has_point(pos): return "start"
		if Rect2(586, 819, 268, 45).has_point(pos): return "help"
		return ""
	if phase == "over":
		return "restart" if Rect2(554, 431, 332, 59).has_point(pos) else ""
	if Rect2(1311, 818, 45, 44).has_point(pos): return "help"
	if Rect2(1365, 818, 43, 44).has_point(pos): return "pause"
	if interactive():
		for i in 3:
			if weapon_rect(i).has_point(pos): return "weapon%d" % i
	return ""

func click_button(id: String) -> void:
	sound.play("click")
	charging = false
	match id:
		"start":
			menu = false
			start_turn()
		"help": help_open = true
		"close_help": help_open = false
		"pause": paused = true
		"resume": paused = false
		"sound": sound.muted = not sound.muted
		"ask_restart": confirm_restart = true
		"cancel_restart": confirm_restart = false
		"restart": begin_match()
		"weapon0": select_weapon(0)
		"weapon1": select_weapon(1)
		"weapon2": select_weapon(2)

func panel(d: Node2D, rect: Rect2, color: Color, radius: int = 12) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0: return
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	d.draw_style_box(style, rect)

func label(d: Node2D, text: String, pos: Vector2, size: int, color: Color, centered := false, heavy := false, right := false) -> void:
	var face: Font = bold if heavy else font
	var p := pos
	if centered: p.x -= face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	if right: p.x -= face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	d.draw_string(face, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func button(d: Node2D, rect: Rect2, text: String, id: String, primary := false, size := 16) -> void:
	var color := Color("ffcb91") if primary else Color("305d67")
	if hovered == id: color = color.lightened(0.13)
	panel(d, rect, color, 13)
	label(d, text, rect.position + Vector2(rect.size.x / 2, rect.size.y / 2 + size * 0.36), size, INK if primary else CREAM, true, true)

func update_demo(dt: float) -> void:
	if not interactive():
		demo_timer = 0.0
		return
	demo_timer += dt
	aim_mouse = false
	# Readable demonstration uses the same real shot/physics functions as play.
	if demo_timer > 1.0 and not charging:
		angle = -0.71 if team == 0 else -PI + 0.71
		units[active].angle = angle
		charging = true
		charge = 0.0
	if charging and charge > 0.70:
		fire_shot(charge)
		demo_timer = 0.0
