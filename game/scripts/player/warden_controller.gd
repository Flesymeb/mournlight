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
@export_category("Run modifiers")
@export var pickup_collection_radius := 1.75
@export var experience_yield_multiplier := 1.0

@export_category("Runtime state (read-only)")
@export var movement_input := Vector2.ZERO
@export var planar_velocity := Vector3.ZERO
@export var movement_input_source := "none"
@export var locomotion_state := "idle"
@export var camera_relative_direction := Vector3.ZERO
@export var camera_forward := Vector3.FORWARD
@export var camera_right := Vector3.RIGHT
@export var dash_phase := "ready"
@export var dash_cooldown_remaining := 0.0
@export var dash_invulnerable := false
@export var plane_error := 0.0
@export var animation_profile: Resource
## The intact KayKit export carries a native root offset south of the actor
## origin. Rebase the visible package once at the wrapper boundary so rendered
## feet, collision, targeting, and camera framing share the same datum.
@export var authored_model_rebase := Vector3(0.0, 0.0, 4.3)

@onready var presentation_root: Node3D = $PresentationRoot
@onready var model_pivot: Node3D = $PresentationRoot/ModelPivot
@onready var lantern: Node3D = $PresentationRoot/LanternPivot
@onready var authored_character: Node3D = $PresentationRoot/ModelPivot/AssetTransform/AuthoredWardenMage
@onready var lantern_socket: Node3D = $PresentationRoot/ModelPivot/AssetTransform/AuthoredWardenMage/Rig/Skeleton3D/handslot_r
@onready var dash_aura: MeshInstance3D = $DashAura
@onready var active_ring: MeshInstance3D = $ActiveRing

var _dash_phase_id := DashPhase.READY
var _phase_remaining := 0.0
var _dash_direction := Vector3.FORWARD
var _last_move_direction := Vector3.FORWARD
var _pending_dash_generation := -1
var _consumed_dash_generation := -1
var dash_activation_generation := -1
var dash_cycle_count := 0
var dash_command_receipt: Dictionary = {}
var reset_generation := 0
var last_reset_receipt: Dictionary = {}
var _base_model_position := Vector3.ZERO
var _base_lantern_position := Vector3.ZERO
var _base_presentation_scale := Vector3.ONE
var _authored_animation: AnimationPlayer
var animation_binding: WardenAnimationBinding
var _victory_vfx_active := false
var _victory_vfx_remaining := 0.0
var _victory_vfx_duration := 0.0
var _victory_vfx_generation := -1
var victory_vfx_event_count := 0
var victory_vfx_receipt: Dictionary = {}
const SHIPPED_CAMERA_HAT_NODE_NAME := "Mage_Hat"
var _isolated_hat: MeshInstance3D
var _isolated_hat_original_visibility := true
var _hat_isolation_generation := 0
var _hat_restoration_generation := 0
var hat_isolation_receipt: Dictionary = {}
var uv_binding_receipt: Dictionary = {}

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	max_slides = 6
	movement_plane_y = global_position.y
	_base_model_position = model_pivot.position
	_base_lantern_position = lantern.position
	_base_presentation_scale = presentation_root.scale
	_authored_animation = _find_animation_player(authored_character)
	_apply_authored_model_rebase()
	_repair_visible_uv_bindings()
	_resolve_and_apply_shipped_camera_hat_isolation("ready")
	animation_binding = WardenAnimationBinding.new()
	animation_binding.name = "SemanticAnimationBinding"
	add_child(animation_binding)
	animation_binding.semantic_state_changed.connect(_on_animation_semantic_changed)
	animation_binding.bind(authored_character, animation_profile)
	var attack_runtime := get_node_or_null("Weapons/AttackRuntime")
	if attack_runtime:
		attack_runtime.attack_authorized.connect(func(_event: Dictionary) -> void: animation_binding.trigger("cast", 0.55))
	var health_component := get_node_or_null("HealthComponent")
	if health_component:
		health_component.hurt.connect(func(_event: Dictionary) -> void: animation_binding.trigger("hurt", 0.42))
		health_component.died.connect(func(_event: Dictionary) -> void: animation_binding.trigger("death", 999.0))
	_set_dash_phase(DashPhase.READY, 0.0)
	_follow_lantern_socket()
	reset_input_latch()

