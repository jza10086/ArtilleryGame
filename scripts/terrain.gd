class_name IslandTerrain
extends Node2D
## Original bitmap terrain. Connected ground keeps caves and overhangs; only
## genuinely disconnected islands fall. Edge rendering and collision share a
## continuously reconstructed distance field derived from the topology mask.

const CELL_SIZE := 3
const GRID_WIDTH := 480
const GRID_HEIGHT := 300
const WORLD_SIZE := Vector2(1440.0, 900.0)
const WATER_Y := 790.0
const FALL_ACCELERATION := 310.0 # cells / second squared
const MAX_FALL_SPEED := 160.0

var _mask := PackedByteArray()
# Signed distance in grid cells. Its zero contour is reconstructed continuously
# for both collision and HD rendering; the byte mask remains the topology source.
const FIELD_RADIUS := 16.0
const SQRT_2 := 1.41421356237
const HD_SHADER = preload("res://shaders/terrain.gdshader")
var _distance := PackedFloat32Array()
var _render_field := PackedFloat32Array()
var _texture: ImageTexture
var _fragments: Array[Dictionary] = []
var _count := 0
var _seed := 1
var _surface := PackedInt32Array()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var hd_material := ShaderMaterial.new()
	hd_material.shader = HD_SHADER
	if _texture != null: hd_material.set_shader_parameter("terrain_field", _texture)
	material = hd_material

func generate(seed_value: int = 1) -> void:
	_seed = seed_value
	_mask.resize(GRID_WIDTH * GRID_HEIGHT)
	_mask.fill(0)
	_distance.resize(GRID_WIDTH * GRID_HEIGHT)
	_distance.fill(-FIELD_RADIUS)
	_render_field.resize(GRID_WIDTH * GRID_HEIGHT * 3)
	_render_field.fill(0.0)
	_surface.resize(GRID_WIDTH)
	_fragments.clear()
	_count = 0
	var phase := float(posmod(seed_value, 21)) * 0.19
	for x in range(GRID_WIDTH):
		var wx := float(x * CELL_SIZE)
		var top := 1000.0
		if wx >= 66.0 and wx <= 678.0:
			top = 531.0 + sin(wx * 0.010 + phase) * 48.0 + sin(wx * 0.026) * 17.0
			top += pow(maxf(0.0, 1.0 - (wx - 66.0) / 88.0), 1.4) * 225.0
			top += pow(maxf(0.0, 1.0 - (678.0 - wx) / 110.0), 1.4) * 215.0
		elif wx >= 762.0 and wx <= 1380.0:
			top = 526.0 + sin(wx * 0.011 + phase + 0.7) * 47.0 + sin(wx * 0.025) * 18.0
			top += pow(maxf(0.0, 1.0 - (wx - 762.0) / 100.0), 1.4) * 230.0
			top += pow(maxf(0.0, 1.0 - (1380.0 - wx) / 100.0), 1.4) * 230.0
		var top_cell := clampi(int(top / CELL_SIZE), 0, GRID_HEIGHT)
		for y in range(top_cell, GRID_HEIGHT):
			_mask[y * GRID_WIDTH + x] = 1
			_count += 1
	_refresh_surface()
	_redraw_region(Rect2i(0, 0, GRID_WIDTH, GRID_HEIGHT))

func solid_at(world: Vector2) -> bool:
	if world.x < 0.0 or world.y < 0.0 or world.x >= WORLD_SIZE.x or world.y >= WORLD_SIZE.y:
		return false
	if _mask.is_empty():
		return false
	var index := int(world.y / CELL_SIZE) * GRID_WIDTH + int(world.x / CELL_SIZE)
	# Away from the edge, topology and the continuous field always agree.
	if absf(_distance[index]) > 2.0:
		return _mask[index] != 0
	return signed_distance_at(world) >= 0.0

