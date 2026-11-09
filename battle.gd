extends RefCounted
## Host-owned artillery rules and fixed-step ballistics; no input, UI or transport.
## The terrain is a solid heightfield: explosions excavate bowls, construction raises banks.
const Settings: Script = preload("res://games/minigame/godot_party_default_artillery_game/settings.gd")
const WIDTH: float = 1920.0
const FLOOR: float = 970.0
const CELL: float = 4.0
const GUN_MOUNT: Vector2 = Vector2(0, -23)
const BARREL_LENGTH: float = 38.0
const TRACK_HALF: float = 19.0
const TRACK_BOTTOM: float = 12.0
const GRAVITY: float = 430.0
const TURN_SECONDS: float = 35.0
const AIM_STEPS: int = 36
const BLACK_HOLE_CORE: float = 18.0
const PORTAL_RADIUS: float = 30.0
const BUMPER_RADIUS: float = 34.0
const WEAPONS: Array[Dictionary] = [
	{"name": "标准弹", "hint": "可靠的单发爆破 · 无限弹药", "radius": 68.0, "damage": 48.0, "color": "ffe6a6"},
	{"name": "重型爆破", "hint": "大范围深坑 · 低初速", "radius": 110.0, "damage": 70.0, "color": "ff8b52"},
	{"name": "三重散射", "hint": "三条弹道同时覆盖相邻落点", "radius": 44.0, "damage": 29.0, "color": "67dbff"},
	{"name": "集束花火", "hint": "在最高点分裂为五枚子弹", "radius": 37.0, "damage": 24.0, "color": "e49cff"},
	{"name": "跳弹", "hint": "沿地表反弹 · 3 秒引信", "radius": 82.0, "damage": 62.0, "color": "a5f27e"},
	{"name": "钻地弹", "hint": "命中后向地下钻进再爆炸", "radius": 78.0, "damage": 60.0, "color": "ffcd66"},
	{"name": "造山弹", "hint": "抬升落点地形 · 低伤害改变掩体", "radius": 100.0, "damage": 16.0, "color": "74edcf"},
	{"name": "虹吸弹", "hint": "造成伤害并回复射手部分生命", "radius": 60.0, "damage": 44.0, "color": "ff78ac"},
	{"name":"滚地雷","hint":"触地后沿地面滑行，接近坦克或 1.5 秒后爆炸","radius":66,"damage":52,"color":"b6f578"},
	{"name":"空爆弹雨","hint":"最高点向下散射七枚穿甲子弹","radius":30,"damage":19,"color":"73dfff"},
	{"name":"燃烧弹","hint":"落点留下火区，之后三个回合各造成 12 伤害","radius":54,"damage":24,"color":"ff9649"},
	{"name":"电磁脉冲","hint":"不破坏地形，命中者下次回合移动额度减半","radius":105,"damage":25,"color":"a7a1ff"},
	{"name":"跃迁弹","hint":"将射手传送至落点，保留生命且不炸地形","radius":42,"damage":0,"color":"63ffe5"},
	{"name":"连锁震爆","hint":"落点向两侧依次引爆五段震波","radius":45,"damage":23,"color":"ffba61"},
	{"name":"感应雷","hint":"留在落点，敌人靠近触发，保留六个回合","radius":75,"damage":58,"color":"ff6c98"},
	{"name":"护盾弹","hint":"给爆心附近的友军增加 60 护盾，上限 100","radius":95,"damage":0,"color":"7fb8ff"}
]
var state: Dictionary = {}
var rules: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _impact_id: int = 0
var _feedback_id: int = 0
var _audio_id: int = 0

