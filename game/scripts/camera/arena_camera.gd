class_name ArenaCamera
extends Camera3D

@export var target: Node3D
@export var arena_contract: CemeterySpatialContract
@export var follow_height := 24.0
@export var follow_distance := 22.0
## Fixed three-quarter azimuth keeps the Warden out of the mausoleum's stair
## silhouette while retaining a high-angle escape-lane read.  The rig still
## follows the player; this is only the authored lateral offset of that rig.
@export var follow_lateral := 7.5
@export var follow_damping := 8.5
@export var lead_distance := 2.4
@export var lead_damping := 5.0
# Keep the Warden in the lower-safe lane without aiming the camera through the
# mausoleum volume.  The previous -5.5 north bias put several Warden AABB
# samples behind the landmark and under-reported shipped visibility.
@export var framing_bias := Vector3(0.0, 0.0, -1.0)
@export var arena_limit := Vector2(34.0, 32.0)
@export var normal_fov := 64.0
@export var safe_frame_fraction := Vector2(0.08, 0.10)
@export var safe_frame_activation_buffer := 0.04
@export var safe_frame_correction_damping := 11.0
@export var safe_frame_max_correction := 1.25
@export var safe_frame_actor_half_width := 0.72
@export var safe_frame_actor_half_depth := 0.48
@export var safe_frame_actor_height := 2.05
@export var coverage_group := &"active_enemies"
@export_range(1, 12, 1) var coverage_subject_limit := 8
@export var coverage_radius := 12.5
@export var coverage_frame_fraction := Vector2(0.07, 0.10)
@export var coverage_actor_half_width := 0.62
@export var coverage_actor_half_depth := 0.48
@export var coverage_actor_height := 1.5
@export var coverage_max_correction := 2.8
@export var coverage_correction_damping := 8.0
@export var coverage_threat_weight := 0.18
@export var dense_fov_boost := 8.0
@export var dense_fov_start_count := 16
@export var dense_fov_full_count := 32
@export var arena_fill_limit := Vector2(33.0, 30.5)
@export var obstruction_inward_weight := 0.38
@export var obstruction_lateral_bypass := 0.0
@export var obstruction_height_boost := 0.8
@export var obstruction_distance_reduction := 0.5
@export var obstruction_fov_boost := 2.0
@export var coverage_occluder_visuals: Array[NodePath] = []
@export_range(0.0, 1.0, 0.01) var coverage_occluder_transparency := 0.78
@export var coverage_settle_seconds := 0.28
@export var visibility_activation_seconds := 0.04
@export var visibility_release_seconds := 0.22
@export var visibility_probe_overscan := 1.25
@export var presentation_body: NodePath
@export var presentation_lantern: NodePath
@export var presentation_effects: Array[NodePath] = []
@export var tall_occluders: Array[NodePath] = []
@export var direct_sight_volume_radius := 0.9
## Dense-wave secondary visibility is a safety compositor, not a second full
## resolution camera. Keep its texture cheap and refresh it on a bounded cadence
## while the primary shipped camera remains responsive every frame.
@export_range(0.25, 1.0, 0.05) var dense_compositor_resolution_scale := 0.5
@export var dense_compositor_refresh_seconds := 0.12

const VISIBILITY_LAYER := 20

var movement_velocity := Vector3.ZERO
var framing_target := Vector3.ZERO
var occlusion_guard_active := false
var safe_frame_ok := true
var safe_frame_correction_active := false
var projected_margins := {"left":0.0, "right":0.0, "top":0.0, "bottom":0.0, "minimum":0.0}
var _lead := Vector3.ZERO
var _safe_frame_offset := Vector3.ZERO
var _safe_frame_screen_shift := Vector2.ZERO
var _coverage_offset := Vector3.ZERO
var _coverage_screen_shift := Vector2.ZERO
var _coverage_subject_paths: Array[String] = []
var _coverage_active_count := 0
var _coverage_members_cache: Array[Node] = []
var _coverage_members_refresh_remaining := 0.0
var _coverage_members_scan_count := 0
var _coverage_members_scan_skips := 0
var _coverage_receipt: Dictionary = {}
var _coverage_response_source := "spawn"
var _coverage_settled_seconds := 0.0
var _coverage_obstructed_count := 0
var _coverage_obstructing_path := ""
var _coverage_obstructing_paths: Array[String] = []
var _arena_containment_active := false
var _obstruction_response_strength := 0.0
var _obstruction_bypass_sign := 0.0
var _coverage_occluder_visual_bindings: Array[GeometryInstance3D] = []
var _coverage_visuals_by_occluder: Dictionary = {}
var _coverage_occluder_original_transparency: Dictionary = {}
var _coverage_occluder_original_visibility: Dictionary = {}
var _blocked_seconds := 0.0
var _clear_seconds := 0.0
var _visibility_samples_blocked := 0
var _last_occluder := ""
var _presentation_visuals: Array[VisualInstance3D] = []
var _source_visuals: Array[VisualInstance3D] = []
var _effect_visuals: Array[VisualInstance3D] = []
var _binding_members: Array[Dictionary] = []
var _original_visual_layers: Dictionary = {}
var _original_visual_visibility: Dictionary = {}
var _original_material_overlays: Dictionary = {}
var _primary_camera_visibility_layer := true
var _visibility_viewport: SubViewport
var _visibility_camera: Camera3D
var _visibility_canvas: CanvasLayer
var _visibility_texture: TextureRect
var _compositor_frame_count := 0
var _tall_occluder_bindings: Array[Dictionary] = []
var _direct_detection_active := false
var _detection_source := "clear"
var _compositor_allowed := false
var _compositor_refresh_remaining := 0.0
var _compositor_requested_updates := 0
var _compositor_skipped_updates := 0

func _ready() -> void:
	current = true
	fov = normal_fov
	if target:
		_normalize_occluder_bindings()
		_bind_visibility_presentation()
		_bind_tall_occluders()
		_bind_coverage_occluder_visuals()
		_build_visibility_compositor()
		_snap_to_target()

