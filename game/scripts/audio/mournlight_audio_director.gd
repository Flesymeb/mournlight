class_name MournlightAudioDirector
extends Node

@export var library: Resource

var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var movement_voices: Array[AudioStreamPlayer] = []
var movement_window_remaining: Array[float] = []
var voice_owners: Array[String] = []
var voice_priorities: Array[int] = []
var voice_semantics: Array[String] = []
var voice_window_remaining: Array[float] = []
var semantic_counts: Dictionary = {}
var rejected_counts: Dictionary = {}
var missing_source_counts: Dictionary = {}
var bounded_drop_counts: Dictionary = {}
var music_state := "silent"
var _variation_cursor: Dictionary = {}
var _footstep_clock := 0.0
var _movement_was_active := false
var owner_retire_counts: Dictionary = {}
var last_owner_retirement: Dictionary = {}
var footstep_source_starts: Array[Dictionary] = []
var footstep_source_retirements: Array[Dictionary] = []
var last_footstep_rejection: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music = AudioStreamPlayer.new()
	music.name = "MusicVoice"
	music.bus = &"Music"
	add_child(music)
	for child_name in [&"FootstepVoiceA", &"FootstepVoiceB"]:
		var movement_voice := get_node_or_null(NodePath(child_name)) as AudioStreamPlayer
		if movement_voice:
			movement_voice.bus = &"Effects"
			movement_voice.max_polyphony = 1
			movement_voices.append(movement_voice)
			movement_window_remaining.append(0.0)
			movement_voice.finished.connect(_on_movement_voice_finished.bind(movement_voices.size() - 1))
	for index in 12:
		var voice := AudioStreamPlayer.new()
		voice.name = "SemanticVoice%02d" % index
		voice.bus = &"Effects"
		voice.max_polyphony = 1
		add_child(voice)
		voices.append(voice)
		voice_owners.append("")
		voice_priorities.append(0)
		voice_semantics.append("")
		voice_window_remaining.append(0.0)
		voice.finished.connect(_release_voice.bind(index))
	call_deferred("_bind_events")

func _process(delta: float) -> void:
	_retire_expired_movement_windows(delta)
	_retire_expired_windows(delta)
	if get_tree().paused:
		return
	var controller := get_parent()
	if not controller or String(controller.get("run_state")) not in ["active", "boss"]:
		if _movement_was_active:
			_retire_semantic("footstep", "run_state_exit")
		_movement_was_active = false
		return
	var warden := controller.get_node_or_null("World/Warden")
	if not warden:
		return
	var moving := float(warden.planar_velocity.length()) > 0.7
	if not moving and _movement_was_active:
		_retire_semantic("footstep", "movement_release")
	_footstep_clock = maxf(0.0, _footstep_clock - delta)
	if moving and _footstep_clock <= 0.0:
		play_semantic("footstep")
		_footstep_clock = 0.42
	_movement_was_active = moving

func _bind_events() -> void:
	var controller := get_parent()
	controller.state_changed.connect(_on_state_changed)
	var attack := controller.get_node_or_null("World/Warden/Weapons/AttackRuntime")
	if attack:
		attack.attack_authorized.connect(func(event: Dictionary) -> void:
			play_semantic("weapon_" + String(event.get("weapon_id", "warden_lantern")) + "_onset"))
		attack.hit_resolved.connect(func(event: Dictionary) -> void:
			play_semantic("weapon_" + String(event.get("weapon_id", "warden_lantern")) + "_impact"))
	var health := controller.get_node_or_null("World/Warden/HealthComponent")
	if health:
		health.hurt.connect(func(_event: Dictionary) -> void: play_semantic("warden_hurt"))
		health.died.connect(func(_event: Dictionary) -> void: play_semantic("death"))
	var warden := controller.get_node_or_null("World/Warden")
	if warden:
		warden.dash_phase_changed.connect(func(phase: String, _invulnerable: bool) -> void:
			if phase == "active":
				play_semantic("dash")
		)
	var spawner := controller.get_node_or_null("World/EncounterSpawner")
	if spawner:
		spawner.reward_dropped.connect(func(_event: Dictionary) -> void: play_semantic("pickup"))
		spawner.enemy_lifecycle.connect(func(event: Dictionary) -> void:
			match String(event.get("phase", "")):
				"telegraph": play_semantic("enemy_warning")
				"death": play_semantic("enemy_death")
		)
	var draft := controller.get_node_or_null("Interface/UpgradeDraft")
	if draft and draft.has_signal("choice_requested"):
		draft.choice_requested.connect(func(_index: int) -> void: play_semantic("upgrade_confirm"))
	_set_music("title")

