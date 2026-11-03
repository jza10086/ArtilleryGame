extends RefCounted
## Host-owned artillery rules and fixed-step ballistics; no input, UI or transport.
## The terrain is a solid heightfield: explosions excavate bowls, construction raises banks.
const WIDTH: float = 1920.0
const FLOOR: float = 970.0
const CELL: float = 4.0
const GRAVITY: float = 430.0
const TURN_SECONDS: float = 35.0
const WEAPONS: Array[Dictionary] = [
	{"name": "标准弹", "hint": "可靠的单发爆破 · 无限弹药", "radius": 68.0, "damage": 48.0, "ammo": -1, "color": "ffe6a6"},
	{"name": "重型爆破", "hint": "大范围深坑 · 低初速", "radius": 110.0, "damage": 70.0, "ammo": 2, "color": "ff8b52"},
	{"name": "三重散射", "hint": "三条弹道同时覆盖相邻落点", "radius": 44.0, "damage": 29.0, "ammo": 3, "color": "67dbff"},
	{"name": "集束花火", "hint": "在最高点分裂为五枚子弹", "radius": 37.0, "damage": 24.0, "ammo": 2, "color": "e49cff"},
	{"name": "跳弹", "hint": "沿地表反弹 · 3 秒引信", "radius": 82.0, "damage": 62.0, "ammo": 3, "color": "a5f27e"},
	{"name": "钻地弹", "hint": "命中后向地下钻进再爆炸", "radius": 78.0, "damage": 60.0, "ammo": 2, "color": "ffcd66"},
	{"name": "造山弹", "hint": "抬升落点地形 · 低伤害改变掩体", "radius": 100.0, "damage": 16.0, "ammo": 2, "color": "74edcf"},
	{"name": "虹吸弹", "hint": "造成伤害并回复射手部分生命", "radius": 60.0, "damage": 44.0, "ammo": 2, "color": "ff78ac"}
]
var state: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _impact_id: int = 0

func setup(players: Array[Dictionary], seed_value: int, mode: String) -> void:
	rng.seed = seed_value
	var terrain: PackedFloat32Array = PackedFloat32Array()
	var phase_offset: float = rng.randf_range(0.0, TAU)
	for i: int in 481:
		var x: float = float(i) * CELL
		terrain.append(690.0 + sin(x * 0.0045 + phase_offset) * 100.0 + sin(x * 0.012 + phase_offset) * 35.0)
	var tanks: Array[Dictionary] = []
	for i: int in players.size():
		var x: float = 180.0 if mode == "training" else lerpf(160.0, 1760.0, float(i) / float(maxi(1, players.size() - 1)))
		if mode == "teams":
			var half: int = players.size() / 2
			x = lerpf(140.0, 780.0, float(i / 2) / float(maxi(1, half - 1))) if i % 2 == 0 else lerpf(1140.0, 1780.0, float(i / 2) / float(maxi(1, half - 1)))
		var ammo: Array[int] = []
		for definition: Dictionary in WEAPONS:
			ammo.append(-1 if mode == "training" else int(definition.ammo))
		tanks.append({"id": players[i].player_id, "name": players[i].name,
			"color": players[i].color, "x": x, "y": terrain[roundi(x / CELL)] - 13.0,
			"hp": 200, "team": i % 2 if mode == "teams" else i,
			"ammo": ammo, "damage": 0, "eliminated": 0, "withdrawn": false})
	if mode == "training":
		for i: int in 3:
			var x: float = 860.0 + i * 330.0
			tanks.append({"id": "target_%d" % i, "name": "靶标 %d" % (i + 1), "color": "ff7d91",
				"x": x, "y": terrain[roundi(x / CELL)] - 13.0, "hp": 200, "team": i + 1,
				"ammo": [], "damage": 0, "eliminated": 0, "withdrawn": false})
	state = {"mode": mode, "terrain": terrain, "tanks": tanks, "projectiles": [],
		"impacts": [], "turn": 0, "active": -1, "phase": "aim", "time": TURN_SECONDS,
		"wind": 0.0, "fuel": 90.0, "wait": 0.0, "winner": -2, "revision": 0}
	_next_turn()