func _normalize_occluder_bindings() -> void:
	# Keep the product-owned sight volumes paired with their authored visuals.
	# The serialized profile predates the mausoleum isolation pass and had the
	# Crypt visual paired with a tree collider, so obstruction detection could
	# never fade the landmark that actually crossed the Warden sightline.  This
	# rebase is runtime-only and does not touch the intact imported package.
	var pairs := [
		[NodePath("../CemeteryGarden/OuterDatum/MausoleumCollision"), NodePath("../CemeteryGarden/PackageTransform/AuthoredCemeteryPackage/Sketchfab_model/59eaeb0f852e494285bd67ea8f850a42_fbx/RootNode/Crypt")],
		[NodePath("../CemeteryGarden/OuterDatum/NortheastTreeCollision"), NodePath("../CemeteryGarden/PackageTransform/AuthoredCemeteryPackage/Sketchfab_model/59eaeb0f852e494285bd67ea8f850a42_fbx/RootNode/DeadTree3")],
		[NodePath("../CemeteryGarden/OuterDatum/NorthwestTreeCollision"), NodePath("../CemeteryGarden/PackageTransform/AuthoredCemeteryPackage/Sketchfab_model/59eaeb0f852e494285bd67ea8f850a42_fbx/RootNode/DeadTree")],
		[NodePath("../CemeteryGarden/OuterDatum/SoutheastTreeCollision"), NodePath("../CemeteryGarden/PackageTransform/AuthoredCemeteryPackage/Sketchfab_model/59eaeb0f852e494285bd67ea8f850a42_fbx/RootNode/DeadTree2")],
	]
	var normalized_colliders: Array[NodePath] = []
	var normalized_visuals: Array[NodePath] = []
	for pair in pairs:
		var collider_path: NodePath = pair[0]
		var visual_path: NodePath = pair[1]
		if is_instance_valid(get_node_or_null(collider_path)) and is_instance_valid(get_node_or_null(visual_path)):
			normalized_colliders.append(collider_path)
			normalized_visuals.append(visual_path)
	if not normalized_colliders.is_empty():
		tall_occluders = normalized_colliders
		coverage_occluder_visuals = normalized_visuals

func _exit_tree() -> void:
	reset_occlusion_response()

func set_movement_velocity(value: Vector3) -> void:
	movement_velocity = Vector3(value.x, 0.0, value.z)

func set_shell_state(run_state: String) -> void:
	# The run controller is the authoritative owner of shell visibility. Draft,
	# pause, settings, title, result, death, and victory never share the viewport
	# with the private Warden compositor.
	_compositor_allowed = run_state in ["active", "boss"]
	if not _compositor_allowed:
		occlusion_guard_active = false
		_blocked_seconds = 0.0
		_clear_seconds = 0.0
		_apply_visibility_overlay(false)

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if not _compositor_allowed:
		if occlusion_guard_active or (is_instance_valid(_visibility_texture) and _visibility_texture.visible):
			set_shell_state("modal")
		return
	_compositor_refresh_remaining = maxf(0.0, _compositor_refresh_remaining - delta)
	_coverage_members_refresh_remaining = maxf(0.0, _coverage_members_refresh_remaining - delta)
	var desired_lead := Vector3.ZERO
	if movement_velocity.length_squared() > 0.04:
		desired_lead = movement_velocity.normalized() * lead_distance
	_lead = _lead.lerp(desired_lead, 1.0 - exp(-lead_damping * delta))
	# Bias the shipped high-angle composition slightly toward the authored
	# north route. This keeps the Warden in the lower-safe lane while bringing
	# the mausoleum/bell landmarks into the same readable frame at spawn.
	var requested_target := target.global_position + _lead + framing_bias
	var subjects := _select_coverage_subjects()
	var arena_target := _compose_arena_target(requested_target, subjects)
	var desired_obstruction_strength := 1.0 if _coverage_obstructed_count > 0 else 0.0
	var obstruction_damping := 7.0 if desired_obstruction_strength > _obstruction_response_strength else 1.8
	_obstruction_response_strength = lerpf(_obstruction_response_strength, desired_obstruction_strength, 1.0 - exp(-obstruction_damping * delta))
	_apply_coverage_occluder_fade()
	var before := _measure_subject_coverage(subjects)
	var activation_fraction := Vector2(
		coverage_frame_fraction.x + safe_frame_activation_buffer,
		coverage_frame_fraction.y + safe_frame_activation_buffer
	)
	var approaching_edge := not _margins_inside_fraction(before, activation_fraction)
	var inside_release_band := _margins_inside_fraction(before, Vector2(activation_fraction.x + safe_frame_activation_buffer, activation_fraction.y + safe_frame_activation_buffer))
	var desired_offset := Vector3.ZERO
	_coverage_screen_shift = Vector2.ZERO
	if approaching_edge:
		_coverage_screen_shift = _screen_shift_into_fraction(before, activation_fraction)
		desired_offset = _coverage_offset + _screen_shift_to_ground_correction(before, _coverage_screen_shift)
		desired_offset.y = 0.0
		desired_offset = desired_offset.limit_length(coverage_max_correction)
	elif safe_frame_correction_active and not inside_release_band:
		desired_offset = _coverage_offset
	_coverage_offset = _coverage_offset.lerp(desired_offset, 1.0 - exp(-coverage_correction_damping * delta))
	_safe_frame_offset = _coverage_offset
	_safe_frame_screen_shift = _coverage_screen_shift
	framing_target = arena_target + _coverage_offset
	framing_target.x = clampf(framing_target.x, -arena_fill_limit.x, arena_fill_limit.x)
	framing_target.z = clampf(framing_target.z, -arena_fill_limit.y, arena_fill_limit.y)
	var dense_fraction := clampf(
		float(_coverage_active_count - dense_fov_start_count) / float(maxi(1, dense_fov_full_count - dense_fov_start_count)),
		0.0,
		1.0
	)
	fov = normal_fov + dense_fov_boost * dense_fraction + obstruction_fov_boost * _obstruction_response_strength
	var effective_height := follow_height + obstruction_height_boost * _obstruction_response_strength
	var effective_distance := follow_distance - obstruction_distance_reduction * _obstruction_response_strength
	var desired_position := framing_target + Vector3(follow_lateral, effective_height, effective_distance)
	desired_position.x += _obstruction_bypass_sign * obstruction_lateral_bypass * _obstruction_response_strength
	# Keep the shipped camera inside the intact authored world.  At the outer
	# perimeter the follow offset can otherwise place the camera beyond the GLB
	# footprint, which renders an empty black half-frame even though the Warden
	# itself is still inside the collision datum.  This clamp only affects the
	# camera rig; it does not resize or duplicate the authored package.
	if is_instance_valid(arena_contract):
		var visual_rect := arena_contract.get_authored_visual_rect()
		# Keep the rig materially inside the authored terrain footprint.  A small
		# three-metre inset still lets the high-angle lens see past the native
		# southern/northern edge at the spawn lane, which reads as a black datum
		# void in shipped captures.  The larger inset preserves external depth in
		# frame while keeping the visible street network authoritative.
		var camera_margin := 8.0
		desired_position.x = clampf(desired_position.x, visual_rect.position.x + camera_margin, visual_rect.end.x - camera_margin)
		desired_position.z = clampf(desired_position.z, visual_rect.position.y + camera_margin, visual_rect.end.y - camera_margin)
	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_damping * delta))
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)
	var warden_after := _measure_projected_safe_frame()
	var after := _measure_subject_coverage(subjects)
	projected_margins = (warden_after.get("margins", {}) as Dictionary).duplicate(true)
	var coverage_inside := bool(after.get("inside_fraction", false))
	var warden_inside := bool(warden_after.get("inside_fraction", false))
	var arena_fill_ok := absf(framing_target.x) <= arena_fill_limit.x + 0.01 and absf(framing_target.z) <= arena_fill_limit.y + 0.01
	var obstruction_resolved := _coverage_obstructed_count == 0 or (_coverage_occluder_visual_bindings.size() > 0 and _obstruction_response_strength >= 0.65)
	safe_frame_ok = warden_inside and coverage_inside and arena_fill_ok and obstruction_resolved
	safe_frame_correction_active = _coverage_offset.length_squared() > 0.0025 or not safe_frame_ok or _arena_containment_active
	_update_coverage_receipt(after, warden_inside, coverage_inside, arena_fill_ok, delta)
	# Projected containment owns framing. Sightline isolation remains a secondary
	# response to cemetery geometry that genuinely crosses the camera-to-Warden ray.
	_update_visibility_isolation(delta)
	_sync_visibility_camera()

