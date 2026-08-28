class_name EnemyNeighborRegistry
extends Node

const MAX_CANDIDATES := 12

var cell_size := 2.5
var _entries: Dictionary = {}
var _cells: Dictionary = {}
var _sorted_ids: Array[String] = []
var _built_physics_frame := -1
var _telemetry_frame := -1
var _frame_rebuilds := 0
var _frame_queries := 0
var _frame_candidate_visits := 0
var _frame_max_query_size := 0
var _last_completed_frame := -1
var _last_frame_rebuilds := 0
var _last_frame_queries := 0
var _last_frame_candidate_visits := 0
var _last_frame_max_query_size := 0
var _total_rebuilds := 0
var _total_queries := 0
var _total_candidate_visits := 0
var _stale_rejections := 0
var _target_frame_queries := 0
var _target_frame_candidate_visits := 0
var _target_frame_maximum_result_size := 0
var _last_target_frame_queries := 0
var _last_target_frame_candidate_visits := 0
var _last_target_frame_maximum_result_size := 0
var _total_target_queries := 0
var _total_target_candidate_visits := 0
var _duplicate_registration_rejections := 0
var _duplicate_retirement_rejections := 0
var _maximum_rebuilds_per_physics_frame := 0
var _maximum_neighbor_queries_per_physics_frame := 0
var _maximum_neighbor_candidate_visits_per_physics_frame := 0
var _maximum_target_queries_per_physics_frame := 0
var _maximum_target_candidate_visits_per_physics_frame := 0

func _ready() -> void:
	name = "EnemyNeighborRegistry"
	process_physics_priority = -100
	add_to_group("mcp_watch")
	set_physics_process(false)

func register_actor(actor: EnemyActor) -> void:
	register_target(actor, actor.spawn_generation if is_instance_valid(actor) else -1)

func register_target(target: Node3D, generation: int) -> void:
	if not is_instance_valid(target) or not target.has_method("get_stable_id"):
		return
	var key := String(target.get_stable_id())
	var existing: Dictionary = _entries.get(key, {})
	if not existing.is_empty() and existing.get("actor") == target and int(existing.get("generation", -1)) == generation:
		_duplicate_registration_rejections += 1
		return
	_entries[key] = {"actor": target, "generation": generation}
	if not _sorted_ids.has(key):
		_sorted_ids.append(key)
		_sorted_ids.sort()
	_built_physics_frame = -1
	set_physics_process(true)

func unregister_actor(stable_id: StringName, generation: int) -> void:
	unregister_target(stable_id, generation)

func unregister_target(stable_id: StringName, generation: int) -> void:
	var key := String(stable_id)
	var entry: Dictionary = _entries.get(key, {})
	if entry.is_empty():
		_duplicate_retirement_rejections += 1
		return
	if int(entry.get("generation", -1)) != generation:
		_stale_rejections += 1
		return
	_entries.erase(key)
	_sorted_ids.erase(key)
	_built_physics_frame = -1
	if _entries.is_empty():
		set_physics_process(false)

func clear() -> void:
	_entries.clear()
	_cells.clear()
	_sorted_ids.clear()
	_built_physics_frame = -1
	set_physics_process(false)
	reset_telemetry()

func reset_telemetry() -> void:
	_built_physics_frame = -1
	_telemetry_frame = Engine.get_physics_frames()
	_frame_rebuilds = 0
	_frame_queries = 0
	_frame_candidate_visits = 0
	_frame_max_query_size = 0
	_last_completed_frame = -1
	_last_frame_rebuilds = 0
	_last_frame_queries = 0
	_last_frame_candidate_visits = 0
	_last_frame_max_query_size = 0
	_total_rebuilds = 0
	_total_queries = 0
	_total_candidate_visits = 0
	_stale_rejections = 0
	_target_frame_queries = 0
	_target_frame_candidate_visits = 0
	_target_frame_maximum_result_size = 0
	_last_target_frame_queries = 0
	_last_target_frame_candidate_visits = 0
	_last_target_frame_maximum_result_size = 0
	_total_target_queries = 0
	_total_target_candidate_visits = 0
	_duplicate_registration_rejections = 0
	_duplicate_retirement_rejections = 0
	_maximum_rebuilds_per_physics_frame = 0
	_maximum_neighbor_queries_per_physics_frame = 0
	_maximum_neighbor_candidate_visits_per_physics_frame = 0
	_maximum_target_queries_per_physics_frame = 0
	_maximum_target_candidate_visits_per_physics_frame = 0

