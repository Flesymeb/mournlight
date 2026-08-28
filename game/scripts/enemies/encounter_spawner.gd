class_name EncounterSpawner
extends Node3D

signal encounter_changed(snapshot: Dictionary)
signal enemy_lifecycle(event: Dictionary)
signal enemy_defeated(event: Dictionary)
signal reward_dropped(event: Dictionary)

@export var enemy_scene: PackedScene
@export var profiles: Array[EnemyProfile] = []
@export var player: WardenController
@export var pool_size := 40
@export var live_cap := 10
@export var minimum_player_safe_radius := 7.0
@export var playable_half_extents := Vector2(10.7, 9.2)
@export var protected_camera_half_extents := Vector2(5.8, 4.2)
@export_range(1, 12, 1) var telegraph_cue_cap := 4
@export_range(0, 16, 1) var role_light_cap := 8
@export_range(0, 8, 1) var hurt_light_cap := 3

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
var _role_variant_cursor: Dictionary = {}
var _role_variant_allocations: Dictionary = {}
var _variant_assignment_by_actor: Dictionary = {}
var _validation_role_sequence: Array[String] = []
var _wave_id := "unconfigured"
var _wave_spawned := 0
var _spawn_budget := 0
var _composition_weights: Dictionary = {}
var _elite_every := 0
var _reconciliation_serial := 0
var retired_total := 0
var last_reconciliation_receipt: Dictionary = {}
var neighbor_registry: EnemyNeighborRegistry
var _telegraph_waiting: Dictionary = {}
var _telegraph_owners: Dictionary = {}
var _cue_requested_total := 0
var _cue_admitted_total := 0
var _cue_released_total := 0
var _cue_peak_admitted := 0
var _last_cue_release: Dictionary = {}
var _role_light_owners: Dictionary = {}
var _hurt_light_owners: Dictionary = {}
var _light_peak_active := 0
var _light_peak_requested := 0
var _baseline_live_cap := 10
var _validation_cohort_active := false
var _validation_cohort_target := 0
var _validation_cohort_generation := 0
var _validation_cohort_start_live := 0
var _validation_cohort_minimum_live := 0
var _validation_cohort_replenished := 0
var _validation_cohort_deaths := 0
var _validation_cohort_maintenance_ticks := 0
var _validation_cohort_last_receipt: Dictionary = {}
var _light_budget_refresh_remaining := 0.0
var _light_budget_update_count := 0
var _light_budget_skipped_frames := 0
var _live_count := 0

const LIGHT_BUDGET_REFRESH_SECONDS := 0.1

const LANES := [
	Vector3(-10.2, 0.05, -7.8), Vector3(-4.2, 0.05, -8.8),
	Vector3(4.6, 0.05, -8.7), Vector3(10.2, 0.05, -3.6),
	Vector3(10.2, 0.05, 7.2), Vector3(4.8, 0.05, 8.8),
	Vector3(-5.4, 0.05, 8.7), Vector3(-10.2, 0.05, 5.0),
]

func _ready() -> void:
	_baseline_live_cap = live_cap
	neighbor_registry = EnemyNeighborRegistry.new()
	add_child(neighbor_registry)
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
	reset_encounter(true)
	active = true
	encounter_id += 1
	set_process(true)
	var initial_spawns := clampi(int(get_meta("initial_spawn_count", 6)), 1, live_cap)
	for index in range(mini(initial_spawns, mini(live_cap, _spawn_budget))):
		_spawn_one(index)
	_emit_snapshot()

func configure_pressure(definition: Dictionary) -> void:
	var next_wave_id := String(definition.get("id", "wave"))
	if next_wave_id != _wave_id:
		_wave_id = next_wave_id
		_wave_spawned = 0
	var requested_cap := clampi(int(definition.get("cap", live_cap)), 1, pool_size)
	if _active_count() > requested_cap:
		_reconcile_to_cap(requested_cap, "wave_cap_reduction")
	live_cap = requested_cap
	_spawn_budget = maxi(live_cap, int(definition.get("spawn_budget", live_cap)))
	_composition_weights = (definition.get("composition_weights", {}) as Dictionary).duplicate(true)
	_elite_every = maxi(0, int(definition.get("elite_every", 0)))
	var cadence := maxf(0.35, float(definition.get("cadence", 1.45)))
	_spawn_cooldown = minf(_spawn_cooldown, cadence)
	set_meta("spawn_cadence", cadence)
	set_meta("initial_spawn_count", clampi(int(definition.get("initial_spawns", 6)), 1, live_cap))

