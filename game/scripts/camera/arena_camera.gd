class_name ArenaCamera
extends Camera3D

@export var target: Node3D
@export var follow_height := 10.8
@export var follow_distance := 8.6
@export var follow_damping := 8.5
@export var lead_distance := 2.4
@export var lead_damping := 5.0
@export var arena_limit := Vector2(10.5, 8.5)
@export var normal_fov := 48.0
@export var visibility_activation_seconds := 0.04
@export var visibility_release_seconds := 0.22
@export var visibility_probe_overscan := 1.25
@export var presentation_body: NodePath
@export var presentation_lantern: NodePath
@export var presentation_effects: Array[NodePath] = []

const VISIBILITY_LAYER := 20

var movement_velocity := Vector3.ZERO
var framing_target := Vector3.ZERO
var occlusion_guard_active := false
var _lead := Vector3.ZERO
var _blocked_seconds := 0.0
var _clear_seconds := 0.0
var _visibility_samples_blocked := 0
var _last_occluder := ""
var _presentation_visuals: Array[VisualInstance3D] = []
var _source_visuals: Array[VisualInstance3D] = []
var _effect_visuals: Array[VisualInstance3D] = []
var _binding_members: Array[Dictionary] = []
var _original_visual_layers: Dictionary = {}
var _original_visual_visibility: Dictionary = {}
var _body_readability_overlay: StandardMaterial3D
var _primary_camera_visibility_layer := true
var _visibility_viewport: SubViewport
var _visibility_camera: Camera3D
var _visibility_canvas: CanvasLayer
var _visibility_texture: TextureRect
var _compositor_frame_count := 0

func _ready() -> void:
	current = true
	fov = normal_fov
	if target:
		_bind_visibility_presentation()
		_build_visibility_compositor()
		_snap_to_target()

func set_movement_velocity(value: Vector3) -> void:
	movement_velocity = Vector3(value.x, 0.0, value.z)

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var desired_lead := Vector3.ZERO
	if movement_velocity.length_squared() > 0.04:
		desired_lead = movement_velocity.normalized() * lead_distance
	_lead = _lead.lerp(desired_lead, 1.0 - exp(-lead_damping * delta))
	framing_target = target.global_position + _lead
	framing_target.x = clampf(framing_target.x, -arena_limit.x, arena_limit.x)
	framing_target.z = clampf(framing_target.z, -arena_limit.y, arena_limit.y)
	# Framing remains stable. Visibility isolation is driven by the live
	# camera-to-Warden sightline and never by player coordinates or map edits.
	_update_visibility_isolation(delta)
	fov = normal_fov
	var desired_position := framing_target + Vector3(0.0, follow_height, follow_distance)
	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_damping * delta))
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)
	_sync_visibility_camera()

func _bind_visibility_presentation() -> void:
	# The compositor owns a concrete Warden contract rather than assuming every
	# descendant can move between view layers. Imported skinned geometry stays on
	# its authored instance and receives a camera-owned no-depth readability pass;
	# shipped effects use the private layer compositor. No duplicate actor exists.
	_bind_member("body", presentation_body)
	_bind_member("lantern", presentation_lantern)
	for effect_path in presentation_effects:
		var effect := get_node_or_null(effect_path)
		if not is_instance_valid(effect):
			continue
		var visuals := _collect_visuals(effect)
		for visual in visuals:
			_register_visual(visual)
			_effect_visuals.append(visual)
		_binding_members.append({"role":"effect", "bound":true, "source_path":String(effect_path), "isolation":"private_layer_compositor", "visual_count":visuals.size()})

func _bind_member(role: String, source_path: NodePath) -> void:
	var source := get_node_or_null(source_path)
	var source_members := _collect_visuals(source)
	for visual in source_members:
		_register_visual(visual)
		_source_visuals.append(visual)
	_binding_members.append({
		"role":role,
		"bound":is_instance_valid(source),
		"source_path":String(source_path),
		"isolation":"direct_no_depth_guard",
		"source_visual_count":source_members.size(),
	})

func _get_body_readability_overlay() -> StandardMaterial3D:
	if is_instance_valid(_body_readability_overlay):
		return _body_readability_overlay
	_body_readability_overlay = StandardMaterial3D.new()
	_body_readability_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_body_readability_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_readability_overlay.albedo_color = Color(0.18, 0.82, 0.88, 0.62)
	_body_readability_overlay.emission_enabled = true
	_body_readability_overlay.emission = Color(0.08, 0.62, 0.76, 1.0)
	_body_readability_overlay.emission_energy_multiplier = 1.6
	_body_readability_overlay.disable_fog = true
	_body_readability_overlay.no_depth_test = true
	return _body_readability_overlay

