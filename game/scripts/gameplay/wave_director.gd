class_name MournlightWaveDirector
extends Node

signal phase_changed(snapshot: Dictionary)
signal boss_requested
signal victory_requested

const WAVE_SEQUENCE := preload("res://resources/waves/mournlight_wave_sequence.tres")
const ROLE_KEYS := ["mossling", "wispbat", "bone_slinger", "grave_brute"]
const MAX_LIVE_ENEMIES := 40
const MAX_SPAWN_BUDGET := 160

var phase := "idle"
var wave_index := -1
var wave_elapsed := 0.0
var warmup_remaining := 4.0
var total_elapsed := 0.0
var boss_spawned := false
var terminated := false
var ordinary_route_wave_ids: Array[String] = []
var diagnostic_jump_count := 0

func reset() -> void:
	phase = "idle"
	wave_index = -1
	wave_elapsed = 0.0
	warmup_remaining = 4.0
	total_elapsed = 0.0
	boss_spawned = false
	terminated = false
	ordinary_route_wave_ids.clear()
	diagnostic_jump_count = 0
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
			_start_wave(0, true)
		return
	if phase != "active":
		return
	wave_elapsed += delta
	if wave_index == _boss_wave_index() and not boss_spawned:
		boss_spawned = true
		boss_requested.emit()
	if wave_elapsed >= float(_definition(wave_index).duration) and wave_index < _wave_count() - 1:
		_start_wave(wave_index + 1, true)

func _start_wave(index: int, ordinary_progression: bool) -> void:
	wave_index = index
	wave_elapsed = 0.0
	phase = "active"
	if ordinary_progression:
		var wave_id := String(_definition(index).get("id", ""))
		if ordinary_route_wave_ids.is_empty() or ordinary_route_wave_ids[-1] != wave_id:
			ordinary_route_wave_ids.append(wave_id)
	else:
		diagnostic_jump_count += 1
	_emit()

func _emit() -> void:
	phase_changed.emit(get_snapshot())

func prepare_test_wave(index: int) -> void:
	if not OS.has_feature("editor"):
		return
	_start_wave(clampi(index, 0, 4), false)

func get_snapshot() -> Dictionary:
	var definition := _definition(wave_index) if wave_index >= 0 else {}
	var expected_ids: PackedStringArray = WAVE_SEQUENCE.get_meta("wave_ids", PackedStringArray())
	var route_complete := _ordinary_route_complete()
	return {"phase":phase,"wave":wave_index + 1,"wave_count":_wave_count(),"wave_elapsed":wave_elapsed,
		"wave_duration":float(definition.get("duration",0.0)),"title":String(definition.get("title","WARMUP")),
		"warning":String(definition.get("warning","PREPARE")),"total_elapsed":total_elapsed,
		"boss_spawned":boss_spawned,"terminated":terminated,"definition":definition,
		"expected_route_wave_ids":Array(expected_ids),
		"ordinary_route_wave_ids":ordinary_route_wave_ids.duplicate(),
		"ordinary_route_complete":route_complete,
		"ordinary_route_eligible":route_complete and diagnostic_jump_count == 0,
		"diagnostic_jump_count":diagnostic_jump_count,
		"sequence_resource":"res://resources/waves/mournlight_wave_sequence.tres"}

func _wave_count() -> int:
	var ids: PackedStringArray = WAVE_SEQUENCE.get_meta("wave_ids", PackedStringArray())
	return ids.size()

func _boss_wave_index() -> int:
	return int(WAVE_SEQUENCE.get_meta("boss_wave_index", _wave_count() - 1))

func _ordinary_route_complete() -> bool:
	var expected: PackedStringArray = WAVE_SEQUENCE.get_meta("wave_ids", PackedStringArray())
	if ordinary_route_wave_ids.size() != expected.size():
		return false
	for index in expected.size():
		if ordinary_route_wave_ids[index] != expected[index]:
			return false
	return true

func _definition(index: int) -> Dictionary:
	if index < 0 or index >= _wave_count():
		return {}
	var ids: PackedStringArray = WAVE_SEQUENCE.get_meta("wave_ids")
	var titles: PackedStringArray = WAVE_SEQUENCE.get_meta("wave_titles")
	var durations: PackedFloat32Array = WAVE_SEQUENCE.get_meta("durations")
	var caps: PackedInt32Array = WAVE_SEQUENCE.get_meta("live_caps")
	var cadences: PackedFloat32Array = WAVE_SEQUENCE.get_meta("cadences")
	var budgets: PackedInt32Array = WAVE_SEQUENCE.get_meta("spawn_budgets")
	var initial_spawns: PackedInt32Array = WAVE_SEQUENCE.get_meta("initial_spawns", PackedInt32Array([6, 6, 6, 6, 6]))
	var warnings: PackedStringArray = WAVE_SEQUENCE.get_meta("warnings")
	var elite_every: PackedInt32Array = WAVE_SEQUENCE.get_meta("elite_every")
	var weights := {}
	for role in ROLE_KEYS:
		var values: PackedInt32Array = WAVE_SEQUENCE.get_meta(role + "_weights")
		weights[role] = int(values[index])
	return {
		"id": ids[index], "index": index, "title": titles[index],
		"duration": maxf(1.0, float(durations[index])),
		"cap": clampi(int(caps[index]), 1, MAX_LIVE_ENEMIES),
		"cadence": maxf(0.1, float(cadences[index])),
		"spawn_budget": clampi(int(budgets[index]), 1, MAX_SPAWN_BUDGET),
		"initial_spawns":int(initial_spawns[index]),
		"composition_weights": weights, "elite_every": int(elite_every[index]),
		"elite_enabled": int(elite_every[index]) > 0, "warning": warnings[index],
		"boss_wave": index == _boss_wave_index(),
	}

func _mcp_state() -> Dictionary:
	return get_snapshot()