func stop_encounter() -> void:
	end_validation_profile_cohort("encounter_stopped")
	active = false
	set_process(false)
	for actor in _pool:
		if actor.state != "pooled":
			actor.remove_from_group("active_enemies")
			actor.return_to_pool()
	_live_count = 0
	_telegraph_waiting.clear()
	_telegraph_owners.clear()
	_role_light_owners.clear()
	_hurt_light_owners.clear()
	neighbor_registry.clear()
	_emit_snapshot()

func reset_encounter(preserve_pressure: bool = false) -> void:
	end_validation_profile_cohort("encounter_reset")
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
	_role_variant_cursor.clear()
	_role_variant_allocations.clear()
	_variant_assignment_by_actor.clear()
	_wave_spawned = 0
	if not preserve_pressure:
		live_cap = _baseline_live_cap
		_wave_id = "unconfigured"
		_spawn_budget = 0
		_composition_weights.clear()
		_elite_every = 0
		set_meta("spawn_cadence", 1.45)
		set_meta("initial_spawn_count", 6)
	retired_total = 0
	last_reconciliation_receipt = {}
	_telegraph_waiting.clear()
	_telegraph_owners.clear()
	_cue_requested_total = 0
	_cue_admitted_total = 0
	_cue_released_total = 0
	_cue_peak_admitted = 0
	_last_cue_release = {}
	_role_light_owners.clear()
	_hurt_light_owners.clear()
	_light_peak_active = 0
	_light_peak_requested = 0
	_light_budget_refresh_remaining = 0.0
	_light_budget_update_count = 0
	_light_budget_skipped_frames = 0
	for actor in _pool:
		actor.remove_from_group("active_enemies")
		actor.return_to_pool()
	_live_count = 0
	neighbor_registry.clear()

func _process(delta: float) -> void:
	if not active:
		return
	_resolve_telegraph_admissions()
	_light_budget_refresh_remaining = maxf(0.0, _light_budget_refresh_remaining - delta)
	if _light_budget_refresh_remaining <= 0.0:
		_update_light_budget()
		_light_budget_refresh_remaining = LIGHT_BUDGET_REFRESH_SECONDS
	else:
		_light_budget_skipped_frames += 1
	_spawn_cooldown = maxf(0.0, _spawn_cooldown - delta)
	if _spawn_cooldown <= 0.0 and _active_count() < live_cap and _wave_spawned < _spawn_budget:
		_spawn_one(_spawn_cursor)
		_spawn_cooldown = float(get_meta("spawn_cadence", 1.45))
	_maintain_validation_profile_cohort()

func _spawn_one(role_offset: int) -> bool:
	var actor := _next_pooled_actor()
	if not actor or profiles.is_empty():
		return false
	for attempt in range(LANES.size()):
		var lane_index := (_spawn_cursor + attempt * 3) % LANES.size()
		var spread_angle := float(spawned_total + attempt) * 2.399963
		var position: Vector3 = LANES[lane_index] + Vector3(cos(spread_angle), 0.0, sin(spread_angle)) * 0.72
		var validation := validate_spawn_position(position)
		if not bool(validation.valid):
			rejected_spawn_count += 1
			continue
		var generation := int(_generation_by_id.get(actor.stable_id, 0)) + 1
		_generation_by_id[actor.stable_id] = generation
		var selected_profile := _select_profile(_wave_spawned + role_offset)
		var variant_index := _allocate_role_variant(String(selected_profile.role_id), actor.stable_id, generation)
		actor.add_to_group("active_enemies")
		actor.activate(selected_profile, player, position, generation, neighbor_registry, self, variant_index)
		spawned_total += 1
		_wave_spawned += 1
		_spawn_cursor = (lane_index + 1) % LANES.size()
		last_spawn_receipt = {
			"stable_id": String(actor.stable_id), "generation": generation,
			"role_id": String(selected_profile.role_id), "lane_index": lane_index,
			"variant_index":variant_index, "variant_id":actor.model_pivot.variant_id,
			"position": position, "validation": validation,
		}
		_emit_snapshot()
		return true
	_spawn_cursor = (_spawn_cursor + 1) % LANES.size()
	return false