func _on_state_changed(_previous: String, current: String) -> void:
	if current not in ["active", "boss"]:
		_retire_owner("movement", "state_%s" % current)
		_movement_was_active = false
	match current:
		"title": _set_music("title")
		"active": _set_music("waves")
		"boss": _set_music("boss")
		"failure":
			_stop_music()
			play_semantic("death")
		"victory":
			_stop_music()
			play_semantic("victory")
		"result": _set_music("result")
		"draft": play_semantic("upgrade_open")

func _set_music(state: String) -> void:
	var streams := _streams_for("music")
	if streams.is_empty():
		_stop_music()
		return
	if music_state == state and music.playing:
		return
	music_state = state
	music.stop()
	music.stream = streams[0]
	music.pitch_scale = {"title":0.88,"waves":1.0,"boss":1.08,"result":0.82}.get(state, 1.0)
	music.volume_db = -18.0 if state == "title" else -15.0
	music.play()
	semantic_counts["music_" + state] = int(semantic_counts.get("music_" + state, 0)) + 1

func _stop_music() -> void:
	music.stop()
	music_state = "silent"

func play_semantic(id: String) -> bool:
	if id == "footstep":
		return _play_footstep_direct()
	var streams := _streams_for(id)
	if streams.is_empty():
		missing_source_counts[id] = int(missing_source_counts.get(id, 0)) + 1
		rejected_counts[id] = int(rejected_counts.get(id, 0)) + 1
		return false
	var owners: Dictionary = library.get_meta("owners", {}) if library else {}
	var priorities: Dictionary = library.get_meta("priorities", {}) if library else {}
	var volumes: Dictionary = library.get_meta("volumes_db", {}) if library else {}
	var owner_limits: Dictionary = library.get_meta("owner_limits", {}) if library else {}
	var owner := String(owners.get(id, id))
	var priority := int(priorities.get(id, 25))
	var voice_index := _claim_voice(owner, priority, int(owner_limits.get(owner, 1)))
	if voice_index < 0:
		bounded_drop_counts[id] = int(bounded_drop_counts.get(id, 0)) + 1
		return false
	var cursor := int(_variation_cursor.get(id, 0))
	var stream: AudioStream = streams[cursor % streams.size()]
	_variation_cursor[id] = cursor + 1
	var voice := voices[voice_index]
	voice.stop()
	voice.stream = stream
	voice.volume_db = float(volumes.get(id, -12.0))
	voice.pitch_scale = 0.96 + float((cursor * 7) % 5) * 0.02
	voice_owners[voice_index] = owner
	voice_priorities[voice_index] = priority
	voice_semantics[voice_index] = id
	var offsets: Dictionary = library.get_meta("playback_offsets", {}) if library else {}
	var windows: Dictionary = library.get_meta("playback_windows", {}) if library else {}
	var semantic_offsets = offsets.get(id, PackedFloat32Array())
	var start_offset := 0.0
	if semantic_offsets is PackedFloat32Array and semantic_offsets.size() > 0:
		start_offset = float(semantic_offsets[cursor % semantic_offsets.size()])
	voice_window_remaining[voice_index] = maxf(0.0, float(windows.get(id, 0.0)))
	voice.play(start_offset)
	semantic_counts[id] = int(semantic_counts.get(id, 0)) + 1
	return true

func _play_footstep_direct() -> bool:
	var streams := _streams_for("footstep")
	if streams.is_empty() or movement_voices.is_empty():
		missing_source_counts["footstep"] = int(missing_source_counts.get("footstep", 0)) + 1
		rejected_counts["footstep"] = int(rejected_counts.get("footstep", 0)) + 1
		last_footstep_rejection = {"reason":"missing_direct_source", "time_msec":Time.get_ticks_msec()}
		return false
	var voice_index := -1
	for index in movement_voices.size():
		if not movement_voices[index].playing and movement_window_remaining[index] <= 0.0:
			voice_index = index
			break
	if voice_index < 0:
		bounded_drop_counts["footstep"] = int(bounded_drop_counts.get("footstep", 0)) + 1
		last_footstep_rejection = {
			"reason":"movement_voice_limit", "time_msec":Time.get_ticks_msec(),
			"active_movement_voices":_active_movement_voice_count(), "movement_voice_limit":movement_voices.size(),
		}
		return false
	var cursor := int(_variation_cursor.get("footstep", 0))
	var stream: AudioStream = streams[cursor % streams.size()]
	_variation_cursor["footstep"] = cursor + 1
	var voice := movement_voices[voice_index]
	# Keep the scene-bound source authoritative. Reassign only if a stale editor
	# instance did not load the exact accepted stream from the audio scene.
	if voice.stream != stream:
		voice.stream = stream
	var volumes: Dictionary = library.get_meta("volumes_db", {}) if library else {}
	var offsets: Dictionary = library.get_meta("playback_offsets", {}) if library else {}
	var windows: Dictionary = library.get_meta("playback_windows", {}) if library else {}
	var semantic_offsets = offsets.get("footstep", PackedFloat32Array())
	var start_offset := 0.0
	if semantic_offsets is PackedFloat32Array and semantic_offsets.size() > 0:
		start_offset = float(semantic_offsets[cursor % semantic_offsets.size()])
	voice.volume_db = float(volumes.get("footstep", -4.0))
	voice.pitch_scale = 0.98 + float(cursor % 3) * 0.02
	movement_window_remaining[voice_index] = maxf(0.01, float(windows.get("footstep", 0.28)))
	voice.play(start_offset)
	semantic_counts["footstep"] = int(semantic_counts.get("footstep", 0)) + 1
	var receipt := {
		"voice_path":String(voice.get_path()), "stream_path":voice.stream.resource_path if voice.stream else "",
		"bus":String(voice.bus), "start_time_msec":Time.get_ticks_msec(), "start_offset_seconds":start_offset,
		"retirement_window_seconds":movement_window_remaining[voice_index], "voice_index":voice_index,
		"active_movement_voices":_active_movement_voice_count(), "movement_voice_limit":movement_voices.size(),
	}
	footstep_source_starts.append(receipt)
	while footstep_source_starts.size() > 12:
		footstep_source_starts.pop_front()
	last_footstep_rejection.clear()
	return true

