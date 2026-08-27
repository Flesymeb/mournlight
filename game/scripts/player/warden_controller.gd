class_name WardenController
extends CharacterBody3D

signal dash_phase_changed(phase: String, invulnerable: bool)
signal dash_readiness_changed(ready: bool, cooldown_remaining: float)

enum DashPhase { READY, ANTICIPATION, ACTIVE, RECOVERY, COOLDOWN }

@export_category("Locomotion")
@export var movement_speed := 5.8
@export var acceleration := 24.0
@export var deceleration := 32.0
@export var turn_speed := 12.0
@export var movement_plane_y := 0.05
@export_category("Dash")
@export var dash_speed := 16.5
@export var anticipation_duration := 0.12
@export var active_duration := 0.18
@export var recovery_duration := 0.22
@export var cooldown_duration := 0.72

@export_category("Runtime state (read-only)")
@export var movement_input := Vector2.ZERO
@export var planar_velocity := Vector3.ZERO
@export var locomotion_state := "idle"
@export var dash_phase := "ready"
@export var dash_cooldown_remaining := 0.0
@export var dash_invulnerable := false
@export var plane_error := 0.0

@onready var presentation_root: Node3D = $PresentationRoot
@onready var model_pivot: Node3D = $PresentationRoot/ModelPivot
@onready var lantern: Node3D = $PresentationRoot/LanternPivot
@onready var dash_aura: MeshInstance3D = $DashAura
@onready var active_ring: MeshInstance3D = $ActiveRing

var _dash_phase_id := DashPhase.READY
var _phase_remaining := 0.0
var _dash_direction := Vector3.FORWARD
var _last_move_direction := Vector3.FORWARD
var _dash_was_pressed := false
var _visual_time := 0.0
var _base_model_position := Vector3.ZERO
var _base_lantern_position := Vector3.ZERO
var _base_presentation_scale := Vector3.ONE
var _authored_animation: AnimationPlayer

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	max_slides = 6
	movement_plane_y = global_position.y
	_base_model_position = model_pivot.position
	_base_lantern_position = lantern.position
	_base_presentation_scale = presentation_root.scale
	_authored_animation = _find_animation_player(model_pivot)
	_play_authored_idle()
	_set_dash_phase(DashPhase.READY, 0.0)
	reset_input_latch()

func _physics_process(delta: float) -> void:
	movement_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.24).limit_length(1.0)
	var desired_direction := _camera_relative_direction(movement_input)
	if desired_direction.length_squared() > 0.001:
		_last_move_direction = desired_direction
	_update_dash_state(delta, desired_direction)
	_update_authoritative_velocity(delta, desired_direction)
	global_position.y = movement_plane_y
	move_and_slide()
	plane_error = global_position.y - movement_plane_y
	global_position.y = movement_plane_y
	velocity.y = 0.0
	planar_velocity = Vector3(velocity.x, 0.0, velocity.z)
	locomotion_state = "locomotion" if planar_velocity.length_squared() > 0.08 else "idle"
	if _dash_phase_id != DashPhase.READY:
		locomotion_state = "dash_" + dash_phase
	_update_facing_and_animation(delta)
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("set_movement_velocity"):
		camera.set_movement_velocity(planar_velocity)
	_dash_was_pressed = Input.is_action_pressed("dash")

func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.length_squared() <= 0.001:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3(input_vector.x, 0.0, input_vector.y).normalized()
	var camera_right := camera.global_transform.basis.x
	var camera_forward := -camera.global_transform.basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()
	return (camera_right * input_vector.x + camera_forward * -input_vector.y).limit_length(1.0)

func _update_dash_state(delta: float, desired_direction: Vector3) -> void:
	if _dash_phase_id != DashPhase.READY:
		_phase_remaining = maxf(0.0, _phase_remaining - delta)
	if dash_cooldown_remaining > 0.0:
		dash_cooldown_remaining = maxf(0.0, dash_cooldown_remaining - delta)
		dash_readiness_changed.emit(false, dash_cooldown_remaining)
	var dash_pressed_now := Input.is_action_pressed("dash")
	if _dash_phase_id == DashPhase.READY and dash_pressed_now and not _dash_was_pressed:
		_dash_direction = desired_direction if desired_direction.length_squared() > 0.001 else _last_move_direction
		_set_dash_phase(DashPhase.ANTICIPATION, anticipation_duration)
	elif _dash_phase_id == DashPhase.ANTICIPATION and _phase_remaining <= 0.0:
		_set_dash_phase(DashPhase.ACTIVE, active_duration)
	elif _dash_phase_id == DashPhase.ACTIVE and _phase_remaining <= 0.0:
		_set_dash_phase(DashPhase.RECOVERY, recovery_duration)
	elif _dash_phase_id == DashPhase.RECOVERY and _phase_remaining <= 0.0:
		dash_cooldown_remaining = cooldown_duration
		_set_dash_phase(DashPhase.COOLDOWN, cooldown_duration)
	elif _dash_phase_id == DashPhase.COOLDOWN and dash_cooldown_remaining <= 0.0:
		_set_dash_phase(DashPhase.READY, 0.0)