func setup(players: Array[Dictionary], seed_value: int, mode: String, configuration: Dictionary = {}) -> void:
	rules = configuration.duplicate(true)
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
		var ammo: Array[int] = Settings.initial_ammo(configuration)
		if mode == "training":
			ammo.fill(-1)
		tanks.append({"id": players[i].player_id, "name": players[i].name,
			"color": players[i].color, "x": x, "aim": 45.0 if x < WIDTH * 0.5 else 135.0, "shots": 0, "fuel": 90.0, "acted": false,
			"hp": 200, "shield": 0, "jammed": false, "team": i % 2 if mode == "teams" else i,
			"ammo": ammo, "damage": 0, "eliminated": 0, "withdrawn": false})
	if mode == "training":
		for i: int in 3:
			var x: float = 860.0 + i * 330.0
			tanks.append({"id": "target_%d" % i, "name": "靶标 %d" % (i + 1), "color": "ff7d91",
				"x": x, "aim": 45.0 if x < WIDTH * 0.5 else 135.0, "shots": 0, "fuel": 90.0, "acted": false, "hp": 200, "shield": 0, "jammed": false, "team": i + 1,
				"ammo": [], "damage": 0, "eliminated": 0, "withdrawn": false})
	state = {"mode": mode, "terrain": terrain, "terrain_origin": terrain.duplicate(), "tanks": tanks, "projectiles": [],
		"impacts": [], "health_feedback": [], "audio_events": [], "events": [], "hazards": [], "bursts": [], "notice": "", "notice_left": 0.0, "turn": 0, "round": 0, "active_team": -1, "active": -1, "phase": "aim", "time": TURN_SECONDS,
		"wind": Vector2.ZERO, "wait": 0.0, "winner": -2, "revision": 0}
	for tank: Dictionary in tanks:
		_seat_on_ground(tank)
	_next_turn()

## Fit the track sole across its footprint. The highest contact supports the hull
## when a crater rim or a sharp crest lies between the two end wheels.
func _seat_on_ground(tank: Dictionary) -> void:
	var x: float = tank.x
	var tilt: float = atan2(ground(x + TRACK_HALF) - ground(x - TRACK_HALF), 2.0 * TRACK_HALF)
	var sole: Vector2 = Vector2(0, TRACK_BOTTOM).rotated(tilt)
	var tangent: Vector2 = Vector2.from_angle(tilt)
	var support: float = INF
	for i: int in 11:
		var foot: Vector2 = sole + tangent * lerpf(-TRACK_HALF, TRACK_HALF, i / 10.0)
		support = minf(support, ground(x + foot.x) - foot.y)
	tank.y = support
	tank.tilt = tilt

static func gun_pivot(tank: Dictionary) -> Vector2:
	return Vector2(tank.x, tank.y) + GUN_MOUNT.rotated(tank.tilt)

static func muzzle_position(tank: Dictionary, degrees: float) -> Vector2:
	return gun_pivot(tank) + Vector2.from_angle(-deg_to_rad(degrees)) * BARREL_LENGTH

func ground(x: float) -> float:
	var cell: float = clampf(x / CELL, 0.0, 480.0)
	var left: int = mini(479, int(cell))
	return lerpf(state.terrain[left], state.terrain[left + 1], cell - left)

func _next_turn() -> void:
	if _check_over():
		return
	var previous_active: int = state.active
	state.turn += 1
	if state.mode == "teams":
		state.active_team = (int(state.active_team) + 1) % 2
		for i: int in state.tanks.size():
			if state.tanks[i].team == state.active_team and state.tanks[i].hp > 0:
				state.active = i
				break
	else:
		state.active = 0 if state.mode == "training" else (int(state.active) + 1) % state.tanks.size()
		while state.tanks[state.active].hp <= 0:
			state.active = (int(state.active) + 1) % state.tanks.size()
	var new_round: bool = state.active_team == 0 if state.mode == "teams" else (state.round == 0 or state.active <= previous_active)
	if state.mode != "training" and new_round:
		state.round += 1
		_distribute_ammo()
	if state.mode == "teams" and state.turn == 2:
		for tank: Dictionary in state.tanks:
			if tank.team == 1 and tank.hp > 0:
				tank.ammo[Settings.TIERS[0][rng.randi_range(0, Settings.TIERS[0].size() - 1)]] += 1
	for i: int in state.tanks.size():
		var tank: Dictionary = state.tanks[i]
		tank.acted = false
		if tank.team == state.active_team if state.mode == "teams" else i == state.active:
			tank.fuel = 45.0 if tank.jammed else 90.0
			tank.jammed = false
	state.phase = "aim"
	state.time = TURN_SECONDS
	_advance_events()
	if _check_over():
		return
	if state.mode != "teams" and state.tanks[state.active].hp <= 0:
		_next_turn()
		return
	state.wind = Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, 38.0)
	state.wait = 0.0
	# Sudden death bounds multiplayer rounds even when every player passes.
	if state.mode != "training" and state.round > 8:
		for tank: Dictionary in state.tanks:
			_hurt(tank, 12)
		if _check_over():
			return
		if state.mode != "teams" and state.tanks[state.active].hp <= 0:
			_next_turn()