func _select_coverage_subjects() -> Array[Node3D]:
	var subjects: Array[Node3D] = []
	if is_instance_valid(target):
		subjects.append(target)
	var candidates: Array[Dictionary] = []
	# Cache the bounded active-enemy membership at the same cadence as other
	# dense presentation budgets. Camera framing remains responsive because
	# transforms are read every frame; only the scene-wide group inventory is
	# staggered, avoiding a 32-enemy allocation/scan on every render tick.
	var active_members: Array[Node] = _coverage_members_cache
	if _coverage_members_refresh_remaining <= 0.0:
		active_members = get_tree().get_nodes_in_group(coverage_group)
		_coverage_members_cache = active_members.duplicate()
		_coverage_members_refresh_remaining = 0.1
		_coverage_members_scan_count += 1
	else:
		_coverage_members_scan_skips += 1
	_coverage_active_count = active_members.size()
	for member in active_members:
		if not is_instance_valid(member) or not member is Node3D or member == target:
			continue
		var actor := member as Node3D
		var distance_squared := actor.global_position.distance_squared_to(target.global_position)
		if distance_squared > coverage_radius * coverage_radius:
			continue
		var state := String(actor.get("state"))
		var danger_priority := 0 if state in ["telegraph", "damage", "attack"] else 1
		candidates.append({"node":actor, "priority":danger_priority, "distance_squared":distance_squared, "path":String(actor.get_path())})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if not is_equal_approx(float(a.distance_squared), float(b.distance_squared)):
			return float(a.distance_squared) < float(b.distance_squared)
		return String(a.path) < String(b.path)
	)
	for index in mini(coverage_subject_limit, candidates.size()):
		subjects.append(candidates[index].node as Node3D)
	_coverage_subject_paths.clear()
	for subject in subjects:
		_coverage_subject_paths.append(String(subject.get_path()))
	return subjects

func _compose_arena_target(requested_target: Vector3, subjects: Array[Node3D]) -> Vector3:
	var composed := arena_contract.clamp_camera_target(requested_target) if is_instance_valid(arena_contract) else requested_target
	if not is_instance_valid(arena_contract):
		composed.x = clampf(composed.x, -arena_fill_limit.x, arena_fill_limit.x)
		composed.z = clampf(composed.z, -arena_fill_limit.y, arena_fill_limit.y)
	else:
		# Leave a small inward look-ahead band at each visual edge.  Without this
		# the camera can be forced to look almost straight down at a perimeter
		# wall, exposing the non-playable underside of the authored GLB.
		var fill := arena_contract.get_camera_fill_rect()
		var edge_inset := 3.0
		composed.x = clampf(composed.x, fill.position.x + edge_inset, fill.end.x - edge_inset)
		composed.z = clampf(composed.z, fill.position.y + edge_inset, fill.end.y - edge_inset)
	_arena_containment_active = not is_equal_approx(composed.x, requested_target.x) or not is_equal_approx(composed.z, requested_target.z)
	if subjects.size() > 1:
		var threat_center := Vector3.ZERO
		for index in range(1, subjects.size()):
			threat_center += subjects[index].global_position
		threat_center /= float(subjects.size() - 1)
		threat_center.y = composed.y
		composed = composed.lerp(threat_center, coverage_threat_weight)
	_coverage_obstructed_count = 0
	_coverage_obstructing_path = ""
	_coverage_obstructing_paths.clear()
	_obstruction_bypass_sign = 0.0
	for subject in subjects:
		var obstruction := _find_registered_subject_occluder(subject)
		if obstruction.is_empty():
			continue
		_coverage_obstructed_count += 1
		if not _coverage_obstructing_paths.has(obstruction):
			_coverage_obstructing_paths.append(obstruction)
		if _coverage_obstructing_path.is_empty():
			_coverage_obstructing_path = obstruction
			var obstruction_node := get_node_or_null(obstruction) as Node3D
			if is_instance_valid(obstruction_node):
				_obstruction_bypass_sign = -1.0 if target.global_position.x <= obstruction_node.global_position.x else 1.0
	if _coverage_obstructed_count > 0:
		var inward := Vector3.ZERO
		inward.y = composed.y
		composed = composed.lerp(inward, obstruction_inward_weight)
	if is_instance_valid(arena_contract):
		composed = arena_contract.clamp_camera_target(composed)
	else:
		composed.x = clampf(composed.x, -arena_fill_limit.x, arena_fill_limit.x)
		composed.z = clampf(composed.z, -arena_fill_limit.y, arena_fill_limit.y)
	return composed

