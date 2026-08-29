class_name CemeterySpatialContract
extends Node3D

@export var camera_world_margin := Vector2(6.0, 5.6)
@export var protected_camera_half_extents := Vector2(9.2, 6.8)
@export var minimum_player_safe_radius := 8.8
@export var spawn_clearance := 0.6
@export var native_map_scale := 1.95

@onready var ground_collision: StaticBody3D = $OuterDatum/GroundCollision
@onready var north_boundary: StaticBody3D = $OuterDatum/NorthBoundary
@onready var south_boundary: StaticBody3D = $OuterDatum/SouthBoundary
@onready var east_boundary: StaticBody3D = $OuterDatum/EastBoundary
@onready var west_boundary: StaticBody3D = $OuterDatum/WestBoundary
@onready var player_spawn: Marker3D = $OuterDatum/PlayerSpawn
@onready var package_root: Node3D = $PackageTransform/AuthoredCemeteryPackage

const AUTHORED_LOCAL_MIN := Vector2(-12.143, -11.415)
const AUTHORED_LOCAL_MAX := Vector2(12.149, 11.418)

func _ready() -> void:
	# The complete cemetery is authored with a native local datum.  Rebase the
	# instance once at runtime so nested scene overrides cannot regress the
	# release framing back to the old camera-sized pad.
	var authored_scale := maxf(1.0, native_map_scale)
	if not is_equal_approx(scale.x, authored_scale):
		scale = Vector3.ONE * authored_scale
	_calibrate_authored_visibility()

func _calibrate_authored_visibility() -> void:
	# The bound GLB carries zero-sized imported custom AABBs on several meshes.
	# Keep the intact package and its materials, but provide a runtime cull
	# envelope so the shipped camera cannot drop native cemetery surfaces.
	if not is_instance_valid(package_root):
		return
	for node in package_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not is_instance_valid(mesh):
			continue
		mesh.extra_cull_margin = 32.0
		mesh.custom_aabb = AABB(Vector3(-64.0, -32.0, -64.0), Vector3(128.0, 64.0, 128.0))

func get_player_spawn() -> Vector3:
	var result := player_spawn.global_position
	result.y = 0.05
	return result

func get_spawn_lanes() -> Array[Vector3]:
	var lanes: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(&"arena_spawn_lane"):
		if node is Marker3D and is_ancestor_of(node):
			var lane := (node as Marker3D).global_position
			lane.y = 0.05
			lanes.append(lane)
	lanes.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2(a.z, a.x) < atan2(b.z, b.x)
	)
	return lanes

func get_route_checkpoints() -> Array[Dictionary]:
	var checkpoints: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group(&"arena_route_checkpoint"):
		if node is Marker3D and is_ancestor_of(node):
			checkpoints.append({"id":String(node.name), "position":(node as Marker3D).global_position})
	checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	return checkpoints

func get_playable_rect() -> Rect2:
	var west_shape := _first_shape(west_boundary)
	var east_shape := _first_shape(east_boundary)
	var north_shape := _first_shape(north_boundary)
	var south_shape := _first_shape(south_boundary)
	var west := west_boundary.global_position.x + _shape_world_half_extents(west_shape).x
	var east := east_boundary.global_position.x - _shape_world_half_extents(east_shape).x
	var north := north_boundary.global_position.z + _shape_world_half_extents(north_shape).y
	var south := south_boundary.global_position.z - _shape_world_half_extents(south_shape).y
	return Rect2(Vector2(west, north), Vector2(east - west, south - north))

