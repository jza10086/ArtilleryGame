extends Node2D
## Chassis tilt carries the turret socket. Gun elevation is measured against the
## world horizon; the sliding tube recoils along the bore independently of the hull.
const Battle: Script = preload("res://games/minigame/godot_party_default_artillery_game/battle.gd")
const RECOIL_TIME: float = 0.19
@onready var hull: Node2D = %Hull
@onready var turret: Node2D = %Turret
@onready var gun: Node2D = %GunPivot
@onready var tube: Node2D = %SlidingTube
@onready var bore: Node2D = %Bore
@onready var muzzle: Marker2D = %Muzzle
@onready var sight: Marker2D = %Optic
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
	position = next_position
	rotation = tank.tilt
	var relative: float = -deg_to_rad(degrees) - rotation
	var facing: float = -1.0 if cos(relative) < 0.0 else 1.0
	turret.scale = Vector2(facing, 1)
	gun.rotation = atan2(sin(relative), facing * cos(relative))
	hull.modulate = tint
	turret.modulate = tint
	# The shot leaves the fully extended tube. Kick back, then return to battery.
	var progress: float = 1.0 - recoil_left / RECOIL_TIME
	tube.position.x = -6.0 * sin(PI * pow(progress, 0.52))
	recoil_left = maxf(0.0, recoil_left - delta)
