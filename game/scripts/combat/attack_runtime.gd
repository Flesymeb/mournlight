class_name AttackRuntime
extends Node

signal attack_authorized(event: Dictionary)
signal hit_resolved(event: Dictionary)
signal attack_rejected(event: Dictionary)
signal attack_finished(event: Dictionary)

@export var owner_id := &"warden"

var _next_attack_serial := 1
var _hit_ledgers: Dictionary = {}
var last_event: Dictionary = {}
var authorized_count := 0
var hit_count := 0
var rejection_count := 0
const HISTORY_LIMIT := 48
var _completed_history: Array[Dictionary] = []
var _rejected_history: Array[Dictionary] = []
var _pending_rewards: Dictionary = {}
var _latest_by_weapon: Dictionary = {}
var _latest_reward_by_weapon: Dictionary = {}
var _event_serial := 0
var _retirement_generation := 0

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
		"generation": _retirement_generation,
	}
	_hit_ledgers[attack_id] = {
		"event": event.duplicate(true),
		"hit_targets": {},
		"timeline": [
			_phase_entry("cooldown_ready", {"cooldown": event.cooldown}),
			_phase_entry("target_selected", {"target_id": event.target_id, "selection_rule": "distance_squared_then_stable_id"}),
			_phase_entry("authorized", event),
		],
	}
	authorized_count += 1
	last_event = event.duplicate(true)
	attack_authorized.emit(event)
	return event

func resolve_hit(attack_event: Dictionary, target: Node3D) -> Dictionary:
	var attack_id := String(attack_event.get("attack_id", ""))
	if not _hit_ledgers.has(attack_id):
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "unknown_attack")
	if not is_instance_valid(target) or not target.is_inside_tree():
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "freed_target_before_hit", {"attack_id":attack_id, "accepted":false, "hit_material":"miss"})
	if not target.has_method("is_legal_target") or not target.is_legal_target():
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "illegal_target_before_hit", {"attack_id": attack_id, "accepted":false, "hit_material":"miss"})
	var target_id := String(target.get_stable_id()) if target.has_method("get_stable_id") else String(target.get_path())
	var ledger: Dictionary = _hit_ledgers[attack_id]
	var hit_targets: Dictionary = ledger.hit_targets
	if hit_targets.has(target_id):
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "once_per_attack_ledger")
	hit_targets[target_id] = true
	record_phase(attack_id, "hit_resolution", {"target_id": target_id})
	var health := target.get_node_or_null("HealthComponent")
	if not health or not health.has_method("apply_damage"):
		return _reject(StringName(attack_event.get("weapon_id", "unknown")), "missing_health_component", {"attack_id":attack_id, "accepted":false, "hit_material":"miss"})
	var resolved_event := attack_event.duplicate(true)
	var profile_value: Variant = target.get("profile")
	var role_id := String(profile_value.get("role_id")) if profile_value is Resource else ""
	# Surface material is a semantic hint for audio only; gameplay damage stays
	# entirely data-driven. Armoured/stone roles use the bounded metal stem,
	# while ordinary foes retain the character-hit stem.
	resolved_event["hit_material"] = "metal" if role_id == "grave_brute" else "character"
	var result: Dictionary = health.apply_damage(resolved_event)
	if result.get("accepted", false):
		hit_count += 1
		result.phase = "impact"
		last_event = result.duplicate(true)
		hit_resolved.emit(result)
		record_phase(attack_id, "damage_applied", result)
		if not String(result.get("death_id", "")).is_empty():
			record_phase(attack_id, "death_committed", {"death_id": result.death_id, "target_id": result.target_id})
		if _pending_rewards.has(attack_id):
			_commit_reward_phase(attack_id, _pending_rewards[attack_id])
			_pending_rewards.erase(attack_id)
	return result

func record_phase(attack_id: String, phase: String, details: Dictionary = {}) -> void:
	if not _hit_ledgers.has(attack_id):
		return
	var ledger: Dictionary = _hit_ledgers[attack_id]
	(ledger.timeline as Array).append(_phase_entry(phase, details))
	last_event = (ledger.event as Dictionary).duplicate(true)
	last_event.merge(details, true)
	last_event.phase = phase

func record_reward(event: Dictionary) -> void:
	var attack_id := String(event.get("attack_id", ""))
	if attack_id.is_empty() or not _hit_ledgers.has(attack_id):
		return
	_pending_rewards[attack_id] = event.duplicate(true)

func _commit_reward_phase(attack_id: String, event: Dictionary) -> void:
	record_phase(attack_id, "drop_committed", {
		"death_id": event.get("death_id", ""), "drop_id": event.get("drop_id", ""),
		"target_id": event.get("target_id", ""),
	})

func finish_attack(attack_id: String, final_phase: String = "recovery") -> void:
	# Attack ledgers live exactly as long as their authoritative attack instance.
	# This keeps repeated automatic combat bounded without weakening the
	# once-per-target rule while an attack is active.
	if not _hit_ledgers.has(attack_id):
		return
	record_phase(attack_id, final_phase)
	record_phase(attack_id, "completed")
	var ledger: Dictionary = _hit_ledgers[attack_id]
	var transaction := {
		"attack_id": attack_id,
		"event": (ledger.event as Dictionary).duplicate(true),
		"timeline": (ledger.timeline as Array).duplicate(true),
		"hit_target_ids": (ledger.hit_targets as Dictionary).keys(),
	}
	var event: Dictionary = ledger.event
	attack_finished.emit({
		"accepted": true,
		"attack_id": attack_id,
		"weapon_id": String(event.get("weapon_id", "unknown")),
		"actor_id": String(event.get("actor_id", owner_id)),
		"phase": final_phase,
		"timeline": (transaction.get("timeline", []) as Array).duplicate(true),
	})
	_completed_history.append(transaction)
	var weapon_id := String((ledger.event as Dictionary).get("weapon_id", "unknown"))
	var summary := _transaction_summary(transaction)
	_latest_by_weapon[weapon_id] = summary
	if bool(summary.get("reward_committed", false)):
		_latest_reward_by_weapon[weapon_id] = summary
	_trim_history(_completed_history)
	_hit_ledgers.erase(attack_id)