func query_neighbors(actor: EnemyActor, radius: float) -> Array[EnemyActor]:
	var frame := Engine.get_physics_frames()
	_begin_frame(frame)
	_rebuild_if_needed(frame)
	_frame_queries += 1
	_total_queries += 1
	var result: Array[EnemyActor] = []
	if not is_instance_valid(actor) or radius <= 0.0:
		return result
	var origin := _cell_for(actor.global_position)
	var candidate_ids: Array[String] = []
	for z_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			var cell_key := Vector2i(origin.x + x_offset, origin.y + z_offset)
			for stable_id in (_cells.get(cell_key, []) as Array):
				if stable_id != String(actor.stable_id):
					candidate_ids.append(String(stable_id))
	candidate_ids.sort()
	var visits := 0
	for stable_id in candidate_ids:
		if visits >= MAX_CANDIDATES:
			break
		visits += 1
		_frame_candidate_visits += 1
		_total_candidate_visits += 1
		var entry: Dictionary = _entries.get(stable_id, {})
		var other: EnemyActor = entry.get("actor") as EnemyActor
		if not is_instance_valid(other) or other.state in ["pooled", "death"]:
			continue
		if int(entry.get("generation", -1)) != other.spawn_generation:
			_stale_rejections += 1
			continue
		var planar := other.global_position - actor.global_position
		planar.y = 0.0
		if planar.length_squared() < radius * radius:
			result.append(other)
	_frame_max_query_size = maxi(_frame_max_query_size, result.size())
	return result

func query_nearest_legal(origin: Vector3, radius: float) -> Node3D:
	var candidates := _query_target_candidates(origin, radius)
	var nearest: Node3D
	var nearest_distance := INF
	var nearest_id := ""
	for candidate in candidates:
		var distance_squared := origin.distance_squared_to(candidate.global_position)
		var candidate_id := String(candidate.get_stable_id())
		if distance_squared < nearest_distance or (is_equal_approx(distance_squared, nearest_distance) and (nearest_id.is_empty() or candidate_id < nearest_id)):
			nearest = candidate
			nearest_distance = distance_squared
			nearest_id = candidate_id
	return nearest

func query_legal_in_radius(origin: Vector3, radius: float) -> Array[Node3D]:
	var result := _query_target_candidates(origin, radius)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.get_stable_id()) < String(b.get_stable_id()))
	return result

func _query_target_candidates(origin: Vector3, radius: float) -> Array[Node3D]:
	var frame := Engine.get_physics_frames()
	_begin_frame(frame)
	_rebuild_if_needed(frame)
	_target_frame_queries += 1
	_total_target_queries += 1
	var result: Array[Node3D] = []
	if radius <= 0.0:
		return result
	var center := _cell_for(origin)
	var cell_radius := ceili(radius / cell_size)
	var radius_squared := radius * radius
	for z_offset in range(-cell_radius, cell_radius + 1):
		for x_offset in range(-cell_radius, cell_radius + 1):
			var cell_key := Vector2i(center.x + x_offset, center.y + z_offset)
			for stable_id_value in (_cells.get(cell_key, []) as Array):
				var stable_id := String(stable_id_value)
				_target_frame_candidate_visits += 1
				_total_target_candidate_visits += 1
				var entry: Dictionary = _entries.get(stable_id, {})
				var candidate := entry.get("actor") as Node3D
				if not _entry_is_current(entry, candidate):
					_stale_rejections += 1
					continue
				if not candidate.has_method("is_legal_target") or not candidate.is_legal_target():
					continue
				if origin.distance_squared_to(candidate.global_position) <= radius_squared:
					result.append(candidate)
	_target_frame_maximum_result_size = maxi(_target_frame_maximum_result_size, result.size())
	return result

func _physics_process(_delta: float) -> void:
	var frame := Engine.get_physics_frames()
	_begin_frame(frame)
	_rebuild_if_needed(frame)