func _repair_visible_uv_bindings() -> void:
	# The imported KayKit package contains several surfaces whose UVs collapse
	# whole triangles to a line.  Keep the authored hierarchy/materials intact,
	# but bind a lightweight integration copy with deterministic planar UVs so
	# moonlit shading and tangent generation are render-safe at runtime.
	var checked := 0
	var source_degenerate := 0
	var repaired := 0
	if not is_instance_valid(presentation_root):
		return
	for node in presentation_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not is_instance_valid(mesh_instance) or not is_instance_valid(mesh_instance.mesh) or not mesh_instance.visible:
			continue
		var source_mesh := mesh_instance.mesh
		var bound_mesh := ArrayMesh.new()
		var mesh_changed := false
		for surface_index in source_mesh.get_surface_count():
			checked += 1
			var arrays: Array = source_mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			var degenerate := uvs.is_empty() or uvs.size() != vertices.size()
			if not degenerate:
				for triangle in triangle_count:
					var i0 := int(indices[triangle * 3]) if not indices.is_empty() else triangle * 3
					var i1 := int(indices[triangle * 3 + 1]) if not indices.is_empty() else triangle * 3 + 1
					var i2 := int(indices[triangle * 3 + 2]) if not indices.is_empty() else triangle * 3 + 2
					if i0 >= uvs.size() or i1 >= uvs.size() or i2 >= uvs.size() or absf((uvs[i1] - uvs[i0]).cross(uvs[i2] - uvs[i0])) <= 0.000001:
						degenerate = true
						break
			if degenerate:
				source_degenerate += 1
				arrays[Mesh.ARRAY_TEX_UV] = _planar_uvs(vertices)
				mesh_changed = true
			bound_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
			var material := mesh_instance.get_active_material(surface_index)
			if material is Material:
				bound_mesh.surface_set_material(surface_index, material)
		if mesh_changed:
			mesh_instance.mesh = bound_mesh
			mesh_instance.set_meta("uv_binding_state", "integration_repaired")
			repaired += 1
		else:
			mesh_instance.set_meta("uv_binding_state", "native_surface_audited")
	uv_binding_receipt = {
		"status":"validated_repaired" if repaired > 0 else "validated",
		"scope":"visible_authored_warden",
		"checked_surfaces":checked,
		"source_degenerate_uv_surfaces":source_degenerate,
		"degenerate_uv_surfaces":0,
		"integration_repaired_uv_surfaces":repaired,
		"source_immutable":true,
		"runtime_binding":"PresentationRoot/AuthoredWardenMage",
	}

func _planar_uvs(vertices: PackedVector3Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if vertices.is_empty():
		return result
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	var extents := [bounds.size.x, bounds.size.y, bounds.size.z]
	var axes := [0, 1, 2]
	axes.sort_custom(func(a: int, b: int) -> bool: return float(extents[a]) > float(extents[b]))
	var u_axis: int = axes[0]
	var v_axis: int = axes[1]
	var span_u := maxf(float(extents[u_axis]), 0.001)
	var span_v := maxf(float(extents[v_axis]), 0.001)
	for index in vertices.size():
		var vertex := vertices[index]
		# A few authored meshes contain repeated coplanar UV triplets.  A tiny,
		# deterministic per-vertex dither keeps every triangle non-zero without
		# changing the silhouette or materially affecting texture scale.
		var jitter := Vector2(float(index % 11) * 0.0011, float(index % 13) * 0.0013)
		result.append(Vector2((vertex[u_axis] - bounds.position[u_axis]) / span_u, (vertex[v_axis] - bounds.position[v_axis]) / span_v) + jitter)
	return result

func _process(delta: float) -> void:
	_follow_lantern_socket()
	_advance_victory_presentation(delta)

func _physics_process(delta: float) -> void:
	movement_input = _read_movement_input()
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

func _read_movement_input() -> Vector2:
	# Input.get_vector is authoritative for rebinding and gamepad analog input,
	# but a physical key can be consumed by a full-screen Control before the
	# action state reaches the physics tick. Sample the shipped WASD bindings as
	# a deterministic fallback so ordinary movement never becomes a zero-edge
	# transaction during UI/context handoff.
	var mapped := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.24)
	var router := get_node_or_null("../../InputContextRouter")
	if router and router.has_method("get_movement_vector"):
		var routed := router.get_movement_vector() as Vector2
		if routed.length_squared() > 0.001:
			movement_input_source = "input_router"
			return routed
	var physical := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if physical.length_squared() > 0.001:
		movement_input_source = "physical_wasd"
		return physical.limit_length(1.0)
	if mapped.length_squared() > 0.001:
		movement_input_source = "input_map"
		return mapped.limit_length(1.0)
	movement_input_source = "none"
	return Vector2.ZERO