func reject_attack(weapon_id: StringName, reason: String, context: Dictionary = {}) -> Dictionary:
	return _reject(weapon_id, reason, context)

func _reject(weapon_id: StringName, reason: String, context: Dictionary = {}) -> Dictionary:
	rejection_count += 1
	var event := {"accepted": false, "actor_id": String(owner_id), "weapon_id": String(weapon_id), "rejection_reason": reason, "phase": "rejected"}
	event.merge(context, true)
	last_event = event.duplicate(true)
	_rejected_history.append(event.duplicate(true))
	_trim_history(_rejected_history)
	attack_rejected.emit(event)
	return event

func _phase_entry(phase: String, details: Dictionary = {}) -> Dictionary:
	_event_serial += 1
	return {"sequence": _event_serial, "phase": phase, "details": details.duplicate(true)}

func _trim_history(history: Array[Dictionary]) -> void:
	while history.size() > HISTORY_LIMIT:
		history.pop_front()

func _transaction_summary(transaction: Dictionary) -> Dictionary:
	var event: Dictionary = transaction.get("event", {})
	var phases: Array[String] = []
	var death_id := ""
	var drop_id := ""
	for entry in transaction.get("timeline", []):
		var phase := String(entry.get("phase", ""))
		phases.append(phase)
		var details: Dictionary = entry.get("details", {})
		if phase == "death_committed":
			death_id = String(details.get("death_id", ""))
		elif phase == "drop_committed":
			drop_id = String(details.get("drop_id", ""))
	return {
		"attack_id": transaction.get("attack_id", ""), "weapon_id": event.get("weapon_id", ""),
		"actor_id": event.get("actor_id", ""), "target_id": event.get("target_id", ""),
		"damage_channel": event.get("damage_channel", ""), "hit_policy": event.get("hit_policy", ""),
		"phases": phases, "hit_target_ids": transaction.get("hit_target_ids", []),
		"death_id": death_id, "drop_id": drop_id,
		"death_committed": not death_id.is_empty(), "reward_committed": not drop_id.is_empty(),
	}

func _causality_digest() -> Dictionary:
	var transactions := {}
	for weapon_id in _latest_by_weapon:
		var summary: Dictionary = _latest_by_weapon[weapon_id]
		transactions[weapon_id] = "%s|target=%s|policy=%s|channel=%s|hits=%d|phases=%s" % [
			summary.get("attack_id", ""), summary.get("target_id", ""), summary.get("hit_policy", ""),
			summary.get("damage_channel", ""), (summary.get("hit_target_ids", []) as Array).size(),
			",".join(summary.get("phases", [])),
		]
	var rewards := {}
	for weapon_id in _latest_reward_by_weapon:
		var summary: Dictionary = _latest_reward_by_weapon[weapon_id]
		rewards[weapon_id] = "%s|target=%s|death=%s|drop=%s" % [summary.get("attack_id", ""), summary.get("target_id", ""), summary.get("death_id", ""), summary.get("drop_id", "")]
	var rejection := ""
	if not _rejected_history.is_empty():
		var source: Dictionary = _rejected_history.back()
		rejection = "%s|target=%s|reason=%s" % [source.get("weapon_id", ""), source.get("target_id", ""), source.get("rejection_reason", "")]
	return {"transactions": transactions, "reward_transactions": rewards, "last_rejection": rejection}

func _receipt_for(weapon_id: String) -> String:
	return String((_causality_digest().get("transactions", {}) as Dictionary).get(weapon_id, ""))

func _reward_receipt_for(weapon_id: String) -> String:
	return String((_causality_digest().get("reward_transactions", {}) as Dictionary).get(weapon_id, ""))

func retire_runtime(reason: String, generation: int) -> Dictionary:
	_retirement_generation = maxi(_retirement_generation, generation)
	var interrupted_ids: Array[String] = []
	for attack_id in _hit_ledgers.keys():
		interrupted_ids.append(String(attack_id))
	_hit_ledgers.clear()
	_pending_rewards.clear()
	_completed_history.clear()
	_rejected_history.clear()
	_latest_by_weapon.clear()
	_latest_reward_by_weapon.clear()
	last_event.clear()
	return {"reason": reason, "generation": _retirement_generation, "interrupted_attack_ids": interrupted_ids, "active_ledgers": 0, "history_count": 0, "complete": true}

func reset_runtime() -> void:
	retire_runtime("reset", _retirement_generation + 1)
	_next_attack_serial = 1
	authorized_count = 0
	hit_count = 0
	rejection_count = 0

func _mcp_state() -> Dictionary:
	var causality := _causality_digest()
	return {
		"lantern_receipt": _receipt_for("warden_lantern"),
		"gravespade_receipt": _receipt_for("gravespade"),
		"wisps_receipt": _receipt_for("wandering_wisps"),
		"lantern_reward_receipt": _reward_receipt_for("warden_lantern"),
		"last_rejection_receipt": causality.get("last_rejection", ""),
		"owner_id": String(owner_id), "authorized_count": authorized_count, "hit_count": hit_count,
		"rejection_count": rejection_count, "active_ledgers": _hit_ledgers.size(),
		"completed_history_count": _completed_history.size(), "history_limit": HISTORY_LIMIT,
		"retirement_generation": _retirement_generation,
	}
