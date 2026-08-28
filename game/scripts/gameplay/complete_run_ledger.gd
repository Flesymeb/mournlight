class_name CompleteRunLedger
extends RefCounted

const EXPECTED_WAVES := ["first_toll", "crossing_shadows", "gravewind", "long_procession", "bellkeeper"]
const PROVENANCE_MANIFEST := "res://ASSET_PROVENANCE.json"
const PROVENANCE_SHA256 := "52bc131684c5d02a8541962e9a983fc7d39062a3db906a7465dc41af99b7babc"
const MAX_SESSION_ROWS := 10
const MAX_DIAGNOSTIC_EVENTS := 24

var current_run: Dictionary = {}
var completed_rows: Array[Dictionary] = []
var diagnostic_events: Array[Dictionary] = []
var credits_traversals: Array[Dictionary] = []
var session_generation := 0

func begin_run(run_serial: int, route_kind: String, started_from: String) -> void:
	_mark_prior_replay_if_applicable(run_serial, started_from)
	session_generation += 1
	current_run = {
		"session_generation":session_generation,
		"run_serial":run_serial,
		"route_kind":route_kind,
		"started_from":started_from,
		"milestones":[_milestone("title_play", 0.0, {"player_caused":true})],
		"wave_ids":[],
		"drafts":[],
		"boss_events":[],
		"diagnostic_jump_count":0,
		"terminal":{},
		"result_presented":false,
		"retry_observed":false,
		"title_return_observed":false,
		"replay_observed":false,
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
	truthful["diagnostic_jump_count"] = diagnostic_jumps
	truthful["ordinary_victory_eligible"] = _ordinary_victory_eligible(truthful)
	truthful["truthful_result_fields"] = _truthful_result_fields(truthful)
	current_run["terminal"] = truthful
	current_run["wave_ids"] = truthful["ordered_wave_ids"]
	(current_run["milestones"] as Array).append(_milestone("terminal_commit", float(terminal.get("elapsed", 0.0)), {"outcome":terminal.get("outcome", ""),"commit_count":terminal.get("commit_count",0)}))
	_append_completed_row()

func record_result_presented(run_serial: int, outcome: String) -> void:
	_update_row(run_serial, "result_presented", true)
	_update_row(run_serial, "result_outcome", outcome)

func record_exit(run_serial: int, exit_kind: String, elapsed: float) -> void:
	if exit_kind == "retry":
		_update_row(run_serial, "retry_observed", true)
	elif exit_kind == "title":
		_update_row(run_serial, "title_return_observed", true)
	if int(current_run.get("run_serial", -1)) == run_serial:
		current_run["%s_observed" % exit_kind] = true
		(current_run["milestones"] as Array).append(_milestone(exit_kind, elapsed, {"player_caused":true}))

func record_credits(run_serial: int, shell_mode: String) -> void:
	var receipt := {
		"run_serial":run_serial,
		"session_generation":session_generation,
		"shell_mode":shell_mode,
		"manifest_path":PROVENANCE_MANIFEST,
		"manifest_sha256":PROVENANCE_SHA256,
		"observed_process_frame":Engine.get_process_frames(),
		"substitutes_for_gameplay_completion":false,
	}
	credits_traversals.append(receipt)
	while credits_traversals.size() > 6:
		credits_traversals.pop_front()

func get_snapshot() -> Dictionary:
	var rows := completed_rows.duplicate(true)
	var shapes: Array[String] = []
	var failure_retry := false
	var victory_replay := false
	for row in rows:
		var terminal: Dictionary = row.get("terminal", {})
		var shape := String(terminal.get("build_shape", ""))
		if bool(terminal.get("ordinary_victory_eligible", false)) and shape in ["focused_lantern", "close_gravespade", "orbiting_wisps"] and shape not in shapes:
			shapes.append(shape)
		failure_retry = failure_retry or (String(terminal.get("outcome", "")) == "failure" and bool(row.get("result_presented", false)) and bool(row.get("retry_observed", false)))
		victory_replay = victory_replay or (String(terminal.get("outcome", "")) == "victory" and bool(terminal.get("ordinary_victory_eligible", false)) and bool(row.get("result_presented", false)) and bool(row.get("replay_observed", false)))
	var missing: Array[String] = []
	if not failure_retry: missing.append("ordinary_failure_result_retry")
	if not victory_replay: missing.append("ordinary_victory_result_replay")
	for required_shape in ["focused_lantern", "close_gravespade", "orbiting_wisps"]:
		if required_shape not in shapes: missing.append("ordinary_build_%s" % required_shape)
	if credits_traversals.is_empty(): missing.append("credits_and_notices")
	return {
		"identity":"mournlight.complete_run_session.v1",
		"session_generation":session_generation,
		"current_run":current_run.duplicate(true),
		"completed_rows":rows,
		"completed_row_count":rows.size(),
		"diagnostic_namespace":diagnostic_events.duplicate(true),
		"diagnostic_events_rejected_from_ordinary":true,
		"credits_traversals":credits_traversals.duplicate(true),
		"provenance_manifest":{"path":PROVENANCE_MANIFEST,"sha256":PROVENANCE_SHA256},
		"matrix":{"failure_result_retry":failure_retry,"victory_result_replay":victory_replay,"ordinary_build_shapes":shapes,"credits_traversed":not credits_traversals.is_empty(),"missing_rows":missing,"complete":missing.is_empty()},
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

func _mark_prior_replay_if_applicable(next_run_serial: int, started_from: String) -> void:
	if started_from not in ["title_play", "retry"]:
		return
	for index in range(completed_rows.size() - 1, -1, -1):
		var terminal: Dictionary = completed_rows[index].get("terminal", {})
		if String(terminal.get("outcome", "")) == "victory" and int(completed_rows[index].get("run_serial", -1)) < next_run_serial:
			completed_rows[index]["replay_observed"] = true
			completed_rows[index]["replay_run_serial"] = next_run_serial
			return

func _accepts_ordinary(route_kind: String, snapshot: Dictionary) -> bool:
	return route_kind == "ordinary" and int(snapshot.get("diagnostic_jump_count", 0)) == 0

func _record_diagnostic(event: String, elapsed: float, payload: Dictionary) -> void:
	diagnostic_events.append({"event":event,"elapsed":elapsed,"payload":payload.duplicate(true),"ordinary_row_population":false})
	while diagnostic_events.size() > MAX_DIAGNOSTIC_EVENTS:
		diagnostic_events.pop_front()

func _ordinary_victory_eligible(terminal: Dictionary) -> bool:
	return (
		String(terminal.get("outcome", "")) == "victory"
		and String(terminal.get("route_kind", "")) == "ordinary"
		and int(terminal.get("diagnostic_jump_count", -1)) == 0
		and Array(terminal.get("ordered_wave_ids", [])) == EXPECTED_WAVES
		and float(terminal.get("elapsed", 0.0)) >= 420.0
		and float(terminal.get("elapsed", 0.0)) <= 600.0
		and int(terminal.get("commit_count", 0)) == 1
	)

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
