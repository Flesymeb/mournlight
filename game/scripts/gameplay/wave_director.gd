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
## A short explicit handoff keeps wave completion readable and gives the
## upgrade transaction a stable intermission state between pressure bands.
const INTERMISSION_SECONDS := 1.0
const ROUTE_CONTRACT_ID := "mournlight.ordinary_five_wave_route.v1"

var phase := "idle"
var wave_index := -1
var wave_elapsed := 0.0
var warmup_remaining := 4.0
var total_elapsed := 0.0
var boss_spawned := false
var boss_request_count := 0
var boss_entry_elapsed := 0.0
var intermission_remaining := 0.0
var terminated := false
var terminal_transition_count := 0
var terminal_outcome := ""
var terminal_rejected_count := 0
var terminal_rejection_reason := ""
var terminal_transition_receipt: Dictionary = {}
var ordinary_route_wave_ids: Array[String] = []
var diagnostic_jump_count := 0
var transition_serial := 0
var stale_transition_rejection_count := 0
var transition_history: Array[Dictionary] = []
var last_transition_receipt: Dictionary = {}
var ordinary_transition_times: Array[float] = []
## Immutable receipts for each completed pressure band.  Keeping completion
## separate from the next-wave transition makes the ordinary five-wave route
## auditable even when an intermission is paused by a draft transaction.
var wave_completion_receipts: Array[Dictionary] = []
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
	intermission_remaining = 0.0
	terminated = false
	terminal_transition_count = 0
	terminal_outcome = ""
	terminal_rejected_count = 0
	terminal_rejection_reason = ""
	terminal_transition_receipt.clear()
	ordinary_route_wave_ids.clear()
	diagnostic_jump_count = 0
	transition_serial = 0
	stale_transition_rejection_count = 0
	transition_history.clear()
	last_transition_receipt.clear()
	ordinary_transition_times.clear()
	wave_completion_receipts.clear()
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
	var requested_outcome := outcome.strip_edges()
	if requested_outcome.is_empty():
		terminal_rejected_count += 1
		terminal_rejection_reason = "empty_outcome"
		return
	terminated = true
	terminal_transition_count += 1
	terminal_outcome = requested_outcome
	phase = requested_outcome
	terminal_transition_receipt = {
		"transition_count":terminal_transition_count,
		"outcome":terminal_outcome,
		"phase":phase,
		"transition_serial":transition_serial,
		"elapsed":total_elapsed,
	}
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
	if phase == "intermission":
		intermission_remaining = maxf(0.0, intermission_remaining - delta)
		if intermission_remaining <= 0.0:
			_start_wave(wave_index + 1, true)
		return
	if phase != "active":
		return
	wave_elapsed += delta
	if wave_index == _boss_wave_index() and not boss_spawned:
		boss_entry_elapsed += delta
		last_transition_receipt["boss_entry_elapsed"] = boss_entry_elapsed
	# Natural Bellkeeper entry is gated by immutable completion receipts for the
	# preceding pressure bands. This keeps a deferred/intermission callback from
	# exposing the boss on a partially traversed ordinary route while diagnostics
	# remain explicitly bypassable and ineligible for release qualification.
	var boss_route_ready := diagnostic_jump_count > 0 or _ordinary_boss_entry_ready()
	if wave_index == _boss_wave_index() and not boss_spawned and boss_request_count == 0 and boss_entry_elapsed >= BOSS_ENTRY_DELAY_SECONDS and boss_route_ready:
		boss_spawned = true
		boss_request_count += 1
		last_transition_receipt["boss_trigger"] = "final_wave_elapsed"
		last_transition_receipt["boss_request_count"] = boss_request_count
		if not transition_history.is_empty():
			transition_history[transition_history.size() - 1] = last_transition_receipt.duplicate(true)
		boss_requested.emit()
	if wave_elapsed >= float(_definition(wave_index).duration) and wave_index < _wave_count() - 1:
		var completed_definition := _definition(wave_index)
		var completed_encounter: Dictionary = encounter_spawner.get_snapshot() if is_instance_valid(encounter_spawner) and encounter_spawner.has_method("get_snapshot") else {}
		wave_completion_receipts.append({
			"wave":wave_index + 1,
			"wave_id":String(completed_definition.get("id", "")),
			"elapsed":total_elapsed,
			"spawn_budget":int(completed_definition.get("spawn_budget", 0)),
			"spawned_in_wave":int(completed_encounter.get("wave_spawned", 0)),
			"active_enemies":int(completed_encounter.get("live", 0)),
			"ordinary_progression":ordinary_route_wave_ids.size() == wave_index + 1 and diagnostic_jump_count == 0,
		})
		phase = "intermission"
		intermission_remaining = INTERMISSION_SECONDS
		last_transition_receipt["intermission_seconds"] = INTERMISSION_SECONDS
		_emit()

