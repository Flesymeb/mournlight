class_name ArenaCamera
extends Camera3D

@export var target: Node3D
@export var arena_contract: CemeterySpatialContract
@export var follow_height := 25.0
@export var follow_distance := 25.0
## Fixed three-quarter azimuth keeps the Warden out of the mausoleum's stair
## silhouette while retaining a high-angle escape-lane read.  The rig still
## follows the player; this is only the authored lateral offset of that rig.
@export var follow_lateral := 5.0
@export var follow_damping := 8.5
@export var lead_distance := 2.4
@export var lead_damping := 5.0
@export_category("Optional aim bias")
## Mouse motion gently rotates the high-angle rig; it never enters first-person
## or free-orbit mode. The bounded pitch range preserves arena context.
@export var mouse_look_sensitivity := 0.11
@export var mouse_pitch_min := 38.0
@export var mouse_pitch_max := 58.0
@export var mouse_yaw_degrees := 0.0
@export var mouse_pitch_degrees := 49.0
# Keep the Warden in the lower-safe lane without aiming the camera through the
# mausoleum volume.  The previous -5.5 north bias put several Warden AABB
# samples behind the landmark and under-reported shipped visibility.
# Aim slightly into the south escape lane so the mausoleum/bell stay in the
# upper third while the Warden and nearby threats occupy the readable lower
# safe lane. This is an authored target datum, not a landmark hide/fade.
@export var framing_bias: Vector3 = Vector3(0.0, 0.0, -6.0)
@export var arena_limit := Vector2(34.0, 32.0)
@export var normal_fov := 78.0
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
## Physics mask used only by camera visibility probes. The authored cemetery
## contract reserves layer 2 for registered tall landmarks; keeping that as the
## serialized default avoids an editor-side probe briefly treating the broad
## gameplay ground shell (layer 4) as a sightline blocker before _ready() binds
## the contract. ArenaCamera still narrows this to its registered tall-occluder
## list, so ordinary graves never become occluders.
@export_flags_3d_physics var camera_visibility_collision_mask := 2
@export_range(0.0, 1.0, 0.01) var coverage_occluder_transparency := 0.78
@export var coverage_settle_seconds := 0.28
@export var tall_occluders: Array[NodePath] = []
@export var direct_sight_volume_radius := 0.9
## Only bodies explicitly marked as camera sight-lane blockers may participate
## in the selective fade.  Gameplay collision bodies (including the broad
## mausoleum footprint) stay solid for traversal but can never become a
## whole-landmark occluder merely because an inherited scene override restores
## a default collision layer.
@export var require_camera_visibility_blocker_meta := true

## Multi-subject projection is the most expensive camera-side query during a
## dense wave (each subject projects an 8-corner actor volume twice per frame).
## Keep the shipped camera responsive, but amortize that diagnostic/containment
## work on a deterministic 20 Hz lane; the cached result is still consumed by
## the every-frame damping and framing code below.
const DENSE_COVERAGE_REFRESH_SECONDS := 0.05

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
var _coverage_measure_remaining := 0.0
var _coverage_before_cache: Dictionary = {}
var _coverage_after_cache: Dictionary = {}
var _coverage_projection_updates := 0
var _coverage_projection_skips := 0
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
var _tall_occluder_bindings: Array[Dictionary] = []
var _camera_response_allowed := false
var _mouse_look_receipt: Dictionary = {}

