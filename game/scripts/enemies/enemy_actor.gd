class_name EnemyActor
extends CharacterBody3D

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

func _ready() -> void:
	add_to_group("combat_targets")
	add_to_group("mcp_watch")
	health.hurt.connect(_on_hurt)
	health.died.connect(_on_died)
	drops.drop_committed.connect(_on_drop)
	set_physics_process(false)
	visible = false
	collider.disabled = true

func activate(next_profile: EnemyProfile, next_target: WardenController, at_position: Vector3, generation: int) -> void:
	profile = next_profile
	target = next_target
	spawn_generation = generation
	_lifetime = 0.0
	attack_serial = 0
	hurt_count = 0
	death_count = 0
	_pool_return_pending = false
	_flank_sign = -1.0 if (String(stable_id).hash() + generation) % 2 == 0 else 1.0
	health.actor_id = stable_id
	health.maximum_health = profile.maximum_health
	health.current_health = profile.maximum_health
	health.reset_health()
	drops.reset_transaction()
	global_position = at_position
	velocity = Vector3.ZERO
	presentation_root.scale = Vector3.ONE * profile.presentation_scale
	presentation_root.rotation = Vector3.ZERO
	presentation_root.position = Vector3.ZERO
	model_pivot.configure(String(profile.role_id), profile.accent_color, stable_id, generation)
	_apply_accent(profile.accent_color)
	visible = true
	collider.disabled = false
	_set_state("spawn", 0.55)
	set_physics_process(true)
	lifecycle_event.emit(_event("spawn", {"position": global_position, "role_id": String(profile.role_id)}))

func return_to_pool() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO
	target = null
	state_remaining = 0.0
	state = "pooled"
	model_pivot.reset_presenter()
	visible = false
	collider.set_deferred("disabled", true)
	telegraph_ring.visible = false
	lane_cue.visible = false
	_pool_return_pending = false
	lifecycle_event.emit(_event("pool_return"))

func retire_from_pressure(reason: String, reconciliation_id: int) -> Dictionary:
	if state == "pooled":
		return {}
	retirement_count += 1
	var receipt := _event("retired", {
		"reason": reason,
		"reconciliation_id": reconciliation_id,
		"retirement_count": retirement_count,
		"reward_committed": false,
		"defeat_committed": false,
	})
	lifecycle_event.emit(receipt)
	return_to_pool()
	return receipt

func _physics_process(delta: float) -> void:
	_lifetime += delta
	hurt_light.light_energy = move_toward(hurt_light.light_energy, 0.0, delta * 14.0)
	if not is_instance_valid(target) or state in ["pooled", "death"]:
		return
	state_remaining = maxf(0.0, state_remaining - delta)
	match state:
		"spawn":
			velocity = Vector3.ZERO
			if state_remaining <= 0.0:
				_set_state("approach")
		"approach":
			_steer_approach(delta)
			if global_position.distance_to(target.global_position) <= profile.attack_range:
				_begin_telegraph()
		"telegraph":
			velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
			telegraph_ring.scale = Vector3.ONE * (1.0 + (1.0 - state_remaining / profile.telegraph_duration) * 0.55)
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
	global_position.y = 0.05
	model_pivot.advance(delta, velocity, state_remaining, _state_duration(state))
	if velocity.length_squared() > 0.04 and state == "approach":
		presentation_root.look_at(global_position + velocity, Vector3.UP)

func _steer_approach(delta: float) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var desired := to_target.normalized()
	if profile.attack_kind == "flank" and to_target.length() > 2.4:
		desired = (desired + Vector3(-desired.z, 0.0, desired.x) * _flank_sign * 0.62).normalized()
	var separation := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("active_enemies"):
		if other == self or not (other is EnemyActor):
			continue
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		var distance := away.length()
		if distance > 0.01 and distance < profile.separation_radius:
			separation += away.normalized() * (profile.separation_radius - distance) / profile.separation_radius
	var target_velocity := (desired + separation * 0.72).normalized() * profile.movement_speed
	velocity = velocity.move_toward(target_velocity, 9.0 * delta)

func _begin_telegraph() -> void:
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
	hurt_count += 1
	hurt_light.light_energy = 4.0
	lifecycle_event.emit(_event("hurt", {"health_after": event.get("health_after", health.current_health)}))

func _on_died(event: Dictionary) -> void:
	if state == "death":
		return
	death_count += 1
	_pool_return_pending = true
	_set_state("death")
	velocity = Vector3.ZERO
	collider.set_deferred("disabled", true)
	telegraph_ring.visible = false
	lane_cue.visible = false
	drops.commit_from_death(event)
	lifecycle_event.emit(_event("death", {"death_id": event.get("death_id", "")}))
	defeated.emit(self, event)

func _on_drop(event: Dictionary) -> void:
	drop_committed.emit(event)
	lifecycle_event.emit(_event("drop", {"drop_id": event.get("drop_id", "")}))

func _set_state(next_state: String, duration: float = 0.0) -> void:
	state = next_state
	state_remaining = duration
	if is_instance_valid(model_pivot):
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
		material.albedo_color = Color(color, 0.55)
		material.emission = color
		material.emission_energy_multiplier = 2.8
		mesh.material_override = material
	hurt_light.light_color = color
	role_glow.light_color = color

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

func is_legal_target() -> bool:
	return visible and state not in ["pooled", "death"] and health.is_alive()

func _mcp_state() -> Dictionary:
	return {
		"stable_id": String(stable_id), "role_id": String(profile.role_id) if profile else "none",
		"generation": spawn_generation, "lifecycle_state": state, "state_remaining": state_remaining,
		"health": health.current_health, "maximum_health": health.maximum_health,
		"hurt_count": hurt_count, "death_count": death_count, "target_valid": is_instance_valid(target),
		"velocity": velocity, "pool_return_pending": _pool_return_pending,
		"retirement_count": retirement_count,
		"presentation_descriptor": model_pivot.presentation_descriptor() if is_instance_valid(model_pivot) else "none",
		"presentation_variant_id": model_pivot.variant_id if is_instance_valid(model_pivot) else "none",
		"semantic_state": model_pivot.semantic_state if is_instance_valid(model_pivot) else state,
		"active_motion_id": model_pivot.active_motion_id if is_instance_valid(model_pivot) else "none",
		"semantic_bindings": model_pivot.semantic_bindings() if is_instance_valid(model_pivot) else {},
	}
