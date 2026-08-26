class_name SurvivalFoundation
extends Node3D

@export var run_state := "active"
@export var pause_state := "running"

@onready var warden: WardenController = $Warden
@onready var pause_overlay: PauseOverlay = $Interface/PauseOverlay
@onready var dash_label: Label = $Interface/HUD/DashCluster/DashLabel
@onready var dash_meter: ProgressBar = $Interface/HUD/DashCluster/DashMeter
@onready var dash_icon: Control = $Interface/HUD/DashCluster/DashIcon

var _materials: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_materials()
	_build_cemetery()
	warden.dash_phase_changed.connect(_on_dash_phase_changed)
	warden.dash_readiness_changed.connect(_on_dash_readiness_changed)
	_on_dash_phase_changed("ready", false)
	get_tree().paused = false

func _exit_tree() -> void:
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if warden.dash_phase == "cooldown":
		dash_meter.value = 1.0 - clampf(warden.dash_cooldown_remaining / warden.cooldown_duration, 0.0, 1.0)

func _toggle_pause() -> void:
	var should_pause := not get_tree().paused
	warden.reset_input_latch()
	if should_pause:
		pause_state = "paused"
		run_state = "ui_paused"
		pause_overlay.present(warden.get_movement_snapshot())
		get_tree().paused = true
	else:
		get_tree().paused = false
		pause_overlay.dismiss()
		warden.reset_input_latch()
		pause_state = "running"
		run_state = "active"

func _on_dash_phase_changed(phase: String, _invulnerable: bool) -> void:
	match phase:
		"ready":
			dash_label.text = "DASH READY"
			dash_meter.value = 1.0
			dash_label.modulate = Color("ffe0a0")
		"anticipation":
			dash_label.text = "FOCUSING"
			dash_meter.value = 0.2
			dash_label.modulate = Color("ffc35d")
		"active":
			dash_label.text = "PHASE SHIFT"
			dash_meter.value = 1.0
			dash_label.modulate = Color("79fff2")
		"recovery":
			dash_label.text = "STEADYING"
			dash_meter.value = 0.08
			dash_label.modulate = Color("f5b5ff")
		"cooldown":
			dash_label.text = "REKINDLING"
			dash_meter.value = 0.0
			dash_label.modulate = Color("b9b7d9")
	dash_icon.queue_redraw()

func _on_dash_readiness_changed(ready: bool, remaining: float) -> void:
	if ready:
		dash_meter.value = 1.0
	elif warden.dash_phase == "cooldown":
		dash_meter.value = 1.0 - clampf(remaining / warden.cooldown_duration, 0.0, 1.0)

func _build_materials() -> void:
	_materials.stone = _material(Color("25283a"), 0.92)
	_materials.stone_edge = _material(Color("3d425a"), 0.78)
	_materials.path = _material(Color("414258"), 0.9)
	_materials.path_light = _material(Color("55556b"), 0.86)
	_materials.grass = _material(Color("18262a"), 1.0)
	_materials.grass_light = _material(Color("253a38"), 0.95)
	_materials.iron = _material(Color("101520"), 0.55, Color.BLACK, 0.72)
	_materials.bark = _material(Color("30232c"), 0.98)
	_materials.leaf = _material(Color("1d3434"), 0.96)
	_materials.leaf_violet = _material(Color("302941"), 0.96)
	_materials.brass = _material(Color("7a5023"), 0.42, Color.BLACK, 0.55)
	_materials.warm = _material(Color("ffb542"), 0.25, Color("ff6c1a"), 4.2)
	_materials.moon = _material(Color("9dc8db"), 0.52, Color("335f84"), 1.15)
	_materials.teal = _material(Color("2fc7bd"), 0.4, Color("106d77"), 2.5)
	_materials.magenta = _material(Color("c74fba"), 0.38, Color("6d185f"), 2.1)
	_materials.door = _material(Color("161923"), 0.72)

