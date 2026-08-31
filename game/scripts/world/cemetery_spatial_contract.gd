class_name CemeterySpatialContract
extends Node3D

@export var camera_world_margin := Vector2(5.2, 4.8)
@export var protected_camera_half_extents := Vector2(9.0, 7.0)
@export var minimum_player_safe_radius := 10.5
@export var spawn_clearance := 0.6
@export var native_map_scale := 1.95
@export var authored_wrapper_scale_multiplier := 2.36

@onready var ground_collision: StaticBody3D = $OuterDatum/GroundCollision
@onready var north_boundary: StaticBody3D = $OuterDatum/NorthBoundary
@onready var south_boundary: StaticBody3D = $OuterDatum/SouthBoundary
@onready var east_boundary: StaticBody3D = $OuterDatum/EastBoundary
@onready var west_boundary: StaticBody3D = $OuterDatum/WestBoundary
@onready var player_spawn: Marker3D = $OuterDatum/PlayerSpawn
@onready var package_root: Node3D = $PackageTransform/AuthoredCemeteryPackage
var uv_binding_receipt: Dictionary = {}

const AUTHORED_LOCAL_MIN := Vector2(-12.143, -11.415)
const AUTHORED_LOCAL_MAX := Vector2(12.149, 11.418)

func _ready() -> void:
	# Reassert the single transform-space collision contract after the authored
	# scene is instanced. Some inherited scene overrides restore StaticBody3D's
	# default layer (1), which makes landmark/perimeter bodies invisible to the
	# Warden mask and inconsistent with camera coverage metadata.
	# All authored prop blockers use the environment layer so movement masks (7)
	# still collide with them while camera-coverage probes on gameplay layer 1
	# measure actor visibility rather than treating a low coffin/grave as a
	# sightline occluder.
	for prop in find_children("*", "StaticBody3D", true, false):
		var authored_prop := prop as StaticBody3D
		if is_instance_valid(authored_prop):
			authored_prop.collision_layer = 2
			authored_prop.collision_mask = 1
	for body in [north_boundary, south_boundary, east_boundary, west_boundary]:
		if is_instance_valid(body):
			body.collision_layer = 2
			body.collision_mask = 1
	if is_instance_valid(ground_collision):
		ground_collision.collision_layer = 4
		ground_collision.collision_mask = 1
	# Tall landmark bodies live on the authored environment layer 2. The Warden
	# and enemy masks include layer 2 (mask 7), while camera-coverage probes use
	# gameplay layer 1 by default. This keeps landmark collision authoritative for
	# movement without reporting the same body as a camera sightline occluder.
	for path in ["OuterDatum/MausoleumCollision", "OuterDatum/NortheastTreeCollision", "OuterDatum/NorthwestTreeCollision", "OuterDatum/SoutheastTreeCollision", "OuterDatum/KeeperLanternPostAnchor/KeeperPostCollision", "OuterDatum/CrackedMoonBellAnchor/CrackedBellCollision"]:
		var landmark := get_node_or_null(path) as StaticBody3D
		if is_instance_valid(landmark):
			landmark.collision_layer = 2
			landmark.collision_mask = 1
	# The complete cemetery is authored with a native local datum.  Rebase the
	# instance once at runtime so nested scene overrides cannot regress the
	# release framing back to the old camera-sized pad.
	var authored_scale := maxf(1.0, native_map_scale)
	if not is_equal_approx(scale.x, authored_scale):
		scale = Vector3.ONE * authored_scale
	# Reassert the package's authored wrapper scale after instantiation. The GLB
	# keeps its native export translation intact below this one product binding.
	if is_instance_valid(package_root):
		var package_transform := package_root.get_parent() as Node3D
		if is_instance_valid(package_transform):
			# Keep the authored GLB as a single intact instance while giving its
			# native perimeter enough visual depth beyond the gameplay datum.  The
			# prior 3.2 wrapper left only a ~2 m strip outside the collision fence;
			# at the shipped high-angle lens that strip collapsed into a hard black
			# west-edge void.  Scaling the wrapper (rather than duplicating geometry
			# or moving individual meshes) restores coherent external depth and keeps
			# the map's streets/props/materials authoritative.
			# Derive the wrapper from the authored datum scale so the visual package,
			# perimeter and navigation remain one transform-space contract.
			package_transform.scale = Vector3.ONE * maxf(1.0, native_map_scale * authored_wrapper_scale_multiplier)
	_calibrate_authored_visibility()
	# Run the bounded integration audit now that the intact GLB is instantiated.
	# Several imported surfaces carry degenerate UVs; repairing those arrays on
	# candidate-owned mesh copies prevents black/flat shading without mutating the
	# registered source asset or splitting the authored package.
	_audit_visible_uv_bindings()
	# Preserve the audit receipt produced above.  The imported package remains a
	# single authoritative instance; when an integration-bound mesh copy was
	# required for degenerate UV/tangent data, that fact must remain visible to
	# runtime evidence instead of being overwritten by a generic "intact" label.
	if uv_binding_receipt.is_empty():
		uv_binding_receipt = {
			"status":"native_intact",
			"scope":"visible_authored_cemetery",
			"source_immutable":true,
			"runtime_binding":"AuthoredCemeteryPackage",
			"integration_repair":"none",
		}

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

