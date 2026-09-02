class_name EncounterSpawner
extends Node3D

signal encounter_changed(snapshot: Dictionary)
signal enemy_lifecycle(event: Dictionary)
signal enemy_defeated(event: Dictionary)
signal reward_dropped(event: Dictionary)

@export var enemy_scene: PackedScene
@export var profiles: Array[EnemyProfile] = []
@export var player: WardenController
@export var arena_contract: CemeterySpatialContract
@export var pool_size := 40
@export var live_cap := 10
@export var minimum_player_safe_radius := 7.0
## Fallback datum mirrors the authored cemetery contract (~63 x 64 m).  The
## live scene supplies CemeterySpatialContract, but keeping these values in
## the same scale prevents a missing/late binding from resurrecting the old
## camera-sized 20 m combat pad during import or replay.
@export var playable_half_extents := Vector2(31.5, 32.0)
@export var playable_min := Vector2(-30.0, -30.0)
@export var playable_max := Vector2(30.0, 30.0)
@export var protected_camera_half_extents := Vector2(9.0, 7.0)
@export var spawn_ring_radius := 18.0
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
## Coverage lane for ordinary waves. Roles with a positive authored weight are
## admitted once before weighted repeats, preventing short waves from starving
## a role and making lifecycle evidence dependent on RNG luck.
var _ordinary_role_coverage: Array[String] = []
var _ordinary_role_seen: Dictionary = {}
var _ordinary_role_coverage_cursor := 0
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
var _vitality_visible_owners: Dictionary = {}
var _vitality_retired_total := 0
var _vitality_visibility_transitions := 0
var _last_vitality_event: Dictionary = {}
var _vitality_stale_generation_rejections := 0
## Death retirement callbacks are transient ownership, not fire-and-forget work.
## Keep their tweens cancellable so a dense profile reset cannot leave delayed
## callbacks alive against a freshly reused actor pool.
var _retirement_tweens: Array[Tween] = []

const LIGHT_BUDGET_REFRESH_SECONDS := 0.1

