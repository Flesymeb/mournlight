class_name RewardPickup
extends Node3D

signal collected(event: Dictionary)

@export var collection_radius := 1.15
@export var lifetime_seconds := 20.0

@onready var presentation: Node3D = $Presentation
@onready var glow: OmniLight3D = $Glow

var pickup_event: Dictionary = {}
var target: Node3D
var age := 0.0
var _base_y := 0.0

func configure(next_target: Node3D, event: Dictionary) -> void:
	target = next_target
	pickup_event = event.duplicate(true)
	pickup_event["reward_value"] = maxi(1, int(pickup_event.get("reward_value", 1)))
	var spawn_position: Vector3 = event.get("position", Vector3.ZERO)
	global_position = spawn_position
	_base_y = global_position.y + 0.3
	global_position.y = _base_y
	set_process(true)

func merge_reward(event: Dictionary) -> void:
	pickup_event["reward_value"] = int(pickup_event.get("reward_value", 1)) + maxi(1, int(event.get("reward_value", 1)))
	var merged_ids: Array = pickup_event.get("merged_drop_ids", [])
	merged_ids.append(String(event.get("drop_id", "unknown")))
	while merged_ids.size() > 8:
		merged_ids.pop_front()
	pickup_event["merged_drop_ids"] = merged_ids
	age = minf(age, lifetime_seconds * 0.5)

func _process(delta: float) -> void:
	age += delta
	presentation.rotation.y += delta * 1.8
	presentation.position.y = sin(age * 3.1) * 0.08
	glow.light_energy = 0.7 + sin(age * 4.2) * 0.18
	if is_instance_valid(target):
		var planar := target.global_position - global_position
		planar.y = 0.0
		var resolved_collection_radius := collection_radius
		var warden := target as WardenController
		if warden:
			resolved_collection_radius = maxf(collection_radius, warden.pickup_collection_radius)
		if planar.length() <= resolved_collection_radius:
			pickup_event.collected_at_age = age
			pickup_event.collection_distance = planar.length()
			pickup_event.collection_radius = resolved_collection_radius
			collected.emit(pickup_event.duplicate(true))
			remove_from_group(&"reward_pickup")
			queue_free()
			return
	if age >= lifetime_seconds:
		remove_from_group(&"reward_pickup")
		queue_free()

func _mcp_state() -> Dictionary:
	var warden := target as WardenController
	return {
		"drop_id":pickup_event.get("drop_id", ""),
		"drop_type":pickup_event.get("drop_type", "escaped_wisp"),
		"reward_value":pickup_event.get("reward_value", 1),
		"age":age,
		"base_collection_radius":collection_radius,
		"collection_radius":maxf(collection_radius, warden.pickup_collection_radius) if warden else collection_radius,
		"target_valid":is_instance_valid(target),
		"production_presentation":"authored_warden_lantern",
	}
