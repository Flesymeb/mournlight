class_name CompleteRunLedger
extends RefCounted

const EXPECTED_WAVES := ["first_toll", "crossing_shadows", "gravewind", "long_procession", "bellkeeper"]
const PROVENANCE_MANIFEST := "res://ASSET_PROVENANCE.json"
const MAX_SESSION_ROWS := 10
const MAX_DIAGNOSTIC_EVENTS := 24
const BUILD_SHAPES := ["focused_lantern", "close_gravespade", "orbiting_wisps"]

var current_run: Dictionary = {}
var completed_rows: Array[Dictionary] = []
var diagnostic_events: Array[Dictionary] = []
var credits_traversals: Array[Dictionary] = []
var session_generation := 0
var contract_checks: Dictionary = {}
var provenance_manifest: Dictionary = {}

func _init() -> void:
	# Shipped manifest bytes are the sole authority. Cache this immutable
	# runtime-session receipt once so Credits and snapshots cannot drift through
	# a copied predecessor literal or incur file I/O on every HUD snapshot.
	provenance_manifest = _read_provenance_manifest()
	contract_checks = _run_contract_checks()

func begin_run(run_serial: int, route_kind: String, started_from: String) -> void:
	_mark_prior_replay_if_applicable(run_serial, started_from)
	session_generation += 1
	var origin_event := "retry_replay" if started_from == "retry" else "title_play"
	current_run = {
		"session_generation":session_generation,
		"run_serial":run_serial,
		"route_kind":route_kind,
		"started_from":started_from,
		"milestones":[_milestone(origin_event, 0.0, {"player_caused":true,"started_from":started_from})],
		"wave_ids":[],
		"drafts":[],
		"boss_events":[],
		"diagnostic_jump_count":0,
		"terminal":{},
		"result_presented":false,
		"retry_observed":false,
		"title_return_observed":false,
		"replay_observed":false,
		"replay_observed_count":0,
	}

func record_wave(snapshot: Dictionary, elapsed: float, route_kind: String) -> void:
	var wave_id := String((snapshot.get("definition", {}) as Dictionary).get("id", ""))
	if wave_id.is_empty():
		return
	if not _accepts_ordinary(route_kind, snapshot):
		_record_diagnostic("wave_prepare", elapsed, {"wave_id":wave_id,"route_kind":route_kind,"diagnostic_jump_count":snapshot.get("diagnostic_jump_count",0)})
		return
	if current_run.is_empty() or int(current_run.get("run_serial", -1)) < 0:
		return
	var wave_ids: Array = current_run.get("wave_ids", [])
	if wave_ids.is_empty() or String(wave_ids.back()) != wave_id:
		wave_ids.append(wave_id)
		current_run["wave_ids"] = wave_ids
		(current_run["milestones"] as Array).append(_milestone("wave_started", elapsed, {"wave_id":wave_id,"ordinal":wave_ids.size()}))

func record_draft(choice: Dictionary, elapsed: float, route_kind: String, diagnostic_jumps: int) -> void:
	if route_kind != "ordinary" or diagnostic_jumps != 0 or not bool(choice.get("natural_choice", false)):
		_record_diagnostic("draft_choice", elapsed, {"route_kind":route_kind,"choice":choice.duplicate(true)})
		return
	var drafts: Array = current_run.get("drafts", [])
	drafts.append(choice.duplicate(true))
	current_run["drafts"] = drafts
	(current_run["milestones"] as Array).append(_milestone("natural_draft", elapsed, {"upgrade_id":choice.get("id", ""),"draft_serial":choice.get("draft_serial",0)}))

func record_boss(event: String, payload: Dictionary, elapsed: float, route_kind: String, diagnostic_jumps: int) -> void:
	if route_kind != "ordinary" or diagnostic_jumps != 0:
		_record_diagnostic(event, elapsed, payload)
		return
	var events: Array = current_run.get("boss_events", [])
	var entry := payload.duplicate(true)
	entry["event"] = event
	entry["elapsed"] = elapsed
	events.append(entry)
	current_run["boss_events"] = events
	(current_run["milestones"] as Array).append(_milestone(event, elapsed, entry))

