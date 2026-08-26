class_name TargetSelector
extends RefCounted

static func nearest_legal(owner: Node3D, maximum_range: float) -> Node3D:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return null
	var candidates: Array[Node] = owner.get_tree().get_nodes_in_group("combat_targets")
	var legal: Array[Node3D] = []
	for candidate in candidates:
		if candidate is Node3D and is_instance_valid(candidate) and candidate.is_inside_tree():
			if candidate.has_method("is_legal_target") and candidate.is_legal_target():
				if owner.global_position.distance_squared_to(candidate.global_position) <= maximum_range * maximum_range:
					legal.append(candidate)
	legal.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var distance_a := owner.global_position.distance_squared_to(a.global_position)
		var distance_b := owner.global_position.distance_squared_to(b.global_position)
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		return _stable_id(a) < _stable_id(b)
	)
	return legal[0] if not legal.is_empty() else null

static func legal_in_radius(origin: Vector3, maximum_range: float, tree: SceneTree) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for candidate in tree.get_nodes_in_group("combat_targets"):
		if candidate is Node3D and is_instance_valid(candidate) and candidate.is_inside_tree():
			if candidate.has_method("is_legal_target") and candidate.is_legal_target():
				if origin.distance_squared_to(candidate.global_position) <= maximum_range * maximum_range:
					result.append(candidate)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _stable_id(a) < _stable_id(b))
	return result

static func _stable_id(candidate: Node) -> String:
	if candidate.has_method("get_stable_id"):
		return String(candidate.get_stable_id())
	return String(candidate.get_path())