func get_authored_visual_rect() -> Rect2:
	# Include the authored package's nested transform in the visual datum.  The
	# previous contract measured only the outer node, so a scaled package (or a
	# package rebase) could report a camera fill rect that disagreed with the
	# actual cemetery geometry and leave a visible outer void.
	var world_scale := global_transform.basis.get_scale().abs()
	var root_scale := Vector2(world_scale.x, world_scale.z)
	var package_offset := Vector2.ZERO
	var package_scale := Vector2.ONE
	if is_instance_valid(package_root):
		var package_transform := package_root.get_parent() as Node3D
		if is_instance_valid(package_transform):
			package_offset = Vector2(package_transform.position.x, package_transform.position.z)
			var nested_scale := package_transform.global_transform.basis.get_scale().abs()
			package_scale = Vector2(nested_scale.x, nested_scale.z) / root_scale
	# The bound Sketchfab package stores a large native export datum in its
	# child transforms.  PackageTransform intentionally rebases that datum onto
	# the gameplay origin; do not let the export offset poison camera margins.
	if package_offset.length() > 100.0:
		package_offset = Vector2.ZERO
	var minimum := (package_offset + Vector2(AUTHORED_LOCAL_MIN.x * package_scale.x, AUTHORED_LOCAL_MIN.y * package_scale.y)) * root_scale
	var maximum := (package_offset + Vector2(AUTHORED_LOCAL_MAX.x * package_scale.x, AUTHORED_LOCAL_MAX.y * package_scale.y)) * root_scale
	return Rect2(minimum, maximum - minimum)

func get_camera_fill_rect() -> Rect2:
	var visual := get_authored_visual_rect()
	var minimum := visual.position + camera_world_margin
	var maximum := visual.end - camera_world_margin
	if maximum.x <= minimum.x or maximum.y <= minimum.y:
		return get_playable_rect()
	return Rect2(minimum, maximum - minimum)

func clamp_camera_target(requested: Vector3) -> Vector3:
	var fill := get_camera_fill_rect()
	var result := requested
	result.x = clampf(result.x, fill.position.x, fill.end.x)
	result.z = clampf(result.z, fill.position.y, fill.end.y)
	return result

func validate_spawn_position(position: Vector3, player_position: Vector3) -> Dictionary:
	var playable := get_playable_rect()
	var point := Vector2(position.x, position.z)
	if not playable.has_point(point):
		return {"valid":false, "reason":"outside_playable_datum", "playable_rect":playable}
	var delta := position - player_position
	delta.y = 0.0
	if delta.length() < minimum_player_safe_radius:
		return {"valid":false, "reason":"inside_player_safe_radius", "safe_distance":delta.length()}
	if absf(delta.x) < protected_camera_half_extents.x and absf(delta.z) < protected_camera_half_extents.y:
		return {"valid":false, "reason":"inside_protected_camera_region"}
	if is_position_blocked(position):
		return {"valid":false, "reason":"inside_authored_collision"}
	if not has_recoverable_approach(position, player_position):
		return {"valid":false, "reason":"no_valid_approach"}
	return {"valid":true, "reason":"validated_lane", "safe_distance":delta.length(), "playable_rect":playable}

func has_recoverable_approach(position: Vector3, destination: Vector3) -> bool:
	var inward := destination - position
	inward.y = 0.0
	if inward.length_squared() < 0.001:
		return false
	inward = inward.normalized()
	var lateral := Vector3(-inward.z, 0.0, inward.x)
	var playable := get_playable_rect()
	for lateral_offset in [0.0, 2.5, -2.5]:
		var entry := position + inward * 3.2 + lateral * float(lateral_offset)
		if playable.has_point(Vector2(entry.x, entry.z)) and not is_position_blocked(entry):
			return true
	return false

func is_position_blocked(position: Vector3) -> bool:
	for body in $OuterDatum.find_children("*", "StaticBody3D", true, false):
		if body in [ground_collision, north_boundary, south_boundary, east_boundary, west_boundary]:
			continue
		for shape_node in (body as StaticBody3D).find_children("*", "CollisionShape3D", true, false):
			var collision_shape := shape_node as CollisionShape3D
			if not collision_shape.disabled and is_instance_valid(collision_shape.shape) and _shape_contains(collision_shape, position):
				return true
	return false