## A round is one pass through the surviving roster, independent of player count.
## Each survivor draws independently with identical per-tier quantities.
func _distribute_ammo() -> void:
	if state.round < 3 or state.round % 2 == 0:
		return
	var stage: String = "late" if state.round >= 7 else ("middle" if state.round >= 5 else "early")
	for tank: Dictionary in state.tanks:
		if tank.hp > 0 and not tank.withdrawn:
			for weapon: int in _draw_supply(stage):
				tank.ammo[weapon] += 1

func _draw_supply(stage: String) -> Array[int]:
	var grant: Array[int] = []
	var counts: Array[int] = Settings.supply_counts(rules, stage)
	for tier: int in 3:
		for draw: int in counts[tier]:
			var pool: Array = Settings.TIERS[tier]
			grant.append(pool[rng.randi_range(0, pool.size() - 1)])
	return grant

static func can_act(snapshot: Dictionary, index: int) -> bool:
	var tank: Dictionary = snapshot.tanks[index]
	return snapshot.phase == "aim" and tank.hp > 0 and not tank.acted and (tank.team == snapshot.active_team if snapshot.mode == "teams" else index == snapshot.active)

func _finish_aim() -> void:
	state.phase = "flight" if not state.projectiles.is_empty() or not state.bursts.is_empty() else "settle"
	state.wait = 0.0

func _team_ready() -> void:
	for i: int in state.tanks.size():
		if can_act(state, i):
			return
	_finish_aim()

## The transport validates payload shape; this boundary enforces turn, actor and ammo.
func command(player_id: String, turn_number: int, action: String, values: Dictionary) -> bool:
	if state.phase != "aim" or turn_number != state.turn:
		return false
	var actor: int = -1
	for i: int in state.tanks.size():
		if state.tanks[i].id == player_id:
			actor = i
			break
	if actor < 0 or not can_act(state, actor):
		return false
	var tank: Dictionary = state.tanks[actor]
	match action:
		"move":
			var dx: float = float(values.direction) * minf(12.0, tank.fuel)
			var x: float = clampf(tank.x + dx, 40.0, WIDTH - 40.0)
			if tank.fuel <= 0.0 or absf(ground(x) - ground(tank.x)) > 32.0:
				return false
			for other: Dictionary in state.tanks:
				if other.id != tank.id and other.hp > 0 and absf(other.x - x) < 42.0:
					return false
			tank.fuel -= absf(x - float(tank.x))
			if x != tank.x:
				_sound("move")
			tank.x = x
			_seat_on_ground(tank)
			_collect_supplies(actor)
			_trigger_mines()
			if tank.hp <= 0:
				_team_ready()
		"fire":
			var weapon: int = values.weapon
			if tank.ammo[weapon] == 0:
				return false
			if tank.ammo[weapon] > 0:
				tank.ammo[weapon] -= 1
			tank.aim = float(values.angle)
			tank.acted = true
			_launch(actor, values)
			_team_ready()
		"pass":
			tank.acted = true
			_team_ready()
		"reset":
			if state.mode != "training":
				return false
			var player: Dictionary = {"player_id": tank.id, "name": tank.name, "color": tank.color}
			var previous_turn: int = state.turn
			setup([player], rng.randi(), "training", rules)
			state.turn = previous_turn + 1
			_sound("reset")
			for event: Dictionary in state.events:
				event.expires += previous_turn
		"finish":
			if state.mode != "training":
				return false
			state.phase = "over"
			state.winner = 0
		_:
			return false
	return true

func _launch(actor: int, values: Dictionary) -> void:
	var tank: Dictionary = state.tanks[actor]
	var weapon: int = values.weapon
	tank.shots += 1
	_sound("fire", weapon)
	var angle: float = deg_to_rad(tank.aim)
	var speed: float = (270.0 + float(values.power) * 6.0) * (0.82 if weapon == 1 else 1.0)
	var direction: Vector2 = Vector2(cos(angle), -sin(angle))
	var muzzle: Vector2 = muzzle_position(tank, tank.aim)
	if weapon == 2:
		for offset: float in [-0.085, 0.0, 0.085]:
			_spawn(muzzle, direction.rotated(offset) * speed, weapon, false, actor)
	else:
		_spawn(muzzle, direction * speed, weapon, false, actor)