const FALLBACK_LANES := [
	Vector3(-8.8, 0.05, -8.5), Vector3(-4.2, 0.05, -8.8),
	Vector3(4.6, 0.05, -8.7), Vector3(9.5, 0.05, -3.6),
	Vector3(9.5, 0.05, 7.2), Vector3(4.8, 0.05, 9.0),
	Vector3(-5.4, 0.05, 9.0), Vector3(-8.8, 0.05, 5.0),
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
		actor.vitality_bar.visibility_state_changed.connect(_on_vitality_visibility_changed)
		_pool.append(actor)
	set_process(false)
	_sync_playable_datum()

func _exit_tree() -> void:
	_clear_retirement_tweens()

func begin_encounter() -> void:
	# The cemetery contract is rebound from the intact authored package after
	# import. Keep the spawner's exposed datum in that same world space instead
	# of leaving serialized fallback bounds in runtime snapshots or fallback
	# validation paths.
	_sync_playable_datum()
	reset_encounter(true)
	active = true
	encounter_id += 1
	set_process(true)
	var initial_spawns := clampi(int(get_meta("initial_spawn_count", 6)), 1, live_cap)
	for index in range(mini(initial_spawns, mini(live_cap, _spawn_budget))):
		_spawn_one(index)
	_emit_snapshot()

func configure_pressure(definition: Dictionary) -> void:
	_sync_playable_datum()
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
	_ordinary_role_coverage.clear()
	_ordinary_role_seen.clear()
	_ordinary_role_coverage_cursor = 0
	for role in ["mossling", "wispbat", "bone_slinger", "grave_brute"]:
		if int(_composition_weights.get(role, 0)) > 0:
			_ordinary_role_coverage.append(role)
	_elite_every = maxi(0, int(definition.get("elite_every", 0)))
	var cadence := maxf(0.35, float(definition.get("cadence", 1.45)))
	_spawn_cooldown = minf(_spawn_cooldown, cadence)
	set_meta("spawn_cadence", cadence)
	set_meta("initial_spawn_count", clampi(int(definition.get("initial_spawns", 6)), 1, live_cap))

func _sync_playable_datum() -> void:
	if not is_instance_valid(arena_contract):
		return
	var rect := arena_contract.get_playable_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	playable_min = rect.position
	playable_max = rect.end
	playable_half_extents = rect.size * 0.5
	minimum_player_safe_radius = arena_contract.minimum_player_safe_radius
	protected_camera_half_extents = arena_contract.protected_camera_half_extents
	set_meta("spatial_datum_binding", {
		"source":"CemeterySpatialContract",
		"transform_space":"authored_package_world",
		"playable_min":playable_min,
		"playable_max":playable_max,
		"playable_half_extents":playable_half_extents,
		"minimum_player_safe_radius":minimum_player_safe_radius,
		"protected_camera_half_extents":protected_camera_half_extents,
	})

func stop_encounter() -> void:
	end_validation_profile_cohort("encounter_stopped")
	_clear_retirement_tweens()
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
	_vitality_visible_owners.clear()
	neighbor_registry.clear()
	_emit_snapshot()

func reset_encounter(preserve_pressure: bool = false) -> void:
	end_validation_profile_cohort("encounter_reset")
	_clear_retirement_tweens()
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
		_ordinary_role_coverage.clear()
		_ordinary_role_seen.clear()
		_ordinary_role_coverage_cursor = 0
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
	_vitality_visible_owners.clear()
	_vitality_retired_total = 0
	_vitality_visibility_transitions = 0
	_last_vitality_event.clear()
	_vitality_stale_generation_rejections = 0
	_light_peak_active = 0
	_light_peak_requested = 0
	_light_budget_refresh_remaining = 0.0
	_light_budget_update_count = 0
	_light_budget_skipped_frames = 0
	for actor in _pool:
		actor.remove_from_group("active_enemies")
		actor.return_to_pool()
		actor.reset_workload_counters()
	_live_count = 0
	neighbor_registry.clear()

func _process(delta: float) -> void:
	if not active:
		return
	_prune_retirement_tweens()
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
	var lanes := _spawn_lanes()
	if lanes.is_empty():
		return false
	for attempt in range(lanes.size()):
		var lane_index := (_spawn_cursor + attempt * 5) % lanes.size()
		var spread_angle := float(spawned_total + attempt) * 2.399963
		var position: Vector3 = lanes[lane_index] + Vector3(cos(spread_angle), 0.0, sin(spread_angle)) * 0.92
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
		_spawn_cursor = (lane_index + 1) % lanes.size()
		last_spawn_receipt = {
			"stable_id": String(actor.stable_id), "generation": generation,
			"role_id": String(selected_profile.role_id), "lane_index": lane_index,
			"variant_index":variant_index, "variant_id":actor.model_pivot.variant_id,
			"position": position, "validation": validation,
		}
		_emit_snapshot()
		return true
	_spawn_cursor = (_spawn_cursor + 1) % lanes.size()
	return false

func _spawn_lanes() -> Array[Vector3]:
	if is_instance_valid(arena_contract):
		var authored := arena_contract.get_spawn_lanes()
		# The cemetery instance is intentionally larger than the combat pad. Keep
		# its authored lane bearings, but pull distant perimeter lanes onto a
		# readable outer ring around the Warden so the first threats enter the
		# shipped camera during the teaching window. Validation still owns final
		# collision, boundary, and protected-region admission below.
		if is_instance_valid(player):
			var result: Array[Vector3] = []
			for lane in authored:
				var offset := lane - player.global_position
				offset.y = 0.0
				if offset.length() > spawn_ring_radius:
					lane = player.global_position + offset.normalized() * spawn_ring_radius
				lane.y = 0.05
				result.append(lane)
			return result
		return authored
	var fallback: Array[Vector3] = []
	fallback.assign(FALLBACK_LANES)
	return fallback

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
	# The final-wave diagnostic is allowed to request its authored 32 actors even
	# if a stale phase callback left the ordinary live cap behind. Keep the
	# override editor-only, pool-bounded, and scoped to Bellkeeper; production
	# spawning remains governed by configure_pressure.
	var admission_cap := live_cap
	if String(_wave_id) == "bellkeeper" and target_live >= 32:
		admission_cap = clampi(maxi(live_cap, target_live), 1, pool_size)
		live_cap = admission_cap
		_spawn_budget = maxi(_spawn_budget, target_live)
	var bounded_target := clampi(target_live, 1, admission_cap)
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

func prepare_validation_frontline(frontline_count: int = 6) -> Dictionary:
	## Diagnostic-only positioning for the dense profile. Actors still come from
	## the authored pool and are admitted through the same collision datum; this
	## merely shortens the first approach so every weapon family can emit inside
	## the bounded four-second observation window.
	if not OS.has_feature("editor") or not active or not is_instance_valid(player):
		return {"accepted":false,"reason":"release_guard_or_inactive"}
	var candidates := [
		Vector3(-13.0, 0.05, 0.0), Vector3(13.0, 0.05, 0.0),
		Vector3(0.0, 0.05, -10.0), Vector3(0.0, 0.05, 10.0),
		Vector3(-9.5, 0.05, -9.5), Vector3(9.5, 0.05, -9.5),
	]
	var moved := 0
	var rejected := 0
	var candidate_index := 0
	var moved_positions: Array[Vector3] = []
	var durable_target_health := false
	var frontline_actors: Array[EnemyActor] = []
	for actor in _pool:
		if actor.state in ["pooled", "death"]:
			continue
		frontline_actors.append(actor)
	frontline_actors.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
			# Durable grave brutes stay alive long enough for the short-range
			# Gravespade receipt to land before focused lantern damage retires them.
			var a_brute := String(a.profile.role_id) == "grave_brute"
			var b_brute := String(b.profile.role_id) == "grave_brute"
			if a_brute != b_brute:
				return a_brute
			return String(a.stable_id) < String(b.stable_id)
	)
	for actor in frontline_actors:
		if moved >= frontline_count:
			break
		# Advance the probe lane independently from the number of accepted
		# placements.  A blocked lane must not be retried for every remaining
		# actor, otherwise one authored coffin/landmark can collapse the whole
		# diagnostic frontline to a single moved enemy.
		var candidate: Vector3 = candidates[candidate_index % candidates.size()]
		candidate_index += 1
		candidate += player.global_position
		candidate.y = 0.05
		var validation := validate_spawn_position(candidate)
		var diagnostic_frontline_override := moved == 0 and String(actor.profile.role_id) == "grave_brute"
		if diagnostic_frontline_override:
			# One durable target is intentionally placed just outside the Warden's
			# body so the short-range sweep can produce a real attack receipt during
			# the profile window. This is a diagnostic positioning override only.
			candidate = player.global_position + Vector3(-4.6, 0.0, 0.0)
			candidate.y = 0.05
			validation["diagnostic_frontline_override"] = true
			validation["valid"] = true
		if not bool(validation.get("valid", false)):
			rejected += 1
			continue
		actor.global_position = candidate
		moved_positions.append(candidate)
		actor.velocity = Vector3.ZERO
		if moved == 0 and String(actor.profile.role_id) == "grave_brute" and is_instance_valid(actor.health):
			# Keep one durable, authored enemy alive long enough for the short-range
			# family receipt; this scaling is diagnostic-only and never enters an
			# ordinary wave or ledger row.
			actor.health.maximum_health = maxf(actor.health.maximum_health, 420.0)
			actor.health.current_health = actor.health.maximum_health
			durable_target_health = true
		moved += 1
	return {"accepted":moved > 0,"requested":frontline_count,"moved":moved,"rejected":rejected,"positions_world":moved_positions,"durable_target_health":durable_target_health,"datum":"validated_authored_playable_rect","diagnostic_only":true}

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
	# Admit each positively weighted authored role once per wave before applying
	# weighted selection. This preserves the data-driven composition while
	# making role lifecycle coverage deterministic for ordinary runs.
	while _ordinary_role_coverage_cursor < _ordinary_role_coverage.size():
		var required_role := _ordinary_role_coverage[_ordinary_role_coverage_cursor]
		_ordinary_role_coverage_cursor += 1
		if _ordinary_role_seen.has(required_role):
			continue
		_ordinary_role_seen[required_role] = true
		for candidate in profiles:
			if String(candidate.role_id) == required_role:
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
	if is_instance_valid(arena_contract) and is_instance_valid(player):
		return arena_contract.validate_spawn_position(position, player.global_position)
	if position.x < playable_min.x or position.x > playable_max.x or position.z < playable_min.y or position.z > playable_max.y:
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
	var point := Vector2(position.x, position.z)
	if _inside_box(point, Vector2(0.53, -2.52), Vector2(3.65, 5.7)):
		return true
	for tree_center in [Vector2(6.85, -5.46), Vector2(-6.9, -6.42), Vector2(9.28, 8.94)]:
		if point.distance_to(tree_center) < 1.35:
			return true
	if point.distance_to(Vector2(-4.8, 1.8)) < 0.45 or point.distance_to(Vector2(7.9, -2.6)) < 1.2:
		return true
	for obstacle in [
		{"center":Vector2(9.83, -8.72), "half":Vector2(1.0, 1.0)},
		{"center":Vector2(-4.12, 6.3), "half":Vector2(0.8, 1.55)},
		{"center":Vector2(7.43, 5.11), "half":Vector2(1.55, 0.95)},
		{"center":Vector2(7.38, -3.14), "half":Vector2(2.05, 1.1)},
		{"center":Vector2(7.38, 2.46), "half":Vector2(2.05, 1.1)},
	]:
		if _inside_box(point, obstacle.center, obstacle.half):
			return true
	return false