func _shape_contains(collision_shape: CollisionShape3D, world_position: Vector3) -> bool:
	var local := collision_shape.global_transform.affine_inverse() * world_position
	var basis_scale := Vector3(
		collision_shape.global_transform.basis.x.length(),
		collision_shape.global_transform.basis.y.length(),
		collision_shape.global_transform.basis.z.length()
	)
	var clearance := Vector3(
		spawn_clearance / maxf(0.001, basis_scale.x),
		0.0,
		spawn_clearance / maxf(0.001, basis_scale.z)
	)
	if collision_shape.shape is BoxShape3D:
		var half := (collision_shape.shape as BoxShape3D).size * 0.5 + clearance
		return absf(local.x) <= half.x and absf(local.z) <= half.z
	if collision_shape.shape is CylinderShape3D:
		var cylinder := collision_shape.shape as CylinderShape3D
		return Vector2(local.x, local.z).length() <= cylinder.radius + maxf(clearance.x, clearance.z)
	if collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		return Vector2(local.x, local.z).length() <= capsule.radius + maxf(clearance.x, clearance.z)
	return false

func _first_shape(body: StaticBody3D) -> CollisionShape3D:
	for node in body.find_children("*", "CollisionShape3D", true, false):
		return node as CollisionShape3D
	return null

func _shape_world_half_extents(shape_node: CollisionShape3D) -> Vector2:
	if not is_instance_valid(shape_node) or not shape_node.shape is BoxShape3D:
		return Vector2.ZERO
	var box := shape_node.shape as BoxShape3D
	var scale := shape_node.global_transform.basis.get_scale().abs()
	return Vector2(box.size.x * scale.x * 0.5, box.size.z * scale.z * 0.5)

func get_snapshot() -> Dictionary:
	var playable := get_playable_rect()
	var visual := get_authored_visual_rect()
	var fill := get_camera_fill_rect()
	return {
		"contract_id":"cemetery_spatial_integrity_v47",
		"authored_bounds_contract":{
			"minimum":visual.position,
			"maximum":visual.end,
			"external_world_required":true,
			"playable_inside_authored":playable.position.x > visual.position.x and playable.end.x < visual.end.x and playable.position.y > visual.position.y and playable.end.y < visual.end.y,
		},
		"world_scale":global_transform.basis.get_scale().abs(),
		"package_transform":{
			"position":package_root.get_parent().position if is_instance_valid(package_root) else Vector3.ZERO,
			"scale":package_root.get_parent().scale if is_instance_valid(package_root) else Vector3.ONE,
			"native_export_rebased":is_instance_valid(package_root) and package_root.get_parent().position.length() > 100.0,
		},
		"playable_rect":playable,
		"playable_area":playable.size.x * playable.size.y,
		"authored_visual_rect":visual,
		"camera_fill_rect":fill,
		"external_depth_margin":{
			"west":playable.position.x - visual.position.x,
			"east":visual.end.x - playable.end.x,
			"north":playable.position.y - visual.position.y,
			"south":visual.end.y - playable.end.y,
		},
		"spawn_lane_count":get_spawn_lanes().size(),
		"route_checkpoints":get_route_checkpoints(),
		"route_checkpoint_count":get_route_checkpoints().size(),
		"protected_camera_half_extents":protected_camera_half_extents,
		"minimum_player_safe_radius":minimum_player_safe_radius,
		"authored_package_instances":1 if is_instance_valid(package_root) else 0,
		"collision_source":"scaled_outer_datum_static_bodies",
		"background_mode":"single_intact_authored_cemetery_with_restrained_fog",
		"external_world":{"source":"intact_authored_package_native_terrain_and_perimeter", "procedural_scenery":false, "primitive_meshes":0, "opaque":true, "non_playable_depth_beyond_all_edges":true},
		"landmark_collision":{"keeper_post":is_instance_valid(get_node_or_null("OuterDatum/KeeperLanternPostAnchor/KeeperPostCollision")), "small_mausoleum":is_instance_valid(get_node_or_null("OuterDatum/MausoleumCollision")), "cracked_bell":is_instance_valid(get_node_or_null("OuterDatum/CrackedMoonBellAnchor/CrackedBellCollision"))},
		"perimeter_collision":{"north":is_instance_valid(north_boundary), "south":is_instance_valid(south_boundary), "east":is_instance_valid(east_boundary), "west":is_instance_valid(west_boundary)},
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