func _allocate_role_variant(role_id: String, stable_id: StringName, generation: int) -> int:
	var ordinal := int(_role_variant_cursor.get(role_id, 0))
	var variant_index := ordinal % 2
	_role_variant_cursor[role_id] = ordinal + 1
	var counts: Dictionary = _role_variant_allocations.get(role_id, {"variant_a":0, "variant_b":0})
	var key := "variant_a" if variant_index == 0 else "variant_b"
	counts[key] = int(counts.get(key, 0)) + 1
	_role_variant_allocations[role_id] = counts
	_variant_assignment_by_actor["%s.g%08d" % [String(stable_id), generation]] = {
		"role_id":role_id, "ordinal":ordinal, "variant_index":variant_index,
		"variant":"a" if variant_index == 0 else "b",
	}
	return variant_index

func prepare_validation_density(target_live: int) -> Dictionary:
	if not OS.has_feature("editor") or not active:
		return {"accepted": false, "reason": "release_guard_or_inactive"}
	var bounded_target := clampi(target_live, 1, live_cap)
	if _active_count() > bounded_target:
		_reconcile_to_cap(bounded_target, "validation_density_checkpoint")
	var attempts := 0
	while _active_count() < bounded_target and _wave_spawned < _spawn_budget and attempts < pool_size * 3:
		_spawn_one(_wave_spawned)
		attempts += 1
	# A validation checkpoint is inspectable, not a request to resume wave
	# growth immediately after preparation. The next wave/checkpoint setup
	# restores its authored cap through configure_pressure().
	live_cap = bounded_target
	_resolve_telegraph_admissions()
	_update_light_budget()
	return {"accepted": _active_count() >= bounded_target, "target": bounded_target,
		"live": _active_count(), "attempts": attempts, "cap": live_cap}

func begin_validation_profile_cohort(target_live: int, setup_generation: int) -> Dictionary:
	if not OS.has_feature("editor") or not active:
		return {"accepted":false,"reason":"release_guard_or_inactive"}
	_validation_cohort_active = true
	_validation_cohort_target = clampi(target_live, 1, mini(live_cap, pool_size))
	_validation_cohort_generation = setup_generation
	_validation_cohort_start_live = _active_count()
	_validation_cohort_minimum_live = _validation_cohort_start_live
	_validation_cohort_replenished = 0
	_validation_cohort_deaths = 0
	_validation_cohort_maintenance_ticks = 0
	_maintain_validation_profile_cohort()
	_validation_cohort_last_receipt = get_validation_profile_cohort_snapshot()
	return _validation_cohort_last_receipt.duplicate(true)

func end_validation_profile_cohort(reason: String) -> Dictionary:
	if not _validation_cohort_active:
		return _validation_cohort_last_receipt.duplicate(true)
	_maintain_validation_profile_cohort()
	_validation_cohort_last_receipt = get_validation_profile_cohort_snapshot()
	_validation_cohort_last_receipt["active"] = false
	_validation_cohort_last_receipt["end_reason"] = reason
	_validation_cohort_last_receipt["end_live"] = _active_count()
	_validation_cohort_active = false
	return _validation_cohort_last_receipt.duplicate(true)

func _maintain_validation_profile_cohort() -> void:
	if not _validation_cohort_active or not OS.has_feature("editor") or not active:
		return
	_validation_cohort_maintenance_ticks += 1
	var attempts := 0
	while _active_count() < _validation_cohort_target and attempts < pool_size:
		# Diagnostic cohort admission intentionally bypasses only the authored
		# wave spawn budget. It uses the same pool, spawn validation, role roster,
		# combat actor and reward lifecycle as production spawning.
		if not _spawn_one(_wave_spawned):
			break
		_validation_cohort_replenished += 1
		attempts += 1
	_validation_cohort_minimum_live = mini(_validation_cohort_minimum_live, _active_count())