func _projectile(pos: Vector2, velocity: Vector2, weapon: int, child: bool, boost: float = 1.0, owner: int = -1) -> Dictionary:
	return {"owner": state.active if owner < 0 else owner, "pos": pos, "vel": velocity, "weapon": weapon, "child": child,
		"age": 0.0, "bounces": 0, "drilling": false, "rolling": 0.0, "boost": boost,
		"lock_until": 0.0, "support": false, "trail": []}

func _spawn(pos: Vector2, velocity: Vector2, weapon: int, child: bool, owner: int) -> void:
	state.projectiles.append(_projectile(pos, velocity, weapon, child, 1.0, owner))

func step(delta: float) -> void:
	if state.phase == "over":
		return
	state.notice_left = maxf(0.0, state.notice_left - delta)
	_tick_supplies(delta)
	if state.phase == "aim":
		_tick_bursts(delta)
		_fly(delta)
		_team_ready()
		if state.mode != "training" and state.phase == "aim":
			state.time = maxf(0.0, state.time - delta)
			if state.time <= 0.0:
				_finish_aim()
	elif state.phase == "flight":
		_tick_bursts(delta)
		_fly(delta)
		if state.projectiles.is_empty() and state.bursts.is_empty():
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
		if shot.rolling > 0.0:
			shot.rolling += delta
			shot.pos.x = clampf(shot.pos.x + signf(shot.vel.x) * 145.0 * delta, 1.0, WIDTH - 1.0)
			shot.pos.y = ground(shot.pos.x) - 5.0
			var near_tank: bool = false
			for tank: Dictionary in state.tanks:
				near_tank = near_tank or (tank.hp > 0 and Vector2(tank.x, tank.y).distance_to(shot.pos) < 28.0)
			if near_tank or shot.rolling >= 1.5:
				_blast(shot.pos, shot.weapon, shot.owner, shot.boost)
				state.projectiles.remove_at(i)
			continue
		shot.vel += projectile_acceleration(state, shot.pos) * delta
		if shot.weapon in [3, 9] and not shot.child and previous_y < 0.0 and shot.vel.y >= 0.0:
			_sound("split", shot.weapon)
			for spread: int in range(-2 if shot.weapon == 3 else -3, 3 if shot.weapon == 3 else 4):
				children.append(_projectile(shot.pos,
					Vector2(shot.vel.x * (1.0 if shot.weapon == 3 else 0.3) + spread * 100.0, 75.0 if shot.weapon == 3 else 260.0),
					shot.weapon, true, shot.boost, shot.owner))
			state.projectiles.remove_at(i)
			continue
		var displacement: Vector2 = shot.vel * delta
		var steps: int = maxi(1, ceili(displacement.length() / 4.0))
		var hit: bool = false
		var absorbed: bool = false
		for s: int in steps:
			var next: Vector2 = shot.pos + displacement / float(steps)
			if next.x < 0.0 or next.x > WIDTH or next.y > FLOOR:
				shot.pos = next
				hit = true
				break
			var interaction: StringName = _flight_events(shot, next, children)
			absorbed = interaction == &"absorbed"
			if absorbed or interaction == &"redirected":
				break
			var terrain_hit: bool = next.y >= ground(next.x)
			if terrain_hit and shot.weapon == 8:
				shot.rolling = delta
				shot.pos = Vector2(next.x, ground(next.x) - 5.0)
				break
			if terrain_hit and shot.weapon == 4 and shot.bounces < 3 and shot.age < 3.0:
				var normal: Vector2 = Vector2(ground(next.x + 4.0) - ground(next.x - 4.0), -8.0).normalized()
				shot.vel = shot.vel.bounce(normal) * 0.68
				shot.pos = Vector2(next.x, ground(next.x) - 3.0)
				shot.bounces += 1
				_sound("bounce", shot.weapon)
				break
			shot.pos = next
			if terrain_hit:
				if shot.weapon == 5 and not shot.drilling:
					shot.drilling = true
					_sound("drill", shot.weapon)
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
		if absorbed or shot.age > 12.0 or shot.pos.y < -1400.0:
			state.projectiles.remove_at(i)
		elif hit:
			if shot.pos.x >= 0.0 and shot.pos.x <= WIDTH and shot.pos.y <= FLOOR:
				_resolve_hit(shot)
			state.projectiles.remove_at(i)
	state.projectiles.append_array(children)

