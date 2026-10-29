extends SceneTree
## Deterministic integration checks for the actual game simulation, no test-only physics.
const Game = preload("res://scripts/game.gd")
const DT := 1.0 / 60.0
var game: Node2D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = Game.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	reset()
	verify(game.units.size() == 6 and game.team_hp(0) == 300 and game.team_hp(1) == 300, "three healthy tanks per team")
	var valid_spawn := true
	for unit in game.units:
		valid_spawn = valid_spawn and not game.terrain.solid_at(unit.pos) and unit.pos.y < game.WATER - 20
	verify(valid_spawn, "all tank centers spawn above solid ground and water")
	tick(120)
	verify(game.team_hp(0) == 300 and game.team_hp(1) == 300, "spawn settling does not damage tanks")
	verify(game.units[0].grounded, "tank remains grounded after fixed-step settling")
	var old_position: Vector2 = game.units[0].pos
	game.jump_active()
	verify(game.units[0].vel.y < 0 and game.fuel == 185, "jump uses movement and launches tank")
	tick(90)
	verify(game.units[0].grounded and game.units[0].hp == 100, "ordinary jump lands safely")
	verify(absf(game.units[0].pos.y - old_position.y) < 5, "jump lands on the same surface")

	reset()
	game.weapon = 1
	game.angle = -0.8
	game.charging = true
	game.fire_shot(0.65)
	verify(game.phase == "flight" and game.projectiles.size() == 1 and not game.charging, "releasing charge starts one flight")
	verify(game.ammunition[0][1] == 1 and game.shots_fired == 1, "special ammunition consumed exactly once")
	game.fire_shot(1.0)
	verify(game.projectiles.size() == 1 and game.ammunition[0][1] == 1, "repeat fire rejected during flight")
	reset()
	game.ammunition[0][2] = 0
	game.select_weapon(2)
	verify(game.weapon == 0, "empty special weapon cannot be selected")

	reset()
	var target: Vector2 = game.units[3].pos
	game.explode(target + Vector2(20, 12), 65, 64)
	verify(game.units[3].hp > 0 and game.units[3].hp < 100, "radial explosion deals distance-scaled damage")
	verify(game.units[3].vel.length() > 50 and game.units[3].vel.y < 0, "explosion adds upward radial knockback")
	verify(game.units[0].hp == 100, "distant units are not damaged")
	var friendly: Vector2 = game.units[0].pos
	game.explode(friendly + Vector2(0, 25), 65, 40)
	verify(game.units[0].hp < 100, "friendly fire is enabled")

	reset()
	var terrain_before: int = game.terrain.get_solid_count()
	game.wind = 0
	game.angle = 0.25
	game.units[0].angle = game.angle
	game.fire_shot(0.3)
	var saw_settle := false
	var frames := 0
	while game.turn == 1 and game.phase != "over" and frames < 1200:
		game._physics_process(DT)
		saw_settle = saw_settle or game.phase == "settle"
		frames += 1
	verify(game.terrain.get_solid_count() < terrain_before, "real swept projectile collision creates a crater")
	verify(saw_settle, "shot enters post-impact settling phase")
	verify(game.turn == 2 and game.team == 1 and game.active == 3, "shot and terrain/body settling hand off to opponent")
	verify(game.projectiles.is_empty(), "projectile is removed after impact")
	verify(game.turn_left == game.TURN_SECONDS, "next turn receives a fresh timer")

	reset()
	var ground: float = game.terrain.surface_y(600)
	game.projectiles.append(projectile(Vector2(600, ground - 10), Vector2(0, 100), 1, 0.3))
	var bounced := false
	for i in 20:
		game.update_projectiles(DT)
		if not game.projectiles.is_empty() and game.projectiles[0].bounces > 0:
			bounced = true
			break
	verify(bounced, "bouncer reflects from terrain before its fuse")
	if not game.projectiles.is_empty():
		game.projectiles[0].age = 2.59
		game.update_projectiles(0.02)
	verify(game.projectiles.is_empty() and not game.rings.is_empty(), "bouncer detonates at 2.6-second fuse")
	reset()
	game.projectiles.append(projectile(Vector2(720, 250), Vector2(180, -2), 2, 0.4))
	game.update_projectiles(DT)
	var all_children: bool = game.projectiles.size() == 3
	for p in game.projectiles: all_children = all_children and p.kind == 3
	verify(all_children, "split shot divides into three live shells at apex")
	var original_x: float = game.projectiles[0].pos.x
	game.update_projectiles(DT)
	verify(game.projectiles[0].pos.x != original_x, "split shells continue their own trajectories")

	reset()
	game.turn_left = 0.001
	game._physics_process(DT)
	verify(game.phase == "settle" and not game.charging, "empty timer safely ends uncharged turn")
	tick(150)
	verify(game.turn == 2 and game.team == 1, "timeout resolves to opposing team")
	reset()
	game.turn_left = 0.001
	game.charging = true
	game.charge = 0.4
	game._physics_process(DT)
	verify(game.phase == "flight" and game.projectiles.size() == 1, "timeout releases an in-progress charge")
	reset()
	var sequence: Array[int] = [game.active]
	for i in 5:
		game.finish_turn()
		sequence.append(game.active)
	verify(sequence == [0, 3, 1, 4, 2, 5], "hotseat rotates both teams and all three tanks")
	reset()
	game.kill_unit(3, false)
	game.finish_turn()
	verify(game.active == 4 and game.units[game.active].hp > 0, "turn selection skips eliminated tank")

	reset()
	game.units[1].pos = Vector2(720, 805)
	game.units[1].grounded = false
	game.update_units(DT)
	verify(game.units[1].hp == 0 and game.units[1].get("dead", false), "water removes tank exactly once")
	var particles_before: int = game.particles.size()
	game.kill_unit(1, true)
	verify(game.particles.size() == particles_before, "repeat water death does not duplicate effects")
	reset()
	game.units[1].pos.y -= 200
	game.units[1].vel = Vector2(0, 450)
	game.units[1].grounded = false
	for i in 120:
		game.update_units(DT)
		if game.units[1].grounded: break
	verify(game.units[1].hp < 100 and game.units[1].hp > 0, "hard landings apply fall damage")
	reset()
	for i in [3, 4, 5]: game.kill_unit(i, false)
	verify(game.check_winner() and game.winner == 0 and game.phase == "over", "last living crew wins")
	game.begin_match(100)
	verify(game.units.size() == 6 and game.team_hp(0) == 300 and game.team_hp(1) == 300, "restart restores all units")
	verify(game.phase == "handoff" and game.turn == 1 and game.ammunition[0][1] == 2 and game.shots_fired == 0, "restart clears match state and replenishes specials")
	reset()
	for i in 6: game.kill_unit(i, false)
	verify(game.check_winner() and game.winner == -1, "simultaneous crew elimination is a draw")

	reset()
	for i in [1, 2, 4, 5]: game.kill_unit(i, false)
	game.units[0].pos = Vector2(720, 801)
	game.units[0].vel = Vector2.ZERO
	game.units[0].grounded = false
	game.units[3].pos = Vector2(720, 700)
	game.units[3].vel = Vector2.ZERO
	game.units[3].grounded = false
	game.phase = "settle"
	game.phase_time = 0.0
	game._physics_process(DT)
	verify(game.phase != "over", "victory waits for the remaining airborne tank to settle")
	tick(180)
	verify(game.phase == "over" and game.winner == -1, "staggered final water deaths resolve as a draw")

	reset()
	game.charging = true
	game.charge = 0.4
	key(KEY_ESCAPE)
	var timer_before: float = game.turn_left
	tick(120)
	verify(game.paused and not game.charging and game.turn_left == timer_before, "pause cancels charge and freezes timer")
	key(KEY_ESCAPE)
	verify(game.interactive() and game.projectiles.is_empty(), "resume does not release a stale shot")
	game.charging = true
	key(KEY_H)
	verify(game.help_open and not game.charging, "field guide cancels charge")
	timer_before = game.turn_left
	tick(120)
	verify(game.turn_left == timer_before, "field guide freezes the match")
	key(KEY_ESCAPE)
	verify(game.interactive(), "closing guide returns to playable turn")
	game.charging = true
	key(KEY_R)
	verify(game.confirm_restart and not game.charging, "restart asks before discarding match")
	game.click_button("cancel_restart")
	verify(game.interactive() and game.turn == 1, "cancel restart preserves active turn")

	reset()
	game.charging = true
	game.charge = 0.6
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	timer_before = game.turn_left
	tick(120)
	verify(game.paused and not game.charging and game.charge == 0.0 and game.turn_left == timer_before, "focus loss pauses and discards pending charge")
	game.click_button("resume")
	verify(game.interactive() and game.projectiles.is_empty(), "resume after focus loss does not fire")
	reset()
	game.menu = true
	game.help_open = true
	key(KEY_ENTER)
	verify(game.menu and game.help_open, "Enter behind menu help does not start a hidden match")
	key(KEY_ESCAPE)
	key(KEY_ENTER)
	verify(not game.menu and game.phase == "handoff", "Enter starts match after guide dismissal")
	reset()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(960, 850)
	mouse.global_position = mouse.position
	# Dummy headless pointer is (0,0); offset the viewport canvas to exercise UI-space guards.
	root.canvas_transform = Transform2D(0, -mouse.position)
	game._unhandled_input(mouse)
	verify(game.pointer.distance_to(Vector2(960, 850)) < 1 and not game.charging, "blank bottom HUD click cannot start charging")
	mouse.pressed = false
	game._unhandled_input(mouse)
	verify(game.projectiles.is_empty(), "release after HUD click cannot fire a shell")
	root.canvas_transform = Transform2D.IDENTITY

	reset()
	game.auto_demo = true
	for i in 7200:
		game._physics_process(DT)
		if game.turn >= 8 or game.phase == "over": break
	verify(game.turn >= 8 or game.phase == "over", "repeated live shots do not stall turn resolution")
	game.auto_demo = false

	print("GAMEPLAY: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

func reset() -> void:
	game.begin_match(54672)
	game.menu = false
	game.phase = "aim"
	game.aim_mouse = false
	game.wind = 0

func tick(frames: int) -> void:
	for i in frames: game._physics_process(DT)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func projectile(pos: Vector2, velocity: Vector2, kind: int, age: float) -> Dictionary:
	return {"pos": pos, "prev": pos, "vel": velocity, "age": age,
		"kind": kind, "owner": 0, "trail": [], "bounces": 0}

func verify(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)