func surface_y(x: float) -> float:
	if x < 0.0 or x >= WORLD_SIZE.x or _surface.is_empty():
		return WORLD_SIZE.y
	return float(_surface[int(x / CELL_SIZE)] * CELL_SIZE)

func get_solid_count() -> int:
	return _count

func is_settling() -> bool:
	return not _fragments.is_empty()

func carve(center: Vector2, radius: float) -> int:
	if _mask.is_empty() or radius <= 0.0:
		return 0
	var cx := center.x / CELL_SIZE
	var cy := center.y / CELL_SIZE
	var r := radius / CELL_SIZE
	var min_x := clampi(int(floor(cx - r)), 0, GRID_WIDTH - 1)
	var max_x := clampi(int(ceil(cx + r)), 0, GRID_WIDTH - 1)
	var min_y := clampi(int(floor(cy - r)), 0, GRID_HEIGHT - 1)
	var max_y := clampi(int(ceil(cy + r)), 0, GRID_HEIGHT - 1)
	var removed := 0
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			var index := y * GRID_WIDTH + x
			if dx * dx + dy * dy <= r * r and _mask[index] != 0:
				_mask[index] = 0
				removed += 1
	if removed == 0:
		return 0
	_count -= removed
	_find_fragments()
	var surface_dirty := _refresh_surface()
	var dirty := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1).grow(5)
	if surface_dirty.size != Vector2i.ZERO:
		dirty = dirty.merge(surface_dirty)
	_redraw_region(dirty)
	return removed

func update_settling(delta: float) -> bool:
	if _fragments.is_empty():
		return false
	var dirty := Rect2i()
	var any_mobile := false
	var did_move := false
	# Lowest chunks move first, so stacked loose chunks follow their support.
	_fragments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.bottom > b.bottom)
	for fragment in _fragments:
		var cells: PackedInt32Array = fragment.cells
		for index in cells:
			_mask[index] = 0
		var mobile := _can_fall(cells)
		if mobile:
			any_mobile = true
			fragment.speed = minf(float(fragment.speed) + FALL_ACCELERATION * delta, MAX_FALL_SPEED)
			fragment.remainder = float(fragment.remainder) + float(fragment.speed) * delta
			var steps := mini(int(fragment.remainder), 30)
			fragment.remainder -= float(steps)
			var distance := 0
			for _step in range(steps):
				if not _can_fall(cells):
					fragment.speed = 0.0
					fragment.remainder = 0.0
					break
				for i in range(cells.size()):
					cells[i] += GRID_WIDTH
				distance += 1
			if distance > 0:
				did_move = true
				var old_rect: Rect2i = fragment.bounds
				var new_rect := Rect2i(old_rect.position + Vector2i(0, distance), old_rect.size)
				var changed := old_rect.merge(new_rect)
				dirty = changed if dirty.size == Vector2i.ZERO else dirty.merge(changed)
				fragment.bounds = new_rect
				fragment.bottom = new_rect.end.y
				fragment.cells = cells
		else:
			fragment.speed = 0.0
			fragment.remainder = 0.0
		for index in cells:
			_mask[index] = 1
	if did_move:
		var surface_dirty := _refresh_surface()
		if surface_dirty.size != Vector2i.ZERO:
			dirty = dirty.merge(surface_dirty)
		_redraw_region(dirty.grow(5))
	if not any_mobile:
		_fragments.clear()
	return not _fragments.is_empty()

func _can_fall(cells: PackedInt32Array) -> bool:
	for index in cells:
		var below := index + GRID_WIDTH
		if below >= _mask.size() or _mask[below] != 0:
			return false
	return true