func ground(x: float) -> float:
	var cell: float = clampf(x / CELL, 0.0, 480.0)
	var left: int = mini(479, int(cell))
	return lerpf(state.terrain[left], state.terrain[left + 1], cell - left)

func _next_turn() -> void:
	if _check_over():
		return
	state.turn += 1
	state.active = 0 if state.mode == "training" else (int(state.active) + 1) % state.tanks.size()
	while state.tanks[state.active].hp <= 0:
		state.active = (int(state.active) + 1) % state.tanks.size()
	state.phase = "aim"
	state.time = TURN_SECONDS
	state.fuel = 90.0
	state.wind = rng.randf_range(-38.0, 38.0)
	state.wait = 0.0
	# Sudden death bounds multiplayer rounds even when every player passes.
	if state.mode != "training" and state.turn > state.tanks.size() * 8:
		for tank: Dictionary in state.tanks:
			_hurt(tank, 12)
		if _check_over():
			return
		if state.tanks[state.active].hp <= 0:
			_next_turn()

## The transport validates payload shape; this boundary enforces turn, actor and ammo.
func command(player_id: String, turn_number: int, action: String, values: Dictionary) -> bool:
	if state.phase != "aim" or turn_number != state.turn:
		return false
	var tank: Dictionary = state.tanks[state.active]
	if tank.id != player_id or tank.hp <= 0:
		return false
	match action:
		"move":
			var dx: float = float(values.direction) * minf(12.0, state.fuel)
			var x: float = clampf(tank.x + dx, 40.0, WIDTH - 40.0)
			if state.fuel <= 0.0 or absf(ground(x) - ground(tank.x)) > 32.0:
				return false
			for other: Dictionary in state.tanks:
				if other.id != tank.id and other.hp > 0 and absf(other.x - x) < 42.0:
					return false
			state.fuel -= absf(x - float(tank.x))
			tank.x = x
			tank.y = ground(x) - 13.0
		"fire":
			var weapon: int = values.weapon
			if tank.ammo[weapon] == 0:
				return false
			if tank.ammo[weapon] > 0:
				tank.ammo[weapon] -= 1
			var angle: float = deg_to_rad(float(values.angle))
			var speed: float = (270.0 + float(values.power) * 6.0) * (0.82 if weapon == 1 else 1.0)
			var direction: Vector2 = Vector2(cos(angle), -sin(angle))
			var muzzle: Vector2 = Vector2(tank.x, tank.y - 12.0) + direction * 35.0
			if weapon == 2:
				for offset: float in [-0.085, 0.0, 0.085]:
					_spawn(muzzle, direction.rotated(offset) * speed, weapon, false)
			else:
				_spawn(muzzle, direction * speed, weapon, false)
			state.phase = "flight"
			state.wait = 0.0
		"pass":
			state.phase = "settle"
			state.wait = 0.0
		"reset":
			if state.mode != "training":
				return false
			var player: Dictionary = {"player_id": tank.id, "name": tank.name, "color": tank.color}
			var previous_turn: int = state.turn
			setup([player], rng.randi(), "training")
			state.turn = previous_turn + 1
		"finish":
			if state.mode != "training":
				return false
			state.phase = "over"
			state.winner = 0
		_:
			return false
	return true

func _spawn(pos: Vector2, velocity: Vector2, weapon: int, child: bool) -> void:
	state.projectiles.append({"pos": pos, "vel": velocity, "weapon": weapon, "child": child,
		"age": 0.0, "bounces": 0, "drilling": false, "trail": []})