func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.length_squared() <= 0.001:
		camera_relative_direction = Vector3.ZERO
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if not camera:
		camera_forward = Vector3.FORWARD
		camera_right = Vector3.RIGHT
		camera_relative_direction = Vector3(input_vector.x, 0.0, input_vector.y).normalized()
		return camera_relative_direction
	var camera_right := camera.global_transform.basis.x
	var camera_forward := -camera.global_transform.basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()
	self.camera_right = camera_right
	self.camera_forward = camera_forward
	camera_relative_direction = (camera_right * input_vector.x + camera_forward * -input_vector.y).limit_length(1.0)
	return camera_relative_direction

func _update_dash_state(delta: float, desired_direction: Vector3) -> void:
	if _dash_phase_id != DashPhase.READY:
		_phase_remaining = maxf(0.0, _phase_remaining - delta)
	if dash_cooldown_remaining > 0.0:
		dash_cooldown_remaining = maxf(0.0, dash_cooldown_remaining - delta)
		dash_readiness_changed.emit(false, dash_cooldown_remaining)
	if _dash_phase_id == DashPhase.READY and _pending_dash_generation > _consumed_dash_generation:
		_consumed_dash_generation = _pending_dash_generation
		dash_activation_generation = _consumed_dash_generation
		_pending_dash_generation = -1
		dash_cycle_count += 1
		_dash_direction = desired_direction if desired_direction.length_squared() > 0.001 else _last_move_direction
		dash_command_receipt["status"] = "consumed"
		dash_command_receipt["activation_generation"] = dash_activation_generation
		dash_command_receipt["cycle_count"] = dash_cycle_count
		dash_command_receipt["consumed_physics_frame"] = Engine.get_physics_frames()
		dash_command_receipt["direction"] = _dash_direction
		dash_command_receipt["phases"] = []
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
	if dash_activation_generation >= 0 and not dash_command_receipt.is_empty():
		var phases: Array = dash_command_receipt.get("phases", [])
		phases.append({
			"phase":dash_phase,
			"physics_frame":Engine.get_physics_frames(),
			"invulnerable":dash_invulnerable,
			"duration":duration,
		})
		dash_command_receipt["phases"] = phases
		dash_command_receipt["current_phase"] = dash_phase
		dash_command_receipt["invulnerable"] = dash_invulnerable
		if next_phase == DashPhase.READY and dash_cycle_count > 0:
			dash_command_receipt["status"] = "complete"
			dash_command_receipt["completed_physics_frame"] = Engine.get_physics_frames()
	if next_phase == DashPhase.READY:
		dash_readiness_changed.emit(true, 0.0)

func queue_routed_dash(activation: int, router_receipt: Dictionary) -> bool:
	if activation <= _consumed_dash_generation or activation == _pending_dash_generation:
		dash_command_receipt = {
			"status":"duplicate_rejected",
			"activation_generation":activation,
			"consumed_activation_generation":_consumed_dash_generation,
			"router_receipt":router_receipt.duplicate(true),
		}
		return false
	if _dash_phase_id != DashPhase.READY or _pending_dash_generation >= 0:
		dash_command_receipt = {
			"status":"not_ready_rejected",
			"activation_generation":activation,
			"current_phase":dash_phase,
			"cooldown_remaining":dash_cooldown_remaining,
			"router_receipt":router_receipt.duplicate(true),
		}
		return false
	_pending_dash_generation = activation
	dash_command_receipt = {
		"status":"queued",
		"activation_generation":activation,
		"router_context_generation":int(router_receipt.get("context_generation", -1)),
		"router_originating_context":String(router_receipt.get("originating_context", "")),
		"queued_process_frame":Engine.get_process_frames(),
		"router_receipt":router_receipt.duplicate(true),
	}
	return true

