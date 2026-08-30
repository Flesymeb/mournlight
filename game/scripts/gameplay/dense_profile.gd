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
const STEERING_BUCKET_COUNT := 3
const NEIGHBOR_QUERY_BUCKET_COUNT := 3
const VITALITY_BUCKET_COUNT := 4
const LIGHT_BUCKET_COUNT := 8
const OPTIONAL_EFFECT_BUCKET_COUNT := 5
const PRESENTATION_UPDATE_BUDGET_SECONDS := 0.1
const SECONDARY_COMPOSITOR_RESOLUTION_SCALE := 0.5
const SECONDARY_COMPOSITOR_REFRESH_SECONDS := 0.12
const NATIVE_STATUS := "qualified"
const SOFTWARE_STATUS := "rejected_software_renderer"
const UNKNOWN_STATUS := "pending_native_renderer"
const QUALIFICATION_MODE := "native_renderer_three_cycle"

static func contract() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"contract_version": CONTRACT_VERSION,
		"sampling_renderer_independent": true,
		"release_guard": "OS.has_feature(\"editor\")",
		"default_enabled": false,
		"editor_opt_in": true,
		"release_presentation_impact": "none_when_disabled",
		"renderer_gate": "hardware_qualification_eligible == true",
		"qualification_mode": QUALIFICATION_MODE,
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
		"sample_history_cap": SAMPLE_HISTORY_CAP,
		"dense_update_budget": {
			"scheduler_version": "owner_snapshot_token_buckets.v1",
			"shared_bucket_policy": "stable_id_hash_plus_spawn_generation",
			"buckets": work_buckets(),
			"steering_bucket_count": STEERING_BUCKET_COUNT,
			"presentation_refresh_seconds": PRESENTATION_UPDATE_BUDGET_SECONDS,
			"secondary_compositor_resolution_scale": SECONDARY_COMPOSITOR_RESOLUTION_SCALE,
			"secondary_compositor_refresh_seconds": SECONDARY_COMPOSITOR_REFRESH_SECONDS,
			"policy": "stable_actor_buckets_with_cached_separation_and_staggered_presentation",
		},
		"enemy_range": {"minimum": MIN_ENEMIES, "maximum": MAX_ENEMIES, "target": TARGET_ENEMIES},
		"metrics": [
			"timestamp_msec", "frame_ms", "physics_ms", "fps", "sample_count", "physics_sample_count", "sample_availability", "active_enemies", "active_projectiles",
			"active_pickups", "active_effects", "active_lights", "active_audio_voices",
			"spawned_total", "despawned_total", "runtime_error_count",
		],
		"receipts": ["requested", "resolved", "reset_isolation"],
		"cycle_protocol": ["prepare", "advance", "reset"],
		"cycle_aggregation": {
			"identity":"mournlight.native_dense_three_cycle.v1",
			"required_complete_cycles":3,
			"aggregation_owner":"RunController",
			"software_sessions":"retained_as_rejected_evidence",
		},
		"ordinary_balance_untouched": true,
		"sample_availability_policy": "record_nonzero_samples_when_frames_run; renderer_gate_does_not_suppress_measurement",
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

static func qualification_contract() -> Dictionary:
	return {
		"mode": QUALIFICATION_MODE,
		"renderer_policy":"native_hardware_only",
		"software_policy":"reject_and_surface_status",
		"required_cycles":3,
		"target_resolution":Vector2i(1920, 1080),
		"target_density":TARGET_ENEMIES,
		"reset_isolation_required":true,
	}
