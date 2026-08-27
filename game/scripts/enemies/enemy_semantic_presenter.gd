class_name EnemySemanticPresenter
extends Node3D

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

func configure(next_role_id: String, _accent: Color, stable_id: StringName, generation: int) -> void:
	role_id = next_role_id
	var variant_index := posmod(String(stable_id).hash() + generation * 17, 2)
	variant_id = "%s.variant_%s" % [ROLE_DESCRIPTORS.get(role_id, "unknown"), ["a", "b"][variant_index]]
	_build_role(variant_index)
	set_semantic("spawn")

func reset_presenter() -> void:
	semantic_state = "pooled"
	active_motion_id = "none"
	_time = 0.0
	_state_time = 0.0
	_animation_player = null
	_active_variant = null
	_presentation = null
	for child in get_children():
		child.queue_free()

func set_semantic(next_state: String) -> void:
	semantic_state = next_state if next_state in SEMANTICS else "approach"
	active_motion_id = "%s.%s" % [variant_id, semantic_state]
	_state_time = 0.0
	_restore_pose()
	_play_authored_motion()

func advance(delta: float, planar_velocity: Vector3, remaining: float = 0.0, duration: float = 0.0) -> void:
	_time += delta
	_state_time += delta
	if not is_instance_valid(_active_variant):
		return
	_restore_pose()
	var speed := Vector2(planar_velocity.x, planar_velocity.z).length()
	match semantic_state:
		"spawn":
			var settle := clampf(_state_time / 0.28, 0.0, 1.0)
			_active_variant.scale = _base_scale * lerpf(0.82, 1.0, settle)
		"approach":
			if role_id == "wispbat":
				_active_variant.position.y += sin(_time * (5.0 + speed)) * 0.08
		"telegraph":
			var charge := 1.0 - clampf(remaining / maxf(duration, 0.01), 0.0, 1.0)
			_active_variant.rotation.x = _base_rotation.x - charge * 0.16
			_active_variant.scale = _base_scale * Vector3(1.0 + charge * 0.05, 1.0 - charge * 0.04, 1.0 + charge * 0.05)
		"damage":
			var strike := sin(clampf(_state_time / 0.22, 0.0, 1.0) * PI)
			_active_variant.rotation.x = _base_rotation.x + strike * 0.32
		"recovery":
			_active_variant.rotation.z = _base_rotation.z + sin(_state_time * 8.0) * 0.035
		"hurt":
			var recoil := sin(clampf(_state_time / 0.18, 0.0, 1.0) * PI)
			_active_variant.rotation.z = _base_rotation.z + recoil * 0.18
		"death":
			var fall := ease(clampf(_state_time / 0.52, 0.0, 1.0), 0.65)
			_active_variant.rotation.z = _base_rotation.z + fall * 1.42
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
		return
	_presentation = packed.instantiate() as Node3D
	_presentation.name = "AuthoredRolePresentation"
	add_child(_presentation)
	var variants: Array[Node] = _presentation.get_children()
	for index in variants.size():
		var candidate := variants[index] as Node3D
		candidate.visible = index == variant_index
		if index == variant_index:
			_active_variant = candidate
	if not is_instance_valid(_active_variant):
		return
	_base_position = _active_variant.position
	_base_rotation = _active_variant.rotation
	_base_scale = _active_variant.scale
	_apply_role_material_treatment(_active_variant, variant_index)
	_animation_player = _find_animation_player(_active_variant)
	_authored_clip = _select_authored_clip(_animation_player)

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
	else:
		_animation_player.stop()

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
