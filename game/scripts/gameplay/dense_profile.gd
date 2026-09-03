class_name DenseWaveProfile
extends RefCounted

## Stable, development-only contract for the representative final-wave probe.
## RunController owns the live sampling lifecycle; this value object documents
## the entrypoint and metric names consumed by host recapture.
const CONTRACT_ID := "mournlight.release_convergence_dense_window.v1"
const CONTRACT_VERSION := 1
const MIN_ENEMIES := 25
const MAX_ENEMIES := 40
const TARGET_ENEMIES := 32
const WINDOW_SECONDS := 4.0
const SAMPLE_INTERVAL_SECONDS := 0.1
const SAMPLE_HISTORY_CAP := 128
## Receipt history is bounded independently from per-window samples so serial
## native retries cannot grow the controller indefinitely between resets.
const CYCLE_RECEIPT_HISTORY_CAP := 12
## Telemetry remains sampled every 100 ms; expensive cross-system coverage
## inspection is amortised across this many samples. Coverage is cumulative.
const SYSTEM_OBSERVATION_STRIDE := 2
const STEERING_BUCKET_COUNT := 3
const NEIGHBOR_QUERY_BUCKET_COUNT := 3
const VITALITY_BUCKET_COUNT := 4
const LIGHT_BUCKET_COUNT := 8
const OPTIONAL_EFFECT_BUCKET_COUNT := 5
const PRIORITY_THREAT_RADIUS := 8.0
const TARGET_CANDIDATE_CAP := 40
const PRESENTATION_UPDATE_BUDGET_SECONDS := 0.1
const SECONDARY_COMPOSITOR_RESOLUTION_SCALE := 0.5
const SECONDARY_COMPOSITOR_REFRESH_SECONDS := 0.12
const NATIVE_STATUS := "qualified"
const SOFTWARE_STATUS := "rejected_software_renderer"
## Stable reason token carried by post-sampling receipts. Keep this aligned
## with the status so host handoff tooling can match either field directly.
const SOFTWARE_REJECTION_REASON := SOFTWARE_STATUS
const UNKNOWN_STATUS := "pending_native_renderer"
const QUALIFICATION_MODE := "native_renderer_three_cycle"
const REQUIRED_QUALIFICATION_CYCLES := 3
const MAX_QUALIFICATION_CYCLES := 3
const PREFLIGHT_ID := "mournlight.native_dense_preflight.v1"
## Qualification controls are intentionally editor-only.  Keeping the guard in
## the profile contract gives host tooling one authoritative predicate instead
## of duplicating release checks across RunController entry points.
const RELEASE_GUARD := "OS.has_feature(\"editor\") and not OS.has_feature(\"release\")"
## Stable provenance marker.  Keep this literal immutable so host recapture can
## reject receipts produced by a different contract without trusting mutable
## runtime state.
const CONTRACT_SIGNATURE := "mournlight.release_convergence_dense_window.v1|renderer_gate_after_sampling|native_1920x1080_three_cycle"