func record_terminal(terminal: Dictionary, wave_snapshot: Dictionary) -> void:
	var route_kind := String(terminal.get("route_kind", ""))
	var diagnostic_jumps := int(wave_snapshot.get("diagnostic_jump_count", 0))
	if route_kind != "ordinary" or diagnostic_jumps != 0:
		_record_diagnostic("terminal_commit", float(terminal.get("elapsed", 0.0)), terminal)
		return
	var truthful := terminal.duplicate(true)
	truthful["weapon_ranks"] = _equipped_weapon_ranks(terminal)
	truthful["build_shape"] = _classify_build_shape(truthful["weapon_ranks"])
	truthful["ordered_wave_ids"] = (wave_snapshot.get("ordinary_route_wave_ids", []) as Array).duplicate()
	truthful["ledger_boss_events"] = (current_run.get("boss_events", []) as Array).duplicate(true)
	truthful["diagnostic_jump_count"] = diagnostic_jumps
	truthful["truthful_result_fields"] = _truthful_result_fields(truthful)
	truthful["ordinary_failure_eligible"] = _ordinary_failure_eligible(truthful)
	truthful["ordinary_victory_eligible"] = _ordinary_victory_eligible(truthful)
	truthful["ordinary_build_eligible"] = _ordinary_build_eligible(truthful)
	current_run["terminal"] = truthful
	current_run["wave_ids"] = truthful["ordered_wave_ids"]
	(current_run["milestones"] as Array).append(_milestone("terminal_commit", float(terminal.get("elapsed", 0.0)), {"outcome":terminal.get("outcome", ""),"commit_count":terminal.get("commit_count",0)}))
	_append_completed_row()

func record_result_presented(run_serial: int, outcome: String) -> void:
	_update_row(run_serial, "result_presented", true)
	_update_row(run_serial, "result_outcome", outcome)
	var terminal: Dictionary = current_run.get("terminal", {})
	_append_row_milestone(run_serial, _milestone("result_presented", float(terminal.get("elapsed", 0.0)), {"outcome":outcome}))

func record_exit(run_serial: int, exit_kind: String, elapsed: float) -> void:
	if exit_kind == "retry":
		_update_row(run_serial, "retry_observed", true)
	elif exit_kind == "title":
		_update_row(run_serial, "title_return_observed", true)
	_append_row_milestone(run_serial, _milestone(exit_kind, elapsed, {"player_caused":true}))
	if int(current_run.get("run_serial", -1)) == run_serial:
		current_run["%s_observed" % exit_kind] = true
		(current_run["milestones"] as Array).append(_milestone(exit_kind, elapsed, {"player_caused":true}))

func record_credits(run_serial: int, shell_mode: String) -> void:
	var receipt := {
		"run_serial":run_serial,
		"session_generation":session_generation,
		"shell_mode":shell_mode,
		"manifest_path":provenance_manifest.get("path", PROVENANCE_MANIFEST),
		"manifest_sha256":provenance_manifest.get("sha256", ""),
		"visible_surface_observed":shell_mode == "credits",
		"provenance_bound":shell_mode == "credits" and bool(provenance_manifest.get("bound", false)),
		"manifest_source":provenance_manifest.get("source", "unavailable"),
		"observed_process_frame":Engine.get_process_frames(),
		"substitutes_for_gameplay_completion":false,
	}
	credits_traversals.append(receipt)
	while credits_traversals.size() > 6:
		credits_traversals.pop_front()

