class_name BellkeeperActor
extends CharacterBody3D

signal boss_changed(snapshot: Dictionary)
signal defeated(event: Dictionary)
signal phase_shifted(phase: int)

@onready var health: HealthComponent = $HealthComponent
@onready var telegraph: MeshInstance3D = $Telegraph
@onready var presentation: Node3D = $Presentation
@onready var collider: CollisionShape3D = $Collider
var target: WardenController
var state := "entrance"
var phase := 1
var attack_clock := 2.4
var state_clock := 1.7
var attack_serial := 0
var committed := false
var telegraph_kind := "bell_wave"
var vulnerable := false
var bell_wave_count := 0
var lane_pressure_count := 0
var phase_shift_count := 0
var _telegraph_direction := Vector3.FORWARD
var _retirement_receipt: Dictionary = {}
var _death_tween: Tween
var _authored_presentation_scale := Vector3.ONE

func _ready() -> void:
	add_to_group("combat_targets")
	add_to_group("active_enemies")
	add_to_group("mcp_watch")
	health.hurt.connect(_on_hurt)
	health.died.connect(_on_died)
	telegraph.visible = false
	_authored_presentation_scale = presentation.scale
	boss_changed.emit(get_snapshot())

func configure(next_target: WardenController) -> void:
	target = next_target
	health.reset_health()
	state = "entrance"
	phase = 1
	committed = false
	_retirement_receipt.clear()
	if is_instance_valid(_death_tween):
		_death_tween.kill()
	presentation.scale = _authored_presentation_scale
	visible = true
	collider.disabled = false
	collision_layer = 1
	collision_mask = 1
	process_mode = Node.PROCESS_MODE_INHERIT
	telegraph_kind = "bell_wave"
	vulnerable = false
	bell_wave_count = 0
	lane_pressure_count = 0
	phase_shift_count = 0
	state_clock = 1.7
	attack_clock = 2.4
	state_clock = 1.7
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if committed or not is_instance_valid(target):
		return
	state_clock = maxf(0.0, state_clock - delta)
	attack_clock = maxf(0.0, attack_clock - delta)
	if state == "entrance":
		velocity = Vector3.ZERO
		if state_clock <= 0.0:
			state = "pursuit"
	elif state == "phase_shift":
		velocity = Vector3.ZERO
		if state_clock <= 0.0:
			_enter_recovery(1.25)
	elif state == "recovery":
		velocity = Vector3.ZERO
		if state_clock <= 0.0:
			vulnerable = false
			state = "pursuit"
	elif state == "telegraph":
		velocity = Vector3.ZERO
		telegraph.scale = Vector3.ONE * (1.0 + (0.9 - state_clock) * 0.7)
		if state_clock <= 0.0:
			_resolve_toll()
	else:
		var direction := target.global_position - global_position
		direction.y = 0.0
		velocity = direction.normalized() * (1.55 if phase == 1 else 2.15)
		if direction.length() < 5.0 and attack_clock <= 0.0:
			state = "telegraph"
			state_clock = 0.9 if phase == 1 else 0.65
			telegraph_kind = "lane_pressure" if attack_serial % 2 == 1 else "bell_wave"
			_telegraph_direction = direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
			telegraph.visible = true
			boss_changed.emit(get_snapshot())
	move_and_slide()
	global_position.y = 0.05

func _resolve_toll() -> void:
	attack_serial += 1
	telegraph.visible = false
	attack_clock = 3.4 if phase == 1 else 2.35
	var accepted := false
	if telegraph_kind == "lane_pressure":
		lane_pressure_count += 1
		var to_target := target.global_position - global_position
		var side_distance := absf(to_target.dot(Vector3(-_telegraph_direction.z, 0.0, _telegraph_direction.x)))
		accepted = to_target.length() <= 7.4 and side_distance <= 1.3
		if accepted:
			target.get_node("HealthComponent").apply_damage({"attack_id":"bellkeeper.lane.%d" % attack_serial,"damage":16.0 if phase == 1 else 22.0,"damage_channel":"boss_lane"})
	else:
		bell_wave_count += 1
		accepted = global_position.distance_to(target.global_position) <= 5.4
		if accepted:
			target.get_node("HealthComponent").apply_damage({"attack_id":"bellkeeper.toll.%d" % attack_serial,"damage":18.0 if phase == 1 else 24.0,"damage_channel":"boss_toll"})
	_enter_recovery(1.45 if phase == 1 else 1.0)
	boss_changed.emit(get_snapshot())

