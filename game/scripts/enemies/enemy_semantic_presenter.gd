class_name EnemySemanticPresenter
extends Node3D

const DenseProfile := preload("res://scripts/gameplay/dense_profile.gd")
const AuthoredMeshBinding := preload("res://scripts/world/authored_mesh_binding.gd")

const ROLE_DESCRIPTORS := {
	"mossling": "mossling.myconid_guardians.v2",
	"wispbat": "wispbat.gargoyle_lanterns.v2",
	"bone_slinger": "bone_slinger.crypt_casters.v2",
	"grave_brute": "grave_brute.stone_revenants.v2",
}
const ROLE_SCENES := {
	"mossling": preload("res://scenes/enemies/presentation/mossling_presenter.tscn"),
	"wispbat": preload("res://scenes/enemies/presentation/wispbat_presenter.tscn"),
	"bone_slinger": preload("res://scenes/enemies/presentation/bone_slinger_presenter.tscn"),
	"grave_brute": preload("res://scenes/enemies/presentation/grave_brute_presenter.tscn"),
}
const SEMANTICS := ["spawn", "approach", "telegraph", "damage", "recovery", "hurt", "death"]
const DENSE_APPROACH_ANIMATION_BUCKETS := 3

var role_id := "none"
var variant_id := "none"
var semantic_state := "pooled"
var active_motion_id := "none"
var _time := 0.0
var _state_time := 0.0
var _presentation: Node3D
var _active_variant: Node3D
var _animation_player: AnimationPlayer
var _authored_clip := &""
var _base_position := Vector3.ZERO
var _base_rotation := Vector3.ZERO
var _base_scale := Vector3.ONE
var _animation_bucket := 0
var _pending_animation_delta := 0.0
var _presentation_updates := 0
var _presentation_skips := 0
var _priority_updates := 0
var _manual_animation_enabled := false
var binding_status := "unbound"
var binding_error := ""
var motion_signature := "none"
var mesh_binding_receipt: Dictionary = {}

func configure(next_role_id: String, _accent: Color, stable_id: StringName, generation: int, allocated_variant_index: int = -1) -> void:
	role_id = next_role_id
	_animation_bucket = DenseProfile.bucket_for(stable_id, generation, DENSE_APPROACH_ANIMATION_BUCKETS)
	binding_status = "binding"
	binding_error = ""
	_pending_animation_delta = 0.0
	_presentation_updates = 0
	_presentation_skips = 0
	_priority_updates = 0
	var variant_index := clampi(allocated_variant_index, 0, 1) if allocated_variant_index >= 0 else DenseProfile.bucket_for(stable_id, generation * 17, 2)
	motion_signature = "%s:%s" % [next_role_id, variant_index]
	variant_id = "%s.variant_%s" % [ROLE_DESCRIPTORS.get(role_id, "unknown"), ["a", "b"][variant_index]]
	_build_role(variant_index)
	set_semantic("spawn")

func reset_presenter() -> void:
	semantic_state = "pooled"
	active_motion_id = "none"
	_time = 0.0
	_state_time = 0.0
	_animation_player = null
	_manual_animation_enabled = false
	binding_status = "unbound"
	binding_error = ""
	_active_variant = null
	_presentation = null
	mesh_binding_receipt.clear()
	motion_signature = "none"
	for child in get_children():
		child.queue_free()

func set_semantic(next_state: String) -> void:
	semantic_state = next_state if next_state in SEMANTICS else "approach"
	active_motion_id = "%s.%s" % [variant_id, semantic_state]
	_state_time = 0.0
	_restore_pose()
	_play_authored_motion()