func _find_registered_subject_occluder(subject: Node3D) -> String:
	var subject_points := [subject.global_position + Vector3.UP * 0.35, subject.global_position + Vector3.UP * 1.0]
	for binding in _tall_occluder_bindings:
		if not bool(binding.get("bound", false)):
			continue
		for shape in binding.get("shapes", []):
			if not is_instance_valid(shape) or shape.disabled:
				continue
			for subject_point in subject_points:
				if _sight_segment_intersects_shape_volume(global_position, subject_point, shape):
					return String(binding.get("resolved_path", binding.get("source_path", "")))
	return ""

func _measure_subject_coverage(subjects: Array[Node3D]) -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0 or subjects.is_empty():
		return {"inside_fraction":false, "viewport":viewport_size, "margins":{}, "rect":Rect2(), "center":Vector2.ZERO, "classifications":[]}
	var min_screen := Vector2(INF, INF)
	var max_screen := Vector2(-INF, -INF)
	var classifications: Array[Dictionary] = []
	for subject in subjects:
		var half_width := safe_frame_actor_half_width if subject == target else coverage_actor_half_width
		var half_depth := safe_frame_actor_half_depth if subject == target else coverage_actor_half_depth
		var actor_height := safe_frame_actor_height if subject == target else coverage_actor_height
		var subject_min := Vector2(INF, INF)
		var subject_max := Vector2(-INF, -INF)
		var behind := false
		for x_offset in [-half_width, half_width]:
			for y_offset in [0.05, actor_height]:
				for z_offset in [-half_depth, half_depth]:
					var world_point := subject.global_position + Vector3(x_offset, y_offset, z_offset)
					if is_position_behind(world_point):
						behind = true
						continue
					var screen := unproject_position(world_point)
					subject_min.x = minf(subject_min.x, screen.x)
					subject_min.y = minf(subject_min.y, screen.y)
					subject_max.x = maxf(subject_max.x, screen.x)
					subject_max.y = maxf(subject_max.y, screen.y)
		if behind or subject_min.x == INF:
			classifications.append({"path":String(subject.get_path()), "classification":"behind"})
			continue
		min_screen.x = minf(min_screen.x, subject_min.x)
		min_screen.y = minf(min_screen.y, subject_min.y)
		max_screen.x = maxf(max_screen.x, subject_max.x)
		max_screen.y = maxf(max_screen.y, subject_max.y)
		var on_screen := subject_min.x >= 0.0 and subject_min.y >= 0.0 and subject_max.x <= viewport_size.x and subject_max.y <= viewport_size.y
		classifications.append({"path":String(subject.get_path()), "classification":"on_screen" if on_screen else "partial_or_offscreen", "rect":Rect2(subject_min, subject_max - subject_min)})
	if min_screen.x == INF:
		return {"inside_fraction":false, "viewport":viewport_size, "margins":{}, "rect":Rect2(), "center":Vector2.ZERO, "classifications":classifications}
	var margins := {"left":min_screen.x, "right":viewport_size.x - max_screen.x, "top":min_screen.y, "bottom":viewport_size.y - max_screen.y}
	margins["minimum"] = minf(minf(float(margins.left), float(margins.right)), minf(float(margins.top), float(margins.bottom)))
	var receipt := {"viewport":viewport_size, "center":(min_screen + max_screen) * 0.5, "rect":Rect2(min_screen, max_screen - min_screen), "margins":margins, "classifications":classifications}
	receipt["inside_fraction"] = _margins_inside_fraction(receipt, coverage_frame_fraction) and classifications.all(func(item: Dictionary) -> bool: return String(item.classification) == "on_screen")
	return receipt

func _update_coverage_receipt(after: Dictionary, warden_inside: bool, coverage_inside: bool, arena_fill_ok: bool, delta: float) -> void:
	if safe_frame_ok and movement_velocity.length_squared() <= 0.01:
		_coverage_settled_seconds += delta
	else:
		_coverage_settled_seconds = 0.0
	var reasons: Array[String] = []
	if _arena_containment_active:
		reasons.append("arena_inward_containment")
	if not coverage_inside:
		reasons.append("multi_subject_projection")
	if _coverage_obstructed_count > 0:
		reasons.append("registered_tall_obstruction")
	if reasons.is_empty():
		reasons.append("stable_follow")
	_coverage_response_source = "+".join(reasons)
	_coverage_receipt = {
		"evaluated_subject_count":_coverage_subject_paths.size(),
		"evaluated_subject_paths":_coverage_subject_paths.duplicate(),
		"dangerous_actor_count":maxi(0, _coverage_subject_paths.size() - 1),
		"subject_limit":coverage_subject_limit,
		"coverage_radius":coverage_radius,
		"warden_inside":warden_inside,
		"coverage_inside":coverage_inside,
		"arena_fill_ok":arena_fill_ok,
		"arena_containment_active":_arena_containment_active,
		"obstructed_subject_count":_coverage_obstructed_count,
		"obstructing_path":_coverage_obstructing_path,
		"response_source":_coverage_response_source,
		"settled":_coverage_settled_seconds >= coverage_settle_seconds,
		"settled_seconds":_coverage_settled_seconds,
		"membership_scan_count":_coverage_members_scan_count,
		"membership_scan_skips":_coverage_members_scan_skips,
		"membership_refresh_seconds":0.1,
		"classifications":(after.get("classifications", []) as Array).duplicate(true),
		"projected_margins":(after.get("margins", {}) as Dictionary).duplicate(true),
	}