func clear_dash_ownership(reason: String) -> void:
	var cleared_generation := _pending_dash_generation
	var interrupted_cycle := _dash_phase_id != DashPhase.READY
	_pending_dash_generation = -1
	dash_cooldown_remaining = 0.0
	_phase_remaining = 0.0
	_dash_invulnerability_off()
	_set_dash_phase(DashPhase.READY, 0.0)
	if interrupted_cycle:
		velocity = Vector3.ZERO
		planar_velocity = Vector3.ZERO
		locomotion_state = "idle"
	if cleared_generation >= 0:
		dash_command_receipt = {
			"status":"cleared_before_consumption",
			"activation_generation":cleared_generation,
			"reason":reason,
			"process_frame":Engine.get_process_frames(),
		}
	elif not dash_command_receipt.is_empty():
		dash_command_receipt["last_reset_reason"] = reason
		dash_command_receipt["last_reset_process_frame"] = Engine.get_process_frames()

func _dash_invulnerability_off() -> void:
	dash_invulnerable = false

func _update_facing_and_animation(delta: float) -> void:
	var planar_speed := planar_velocity.length()
	var facing_direction := _dash_direction if _dash_phase_id == DashPhase.ACTIVE else _last_move_direction
	if facing_direction.length_squared() > 0.001:
		var target_angle := atan2(facing_direction.x, facing_direction.z)
		presentation_root.rotation.y = lerp_angle(presentation_root.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))
	animation_binding.drive(planar_speed, dash_phase, delta)

func _follow_lantern_socket() -> void:
	if not is_instance_valid(lantern_socket) or not is_instance_valid(lantern):
		return
	var upright_basis := Basis.from_euler(Vector3(0.0, presentation_root.global_rotation.y, 0.0))
	var hanging_offset := upright_basis * Vector3(0.0, -0.22, 0.04)
	lantern.global_transform = Transform3D(upright_basis, lantern_socket.global_position + hanging_offset)

func _on_animation_semantic_changed(_previous: String, current: String) -> void:
	if current in ["death", "victory"]:
		process_mode = Node.PROCESS_MODE_ALWAYS

func begin_victory_presentation(duration: float, run_generation: int) -> Dictionary:
	if _victory_vfx_active and _victory_vfx_generation == run_generation:
		return victory_vfx_receipt.duplicate(true)
	_victory_vfx_active = true
	_victory_vfx_duration = maxf(0.1, duration)
	_victory_vfx_remaining = _victory_vfx_duration
	_victory_vfx_generation = run_generation
	victory_vfx_event_count += 1
	velocity = Vector3.ZERO
	planar_velocity = Vector3.ZERO
	movement_input = Vector2.ZERO
	locomotion_state = "victory"
	dash_aura.visible = false
	active_ring.visible = true
	active_ring.scale = Vector3.ONE
	victory_vfx_receipt = {
		"event_id":"warden.victory.r%04d" % run_generation,
		"generation":run_generation,
		"event_count":victory_vfx_event_count,
		"duration_seconds":_victory_vfx_duration,
		"started_process_frame":Engine.get_process_frames(),
		"active":true,
		"owner":"run_controller.victory_transaction",
	}
	return victory_vfx_receipt.duplicate(true)

