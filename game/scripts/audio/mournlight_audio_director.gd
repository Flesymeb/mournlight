class_name MournlightAudioDirector
extends Node

@export var library: Resource

var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var voice_owners: Array[String] = []
var voice_priorities: Array[int] = []
var voice_semantics: Array[String] = []
var semantic_counts: Dictionary = {}
var rejected_counts: Dictionary = {}
var missing_source_counts: Dictionary = {}
var bounded_drop_counts: Dictionary = {}
var music_state := "silent"
var _variation_cursor: Dictionary = {}
var _footstep_clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music = AudioStreamPlayer.new()
	music.name = "MusicVoice"
	music.bus = &"Music"
	add_child(music)
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
		voice.finished.connect(_release_voice.bind(index))
	call_deferred("_bind_events")

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	var controller := get_parent()
	if not controller or String(controller.get("run_state")) not in ["active", "boss"]:
		return
	var warden := controller.get_node_or_null("World/Warden")
	if not warden:
		return
	var moving := float(warden.planar_velocity.length()) > 0.7
	_footstep_clock = maxf(0.0, _footstep_clock - delta)
	if moving and _footstep_clock <= 0.0:
		play_semantic("footstep")
		_footstep_clock = 0.42

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
	voice.play()
	semantic_counts[id] = int(semantic_counts.get(id, 0)) + 1
	return true

func _streams_for(id: String) -> Array:
	if not library or not library.has_meta(id):
		return []
	var value = library.get_meta(id)
	return value if value is Array else []

func _claim_voice(owner: String, priority: int, owner_limit: int) -> int:
	var owner_playing: Array[int] = []
	var lowest_index := -1
	var lowest_priority := 1000000
	for index in voices.size():
		if not voices[index].playing:
			return index
		if voice_owners[index] == owner:
			owner_playing.append(index)
		if voice_priorities[index] < lowest_priority:
			lowest_priority = voice_priorities[index]
			lowest_index = index
	if owner_playing.size() >= owner_limit:
		var same_owner := owner_playing[0]
		for index in owner_playing:
			if voice_priorities[index] < voice_priorities[same_owner]:
				same_owner = index
		return same_owner if priority >= voice_priorities[same_owner] else -1
	return lowest_index if priority > lowest_priority else -1

func _release_voice(index: int) -> void:
	if index < 0 or index >= voices.size():
		return
	voice_owners[index] = ""
	voice_priorities[index] = 0
	voice_semantics[index] = ""

func reset_for_run() -> void:
	for index in voices.size():
		voices[index].stop()
		_release_voice(index)
	semantic_counts.clear()
	rejected_counts.clear()
	missing_source_counts.clear()
	bounded_drop_counts.clear()
	_variation_cursor.clear()
	_footstep_clock = 0.0

func retire_run_ownership(route: String, generation: int) -> Dictionary:
	var stopped_effects := 0
	var owners_before: Array[String] = []
	for index in voices.size():
		if voices[index].playing:
			stopped_effects += 1
			owners_before.append(voice_owners[index])
		voices[index].stop()
		_release_voice(index)
	_stop_music()
	_footstep_clock = 0.0
	return {"route":route, "generation":generation, "stopped_effects":stopped_effects, "owners_before":owners_before, "active_effect_voices":0, "music_state":music_state, "music_playing":music.playing}

func _mcp_state() -> Dictionary:
	var playing := 0
	var active_by_owner: Dictionary = {}
	for index in voices.size():
		if voices[index].playing:
			playing += 1
			var owner := voice_owners[index]
			active_by_owner[owner] = int(active_by_owner.get(owner, 0)) + 1
	return {"music_state":music_state,"music_playing":music.playing,"active_effect_voices":playing,
		"voice_limit":voices.size(),"active_by_owner":active_by_owner,"semantic_counts":semantic_counts,
		"rejected_counts":rejected_counts,"missing_source_counts":missing_source_counts,
		"bounded_drop_counts":bounded_drop_counts,"library_bound":library != null,
		"source_revision":String(library.get_meta("source_revision", "")) if library else ""}