func _measure_projected_safe_frame() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0 or not is_instance_valid(target):
		return {"inside_fraction":false, "margins":projected_margins.duplicate(true), "center":Vector2.ZERO, "rect":Rect2()}
	var min_screen := Vector2(INF, INF)
	var max_screen := Vector2(-INF, -INF)
	var center_world := target.global_position + Vector3.UP * safe_frame_actor_height * 0.5
	for x_offset in [-safe_frame_actor_half_width, safe_frame_actor_half_width]:
		for y_offset in [0.05, safe_frame_actor_height]:
			for z_offset in [-safe_frame_actor_half_depth, safe_frame_actor_half_depth]:
				var world_point := target.global_position + Vector3(x_offset, y_offset, z_offset)
				if is_position_behind(world_point):
					return {"inside_fraction":false, "margins":{"left":-INF,"right":-INF,"top":-INF,"bottom":-INF,"minimum":-INF}, "center":Vector2.ZERO, "rect":Rect2()}
				var screen := unproject_position(world_point)
				min_screen.x = minf(min_screen.x, screen.x)
				min_screen.y = minf(min_screen.y, screen.y)
				max_screen.x = maxf(max_screen.x, screen.x)
				max_screen.y = maxf(max_screen.y, screen.y)
	var margins := {
		"left":min_screen.x, "right":viewport_size.x - max_screen.x,
		"top":min_screen.y, "bottom":viewport_size.y - max_screen.y,
	}
	margins["minimum"] = minf(minf(float(margins.left), float(margins.right)), minf(float(margins.top), float(margins.bottom)))
	var receipt := {
		"viewport":viewport_size,
		"center":unproject_position(center_world),
		"rect":Rect2(min_screen, max_screen - min_screen),
		"margins":margins,
	}
	receipt["inside_fraction"] = _margins_inside_fraction(receipt, safe_frame_fraction)
	return receipt

func _margins_inside_fraction(receipt: Dictionary, fraction: Vector2) -> bool:
	var viewport_size: Vector2 = receipt.get("viewport", get_viewport().get_visible_rect().size)
	var margins: Dictionary = receipt.get("margins", {})
	return (
		float(margins.get("left", -INF)) >= viewport_size.x * fraction.x
		and float(margins.get("right", -INF)) >= viewport_size.x * fraction.x
		and float(margins.get("top", -INF)) >= viewport_size.y * fraction.y
		and float(margins.get("bottom", -INF)) >= viewport_size.y * fraction.y
	)

func _screen_shift_into_fraction(receipt: Dictionary, fraction: Vector2) -> Vector2:
	var viewport_size: Vector2 = receipt.get("viewport", get_viewport().get_visible_rect().size)
	var rect: Rect2 = receipt.get("rect", Rect2())
	var safe_min := Vector2(viewport_size.x * fraction.x, viewport_size.y * fraction.y)
	var safe_max := Vector2(viewport_size.x * (1.0 - fraction.x), viewport_size.y * (1.0 - fraction.y))
	var shift := Vector2.ZERO
	if rect.position.x < safe_min.x:
		shift.x = safe_min.x - rect.position.x
	elif rect.end.x > safe_max.x:
		shift.x = safe_max.x - rect.end.x
	if rect.position.y < safe_min.y:
		shift.y = safe_min.y - rect.position.y
	elif rect.end.y > safe_max.y:
		shift.y = safe_max.y - rect.end.y
	return shift

func _screen_shift_to_ground_correction(receipt: Dictionary, shift: Vector2) -> Vector3:
	if shift.length_squared() < 0.01:
		return Vector3.ZERO
	var center: Vector2 = receipt.get("center", Vector2.ZERO)
	var current_ground := _screen_to_target_plane(center)
	var desired_ground := _screen_to_target_plane(center + shift)
	return current_ground - desired_ground

func _screen_to_target_plane(screen: Vector2) -> Vector3:
	var origin := project_ray_origin(screen)
	var direction := project_ray_normal(screen)
	if absf(direction.y) < 0.0001:
		return target.global_position
	var distance := (target.global_position.y - origin.y) / direction.y
	return origin + direction * maxf(0.0, distance)

func _bind_visibility_presentation() -> void:
	# The compositor owns the complete concrete Warden contract. Every authored
	# body, lantern, and effect visual moves through the same private camera layer
	# while obstructed; no proxy material or duplicate actor exists.
	_bind_member("body", presentation_body)
	_bind_member("lantern", presentation_lantern)
	for effect_path in presentation_effects:
		var effect := get_node_or_null(effect_path)
		if not is_instance_valid(effect):
			continue
		var visuals := _collect_visuals(effect)
		for visual in visuals:
			_register_visual(visual)
			_effect_visuals.append(visual)
		_binding_members.append({"role":"effect", "bound":true, "source_path":String(effect_path), "isolation":"complete_private_layer_compositor", "visual_count":visuals.size()})

func _bind_tall_occluders() -> void:
	_tall_occluder_bindings.clear()
	for source_path in tall_occluders:
		var body := get_node_or_null(source_path) as CollisionObject3D
		var shapes: Array[CollisionShape3D] = []
		if is_instance_valid(body):
			for child in body.find_children("*", "CollisionShape3D", true, false):
				if child is CollisionShape3D and is_instance_valid((child as CollisionShape3D).shape):
					shapes.append(child as CollisionShape3D)
		_tall_occluder_bindings.append({
			"source_path":String(source_path),
			"resolved_path":String(body.get_path()) if is_instance_valid(body) else "",
			"body":body,
			"shapes":shapes,
			"bound":is_instance_valid(body) and not shapes.is_empty(),
			"shape_count":shapes.size(),
		})

