class_name ArenaCamera
extends Camera3D

@export var target: Node3D
@export var follow_height := 10.8
@export var follow_distance := 8.6
@export var follow_damping := 8.5
@export var lead_distance := 2.4
@export var lead_damping := 5.0
@export var arena_limit := Vector2(10.5, 8.5)
@export var occlusion_guard_height := 18.5
@export var occlusion_guard_distance := 3.2
@export var normal_fov := 48.0
@export var occlusion_guard_fov := 43.0

var movement_velocity := Vector3.ZERO
var framing_target := Vector3.ZERO
var occlusion_guard_active := false
var _lead := Vector3.ZERO

func _ready() -> void:
	current = true
	fov = normal_fov
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
	# The complete imported cemetery stays intact. These two product-owned
	# sight-lane zones steepen the camera when the Warden reaches the back of
	# the central mausoleum or the northeast tree instead of hiding the actor.
	var target_position := target.global_position
	occlusion_guard_active = (
		(target_position.z < 0.5 and absf(target_position.x) < 4.2)
		or (absf(target_position.x) > 4.4 and target_position.z < 2.0)
	)
	if occlusion_guard_active:
		# Keep the near arena edge in frame so the camera never presents the
		# un-authored void as the player's next movement choice.
		framing_target.z = maxf(framing_target.z, -2.0)
		framing_target.x = clampf(framing_target.x, -9.0, 9.0)
	var effective_height := occlusion_guard_height if occlusion_guard_active else follow_height
	var effective_distance := occlusion_guard_distance if occlusion_guard_active else follow_distance
	var desired_fov := occlusion_guard_fov if occlusion_guard_active else normal_fov
	fov = lerpf(fov, desired_fov, 1.0 - exp(-5.0 * delta))
	var desired_position := framing_target + Vector3(0.0, effective_height, effective_distance)
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
		"occlusion_guard_active": occlusion_guard_active,
		"occlusion_guard_height": occlusion_guard_height,
		"occlusion_guard_distance": occlusion_guard_distance,
		"lead_distance": lead_distance,
		"fov": fov,
	}