func get_snapshot() -> Dictionary:
	var rows := completed_rows.duplicate(true)
	var matrix := _evaluate_matrix(rows, credits_traversals)
	return {
		"identity":"mournlight.complete_run_session.v1",
		"session_generation":session_generation,
		"current_run":current_run.duplicate(true),
		"completed_rows":rows,
		"completed_row_count":rows.size(),
		"diagnostic_namespace":diagnostic_events.duplicate(true),
		"diagnostic_events_rejected_from_ordinary":true,
		"credits_traversals":credits_traversals.duplicate(true),
		"provenance_manifest":provenance_manifest.duplicate(true),
		"matrix":matrix,
		"contract_checks":contract_checks.duplicate(true),
	}

func _evaluate_matrix(rows: Array, credits: Array) -> Dictionary:
	var shapes: Array[String] = []
	var shape_rows: Dictionary = {}
	var row_qualifications: Array[Dictionary] = []
	var seen_run_serials: Dictionary = {}
	var failure_retry := false
	var failure_row_serial := -1
	var victory_replay := false
	var victory_row_serial := -1
	for row_value in rows:
		var row: Dictionary = row_value
		var terminal: Dictionary = row.get("terminal", {})
		var run_serial := int(row.get("run_serial", -1))
		var repeated_run_serial := seen_run_serials.has(run_serial)
		seen_run_serials[run_serial] = true
		var result_matches := bool(row.get("result_presented", false)) and String(row.get("result_outcome", "")) == String(terminal.get("outcome", ""))
		var qualification := _row_qualification(row, repeated_run_serial)
		var shape := String(qualification.get("build_shape", ""))
		var matrix_accepted := false
		var matrix_rejection_reason := String(qualification.get("rejection_reason", ""))
		if bool(qualification.get("success_qualified", false)):
			if shape_rows.has(shape):
				matrix_rejection_reason = "build_shape_already_filled"
			else:
				shapes.append(shape)
				shape_rows[shape] = run_serial
				matrix_accepted = true
		qualification["matrix_accepted"] = matrix_accepted
		qualification["matrix_rejection_reason"] = matrix_rejection_reason
		row_qualifications.append(qualification)
		if not repeated_run_serial and not failure_retry and _ordinary_failure_eligible(terminal) and result_matches and bool(row.get("retry_observed", false)):
			failure_retry = true
			failure_row_serial = run_serial
		var replay_count := int(row.get("replay_observed_count", 1 if bool(row.get("replay_observed", false)) else 0))
		if not repeated_run_serial and not victory_replay and _ordinary_victory_eligible(terminal) and result_matches and replay_count == 1:
			victory_replay = true
			victory_row_serial = run_serial
	var credits_traversed := false
	for credit_value in credits:
		var credit: Dictionary = credit_value
		if bool(credit.get("visible_surface_observed", false)) and bool(credit.get("provenance_bound", false)) and String(credit.get("shell_mode", "")) == "credits":
			credits_traversed = true
			break
	var missing: Array[String] = []
	if not failure_retry: missing.append("ordinary_failure_result_retry")
	if not victory_replay: missing.append("ordinary_victory_result_replay")
	for required_shape in ["focused_lantern", "close_gravespade", "orbiting_wisps"]:
		if not shape_rows.has(required_shape): missing.append("ordinary_build_%s" % required_shape)
	if not credits_traversed: missing.append("credits_and_notices")
	return {
		"failure_result_retry":failure_retry,
		"failure_row_serial":failure_row_serial,
		"victory_result_replay":victory_replay,
		"victory_row_serial":victory_row_serial,
		"ordinary_build_shapes":shapes,
		"ordinary_build_shape_rows":shape_rows,
		"distinct_build_row_count":shape_rows.size(),
		"row_qualifications":row_qualifications,
		"credits_traversed":credits_traversed,
		"missing_rows":missing,
		"remaining_matrix_cells":missing.duplicate(),
		"complete":missing.is_empty(),
	}