func step(delta: float) -> void:
	if state.phase == "over":
		return
	if state.phase == "aim":
		if state.mode != "training":
			state.time = maxf(0.0, state.time - delta)
			if state.time <= 0.0:
				state.phase = "settle"
				state.wait = 0.0
	elif state.phase == "flight":
		_fly(delta)
		if state.projectiles.is_empty():
			state.phase = "settle"
			state.wait = 0.0
	elif state.phase == "settle":
		state.wait += delta
		if state.wait >= 1.0:
			_next_turn()

func _fly(delta: float) -> void:
	var children: Array[Dictionary] = []
	for i: int in range(state.projectiles.size() - 1, -1, -1):
		var shot: Dictionary = state.projectiles[i]
		shot.age += delta
		var previous_y: float = shot.vel.y
		shot.vel += Vector2(state.wind, GRAVITY) * delta
		if shot.weapon == 3 and not shot.child and previous_y < 0.0 and shot.vel.y >= 0.0:
			for spread: int in range(-2, 3):
				children.append({"pos": shot.pos, "vel": Vector2(shot.vel.x + spread * 115.0, 75.0),
					"weapon": 3, "child": true, "age": 0.0, "bounces": 0, "drilling": false, "trail": []})
			state.projectiles.remove_at(i)
			continue
		var displacement: Vector2 = shot.vel * delta
		var steps: int = maxi(1, ceili(displacement.length() / 4.0))
		var hit: bool = false
		for s: int in steps:
			var next: Vector2 = shot.pos + displacement / float(steps)
			if next.x < 0.0 or next.x > WIDTH or next.y > FLOOR:
				shot.pos = next
				hit = true
				break
			var terrain_hit: bool = next.y >= ground(next.x)
			if terrain_hit and shot.weapon == 4 and shot.bounces < 3 and shot.age < 3.0:
				var normal: Vector2 = Vector2(ground(next.x + 4.0) - ground(next.x - 4.0), -8.0).normalized()
				shot.vel = shot.vel.bounce(normal) * 0.68
				shot.pos = Vector2(next.x, ground(next.x) - 3.0)
				shot.bounces += 1
				break
			shot.pos = next
			if terrain_hit:
				if shot.weapon == 5 and not shot.drilling:
					shot.drilling = true
					shot.depth = 0.0
				if shot.drilling:
					shot.depth += displacement.length() / float(steps)
					hit = shot.depth >= 75.0
				else:
					hit = true
			if not shot.drilling and shot.age > 0.10:
				for tank: Dictionary in state.tanks:
					if tank.hp > 0 and Vector2(tank.x, tank.y).distance_to(next) < 20.0:
						hit = true
						break
			if hit:
				break
		shot.trail.append(shot.pos)
		if shot.trail.size() > 22:
			shot.trail.pop_front()
		if shot.weapon == 4 and shot.age >= 3.0:
			hit = true
		if shot.age > 12.0 or shot.pos.y < -1400.0:
			state.projectiles.remove_at(i)
		elif hit:
			if shot.pos.x >= 0.0 and shot.pos.x <= WIDTH and shot.pos.y <= FLOOR:
				_blast(shot.pos, shot.weapon)
			state.projectiles.remove_at(i)
	state.projectiles.append_array(children)

