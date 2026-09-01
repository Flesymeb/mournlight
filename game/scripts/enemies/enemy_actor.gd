class_name EnemyActor
extends CharacterBody3D

const DenseProfile := preload("res://scripts/gameplay/dense_profile.gd")

signal lifecycle_event(event: Dictionary)
signal defeated(actor: EnemyActor, event: Dictionary)
signal drop_committed(event: Dictionary)

@export var profile: EnemyProfile
@export var stable_id := &"enemy.pool.00"

@onready var health: HealthComponent = $HealthComponent
@onready var drops: DropTransaction = $DropTransaction
@onready var presentation_root: Node3D = $PresentationRoot
@onready var model_pivot: EnemySemanticPresenter = $PresentationRoot/ModelPivot
@onready var telegraph_ring: MeshInstance3D = $TelegraphRing
@onready var lane_cue: MeshInstance3D = $LaneCue
@onready var hurt_light: OmniLight3D = $HurtLight
@onready var role_glow: OmniLight3D = $RoleGlow
@onready var collider: CollisionShape3D = $Collider
@onready var vitality_bar: EnemyVitalityBar = $EnemyVitalityBar

var target: WardenController
var state := "pooled"
var spawn_generation := 0
var state_remaining := 0.0
var attack_serial := 0
var hurt_count := 0
var death_count := 0
var _lifetime := 0.0
var _flank_sign := 1.0
var _pool_return_pending := false
var retirement_count := 0
var pool_return_rejections := 0
var neighbor_registry: EnemyNeighborRegistry
var encounter_owner: EncounterSpawner
var telegraph_admitted := false
var _hurt_light_remaining := 0.0
var _role_light_active := false
var _hurt_light_active := false
var _facing_bucket := 0
var _facing_updates := 0
var _facing_skips := 0
var _physics_steps_total := 0
var _steering_steps_total := 0
var _body_motion_steps_total := 0
var _steering_query_skips := 0
var _cached_separation := Vector3.ZERO
var _steering_bucket := 0
var _vitality_bucket := 0
var _vitality_refresh_remaining := 0.0
var _vitality_updates := 0
var _vitality_skips := 0
var _priority_presentation_updates := 0
var _staggered_presentation_updates := 0
## Hurt is a presentation interrupt, not a second gameplay state.  Keep the
## authoritative attack/approach state intact while the authored presenter
## runs its short recoil clip, then restore the current semantic deterministically.
var _hurt_motion_remaining := 0.0
var _hurt_motion_count := 0
var _lifecycle_trace: Dictionary = {}
var _last_completed_lifecycle: Dictionary = {}

const DENSE_STEERING_BUCKETS := 3
const DENSE_VITALITY_REFRESH_SECONDS := 0.05

func _ready() -> void:
	add_to_group("mcp_watch")
	health.hurt.connect(_on_hurt)
	health.died.connect(_on_died)
	drops.drop_committed.connect(_on_drop)
	set_physics_process(false)
	visible = false
	collider.disabled = true

