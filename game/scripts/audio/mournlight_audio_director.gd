class_name MournlightAudioDirector
extends Node

@export var library: Resource

var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var movement_voices: Array[AudioStreamPlayer] = []
var terminal_victory_voice: AudioStreamPlayer
var movement_window_remaining: Array[float] = []
var voice_owners: Array[String] = []
var voice_priorities: Array[int] = []
var voice_semantics: Array[String] = []
var voice_window_remaining: Array[float] = []
var semantic_counts: Dictionary = {}
var attack_audio_events: Array[Dictionary] = []
var _attack_audio_seen: Dictionary = {}
var last_attack_audio_receipt: Dictionary = {}
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
var terminal_audio_owner := ""
var terminal_audio_semantic := ""
var terminal_audio_generation := 0
var terminal_audio_reset_generation := 0
var last_terminal_audio_receipt: Dictionary = {}
var terminal_voice_window_remaining := 0.0
var terminal_voice_retirement_reason := "idle"
var terminal_source_start_count := 0
var terminal_voice_start_pending := false
var terminal_voice_started_msec := 0
var terminal_voice_finished_msec := 0
var terminal_voice_last_finished_position := 0.0
var terminal_voice_declared_source_path := ""
var terminal_voice_runtime_decode := "scene_resource"
var pickup_audio_event_count := 0
var last_pickup_audio_receipt: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_attack_semantic_bindings()
	music = AudioStreamPlayer.new()
	music.name = "MusicVoice"
	music.bus = &"Music"
	add_child(music)
	terminal_victory_voice = get_node_or_null("TerminalVictoryVoice") as AudioStreamPlayer
	if terminal_victory_voice:
		terminal_victory_voice.bus = &"Effects"
		terminal_victory_voice.max_polyphony = 1
		terminal_voice_declared_source_path = terminal_victory_voice.stream.resource_path if terminal_victory_voice.stream else ""
		terminal_victory_voice.finished.connect(_on_terminal_victory_finished)
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

func _ensure_attack_semantic_bindings() -> void:
	"""Materialize the authored lantern causal aliases before any event arrives.

	Some Godot resource importers discard unknown metadata keys from a generic
	Resource.  The source recordings remain authored in the audio library; this
	adapter binds the explicit anticipation/recovery semantic ids to those exact
	streams at the ownership boundary, preserving one deterministic Effects-bus
	voice per attack phase.
	"""
	if not library:
		return
	var onset: Variant = library.get_meta("weapon_warden_lantern_onset", [])
	var impact: Variant = library.get_meta("weapon_warden_lantern_impact", [])
	if onset is Array and not onset.is_empty() and not library.has_meta("weapon_warden_lantern_anticipation"):
		library.set_meta("weapon_warden_lantern_anticipation", onset.duplicate())
	if impact is Array and not impact.is_empty() and not library.has_meta("weapon_warden_lantern_recovery"):
		library.set_meta("weapon_warden_lantern_recovery", impact.duplicate())
	var windows: Dictionary = library.get_meta("playback_windows", {})
	if not windows.has("weapon_warden_lantern_anticipation"):
		windows["weapon_warden_lantern_anticipation"] = 0.16
	if not windows.has("weapon_warden_lantern_recovery"):
		windows["weapon_warden_lantern_recovery"] = 0.18
	library.set_meta("playback_windows", windows)
	var owners: Dictionary = library.get_meta("owners", {})
	owners["weapon_warden_lantern_anticipation"] = "lantern"
	owners["weapon_warden_lantern_recovery"] = "lantern"
	library.set_meta("owners", owners)
	var priorities: Dictionary = library.get_meta("priorities", {})
	priorities["weapon_warden_lantern_anticipation"] = 50
	priorities["weapon_warden_lantern_recovery"] = 40
	library.set_meta("priorities", priorities)
	var volumes: Dictionary = library.get_meta("volumes_db", {})
	volumes["weapon_warden_lantern_anticipation"] = -17.0
	volumes["weapon_warden_lantern_recovery"] = -20.0
	library.set_meta("volumes_db", volumes)

