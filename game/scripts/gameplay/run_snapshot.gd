class_name RunSnapshot
extends RefCounted

const DenseWaveProfileClass := preload("res://scripts/gameplay/dense_profile.gd")

static func make(controller: Node, world: Node, warden: Node, health: Node, spawner: Node, inventory: Node) -> Dictionary:
	var health_current := float(health.current_health) if health else 0.0
	var health_maximum := float(health.maximum_health) if health else 0.0
	var wave_snapshot: Dictionary = controller.wave_director.get_snapshot()
	var wave_definition: Dictionary = wave_snapshot.get("definition", {})
	var ledger_snapshot: Dictionary = controller.complete_run_ledger.get_snapshot() if controller.complete_run_ledger else {}
	var ledger_matrix: Dictionary = ledger_snapshot.get("matrix", {})
	var ledger_current: Dictionary = ledger_snapshot.get("current_run", {})
	var terminal: Dictionary = controller.terminal_snapshot if controller.terminal_snapshot is Dictionary else {}
	var arena_camera := world.get_node_or_null("ArenaCamera") if world else null
	var cemetery_contract := world.get_node_or_null("CemeteryGarden") if world else null
	var camera_visibility: Dictionary = arena_camera._mcp_state() if arena_camera and arena_camera.has_method("_mcp_state") else {}
	var camera_zoom: Dictionary = (camera_visibility.get("zoom", {}) as Dictionary).duplicate(true)
	return {
		"serial": int(controller.run_serial),
		"state": String(controller.run_state),
		"elapsed": float(controller.run_elapsed),
		"health": health_current,
		"health_maximum": health_maximum,
		"experience": int(controller.experience),
		"experience_threshold": int(controller.experience_threshold),
		"pending_levelup_transactions": int(controller._pending_levelup_transactions),
		"level": int(controller.level),
		"defeated": int(controller.defeated_enemies),
		"damage_taken": int(controller.damage_taken),
		"encounter": spawner.get_snapshot() if spawner else {},
		"weapons": inventory.get_snapshot() if inventory else {},
		"dash_phase": String(warden.dash_phase) if warden else "ready",
		"dash_remaining": float(warden.dash_cooldown_remaining) if warden else 0.0,
		"dash_duration": float(warden.cooldown_duration) if warden else 1.0,
		"pickup_collection_radius":float(warden.pickup_collection_radius) if warden else 1.75,
		"experience_yield_multiplier":float(warden.experience_yield_multiplier) if warden else 1.0,
		"wave": int(wave_snapshot.get("wave",1)),
		"wave_count": int(wave_snapshot.get("wave_count",5)),
		"wave_id": String(wave_definition.get("id","warmup")),
		"wave_title": String(wave_snapshot.get("title","WARMUP")),
		"wave_elapsed": float(wave_snapshot.get("wave_elapsed",0.0)),
		"wave_duration": float(wave_snapshot.get("wave_duration",0.0)),
		"wave_definition": wave_definition.duplicate(true),
		"ordinary_route_wave_ids":(wave_snapshot.get("ordinary_route_wave_ids", []) as Array).duplicate(),
		"ordinary_route_complete":bool(wave_snapshot.get("ordinary_route_complete", false)),
		"ordinary_route_eligible":String(controller.run_route_kind) == "ordinary" and bool(wave_snapshot.get("ordinary_route_eligible", false)),
		"route_contract":controller.wave_director.get_route_contract_receipt() if controller.wave_director.has_method("get_route_contract_receipt") else {},
		"diagnostic_jump_count":int(wave_snapshot.get("diagnostic_jump_count", 0)),
		"run_route_kind":String(controller.run_route_kind),
		"boss_active": bool(controller.boss_snapshot.get("active",false)),
		"boss_health": float(controller.boss_snapshot.get("health",0.0)),
		"boss_health_maximum": float(controller.boss_snapshot.get("health_maximum",0.0)),
		"boss_phase": int(controller.boss_snapshot.get("phase",1)),
		"boss_state": String(controller.boss_snapshot.get("state","inactive")),
		"boss_vulnerable": bool(controller.boss_snapshot.get("vulnerable",false)),
		"outcome": String(controller.outcome),
		"completion_reason": String(terminal.get("completion_reason", "")),
		"terminal_commit_count": int(controller.terminal_commit_count),
		"reset_generation": int((controller.teardown_receipt as Dictionary).get("completion_generation", 0)),
		"replay_status": {
			"observed": bool(ledger_current.get("replay_observed", false)),
			"observed_count": int(ledger_current.get("replay_observed_count", 0)),
			"victory_result_replay": bool(ledger_matrix.get("victory_result_replay", false)),
		},
		"build_shape_qualification": {
			"shape": String(terminal.get("build_shape", "unclassified")),
			"ordinary_build_eligible": bool(terminal.get("ordinary_build_eligible", false)),
			"ordinary_route_eligible": bool(terminal.get("ordinary_route_eligible", false)),
		},
		"damage_dealt": int(controller.damage_dealt),
		"selected_upgrades": controller.selected_upgrades.duplicate(true),
		"first_run_guidance":controller._first_run_guidance_snapshot(),
		"reward_feedback":controller._reward_feedback_snapshot(),
		"warden_animation": warden.animation_binding.get_snapshot() if warden and warden.animation_binding else {},
		"warden_movement": warden.get_movement_snapshot() if warden else {},
		"camera_visibility": camera_visibility,
		# Promote the bounded lens contract to the top-level run receipt so
		# Tester/runtime probes can verify min/default/max and modal isolation
		# without depending on a deep/truncated camera payload.
		"camera_zoom": camera_zoom,
		"arena_collision": cemetery_contract._mcp_state() if cemetery_contract and cemetery_contract.has_method("_mcp_state") else {},
		"terminal_reset_invariants": controller._terminal_reset_invariants("snapshot"),
		"upgrade_draft": controller.draft_controller.get_snapshot(),
		"teardown_receipt": controller.teardown_receipt.duplicate(true),
		"pause_ownership": {
			"tree_paused":controller.get_tree().paused,
			"controller_process_mode":controller.process_mode,
			"shell_process_mode":controller.shell.process_mode,
			"world_process_mode":world.process_mode if world else Node.PROCESS_MODE_DISABLED,
			"wave_process_mode":controller.wave_director.process_mode,
		},
		"terminal_handoff":controller.terminal_handoff_receipt.duplicate(true),
		"context_handoff":controller.context_handoff_receipt.duplicate(true),
		"validation_density":controller.validation_density_receipt.duplicate(true),
		"validation_profile":controller.validation_profile_receipt.duplicate(true),
		"validation_profile_sample":controller.validation_profile_sample.duplicate(true),
		"validation_profile_cycles":controller.validation_profile_cycles.duplicate(true),
		"ordinary_profile_cycles":controller.ordinary_profile_cycles.duplicate(true),
		"validation_profile_cycle_comparison":controller._profile_cycle_comparison(),
		"dense_profile_cycle_comparison":controller._dense_profile_cycle_comparison(),
		"dense_profile_contract":DenseWaveProfileClass.contract(),
		"ordinary_profile_contract_checks":controller.ordinary_profile_contract_checks.duplicate(true),
		"density_matrix_contract_checks":controller.density_matrix_contract_checks.duplicate(true),
		"validation_retry_baselines":controller.validation_retry_baselines.duplicate(true),
		"boss_transition_history":controller.boss_transition_history.duplicate(true),
		"ordinary_victory_receipt":controller.ordinary_victory_receipt.duplicate(true),
		"tester_victory_fixture":controller.tester_victory_fixture_receipt.duplicate(true),
		"warden_hat_isolation":warden.hat_isolation_receipt.duplicate(true) if warden else {},
		"complete_run_ledger":ledger_snapshot,
		"complete_run_row_qualifications":(ledger_matrix.get("row_qualifications", []) as Array).duplicate(true),
		"complete_run_build_shape_rows":(ledger_matrix.get("ordinary_build_shape_rows", {}) as Dictionary).duplicate(true),
		"complete_run_remaining_matrix_cells":(ledger_matrix.get("remaining_matrix_cells", []) as Array).duplicate(),
		"validation_profile_matrix":controller._profile_matrix_snapshot(),
		"world_active": world.session_active if world else false,
	}