static func contract() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"contract_version": CONTRACT_VERSION,
		"contract_signature": CONTRACT_SIGNATURE,
		"sampling_renderer_independent": true,
		"release_guard": RELEASE_GUARD,
		"default_enabled": false,
		"editor_opt_in": true,
		"release_presentation_impact": "none_when_disabled",
		"renderer_gate": "hardware_qualification_eligible == true",
		"hardware_eligibility_field": "hardware_eligibility",
		"qualification_mode": QUALIFICATION_MODE,
		"cycle_budget": {"required": REQUIRED_QUALIFICATION_CYCLES, "maximum": MAX_QUALIFICATION_CYCLES, "bounded": true},
		"qualification_statuses": {
			"hardware": NATIVE_STATUS,
			"software": SOFTWARE_STATUS,
			"unknown": UNKNOWN_STATUS,
		},
		"entrypoints": {
			"prepare": "tester_dense_prepare",
			"advance": "tester_dense_advance",
			"reset": "tester_dense_reset",
			"legacy_aliases": ["validation_prepare_final_profile", "validation_advance_final_profile", "validation_reset_final_profile"],
		},
		"window_seconds": WINDOW_SECONDS,
		"sample_interval_seconds": SAMPLE_INTERVAL_SECONDS,
		"system_observation_stride": SYSTEM_OBSERVATION_STRIDE,
		"sample_history_cap": SAMPLE_HISTORY_CAP,
		"cycle_receipt_history_cap": CYCLE_RECEIPT_HISTORY_CAP,
		"dense_update_budget": {
			"scheduler_version": "owner_snapshot_token_buckets.v1",
			"quality_wrapper": {"revision":"dense_quality_wrapper_v1", "activation":"tester_dense_prepare", "restoration":"tester_dense_reset_or_run_teardown", "controls":["directional_shadows","landmark_shadows","fullscreen_glow"]},
			"shared_bucket_policy": "stable_id_hash_plus_spawn_generation",
			"buckets": work_buckets(),
			"steering_bucket_count": STEERING_BUCKET_COUNT,
			"presentation_refresh_seconds": PRESENTATION_UPDATE_BUDGET_SECONDS,
			"secondary_compositor_resolution_scale": SECONDARY_COMPOSITOR_RESOLUTION_SCALE,
			"secondary_compositor_refresh_seconds": SECONDARY_COMPOSITOR_REFRESH_SECONDS,
			"policy": "stable_actor_buckets_with_cached_separation_and_staggered_presentation",
			"priority_policy": "telegraph_damage_recent_hurt_and_nearby_threats_update_first",
			"priority_threat_radius": PRIORITY_THREAT_RADIUS,
			"target_candidate_cap": TARGET_CANDIDATE_CAP,
		},
		"enemy_range": {"minimum": MIN_ENEMIES, "maximum": MAX_ENEMIES, "target": TARGET_ENEMIES},
		"metrics": [
			"timestamp_msec", "frame_ms", "physics_ms", "render_ms", "draw_calls", "allocation_bytes", "orphan_nodes", "fps", "sample_count", "physics_sample_count", "sample_availability", "active_enemies", "active_projectiles",
			"active_pickups", "active_effects", "active_lights", "active_audio_voices", "pooled_enemies", "pooled_pickups",
			"spawned_total", "despawned_total", "runtime_error_count", "subsystem_samples", "sample_distributions", "high_water_marks", "lifecycle_deltas",
		],
		"telemetry": {"sample_history_cap": SAMPLE_HISTORY_CAP, "per_sample_metrics": true, "runtime_errors_source": "godot_runtime_log"},
		"receipts": ["requested", "resolved", "reset_isolation", "setup_generation", "advance_generation", "cycle_id", "phase"],
		"phase_receipts": ["prepare", "advance_start", "advance_complete", "reset", "reset_next_frame"],
		"cycle_identity": ["identity", "cycle_index", "cycle_id", "run_serial", "setup_generation", "advance_generation"],
		"target_viewport": {"width": 1920, "height": 1080},
		"target_density": TARGET_ENEMIES,
		"native_recapture_prerequisites": {
			"renderer_classification": "hardware",
			"hardware_qualification_eligible": true,
			"viewport": {"width": 1920, "height": 1080},
			"serial_protocol": ["tester_dense_prepare", "tester_dense_advance", "tester_dense_reset"],
			"required_complete_cycles": 3,
			"reset_isolation": "next_frame_input_context_active_and_zero_live_actors",
			"software_evidence_policy": "retain_as_rejected_software_renderer; do_not_qualify",
		},
		"release_export_available": false,
		"cycle_protocol": ["prepare", "advance", "reset"],
		"idempotency": {
			"prepare": "reject_while_prepared_or_sampling_until_reset",
			"advance": "exactly_once_per_prepare_until_reset",
			"reset": "repeat_returns_existing_isolation_receipt",
			"delayed_callbacks": "must_not_replace_cycle_identity_or_run_serial",
			"receipt_history": "capped_to_cycle_receipt_history_cap",
		},
		"host_sequence": "tester_dense_prepare -> tester_dense_advance -> tester_dense_reset (serial, once per cycle)",
		"self_audit_id": "mournlight.dense_receipt_self_audit.v1",
		"cycle_aggregation": {
			"identity":"mournlight.native_dense_three_cycle.v1",
			"required_complete_cycles":3,
			"aggregation_owner":"RunController",
			"software_sessions":"retained_as_rejected_evidence",
		},
		# This is a transport handoff, not a qualification verdict. Runtime/Tester
		# can use one stable payload to recapture the exact three-cycle protocol on
		# native hardware while preserving this candidate's software evidence.
		"host_handoff": host_handoff_contract(),
		"ordinary_balance_untouched": true,
		"sample_availability_policy": "record_nonzero_samples_when_frames_run; renderer_gate_does_not_suppress_measurement",
		"preflight": {
			"id": PREFLIGHT_ID,
			"records_before_qualification": ["renderer", "hardware_eligibility", "frame_execution", "sample_availability", "cycle_provenance", "reset_isolation"],
			"renderer_gate_order": "classify_before_sampling_gate_after_sampling",
			"renderer_gate_deferred_until_sampling_complete": true,
			"native_renderer_required_for_qualification": true,
		},
}