func _enter_recovery(duration: float) -> void:
	state = "recovery"
	state_clock = duration
	vulnerable = true
	telegraph.visible = false

func _on_hurt(_event: Dictionary) -> void:
	if phase == 1 and health.current_health <= health.maximum_health * 0.5:
		phase = 2
		state = "phase_shift"
		state_clock = 1.2
		vulnerable = false
		phase_shift_count += 1
		phase_shifted.emit(phase)
	boss_changed.emit(get_snapshot())

func _on_died(event: Dictionary) -> void:
	if committed:
		return
	committed = true
	state = "defeated"
	vulnerable = false
	set_physics_process(false)
	remove_from_group("active_enemies")
	velocity = Vector3.ZERO
	telegraph.visible = false
	_death_tween = create_tween()
	# The imported Bellkeeper is authored at 0.025 scale. The old absolute 1.4
	# target enlarged X/Z by 56x and covered the shipped camera during Cheer.
	# Keep the same readable squash/bloom idea, but express it relative to the
	# intact authored instance and settle near that reference before the hold.
	_death_tween.tween_property(presentation, "scale", _authored_presentation_scale * Vector3(1.30, 0.72, 1.30), 0.18)
	_death_tween.tween_property(presentation, "scale", _authored_presentation_scale * Vector3(1.06, 0.94, 1.06), 0.34)
	defeated.emit(event)
	boss_changed.emit(get_snapshot())

func terminate(reason: String) -> void:
	retire_run_actor(reason, 0)

func retire_run_actor(reason: String, completion_generation: int) -> Dictionary:
	if not _retirement_receipt.is_empty():
		return _retirement_receipt.duplicate(true)
	committed = true
	state = "retired_" + reason
	vulnerable = false
	target = null
	velocity = Vector3.ZERO
	attack_clock = 0.0
	state_clock = 0.0
	telegraph.visible = false
	visible = false
	set_physics_process(false)
	set_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED
	collider.disabled = true
	collision_layer = 0
	collision_mask = 0
	remove_from_group("active_enemies")
	remove_from_group("combat_targets")
	if is_instance_valid(_death_tween):
		_death_tween.kill()
	_retirement_receipt = {
		"stable_id":"boss.bellkeeper", "reason":reason, "completion_generation":completion_generation,
		"active":false, "state":state, "visible":visible, "physics_enabled":is_physics_processing(),
		"collision_layer":collision_layer, "collision_mask":collision_mask,
		"in_active_group":is_in_group("active_enemies"), "in_combat_group":is_in_group("combat_targets"),
		"telegraph_visible":telegraph.visible,
	}
	boss_changed.emit(get_snapshot())
	return _retirement_receipt.duplicate(true)

func is_legal_target() -> bool:
	return not committed and health.is_alive() and vulnerable

func get_stable_id() -> StringName:
	return &"boss.bellkeeper"

func get_snapshot() -> Dictionary:
	return {"active":not committed,"state":state,"phase":phase,"health":health.current_health,"health_maximum":health.maximum_health,
		"attack_clock":attack_clock,"telegraph_kind":telegraph_kind,"vulnerable":vulnerable,
		"bell_wave_count":bell_wave_count,"lane_pressure_count":lane_pressure_count,
		"phase_shift_count":phase_shift_count,"defeat_committed":committed,
		"presentation_scale":presentation.scale,"authored_presentation_scale":_authored_presentation_scale,
		"death_scale_relative":Vector3(
			presentation.scale.x / maxf(_authored_presentation_scale.x, 0.0001),
			presentation.scale.y / maxf(_authored_presentation_scale.y, 0.0001),
			presentation.scale.z / maxf(_authored_presentation_scale.z, 0.0001)
		),
		"death_scale_policy":"authored_relative_bounded"}

func _mcp_state() -> Dictionary:
	return get_snapshot()
