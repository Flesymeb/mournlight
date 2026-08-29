class_name EnemyVitalityBar
extends Node3D

signal visibility_state_changed(event: Dictionary)

const USEFUL_PROXIMITY := 5.4
const DAMAGE_HOLD_SECONDS := 2.8

@onready var background: MeshInstance3D = $Background
@onready var fill: MeshInstance3D = $Fill
@onready var brass_edge: MeshInstance3D = $BrassEdge

var actor_id := ""
var spawn_generation := -1
var current_health := 0.0
var maximum_health := 1.0
var display_ratio := 1.0
var useful_reason := "hidden"
var damage_hold_remaining := 0.0
var alpha := 0.0
var retirement_count := 0
var _bound := false
var _elite := false
var _reported_visible := false
var _bound_health: HealthComponent
var binding_serial := 0
var generation_mismatch_retirements := 0
var last_retirement_reason := "never_bound"

func _ready() -> void:
	_set_visible(false, "ready")

func bind_actor(health: HealthComponent, next_actor_id: StringName, generation: int, elite: bool) -> void:
	_disconnect_health()
	actor_id = String(next_actor_id)
	spawn_generation = generation
	binding_serial += 1
	_elite = elite
	_bound = true
	_bound_health = health
	if is_instance_valid(_bound_health) and not _bound_health.health_changed.is_connected(_on_health_changed):
		_bound_health.health_changed.connect(_on_health_changed)
	damage_hold_remaining = 0.0
	alpha = 0.0
	useful_reason = "hidden"
	current_health = health.current_health
	maximum_health = maxf(1.0, health.maximum_health)
	_set_ratio(current_health / maximum_health)
	_apply_alpha(0.0)
	_set_visible(false, "bind")

func reveal_damage() -> void:
	if not _bound:
		return
	if not _actor_generation_matches():
		generation_mismatch_retirements += 1
		retire("generation_mismatch")
		return
	damage_hold_remaining = DAMAGE_HOLD_SECONDS
	useful_reason = "damaged"
	# Health signals are emitted synchronously by HealthComponent.  Reveal the
	# indicator immediately instead of waiting for the actor's next physics tick;
	# this keeps a same-frame damage probe truthful and prevents a one-frame
	# invisible bar at dense-wave cadence.
	alpha = maxf(alpha, 0.92)
	_apply_alpha(alpha)
	_set_visible(true, "damage")

func advance(delta: float, target_distance: float, lifecycle_active: bool) -> void:
	if not _bound or not lifecycle_active:
		_retire_visibility("inactive")
		return
	if not _actor_generation_matches():
		generation_mismatch_retirements += 1
		retire("generation_mismatch")
		return
	damage_hold_remaining = maxf(0.0, damage_hold_remaining - delta)
	var proximity_useful := target_distance <= USEFUL_PROXIMITY
	var should_show := damage_hold_remaining > 0.0 or proximity_useful or _elite
	if damage_hold_remaining > 0.0:
		useful_reason = "damaged"
	elif _elite:
		useful_reason = "elite_engaged"
	elif proximity_useful:
		useful_reason = "proximity"
	else:
		useful_reason = "fading"
	alpha = move_toward(alpha, 1.0 if should_show else 0.0, delta * (5.5 if should_show else 1.8))
	_set_visible(alpha > 0.025, useful_reason)
	_apply_alpha(alpha)
	if not visible:
		useful_reason = "hidden"

func retire(reason: String) -> void:
	if _bound or visible:
		retirement_count += 1
	# Report the final visibility transition while the authoritative spawn
	# generation is still intact so the encounter owner can retire the exact
	# pooled identity it previously registered.
	_set_visible(false, reason)
	_bound = false
	_disconnect_health()
	spawn_generation = -1
	damage_hold_remaining = 0.0
	alpha = 0.0
	_apply_alpha(0.0)
	useful_reason = "retired_%s" % reason
	last_retirement_reason = reason

func _retire_visibility(reason: String) -> void:
	alpha = 0.0
	_set_visible(false, reason)
	useful_reason = reason

func _set_visible(next_visible: bool, reason: String) -> void:
	visible = next_visible
	if next_visible == _reported_visible:
		return
	_reported_visible = next_visible
	visibility_state_changed.emit({
		"actor_id":actor_id, "spawn_generation":spawn_generation,
		"visible":next_visible, "reason":reason,
		"retirement_count":retirement_count,
	})

func _on_health_changed(next_current: float, next_maximum: float) -> void:
	if not _bound or not _actor_generation_matches():
		return
	var was_damaged := next_current < current_health
	current_health = next_current
	maximum_health = maxf(1.0, next_maximum)
	_set_ratio(current_health / maximum_health)
	if was_damaged and current_health > 0.0:
		reveal_damage()
	if current_health <= 0.0:
		_retire_visibility("death")

func _set_ratio(next_ratio: float) -> void:
	display_ratio = clampf(next_ratio, 0.0, 1.0)
	fill.scale.x = maxf(0.001, display_ratio)
	fill.position.x = -0.58 * (1.0 - display_ratio)

func _apply_alpha(value: float) -> void:
	var inverse_alpha := 1.0 - clampf(value, 0.0, 0.86)
	background.transparency = inverse_alpha
	fill.transparency = inverse_alpha
	brass_edge.transparency = inverse_alpha

func _disconnect_health() -> void:
	if is_instance_valid(_bound_health) and _bound_health.health_changed.is_connected(_on_health_changed):
		_bound_health.health_changed.disconnect(_on_health_changed)
	_bound_health = null

func _actor_generation_matches() -> bool:
	var actor := get_parent() as EnemyActor
	return is_instance_valid(actor) and actor.spawn_generation == spawn_generation

func get_snapshot() -> Dictionary:
	return {
		"actor_id":actor_id, "spawn_generation":spawn_generation,
		"bound":_bound, "visible":visible, "reason":useful_reason,
		"current":current_health, "maximum":maximum_health,
		"ratio":display_ratio, "fill_direction":"left_to_right",
		"alpha":alpha, "camera_facing":"material_billboard",
		"retirement_count":retirement_count,
		"binding_serial":binding_serial,
		"generation_current":_actor_generation_matches() if _bound else false,
		"generation_mismatch_retirements":generation_mismatch_retirements,
		"last_retirement_reason":last_retirement_reason,
		"health_signal_bound":is_instance_valid(_bound_health) and _bound_health.health_changed.is_connected(_on_health_changed),
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