func _begin_frame(frame: int) -> void:
	if _telemetry_frame == frame:
		return
	if _telemetry_frame >= 0:
		_last_completed_frame = _telemetry_frame
		_last_frame_rebuilds = _frame_rebuilds
		_last_frame_queries = _frame_queries
		_last_frame_candidate_visits = _frame_candidate_visits
		_last_frame_max_query_size = _frame_max_query_size
		_last_target_frame_queries = _target_frame_queries
		_last_target_frame_candidate_visits = _target_frame_candidate_visits
		_last_target_frame_maximum_result_size = _target_frame_maximum_result_size
		_maximum_rebuilds_per_physics_frame = maxi(_maximum_rebuilds_per_physics_frame, _frame_rebuilds)
		_maximum_neighbor_queries_per_physics_frame = maxi(_maximum_neighbor_queries_per_physics_frame, _frame_queries)
		_maximum_neighbor_candidate_visits_per_physics_frame = maxi(_maximum_neighbor_candidate_visits_per_physics_frame, _frame_candidate_visits)
		_maximum_target_queries_per_physics_frame = maxi(_maximum_target_queries_per_physics_frame, _target_frame_queries)
		_maximum_target_candidate_visits_per_physics_frame = maxi(_maximum_target_candidate_visits_per_physics_frame, _target_frame_candidate_visits)
	_telemetry_frame = frame
	_frame_rebuilds = 0
	_frame_queries = 0
	_frame_candidate_visits = 0
	_frame_max_query_size = 0
	_target_frame_queries = 0
	_target_frame_candidate_visits = 0
	_target_frame_maximum_result_size = 0

func _rebuild_if_needed(frame: int) -> void:
	if _built_physics_frame == frame:
		return
	_cells.clear()
	for stable_id in _sorted_ids:
		var entry: Dictionary = _entries.get(stable_id, {})
		var actor := entry.get("actor") as Node3D
		if not _entry_is_current(entry, actor):
			continue
		var key := _cell_for(actor.global_position)
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(String(stable_id))
	_built_physics_frame = frame
	_frame_rebuilds += 1
	_total_rebuilds += 1

func _entry_is_current(entry: Dictionary, actor: Node3D) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return false
	if actor.has_method("get_target_generation") and int(entry.get("generation", -1)) != int(actor.get_target_generation()):
		return false
	if actor is EnemyActor and actor.state in ["pooled", "death"]:
		return false
	return true

func _cell_for(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.z / cell_size))

func get_snapshot() -> Dictionary:
	return {
		"active_count": _entries.size(),
		"registered_count": _entries.size(),
		"physics_frame": _last_completed_frame,
		"rebuild_count": _last_frame_rebuilds,
		"query_count": _last_frame_queries,
		"candidate_visits": _last_frame_candidate_visits,
		"maximum_query_size": _last_frame_max_query_size,
		"current_frame": {"physics_frame":_telemetry_frame, "rebuild_count":_frame_rebuilds, "query_count":_frame_queries, "candidate_visits":_frame_candidate_visits, "maximum_query_size":_frame_max_query_size},
		"candidate_budget": MAX_CANDIDATES,
		"stable_order_cache_size":_sorted_ids.size(),
		"total_rebuilds": _total_rebuilds,
		"total_queries": _total_queries,
		"total_candidate_visits": _total_candidate_visits,
		"stale_generation_rejections": _stale_rejections,
		"target_query_count":_last_target_frame_queries,
		"target_candidate_visits":_last_target_frame_candidate_visits,
		"target_maximum_result_size":_last_target_frame_maximum_result_size,
		"target_current_frame":{"query_count":_target_frame_queries,"candidate_visits":_target_frame_candidate_visits,"maximum_result_size":_target_frame_maximum_result_size},
		"total_target_queries":_total_target_queries,
		"total_target_candidate_visits":_total_target_candidate_visits,
		"maximum_rebuilds_per_physics_frame":_maximum_rebuilds_per_physics_frame,
		"maximum_neighbor_queries_per_physics_frame":_maximum_neighbor_queries_per_physics_frame,
		"maximum_neighbor_candidate_visits_per_physics_frame":_maximum_neighbor_candidate_visits_per_physics_frame,
		"maximum_target_queries_per_physics_frame":_maximum_target_queries_per_physics_frame,
		"maximum_target_candidate_visits_per_physics_frame":_maximum_target_candidate_visits_per_physics_frame,
		"rebuild_bound_respected":_maximum_rebuilds_per_physics_frame <= 1 and _frame_rebuilds <= 1,
		"telemetry_reset_scope":"ordinary_run",
		"full_group_inventory_count":0,
		"duplicate_registration_rejections":_duplicate_registration_rejections,
		"duplicate_retirement_rejections":_duplicate_retirement_rejections,
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
