class_name MournlightWaveDirector
extends Node

signal phase_changed(snapshot: Dictionary)
signal boss_requested
signal victory_requested

const WAVE_SEQUENCE := preload("res://resources/waves/mournlight_wave_sequence.tres")
const ROLE_KEYS := ["mossling", "wispbat", "bone_slinger", "grave_brute"]
const MAX_LIVE_ENEMIES := 40
const MAX_SPAWN_BUDGET := 160
## Keep a short authored warning beat at the start of the Bellkeeper wave.
## The director remains the sole owner of boss timing; this delay gives the
## HUD/camera a deterministic transition window before the boss is requested.
const BOSS_ENTRY_DELAY_SECONDS := 1.5
const ROUTE_CONTRACT_ID := "mournlight.ordinary_five_wave_route.v1"

var phase := "idle"
var wave_index := -1
var wave_elapsed := 0.0
var warmup_remaining := 4.0
var total_elapsed := 0.0
var boss_spawned := false
var boss_request_count := 0
var boss_entry_elapsed := 0.0
var terminated := false
var terminal_transition_count := 0
var ordinary_route_wave_ids: Array[String] = []
var diagnostic_jump_count := 0
var transition_serial := 0
var transition_history: Array[Dictionary] = []
var last_transition_receipt: Dictionary = {}
var ordinary_transition_times: Array[float] = []
## Sibling encounter owner used only for read-only receipts. Wave timing remains
## authoritative here; the spawner owns entity lifetime and never drives phase.
@onready var encounter_spawner: Node = get_parent().get_node_or_null("World/EncounterSpawner")

func reset() -> void:
	phase = "idle"
	wave_index = -1
	wave_elapsed = 0.0
	warmup_remaining = 4.0
	total_elapsed = 0.0
	boss_spawned = false
	boss_request_count = 0
	boss_entry_elapsed = 0.0
	terminated = false
	terminal_transition_count = 0
	ordinary_route_wave_ids.clear()
	diagnostic_jump_count = 0
	transition_serial = 0
	transition_history.clear()
	last_transition_receipt.clear()
	ordinary_transition_times.clear()
	set_process(false)

func begin() -> void:
	reset()
	phase = "warmup"
	set_process(true)
	_emit()

func terminate(outcome: String) -> void:
	# Terminal ownership is single-shot. Repeated victory/failure callbacks can
	# arrive during deferred teardown; keep the first authoritative outcome and
	# do not emit duplicate phase transitions into the run controller.
	if terminated:
		return
	terminated = true
	terminal_transition_count += 1
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
		boss_entry_elapsed += delta
		last_transition_receipt["boss_entry_elapsed"] = boss_entry_elapsed
	var boss_route_ready := diagnostic_jump_count > 0 or _ordinary_route_complete()
	if wave_index == _boss_wave_index() and not boss_spawned and boss_request_count == 0 and boss_entry_elapsed >= BOSS_ENTRY_DELAY_SECONDS and boss_route_ready:
		boss_spawned = true
		boss_request_count += 1
		last_transition_receipt["boss_trigger"] = "final_wave_elapsed"
		last_transition_receipt["boss_request_count"] = boss_request_count
		if not transition_history.is_empty():
			transition_history[transition_history.size() - 1] = last_transition_receipt.duplicate(true)
		boss_requested.emit()
	if wave_elapsed >= float(_definition(wave_index).duration) and wave_index < _wave_count() - 1:
		_start_wave(wave_index + 1, true)

func _start_wave(index: int, ordinary_progression: bool) -> void:
	if terminated:
		return
	var bounded_index := clampi(index, 0, maxi(0, _wave_count() - 1))
	# Ordinary eligibility is earned only by the contiguous authored sequence.
	# Treat any out-of-order request as diagnostic, even if a stale caller marks
	# it ordinary; this keeps fixture jumps from silently qualifying a run.
	var expected_ordinary_index := 0 if wave_index < 0 else wave_index + 1
	if ordinary_progression and (bounded_index != expected_ordinary_index or ordinary_route_wave_ids.size() != bounded_index):
		ordinary_progression = false
	# Duplicate callbacks during reload/teardown must not reset an active wave or
	# append a second copy of its stable route id.
	if phase == "active" and wave_index == bounded_index:
		return
	wave_index = bounded_index
	wave_elapsed = 0.0
	# A fresh fifth-wave entry always owns a new warning window, including
	# editor-only retests that revisit the final wave after a prior boss request.
	boss_entry_elapsed = 0.0
	phase = "active"
	transition_serial += 1
	var wave_id := String(_definition(wave_index).get("id", ""))
	last_transition_receipt = {
		"serial":transition_serial, "wave_index":wave_index, "wave":wave_index + 1,
		"wave_id":wave_id, "ordinary_progression":ordinary_progression,
		"diagnostic_jump_count":diagnostic_jump_count, "elapsed_before":total_elapsed,
		"boss_entry_delay_seconds":BOSS_ENTRY_DELAY_SECONDS if bounded_index == _boss_wave_index() else 0.0,
		"boss_entry_elapsed":0.0,
	}
	transition_history.append(last_transition_receipt.duplicate(true))
	while transition_history.size() > 8:
		transition_history.pop_front()
	if ordinary_progression:
		if ordinary_route_wave_ids.is_empty() or ordinary_route_wave_ids[-1] != wave_id:
			ordinary_route_wave_ids.append(wave_id)
			ordinary_transition_times.append(total_elapsed)
	else:
		diagnostic_jump_count += 1
		last_transition_receipt["diagnostic_jump_count"] = diagnostic_jump_count
		transition_history[transition_history.size() - 1] = last_transition_receipt.duplicate(true)
	_emit()

