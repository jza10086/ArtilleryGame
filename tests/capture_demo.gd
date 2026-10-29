extends SceneTree
## Native viewport capture of actual gameplay (no fake projectile or terrain states).
var game: Node2D
var frame := 0
var elapsed := 0.0
var aim_wait := 0.0
var planned_turn := 0
var target_power := 0.5
var output := ""
var captured_impact := false

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output = arg.trim_prefix("--capture-dir=")
	if output.is_empty():
		push_error("Pass -- --capture-dir=/absolute/output/directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	game.begin_match(54672)
	game.menu = false
	game.phase = "aim"
	game.wind = 0.0
	game.aim_mouse = false
	game.sound.muted = true
	game.set_physics_process(false)

func _process(_dt: float) -> bool:
	if game == null: return false
	var dt := 1.0 / 30.0
	elapsed += dt
	game.paused = false
	if game.interactive():
		if planned_turn != game.turn:
			planned_turn = game.turn
			aim_wait = 0.0
			game.wind = 0.0
			game.select_weapon(0 if game.turn == 1 else (2 if game.turn == 2 else 1))
			var target_index := 3 if game.team == 0 else 1
			var target: Vector2 = game.units[target_index].pos
			var origin: Vector2 = game.units[game.active].pos + Vector2(0, -12)
			game.angle = -0.67 if game.team == 0 else -PI + 0.67
			game.units[game.active].angle = game.angle
			origin += Vector2.from_angle(game.angle) * 31.0
			var dx := target.x - origin.x
			var dy := target.y - origin.y
			var speed := sqrt(400 * dx * dx / (2 * pow(cos(game.angle), 2) * (dy - dx * tan(game.angle))))
			if game.weapon == 1: speed /= 0.82
			target_power = clampf((speed - 290) / 490, 0.15, 0.92)
			target_power *= 0.92 if game.weapon == 2 else 1.0
		aim_wait += dt
		if aim_wait >= 1.25 and not game.charging:
			game.charging = true
			game.charge = 0.0
		if game.charging and game.charge >= target_power:
			game.fire_shot(game.charge)
	game._physics_process(dt)
	frame += 1
	if frame % 3 == 0:
		capture.call_deferred()
	if elapsed > 18.0:
		finish.call_deferred()
	return false

func capture() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join("frames/%04d.png" % frame))
	if frame == 30: image.save_png(output.path_join("tiny-barrage-gameplay.png"))
	if not captured_impact and not game.rings.is_empty():
		image.save_png(output.path_join("tiny-barrage-impact.png"))
		captured_impact = true
	if frame == 510: image.save_png(output.path_join("tiny-barrage-aftermath.png"))

func finish() -> void:
	print("CAPTURE: %d frames, %d shots, turn %d, health %d/%d" % [frame, game.shots_fired, game.turn, game.team_hp(0), game.team_hp(1)])
	quit()
