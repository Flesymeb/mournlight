class_name EnemyNeighborRegistry
extends Node

const MAX_CANDIDATES := 12

var cell_size := 2.5
var _entries: Dictionary = {}
var _cells: Dictionary = {}
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

func _ready() -> void:
	name = "EnemyNeighborRegistry"
	process_physics_priority = -100
	add_to_group("mcp_watch")
	set_physics_process(false)

func register_actor(actor: EnemyActor) -> void:
	if not is_instance_valid(actor):
		return
	_entries[String(actor.stable_id)] = {"actor": actor, "generation": actor.spawn_generation}
	_built_physics_frame = -1
	set_physics_process(true)

func unregister_actor(stable_id: StringName, generation: int) -> void:
	var key := String(stable_id)
	var entry: Dictionary = _entries.get(key, {})
	if entry.is_empty():
		return
	if int(entry.get("generation", -1)) != generation:
		_stale_rejections += 1
		return
	_entries.erase(key)
	_built_physics_frame = -1
	if _entries.is_empty():
		set_physics_process(false)

func clear() -> void:
	_entries.clear()
	_cells.clear()
	_built_physics_frame = -1
	set_physics_process(false)
	_begin_frame(Engine.get_physics_frames())

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
	_telemetry_frame = frame
	_frame_rebuilds = 0
	_frame_queries = 0
	_frame_candidate_visits = 0
	_frame_max_query_size = 0

func _rebuild_if_needed(frame: int) -> void:
	if _built_physics_frame == frame:
		return
	_cells.clear()
	var stable_ids: Array = _entries.keys()
	stable_ids.sort()
	for stable_id in stable_ids:
		var entry: Dictionary = _entries.get(stable_id, {})
		var actor: EnemyActor = entry.get("actor") as EnemyActor
		if not is_instance_valid(actor) or actor.state in ["pooled", "death"] or int(entry.get("generation", -1)) != actor.spawn_generation:
			continue
		var key := _cell_for(actor.global_position)
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(String(stable_id))
	_built_physics_frame = frame
	_frame_rebuilds += 1
	_total_rebuilds += 1

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
		"total_rebuilds": _total_rebuilds,
		"total_queries": _total_queries,
		"total_candidate_visits": _total_candidate_visits,
		"stale_generation_rejections": _stale_rejections,
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