func _ready() -> void:
	# Rebase the shipped camera from one authoritative sight lane. Older
	# instanced scene resources can retain serialized east-side values even after
	# the product scene is edited; applying the release datum here keeps the live
	# camera, player spawn, and authored landmark in the same transform contract.
	# Match the authored composition datum in CemeterySpatialContract.  This
	# keeps the shipped player silhouette large enough to read while the native
	# package, external depth, and escape lanes remain in frame.
	# The native street package is materially larger than the old combat pad.
	# A wider authored orbit keeps the mausoleum readable as a landmark while
	# retaining keeper/bell silhouettes and a visible escape lane in one frame.
	# The authored package is now on a materially larger native datum. Keep the
	# camera high-angle, but bring the lens back into the readable gameplay band
	# so the Warden, telegraphs, and nearby pickups occupy the same visual scale
	# as the PRD target instead of shrinking to thumbnail silhouettes.
	# Keep the native cemetery legible at the shipped 16:9 lens.  The authored
	# map is now materially larger than the old combat pad, so the previous
	# 28 m rig rendered the Warden as a thumbnail and weakened threat reads.
	# A 22 m high-angle orbit still exposes the mausoleum, bell and an escape
	# lane while giving the player silhouette enough pixels for ordinary play.
	# Keep the high-angle context, but use a closer authored orbit so the Warden,
	# nearby drops, and attack telegraphs occupy a readable share of the shipped
	# frame.  Landmark coverage remains protected by the damped framing target
	# and the camera's bounded FOV correction below.
	follow_height = 25.0
	follow_distance = 25.0
	follow_lateral = -4.0
	# Aim a little farther up the authored north route so the mausoleum and bell
	# remain fully framed from spawn; the closer 22 m rig keeps the Warden in the
	# lower safe lane despite this landmark-forward bias.
	# Keep the Warden inside the lower safe lane at the instant the camera is
	# sampled (before the first follow tick) while retaining the northward
	# landmark read.  A southward bias avoids an initial offscreen fallback in
	# camera_coverage when the player is still at the authored spawn marker.
	# Keep the spawn composition aimed into the native north route.  The
	# previous southward bias left the cracked bell and mausoleum roofs above
	# the shipped frustum (camera_coverage reported 0.8/0.6 visibility) even
	# though their collision/anchor bindings were valid.  A modest north bias
	# preserves the Warden in the lower safe lane while keeping both landmarks
	# fully readable; it does not move authored geometry.
	framing_bias = Vector3(0.0, 0.0, -2.0)
	# A fixed three-quarter release azimuth keeps the mausoleum off the optical
	# centre while the enlarged keeper post and cracked bell silhouettes remain
	# in the same high-angle spawn composition. Mouse look still owns optional
	# bounded yaw after this authored baseline.
	mouse_yaw_degrees = 34.0
	obstruction_lateral_bypass = 0.0
	current = true
	normal_fov = 78.0
	fov = normal_fov
	# Keep the shipped camera's visibility query bound to the same dedicated
	# landmark layer as CemeterySpatialContract.  The scene resource historically
	# carried the old environment-layer value (4), which made camera-coverage
	# rays hit the gameplay ground shell and report false landmark occlusion.
	# Resolve the binding from the authoritative world contract at runtime so the
	# intact map, movement collision, and diagnostic visibility stay in one
	# transform/layer contract even when an older scene override is loaded.
	if is_instance_valid(arena_contract) and arena_contract.has_method("get_camera_visibility_collision_mask"):
		camera_visibility_collision_mask = int(arena_contract.get_camera_visibility_collision_mask())
	if target:
		_normalize_occluder_bindings()
		_bind_tall_occluders()
		_bind_coverage_occluder_visuals()
		_snap_to_target()

