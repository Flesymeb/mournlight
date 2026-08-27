class_name MournlightAudioDirector
extends Node

const MUSIC := preload("res://assets/audio_library/Music/Marksmans_Mayhem.ogg")
const CAST := preload("res://assets/audio_library/SFX/345448__artmasterrich__laserfire_02.wav")
const IMPACT := preload("res://assets/audio_library/SFX/258198__wadaltmon__thompson-smg-shot.wav")
const HURT := preload("res://assets/audio_library/SFX/163441__under7dude__man-getting-hit.wav")
const WARNING := preload("res://assets/audio_library/SFX/621155__ktfreesound__reload-escopeta-m7.wav")

var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var voice_cursor := 0
var semantic_counts: Dictionary = {}
var music_state := "silent"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music = AudioStreamPlayer.new()
	music.name = "MusicVoice"
	music.bus = &"Music"
	music.stream = MUSIC
	add_child(music)
	for index in 10:
		var voice := AudioStreamPlayer.new()
		voice.name = "EffectVoice%02d" % index
		voice.bus = &"Effects"
		add_child(voice)
		voices.append(voice)
	call_deferred("_bind_events")

func _bind_events() -> void:
	var controller := get_parent()
	if controller.has_signal("state_changed"):
		controller.state_changed.connect(_on_state_changed)
	var attack := controller.get_node_or_null("World/Warden/Weapons/AttackRuntime")
	if attack:
		attack.attack_authorized.connect(func(event: Dictionary) -> void: play_semantic("weapon_" + String(event.get("weapon_id","cast")), CAST, -8.0))
		attack.hit_resolved.connect(func(_event: Dictionary) -> void: play_semantic("impact", IMPACT, -14.0))
	var health := controller.get_node_or_null("World/Warden/HealthComponent")
	if health:
		health.hurt.connect(func(_event: Dictionary) -> void: play_semantic("warden_hurt", HURT, -5.0, 1.05))
	var spawner := controller.get_node_or_null("World/EncounterSpawner")
	if spawner:
		spawner.reward_dropped.connect(func(_event: Dictionary) -> void: play_semantic("pickup", CAST, -16.0, 1.35))
	_set_music("title")

func _on_state_changed(_previous: String, current: String) -> void:
	match current:
		"title": _set_music("title")
		"active": _set_music("normal")
		"boss": _set_music("boss")
		"failure", "victory", "result": _set_music("result")
		"draft": play_semantic("upgrade_open", WARNING, -12.0, 1.22)

func _set_music(state: String) -> void:
	if music_state == state and music.playing:
		return
	music_state = state
	music.stop()
	music.pitch_scale = {"title":0.88,"normal":1.0,"boss":1.12,"result":0.76}.get(state, 1.0)
	music.volume_db = -18.0 if state == "title" else -15.0
	music.play()
	semantic_counts["music_" + state] = int(semantic_counts.get("music_" + state, 0)) + 1

func play_semantic(id: String, stream: AudioStream, volume_db := -10.0, pitch := 1.0) -> void:
	if not stream or voices.is_empty():
		return
	var voice := voices[voice_cursor % voices.size()]
	voice_cursor += 1
	voice.stop()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
	semantic_counts[id] = int(semantic_counts.get(id, 0)) + 1

func reset_for_run() -> void:
	for voice in voices:
		voice.stop()
	voice_cursor = 0
	semantic_counts.clear()

func _mcp_state() -> Dictionary:
	var playing := 0
	for voice in voices:
		playing += int(voice.playing)
	return {"music_state":music_state,"music_playing":music.playing,"active_effect_voices":playing,"voice_limit":voices.size(),"semantic_counts":semantic_counts}