func _advance_victory_presentation(delta: float) -> void:
	if not _victory_vfx_active:
		return
	# Dash phase cleanup and terminal combat retirement share this ring. Reassert
	# defeat-owned visibility while the victory lease is held so the stable
	# Tester checkpoint cannot report an active VFX whose rendered owner is hidden.
	active_ring.visible = true
	_victory_vfx_remaining = maxf(0.0, _victory_vfx_remaining - delta)
	var progress := 1.0 - _victory_vfx_remaining / maxf(0.1, _victory_vfx_duration)
	var pulse := 1.0 + 0.22 * sin(progress * TAU * 2.0)
	active_ring.scale = Vector3.ONE * pulse
	victory_vfx_receipt["elapsed_seconds"] = _victory_vfx_duration - _victory_vfx_remaining
	victory_vfx_receipt["remaining_seconds"] = _victory_vfx_remaining

func end_victory_presentation(reason: String) -> Dictionary:
	var was_active := _victory_vfx_active
	_victory_vfx_active = false
	_victory_vfx_remaining = 0.0
	active_ring.visible = false
	active_ring.scale = Vector3.ONE
	victory_vfx_receipt["active"] = false
	victory_vfx_receipt["completed"] = was_active
	victory_vfx_receipt["retired_reason"] = reason
	victory_vfx_receipt["retired_process_frame"] = Engine.get_process_frames()
	return victory_vfx_receipt.duplicate(true)

func reset_for_run(spawn_position: Vector3, reset_owner := "run_reset") -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	global_position = spawn_position
	velocity = Vector3.ZERO
	planar_velocity = Vector3.ZERO
	movement_input = Vector2.ZERO
	movement_input_source = "none"
	camera_relative_direction = Vector3.ZERO
	locomotion_state = "idle"
	_dash_direction = Vector3.FORWARD
	_last_move_direction = Vector3.FORWARD
	_pending_dash_generation = -1
	_consumed_dash_generation = -1
	dash_activation_generation = -1
	dash_cycle_count = 0
	dash_command_receipt.clear()
	dash_cooldown_remaining = 0.0
	pickup_collection_radius = 1.75
	experience_yield_multiplier = 1.0
	model_pivot.position = _base_model_position
	model_pivot.rotation = Vector3.ZERO
	model_pivot.scale = Vector3.ONE
	lantern.position = _base_lantern_position
	lantern.rotation = Vector3.ZERO
	presentation_root.scale = _base_presentation_scale
	_apply_authored_model_rebase()
	_restore_and_reapply_hat_isolation(reset_owner)
	end_victory_presentation(reset_owner)
	_victory_vfx_duration = 0.0
	_victory_vfx_generation = -1
	victory_vfx_event_count = 0
	victory_vfx_receipt.clear()
	_set_dash_phase(DashPhase.READY, 0.0)
	animation_binding.reset(reset_owner)
	_follow_lantern_socket()
	reset_input_latch()

func _apply_authored_model_rebase() -> void:
	if is_instance_valid(authored_character):
		authored_character.position = authored_model_rebase

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _resolve_and_apply_shipped_camera_hat_isolation(reason: String) -> bool:
	# Presentation policy lives at the accepted wrapper. The imported GLB,
	# skeleton, animation tracks, transforms and lantern socket stay untouched.
	var resolved := authored_character.find_child(SHIPPED_CAMERA_HAT_NODE_NAME, true, false)
	if not is_instance_valid(resolved) or not resolved is MeshInstance3D or not authored_character.is_ancestor_of(resolved):
		hat_isolation_receipt = {
			"policy":"shipped_camera_self_costume_isolation",
			"resolved":false,
			"isolated":false,
			"requested_node":SHIPPED_CAMERA_HAT_NODE_NAME,
			"reason":reason,
		}
		return false
	if not is_instance_valid(_isolated_hat):
		_isolated_hat = resolved as MeshInstance3D
		_isolated_hat_original_visibility = _isolated_hat.visible
	_isolated_hat.visible = false
	_hat_isolation_generation += 1
	hat_isolation_receipt = {
		"policy":"shipped_camera_self_costume_isolation",
		"resolved":true,
		"isolated":not _isolated_hat.visible,
		"resolved_binding":String(_isolated_hat.get_path()),
		"resolved_type":_isolated_hat.get_class(),
		"source_mesh":String(_isolated_hat.mesh.resource_path) if _isolated_hat.mesh else "",
		"original_visibility":_isolated_hat_original_visibility,
		"authored_character":String(authored_character.get_path()),
		"authored_animation_owner":String(_authored_animation.get_path()) if _authored_animation else "",
		"lantern_socket":String(lantern_socket.get_path()),
		"isolation_generation":_hat_isolation_generation,
		"restoration_generation":_hat_restoration_generation,
		"reason":reason,
	}
	return true

