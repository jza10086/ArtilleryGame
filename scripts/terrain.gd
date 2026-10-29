class_name IslandTerrain
extends Node2D
## Original bitmap terrain. Connected ground keeps caves and overhangs; only
## genuinely disconnected islands fall. Rendering and collision share one mask.

const CELL_SIZE := 3
const GRID_WIDTH := 480
const GRID_HEIGHT := 300
const WORLD_SIZE := Vector2(1440.0, 900.0)
const WATER_Y := 790.0
const FALL_ACCELERATION := 310.0 # cells / second squared
const MAX_FALL_SPEED := 160.0

var _mask := PackedByteArray()
var _pixels := PackedByteArray()
var _texture: ImageTexture
var _fragments: Array[Dictionary] = []
var _count := 0
var _seed := 1
var _surface := PackedInt32Array()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func generate(seed_value: int = 1) -> void:
	_seed = seed_value
	_mask.resize(GRID_WIDTH * GRID_HEIGHT)
	_mask.fill(0)
	_pixels.resize(GRID_WIDTH * GRID_HEIGHT * 4)
	_pixels.fill(0)
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
	return _mask[int(world.y / CELL_SIZE) * GRID_WIDTH + int(world.x / CELL_SIZE)] != 0 if not _mask.is_empty() else false

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
	var rect := region.intersection(Rect2i(0, 0, GRID_WIDTH, GRID_HEIGHT))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var index := y * GRID_WIDTH + x
			var pixel := index * 4
			if _mask[index] == 0:
				_pixels[pixel + 3] = 0
				continue
			var depth := y - _surface[x]
			var color: Color
			var noise_value := posmod(x * 17 + y * 53 + x * y * 3 + _seed, 23)
			var band := sin(float(y) * 0.13 + sin(float(x) * 0.036) * 0.9)
			var shade := float(noise_value) / 350.0
			if depth == 0:
				color = Color(0.78 + shade, 0.87 + shade * 0.5, 0.40)
			elif depth <= 2:
				color = Color(0.48 + shade, 0.66 + shade * 0.5, 0.25)
			elif depth <= 4:
				color = Color(0.28 + shade, 0.44 + shade, 0.23)
			else:
				color = Color(0.57 + band * 0.035 + shade, 0.31 + band * 0.04 + shade, 0.23 + band * 0.025 + shade * 0.6)
				if y > 233:
					color = color.lerp(Color(0.30, 0.29, 0.31), clampf(float(y - 233) / 90.0, 0.0, 0.65))
				var edge := (x == 0 or x == GRID_WIDTH - 1 or y == 0 or y == GRID_HEIGHT - 1)
				if not edge:
					edge = _mask[index - 1] == 0 or _mask[index + 1] == 0 or _mask[index - GRID_WIDTH] == 0 or _mask[index + GRID_WIDTH] == 0
				if edge:
					color = Color(0.30, 0.22, 0.22)
				elif posmod(x * 73 + y * 29, 197) < 2:
					color = color.lightened(0.16)
			_pixels[pixel] = int(color.r * 255.0)
			_pixels[pixel + 1] = int(color.g * 255.0)
			_pixels[pixel + 2] = int(color.b * 255.0)
			_pixels[pixel + 3] = 255
	var image := Image.create_from_data(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_RGBA8, _pixels)
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	queue_redraw()

func _draw() -> void:
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, WORLD_SIZE), false)
	# Sparse meadow tufts break the mask silhouette without hiding collisions.
	for x in range(31, GRID_WIDTH - 30, 9):
		if _surface.is_empty() or _surface[x] >= 258:
			continue
		var base := Vector2(float(x * CELL_SIZE), float(_surface[x] * CELL_SIZE + 2))
		var height := 4.0 + float(posmod(x * 17, 6))
		draw_line(base, base + Vector2(-3, -height), Color(0.68, 0.79, 0.35), 2.0, true)
		draw_line(base + Vector2(2, 0), base + Vector2(4, -height - 1), Color(0.73, 0.84, 0.38), 2.0, true)
