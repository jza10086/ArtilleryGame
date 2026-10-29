extends SceneTree

const Terrain = preload("res://scripts/terrain.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var terrain = Terrain.new()
	root.add_child(terrain)
	terrain.generate(1)
	verify(terrain.get_solid_count() > 30000, "generation provides substantial terrain")
	for x in [180.0, 330.0, 490.0, 950.0, 1110.0, 1260.0]:
		verify(terrain.surface_y(x) >= 450.0 and terrain.surface_y(x) <= 620.0, "spawn surface %.0f" % x)
	verify(not terrain.solid_at(Vector2(720, 700)), "central water channel is open")
	verify(not terrain.solid_at(Vector2(-1, 500)), "left bounds are safe")
	verify(not terrain.solid_at(Vector2(1440, 500)), "right bounds are safe")
	verify(not terrain.solid_at(Vector2(300, -1)), "upper bounds are safe")
	verify(not terrain.solid_at(Vector2(300, 900)), "lower bounds are safe")
	verify(terrain.surface_y(-1) == 900.0, "outside surface has safe sentinel")
	var original_surface: float = terrain.surface_y(330)
	var center := Vector2(330, original_surface + 90)
	var before: int = terrain.get_solid_count()
	var removed: int = terrain.carve(center, 27)
	verify(removed > 150, "explosion removes a circular volume")
	verify(terrain.get_solid_count() == before - removed, "solid count tracks removed cells exactly")
	verify(not terrain.solid_at(center), "explosion creates a real internal cavity")
	verify(terrain.solid_at(center + Vector2(0, -42)), "cavity retains its overhang")
	verify(terrain.solid_at(center + Vector2(0, 42)), "cavity retains its floor")
	verify(terrain.surface_y(330) == original_surface, "internal cavity does not flatten height-map")
	verify(not terrain.is_settling(), "connected overhang does not collapse")
	# HD contour reconstruction and collision must use the same field, including
	# a newly carved interior cavity, not just the original island surface.
	var agreement := true
	var continuous := true
	var maximum_shift := 0.0
	for i in 144:
		var a := float(i) * TAU / 144.0
		var p := center + Vector2.from_angle(a) * 27.0
		var field: float = terrain.signed_distance_at(p)
		agreement = agreement and terrain.solid_at(p) == (field >= 0.0)
		var tiny: float = terrain.signed_distance_at(p + Vector2(0.001, 0.001))
		continuous = continuous and absf(tiny - field) < 0.01
		maximum_shift = maxf(maximum_shift, absf(field))
	verify(agreement, "HD crater contour and collision use the identical continuous field")
	verify(continuous, "subpixel contour samples have no cell-sized discontinuities")
	verify(maximum_shift < 3.0, "smooth crater boundary stays within one topology cell")
	verify(terrain.carve(Vector2(720, 100), 20) == 0, "empty-air carve has no effect")
	terrain.generate(1)
	# A circular chain of overlapping blasts isolates an interior disk.
	var island := Vector2(330, 690)
	for i in range(16):
		terrain.carve(island + Vector2.from_angle(float(i) * TAU / 16.0) * 60.0, 21.0)
	verify(terrain.is_settling(), "disconnected chunk is detected")
	verify(terrain.solid_at(island), "detached chunk exists before falling")
	var after_cut: int = terrain.get_solid_count()
	var steps := 0
	while terrain.is_settling() and steps < 360:
		terrain.update_settling(1.0 / 60.0)
		steps += 1
	verify(not terrain.is_settling(), "disconnected chunk reaches stable resting state")
	verify(steps > 1 and steps < 360, "fall animates over multiple frames and terminates")
	verify(terrain.get_solid_count() == after_cut, "settling conserves terrain volume")
	verify(not terrain.solid_at(island + Vector2(0, -30)), "chunk vacates its old upper volume")
	verify(terrain.solid_at(island + Vector2(0, 55)), "chunk lands lower in its cavity")
	terrain.carve(Vector2(0, 0), 10000)
	verify(terrain.get_solid_count() == 0, "oversized edge-clipped carve removes all terrain")
	verify(not terrain.is_settling(), "empty terrain is stable")
	terrain.queue_free()
	print("TERRAIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func verify(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)