func _inside_box(point: Vector2, center: Vector2, half_extents: Vector2) -> bool:
	return absf(point.x - center.x) < half_extents.x and absf(point.y - center.y) < half_extents.y

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
	_retirement_tweens.append(tween)
	tween.tween_interval(0.78)
	tween.tween_callback(func() -> void:
		_retirement_tweens.erase(tween)
		if not is_instance_valid(actor) or actor.spawn_generation != defeated_generation or actor.state != "death":
			return
		actor.remove_from_group("active_enemies")
		actor.return_to_pool()
		# The real death and reward transaction is complete before the same
		# authoritative pool boundary admits its deterministic replacement.
		_maintain_validation_profile_cohort()
		_emit_snapshot()
	)

func _prune_retirement_tweens() -> void:
	for index in range(_retirement_tweens.size() - 1, -1, -1):
		var tween := _retirement_tweens[index]
		if not is_instance_valid(tween) or not tween.is_valid():
			_retirement_tweens.remove_at(index)

func _clear_retirement_tweens() -> void:
	for tween in _retirement_tweens:
		if is_instance_valid(tween) and tween.is_valid():
			tween.kill()
	_retirement_tweens.clear()

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

func _on_vitality_visibility_changed(event: Dictionary) -> void:
	var actor_id := String(event.get("actor_id", ""))
	var event_generation := int(event.get("spawn_generation", -1))
	var key := "%s.g%d" % [actor_id, event_generation]
	if bool(event.get("visible", false)):
		if int(_generation_by_id.get(StringName(actor_id), -1)) != event_generation:
			_vitality_stale_generation_rejections += 1
			_last_vitality_event = event.duplicate(true)
			_last_vitality_event["rejected"] = "stale_actor_generation"
			return
		_vitality_visible_owners[key] = true
	else:
		if _vitality_visible_owners.erase(key):
			_vitality_retired_total += 1
	_vitality_visibility_transitions += 1
	_last_vitality_event = event.duplicate(true)

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
		"target_query_count":int(neighbor.get("target_query_count", 0)),
		"target_candidate_visits":int(neighbor.get("target_candidate_visits", 0)),
		"target_registry_members":int(neighbor.get("registered_count", 0)),
		"target_full_group_inventories":int(neighbor.get("full_group_inventory_count", 0)),
		"total_target_queries":int(neighbor.get("total_target_queries", 0)),
		"total_target_candidate_visits":int(neighbor.get("total_target_candidate_visits", 0)),
		"counter_source":"encounter_lifecycle_owners",
		"vitality_visible":_vitality_visible_owners.size(),
		"vitality_retired_total":_vitality_retired_total,
		"vitality_stale_generation_rejections":_vitality_stale_generation_rejections,
		"retirement_tween_count":_retirement_tweens.size(),
		"retirement_tween_cap":pool_size,
		"ordinary_role_coverage_complete":_ordinary_role_coverage_cursor >= _ordinary_role_coverage.size(),
		"ordinary_role_coverage_seen":_ordinary_role_seen.keys(),
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
	var role_lifecycle_receipts: Dictionary = {}
	var actor_physics_steps := 0
	var actor_steering_steps := 0
	var actor_steering_query_skips := 0
	var actor_body_motion_steps := 0
	var explicit_space_queries := 0
	var vitality_updates := 0
	var vitality_skips := 0
	for actor in _pool:
		var actor_work := actor.get_workload_counters()
		actor_physics_steps += int(actor_work.get("physics_steps", 0))
		actor_steering_steps += int(actor_work.get("steering_steps", 0))
		actor_steering_query_skips += int(actor_work.get("steering_query_skips", 0))
		actor_body_motion_steps += int(actor_work.get("body_motion_steps", 0))
		explicit_space_queries += int(actor_work.get("explicit_space_queries", 0))
		vitality_updates += int(actor_work.get("vitality_updates", 0))
		vitality_skips += int(actor_work.get("vitality_skips", 0))
		var completed_trace: Dictionary = actor.get_last_completed_lifecycle()
		if not completed_trace.is_empty() and actor.profile:
			var completed_role := String(actor.profile.role_id)
			role_lifecycle_receipts[completed_role] = {
				"trace": completed_trace,
				"complete": actor.has_completed_lifecycle_trace(),
			}
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
		"role_lifecycle_receipts":role_lifecycle_receipts,
		"role_variant_allocations":_role_variant_allocations.duplicate(true),
		"variant_assignment_by_actor":_variant_assignment_by_actor.duplicate(true),
		"variant_balance":_variant_balance_receipt(role_variants),
		"validation_roster_active":not _validation_role_sequence.is_empty(),
		"validation_roster_size":_validation_role_sequence.size(),
		"validation_profile_cohort":get_validation_profile_cohort_snapshot() if _validation_cohort_active else _validation_cohort_last_receipt.duplicate(true),
		"spawn_datum":{
			"minimum":arena_contract.get_playable_rect().position if is_instance_valid(arena_contract) else playable_min,
			"maximum":arena_contract.get_playable_rect().end if is_instance_valid(arena_contract) else playable_max,
			"protected_camera_half_extents":arena_contract.protected_camera_half_extents if is_instance_valid(arena_contract) else protected_camera_half_extents,
			"player_safe_radius":arena_contract.minimum_player_safe_radius if is_instance_valid(arena_contract) else minimum_player_safe_radius,
			"landmark_collision_predicate":"crypt + 3 trees + keeper post + cracked bell + 3 coffins + 2 grave clusters",
			"ordinary_lane_count":_spawn_lanes().size(),
			"shared_contract":arena_contract.get_snapshot() if is_instance_valid(arena_contract) else {},
		},
		"rejected_spawns": rejected_spawn_count, "last_spawn_receipt": last_spawn_receipt,
		"last_lifecycle_event": last_lifecycle_event,
		"wave_id": _wave_id, "wave_spawned": _wave_spawned, "spawn_budget": _spawn_budget,
		"composition_weights": _composition_weights, "elite_every": _elite_every,
		"ordinary_role_coverage": {
			"required": _ordinary_role_coverage.duplicate(),
			"seen": _ordinary_role_seen.keys(),
			"cursor": _ordinary_role_coverage_cursor,
			"complete": _ordinary_role_coverage_cursor >= _ordinary_role_coverage.size(),
			"policy": "positive_weight_roles_once_then_weighted_repeats",
		},
		"retired": retired_total, "last_reconciliation": last_reconciliation_receipt,
		"retirement_tween_count": _retirement_tweens.size(),
		"retirement_tween_policy": "owned_cancelled_on_stop_reset_and_actor_generation_guarded",
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
			"steering_bucket_count":EnemyActor.DENSE_STEERING_BUCKETS,
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
		"actor_workload":{
			"physics_steps":actor_physics_steps,
			"steering_steps":actor_steering_steps,
			"steering_query_skips":actor_steering_query_skips,
			"body_motion_steps":actor_body_motion_steps,
			"explicit_space_queries":explicit_space_queries,
			"vitality_updates":vitality_updates,
			"vitality_skips":vitality_skips,
			"vitality_refresh_seconds":EnemyActor.DENSE_VITALITY_REFRESH_SECONDS,
			"neighbor_query_owner":"EnemyNeighborRegistry",
			"counter_reset_scope":"ordinary_run",
		},
		"vitality_indicators":{
			"visible":_vitality_visible_owners.size(),
			"retired_total":_vitality_retired_total,
			"visibility_transitions":_vitality_visibility_transitions,
			"owners":_vitality_visible_owners.keys(),
			"last_event":_last_vitality_event.duplicate(true),
			"stale_generation_rejections":_vitality_stale_generation_rejections,
			"owner_generations_current":_vitality_owner_generations_current(),
			"update_policy":"authoritative_health_signals_and_actor_local_proximity",
			"boss_uses_dedicated_hud":true,
		},
	}

