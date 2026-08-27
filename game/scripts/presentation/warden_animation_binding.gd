class_name WardenAnimationBinding
extends Node

signal semantic_state_changed(previous: String, current: String)

const REQUIRED_STATES := ["idle", "move", "dash", "cast", "hurt", "death", "victory"]
const CLIP_TOKENS := {
	"idle":["idle"], "move":["walk", "run", "locomotion"], "dash":["dash", "dodge", "roll"],
	"cast":["cast", "spell", "attack", "shoot"], "hurt":["hurt", "hit", "damage", "impact"],
	"death":["death", "die", "dead"], "victory":["victory", "celebrate", "dance", "cheer"],
}

var player: AnimationPlayer
var semantic_clips: Dictionary = {}
var semantic_state := "idle"
var previous_state := ""
var event_hold := 0.0
var binding_valid := false
var missing_semantics: Array[String] = []
var rejected_source_clips: Array[String] = []

func bind(root: Node) -> void:
	player = _find_player(root)
	semantic_clips.clear()
	missing_semantics.clear()
	rejected_source_clips.clear()
	binding_valid = false
	if not player:
		missing_semantics.assign(REQUIRED_STATES)
		return
	var clips := player.get_animation_list()
	for semantic in REQUIRED_STATES:
		var resolved := _resolve_clip(clips, semantic)
		if resolved == &"":
			missing_semantics.append(semantic)
		else:
			semantic_clips[semantic] = resolved
	var distinct := {}
	for clip in semantic_clips.values():
		distinct[String(clip)] = true
	binding_valid = missing_semantics.is_empty() and distinct.size() == REQUIRED_STATES.size()
	if not binding_valid:
		for clip in clips:
			rejected_source_clips.append(String(clip))
		player.stop()
		return
	_play("idle", true)

func drive(planar_speed: float, dash_phase: String, delta: float) -> void:
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
	set_semantic(event_state, true)
	event_hold = duration

func set_semantic(next_state: String, restart := false) -> void:
	if next_state not in REQUIRED_STATES:
		return
	if next_state == semantic_state and not restart:
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
	set_semantic("idle", true)

func _resolve_clip(clips: PackedStringArray, semantic: String) -> StringName:
	for clip in clips:
		var normalized := String(clip).to_lower()
		for token in CLIP_TOKENS[semantic]:
			if normalized.contains(token):
				return clip
	return &""

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null

func get_snapshot() -> Dictionary:
	return {"semantic_state":semantic_state,"previous_state":previous_state,
		"resolved_clip":String(semantic_clips.get(semantic_state, &"")),"clip_map":semantic_clips,
		"binding_valid":binding_valid,"event_hold":event_hold,"missing_semantics":missing_semantics,
		"rejected_source_clips":rejected_source_clips,"truthful_fail_closed":not binding_valid}