func _collect_visuals(root: Node) -> Array[VisualInstance3D]:
	var result: Array[VisualInstance3D] = []
	if not is_instance_valid(root):
		return result
	if root is VisualInstance3D:
		result.append(root as VisualInstance3D)
	for child in root.find_children("*", "VisualInstance3D", true, false):
		if child is VisualInstance3D:
			result.append(child as VisualInstance3D)
	return result

func _register_visual(visual: VisualInstance3D) -> void:
	if _presentation_visuals.has(visual):
		return
	_presentation_visuals.append(visual)
	_original_visual_layers[visual.get_instance_id()] = visual.layers
	_original_visual_visibility[visual.get_instance_id()] = visual.visible

func _build_visibility_compositor() -> void:
	# The isolation camera shares the live World3D but renders only the Warden's
	# private visibility layer onto a transparent full-viewport texture. This is
	# a camera-owned composition boundary: cemetery geometry remains untouched
	# and cannot depth-occlude the isolated silhouette.
	_primary_camera_visibility_layer = get_cull_mask_value(VISIBILITY_LAYER)
	_visibility_viewport = SubViewport.new()
	_visibility_viewport.name = "WardenVisibilityViewport"
	_visibility_viewport.transparent_bg = true
	_visibility_viewport.own_world_3d = false
	_visibility_viewport.world_3d = get_world_3d()
	_visibility_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_visibility_viewport.size = get_viewport().get_visible_rect().size
	add_child(_visibility_viewport)
	_visibility_camera = Camera3D.new()
	_visibility_camera.name = "WardenVisibilityCamera"
	_visibility_camera.cull_mask = 0
	_visibility_camera.set_cull_mask_value(VISIBILITY_LAYER, true)
	_visibility_camera.current = true
	_visibility_viewport.add_child(_visibility_camera)
	_visibility_canvas = CanvasLayer.new()
	_visibility_canvas.name = "WardenVisibilityCanvas"
	_visibility_canvas.layer = 8
	add_child(_visibility_canvas)
	_visibility_texture = TextureRect.new()
	_visibility_texture.name = "WardenVisibilityTexture"
	_visibility_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visibility_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_visibility_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_visibility_texture.texture = _visibility_viewport.get_texture()
	_visibility_texture.visible = false
	_visibility_canvas.add_child(_visibility_texture)
	_resize_visibility_compositor()
	get_viewport().size_changed.connect(_resize_visibility_compositor)

func _resize_visibility_compositor() -> void:
	if not is_instance_valid(_visibility_viewport) or not is_instance_valid(_visibility_texture):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_visibility_viewport.size = Vector2i(maxi(1, int(viewport_size.x)), maxi(1, int(viewport_size.y)))
	_visibility_texture.position = Vector2.ZERO
	_visibility_texture.size = viewport_size

func _sync_visibility_camera() -> void:
	if not is_instance_valid(_visibility_camera):
		return
	_visibility_camera.global_transform = global_transform
	_visibility_camera.projection = projection
	_visibility_camera.fov = fov
	_visibility_camera.size = size
	_visibility_camera.near = near
	_visibility_camera.far = far
	_visibility_camera.frustum_offset = frustum_offset
	if occlusion_guard_active:
		_compositor_frame_count += 1

