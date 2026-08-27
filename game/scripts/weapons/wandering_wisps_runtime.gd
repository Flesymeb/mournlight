class_name WanderingWispsRuntime
extends Node3D

@export var weapon_id := &"wandering_wisps"
@export var wisp_scene: PackedScene
@onready var owner_actor: Node3D = get_parent().get_parent()
@onready var inventory: WeaponInventory = get_parent().get_node("WeaponInventory")
@onready var attack_runtime: AttackRuntime = get_parent().get_node("AttackRuntime")

var orbit_phase := 0.0
var contact_hit_count := 0
var active_wisp_count := 0
var _wisps: Array[Node3D] = []
var _target_next_hit_time: Dictionary = {}
var _gameplay_time := 0.0
var _retired := false
var _retirement_generation := 0

func _physics_process(delta: float) -> void:
	if _retired:
		return
	if not inventory.is_equipped(weapon_id):
		_clear_wisps()
		return
	_gameplay_time += delta
	var stats := inventory.get_stats(weapon_id)
	_sync_wisp_count(int(stats.count))
	orbit_phase = fmod(orbit_phase + delta * (1.9 + inventory.get_rank(weapon_id) * 0.16), TAU)
	for index in _wisps.size():
		var angle := orbit_phase + TAU * float(index) / float(_wisps.size())
		var radius := float(stats.area)
		_wisps[index].position = Vector3(cos(angle) * radius, 0.85 + sin(angle * 2.0) * 0.16, sin(angle) * radius)
	_resolve_contacts(stats)

func _sync_wisp_count(count: int) -> void:
	while _wisps.size() < count:
		var wisp := wisp_scene.instantiate() if wisp_scene else Node3D.new()
		add_child(wisp)
		if wisp.has_method("configure"):
			wisp.configure(_wisps.size())
		_wisps.append(wisp)
	while _wisps.size() > count:
		var removed: Node3D = _wisps.pop_back()
		removed.queue_free()
	active_wisp_count = _wisps.size()

func _resolve_contacts(stats: Dictionary) -> void:
	const CONTACT_RADIUS := 1.35
	for target in TargetSelector.legal_in_radius(owner_actor.global_position, float(stats.area) + CONTACT_RADIUS, get_tree()):
		var target_id := String(target.get_stable_id())
		if _gameplay_time < float(_target_next_hit_time.get(target_id, 0.0)):
			continue
		var closest := 99999.0
		for wisp in _wisps:
			closest = minf(closest, wisp.global_position.distance_to(target.global_position + Vector3.UP * 0.65))
		if closest > CONTACT_RADIUS:
			continue
		var event := attack_runtime.authorize(weapon_id, target, stats, "per_target_interval")
		if event.get("accepted", false):
			attack_runtime.record_phase(String(event.attack_id), "onset", {"wisp_contact": true})
			attack_runtime.resolve_hit(event, target)
			attack_runtime.finish_attack(String(event.attack_id), "recovery")
			contact_hit_count += 1
			_target_next_hit_time[target_id] = _gameplay_time + float(stats.hit_interval)

func _clear_wisps() -> void:
	for wisp in _wisps:
		if is_instance_valid(wisp):
			wisp.queue_free()
	_wisps.clear()
	active_wisp_count = 0

func _exit_tree() -> void:
	retire_runtime("exit_tree", _retirement_generation + 1)

func retire_runtime(reason: String, generation: int) -> Dictionary:
	# Ownership is invalidated synchronously before the presentation nodes are
	# queued. Generic group retirement can therefore never leave a live handle
	# for the next physics tick to dereference.
	set_physics_process(false)
	_retired = true
	_retirement_generation = maxi(_retirement_generation, generation)
	var before := {
		"wisp_handles": _wisps.size(),
		"per_target_intervals": _target_next_hit_time.size(),
		"orbit_phase": orbit_phase,
	}
	_clear_wisps()
	_target_next_hit_time.clear()
	_gameplay_time = 0.0
	orbit_phase = 0.0
	return {
		"weapon_id": String(weapon_id), "reason": reason,
		"generation": _retirement_generation, "before": before,
		"after": {"wisp_handles": _wisps.size(), "per_target_intervals": _target_next_hit_time.size(), "orbit_phase": orbit_phase},
		"complete": true,
	}

func reset_runtime() -> void:
	retire_runtime("reset", _retirement_generation + 1)
	contact_hit_count = 0
	_retired = false

func _mcp_state() -> Dictionary:
	return {
		"weapon_id": String(weapon_id), "equipped": inventory.is_equipped(weapon_id), "rank": inventory.get_rank(weapon_id),
		"active_wisp_count": active_wisp_count, "contact_hit_count": contact_hit_count,
		"per_target_interval_count": _target_next_hit_time.size(), "orbit_phase": orbit_phase,
		"gameplay_clock": _gameplay_time, "retired": _retired,
		"retirement_generation": _retirement_generation,
		"stats": inventory.get_stats(weapon_id),
	}