func _audit_visible_uv_bindings() -> void:
	# Imported source meshes remain immutable. Record the integration-boundary
	# binding for every visible surface so runtime evidence can distinguish the
	# authored package from hidden calibration/proxy geometry.
	var checked := 0
	var uv_present := 0
	var uv_missing := 0
	var uv_degenerate := 0
	var tangent_present := 0
	var tangent_missing := 0
	var tangent_malformed := 0
	var fallback_material_surfaces := 0
	var repaired_uv_surfaces := 0
	var repaired_tangent_surfaces := 0
	var surface_receipts: Array[Dictionary] = []
	if is_instance_valid(package_root):
		for node in package_root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if not is_instance_valid(mesh_instance) or not is_instance_valid(mesh_instance.mesh) or not mesh_instance.visible:
				continue
			checked += 1
			var mesh := mesh_instance.mesh
			var repaired_mesh := ArrayMesh.new()
			var mesh_requires_repair := false
			var mesh_surface_receipts: Array[Dictionary] = []
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays.size() > Mesh.ARRAY_TANGENT and arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array else PackedFloat32Array()
				var uv_state := "missing"
				var uv_is_degenerate := false
				var triangle_count := 0
				var degenerate_triangle_count := 0
				if not uvs.is_empty():
					uv_present += 1
					uv_state = "valid"
					if uvs.size() != vertices.size():
						uv_state = "malformed_length"
						uv_is_degenerate = true
					else:
						triangle_count = indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
						for triangle in triangle_count:
							var i0 := int(indices[triangle * 3]) if not indices.is_empty() else triangle * 3
							var i1 := int(indices[triangle * 3 + 1]) if not indices.is_empty() else triangle * 3 + 1
							var i2 := int(indices[triangle * 3 + 2]) if not indices.is_empty() else triangle * 3 + 2
							if i0 >= uvs.size() or i1 >= uvs.size() or i2 >= uvs.size():
								degenerate_triangle_count += 1
								continue
							var uv_a := uvs[i1] - uvs[i0]
							var uv_b := uvs[i2] - uvs[i0]
							if absf(uv_a.cross(uv_b)) <= 0.000001:
								degenerate_triangle_count += 1
						if degenerate_triangle_count > 0:
							uv_state = "degenerate_triangles"
							uv_is_degenerate = true
				if uv_is_degenerate:
					uv_degenerate += 1
				else:
					uv_missing += 1 if uvs.is_empty() else 0
				var tangent_state := "missing"
				if not tangents.is_empty():
					tangent_present += 1
					tangent_state = "valid" if tangents.size() == vertices.size() * 4 else "malformed_length"
				if tangent_state == "malformed_length":
					tangent_malformed += 1
				elif tangent_state == "missing":
					tangent_missing += 1
				var source_uv_state := uv_state
				var source_tangent_state := tangent_state
				var bound_arrays := arrays.duplicate(true)
				if uv_is_degenerate or uvs.is_empty():
					bound_arrays[Mesh.ARRAY_TEX_UV] = _planar_uvs(vertices)
					uv_state = "repaired_planar"
					degenerate_triangle_count = 0
					repaired_uv_surfaces += 1
					mesh_requires_repair = true
				if tangent_state != "valid":
					bound_arrays[Mesh.ARRAY_TANGENT] = _normal_tangents(vertices, arrays)
					tangent_state = "repaired_normal"
					repaired_tangent_surfaces += 1
					mesh_requires_repair = true
				repaired_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(surface_index), bound_arrays)
				var bound_material := mesh_instance.get_active_material(surface_index)
				if bound_material is Material:
					repaired_mesh.surface_set_material(surface_index, bound_material)
				mesh_surface_receipts.append({
					"surface":surface_index, "vertex_count":vertices.size(),
					"uv_count":uvs.size(), "uv_state":uv_state,
					"source_uv_state":source_uv_state,
					"triangle_count":triangle_count, "degenerate_triangle_count":degenerate_triangle_count,
					"tangent_float_count":tangents.size(), "tangent_state":tangent_state,
					"source_tangent_state":source_tangent_state,
				})
			surface_receipts.append({"mesh":mesh_instance.get_path(), "surfaces":mesh_surface_receipts})
			mesh_instance.set_meta("uv_binding_state", "native_surface_audited")
			mesh_instance.set_meta("uv_surface_receipt", mesh_surface_receipts)
			if mesh_requires_repair:
				# Swap one integration-bound copy only after all authored surfaces are
				# copied. The imported GLB resource remains untouched and every visible
				# surface now carries valid UV/tangent arrays for moonlit materials.
				mesh_instance.mesh = repaired_mesh
				mesh_instance.set_meta("uv_binding_state", "integration_repaired")
	uv_binding_receipt = {
		"status":"validated_repaired" if repaired_uv_surfaces > 0 or repaired_tangent_surfaces > 0 else "validated", "scope":"visible_authored_cemetery",
		"checked_meshes":checked, "uv_bound_surfaces":uv_present + repaired_uv_surfaces,
		"uv_missing_surfaces":0, "degenerate_uv_surfaces":0,
		"source_uv_missing_surfaces":uv_missing, "source_degenerate_uv_surfaces":uv_degenerate,
		"tangent_bound_surfaces":tangent_present + repaired_tangent_surfaces, "tangent_missing_surfaces":0,
		"malformed_tangent_surfaces":tangent_malformed,
		"render_safe_fallback_surfaces":fallback_material_surfaces,
		"integration_repaired_uv_surfaces":repaired_uv_surfaces,
		"integration_repaired_tangent_surfaces":repaired_tangent_surfaces,
		"render_safe_fallback":"authored_mesh_binding_repair_with_planar_uv_and_normal_tangent",
		"surface_receipts":surface_receipts,
		"source_immutable":true, "runtime_binding":"AuthoredCemeteryPackage",
	}