static func host_handoff_contract() -> Dictionary:
	return {
		"id":"mournlight.native_dense_host_handoff.v1",
		"owner":"GameLoop Runtime + Tester",
		"status":"pending_native_recapture",
		"qualification_owner":"Tester",
		"native_capture_required":true,
		"renderer_gate":"hardware_qualification_eligible == true",
		"hardware_eligibility_field":"hardware_eligibility",
		"target_viewport":{"width":1920,"height":1080},
		"required_cycles":REQUIRED_QUALIFICATION_CYCLES,
		"serial_protocol":["tester_dense_prepare","tester_dense_advance","tester_dense_reset"],
		"cycle_identity":["cycle_id","cycle_index","run_serial","setup_generation","advance_generation"],
		"required_receipts":["renderer","preflight","sample_distributions","lifecycle_deltas","reset_isolation","next_frame_input_context"],
		"software_evidence_policy":"retain_as_rejected_software_renderer",
		"release_export_available":false,
	}

static func tester_guard() -> bool:
	return OS.has_feature("editor") and not OS.has_feature("release")

static func preflight(renderer: Dictionary, viewport: Dictionary, process_frame_start: int, process_frame_end: int, frame_sample_count: int, physics_sample_count: int, phase: String, cycle_provenance: Dictionary = {}, reset_isolation: Dictionary = {}) -> Dictionary:
	var frames_delta := maxi(0, process_frame_end - process_frame_start)
	var frames_ran := frames_delta > 0
	var frame_samples_nonzero := frame_sample_count > 0
	var physics_samples_nonzero := physics_sample_count > 0
	var classification := String(renderer.get("classification", "unknown"))
	var hardware_eligible := bool(renderer.get("hardware_qualification_eligible", false))
	return {
		"id": PREFLIGHT_ID,
		"phase": phase,
		"renderer": renderer.duplicate(true),
		"renderer_classification": classification,
		"hardware_qualification_eligible": hardware_eligible,
		"renderer_gate_status": renderer_status(classification, hardware_eligible),
		"renderer_rejection_reason": SOFTWARE_REJECTION_REASON if classification == "software" else ("native_identity_pending" if classification == "unknown" else ""),
		"viewport": viewport.duplicate(true),
		"frame_execution": {
			"process_frame_start": process_frame_start,
			"process_frame_end": process_frame_end,
			"process_frame_delta": frames_delta,
			"frames_ran": frames_ran,
		},
		"sample_availability": {
			"frame_sample_count": frame_sample_count,
			"physics_sample_count": physics_sample_count,
			"frame_samples_nonzero": frame_samples_nonzero,
			"physics_samples_nonzero": physics_samples_nonzero,
			"samples_expected": frames_ran,
			"samples_available": frame_samples_nonzero and physics_samples_nonzero,
			"qualification_ready": frames_ran and frame_samples_nonzero and physics_samples_nonzero,
		},
		"renderer_gate_order": "classify_before_sampling_gate_after_sampling",
		"renderer_gate_deferred_until_sampling_complete": true,
		"native_renderer_required_for_qualification": true,
		"cycle_provenance": cycle_provenance.duplicate(true),
		"reset_isolation": reset_isolation.duplicate(true),
		"qualification_gate_deferred": true,
	}

static func work_buckets() -> Dictionary:
	# Every non-authoritative dense subsystem gets a deterministic token lane.
	# The lane is derived from stable actor ownership, so reset/replay produces
	# the same work distribution without scanning the scene tree on sampled frames.
	return {
		"neighbor_queries": {"bucket_count": NEIGHBOR_QUERY_BUCKET_COUNT, "cadence_frames": 3, "authoritative": false},
		"steering": {"bucket_count": STEERING_BUCKET_COUNT, "cadence_frames": 3, "authoritative": false},
		"vitality": {"bucket_count": VITALITY_BUCKET_COUNT, "cadence_seconds": 0.05, "authoritative": false},
		"presentation": {"bucket_count": STEERING_BUCKET_COUNT, "cadence_seconds": PRESENTATION_UPDATE_BUDGET_SECONDS, "authoritative": false},
		"lights": {"bucket_count": LIGHT_BUCKET_COUNT, "cadence_seconds": 0.1, "authoritative": false},
		"optional_effects": {"bucket_count": OPTIONAL_EFFECT_BUCKET_COUNT, "cadence_seconds": 0.12, "authoritative": false},
		"priority_threats": {"bucket_count": 1, "cadence_seconds": 0.0, "authoritative": false, "radius": PRIORITY_THREAT_RADIUS, "states": ["waiting_admission", "telegraph", "damage", "recent_hurt"]},
		"authoritative_events": {"bucket_count": 1, "cadence_seconds": 0.0, "authoritative": true, "events": ["telegraph", "accepted_hit", "damage", "death", "drop", "pool_retirement"]},
	}

