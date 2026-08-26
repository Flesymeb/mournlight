class_name AttackRuntime
extends Node

signal attack_authorized(event: Dictionary)
signal hit_resolved(event: Dictionary)
signal attack_rejected(event: Dictionary)

@export var owner_id := &"warden"

var _next_attack_serial := 1
var _hit_ledgers: Dictionary = {}
var last_event: Dictionary = {}
var authorized_count := 0
var hit_count := 0
var rejection_count := 0

func authorize(weapon_id: StringName, target: Node3D, stats: Dictionary, hit_policy: String) -> Dictionary:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return _reject(weapon_id, "invalid_or_freed_target")
	if not target.has_method("is_legal_target") or not target.is_legal_target():
		return _reject(weapon_id, "dead_or_illegal_target")
	var attack_id := "%s.%s.%06d" % [owner_id, weapon_id, _next_attack_serial]
	_next_attack_serial += 1
	var event := {
		"accepted": true,
		"phase": "authorized",
		"actor_id": String(owner_id),
		"audio_owner": String(owner_id),
		"weapon_id": String(weapon_id),
		"attack_id": attack_id,
		"target_id": String(target.get_stable_id()) if target.has_method("get_stable_id") else String(target.get_path()),
		"damage": float(stats.get("damage", 0.0)),
		"damage_channel": "spectral_player",
		"hit_policy": hit_policy,
		"cooldown": float(stats.get("cooldown", 0.0)),
		"range": float(stats.get("range", 0.0)),
	}
	_hit_ledgers[attack_id] = {}
	authorized_count += 1
	last_event = event
	attack_authorized.emit(event)
	return event

func resolve_hit(attack_event: Dictionary, target: Node3D) -> Dictionary:
	var attack_id := String(attack_event.get("attack_id", ""))
	if not _hit_ledgers.has(attack_id):
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "unknown_attack")
	if not is_instance_valid(target) or not target.is_inside_tree():
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "freed_target_before_hit")
	var target_id := String(target.get_stable_id()) if target.has_method("get_stable_id") else String(target.get_path())
	var ledger: Dictionary = _hit_ledgers[attack_id]
	if ledger.has(target_id):
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "once_per_attack_ledger")
	ledger[target_id] = true
	var health := target.get_node_or_null("HealthComponent")
	if not health or not health.has_method("apply_damage"):
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "missing_health_component")
	var result: Dictionary = health.apply_damage(attack_event)
	if result.get("accepted", false):
		hit_count += 1
		result.phase = "impact"
		last_event = result
		hit_resolved.emit(result)
	return result

func finish_attack(attack_id: String) -> void:
	# Attack ledgers live exactly as long as their authoritative attack instance.
	# This keeps repeated automatic combat bounded without weakening the
	# once-per-target rule while an attack is active.
	_hit_ledgers.erase(attack_id)

func reject_attack(weapon_id: StringName, reason: String) -> Dictionary:
	return _reject(weapon_id, reason)

func _reject(weapon_id: StringName, reason: String) -> Dictionary:
	rejection_count += 1
	var event := {"accepted": false, "weapon_id": String(weapon_id), "rejection_reason": reason, "phase": "rejected"}
	last_event = event
	attack_rejected.emit(event)
	return event

func reset_runtime() -> void:
	_next_attack_serial = 1
	_hit_ledgers.clear()
	last_event.clear()
	authorized_count = 0
	hit_count = 0
	rejection_count = 0

func _mcp_state() -> Dictionary:
	return {
		"owner_id": String(owner_id), "authorized_count": authorized_count, "hit_count": hit_count,
		"rejection_count": rejection_count, "active_ledgers": _hit_ledgers.size(), "last_event": last_event,
	}
