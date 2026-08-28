class_name RunController
extends Node

signal state_changed(previous: String, current: String)
signal snapshot_changed(snapshot: Dictionary)

@onready var world: SurvivalFoundation = $World
@onready var warden: WardenController = $World/Warden
@onready var health: WardenHealth = $World/Warden/HealthComponent
@onready var inventory: WeaponInventory = $World/Warden/Weapons/WeaponInventory
@onready var spawner: EncounterSpawner = $World/EncounterSpawner
@onready var hud: RunHUD = $Interface/GameplayHUD
@onready var shell: RunShellView = $Interface/RunShellView
@onready var title_menu = $Interface/MainMenu
@onready var wave_director: MournlightWaveDirector = $WaveDirector
@onready var draft_controller: UpgradeDraftController = $UpgradeDraftController
@onready var draft_view: UpgradeDraftView = $Interface/UpgradeDraft
@onready var audio_director: MournlightAudioDirector = $MournlightAudio
@onready var input_router: InputContextRouter = $InputContextRouter
@onready var lantern_runtime: WardenLanternRuntime = $World/Warden/Weapons/WardenLanternRuntime
@onready var gravespade_runtime: GravespadeRuntime = $World/Warden/Weapons/GravespadeRuntime
@onready var wisps_runtime: WanderingWispsRuntime = $World/Warden/Weapons/WanderingWispsRuntime
const BELLKEEPER_SCENE := preload("res://scenes/enemies/bellkeeper.tscn")
const REWARD_PICKUP_SCENE := preload("res://scenes/gameplay/reward_pickup.tscn")
const MAX_ACTIVE_PICKUPS := 16
const VICTORY_PRESENTATION_HOLD_SECONDS := 2.6
const PROFILE_DENSITY_MIN := 25
const PROFILE_DENSITY_MAX := 40
const CompleteRunLedgerClass := preload("res://scripts/gameplay/complete_run_ledger.gd")

var run_state := "title"
var run_serial := 0
var run_elapsed := 0.0
var experience := 0
var experience_threshold := 5
var level := 1
var defeated_enemies := 0
var damage_taken := 0
var damage_dealt := 0
var outcome := ""
var selected_upgrades: Array[Dictionary] = []
var boss_transition_history: Array[Dictionary] = []
var boss: BellkeeperActor
var boss_snapshot: Dictionary = {}
var quit_requested := false
var _resume_state := "active"
var result_committed := false
var terminal_commit_count := 0
var run_route_kind := "ordinary"
var terminal_snapshot: Dictionary = {}
var state_history: Array[String] = []
var last_snapshot: Dictionary = {}
var _snapshot_clock := 0.0
var _last_health := 100.0
var _health_accounting_suspended := false
var teardown_receipt: Dictionary = {}
var _teardown_generation := 0
var _teardown_active := false
var _terminal_handoff_generation := 0
var _terminal_handoff_active := false
var _terminal_handoff_release_frames := 0
var terminal_handoff_receipt: Dictionary = {}
var context_handoff_receipt: Dictionary = {}
var _context_handoff_active := false
var _context_handoff_destination := ""
var _context_handoff_physical := ""
var _context_handoff_activation_generation := -1
var _context_handoff_generation := 0
var _validation_setup_generation := 0
var validation_density_receipt: Dictionary = {}
var validation_profile_receipt: Dictionary = {}
var validation_profile_sample: Dictionary = {}
var validation_retry_baselines: Array[Dictionary] = []
var validation_profile_cycles: Array[Dictionary] = []
var ordinary_profile_cycles: Array[Dictionary] = []
var ordinary_profile_contract_checks: Dictionary = {}
var ordinary_victory_receipt: Dictionary = {}
var ordinary_victory_transactions: Array[Dictionary] = []
var tester_victory_fixture_receipt: Dictionary = {}
var pickup_spawned_total := 0
var pickup_collected_total := 0
var _profile_samples_ms: Array[float] = []
var _profile_active := false
var _profile_elapsed := 0.0
var _profile_duration := 4.0
var _profile_origin := ""
var _profile_start_counts: Dictionary = {}
var _next_baseline_reason := "fresh_start"
var _retry_baseline_generation := 0
var _victory_transaction_active := false
var _victory_hold_remaining := 0.0
var _victory_hold_elapsed := 0.0
var _victory_source_run_serial := -1
var _victory_hold_started_msec := 0
var _profile_start_lifecycle: Dictionary = {}
var _profile_armed := false
var _profile_arm_receipt: Dictionary = {}
var _profile_minimum_enemy_workload := 0
var _profile_maximum_enemy_workload := 0
var _profile_rearm_count := 0
var _victory_fixture_commit_held := false
var _victory_fixture_hold_generation := -1
var complete_run_ledger: CompleteRunLedger
var _profile_physics_samples_ms: Array[float] = []
var _profile_advance_generation := 0
var validation_profile_matrix_samples: Array[Dictionary] = []
var _active_pickups: Dictionary = {}
var _active_pickup_count := 0
var _active_effect_count := 0
var _profile_static_light_count := 0
var _profile_setup_scene_scans := 0
var _profile_sample_counter_reads := 0
var _profile_gate_counter_reads := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	complete_run_ledger = CompleteRunLedgerClass.new()
	ordinary_profile_contract_checks = _ordinary_profile_contract_checks()
	_profile_static_light_count = _bounded_static_light_snapshot()
	shell.action_requested.connect(_on_shell_action)
	title_menu.game_started.connect(start_run)
	title_menu.game_exited.connect(_on_title_exit_requested)
	title_menu.settings_requested.connect(_on_title_page_requested.bind("settings"))
	title_menu.credits_requested.connect(_on_title_page_requested.bind("credits"))
	health.failed.connect(_on_warden_failed)
	health.health_changed.connect(_on_health_changed)
	spawner.enemy_defeated.connect(_on_enemy_defeated)
	spawner.reward_dropped.connect(_on_reward_dropped)
	spawner.encounter_changed.connect(_on_encounter_changed)
	inventory.build_changed.connect(_on_build_changed)
	wave_director.phase_changed.connect(_on_wave_phase_changed)
	wave_director.boss_requested.connect(_spawn_bellkeeper)
	draft_controller.draft_opened.connect(_on_draft_opened)
	draft_view.choice_requested.connect(_on_draft_choice)
	world.attack_runtime.hit_resolved.connect(_on_player_hit_resolved)
	warden.dash_phase_changed.connect(_on_dash_changed)
	input_router.logical_press_edge.connect(_on_logical_press_edge)
	input_router.context_changed.connect(_on_input_context_changed)
	if OS.has_feature("editor"):
		for action in [&"validation_prepare_wave4", &"validation_prepare_boss", &"validation_prepare_draft", &"validation_prepare_result_failure", &"validation_prepare_result_victory", &"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10", &"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_advance_density", &"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile", &"validation_reset_final_profile", &"tester_victory_prepare", &"tester_victory_advance", &"tester_victory_commit", &"tester_final_profile_prepare", &"tester_final_profile_advance", &"tester_final_profile_reset"]:
			if not InputMap.has_action(action):
				InputMap.add_action(action)
	_enter_title()

func _process(delta: float) -> void:
	_advance_context_handoff()
	_advance_victory_transaction(delta)
	_try_begin_passive_ordinary_profile()
	_advance_profile_sample(delta)
	if run_state in ["active","boss"] and not get_tree().paused:
		run_elapsed += delta
	_snapshot_clock -= delta
	if _snapshot_clock <= 0.0:
		_snapshot_clock = 0.1
		_emit_snapshot()

func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_victory_prepare"):
		_prepare_tester_victory()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_victory_advance"):
		_advance_tester_victory()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_victory_commit"):
		_commit_tester_victory()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_final_profile_prepare"):
		_prepare_final_profile()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_final_profile_advance"):
		_advance_final_profile()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_final_profile_reset"):
		_reset_final_profile()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_final_profile"):
		_prepare_final_profile()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_advance_final_profile"):
		_advance_final_profile()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_reset_final_profile"):
		_reset_final_profile()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_density_3"):
		_prepare_validation_density_checkpoint(3)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_density_5"):
		_prepare_validation_density_checkpoint(5)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_density_10"):
		_prepare_validation_density_checkpoint(10)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_density_18"):
		_prepare_validation_density_checkpoint(18)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_density_32"):
		_prepare_validation_density_checkpoint(32)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_advance_density"):
		_advance_validation_density_checkpoint()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_reset_density"):
		_reset_validation_density()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_wave4"):
		_prepare_validation_wave(3)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_boss"):
		_prepare_validation_wave(4)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_draft"):
		_open_upgrade_draft()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_result_failure"):
		_prepare_validation_result("failure")
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_result_victory"):
		_prepare_tester_victory()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		if run_state in ["active","boss"]:
			_pause_run()
		elif run_state == "paused":
			_resume_run()
		get_viewport().set_input_as_handled()

func start_run() -> void:
	_next_baseline_reason = "fresh_start"
	_teardown_run("fresh_start", "defensive_start_cleanup")
	_begin_run()

func _begin_run() -> void:
	get_tree().paused = false
	_profile_active = false
	_profile_origin = ""
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_elapsed = 0.0
	_profile_start_counts.clear()
	_profile_armed = false
	_profile_arm_receipt.clear()
	_profile_minimum_enemy_workload = 0
	_profile_maximum_enemy_workload = 0
	_profile_sample_counter_reads = 0
	_profile_gate_counter_reads = 0
	_active_pickups.clear()
	_active_pickup_count = 0
	_active_effect_count = 0
	_transition("initializing")
	run_serial += 1
	complete_run_ledger.begin_run(run_serial, "ordinary", "retry" if _next_baseline_reason == "retry" else "title_play")
	run_elapsed = 0.0
	experience = 0
	experience_threshold = 5
	level = 1
	defeated_enemies = 0
	damage_taken = 0
	damage_dealt = 0
	pickup_spawned_total = 0
	pickup_collected_total = 0
	outcome = ""
	selected_upgrades.clear()
	boss_transition_history.clear()
	ordinary_victory_receipt.clear()
	tester_victory_fixture_receipt.clear()
	_victory_transaction_active = false
	_victory_hold_remaining = 0.0
	_victory_hold_elapsed = 0.0
	_victory_source_run_serial = -1
	_victory_hold_started_msec = 0
	_victory_fixture_commit_held = false
	_victory_fixture_hold_generation = -1
	boss_snapshot.clear()
	result_committed = false
	terminal_commit_count = 0
	run_route_kind = "ordinary"
	terminal_snapshot.clear()
	draft_controller.reset()
	audio_director.reset_for_run()
	world.reset_session(true, "begin_run_%s" % _next_baseline_reason)
	_health_accounting_suspended = true
	health.maximum_health = 100.0
	health.reset_warden_health()
	warden.cooldown_duration = 0.72
	warden.pickup_collection_radius = 1.75
	warden.experience_yield_multiplier = 1.0
	_last_health = health.current_health
	_health_accounting_suspended = false
	inventory.reset_starting_build()
	world.set_session_active(true)
	_set_title_surface(false)
	shell.set_mode("hidden")
	spawner.clear_validation_roster()
	spawner.reset_encounter()
	wave_director.begin()
	_transition("active")
	_record_retry_baseline(_next_baseline_reason)
	_next_baseline_reason = "ordinary_run"
	_emit_snapshot()

func retry_run() -> void:
	var source_run_serial := run_serial
	var victory_transaction := ordinary_victory_receipt.duplicate(true)
	var victory_fixture := tester_victory_fixture_receipt.duplicate(true)
	_next_baseline_reason = "retry"
	complete_run_ledger.record_exit(run_serial, "retry", run_elapsed)
	_update_ordinary_profile_cycle(source_run_serial, "retry", {
		"player_caused":true,
		"source_state":run_state,
		"elapsed":run_elapsed,
		"process_frame":Engine.get_process_frames(),
	})
	_teardown_run("retry", "player_retry")
	_transition("retrying")
	_begin_run()
	_record_ordinary_retry_baseline(source_run_serial)
	if not victory_fixture.is_empty():
		tester_victory_fixture_receipt = victory_fixture
	if not victory_transaction.is_empty():
		_finalize_victory_retry(victory_transaction)

func _enter_title() -> void:
	if run_serial > 0:
		complete_run_ledger.record_exit(run_serial, "title", run_elapsed)
	_context_handoff_active = false
	_terminal_handoff_active = false
	_teardown_run("title", "return_to_title")
	boss_snapshot.clear()
	hud.clear_snapshot()
	_transition("title")
	shell.set_mode("hidden")
	_set_title_surface(true)
	title_menu.new_game_button.grab_focus.call_deferred()
	_emit_snapshot()

func _begin_terminal_title_handoff() -> void:
	if _terminal_handoff_active:
		return
	_terminal_handoff_generation += 1
	_begin_shell_title_handoff("result", "confirm")
	terminal_handoff_receipt = context_handoff_receipt.duplicate(true)

func _begin_shell_title_handoff(source: String, physical: String) -> void:
	_teardown_run("title", "return_to_title")
	boss_snapshot.clear()
	hud.clear_snapshot()
	_transition("title")
	shell.set_mode("hidden")
	_set_title_surface(false)
	_begin_context_handoff(source, "title", physical)
	_emit_snapshot()

func _begin_context_handoff(source: String, destination: String, physical: String) -> void:
	var transaction: Dictionary = input_router.active_transactions.get(physical, {})
	if transaction.is_empty():
		# Focused buttons may commit ui_accept on the same logical-release frame,
		# after the router has archived the physical transaction. Bind that exact
		# release; older receipts remain ineligible so mouse/programmatic actions
		# cannot inherit stale keyboard or gamepad ownership.
		var archived: Dictionary = input_router.last_release_receipt
		var release_frame := int(archived.get("release_observation_frame", -1000))
		var same_release := (
			String(archived.get("physical", "")) == physical
			and String(archived.get("originating_context", "")) == source
			and bool(archived.get("physical_release_observed", false))
			and Engine.get_process_frames() - release_frame <= 1
		)
		_context_handoff_generation += 1
		context_handoff_receipt = {
			"generation":_context_handoff_generation,
			"source":source, "destination":destination,
			"physical":physical if same_release else "mouse_or_programmatic",
			"originating_context":archived.get("originating_context", source) if same_release else source,
			"originating_context_generation":archived.get("originating_context_generation", -1) if same_release else -1,
			"activation_generation":archived.get("activation_generation", -1) if same_release else -1,
			"shell_action_generation":shell.action_generation,
			"stage":"complete", "release_observed":same_release,
			"release_context":archived.get("release_context", source) if same_release else source,
			"logical_release_dispatched":archived.get("logical_release_dispatched", false) if same_release else false,
			"destination_exposed":true, "downstream_action_count":1,
			"teardown_complete":bool(teardown_receipt.get("complete", false)),
			"teardown_generation":int(teardown_receipt.get("completion_generation", 0)),
			"reset_invariants":(teardown_receipt.get("reset_invariants", {}) as Dictionary).duplicate(true),
			"focus_target":"Play" if destination == "title" else "Resume",
			"quit_requested":quit_requested,
		}
		_complete_context_handoff(destination, true)
		return
	_context_handoff_active = true
	_context_handoff_generation += 1
	_context_handoff_destination = destination
	_context_handoff_physical = physical
	_context_handoff_activation_generation = int(transaction.get("activation_generation", -1))
	input_router.bind_destination(physical, destination, 1)
	context_handoff_receipt = {
		"generation":_context_handoff_generation,
		"source":source, "destination":destination,
		"physical":physical,
		"originating_context":transaction.get("originating_context", source),
		"originating_context_generation":transaction.get("originating_context_generation", -1),
		"activation_generation":_context_handoff_activation_generation,
		"shell_action_generation":shell.action_generation,
		"stage":"awaiting_physical_release",
		"release_observed":false, "destination_exposed":false,
		"downstream_action_count":1,
		"teardown_complete":bool(teardown_receipt.get("complete", false)),
		"teardown_generation":int(teardown_receipt.get("completion_generation", 0)),
		"reset_invariants":(teardown_receipt.get("reset_invariants", {}) as Dictionary).duplicate(true),
	}
	if source == "result":
		_terminal_handoff_active = true
		terminal_handoff_receipt = context_handoff_receipt.duplicate(true)