func get_validation_profile_cohort_snapshot() -> Dictionary:
	return {
		"active":_validation_cohort_active,
		"setup_generation":_validation_cohort_generation,
		"requested":_validation_cohort_target,
		"start":_validation_cohort_start_live,
		"minimum":_validation_cohort_minimum_live,
		"current":_active_count(),
		"replenished":_validation_cohort_replenished,
		"combat_deaths":_validation_cohort_deaths,
		"maintenance_ticks":_validation_cohort_maintenance_ticks,
		"pool_size":pool_size,
		"wave_budget_bypass_only":true,
		"combat_causality_preserved":true,
	}

func _select_profile(sequence_index: int) -> EnemyProfile:
	if profiles.is_empty():
		return null
	if OS.has_feature("editor") and not _validation_role_sequence.is_empty():
		var requested_role := _validation_role_sequence[_wave_spawned % _validation_role_sequence.size()]
		for candidate in profiles:
			if String(candidate.role_id) == requested_role:
				return candidate
	if _elite_every > 0 and _wave_spawned > 0 and _wave_spawned % _elite_every == 0:
		for candidate in profiles:
			if String(candidate.role_id) == "grave_brute":
				return candidate
	var total_weight := 0
	for candidate in profiles:
		total_weight += maxi(0, int(_composition_weights.get(String(candidate.role_id), 0)))
	if total_weight <= 0:
		return profiles[sequence_index % profiles.size()]
	var cursor := sequence_index % total_weight
	for candidate in profiles:
		var weight := maxi(0, int(_composition_weights.get(String(candidate.role_id), 0)))
		if cursor < weight:
			return candidate
		cursor -= weight
	return profiles[0]

func configure_validation_roster(role_sequence: Array) -> void:
	if OS.has_feature("editor"):
		_validation_role_sequence.clear()
		for role in role_sequence:
			_validation_role_sequence.append(String(role))

func clear_validation_roster() -> void:
	_validation_role_sequence.clear()

func _reconcile_to_cap(target_cap: int, reason: String) -> void:
	_reconciliation_serial += 1
	var retired: Array[String] = []
	for index in range(_pool.size() - 1, -1, -1):
		if _active_count() <= target_cap:
			break
		var actor := _pool[index]
		if actor.state == "pooled":
			continue
		var receipt := actor.retire_from_pressure(reason, _reconciliation_serial)
		actor.remove_from_group("active_enemies")
		if not receipt.is_empty():
			retired.append(String(actor.stable_id))
			retired_total += 1
	last_reconciliation_receipt = {
		"reconciliation_id": _reconciliation_serial,
		"reason": reason,
		"target_cap": target_cap,
		"retired_ids": retired,
		"retired_count": retired.size(),
		"live_after": _active_count(),
		"defeats_added": 0,
		"rewards_added": 0,
	}
	_emit_snapshot()

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
	return _live_count

func request_telegraph_admission(actor: EnemyActor) -> bool:
	if not active or not is_instance_valid(actor) or actor.state in ["pooled", "death"]:
		return false
	var key := _actor_key(actor)
	if _telegraph_owners.has(key):
		return true
	if not _telegraph_waiting.has(key):
		_telegraph_waiting[key] = actor
		_cue_requested_total += 1
	return false

func has_telegraph_admission(actor: EnemyActor) -> bool:
	return is_instance_valid(actor) and _telegraph_owners.get(_actor_key(actor)) == actor

func release_telegraph_admission(actor: EnemyActor, reason: String) -> void:
	if not is_instance_valid(actor):
		return
	var key := _actor_key(actor)
	var released_owner := _telegraph_owners.erase(key)
	var released_waiter := _telegraph_waiting.erase(key)
	if released_owner or released_waiter:
		_cue_released_total += 1
		_last_cue_release = {"stable_id":String(actor.stable_id), "generation":actor.spawn_generation, "reason":reason}

func _resolve_telegraph_admissions() -> void:
	_prune_actor_map(_telegraph_owners)
	_prune_actor_map(_telegraph_waiting)
	var keys: Array = _telegraph_waiting.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for key in keys:
		if _telegraph_owners.size() >= telegraph_cue_cap:
			break
		var actor: EnemyActor = _telegraph_waiting.get(key)
		if not is_instance_valid(actor):
			continue
		_telegraph_waiting.erase(key)
		_telegraph_owners[key] = actor
		_cue_admitted_total += 1
	_cue_peak_admitted = maxi(_cue_peak_admitted, _telegraph_owners.size())