func activate(next_profile: EnemyProfile, next_target: WardenController, at_position: Vector3, generation: int, registry: EnemyNeighborRegistry = null, owner: EncounterSpawner = null, presentation_variant_index: int = -1) -> void:
	if is_instance_valid(neighbor_registry):
		neighbor_registry.unregister_actor(stable_id, spawn_generation)
	profile = next_profile
	target = next_target
	spawn_generation = generation
	neighbor_registry = registry
	encounter_owner = owner
	telegraph_admitted = false
	_hurt_light_remaining = 0.0
	_hurt_motion_remaining = 0.0
	_hurt_motion_count = 0
	_lifecycle_trace = {"stable_id":String(stable_id),"role_id":String(profile.role_id),"generation":generation,"spawn":0,"approach":0,"telegraph":0,"damage":0,"hurt":0,"death":0,"drop":0,"pool_return":0}
	_set_light_budget(false, false)
	_lifetime = 0.0
	attack_serial = 0
	hurt_count = 0
	death_count = 0
	_pool_return_pending = false
	pool_return_rejections = 0
	_flank_sign = -1.0 if (String(stable_id).hash() + generation) % 2 == 0 else 1.0
	_facing_bucket = DenseProfile.bucket_for(stable_id, generation, EnemySemanticPresenter.DENSE_APPROACH_ANIMATION_BUCKETS)
	_facing_updates = 0
	_facing_skips = 0
	_steering_query_skips = 0
	_cached_separation = Vector3.ZERO
	_steering_bucket = DenseProfile.bucket_for(stable_id, generation, DENSE_STEERING_BUCKETS)
	_vitality_bucket = DenseProfile.bucket_for(stable_id, generation, DenseProfile.VITALITY_BUCKET_COUNT)
	_vitality_refresh_remaining = 0.0
	_vitality_updates = 0
	_vitality_skips = 0
	_priority_presentation_updates = 0
	_staggered_presentation_updates = 0
	health.actor_id = stable_id
	health.maximum_health = profile.maximum_health
	health.current_health = profile.maximum_health
	health.reset_health()
	vitality_bar.bind_actor(health, stable_id, generation, String(profile.role_id) == "grave_brute")
	drops.reset_transaction()
	global_position = at_position
	velocity = Vector3.ZERO
	presentation_root.scale = Vector3.ONE * profile.presentation_scale
	presentation_root.rotation = Vector3.ZERO
	presentation_root.position = Vector3.ZERO
	model_pivot.configure(String(profile.role_id), profile.accent_color, stable_id, generation, presentation_variant_index)
	_apply_accent(profile.accent_color)
	visible = true
	collider.disabled = false
	add_to_group("combat_targets")
	_set_state("spawn", 0.55)
	set_physics_process(true)
	if is_instance_valid(neighbor_registry):
		neighbor_registry.register_actor(self)
	lifecycle_event.emit(_event("spawn", {"position": global_position, "role_id": String(profile.role_id)}))

func return_to_pool() -> void:
	# Retirement is an exactly-once lifecycle edge. Several owners may observe
	# the same death during deferred teardown; a duplicate call must not emit a
	# second pool_return event or mutate the completed lifecycle trace.
	if state == "pooled":
		pool_return_rejections += 1
		return
	_release_telegraph_admission("pool_return")
	if is_instance_valid(neighbor_registry) and state != "death":
		neighbor_registry.unregister_actor(stable_id, spawn_generation)
	remove_from_group("combat_targets")
	set_physics_process(false)
	velocity = Vector3.ZERO
	target = null
	state_remaining = 0.0
	state = "pooled"
	_lifecycle_trace["pool_return"] = int(_lifecycle_trace.get("pool_return", 0)) + 1
	_last_completed_lifecycle = _lifecycle_trace.duplicate(true)
	model_pivot.reset_presenter()
	vitality_bar.retire("pool_return")
	visible = false
	collider.set_deferred("disabled", true)
	telegraph_ring.visible = false
	lane_cue.visible = false
	_hurt_light_remaining = 0.0
	_hurt_motion_remaining = 0.0
	_hurt_motion_count = 0
	_set_light_budget(false, false)
	_pool_return_pending = false
	lifecycle_event.emit(_event("pool_return"))
	neighbor_registry = null
	encounter_owner = null

func retire_from_pressure(reason: String, reconciliation_id: int) -> Dictionary:
	if state == "pooled":
		return {}
	retirement_count += 1
	var receipt := _event("retired", {
		"reason": reason,
		"reconciliation_id": reconciliation_id,
		"retirement_count": retirement_count,
		"pool_return_rejections": pool_return_rejections,
		"reward_committed": false,
		"defeat_committed": false,
	})
	lifecycle_event.emit(receipt)
	return_to_pool()
	return receipt