func _retire_expired_movement_windows(delta: float) -> void:
	for index in movement_voices.size():
		if movement_window_remaining[index] <= 0.0:
			continue
		movement_window_remaining[index] = maxf(0.0, movement_window_remaining[index] - delta)
		if movement_window_remaining[index] <= 0.0:
			_retire_movement_voice(index, "window_elapsed")

func _on_movement_voice_finished(index: int) -> void:
	_retire_movement_voice(index, "source_finished", false)

func _retire_movement_voice(index: int, reason: String, stop_source := true) -> void:
	if index < 0 or index >= movement_voices.size():
		return
	var voice := movement_voices[index]
	var was_owned := movement_window_remaining[index] > 0.0 or voice.playing
	if stop_source and voice.playing:
		voice.stop()
	movement_window_remaining[index] = 0.0
	if not was_owned:
		return
	var receipt := {
		"voice_path":String(voice.get_path()), "stream_path":voice.stream.resource_path if voice.stream else "",
		"bus":String(voice.bus), "retired_time_msec":Time.get_ticks_msec(), "reason":reason,
		"voice_index":index, "active_movement_voices":_active_movement_voice_count(),
	}
	footstep_source_retirements.append(receipt)
	while footstep_source_retirements.size() > 12:
		footstep_source_retirements.pop_front()
	owner_retire_counts["movement"] = int(owner_retire_counts.get("movement", 0)) + 1
	last_owner_retirement = {"owner":"movement", "reason":reason, "retired":1, "voice_path":String(voice.get_path())}

func _active_movement_voice_count() -> int:
	var active := 0
	for index in movement_voices.size():
		if movement_voices[index].playing or movement_window_remaining[index] > 0.0:
			active += 1
	return active

func active_effect_voice_count() -> int:
	var active := _active_movement_voice_count()
	for voice in voices:
		if voice.playing:
			active += 1
	return active

func _streams_for(id: String) -> Array:
	if not library or not library.has_meta(id):
		return []
	var value = library.get_meta(id)
	return value if value is Array else []

func _claim_voice(owner: String, priority: int, owner_limit: int) -> int:
	var owner_allocated: Array[int] = []
	var lowest_index := -1
	var lowest_priority := 1000000
	for index in voices.size():
		if voice_owners[index] == owner:
			owner_allocated.append(index)
		if not voice_owners[index].is_empty() and voice_priorities[index] < lowest_priority:
			lowest_priority = voice_priorities[index]
			lowest_index = index
	if owner_allocated.size() >= owner_limit:
		var same_owner := owner_allocated[0]
		for index in owner_allocated:
			if voice_priorities[index] < voice_priorities[same_owner]:
				same_owner = index
		return same_owner if priority >= voice_priorities[same_owner] else -1
	# Allocation is authoritative immediately after play() is requested. The
	# engine can report playing=false until its mixer begins, so using that flag
	# here lets another same-frame semantic overwrite a source before onset.
	for index in voices.size():
		if voice_owners[index].is_empty():
			return index
	return lowest_index if priority > lowest_priority else -1

func _release_voice(index: int) -> void:
	if index < 0 or index >= voices.size():
		return
	voice_owners[index] = ""
	voice_priorities[index] = 0
	voice_semantics[index] = ""
	voice_window_remaining[index] = 0.0

