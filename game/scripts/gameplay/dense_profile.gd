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

static func contract() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"release_guard": "OS.has_feature(\"editor\")",
		"entrypoints": {
			"prepare": "validation_prepare_final_profile",
			"advance": "validation_advance_final_profile",
			"reset": "validation_reset_final_profile",
		},
		"window_seconds": WINDOW_SECONDS,
		"enemy_range": {"minimum": MIN_ENEMIES, "maximum": MAX_ENEMIES, "target": TARGET_ENEMIES},
		"metrics": [
			"timestamp_msec", "frame_ms", "fps", "active_enemies", "active_projectiles",
			"active_pickups", "active_effects", "active_lights", "active_audio_voices",
			"spawned_total", "despawned_total", "runtime_error_count",
		],
		"ordinary_balance_untouched": true,
	}

