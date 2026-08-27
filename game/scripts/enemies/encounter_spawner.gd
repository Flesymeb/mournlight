class_name EncounterSpawner
extends Node3D

signal encounter_changed(snapshot: Dictionary)
signal enemy_lifecycle(event: Dictionary)
signal enemy_defeated(event: Dictionary)
signal reward_dropped(event: Dictionary)

@export var enemy_scene: PackedScene
@export var profiles: Array[EnemyProfile] = []
@export var player: WardenController
@export var pool_size := 12
@export var live_cap := 10
@export var minimum_player_safe_radius := 7.0
@export var playable_half_extents := Vector2(14.4, 10.2)
@export var protected_camera_half_extents := Vector2(7.2, 4.6)

var active := false
var encounter_id := 0
var spawned_total := 0
var defeated_total := 0
var rejected_spawn_count := 0
var last_spawn_receipt: Dictionary = {}
var last_lifecycle_event: Dictionary = {}
var _pool: Array[EnemyActor] = []
var _spawn_cursor := 0
var _spawn_cooldown := 0.0
var _generation_by_id: Dictionary = {}

const LANES := [
	Vector3(-12.8, 0.05, -8.2), Vector3(-4.5, 0.05, -10.0),
	Vector3(5.0, 0.05, -9.8), Vector3(13.2, 0.05, -4.0),
	Vector3(13.4, 0.05, 7.7), Vector3(5.0, 0.05, 10.0),
	Vector3(-6.0, 0.05, 9.8), Vector3(-13.2, 0.05, 5.4),
]

func _ready() -> void:
	for index in range(pool_size):
		var actor := enemy_scene.instantiate() as EnemyActor
		actor.stable_id = StringName("enemy.pool.%02d" % index)
		actor.defeated.connect(_on_enemy_defeated)
		actor.drop_committed.connect(_on_reward_dropped)
		actor.lifecycle_event.connect(_on_lifecycle_event)
		add_child(actor)
		_pool.append(actor)
	set_process(false)

func begin_encounter() -> void:
	reset_encounter()
	active = true
	encounter_id += 1
	set_process(true)
	for index in range(mini(8, live_cap)):
		_spawn_one(index)
	_emit_snapshot()

func stop_encounter() -> void:
	active = false
	set_process(false)
	for actor in _pool:
		if actor.state != "pooled":
			actor.remove_from_group("active_enemies")
			actor.return_to_pool()
	_emit_snapshot()

func reset_encounter() -> void:
	active = false
	set_process(false)
	spawned_total = 0
	defeated_total = 0
	rejected_spawn_count = 0
	last_spawn_receipt = {}
	last_lifecycle_event = {}
	_spawn_cursor = 0
	_spawn_cooldown = 0.0
	_generation_by_id.clear()
	for actor in _pool:
		actor.remove_from_group("active_enemies")
		actor.return_to_pool()

func _process(delta: float) -> void:
	if not active:
		return
	_spawn_cooldown = maxf(0.0, _spawn_cooldown - delta)
	if _spawn_cooldown <= 0.0 and _active_count() < live_cap:
		_spawn_one(_spawn_cursor)
		_spawn_cooldown = 1.45

func _spawn_one(role_offset: int) -> bool:
	var actor := _next_pooled_actor()
	if not actor or profiles.is_empty():
		return false
	for attempt in range(LANES.size()):
		var lane_index := (_spawn_cursor + attempt * 3) % LANES.size()
		var position: Vector3 = LANES[lane_index]
		var validation := validate_spawn_position(position)
		if not bool(validation.valid):
			rejected_spawn_count += 1
			continue
		var generation := int(_generation_by_id.get(actor.stable_id, 0)) + 1
		_generation_by_id[actor.stable_id] = generation
		var selected_profile := profiles[spawned_total % profiles.size()]
		actor.add_to_group("active_enemies")
		actor.activate(selected_profile, player, position, generation)
		spawned_total += 1
		_spawn_cursor = (lane_index + 1) % LANES.size()
		last_spawn_receipt = {
			"stable_id": String(actor.stable_id), "generation": generation,
			"role_id": String(selected_profile.role_id), "lane_index": lane_index,
			"position": position, "validation": validation,
		}
		_emit_snapshot()
		return true
	return false

func validate_spawn_position(position: Vector3) -> Dictionary:
	if absf(position.x) > playable_half_extents.x or absf(position.z) > playable_half_extents.y:
		return {"valid": false, "reason": "outside_playable_datum"}
	if not is_instance_valid(player):
		return {"valid": false, "reason": "missing_player"}
	var delta := position - player.global_position
	if delta.length() < minimum_player_safe_radius:
		return {"valid": false, "reason": "inside_player_safe_radius"}
	if absf(delta.x) < protected_camera_half_extents.x and absf(delta.z) < protected_camera_half_extents.y:
		return {"valid": false, "reason": "inside_protected_camera_region"}
	if _inside_authored_collision(position):
		return {"valid": false, "reason": "inside_authored_collision"}
	if not _has_valid_approach(position):
		return {"valid": false, "reason": "no_valid_approach"}
	return {"valid": true, "reason": "validated_lane", "safe_distance": delta.length()}

func _inside_authored_collision(position: Vector3) -> bool:
	var in_mausoleum := absf(position.x - 0.1) < 2.6 and absf(position.z + 1.1) < 2.0
	var in_tree := Vector2(position.x - 5.2, position.z + 2.8).length() < 1.35
	return in_mausoleum or in_tree

func _has_valid_approach(position: Vector3) -> bool:
	var midpoint := position.lerp(player.global_position, 0.5)
	return not _inside_authored_collision(midpoint)

func _next_pooled_actor() -> EnemyActor:
	for actor in _pool:
		if actor.state == "pooled":
			return actor
	return null

func _active_count() -> int:
	var count := 0
	for actor in _pool:
		if actor.state != "pooled":
			count += 1
	return count

func _on_enemy_defeated(actor: EnemyActor, event: Dictionary) -> void:
	defeated_total += 1
	var report := event.duplicate(true)
	report.stable_id = String(actor.stable_id)
	report.role_id = String(actor.profile.role_id)
	enemy_defeated.emit(report)
	_emit_snapshot()
	var tween := create_tween()
	tween.tween_interval(0.78)
	tween.tween_callback(func() -> void:
		actor.remove_from_group("active_enemies")
		actor.return_to_pool()
		_emit_snapshot()
	)

func _on_reward_dropped(event: Dictionary) -> void:
	reward_dropped.emit(event)

func _on_lifecycle_event(event: Dictionary) -> void:
	last_lifecycle_event = event.duplicate(true)
	enemy_lifecycle.emit(last_lifecycle_event)

func _emit_snapshot() -> void:
	encounter_changed.emit(get_snapshot())

func get_snapshot() -> Dictionary:
	var roles: Dictionary = {}
	for actor in _pool:
		if actor.state == "pooled" or not actor.profile:
			continue
		var role := String(actor.profile.role_id)
		roles[role] = int(roles.get(role, 0)) + 1
	return {
		"encounter_id": encounter_id, "active": active, "live": _active_count(),
		"cap": live_cap, "spawned": spawned_total, "defeated": defeated_total,
		"pooled": pool_size - _active_count(), "roles": roles,
		"rejected_spawns": rejected_spawn_count, "last_spawn_receipt": last_spawn_receipt,
		"last_lifecycle_event": last_lifecycle_event,
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