func _physics_process(delta: float) -> void:
	_physics_steps_total += 1
	_lifetime += delta
	_hurt_light_remaining = maxf(0.0, _hurt_light_remaining - delta)
	_hurt_motion_remaining = maxf(0.0, _hurt_motion_remaining - delta)
	if _hurt_motion_remaining <= 0.0 and is_instance_valid(model_pivot) and model_pivot.semantic_state == "hurt":
		model_pivot.set_semantic(state)
	if _hurt_light_remaining <= 0.0 and _hurt_light_active:
		_set_light_budget(_role_light_active, false)
	if not is_instance_valid(target) or state in ["pooled", "death"]:
		return
	var target_offset := target.global_position - global_position
	target_offset.y = 0.0
	var target_distance_squared := target_offset.length_squared()
	var dense_priority := _is_dense_priority(target_distance_squared)
	# Health changes still reveal immediately through the authoritative signal;
	# proximity/fade presentation is capped at 20 Hz to keep a 25–40 actor wave
	# from paying one UI update per physics tick.
	_vitality_refresh_remaining = maxf(0.0, _vitality_refresh_remaining - delta)
	var vitality_due := _vitality_refresh_remaining <= 0.0 or dense_priority
	if vitality_due:
		_vitality_refresh_remaining = DENSE_VITALITY_REFRESH_SECONDS
		_vitality_updates += 1
		vitality_bar.advance(delta, sqrt(target_distance_squared), true)
	else:
		_vitality_skips += 1
	state_remaining = maxf(0.0, state_remaining - delta)
	match state:
		"spawn":
			velocity = Vector3.ZERO
			if state_remaining <= 0.0:
				_set_state("approach")
		"approach":
			_steer_approach(delta)
			if target_distance_squared <= profile.attack_range * profile.attack_range:
				_request_telegraph_admission()
		"waiting_admission":
			velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
			if target_distance_squared > (profile.attack_range + 0.9) * (profile.attack_range + 0.9):
				_release_telegraph_admission("escape")
				_set_state("approach")
			elif is_instance_valid(encounter_owner) and encounter_owner.has_telegraph_admission(self):
				_begin_telegraph()
		"telegraph":
			velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
			telegraph_ring.scale = Vector3.ONE * (1.0 + (1.0 - state_remaining / profile.telegraph_duration) * 0.24)
			if state_remaining <= 0.0:
				_damage_frame()
		"damage":
			velocity = Vector3.ZERO
			if state_remaining <= 0.0:
				_set_state("recovery", profile.recovery_duration)
		"recovery":
			velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
			if state_remaining <= 0.0:
				_set_state("approach")
	move_and_slide()
	_body_motion_steps_total += 1
	global_position.y = 0.05
	if is_instance_valid(neighbor_registry):
		neighbor_registry.update_actor_position(self)
	model_pivot.advance(delta, velocity, state_remaining, _state_duration(state), dense_priority)
	if dense_priority:
		_priority_presentation_updates += 1
	else:
		_staggered_presentation_updates += 1
	if velocity.length_squared() > 0.04 and state == "approach":
		if dense_priority or posmod(Engine.get_physics_frames(), EnemySemanticPresenter.DENSE_APPROACH_ANIMATION_BUCKETS) == _facing_bucket:
			presentation_root.look_at(global_position + velocity, Vector3.UP)
			_facing_updates += 1
		else:
			_facing_skips += 1

func _steer_approach(delta: float) -> void:
	_steering_steps_total += 1
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var desired := to_target.normalized()
	var target_distance_squared := to_target.length_squared()
	if profile.attack_kind == "flank" and target_distance_squared > 5.76:
		desired = (desired + Vector3(-desired.z, 0.0, desired.x) * _flank_sign * 0.62).normalized()
	# Neighbor broad-phase queries are the dominant dense-wave CPU cost. Keep
	# steering deterministic while staggering the expensive query across three
	# stable actor buckets; the cached vector is blended into every frame's
	# desired velocity so actors never stop or teleport between query ticks.
	var separation := _cached_separation
	var query_due := target_distance_squared <= DenseProfile.PRIORITY_THREAT_RADIUS * DenseProfile.PRIORITY_THREAT_RADIUS or posmod(Engine.get_physics_frames(), DENSE_STEERING_BUCKETS) == _steering_bucket
	if query_due:
		separation = Vector3.ZERO
		var neighbors: Array[EnemyActor] = neighbor_registry.query_neighbors(self, profile.separation_radius) if is_instance_valid(neighbor_registry) else []
		for other in neighbors:
			var away: Vector3 = global_position - other.global_position
			away.y = 0.0
			var distance_squared := away.length_squared()
			if distance_squared > 0.0001 and distance_squared < profile.separation_radius * profile.separation_radius:
				var distance := sqrt(distance_squared)
				separation += away.normalized() * (profile.separation_radius - distance) / profile.separation_radius
		_cached_separation = separation
	else:
		_steering_query_skips += 1
	var target_velocity := (desired + separation * 0.72).normalized() * profile.movement_speed
	velocity = velocity.move_toward(target_velocity, 9.0 * delta)

