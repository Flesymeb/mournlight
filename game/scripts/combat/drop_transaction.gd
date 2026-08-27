class_name DropTransaction
extends Node

signal drop_committed(event: Dictionary)

@export var drop_type := &"escaped_wisp"
var _death_ids: Dictionary = {}
var drop_count := 0
var last_drop_id := ""

func commit_from_death(death_event: Dictionary) -> Dictionary:
	var death_id := String(death_event.get("death_id", ""))
	if death_id.is_empty():
		return {"accepted": false, "rejection_reason": "missing_death_id"}
	if _death_ids.has(death_id):
		return {"accepted": false, "rejection_reason": "duplicate_death_transaction"}
	_death_ids[death_id] = true
	drop_count += 1
	last_drop_id = "%s.drop.%d" % [drop_type, drop_count]
	var event := death_event.duplicate(true)
	event.drop_id = last_drop_id
	event.drop_type = String(drop_type)
	event.drop_count = drop_count
	event.accepted = true
	drop_committed.emit(event)
	return event

func reset_transaction() -> void:
	_death_ids.clear()
	drop_count = 0
	last_drop_id = ""

func _mcp_state() -> Dictionary:
	return {"drop_count": drop_count, "last_drop_id": last_drop_id, "committed_death_count": _death_ids.size()}