func _advance_context_handoff() -> void:
	if not _context_handoff_active:
		return
	if not input_router.transaction_released(_context_handoff_physical, _context_handoff_activation_generation):
		return
	var transaction := input_router.transaction_receipt(_context_handoff_physical, _context_handoff_activation_generation)
	context_handoff_receipt["release_observed"] = bool(transaction.get("physical_release_observed", false))
	context_handoff_receipt["release_context"] = transaction.get("release_context", "")
	context_handoff_receipt["logical_release_dispatched"] = transaction.get("logical_release_dispatched", false)
	context_handoff_receipt["downstream_action_count"] = transaction.get("downstream_action_count", 0)
	_complete_context_handoff(_context_handoff_destination, false)

func _complete_context_handoff(destination: String, immediate: bool) -> void:
	_context_handoff_active = false
	_context_handoff_destination = ""
	_context_handoff_physical = ""
	_context_handoff_activation_generation = -1
	if destination == "title":
		shell.set_mode("hidden")
		_set_title_surface(true)
		title_menu.new_game_button.grab_focus.call_deferred()
	elif destination == "pause":
		_set_title_surface(false)
		get_tree().paused = true
		shell.set_mode("pause", last_snapshot)
	if not immediate:
		context_handoff_receipt["stage"] = "complete"
		context_handoff_receipt["destination_exposed"] = true
		context_handoff_receipt["focus_target"] = "Play" if destination == "title" else "Resume"
		context_handoff_receipt["quit_requested"] = quit_requested
	if _terminal_handoff_active:
		_terminal_handoff_active = false
		terminal_handoff_receipt = context_handoff_receipt.duplicate(true)
	_emit_snapshot()

func _pause_run() -> void:
	warden.reset_input_latch("pause")
	_resume_state = run_state
	_transition("paused")
	get_tree().paused = true
	shell.set_mode("pause", last_snapshot)
	_emit_snapshot()

func _resume_run() -> void:
	get_tree().paused = false
	warden.reset_input_latch("resume")
	shell.set_mode("hidden")
	_transition(_resume_state)
	_emit_snapshot()

func _on_warden_failed(event: Dictionary) -> void:
	if result_committed or run_state not in ["active", "boss", "paused", "draft"]:
		return
	result_committed = true
	outcome = "failure"
	if warden.animation_binding:
		warden.animation_binding.acquire_terminal_lease("death", "run_controller.failure", run_serial)
	_commit_terminal_snapshot("failure")
	_teardown_run("result", "failure")
	get_tree().paused = true
	_transition("failure")
	_emit_snapshot()
	call_deferred("_present_result", event)

func _present_result(_event: Dictionary) -> void:
	_transition("result")
	complete_run_ledger.record_result_presented(run_serial, outcome)
	hud.visible = false
	shell.set_mode("result", terminal_snapshot)
	_update_ordinary_profile_cycle(run_serial, "result", {
		"presented":shell.mode == "result",
		"outcome":outcome,
		"displayed_fields":shell._displayed_result_fields(),
		"process_frame":Engine.get_process_frames(),
	})
	if outcome == "victory" and int(ordinary_victory_receipt.get("source_run_serial", -1)) == run_serial:
		var result_animation := warden.animation_binding.get_snapshot() if warden.animation_binding else {}
		var result_handoff := {
			"run_state":run_state, "shell_mode":shell.mode,
			"terminal_owner":"victory", "animation":result_animation,
		}
		ordinary_victory_receipt["status"] = "result_presented"
		ordinary_victory_receipt["result_handoff"] = result_handoff
		(ordinary_victory_receipt["stages"] as Array).append({"stage":"result_presented","run_state":run_state,"shell_mode":shell.mode,"animation":result_animation})
		if String(tester_victory_fixture_receipt.get("branch_id", "")) == "tester_victory_transaction":
			tester_victory_fixture_receipt["result_presented"] = true
			tester_victory_fixture_receipt["result_commit_count"] = terminal_commit_count
			tester_victory_fixture_receipt["presentation_transaction"] = ordinary_victory_receipt.duplicate(true)
	_emit_snapshot()

func _finalize_victory_retry(transaction: Dictionary) -> void:
	transaction["status"] = "retry_idle_restored"
	var retry_state := {
		"prior_run_serial":transaction.get("source_run_serial", -1),
		"new_run_serial":run_serial,
		"run_state":run_state,
		"route_kind":run_route_kind,
		"terminal_owner_cleared":not result_committed and terminal_snapshot.is_empty(),
		"terminal_commit_count_reset":terminal_commit_count == 0,
		"animation":warden.animation_binding.get_snapshot() if warden.animation_binding else {},
		"counts":_profile_counts(),
		"teardown":teardown_receipt.duplicate(true),
	}
	transaction["retry"] = retry_state
	var retry_animation: Dictionary = retry_state.get("animation", {})
	transaction["retry_clean"] = (
		bool(retry_state.get("terminal_owner_cleared", false))
		and bool(retry_state.get("terminal_commit_count_reset", false))
		and String(retry_animation.get("semantic_state", "")) == "idle"
		and String(retry_animation.get("resolved_clip", "")) == "Idle"
		and bool((_terminal_reset_invariants("retry") as Dictionary).get("complete", false))
		and _counts_are_isolated(retry_state.get("counts", {}))
	)
	var stages: Array = transaction.get("stages", [])
	stages.append({"stage":"retry_idle_restored","prior_run_serial":transaction.get("source_run_serial",-1),"new_run_serial":run_serial,"retry_clean":transaction["retry_clean"],"animation":retry_animation})
	transaction["stages"] = stages
	ordinary_victory_receipt = transaction.duplicate(true)
	if String(tester_victory_fixture_receipt.get("branch_id", "")) == "tester_victory_transaction":
		tester_victory_fixture_receipt["retry_run_serial"] = run_serial
		tester_victory_fixture_receipt["reset_counts"] = _profile_counts()
		tester_victory_fixture_receipt["reset_isolation"] = _counts_are_isolated(_profile_counts())
		tester_victory_fixture_receipt["reset_lifecycle"] = _lifecycle_counters()
	ordinary_victory_transactions.append(transaction.duplicate(true))
	while ordinary_victory_transactions.size() > 2:
		ordinary_victory_transactions.pop_front()
	_emit_snapshot()

func _on_health_changed(current: float, _maximum: float) -> void:
	if _health_accounting_suspended:
		_last_health = current
		return
	if current < _last_health:
		damage_taken += int(round(_last_health - current))
	_last_health = current
	_emit_snapshot()

func _on_enemy_defeated(_event: Dictionary) -> void:
	defeated_enemies += 1
	_emit_snapshot()

func _on_reward_dropped(event: Dictionary) -> void:
	_spawn_reward_pickup(event)
	_emit_snapshot()

func _on_reward_pickup_collected(event: Dictionary) -> void:
	pickup_collected_total += 1
	var base_reward := maxi(1, int(event.get("reward_value", 1)))
	var resolved_reward := maxi(1, int(round(float(base_reward) * warden.experience_yield_multiplier)))
	experience += resolved_reward
	if experience >= experience_threshold:
		experience -= experience_threshold
		level += 1
		experience_threshold = 5 + (level - 1) * 2
		_open_upgrade_draft()
	_emit_snapshot()

func _on_reward_pickup_retired(event: Dictionary) -> void:
	var instance_id := int(event.get("instance_id", 0))
	if _active_pickups.erase(instance_id):
		_active_pickup_count = _active_pickups.size()

func _spawn_reward_pickup(event: Dictionary) -> RewardPickup:
	if _active_pickup_count >= MAX_ACTIVE_PICKUPS:
		var merge_target: RewardPickup
		for pickup_value in _active_pickups.values():
			if is_instance_valid(pickup_value):
				merge_target = pickup_value as RewardPickup
				break
		if is_instance_valid(merge_target):
			merge_target.merge_reward(event)
			pickup_spawned_total += 1
			return merge_target
	var pickup := REWARD_PICKUP_SCENE.instantiate() as RewardPickup
	world.add_child(pickup)
	pickup.configure(warden, event)
	pickup.collected.connect(_on_reward_pickup_collected)
	pickup.retired.connect(_on_reward_pickup_retired)
	_active_pickups[pickup.get_instance_id()] = pickup
	_active_pickup_count = _active_pickups.size()
	pickup_spawned_total += 1
	return pickup

func _seed_profile_pickups(count: int) -> int:
	var seeded := 0
	for index in range(clampi(count, 0, 8)):
		var angle := TAU * float(index) / maxf(1.0, float(count))
		var event := {
			"accepted":true,
			"drop_id":"profile.g%04d.pickup.%02d" % [_validation_setup_generation + 1, index],
			"drop_type":"escaped_wisp",
			"position":Vector3(cos(angle) * 4.2, 0.05, sin(angle) * 3.6),
			"profile_seeded":true,
		}
		_spawn_reward_pickup(event)
		seeded += 1
	return seeded

func _on_encounter_changed(_snapshot: Dictionary) -> void:
	_try_begin_passive_ordinary_profile()
	_emit_snapshot()

func _on_build_changed(_snapshot: Dictionary) -> void:
	_emit_snapshot()

func _on_dash_changed(_phase: String, _invulnerable: bool) -> void:
	_emit_snapshot()

func _on_logical_press_edge(action: StringName, activation: int, receipt: Dictionary) -> void:
	if action != &"dash":
		return
	var accepted := false
	if run_state in ["active", "boss"] and not get_tree().paused:
		accepted = warden.queue_routed_dash(activation, receipt)
	input_router.bind_destination(
		"confirm",
		"warden_dash" if accepted else "warden_dash_rejected",
		1 if accepted else 0
	)

func _on_input_context_changed(_previous: String, current: String, _generation: int) -> void:
	if current not in ["active", "boss"]:
		warden.clear_dash_ownership("context_%s" % current)

func _on_shell_action(action: StringName) -> void:
	match action:
		&"play": start_run()
		&"resume": _resume_run()
		&"retry": retry_run()
		&"title":
			if run_state == "result":
				_begin_terminal_title_handoff()
			else:
				_begin_shell_title_handoff(shell.mode, "confirm")
		&"settings": _open_settings_page()
		&"credits": _open_credits_page()
		&"back": _return_from_shell_page()
		&"quit":
			quit_requested = true
			if not OS.has_feature("editor"):
				get_tree().quit()

func _on_title_page_requested(page: String) -> void:
	_set_title_surface(false)
	shell.set_mode(page)
	if page == "credits":
		complete_run_ledger.record_credits(run_serial, shell.mode)
	_emit_snapshot()

func _open_settings_page() -> void:
	if run_state == "paused":
		_transition("settings")
		get_tree().paused = true
		shell.set_mode("settings", last_snapshot)
	elif run_state == "title":
		_set_title_surface(false)
		shell.set_mode("settings")
	_emit_snapshot()

func _open_credits_page() -> void:
	if run_state == "title":
		_set_title_surface(false)
		shell.set_mode("credits")
		complete_run_ledger.record_credits(run_serial, shell.mode)
	_emit_snapshot()

func _return_from_shell_page() -> void:
	if shell.return_mode == "pause" and run_state == "settings":
		get_tree().paused = true
		_transition("paused")
		shell.set_mode("hidden")
		_begin_context_handoff("settings", "pause", "back")
		_emit_snapshot()
	else:
		var source := shell.mode
		_teardown_run("title", "return_from_%s" % source)
		boss_snapshot.clear()
		hud.clear_snapshot()
		_transition("title")
		shell.set_mode("hidden")
		_set_title_surface(false)
		_begin_context_handoff(source, "title", "back")
		_emit_snapshot()

func _on_title_exit_requested() -> void:
	quit_requested = true
	if not OS.has_feature("editor"):
		get_tree().quit()

func _set_title_surface(exposed: bool) -> void:
	if exposed:
		title_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		title_menu.show()
	else:
		title_menu.hide()
		title_menu.process_mode = Node.PROCESS_MODE_DISABLED

func _open_upgrade_draft() -> void:
	if run_state != "active" or draft_controller.active:
		return
	warden.reset_input_latch("draft")
	_transition("draft")
	get_tree().paused = true
	draft_controller.open_draft(inventory, health, warden)

func _on_draft_opened(cards: Array[Dictionary]) -> void:
	draft_view.present(cards)
	_emit_snapshot()

func _on_draft_choice(index: int) -> void:
	var choice := draft_controller.choose(index, inventory, health, warden)
	if choice.is_empty():
		return
	var wave_state := wave_director.get_snapshot()
	choice["draft_serial"] = draft_controller.draft_serial
	choice["accepted_at_elapsed"] = run_elapsed
	choice["accepted_at_wave_id"] = String((wave_state.get("definition", {}) as Dictionary).get("id", "warmup"))
	choice["route_kind"] = run_route_kind
	choice["natural_choice"] = run_route_kind == "ordinary" and int(wave_state.get("diagnostic_jump_count", 0)) == 0
	choice["truthful_transaction"] = bool((choice.get("application", {}) as Dictionary).get("accepted", false)) and bool((choice.get("application", {}) as Dictionary).get("matches_projection", false))
	selected_upgrades.append(choice)
	complete_run_ledger.record_draft(choice, run_elapsed, run_route_kind, int(wave_state.get("diagnostic_jump_count", 0)))
	draft_view.close()
	get_tree().paused = false
	_transition("active")
	_emit_snapshot()

func _on_wave_phase_changed(snapshot: Dictionary) -> void:
	if String(snapshot.get("phase","")) == "active":
		complete_run_ledger.record_wave(snapshot, run_elapsed, run_route_kind)
		var definition: Dictionary = snapshot.get("definition",{})
		spawner.configure_pressure(definition)
		if not spawner.active:
			spawner.begin_encounter()
		if int(snapshot.get("wave",1)) == 5:
			_transition("boss")
			_arm_passive_ordinary_profile(snapshot)
	_emit_snapshot()

func _spawn_bellkeeper() -> void:
	if is_instance_valid(boss) or result_committed:
		return
	boss = BELLKEEPER_SCENE.instantiate() as BellkeeperActor
	world.get_node("BossAnchor").add_child(boss)
	boss.position = Vector3.ZERO
	boss.configure(warden)
	var wave_state := wave_director.get_snapshot()
	boss_transition_history.append({
		"event":"bellkeeper_spawned", "elapsed":run_elapsed,
		"wave_id":String((wave_state.get("definition", {}) as Dictionary).get("id", "")),
		"wave_index":int(wave_state.get("wave", 0)), "route_kind":run_route_kind,
		"natural_transition":run_route_kind == "ordinary" and int(wave_state.get("diagnostic_jump_count", 0)) == 0,
	})
	complete_run_ledger.record_boss("bellkeeper_spawned", boss_transition_history.back(), run_elapsed, run_route_kind, int(wave_state.get("diagnostic_jump_count", 0)))
	boss.boss_changed.connect(_on_boss_changed)
	boss.defeated.connect(_on_boss_defeated)
	boss.phase_shifted.connect(_on_boss_phase_shifted)
	boss_snapshot = boss.get_snapshot()
	_try_begin_passive_ordinary_profile()

func _on_boss_phase_shifted(next_phase: int) -> void:
	audio_director.play_semantic("boss_phase")
	var wave_state := wave_director.get_snapshot()
	boss_transition_history.append({
		"event":"bellkeeper_phase_shifted", "phase":next_phase, "elapsed":run_elapsed,
		"wave_id":String((wave_state.get("definition", {}) as Dictionary).get("id", "")),
		"route_kind":run_route_kind,
		"natural_transition":run_route_kind == "ordinary" and int(wave_state.get("diagnostic_jump_count", 0)) == 0,
	})
	complete_run_ledger.record_boss("bellkeeper_phase_shifted", boss_transition_history.back(), run_elapsed, run_route_kind, int(wave_state.get("diagnostic_jump_count", 0)))

func _on_boss_changed(snapshot: Dictionary) -> void:
	boss_snapshot = snapshot.duplicate(true)
	_emit_snapshot()