func _normalize_occluder_bindings() -> void:
	# Keep the product-owned sight volumes paired with their authored visuals.
	# The serialized profile predates the mausoleum isolation pass and had the
	# Crypt visual paired with a tree collider, so obstruction detection could
	# never fade the landmark that actually crossed the Warden sightline.  This
	# rebase is runtime-only and does not touch the intact imported package.
	var pairs := [
		# MausoleumCollision is intentionally omitted: it remains authoritative
		# gameplay geometry, never a camera sight-lane blocker.
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
	# The run controller remains the authoritative owner of camera updates. Modal
	# pages freeze this response, while ordinary and dense play use the one shipped
	# camera and the same reversible landmark-fade path.
	_camera_response_allowed = run_state in ["active", "boss"]
	if not _camera_response_allowed:
		occlusion_guard_active = false
		_coverage_measure_remaining = 0.0
		_coverage_before_cache.clear()
		_coverage_after_cache.clear()
		reset_occlusion_response()

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if not _camera_response_allowed:
		return
	_update_mouse_look()
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
	_coverage_measure_remaining = maxf(0.0, _coverage_measure_remaining - delta)
	var coverage_due := (
		_coverage_measure_remaining <= 0.0
		or _coverage_before_cache.is_empty()
		or _coverage_after_cache.is_empty()
		or (_coverage_before_cache.get("subject_paths", []) as Array) != _coverage_subject_paths
	)
	var before: Dictionary
	if coverage_due:
		_coverage_projection_updates += 1
		before = _measure_subject_coverage(subjects)
		before["subject_paths"] = _coverage_subject_paths.duplicate()
		_coverage_before_cache = before.duplicate(true)
	else:
		_coverage_projection_skips += 1
		before = _coverage_before_cache
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
	if is_instance_valid(arena_contract):
		framing_target = arena_contract.clamp_camera_target(framing_target)
	else:
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
	# The authored mausoleum is a tall native landmark. Keep a little more
	# breathing room in the shipped lens so its roof/door silhouette and the
	# Warden remain readable together; this is an additive camera datum and does
	# not move or replace any imported geometry.
	var landmark_anchor := get_node_or_null("../CemeteryGarden/OuterDatum/SmallMausoleumAnchor") as Node3D
	if is_instance_valid(landmark_anchor):
		# Preserve the landmark silhouette while keeping the Warden readable at
		# ordinary traversal distance. External depth comes from the intact map,
		# not from pushing the shipped lens into a thumbnail view.
		effective_height += 0.8
		effective_distance += 1.2
	var orbit_radius := maxf(0.1, Vector2(effective_height, effective_distance).length())
	var pitch_radians := deg_to_rad(mouse_pitch_degrees)
	var yaw_radians := deg_to_rad(mouse_yaw_degrees)
	var orbit_offset := Vector3(
		 sin(yaw_radians) * cos(pitch_radians) * orbit_radius,
		 sin(pitch_radians) * orbit_radius,
		 cos(yaw_radians) * cos(pitch_radians) * orbit_radius
	)
	var desired_position := framing_target + orbit_offset + Vector3(follow_lateral, 0.0, 0.0)
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
		# Keep enough native cemetery depth in every cardinal view. At the old
		# eight-metre inset the high-angle frustum crossed the authored edge and
		# exposed the empty world background as a hard dark band.
		var camera_margin := 16.0
		desired_position.x = clampf(desired_position.x, visual_rect.position.x + camera_margin, visual_rect.end.x - camera_margin)
		desired_position.z = clampf(desired_position.z, visual_rect.position.y + camera_margin, visual_rect.end.y - camera_margin)
	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_damping * delta))
	# Aim slightly above the street datum when the native mausoleum is present.
	# This keeps its tall doorway/roof in-frame while the Warden remains inside
	# the lower safe band; no authored child transform is altered.
	var look_height := 0.65
	if is_instance_valid(get_node_or_null("../CemeteryGarden/OuterDatum/SmallMausoleumAnchor")):
		look_height = 1.8
	look_at(framing_target + Vector3(0.0, look_height, 0.0), Vector3.UP)
	var warden_after := _measure_projected_safe_frame()
	var after: Dictionary
	if coverage_due:
		after = _measure_subject_coverage(subjects)
		after["subject_paths"] = _coverage_subject_paths.duplicate()
		_coverage_after_cache = after.duplicate(true)
		_coverage_measure_remaining = DENSE_COVERAGE_REFRESH_SECONDS
	else:
		after = _coverage_after_cache
	projected_margins = (warden_after.get("margins", {}) as Dictionary).duplicate(true)
	var coverage_inside := bool(after.get("inside_fraction", false))
	var warden_inside := bool(warden_after.get("inside_fraction", false))
	var arena_fill_ok := true
	if is_instance_valid(arena_contract):
		arena_fill_ok = arena_contract.get_camera_fill_rect().has_point(Vector2(framing_target.x, framing_target.z))
	else:
		arena_fill_ok = absf(framing_target.x) <= arena_fill_limit.x + 0.01 and absf(framing_target.z) <= arena_fill_limit.y + 0.01
	var obstruction_resolved := _coverage_obstructed_count == 0 or (_coverage_occluder_visual_bindings.size() > 0 and _obstruction_response_strength >= 0.65)
	safe_frame_ok = warden_inside and coverage_inside and arena_fill_ok and obstruction_resolved
	safe_frame_correction_active = _coverage_offset.length_squared() > 0.0025 or not safe_frame_ok or _arena_containment_active
	_update_coverage_receipt(after, warden_inside, coverage_inside, arena_fill_ok, delta)
	# Projected containment and the bounded selective landmark fade are the full
	# shipped visibility response. No secondary camera or world render is used.

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
	# Keep the density/FOV lane truthful on both sides of the cache refresh. The
	# first frame after a refresh used to leave this at its previous value (often
	# zero), so a newly admitted dense wave could retain the narrow lens until
	# the next membership tick.
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
	# The Bellkeeper begins outside the ordinary threat radius. Always include
	# the active boss as one bounded coverage subject so the shipped camera keeps
	# its silhouette in frame during entrance, near contact, and departure.
	var boss := get_node_or_null("../BossAnchor/Bellkeeper") as Node3D
	if is_instance_valid(boss) and not bool(boss.get("committed")) and boss not in subjects:
		subjects.append(boss)
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
	# Keep the authored landmark cluster in the same readable band as the Warden
	# during the critical route and perimeter traversal. The imported cemetery is
	# intentionally one intact instance; tracking the three native anchors keeps
	# their silhouettes from cropping when the player reaches the south/east edge
	# without moving any authored child mesh or introducing proxy geometry.
	var landmark_sum := Vector3.ZERO
	var landmark_count := 0
	for landmark_path in [
		"../CemeteryGarden/OuterDatum/KeeperLanternPostAnchor",
		"../CemeteryGarden/OuterDatum/SmallMausoleumAnchor",
		"../CemeteryGarden/OuterDatum/CrackedMoonBellAnchor",
	]:
		var landmark := get_node_or_null(landmark_path) as Node3D
		if not is_instance_valid(landmark):
			continue
		landmark_sum += landmark.global_position
		landmark_count += 1
	if landmark_count > 0:
		var landmark_target := landmark_sum / float(landmark_count)
		landmark_target.y = composed.y
		# Keep player movement primary while reserving a stable 18% look-ahead for
		# the authored landmark cluster. This retains the north route in-frame on
		# cardinal views without pulling the camera off the street.
		# Keep the player as the primary framing owner. A smaller landmark blend
		# prevents the mausoleum from being pulled into the optical centre at the
		# south spawn while preserving keeper/bell silhouettes in the upper safe
		# lane and leaving a readable escape route around the central stair.
		composed = composed.lerp(landmark_target, 0.18)
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
	# Landmark readability is part of the shipped composition, not only an
	# enemy-framing concern.  The mausoleum can sit between the camera and the
	# keeper post/bell even while the Warden remains unobstructed, so inspect
	# those two authored anchors explicitly and feed the same selective-fade
	# response.  The mausoleum anchor is intentionally omitted to avoid a
	# self-hit against its own registered collision volume.
	for landmark_path in [
		"../CemeteryGarden/OuterDatum/KeeperLanternPostAnchor",
		"../CemeteryGarden/OuterDatum/CrackedMoonBellAnchor",
	]:
		var landmark := get_node_or_null(landmark_path) as Node3D
		if not is_instance_valid(landmark):
			continue
		var landmark_obstruction := _find_registered_subject_occluder(landmark)
		if landmark_obstruction.is_empty() or _coverage_obstructing_paths.has(landmark_obstruction):
			continue
		_coverage_obstructed_count += 1
		_coverage_obstructing_paths.append(landmark_obstruction)
		if _coverage_obstructing_path.is_empty():
			_coverage_obstructing_path = landmark_obstruction
			var landmark_obstruction_node := get_node_or_null(landmark_obstruction) as Node3D
			if is_instance_valid(landmark_obstruction_node):
				_obstruction_bypass_sign = -1.0 if target.global_position.x <= landmark_obstruction_node.global_position.x else 1.0
	if _coverage_obstructed_count > 0:
		# If a registered visual really crosses a sight lane, bias toward the
		# playable datum center rather than the world origin.  The previous zero
		# vector silently pulled the camera toward (0, 0), which could expose an
		# unrelated edge and made obstruction handling fight arena containment.
		var datum_center := Vector3.ZERO
		if is_instance_valid(arena_contract):
			var playable := arena_contract.get_playable_rect()
			datum_center = Vector3(playable.get_center().x, composed.y, playable.get_center().y)
		else:
			datum_center = Vector3(0.0, composed.y, 0.0)
		var inward := datum_center
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
		# Landmark collision remains authoritative for movement, but visibility
		# probing is intentionally isolated to its own physics mask.  Bodies on
		# the gameplay layer must never classify as camera occluders.
		var body := binding.get("body") as CollisionObject3D
		if require_camera_visibility_blocker_meta and (not is_instance_valid(body) or not bool(body.get_meta("camera_visibility_blocker", false))):
			continue
		if is_instance_valid(body) and (int(body.collision_layer) & camera_visibility_collision_mask) == 0:
			continue
		var visual_bounds: AABB = binding.get("visual_bounds", AABB())
		if visual_bounds.size.length_squared() > 0.001:
			for subject_point in subject_points:
				if _segment_intersects_world_aabb(global_position, subject_point, visual_bounds.grow(direct_sight_volume_radius)):
					return String(binding.get("resolved_path", binding.get("source_path", "")))
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

