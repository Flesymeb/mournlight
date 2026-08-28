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
@export var safe_frame_fraction := Vector2(0.18, 0.24)
@export var safe_frame_activation_buffer := 0.04
@export var safe_frame_correction_damping := 11.0
@export var safe_frame_max_correction := 1.25
@export var safe_frame_actor_half_width := 0.72
@export var safe_frame_actor_half_depth := 0.48
@export var safe_frame_actor_height := 2.05
@export var visibility_activation_seconds := 0.04
@export var visibility_release_seconds := 0.22
@export var visibility_probe_overscan := 1.25
@export var presentation_body: NodePath
@export var presentation_lantern: NodePath
@export var presentation_effects: Array[NodePath] = []
@export var tall_occluders: Array[NodePath] = []
@export var direct_sight_volume_radius := 0.9

const VISIBILITY_LAYER := 20

var movement_velocity := Vector3.ZERO
var framing_target := Vector3.ZERO
var occlusion_guard_active := false
var safe_frame_ok := true
var safe_frame_correction_active := false
var projected_margins := {"left":0.0, "right":0.0, "top":0.0, "bottom":0.0, "minimum":0.0}
var _lead := Vector3.ZERO
var _safe_frame_offset := Vector3.ZERO
var _safe_frame_screen_shift := Vector2.ZERO
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
var _original_material_overlays: Dictionary = {}
var _primary_camera_visibility_layer := true
var _visibility_viewport: SubViewport
var _visibility_camera: Camera3D
var _visibility_canvas: CanvasLayer
var _visibility_texture: TextureRect
var _compositor_frame_count := 0
var _tall_occluder_bindings: Array[Dictionary] = []
var _direct_detection_active := false
var _detection_source := "clear"

func _ready() -> void:
	current = true
	fov = normal_fov
	if target:
		_bind_visibility_presentation()
		_bind_tall_occluders()
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
	var requested_target := target.global_position + _lead
	var arena_target := requested_target
	arena_target.x = clampf(arena_target.x, -arena_limit.x, arena_limit.x)
	arena_target.z = clampf(arena_target.z, -arena_limit.y, arena_limit.y)
	var before := _measure_projected_safe_frame()
	var activation_fraction := Vector2(
		safe_frame_fraction.x + safe_frame_activation_buffer,
		safe_frame_fraction.y + safe_frame_activation_buffer
	)
	var approaching_edge := not _margins_inside_fraction(before, activation_fraction)
	var inside_release_band := _margins_inside_fraction(before, Vector2(activation_fraction.x + safe_frame_activation_buffer, activation_fraction.y + safe_frame_activation_buffer))
	var desired_offset := Vector3.ZERO
	_safe_frame_screen_shift = Vector2.ZERO
	if approaching_edge:
		_safe_frame_screen_shift = _screen_shift_into_fraction(before, activation_fraction)
		desired_offset = _safe_frame_offset + _screen_shift_to_ground_correction(before, _safe_frame_screen_shift)
		desired_offset.y = 0.0
		desired_offset = desired_offset.limit_length(safe_frame_max_correction)
	elif safe_frame_correction_active and not inside_release_band:
		desired_offset = _safe_frame_offset
	_safe_frame_offset = _safe_frame_offset.lerp(desired_offset, 1.0 - exp(-safe_frame_correction_damping * delta))
	framing_target = arena_target + _safe_frame_offset
	fov = normal_fov
	var desired_position := framing_target + Vector3(0.0, follow_height, follow_distance)
	global_position = global_position.lerp(desired_position, 1.0 - exp(-follow_damping * delta))
	look_at(framing_target + Vector3(0.0, 0.65, 0.0), Vector3.UP)
	var after := _measure_projected_safe_frame()
	projected_margins = (after.get("margins", {}) as Dictionary).duplicate(true)
	safe_frame_ok = bool(after.get("inside_fraction", false))
	safe_frame_correction_active = _safe_frame_offset.length_squared() > 0.0025 or not safe_frame_ok
	# Projected containment owns framing. Sightline isolation remains a secondary
	# response to cemetery geometry that genuinely crosses the camera-to-Warden ray.
	_update_visibility_isolation(delta)
	_sync_visibility_camera()