static func bucket_for(stable_id: StringName, generation: int, bucket_count: int) -> int:
	return posmod(String(stable_id).hash() + generation, maxi(1, bucket_count))

static func renderer_status(classification: String, hardware_eligible: bool) -> String:
	# Renderer identity is an evidence gate, never a tuning override. Unknown
	# adapters remain explicitly pending until the host supplies native proof.
	if hardware_eligible and classification == "hardware":
		return NATIVE_STATUS
	if classification == "software":
		return SOFTWARE_STATUS
	return UNKNOWN_STATUS

## Explicit renderer gate shared by the live collector and host receipts.
## Sampling remains enabled on every adapter, while only a complete native
## identity can advance qualification. Software markers therefore remain
## visible as rejected evidence instead of being converted into a pass.
static func renderer_guard(renderer: Dictionary) -> Dictionary:
	var classification := String(renderer.get("classification", "unknown"))
	var hardware_eligible := bool(renderer.get("hardware_qualification_eligible", false))
	var status := renderer_status(classification, hardware_eligible)
	return {
		"classification":classification,
		"hardware_qualification_eligible":hardware_eligible,
		# Stable short alias for host receipts. Keep the qualification-specific
		# field above as the authoritative gate while exposing the plain-language
		# eligibility predicate used by release tooling.
		"hardware_eligibility":hardware_eligible,
		"status":status,
		"native_qualification_allowed":status == NATIVE_STATUS,
		"sampling_allowed":true,
		"software_rejected":status == SOFTWARE_STATUS,
		"reason":"native_identity_verified" if status == NATIVE_STATUS else ("software_renderer_detected" if status == SOFTWARE_STATUS else "native_identity_pending"),
		"renderer_rejection_reason":SOFTWARE_REJECTION_REASON if status == SOFTWARE_STATUS else ("native_identity_pending" if status == UNKNOWN_STATUS else ""),
	}

static func qualification_contract() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"contract_version": CONTRACT_VERSION,
		"contract_signature": CONTRACT_SIGNATURE,
		"mode": QUALIFICATION_MODE,
		"renderer_policy":"native_hardware_only",
		"software_policy":"reject_and_surface_status",
		"required_cycles":REQUIRED_QUALIFICATION_CYCLES,
		"target_resolution":Vector2i(1920, 1080),
		"target_viewport":{"width":1920,"height":1080},
		"target_density":TARGET_ENEMIES,
		"native_recapture_prerequisites": {
			"renderer_classification": "hardware",
			"hardware_qualification_eligible": true,
			"viewport": {"width": 1920, "height": 1080},
			"serial_protocol": ["tester_dense_prepare", "tester_dense_advance", "tester_dense_reset"],
			"required_complete_cycles": 3,
			"reset_isolation": "next_frame_input_context_active_and_zero_live_actors",
			"software_evidence_policy": "retain_as_rejected_software_renderer; do_not_qualify",
		},
		"reset_isolation_required":true,
		"host_handoff":host_handoff_contract(),
	}

