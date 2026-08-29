class_name DenseWaveProfile
extends RefCounted

## Stable, development-only contract for the representative final-wave probe.
## RunController owns the live sampling lifecycle; this value object documents
## the entrypoint and metric names consumed by host recapture.
const CONTRACT_ID := "mournlight.release_convergence_dense_window.v1"
const MIN_ENEMIES := 25
const MAX_ENEMIES := 40
const TARGET_ENEMIES := 32
const WINDOW_SECONDS := 4.0
const SAMPLE_INTERVAL_SECONDS := 0.1
const SAMPLE_HISTORY_CAP := 128
const STEERING_BUCKET_COUNT := 2
const PRESENTATION_UPDATE_BUDGET_SECONDS := 0.1
const SECONDARY_COMPOSITOR_RESOLUTION_SCALE := 0.5
const SECONDARY_COMPOSITOR_REFRESH_SECONDS := 0.12
const NATIVE_STATUS := "qualified"
const SOFTWARE_STATUS := "rejected_software_renderer"
const UNKNOWN_STATUS := "pending_native_renderer"

static func contract() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"release_guard": "OS.has_feature(\"editor\")",
		"renderer_gate": "hardware_qualification_eligible == true",
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
			"steering_bucket_count": STEERING_BUCKET_COUNT,
			"presentation_refresh_seconds": PRESENTATION_UPDATE_BUDGET_SECONDS,
			"secondary_compositor_resolution_scale": SECONDARY_COMPOSITOR_RESOLUTION_SCALE,
			"secondary_compositor_refresh_seconds": SECONDARY_COMPOSITOR_REFRESH_SECONDS,
			"policy": "stable_actor_buckets_with_cached_separation_and_staggered_presentation",
		},
		"enemy_range": {"minimum": MIN_ENEMIES, "maximum": MAX_ENEMIES, "target": TARGET_ENEMIES},
		"metrics": [
			"timestamp_msec", "frame_ms", "physics_ms", "fps", "active_enemies", "active_projectiles",
			"active_pickups", "active_effects", "active_lights", "active_audio_voices",
			"spawned_total", "despawned_total", "runtime_error_count",
		],
		"receipts": ["requested", "resolved", "reset_isolation"],
		"ordinary_balance_untouched": true,
	}

static func renderer_status(classification: String, hardware_eligible: bool) -> String:
	# Renderer identity is an evidence gate, never a tuning override. Unknown
	# adapters remain explicitly pending until the host supplies native proof.
	if hardware_eligible and classification == "hardware":
		return NATIVE_STATUS
	if classification == "software":
		return SOFTWARE_STATUS
	return UNKNOWN_STATUS
