class_name HealthComponent
extends Node

signal hurt(event: Dictionary)
signal died(event: Dictionary)
signal health_changed(current: float, maximum: float)

@export var actor_id := &"target.unknown"
@export var maximum_health := 80.0
@export var current_health := 80.0

var _resolved_attack_ids: Dictionary = {}
var _death_committed := false
var death_count := 0

func apply_damage(event: Dictionary) -> Dictionary:
	var attack_id := String(event.get("attack_id", ""))
	if attack_id.is_empty():
		return {"accepted": false, "rejection_reason": "missing_attack_id"}
	if _death_committed:
		return {"accepted": false, "rejection_reason": "already_dead"}
	if _resolved_attack_ids.has(attack_id):
		return {"accepted": false, "rejection_reason": "duplicate_attack_hit"}
	_resolved_attack_ids[attack_id] = true
	var health_before := current_health
	current_health = maxf(0.0, current_health - maxf(0.0, float(event.get("damage", 0.0))))
	var resolved := event.duplicate(true)
	resolved.health_before = health_before
	resolved.health_after = current_health
	resolved.target_id = String(actor_id)
	resolved.accepted = true
	hurt.emit(resolved)
	health_changed.emit(current_health, maximum_health)
	if current_health <= 0.0:
		_death_committed = true
		death_count += 1
		resolved.death_id = "%s.death.%d" % [actor_id, death_count]
		died.emit(resolved)
	return resolved

func is_alive() -> bool:
	return not _death_committed and current_health > 0.0

func reset_health() -> void:
	current_health = maximum_health
	_resolved_attack_ids.clear()
	_death_committed = false
	death_count = 0
	health_changed.emit(current_health, maximum_health)

func _mcp_state() -> Dictionary:
	return {
		"actor_id": String(actor_id), "health": current_health, "maximum_health": maximum_health,
		"alive": is_alive(), "death_count": death_count, "resolved_hit_count": _resolved_attack_ids.size(),
	}

