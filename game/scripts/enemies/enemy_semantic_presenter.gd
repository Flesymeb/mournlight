class_name EnemySemanticPresenter
extends Node3D

const ROLE_DESCRIPTORS := {
	"mossling": "mossling.rooted_guardian.v1",
	"wispbat": "wispbat.nightwing.v1",
	"bone_slinger": "bone_slinger.crypt_archer.v1",
	"grave_brute": "grave_brute.tomb_bearer.v1",
}
const SEMANTICS := ["spawn", "approach", "telegraph", "damage", "recovery", "hurt", "death"]

var role_id := "none"
var variant_id := "none"
var semantic_state := "pooled"
var active_motion_id := "none"
var _time := 0.0
var _state_time := 0.0
var _parts: Dictionary = {}
var _base_positions: Dictionary = {}
var _base_rotations: Dictionary = {}
var _accent := Color.WHITE

func configure(next_role_id: String, accent: Color, stable_id: StringName, generation: int) -> void:
	role_id = next_role_id
	_accent = accent
	var variant_index := posmod(String(stable_id).hash() + generation * 17, 3)
	variant_id = "%s.variant_%s" % [ROLE_DESCRIPTORS.get(role_id, "unknown"), ["thorn", "relic", "ward"][variant_index]]
	_build_role(variant_index)
	set_semantic("spawn")

func reset_presenter() -> void:
	semantic_state = "pooled"
	active_motion_id = "none"
	_time = 0.0
	_state_time = 0.0
	for child in get_children():
		child.queue_free()
	_parts.clear()
	_base_positions.clear()
	_base_rotations.clear()

func set_semantic(next_state: String) -> void:
	semantic_state = next_state if next_state in SEMANTICS else "approach"
	active_motion_id = "%s.%s" % [variant_id, semantic_state]
	_state_time = 0.0
	_restore_pose()

func advance(delta: float, planar_velocity: Vector3, remaining: float = 0.0, duration: float = 0.0) -> void:
	_time += delta
	_state_time += delta
	var speed := Vector2(planar_velocity.x, planar_velocity.z).length()
	var cycle := _time * (4.5 + minf(speed, 4.0))
	match role_id:
		"mossling": _pose_mossling(cycle, speed, remaining, duration)
		"wispbat": _pose_wispbat(cycle, speed, remaining, duration)
		"bone_slinger": _pose_slinger(cycle, speed, remaining, duration)
		"grave_brute": _pose_brute(cycle, speed, remaining, duration)

func presentation_descriptor() -> String:
	return String(ROLE_DESCRIPTORS.get(role_id, "none"))

func semantic_bindings() -> Dictionary:
	var result := {}
	for semantic in SEMANTICS:
		result[semantic] = "%s.%s" % [variant_id, semantic]
	return result

func _build_role(variant: int) -> void:
	for child in get_children():
		child.queue_free()
	_parts.clear()
	_base_positions.clear()
	_base_rotations.clear()
	match role_id:
		"mossling": _build_mossling(variant)
		"wispbat": _build_wispbat(variant)
		"bone_slinger": _build_slinger(variant)
		"grave_brute": _build_brute(variant)

func _build_mossling(variant: int) -> void:
	var bark := _material(Color("26351f"), 0.74)
	var moss := _material(Color("668c39"), 0.18)
	var bone := _material(Color("c9c19d"), 0.08)
	_part("torso", "sphere", Vector3(0, 0.78, 0), Vector3(0.62, 0.7, 0.52), bark)
	_part("head", "sphere", Vector3(0, 1.42, -0.08), Vector3(0.46, 0.38, 0.42), moss)
	_part("jaw", "box", Vector3(0, 1.26, -0.38), Vector3(0.36, 0.16, 0.24), bark)
	_part("arm_l", "capsule", Vector3(-0.57, 0.72, -0.04), Vector3(0.22, 0.6, 0.22), bark)
	_part("arm_r", "capsule", Vector3(0.57, 0.72, -0.04), Vector3(0.22, 0.6, 0.22), bark)
	_part("leg_l", "capsule", Vector3(-0.25, 0.25, 0.02), Vector3(0.25, 0.42, 0.25), moss)
	_part("leg_r", "capsule", Vector3(0.25, 0.25, 0.02), Vector3(0.25, 0.42, 0.25), moss)
	_part("tuft_l", "cone", Vector3(-0.28, 1.78, 0), Vector3(0.18, 0.42, 0.18), moss)
	_part("tuft_r", "cone", Vector3(0.18, 1.8, 0.02), Vector3(0.15, 0.34, 0.15), moss)
	if variant == 0: _part("detail", "cone", Vector3(0.46, 1.55, 0), Vector3(0.14, 0.52, 0.14), bone, Vector3(0, 0, -0.7))
	elif variant == 1: _part("detail", "sphere", Vector3(-0.5, 1.02, 0.12), Vector3(0.28, 0.28, 0.16), moss)
	else: _part("detail", "box", Vector3(0, 0.92, 0.48), Vector3(0.62, 0.46, 0.13), bone)