func _resolve_hit(shot: Dictionary) -> void:
	var weapon: int = shot.weapon
	if weapon == 10 or weapon == 14:
		state.hazards.append({"kind": "fire" if weapon == 10 else "mine", "x": shot.pos.x,
			"owner": shot.owner, "boost": shot.boost, "expires": state.turn + (3 if weapon == 10 else 6)})
		if weapon == 14:
			_sound("arm", weapon)
			return
	if weapon == 13:
		for index: int in 5:
			var x: float = clampf(shot.pos.x + (index - 2) * 64.0, 1.0, WIDTH - 1.0)
			state.bursts.append({"owner": shot.owner, "x": x, "delay": absf(index - 2) * 0.18, "boost": shot.boost})
		return
	_blast(shot.pos, weapon, shot.owner, shot.boost)

func _blast(pos: Vector2, weapon: int, owner: int = -1, damage_scale: float = 1.0) -> void:
	var definition: Dictionary = WEAPONS[weapon]
	var radius: float = definition.radius
	_sound("impact", weapon)
	_impact_id += 1
	state.impacts.append({"id": _impact_id, "pos": pos, "radius": radius, "weapon": weapon})
	if state.impacts.size() > 32:
		state.impacts.pop_front()
	var total: int = 0
	var shooter: Dictionary = state.tanks[state.active if owner < 0 else owner]
	if weapon == 12:
		var destination: float = clampf(pos.x, 40.0, WIDTH - 40.0)
		for other: Dictionary in state.tanks:
			if other != shooter and other.hp > 0 and absf(other.x - destination) < 48.0:
				_notify("跃迁落点被占据")
				return
		if ground(destination) >= FLOOR - 15.0 or shooter.hp <= 0:
			_notify("跃迁落点不可用")
			return
		shooter.x = destination
		_seat_on_ground(shooter)
		_collect_supplies(state.active if owner < 0 else owner)
		_trigger_mines()
		return
	for tank: Dictionary in state.tanks:
		if tank.hp <= 0:
			continue
		var distance: float = Vector2(tank.x, tank.y).distance_to(pos)
		if distance < radius + 22.0:
			if weapon == 15:
				if tank.team == shooter.team:
					tank.shield = mini(100, int(tank.shield) + 60)
				continue
			if weapon == 11:
				tank.jammed = true
			var amount: int = roundi(float(definition.damage) * damage_scale * clampf(1.0 - (distance - 20.0) / radius, 0.0, 1.0))
			var before: int = tank.hp + tank.shield
			_hurt(tank, amount)
			var actual: int = before - int(tank.hp) - int(tank.shield)
			if tank.team != shooter.team:
				total += actual
	shooter.damage += total
	if weapon == 7 and shooter.hp > 0:
		_heal(shooter, roundi(total * 0.55))
	if weapon in [11, 15]:
		return
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
		var old_y: float = tank.y
		_seat_on_ground(tank)
		var fall: float = tank.y - old_y
		if state.mode != "training" or tank.id.begins_with("target_"):
			_hurt(tank, maxi(0, roundi((fall - 65.0) * 0.32)))
			if tank.y >= FLOOR - 15.0:
				_hurt(tank, 200)

func _hurt(tank: Dictionary, amount: int) -> void:
	# The single-player range keeps its shooter alive; stationary targets still take damage.
	if state.mode == "training" and tank.id == state.tanks[0].id and not tank.withdrawn:
		return
	if tank.hp <= 0 or amount <= 0:
		return
	var before: int = tank.hp + tank.shield
	var absorbed: int = mini(tank.shield, amount)
	tank.shield -= absorbed
	tank.hp = maxi(0, int(tank.hp) - amount + absorbed)
	if not tank.withdrawn:
		_record_health_feedback(tank, int(tank.hp) + int(tank.shield) - before)
	if tank.hp == 0:
		tank.eliminated = state.turn

## Record actual healing separately from damage, even when both happen between snapshots.
func _heal(tank: Dictionary, amount: int) -> void:
	var before: int = tank.hp
	tank.hp = mini(200, before + amount)
	_record_health_feedback(tank, int(tank.hp) - before)