func _process(delta: float) -> void:
	_retire_expired_movement_windows(delta)
	_retire_expired_windows(delta)
	_retire_expired_terminal_window(delta)
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
		attack.attack_authorized.connect(_on_attack_authorized)
		attack.hit_resolved.connect(_on_attack_hit)
		if attack.has_signal("attack_finished"):
			attack.attack_finished.connect(_on_attack_finished)
	var health := controller.get_node_or_null("World/Warden/HealthComponent")
	if health:
		health.hurt.connect(func(_event: Dictionary) -> void: play_semantic("warden_hurt"))
		# RunController owns terminal audio after combat teardown. Health still
		# owns deformation immediately, without starting a duplicate death voice.
	var warden := controller.get_node_or_null("World/Warden")
	if warden:
		warden.dash_phase_changed.connect(func(phase: String, _invulnerable: bool) -> void:
			if phase == "active":
				play_semantic("dash")
		)
	var spawner := controller.get_node_or_null("World/EncounterSpawner")
	if spawner:
		spawner.enemy_lifecycle.connect(func(event: Dictionary) -> void:
			match String(event.get("phase", "")):
				"telegraph": play_semantic("enemy_warning")
				"death": play_semantic("enemy_death")
		)
	if controller.has_signal("reward_collected"):
		controller.reward_collected.connect(_on_reward_collected)
	var draft := controller.get_node_or_null("Interface/UpgradeDraft")
	if draft and draft.has_signal("choice_requested"):
		draft.choice_requested.connect(func(_index: int) -> void: play_semantic("upgrade_confirm"))
	_set_music("title")

func _on_attack_authorized(event: Dictionary) -> void:
	# One bounded report belongs to each authoritative automatic attack. The
	# onset is emitted here, before the bolt travels, so the audible transient
	# lines up with AttackRuntime authorization without a duplicate anticipation
	# voice or a retained presentation replay.
	_emit_attack_audio(event, "onset")

func _on_attack_hit(event: Dictionary) -> void:
	_emit_attack_audio(event, "impact")

func _on_attack_finished(event: Dictionary) -> void:
	# Recovery is a lifecycle marker, not a second audible attack cue. Keeping it
	# silent prevents cadence from stacking a second transient on the Effects bus.
	return

func _emit_attack_audio(event: Dictionary, phase: String) -> bool:
	# AttackRuntime is the sole authority for these reports.  Deduplicate by the
	# stable transaction id and phase so presentation/VFX cannot replay a cue.
	var attack_id := String(event.get("attack_id", ""))
	if attack_id.is_empty():
		return false
	var event_key := "%s:%s" % [attack_id, phase]
	if _attack_audio_seen.has(event_key):
		return false
	_attack_audio_seen[event_key] = true
	var weapon_id := String(event.get("weapon_id", "warden_lantern"))
	var semantic := "weapon_%s_%s" % [weapon_id, phase]
	var started := play_semantic(semantic)
	var source_paths: Array[String] = []
	for stream in _streams_for(semantic):
		if stream is AudioStream:
			source_paths.append((stream as AudioStream).resource_path)
	var receipt := {
		"event_id": event_key,
		"attack_id": attack_id,
		"phase": phase,
		"weapon_id": weapon_id,
		"semantic": semantic,
		"started": started,
		"timestamp_msec": Time.get_ticks_msec(),
		"process_frame": Engine.get_process_frames(),
		"bus": "Effects",
		"source_paths": source_paths,
		"causal_owner": String(event.get("audio_owner", event.get("actor_id", "warden"))),
		"bounded_window_seconds": float((library.get_meta("playback_windows", {}) as Dictionary).get(semantic, 0.0)) if library else 0.0,
	}
	attack_audio_events.append(receipt)
	while attack_audio_events.size() > 24:
		attack_audio_events.pop_front()
	last_attack_audio_receipt = receipt.duplicate(true)
	return started