func _bind_coverage_occluder_visuals() -> void:
	_coverage_occluder_visual_bindings.clear()
	_coverage_visuals_by_occluder.clear()
	_coverage_occluder_original_transparency.clear()
	_coverage_occluder_original_visibility.clear()
	for index in mini(coverage_occluder_visuals.size(), _tall_occluder_bindings.size()):
		var source_path := coverage_occluder_visuals[index]
		var binding: Dictionary = _tall_occluder_bindings[index]
		var occluder_path := String(binding.get("resolved_path", ""))
		var bound_visuals: Array[GeometryInstance3D] = []
		var source := get_node_or_null(source_path)
		for member in _collect_visuals(source):
			if not is_instance_valid(member) or not member is GeometryInstance3D:
				continue
			var visual := member as GeometryInstance3D
			if _coverage_occluder_visual_bindings.has(visual):
				continue
			_coverage_occluder_visual_bindings.append(visual)
			bound_visuals.append(visual)
			_coverage_occluder_original_transparency[visual.get_instance_id()] = visual.transparency
			_coverage_occluder_original_visibility[visual.get_instance_id()] = visual.visible
		if not occluder_path.is_empty():
			_coverage_visuals_by_occluder[occluder_path] = bound_visuals

func _apply_coverage_occluder_fade() -> void:
	for visual in _coverage_occluder_visual_bindings:
		if not is_instance_valid(visual):
			continue
		var active_for_visual := false
		for occluder_path in _coverage_obstructing_paths:
			if visual in (_coverage_visuals_by_occluder.get(occluder_path, []) as Array):
				active_for_visual = true
				break
		var response := _obstruction_response_strength if active_for_visual else 0.0
		var original := float(_coverage_occluder_original_transparency.get(visual.get_instance_id(), 0.0))
		visual.transparency = lerpf(original, maxf(original, coverage_occluder_transparency), response)
		# Never hard-hide a registered occluder. Members authored hidden stay hidden;
		# originally visible members remain rendered throughout the continuous fade.
		visual.visible = bool(_coverage_occluder_original_visibility.get(visual.get_instance_id(), true))

func reset_occlusion_response() -> void:
	_obstruction_response_strength = 0.0
	_coverage_obstructed_count = 0
	_coverage_obstructing_path = ""
	_coverage_obstructing_paths.clear()
	_blocked_seconds = 0.0
	_clear_seconds = 0.0
	occlusion_guard_active = false
	_apply_visibility_overlay(false)
	for visual in _coverage_occluder_visual_bindings:
		if not is_instance_valid(visual):
			continue
		var instance_id := visual.get_instance_id()
		visual.transparency = float(_coverage_occluder_original_transparency.get(instance_id, visual.transparency))
		visual.visible = bool(_coverage_occluder_original_visibility.get(instance_id, visual.visible))

func _bind_member(role: String, source_path: NodePath) -> void:
	var source := get_node_or_null(source_path)
	var source_members := _collect_visuals(source)
	for visual in source_members:
		_register_visual(visual)
		_source_visuals.append(visual)
	_binding_members.append({
		"role":role,
		"bound":is_instance_valid(source),
		"source_path":String(source_path),
		"isolation":"complete_private_layer_compositor",
		"source_visual_count":source_members.size(),
	})

func _collect_visuals(root: Node) -> Array[VisualInstance3D]:
	var result: Array[VisualInstance3D] = []
	if not is_instance_valid(root):
		return result
	if root is VisualInstance3D:
		result.append(root as VisualInstance3D)
	for child in root.find_children("*", "VisualInstance3D", true, false):
		if is_instance_valid(child) and child is VisualInstance3D:
			result.append(child as VisualInstance3D)
	return result

func _register_visual(visual: VisualInstance3D) -> void:
	if _presentation_visuals.has(visual):
		return
	_presentation_visuals.append(visual)
	_original_visual_layers[visual.get_instance_id()] = visual.layers
	_original_visual_visibility[visual.get_instance_id()] = visual.visible
	if visual is GeometryInstance3D:
		_original_material_overlays[visual.get_instance_id()] = (visual as GeometryInstance3D).material_overlay

func _build_visibility_compositor() -> void:
	# The isolation camera shares the live World3D but renders only the Warden's
	# private visibility layer onto a transparent full-viewport texture. This is
	# a camera-owned composition boundary: cemetery geometry remains untouched
	# and cannot depth-occlude the isolated silhouette.
	_primary_camera_visibility_layer = get_cull_mask_value(VISIBILITY_LAYER)
	_visibility_viewport = SubViewport.new()
	_visibility_viewport.name = "WardenVisibilityViewport"
	_visibility_viewport.transparent_bg = true
	_visibility_viewport.own_world_3d = false
	_visibility_viewport.world_3d = get_world_3d()
	_visibility_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_visibility_viewport.size = _secondary_viewport_size()
	add_child(_visibility_viewport)
	_visibility_camera = Camera3D.new()
	_visibility_camera.name = "WardenVisibilityCamera"
	_visibility_camera.cull_mask = 0
	_visibility_camera.set_cull_mask_value(VISIBILITY_LAYER, true)
	_visibility_camera.current = true
	_visibility_viewport.add_child(_visibility_camera)
	_visibility_canvas = CanvasLayer.new()
	_visibility_canvas.name = "WardenVisibilityCanvas"
	_visibility_canvas.layer = 8
	add_child(_visibility_canvas)
	_visibility_texture = TextureRect.new()
	_visibility_texture.name = "WardenVisibilityTexture"
	_visibility_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visibility_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_visibility_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_visibility_texture.texture = _visibility_viewport.get_texture()
	_visibility_texture.visible = false
	_visibility_canvas.add_child(_visibility_texture)
	_resize_visibility_compositor()
	get_viewport().size_changed.connect(_resize_visibility_compositor)

func _resize_visibility_compositor() -> void:
	if not is_instance_valid(_visibility_viewport) or not is_instance_valid(_visibility_texture):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_visibility_viewport.size = _secondary_viewport_size()
	_visibility_texture.position = Vector2.ZERO
	_visibility_texture.size = viewport_size

func _secondary_viewport_size() -> Vector2i:
	var viewport_size := get_viewport().get_visible_rect().size
	var scale := clampf(dense_compositor_resolution_scale, 0.25, 1.0)
	return Vector2i(maxi(1, int(viewport_size.x * scale)), maxi(1, int(viewport_size.y * scale)))