## Separate flight stages survive snapshot intervals and never depend on client input.
func _sound(kind: String, weapon: int = 0) -> void:
	_audio_id += 1
	state.audio_events.append({"id": _audio_id, "kind": kind, "weapon": weapon})
	if state.audio_events.size() > 96:
		state.audio_events.pop_front()

func _record_health_feedback(tank: Dictionary, amount: int) -> void:
	if amount == 0:
		return
	_feedback_id += 1
	state.health_feedback.append({"id": _feedback_id, "tank": tank.id,
		"pos": Vector2(tank.x, tank.y), "amount": amount})
	# Retain recent events across snapshots; IDs remain monotonic through training resets.
	if state.health_feedback.size() > 64:
		state.health_feedback.pop_front()

func withdraw(player_id: String) -> void:
	for tank: Dictionary in state.tanks:
		if tank.id == player_id:
			tank.withdrawn = true
			tank.shield = 0
			_hurt(tank, 200)
	if state.phase == "aim":
		_team_ready()
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


## Events use the host RNG and turn clock. Snapshots carry every position and lifetime.
func _advance_events() -> void:
	for event: Dictionary in state.events.duplicate():
		if event.expires < state.turn:
			state.events.erase(event)
	for hazard: Dictionary in state.hazards.duplicate():
		if hazard.expires < state.turn:
			state.hazards.erase(hazard)
		elif hazard.kind == "fire":
			var owner: Dictionary = state.tanks[hazard.owner]
			for tank: Dictionary in state.tanks:
				if tank.hp > 0 and absf(tank.x - hazard.x) < 65.0:
					var before: int = tank.hp + tank.shield
					_hurt(tank, roundi(12.0 * float(hazard.boost)))
					if tank.team != owner.team:
						owner.damage += before - int(tank.hp) - int(tank.shield)
	var cycle: int = (int(state.turn) - 1) % 8
	if cycle == 0:
		var x: float = rng.randf_range(650.0, 1270.0)
		state.events.append({"kind": "black_hole", "pos": Vector2(x, ground(x) - 240.0), "expires": state.turn + 3})
		_notify("黑洞出现 · 引力弯曲弹道，核心吞噬炮弹")
	if cycle in [0, 3, 6]:
		var x: float = rng.randf_range(260.0, 1660.0)
		state.events.append({"kind": "supply", "pos": Vector2(x, 100.0), "expires": state.turn + 5})
		_notify("黑洞扭曲弹道、吞噬炮弹 · 补给靠近或射中领取" if cycle == 0 else "补给空投 · 靠近或射中领取生命和弹药")
	if cycle == 1:
		var left: float = rng.randf_range(380.0, 680.0)
		var right: float = rng.randf_range(1240.0, 1540.0)
		state.events.append({"kind": "portal", "pos": Vector2(left, ground(left) - 165.0),
			"exit": Vector2(right, ground(right) - 165.0), "expires": state.turn + 3})
		_notify("双向传送门 · 炮弹保留速度，从另一端飞出")
	if cycle == 2:
		var x: float = rng.randf_range(820.0, 1100.0)
		state.events.append({"kind": "bumper", "pos": Vector2(x, ground(x) - 100.0), "expires": state.turn + 3})
		_notify("反弹障碍 · 碰到洋红光环会反射弹道")
	if cycle == 4:
		var x: float = rng.randf_range(500.0, 1420.0)
		var factor: float = 3.0 if rng.randf() < 0.2 else 2.0
		state.events.append({"kind": "amplifier", "pos": Vector2(x, ground(x) - 200.0),
			"factor": factor, "radius": 26.0 if factor == 3.0 else 42.0, "expires": state.turn + 3})
		_notify("增伤标记 ×%d · 首枚命中的炮弹领取，倍率取最高值" % int(factor))
	if cycle == 5:
		var x: float = rng.randf_range(460.0, 1460.0)
		state.events.append({"kind": "drone", "pos": Vector2(x, ground(x) - 330.0), "expires": state.turn + 2})
		_notify("支援无人机 · 射中后向最近的敌人发射三枚炮弹")
	_trigger_mines()