func advance(delta: float, planar_velocity: Vector3, remaining: float = 0.0, duration: float = 0.0, priority_override: bool = false) -> void:
	_time += delta
	_state_time += delta
	_pending_animation_delta += delta
	if not is_instance_valid(_active_variant):
		return
	var priority_state := semantic_state != "approach" or priority_override
	var presentation_due := priority_state or posmod(Engine.get_physics_frames(), DENSE_APPROACH_ANIMATION_BUCKETS) == _animation_bucket
	if not presentation_due:
		_presentation_skips += 1
		return
	_presentation_updates += 1
	if priority_state:
		_priority_updates += 1
	if _manual_animation_enabled and _animation_player.is_playing():
		_animation_player.advance(_pending_animation_delta)
	_pending_animation_delta = 0.0
	_restore_pose()
	var speed := Vector2(planar_velocity.x, planar_velocity.z).length()
	match semantic_state:
		"spawn":
			var settle := clampf(_state_time / 0.28, 0.0, 1.0)
			_active_variant.scale = _base_scale * lerpf(0.82, 1.0, settle)
		"approach":
			# Every role has a distinct, velocity-driven locomotion cue. These are
			# additive to the authored clip and never replace the imported rig.
			var stride := sin(_time * (5.0 + speed * 0.7))
			match role_id:
				"mossling":
					_active_variant.position.y += absf(stride) * 0.045
					_active_variant.rotation.z = _base_rotation.z + stride * 0.028
				"wispbat":
					_active_variant.position.y += sin(_time * (5.0 + speed)) * 0.12
					_active_variant.rotation.y = _base_rotation.y + sin(_time * 3.5) * 0.11
				"bone_slinger":
					_active_variant.rotation.x = _base_rotation.x + stride * 0.055
					_active_variant.position.y += absf(stride) * 0.028
				"grave_brute":
					_active_variant.position.y += absf(stride) * 0.06
					_active_variant.scale = _base_scale * (1.0 + absf(stride) * 0.018)
		"telegraph":
			var charge := 1.0 - clampf(remaining / maxf(duration, 0.01), 0.0, 1.0)
			var telegraph_axis := -0.16
			if role_id == "wispbat": telegraph_axis = -0.24
			elif role_id == "bone_slinger": telegraph_axis = 0.18
			elif role_id == "grave_brute": telegraph_axis = -0.1
			_active_variant.rotation.x = _base_rotation.x + charge * telegraph_axis
			_active_variant.scale = _base_scale * Vector3(1.0 + charge * (0.05 if role_id != "grave_brute" else 0.08), 1.0 - charge * 0.04, 1.0 + charge * 0.05)
		"damage":
			var strike := sin(clampf(_state_time / 0.22, 0.0, 1.0) * PI)
			var strike_axis := 0.32 if role_id in ["mossling", "grave_brute"] else 0.22
			_active_variant.rotation.x = _base_rotation.x + strike * strike_axis
			if role_id == "bone_slinger": _active_variant.rotation.z = _base_rotation.z - strike * 0.2
			elif role_id == "wispbat": _active_variant.position.y += strike * 0.14
		"recovery":
			_active_variant.rotation.z = _base_rotation.z + sin(_state_time * 8.0) * 0.035
		"hurt":
			var recoil := sin(clampf(_state_time / 0.18, 0.0, 1.0) * PI)
			_active_variant.rotation.z = _base_rotation.z + recoil * 0.18
		"death":
			var fall := ease(clampf(_state_time / 0.52, 0.0, 1.0), 0.65)
			var fall_axis := 1.42 if role_id != "wispbat" else 0.9
			_active_variant.rotation.z = _base_rotation.z + fall * fall_axis
			_active_variant.position.y -= fall * 0.26

func presentation_descriptor() -> String:
	return String(ROLE_DESCRIPTORS.get(role_id, "none"))

func semantic_bindings() -> Dictionary:
	var result := {}
	for semantic in SEMANTICS:
		result[semantic] = "%s.%s" % [variant_id, semantic]
	return result

