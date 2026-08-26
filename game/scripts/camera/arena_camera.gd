class_name ArenaCamera
extends Camera3D

@export var target: Node3D
@export var follow_height := 16.5
@export var follow_distance := 13.5
@export var follow_damping := 7.5
@export var lead_distance := 2.4
@export var lead_damping := 5.0
@export var arena_limit := Vector2(12.5, 9.5)

var movement_velocity := Vector3.ZERO
var framing_target := Vector3.ZERO
var _lead := Vector3.ZERO

func _ready() -> void:
	current = true
	if target:
		_snap_to_target()

func set_movement_velocity(value: Vector3) -> void:
	movement_velocity = Vector3(value.x, 0.0, value.z)

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var desired_lead := Vector3.ZERO
	if movement_velocity.length_squared() > 0.04:
		desired_lead = movement_velocity.normalized() * lead_distance
	_lead = _lead.lerp(desired_lead, 1.0 - exp(-lead_damping * delta))
	framing_target = target.global_position + _lead
	framing_target.x = clampf(framing_target.x, -arena_limit.x, arena_limit.x)
	framing_target.z = clampf(framing_target.z, -arena_limit.y, arena_limit.y)
	var desired_position := framing_target + Vector3(0.0, follow_height, follow_distance)
	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_damping * delta))
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)

func _snap_to_target() -> void:
	framing_target = target.global_position
	global_position = framing_target + Vector3(0.0, follow_height, follow_distance)
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)

func _mcp_state() -> Dictionary:
	return {
		"framing_target": framing_target,
		"movement_velocity": movement_velocity,
		"follow_height": follow_height,
		"follow_distance": follow_distance,
		"lead_distance": lead_distance,
		"fov": fov,
	}
