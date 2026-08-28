class_name RewardPickup
extends Node3D

signal collected(event: Dictionary)
signal retired(event: Dictionary)
signal attraction_started(event: Dictionary)
signal collection_fx_started(event: Dictionary)

@export var collection_radius := 1.15
@export var lifetime_seconds := 20.0

@onready var presentation: Node3D = $Presentation
@onready var glow: OmniLight3D = $Glow
@onready var pickup_ring: MeshInstance3D = $PickupRing
@onready var motion_tail: MeshInstance3D = $MotionTail

var pickup_event: Dictionary = {}
var target: Node3D
var age := 0.0
var _base_y := 0.0
var _retired := false
var state := "settle"
var attraction_speed := 0.0
var attraction_started_at_age := -1.0
var _collection_committed := false
var _collection_fx_remaining := 0.0
var _constituent_drop_ids: Array[String] = []
var merge_count := 0
var last_merge_position := Vector3.ZERO

const SETTLE_DURATION := 0.42
const COLLECTION_CORE_RADIUS := 0.42
const ATTRACTION_ACCELERATION := 13.5
const ATTRACTION_MAX_SPEED := 14.0
const COLLECTION_FX_SECONDS := 0.24

func configure(next_target: Node3D, event: Dictionary) -> void:
	if not is_in_group(&"reward_pickup"):
		add_to_group(&"reward_pickup")
	_retired = false
	target = next_target
	pickup_event = event.duplicate(true)
	pickup_event["reward_value"] = maxi(1, int(pickup_event.get("reward_value", 1)))
	var drop_id := String(pickup_event.get("drop_id", ""))
	_constituent_drop_ids.clear()
	for id_value in pickup_event.get("constituent_drop_ids", []):
		var constituent_id := String(id_value)
		if not constituent_id.is_empty() and not _constituent_drop_ids.has(constituent_id):
			_constituent_drop_ids.append(constituent_id)
	if not drop_id.is_empty() and not _constituent_drop_ids.has(drop_id):
		_constituent_drop_ids.append(drop_id)
	pickup_event["constituent_drop_ids"] = _constituent_drop_ids.duplicate()
	pickup_event["constituent_count"] = _constituent_drop_ids.size()
	var spawn_position: Vector3 = event.get("position", Vector3.ZERO)
	global_position = spawn_position
	_base_y = global_position.y + 0.3
	global_position.y = _base_y
	state = "settle"
	age = 0.0
	attraction_speed = 0.0
	attraction_started_at_age = -1.0
	_collection_committed = false
	_collection_fx_remaining = 0.0
	merge_count = 0
	last_merge_position = spawn_position
	presentation.scale = Vector3.ONE * (0.125 if int(pickup_event.reward_value) >= 3 else 0.09)
	pickup_ring.scale = Vector3.ONE
	motion_tail.visible = false
	set_process(true)

func can_accept_merge(drop_id: String) -> bool:
	return not drop_id.is_empty() and not _constituent_drop_ids.has(drop_id) and not _collection_committed and state != "collection_fx"

func merge_reward(event: Dictionary) -> bool:
	var drop_id := String(event.get("drop_id", ""))
	if not can_accept_merge(drop_id):
		return false
	pickup_event["reward_value"] = int(pickup_event.get("reward_value", 1)) + maxi(1, int(event.get("reward_value", 1)))
	_constituent_drop_ids.append(drop_id)
	pickup_event["constituent_drop_ids"] = _constituent_drop_ids.duplicate()
	pickup_event["constituent_count"] = _constituent_drop_ids.size()
	# At the visual cap, reuse the oldest unresolved owner at the newest
	# authoritative death position. Prior constituent value remains attached,
	# while the recent death still receives a visible settle/pulse onset.
	var merged_position: Vector3 = event.get("position", global_position)
	global_position = merged_position
	_base_y = merged_position.y + 0.3
	global_position.y = _base_y
	last_merge_position = merged_position
	merge_count += 1
	state = "settle"
	age = 0.0
	attraction_speed = 0.0
	attraction_started_at_age = -1.0
	motion_tail.visible = false
	pickup_ring.scale = Vector3.ONE
	glow.light_energy = 0.88
	presentation.scale = Vector3.ONE * 0.125
	return true