func _start_wave(index: int, ordinary_progression: bool) -> void:
	if terminated:
		return
	var bounded_index := clampi(index, 0, maxi(0, _wave_count() - 1))
	# Wave ownership is monotonic for a live run.  Deferred callbacks can arrive
	# after an intermission has already handed off to the next pressure band;
	# accepting a stale lower index would rewind the authoritative route and make
	# a fresh ordinary replay look permanently stuck in Wave 1.  Ignore those
	# callbacks (and same-index duplicates) before mutating any state.
	if phase in ["active", "intermission"] and bounded_index <= wave_index:
		stale_transition_rejection_count += 1
		return
	# Ordinary eligibility is earned only by the contiguous authored sequence.
	# Treat any out-of-order request as diagnostic, even if a stale caller marks
	# it ordinary; this keeps fixture jumps from silently qualifying a run.
	var expected_ordinary_index := 0 if wave_index < 0 else wave_index + 1
	if ordinary_progression and (bounded_index != expected_ordinary_index or ordinary_route_wave_ids.size() != bounded_index):
		ordinary_progression = false
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
		"intermission_seconds":0.0,
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
	var expected_ids: PackedStringArray = _meta_string_array("wave_ids", PackedStringArray(["first_toll", "crossing_shadows", "gravewind", "long_procession", "bellkeeper"]))
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
		"boss_spawned":boss_spawned,"boss_request_count":boss_request_count,
		# Before the request, zero is the only valid count; after it, exactly one
		# is required. This makes duplicate-request regressions observable even
		# when a stale callback arrives before the Bellkeeper node is attached.
		"boss_requested_exactly_once": (boss_request_count == 0 and not boss_spawned) or (boss_spawned and boss_request_count == 1),
		"boss_entry_elapsed":boss_entry_elapsed,"boss_entry_delay_seconds":BOSS_ENTRY_DELAY_SECONDS if wave_index == _boss_wave_index() else 0.0,
		"intermission_remaining":intermission_remaining,
		# Compact retest receipts: these mirror authoritative sibling state while
		# keeping timing, spawn budget, and terminal ownership in separate systems.
		"spawn_budget":budget_total,
		"spawned_in_wave":spawned_in_wave,
		"spawn_budget_remaining":maxi(0, budget_total - spawned_in_wave),
		"active_enemies":int(encounter.get("live", 0)),
		"enemy_cap":int(encounter.get("cap", definition.get("cap", 0))),
		"boss_state":"absent" if not boss_spawned else ("requested" if boss_request_count > 0 else "pending"),
		"terminal_predicate": {"terminated":terminated,"terminal_transition_count":terminal_transition_count,"spawning_allowed":not terminated and phase == "active","outcome":terminal_outcome,"rejected_count":terminal_rejected_count},
		"terminated":terminated,"terminal_outcome":terminal_outcome,"terminal_transition_receipt":terminal_transition_receipt.duplicate(true),
		"terminal_rejected_count":terminal_rejected_count,"terminal_rejection_reason":terminal_rejection_reason,"definition":definition,
		"expected_route_wave_ids":Array(expected_ids),
		"ordinary_route_wave_ids":ordinary_route_wave_ids.duplicate(),
		"ordinary_transition_times":ordinary_transition_times.duplicate(),
		"wave_completion_receipts":wave_completion_receipts.duplicate(true),
		"ordinary_route_next_wave_id":next_wave_id,
		"ordinary_route_contiguous":route_contiguous,
		"ordinary_route_complete":route_complete,
		"ordinary_boss_entry_ready":_ordinary_boss_entry_ready() or diagnostic_jump_count > 0,
		"ordinary_route_eligible":route_complete and diagnostic_jump_count == 0,
		"diagnostic_jump_count":diagnostic_jump_count,
		"stale_transition_rejection_count":stale_transition_rejection_count,
		"transition_serial":transition_serial,
		"transition_history":transition_history.duplicate(true),
		"last_transition":last_transition_receipt.duplicate(true),
		"terminal_transition_count":terminal_transition_count,
		"sequence_resource":"res://resources/waves/mournlight_wave_sequence.tres"}

func _wave_count() -> int:
	var ids: PackedStringArray = _meta_string_array("wave_ids", PackedStringArray())
	return ids.size()

func _boss_wave_index() -> int:
	var value: Variant = WAVE_SEQUENCE.get_meta("boss_wave_index", _wave_count() - 1)
	return clampi(int(value), 0, maxi(0, _wave_count() - 1))

func _ordinary_route_complete() -> bool:
	var expected: PackedStringArray = _meta_string_array("wave_ids", PackedStringArray(["first_toll", "crossing_shadows", "gravewind", "long_procession", "bellkeeper"]))
	if ordinary_route_wave_ids.size() != expected.size():
		return false
	for index in expected.size():
		if ordinary_route_wave_ids[index] != expected[index]:
			return false
	return true