func _update_light_budget() -> void:
	_light_budget_update_count += 1
	var active_actors: Array[EnemyActor] = []
	var hurt_requested := 0
	for actor in _pool:
		if actor.state in ["pooled", "death"]:
			continue
		active_actors.append(actor)
		if actor.has_hurt_light_request():
			hurt_requested += 1
	_role_light_owners = _select_light_owners(active_actors, role_light_cap, _role_light_owners, false)
	_hurt_light_owners = _select_light_owners(active_actors, hurt_light_cap, _hurt_light_owners, true)
	for actor in _pool:
		var key := _actor_key(actor)
		actor.set_light_budget(_role_light_owners.has(key), _hurt_light_owners.has(key))
	var requested := active_actors.size() + hurt_requested
	var active_lights := _role_light_owners.size() + _hurt_light_owners.size()
	_light_peak_requested = maxi(_light_peak_requested, requested)
	_light_peak_active = maxi(_light_peak_active, active_lights)

func _select_light_owners(candidates: Array[EnemyActor], cap: int, previous: Dictionary, hurt_only: bool) -> Dictionary:
	if cap <= 0:
		return {}
	var eligible: Array[EnemyActor] = []
	for actor in candidates:
		if not hurt_only or actor.has_hurt_light_request():
			eligible.append(actor)
	eligible.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		var a_priority := _light_priority(a, previous.has(_actor_key(a)), hurt_only)
		var b_priority := _light_priority(b, previous.has(_actor_key(b)), hurt_only)
		if a_priority != b_priority:
			return a_priority < b_priority
		return _actor_key(a) < _actor_key(b)
	)
	var selected: Dictionary = {}
	for index in range(mini(cap, eligible.size())):
		var actor := eligible[index]
		selected[_actor_key(actor)] = actor
	return selected

func _light_priority(actor: EnemyActor, was_selected: bool, hurt_only: bool) -> int:
	var state_priority := 0
	if not hurt_only:
		match actor.state:
			"telegraph": state_priority = -100
			"waiting_admission": state_priority = -70
			"damage": state_priority = -45
			_: state_priority = 0
	var distance_bucket := int(actor.global_position.distance_to(player.global_position) * 2.0) if is_instance_valid(player) else 100
	return state_priority + distance_bucket - (18 if was_selected else 0)

func _prune_actor_map(actor_map: Dictionary) -> void:
	for key in actor_map.keys():
		var actor: EnemyActor = actor_map.get(key)
		if not is_instance_valid(actor) or actor.state in ["pooled", "death"] or _actor_key(actor) != String(key):
			actor_map.erase(key)

func _actor_key(actor: EnemyActor) -> String:
	return "%s.g%08d" % [String(actor.stable_id), actor.spawn_generation]

func _on_enemy_defeated(actor: EnemyActor, event: Dictionary) -> void:
	defeated_total += 1
	if _validation_cohort_active:
		_validation_cohort_deaths += 1
	var report := event.duplicate(true)
	report.stable_id = String(actor.stable_id)
	report.role_id = String(actor.profile.role_id)
	enemy_defeated.emit(report)
	_emit_snapshot()
	var defeated_generation := actor.spawn_generation
	var tween := create_tween()
	tween.tween_interval(0.78)
	tween.tween_callback(func() -> void:
		if not is_instance_valid(actor) or actor.spawn_generation != defeated_generation or actor.state != "death":
			return
		actor.remove_from_group("active_enemies")
		actor.return_to_pool()
		# The real death and reward transaction is complete before the same
		# authoritative pool boundary admits its deterministic replacement.
		_maintain_validation_profile_cohort()
		_emit_snapshot()
	)

func _on_reward_dropped(event: Dictionary) -> void:
	reward_dropped.emit(event)

func _on_lifecycle_event(event: Dictionary) -> void:
	last_lifecycle_event = event.duplicate(true)
	match String(event.get("phase", "")):
		"spawn": _live_count = mini(pool_size, _live_count + 1)
		"pool_return": _live_count = maxi(0, _live_count - 1)
	if active and String(event.get("phase", "")) in ["spawn", "telegraph", "damage", "hurt", "death", "pool_return", "retired"]:
		_update_light_budget()
		_light_budget_refresh_remaining = LIGHT_BUDGET_REFRESH_SECONDS
	enemy_lifecycle.emit(last_lifecycle_event)

