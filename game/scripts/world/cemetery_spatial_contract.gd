class_name CemeterySpatialContract
extends Node3D

@export var camera_world_margin := Vector2(11.2, 10.8)
@export var protected_camera_half_extents := Vector2(7.2, 5.4)
@export var minimum_player_safe_radius := 8.2
@export var spawn_clearance := 0.6
@export var external_world_half_extent := 96.0
@export var external_world_cell_size := 4.0

@onready var ground_collision: StaticBody3D = $OuterDatum/GroundCollision
@onready var north_boundary: StaticBody3D = $OuterDatum/NorthBoundary
@onready var south_boundary: StaticBody3D = $OuterDatum/SouthBoundary
@onready var east_boundary: StaticBody3D = $OuterDatum/EastBoundary
@onready var west_boundary: StaticBody3D = $OuterDatum/WestBoundary
@onready var player_spawn: Marker3D = $OuterDatum/PlayerSpawn
@onready var package_root: Node3D = $PackageTransform/AuthoredCemeteryPackage

const AUTHORED_LOCAL_MIN := Vector2(-12.143, -11.415)
const AUTHORED_LOCAL_MAX := Vector2(12.149, 11.418)
const EXTERNAL_INNER_HALF_EXTENTS := Vector2(10.8, 10.45)

var _external_world_root: Node3D
var _external_visual_paths: Array[String] = []
var _external_instance_counts := {"grave_markers":0, "grave_bases":0, "tree_trunks":0, "tree_crowns":0, "stone_clusters":0}

func _ready() -> void:
	_build_external_world()

func _build_external_world() -> void:
	_external_world_root = Node3D.new()
	_external_world_root.name = "ExternalWorld"
	_external_world_root.add_to_group(&"external_world_scenery")
	$OuterDatum.add_child(_external_world_root)
	_build_external_terrain()
	_build_external_silhouettes()

func _build_external_terrain() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_cells := ceili(external_world_half_extent / external_world_cell_size)
	for z_index in range(-half_cells, half_cells):
		for x_index in range(-half_cells, half_cells):
			var center := Vector2((float(x_index) + 0.5) * external_world_cell_size, (float(z_index) + 0.5) * external_world_cell_size)
			if absf(center.x) < EXTERNAL_INNER_HALF_EXTENTS.x and absf(center.y) < EXTERNAL_INNER_HALF_EXTENTS.y:
				continue
			_add_terrain_quad(surface, center, external_world_cell_size)
	var terrain := MeshInstance3D.new()
	terrain.name = "OpaqueMoonlitTerrain"
	terrain.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.96
	material.metallic = 0.02
	terrain.material_override = material
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_external_world_root.add_child(terrain)
	_external_visual_paths.append(String(terrain.get_path()))

func _add_terrain_quad(surface: SurfaceTool, center: Vector2, cell_size: float) -> void:
	var half := cell_size * 0.5
	var points := [
		_terrain_point(center.x - half, center.y - half),
		_terrain_point(center.x - half, center.y + half),
		_terrain_point(center.x + half, center.y + half),
		_terrain_point(center.x + half, center.y - half),
	]
	# Godot's front-face convention is clockwise when viewed from the front.
	for index in [0, 2, 1, 0, 3, 2]:
		var point: Vector3 = points[index]
		surface.set_color(_terrain_color(point.x, point.z))
		surface.set_normal(Vector3.UP)
		surface.add_vertex(point)

func _terrain_color(x: float, z: float) -> Color:
	# Shared-corner colors prevent the procedural cells reading as a checkerboard.
	# The near band matches the authored cemetery's near-black moss; distance
	# cools gently into moonlit navy without becoming a bright finished-art plane.
	var distance_mix := clampf(Vector2(x, z).length() / external_world_half_extent, 0.0, 1.0)
	var broad_mottle := 0.5 + 0.5 * sin(x * 0.13 + z * 0.09) * cos(z * 0.07 - x * 0.05)
	var near_moss := Color("07130e").lerp(Color("0b1a13"), broad_mottle * 0.32)
	return near_moss.lerp(Color("040817"), distance_mix * 0.72)

func _terrain_point(x: float, z: float) -> Vector3:
	return Vector3(x, -0.13 + sin(x * 0.19) * cos(z * 0.17) * 0.11, z)