func _measure_projected_safe_frame() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0 or not is_instance_valid(target):
		return {"inside_fraction":false, "margins":projected_margins.duplicate(true), "center":Vector2.ZERO, "rect":Rect2()}
	var min_screen := Vector2(INF, INF)
	var max_screen := Vector2(-INF, -INF)
	var center_world := target.global_position + Vector3.UP * safe_frame_actor_height * 0.5
	for x_offset in [-safe_frame_actor_half_width, safe_frame_actor_half_width]:
		for y_offset in [0.05, safe_frame_actor_height]:
			for z_offset in [-safe_frame_actor_half_depth, safe_frame_actor_half_depth]:
				var world_point := target.global_position + Vector3(x_offset, y_offset, z_offset)
				if is_position_behind(world_point):
					return {"inside_fraction":false, "margins":{"left":-INF,"right":-INF,"top":-INF,"bottom":-INF,"minimum":-INF}, "center":Vector2.ZERO, "rect":Rect2()}
				var screen := unproject_position(world_point)
				min_screen.x = minf(min_screen.x, screen.x)
				min_screen.y = minf(min_screen.y, screen.y)
				max_screen.x = maxf(max_screen.x, screen.x)
				max_screen.y = maxf(max_screen.y, screen.y)
	var margins := {
		"left":min_screen.x, "right":viewport_size.x - max_screen.x,
		"top":min_screen.y, "bottom":viewport_size.y - max_screen.y,
	}
	margins["minimum"] = minf(minf(float(margins.left), float(margins.right)), minf(float(margins.top), float(margins.bottom)))
	var receipt := {
		"viewport":viewport_size,
		"center":unproject_position(center_world),
		"rect":Rect2(min_screen, max_screen - min_screen),
		"margins":margins,
	}
	receipt["inside_fraction"] = _margins_inside_fraction(receipt, safe_frame_fraction)
	return receipt

func _margins_inside_fraction(receipt: Dictionary, fraction: Vector2) -> bool:
	var viewport_size: Vector2 = receipt.get("viewport", get_viewport().get_visible_rect().size)
	var margins: Dictionary = receipt.get("margins", {})
	return (
		float(margins.get("left", -INF)) >= viewport_size.x * fraction.x
		and float(margins.get("right", -INF)) >= viewport_size.x * fraction.x
		and float(margins.get("top", -INF)) >= viewport_size.y * fraction.y
		and float(margins.get("bottom", -INF)) >= viewport_size.y * fraction.y
	)

func _screen_shift_into_fraction(receipt: Dictionary, fraction: Vector2) -> Vector2:
	var viewport_size: Vector2 = receipt.get("viewport", get_viewport().get_visible_rect().size)
	var rect: Rect2 = receipt.get("rect", Rect2())
	var safe_min := Vector2(viewport_size.x * fraction.x, viewport_size.y * fraction.y)
	var safe_max := Vector2(viewport_size.x * (1.0 - fraction.x), viewport_size.y * (1.0 - fraction.y))
	var shift := Vector2.ZERO
	if rect.position.x < safe_min.x:
		shift.x = safe_min.x - rect.position.x
	elif rect.end.x > safe_max.x:
		shift.x = safe_max.x - rect.end.x
	if rect.position.y < safe_min.y:
		shift.y = safe_min.y - rect.position.y
	elif rect.end.y > safe_max.y:
		shift.y = safe_max.y - rect.end.y
	return shift

func _screen_shift_to_ground_correction(receipt: Dictionary, shift: Vector2) -> Vector3:
	if shift.length_squared() < 0.01:
		return Vector3.ZERO
	var center: Vector2 = receipt.get("center", Vector2.ZERO)
	var current_ground := _screen_to_target_plane(center)
	var desired_ground := _screen_to_target_plane(center + shift)
	return current_ground - desired_ground

func _screen_to_target_plane(screen: Vector2) -> Vector3:
	var origin := project_ray_origin(screen)
	var direction := project_ray_normal(screen)
	if absf(direction.y) < 0.0001:
		return target.global_position
	var distance := (target.global_position.y - origin.y) / direction.y
	return origin + direction * maxf(0.0, distance)