func _on_reward_collected(event: Dictionary) -> void:
	pickup_audio_event_count += 1
	var started := play_semantic("pickup")
	var source_paths: Array[String] = []
	for stream in _streams_for("pickup"):
		if stream is AudioStream:
			source_paths.append((stream as AudioStream).resource_path)
	last_pickup_audio_receipt = {
		"event_id":"pickup_audio.g%04d" % pickup_audio_event_count,
		"authorized_once":true,
		"started":started,
		"semantic":"pickup",
		"bus":"Effects",
		"source_paths":source_paths,
		"resolved_drop_ids":(event.get("resolved_drop_ids", []) as Array).duplicate(),
		"reward_run_serial":event.get("run_serial", -1),
		"semantic_count_after":int(semantic_counts.get("pickup", 0)),
		"active_effect_voices":active_effect_voice_count(),
		"voice_limit":voices.size() + movement_voices.size(),
		"bounded_rejection_count":int(bounded_drop_counts.get("pickup", 0)),
		"process_frame":Engine.get_process_frames(),
	}

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
			_acquire_terminal_audio("death", "run_state_failure")
		"victory":
			_stop_music()
			_acquire_terminal_audio("victory", "run_state_victory")
		"result": _set_music("result")
		"draft": play_semantic("upgrade_open")

func _acquire_terminal_audio(semantic: String, owner: String) -> bool:
	if not terminal_audio_semantic.is_empty():
		return terminal_audio_semantic == semantic
	var started := _play_terminal_victory() if semantic == "victory" else play_semantic(semantic)
	if not started:
		return false
	terminal_audio_generation += 1
	terminal_audio_semantic = semantic
	terminal_audio_owner = owner
	var streams := _streams_for(semantic)
	var source_paths: Array[String] = []
	for stream in streams:
		if stream is AudioStream:
			source_paths.append((stream as AudioStream).resource_path)
	var families: Dictionary = library.get_meta("semantic_families", {}) if library else {}
	last_terminal_audio_receipt = {
		"event_id":"terminal_audio.%s.g%04d" % [semantic, terminal_audio_generation],
		"semantic":semantic,"owner":owner,"event_count":int(semantic_counts.get(semantic, 0)),
		"source_paths":source_paths,"source_family":String(families.get(semantic, semantic)),
		"playback_window_seconds":float((library.get_meta("playback_windows", {}) as Dictionary).get(semantic, 0.0)) if library else 0.0,
		"source_receipt":String(library.get_meta("victory_source_receipt", "")) if semantic == "victory" and library else "",
		"source_sha256":String(library.get_meta("victory_source_sha256", "")) if semantic == "victory" and library else "",
		"acquired_process_frame":Engine.get_process_frames(),
		"voice_path":String(terminal_victory_voice.get_path()) if semantic == "victory" and terminal_victory_voice else "dynamic_semantic_pool",
		"bus":String(terminal_victory_voice.bus) if semantic == "victory" and terminal_victory_voice else "Effects",
		"source_started":terminal_victory_voice.playing if semantic == "victory" and terminal_victory_voice else true,
		"playback_position_seconds":terminal_victory_voice.get_playback_position() if semantic == "victory" and terminal_victory_voice else 0.0,
		"retirement_reason":terminal_voice_retirement_reason if semantic == "victory" else "dynamic_window",
		"effects_route":_bus_route_receipt(&"Effects"),
		"master_route":_bus_route_receipt(&"Master"),
		"persisted_settings":_persisted_audio_settings_receipt(),
	}
	return true

func _play_terminal_victory() -> bool:
	var streams := _streams_for("victory")
	if not terminal_victory_voice or streams.is_empty():
		missing_source_counts["victory"] = int(missing_source_counts.get("victory", 0)) + 1
		rejected_counts["victory"] = int(rejected_counts.get("victory", 0)) + 1
		return false
	var volumes: Dictionary = library.get_meta("volumes_db", {}) if library else {}
	var windows: Dictionary = library.get_meta("playback_windows", {}) if library else {}
	terminal_victory_voice.stop()
	terminal_victory_voice.volume_db = float(volumes.get("victory", -4.0))
	terminal_victory_voice.pitch_scale = 1.0
	terminal_voice_window_remaining = maxf(0.1, float(windows.get("victory", 1.5)))
	terminal_voice_retirement_reason = "start_deferred"
	terminal_voice_start_pending = true
	call_deferred("_start_terminal_victory_source")
	semantic_counts["victory"] = int(semantic_counts.get("victory", 0)) + 1
	return true