func _build_external_silhouettes() -> void:
	var grave_transforms: Array[Transform3D] = []
	var base_transforms: Array[Transform3D] = []
	for index in 112:
		var angle := float(index) * TAU / 112.0 + sin(float(index) * 1.7) * 0.08
		var radius := 13.8 + float(posmod(index * 17, 43)) * 0.92
		var position := Vector3(cos(angle) * radius, 0.42, sin(angle) * radius)
		var scale := Vector3(0.52 + float(posmod(index, 3)) * 0.08, 0.82 + float(posmod(index * 5, 4)) * 0.12, 0.22)
		grave_transforms.append(Transform3D(Basis(Vector3.UP, -angle + PI * 0.5).scaled(scale), position))
		base_transforms.append(Transform3D(Basis(Vector3.UP, -angle + PI * 0.5).scaled(Vector3(scale.x * 1.35, 0.16, 0.55)), Vector3(position.x, 0.08, position.z)))
	_add_external_multimesh("MoonlitGraveMarkers", _box_mesh(Vector3.ONE, Color("33465d")), grave_transforms, "grave_markers")
	_add_external_multimesh("GraveMarkerBases", _box_mesh(Vector3.ONE, Color("202d42")), base_transforms, "grave_bases")

	var trunk_transforms: Array[Transform3D] = []
	var crown_transforms: Array[Transform3D] = []
	for index in 52:
		var angle := float(index) * TAU / 52.0 + 0.17
		var radius := 25.0 + float(posmod(index * 11, 28)) * 1.05
		var height := 3.4 + float(posmod(index * 3, 5)) * 0.42
		var position := Vector3(cos(angle) * radius, height * 0.5, sin(angle) * radius)
		trunk_transforms.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(0.52, height, 0.52)), position))
		var crown_position := Vector3(position.x, height + 0.72, position.z)
		crown_transforms.append(Transform3D(Basis(Vector3.UP, angle * 1.7).scaled(Vector3(2.05, 2.25, 1.75)), crown_position))
		crown_transforms.append(Transform3D(Basis(Vector3.UP, angle * 1.7 + 0.8).scaled(Vector3(1.45, 1.65, 1.35)), crown_position + Vector3(sin(angle) * 0.45, 1.45, cos(angle) * 0.45)))
	_add_external_multimesh("CemeteryTreeTrunks", _cylinder_mesh(Color("182337")), trunk_transforms, "tree_trunks")
	_add_external_multimesh("CemeteryTreeCrowns", _sphere_mesh(Color("15283a")), crown_transforms, "tree_crowns")

	var stone_transforms: Array[Transform3D] = []
	for index in 92:
		var angle := float(index) * TAU / 92.0 + 0.31
		var radius := 17.0 + float(posmod(index * 13, 38)) * 1.05
		var scale := Vector3(0.65 + float(posmod(index, 4)) * 0.13, 0.34 + float(posmod(index * 2, 3)) * 0.1, 0.55 + float(posmod(index * 5, 4)) * 0.12)
		stone_transforms.append(Transform3D(Basis(Vector3.UP, angle * 2.0).scaled(scale), Vector3(cos(angle) * radius, scale.y * 0.48 - 0.05, sin(angle) * radius)))
	_add_external_multimesh("FogStoneClusters", _sphere_mesh(Color("26364b")), stone_transforms, "stone_clusters")

func _add_external_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], counter_key: String) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = transforms.size()
	multimesh.mesh = mesh
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_external_world_root.add_child(instance)
	_external_visual_paths.append(String(instance.get_path()))
	_external_instance_counts[counter_key] = transforms.size()

func _box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _opaque_material(color)
	return mesh

func _cylinder_mesh(color: Color) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.62
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = _opaque_material(color)
	return mesh

func _sphere_mesh(color: Color) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 7
	mesh.rings = 4
	mesh.material = _opaque_material(color)
	return mesh

func _opaque_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.metallic = 0.03
	return material

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
	var world_scale := global_transform.basis.get_scale().abs()
	var root_scale := Vector2(world_scale.x, world_scale.z)
	var minimum := AUTHORED_LOCAL_MIN * root_scale
	var maximum := AUTHORED_LOCAL_MAX * root_scale
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
		"contract_id":"cemetery_spatial_integrity_v44",
		"world_scale":global_transform.basis.get_scale().abs(),
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
		"background_mode":"opaque_moonlit_world_with_fog",
		"external_world":{"built":is_instance_valid(_external_world_root), "half_extent":external_world_half_extent, "visual_paths":_external_visual_paths.duplicate(), "instance_counts":_external_instance_counts.duplicate(true), "opaque":true, "non_playable":true},
		"landmark_collision":{"keeper_post":is_instance_valid(get_node_or_null("OuterDatum/KeeperLanternPostAnchor/KeeperPostCollision")), "small_mausoleum":is_instance_valid(get_node_or_null("OuterDatum/MausoleumCollision")), "cracked_bell":is_instance_valid(get_node_or_null("OuterDatum/CrackedMoonBellAnchor/CrackedBellCollision"))},
		"perimeter_collision":{"north":is_instance_valid(north_boundary), "south":is_instance_valid(south_boundary), "east":is_instance_valid(east_boundary), "west":is_instance_valid(west_boundary)},
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