func _bind_visibility_presentation() -> void:
	# The compositor owns the complete concrete Warden contract. Every authored
	# body, lantern, and effect visual moves through the same private camera layer
	# while obstructed; no proxy material or duplicate actor exists.
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
		_binding_members.append({"role":"effect", "bound":true, "source_path":String(effect_path), "isolation":"complete_private_layer_compositor", "visual_count":visuals.size()})

func _bind_tall_occluders() -> void:
	_tall_occluder_bindings.clear()
	for source_path in tall_occluders:
		var body := get_node_or_null(source_path) as CollisionObject3D
		var shapes: Array[CollisionShape3D] = []
		if is_instance_valid(body):
			for child in body.find_children("*", "CollisionShape3D", true, false):
				if child is CollisionShape3D and is_instance_valid((child as CollisionShape3D).shape):
					shapes.append(child as CollisionShape3D)
		_tall_occluder_bindings.append({
			"source_path":String(source_path),
			"resolved_path":String(body.get_path()) if is_instance_valid(body) else "",
			"body":body,
			"shapes":shapes,
			"bound":is_instance_valid(body) and not shapes.is_empty(),
			"shape_count":shapes.size(),
		})

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
		"isolation":"complete_private_layer_compositor",
		"source_visual_count":source_members.size(),
	})

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
	if visual is GeometryInstance3D:
		_original_material_overlays[visual.get_instance_id()] = (visual as GeometryInstance3D).material_overlay

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
	_direct_detection_active = false
	_detection_source = "clear"
	var direct_occluder := _find_registered_sight_occluder()
	if not direct_occluder.is_empty():
		_direct_detection_active = true
		_detection_source = "registered_tall_occluder_sight_volume"
		_last_occluder = direct_occluder
		_visibility_samples_blocked = 1
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
		if _direct_detection_active:
			break
		var target_point: Vector3 = target.global_position + Vector3.UP * float(height)
		var query := PhysicsRayQueryParameters3D.new()
		query.from = global_position
		# The ray remains a fallback for unregistered incidental geometry. Tall
		# authored occluders are owned by the explicit conservative volume above,
		# so activation no longer depends on overscanning this short ray.
		query.to = target_point
		query.exclude = exclude
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			_detection_source = "fallback_physics_ray"
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

func _find_registered_sight_occluder() -> String:
	if not is_instance_valid(target):
		return ""
	var target_points := [
		target.global_position + Vector3.UP * 0.35,
		target.global_position + Vector3.UP * 1.0,
		target.global_position + Vector3.UP * 1.75,
	]
	for binding in _tall_occluder_bindings:
		if not bool(binding.get("bound", false)):
			continue
		for shape in binding.get("shapes", []):
			if not is_instance_valid(shape) or shape.disabled:
				continue
			for target_point in target_points:
				if _sight_segment_intersects_shape_volume(global_position, target_point, shape):
					return String(binding.get("resolved_path", binding.get("source_path", "")))
	return ""

func _sight_segment_intersects_shape_volume(from_world: Vector3, to_world: Vector3, collision_shape: CollisionShape3D) -> bool:
	var shape_transform := collision_shape.global_transform
	var local_from := shape_transform.affine_inverse() * from_world
	var local_to := shape_transform.affine_inverse() * to_world
	var extents := Vector3.ONE * direct_sight_volume_radius
	if collision_shape.shape is BoxShape3D:
		extents += (collision_shape.shape as BoxShape3D).size * 0.5
	elif collision_shape.shape is CylinderShape3D:
		var cylinder := collision_shape.shape as CylinderShape3D
		extents += Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
	elif collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		extents += Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)
	else:
		return false
	return _segment_intersects_centered_aabb(local_from, local_to, extents)

func _segment_intersects_centered_aabb(from: Vector3, to: Vector3, extents: Vector3) -> bool:
	var direction := to - from
	var entry := 0.0
	var exit := 1.0
	for axis in 3:
		var origin := from[axis]
		var delta := direction[axis]
		var minimum := -extents[axis]
		var maximum := extents[axis]
		if absf(delta) <= 0.00001:
			if origin < minimum or origin > maximum:
				return false
			continue
		var inverse := 1.0 / delta
		var near_time := (minimum - origin) * inverse
		var far_time := (maximum - origin) * inverse
		if near_time > far_time:
			var swap := near_time
			near_time = far_time
			far_time = swap
		entry = maxf(entry, near_time)
		exit = minf(exit, far_time)
		if entry > exit:
			return false
	return true