func _material(color: Color, roughness: float, emission := Color.BLACK, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.0
	return material

func _build_cemetery() -> void:
	var world := Node3D.new()
	world.name = "AuthoredCemetery"
	add_child(world)
	_build_ground(world)
	_build_boundaries(world)
	_build_mausoleum(world, Vector3(8.6, 0.0, -7.4))
	_build_bell_landmark(world, Vector3(-10.2, 0.0, -7.5))
	_build_lantern_post(world, Vector3(-4.8, 0.0, 1.8))
	_build_lantern_post(world, Vector3(7.2, 0.0, 5.3))
	_build_grave_garden(world)
	_build_trees(world)
	_build_moon_motifs(world)

func _build_ground(parent: Node3D) -> void:
	_add_box(parent, "GardenGround", Vector3(32.0, 0.7, 24.0), Vector3(0, -0.38, 0), _materials.grass, true)
	for z in range(-10, 11, 2):
		_add_box(parent, "CrossPathZ_%s" % z, Vector3(4.3, 0.08, 1.72), Vector3(0, 0.025, z), _materials.path if z % 4 == 0 else _materials.path_light)
	for x in range(-14, 15, 2):
		_add_box(parent, "CrossPathX_%s" % x, Vector3(1.72, 0.08, 3.4), Vector3(x, 0.03, 1.3), _materials.path if x % 4 == 0 else _materials.path_light)
	for x in [-12.5, -8.5, 9.5, 13.0]:
		for z in [-3.8, 6.7]:
			_add_disc(parent, "GroundAccent", Vector3(x, 0.018, z), 1.2, _materials.grass_light)

func _build_boundaries(parent: Node3D) -> void:
	_add_box(parent, "NorthWall", Vector3(32.8, 1.15, 0.55), Vector3(0, 0.52, -12.05), _materials.stone_edge, true)
	_add_box(parent, "SouthWall", Vector3(32.8, 1.15, 0.55), Vector3(0, 0.52, 12.05), _materials.stone_edge, true)
	_add_box(parent, "WestWall", Vector3(0.55, 1.15, 24.0), Vector3(-16.05, 0.52, 0), _materials.stone_edge, true)
	_add_box(parent, "EastWall", Vector3(0.55, 1.15, 24.0), Vector3(16.05, 0.52, 0), _materials.stone_edge, true)
	for x in range(-15, 16, 3):
		_add_pillar(parent, Vector3(x, 1.22, -12.05), 0.38, 2.25, _materials.stone)
		_add_pillar(parent, Vector3(x, 1.22, 12.05), 0.38, 2.25, _materials.stone)
	for z in range(-9, 10, 3):
		_add_pillar(parent, Vector3(-16.05, 1.22, z), 0.38, 2.25, _materials.stone)
		_add_pillar(parent, Vector3(16.05, 1.22, z), 0.38, 2.25, _materials.stone)

func _build_mausoleum(parent: Node3D, origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "MoonMausoleum"
	root.position = origin
	parent.add_child(root)
	_add_box(root, "Foundation", Vector3(5.2, 0.6, 3.7), Vector3(0, 0.3, 0), _materials.stone_edge, true)
	_add_box(root, "Hall", Vector3(4.2, 3.3, 2.8), Vector3(0, 2.15, -0.1), _materials.stone, true)
	_add_box(root, "Roof", Vector3(5.0, 0.65, 3.55), Vector3(0, 4.02, -0.1), _materials.stone_edge)
	_add_box(root, "Door", Vector3(1.35, 2.45, 0.16), Vector3(0, 1.76, 1.34), _materials.door)
	for x in [-1.65, 1.65]:
		_add_pillar(root, Vector3(x, 1.9, 1.48), 0.28, 3.2, _materials.stone_edge)
		_add_lamp(root, Vector3(x * 0.72, 1.15, 1.55))
	_add_disc(root, "MoonSeal", Vector3(0, 3.05, 1.51), 0.42, _materials.moon, Vector3(1.5708, 0, 0))

func _build_bell_landmark(parent: Node3D, origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "CrackedMoonBell"
	root.position = origin
	parent.add_child(root)
	_add_box(root, "BellPlinth", Vector3(4.2, 0.65, 3.1), Vector3(0, 0.32, 0), _materials.stone_edge, true)
	for x in [-1.35, 1.35]:
		_add_pillar(root, Vector3(x, 2.2, 0), 0.34, 3.9, _materials.stone)
	_add_box(root, "ArchBeam", Vector3(3.4, 0.5, 0.7), Vector3(0, 4.05, 0), _materials.stone)
	_add_cylinder(root, "Bell", Vector3(0, 2.85, 0), 0.76, 1.25, _materials.brass)
	_add_cylinder(root, "BellGlow", Vector3(0.15, 2.8, 0.05), 0.28, 0.7, _materials.warm)
	_add_box(root, "Crack", Vector3(0.07, 0.8, 0.82), Vector3(0.18, 2.82, 0.12), _materials.door)

func _build_lantern_post(parent: Node3D, origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "KeeperLanternPost"
	root.position = origin
	parent.add_child(root)
	_add_pillar(root, Vector3(0, 1.65, 0), 0.16, 3.2, _materials.iron)
	_add_box(root, "Hook", Vector3(0.85, 0.13, 0.13), Vector3(0.34, 3.08, 0), _materials.brass)
	_add_box(root, "LanternFrame", Vector3(0.5, 0.68, 0.5), Vector3(0.7, 2.67, 0), _materials.brass)
	_add_cylinder(root, "LanternGlass", Vector3(0.7, 2.67, 0), 0.16, 0.48, _materials.warm)
	_add_lamp(root, Vector3(0.7, 2.68, 0), 5.4)

func _build_grave_garden(parent: Node3D) -> void:
	var grave_positions := [
		Vector3(-7.8, 0, -2.5), Vector3(-10.5, 0, -1.3), Vector3(-13.0, 0, -4.4),
		Vector3(-7.0, 0, 5.7), Vector3(-10.2, 0, 7.1), Vector3(-13.3, 0, 4.7),
		Vector3(6.2, 0, -3.1), Vector3(11.2, 0, -2.2), Vector3(13.6, 0, -5.2),
		Vector3(5.7, 0, 7.5), Vector3(10.6, 0, 8.0), Vector3(13.5, 0, 5.0)
	]
	for index in grave_positions.size():
		_build_grave(parent, grave_positions[index], -0.08 + float(index % 3) * 0.08, index % 4 == 0)

func _build_grave(parent: Node3D, origin: Vector3, angle: float, collidable: bool) -> void:
	var root := Node3D.new()
	root.name = "CarvedGrave"
	root.position = origin
	root.rotation.y = angle
	parent.add_child(root)
	_add_box(root, "Base", Vector3(1.15, 0.25, 0.72), Vector3(0, 0.12, 0), _materials.stone_edge, collidable)
	_add_box(root, "Marker", Vector3(0.74, 1.25, 0.24), Vector3(0, 0.85, -0.08), _materials.stone, collidable)
	_add_disc(root, "MoonCarving", Vector3(0, 1.02, 0.055), 0.16, _materials.moon, Vector3(1.5708, 0, 0))
	for offset in [-0.35, 0.34]:
		_add_cylinder(root, "Moss", Vector3(offset, 0.28, 0.1), 0.14, 0.16, _materials.grass_light)

func _build_trees(parent: Node3D) -> void:
	var tree_positions := [Vector3(-14.0, 0, -9.3), Vector3(-14.2, 0, 9.2), Vector3(14.1, 0, -9.1), Vector3(14.2, 0, 9.2), Vector3(-5.6, 0, -9.4)]
	for index in tree_positions.size():
		var root := Node3D.new()
		root.name = "MoonTree"
		root.position = tree_positions[index]
		parent.add_child(root)
		_add_cylinder(root, "Trunk", Vector3(0, 1.4, 0), 0.34, 2.8, _materials.bark)
		_add_sphere(root, "CrownA", Vector3(0, 3.25, 0), Vector3(1.25, 0.95, 1.15), _materials.leaf if index % 2 == 0 else _materials.leaf_violet)
		_add_sphere(root, "CrownB", Vector3(-0.65, 2.9, 0.2), Vector3(0.85, 0.72, 0.8), _materials.leaf)

func _build_moon_motifs(parent: Node3D) -> void:
	for position in [Vector3(-2.8, 0.07, -7.0), Vector3(3.3, 0.07, 6.5), Vector3(9.4, 0.07, 1.3)]:
		_add_disc(parent, "WispSeal", position, 0.34, _materials.teal)
	for position in [Vector3(-11.4, 0.07, 1.4), Vector3(3.5, 0.07, -8.2)]:
		_add_disc(parent, "MourningSeal", position, 0.3, _materials.magenta)

func _add_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material, collidable := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	if collidable:
		_add_collision(parent, part_name + "Collision", BoxShape3D.new(), position, size)
	return instance

func _add_collision(parent: Node3D, collision_name: String, shape: Shape3D, position: Vector3, size: Vector3) -> void:
	if shape is BoxShape3D:
		shape.size = size
	var body := StaticBody3D.new()
	body.name = collision_name
	body.position = position
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func _add_pillar(parent: Node3D, position: Vector3, radius: float, height: float, material: Material) -> void:
	_add_cylinder(parent, "CarvedPillar", position, radius, height, material)

func _add_cylinder(parent: Node3D, part_name: String, position: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.86
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance

func _add_disc(parent: Node3D, part_name: String, position: Vector3, radius: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	mesh.radial_segments = 12
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _add_sphere(parent: Node3D, part_name: String, position: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale_value
	parent.add_child(instance)
	return instance

func _add_lamp(parent: Node3D, position: Vector3, energy := 3.2) -> void:
	var light := OmniLight3D.new()
	light.name = "WarmGuidingLight"
	light.position = position
	light.light_color = Color("ffad4a")
	light.light_energy = energy
	light.omni_range = 6.5
	light.shadow_enabled = true
	parent.add_child(light)

func _mcp_state() -> Dictionary:
	return {
		"run_state": run_state,
		"pause_state": pause_state,
		"tree_paused": get_tree().paused,
	}