func _emit() -> void:
	phase_changed.emit(get_snapshot())

func prepare_test_wave(index: int) -> void:
	if not OS.has_feature("editor"):
		return
	_start_wave(clampi(index, 0, 4), false)

func get_snapshot() -> Dictionary:
	var definition := _definition(wave_index) if wave_index >= 0 else {}
	var encounter: Dictionary = encounter_spawner.get_snapshot() if is_instance_valid(encounter_spawner) and encounter_spawner.has_method("get_snapshot") else {}
	var expected_ids: PackedStringArray = WAVE_SEQUENCE.get_meta("wave_ids", PackedStringArray())
	var route_complete := _ordinary_route_complete()
	var next_wave_id := ""
	if ordinary_route_wave_ids.size() < expected_ids.size():
		next_wave_id = String(expected_ids[ordinary_route_wave_ids.size()])
	var route_contiguous := (diagnostic_jump_count == 0 and ordinary_route_wave_ids.size() == wave_index + 1) if wave_index >= 0 else ordinary_route_wave_ids.is_empty()
	var budget_total := int(definition.get("spawn_budget", 0))
	var spawned_in_wave := int(encounter.get("wave_spawned", 0))
	return {"phase":phase,"wave":wave_index + 1,"wave_count":_wave_count(),"wave_elapsed":wave_elapsed,
		"route_contract_id":ROUTE_CONTRACT_ID,
		"ordinary_route_progress": {"completed":ordinary_route_wave_ids.size(), "required":expected_ids.size(), "next_wave_id":next_wave_id},
		"wave_duration":float(definition.get("duration",0.0)),"title":String(definition.get("title","WARMUP")),
		"warning":String(definition.get("warning","PREPARE")),"total_elapsed":total_elapsed,
		"boss_spawned":boss_spawned,"boss_request_count":boss_request_count,"boss_requested_exactly_once":boss_request_count == 1 if boss_spawned else true,
		"boss_entry_elapsed":boss_entry_elapsed,"boss_entry_delay_seconds":BOSS_ENTRY_DELAY_SECONDS if wave_index == _boss_wave_index() else 0.0,
		# Compact retest receipts: these mirror authoritative sibling state while
		# keeping timing, spawn budget, and terminal ownership in separate systems.
		"spawn_budget":budget_total,
		"spawned_in_wave":spawned_in_wave,
		"spawn_budget_remaining":maxi(0, budget_total - spawned_in_wave),
		"active_enemies":int(encounter.get("live", 0)),
		"enemy_cap":int(encounter.get("cap", definition.get("cap", 0))),
		"boss_state":"absent" if not boss_spawned else ("requested" if boss_request_count > 0 else "pending"),
		"terminal_predicate": {"terminated":terminated,"terminal_transition_count":terminal_transition_count,"spawning_allowed":not terminated and phase == "active"},
		"terminated":terminated,"definition":definition,
		"expected_route_wave_ids":Array(expected_ids),
		"ordinary_route_wave_ids":ordinary_route_wave_ids.duplicate(),
		"ordinary_transition_times":ordinary_transition_times.duplicate(),
		"ordinary_route_next_wave_id":next_wave_id,
		"ordinary_route_contiguous":route_contiguous,
		"ordinary_route_complete":route_complete,
		"ordinary_route_eligible":route_complete and diagnostic_jump_count == 0,
		"diagnostic_jump_count":diagnostic_jump_count,
		"transition_serial":transition_serial,
		"transition_history":transition_history.duplicate(true),
		"last_transition":last_transition_receipt.duplicate(true),
		"terminal_transition_count":terminal_transition_count,
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
