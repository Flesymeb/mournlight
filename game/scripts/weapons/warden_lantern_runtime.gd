class_name WardenLanternRuntime
extends Node3D

const PITCH_VARIANTS: Array[float] = [0.92, 1.0, 1.08, 0.84]
const TRAVEL_VARIANTS: Array[float] = [0.0, 0.025, -0.02, 0.04]
const BOLT_POOL_CAP := 12

@export var weapon_id := &"warden_lantern"
@export var bolt_scene: PackedScene
@onready var owner_actor: Node3D = get_parent().get_parent()
@onready var inventory: WeaponInventory = get_parent().get_node("WeaponInventory")
@onready var attack_runtime: AttackRuntime = get_parent().get_node("AttackRuntime")
@onready var audio_player: AudioStreamPlayer3D = $Audio
var target_registry: EnemyNeighborRegistry

var cooldown_remaining := 0.18
var attack_phase := "cooldown"
var selected_target_id := ""
var emitted_count := 0
var resolved_hit_count := 0
var presentation_variant := -1
var last_attack_id := ""
var _emitting := false
var _runtime_generation := 0
var active_presentation_count := 0
var _active_presentations: Dictionary = {}
var _presentation_pool: Array[LanternBoltPresentation] = []
var _bolt_total := 0

func _ready() -> void:
	audio_player.stop()
	audio_player.stream = null

func configure_target_registry(registry: EnemyNeighborRegistry) -> void:
	target_registry = registry

func _physics_process(delta: float) -> void:
	if not inventory.is_equipped(weapon_id):
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if cooldown_remaining > 0.0 or _emitting:
		return
	var stats := inventory.get_stats(weapon_id)
	var target := TargetSelector.nearest_legal(owner_actor, float(stats.get("range", 0.0)), target_registry)
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
	# Focus is an explicit HUD affordance: the currently selected legal threat
	# gets a short vitality reveal even before the bolt lands, so automatic
	# targeting remains readable at dense-wave cadence.
	var focused_bar := target.get_node_or_null("EnemyVitalityBar")
	if focused_bar and focused_bar.has_method("reveal_focus"):
		focused_bar.reveal_focus()
	await get_tree().create_timer(0.11).timeout
	if generation != _runtime_generation:
		# A pause/retry/terminal teardown can invalidate an in-flight anticipation
		# while its timer is still pending.  Retire the local emission latch as
		# well as the authoritative ledger so a subsequent run cannot inherit a
		# stale "anticipation" phase or remain blocked from automatic fire.
		_abort_emission_for_generation_change()
		return
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_legal_target():
		attack_runtime.reject_attack(weapon_id, "target_invalid_during_anticipation", {"target_id": selected_target_id})
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
	attack_runtime.record_phase(last_attack_id, "onset", {"presentation": "lantern_bolt"})
	presentation_variant = posmod(emitted_count - 1, 4)
	attack_phase = "onset"
	if bolt_scene:
		var bolt := _acquire_bolt()
		if not is_instance_valid(bolt):
			# Deterministic exhaustion policy: the attack remains authoritative even
			# when presentation capacity is saturated.
			bolt = null
		if is_instance_valid(bolt):
			bolt.configure(global_position, target.global_position, event, presentation_variant)
			_track_presentation(bolt)
	await get_tree().create_timer(0.18 + TRAVEL_VARIANTS[presentation_variant]).timeout
	if generation != _runtime_generation:
		_abort_emission_for_generation_change()
		return
	attack_phase = "impact"
	attack_runtime.record_phase(last_attack_id, "impact", {"target_id": selected_target_id})
	var result := attack_runtime.resolve_hit(event, target)
	if result.get("accepted", false):
		resolved_hit_count += 1
	await get_tree().create_timer(0.12).timeout
	if generation != _runtime_generation:
		_abort_emission_for_generation_change()
		return
	attack_phase = "recovery"
	attack_runtime.finish_attack(String(event.attack_id), "recovery")
	cooldown_remaining = float(stats.cooldown)
	_emitting = false