func _sync_visibility_camera() -> void:
	if not is_instance_valid(_visibility_camera):
		return
	_visibility_camera.global_transform = global_transform
	_visibility_camera.projection = projection
	_visibility_camera.fov = fov
	_visibility_camera.size = size
	_visibility_camera.near = near
	_visibility_camera.far = far
	_visibility_camera.frustum_offset = frustum_offset
	if occlusion_guard_active:
		# UPDATE_ONCE renders a fresh occlusion sample and then idles. This avoids
		# paying a full secondary visibility pass on every render frame while the
		# primary camera and gameplay continue at native cadence.
		if _compositor_refresh_remaining <= 0.0:
			_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_compositor_refresh_remaining = maxf(0.04, dense_compositor_refresh_seconds)
			_compositor_requested_updates += 1
			_compositor_frame_count += 1
		else:
			_compositor_skipped_updates += 1

func _update_visibility_isolation(delta: float) -> void:
	_visibility_samples_blocked = 0
	_last_occluder = ""
	_direct_detection_active = false
	_detection_source = "clear"
	var direct_occluder := _find_registered_sight_occluder()
	if not direct_occluder.is_empty():
		_direct_detection_active = true
		_detection_source = "registered_tall_occluder_sight_volume"
		_last_occluder = direct_occluder
		_visibility_samples_blocked = 1
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
		if _direct_detection_active:
			break
		var target_point: Vector3 = target.global_position + Vector3.UP * float(height)
		var query := PhysicsRayQueryParameters3D.new()
		query.from = global_position
		# The ray remains a fallback for unregistered incidental geometry. Tall
		# authored occluders are owned by the explicit conservative volume above,
		# so activation no longer depends on overscanning this short ray.
		query.to = target_point
		# Perimeter bodies constrain the player but sit between an exterior camera
		# sample and the actor when the camera follows near an edge. Only authored
		# landmark occluders participate in the fallback sight test.
		query.collision_mask = 2
		query.exclude = exclude
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			_detection_source = "fallback_physics_ray"
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

func _find_registered_sight_occluder() -> String:
	if not is_instance_valid(target):
		return ""
	var target_points := [
		target.global_position + Vector3.UP * 0.35,
		target.global_position + Vector3.UP * 1.0,
		target.global_position + Vector3.UP * 1.75,
	]
	for binding in _tall_occluder_bindings:
		if not bool(binding.get("bound", false)):
			continue
		for shape in binding.get("shapes", []):
			if not is_instance_valid(shape) or shape.disabled:
				continue
			for target_point in target_points:
				if _sight_segment_intersects_shape_volume(global_position, target_point, shape):
					return String(binding.get("resolved_path", binding.get("source_path", "")))
	return ""

func _sight_segment_intersects_shape_volume(from_world: Vector3, to_world: Vector3, collision_shape: CollisionShape3D) -> bool:
	var shape_transform := collision_shape.global_transform
	var local_from := shape_transform.affine_inverse() * from_world
	var local_to := shape_transform.affine_inverse() * to_world
	var extents := Vector3.ONE * direct_sight_volume_radius
	if collision_shape.shape is BoxShape3D:
		extents += (collision_shape.shape as BoxShape3D).size * 0.5
	elif collision_shape.shape is CylinderShape3D:
		var cylinder := collision_shape.shape as CylinderShape3D
		extents += Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
	elif collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		extents += Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)
	else:
		return false
	return _segment_intersects_centered_aabb(local_from, local_to, extents)

func _segment_intersects_centered_aabb(from: Vector3, to: Vector3, extents: Vector3) -> bool:
	var direction := to - from
	var entry := 0.0
	var exit := 1.0
	for axis in 3:
		var origin := from[axis]
		var delta := direction[axis]
		var minimum := -extents[axis]
		var maximum := extents[axis]
		if absf(delta) <= 0.00001:
			if origin < minimum or origin > maximum:
				return false
			continue
		var inverse := 1.0 / delta
		var near_time := (minimum - origin) * inverse
		var far_time := (maximum - origin) * inverse
		if near_time > far_time:
			var swap := near_time
			near_time = far_time
			far_time = swap
		entry = maxf(entry, near_time)
		exit = minf(exit, far_time)
		if entry > exit:
			return false
	return true

func _apply_visibility_overlay(active: bool) -> void:
	if not is_instance_valid(_visibility_viewport) or not is_instance_valid(_visibility_texture):
		return
	for visual in _presentation_visuals:
		if not is_instance_valid(visual):
			continue
		var instance_id := visual.get_instance_id()
		visual.visible = bool(_original_visual_visibility.get(instance_id, true))
		visual.layers = 1 << (VISIBILITY_LAYER - 1) if active else int(_original_visual_layers.get(instance_id, 1))
		if visual is GeometryInstance3D:
			(visual as GeometryInstance3D).material_overlay = _original_material_overlays.get(instance_id) as Material
	set_cull_mask_value(VISIBILITY_LAYER, not active and _primary_camera_visibility_layer)
	_visibility_texture.visible = active
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED
	_compositor_refresh_remaining = 0.0
	if active:
		_sync_visibility_camera()

func _snap_to_target() -> void:
	framing_target = target.global_position
	_safe_frame_offset = Vector3.ZERO
	_coverage_offset = Vector3.ZERO
	global_position = framing_target + Vector3(follow_lateral, follow_height, follow_distance)
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)

func _original_presentation_restored() -> bool:
	if occlusion_guard_active:
		return false
	for visual in _presentation_visuals:
		if not is_instance_valid(visual):
			return false
		if visual.layers != int(_original_visual_layers.get(visual.get_instance_id(), visual.layers)):
			return false
		if visual.visible != bool(_original_visual_visibility.get(visual.get_instance_id(), visual.visible)):
			return false
		if visual is GeometryInstance3D and (visual as GeometryInstance3D).material_overlay != (_original_material_overlays.get(visual.get_instance_id()) as Material):
			return false
	return true

func _coverage_occluders_restored() -> bool:
	# Camera containment also contributes to the shared response strength. It does
	# not fade any landmark when there is no registered occluder, so restoration
	# truth is the exact member state plus an empty occluder set.
	if not _coverage_obstructing_paths.is_empty():
		return false
	for visual in _coverage_occluder_visual_bindings:
		if not is_instance_valid(visual):
			return false
		var instance_id := visual.get_instance_id()
		if not is_equal_approx(visual.transparency, float(_coverage_occluder_original_transparency.get(instance_id, visual.transparency))):
			return false
		if visual.visible != bool(_coverage_occluder_original_visibility.get(instance_id, visual.visible)):
			return false
	return true

