class_name WardenAnimationBinding
extends Node

signal semantic_state_changed(previous: String, current: String)

const REQUIRED_STATES := ["idle", "move", "dash", "cast", "hurt", "death", "victory"]
const LOOPING_STATES := ["idle", "move"]

var player: AnimationPlayer
var skeleton: Skeleton3D
var semantic_clips: Dictionary = {}
var explicit_profile_mappings: Dictionary = {}
var deformation_tracks: Dictionary = {}
var semantic_state := "idle"
var previous_state := ""
var event_hold := 0.0
var binding_valid := false
var missing_semantics: Array[String] = []
var rejected_source_clips: Array[String] = []
var profile_id := "unbound"
var terminal_state := ""

func bind(root: Node, profile: Resource) -> void:
	player = _find_player(root)
	skeleton = _find_skeleton(root)
	semantic_clips.clear()
	explicit_profile_mappings.clear()
	deformation_tracks.clear()
	missing_semantics.clear()
	rejected_source_clips.clear()
	binding_valid = false
	terminal_state = ""
	profile_id = "missing_profile"
	if profile:
		profile_id = String(profile.get_meta("profile_id", "unnamed"))
		explicit_profile_mappings = (profile.get_meta("semantic_clips", {}) as Dictionary).duplicate(true)
	if not player or not skeleton:
		missing_semantics.assign(REQUIRED_STATES)
		return
	var available := player.get_animation_list()
	for semantic in REQUIRED_STATES:
		var exact_name := StringName(explicit_profile_mappings.get(semantic, ""))
		var track_count := _deformation_track_count(exact_name)
		if exact_name == &"" or not player.has_animation(exact_name) or track_count <= 0:
			missing_semantics.append(semantic)
		else:
			semantic_clips[semantic] = exact_name
			deformation_tracks[semantic] = track_count
	var distinct := {}
	for clip in semantic_clips.values():
		distinct[String(clip)] = true
	binding_valid = missing_semantics.is_empty() and distinct.size() == REQUIRED_STATES.size() and skeleton.get_bone_count() > 0
	if not binding_valid:
		for clip in available:
			rejected_source_clips.append(String(clip))
		player.stop()
		return
	_play("idle", true)

func drive(planar_speed: float, dash_phase: String, delta: float) -> void:
	if not terminal_state.is_empty():
		return
	event_hold = maxf(0.0, event_hold - delta)
	if event_hold > 0.0:
		return
	if dash_phase in ["anticipation", "active", "recovery"]:
		set_semantic("dash")
	elif planar_speed > 0.3:
		set_semantic("move")
	else:
		set_semantic("idle")

func trigger(event_state: String, duration := 0.32) -> void:
	if not terminal_state.is_empty() and event_state != terminal_state:
		return
	if event_state in ["death", "victory"]:
		terminal_state = event_state
		if player:
			player.process_mode = Node.PROCESS_MODE_ALWAYS
	set_semantic(event_state, true)
	event_hold = duration

func set_semantic(next_state: String, restart := false) -> void:
	if next_state not in REQUIRED_STATES:
		return
	if next_state == semantic_state and not restart:
		if next_state in LOOPING_STATES and player and not player.is_playing():
			_play(next_state, true)
		return
	previous_state = semantic_state
	semantic_state = next_state
	_play(next_state, restart)
	semantic_state_changed.emit(previous_state, semantic_state)

func _play(state: String, restart: bool) -> void:
	if not binding_valid or not semantic_clips.has(state):
		return
	var clip: StringName = semantic_clips[state]
	if restart or player.current_animation != clip or not player.is_playing():
		player.play(clip, 0.12)

func reset() -> void:
	event_hold = 0.0
	terminal_state = ""
	if player:
		player.process_mode = Node.PROCESS_MODE_INHERIT
	set_semantic("idle", true)

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

func _deformation_track_count(clip: StringName) -> int:
	if clip == &"" or not player or not player.has_animation(clip):
		return 0
	var animation := player.get_animation(clip)
	if not animation:
		return 0
	var count := 0
	for index in animation.get_track_count():
		var path := String(animation.track_get_path(index))
		if "Skeleton3D:" in path:
			count += 1
	return count

func get_snapshot() -> Dictionary:
	var distinct_clips := {}
	for clip in semantic_clips.values():
		distinct_clips[String(clip)] = true
	return {"semantic_state":semantic_state,"previous_state":previous_state,
		"resolved_clip":String(semantic_clips.get(semantic_state, &"")),"clip_map":semantic_clips,
		"explicit_profile_mappings":explicit_profile_mappings,"profile_id":profile_id,
		"binding_valid":binding_valid,"event_hold":event_hold,"missing_semantics":missing_semantics,
		"rejected_source_clips":rejected_source_clips,"terminal_state":terminal_state,
		"animation_owner_path":String(player.get_path()) if player else "",
		"animation_owner_root":String(player.root_node) if player else "",
		"deformation_owner_path":String(skeleton.get_path()) if skeleton else "",
		"deformation_bone_count":skeleton.get_bone_count() if skeleton else 0,
		"deformation_hierarchy":_deformation_hierarchy(),
		"deformation_tracks":deformation_tracks,
		"source_clip_count":player.get_animation_list().size() if player else 0,
		"explicit_mapping_count":explicit_profile_mappings.size(),
		"distinct_resolved_clip_count":distinct_clips.size(),"truthful_fail_closed":not binding_valid}

func _deformation_hierarchy() -> Dictionary:
	if not skeleton:
		return {}
	var roots: Array[String] = []
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_parent(index) < 0:
			roots.append(skeleton.get_bone_name(index))
	return {"skeleton":skeleton.name,"bone_count":skeleton.get_bone_count(),"root_bones":roots}