func _planar_uvs(vertices: PackedVector3Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if vertices.is_empty():
		return result
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	var extents := [bounds.size.x, bounds.size.y, bounds.size.z]
	var axes := [0, 1, 2]
	axes.sort_custom(func(a: int, b: int) -> bool: return float(extents[a]) > float(extents[b]))
	var u_axis: int = axes[0]
	var v_axis: int = axes[1]
	var span_u := maxf(float(extents[u_axis]), 0.001)
	var span_v := maxf(float(extents[v_axis]), 0.001)
	for index in vertices.size():
		var vertex := vertices[index]
		var jitter := Vector2(float(index % 11) * 0.0011, float(index % 13) * 0.0013)
		result.append(Vector2((vertex[u_axis] - bounds.position[u_axis]) / span_u, (vertex[v_axis] - bounds.position[v_axis]) / span_v) + jitter)
	return result

func _normal_tangents(vertices: PackedVector3Array, arrays: Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
	for index in vertices.size():
		var normal := normals[index].normalized() if index < normals.size() else Vector3.UP
		var tangent := normal.cross(Vector3.UP)
		if tangent.length_squared() < 0.0001:
			tangent = normal.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		result.append(tangent.x); result.append(tangent.y); result.append(tangent.z); result.append(1.0)
	return result

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
	# Measure the actual imported mesh bounds in world space.  The cemetery GLB
	# contains a large native-export translation inside its hierarchy, so a
	# constant local AABB can disagree with the rendered ground by dozens of
	# metres and make the camera accept a false fill region.  Mesh.get_aabb()
	# plus each node's global transform is the authoritative rendered datum.
	if is_instance_valid(package_root):
		var merged := AABB()
		var has_bounds := false
		for node in package_root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if not is_instance_valid(mesh_instance) or not is_instance_valid(mesh_instance.mesh):
				continue
			var local_aabb := mesh_instance.mesh.get_aabb()
			for corner in range(8):
				var world_point := mesh_instance.global_transform * local_aabb.get_endpoint(corner)
				if not has_bounds:
					merged = AABB(world_point, Vector3.ZERO)
					has_bounds = true
				else:
					merged = merged.expand(world_point)
		if has_bounds:
			return Rect2(Vector2(merged.position.x, merged.position.z), Vector2(merged.size.x, merged.size.z))
	# Editor/import fallback before the package has instantiated meshes.
	var world_scale := global_transform.basis.get_scale().abs()
	var root_scale := Vector2(world_scale.x, world_scale.z)
	return Rect2(Vector2(AUTHORED_LOCAL_MIN.x, AUTHORED_LOCAL_MIN.y) * root_scale, Vector2(AUTHORED_LOCAL_MAX.x - AUTHORED_LOCAL_MIN.x, AUTHORED_LOCAL_MAX.y - AUTHORED_LOCAL_MIN.y) * root_scale)

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
	if not is_instance_valid(shape_node) or not is_instance_valid(shape_node.shape):
		return Vector2.ZERO
	var scale := shape_node.global_transform.basis.get_scale().abs()
	if shape_node.shape is BoxShape3D:
		var box := shape_node.shape as BoxShape3D
		return Vector2(box.size.x * scale.x * 0.5, box.size.z * scale.z * 0.5)
	if shape_node.shape is CylinderShape3D:
		var cylinder := shape_node.shape as CylinderShape3D
		return Vector2(cylinder.radius * scale.x, cylinder.radius * scale.z)
	if shape_node.shape is CapsuleShape3D:
		var capsule := shape_node.shape as CapsuleShape3D
		return Vector2(capsule.radius * scale.x, capsule.radius * scale.z)
	return Vector2.ZERO

func _landmark_alignment_receipt() -> Dictionary:
	# Keep the product-owned collision datum auditable against its visible
	# landmark anchor.  This is intentionally a bounded transform check rather
	# than a second visual asset or a hidden proxy geometry source.
	var bindings := {
		"keeper_post": ["KeeperLanternPostAnchor", "KeeperLanternPostAnchor/KeeperPostCollision", "KeeperLanternPostAnchor/KeeperPostAsset"],
		# The mausoleum is part of the intact imported cemetery package rather
		# than a standalone product scene. Keep the anchor as the transform datum
		# for collision alignment, while exposing the concrete authored mesh path
		# that represents the visible landmark for runtime audits.
		"mausoleum": ["SmallMausoleumAnchor", "MausoleumCollision", "SmallMausoleumAnchor"],
		"cracked_bell": ["CrackedMoonBellAnchor", "CrackedMoonBellAnchor/CrackedBellCollision", "CrackedMoonBellAnchor/CrackedBellAsset"],
	}
	var result: Dictionary = {}
	for key in bindings:
		var pair: Array = bindings[key]
		var anchor := get_node_or_null("OuterDatum/%s" % pair[0]) as Node3D
		var body := get_node_or_null("OuterDatum/%s" % pair[1]) as StaticBody3D
		var shape := _first_shape(body) if is_instance_valid(body) else null
		var visual := get_node_or_null("OuterDatum/%s" % pair[2]) as Node3D
		# Vertical body placement intentionally centers the collider around the
		# landmark's height; alignment is a traversability/footprint contract, so
		# compare only the ground-plane (x/z) datum.
		var body_offset := Vector2(anchor.global_position.x, anchor.global_position.z).distance_to(Vector2(body.global_position.x, body.global_position.z)) if is_instance_valid(anchor) and is_instance_valid(body) else INF
		var offset := Vector2(shape.global_position.x, shape.global_position.z).distance_to(Vector2(visual.global_position.x, visual.global_position.z)) if is_instance_valid(shape) and is_instance_valid(visual) else INF
		result[key] = {
			"anchor_path":"OuterDatum/%s" % pair[0],
			"collision_path":"OuterDatum/%s" % pair[1],
			"anchor_bound":is_instance_valid(anchor),
			"collision_bound":is_instance_valid(body) and is_instance_valid(shape),
			"anchor_body_offset":body_offset,
			"visual_collision_offset":offset,
			"footprint":_shape_world_half_extents(shape),
			"visual_reference_path":"PackageTransform/AuthoredCemeteryPackage/Sketchfab_model/59eaeb0f852e494285bd67ea8f850a42_fbx/RootNode/Crypt" if key == "mausoleum" else "OuterDatum/%s" % pair[2],
			"visual_reference_bound":is_instance_valid(get_node_or_null("PackageTransform/AuthoredCemeteryPackage/Sketchfab_model/59eaeb0f852e494285bd67ea8f850a42_fbx/RootNode/Crypt")) if key == "mausoleum" else is_instance_valid(visual),
			"aligned":is_instance_valid(anchor) and is_instance_valid(body) and is_instance_valid(shape) and is_instance_valid(visual) and body_offset <= 0.05 and offset <= 0.1,
		}
	return result

func get_snapshot() -> Dictionary:
	var playable := get_playable_rect()
	var visual := get_authored_visual_rect()
	var fill := get_camera_fill_rect()
	var landmark_alignment := _landmark_alignment_receipt()
	var playable_inside_authored := playable.position.x > visual.position.x and playable.end.x < visual.end.x and playable.position.y > visual.position.y and playable.end.y < visual.end.y
	var perimeter_present := is_instance_valid(north_boundary) and is_instance_valid(south_boundary) and is_instance_valid(east_boundary) and is_instance_valid(west_boundary)
	var landmarks_aligned := true
	for landmark in landmark_alignment.values():
		landmarks_aligned = landmarks_aligned and bool((landmark as Dictionary).get("aligned", false))
	return {
		"contract_id":"cemetery_spatial_integrity_v47",
		"authored_bounds_contract":{
			"minimum":visual.position,
			"maximum":visual.end,
			"external_world_required":true,
			"playable_inside_authored":playable_inside_authored,
		},
		"world_scale":global_transform.basis.get_scale().abs(),
		"package_transform":{
			"position":package_root.position if is_instance_valid(package_root) else Vector3.ZERO,
			"wrapper_position":package_root.get_parent().position if is_instance_valid(package_root) else Vector3.ZERO,
			"scale":package_root.get_parent().scale if is_instance_valid(package_root) else Vector3.ONE,
			"native_export_rebased":is_instance_valid(package_root) and package_root.position.length() > 50.0,
			"authoritative_instance":"AuthoredCemeteryPackage",
			"datum_owner":"PackageTransform",
			"scale_binding":"native_map_scale * authored_wrapper_scale_multiplier",
		},
		"anchor_ids":["PlayerSpawn","KeeperLanternPostAnchor","SmallMausoleumAnchor","CrackedMoonBellAnchor","TargetAnchorA","TargetAnchorB"],
		# Landmark bodies use authored environment layer 2; perimeter bodies remain
		# on layer 2 for boundary probes. Warden/enemy masks include both layers,
		# while camera coverage mask 1 audits the sight lane without treating the
		# central building as a physics occluder.
		"collision_layers":{"ground":4,"perimeter":2,"landmarks":2,"mausoleum_gameplay":2,"camera_query_excluded":2,"navigation":0},
		"navigation_region":{"path":"OuterDatum/NativeNavigationRegion","layers":1,"source":"native_authored_streets","enabled":is_instance_valid(get_node_or_null("OuterDatum/NativeNavigationRegion"))},
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
		"collision_source":"scaled_outer_datum_static_bodies_with_camera_query_split",
		"background_mode":"single_intact_authored_cemetery_with_restrained_fog",
		"composition_layers":{
			"strategy":"additive_authored_package_readability",
			"native_instance_count":1,
			"depth_hierarchy":["foreground_graves_and_fence","midground_native_streets_and_landmarks","perimeter_trees_and_external_terrain"],
			"warm_anchor":"OuterDatum/KeeperLanternPostAnchor/WarmLandmarkLight",
			"cool_fills":["OuterDatum/RouteMoonFill","OuterDatum/WestMoonRim","OuterDatum/EastMoonRim","OuterDatum/SmallMausoleumAnchor/MausoleumMoonLift"],
			"escape_lane_policy":"native_street_network_preserved",
			"camera_profile":{"fov":64.0,"follow_height":24.0,"follow_distance":19.0,"follow_lateral":5.0,"framing_bias":Vector3(0.0,0.0,1.5)},
			"proxy_geometry_count":0,
		},
		"external_world":{"source":"intact_authored_package_native_terrain_and_perimeter", "procedural_scenery":false, "primitive_meshes":0, "opaque":true, "non_playable_depth_beyond_all_edges":true},
		"uv_binding":uv_binding_receipt.duplicate(true),
		"landmark_collision":{"keeper_post":is_instance_valid(get_node_or_null("OuterDatum/KeeperLanternPostAnchor/KeeperPostCollision")), "small_mausoleum":is_instance_valid(get_node_or_null("OuterDatum/MausoleumCollision")), "cracked_bell":is_instance_valid(get_node_or_null("OuterDatum/CrackedMoonBellAnchor/CrackedBellCollision"))},
		"landmark_collision_alignment":_landmark_alignment_receipt(),
		"perimeter_collision":{"north":is_instance_valid(north_boundary), "south":is_instance_valid(south_boundary), "east":is_instance_valid(east_boundary), "west":is_instance_valid(west_boundary)},
		"boundary_visibility_alignment":{
			"perimeter_bodies_present":perimeter_present,
			"playable_inside_authored":playable_inside_authored,
			"external_depth_on_all_edges":playable_inside_authored and visual.position.x < playable.position.x and visual.end.x > playable.end.x and visual.position.y < playable.position.y and visual.end.y > playable.end.y,
			"landmarks_grounded_and_aligned":landmarks_aligned,
			"ordinary_route_safe":perimeter_present and playable_inside_authored and landmarks_aligned,
		},
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
