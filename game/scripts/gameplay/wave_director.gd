class_name MournlightWaveDirector
extends Node

signal phase_changed(snapshot: Dictionary)
signal boss_requested
signal victory_requested

const WAVES := [
	{"title":"The First Toll","duration":75.0,"cap":6,"cadence":1.75,"warning":"TEACHING PRESSURE"},
	{"title":"Crossing Shadows","duration":90.0,"cap":8,"cadence":1.35,"warning":"FLANK PRESSURE"},
	{"title":"Gravewind","duration":105.0,"cap":10,"cadence":1.10,"warning":"RANGED ELITE"},
	{"title":"The Long Procession","duration":120.0,"cap":12,"cadence":0.90,"warning":"MIXED DENSITY"},
	{"title":"The Bellkeeper","duration":150.0,"cap":5,"cadence":2.5,"warning":"FINAL TOLL"},
]

var phase := "idle"
var wave_index := -1
var wave_elapsed := 0.0
var warmup_remaining := 4.0
var total_elapsed := 0.0
var boss_spawned := false
var terminated := false

func reset() -> void:
	phase = "idle"
	wave_index = -1
	wave_elapsed = 0.0
	warmup_remaining = 4.0
	total_elapsed = 0.0
	boss_spawned = false
	terminated = false
	set_process(false)

func begin() -> void:
	reset()
	phase = "warmup"
	set_process(true)
	_emit()

func terminate(outcome: String) -> void:
	terminated = true
	phase = outcome
	set_process(false)
	_emit()

func _process(delta: float) -> void:
	if terminated:
		return
	total_elapsed += delta
	if phase == "warmup":
		warmup_remaining -= delta
		if warmup_remaining <= 0.0:
			_start_wave(0)
		return
	if phase != "active":
		return
	wave_elapsed += delta
	if wave_index == 4 and not boss_spawned:
		boss_spawned = true
		boss_requested.emit()
	if wave_elapsed >= float(WAVES[wave_index].duration) and wave_index < 4:
		_start_wave(wave_index + 1)

func _start_wave(index: int) -> void:
	wave_index = index
	wave_elapsed = 0.0
	phase = "active"
	_emit()

func _emit() -> void:
	phase_changed.emit(get_snapshot())

func prepare_test_wave(index: int) -> void:
	_start_wave(clampi(index, 0, 4))

func get_snapshot() -> Dictionary:
	var definition: Dictionary = WAVES[wave_index] if wave_index >= 0 else {}
	return {"phase":phase,"wave":wave_index + 1,"wave_count":5,"wave_elapsed":wave_elapsed,
		"wave_duration":float(definition.get("duration",0.0)),"title":String(definition.get("title","WARMUP")),
		"warning":String(definition.get("warning","PREPARE")),"total_elapsed":total_elapsed,
		"boss_spawned":boss_spawned,"terminated":terminated,"definition":definition}

func _mcp_state() -> Dictionary:
	return get_snapshot()