func _bind_tall_occluders() -> void:
	_tall_occluder_bindings.clear()
	for index in tall_occluders.size():
		var source_path := tall_occluders[index]
		var body := get_node_or_null(source_path) as CollisionObject3D
		var shapes: Array[CollisionShape3D] = []
		if is_instance_valid(body):
			for child in body.find_children("*", "CollisionShape3D", true, false):
				if child is CollisionShape3D and is_instance_valid((child as CollisionShape3D).shape):
					shapes.append(child as CollisionShape3D)
		var visual_path := coverage_occluder_visuals[index] if index < coverage_occluder_visuals.size() else NodePath()
		var visual_bounds := AABB()
		if is_instance_valid(arena_contract) and not visual_path.is_empty():
			var visual_node := get_node_or_null(visual_path)
			if is_instance_valid(visual_node):
				visual_bounds = arena_contract.get_visual_subtree_aabb(String(arena_contract.get_path_to(visual_node)))
		_tall_occluder_bindings.append({
			"source_path":String(source_path),
			"resolved_path":String(body.get_path()) if is_instance_valid(body) else "",
			"visual_path":String(visual_path),
			"visual_bounds":visual_bounds,
			"body":body,
			"shapes":shapes,
			"bound":is_instance_valid(body) and not shapes.is_empty() and visual_bounds.size.length_squared() > 0.001,
			"visibility_bound":is_instance_valid(body) and (int(body.collision_layer) & camera_visibility_collision_mask) != 0,
			"shape_count":shapes.size(),
		})