func _find_fragments() -> void:
	_fragments.clear()
	var visited := PackedByteArray()
	visited.resize(_mask.size())
	visited.fill(0)
	var queue := PackedInt32Array()
	queue.resize(_mask.size())
	var end := 0
	for x in range(GRID_WIDTH):
		var index := (GRID_HEIGHT - 1) * GRID_WIDTH + x
		if _mask[index] != 0:
			queue[end] = index
			end += 1
			visited[index] = 1
	var cursor := 0
	while cursor < end:
		var index := queue[cursor]
		cursor += 1
		var x := index % GRID_WIDTH
		for neighbor in [index - GRID_WIDTH, index + GRID_WIDTH, index - 1 if x > 0 else -1, index + 1 if x < GRID_WIDTH - 1 else -1]:
			if neighbor >= 0 and neighbor < _mask.size() and _mask[neighbor] != 0 and visited[neighbor] == 0:
				visited[neighbor] = 1
				queue[end] = neighbor
				end += 1
	for first in range(_mask.size()):
		if _mask[first] == 0 or visited[first] != 0:
			continue
		var cells := PackedInt32Array()
		queue[0] = first
		end = 1
		cursor = 0
		visited[first] = 1
		var min_x := GRID_WIDTH
		var min_y := GRID_HEIGHT
		var max_x := 0
		var max_y := 0
		while cursor < end:
			var index := queue[cursor]
			cursor += 1
			cells.append(index)
			var x := index % GRID_WIDTH
			var y := int(index / GRID_WIDTH)
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
			for neighbor in [index - GRID_WIDTH, index + GRID_WIDTH, index - 1 if x > 0 else -1, index + 1 if x < GRID_WIDTH - 1 else -1]:
				if neighbor >= 0 and neighbor < _mask.size() and _mask[neighbor] != 0 and visited[neighbor] == 0:
					visited[neighbor] = 1
					queue[end] = neighbor
					end += 1
		var bounds := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
		_fragments.append({"cells": cells, "bounds": bounds, "bottom": max_y + 1, "speed": 0.0, "remainder": 0.0})

func _refresh_surface() -> Rect2i:
	var dirty := Rect2i()
	for x in range(GRID_WIDTH):
		var previous := _surface[x]
		_surface[x] = GRID_HEIGHT
		for y in range(GRID_HEIGHT):
			if _mask[y * GRID_WIDTH + x] != 0:
				_surface[x] = y
				break
		if previous != _surface[x]:
			var top := mini(previous, _surface[x])
			var bottom := maxi(previous, _surface[x]) + 6
			var changed := Rect2i(x, top, 1, bottom - top)
			dirty = changed if dirty.size == Vector2i.ZERO else dirty.merge(changed)
	return dirty

