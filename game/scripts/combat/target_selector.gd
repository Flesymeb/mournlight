class_name TargetSelector
extends RefCounted

static var _target_bias_mode := 0

static func configure_bias(mode: int) -> void:
	_target_bias_mode = clampi(mode, 0, 1)

static func target_bias_mode() -> int:
	return _target_bias_mode

static func nearest_legal(owner: Node3D, maximum_range: float, registry: EnemyNeighborRegistry) -> Node3D:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or not is_instance_valid(registry):
		return null
	return registry.query_nearest_legal(owner.global_position, maximum_range)

static func legal_in_radius(origin: Vector3, maximum_range: float, registry: EnemyNeighborRegistry) -> Array[Node3D]:
	if not is_instance_valid(registry):
		return []
	return registry.query_legal_in_radius(origin, maximum_range)