func _mcp_state() -> Dictionary:
	return {
		"binding_member_count": _binding_members.size(),
		"compositor_updates": _visibility_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED if is_instance_valid(_visibility_viewport) else false,
		"compositor_allowed":_compositor_allowed,
		"effect_visual_count": _effect_visuals.size(),
		"framing_target": framing_target,
		"safe_frame_ok":safe_frame_ok,
		"safe_frame_correction_active":safe_frame_correction_active,
		"safe_frame_offset":_safe_frame_offset,
		"safe_frame_screen_shift":_safe_frame_screen_shift,
		"projected_margins":projected_margins.duplicate(true),
		"safe_frame_fraction":safe_frame_fraction,
		"multi_subject_coverage":_coverage_receipt.duplicate(true),
		"coverage_frame_fraction":coverage_frame_fraction,
		"coverage_active_count":_coverage_active_count,
		"dense_fov_boost":dense_fov_boost,
		"coverage_offset":_coverage_offset,
		"coverage_screen_shift":_coverage_screen_shift,
		"arena_fill_limit":arena_fill_limit,
		"arena_spatial_contract":arena_contract.get_snapshot() if is_instance_valid(arena_contract) else {},
		"camera_response_source":_coverage_response_source,
		"obstruction_response_strength":_obstruction_response_strength,
		"obstruction_bypass_sign":_obstruction_bypass_sign,
		"coverage_occluder_visual_count":_coverage_occluder_visual_bindings.size(),
		"coverage_occluder_transparency":coverage_occluder_transparency * _obstruction_response_strength,
		"coverage_occluders_continuously_faded":_coverage_occluder_visual_bindings.size() > 0 and _obstruction_response_strength > 0.001,
		"coverage_hard_hide_disabled":true,
		"coverage_bound_visual_paths":_coverage_occluder_visual_bindings.map(func(visual: GeometryInstance3D) -> String: return String(visual.get_path())),
		"coverage_active_occluders":_coverage_obstructing_paths.duplicate(),
		"coverage_restoration_result":_coverage_occluders_restored(),
		"effective_follow_height":follow_height + obstruction_height_boost * _obstruction_response_strength,
		"effective_follow_distance":follow_distance - obstruction_distance_reduction * _obstruction_response_strength,
		"isolated_visual_count": _presentation_visuals.size(),
		"movement_velocity": movement_velocity,
		"follow_height": follow_height,
		"follow_distance": follow_distance,
		"follow_lateral": follow_lateral,
		"occlusion_guard_active": occlusion_guard_active,
		"direct_occluder_detection_active":_direct_detection_active,
		"occluder_detection_source":_detection_source,
		"active_occluder_path":_last_occluder,
		"registered_tall_occluder_count":_tall_occluder_bindings.filter(func(binding: Dictionary) -> bool: return bool(binding.get("bound", false))).size(),
		"presentation_binding_complete": _binding_members.size() == 5 and _source_visuals.size() >= 2 and _effect_visuals.size() == 3,
		"presentation_roles": ["body", "lantern", "dash_aura", "active_ring", "warden_halo"],
		"original_presentation_restored": _original_presentation_restored(),
		"primary_camera_visibility_layer": get_cull_mask_value(VISIBILITY_LAYER),
		"source_visual_count": _source_visuals.size(),
		"visibility_strategy": "deterministic_multi_subject_arena_containment_with_secondary_private_layer_compositor",
		"dense_render_budget": {
			"secondary_resolution_scale": dense_compositor_resolution_scale,
			"secondary_refresh_seconds": dense_compositor_refresh_seconds,
			"requested_updates": _compositor_requested_updates,
			"skipped_updates": _compositor_skipped_updates,
			"policy": "half_resolution_update_once_cadence_with_primary_camera_native"
		},
		"tall_occluder_registry":{
			"requested_count":tall_occluders.size(),
			"bound_count":_tall_occluder_bindings.filter(func(binding: Dictionary) -> bool: return bool(binding.get("bound", false))).size(),
			"bindings":_tall_occluder_bindings.map(func(binding: Dictionary) -> Dictionary: return {
				"source_path":binding.get("source_path", ""), "resolved_path":binding.get("resolved_path", ""),
				"bound":binding.get("bound", false), "shape_count":binding.get("shape_count", 0),
			}),
			"sight_volume_radius":direct_sight_volume_radius,
			"direct_detection_active":_direct_detection_active,
			"detection_source":_detection_source,
		},
		"visibility_isolation": {
			"active": occlusion_guard_active, "blocked_samples": _visibility_samples_blocked,
			"sample_count": 3, "blocked_seconds": _blocked_seconds,
			"clear_seconds": _clear_seconds, "last_occluder": _last_occluder,
				"strategy": "complete_private_layer_compositor",
				"isolated_visual_count": _presentation_visuals.size(),
				"source_visual_count": _source_visuals.size(),
				"isolation_visual_count": _source_visuals.size() + _effect_visuals.size(),
				"effect_visual_count": _effect_visuals.size(),
				"binding_members": _binding_members.duplicate(true),
				"binding_complete": _binding_members.size() == 5 and _source_visuals.size() >= 2 and _effect_visuals.size() == 3,
			"compositor_visible": _visibility_texture.visible if is_instance_valid(_visibility_texture) else false,
			"compositor_updates": _visibility_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED if is_instance_valid(_visibility_viewport) else false,
			"compositor_frame_count": _compositor_frame_count,
			"compositor_requested_updates": _compositor_requested_updates,
			"compositor_skipped_updates": _compositor_skipped_updates,
			"compositor_resolution_scale": dense_compositor_resolution_scale,
			"compositor_refresh_seconds": dense_compositor_refresh_seconds,
			"primary_camera_visibility_layer": get_cull_mask_value(VISIBILITY_LAYER),
			"probe_overscan": visibility_probe_overscan,
		},
		"lead_distance": lead_distance,
		"fov": fov,
	}