## Small swept steps resolve contacts in order. A short lock and an offset beyond
## the exit surface prevent re-entry; teleport clears the trail across the map.
func _flight_events(shot: Dictionary, next: Vector2, children: Array[Dictionary]) -> StringName:
	if shot.drilling:
		return &""
	for event: Dictionary in state.events.duplicate():
		var distance: float = next.distance_to(event.pos)
		match event.kind:
			"black_hole":
				if distance < BLACK_HOLE_CORE:
					_sound("black_hole")
					return &"absorbed"
			"amplifier":
				if distance < event.radius:
					_sound("amplifier")
					shot.boost = maxf(shot.boost, event.factor)
					state.events.erase(event)
			"supply":
				if distance < 24.0:
					_claim_supply(event, shot.owner)
			"portal":
				if shot.age < shot.lock_until:
					continue
				var into_first: bool = distance < PORTAL_RADIUS
				if into_first or next.distance_to(event.exit) < PORTAL_RADIUS:
					var destination: Vector2 = event.exit if into_first else event.pos
					shot.pos = destination + shot.vel.normalized() * (PORTAL_RADIUS + 6.0)
					shot.lock_until = shot.age + 0.12
					shot.trail.clear()
					_sound("portal")
					return &"redirected"
			"bumper":
				if distance < BUMPER_RADIUS and shot.age >= shot.lock_until:
					var normal: Vector2 = (next - event.pos).normalized() if distance > 0.01 else -shot.vel.normalized()
					shot.vel = shot.vel.bounce(normal)
					shot.pos = event.pos + normal * (BUMPER_RADIUS + 4.0)
					shot.lock_until = shot.age + 0.12
					return &"redirected"
			"drone":
				if distance < 28.0:
					_activate_drone(event, children, shot.owner)
	return &""

func _activate_drone(event: Dictionary, children: Array[Dictionary], owner: int) -> void:
	var target: int = -1
	var nearest: float = INF
	var shooter: Dictionary = state.tanks[owner]
	for index: int in state.tanks.size():
		var tank: Dictionary = state.tanks[index]
		if tank.hp <= 0 or tank.team == shooter.team:
			continue
		var distance: float = event.pos.distance_to(Vector2(tank.x, tank.y))
		if distance < nearest:
			nearest = distance
			target = index
	if target < 0:
		return
	state.events.erase(event)
	var enemy: Dictionary = state.tanks[target]
	for index: int in 3:
		var duration: float = 0.8 + index * 0.15
		var destination: Vector2 = Vector2(enemy.x + (index - 1) * 20.0, enemy.y)
		var velocity: Vector2 = (destination - event.pos) / duration - (state.wind + Vector2(0.0, GRAVITY)) * duration * 0.5
		var shot: Dictionary = _projectile(event.pos, velocity, 9, true, 1.0, owner)
		shot.support = true
		children.append(shot)
	_notify("%s 激活无人机支援" % shooter.name)

static func projectile_acceleration(snapshot: Dictionary, pos: Vector2) -> Vector2:
	var force: Vector2 = snapshot.wind + Vector2(0.0, GRAVITY)
	for event: Dictionary in snapshot.events:
		if event.kind != "black_hole":
			continue
		var offset: Vector2 = event.pos - pos
		var distance: float = offset.length()
		if distance < 280.0 and distance > 0.01:
			force += offset / distance * 1500.0 * (1.0 - distance / 280.0)
	return force

func _tick_supplies(delta: float) -> void:
	for event: Dictionary in state.events:
		if event.kind == "supply":
			event.pos.y = minf(ground(event.pos.x) - 18.0, event.pos.y + 100.0 * delta)
	for index: int in state.tanks.size():
		_collect_supplies(index)

func _collect_supplies(index: int) -> void:
	var tank: Dictionary = state.tanks[index]
	if tank.hp <= 0 or tank.id.begins_with("target_"):
		return
	for event: Dictionary in state.events.duplicate():
		if event.kind == "supply" and Vector2(tank.x, tank.y).distance_to(event.pos) < 48.0:
			_claim_supply(event, index)

func _claim_supply(event: Dictionary, index: int) -> void:
	var tank: Dictionary = state.tanks[index]
	if tank.hp <= 0:
		return
	state.events.erase(event)
	_heal(tank, 35)
	_sound("supply")
	var names: Array[String] = []
	for weapon: int in _draw_supply("crate"):
		if tank.ammo[weapon] >= 0:
			tank.ammo[weapon] += 1
		names.append(WEAPONS[weapon].name)
	_notify("%s 获得补给 · 生命 +35 · %s" % [tank.name, " / ".join(names)])