func _update_visibility_isolation(delta: float) -> void:
	_visibility_samples_blocked = 0
	_last_occluder = ""
	var space_state := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	# The horizontal play datum is never a screen-space occluder. Excluding its
	# collision RID prevents a low body sample from falsely isolating the actor.
	var ground := get_node_or_null("../CemeteryGarden/OuterDatum/GroundCollision") as CollisionObject3D
	if is_instance_valid(ground):
		exclude.append(ground.get_rid())
	for height in [0.45, 0.95, 1.45]:
		var target_point: Vector3 = target.global_position + Vector3.UP * float(height)
		var sight_direction: Vector3 = (target_point - global_position).normalized()
		var query := PhysicsRayQueryParameters3D.new()
		query.from = global_position
		# Imported collision proxies are intentionally conservative. Extend the
		# sightline by roughly one actor depth so overlap is detected while the
		# silhouette is entering cover, not only after its origin disappears.
		query.to = target_point + sight_direction * visibility_probe_overscan
		query.exclude = exclude
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			_visibility_samples_blocked += 1
			if _last_occluder.is_empty() and is_instance_valid(hit.get("collider")):
				_last_occluder = String((hit.collider as Node).get_path())
	if _visibility_samples_blocked > 0:
		_blocked_seconds += delta
		_clear_seconds = 0.0
	else:
		_clear_seconds += delta
		_blocked_seconds = 0.0
	var next_active := occlusion_guard_active
	if not next_active and _blocked_seconds >= visibility_activation_seconds:
		next_active = true
	elif next_active and _clear_seconds >= visibility_release_seconds:
		next_active = false
	if next_active != occlusion_guard_active:
		occlusion_guard_active = next_active
		_apply_visibility_overlay(occlusion_guard_active)

func _apply_visibility_overlay(active: bool) -> void:
	if not is_instance_valid(_visibility_viewport) or not is_instance_valid(_visibility_texture):
		return
	for visual in _source_visuals:
		if is_instance_valid(visual):
			visual.visible = bool(_original_visual_visibility.get(visual.get_instance_id(), true))
			visual.layers = int(_original_visual_layers.get(visual.get_instance_id(), 1))
			if visual is GeometryInstance3D:
				(visual as GeometryInstance3D).material_overlay = _get_body_readability_overlay() if active else null
	for visual in _effect_visuals:
		if not is_instance_valid(visual):
			continue
		visual.layers = 1 << (VISIBILITY_LAYER - 1) if active else int(_original_visual_layers.get(visual.get_instance_id(), 1))
	set_cull_mask_value(VISIBILITY_LAYER, not active and _primary_camera_visibility_layer)
	_visibility_texture.visible = active
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if active:
		_sync_visibility_camera()

func _snap_to_target() -> void:
	framing_target = target.global_position
	global_position = framing_target + Vector3(0.0, follow_height, follow_distance)
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)

func _original_presentation_restored() -> bool:
	if occlusion_guard_active:
		return false
	for visual in _presentation_visuals:
		if not is_instance_valid(visual):
			return false
		if visual.layers != int(_original_visual_layers.get(visual.get_instance_id(), visual.layers)):
			return false
		if visual.visible != bool(_original_visual_visibility.get(visual.get_instance_id(), visual.visible)):
			return false
		if is_instance_valid(_body_readability_overlay) and visual is GeometryInstance3D and (visual as GeometryInstance3D).material_overlay == _body_readability_overlay:
			return false
	return true

func _mcp_state() -> Dictionary:
	return {
		"framing_target": framing_target,
		"movement_velocity": movement_velocity,
		"follow_height": follow_height,
		"follow_distance": follow_distance,
		"occlusion_guard_active": occlusion_guard_active,
		"presentation_binding_complete": _binding_members.size() == 5 and _source_visuals.size() >= 2 and _effect_visuals.size() == 3,
		"presentation_roles": ["body", "lantern", "dash_aura", "active_ring", "warden_halo"],
		"original_presentation_restored": _original_presentation_restored(),
		"visibility_isolation": {
			"active": occlusion_guard_active, "blocked_samples": _visibility_samples_blocked,
			"sample_count": 3, "blocked_seconds": _blocked_seconds,
			"clear_seconds": _clear_seconds, "last_occluder": _last_occluder,
				"strategy": "explicit_whole_warden_binding",
				"isolated_visual_count": _presentation_visuals.size(),
				"source_visual_count": _source_visuals.size(),
				"isolation_visual_count": _source_visuals.size() + _effect_visuals.size(),
				"effect_visual_count": _effect_visuals.size(),
				"binding_members": _binding_members.duplicate(true),
				"binding_complete": _binding_members.size() == 5 and _source_visuals.size() >= 2 and _effect_visuals.size() == 3,
			"compositor_visible": _visibility_texture.visible if is_instance_valid(_visibility_texture) else false,
			"compositor_updates": _visibility_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS if is_instance_valid(_visibility_viewport) else false,
			"compositor_frame_count": _compositor_frame_count,
			"primary_camera_visibility_layer": get_cull_mask_value(VISIBILITY_LAYER),
			"probe_overscan": visibility_probe_overscan,
		},
		"lead_distance": lead_distance,
		"fov": fov,
	}
