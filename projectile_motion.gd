extends RefCounted
## Visual-only flight from reliable trajectory segments. Never applies damage or claims pickups.
const Battle: Script = preload("res://games/minigame/gp_artillery/battle.gd")
const STEP: float = 1.0 / 60.0

static func signature(shot: Dictionary) -> Array:
	return [shot.bounces, shot.drilling, shot.rolling > 0.0, shot.boost, shot.lock_until, shot.support]

static func sample(shot: Dictionary, at_msec: int) -> Dictionary:
	return {"id": shot.id, "pos": shot.pos, "vel": shot.vel, "weapon": shot.weapon,
		"boost": shot.boost, "support": shot.support, "rolling": shot.rolling > 0.0,
		"at_msec": at_msec}

static func valid(value: Variant) -> bool:
	return value is Dictionary and value.get("id") is int and value.get("pos") is Vector2 and value.pos.is_finite() and value.get("vel") is Vector2 and value.vel.is_finite() and value.get("weapon") is int and value.weapon >= 0 and value.weapon < Battle.WEAPONS.size() and value.get("at_msec") is int and value.get("rolling") is bool and value.get("support") is bool and (value.get("boost") is float or value.get("boost") is int) and is_finite(float(value.boost))

## Fixed steps match host integration; only the fractional remainder is extrapolated for display.
static func render(shot: Dictionary, snapshot: Dictionary, now_msec: int) -> Dictionary:
	var elapsed: float = clampf(float(now_msec - int(shot.at_msec)) / 1000.0, 0.0, 12.0)
	var target_step: int = floori(elapsed / STEP)
	while int(shot.steps) < target_step:
		if shot.rolling:
			shot.pos.x = clampf(shot.pos.x + signf(shot.vel.x) * 145.0 * STEP, 1.0, Battle.WIDTH - 1.0)
			shot.pos.y = surface(snapshot, shot.pos.x) - 5.0
		else:
			shot.vel += Battle.projectile_acceleration(snapshot, shot.pos) * STEP
			shot.pos += shot.vel * STEP
		shot.steps += 1
	var visual: Dictionary = shot.duplicate()
	var remainder: float = elapsed - int(shot.steps) * STEP
	if shot.rolling:
		visual.pos.x = clampf(shot.pos.x + signf(shot.vel.x) * 145.0 * remainder, 1.0, Battle.WIDTH - 1.0)
		visual.pos.y = surface(snapshot, visual.pos.x) - 5.0
	else:
		visual.pos += shot.vel * remainder
	return visual

static func surface(snapshot: Dictionary, x: float) -> float:
	var cell: float = clampf(x / Battle.CELL, 0.0, 480.0)
	var left: int = mini(479, int(cell))
	return lerpf(snapshot.terrain[left], snapshot.terrain[left + 1], cell - left)