func _row_qualification(row: Dictionary, repeated_run_serial: bool) -> Dictionary:
	var terminal: Dictionary = row.get("terminal", {})
	var result_presented := bool(row.get("result_presented", false))
	var terminal_outcome := String(terminal.get("outcome", ""))
	var result_outcome := String(row.get("result_outcome", ""))
	var result_matches := result_presented and result_outcome == terminal_outcome
	var rejection_reasons := _victory_rejection_reasons(terminal)
	var build_shape := String(terminal.get("build_shape", "unclassified"))
	if build_shape not in BUILD_SHAPES:
		rejection_reasons.append("build_shape_%s" % build_shape)
	if (terminal.get("weapon_ranks", []) as Array).is_empty():
		rejection_reasons.append("no_equipped_weapon_ranks")
	if not result_presented:
		rejection_reasons.append("result_not_presented")
	elif not result_matches:
		rejection_reasons.append("result_outcome_mismatch")
	if repeated_run_serial:
		rejection_reasons.append("repeated_run_serial")
	return {
		"run_serial":int(row.get("run_serial", -1)),
		"outcome":terminal_outcome,
		"route_kind":String(terminal.get("route_kind", "")),
		"route_eligible":_ordinary_victory_eligible(terminal),
		"build_shape":build_shape,
		"success_qualified":rejection_reasons.is_empty(),
		"result_presented":result_presented,
		"result_matches_terminal":result_matches,
		"rejection_reason":"qualified" if rejection_reasons.is_empty() else String(rejection_reasons[0]),
		"rejection_reasons":rejection_reasons,
	}

func _append_completed_row() -> void:
	if current_run.is_empty():
		return
	var row := current_run.duplicate(true)
	row["completed_process_frame"] = Engine.get_process_frames()
	completed_rows.append(row)
	while completed_rows.size() > MAX_SESSION_ROWS:
		completed_rows.pop_front()

func _update_row(run_serial: int, key: String, value: Variant) -> void:
	for index in range(completed_rows.size() - 1, -1, -1):
		if int(completed_rows[index].get("run_serial", -1)) == run_serial:
			completed_rows[index][key] = value
			return

func _append_row_milestone(run_serial: int, milestone: Dictionary) -> void:
	for index in range(completed_rows.size() - 1, -1, -1):
		if int(completed_rows[index].get("run_serial", -1)) != run_serial:
			continue
		var milestones: Array = completed_rows[index].get("milestones", [])
		milestones.append(milestone.duplicate(true))
		completed_rows[index]["milestones"] = milestones
		return

func _mark_prior_replay_if_applicable(next_run_serial: int, started_from: String) -> void:
	# A new title Play is a new route, not proof that the prior victory's Result
	# Replay control was traversed. Only the player-caused Result Retry route may
	# fill the replay cell.
	if started_from != "retry":
		return
	var replay_source_serial := next_run_serial - 1
	for index in range(completed_rows.size() - 1, -1, -1):
		if int(completed_rows[index].get("run_serial", -1)) != replay_source_serial:
			continue
		var terminal: Dictionary = completed_rows[index].get("terminal", {})
		var result_matches := bool(completed_rows[index].get("result_presented", false)) and String(completed_rows[index].get("result_outcome", "")) == String(terminal.get("outcome", ""))
		if _ordinary_victory_eligible(terminal) and result_matches and not bool(completed_rows[index].get("replay_observed", false)):
			completed_rows[index]["replay_observed"] = true
			completed_rows[index]["replay_run_serial"] = next_run_serial
			completed_rows[index]["replay_observed_count"] = 1
		return

func _accepts_ordinary(route_kind: String, snapshot: Dictionary) -> bool:
	return route_kind == "ordinary" and int(snapshot.get("diagnostic_jump_count", 0)) == 0

func _record_diagnostic(event: String, elapsed: float, payload: Dictionary) -> void:
	diagnostic_events.append({"event":event,"elapsed":elapsed,"payload":payload.duplicate(true),"ordinary_row_population":false})
	while diagnostic_events.size() > MAX_DIAGNOSTIC_EVENTS:
		diagnostic_events.pop_front()

func _ordinary_victory_eligible(terminal: Dictionary) -> bool:
	return _victory_rejection_reasons(terminal).is_empty()

