class_name AuthoredMeshBinding
extends RefCounted

## Repairs only product-owned runtime bindings. Imported mesh resources remain
## untouched; an integration copy is created only when UV/tangent data is
## missing, malformed, or triangle-degenerate.
static func repair_visible_meshes(root: Node) -> Dictionary:
	var checked := 0
	var repaired := 0
	var repaired_surfaces := 0
	var source_degenerate := 0
	if not is_instance_valid(root):
		return {"status":"invalid_root", "checked_meshes":0, "repaired_meshes":0, "repaired_surfaces":0, "source_degenerate_uv_surfaces":0}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not is_instance_valid(instance) or not instance.visible or not is_instance_valid(instance.mesh):
			continue
		checked += 1
		var source: Mesh = instance.mesh
		var copy := ArrayMesh.new()
		var needs_copy := false
		for surface_index in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays.size() > Mesh.ARRAY_TANGENT and arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array else PackedFloat32Array()
			var uv_bad := uvs.is_empty() or uvs.size() != vertices.size()
			if not uv_bad and not vertices.is_empty():
				var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
				for triangle in triangle_count:
					var i0 := int(indices[triangle * 3]) if not indices.is_empty() else triangle * 3
					var i1 := int(indices[triangle * 3 + 1]) if not indices.is_empty() else triangle * 3 + 1
					var i2 := int(indices[triangle * 3 + 2]) if not indices.is_empty() else triangle * 3 + 2
					if i0 >= uvs.size() or i1 >= uvs.size() or i2 >= uvs.size() or absf((uvs[i1] - uvs[i0]).cross(uvs[i2] - uvs[i0])) <= 0.000001:
						uv_bad = true
						break
			if uv_bad:
				source_degenerate += 1
			var tangent_bad := tangents.size() != vertices.size() * 4
			if not uv_bad and not tangent_bad:
				# Preserve the original resource when it is already render-safe.
				copy.add_surface_from_arrays(source.surface_get_primitive_type(surface_index), arrays)
			else:
				needs_copy = true
				var bound := arrays.duplicate(true)
				if uv_bad:
					bound[Mesh.ARRAY_TEX_UV] = _planar_uvs(vertices)
				if tangent_bad:
					bound[Mesh.ARRAY_TANGENT] = _normal_tangents(vertices, arrays)
				copy.add_surface_from_arrays(source.surface_get_primitive_type(surface_index), bound)
				repaired_surfaces += 1
			var material := instance.get_active_material(surface_index)
			if material is Material:
				copy.surface_set_material(surface_index, material)
		if needs_copy:
			instance.mesh = copy
			instance.set_meta("authored_mesh_binding", "integration_repaired")
			instance.set_meta("authored_mesh_source_immutable", true)
			repaired += 1
		else:
			instance.set_meta("authored_mesh_binding", "native_validated")
	return {"status":"validated_repaired" if repaired > 0 else "validated", "checked_meshes":checked, "repaired_meshes":repaired, "repaired_surfaces":repaired_surfaces, "source_degenerate_uv_surfaces":source_degenerate, "source_immutable":true}

static func _planar_uvs(vertices: PackedVector3Array) -> PackedVector2Array:
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
		result.append(Vector2((vertex[u_axis] - bounds.position[u_axis]) / span_u, (vertex[v_axis] - bounds.position[v_axis]) / span_v) + Vector2(float(index % 11) * 0.0011, float(index % 13) * 0.0013))
	return result

static func _normal_tangents(vertices: PackedVector3Array, arrays: Array) -> PackedFloat32Array:
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