func _is_dense_priority(target_distance_squared: float) -> bool:
	return (
		state in ["waiting_admission", "telegraph", "damage"]
		or _hurt_motion_remaining > 0.0
		or target_distance_squared <= DenseProfile.PRIORITY_THREAT_RADIUS * DenseProfile.PRIORITY_THREAT_RADIUS
	)

func _request_telegraph_admission() -> void:
	if not is_instance_valid(encounter_owner):
		telegraph_admitted = true
		_begin_telegraph()
		return
	encounter_owner.request_telegraph_admission(self)
	_set_state("waiting_admission")

func _begin_telegraph() -> void:
	telegraph_admitted = true
	_set_state("telegraph", profile.telegraph_duration)
	telegraph_ring.visible = true
	lane_cue.visible = profile.attack_kind == "ranged"
	if lane_cue.visible:
		var distance := global_position.distance_to(target.global_position)
		lane_cue.global_position = global_position.lerp(target.global_position, 0.5) + Vector3(0, 0.08, 0)
		lane_cue.look_at(target.global_position + Vector3(0, 0.08, 0), Vector3.UP)
		lane_cue.scale.z = distance / 5.0
	lifecycle_event.emit(_event("telegraph", {"attack_kind": profile.attack_kind}))

func _damage_frame() -> void:
	_release_telegraph_admission("damage")
	_set_state("damage", 0.13)
	telegraph_ring.visible = false
	lane_cue.visible = false
	attack_serial += 1
	var distance := global_position.distance_to(target.global_position)
	var accepted_range := profile.attack_range + (0.8 if profile.attack_kind == "slam" else 0.45)
	var event := _event("damage", {
		"attack_id": "%s.g%d.a%d" % [stable_id, spawn_generation, attack_serial],
		"damage": profile.attack_damage,
		"damage_channel": "enemy_%s" % profile.attack_kind,
		"attack_kind": profile.attack_kind,
		"distance": distance,
	})
	if distance <= accepted_range:
		var resolved: Dictionary = target.get_node("HealthComponent").apply_damage(event)
		event.accepted = bool(resolved.get("accepted", false))
	else:
		event.accepted = false
		event.rejection_reason = "escaped_telegraph"
	lifecycle_event.emit(event)

func _on_hurt(event: Dictionary) -> void:
	_lifecycle_trace["hurt"] = int(_lifecycle_trace.get("hurt", 0)) + 1
	hurt_count += 1
	_hurt_motion_count += 1
	_hurt_motion_remaining = 0.22
	if is_instance_valid(model_pivot):
		# Preserve the gameplay state; only the authored semantic presenter is
		# interrupted so hurt feedback cannot cancel telegraph/damage ownership.
		model_pivot.set_semantic("hurt")
	vitality_bar.reveal_damage()
	_hurt_light_remaining = 0.24
	lifecycle_event.emit(_event("hurt", {"health_after": event.get("health_after", health.current_health)}))

func _on_died(event: Dictionary) -> void:
	if state == "death":
		return
	death_count += 1
	if is_instance_valid(neighbor_registry):
		neighbor_registry.unregister_actor(stable_id, spawn_generation)
	remove_from_group("combat_targets")
	_release_telegraph_admission("death")
	_hurt_light_remaining = 0.0
	_set_light_budget(false, false)
	_pool_return_pending = true
	_set_state("death")
	velocity = Vector3.ZERO
	collider.set_deferred("disabled", true)
	telegraph_ring.visible = false
	lane_cue.visible = false
	vitality_bar.retire("death")
	var drop_event := event.duplicate(true)
	drop_event.position = global_position
	drop_event.actor_stable_id = String(stable_id)
	drop_event.spawn_generation = spawn_generation
	drops.commit_from_death(drop_event)
	lifecycle_event.emit(_event("death", {"death_id": event.get("death_id", "")}))
	defeated.emit(self, event)