func _build_wispbat(variant: int) -> void:
	var hide := _material(Color("32234a"), 0.4)
	var wing := _material(Color("8b3fa1"), 0.22)
	var glow := _material(Color("ef73ff"), 2.3)
	_part("body", "sphere", Vector3(0, 1.25, 0), Vector3(0.34, 0.46, 0.3), hide)
	_part("head", "sphere", Vector3(0, 1.62, -0.12), Vector3(0.3, 0.25, 0.3), hide)
	_part("wing_l", "box", Vector3(-0.58, 1.38, 0), Vector3(0.78, 0.08, 0.56), wing, Vector3(0, 0.18, -0.22))
	_part("wing_r", "box", Vector3(0.58, 1.38, 0), Vector3(0.78, 0.08, 0.56), wing, Vector3(0, -0.18, 0.22))
	_part("ear_l", "cone", Vector3(-0.16, 1.93, -0.08), Vector3(0.12, 0.42, 0.12), hide, Vector3(0,0,-0.25))
	_part("ear_r", "cone", Vector3(0.16, 1.93, -0.08), Vector3(0.12, 0.42, 0.12), hide, Vector3(0,0,0.25))
	_part("core", "sphere", Vector3(0, 1.4, -0.29), Vector3(0.12, 0.12, 0.12), glow)
	if variant == 0: _part("detail", "cone", Vector3(0, 0.82, 0.1), Vector3(0.1, 0.65, 0.1), wing, Vector3(0.7,0,0))
	elif variant == 1: _part("detail", "torus", Vector3(0, 1.4, 0.18), Vector3(0.32, 0.32, 0.12), glow, Vector3(PI*0.5,0,0))
	else: _part("detail", "box", Vector3(0, 1.18, 0.28), Vector3(0.48, 0.12, 0.28), wing)

func _build_slinger(variant: int) -> void:
	var bone := _material(Color("c8c2a4"), 0.08)
	var cloth := _material(Color("274b51"), 0.32)
	var teal := _material(Color("55dbc9"), 1.8)
	_part("pelvis", "box", Vector3(0, 0.68, 0), Vector3(0.45, 0.24, 0.32), cloth)
	_part("spine", "capsule", Vector3(0, 1.08, 0), Vector3(0.19, 0.7, 0.19), bone)
	_part("head", "sphere", Vector3(0, 1.62, -0.04), Vector3(0.31, 0.34, 0.3), bone)
	_part("arm_l", "capsule", Vector3(-0.38, 1.18, -0.12), Vector3(0.13, 0.66, 0.13), bone, Vector3(0,0,-0.45))
	_part("arm_r", "capsule", Vector3(0.42, 1.14, -0.16), Vector3(0.13, 0.68, 0.13), bone, Vector3(0,0,0.45))
	_part("leg_l", "capsule", Vector3(-0.2, 0.3, 0), Vector3(0.15, 0.52, 0.15), bone)
	_part("leg_r", "capsule", Vector3(0.2, 0.3, 0), Vector3(0.15, 0.52, 0.15), bone)
	_part("bow", "torus", Vector3(-0.64, 1.16, -0.22), Vector3(0.56, 0.56, 0.09), teal, Vector3(0,PI*0.5,0))
	if variant == 0: _part("detail", "box", Vector3(0.5, 1.2, 0.24), Vector3(0.22, 0.72, 0.18), cloth, Vector3(0,0,-0.15))
	elif variant == 1: _part("detail", "cone", Vector3(0, 1.98, 0), Vector3(0.25, 0.5, 0.25), cloth)
	else: _part("detail", "box", Vector3(0, 1.06, 0.24), Vector3(0.75, 0.12, 0.18), teal)