func retire_runtime(reason: String, generation: int) -> Dictionary:
	set_physics_process(false)
	var before := {"attack_phase": attack_phase, "emitting": _emitting, "attack_id": last_attack_id}
	_runtime_generation += 1
	attack_phase = "retired"
	selected_target_id = ""
	last_attack_id = ""
	_emitting = false
	for presentation in _active_presentations.values().duplicate():
		if is_instance_valid(presentation) and presentation.has_method("retire_for_pool"):
			presentation.retire_for_pool()
	_active_presentations.clear()
	active_presentation_count = 0
	return {"weapon_id": String(weapon_id), "reason": reason, "generation": generation, "before": before, "active": false, "complete": true}

func _track_presentation(presentation: Node) -> void:
	var instance_id := presentation.get_instance_id()
	_active_presentations[instance_id] = true
	active_presentation_count = _active_presentations.size()
	var exiting_cb := _on_presentation_exiting.bind(instance_id)
	if not presentation.tree_exiting.is_connected(exiting_cb):
		presentation.tree_exiting.connect(exiting_cb)
	if presentation is LanternBoltPresentation and not (presentation as LanternBoltPresentation).retired.is_connected(_on_bolt_retired):
		(presentation as LanternBoltPresentation).retired.connect(_on_bolt_retired)

func _acquire_bolt() -> LanternBoltPresentation:
	var bolt: LanternBoltPresentation
	while not _presentation_pool.is_empty() and not is_instance_valid(_presentation_pool.back()):
		_presentation_pool.pop_back()
	if not _presentation_pool.is_empty():
		bolt = _presentation_pool.pop_back()
	else:
		if _bolt_total >= BOLT_POOL_CAP or not bolt_scene:
			return null
		bolt = bolt_scene.instantiate() as LanternBoltPresentation
		add_child(bolt)
		_bolt_total += 1
		bolt.retired.connect(_on_bolt_retired)
	return bolt

func _on_bolt_retired(bolt: LanternBoltPresentation) -> void:
	var instance_id := bolt.get_instance_id()
	_active_presentations.erase(instance_id)
	active_presentation_count = _active_presentations.size()
	if not _presentation_pool.has(bolt): _presentation_pool.append(bolt)

func _on_presentation_exiting(instance_id: int) -> void:
	if _active_presentations.erase(instance_id):
		active_presentation_count = _active_presentations.size()

func reset_runtime() -> void:
	retire_runtime("reset", _runtime_generation + 1)
	cooldown_remaining = 0.18
	attack_phase = "cooldown"
	selected_target_id = ""
	emitted_count = 0
	resolved_hit_count = 0
	presentation_variant = -1
	last_attack_id = ""
	_emitting = false
	set_physics_process(true)

func _abort_emission_for_generation_change() -> void:
	_emitting = false
	attack_phase = "retired"
	selected_target_id = ""
	last_attack_id = ""
	cooldown_remaining = 0.12

func _mcp_state() -> Dictionary:
	var stats := inventory.get_stats(weapon_id) if inventory else {}
	return {
		"weapon_id": String(weapon_id), "equipped": inventory.is_equipped(weapon_id), "rank": inventory.get_rank(weapon_id),
		"cooldown_remaining": cooldown_remaining, "attack_phase": attack_phase, "selected_target_id": selected_target_id,
		"emitted_count": emitted_count, "resolved_hit_count": resolved_hit_count, "presentation_variant": presentation_variant,
		"last_attack_id": last_attack_id, "stats": stats,
		"active_presentation_count":active_presentation_count,
		"presentation_pool_active":active_presentation_count, "presentation_pool_available":_presentation_pool.size(), "presentation_pool_total":_bolt_total, "presentation_pool_cap":BOLT_POOL_CAP,
	}