func _segment_intersects_world_aabb(from_world: Vector3, to_world: Vector3, bounds: AABB) -> bool:
	return bounds.intersects_segment(from_world, to_world) != null

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
	occlusion_guard_active = false
	for visual in _coverage_occluder_visual_bindings:
		if not is_instance_valid(visual):
			continue
		var instance_id := visual.get_instance_id()
		visual.transparency = float(_coverage_occluder_original_transparency.get(instance_id, visual.transparency))
		visual.visible = bool(_coverage_occluder_original_visibility.get(instance_id, visual.visible))

func reset_view() -> void:
	"""Return the optional aim bias to the authored high-angle release datum."""
	# The release datum is a three-quarter azimuth so the central mausoleum does
	# not swallow the keeper post/bell sight lane at spawn. Subsequent mouse-look
	# remains bounded around this authored baseline.
	mouse_yaw_degrees = 34.0
	mouse_pitch_degrees = 49.0
	_mouse_look_receipt.clear()
	var router := get_node_or_null("../../InputContextRouter")
	if is_instance_valid(router) and router.has_method("consume_mouse_look"):
		router.consume_mouse_look()

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

func _snap_to_target() -> void:
	framing_target = target.global_position + framing_bias
	if is_instance_valid(arena_contract):
		framing_target = arena_contract.clamp_camera_target(framing_target)
	_safe_frame_offset = Vector3.ZERO
	_coverage_offset = Vector3.ZERO
	global_position = framing_target + Vector3(follow_lateral, follow_height, follow_distance)
	look_at(framing_target + Vector3(0.0, 1.8, 0.0), Vector3.UP)