func _retire_expired_windows(delta: float) -> void:
	for index in voices.size():
		if voice_window_remaining[index] <= 0.0:
			continue
		voice_window_remaining[index] = maxf(0.0, voice_window_remaining[index] - delta)
		if voice_window_remaining[index] <= 0.0:
			voices[index].stop()
			_release_voice(index)

func _retire_semantic(semantic: String, reason: String) -> int:
	if semantic == "footstep":
		return _retire_movement_owner(reason)
	var retired := 0
	for index in voices.size():
		if voice_semantics[index] != semantic:
			continue
		voices[index].stop()
		_release_voice(index)
		retired += 1
	if retired > 0:
		owner_retire_counts[semantic] = int(owner_retire_counts.get(semantic, 0)) + retired
		last_owner_retirement = {"owner":semantic, "reason":reason, "retired":retired}
	return retired

func _retire_owner(owner: String, reason: String) -> int:
	if owner == "movement":
		return _retire_movement_owner(reason)
	var retired := 0
	for index in voices.size():
		if voice_owners[index] != owner:
			continue
		voices[index].stop()
		_release_voice(index)
		retired += 1
	if retired > 0:
		owner_retire_counts[owner] = int(owner_retire_counts.get(owner, 0)) + retired
		last_owner_retirement = {"owner":owner, "reason":reason, "retired":retired}
	return retired

func _retire_movement_owner(reason: String) -> int:
	var retired := 0
	for index in movement_voices.size():
		if movement_voices[index].playing or movement_window_remaining[index] > 0.0:
			_retire_movement_voice(index, reason)
			retired += 1
	return retired

func reset_for_run() -> void:
	for index in movement_voices.size():
		_retire_movement_voice(index, "run_reset")
	for index in voices.size():
		voices[index].stop()
		_release_voice(index)
	semantic_counts.clear()
	rejected_counts.clear()
	missing_source_counts.clear()
	bounded_drop_counts.clear()
	_variation_cursor.clear()
	_footstep_clock = 0.0
	_movement_was_active = false
	owner_retire_counts.clear()
	last_owner_retirement.clear()
	footstep_source_starts.clear()
	footstep_source_retirements.clear()
	last_footstep_rejection.clear()

func retire_run_ownership(route: String, generation: int) -> Dictionary:
	var stopped_effects := 0
	var owners_before: Array[String] = []
	var movement_before := _active_movement_voice_count()
	if movement_before > 0:
		owners_before.append("movement")
		stopped_effects += _retire_movement_owner("route_%s" % route)
	for index in voices.size():
		if voices[index].playing:
			stopped_effects += 1
			owners_before.append(voice_owners[index])
		voices[index].stop()
		_release_voice(index)
	_stop_music()
	_footstep_clock = 0.0
	_movement_was_active = false
	return {"route":route, "generation":generation, "stopped_effects":stopped_effects, "owners_before":owners_before, "movement_before":movement_before, "active_effect_voices":active_effect_voice_count(), "active_movement_voices":_active_movement_voice_count(), "music_state":music_state, "music_playing":music.playing}

func _mcp_state() -> Dictionary:
	var playing := _active_movement_voice_count()
	var active_by_owner: Dictionary = {}
	if playing > 0:
		active_by_owner["movement"] = playing
	for index in voices.size():
		if voices[index].playing:
			playing += 1
			var owner := voice_owners[index]
			active_by_owner[owner] = int(active_by_owner.get(owner, 0)) + 1
	return {"music_state":music_state,"music_playing":music.playing,"active_effect_voices":playing,
		"voice_limit":voices.size() + movement_voices.size(),"semantic_voice_limit":voices.size(),"active_by_owner":active_by_owner,"semantic_counts":semantic_counts,
		"rejected_counts":rejected_counts,"missing_source_counts":missing_source_counts,
		"bounded_drop_counts":bounded_drop_counts,"library_bound":library != null,
		"owner_retire_counts":owner_retire_counts,"last_owner_retirement":last_owner_retirement,
		"movement_voice_limit":movement_voices.size(),"active_movement_voices":_active_movement_voice_count(),
		"footstep_sources":movement_voices.map(func(voice: AudioStreamPlayer) -> Dictionary: return {"path":String(voice.get_path()),"stream_path":voice.stream.resource_path if voice.stream else "","bus":String(voice.bus),"playing":voice.playing,"playback_position":voice.get_playback_position() if voice.playing else 0.0}),
		"footstep_source_starts":footstep_source_starts,"footstep_source_retirements":footstep_source_retirements,"last_footstep_rejection":last_footstep_rejection,
		"footstep_window_seconds":float((library.get_meta("playback_windows", {}) as Dictionary).get("footstep", 0.0)) if library else 0.0,
		"source_revision":String(library.get_meta("source_revision", "")) if library else ""}
