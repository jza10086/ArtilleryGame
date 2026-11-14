extends Node2D
## Chassis tilt carries the turret socket. Gun elevation is measured against the
## chassis upper half-plane; the sliding tube recoils along the bore independently of the hull.
const Battle: Script = preload("res://games/minigame/gp_artillery/battle.gd")
const RECOIL_TIME: float = 0.19
@onready var hull: Node2D = %Hull
@onready var turret: Node2D = %Turret
@onready var gun: Node2D = %GunPivot
@onready var tube: Node2D = %SlidingTube
@onready var bore: Node2D = %Bore
@onready var muzzle: Marker2D = %Muzzle
@onready var sight: Marker2D = %Optic
@export_range(0.01, 0.3) var movement_blend_seconds: float = 0.12
var target_position: Vector2
var start_position: Vector2
var start_tilt: float = 0.0
var target_tilt: float = 0.0
var movement_age: float = 0.0
var placed: bool = false
var shot_count: int = -1
var recoil_left: float = 0.0

func _ready() -> void:
	turret.position = Battle.GUN_MOUNT
	bore.scale.x = Battle.BARREL_LENGTH

func pose(tank: Dictionary, degrees: float, tint: Color, delta: float) -> void:
	visible = tank.hp > 0
	if not visible:
		return
	var next_position: Vector2 = Vector2(tank.x, tank.y)
	if shot_count >= 0:
		if tank.shots > shot_count:
			recoil_left = RECOIL_TIME
	shot_count = tank.shots
	# Linear interpolation spans each movement command instead of braking after every sample.
	if not placed or position.distance_to(next_position) > 90.0 or delta == 0.0:
		position = next_position
		rotation = tank.tilt
		target_position = next_position
		target_tilt = tank.tilt
		start_position = position
		start_tilt = rotation
		movement_age = movement_blend_seconds
		placed = true
	elif next_position != target_position or not is_equal_approx(float(tank.tilt), target_tilt):
		start_position = position
		start_tilt = rotation
		target_position = next_position
		target_tilt = tank.tilt
		movement_age = 0.0
	movement_age = minf(movement_age + delta, movement_blend_seconds)
	var weight: float = movement_age / movement_blend_seconds
	position = start_position.lerp(target_position, weight)
	rotation = lerp_angle(start_tilt, target_tilt, weight)
	var relative: float = -deg_to_rad(clampf(degrees, 0.0, 180.0))
	var facing: float = -1.0 if cos(relative) < 0.0 else 1.0
	turret.scale = Vector2(facing, 1)
	gun.rotation = atan2(sin(relative), facing * cos(relative))
	hull.modulate = tint
	turret.modulate = tint
	# The shot leaves the fully extended tube. Kick back, then return to battery.
	var progress: float = 1.0 - recoil_left / RECOIL_TIME
	tube.position.x = -6.0 * sin(PI * pow(progress, 0.52))
	recoil_left = maxf(0.0, recoil_left - delta)