## Deterministic, side-effect-free contract fixtures used by the release guard.
## These checks validate the receipt protocol itself; they never fabricate
## performance samples or alter the live profile lifecycle.
static func self_audit() -> Dictionary:
	var valid := _audit_cycle([
		{"phase":"prepare", "cycle_id":"audit.1", "setup_generation":1, "advance_generation":0, "requested":32, "resolved":32},
		{"phase":"advance_complete", "cycle_id":"audit.1", "setup_generation":1, "advance_generation":1, "requested":32, "resolved":32, "sample_count":8, "physics_sample_count":8, "sample_distributions":{"frame_ms":{"sample_count":8}, "render_ms":{"sample_count":8}}, "lifecycle_deltas":{}, "reset_isolation":false},
		{"phase":"reset_next_frame", "cycle_id":"audit.1", "setup_generation":2, "advance_generation":1, "requested":32, "resolved":0, "reset_isolation":true}
	])
	var duplicate := _audit_cycle([
		{"phase":"prepare", "cycle_id":"audit.dup", "setup_generation":1, "advance_generation":0, "requested":32, "resolved":32},
		{"phase":"prepare", "cycle_id":"audit.dup", "setup_generation":1, "advance_generation":0, "requested":32, "resolved":32}
	])
	var incomplete := _audit_cycle([
		{"phase":"prepare", "cycle_id":"audit.incomplete", "setup_generation":1, "advance_generation":0, "requested":32, "resolved":32},
		{"phase":"advance_start", "cycle_id":"audit.incomplete", "setup_generation":1, "advance_generation":1, "requested":32, "resolved":32}
	])
	var timeout := _audit_cycle([
		{"phase":"prepare", "cycle_id":"audit.timeout", "setup_generation":1, "advance_generation":0, "requested":32, "resolved":32},
		{"phase":"advance_timeout", "cycle_id":"audit.timeout", "setup_generation":1, "advance_generation":1, "requested":32, "resolved":32, "timeout":true}
	])
	var reset_failure := _audit_cycle([
		{"phase":"prepare", "cycle_id":"audit.reset_failure", "setup_generation":1, "advance_generation":0, "requested":32, "resolved":32},
		{"phase":"advance_complete", "cycle_id":"audit.reset_failure", "setup_generation":1, "advance_generation":1, "requested":32, "resolved":32, "sample_count":8, "physics_sample_count":8, "sample_distributions":{"frame_ms":{"sample_count":8}, "render_ms":{"sample_count":8}}, "lifecycle_deltas":{}, "reset_isolation":false},
		{"phase":"reset_next_frame", "cycle_id":"audit.reset_failure", "setup_generation":2, "advance_generation":1, "requested":32, "resolved":0, "reset_isolation":false}
	])
	var required_metrics: Array[String] = []
	for metric in contract().get("metrics", []):
		required_metrics.append(String(metric))
	var native_guard := renderer_guard({"classification":"hardware", "hardware_qualification_eligible":true})
	var software_guard := renderer_guard({"classification":"software", "hardware_qualification_eligible":false})
	var unknown_guard := renderer_guard({"classification":"unknown", "hardware_qualification_eligible":false})
	var checks := {
		"valid_cycle_complete":bool(valid.get("complete", false)),
		"duplicate_cycle_rejected":String(duplicate.get("status", "")) == "rejected" and duplicate.get("reasons", []).has("duplicate_phase"),
		"incomplete_cycle_pending":String(incomplete.get("status", "")) == "pending" and incomplete.get("reasons", []).has("incomplete_phase_sequence"),
		"timeout_bounded_pending":String(timeout.get("status", "")) == "pending" and timeout.get("reasons", []).has("timeout"),
		"reset_isolation_failure_rejected":String(reset_failure.get("status", "")) == "rejected" and reset_failure.get("reasons", []).has("reset_isolation_false"),
		"required_metric_names_present":required_metrics.size() >= 10 and required_metrics.has("frame_ms") and required_metrics.has("physics_ms") and required_metrics.has("render_ms") and required_metrics.has("allocation_bytes") and required_metrics.has("subsystem_samples") and required_metrics.has("lifecycle_deltas") and required_metrics.has("runtime_error_count"),
		"renderer_guard_native_pass":bool(native_guard.get("native_qualification_allowed", false)) and native_guard.get("status", "") == NATIVE_STATUS,
		"renderer_guard_software_rejected":bool(software_guard.get("software_rejected", false)) and not bool(software_guard.get("native_qualification_allowed", true)) and software_guard.get("renderer_rejection_reason", "") == SOFTWARE_REJECTION_REASON,
		"renderer_guard_unknown_pending":unknown_guard.get("status", "") == UNKNOWN_STATUS and not bool(unknown_guard.get("native_qualification_allowed", true)),
	}
	var all_pass := true
	for value in checks.values():
		all_pass = all_pass and bool(value)
	return {
		"identity":"mournlight.dense_receipt_self_audit.v1",
		"release_guard":RELEASE_GUARD,
		"contract_id":CONTRACT_ID,
		"contract_version":CONTRACT_VERSION,
		"contract_signature":CONTRACT_SIGNATURE,
		"enemy_range":{"minimum":MIN_ENEMIES,"maximum":MAX_ENEMIES,"target":TARGET_ENEMIES},
		"target_viewport":{"width":1920,"height":1080},
		"required_metrics":required_metrics,
		"required_cycles":REQUIRED_QUALIFICATION_CYCLES,
		"cycle_protocol":["prepare","advance","reset"],
		"bounded_history_cap":SAMPLE_HISTORY_CAP,
		"fixtures":{"valid":valid,"duplicate":duplicate,"incomplete":incomplete,"timeout":timeout,"reset_isolation_failure":reset_failure},
		"checks":checks,
		"renderer_guard": {"native":native_guard, "software":software_guard, "unknown":unknown_guard},
		"all_checks_pass":all_pass,
	}