func _victory_rejection_reasons(terminal: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	if String(terminal.get("outcome", "")) != "victory": reasons.append("outcome_not_victory")
	if String(terminal.get("route_kind", "")) != "ordinary": reasons.append("route_not_ordinary")
	if int(terminal.get("diagnostic_jump_count", -1)) != 0: reasons.append("diagnostic_route")
	if Array(terminal.get("ordered_wave_ids", [])) != EXPECTED_WAVES: reasons.append("ordered_five_wave_route_incomplete")
	var elapsed := float(terminal.get("elapsed", 0.0))
	if elapsed < 420.0 or elapsed > 600.0: reasons.append("elapsed_outside_420_600")
	if int(terminal.get("commit_count", 0)) != 1: reasons.append("terminal_commit_count_not_one")
	if not bool(terminal.get("ordinary_route_eligible", false)): reasons.append("ordinary_route_not_eligible")
	if not bool(terminal.get("truthful_result_fields", false)): reasons.append("truthful_result_fields_missing")
	if not _terminal_has_two_phase_bellkeeper_defeat(terminal): reasons.append("natural_two_phase_bellkeeper_defeat_missing")
	return reasons

func _ordinary_failure_eligible(terminal: Dictionary) -> bool:
	return (
		String(terminal.get("outcome", "")) == "failure"
		and String(terminal.get("route_kind", "")) == "ordinary"
		and int(terminal.get("diagnostic_jump_count", -1)) == 0
		and int(terminal.get("commit_count", 0)) == 1
		and bool(terminal.get("truthful_result_fields", false))
	)

func _ordinary_build_eligible(terminal: Dictionary) -> bool:
	return (
		_ordinary_victory_eligible(terminal)
		and String(terminal.get("build_shape", "")) in BUILD_SHAPES
		and not (terminal.get("weapon_ranks", []) as Array).is_empty()
	)

func _terminal_has_two_phase_bellkeeper_defeat(terminal: Dictionary) -> bool:
	var phase_two := false
	var defeated := false
	for event_value in terminal.get("boss_transition_history", []):
		var event: Dictionary = event_value
		var event_name := String(event.get("event", ""))
		if event_name == "bellkeeper_phase_shifted" and int(event.get("phase", 0)) >= 2 and bool(event.get("natural_transition", false)):
			phase_two = true
	for event_value in terminal.get("ledger_boss_events", []):
		var event: Dictionary = event_value
		if String(event.get("event", "")) == "bellkeeper_defeated" and bool(event.get("defeat_committed", false)):
			defeated = true
	return phase_two and defeated

func _run_contract_checks() -> Dictionary:
	var live_rows_before := completed_rows.duplicate(true)
	var failure_terminal := _contract_terminal("failure", "close_gravespade")
	var lantern_victory := _contract_terminal("victory", "focused_lantern")
	var gravespade_victory := _contract_terminal("victory", "close_gravespade")
	var wisps_victory := _contract_terminal("victory", "orbiting_wisps")
	var diagnostic_terminal := _contract_terminal("victory", "focused_lantern")
	diagnostic_terminal["diagnostic_jump_count"] = 1
	diagnostic_terminal["ordinary_route_eligible"] = false
	var tied_terminal := _contract_terminal("victory", "mixed")
	var unclassified_terminal := _contract_terminal("victory", "unclassified")
	var incomplete_terminal := _contract_terminal("victory", "focused_lantern")
	incomplete_terminal["ordered_wave_ids"] = EXPECTED_WAVES.slice(0, 4)
	incomplete_terminal["ordinary_route_eligible"] = false
	var credit := {"shell_mode":"credits","visible_surface_observed":true,"provenance_bound":true}
	var failure_matrix := _evaluate_matrix([{"run_serial":1,"terminal":failure_terminal,"result_presented":true,"result_outcome":"failure","retry_observed":true}], [])
	var failed_build_matrix := _evaluate_matrix([{"run_serial":2,"terminal":failure_terminal,"result_presented":true,"result_outcome":"failure","retry_observed":true}], [])
	var repeated_serial_matrix := _evaluate_matrix([
		{"run_serial":3,"terminal":lantern_victory,"result_presented":true,"result_outcome":"victory"},
		{"run_serial":3,"terminal":gravespade_victory,"result_presented":true,"result_outcome":"victory"},
	], [])
	var diagnostic_matrix := _evaluate_matrix([{"run_serial":6,"terminal":diagnostic_terminal,"result_presented":true,"result_outcome":"victory"}], [])
	var tied_matrix := _evaluate_matrix([{"run_serial":7,"terminal":tied_terminal,"result_presented":true,"result_outcome":"victory"}], [])
	var mismatch_matrix := _evaluate_matrix([{"run_serial":8,"terminal":wisps_victory,"result_presented":true,"result_outcome":"failure"}], [])
	var unclassified_matrix := _evaluate_matrix([{"run_serial":9,"terminal":unclassified_terminal,"result_presented":true,"result_outcome":"victory"}], [])
	var incomplete_matrix := _evaluate_matrix([{"run_serial":10,"terminal":incomplete_terminal,"result_presented":true,"result_outcome":"victory"}], [])
	var complete_matrix := _evaluate_matrix([
		{"run_serial":1,"terminal":failure_terminal,"result_presented":true,"result_outcome":"failure","retry_observed":true},
		{"run_serial":3,"terminal":lantern_victory,"result_presented":true,"result_outcome":"victory","replay_observed":true,"replay_observed_count":1},
		{"run_serial":4,"terminal":gravespade_victory,"result_presented":true,"result_outcome":"victory"},
		{"run_serial":5,"terminal":wisps_victory,"result_presented":true,"result_outcome":"victory"},
	], [credit])
	var missing_matrix := _evaluate_matrix([], [])
	var live_rows_unchanged := completed_rows == live_rows_before
	var all_checks := (
		bool(failure_matrix.get("failure_result_retry", false))
		and int(failed_build_matrix.get("distinct_build_row_count", -1)) == 0
		and int(repeated_serial_matrix.get("distinct_build_row_count", -1)) == 1
		and int(diagnostic_matrix.get("distinct_build_row_count", -1)) == 0
		and int(tied_matrix.get("distinct_build_row_count", -1)) == 0
		and int(mismatch_matrix.get("distinct_build_row_count", -1)) == 0
		and int(unclassified_matrix.get("distinct_build_row_count", -1)) == 0
		and int(incomplete_matrix.get("distinct_build_row_count", -1)) == 0
		and int(complete_matrix.get("distinct_build_row_count", 0)) == 3
		and bool(complete_matrix.get("complete", false))
		and (missing_matrix.get("missing_rows", []) as Array).size() == 6
		and live_rows_unchanged
		and bool(provenance_manifest.get("bound", false))
	)
	return {
		"identity":"mournlight.complete_run_predicate_checks.v2",
		"failure_then_retry_independent":bool(failure_matrix.get("failure_result_retry", false)) and not bool(failure_matrix.get("victory_result_replay", false)),
		"failure_shaped_build_rejected":int(failed_build_matrix.get("distinct_build_row_count", -1)) == 0,
		"repeated_run_serial_rejected":int(repeated_serial_matrix.get("distinct_build_row_count", -1)) == 1,
		"tied_build_rejected":int(tied_matrix.get("distinct_build_row_count", -1)) == 0,
		"unclassified_build_rejected":int(unclassified_matrix.get("distinct_build_row_count", -1)) == 0,
		"incomplete_route_rejected":int(incomplete_matrix.get("distinct_build_row_count", -1)) == 0,
		"mismatched_result_rejected":int(mismatch_matrix.get("distinct_build_row_count", -1)) == 0,
		"three_distinct_build_rows":int(complete_matrix.get("distinct_build_row_count", 0)) == 3,
		"three_distinct_successful_victory_rows":int(complete_matrix.get("distinct_build_row_count", 0)) == 3 and bool(complete_matrix.get("victory_result_replay", false)),
		"diagnostic_row_excluded":int(diagnostic_matrix.get("distinct_build_row_count", -1)) == 0,
		"credits_independent_and_bound":bool(complete_matrix.get("credits_traversed", false)),
		"runtime_manifest_truth_bound":bool(provenance_manifest.get("bound", false)),
		"runtime_manifest_source":provenance_manifest.get("source", "unavailable"),
		"explicit_missing_rows":(missing_matrix.get("missing_rows", []) as Array).size() == 6,
		"all_checks_pass":all_checks,
		"session_mutated":not live_rows_unchanged,
		"rows_injected":0,
		"ordinary_completion_substitute":false,
	}

func _read_provenance_manifest() -> Dictionary:
	var exists := FileAccess.file_exists(PROVENANCE_MANIFEST)
	var digest := FileAccess.get_sha256(PROVENANCE_MANIFEST) if exists else ""
	return {
		"path":PROVENANCE_MANIFEST,
		"sha256":digest,
		"exists":exists,
		"bound":exists and digest.length() == 64,
		"source":"runtime_shipped_manifest_bytes",
	}

func _contract_terminal(outcome: String, build_shape: String) -> Dictionary:
	var weapon_id := "warden_lantern"
	if build_shape == "close_gravespade": weapon_id = "gravespade"
	elif build_shape == "orbiting_wisps": weapon_id = "wandering_wisps"
	var terminal := {
		"outcome":outcome,
		"route_kind":"ordinary",
		"diagnostic_jump_count":0,
		"ordered_wave_ids":EXPECTED_WAVES.duplicate(),
		"elapsed":480.0,
		"commit_count":1,
		"ordinary_route_eligible":outcome == "victory",
		"level":12,
		"defeated":140,
		"damage_dealt":2400,
		"damage_taken":48,
		"selected_upgrades":[],
		"weapons":{},
		"weapon_ranks":[{"weapon_id":weapon_id,"rank":5}],
		"build_shape":build_shape,
		"boss_transition_history":[{"event":"bellkeeper_phase_shifted","phase":2,"natural_transition":true}],
		"ledger_boss_events":[{"event":"bellkeeper_defeated","defeat_committed":true}],
	}
	terminal["truthful_result_fields"] = _truthful_result_fields(terminal)
	return terminal

func _truthful_result_fields(terminal: Dictionary) -> bool:
	return terminal.has_all(["elapsed","level","defeated","damage_dealt","damage_taken","selected_upgrades","outcome","commit_count"])

func _equipped_weapon_ranks(terminal: Dictionary) -> Array[Dictionary]:
	var ranks: Array[Dictionary] = []
	for weapon in (terminal.get("weapons", {}) as Dictionary).get("weapons", []):
		if bool(weapon.get("equipped", false)):
			ranks.append({"weapon_id":String(weapon.get("weapon_id", "")),"rank":int(weapon.get("rank", 0))})
	return ranks

func _classify_build_shape(ranks: Array[Dictionary]) -> String:
	var best_id := ""
	var best_rank := -1
	var tied := false
	for entry in ranks:
		var rank := int(entry.get("rank", 0))
		if rank > best_rank:
			best_rank = rank
			best_id = String(entry.get("weapon_id", ""))
			tied = false
		elif rank == best_rank:
			tied = true
	if tied:
		return "mixed"
	match best_id:
		"warden_lantern": return "focused_lantern"
		"gravespade": return "close_gravespade"
		"wandering_wisps": return "orbiting_wisps"
	return "unclassified"

func _milestone(event: String, elapsed: float, payload: Dictionary) -> Dictionary:
	return {"event":event,"elapsed":elapsed,"process_frame":Engine.get_process_frames(),"payload":payload.duplicate(true)}
