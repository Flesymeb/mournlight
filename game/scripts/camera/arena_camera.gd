class_name ArenaCamera
extends Camera3D

@export var target: Node3D
@export var follow_height := 10.8
@export var follow_distance := 8.6
@export var follow_damping := 8.5
@export var lead_distance := 2.4
@export var lead_damping := 5.0
@export var arena_limit := Vector2(10.5, 8.5)
@export var normal_fov := 48.0
@export var visibility_activation_seconds := 0.04
@export var visibility_release_seconds := 0.22
@export var visibility_probe_overscan := 1.25

var movement_velocity := Vector3.ZERO
var framing_target := Vector3.ZERO
var occlusion_guard_active := false
var _lead := Vector3.ZERO
var _blocked_seconds := 0.0
var _clear_seconds := 0.0
var _visibility_samples_blocked := 0
var _last_occluder := ""
var _presentation_meshes: Array[MeshInstance3D] = []
var _original_overlays: Dictionary = {}
var _visibility_overlay: StandardMaterial3D

func _ready() -> void:
	current = true
	fov = normal_fov
	if target:
		_bind_visibility_presentation()
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
	# Framing remains stable. Visibility isolation is driven by the live
	# camera-to-Warden sightline and never by player coordinates or map edits.
	_update_visibility_isolation(delta)
	fov = normal_fov
	var desired_position := framing_target + Vector3(0.0, follow_height, follow_distance)
	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_damping * delta))
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)

func _bind_visibility_presentation() -> void:
	_visibility_overlay = StandardMaterial3D.new()
	_visibility_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_visibility_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visibility_overlay.albedo_color = Color(1.0, 0.72, 0.24, 0.64)
	_visibility_overlay.emission_enabled = true
	_visibility_overlay.emission = Color(1.0, 0.52, 0.12)
	_visibility_overlay.emission_energy_multiplier = 1.8
	_visibility_overlay.no_depth_test = true
	_visibility_overlay.disable_fog = true
	for child in target.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D and String((child as Node).get_path()).contains("/PresentationRoot/"):
			var mesh := child as MeshInstance3D
			_presentation_meshes.append(mesh)
			_original_overlays[mesh.get_instance_id()] = mesh.material_overlay

func _update_visibility_isolation(delta: float) -> void:
	_visibility_samples_blocked = 0
	_last_occluder = ""
	var space_state := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	# The horizontal play datum is never a screen-space occluder. Excluding its
	# collision RID prevents a low body sample from falsely isolating the actor.
	var ground := get_node_or_null("../CemeteryGarden/OuterDatum/GroundCollision") as CollisionObject3D
	if is_instance_valid(ground):
		exclude.append(ground.get_rid())
	for height in [0.45, 0.95, 1.45]:
		var target_point: Vector3 = target.global_position + Vector3.UP * float(height)
		var sight_direction: Vector3 = (target_point - global_position).normalized()
		var query := PhysicsRayQueryParameters3D.new()
		query.from = global_position
		# Imported collision proxies are intentionally conservative. Extend the
		# sightline by roughly one actor depth so overlap is detected while the
		# silhouette is entering cover, not only after its origin disappears.
		query.to = target_point + sight_direction * visibility_probe_overscan
		query.exclude = exclude
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			_visibility_samples_blocked += 1
			if _last_occluder.is_empty() and is_instance_valid(hit.get("collider")):
				_last_occluder = String((hit.collider as Node).get_path())
	if _visibility_samples_blocked > 0:
		_blocked_seconds += delta
		_clear_seconds = 0.0
	else:
		_clear_seconds += delta
		_blocked_seconds = 0.0
	var next_active := occlusion_guard_active
	if not next_active and _blocked_seconds >= visibility_activation_seconds:
		next_active = true
	elif next_active and _clear_seconds >= visibility_release_seconds:
		next_active = false
	if next_active != occlusion_guard_active:
		occlusion_guard_active = next_active
		_apply_visibility_overlay(occlusion_guard_active)

func _apply_visibility_overlay(active: bool) -> void:
	for mesh in _presentation_meshes:
		if not is_instance_valid(mesh):
			continue
		mesh.material_overlay = _visibility_overlay if active else _original_overlays.get(mesh.get_instance_id())

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
		"visibility_isolation": {
			"active": occlusion_guard_active, "blocked_samples": _visibility_samples_blocked,
			"sample_count": 3, "blocked_seconds": _blocked_seconds,
			"clear_seconds": _clear_seconds, "last_occluder": _last_occluder,
			"overlay_mesh_count": _presentation_meshes.size(), "probe_overscan": visibility_probe_overscan,
		},
		"lead_distance": lead_distance,
		"fov": fov,
	}