static func _audit_cycle(records: Array) -> Dictionary:
	var phases := ["prepare", "advance_complete", "reset_next_frame"]
	var reasons: Array[String] = []
	var seen_phases: Dictionary = {}
	var cycle_id := ""
	for value in records:
		if not value is Dictionary:
			reasons.append("malformed_receipt")
			continue
		var receipt: Dictionary = value
		var phase := String(receipt.get("phase", ""))
		if not cycle_id.is_empty() and String(receipt.get("cycle_id", "")) != cycle_id:
			reasons.append("cycle_id_mismatch")
		cycle_id = String(receipt.get("cycle_id", cycle_id))
		if seen_phases.has(phase):
			reasons.append("duplicate_phase")
		seen_phases[phase] = true
		if phase not in phases and phase != "advance_start":
			reasons.append("unknown_phase")
		if int(receipt.get("setup_generation", 0)) <= 0:
			reasons.append("setup_generation_missing")
		if phase in ["advance_start", "advance_complete", "advance_timeout"] and int(receipt.get("advance_generation", 0)) <= 0:
			reasons.append("advance_generation_missing")
		if bool(receipt.get("timeout", false)) or phase == "advance_timeout":
			reasons.append("timeout")
		if phase == "reset_next_frame" and not bool(receipt.get("reset_isolation", false)):
			reasons.append("reset_isolation_false")
	var has_complete_sample := seen_phases.has("advance_complete")
	var has_reset := seen_phases.has("reset_next_frame")
	if not phases.all(func(expected: String) -> bool: return seen_phases.has(expected)):
		reasons.append("incomplete_phase_sequence")
	if has_complete_sample:
		var sample: Dictionary = records[1] if records.size() > 1 and records[1] is Dictionary else {}
		if int(sample.get("sample_count", 0)) <= 0 or int(sample.get("physics_sample_count", 0)) <= 0:
			reasons.append("nonzero_samples_required")
	var status := "complete" if reasons.is_empty() and has_complete_sample and has_reset else ("rejected" if reasons.has("duplicate_phase") or reasons.has("reset_isolation_false") or reasons.has("malformed_receipt") else "pending")
	return {"status":status,"complete":status == "complete","cycle_id":cycle_id,"phases":seen_phases.keys(),"reasons":reasons,"bounded":records.size() <= 4}

## Normalize the bounded per-frame history into host-auditable distributions.
## Raw samples remain available; this summary keeps collector logic consistent.
static func sample_distribution(samples: Array) -> Dictionary:
	var keys := ["frame_ms", "physics_ms", "render_ms", "draw_calls", "allocation_bytes", "orphan_nodes", "active_enemies", "active_projectiles", "active_pickups", "active_effects", "active_lights", "active_audio_voices", "pooled_enemies", "pooled_pickups"]
	var distributions: Dictionary = {}
	var high_water_marks: Dictionary = {}
	for key_value in keys:
		var key := String(key_value)
		var values: Array[float] = []
		for sample_value in samples:
			var sample: Dictionary = sample_value
			values.append(float(sample.get(key, 0.0)))
		values.sort()
		var maximum: float = float(values.back()) if not values.is_empty() else 0.0
		distributions[key] = {
			"p50": _percentile(values, 0.50),
			"p95": _percentile(values, 0.95),
			"p99": _percentile(values, 0.99),
			"maximum": maximum,
			"sample_count": values.size(),
		}
		if key.begins_with("active_") or key.begins_with("pooled_"):
			high_water_marks[key] = maximum
	return {"sample_count":samples.size(),"distributions":distributions,"high_water_marks":high_water_marks,"bounded":true}

static func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(ceil((sorted.size() - 1) * fraction)), 0, sorted.size() - 1)]