func _process(delta: float) -> void:
	age += delta
	if state == "collection_fx":
		_collection_fx_remaining = maxf(0.0, _collection_fx_remaining - delta)
		var progress := 1.0 - _collection_fx_remaining / COLLECTION_FX_SECONDS
		pickup_ring.scale = Vector3.ONE * (1.0 + progress * 2.4)
		presentation.scale = Vector3.ONE * maxf(0.001, 0.12 * (1.0 - progress))
		glow.light_energy = 2.4 * (1.0 - progress)
		if _collection_fx_remaining <= 0.0:
			_retire("collected_fx_complete")
		return
	presentation.rotation.y += delta * 1.8
	presentation.position.y = sin(age * 3.1) * (0.035 if state == "attracting" else 0.08)
	glow.light_energy = 0.7 + sin(age * 4.2) * 0.18
	if is_instance_valid(target):
		var planar := target.global_position - global_position
		planar.y = 0.0
		var resolved_attraction_radius := collection_radius
		var warden := target as WardenController
		if warden:
			resolved_attraction_radius = maxf(collection_radius, warden.pickup_collection_radius)
		var distance := planar.length()
		if age >= SETTLE_DURATION and distance <= resolved_attraction_radius:
			if state != "attracting":
				state = "attracting"
				attraction_started_at_age = age
				motion_tail.visible = true
				attraction_started.emit(_event_receipt("attraction_started", distance, resolved_attraction_radius))
			attraction_speed = move_toward(attraction_speed, ATTRACTION_MAX_SPEED, ATTRACTION_ACCELERATION * delta)
			var step_distance := minf(distance, attraction_speed * delta)
			if distance > 0.0001:
				global_position += planar / distance * step_distance
			motion_tail.position = Vector3(0.0, -0.04, clampf(attraction_speed * -0.018, -0.22, -0.04))
			distance = Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()
			if distance <= COLLECTION_CORE_RADIUS:
				_commit_collection(distance, resolved_attraction_radius)
				return
	if age >= lifetime_seconds:
		_retire("lifetime_expired")

func _commit_collection(distance: float, attraction_radius: float) -> void:
	if _collection_committed:
		return
	_collection_committed = true
	state = "collection_fx"
	_collection_fx_remaining = COLLECTION_FX_SECONDS
	motion_tail.visible = false
	pickup_event["collected_at_age"] = age
	pickup_event["collection_distance"] = distance
	pickup_event["attraction_radius"] = attraction_radius
	pickup_event["collection_core_radius"] = COLLECTION_CORE_RADIUS
	pickup_event["attraction_started_at_age"] = attraction_started_at_age
	pickup_event["constituent_drop_ids"] = _constituent_drop_ids.duplicate()
	pickup_event["constituent_count"] = _constituent_drop_ids.size()
	pickup_event["exactly_once_committed"] = true
	collected.emit(pickup_event.duplicate(true))
	collection_fx_started.emit(pickup_event.duplicate(true))

func _event_receipt(phase: String, distance: float, attraction_radius: float) -> Dictionary:
	return {
		"phase":phase, "drop_id":pickup_event.get("drop_id", ""),
		"constituent_drop_ids":_constituent_drop_ids.duplicate(),
		"reward_value":pickup_event.get("reward_value", 1),
		"age":age, "distance":distance,
		"attraction_radius":attraction_radius,
		"speed":attraction_speed,
	}

func _exit_tree() -> void:
	_retire("exit_tree")

func _retire(reason: String) -> void:
	if _retired:
		return
	_retired = true
	visible = false
	set_process(false)
	state = "pooled"
	target = null
	remove_from_group(&"reward_pickup")
	retired.emit({"instance_id":get_instance_id(),"drop_id":pickup_event.get("drop_id", ""),"reason":reason})

func retire_for_pool(reason: String = "run_teardown") -> void:
	_retire(reason)

func _mcp_state() -> Dictionary:
	var warden := target as WardenController
	return {
		"drop_id":pickup_event.get("drop_id", ""),
		"drop_type":pickup_event.get("drop_type", "escaped_wisp"),
		"reward_value":pickup_event.get("reward_value", 1),
		"age":age,
		"state":state,
		"constituent_drop_ids":_constituent_drop_ids.duplicate(),
		"constituent_count":_constituent_drop_ids.size(),
		"merge_count":merge_count,
		"last_merge_position":last_merge_position,
		"attraction_speed":attraction_speed,
		"attraction_started_at_age":attraction_started_at_age,
		"collection_committed":_collection_committed,
		"settle_duration":SETTLE_DURATION,
		"collection_core_radius":COLLECTION_CORE_RADIUS,
		"base_collection_radius":collection_radius,
		"collection_radius":maxf(collection_radius, warden.pickup_collection_radius) if warden else collection_radius,
		"target_valid":is_instance_valid(target),
		"production_presentation":"authored_warden_lantern",
		"presentation_variant":"high_value" if int(pickup_event.get("reward_value", 1)) >= 3 else "standard",
	}