func _on_boss_defeated(_event: Dictionary) -> void:
	if result_committed or _victory_transaction_active:
		return
	outcome = "victory"
	_victory_transaction_active = true
	_victory_hold_remaining = VICTORY_PRESENTATION_HOLD_SECONDS
	_victory_hold_elapsed = 0.0
	_victory_source_run_serial = run_serial
	_victory_hold_started_msec = Time.get_ticks_msec()
	var acquisition_frame := Engine.get_process_frames()
	var lease_acquired := false
	if warden.animation_binding:
		lease_acquired = warden.animation_binding.acquire_terminal_lease("victory", "run_controller.bellkeeper_defeat", run_serial)
	var vfx_receipt := warden.begin_victory_presentation(VICTORY_PRESENTATION_HOLD_SECONDS, run_serial)
	var wave_state := wave_director.get_snapshot()
	complete_run_ledger.record_boss("bellkeeper_defeated", {"phase":boss_snapshot.get("phase",0),"defeat_committed":true}, run_elapsed, run_route_kind, int(wave_state.get("diagnostic_jump_count", 0)))
	wave_director.terminate("victory_presentation")
	_teardown_generation += 1
	var hold_retirement := _retire_transient_ownership("victory_hold", "bellkeeper_defeated", _teardown_generation)
	world.reset_session(false)
	_transition("victory")
	var animation_snapshot := warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	ordinary_victory_receipt = {
		"transaction_id":"victory.r%04d" % run_serial,
		"source_run_serial":run_serial,
		"status":"presentation_holding",
		"route_kind":run_route_kind, "elapsed":run_elapsed,
		"wave_id":String((wave_state.get("definition", {}) as Dictionary).get("id", "")),
		"wave_ids":(wave_state.get("ordinary_route_wave_ids", []) as Array).duplicate(),
		"ordinary_route_complete":bool(wave_state.get("ordinary_route_complete", false)),
		"ordinary_route_eligible":run_route_kind == "ordinary" and bool(wave_state.get("ordinary_route_eligible", false)),
		"diagnostic_jump_count":int(wave_state.get("diagnostic_jump_count", 0)),
		"boss_defeat_committed":true,
		"lease_acquired":lease_acquired,
		"acquisition_frame":acquisition_frame,
		"animation":animation_snapshot,
		"terminal_owner":"victory",
		"presentation_hold":{"required_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,"elapsed_seconds":0.0,"remaining_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,"complete":false},
		"audiovisual":{"vfx":vfx_receipt,"audio":audio_director._mcp_state().get("terminal_audio_lease",{}),"event_count":1},
		"combat_retirement":hold_retirement,
		"stages":[
			{"stage":"bellkeeper_defeated","run_state":run_state,"elapsed":run_elapsed,"boss_defeat_committed":true},
			{"stage":"victory_animation_acquired","acquisition_frame":acquisition_frame,"lease_acquired":lease_acquired,"animation":animation_snapshot},
			{"stage":"victory_presentation_holding","required_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,"combat_retired":hold_retirement.get("complete",false)},
		],
		"result_commit_count_before":terminal_commit_count,
		"result_committed":false,
	}
	_emit_snapshot()

func _advance_victory_transaction(delta: float) -> void:
	if not _victory_transaction_active:
		return
	if _victory_fixture_commit_held:
		return
	if _victory_source_run_serial != run_serial:
		_victory_transaction_active = false
		return
	# A paused preparation can resume with a catch-up delta. The terminal hold is
	# a presentation window, so one hitch must not skip Cheer and audio onset.
	var presentation_delta := minf(maxf(delta, 0.0), 0.1)
	_victory_hold_elapsed += presentation_delta
	_victory_hold_remaining = maxf(0.0, _victory_hold_remaining - presentation_delta)
	ordinary_victory_receipt["presentation_hold"] = {
		"required_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,
		"elapsed_seconds":_victory_hold_elapsed,
		"remaining_seconds":_victory_hold_remaining,
		"complete":_victory_hold_remaining <= 0.0,
		"wall_elapsed_seconds":float(Time.get_ticks_msec() - _victory_hold_started_msec) / 1000.0,
		"audio_source_completed":audio_director.terminal_voice_retirement_reason == "source_finished",
	}
	ordinary_victory_receipt["held_animation"] = warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	var wall_elapsed := float(Time.get_ticks_msec() - _victory_hold_started_msec) / 1000.0
	var audio_source_completed := audio_director.terminal_voice_retirement_reason == "source_finished"
	if _victory_hold_remaining <= 0.0 and wall_elapsed >= VICTORY_PRESENTATION_HOLD_SECONDS and audio_source_completed:
		_commit_victory_transaction()

func _commit_victory_transaction() -> void:
	if not _victory_transaction_active or result_committed or _victory_source_run_serial != run_serial:
		return
	_victory_transaction_active = false
	result_committed = true
	warden.end_victory_presentation("result_handoff")
	ordinary_victory_receipt["status"] = "presentation_complete"
	ordinary_victory_receipt["presentation_hold"] = {
		"required_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,
		"elapsed_seconds":_victory_hold_elapsed,
		"remaining_seconds":0.0,
		"complete":true,
		"completion_frame":Engine.get_process_frames(),
	}
	(ordinary_victory_receipt["stages"] as Array).append({"stage":"victory_presentation_complete","held_seconds":_victory_hold_elapsed,"animation":warden.animation_binding.get_snapshot() if warden.animation_binding else {}})
	_commit_terminal_snapshot("victory")
	ordinary_victory_receipt["result_commit_count_after"] = terminal_commit_count
	ordinary_victory_receipt["result_committed"] = result_committed
	ordinary_victory_receipt["exactly_one_result_commit"] = terminal_commit_count == 1
	(ordinary_victory_receipt["stages"] as Array).append({"stage":"terminal_snapshot_committed","commit_count":terminal_commit_count,"terminal_snapshot":_terminal_snapshot_digest()})
	var victory_teardown := _teardown_run("result", "victory")
	ordinary_victory_receipt["teardown"] = victory_teardown
	ordinary_victory_receipt["handoff_animation"] = warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	(ordinary_victory_receipt["stages"] as Array).append({"stage":"victory_teardown_complete","teardown_complete":victory_teardown.get("complete",false),"animation":ordinary_victory_receipt["handoff_animation"]})
	get_tree().paused = true
	_emit_snapshot()
	call_deferred("_present_result",{})

func _on_player_hit_resolved(event: Dictionary) -> void:
	damage_dealt += int(round(float(event.get("damage",0.0))))

func _commit_terminal_snapshot(terminal_outcome: String) -> void:
	if not terminal_snapshot.is_empty():
		return
	terminal_commit_count += 1
	terminal_snapshot = RunSnapshot.make(self,world,warden,health,spawner,inventory)
	terminal_snapshot.outcome = terminal_outcome
	terminal_snapshot.state = "result"
	terminal_snapshot["committed"] = true
	terminal_snapshot["commit_run_serial"] = run_serial
	terminal_snapshot["commit_count"] = terminal_commit_count
	terminal_snapshot["route_kind"] = run_route_kind
	terminal_snapshot["natural_build_history"] = selected_upgrades.duplicate(true)
	terminal_snapshot["boss_transition_history"] = boss_transition_history.duplicate(true)
	terminal_snapshot["terminal_animation"] = warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	if terminal_outcome == "victory":
		terminal_snapshot["victory_transaction"] = ordinary_victory_receipt.duplicate(true)
	var wave_state := wave_director.get_snapshot()
	var inside_victory_window := terminal_outcome == "victory" and run_elapsed >= 420.0 and run_elapsed <= 600.0
	terminal_snapshot["victory_window_seconds"] = {"minimum":420.0, "maximum":600.0, "inside":inside_victory_window}
	terminal_snapshot["ordinary_route_eligible"] = (
		inside_victory_window
		and run_route_kind == "ordinary"
		and bool(wave_state.get("ordinary_route_complete", false))
		and int(wave_state.get("diagnostic_jump_count", 0)) == 0
		and not boss_transition_history.is_empty()
		and bool(boss_transition_history[-1].get("natural_transition", false))
		and _ordinary_progression_truthful()
		and _boss_two_phase_history_truthful()
	)
	complete_run_ledger.record_terminal(terminal_snapshot, wave_state)
	_update_ordinary_profile_cycle(run_serial, "terminal", {
		"run_serial":run_serial,
		"outcome":terminal_outcome,
		"route_kind":run_route_kind,
		"commit_count":terminal_commit_count,
		"real_terminal":terminal_outcome in ["failure", "victory"] and result_committed,
		"elapsed":run_elapsed,
		"snapshot":_terminal_snapshot_digest(),
		"lifecycle":_lifecycle_counters(),
	})
	terminal_snapshot = terminal_snapshot.duplicate(true)

func _teardown_run(route: String, reason: String) -> Dictionary:
	if _teardown_active:
		return teardown_receipt.duplicate(true)
	_teardown_active = true
	_victory_fixture_commit_held = false
	_victory_fixture_hold_generation = -1
	_teardown_generation += 1
	get_tree().paused = false
	warden.reset_input_latch("teardown_%s_%s" % [route, reason])
	draft_controller.reset()
	draft_view.close()
	if route == "result":
		wave_director.terminate(reason)
	else:
		wave_director.reset()
	var boss_retirement := {"active":false, "state":"absent", "reason":reason, "completion_generation":_teardown_generation}
	if not is_instance_valid(boss) and int(teardown_receipt.get("run_serial", -1)) == run_serial:
		var previous_boss_retirement: Dictionary = teardown_receipt.get("boss_retirement", {})
		if String(previous_boss_retirement.get("state", "")).begins_with("retired_"):
			boss_retirement = previous_boss_retirement.duplicate(true)
	if is_instance_valid(boss):
		boss_retirement = boss.retire_run_actor(reason, _teardown_generation)
		boss_snapshot = boss.get_snapshot().duplicate(true)
		if boss.boss_changed.is_connected(_on_boss_changed):
			boss.boss_changed.disconnect(_on_boss_changed)
		if boss.defeated.is_connected(_on_boss_defeated):
			boss.defeated.disconnect(_on_boss_defeated)
		if boss.phase_shifted.is_connected(_on_boss_phase_shifted):
			boss.phase_shifted.disconnect(_on_boss_phase_shifted)
		boss.queue_free()
	boss = null
	var transient_retirement := _retire_transient_ownership(route, reason, _teardown_generation)
	# Combat ownership always retires without touching terminal deformation.
	# Title resets here; Retry/fresh-start/profile reset do their single reset
	# in _begin_run(), while result preserves the lease.
	world.reset_session(false)
	var presentation_reset: Dictionary = {}
	if route == "title":
		warden.reset_for_run(Vector3(0, 0.05, 6.0), "title")
		presentation_reset = warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	var encounter := spawner.get_snapshot()
	var post_counts := _profile_counts()
	var reset_invariants := _terminal_reset_invariants(route)
	var teardown_complete := (
		bool(transient_retirement.get("complete", false))
		and int(encounter.get("live", -1)) == 0
		and int((encounter.get("neighbor_registry", {}) as Dictionary).get("registered_count", -1)) == 0
		and _counts_are_isolated(post_counts)
	)
	teardown_receipt = {
		"run_serial":run_serial, "route":route, "reason":reason,
		"boss_retirement":boss_retirement, "boss_reference_cleared":boss == null,
		"active_enemy_group_count":get_tree().get_nodes_in_group("active_enemies").size(),
		"spawner_live":encounter.get("live", -1), "spawner_pooled":encounter.get("pooled", -1),
		"spawner_registered":(encounter.get("neighbor_registry", {}) as Dictionary).get("registered_count", -1),
		"world_active":world.session_active, "tree_paused":get_tree().paused,
		"runtime_retirement":transient_retirement.get("runtime_retirement",{}),
		"retired_attack_presentations":transient_retirement.get("retired_attack_presentations",0),
		"remaining_attack_presentations":post_counts.get("projectiles", -1),
		"audio_retirement":transient_retirement.get("audio_retirement",{}), "terminal_snapshot_preserved":not terminal_snapshot.is_empty(),
		"presentation_reset":presentation_reset,
		"reset_invariants":reset_invariants,
		"post_counts":post_counts,
		"completion_generation":_teardown_generation, "complete":teardown_complete,
	}
	_teardown_active = false
	return teardown_receipt.duplicate(true)

func _terminal_reset_invariants(destination: String) -> Dictionary:
	var animation := warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	var movement := warden.get_movement_snapshot()
	var warden_state := warden._mcp_state()
	var victory_vfx: Dictionary = warden_state.get("victory_vfx", {})
	var audio_state := audio_director._mcp_state()
	var counts := _profile_counts()
	var reset_expected := destination in ["title", "retry", "fresh_start", "profile_reset"]
	var idle_complete := (
		String(movement.get("locomotion_state", "")) == "idle"
		and (movement.get("velocity", Vector3.ONE) as Vector3).length_squared() <= 0.0001
		and (movement.get("movement_input", Vector2.ONE) as Vector2).length_squared() <= 0.0001
		and String(movement.get("dash_phase", "")) == "ready"
		and not bool(movement.get("invulnerable", true))
		and String(animation.get("semantic_state", "")) == "idle"
		and String(animation.get("resolved_clip", "")) == "Idle"
		and not bool((animation.get("terminal_lease", {}) as Dictionary).get("active", false))
		and not bool(victory_vfx.get("active", false))
		and not bool((audio_state.get("terminal_audio_lease", {}) as Dictionary).get("active", false))
		and int(audio_state.get("terminal_active_voice_count", -1)) == 0
	)
	return {
		"destination":destination,
		"reset_expected":reset_expected,
		"complete":idle_complete if reset_expected else true,
		"locomotion_state":movement.get("locomotion_state", ""),
		"movement_input":movement.get("movement_input", Vector2.ZERO),
		"planar_velocity":movement.get("velocity", Vector3.ZERO),
		"dash_phase":movement.get("dash_phase", ""),
		"dash_invulnerable":movement.get("invulnerable", false),
		"animation":animation,
		"victory_vfx":victory_vfx,
		"terminal_audio_lease":audio_state.get("terminal_audio_lease", {}),
		"terminal_voice_count":audio_state.get("terminal_active_voice_count", -1),
		"actors":{"enemies":counts.get("enemies", -1), "bosses":counts.get("bosses", -1), "projectiles":counts.get("projectiles", -1), "pickups":counts.get("pickups", -1)},
		"run_serial":run_serial,
	}

func _retire_transient_ownership(route: String, reason: String, generation: int) -> Dictionary:
	# Both ordinary lifecycle routes and the dense diagnostic reset enter this
	# exact ordering: stop update owners, synchronously invalidate weapon/combat
	# references, retire encounters, then retire generic presentation and audio.
	var runtime_retirement := world.retire_run_ownership(reason, generation)
	spawner.stop_encounter()
	var retired_attack_presentations := _retire_run_group("friendly_attack")
	var retired_pickups := _retire_run_group("reward_pickup")
	_active_pickups.clear()
	_active_pickup_count = 0
	var audio_retirement := audio_director.retire_run_ownership(route, generation)
	var remaining_counts := _profile_counts()
	return {
		"route": route, "reason": reason, "generation": generation,
		"runtime_retirement": runtime_retirement,
		"retired_attack_presentations": retired_attack_presentations,
		"remaining_attack_presentations":remaining_counts.get("projectiles", -1),
		"retired_pickups":retired_pickups,
		"remaining_pickups":remaining_counts.get("pickups", -1),
		"audio_retirement": audio_retirement,
		"complete":bool(runtime_retirement.get("complete", false)) and int(remaining_counts.get("projectiles", -1)) == 0 and int(remaining_counts.get("pickups", -1)) == 0,
	}

func _retire_run_group(group_name: StringName) -> int:
	var retired := 0
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		retired += 1
		if node is Node3D:
			(node as Node3D).visible = false
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.remove_from_group(group_name)
		if not node.is_queued_for_deletion():
			node.queue_free()
	return retired

func _transition(next_state: String) -> void:
	if run_state == next_state:
		return
	var previous := run_state
	run_state = next_state
	state_history.append(next_state)
	state_changed.emit(previous, next_state)

func _prepare_final_profile() -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"]:
		return
	_profile_active = false
	_profile_origin = "diagnostic_prepared"
	run_route_kind = "diagnostic_prepared"
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_elapsed = 0.0
	get_tree().paused = false
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
	experience = 0
	experience_threshold = 9999
	var build_receipt := inventory.prepare_legal_build("representative")
	spawner.configure_validation_roster([
		"mossling","wispbat","mossling","bone_slinger","grave_brute","mossling","wispbat","mossling",
		"bone_slinger","grave_brute","mossling","wispbat","mossling","bone_slinger","grave_brute","mossling",
		"wispbat","mossling","bone_slinger","grave_brute","mossling","wispbat","mossling","bone_slinger",
		"grave_brute","mossling","wispbat","mossling","bone_slinger","grave_brute","mossling","wispbat",
	])
	# The representative profile is the authored fifth wave, not Wave 4 with a
	# manually co-located boss. Preparation is still diagnostic and separate
	# from advancement, but every workload receipt now truthfully names the
	# Bellkeeper wave it is qualifying.
	wave_director.prepare_test_wave(4)
	var attack_count_before := world.attack_runtime.authorized_count
	var preparation := spawner.prepare_validation_density(32)
	var seeded_pickups := _seed_profile_pickups(6)
	if not is_instance_valid(boss):
		_spawn_bellkeeper()
	if is_instance_valid(boss):
		boss_snapshot = boss.get_snapshot().duplicate(true)
	_transition("boss")
	_validation_setup_generation += 1
	var encounter := spawner.get_snapshot()
	get_tree().paused = true
	validation_profile_receipt = {
		"accepted":bool(preparation.get("accepted",false)) and is_instance_valid(boss),
		"branch_id":"final_wave_bellkeeper_profile",
		"run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"requested_density":32,
		"resolved_density":int(encounter.get("live",0)),
		"enemy_roles":(encounter.get("roles",{}) as Dictionary).duplicate(true),
		"boss_state":boss_snapshot.get("state","absent"),
		"boss_phase":boss_snapshot.get("phase",0),
		"weapon_ranks":_profile_weapon_ranks(),
		"build_receipt":build_receipt.duplicate(true),
		"counts":_profile_counts(),
		"production_pickups_seeded":seeded_pickups,
		"production_pickup_scene":"res://scenes/gameplay/reward_pickup.tscn",
		"telegraph_admission":(encounter.get("telegraph_admission",{}) as Dictionary).duplicate(true),
		"neighbor_registry":(encounter.get("neighbor_registry",{}) as Dictionary).duplicate(true),
		"ordinary_light_budget":(encounter.get("ordinary_light_budget",{}) as Dictionary).duplicate(true),
		"pool_counts":{"active":encounter.get("live",0),"pooled":encounter.get("pooled",0)},
		"work_caps":_dense_work_caps(encounter),
		"workload":_profile_workload_receipt(encounter),
		"lifecycle":_lifecycle_counters(),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"requested_profile":"representative_final_wave_and_bellkeeper",
		"resolved_profile":"prepared_paused",
		"preparation_paused":get_tree().paused,
		"attacks_advanced_by_preparation":world.attack_runtime.authorized_count != attack_count_before,
		"terminal_state_advanced":result_committed,
		"advance_action_required":true,
		"reset_isolation_pending":true,
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_record_profile_cycle("prepare", validation_profile_receipt)
	_emit_snapshot()

func _advance_final_profile() -> void:
	if not OS.has_feature("editor") or not bool(validation_profile_receipt.get("accepted",false)) or _profile_active:
		return
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_elapsed = 0.0
	_profile_sample_counter_reads = 0
	_profile_active = true
	_profile_origin = "diagnostic_prepared"
	_profile_advance_generation += 1
	_profile_start_counts = _profile_counts()
	_profile_start_lifecycle = _lifecycle_counters()
	var cohort := spawner.begin_validation_profile_cohort(32, int(validation_profile_receipt.get("setup_generation", 0)))
	validation_profile_sample = {
		"status":"sampling", "branch_id":validation_profile_receipt.get("branch_id",""),
		"sample_kind":_profile_origin, "route_kind":run_route_kind,
		"run_serial":run_serial, "setup_generation":validation_profile_receipt.get("setup_generation",0),
		"advance_generation":_profile_advance_generation,
		"requested_density":32,
		"resolved_density":int(validation_profile_receipt.get("resolved_density", 0)),
		"boss_presence":is_instance_valid(boss),
		"weapon_ranks":_profile_weapon_ranks(),
		"window_seconds":_profile_duration,
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"start_counts":_profile_start_counts.duplicate(true),
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"cohort_start":cohort,
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"workload_start":_profile_workload_receipt(spawner.get_snapshot()),
	}
	get_tree().paused = false

func _arm_passive_ordinary_profile(wave_snapshot: Dictionary) -> void:
	if run_route_kind != "ordinary" or _profile_active or _profile_armed:
		return
	if int(wave_snapshot.get("wave", 0)) != 5 or int(wave_snapshot.get("diagnostic_jump_count", 0)) != 0:
		return
	_profile_armed = true
	_profile_arm_receipt = {
		"status":"armed_waiting_for_representative_workload",
		"run_serial":run_serial,
		"armed_process_frame":Engine.get_process_frames(),
		"armed_elapsed_seconds":run_elapsed,
		"required_density":{"minimum":PROFILE_DENSITY_MIN,"maximum":PROFILE_DENSITY_MAX},
		"wave":wave_snapshot.duplicate(true),
		"diagnostic_mutation":false,
		"rearm_count":_profile_rearm_count,
	}
	validation_profile_receipt = _profile_arm_receipt.duplicate(true)

func _representative_system_gate() -> Dictionary:
	_profile_gate_counter_reads += 1
	var counts := _profile_counts()
	var animation := warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	var audio := audio_director._mcp_state()
	var equipped: Array = inventory.get_snapshot().get("equipped_weapon_ids", [])
	var vfx_active := int(counts.get("projectiles", 0)) > 0 or int(counts.get("effects", 0)) > 0 or int(counts.get("wisp_handles", 0)) > 0
	return {
		"boss":is_instance_valid(boss) and bool(boss_snapshot.get("active", false)),
		"three_weapon_families":equipped.size() == 3,
		"pickups":int(counts.get("pickups", 0)) > 0,
		"hud":hud.visible,
		"animation":bool(animation.get("binding_valid", false)),
		"vfx":vfx_active,
		"lights":int(counts.get("lights", 0)) > 0,
		"audio":int(audio.get("active_effect_voices", 0)) > 0,
		"all_ready":is_instance_valid(boss) and bool(boss_snapshot.get("active", false)) and equipped.size() == 3 and int(counts.get("pickups", 0)) > 0 and hud.visible and bool(animation.get("binding_valid", false)) and vfx_active and int(counts.get("lights", 0)) > 0 and int(audio.get("active_effect_voices", 0)) > 0,
	}

func _try_begin_passive_ordinary_profile() -> void:
	if not _profile_armed or _profile_active or get_tree().paused or result_committed:
		return
	var wave_snapshot := wave_director.get_snapshot()
	if run_route_kind != "ordinary" or int(wave_snapshot.get("wave", 0)) != 5 or int(wave_snapshot.get("diagnostic_jump_count", 0)) != 0:
		_profile_armed = false
		return
	var live_density := int(spawner.get_profile_counters().get("live", 0))
	var systems := _representative_system_gate()
	_profile_arm_receipt["observed_density"] = live_density
	_profile_arm_receipt["representative_systems"] = systems.duplicate(true)
	if live_density < PROFILE_DENSITY_MIN or live_density > PROFILE_DENSITY_MAX or not bool(systems.get("all_ready", false)):
		return
	_profile_armed = false
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_elapsed = 0.0
	_profile_sample_counter_reads = 0
	_profile_active = true
	_profile_origin = "ordinary_final_wave_passive"
	_profile_start_counts = _profile_counts()
	_profile_start_lifecycle = _lifecycle_counters()
	_profile_minimum_enemy_workload = live_density
	_profile_maximum_enemy_workload = live_density
	validation_profile_sample = {
		"status":"sampling", "branch_id":"ordinary_final_wave_window",
		"sample_kind":_profile_origin, "route_kind":run_route_kind,
		"passive":true, "diagnostic_mutation":false,
		"run_serial":run_serial, "setup_generation":_validation_setup_generation,
		"window_seconds":_profile_duration,
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"start_counts":_profile_start_counts.duplicate(true),
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"wave_start":wave_snapshot.duplicate(true),
		"density_threshold_crossing":{"process_frame":Engine.get_process_frames(),"elapsed_seconds":run_elapsed,"live_enemies":live_density,"required_minimum":PROFILE_DENSITY_MIN,"required_maximum":PROFILE_DENSITY_MAX},
		"representative_systems":systems.duplicate(true),
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"workload_start":_profile_workload_receipt(spawner.get_snapshot()),
	}
	_emit_snapshot()

func _advance_profile_sample(delta: float) -> void:
	if not _profile_active or get_tree().paused:
		return
	_profile_sample_counter_reads += 1
	var live_density := int(spawner.get_profile_counters().get("live", 0))
	if _profile_samples_ms.is_empty():
		_profile_minimum_enemy_workload = live_density
		_profile_maximum_enemy_workload = live_density
	else:
		_profile_minimum_enemy_workload = mini(_profile_minimum_enemy_workload, live_density)
		_profile_maximum_enemy_workload = maxi(_profile_maximum_enemy_workload, live_density)
	var frame_ms := maxf(0.0,delta*1000.0)
	_profile_samples_ms.append(frame_ms)
	_profile_physics_samples_ms.append(maxf(0.0, float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0))
	_profile_elapsed += delta
	if _profile_elapsed < _profile_duration:
		return
	_profile_active = false
	var sorted := _profile_samples_ms.duplicate()
	sorted.sort()
	var sorted_physics := _profile_physics_samples_ms.duplicate()
	sorted_physics.sort()
	var sample_branch := String(validation_profile_sample.get("branch_id", ""))
	var sample_setup_generation := int(validation_profile_sample.get("setup_generation", _validation_setup_generation))
	var sample_start := validation_profile_sample.duplicate(true)
	var cohort := spawner.end_validation_profile_cohort("sample_complete") if _profile_origin.begins_with("diagnostic_") else {}
	var end_counts := _profile_counts()
	validation_profile_sample = {
		"status":"complete", "branch_id":sample_branch,
		"sample_kind":_profile_origin, "route_kind":run_route_kind,
		"passive":_profile_origin == "ordinary_final_wave_passive",
		"diagnostic_mutation":_profile_origin.begins_with("diagnostic_"),
		"run_serial":run_serial, "setup_generation":sample_setup_generation,
		"advance_generation":validation_profile_sample.get("advance_generation", _profile_advance_generation),
		"requested_density":validation_profile_sample.get("requested_density", _profile_start_counts.get("enemies", 0)),
		"resolved_density":validation_profile_sample.get("resolved_density", _profile_start_counts.get("enemies", 0)),
		"boss_presence":validation_profile_sample.get("boss_presence", is_instance_valid(boss)),
		"weapon_ranks":validation_profile_sample.get("weapon_ranks", _profile_weapon_ranks()),
		"representative_systems":sample_start.get("representative_systems", {}),
		"density_threshold_crossing":sample_start.get("density_threshold_crossing", {}),
		"sample_count":sorted.size(), "window_seconds":_profile_elapsed,
		"frame_ms":{"p50":_percentile(sorted,0.50),"p95":_percentile(sorted,0.95),"p99":_percentile(sorted,0.99),"worst":sorted.back() if not sorted.is_empty() else 0.0},
		"physics_ms":{"p50":_percentile(sorted_physics,0.50),"p95":_percentile(sorted_physics,0.95),"p99":_percentile(sorted_physics,0.99),"worst":sorted_physics.back() if not sorted_physics.is_empty() else 0.0},
		"start_counts":_profile_start_counts.duplicate(true),
		"end_counts":end_counts.duplicate(true), "counts":end_counts.duplicate(true),
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"end_lifecycle":_lifecycle_counters(),
		"cohort":cohort,
		"requested_enemy_workload":int(cohort.get("requested", _profile_start_counts.get("enemies", 0))),
		"start_enemy_workload":int(cohort.get("start", _profile_start_counts.get("enemies", 0))),
		"minimum_enemy_workload":int(cohort.get("minimum", _profile_minimum_enemy_workload)),
		"maximum_enemy_workload":int(cohort.get("requested", _profile_maximum_enemy_workload)),
		"end_enemy_workload":int(cohort.get("end_live", end_counts.get("enemies", 0))),
		"replenished_enemy_count":int(cohort.get("replenished", 0)),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"wave_end":wave_director.get_snapshot().duplicate(true),
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"workload_start":sample_start.get("workload_start", _profile_workload_receipt(spawner.get_snapshot())),
		"workload_end":_profile_workload_receipt(spawner.get_snapshot()),
		"observation_work":_profile_observation_work_receipt(),
		"route_qualification":_route_qualification(wave_director.get_snapshot()),
	}
	validation_profile_sample["qualification"] = _profile_qualification(validation_profile_sample)
	_record_profile_matrix_sample(validation_profile_sample)
	_record_profile_cycle("advance", validation_profile_sample)
	if _profile_origin == "ordinary_final_wave_passive":
		_record_ordinary_profile_sample(validation_profile_sample)
	if _profile_origin.begins_with("diagnostic_"):
		get_tree().paused = true
	elif not bool((validation_profile_sample.get("qualification", {}) as Dictionary).get("density_qualified", false)) and run_state == "boss" and not result_committed:
		_profile_rearm_count += 1
		_profile_armed = true
		_profile_arm_receipt = {
			"status":"rearmed_after_unqualified_window",
			"run_serial":run_serial,
			"rearm_count":_profile_rearm_count,
			"previous_sample":validation_profile_sample.duplicate(true),
			"required_density":{"minimum":PROFILE_DENSITY_MIN,"maximum":PROFILE_DENSITY_MAX},
		}
		validation_profile_receipt = _profile_arm_receipt.duplicate(true)
	_emit_snapshot()

func _reset_final_profile() -> void:
	if not OS.has_feature("editor"):
		return
	var source_run_serial := run_serial
	var source_sample := validation_profile_sample.duplicate(true)
	_validation_setup_generation += 1
	var setup_generation := _validation_setup_generation
	_profile_active = false
	# Retire the public record immediately beside the active-owner flag. Any
	# teardown callback or snapshot emitted below therefore sees one state.
	validation_profile_sample = _profile_reset_sample(
		source_sample,
		source_run_serial,
		run_serial + 1,
		setup_generation,
		"tester_final_profile_reset"
	)
	_profile_origin = ""
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_elapsed = 0.0
	spawner.end_validation_profile_cohort("profile_reset")
	get_tree().paused = false
	var requested_counts := _profile_counts()
	var retirement := _teardown_run("validation_profile_reset", "validation_profile_reset")
	_next_baseline_reason = "validation_profile_reset"
	_begin_run()
	# _begin_run() has authoritatively restored the ordinary active state, but
	# InputContextRouter normally observes that state on its next process tick.
	# Qualification samples happen inside this same input dispatch, so synchronize
	# the live router before serializing the immediate reset boundary.
	input_router._sync_context()
	var immediate_input_context := input_router.context
	var counts := _profile_counts()
	validation_profile_sample["run_serial"] = run_serial
	validation_profile_sample["ordinary_run_counts"] = counts.duplicate(true)
	validation_profile_sample["ordinary_run_state"] = run_state
	validation_profile_sample["ordinary_input_context"] = immediate_input_context
	validation_profile_sample["reset_phase"] = "ordinary_run_ready"
	validation_profile_receipt = {
		"accepted":true, "reset":true, "branch_id":"final_wave_bellkeeper_profile",
		"source_run_serial":source_run_serial, "run_serial":run_serial, "setup_generation":setup_generation,
		"requested_density":requested_counts.get("enemies",-1), "resolved_density":counts.get("enemies",-1),
		"requested_profile":"reset", "resolved_profile":"ordinary_run_ready",
		"requested_counts": requested_counts, "resolved_retirement": retirement,
		"post_reset_counts":counts, "counts":counts,
		"reset_isolation":_counts_are_isolated(counts),
		"route_kind":run_route_kind,
		"input_context":immediate_input_context,
		"wave_route":_route_qualification(wave_director.get_snapshot()),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"lifecycle":_lifecycle_counters(),
		"next_frame_isolation_pending": true,
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_record_profile_cycle("reset_immediate", validation_profile_receipt)
	_emit_snapshot()
	call_deferred("_capture_profile_next_frame_isolation", setup_generation, run_serial)

func _profile_reset_sample(source_sample: Dictionary, source_run_serial: int, next_run_serial: int, setup_generation: int, reason: String) -> Dictionary:
	var source_status := String(source_sample.get("status", "idle"))
	var source_branch := String(source_sample.get("branch_id", validation_profile_receipt.get("branch_id", "final_wave_bellkeeper_profile")))
	return {
		"status":"reset",
		"retired":true,
		"reset_reason":reason,
		"reset_phase":"retired_before_ordinary_run",
		"interrupted":source_status == "sampling",
		"completed_before_reset":source_status == "complete",
		"source_status":source_status,
		"source_branch_id":source_branch,
		"source_run_serial":source_run_serial,
		"branch_id":source_branch,
		"sample_kind":"reset",
		"route_kind":"ordinary",
		"run_serial":next_run_serial,
		"setup_generation":setup_generation,
		"active_workload_owner":false,
		"requested_density":0,
		"resolved_density":0,
		"requested_enemy_workload":0,
		"start_enemy_workload":0,
		"minimum_enemy_workload":0,
		"maximum_enemy_workload":0,
		"end_enemy_workload":0,
		"sample_count":0,
		"window_seconds":0.0,
		"cohort":{"requested":0,"start":0,"minimum":0,"maximum":0,"end_live":0,"replenished":0,"active":false},
		"frame_ms":{"p50":0.0,"p95":0.0,"p99":0.0,"worst":0.0},
		"physics_ms":{"p50":0.0,"p95":0.0,"p99":0.0,"worst":0.0},
		"observation_work":{"sampled_frame_scene_scans":0,"sampled_frame_group_inventories":0,"sampled_frame_counter_read_count":0},
		"qualification":{"qualified":false,"ordinary_route_qualified":false,"density_qualified":false,"reasons":["retired_by_profile_reset"]},
		"reset_process_frame":Engine.get_process_frames(),
	}

func _capture_profile_next_frame_isolation(setup_generation: int, expected_run_serial: int) -> void:
	await get_tree().process_frame
	if setup_generation != _validation_setup_generation or expected_run_serial != run_serial:
		return
	# The process-frame signal resumes before child _process callbacks. Sample the
	# router only after explicitly reconciling it with this frame's authoritative
	# run state, rather than inheriting the immediate receipt value.
	input_router._sync_context()
	var next_frame_input_context := input_router.context
	var next_counts := _profile_counts()
	validation_profile_receipt.next_frame_counts = next_counts
	validation_profile_receipt.next_frame_isolation = _counts_are_isolated(next_counts)
	validation_profile_receipt.next_frame_lifecycle = _lifecycle_counters()
	validation_profile_receipt.next_frame_input_context = next_frame_input_context
	validation_profile_receipt.next_frame_isolation_pending = false
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_record_profile_cycle("reset_next_frame", validation_profile_receipt)
	_emit_snapshot()

func _record_profile_cycle(phase: String, receipt: Dictionary) -> void:
	var entry := receipt.duplicate(true)
	entry["receipt_phase"] = phase
	validation_profile_cycles.append(entry)
	while validation_profile_cycles.size() > 16:
		validation_profile_cycles.pop_front()

func _profile_cycle_comparison() -> Dictionary:
	return _evaluate_ordinary_profile_cycles(ordinary_profile_cycles, true)

func _evaluate_ordinary_profile_cycles(records: Array, include_diagnostic_audit: bool = false) -> Dictionary:
	var qualified: Array[Dictionary] = []
	var audited: Array[Dictionary] = []
	var seen_serials: Dictionary = {}
	for value in records:
		var cycle: Dictionary = value
		var reasons: Array[String] = []
		var sample: Dictionary = cycle.get("sample", {})
		var sample_qualification: Dictionary = sample.get("qualification", {})
		var terminal: Dictionary = cycle.get("terminal", {})
		var result: Dictionary = cycle.get("result", {})
		var retry: Dictionary = cycle.get("retry", {})
		var baseline: Dictionary = cycle.get("next_baseline", {})
		var serial := int(cycle.get("run_serial", -1))
		if seen_serials.has(serial): reasons.append("repeated_run_serial")
		seen_serials[serial] = true
		if not bool(sample_qualification.get("ordinary_route_qualified", false)): reasons.append("ordinary_native_sample_not_qualified")
		if int(sample.get("run_serial", -2)) != serial: reasons.append("sample_run_serial_mismatch")
		if not bool(terminal.get("real_terminal", false)): reasons.append("real_terminal_missing")
		if int(terminal.get("commit_count", 0)) != 1: reasons.append("terminal_commit_count_not_one")
		if int(terminal.get("run_serial", -2)) != serial: reasons.append("terminal_run_serial_mismatch")
		if not bool(result.get("presented", false)): reasons.append("result_not_presented")
		if String(result.get("outcome", "")) != String(terminal.get("outcome", "")): reasons.append("result_outcome_mismatch")
		if not bool(retry.get("player_caused", false)) or String(retry.get("source_state", "")) != "result": reasons.append("player_result_retry_missing")
		if not bool(baseline.get("complete", false)): reasons.append("next_ordinary_baseline_missing")
		if int(baseline.get("source_run_serial", -2)) != serial or int(baseline.get("run_serial", -1)) <= serial: reasons.append("next_baseline_serial_mismatch")
		if String(baseline.get("route_kind", "")) != "ordinary" or String(baseline.get("run_state", "")) != "active": reasons.append("next_baseline_not_ordinary_active")
		if String(baseline.get("immediate_input_context", "")) != "active" or String(baseline.get("next_frame_input_context", "")) != "active": reasons.append("next_baseline_context_stale")
		if not bool(baseline.get("isolated", false)): reasons.append("next_baseline_not_isolated")
		var audit := cycle.duplicate(true)
		audit["qualified_complete_cycle"] = reasons.is_empty()
		audit["rejection_reasons"] = reasons
		audited.append(audit)
		if reasons.is_empty(): qualified.append(audit)
	var aggregate_cycles := qualified.slice(maxi(0, qualified.size() - 3), qualified.size())
	var growth := _profile_cycle_growth(aggregate_cycles)
	var diagnostic := _diagnostic_profile_cycle_comparison() if include_diagnostic_audit else {}
	return {
		"identity":"mournlight.ordinary_native_retry_cycles.v1",
		"required_cycle_count":3,
		"completed_cycle_count":qualified.size(),
		"cycles":aggregate_cycles,
		"session_records":audited,
		"three_cycle_ready":qualified.size() >= 3,
		"stale_reset_context_cycle_count":_count_stale_ordinary_cycle_contexts(aggregate_cycles),
		"three_cycle_context_truthful":qualified.size() >= 3 and _count_stale_ordinary_cycle_contexts(aggregate_cycles) == 0,
		"growth":growth,
		"three_cycle_no_growth":qualified.size() >= 3 and bool(growth.get("no_structural_growth", false)),
		"diagnostic_reset_audit":diagnostic,
		"diagnostic_cycles_excluded":true,
	}

func _ordinary_profile_contract_checks() -> Dictionary:
	var live_records_before := ordinary_profile_cycles.duplicate(true)
	var hardware_sample := _contract_ordinary_profile_sample("hardware", 1920, 1080)
	var software_sample := _contract_ordinary_profile_sample("software", 1920, 1080)
	var low_resolution_sample := _contract_ordinary_profile_sample("hardware", 1280, 720)
	var diagnostic_sample := hardware_sample.duplicate(true)
	diagnostic_sample["passive"] = false
	diagnostic_sample["diagnostic_mutation"] = true
	diagnostic_sample["qualification"] = _profile_qualification(diagnostic_sample)
	var complete_records := [
		_contract_ordinary_profile_cycle(101, hardware_sample),
		_contract_ordinary_profile_cycle(102, hardware_sample),
		_contract_ordinary_profile_cycle(103, hardware_sample),
	]
	var complete := _evaluate_ordinary_profile_cycles(complete_records)
	var missing_retry := _contract_ordinary_profile_cycle(104, hardware_sample)
	missing_retry.erase("retry")
	var missing_retry_result := _evaluate_ordinary_profile_cycles([missing_retry])
	var repeated := _evaluate_ordinary_profile_cycles([
		_contract_ordinary_profile_cycle(105, hardware_sample),
		_contract_ordinary_profile_cycle(105, hardware_sample),
	])
	var live_unchanged := ordinary_profile_cycles == live_records_before
	var all_checks := (
		bool(complete.get("three_cycle_ready", false))
		and bool(complete.get("three_cycle_context_truthful", false))
		and bool(complete.get("three_cycle_no_growth", false))
		and not bool((software_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false))
		and not bool((low_resolution_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false))
		and not bool((diagnostic_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false))
		and int(missing_retry_result.get("completed_cycle_count", -1)) == 0
		and int(repeated.get("completed_cycle_count", -1)) == 1
		and live_unchanged
	)
	return {
		"identity":"mournlight.ordinary_native_retry_predicate_checks.v1",
		"three_distinct_complete_cycles_accepted":bool(complete.get("three_cycle_ready", false)),
		"software_renderer_rejected":not bool((software_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false)),
		"sub_1920x1080_rejected":not bool((low_resolution_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false)),
		"diagnostic_sample_rejected":not bool((diagnostic_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false)),
		"missing_player_retry_rejected":int(missing_retry_result.get("completed_cycle_count", -1)) == 0,
		"repeated_run_serial_rejected":int(repeated.get("completed_cycle_count", -1)) == 1,
		"live_records_mutated":not live_unchanged,
		"all_checks_pass":all_checks,
	}

func _contract_ordinary_profile_sample(renderer_classification: String, viewport_width: int, viewport_height: int) -> Dictionary:
	var hardware := renderer_classification == "hardware"
	var sample := {
		"passive":true,
		"diagnostic_mutation":false,
		"route_kind":"ordinary",
		"run_serial":1,
		"wave_start":{"wave":5,"diagnostic_jump_count":0},
		"representative_systems":{"all_ready":true},
		"boss_presence":true,
		"weapon_ranks":[{"weapon_id":"warden_lantern","rank":4},{"weapon_id":"gravespade","rank":3},{"weapon_id":"wandering_wisps","rank":2}],
		"requested_enemy_workload":32,
		"start_enemy_workload":32,
		"minimum_enemy_workload":30,
		"maximum_enemy_workload":34,
		"end_enemy_workload":31,
		"frame_ms":{"p95":12.0},
		"viewport":{"width":viewport_width,"height":viewport_height,"resolution_qualified":viewport_width >= 1920 and viewport_height >= 1080},
		"renderer":{"classification":renderer_classification,"identity_complete":true,"hardware_backed":hardware,"hardware_qualification_eligible":hardware},
	}
	sample["qualification"] = _profile_qualification(sample)
	return sample

func _contract_ordinary_profile_cycle(serial: int, source_sample: Dictionary) -> Dictionary:
	var sample := source_sample.duplicate(true)
	sample["run_serial"] = serial
	var lifecycle := {
		"scene_tree_nodes":100,"object_count":200,"orphan_nodes":0,"static_memory_bytes":1000000,
		"input_action_count":40,"owned_signal_bindings":5,"enemy_active":0,"enemy_pooled":40,
		"projectiles":0,"pickups":0,"effects":0,"light_count":12,"audio_voices":0,
		"active_attack_ledgers":0,
	}
	return {
		"run_serial":serial,
		"sample":sample,
		"sample_attempts":[sample.duplicate(true)],
		"terminal":{"run_serial":serial,"outcome":"victory","route_kind":"ordinary","commit_count":1,"real_terminal":true},
		"result":{"presented":true,"outcome":"victory"},
		"retry":{"player_caused":true,"source_state":"result"},
		"next_baseline":{"complete":true,"source_run_serial":serial,"run_serial":serial + 1,"route_kind":"ordinary","run_state":"active","immediate_input_context":"active","next_frame_input_context":"active","isolated":true,"next_frame_lifecycle":lifecycle},
	}

func _diagnostic_profile_cycle_comparison() -> Dictionary:
	var completed: Array[Dictionary] = []
	var current: Dictionary = {}
	for entry in validation_profile_cycles:
		var phase := String(entry.get("receipt_phase", ""))
		if phase == "prepare":
			current = {
				"prepared_run_serial":entry.get("run_serial", -1),
				"prepare_setup_generation":entry.get("setup_generation", -1),
					"requested_density":entry.get("requested_density", -1),
					"resolved_density":entry.get("resolved_density", -1),
					"lifecycle":(entry.get("lifecycle", {}) as Dictionary).duplicate(true),
			}
		elif phase == "advance" and not current.is_empty():
			current["sample"] = {
				"sample_count":entry.get("sample_count", 0),
				"window_seconds":entry.get("window_seconds", 0.0),
				"frame_ms":(entry.get("frame_ms", {}) as Dictionary).duplicate(true),
				"physics_ms":(entry.get("physics_ms", {}) as Dictionary).duplicate(true),
				"renderer":(entry.get("renderer", {}) as Dictionary).duplicate(true),
				"requested_enemy_workload":entry.get("requested_enemy_workload", -1),
				"start_enemy_workload":entry.get("start_enemy_workload", -1),
				"minimum_enemy_workload":entry.get("minimum_enemy_workload", -1),
				"end_enemy_workload":entry.get("end_enemy_workload", -1),
					"replenished_enemy_count":entry.get("replenished_enemy_count", 0),
					"start_lifecycle":(entry.get("start_lifecycle", {}) as Dictionary).duplicate(true),
					"end_lifecycle":(entry.get("end_lifecycle", {}) as Dictionary).duplicate(true),
			}
		elif phase == "reset_immediate" and not current.is_empty():
			var immediate_lifecycle: Dictionary = entry.get("lifecycle", {})
			current["reset"] = {
				"source_run_serial":entry.get("source_run_serial", -1),
				"next_run_serial":entry.get("run_serial", -1),
				"reset_setup_generation":entry.get("setup_generation", -1),
				"immediate_isolation":entry.get("reset_isolation", false),
				"immediate_input_context":entry.get("input_context", immediate_lifecycle.get("input_context", "unavailable")),
				"immediate_lifecycle":immediate_lifecycle.duplicate(true),
			}
		elif phase == "reset_next_frame" and not current.is_empty():
			var reset: Dictionary = current.get("reset", {})
			var next_frame_lifecycle: Dictionary = entry.get("next_frame_lifecycle", {})
			reset["next_frame_isolation"] = entry.get("next_frame_isolation", false)
			reset["next_frame_counts"] = (entry.get("next_frame_counts", {}) as Dictionary).duplicate(true)
			reset["next_frame_input_context"] = entry.get("next_frame_input_context", next_frame_lifecycle.get("input_context", "unavailable"))
			reset["next_frame_lifecycle"] = next_frame_lifecycle.duplicate(true)
			current["reset"] = reset
			current["complete"] = true
			completed.append(current.duplicate(true))
			current.clear()
	while completed.size() > 3:
		completed.pop_front()
	var stale_reset_context_cycle_count := 0
	for cycle in completed:
		var reset: Dictionary = cycle.get("reset", {})
		if String(reset.get("immediate_input_context", "")) != "active" or String(reset.get("next_frame_input_context", "")) != "active":
			stale_reset_context_cycle_count += 1
	var growth := _profile_cycle_growth(completed)
	return {
		"required_cycle_count":3,
		"completed_cycle_count":completed.size(),
		"cycles":completed,
		"three_cycle_ready":completed.size() == 3,
		"stale_reset_context_cycle_count":stale_reset_context_cycle_count,
		"three_cycle_context_truthful":completed.size() == 3 and stale_reset_context_cycle_count == 0,
		"growth":growth,
		"three_cycle_no_growth":completed.size() == 3 and bool(growth.get("no_structural_growth", false)),
	}

func _profile_cycle_growth(completed: Array[Dictionary]) -> Dictionary:
	if completed.is_empty():
		return {"ready":false}
	var first_reset: Dictionary = _cycle_baseline_lifecycle(completed.front())
	var last_reset: Dictionary = _cycle_baseline_lifecycle(completed.back())
	if first_reset.is_empty() or last_reset.is_empty():
		return {"ready":false}
	var node_growth := int(last_reset.get("scene_tree_nodes", 0)) - int(first_reset.get("scene_tree_nodes", 0))
	var object_growth := int(last_reset.get("object_count", 0)) - int(first_reset.get("object_count", 0))
	var orphan_growth := int(last_reset.get("orphan_nodes", 0)) - int(first_reset.get("orphan_nodes", 0))
	var memory_growth := int(last_reset.get("static_memory_bytes", 0)) - int(first_reset.get("static_memory_bytes", 0))
	var input_growth := int(last_reset.get("input_action_count", 0)) - int(first_reset.get("input_action_count", 0))
	var signal_growth := int(last_reset.get("owned_signal_bindings", 0)) - int(first_reset.get("owned_signal_bindings", 0))
	var enemy_active_growth := int(last_reset.get("enemy_active", 0)) - int(first_reset.get("enemy_active", 0))
	var enemy_pooled_growth := int(last_reset.get("enemy_pooled", 0)) - int(first_reset.get("enemy_pooled", 0))
	var projectile_growth := int(last_reset.get("projectiles", 0)) - int(first_reset.get("projectiles", 0))
	var pickup_growth := int(last_reset.get("pickups", 0)) - int(first_reset.get("pickups", 0))
	var effect_growth := int(last_reset.get("effects", 0)) - int(first_reset.get("effects", 0))
	var light_growth := int(last_reset.get("light_count", 0)) - int(first_reset.get("light_count", 0))
	var audio_growth := int(last_reset.get("audio_voices", 0)) - int(first_reset.get("audio_voices", 0))
	var active_attack_growth := int(last_reset.get("active_attack_ledgers", 0)) - int(first_reset.get("active_attack_ledgers", 0))
	return {
		"ready":completed.size() == 3,
		"node_growth":node_growth,
		"object_growth":object_growth,
		"orphan_growth":orphan_growth,
		"static_memory_growth_bytes":memory_growth,
		"input_action_growth":input_growth,
		"owned_signal_binding_growth":signal_growth,
		"enemy_active_growth":enemy_active_growth,
		"enemy_pooled_growth":enemy_pooled_growth,
		"projectile_growth":projectile_growth,
		"pickup_growth":pickup_growth,
		"effect_growth":effect_growth,
		"light_growth":light_growth,
		"audio_voice_growth":audio_growth,
		"active_attack_ledger_growth":active_attack_growth,
		"no_structural_growth":node_growth <= 0 and orphan_growth <= 0 and input_growth == 0 and signal_growth == 0 and enemy_active_growth <= 0 and enemy_pooled_growth <= 0 and projectile_growth <= 0 and pickup_growth <= 0 and effect_growth <= 0 and light_growth <= 0 and audio_growth <= 0 and active_attack_growth <= 0,
		"memory_observational_only":true,
	}

func _cycle_baseline_lifecycle(cycle: Dictionary) -> Dictionary:
	var ordinary_baseline: Dictionary = cycle.get("next_baseline", {})
	if not ordinary_baseline.is_empty():
		return ordinary_baseline.get("next_frame_lifecycle", {})
	return (cycle.get("reset", {}) as Dictionary).get("next_frame_lifecycle", {})

func _count_stale_ordinary_cycle_contexts(cycles: Array[Dictionary]) -> int:
	var stale := 0
	for cycle in cycles:
		var baseline: Dictionary = cycle.get("next_baseline", {})
		if String(baseline.get("immediate_input_context", "")) != "active" or String(baseline.get("next_frame_input_context", "")) != "active":
			stale += 1
	return stale

func _record_ordinary_profile_sample(sample: Dictionary) -> void:
	var serial := int(sample.get("run_serial", -1))
	var index := _ordinary_profile_cycle_index(serial)
	if index < 0:
		ordinary_profile_cycles.append({"run_serial":serial,"sample_attempts":[]})
		index = ordinary_profile_cycles.size() - 1
	var attempts: Array = ordinary_profile_cycles[index].get("sample_attempts", [])
	attempts.append(sample.duplicate(true))
	while attempts.size() > 3:
		attempts.pop_front()
	ordinary_profile_cycles[index]["sample_attempts"] = attempts
	if bool((sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false)):
		ordinary_profile_cycles[index]["sample"] = sample.duplicate(true)
	while ordinary_profile_cycles.size() > 8:
		ordinary_profile_cycles.pop_front()

func _update_ordinary_profile_cycle(source_run_serial: int, phase: String, payload: Dictionary) -> void:
	var index := _ordinary_profile_cycle_index(source_run_serial)
	if index < 0:
		return
	ordinary_profile_cycles[index][phase] = payload.duplicate(true)

func _ordinary_profile_cycle_index(source_run_serial: int) -> int:
	for index in range(ordinary_profile_cycles.size() - 1, -1, -1):
		if int(ordinary_profile_cycles[index].get("run_serial", -1)) == source_run_serial:
			return index
	return -1

func _record_ordinary_retry_baseline(source_run_serial: int) -> void:
	input_router._sync_context()
	var baseline: Dictionary = validation_retry_baselines.back().duplicate(true) if not validation_retry_baselines.is_empty() else {}
	baseline["source_run_serial"] = source_run_serial
	baseline["route_kind"] = run_route_kind
	baseline["immediate_input_context"] = input_router.context
	baseline["immediate_lifecycle"] = _lifecycle_counters()
	baseline["complete"] = false
	_update_ordinary_profile_cycle(source_run_serial, "next_baseline", baseline)
	call_deferred("_capture_ordinary_retry_next_frame_baseline", source_run_serial, run_serial, _retry_baseline_generation)

func _capture_ordinary_retry_next_frame_baseline(source_run_serial: int, expected_run_serial: int, expected_generation: int) -> void:
	await get_tree().process_frame
	if run_serial != expected_run_serial or _retry_baseline_generation != expected_generation:
		return
	input_router._sync_context()
	var index := _ordinary_profile_cycle_index(source_run_serial)
	if index < 0:
		return
	var baseline: Dictionary = ordinary_profile_cycles[index].get("next_baseline", {})
	var counts := _profile_counts()
	baseline["next_frame_input_context"] = input_router.context
	baseline["next_frame_lifecycle"] = _lifecycle_counters()
	baseline["next_frame_counts"] = counts
	baseline["isolated"] = _counts_are_isolated(counts) and bool((_terminal_reset_invariants("retry") as Dictionary).get("complete", false))
	baseline["complete"] = true
	ordinary_profile_cycles[index]["next_baseline"] = baseline
	_emit_snapshot()

func _record_profile_matrix_sample(sample: Dictionary) -> void:
	var entry := sample.duplicate(true)
	entry["matrix_density"] = int(sample.get("requested_density", sample.get("requested_enemy_workload", 0)))
	validation_profile_matrix_samples.append(entry)
	while validation_profile_matrix_samples.size() > 10:
		validation_profile_matrix_samples.pop_front()

func _profile_matrix_snapshot() -> Dictionary:
	var latest_by_density: Dictionary = {}
	for sample in validation_profile_matrix_samples:
		latest_by_density[int(sample.get("matrix_density", 0))] = sample.duplicate(true)
	var missing: Array[int] = []
	for required_density in [3, 5, 10, 18, 32]:
		if not latest_by_density.has(required_density):
			missing.append(required_density)
	return {
		"identity":"mournlight.native_dense_profile_matrix.v1",
		"editor_only":OS.has_feature("editor"),
		"release_export_available":false,
		"required_densities":[3,5,10,18,32],
		"latest_by_density":latest_by_density,
		"missing_densities":missing,
		"complete":missing.is_empty(),
		"prepare_and_advance_separate":true,
		"advance_generation":_profile_advance_generation,
		"native_qualification_requires":{"minimum_viewport":[1920,1080],"non_software_renderer":true},
	}

func _counts_are_isolated(counts: Dictionary) -> bool:
	return (
		int(counts.get("enemies", -1)) == 0
		and int(counts.get("bosses", -1)) == 0
		and int(counts.get("projectiles", -1)) == 0
		and int(counts.get("pickups", -1)) == 0
		and int(counts.get("effects", -1)) == 0
		and int(counts.get("wisp_handles", -1)) == 0
		and int(counts.get("wisp_interval_targets", -1)) == 0
		and int(counts.get("active_attack_ledgers", -1)) == 0
		and int(counts.get("registered_neighbors", -1)) == 0
		and int(counts.get("audio_voices", -1)) == 0
	)

func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(ceil((sorted.size()-1)*fraction)),0,sorted.size()-1)]

func _profile_weapon_ranks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon in inventory.get_snapshot().get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			result.append({"weapon_id":weapon.get("weapon_id",""),"rank":weapon.get("rank",0)})
	return result

func _profile_counts() -> Dictionary:
	var encounter := spawner.get_profile_counters()
	var projectile_count := lantern_runtime.active_presentation_count + gravespade_runtime.active_presentation_count + wisps_runtime.active_wisp_count
	var lights := _profile_static_light_count + int(encounter.get("active_lights", 0)) + _active_pickup_count + wisps_runtime.active_wisp_count + (1 if is_instance_valid(boss) else 0)
	var audio_voices := audio_director.active_effect_voice_count()
	return {
		"enemies":int(encounter.get("live",0)),
		"pooled_enemies":int(encounter.get("pooled",0)),
		"bosses":1 if is_instance_valid(boss) else 0,
		"projectiles":projectile_count,
		"pickups":_active_pickup_count,
		"pickup_production_ready":spawner.reward_dropped.is_connected(_on_reward_dropped),
		"effects":_active_effect_count,
		"lights":lights, "audio_voices":audio_voices,
		"telegraph_active":int(encounter.get("telegraph_active", 0)),
		"neighbor_candidate_visits":int(encounter.get("neighbor_candidate_visits", 0)),
		"registered_neighbors":int(encounter.get("registered_neighbors", 0)),
		"wisp_handles":wisps_runtime.active_wisp_count,
		"wisp_interval_targets":wisps_runtime._target_next_hit_time.size(),
		"active_attack_ledgers":world.attack_runtime._hit_ledgers.size(),
		"counter_source":"lifecycle_owners",
	}

func _bounded_static_light_snapshot() -> int:
	_profile_setup_scene_scans += 1
	var count := 0
	for node in world.find_children("*", "Light3D", true, false):
		if node is Light3D and node.is_visible_in_tree():
			count += 1
	return count

func _profile_observation_work_receipt() -> Dictionary:
	return {
		"bounded_setup_scene_scans":_profile_setup_scene_scans,
		"sampled_frame_scene_scans":0,
		"sampled_frame_group_inventories":0,
		"sampled_frame_counter_read_count":_profile_sample_counter_reads,
		"arming_gate_counter_read_count":_profile_gate_counter_reads,
		"counter_sources":["encounter_lifecycle_owners","weapon_presentation_owners","reward_pickup_owners","audio_fixed_voice_pool","wisp_runtime_owners"],
		"setup_and_finalization_excluded_from_frame_samples":true,
	}

func _profile_viewport_receipt() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	return {
		"width":int(viewport_size.x), "height":int(viewport_size.y),
		"target_width":1920, "target_height":1080,
		"resolution_qualified":int(viewport_size.x) >= 1920 and int(viewport_size.y) >= 1080,
	}

func _profile_renderer_receipt() -> Dictionary:
	var adapter_name := RenderingServer.get_video_adapter_name()
	var adapter_vendor := RenderingServer.get_video_adapter_vendor()
	var rendering_driver := RenderingServer.get_current_rendering_driver_name()
	var adapter_api_version := RenderingServer.get_video_adapter_api_version()
	var driver_info := OS.get_video_adapter_driver_info()
	var identity_text := (adapter_name + " " + adapter_vendor + " " + rendering_driver + " " + adapter_api_version + " " + str(driver_info)).to_lower()
	var software_renderer := false
	for marker in ["llvmpipe", "softpipe", "swiftshader", "lavapipe", "software rasterizer"]:
		software_renderer = software_renderer or identity_text.contains(marker)
	var identity_complete := not adapter_name.strip_edges().is_empty() and not adapter_vendor.strip_edges().is_empty() and not adapter_api_version.strip_edges().is_empty()
	return {
		"rendering_method":RenderingServer.get_current_rendering_method(),
		"rendering_driver":rendering_driver,
		"adapter_name":adapter_name,
		"adapter_vendor":adapter_vendor,
		"adapter_type":int(RenderingServer.get_video_adapter_type()),
		"adapter_api_version":adapter_api_version,
		"adapter_driver_info":driver_info,
		"identity_complete":identity_complete,
		"software_renderer":software_renderer,
		"hardware_backed":identity_complete and not software_renderer,
		"classification":"software" if software_renderer else ("hardware" if identity_complete else "unknown"),
		"hardware_qualification_eligible":identity_complete and not software_renderer,
		"project_name":String(ProjectSettings.get_setting("application/config/name", "Mournlight")),
		"profile_identity":"mournlight.release.final_wave.v1",
	}

func _profile_qualification(sample: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	var renderer: Dictionary = sample.get("renderer", {})
	var viewport: Dictionary = sample.get("viewport", {})
	var frame_ms: Dictionary = sample.get("frame_ms", {})
	if not bool(viewport.get("resolution_qualified", false)):
		reasons.append("viewport_below_1920x1080")
	if not bool(renderer.get("identity_complete", false)):
		reasons.append("renderer_identity_incomplete")
	if not bool(renderer.get("hardware_backed", false)):
		reasons.append("software_or_unknown_renderer")
	var requested_workload := int(sample.get("requested_enemy_workload", -1))
	var start_workload := int(sample.get("start_enemy_workload", -1))
	var minimum_workload := int(sample.get("minimum_enemy_workload", -1))
	var maximum_workload := int(sample.get("maximum_enemy_workload", -1))
	var end_workload := int(sample.get("end_enemy_workload", -1))
	var passive_ordinary := bool(sample.get("passive", false)) and not bool(sample.get("diagnostic_mutation", true))
	if passive_ordinary:
		var representative_systems: Dictionary = sample.get("representative_systems", {})
		var wave_start: Dictionary = sample.get("wave_start", {})
		if String(sample.get("route_kind", "")) != "ordinary" or int(wave_start.get("wave", 0)) != 5 or int(wave_start.get("diagnostic_jump_count", -1)) != 0:
			reasons.append("ordinary_zero_jump_fifth_wave_missing")
		if not bool(representative_systems.get("all_ready", false)):
			reasons.append("representative_systems_not_simultaneously_active")
		if not bool(sample.get("boss_presence", false)) or (sample.get("weapon_ranks", []) as Array).size() != 3:
			reasons.append("boss_or_three_weapon_families_missing")
		if start_workload < PROFILE_DENSITY_MIN or start_workload > PROFILE_DENSITY_MAX or end_workload < PROFILE_DENSITY_MIN or end_workload > PROFILE_DENSITY_MAX:
			reasons.append("ordinary_enemy_boundary_outside_25_40")
	else:
		if requested_workload != 32 or start_workload != 32 or end_workload != 32:
			reasons.append("diagnostic_enemy_cohort_boundary_not_32")
	if minimum_workload < PROFILE_DENSITY_MIN or maximum_workload > PROFILE_DENSITY_MAX:
		reasons.append("enemy_density_outside_25_40")
	if float(frame_ms.get("p95", INF)) > 16.67:
		reasons.append("p95_above_16_67ms")
	var density_qualified := minimum_workload >= PROFILE_DENSITY_MIN and maximum_workload <= PROFILE_DENSITY_MAX and start_workload >= PROFILE_DENSITY_MIN and end_workload >= PROFILE_DENSITY_MIN
	return {"qualified":reasons.is_empty(), "ordinary_route_qualified":passive_ordinary and reasons.is_empty(), "density_qualified":density_qualified, "reasons":reasons, "requires_hardware":true, "p95_limit_ms":16.67,
		"required_density_range":{"minimum":25,"maximum":40,"boundary_target":32}}

func _validation_controls_receipt() -> Dictionary:
	var actions := [&"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10", &"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_advance_density", &"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile", &"validation_reset_final_profile"]
	var controls: Array[Dictionary] = []
	for action in actions:
		controls.append({"action":String(action), "registered":InputMap.has_action(action), "physical_binding_count":InputMap.action_get_events(action).size() if InputMap.has_action(action) else 0})
	for action in [&"tester_victory_prepare", &"tester_victory_advance", &"tester_victory_commit", &"tester_final_profile_prepare", &"tester_final_profile_advance", &"tester_final_profile_reset"]:
		controls.append({"action":String(action), "registered":InputMap.has_action(action), "physical_binding_count":InputMap.action_get_events(action).size() if InputMap.has_action(action) else 0})
	return {"editor_only":OS.has_feature("editor"), "release_export_available":false, "controls":controls, "prepare_and_advance_separate":true, "density_checkpoints":[3,5,10,18,32]}

func _dense_work_caps(encounter: Dictionary) -> Dictionary:
	var neighbor_state: Dictionary = encounter.get("neighbor_registry", {})
	var audio_state := audio_director._mcp_state()
	var attack_state := world.attack_runtime._mcp_state()
	return {
		"enemy_pool":spawner.pool_size, "enemy_live":spawner.live_cap,
		"neighbor_candidates_per_query":int(neighbor_state.get("candidate_budget", 12)),
		"telegraph_cues":spawner.telegraph_cue_cap,
		"reward_pickups":MAX_ACTIVE_PICKUPS,
		"ordinary_role_lights":spawner.role_light_cap,
		"hurt_lights":spawner.hurt_light_cap,
		"audio_effect_voices":int(audio_state.get("voice_limit", 0)),
		"completed_attack_history":int(attack_state.get("history_limit", 0)),
		"dense_presentation":(encounter.get("dense_presentation_budget", {}) as Dictionary).duplicate(true),
	}

func _profile_workload_receipt(encounter: Dictionary) -> Dictionary:
	var audio_state := audio_director._mcp_state()
	var attack_state := world.attack_runtime._mcp_state()
	var light_budget: Dictionary = encounter.get("ordinary_light_budget", {})
	var counts := _profile_counts()
	return {
		"role_composition":(encounter.get("roles", {}) as Dictionary).duplicate(true),
		"active_and_pooled":{"active":encounter.get("live", 0),"pooled":encounter.get("pooled", 0)},
		"attacks":{"authorized":attack_state.get("authorized_count", 0),"hits":attack_state.get("hit_count", 0),"active_ledgers":attack_state.get("active_ledgers", 0)},
		"projectiles":counts.get("projectiles", 0),
		"pickups":counts.get("pickups", 0),
		"effects":counts.get("effects", 0),
		"audio":{"active_voices":audio_state.get("active_effect_voices", 0),"active_by_owner":(audio_state.get("active_by_owner", {}) as Dictionary).duplicate(true),"voice_limit":audio_state.get("voice_limit", 0)},
		"neighbor_work":(encounter.get("neighbor_registry", {}) as Dictionary).duplicate(true),
		"presentation_updates":(encounter.get("dense_presentation_budget", {}) as Dictionary).duplicate(true),
		"light_owners":{"active":light_budget.get("active", 0),"role":(light_budget.get("role", {}) as Dictionary).duplicate(true),"hurt":(light_budget.get("hurt", {}) as Dictionary).duplicate(true)},
		"telegraph_admission":(encounter.get("telegraph_admission", {}) as Dictionary).duplicate(true),
	}

func _lifecycle_counters() -> Dictionary:
	var owned_signal_bindings := 0
	owned_signal_bindings += 1 if spawner.enemy_defeated.is_connected(_on_enemy_defeated) else 0
	owned_signal_bindings += 1 if spawner.reward_dropped.is_connected(_on_reward_dropped) else 0
	owned_signal_bindings += 1 if spawner.encounter_changed.is_connected(_on_encounter_changed) else 0
	owned_signal_bindings += 1 if wave_director.phase_changed.is_connected(_on_wave_phase_changed) else 0
	owned_signal_bindings += 1 if wave_director.boss_requested.is_connected(_spawn_bellkeeper) else 0
	var counts := _profile_counts()
	return {
		"scene_tree_nodes":get_tree().get_node_count(),
		"object_count":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"input_action_count":InputMap.get_actions().size(),
		"owned_signal_bindings":owned_signal_bindings,
		"audio_voices":audio_director.active_effect_voice_count(),
		"enemy_active":int(counts.get("enemies", 0)),
		"enemy_pooled":int(counts.get("pooled_enemies", 0)),
		"active_pools":int(counts.get("enemies", 0)),
		"projectiles":int(counts.get("projectiles", 0)),
		"pickups":int(counts.get("pickups", 0)),
		"telegraph_active":int(counts.get("telegraph_active", 0)),
		"light_count":int(counts.get("lights", 0)),
		"wisp_hit_ledgers":int(counts.get("wisp_interval_targets", 0)),
		"active_attack_ledgers":int(counts.get("active_attack_ledgers", 0)),
		"effects":int(counts.get("effects", 0)),
		"input_owner_count":input_router.active_transactions.size(),
		"input_context":input_router.context,
		"terminal_commit_count":terminal_commit_count,
	}

func _route_qualification(wave_state: Dictionary) -> Dictionary:
	return {
		"expected_wave_ids":(wave_state.get("expected_route_wave_ids", []) as Array).duplicate(),
		"observed_wave_ids":(wave_state.get("ordinary_route_wave_ids", []) as Array).duplicate(),
		"ordinary_route_complete":bool(wave_state.get("ordinary_route_complete", false)),
		"diagnostic_jump_count":int(wave_state.get("diagnostic_jump_count", 0)),
		"run_route_kind":run_route_kind,
		"ordinary_route_eligible":run_route_kind == "ordinary" and bool(wave_state.get("ordinary_route_eligible", false)),
		"victory_window_seconds":{"minimum":420.0,"maximum":600.0},
		"boss_transition_history":boss_transition_history.duplicate(true),
		"natural_build_history":selected_upgrades.duplicate(true),
		"natural_build_history_truthful":_natural_build_history_truthful(),
		"natural_collection_transactions":pickup_collected_total,
		"natural_progression_truthful":_ordinary_progression_truthful(),
		"boss_two_phase_history_truthful":_boss_two_phase_history_truthful(),
	}

func _natural_build_history_truthful() -> bool:
	if selected_upgrades.is_empty():
		return false
	for choice in selected_upgrades:
		if not bool(choice.get("natural_choice", false)) or not bool(choice.get("truthful_transaction", false)):
			return false
	return true

func _ordinary_progression_truthful() -> bool:
	return (
		_natural_build_history_truthful()
		and pickup_collected_total >= selected_upgrades.size()
		and defeated_enemies > 0
	)

func _boss_two_phase_history_truthful() -> bool:
	for transition in boss_transition_history:
		if String(transition.get("event", "")) == "bellkeeper_phase_shifted" and int(transition.get("phase", 0)) >= 2 and bool(transition.get("natural_transition", false)):
			return true
	return false

func _record_retry_baseline(reason: String) -> void:
	_retry_baseline_generation += 1
	var receipt := {
		"run_serial":run_serial, "baseline_generation":_retry_baseline_generation,
		"source":reason,
		"tree_paused":get_tree().paused, "run_state":run_state,
		"counts":_profile_counts(),
		"warden_animation":warden.animation_binding.get_snapshot() if warden.animation_binding else {},
		"reset_invariants":_terminal_reset_invariants("retry" if reason == "retry" else "fresh_start"),
		"world_active":world.session_active,
		"teardown_generation":teardown_receipt.get("completion_generation",0),
	}
	validation_retry_baselines.append(receipt)
	if validation_retry_baselines.size() > 3:
		validation_retry_baselines.pop_front()

func _prepare_validation_wave(index: int) -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"]:
		return
	run_route_kind = "diagnostic_prepared"
	if index >= 3:
		health.maximum_health = 5000.0
		health.reset_warden_health()
		_last_health = health.current_health
		experience = 0
		experience_threshold = 9999
	wave_director.prepare_test_wave(index)
	if index == 3:
		_record_validation_density(32)

func _prepare_validation_density_checkpoint(target_live: int) -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"]:
		return
	run_route_kind = "diagnostic_prepared"
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
	experience = 0
	experience_threshold = 9999
	get_tree().paused = true
	var build_receipt := inventory.prepare_legal_build("representative")
	wave_director.prepare_test_wave(3)
	_record_validation_density(target_live, build_receipt)

func _record_validation_density(target_live: int, build_receipt: Dictionary = {}) -> void:
	var before := spawner.get_snapshot()
	var preparation := spawner.prepare_validation_density(target_live)
	var seeded_pickups := _seed_profile_pickups(3)
	_validation_setup_generation += 1
	var after := spawner.get_snapshot()
	validation_density_receipt = {
		"accepted":bool(preparation.get("accepted", false)),
		"requested_density":target_live,
		"resolved_density":int(after.get("live", 0)),
		"run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"route_kind":run_route_kind,
		"requested_profile":"density_matrix_%d" % target_live,
		"resolved_profile":"prepared_paused",
		"preparation_paused":get_tree().paused,
		"advance_action_required":true,
		"build_receipt":build_receipt.duplicate(true),
		"weapon_ranks":_profile_weapon_ranks(),
		"boss_presence":is_instance_valid(boss),
		"pickups_seeded":seeded_pickups,
		"active":int(after.get("live", 0)), "pooled":int(after.get("pooled", 0)),
		"before_active":int(before.get("live", 0)),
		"light_budget":(after.get("ordinary_light_budget", {}) as Dictionary).duplicate(true),
		"neighbor_registry":(after.get("neighbor_registry", {}) as Dictionary).duplicate(true),
		"telegraph_admission":(after.get("telegraph_admission", {}) as Dictionary).duplicate(true),
		"preparation":preparation.duplicate(true),
		"attacks_advanced_by_preparation":false,
		"terminal_state_advanced":false,
		"work_caps":_dense_work_caps(after),
		"workload":_profile_workload_receipt(after),
		"lifecycle":_lifecycle_counters(),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
	}
	validation_profile_receipt = validation_density_receipt.duplicate(true)
	_record_profile_cycle("prepare", validation_profile_receipt)
	_emit_snapshot()

func _advance_validation_density_checkpoint() -> void:
	if not OS.has_feature("editor") or _profile_active or not bool(validation_density_receipt.get("accepted", false)):
		return
	if int(validation_density_receipt.get("setup_generation", -1)) != _validation_setup_generation or int(validation_density_receipt.get("run_serial", -1)) != run_serial:
		validation_density_receipt["advance_rejected"] = "stale_generation_or_run"
		_emit_snapshot()
		return
	var requested := int(validation_density_receipt.get("requested_density", 0))
	if requested not in [3, 5, 10, 18, 32]:
		validation_density_receipt["advance_rejected"] = "density_not_in_matrix"
		_emit_snapshot()
		return
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_elapsed = 0.0
	_profile_sample_counter_reads = 0
	_profile_active = true
	_profile_origin = "diagnostic_density_matrix"
	_profile_advance_generation += 1
	_profile_start_counts = _profile_counts()
	_profile_start_lifecycle = _lifecycle_counters()
	var cohort := spawner.begin_validation_profile_cohort(requested, _validation_setup_generation)
	validation_profile_sample = {
		"status":"sampling",
		"branch_id":"density_matrix_%d" % requested,
		"sample_kind":_profile_origin,
		"route_kind":run_route_kind,
		"run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"advance_generation":_profile_advance_generation,
		"requested_density":requested,
		"resolved_density":int(validation_density_receipt.get("resolved_density", 0)),
		"boss_presence":is_instance_valid(boss),
		"weapon_ranks":_profile_weapon_ranks(),
		"window_seconds":_profile_duration,
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"start_counts":_profile_start_counts.duplicate(true),
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"cohort_start":cohort,
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"workload_start":_profile_workload_receipt(spawner.get_snapshot()),
	}
	get_tree().paused = false
	_emit_snapshot()

func _reset_validation_density() -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"]:
		return
	spawner.reset_encounter()
	_validation_setup_generation += 1
	var after := spawner.get_snapshot()
	validation_density_receipt = {
		"accepted":true, "reset":true, "requested_density":0,
		"resolved_density":int(after.get("live", 0)), "run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"active":int(after.get("live", 0)), "pooled":int(after.get("pooled", 0)),
		"light_budget":(after.get("ordinary_light_budget", {}) as Dictionary).duplicate(true),
		"neighbor_registry":(after.get("neighbor_registry", {}) as Dictionary).duplicate(true),
		"telegraph_admission":(after.get("telegraph_admission", {}) as Dictionary).duplicate(true),
		"reset_isolated":int(after.get("live", -1)) == 0 and int((after.get("neighbor_registry", {}) as Dictionary).get("registered_count", -1)) == 0 and int((after.get("ordinary_light_budget", {}) as Dictionary).get("active", -1)) == 0,
	}
	_emit_snapshot()

func _prepare_tester_victory() -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"] or result_committed or _victory_transaction_active:
		return
	_victory_fixture_commit_held = false
	_victory_fixture_hold_generation = -1
	run_route_kind = "diagnostic_prepared"
	inventory.prepare_legal_build("representative")
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
	warden.global_position = Vector3(0.0, 0.05, 6.0)
	warden.velocity = Vector3.ZERO
	warden.planar_velocity = Vector3.ZERO
	warden.reset_input_latch("tester_victory_prepare")
	wave_director.prepare_test_wave(4)
	if not is_instance_valid(boss):
		_spawn_bellkeeper()
	if not is_instance_valid(boss):
		return
	boss.health.current_health = maxf(1.0, boss.health.maximum_health * 0.05)
	boss.state = "recovery"
	boss.vulnerable = true
	boss.state_clock = 999.0
	boss_snapshot = boss.get_snapshot().duplicate(true)
	world.set_session_active(false)
	_validation_setup_generation += 1
	get_tree().paused = true
	var prepared_animation := warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	var prepared_audio := audio_director._mcp_state()
	tester_victory_fixture_receipt = {
		"branch_id":"tester_victory_transaction",
		"requested_branch_id":"tester_victory_transaction.prepare",
		"resolved_branch_id":"tester_victory_transaction.prepared",
		"setup_generation":_validation_setup_generation,
		"run_serial":run_serial,
		"requested_state":"stable_bellkeeper_recovery_before_defeat",
		"resolved_state":boss_snapshot.get("state", "absent"),
		"requested_route_kind":"diagnostic_prepared",
		"resolved_route_kind":run_route_kind,
		"prepare_paused":get_tree().paused,
		"boss_defeat_committed":bool(boss_snapshot.get("defeat_committed", false)),
		"result_committed":result_committed,
		"terminal_commit_count":terminal_commit_count,
		"advance_requested":false,
		"advance_resolved":false,
		"advance_edge_count":0,
		"commit_requested":false,
		"commit_resolved":false,
		"commit_edge_count":0,
		"rejected_edge_count":0,
		"animation_before_advance":prepared_animation,
		"terminal_lease_before_advance":prepared_animation.get("terminal_lease", {}),
		"audio_lease_before_advance":prepared_audio.get("terminal_audio_lease", {}),
		"terminal_voice_count_before_advance":prepared_audio.get("terminal_active_voice_count", 0),
		"preparation_has_no_terminal_onset":not bool((prepared_animation.get("terminal_lease", {}) as Dictionary).get("active", false)) and not bool((prepared_audio.get("terminal_audio_lease", {}) as Dictionary).get("active", false)) and int(prepared_audio.get("terminal_active_voice_count", 0)) == 0,
		"reset_isolation":_counts_are_isolated(_profile_counts()),
		"counts":_profile_counts(),
		"lifecycle":_lifecycle_counters(),
	}
	_emit_snapshot()

func _advance_tester_victory() -> void:
	if not OS.has_feature("editor") or String(tester_victory_fixture_receipt.get("branch_id", "")) != "tester_victory_transaction":
		return
	if int(tester_victory_fixture_receipt.get("setup_generation", -1)) != _validation_setup_generation or int(tester_victory_fixture_receipt.get("run_serial", -1)) != run_serial:
		_reject_tester_victory_edge("advance", "stale_generation_or_run")
		return
	if not is_instance_valid(boss) or result_committed or _victory_transaction_active:
		_reject_tester_victory_edge("advance", "already_advanced_or_terminal")
		return
	_victory_fixture_commit_held = true
	_victory_fixture_hold_generation = _validation_setup_generation
	get_tree().paused = false
	tester_victory_fixture_receipt["advance_requested"] = true
	tester_victory_fixture_receipt["advance_edge_count"] = int(tester_victory_fixture_receipt.get("advance_edge_count", 0)) + 1
	tester_victory_fixture_receipt["requested_branch_id"] = "tester_victory_transaction.advance"
	tester_victory_fixture_receipt["advance_frame"] = Engine.get_process_frames()
	var resolution := boss.health.apply_damage({
		"attack_id":"tester.victory.advance.g%04d" % _validation_setup_generation,
		"damage":boss.health.current_health,
		"damage_channel":"tester_terminal_advance",
	})
	get_tree().paused = true
	var animation := warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	var audio := audio_director._mcp_state()
	var vfx: Dictionary = warden._mcp_state().get("victory_vfx", {})
	tester_victory_fixture_receipt["advance_resolved"] = bool(resolution.get("accepted", false)) and not boss.health.is_alive()
	tester_victory_fixture_receipt["resolved_branch_id"] = "tester_victory_transaction.presentation_held" if bool(tester_victory_fixture_receipt["advance_resolved"]) else "tester_victory_transaction.advance_rejected"
	tester_victory_fixture_receipt["resolved_state"] = run_state
	tester_victory_fixture_receipt["boss_defeat_committed"] = bool(boss_snapshot.get("defeat_committed", false))
	tester_victory_fixture_receipt["result_committed_after_advance"] = result_committed
	tester_victory_fixture_receipt["terminal_commit_count_after_advance"] = terminal_commit_count
	tester_victory_fixture_receipt["presentation_paused"] = get_tree().paused
	tester_victory_fixture_receipt["semantic_clip"] = animation.get("resolved_clip", "")
	tester_victory_fixture_receipt["semantic_state"] = animation.get("semantic_state", "")
	tester_victory_fixture_receipt["deformation_bone_count"] = animation.get("deformation_bone_count", 0)
	tester_victory_fixture_receipt["deformation_track_count"] = int((animation.get("deformation_tracks", {}) as Dictionary).get("victory", 0))
	tester_victory_fixture_receipt["animation_lease"] = (animation.get("terminal_lease", {}) as Dictionary).duplicate(true)
	tester_victory_fixture_receipt["audio_lease"] = (audio.get("terminal_audio_lease", {}) as Dictionary).duplicate(true)
	tester_victory_fixture_receipt["terminal_voice_count"] = audio.get("terminal_active_voice_count", 0)
	tester_victory_fixture_receipt["vfx_onset"] = vfx.duplicate(true)
	tester_victory_fixture_receipt["commit_held"] = _victory_fixture_commit_held
	tester_victory_fixture_receipt["presentation_transaction"] = ordinary_victory_receipt.duplicate(true)
	tester_victory_fixture_receipt["reset_isolation"] = false
	_emit_snapshot()

func _commit_tester_victory() -> void:
	if not OS.has_feature("editor") or String(tester_victory_fixture_receipt.get("branch_id", "")) != "tester_victory_transaction":
		return
	if int(tester_victory_fixture_receipt.get("setup_generation", -1)) != _validation_setup_generation or int(tester_victory_fixture_receipt.get("run_serial", -1)) != run_serial:
		_reject_tester_victory_edge("commit", "stale_generation_or_run")
		return
	if not _victory_fixture_commit_held or _victory_fixture_hold_generation != _validation_setup_generation or not _victory_transaction_active or result_committed or not bool(tester_victory_fixture_receipt.get("advance_resolved", false)):
		_reject_tester_victory_edge("commit", "presentation_not_held_or_already_committed")
		return
	tester_victory_fixture_receipt["commit_requested"] = true
	tester_victory_fixture_receipt["commit_edge_count"] = int(tester_victory_fixture_receipt.get("commit_edge_count", 0)) + 1
	tester_victory_fixture_receipt["requested_branch_id"] = "tester_victory_transaction.commit"
	tester_victory_fixture_receipt["commit_frame"] = Engine.get_process_frames()
	tester_victory_fixture_receipt["held_wall_seconds_before_commit"] = float(Time.get_ticks_msec() - _victory_hold_started_msec) / 1000.0
	_victory_fixture_commit_held = false
	_victory_fixture_hold_generation = -1
	tester_victory_fixture_receipt["commit_held"] = false
	get_tree().paused = false
	_commit_victory_transaction()
	tester_victory_fixture_receipt["commit_resolved"] = result_committed and terminal_commit_count == 1
	tester_victory_fixture_receipt["resolved_branch_id"] = "tester_victory_transaction.result_committed" if bool(tester_victory_fixture_receipt["commit_resolved"]) else "tester_victory_transaction.commit_rejected"
	tester_victory_fixture_receipt["result_committed_after_commit"] = result_committed
	tester_victory_fixture_receipt["terminal_commit_count_after_commit"] = terminal_commit_count
	tester_victory_fixture_receipt["result_committed"] = result_committed
	tester_victory_fixture_receipt["terminal_commit_count"] = terminal_commit_count
	tester_victory_fixture_receipt["presentation_transaction"] = ordinary_victory_receipt.duplicate(true)
	_emit_snapshot()

func _reject_tester_victory_edge(action: String, reason: String) -> void:
	if tester_victory_fixture_receipt.is_empty():
		return
	tester_victory_fixture_receipt["rejected_edge_count"] = int(tester_victory_fixture_receipt.get("rejected_edge_count", 0)) + 1
	tester_victory_fixture_receipt["last_rejected_edge"] = {
		"action":action,
		"reason":reason,
		"run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"process_frame":Engine.get_process_frames(),
	}
	_emit_snapshot()

func _prepare_validation_result(validation_outcome: String) -> void:
	if not OS.has_feature("editor") or run_state not in ["active","boss"]:
		return
	run_route_kind = "diagnostic_prepared"
	inventory.prepare_legal_build("representative")
	var lantern := inventory.get_stats(&"warden_lantern")
	var spade := inventory.get_stats(&"gravespade")
	var wisps := inventory.get_stats(&"wandering_wisps")
	selected_upgrades = [
		{"id":"representative_build","title":"Three-weapon Vigil","rank_label":"MAX","concrete_change":"Lantern %.0f • Spade %.0f • Wisps %.0f" % [lantern.damage, spade.damage, wisps.damage]},
	]
	defeated_enemies = maxi(defeated_enemies,18)
	damage_dealt = maxi(damage_dealt,742)
	damage_taken = maxi(damage_taken,37)
	if validation_outcome == "victory":
		_prepare_tester_victory()
	else:
		health.current_health = 0.0
		_on_warden_failed({"validation":true})

func _emit_snapshot() -> void:
	if not is_node_ready():
		return
	last_snapshot = RunSnapshot.make(self, world, warden, health, spawner, inventory)
	snapshot_changed.emit(last_snapshot)
	if run_state in ["active", "boss", "paused", "draft"]:
		hud.bind_snapshot(last_snapshot)

func _mcp_state() -> Dictionary:
	var wave_state := wave_director.get_snapshot()
	var profile_renderer: Dictionary = validation_profile_sample.get("renderer", {})
	var profile_viewport: Dictionary = validation_profile_sample.get("viewport", {})
	var profile_frame_ms: Dictionary = validation_profile_sample.get("frame_ms", {})
	var profile_cohort: Dictionary = validation_profile_sample.get("cohort", {})
	var profile_qualification: Dictionary = validation_profile_sample.get("qualification", {})
	var cycle_comparison := _profile_cycle_comparison()
	var ledger_snapshot := complete_run_ledger.get_snapshot()
	var ledger_matrix: Dictionary = ledger_snapshot.get("matrix", {})
	var ledger_checks: Dictionary = ledger_snapshot.get("contract_checks", {})
	var observation_work: Dictionary = validation_profile_sample.get("observation_work", _profile_observation_work_receipt())
	return {
		"run_state":run_state, "run_serial":run_serial, "run_elapsed":run_elapsed,
		"profile_status":validation_profile_sample.get("status", "idle"),
		"profile_armed":_profile_armed,
		"profile_arm_receipt":_profile_arm_receipt,
		"profile_sample_kind":validation_profile_sample.get("sample_kind", ""),
		"profile_p50_ms":profile_frame_ms.get("p50", 0.0),
		"profile_p95_ms":profile_frame_ms.get("p95", 0.0),
		"profile_p99_ms":profile_frame_ms.get("p99", 0.0),
		"profile_worst_ms":profile_frame_ms.get("worst", 0.0),
		"profile_renderer_classification":profile_renderer.get("classification", "unknown"),
		"profile_hardware_eligible":profile_renderer.get("hardware_qualification_eligible", false),
		"profile_viewport_width":profile_viewport.get("width", 0),
		"profile_viewport_height":profile_viewport.get("height", 0),
		"profile_requested_enemies":profile_cohort.get("requested", validation_profile_sample.get("requested_enemy_workload", 0)),
		"profile_start_enemies":profile_cohort.get("start", validation_profile_sample.get("start_enemy_workload", 0)),
		"profile_minimum_enemies":profile_cohort.get("minimum", validation_profile_sample.get("minimum_enemy_workload", 0)),
		"profile_end_enemies":profile_cohort.get("end_live", validation_profile_sample.get("end_enemy_workload", 0)),
		"profile_qualified":profile_qualification.get("qualified", false),
		"profile_sampled_frame_scene_scans":observation_work.get("sampled_frame_scene_scans", 0),
		"profile_sampled_frame_group_inventories":observation_work.get("sampled_frame_group_inventories", 0),
		"profile_sampled_frame_counter_reads":observation_work.get("sampled_frame_counter_read_count", _profile_sample_counter_reads),
		"profile_completed_cycles":cycle_comparison.get("completed_cycle_count", 0),
		"profile_stale_reset_context_cycles":cycle_comparison.get("stale_reset_context_cycle_count", 0),
		"profile_three_cycle_context_truthful":cycle_comparison.get("three_cycle_context_truthful", false),
		"profile_three_cycle_no_growth":cycle_comparison.get("three_cycle_no_growth", false),
		"profile_reset_contexts":{
			"immediate":validation_profile_receipt.get("input_context", "unavailable"),
			"next_frame":validation_profile_receipt.get("next_frame_input_context", "pending"),
			"live":input_router.context,
			"run_state":run_state,
		},
		"ordinary_wave_ids":wave_state.get("ordinary_route_wave_ids", []),
		"ordinary_diagnostic_jumps":wave_state.get("diagnostic_jump_count", 0),
		"ordinary_natural_progression_truthful":_ordinary_progression_truthful(),
		"ordinary_boss_two_phase_truthful":_boss_two_phase_history_truthful(),
		"ledger_contract_checks_pass":ledger_checks.get("all_checks_pass", false),
		"ledger_failure_result_retry":ledger_matrix.get("failure_result_retry", false),
		"ledger_victory_result_replay":ledger_matrix.get("victory_result_replay", false),
		"ledger_distinct_build_row_count":ledger_matrix.get("distinct_build_row_count", 0),
		"ledger_build_shape_rows":ledger_matrix.get("ordinary_build_shape_rows", {}),
		"ledger_row_qualifications":ledger_matrix.get("row_qualifications", []),
		"ledger_credits_traversed":ledger_matrix.get("credits_traversed", false),
		"ledger_missing_rows":ledger_matrix.get("remaining_matrix_cells", ledger_matrix.get("missing_rows", [])),
		"authoritative_teardown":teardown_receipt,
		"experience": experience, "experience_threshold": experience_threshold, "level": level,
		"defeated_enemies": defeated_enemies, "damage_taken": damage_taken,
		"damage_dealt":damage_dealt,"outcome":outcome,"selected_upgrade_count":selected_upgrades.size(),
		"wave":{"wave":wave_state.get("wave",0),"wave_count":wave_state.get("wave_count",5),"phase":wave_state.get("phase","idle"),"title":wave_state.get("title","")},
		"boss":{"active":boss_snapshot.get("active",false),"health":boss_snapshot.get("health",0.0),"health_maximum":boss_snapshot.get("health_maximum",0.0),"phase":boss_snapshot.get("phase",0)},"quit_requested":quit_requested,
		"result_committed": result_committed, "terminal_snapshot_digest": _terminal_snapshot_digest(), "state_history": state_history,
		"terminal_commit_count":terminal_commit_count, "run_route_kind":run_route_kind,
		"victory_transaction":{"active":_victory_transaction_active,"source_run_serial":_victory_source_run_serial,"hold_required_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,"hold_elapsed_seconds":_victory_hold_elapsed,"hold_remaining_seconds":_victory_hold_remaining,"tester_commit_held":_victory_fixture_commit_held,"tester_hold_generation":_victory_fixture_hold_generation},
		"boss_transition_history":boss_transition_history,
		"natural_build_history":selected_upgrades,
		"natural_build_history_truthful":_natural_build_history_truthful(),
		"route_qualification":_route_qualification(wave_state),
		"upgrade_draft":draft_controller.get_snapshot(), "teardown_receipt":teardown_receipt,
		"tree_paused": get_tree().paused, "shell_mode": shell.mode,
		"shell_return_mode": shell.return_mode, "shell_action_latched": shell.action_latched,
		"process_ownership":{
			"controller":process_mode, "shell":shell.process_mode,
			"world":world.process_mode, "wave_director":wave_director.process_mode,
			"upgrade_draft":draft_controller.process_mode,
		},
		"terminal_handoff":terminal_handoff_receipt,
		"terminal_handoff_active":_terminal_handoff_active,
		"context_handoff":context_handoff_receipt,
		"context_handoff_active":_context_handoff_active,
		"validation_density":validation_density_receipt,
		"validation_profile":validation_profile_receipt,
		"validation_profile_sample":validation_profile_sample,
		"validation_profile_cycles":validation_profile_cycles,
		"ordinary_profile_cycles":ordinary_profile_cycles,
		"ordinary_profile_contract_checks":ordinary_profile_contract_checks,
		"validation_profile_cycle_comparison":cycle_comparison,
		"validation_controls":_validation_controls_receipt(),
		"validation_retry_baselines":validation_retry_baselines,
		"ordinary_victory_receipt":ordinary_victory_receipt,
		"ordinary_victory_transactions":ordinary_victory_transactions,
		"warden_hat_isolation":warden.hat_isolation_receipt,
		"complete_run_ledger":complete_run_ledger.get_snapshot(),
		"validation_profile_matrix":_profile_matrix_snapshot(),
		"tester_victory_fixture":tester_victory_fixture_receipt,
		"reward_pickups":{"spawned_total":pickup_spawned_total,"collected_total":pickup_collected_total,"live":_active_pickup_count},
		"shell_focus": String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none",
	}

func _terminal_snapshot_digest() -> Dictionary:
	if terminal_snapshot.is_empty(): return {}
	return {"committed":terminal_snapshot.get("committed",false),"commit_run_serial":terminal_snapshot.get("commit_run_serial",0),
		"commit_count":terminal_snapshot.get("commit_count",0),"route_kind":terminal_snapshot.get("route_kind",""),"ordinary_route_eligible":terminal_snapshot.get("ordinary_route_eligible",false),
		"outcome":terminal_snapshot.get("outcome",""),"elapsed":terminal_snapshot.get("elapsed",0.0),"wave":terminal_snapshot.get("wave",0),
		"level":terminal_snapshot.get("level",0),"defeated":terminal_snapshot.get("defeated",0),"damage_dealt":terminal_snapshot.get("damage_dealt",0),
		"damage_taken":terminal_snapshot.get("damage_taken",0),"weapon_ranks":_terminal_weapon_ranks(),"selected_upgrades":terminal_snapshot.get("selected_upgrades",[]),
		"terminal_animation":terminal_snapshot.get("terminal_animation",{})}

func _terminal_weapon_ranks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon in (terminal_snapshot.get("weapons",{}) as Dictionary).get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			result.append({"weapon_id":weapon.get("weapon_id",""),"rank":weapon.get("rank",0)})
	return result