func _update_authoritative_velocity(delta: float, desired_direction: Vector3) -> void:
	var target_velocity := desired_direction * movement_speed
	if _dash_phase_id == DashPhase.ACTIVE:
		target_velocity = _dash_direction * dash_speed
		velocity = Vector3(target_velocity.x, 0.0, target_velocity.z)
	elif _dash_phase_id == DashPhase.ANTICIPATION:
		velocity = velocity.move_toward(Vector3.ZERO, deceleration * 1.8 * delta)
	elif _dash_phase_id == DashPhase.RECOVERY:
		velocity = velocity.move_toward(target_velocity * 0.4, deceleration * 2.6 * delta)
	else:
		var rate := acceleration if target_velocity.length_squared() > 0.001 else deceleration
		velocity = velocity.move_toward(target_velocity, rate * delta)
	velocity.y = 0.0

func _set_dash_phase(next_phase: DashPhase, duration: float) -> void:
	_dash_phase_id = next_phase
	_phase_remaining = duration
	dash_invulnerable = next_phase == DashPhase.ACTIVE
	match next_phase:
		DashPhase.READY: dash_phase = "ready"
		DashPhase.ANTICIPATION: dash_phase = "anticipation"
		DashPhase.ACTIVE: dash_phase = "active"
		DashPhase.RECOVERY: dash_phase = "recovery"
		DashPhase.COOLDOWN: dash_phase = "cooldown"
	dash_aura.visible = next_phase == DashPhase.ANTICIPATION or next_phase == DashPhase.RECOVERY
	active_ring.visible = next_phase == DashPhase.ACTIVE
	dash_phase_changed.emit(dash_phase, dash_invulnerable)
	if next_phase == DashPhase.READY:
		dash_readiness_changed.emit(true, 0.0)

func _update_facing_and_animation(delta: float) -> void:
	_visual_time += delta
	var planar_speed := planar_velocity.length()
	var facing_direction := _dash_direction if _dash_phase_id == DashPhase.ACTIVE else _last_move_direction
	if facing_direction.length_squared() > 0.001:
		var target_angle := atan2(facing_direction.x, facing_direction.z)
		presentation_root.rotation.y = lerp_angle(presentation_root.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))
	var stride := clampf(planar_speed / movement_speed, 0.0, 1.0)
	var cycle := sin(_visual_time * 10.0) * stride
	model_pivot.rotation.x = -stride * 0.055
	model_pivot.position = _base_model_position + Vector3(0.0, abs(cycle) * 0.026, 0.0)
	lantern.position = _base_lantern_position + Vector3(0.0, sin(_visual_time * 3.2) * 0.025, 0.0)
	if _dash_phase_id == DashPhase.ANTICIPATION:
		presentation_root.scale = presentation_root.scale.lerp(_base_presentation_scale * Vector3(1.16, 0.78, 1.16), 1.0 - exp(-18.0 * delta))
		dash_aura.scale = Vector3.ONE * (0.82 + sin(_visual_time * 22.0) * 0.08)
	elif _dash_phase_id == DashPhase.ACTIVE:
		presentation_root.scale = presentation_root.scale.lerp(_base_presentation_scale * Vector3(0.82, 1.0, 1.32), 1.0 - exp(-24.0 * delta))
		active_ring.scale = Vector3.ONE * (1.0 + sin(_visual_time * 30.0) * 0.12)
	elif _dash_phase_id == DashPhase.RECOVERY:
		presentation_root.scale = presentation_root.scale.lerp(_base_presentation_scale * Vector3(1.08, 0.9, 1.08), 1.0 - exp(-12.0 * delta))
	else:
		presentation_root.scale = presentation_root.scale.lerp(_base_presentation_scale, 1.0 - exp(-14.0 * delta))

func reset_for_run(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	planar_velocity = Vector3.ZERO
	movement_input = Vector2.ZERO
	_dash_direction = Vector3.FORWARD
	_last_move_direction = Vector3.FORWARD
	dash_cooldown_remaining = 0.0
	presentation_root.scale = _base_presentation_scale
	_set_dash_phase(DashPhase.READY, 0.0)
	_play_authored_idle()
	reset_input_latch()

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _play_authored_idle() -> void:
	if not _authored_animation:
		return
	var animations := _authored_animation.get_animation_list()
	for preferred in [&"standby", &"idle", &"Idle", &"Take 001"]:
		if animations.has(preferred):
			_authored_animation.play(preferred)
			return
	for animation_name in animations:
		if String(animation_name) != "RESET":
			_authored_animation.play(animation_name)
			return

func reset_input_latch() -> void:
	_dash_was_pressed = Input.is_action_pressed("dash")
	movement_input = Vector2.ZERO

func get_movement_snapshot() -> Dictionary:
	return {
		"movement_input": movement_input,
		"velocity": planar_velocity,
		"locomotion_state": locomotion_state,
		"dash_phase": dash_phase,
		"cooldown_remaining": dash_cooldown_remaining,
		"invulnerable": dash_invulnerable,
	}

func _mcp_state() -> Dictionary:
	return {
		"movement_input": movement_input,
		"planar_velocity": planar_velocity,
		"planar_speed": planar_velocity.length(),
		"locomotion_state": locomotion_state,
		"dash_phase": dash_phase,
		"dash_cooldown_remaining": dash_cooldown_remaining,
		"dash_invulnerable": dash_invulnerable,
		"movement_speed": movement_speed,
		"dash_speed": dash_speed,
		"movement_plane_y": movement_plane_y,
		"plane_error": plane_error,
		"authored_animation": String(_authored_animation.current_animation) if _authored_animation else "none",
	}
