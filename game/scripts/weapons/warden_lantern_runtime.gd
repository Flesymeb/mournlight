class_name WardenLanternRuntime
extends Node3D

const PITCH_VARIANTS: Array[float] = [0.92, 1.0, 1.08, 0.84]
const TRAVEL_VARIANTS: Array[float] = [0.0, 0.025, -0.02, 0.04]

@export var weapon_id := &"warden_lantern"
@export var bolt_scene: PackedScene
@onready var owner_actor: Node3D = get_parent().get_parent()
@onready var inventory: WeaponInventory = get_parent().get_node("WeaponInventory")
@onready var attack_runtime: AttackRuntime = get_parent().get_node("AttackRuntime")
@onready var audio_player: AudioStreamPlayer3D = $Audio

var cooldown_remaining := 0.18
var attack_phase := "cooldown"
var selected_target_id := ""
var emitted_count := 0
var resolved_hit_count := 0
var presentation_variant := -1
var last_attack_id := ""
var _emitting := false
var _runtime_generation := 0

func _ready() -> void:
	audio_player.stop()
	audio_player.stream = null

func _physics_process(delta: float) -> void:
	if not inventory.is_equipped(weapon_id):
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if cooldown_remaining > 0.0 or _emitting:
		return
	var stats := inventory.get_stats(weapon_id)
	var target := TargetSelector.nearest_legal(owner_actor, float(stats.get("range", 0.0)))
	if not target:
		attack_phase = "ready_no_target"
		selected_target_id = ""
		return
	_emit_attack(target, stats)

func _emit_attack(target: Node3D, stats: Dictionary) -> void:
	var generation := _runtime_generation
	_emitting = true
	attack_phase = "anticipation"
	selected_target_id = String(target.get_stable_id())
	await get_tree().create_timer(0.11).timeout
	if generation != _runtime_generation:
		return
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_legal_target():
		attack_runtime.reject_attack(weapon_id, "target_invalid_during_anticipation")
		attack_phase = "rejected"
		_emitting = false
		cooldown_remaining = 0.12
		return
	var event := attack_runtime.authorize(weapon_id, target, stats, "focused_once_per_attack")
	if not event.get("accepted", false):
		_emitting = false
		cooldown_remaining = 0.12
		return
	emitted_count += 1
	last_attack_id = String(event.attack_id)
	presentation_variant = posmod(emitted_count - 1, 4)
	attack_phase = "onset"
	if bolt_scene:
		var bolt := bolt_scene.instantiate()
		get_tree().current_scene.add_child(bolt)
		bolt.configure(global_position, target.global_position, event, presentation_variant)
	await get_tree().create_timer(0.18 + TRAVEL_VARIANTS[presentation_variant]).timeout
	if generation != _runtime_generation:
		return
	attack_phase = "impact"
	var result := attack_runtime.resolve_hit(event, target)
	if result.get("accepted", false):
		resolved_hit_count += 1
	await get_tree().create_timer(0.12).timeout
	if generation != _runtime_generation:
		return
	attack_phase = "recovery"
	attack_runtime.finish_attack(String(event.attack_id))
	cooldown_remaining = float(stats.cooldown)
	_emitting = false

func reset_runtime() -> void:
	_runtime_generation += 1
	cooldown_remaining = 0.18
	attack_phase = "cooldown"
	selected_target_id = ""
	emitted_count = 0
	resolved_hit_count = 0
	presentation_variant = -1
	last_attack_id = ""
	_emitting = false

func _mcp_state() -> Dictionary:
	var stats := inventory.get_stats(weapon_id) if inventory else {}
	return {
		"weapon_id": String(weapon_id), "equipped": inventory.is_equipped(weapon_id), "rank": inventory.get_rank(weapon_id),
		"cooldown_remaining": cooldown_remaining, "attack_phase": attack_phase, "selected_target_id": selected_target_id,
		"emitted_count": emitted_count, "resolved_hit_count": resolved_hit_count, "presentation_variant": presentation_variant,
		"last_attack_id": last_attack_id, "stats": stats,
	}