func _build_brute(variant: int) -> void:
	var stone := _material(Color("3f4651"), 0.7)
	var hide := _material(Color("40572f"), 0.42)
	var ember := _material(Color("d34f79"), 2.0)
	_part("torso", "box", Vector3(0, 1.05, 0), Vector3(1.05, 1.05, 0.72), stone)
	_part("head", "sphere", Vector3(0, 1.78, -0.16), Vector3(0.43, 0.4, 0.4), hide)
	_part("arm_l", "capsule", Vector3(-0.72, 0.92, -0.08), Vector3(0.34, 0.92, 0.34), hide, Vector3(0,0,-0.18))
	_part("arm_r", "capsule", Vector3(0.72, 0.92, -0.08), Vector3(0.34, 0.92, 0.34), hide, Vector3(0,0,0.18))
	_part("leg_l", "capsule", Vector3(-0.34, 0.28, 0), Vector3(0.31, 0.5, 0.31), hide)
	_part("leg_r", "capsule", Vector3(0.34, 0.28, 0), Vector3(0.31, 0.5, 0.31), hide)
	_part("tomb", "box", Vector3(0, 1.28, 0.56), Vector3(0.92, 1.34, 0.2), stone, Vector3(-0.12,0,0))
	_part("rune", "torus", Vector3(0, 1.3, -0.39), Vector3(0.24, 0.24, 0.07), ember, Vector3(PI*0.5,0,0))
	if variant == 0: _part("detail", "cone", Vector3(-0.58, 1.84, 0), Vector3(0.22, 0.62, 0.22), stone, Vector3(0,0,-0.5))
	elif variant == 1: _part("detail", "box", Vector3(0.6, 1.66, 0.1), Vector3(0.3, 0.72, 0.34), ember)
	else: _part("detail", "torus", Vector3(0, 2.05, 0), Vector3(0.36, 0.36, 0.09), stone, Vector3(PI*0.5,0,0))

func _part(part_name: String, shape: String, at: Vector3, part_scale: Vector3, material: Material, rotation := Vector3.ZERO) -> void:
	var pivot := Node3D.new()
	pivot.name = part_name
	pivot.position = at
	pivot.rotation = rotation
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Surface"
	mesh_instance.mesh = _mesh(shape)
	mesh_instance.scale = part_scale
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(mesh_instance)
	add_child(pivot)
	_parts[part_name] = pivot
	_base_positions[part_name] = at
	_base_rotations[part_name] = rotation

func _mesh(shape: String) -> PrimitiveMesh:
	match shape:
		"box": return BoxMesh.new()
		"capsule":
			var mesh := CapsuleMesh.new(); mesh.radial_segments = 8; mesh.rings = 4; return mesh
		"cone":
			var mesh := CylinderMesh.new(); mesh.top_radius = 0.0; mesh.bottom_radius = 0.5; mesh.radial_segments = 7; return mesh
		"torus":
			var mesh := TorusMesh.new(); mesh.rings = 12; mesh.ring_segments = 5; return mesh
		_:
			var mesh := SphereMesh.new(); mesh.radial_segments = 8; mesh.rings = 5; return mesh

func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	if emission > 1.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

func _restore_pose() -> void:
	for key in _parts:
		var part: Node3D = _parts[key]
		part.position = _base_positions[key]
		part.rotation = _base_rotations[key]

func _pose_mossling(cycle: float, speed: float, remaining: float, duration: float) -> void:
	var stride := sin(cycle) * minf(speed / 2.0, 1.0)
	_pose_standard(stride, 0.42)
	if semantic_state == "spawn":
		_part_rot("tuft_l", Vector3(0,0,sin(_state_time*9.0)*0.2)); _part_rot("tuft_r", Vector3(0,0,-sin(_state_time*9.0)*0.2))
	elif semantic_state == "telegraph":
		_part_rot("arm_l", Vector3(-0.8,0,-0.5)); _part_rot("arm_r", Vector3(-0.8,0,0.5)); _part_rot("head", Vector3(-0.25,0,0))
	elif semantic_state == "damage":
		_part_rot("arm_l", Vector3(1.15,0,-0.25)); _part_rot("arm_r", Vector3(1.15,0,0.25))
	_pose_terminal()