func _update_mouse_look() -> void:
	# ArenaCamera lives under World; the router is a sibling of World on the
	# run-shell root, so keep this binding explicit and scene-relative.
	var router := get_node_or_null("../../InputContextRouter")
	if not is_instance_valid(router) or not router.has_method("consume_mouse_look"):
		return
	var relative := router.consume_mouse_look() as Vector2
	if relative.length_squared() <= 0.0001:
		return
	# Horizontal motion changes yaw; vertical motion changes pitch. Both are
	# deliberately bounded so the arena remains readable during dense waves.
	mouse_yaw_degrees = fposmod(mouse_yaw_degrees - relative.x * mouse_look_sensitivity + 180.0, 360.0) - 180.0
	mouse_pitch_degrees = clampf(mouse_pitch_degrees - relative.y * mouse_look_sensitivity, mouse_pitch_min, mouse_pitch_max)
	_mouse_look_receipt = {
		"generation":int(router.get("mouse_look_generation")),
		"relative":relative,
		"yaw_degrees":mouse_yaw_degrees,
		"pitch_degrees":mouse_pitch_degrees,
		"camera_forward":(-global_transform.basis.z).normalized(),
	}

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

func _active_isolated_visual_count() -> int:
	var active_count := 0
	for visual in _coverage_occluder_visual_bindings:
		if not is_instance_valid(visual):
			continue
		for occluder_path in _coverage_obstructing_paths:
			if visual in (_coverage_visuals_by_occluder.get(occluder_path, []) as Array):
				active_count += 1
				break
	return active_count