func get_profile_counters() -> Dictionary:
	var neighbor := neighbor_registry.get_snapshot() if is_instance_valid(neighbor_registry) else {}
	return {
		"live":_live_count,
		"pooled":pool_size - _live_count,
		"telegraph_active":_telegraph_owners.size(),
		"telegraph_waiting":_telegraph_waiting.size(),
		"role_lights":_role_light_owners.size(),
		"hurt_lights":_hurt_light_owners.size(),
		"active_lights":_role_light_owners.size() + _hurt_light_owners.size(),
		"neighbor_candidate_visits":int(neighbor.get("candidate_visits", 0)),
		"registered_neighbors":int(neighbor.get("registered_count", 0)),
		"counter_source":"encounter_lifecycle_owners",
	}

func _emit_snapshot() -> void:
	encounter_changed.emit(get_snapshot())

func get_snapshot() -> Dictionary:
	var roles: Dictionary = {}
	var role_variants: Dictionary = {}
	var hurt_requested := 0
	var role_active := 0
	var hurt_active := 0
	var role_owner_keys: Array[String] = []
	var hurt_owner_keys: Array[String] = []
	var presentation_updates := 0
	var presentation_skips := 0
	var presentation_priority_updates := 0
	var facing_updates := 0
	var facing_skips := 0
	var manual_animation_players := 0
	for actor in _pool:
		if actor.state == "pooled" or not actor.profile:
			continue
		var role := String(actor.profile.role_id)
		roles[role] = int(roles.get(role, 0)) + 1
		var variant_counts: Dictionary = role_variants.get(role, {"variant_a":0, "variant_b":0})
		var variant_key := "variant_b" if String(actor.model_pivot.variant_id).ends_with("variant_b") else "variant_a"
		variant_counts[variant_key] = int(variant_counts.get(variant_key, 0)) + 1
		role_variants[role] = variant_counts
		if actor.has_hurt_light_request():
			hurt_requested += 1
		if actor.is_role_light_active():
			role_active += 1
			role_owner_keys.append(_actor_key(actor))
		if actor.is_hurt_light_active():
			hurt_active += 1
			hurt_owner_keys.append(_actor_key(actor))
		var presentation_budget := actor.get_presentation_budget_snapshot()
		presentation_updates += int(presentation_budget.get("updates", 0))
		presentation_skips += int(presentation_budget.get("skips", 0))
		presentation_priority_updates += int(presentation_budget.get("priority_updates", 0))
		facing_updates += int(presentation_budget.get("facing_updates", 0))
		facing_skips += int(presentation_budget.get("facing_skips", 0))
		if bool(presentation_budget.get("manual_animation", false)):
			manual_animation_players += 1
	var role_requested := _active_count()
	var light_requested := role_requested + hurt_requested
	var light_active := role_active + hurt_active
	return {
		"encounter_id": encounter_id, "active": active, "live": _active_count(),
		"cap": live_cap, "spawned": spawned_total, "defeated": defeated_total,
		"pooled": pool_size - _active_count(), "roles": roles,
		"role_variants":role_variants,
		"role_variant_allocations":_role_variant_allocations.duplicate(true),
		"variant_assignment_by_actor":_variant_assignment_by_actor.duplicate(true),
		"variant_balance":_variant_balance_receipt(role_variants),
		"validation_roster_active":not _validation_role_sequence.is_empty(),
		"validation_roster_size":_validation_role_sequence.size(),
		"validation_profile_cohort":get_validation_profile_cohort_snapshot() if _validation_cohort_active else _validation_cohort_last_receipt.duplicate(true),
		"rejected_spawns": rejected_spawn_count, "last_spawn_receipt": last_spawn_receipt,
		"last_lifecycle_event": last_lifecycle_event,
		"wave_id": _wave_id, "wave_spawned": _wave_spawned, "spawn_budget": _spawn_budget,
		"composition_weights": _composition_weights, "elite_every": _elite_every,
		"retired": retired_total, "last_reconciliation": last_reconciliation_receipt,
		"neighbor_registry": neighbor_registry.get_snapshot() if is_instance_valid(neighbor_registry) else {},
		"telegraph_admission": {
			"cap":telegraph_cue_cap, "requested_total":_cue_requested_total,
			"admitted_total":_cue_admitted_total, "waiting":_telegraph_waiting.size(),
			"active":_telegraph_owners.size(), "released_total":_cue_released_total,
			"peak_active":_cue_peak_admitted, "owners":_telegraph_owners.keys(),
			"waiting_keys":_telegraph_waiting.keys(), "last_release":_last_cue_release,
		},
		"ordinary_light_budget": {
			"role_cap":role_light_cap, "hurt_cap":hurt_light_cap,
			"requested":light_requested, "active":light_active,
			"suppressed":maxi(0, light_requested - light_active),
			"peak_requested":_light_peak_requested, "peak_active":_light_peak_active,
			"role":{"requested":role_requested, "active":role_active, "suppressed":maxi(0, role_requested - role_active), "owners":role_owner_keys},
			"hurt":{"requested":hurt_requested, "active":hurt_active, "suppressed":maxi(0, hurt_requested - hurt_active), "owners":hurt_owner_keys},
		},
		"dense_presentation_budget": {
			"family":"staggered_authored_animation",
			"approach_bucket_count":EnemySemanticPresenter.DENSE_APPROACH_ANIMATION_BUCKETS,
			"manual_animation_players":manual_animation_players,
			"updates":presentation_updates,
			"skips":presentation_skips,
			"priority_updates":presentation_priority_updates,
			"facing_updates":facing_updates,
			"facing_skips":facing_skips,
			"danger_states_unstaggered":true,
			"light_budget_refresh_seconds":LIGHT_BUDGET_REFRESH_SECONDS,
			"light_budget_updates":_light_budget_update_count,
			"light_budget_skipped_frames":_light_budget_skipped_frames,
		},
	}