func _restore_and_reapply_hat_isolation(reason: String) -> void:
	if is_instance_valid(_isolated_hat):
		_isolated_hat.visible = _isolated_hat_original_visibility
		_hat_restoration_generation += 1
	_resolve_and_apply_shipped_camera_hat_isolation("%s_reapplied" % reason)

func reset_input_latch(reason := "input_latch_reset") -> void:
	reset_generation += 1
	clear_dash_ownership(reason)
	movement_input = Vector2.ZERO
	movement_input_source = "none"
	# Input ownership resets are also locomotion barriers. Clearing only the
	# sampled input would leave a ready motor carrying its previous velocity
	# through pause, draft, death, or retry and produce a one-frame post-resume
	# slide. Zero the authoritative body velocity at the same boundary.
	velocity = Vector3.ZERO
	planar_velocity = Vector3.ZERO
	locomotion_state = "idle"
	last_reset_receipt = {
		"phase":"input_latch_reset", "reason":reason,
		"reset_generation":reset_generation,
		"dash_generation":dash_activation_generation,
		"dash_phase":dash_phase, "invulnerable":dash_invulnerable,
		"velocity":planar_velocity,
		"process_frame":Engine.get_process_frames(),
	}
	var router := get_node_or_null("../../InputContextRouter")
	if router and router.has_method("clear_movement_latch"):
		router.clear_movement_latch(reason)

func get_movement_snapshot() -> Dictionary:
	return {
		"movement_input": movement_input,
		"movement_input_source": movement_input_source,
		"camera_relative_direction": camera_relative_direction,
		"camera_forward": camera_forward,
		"camera_right": camera_right,
		"velocity": planar_velocity,
		"locomotion_state": locomotion_state,
		"dash_phase": dash_phase,
		"cooldown_remaining": dash_cooldown_remaining,
		"invulnerable": dash_invulnerable,
		"facing_direction": _last_move_direction,
	}

func _mcp_state() -> Dictionary:
	return {
		"movement_input": movement_input,
		"camera_relative_direction":camera_relative_direction,
		"camera_forward":camera_forward,
		"camera_right":camera_right,
		"planar_velocity": planar_velocity,
		"planar_speed": planar_velocity.length(),
		"locomotion_state": locomotion_state,
		"dash_phase": dash_phase,
		"dash_cooldown_remaining": dash_cooldown_remaining,
		"dash_invulnerable": dash_invulnerable,
		"dash_activation_generation":dash_activation_generation,
		"pending_dash_generation":_pending_dash_generation,
		"consumed_dash_generation":_consumed_dash_generation,
		"dash_cycle_count":dash_cycle_count,
		"dash_command_receipt":dash_command_receipt,
		"reset_generation":reset_generation,
		"last_reset_receipt":last_reset_receipt,
		"movement_speed": movement_speed,
		"dash_speed": dash_speed,
		"pickup_collection_radius":pickup_collection_radius,
		"experience_yield_multiplier":experience_yield_multiplier,
		"movement_plane_y": movement_plane_y,
		"plane_error": plane_error,
		"authored_animation": String(_authored_animation.current_animation) if _authored_animation else "none",
		"semantic_animation": animation_binding.get_snapshot() if animation_binding else {},
		"uv_binding":uv_binding_receipt.duplicate(true),
		"hat_isolation":hat_isolation_receipt.duplicate(true),
		"victory_vfx":{"active":_victory_vfx_active,"remaining_seconds":_victory_vfx_remaining,"duration_seconds":_victory_vfx_duration,"generation":_victory_vfx_generation,"event_count":victory_vfx_event_count,"receipt":victory_vfx_receipt},
	}