func _mcp_state() -> Dictionary:
	var isolated_visual_count := _active_isolated_visual_count()
	return {
		"binding_member_count":_coverage_occluder_visual_bindings.size(),
		"compositor_updates":false,
		"compositor_allowed":false,
		"effect_visual_count":isolated_visual_count,
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
		"visibility_collision_mask":camera_visibility_collision_mask,
		"gameplay_collision_layers_excluded":true,
		"coverage_projection_updates":_coverage_projection_updates,
		"coverage_projection_skips":_coverage_projection_skips,
		"coverage_projection_refresh_seconds":DENSE_COVERAGE_REFRESH_SECONDS,
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
		"isolated_visual_count":isolated_visual_count,
		"movement_velocity": movement_velocity,
		"mouse_look": {
			"sensitivity":mouse_look_sensitivity,
			"yaw_degrees":mouse_yaw_degrees,
			"pitch_degrees":mouse_pitch_degrees,
			"pitch_bounds":[mouse_pitch_min, mouse_pitch_max],
			"last_receipt":_mouse_look_receipt.duplicate(true),
			"camera_relative":true,
		},
		"follow_height": follow_height,
		"follow_distance": follow_distance,
		"follow_lateral": follow_lateral,
		"occlusion_guard_active":_coverage_obstructed_count > 0,
		"direct_occluder_detection_active":not _coverage_obstructing_paths.is_empty(),
		"occluder_detection_source":"registered_subject_sight_volume" if not _coverage_obstructing_paths.is_empty() else "clear",
		"active_occluder_path":_coverage_obstructing_path,
		"registered_tall_occluder_count":_tall_occluder_bindings.filter(func(binding: Dictionary) -> bool: return bool(binding.get("bound", false))).size(),
		"camera_visibility_occluder_count":_tall_occluder_bindings.filter(func(binding: Dictionary) -> bool: return bool(binding.get("bound", false)) and bool(binding.get("visibility_bound", false))).size(),
		"presentation_binding_complete":true,
		"presentation_roles":["primary_camera_world"],
		"original_presentation_restored":true,
		"primary_camera_cull_mask":cull_mask,
		"source_visual_count":_coverage_occluder_visual_bindings.size(),
		"visibility_strategy":"single_primary_camera_package_bound_visual_aabb_with_selective_reversible_landmark_fade",
		# Host/Tester can bind the spatial claim to the same shipped-camera owner
		# without inferring it from a screenshot.  The phases are deliberately
		# explicit so spawn, approach, near-contact, departure, and cardinal street
		# replays remain separate observations; whole-landmark hiding is forbidden.
		"landmark_visibility_contract": {
			"required_phases":["spawn","approach","near_contact","departure","cardinal_north","cardinal_east","cardinal_south","cardinal_west"],
			"camera_owner":"ArenaCamera",
			"collision_owner":"CemeterySpatialContract",
			"hard_hide_disabled":true,
			"external_depth_required":true,
			"status":"bound_runtime_camera",
		},
		"dense_render_budget": {
			"secondary_render_pass":false,
			"secondary_camera_count":0,
			"projection_refresh_seconds":DENSE_COVERAGE_REFRESH_SECONDS,
			"membership_refresh_seconds":0.1,
			"policy":"primary_camera_only_with_bounded_projection_and_cached_membership"
		},
		"tall_occluder_registry":{
			"requested_count":tall_occluders.size(),
			"bound_count":_tall_occluder_bindings.filter(func(binding: Dictionary) -> bool: return bool(binding.get("bound", false))).size(),
			"bindings":_tall_occluder_bindings.map(func(binding: Dictionary) -> Dictionary: return {
				"source_path":binding.get("source_path", ""), "resolved_path":binding.get("resolved_path", ""),
				"visual_path":binding.get("visual_path", ""), "visual_bounds":binding.get("visual_bounds", AABB()),
				"bound":binding.get("bound", false), "shape_count":binding.get("shape_count", 0),
			}),
			"sight_volume_radius":direct_sight_volume_radius,
			"direct_detection_active":not _coverage_obstructing_paths.is_empty(),
			"detection_source":"registered_subject_sight_volume" if not _coverage_obstructing_paths.is_empty() else "clear",
		},
		"visibility_isolation": {
			"active":isolated_visual_count > 0,
			"strategy":"primary_camera_segment_to_subject_selective_visual_fade",
			"secondary_render_pass":false,
			"secondary_camera_count":0,
			"isolated_visual_count":isolated_visual_count,
			"bound_visual_count":_coverage_occluder_visual_bindings.size(),
			"active_occluder_paths":_coverage_obstructing_paths.duplicate(),
			"continuous_response":true,
			"minimum_retained_opacity":1.0 - coverage_occluder_transparency,
			"collision_unchanged":true,
			"restored":_coverage_occluders_restored(),
			"compositor_visible":false,
			"compositor_updates":false,
		},
		"lead_distance": lead_distance,
		"fov": fov,
	}