func _pose_wispbat(cycle: float, speed: float, remaining: float, duration: float) -> void:
	var flap := sin(cycle * 1.45)
	_part_rot("wing_l", Vector3(0,0,-0.25-flap*0.72)); _part_rot("wing_r", Vector3(0,0,0.25+flap*0.72))
	_part_pos("body", Vector3(0, sin(cycle*0.7)*0.08, 0))
	if semantic_state == "telegraph":
		_part_rot("wing_l", Vector3(0,0,-1.05)); _part_rot("wing_r", Vector3(0,0,1.05)); _part_pos("head", Vector3(0,-0.12,-0.16))
	elif semantic_state == "damage":
		_part_rot("wing_l", Vector3(0.55,0,-0.15)); _part_rot("wing_r", Vector3(0.55,0,0.15)); _part_pos("head", Vector3(0,0,-0.3))
	_pose_terminal()

func _pose_slinger(cycle: float, speed: float, remaining: float, duration: float) -> void:
	var stride := sin(cycle) * minf(speed / 2.0, 1.0)
	_pose_standard(stride, 0.55)
	if semantic_state == "telegraph":
		var draw := 1.0 - clampf(remaining / maxf(duration,0.01), 0.0, 1.0)
		_part_rot("arm_l", Vector3(-0.55,0,-0.9)); _part_rot("arm_r", Vector3(-0.45,0,0.25+draw*0.75)); _part_pos("bow", Vector3(-0.06,0,-0.18))
	elif semantic_state == "damage":
		_part_rot("arm_l", Vector3(-0.2,0,-0.45)); _part_rot("arm_r", Vector3(0.7,0,-0.2))
	_pose_terminal()

func _pose_brute(cycle: float, speed: float, remaining: float, duration: float) -> void:
	var stride := sin(cycle*0.65) * minf(speed / 1.4, 1.0)
	_pose_standard(stride, 0.26)
	if semantic_state == "telegraph":
		var charge := 1.0-clampf(remaining/maxf(duration,0.01),0.0,1.0)
		_part_rot("arm_l", Vector3(-1.4*charge,0,-0.3)); _part_rot("arm_r", Vector3(-1.4*charge,0,0.3)); _part_rot("torso", Vector3(-0.25*charge,0,0))
	elif semantic_state == "damage":
		_part_rot("arm_l", Vector3(1.25,0,-0.15)); _part_rot("arm_r", Vector3(1.25,0,0.15)); _part_rot("torso", Vector3(0.38,0,0))
	_pose_terminal()

func _pose_standard(stride: float, amount: float) -> void:
	if semantic_state == "approach":
		_part_rot("leg_l", Vector3(stride*amount,0,0)); _part_rot("leg_r", Vector3(-stride*amount,0,0))
		_part_rot("arm_l", Vector3(-stride*amount*0.7,0,0)); _part_rot("arm_r", Vector3(stride*amount*0.7,0,0))
	elif semantic_state == "recovery":
		_part_rot("head", Vector3(sin(_state_time*7.0)*0.08,0,0))

func _pose_terminal() -> void:
	if semantic_state == "hurt":
		_part_rot("head", Vector3(0.22,0,sin(_state_time*18.0)*0.14)); _part_rot("torso", Vector3(0,0,sin(_state_time*16.0)*0.1))
	elif semantic_state == "death":
		var fall := clampf(_state_time/0.48,0.0,1.0)
		for part_name in _parts:
			var sign_value := -1.0 if String(part_name).hash()%2==0 else 1.0
			_part_rot(String(part_name), Vector3(fall*(0.5+absf(sign_value)*0.25),0,sign_value*fall*0.9))
			_part_pos(String(part_name), Vector3(sign_value*fall*0.16,-fall*0.34,0))

func _part_rot(part_name: String, delta_rotation: Vector3) -> void:
	if _parts.has(part_name): (_parts[part_name] as Node3D).rotation = (_base_rotations[part_name] as Vector3) + delta_rotation

func _part_pos(part_name: String, delta_position: Vector3) -> void:
	if _parts.has(part_name): (_parts[part_name] as Node3D).position = (_base_positions[part_name] as Vector3) + delta_position