func _apply_visibility_overlay(active: bool) -> void:
	if not is_instance_valid(_visibility_viewport) or not is_instance_valid(_visibility_texture):
		return
	for visual in _presentation_visuals:
		if not is_instance_valid(visual):
			continue
		var instance_id := visual.get_instance_id()
		visual.visible = bool(_original_visual_visibility.get(instance_id, true))
		visual.layers = 1 << (VISIBILITY_LAYER - 1) if active else int(_original_visual_layers.get(instance_id, 1))
		if visual is GeometryInstance3D:
			(visual as GeometryInstance3D).material_overlay = _original_material_overlays.get(instance_id) as Material
	set_cull_mask_value(VISIBILITY_LAYER, not active and _primary_camera_visibility_layer)
	_visibility_texture.visible = active
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if active:
		_sync_visibility_camera()

func _snap_to_target() -> void:
	framing_target = target.global_position
	_safe_frame_offset = Vector3.ZERO
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
		if visual is GeometryInstance3D and (visual as GeometryInstance3D).material_overlay != (_original_material_overlays.get(visual.get_instance_id()) as Material):
			return false
	return true

func _mcp_state() -> Dictionary:
	return {
		"binding_member_count": _binding_members.size(),
		"compositor_updates": _visibility_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS if is_instance_valid(_visibility_viewport) else false,
		"effect_visual_count": _effect_visuals.size(),
		"framing_target": framing_target,
		"safe_frame_ok":safe_frame_ok,
		"safe_frame_correction_active":safe_frame_correction_active,
		"safe_frame_offset":_safe_frame_offset,
		"safe_frame_screen_shift":_safe_frame_screen_shift,
		"projected_margins":projected_margins.duplicate(true),
		"safe_frame_fraction":safe_frame_fraction,
		"isolated_visual_count": _presentation_visuals.size(),
		"movement_velocity": movement_velocity,
		"follow_height": follow_height,
		"follow_distance": follow_distance,
		"occlusion_guard_active": occlusion_guard_active,
		"direct_occluder_detection_active":_direct_detection_active,
		"occluder_detection_source":_detection_source,
		"active_occluder_path":_last_occluder,
		"registered_tall_occluder_count":_tall_occluder_bindings.filter(func(binding: Dictionary) -> bool: return bool(binding.get("bound", false))).size(),
		"presentation_binding_complete": _binding_members.size() == 5 and _source_visuals.size() >= 2 and _effect_visuals.size() == 3,
		"presentation_roles": ["body", "lantern", "dash_aura", "active_ring", "warden_halo"],
		"original_presentation_restored": _original_presentation_restored(),
		"primary_camera_visibility_layer": get_cull_mask_value(VISIBILITY_LAYER),
		"source_visual_count": _source_visuals.size(),
		"visibility_strategy": "projected_safe_frame_with_secondary_private_layer_compositor",
		"tall_occluder_registry":{
			"requested_count":tall_occluders.size(),
			"bound_count":_tall_occluder_bindings.filter(func(binding: Dictionary) -> bool: return bool(binding.get("bound", false))).size(),
			"bindings":_tall_occluder_bindings.map(func(binding: Dictionary) -> Dictionary: return {
				"source_path":binding.get("source_path", ""), "resolved_path":binding.get("resolved_path", ""),
				"bound":binding.get("bound", false), "shape_count":binding.get("shape_count", 0),
			}),
			"sight_volume_radius":direct_sight_volume_radius,
			"direct_detection_active":_direct_detection_active,
			"detection_source":_detection_source,
		},
		"visibility_isolation": {
			"active": occlusion_guard_active, "blocked_samples": _visibility_samples_blocked,
			"sample_count": 3, "blocked_seconds": _blocked_seconds,
			"clear_seconds": _clear_seconds, "last_occluder": _last_occluder,
				"strategy": "complete_private_layer_compositor",
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
