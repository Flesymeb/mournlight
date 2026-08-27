class_name WardenAnimationBinding
extends Node

signal semantic_state_changed(previous: String, current: String)

const SOURCE_CLIP_PREFIX := "metarig_003|metarig_003|metarig_003|"
const SEMANTIC_SPEED := {"idle":0.82,"move":1.18,"dash":1.55,"cast":1.28,"hurt":0.72,"death":0.42,"victory":0.66}

var player: AnimationPlayer
var source_clip: StringName
var semantic_state := "idle"
var previous_state := ""
var event_hold := 0.0
var binding_valid := false

func bind(root: Node) -> void:
	player = _find_player(root)
	binding_valid = false
	if not player:
		return
	var clips := player.get_animation_list()
	if clips.size() == 1 and String(clips[0]).begins_with(SOURCE_CLIP_PREFIX):
		source_clip = clips[0]
		binding_valid = true
		player.play(source_clip)
		player.speed_scale = float(SEMANTIC_SPEED.idle)

func drive(planar_speed: float, dash_phase: String, delta: float) -> void:
	event_hold = maxf(0.0, event_hold - delta)
	if event_hold > 0.0:
		return
	if dash_phase in ["anticipation","active","recovery"]:
		set_semantic("dash")
	elif planar_speed > 0.3:
		set_semantic("move")
	else:
		set_semantic("idle")

func trigger(event_state: String, duration := 0.32) -> void:
	set_semantic(event_state, true)
	event_hold = duration

func set_semantic(next_state: String, restart := false) -> void:
	if next_state == semantic_state and not restart:
		return
	previous_state = semantic_state
	semantic_state = next_state
	if binding_valid:
		player.speed_scale = float(SEMANTIC_SPEED.get(next_state, 1.0))
		if restart or not player.is_playing():
			player.play(source_clip, 0.12)
	semantic_state_changed.emit(previous_state, semantic_state)

func reset() -> void:
	event_hold = 0.0
	set_semantic("idle", true)

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null

func get_snapshot() -> Dictionary:
	return {"semantic_state":semantic_state,"previous_state":previous_state,"source_clip":String(source_clip),"binding_valid":binding_valid,"event_hold":event_hold}