func get_target_generation() -> int:
	return spawn_generation

func _on_drop(event: Dictionary) -> void:
	_lifecycle_trace["drop"] = int(_lifecycle_trace.get("drop", 0)) + 1
	drop_committed.emit(event)
	lifecycle_event.emit(_event("drop", {"drop_id": event.get("drop_id", "")}))

func _set_state(next_state: String, duration: float = 0.0) -> void:
	state = next_state
	if _lifecycle_trace.has(next_state):
		_lifecycle_trace[next_state] = int(_lifecycle_trace.get(next_state, 0)) + 1
	state_remaining = duration
	if is_instance_valid(model_pivot) and _hurt_motion_remaining <= 0.0:
		model_pivot.set_semantic(next_state)

func _state_duration(for_state: String) -> float:
	match for_state:
		"spawn": return 0.55
		"telegraph": return profile.telegraph_duration if profile else 0.0
		"damage": return 0.13
		"recovery": return profile.recovery_duration if profile else 0.0
		_: return 0.0

func _apply_accent(color: Color) -> void:
	for mesh in [telegraph_ring, lane_cue]:
		var material := mesh.get_active_material(0).duplicate() as StandardMaterial3D
		material.albedo_color = Color(color, 0.32)
		material.emission = color
		material.emission_energy_multiplier = 1.35
		mesh.material_override = material
	hurt_light.light_color = color
	role_glow.light_color = color

func _release_telegraph_admission(reason: String) -> void:
	if is_instance_valid(encounter_owner):
		encounter_owner.release_telegraph_admission(self, reason)
	telegraph_admitted = false

func has_hurt_light_request() -> bool:
	return state not in ["pooled", "death"] and _hurt_light_remaining > 0.0

func is_role_light_active() -> bool:
	return _role_light_active

func is_hurt_light_active() -> bool:
	return _hurt_light_active

func set_light_budget(role_active: bool, hurt_active: bool) -> void:
	_set_light_budget(role_active, hurt_active)

func _set_light_budget(role_active: bool, hurt_active: bool) -> void:
	_role_light_active = role_active and state not in ["pooled", "death"]
	_hurt_light_active = hurt_active and has_hurt_light_request()
	if is_instance_valid(role_glow):
		role_glow.light_energy = 0.52 if _role_light_active else 0.0
		role_glow.visible = _role_light_active
	if is_instance_valid(hurt_light):
		hurt_light.light_energy = 3.2 * clampf(_hurt_light_remaining / 0.24, 0.0, 1.0) if _hurt_light_active else 0.0
		hurt_light.visible = _hurt_light_active

func _event(phase: String, extra: Dictionary = {}) -> Dictionary:
	var event := {
		"phase": phase,
		"stable_id": String(stable_id),
		"role_id": String(profile.role_id) if profile else "none",
		"generation": spawn_generation,
	}
	event.merge(extra, true)
	return event

func get_stable_id() -> StringName:
	return stable_id

func get_lifecycle_trace() -> Dictionary:
	return _lifecycle_trace.duplicate(true)

func get_last_completed_lifecycle() -> Dictionary:
	return _last_completed_lifecycle.duplicate(true)

func has_completed_lifecycle_trace() -> bool:
	return _lifecycle_trace_complete(_last_completed_lifecycle)

func is_legal_target() -> bool:
	return visible and state not in ["pooled", "death"] and health.is_alive()