func _blast(pos: Vector2, weapon: int) -> void:
	var definition: Dictionary = WEAPONS[weapon]
	var radius: float = definition.radius
	_impact_id += 1
	state.impacts.append({"id": _impact_id, "pos": pos, "radius": radius, "weapon": weapon})
	if state.impacts.size() > 32:
		state.impacts.pop_front()
	var total: int = 0
	var shooter: Dictionary = state.tanks[state.active]
	for tank: Dictionary in state.tanks:
		if tank.hp <= 0:
			continue
		var distance: float = Vector2(tank.x, tank.y).distance_to(pos)
		if distance < radius + 22.0:
			var amount: int = roundi(float(definition.damage) * clampf(1.0 - (distance - 20.0) / radius, 0.0, 1.0))
			var actual: int = mini(tank.hp, amount)
			_hurt(tank, amount)
			if tank.team != shooter.team:
				total += actual
	shooter.damage += total
	if weapon == 7 and shooter.hp > 0:
		shooter.hp = mini(200, int(shooter.hp) + roundi(total * 0.55))
	var first: int = maxi(0, floori((pos.x - radius) / CELL))
	var last: int = mini(480, ceili((pos.x + radius) / CELL))
	for cell: int in range(first, last + 1):
		var horizontal: float = float(cell) * CELL - pos.x
		if absf(horizontal) > radius:
			continue
		var depth: float = sqrt(maxf(0.0, radius * radius - horizontal * horizontal))
		if weapon == 6:
			state.terrain[cell] = maxf(280.0, minf(state.terrain[cell], pos.y - depth * 0.85))
		else:
			state.terrain[cell] = minf(FLOOR, maxf(state.terrain[cell], pos.y + depth))
	for tank: Dictionary in state.tanks:
		if tank.hp <= 0:
			continue
		var new_y: float = ground(tank.x) - 13.0
		var fall: float = new_y - float(tank.y)
		tank.y = new_y
		if state.mode != "training" or tank.id.begins_with("target_"):
			_hurt(tank, maxi(0, roundi((fall - 65.0) * 0.32)))
			if new_y >= FLOOR - 15.0:
				_hurt(tank, 200)

func _hurt(tank: Dictionary, amount: int) -> void:
	# The single-player range keeps its shooter alive; stationary targets still take damage.
	if state.mode == "training" and tank.id == state.tanks[0].id and not tank.withdrawn:
		return
	if tank.hp <= 0 or amount <= 0:
		return
	tank.hp = maxi(0, int(tank.hp) - amount)
	if tank.hp == 0:
		tank.eliminated = state.turn

func withdraw(player_id: String) -> void:
	for tank: Dictionary in state.tanks:
		if tank.id == player_id:
			tank.withdrawn = true
			_hurt(tank, 200)
	if state.phase == "aim" and state.tanks[state.active].hp <= 0:
		state.phase = "settle"
		state.wait = 0.0
	_check_over()

func _check_over() -> bool:
	if state.mode == "training":
		if state.tanks[0].withdrawn:
			state.phase = "over"
			state.winner = -1
			return true
		return state.phase == "over"
	var surviving: Array[int] = []
	for tank: Dictionary in state.tanks:
		if tank.hp > 0 and tank.team not in surviving:
			surviving.append(tank.team)
	if surviving.size() <= 1:
		state.phase = "over"
		state.winner = surviving[0] if surviving.size() == 1 else -1
		return true
	return false

func result(request_id: String) -> Dictionary:
	var rows: Array[Dictionary] = []
	var ordered: Array[Dictionary] = []
	for tank: Dictionary in state.tanks:
		if not tank.id.begins_with("target_"):
			ordered.append(tank)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.hp > 0) != (b.hp > 0):
			return a.hp > 0
		return int(a.eliminated) > int(b.eliminated))
	var placed: int = 0
	var previous_elimination: int = -1
	var previous_rank: int = 0
	for tank: Dictionary in ordered:
		var rank: int = 0
		if not tank.withdrawn:
			placed += 1
			rank = placed
			if state.mode == "teams":
				rank = 1 if state.winner == -1 or tank.team == state.winner else 2
			elif tank.hp == 0 and tank.eliminated == previous_elimination:
				rank = previous_rank
			previous_elimination = tank.eliminated if tank.hp == 0 else -1
			previous_rank = rank
		rows.append({"player_id": tank.id, "rank": 0 if tank.withdrawn else rank,
			"status": "withdrawn" if tank.withdrawn else "completed",
			"metrics": {"damage": tank.damage, "health": tank.hp}})
	return {"request_id": request_id, "reason": "completed", "rankings": rows,
		"columns": [{"key": "damage", "title": "伤害", "format": "integer"},
			{"key": "health", "title": "生命", "format": "integer"}]}