func _start_terminal_victory_source() -> void:
	if not terminal_voice_start_pending or terminal_audio_semantic != "victory" or not terminal_victory_voice:
		return
	terminal_voice_start_pending = false
	terminal_voice_retirement_reason = "playing_window"
	terminal_victory_voice.play()
	terminal_source_start_count += 1
	terminal_voice_started_msec = Time.get_ticks_msec()
	if not last_terminal_audio_receipt.is_empty():
		last_terminal_audio_receipt["source_started"] = true
		last_terminal_audio_receipt["source_start_process_frame"] = Engine.get_process_frames()

func _retire_expired_terminal_window(_delta: float) -> void:
	if terminal_voice_window_remaining <= 0.0:
		return
	# The accepted recording is already shorter than its declared playback
	# window. Let AudioServer finish the scene-bound source; process-frame catchup
	# must never stop it before the mixer emits onset.
	if terminal_victory_voice and terminal_victory_voice.playing:
		terminal_voice_window_remaining = maxf(0.0, 1.5 - terminal_victory_voice.get_playback_position())

func _on_terminal_victory_finished() -> void:
	terminal_voice_finished_msec = Time.get_ticks_msec()
	terminal_voice_last_finished_position = terminal_victory_voice.get_playback_position() if terminal_victory_voice else 0.0
	_retire_terminal_victory("source_finished", false)

func _retire_terminal_victory(reason: String, stop_source := true) -> bool:
	if not terminal_victory_voice:
		return false
	var was_active := terminal_victory_voice.playing or terminal_voice_window_remaining > 0.0
	if stop_source and terminal_victory_voice.playing:
		terminal_victory_voice.stop()
	terminal_voice_window_remaining = 0.0
	terminal_voice_start_pending = false
	terminal_voice_retirement_reason = reason
	if not last_terminal_audio_receipt.is_empty():
		last_terminal_audio_receipt["completed"] = was_active
		last_terminal_audio_receipt["retirement_reason"] = reason
		last_terminal_audio_receipt["retired_process_frame"] = Engine.get_process_frames()
	return was_active

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
	if id == "victory":
		return _acquire_terminal_audio("victory", "semantic_victory")
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
	if terminal_victory_voice and terminal_victory_voice.playing:
		active += 1
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
	_retire_terminal_victory("run_reset")
	for index in movement_voices.size():
		_retire_movement_voice(index, "run_reset")
	for index in voices.size():
		voices[index].stop()
		_release_voice(index)
	semantic_counts.clear()
	_attack_audio_seen.clear()
	attack_audio_events.clear()
	last_attack_audio_receipt.clear()
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
	pickup_audio_event_count = 0
	last_pickup_audio_receipt.clear()
	terminal_audio_owner = ""
	terminal_audio_semantic = ""
	last_terminal_audio_receipt.clear()
	terminal_voice_retirement_reason = "run_reset"
	terminal_source_start_count = 0
	terminal_voice_start_pending = false
	terminal_voice_started_msec = 0
	terminal_voice_finished_msec = 0
	terminal_voice_last_finished_position = 0.0
	terminal_audio_reset_generation += 1