func _variant_balance_receipt(role_variants: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for role in role_variants:
		var counts: Dictionary = role_variants[role]
		var a := int(counts.get("variant_a", 0))
		var b := int(counts.get("variant_b", 0))
		var total := a + b
		result[role] = {
			"variant_a":a, "variant_b":b, "total":total,
			"difference":absi(a-b),
			"maximum_single_variant_share":(float(maxi(a,b)) / float(total)) if total > 0 else 0.0,
			"within_release_ceiling":total >= 2 and float(maxi(a,b)) / float(total) <= 0.75,
		}
	return result

func _mcp_state() -> Dictionary:
	var snapshot := get_snapshot()
	var presentation: Dictionary = snapshot.get("dense_presentation_budget", {})
	var neighbors: Dictionary = snapshot.get("neighbor_registry", {})
	return {
		"active":snapshot.get("active", false), "live":snapshot.get("live", 0),
		"pooled":snapshot.get("pooled", 0), "cap":snapshot.get("cap", 0),
		"presentation_updates":presentation.get("updates", 0),
		"presentation_skips":presentation.get("skips", 0),
		"presentation_priority_updates":presentation.get("priority_updates", 0),
		"facing_updates":presentation.get("facing_updates", 0),
		"facing_skips":presentation.get("facing_skips", 0),
		"light_budget_updates":presentation.get("light_budget_updates", 0),
		"light_budget_skipped_frames":presentation.get("light_budget_skipped_frames", 0),
		"neighbor_queries":neighbors.get("query_count", 0),
		"neighbor_candidate_visits":neighbors.get("candidate_visits", 0),
		"neighbor_candidate_budget":neighbors.get("candidate_budget", 0),
		"neighbor_stable_order_cache_size":neighbors.get("stable_order_cache_size", 0),
		"roles":snapshot.get("roles", {}),
		"role_variants":snapshot.get("role_variants", {}),
		"variant_balance":snapshot.get("variant_balance", {}),
		"telegraph_admission":snapshot.get("telegraph_admission", {}),
		"ordinary_light_budget":snapshot.get("ordinary_light_budget", {}),
		"dense_presentation_budget":snapshot.get("dense_presentation_budget", {}),
		"neighbor_registry":snapshot.get("neighbor_registry", {}),
		"validation_profile_cohort":snapshot.get("validation_profile_cohort", {}),
		"last_lifecycle_event":snapshot.get("last_lifecycle_event", {}),
	}