func _ordinary_boss_entry_ready() -> bool:
	if not _ordinary_route_complete():
		return false
	var completed_ids: Dictionary = {}
	for receipt_value in wave_completion_receipts:
		var receipt: Dictionary = receipt_value
		if bool(receipt.get("ordinary_progression", false)):
			completed_ids[String(receipt.get("wave_id", ""))] = true
	for required_id in ["first_toll", "crossing_shadows", "gravewind", "long_procession"]:
		if not completed_ids.has(required_id):
			return false
	return wave_index == _boss_wave_index() and phase == "active"

## Compact, read-only receipt used by focused route checks and runtime probes.
## It reports the contiguous sequence, cap/budget ownership, and single boss
## request predicate without mutating director state.
func get_route_contract_receipt() -> Dictionary:
	var snapshot := get_snapshot()
	return {
		"contract_id": ROUTE_CONTRACT_ID,
		"expected_wave_ids": (snapshot.get("expected_route_wave_ids", []) as Array).duplicate(),
		"observed_wave_ids": (snapshot.get("ordinary_route_wave_ids", []) as Array).duplicate(),
		"contiguous": bool(snapshot.get("ordinary_route_contiguous", false)),
		"complete": bool(snapshot.get("ordinary_route_complete", false)),
		"eligible": bool(snapshot.get("ordinary_route_eligible", false)),
		"boss_entry_ready": bool(snapshot.get("ordinary_boss_entry_ready", false)),
		"live_cap": int(snapshot.get("enemy_cap", 0)),
		"spawn_budget_remaining": int(snapshot.get("spawn_budget_remaining", 0)),
		"boss_request_count": int(snapshot.get("boss_request_count", 0)),
		"boss_requested_exactly_once": bool(snapshot.get("boss_requested_exactly_once", false)),
		"stale_transition_rejection_count": int(snapshot.get("stale_transition_rejection_count", 0)),
		"terminal_outcome": String(snapshot.get("terminal_outcome", "")),
		"terminal_transition_receipt": (snapshot.get("terminal_transition_receipt", {}) as Dictionary).duplicate(true),
		"terminal": (snapshot.get("terminal_predicate", {}) as Dictionary).duplicate(true),
	}

func _definition(index: int) -> Dictionary:
	if index < 0 or index >= _wave_count():
		return {}
	var ids: PackedStringArray = _meta_string_array("wave_ids", PackedStringArray(["first_toll", "crossing_shadows", "gravewind", "long_procession", "bellkeeper"]))
	var titles: PackedStringArray = _meta_string_array("wave_titles", PackedStringArray(["The First Toll", "Crossing Shadows", "Gravewind", "The Long Procession", "The Bellkeeper"]))
	var durations: PackedFloat32Array = _meta_float_array("durations", PackedFloat32Array([30.0, 85.0, 130.0, 165.0, 120.0]))
	var caps: PackedInt32Array = _meta_int_array("live_caps", PackedInt32Array([6, 14, 18, 36, 32]))
	var cadences: PackedFloat32Array = _meta_float_array("cadences", PackedFloat32Array([1.9, 1.15, 0.98, 0.58, 0.48]))
	var budgets: PackedInt32Array = _meta_int_array("spawn_budgets", PackedInt32Array([22, 46, 60, 120, 128]))
	var initial_spawns: PackedInt32Array = _meta_int_array("initial_spawns", PackedInt32Array([6, 6, 6, 6, 6]))
	var warnings: PackedStringArray = _meta_string_array("warnings", PackedStringArray(["TEACHING PRESSURE", "FLANK PRESSURE", "RANGED ELITE", "MIXED DENSITY", "FINAL TOLL"]))
	var elite_every: PackedInt32Array = _meta_int_array("elite_every", PackedInt32Array([0, 0, 9, 7, 8]))
	var weights := {}
	for role in ROLE_KEYS:
		var values: PackedInt32Array = _meta_int_array(role + "_weights", PackedInt32Array([0, 0, 0, 0, 0]))
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

func _meta_string_array(key: String, fallback: PackedStringArray) -> PackedStringArray:
	var value: Variant = WAVE_SEQUENCE.get_meta(key, fallback)
	return value if value is PackedStringArray and value.size() > 0 else fallback

func _meta_float_array(key: String, fallback: PackedFloat32Array) -> PackedFloat32Array:
	var value: Variant = WAVE_SEQUENCE.get_meta(key, fallback)
	return value if value is PackedFloat32Array and value.size() > 0 else fallback

func _meta_int_array(key: String, fallback: PackedInt32Array) -> PackedInt32Array:
	var value: Variant = WAVE_SEQUENCE.get_meta(key, fallback)
	return value if value is PackedInt32Array and value.size() > 0 else fallback

func _mcp_state() -> Dictionary:
	return get_snapshot()
