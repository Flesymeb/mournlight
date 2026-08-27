class_name GravespadeRuntime
extends Node3D

@export var weapon_id := &"gravespade"
@export var sweep_scene: PackedScene
@onready var owner_actor: Node3D = get_parent().get_parent()
@onready var inventory: WeaponInventory = get_parent().get_node("WeaponInventory")
@onready var attack_runtime: AttackRuntime = get_parent().get_node("AttackRuntime")

var cooldown_remaining := 0.35
var attack_phase := "unequipped"
var sweep_count := 0
var presentation_variant := -1
var last_target_id := ""
var _emitting := false
var _runtime_generation := 0

func _physics_process(delta: float) -> void:
	if not inventory.is_equipped(weapon_id):
		attack_phase = "unequipped"
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if cooldown_remaining > 0.0 or _emitting:
		return
	var stats := inventory.get_stats(weapon_id)
	var target := TargetSelector.nearest_legal(owner_actor, float(stats.range))
	if target:
		_emit_sweep(target, stats)
	else:
		attack_phase = "ready_no_target"

func _emit_sweep(primary_target: Node3D, stats: Dictionary) -> void:
	var generation := _runtime_generation
	_emitting = true
	attack_phase = "anticipation"
	last_target_id = String(primary_target.get_stable_id())
	var direction := (primary_target.global_position - owner_actor.global_position)
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		global_rotation.y = atan2(direction.x, direction.z)
	await get_tree().create_timer(0.14).timeout
	if generation != _runtime_generation:
		return
	if not is_instance_valid(primary_target) or not primary_target.is_legal_target():
		attack_phase = "rejected"
		_emitting = false
		cooldown_remaining = 0.12
		return
	var event := attack_runtime.authorize(weapon_id, primary_target, stats, "sweep_once_per_target")
	if not event.get("accepted", false):
		_emitting = false
		return
	sweep_count += 1
	presentation_variant = posmod(sweep_count - 1, 3)
	attack_phase = "active"
	if sweep_scene:
		var arc_count := int(stats.count)
		for arc_index in arc_count:
			var sweep: Node3D = sweep_scene.instantiate() as Node3D
			add_child(sweep)
			sweep.position.x = (float(arc_index) - float(arc_count - 1) * 0.5) * 0.38
			if sweep.has_method("configure"):
				sweep.configure(posmod(presentation_variant + arc_index, 3))
	var targets := TargetSelector.legal_in_radius(owner_actor.global_position, float(stats.area), get_tree())
	for target in targets:
		var to_target := (target.global_position - owner_actor.global_position).normalized()
		if direction.normalized().dot(to_target) >= -0.15:
			attack_runtime.resolve_hit(event, target)
	attack_phase = "impact"
	await get_tree().create_timer(0.16).timeout
	if generation != _runtime_generation:
		return
	attack_phase = "recovery"
	attack_runtime.finish_attack(String(event.attack_id))
	cooldown_remaining = float(stats.cooldown)
	_emitting = false

func reset_runtime() -> void:
	_runtime_generation += 1
	cooldown_remaining = 0.35
	attack_phase = "unequipped" if not inventory.is_equipped(weapon_id) else "cooldown"
	sweep_count = 0
	presentation_variant = -1
	last_target_id = ""
	_emitting = false

func _mcp_state() -> Dictionary:
	return {
		"weapon_id": String(weapon_id), "equipped": inventory.is_equipped(weapon_id), "rank": inventory.get_rank(weapon_id),
		"attack_phase": attack_phase, "cooldown_remaining": cooldown_remaining, "sweep_count": sweep_count,
		"presentation_variant": presentation_variant, "last_target_id": last_target_id,
		"stats": inventory.get_stats(weapon_id),
	}