func _build_role(variant_index: int) -> void:
	for child in get_children():
		child.queue_free()
	var packed: PackedScene = ROLE_SCENES.get(role_id)
	if packed == null:
		_fail_binding("missing_role_scene:%s" % role_id)
		return
	_presentation = packed.instantiate() as Node3D
	_presentation.name = "AuthoredRolePresentation"
	add_child(_presentation)
	var variants: Array[Node] = _presentation.get_children()
	for index in variants.size():
		var candidate := variants[index] as Node3D
		if index == variant_index:
			candidate.visible = true
			_active_variant = candidate
		else:
			# Each pooled actor needs one authored runtime variant. Removing the
			# unselected imported hierarchy prevents its hidden skeleton and
			# AnimationPlayer from consuming dense-wave work.
			_presentation.remove_child(candidate)
			candidate.free()
	if not is_instance_valid(_active_variant):
		_fail_binding("missing_authored_variant:%s" % role_id)
		return
	binding_status = "bound"
	_base_position = _active_variant.position
	_base_rotation = _active_variant.rotation
	_base_scale = _active_variant.scale
	mesh_binding_receipt = AuthoredMeshBinding.repair_visible_meshes(_active_variant)
	_apply_dense_render_budget(_active_variant)
	_apply_role_material_treatment(_active_variant, variant_index)
	_animation_player = _find_animation_player(_active_variant)
	_authored_clip = _select_authored_clip(_animation_player)
	if _animation_player:
		_animation_player.set_process_callback(AnimationPlayer.ANIMATION_PROCESS_MANUAL)
		_manual_animation_enabled = true

func _fail_binding(reason: String) -> void:
	# Development builds must make a missing authored role obvious.  There is no
	# shared hostile-lantern fallback: the actor remains unbound and carries a
	# visible red marker so QA can stop on the exact role/package mismatch.
	binding_status = "error"
	binding_error = reason
	if OS.has_feature("editor"):
		var marker := Label3D.new()
		marker.name = "MissingRoleBinding"
		marker.text = "MISSING ROLE\n%s" % role_id.to_upper()
		marker.modulate = Color(1.0, 0.18, 0.16, 1.0)
		marker.outline_size = 8
		marker.position = Vector3(0.0, 1.4, 0.0)
		add_child(marker)

func _select_authored_clip(candidate: AnimationPlayer) -> StringName:
	if candidate == null:
		return &""
	for clip in candidate.get_animation_list():
		var normalized := String(clip).to_lower()
		if not normalized.contains("t-pose") and normalized != "reset":
			return clip
	return &""

func _play_authored_motion() -> void:
	if _animation_player == null or _authored_clip == &"":
		return
	if semantic_state in ["spawn", "approach", "telegraph", "damage", "recovery"]:
		_animation_player.play(_authored_clip, 0.1)
		if _manual_animation_enabled:
			_animation_player.advance(0.0)
	else:
		_animation_player.stop()

func presentation_budget_snapshot() -> Dictionary:
	var attempts := _presentation_updates + _presentation_skips
	return {
		"bucket_count":DENSE_APPROACH_ANIMATION_BUCKETS,
		"bucket":_animation_bucket,
		"manual_animation":_manual_animation_enabled,
		"updates":_presentation_updates,
		"skips":_presentation_skips,
		"priority_updates":_priority_updates,
		"update_ratio":float(_presentation_updates) / float(attempts) if attempts > 0 else 0.0,
		"binding_status":binding_status,
		"binding_error":binding_error,
		"motion_signature":motion_signature,
		"role_motion_profile":role_id,
		"mesh_binding":mesh_binding_receipt.duplicate(true),
	}

func _restore_pose() -> void:
	if not is_instance_valid(_active_variant):
		return
	_active_variant.position = _base_position
	_active_variant.rotation = _base_rotation
	_active_variant.scale = _base_scale

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _apply_role_material_treatment(node: Node, variant_index: int) -> void:
	# The Gargoyle source intentionally ships with neutral white material data.
	# Give each authored use a cemetery-specific stone treatment while keeping
	# its imported mesh, rig, proportions, hierarchy, and animation intact.
	if variant_index == 0 and role_id in ["wispbat", "grave_brute"]:
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("324658") if role_id == "wispbat" else Color("45434c")
		stone.roughness = 0.76
		stone.metallic = 0.08
		stone.emission_enabled = true
		stone.emission = Color("2ebbb0") if role_id == "wispbat" else Color("9c375f")
		stone.emission_energy_multiplier = 0.28
		_set_material_recursive(node, stone)

func _set_material_recursive(node: Node, material: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = material
	for child in node.get_children():
		_set_material_recursive(child, material)

func _apply_dense_render_budget(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		geometry.lod_bias = 0.35
	for child in node.get_children():
		_apply_dense_render_budget(child)