func retire_run_ownership(route: String, generation: int) -> Dictionary:
	var stopped_effects := 0
	var owners_before: Array[String] = []
	var movement_before := _active_movement_voice_count()
	var terminal_voice_before := terminal_victory_voice != null and terminal_victory_voice.playing
	if movement_before > 0:
		owners_before.append("movement")
		stopped_effects += _retire_movement_owner("route_%s" % route)
	for index in voices.size():
		if voices[index].playing:
			stopped_effects += 1
			owners_before.append(voice_owners[index])
		voices[index].stop()
		_release_voice(index)
	if terminal_voice_before:
		stopped_effects += 1
		owners_before.append("critical_terminal")
		_retire_terminal_victory("route_%s" % route)
	_stop_music()
	_footstep_clock = 0.0
	_movement_was_active = false
	var released_terminal := {"semantic":terminal_audio_semantic,"owner":terminal_audio_owner,"generation":terminal_audio_generation}
	# Victory owns a bounded hold and is fully evidenced before Result commits;
	# its semantic lease must not survive that handoff. Preserve the established
	# failure/death lease behavior, which is outside this terminal repair.
	var preserve_terminal := route == "result" and terminal_audio_semantic == "death"
	if not preserve_terminal:
		terminal_audio_owner = ""
		terminal_audio_semantic = ""
		terminal_audio_reset_generation += 1
	return {"route":route, "generation":generation, "stopped_effects":stopped_effects, "owners_before":owners_before, "movement_before":movement_before, "terminal_voice_before":terminal_voice_before, "active_effect_voices":active_effect_voice_count(), "active_movement_voices":_active_movement_voice_count(), "music_state":music_state, "music_playing":music.playing, "released_terminal":released_terminal, "terminal_preserved":preserve_terminal}

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
	if terminal_victory_voice and terminal_victory_voice.playing:
		playing += 1
		active_by_owner["critical_terminal"] = 1
	var effects_route := _bus_route_receipt(&"Effects")
	var master_route := _bus_route_receipt(&"Master")
	var route_valid := (
		bool(effects_route.get("present", false))
		and String(effects_route.get("send", "")) == "Master"
		and not bool(effects_route.get("mute", true))
		and not bool(effects_route.get("bypass_effects", true))
		and float(effects_route.get("volume_linear", 0.0)) > 0.0
		and bool(master_route.get("present", false))
		and not bool(master_route.get("mute", true))
		and float(master_route.get("volume_linear", 0.0)) > 0.0
	)
	return {"music_state":music_state,"music_playing":music.playing,
		"effects_bus_index":effects_route.get("index", -1),
		"effects_bus_send":effects_route.get("send", ""),
		"effects_bus_volume_db":effects_route.get("volume_db", -INF),
		"effects_bus_volume_linear":effects_route.get("volume_linear", 0.0),
		"effects_bus_muted":effects_route.get("mute", true),
		"effects_bus_bypass":effects_route.get("bypass_effects", true),
		"master_bus_index":master_route.get("index", -1),
		"master_bus_volume_db":master_route.get("volume_db", -INF),
		"master_bus_volume_linear":master_route.get("volume_linear", 0.0),
		"master_bus_muted":master_route.get("mute", true),
		"persisted_effects_setting":((_persisted_audio_settings_receipt().get("configured_linear", {}) as Dictionary).get("Effects", -1.0)),
		"settings_apply_generation":_persisted_audio_settings_receipt().get("apply_generation", 0),
		"audio_route_valid":route_valid,
		"victory_authorization_count":int(semantic_counts.get("victory", 0)),
		"victory_source_start_count":terminal_source_start_count,
		"victory_source_finished_msec":terminal_voice_finished_msec,
		"victory_retirement_reason":terminal_voice_retirement_reason,
		"terminal_active_voice_count":1 if terminal_victory_voice and terminal_victory_voice.playing else 0,
		"effect_active_voice_count":playing,
		"audio_driver":AudioServer.get_driver_name(),
		"audio_bus_count":AudioServer.bus_count,
		"same_bus_control":"ordinary_physical_dash_on_Effects",
		"dash_semantic_count":int(semantic_counts.get("dash", 0)),
		"footstep_semantic_count":int(semantic_counts.get("footstep", 0)),
		"pickup_semantic_count":int(semantic_counts.get("pickup", 0)),
		"pickup_audio_event_count":pickup_audio_event_count,
		"attack_audio_event_count":attack_audio_events.size(),
		"attack_audio_events":attack_audio_events.duplicate(true),
		"last_attack_audio_receipt":last_attack_audio_receipt.duplicate(true),
		"attack_audio_dedup_keys":_attack_audio_seen.keys(),
		"last_pickup_audio_receipt":last_pickup_audio_receipt,
		"collector_localization_rule":"same_bus_control_silent_with_valid_route_requires_host_collector_or_driver_diagnosis",
		"terminal_voice_bound":terminal_victory_voice != null,
		"terminal_voice_playing":terminal_victory_voice.playing if terminal_victory_voice else false,
		"terminal_voice_start_pending":terminal_voice_start_pending,
		"terminal_voice_bus":String(terminal_victory_voice.bus) if terminal_victory_voice else "",
		"terminal_voice_stream_path":terminal_voice_declared_source_path,
		"terminal_voice_runtime_decode":terminal_voice_runtime_decode,
		"terminal_voice_window_remaining_seconds":terminal_voice_window_remaining,
		"terminal_source_start_count":terminal_source_start_count,
		"terminal_voice_retirement_reason":terminal_voice_retirement_reason,
		"terminal_voice_started_msec":terminal_voice_started_msec,
		"terminal_voice_finished_msec":terminal_voice_finished_msec,
		"terminal_voice_wall_duration_seconds":float(terminal_voice_finished_msec - terminal_voice_started_msec) / 1000.0 if terminal_voice_finished_msec >= terminal_voice_started_msec and terminal_voice_started_msec > 0 else 0.0,
		"terminal_voice_last_finished_position":terminal_voice_last_finished_position,
		"active_effect_voices":playing,
		"voice_limit":voices.size() + movement_voices.size(),"semantic_voice_limit":voices.size(),"active_by_owner":active_by_owner,"semantic_counts":semantic_counts,
		"rejected_counts":rejected_counts,"missing_source_counts":missing_source_counts,
		"bounded_drop_counts":bounded_drop_counts,"library_bound":library != null,
		"owner_retire_counts":owner_retire_counts,"last_owner_retirement":last_owner_retirement,
		"terminal_audio_lease":{"active":not terminal_audio_semantic.is_empty(),"semantic":terminal_audio_semantic,"owner":terminal_audio_owner,"generation":terminal_audio_generation,"reset_generation":terminal_audio_reset_generation,"receipt":last_terminal_audio_receipt},
		"terminal_voice":{"bound":terminal_victory_voice != null,"path":String(terminal_victory_voice.get_path()) if terminal_victory_voice else "","stream_path":terminal_victory_voice.stream.resource_path if terminal_victory_voice and terminal_victory_voice.stream else "","bus":String(terminal_victory_voice.bus) if terminal_victory_voice else "","playing":terminal_victory_voice.playing if terminal_victory_voice else false,"playback_position_seconds":terminal_victory_voice.get_playback_position() if terminal_victory_voice else 0.0,"window_remaining_seconds":terminal_voice_window_remaining,"source_start_count":terminal_source_start_count,"retirement_reason":terminal_voice_retirement_reason},
		"movement_voice_limit":movement_voices.size(),"active_movement_voices":_active_movement_voice_count(),
		"footstep_sources":movement_voices.map(func(voice: AudioStreamPlayer) -> Dictionary: return {"path":String(voice.get_path()),"stream_path":voice.stream.resource_path if voice.stream else "","bus":String(voice.bus),"playing":voice.playing,"playback_position":voice.get_playback_position() if voice.playing else 0.0}),
		"footstep_source_starts":footstep_source_starts,"footstep_source_retirements":footstep_source_retirements,"last_footstep_rejection":last_footstep_rejection,
		"footstep_window_seconds":float((library.get_meta("playback_windows", {}) as Dictionary).get("footstep", 0.0)) if library else 0.0,
		"source_revision":String(library.get_meta("source_revision", "")) if library else ""}

func _bus_route_receipt(bus_name: StringName) -> Dictionary:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return {"name":String(bus_name), "index":-1, "present":false}
	return {
		"name":AudioServer.get_bus_name(index), "index":index, "present":true,
		"send":String(AudioServer.get_bus_send(index)),
		"volume_db":AudioServer.get_bus_volume_db(index),
		"volume_linear":AudioServer.get_bus_volume_linear(index),
		"mute":AudioServer.is_bus_mute(index),
		"bypass_effects":AudioServer.is_bus_bypassing_effects(index),
		"solo":AudioServer.is_bus_solo(index),
	}

func _persisted_audio_settings_receipt() -> Dictionary:
	var tree := get_tree()
	if tree and tree.root.has_meta("mournlight_audio_settings_receipt"):
		return (tree.root.get_meta("mournlight_audio_settings_receipt", {}) as Dictionary).duplicate(true)
	return {"apply_generation":0, "missing":true}