func _redraw_region(region: Rect2i) -> void:
	# The visual field is rebuilt only near changed geometry, never every frame.
	# Extra padding makes the bounded chamfer transform identical at the edge to
	# a full rebuild, up to FIELD_RADIUS, while keeping impact latency modest.
	var rect := region.grow(int(FIELD_RADIUS) + 2).intersection(Rect2i(0, 0, GRID_WIDTH, GRID_HEIGHT))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var index := y * GRID_WIDTH + x
			var inside := _mask[index] != 0
			var boundary := false
			for next in [index - GRID_WIDTH if y > 0 else -1, index + GRID_WIDTH if y < GRID_HEIGHT - 1 else -1, index - 1 if x > 0 else -1, index + 1 if x < GRID_WIDTH - 1 else -1]:
				if (next >= 0 and (_mask[next] != 0) != inside) or (next < 0 and inside):
					boundary = true
					break
			_distance[index] = 0.5 if boundary else FIELD_RADIUS
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var index := y * GRID_WIDTH + x
			var value := _distance[index]
			if x > rect.position.x: value = minf(value, _distance[index - 1] + 1.0)
			if y > rect.position.y:
				value = minf(value, _distance[index - GRID_WIDTH] + 1.0)
				if x > rect.position.x: value = minf(value, _distance[index - GRID_WIDTH - 1] + SQRT_2)
				if x < rect.end.x - 1: value = minf(value, _distance[index - GRID_WIDTH + 1] + SQRT_2)
			_distance[index] = value
	for y in range(rect.end.y - 1, rect.position.y - 1, -1):
		for x in range(rect.end.x - 1, rect.position.x - 1, -1):
			var index := y * GRID_WIDTH + x
			var value := _distance[index]
			if x < rect.end.x - 1: value = minf(value, _distance[index + 1] + 1.0)
			if y < rect.end.y - 1:
				value = minf(value, _distance[index + GRID_WIDTH] + 1.0)
				if x > rect.position.x: value = minf(value, _distance[index + GRID_WIDTH - 1] + SQRT_2)
				if x < rect.end.x - 1: value = minf(value, _distance[index + GRID_WIDTH + 1] + SQRT_2)
			_distance[index] = value
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var index := y * GRID_WIDTH + x
			_distance[index] *= 1.0 if _mask[index] != 0 else -1.0
	# A compact separable Gaussian removes topology-grid waviness before cubic
	# reconstruction. Collision queries use this same smoothed distance field.
	var horizontal := _distance.duplicate()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var index := y * GRID_WIDTH + x
			horizontal[index] = (_distance[y * GRID_WIDTH + maxi(0, x - 1)] + _distance[y * GRID_WIDTH + mini(GRID_WIDTH - 1, x + 1)]) * 0.25 + _distance[index] * 0.5
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var index := y * GRID_WIDTH + x
			_distance[index] = (horizontal[maxi(0, y - 1) * GRID_WIDTH + x] + horizontal[mini(GRID_HEIGHT - 1, y + 1) * GRID_WIDTH + x]) * 0.25 + horizontal[index] * 0.5
	# Broad normals are independent of screen derivatives. This avoids little
	# alternating green/orange teeth when rendering above the topology resolution.
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var index := y * GRID_WIDTH + x
			var gradient := Vector2(_distance[y * GRID_WIDTH + mini(GRID_WIDTH - 1, x + 3)] - _distance[y * GRID_WIDTH + maxi(0, x - 3)],
				_distance[mini(GRID_HEIGHT - 1, y + 3) * GRID_WIDTH + x] - _distance[maxi(0, y - 3) * GRID_WIDTH + x]).normalized()
			_render_field[index * 3] = _distance[index]
			_render_field[index * 3 + 1] = gradient.x
			_render_field[index * 3 + 2] = gradient.y
	var image := Image.create_from_data(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_RGBF, _render_field.to_byte_array())
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	if material != null: material.set_shader_parameter("terrain_field", _texture)
	queue_redraw()

func signed_distance_at(world: Vector2) -> float:
	## Same cubic B-spline reconstruction as the shader, in world pixels.
	if _distance.is_empty():
		return -FIELD_RADIUS * CELL_SIZE
	var cell := world / float(CELL_SIZE) - Vector2(0.5, 0.5)
	var base := Vector2i(int(floor(cell.x)), int(floor(cell.y)))
	var fraction := cell - Vector2(base)
	var wx := _cubic_weights(fraction.x)
	var wy := _cubic_weights(fraction.y)
	var result := 0.0
	for j in 4:
		var row := clampi(base.y + j - 1, 0, GRID_HEIGHT - 1) * GRID_WIDTH
		for i in 4:
			result += _distance[row + clampi(base.x + i - 1, 0, GRID_WIDTH - 1)] * wx[i] * wy[j]
	return result * CELL_SIZE

func _cubic_weights(fraction: float) -> PackedFloat32Array:
	var inverse := 1.0 - fraction
	var square := fraction * fraction
	var cube := square * fraction
	return PackedFloat32Array([inverse * inverse * inverse / 6.0,
		(3.0 * cube - 6.0 * square + 4.0) / 6.0,
		(-3.0 * cube + 3.0 * square + 3.0 * fraction + 1.0) / 6.0,
		cube / 6.0])

func _draw() -> void:
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, WORLD_SIZE), false)