func _trigger_mines() -> void:
	for hazard: Dictionary in state.hazards.duplicate():
		if hazard.kind != "mine":
			continue
		var owner: Dictionary = state.tanks[hazard.owner]
		for tank: Dictionary in state.tanks:
			if tank.hp > 0 and tank.team != owner.team and absf(tank.x - hazard.x) < 52.0:
				state.hazards.erase(hazard)
				_blast(Vector2(hazard.x, ground(hazard.x) - 5.0), 14, hazard.owner, hazard.boost)
				break

func _tick_bursts(delta: float) -> void:
	for burst: Dictionary in state.bursts.duplicate():
		burst.delay -= delta
		if burst.delay <= 0.0:
			_blast(Vector2(burst.x, ground(burst.x)), 13, burst.owner, burst.boost)
			state.bursts.erase(burst)

func _notify(message: String) -> void:
	state.notice = message
	state.notice_left = 4.0

## Shared visible preview: only the first 0.6 seconds, cut at obstacles or splitting.
## Returning the muzzle alone is valid when the first step is already obstructed.
static func aim_path(snapshot: Dictionary, pos: Vector2, velocity: Vector2, weapon: int, steps: int = AIM_STEPS) -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array([pos])
	for i: int in mini(steps, AIM_STEPS):
		velocity += projectile_acceleration(snapshot, pos) / 60.0
		var next: Vector2 = pos + velocity / 60.0
		var obstacle: bool = false
		for event: Dictionary in snapshot.events:
			if event.kind == "portal":
				obstacle = obstacle or next.distance_to(event.pos) < PORTAL_RADIUS or next.distance_to(event.exit) < PORTAL_RADIUS
			elif event.kind == "bumper":
				obstacle = obstacle or next.distance_to(event.pos) < BUMPER_RADIUS
			elif event.kind == "black_hole":
				obstacle = obstacle or next.distance_to(event.pos) < BLACK_HOLE_CORE
		if obstacle or next.x < 0.0 or next.x > WIDTH:
			break
		if next.y >= snapshot.terrain[roundi(next.x / CELL)]:
			break
		if weapon in [3, 9] and velocity.y >= 0.0:
			break
		path.append(next)
		pos = next
	return path

## Aim through nearby cursor positions. Beyond the visible preview, solve against
## its endpoint tangent, not the hidden ballistic arc. Both branches meet at 0.6 s.
## Legal elevation/power limits still apply to unreachable or obstructed targets.
static func aim_at(snapshot: Dictionary, tank: Dictionary, weapon: int, target: Vector2) -> Vector2:
	var pivot: Vector2 = gun_pivot(tank)
	var steps: int = maxi(1, roundi(clampf(pivot.distance_to(target) / 600.0, 0.12, 3.0) * 60.0))
	var duration: float = steps / 60.0
	var visible_duration: float = mini(steps, AIM_STEPS) / 60.0
	var acceleration: Vector2 = snapshot.wind + Vector2(0.0, GRAVITY)
	var velocity: Vector2 = (target - pivot - acceleration * visible_duration * (duration - (visible_duration - 1.0 / 60.0) * 0.5)) / duration
	for correction: int in 6:
		var degrees: float = clampf(rad_to_deg(atan2(-velocity.y, velocity.x)), 5.0, 175.0)
		var muzzle: Vector2 = muzzle_position(tank, degrees)
		var path: PackedVector2Array = aim_path(snapshot, muzzle, velocity, weapon, steps)
		var tangent: Vector2 = (path[-1] - path[-2]) * 60.0 if path.size() > 1 else velocity
		var projection: Vector2 = path[-1] + tangent * (duration - (path.size() - 1) / 60.0)
		velocity += (target - projection) / duration
	var angle: float = clampf(rad_to_deg(atan2(-velocity.y, velocity.x)), 5.0, 175.0)
	var speed_scale: float = 0.82 if weapon == 1 else 1.0
	var power: float = clampf((velocity.length() / speed_scale - 270.0) / 6.0, 10.0, 100.0)
	return Vector2(angle, power)