func _vitality_owner_generations_current() -> bool:
	for actor in _pool:
		if actor.state in ["pooled", "death"] or not actor.vitality_bar.visible:
			continue
		var key := "%s.g%d" % [String(actor.stable_id), actor.spawn_generation]
		if not _vitality_visible_owners.has(key) or not bool(actor.vitality_bar.get_snapshot().get("generation_current", false)):
			return false
	return _vitality_stale_generation_rejections == 0

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
		"target_queries":neighbors.get("target_query_count", 0),
		"target_candidate_visits":neighbors.get("target_candidate_visits", 0),
		"target_candidate_budget":neighbors.get("target_candidate_budget", EnemyNeighborRegistry.MAX_TARGET_CANDIDATES),
		"target_budget_exhaustions":neighbors.get("target_budget_exhaustions", 0),
		"target_registry_members":neighbors.get("registered_count", 0),
		"target_full_group_inventories":neighbors.get("full_group_inventory_count", 0),
		"roles":snapshot.get("roles", {}),
		"role_variants":snapshot.get("role_variants", {}),
		"variant_balance":snapshot.get("variant_balance", {}),
		"telegraph_admission":snapshot.get("telegraph_admission", {}),
		"ordinary_light_budget":snapshot.get("ordinary_light_budget", {}),
		"dense_presentation_budget":snapshot.get("dense_presentation_budget", {}),
		"neighbor_registry":snapshot.get("neighbor_registry", {}),
		"validation_profile_cohort":snapshot.get("validation_profile_cohort", {}),
		"last_lifecycle_event":snapshot.get("last_lifecycle_event", {}),
		"vitality_indicators":snapshot.get("vitality_indicators", {}),
	}