func _mcp_state() -> Dictionary:
	return {
		"stable_id": String(stable_id), "role_id": String(profile.role_id) if profile else "none",
		"generation": spawn_generation, "lifecycle_state": state, "state_remaining": state_remaining,
		"health": health.current_health, "maximum_health": health.maximum_health,
		"hurt_count": hurt_count, "death_count": death_count, "target_valid": is_instance_valid(target),
		"hurt_motion_active": _hurt_motion_remaining > 0.0,
		"hurt_motion_remaining": _hurt_motion_remaining,
		"hurt_motion_count": _hurt_motion_count,
		"velocity": velocity, "pool_return_pending": _pool_return_pending,
		"retirement_count": retirement_count,
		"telegraph_admitted": telegraph_admitted,
		"telegraph_waiting": state == "waiting_admission",
		"role_light_requested": state not in ["pooled", "death"],
		"role_light_active": _role_light_active,
		"hurt_light_requested": has_hurt_light_request(),
		"hurt_light_active": _hurt_light_active,
		"presentation_descriptor": model_pivot.presentation_descriptor() if is_instance_valid(model_pivot) else "none",
		"presentation_variant_id": model_pivot.variant_id if is_instance_valid(model_pivot) else "none",
		"semantic_state": model_pivot.semantic_state if is_instance_valid(model_pivot) else state,
		"active_motion_id": model_pivot.active_motion_id if is_instance_valid(model_pivot) else "none",
		"lifecycle_trace": _lifecycle_trace.duplicate(true),
		"last_completed_lifecycle": _last_completed_lifecycle.duplicate(true),
		"lifecycle_trace_complete": _lifecycle_trace_complete(_lifecycle_trace),
		"last_lifecycle_trace_complete": _lifecycle_trace_complete(_last_completed_lifecycle),
		"semantic_bindings": model_pivot.semantic_bindings() if is_instance_valid(model_pivot) else {},
		"presentation_budget": get_presentation_budget_snapshot(),
		"vitality":vitality_bar.get_snapshot() if is_instance_valid(vitality_bar) else {},
}

func _lifecycle_trace_complete(trace: Dictionary) -> bool:
	for phase in ["spawn", "approach", "telegraph", "damage", "hurt", "death", "drop", "pool_return"]:
		if int(trace.get(phase, 0)) <= 0:
			return false
	return true

func get_presentation_budget_snapshot() -> Dictionary:
	var receipt := model_pivot.presentation_budget_snapshot() if is_instance_valid(model_pivot) else {}
	receipt["facing_bucket"] = _facing_bucket
	receipt["facing_updates"] = _facing_updates
	receipt["facing_skips"] = _facing_skips
	receipt["non_priority_facing_staggered"] = true
	receipt["priority_updates"] = _priority_presentation_updates
	receipt["staggered_lane_updates"] = _staggered_presentation_updates
	receipt["priority_radius"] = DenseProfile.PRIORITY_THREAT_RADIUS
	return receipt

func reset_workload_counters() -> void:
	_physics_steps_total = 0
	_steering_steps_total = 0
	_body_motion_steps_total = 0
	_steering_query_skips = 0
	_vitality_updates = 0
	_vitality_skips = 0
	_priority_presentation_updates = 0
	_staggered_presentation_updates = 0

func get_workload_counters() -> Dictionary:
	return {
		"physics_steps":_physics_steps_total,
		"steering_steps":_steering_steps_total,
		"body_motion_steps":_body_motion_steps_total,
		"steering_query_skips":_steering_query_skips,
		"steering_query_bucket_count":DENSE_STEERING_BUCKETS,
		"steering_bucket":_steering_bucket,
		"neighbor_query_bucket":_steering_bucket,
		"neighbor_query_bucket_count":DenseProfile.NEIGHBOR_QUERY_BUCKET_COUNT,
		"explicit_space_queries":0,
		"vitality_updates":_vitality_updates,
		"vitality_skips":_vitality_skips,
		"vitality_refresh_seconds":DENSE_VITALITY_REFRESH_SECONDS,
		"vitality_bucket":_vitality_bucket,
		"vitality_bucket_count":DenseProfile.VITALITY_BUCKET_COUNT,
		"priority_presentation_updates":_priority_presentation_updates,
		"staggered_presentation_updates":_staggered_presentation_updates,
		"priority_threat_radius":DenseProfile.PRIORITY_THREAT_RADIUS,
		"space_query_policy":"registry_neighbors_and_move_and_slide_only",
	}
