class_name RunController
extends Node

signal state_changed(previous: String, current: String)
signal snapshot_changed(snapshot: Dictionary)
signal reward_collected(event: Dictionary)

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
@onready var arena_camera: ArenaCamera = $World/ArenaCamera
const BELLKEEPER_SCENE := preload("res://scenes/enemies/bellkeeper.tscn")
const REWARD_PICKUP_SCENE := preload("res://scenes/gameplay/reward_pickup.tscn")
const MAX_ACTIVE_PICKUPS := 16
const PICKUP_POOL_CAP := MAX_ACTIVE_PICKUPS
const MAX_PENDING_REWARDS := 16
const VICTORY_PRESENTATION_HOLD_SECONDS := 2.6
## The ordinary route is intentionally traversal-first: contact damage must be
## recoverable while the player learns the cemetery loop and waits through the
## authored five-wave cadence.  Keep a generous baseline and a small passive
## recovery so an unattended frame hitch or one crowded lane cannot terminate
## the release route before Bellkeeper eligibility is possible.
const STARTING_HEALTH := 500.0
const ORDINARY_PASSIVE_RECOVERY_PER_SECOND := 1.35
const PROFILE_DENSITY_MIN := 25
const PROFILE_DENSITY_MAX := 40
const PROFILE_COVERAGE_CELLS := [
	"enemy_density", "boss", "warden_lantern", "gravespade",
	"wandering_wisps", "pickups", "hud", "animation", "vfx",
	"lights", "audio",
	"vitality_indicators",
]
const CompleteRunLedgerClass := preload("res://scripts/gameplay/complete_run_ledger.gd")
const DenseWaveProfileClass := preload("res://scripts/gameplay/dense_profile.gd")

var run_state := "title"
var run_serial := 0
var run_elapsed := 0.0
var experience := 0
var experience_threshold := 5
var _pending_levelup_transactions := 0
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
var dense_profile_self_audit: Dictionary = {}
var ordinary_victory_receipt: Dictionary = {}
var ordinary_victory_transactions: Array[Dictionary] = []
var tester_victory_fixture_receipt: Dictionary = {}
var tester_failure_fixture_receipt: Dictionary = {}
var pickup_spawned_total := 0
var pickup_collected_total := 0
var _profile_samples_ms: Array[float] = []
var _profile_active := false
var _profile_paused := false
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
var _profile_metric_samples: Array[Dictionary] = []
var _profile_advance_generation := 0
var _profile_process_frame_start := 0
var _profile_physics_frame_start := 0
var _profile_completion_grace_frames := 0
var _dense_cycle_index := 0
var validation_profile_matrix_samples: Array[Dictionary] = []
var density_matrix_contract_checks: Dictionary = {}
var _active_pickups: Dictionary = {}
var _pickup_pool: Array[RewardPickup] = []
var _pickup_total := 0
var _active_pickup_count := 0
var _pending_reward_events: Array[Dictionary] = []
var _reward_cap_deferrals := 0
var _active_effect_count := 0
var _profile_static_light_count := 0
var _profile_setup_scene_scans := 0
var _profile_sample_counter_reads := 0
var _profile_gate_counter_reads := 0
## Dense qualification uses a deterministic, product-owned render-quality
## wrapper.  It only changes presentation cost for the bounded editor profile;
## ordinary runs restore the authored lighting immediately.
const DENSE_QUALITY_REVISION := "dense_quality_wrapper_v1"
var _dense_quality_active := false
var _dense_quality_originals: Dictionary = {}
var _dense_quality_receipt: Dictionary = {"active":false,"revision":DENSE_QUALITY_REVISION}
var _profile_sample_accumulator := 0.0
## Dense windows retain a 100 ms metric cadence, but the expensive cross-system
## coverage read is intentionally sampled at a coarser deterministic stride.
## Coverage is cumulative for the whole window, so skipping an intermediate
## read cannot erase a weapon/VFX/audio observation while it avoids repeatedly
## walking the audio and presentation owners on every telemetry tick.
var _profile_observation_stride := 0
var _profile_last_system_observation: Dictionary = {}
var _profile_coverage: Dictionary = {}
var _profile_coverage_first_seen: Dictionary = {}
var _first_run_guidance_completed := false
var _first_run_guidance_completion: Dictionary = {}
var _first_run_guidance_dismissed := false
var _guidance_movement_observed := false
var _guidance_dash_observed := false
var _guidance_attack_observed := false
var _guidance_progress_stage := 0
var _guidance_attack_baseline := 0
var _guidance_reset_generation := 0
var _guidance_reset_receipt: Dictionary = {}
var _known_reward_ids: Dictionary = {}
var _resolved_reward_ids: Dictionary = {}
var _reward_spawn_receipt: Dictionary = {}
var _reward_attraction_receipt: Dictionary = {}
var _reward_collection_receipt: Dictionary = {}
var _reward_experience_receipt: Dictionary = {}
var _reward_duplicate_rejections := 0
var upgrade_transaction_receipt: Dictionary = {}
var _upgrade_commit_in_progress := false
var candidate_session_handshake: Dictionary = {}

const PROFILE_SAMPLE_INTERVAL_SECONDS := 0.1
const PROFILE_MAX_SAMPLES := 128
const DEVELOPMENT_ONLY_ACTIONS := [
	&"validation_prepare_build", &"validation_reset_build", &"validation_prepare_wisps",
	&"validation_prepare_wave4", &"validation_prepare_boss", &"validation_prepare_draft",
	&"validation_prepare_result_failure", &"validation_prepare_result_victory",
	&"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10",
	&"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_advance_density",
	&"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile",
	&"validation_reset_final_profile", &"tester_victory_prepare", &"tester_victory_advance",
	&"tester_victory_commit", &"tester_final_profile_prepare", &"tester_final_profile_advance",
	&"tester_final_profile_reset", &"tester_dense_prepare", &"tester_dense_advance", &"tester_dense_reset",
	&"tester_failure_prepare", &"tester_failure_advance", &"tester_failure_commit",
	&"qa_reset_first_run_guidance",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	candidate_session_handshake = {
		"contract_id":"mournlight.candidate_session.v1",
		"scene":"res://main.tscn",
		"workspace":ProjectSettings.globalize_path("res://"),
		"generation":1,
		"ready":true,
		"shell_owner":"/root/Mournlight/Interface/RunShellView",
	}
	set_meta("candidate_session_handshake", candidate_session_handshake.duplicate(true))
	set_meta("dense_quality_profile", _dense_quality_receipt.duplicate(true))
	# Development qualification controls are intentionally absent from release
	# InputMap state.  They remain unbound in editor sessions for host-driven
	# probes, but an exported build must not expose tester/validation actions even
	# if a stale project.godot carried their names forward.
	if not OS.has_feature("editor"):
		for action in DEVELOPMENT_ONLY_ACTIONS:
			if InputMap.has_action(action):
				InputMap.erase_action(action)
	complete_run_ledger = CompleteRunLedgerClass.new()
	ordinary_profile_contract_checks = _ordinary_profile_contract_checks()
	dense_profile_self_audit = DenseWaveProfileClass.self_audit()
	density_matrix_contract_checks = _density_matrix_contract_checks()
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
	draft_view.cancel_requested.connect(_on_draft_cancel)
	world.attack_runtime.hit_resolved.connect(_on_player_hit_resolved)
	warden.dash_phase_changed.connect(_on_dash_changed)
	input_router.logical_press_edge.connect(_on_logical_press_edge)
	input_router.context_changed.connect(_on_input_context_changed)
	input_router.device_changed.connect(_on_input_device_changed)
	draft_view.set_input_device(input_router.active_device, input_router.device_generation)
	if OS.has_feature("editor"):
		for action in [&"validation_prepare_wave4", &"validation_prepare_boss", &"validation_prepare_draft", &"validation_prepare_result_failure", &"validation_prepare_result_victory", &"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10", &"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_advance_density", &"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile", &"validation_reset_final_profile", &"tester_victory_prepare", &"tester_victory_advance", &"tester_victory_commit", &"tester_final_profile_prepare", &"tester_final_profile_advance", &"tester_final_profile_reset", &"tester_dense_prepare", &"tester_dense_advance", &"tester_dense_reset", &"tester_failure_prepare", &"tester_failure_advance", &"tester_failure_commit", &"qa_reset_first_run_guidance"]:
			if not InputMap.has_action(action):
				InputMap.add_action(action)
	_enter_title()

func _process(delta: float) -> void:
	# The development dense collector owns its sampling window. A timed MCP
	# advance can leave the SceneTree paused after the input edge returns even
	# though the game is not in its pause menu; release that stale pause latch so
	# real frames continue to be measured. Ordinary gameplay and passive
	# profiling never override the player's pause ownership.
	if _profile_active and _profile_origin.begins_with("diagnostic_") and get_tree().paused and not _profile_paused:
		get_tree().paused = false
	_advance_context_handoff()
	_advance_victory_transaction(delta)
	_try_begin_passive_ordinary_profile()
	_advance_profile_sample(delta)
	if run_state in ["active","boss"] and not get_tree().paused:
		run_elapsed += delta
		# Passive recovery belongs to the authoritative run controller rather
		# than presentation/UI.  It is bounded, emits the normal health signal,
		# and never runs during draft, pause, result, or teardown ownership.
		if health.current_health > 0.0 and health.current_health < health.maximum_health:
			var recovered := minf(health.maximum_health, health.current_health + ORDINARY_PASSIVE_RECOVERY_PER_SECOND * delta)
			if recovered > health.current_health:
				health.current_health = recovered
				health.health_changed.emit(health.current_health, health.maximum_health)
		if not _guidance_movement_observed and warden.planar_velocity.length() > 0.45:
			_guidance_movement_observed = true
			_guidance_progress_stage = maxi(_guidance_progress_stage, 1)
		if not _guidance_attack_observed and world.attack_runtime.authorized_count > _guidance_attack_baseline:
			_guidance_attack_observed = true
			_guidance_progress_stage = maxi(_guidance_progress_stage, 3)
	_snapshot_clock -= delta
	if _snapshot_clock <= 0.0:
		_snapshot_clock = 0.1
		_emit_snapshot()

func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("editor") and event.is_action_pressed(&"qa_reset_first_run_guidance"):
		_qa_reset_first_run_guidance()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"guidance_help") and run_state in ["active", "boss"]:
		_first_run_guidance_dismissed = not _first_run_guidance_dismissed
		_emit_snapshot()
		get_viewport().set_input_as_handled()
		return
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
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_failure_prepare"):
		_prepare_tester_failure()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_failure_advance"):
		_advance_tester_failure()
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"tester_failure_commit"):
		_commit_tester_failure()
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
	if DenseWaveProfileClass.tester_guard() and event.is_action_pressed(&"tester_dense_prepare"):
		_prepare_final_profile()
		get_viewport().set_input_as_handled()
		return
	if DenseWaveProfileClass.tester_guard() and event.is_action_pressed(&"tester_dense_advance"):
		_advance_final_profile()
		get_viewport().set_input_as_handled()
		return
	if DenseWaveProfileClass.tester_guard() and event.is_action_pressed(&"tester_dense_reset"):
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
	# Pause ownership is routed exclusively through InputContextRouter.  The
	# physical Escape/Start event is also bound to context_back, so handling it
	# here would toggle twice (once from the router's synthetic logical edge and
	# once from this raw event) and leave the run in its prior state.  Keeping the
	# fallback out of _unhandled_input preserves one activation per transaction.

func start_run() -> void:
	# A Play action from the title is an intentional fresh onboarding session.
	# Retry calls _begin_run() directly and must retain completed guidance, while
	# returning to title and choosing Play should expose the first-run sequence
	# again so a new player can rediscover movement, drops, and upgrades.
	if run_state == "title":
		_reset_first_run_guidance_for_fresh_title_start()
	_next_baseline_reason = "fresh_start"
	_teardown_run("fresh_start", "defensive_start_cleanup")
	_begin_run()

func _reset_first_run_guidance_for_fresh_title_start() -> void:
	_first_run_guidance_completed = false
	_first_run_guidance_completion.clear()
	_first_run_guidance_dismissed = false
	_guidance_movement_observed = false
	_guidance_dash_observed = false
	_guidance_attack_observed = false
	_guidance_progress_stage = 0
	_guidance_attack_baseline = world.attack_runtime.authorized_count
	_guidance_reset_generation += 1
	_guidance_reset_receipt = {
		"requested":true,
		"resolved":true,
		"generation":_guidance_reset_generation,
		"editor_only":false,
		"reason":"fresh_title_play",
		"physical_binding_count":0,
		"release_action_exposed":false,
		"run_serial":run_serial,
		"reset_isolated_to_guidance":true,
	}

func _apply_dense_quality_profile(enabled: bool) -> void:
	"""Apply/restore the bounded dense-render quality profile."""
	if enabled == _dense_quality_active:
		return
	var key_light := world.get_node_or_null("MoonKey") as DirectionalLight3D
	var post_light := world.get_node_or_null("CemeteryGarden/OuterDatum/KeeperLanternPostAnchor/WarmLandmarkLight") as Light3D
	var environment_node := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if enabled:
		_dense_quality_originals.clear()
		if is_instance_valid(key_light):
			_dense_quality_originals["moon_key_shadow"] = key_light.shadow_enabled
			key_light.shadow_enabled = false
		if is_instance_valid(post_light):
			_dense_quality_originals["post_shadow"] = post_light.shadow_enabled
			post_light.shadow_enabled = false
		if is_instance_valid(environment_node) and is_instance_valid(environment_node.environment):
			_dense_quality_originals["glow_enabled"] = environment_node.environment.glow_enabled
			# Glow is the largest full-screen cost in the compatibility renderer;
			# hostile telegraphs and lantern materials remain emissive/readable.
			environment_node.environment.glow_enabled = false
		_dense_quality_active = true
	else:
		if is_instance_valid(key_light) and _dense_quality_originals.has("moon_key_shadow"):
			key_light.shadow_enabled = bool(_dense_quality_originals["moon_key_shadow"])
		if is_instance_valid(post_light) and _dense_quality_originals.has("post_shadow"):
			post_light.shadow_enabled = bool(_dense_quality_originals["post_shadow"])
		if is_instance_valid(environment_node) and is_instance_valid(environment_node.environment) and _dense_quality_originals.has("glow_enabled"):
			environment_node.environment.glow_enabled = bool(_dense_quality_originals["glow_enabled"])
		_dense_quality_active = false
		_dense_quality_originals.clear()
	_dense_quality_receipt = {
		"active":_dense_quality_active,
		"revision":DENSE_QUALITY_REVISION,
		"scope":"dense_profile_only",
		"renderer_cost_controls":["directional_shadows","landmark_shadows","fullscreen_glow"],
		"ordinary_route_restored":not _dense_quality_active,
		"combat_readability_preserved":true,
	}
	set_meta("dense_quality_profile", _dense_quality_receipt.duplicate(true))

func _begin_run() -> void:
	get_tree().paused = false
	_apply_dense_quality_profile(false)
	# A quit request belongs to the prior shell transaction. Clear it before
	# exposing a fresh ordinary run so retry/title replay receipts cannot inherit
	# a stale terminal intent from a previous Quit activation.
	quit_requested = false
	world.visible = true
	_profile_active = false
	_profile_paused = false
	_profile_origin = ""
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_metric_samples.clear()
	_profile_elapsed = 0.0
	_profile_sample_accumulator = 0.0
	_profile_observation_stride = 0
	_profile_last_system_observation.clear()
	_profile_completion_grace_frames = 0
	_profile_start_counts.clear()
	_profile_armed = false
	_profile_arm_receipt.clear()
	_profile_minimum_enemy_workload = 0
	_profile_maximum_enemy_workload = 0
	_profile_sample_counter_reads = 0
	_profile_gate_counter_reads = 0
	_profile_rearm_count = 0
	_profile_coverage.clear()
	_profile_coverage_first_seen.clear()
	validation_profile_matrix_samples.clear()
	_active_pickups.clear()
	_active_pickup_count = 0
	_pending_reward_events.clear()
	_reward_cap_deferrals = 0
	_active_effect_count = 0
	_known_reward_ids.clear()
	_resolved_reward_ids.clear()
	_reward_spawn_receipt.clear()
	_reward_attraction_receipt.clear()
	_reward_collection_receipt.clear()
	_reward_experience_receipt.clear()
	_reward_duplicate_rejections = 0
	_guidance_movement_observed = false
	_guidance_dash_observed = false
	_guidance_attack_observed = false
	_guidance_progress_stage = 0
	_guidance_attack_baseline = world.attack_runtime.authorized_count
	if not _first_run_guidance_completed:
		_first_run_guidance_dismissed = false
	_transition("initializing")
	run_serial += 1
	if String(_guidance_reset_receipt.get("reason", "")) == "fresh_title_play":
		_guidance_reset_receipt["run_serial"] = run_serial
	complete_run_ledger.begin_run(run_serial, "ordinary", "retry" if _next_baseline_reason == "retry" else "title_play")
	run_elapsed = 0.0
	experience = 0
	experience_threshold = 5
	_pending_levelup_transactions = 0
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
	tester_failure_fixture_receipt.clear()
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
	upgrade_transaction_receipt.clear()
	_upgrade_commit_in_progress = false
	draft_controller.reset()
	arena_camera.reset_occlusion_response()
	arena_camera.reset_view()
	audio_director.reset_for_run()
	world.reset_session(true, "begin_run_%s" % _next_baseline_reason)
	_guidance_attack_baseline = world.attack_runtime.authorized_count
	_health_accounting_suspended = true
	health.maximum_health = STARTING_HEALTH
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
	# Retire the short-lived attack voices before tearing down entities.  This is
	# intentionally idempotent with _retire_transient_ownership and closes the
	# gap where a held Retry activation could carry a report into the fresh run.
	audio_director.reset_attack_audio_lifecycle("retry_preflight")
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
	_clear_terminal_state_for_title()
	boss_snapshot.clear()
	hud.clear_snapshot()
	world.visible = false
	_transition("title")
	shell.set_mode("hidden")
	_set_title_surface(true)
	title_menu.new_game_button.grab_focus.call_deferred()
	_emit_snapshot()

func _begin_terminal_title_handoff() -> void:
	if _terminal_handoff_active:
		return
	_terminal_handoff_generation += 1
	_terminal_handoff_active = true
	_begin_shell_title_handoff("result", "confirm")
	terminal_handoff_receipt = context_handoff_receipt.duplicate(true)

func _begin_shell_title_handoff(source: String, physical: String) -> void:
	if run_serial > 0 and run_state != "title":
		# Persist the player-caused Result/credits/settings → title traversal in
		# the same run ledger used by _enter_title. This closes the shell-back path
		# without duplicating an already observed title return.
		complete_run_ledger.record_exit(run_serial, "title", run_elapsed)
	_teardown_run("title", "return_to_title")
	_clear_terminal_state_for_title()
	boss_snapshot.clear()
	hud.clear_snapshot()
	world.visible = false
	_transition("title")
	shell.set_mode("hidden")
	_set_title_surface(false)
	_begin_context_handoff(source, "title", physical)
	_emit_snapshot()

func _clear_terminal_state_for_title() -> void:
	# Title is a clean shell surface, not a latent Result page. Retire terminal
	# ownership and pending level-up transactions after the teardown receipt has
	# captured the prior run, preventing stale victory/failure flags from leaking
	# into a later title snapshot or fresh Play transaction.
	result_committed = false
	terminal_snapshot.clear()
	terminal_commit_count = 0
	outcome = ""
	_pending_levelup_transactions = 0
	_victory_transaction_active = false
	_victory_hold_remaining = 0.0
	_victory_hold_elapsed = 0.0
	_victory_source_run_serial = -1

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
	# A valid UI activation already committed the player's destination.  Do not
	# hold the title/result handoff hostage to a later physical release: the
	# router still binds the originating transaction so the held confirm cannot
	# leak into the newly exposed page, while the receipt records the release as
	# pending for QA visibility.
	_context_handoff_active = false
	_context_handoff_generation += 1
	var activation_generation := int(transaction.get("activation_generation", -1))
	_context_handoff_destination = ""
	_context_handoff_physical = ""
	_context_handoff_activation_generation = -1
	input_router.bind_destination(physical, destination, 1)
	context_handoff_receipt = {
		"generation":_context_handoff_generation,
		"source":source, "destination":destination,
		"physical":physical,
		"originating_context":transaction.get("originating_context", source),
		"originating_context_generation":transaction.get("originating_context_generation", -1),
		"activation_generation":activation_generation,
		"shell_action_generation":shell.action_generation,
		"stage":"complete",
		"release_observed":false, "destination_exposed":true,
		"downstream_action_count":1,
		"teardown_complete":bool(teardown_receipt.get("complete", false)),
		"teardown_generation":int(teardown_receipt.get("completion_generation", 0)),
		"reset_invariants":(teardown_receipt.get("reset_invariants", {}) as Dictionary).duplicate(true),
	}
	if source == "result":
		_terminal_handoff_active = false
		terminal_handoff_receipt = context_handoff_receipt.duplicate(true)
	_complete_context_handoff(destination, true)

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
		world.visible = false
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
	audio_director.reset_attack_audio_lifecycle("pause")
	_resume_state = run_state
	# A paused run suspends dense sampling explicitly. Keep the window owner and
	# accumulated samples intact so resume can continue the same bounded window,
	# but disable the renderer timing probe while no frames are advancing.
	if _profile_active and not _profile_paused:
		_profile_paused = true
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
		validation_profile_sample["pause_lifecycle"] = {
			"phase":"paused", "process_frame":Engine.get_process_frames(),
			"elapsed_seconds":_profile_elapsed, "samples_retained":_profile_metric_samples.size(),
			"renderer_probe_enabled":false,
		}
	_transition("paused")
	# Preparation is an inspectable checkpoint, not a modal pause. Leaving the
	# tree running lets Tester invoke the separate advance edge through the
	# registered input surface; advance itself owns the brief presentation hold.
	get_tree().paused = false
	shell.set_mode("pause", last_snapshot)
	_emit_snapshot()

func _resume_run() -> void:
	get_tree().paused = false
	if _profile_active and _profile_paused:
		_profile_paused = false
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		validation_profile_sample["pause_lifecycle"] = {
			"phase":"resumed", "process_frame":Engine.get_process_frames(),
			"elapsed_seconds":_profile_elapsed, "samples_retained":_profile_metric_samples.size(),
			"renderer_probe_enabled":true,
		}
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
	if String(tester_failure_fixture_receipt.get("branch_id", "")) == "tester_failure_transaction":
		tester_failure_fixture_receipt["result_presented"] = true
		tester_failure_fixture_receipt["result_committed"] = result_committed
		tester_failure_fixture_receipt["result_commit_count"] = terminal_commit_count
		tester_failure_fixture_receipt["presentation_paused"] = get_tree().paused
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
	var drop_id := String(event.get("drop_id", ""))
	if drop_id.is_empty() or _known_reward_ids.has(drop_id):
		_reward_duplicate_rejections += 1
		_reward_spawn_receipt = {"accepted":false,"drop_id":drop_id,"reason":"missing_or_duplicate_identity"}
		_emit_snapshot()
		return
	_known_reward_ids[drop_id] = true
	# Keep the tutorial's authoritative milestone cursor monotonic with the
	# actual reward chain.  The HUD still derives copy from the live drop and
	# attraction receipts below, but this cursor makes QA resets/replays able to
	# assert that death-position drops were observed without relying on timing.
	_guidance_progress_stage = maxi(_guidance_progress_stage, 4)
	_reward_spawn_receipt = {
		"accepted":true, "phase":"spawned", "drop_id":drop_id,
		"position":event.get("position", Vector3.ZERO),
		"reward_value":event.get("reward_value", 1),
		"run_serial":run_serial,
	}
	_spawn_reward_pickup(event)
	_emit_snapshot()

func _on_reward_pickup_collected(event: Dictionary) -> void:
	var constituent_ids: Array = event.get("constituent_drop_ids", [String(event.get("drop_id", ""))])
	var accepted_ids: Array[String] = []
	for id_value in constituent_ids:
		var drop_id := String(id_value)
		if drop_id.is_empty() or _resolved_reward_ids.has(drop_id):
			continue
		_resolved_reward_ids[drop_id] = true
		accepted_ids.append(drop_id)
	if accepted_ids.is_empty():
		_reward_duplicate_rejections += 1
		return
	pickup_collected_total += 1
	_guidance_progress_stage = maxi(_guidance_progress_stage, 6)
	var base_reward := maxi(1, int(event.get("reward_value", 1)))
	var resolved_reward := maxi(1, int(round(float(base_reward) * warden.experience_yield_multiplier)))
	var experience_before := experience
	var level_before := level
	var threshold_before := experience_threshold
	experience += resolved_reward
	# Consume every crossed threshold, but serialize the resulting drafts.  A
	# merged pickup can legitimately carry enough XP for multiple levels; one
	# draft is presented at a time so held confirm cannot skip a transaction and
	# overflow remains authoritative for the next threshold.
	while experience >= experience_threshold:
		experience -= experience_threshold
		level += 1
		experience_threshold = 5 + (level - 1) * 2
		_pending_levelup_transactions += 1
	# Validate overflow against the same threshold progression used by the
	# authoritative loop.  A merged pickup can cross several levels; subtracting
	# only the starting threshold would falsely report a lost remainder and make
	# the HUD/result evidence disagree with the build state.
	var expected_experience := experience_before + resolved_reward
	var expected_level := level_before
	var expected_threshold := threshold_before
	while expected_experience >= expected_threshold:
		expected_experience -= expected_threshold
		expected_level += 1
		expected_threshold = 5 + (expected_level - 1) * 2
	_reward_collection_receipt = event.duplicate(true)
	_reward_collection_receipt.merge({
		"accepted":true, "phase":"collected", "resolved_drop_ids":accepted_ids,
		"resolved_identity_count":accepted_ids.size(), "exactly_once":true,
		"run_serial":run_serial,
	}, true)
	_reward_experience_receipt = {
		"phase":"experience_applied", "reward_value":resolved_reward,
		"experience_before":experience_before, "experience_after":experience,
		"threshold_before":threshold_before, "threshold_after":experience_threshold,
		"level_before":level_before, "level_after":level,
		"overflow_preserved":experience == expected_experience and level == expected_level and experience_threshold == expected_threshold,
		"expected_overflow":expected_experience,
		"expected_level":expected_level,
		"expected_threshold":expected_threshold,
		"hud_interpolation_requested":true,
	}
	# Publish the completed drop -> collection -> experience handoff before the
	# modal owns pause.  The previous ordering opened the draft first, so the
	# snapshot emitted during `present()` could still contain the prior pickup
	# receipt; a tester (or the HUD) then saw a level-up with no causal pickup
	# feedback.  Receipts are now authoritative before the draft transition.
	reward_collected.emit(_reward_collection_receipt.duplicate(true))
	if _pending_levelup_transactions > 0:
		_open_upgrade_draft()
	_emit_snapshot()

func _on_reward_attraction_started(event: Dictionary) -> void:
	_guidance_progress_stage = maxi(_guidance_progress_stage, 5)
	_reward_attraction_receipt = event.duplicate(true)
	_reward_attraction_receipt["run_serial"] = run_serial
	_emit_snapshot()

func _on_reward_pickup_retired(event: Dictionary) -> void:
	var instance_id := int(event.get("instance_id", 0))
	var retired_pickup: RewardPickup = _active_pickups.get(instance_id) as RewardPickup
	if _active_pickups.erase(instance_id):
		_active_pickup_count = _active_pickups.size()
		if is_instance_valid(retired_pickup) and not _pickup_pool.has(retired_pickup):
			_pickup_pool.append(retired_pickup)
	if not _teardown_active and run_state in ["active", "boss", "draft"] and _active_pickup_count < MAX_ACTIVE_PICKUPS and not _pending_reward_events.is_empty():
		var pending: Dictionary = _pending_reward_events.pop_front()
		_spawn_reward_pickup(pending, false)
		_emit_snapshot()

func _spawn_reward_pickup(event: Dictionary, allow_defer: bool = true) -> RewardPickup:
	if _active_pickup_count >= MAX_ACTIVE_PICKUPS:
		var merge_target: RewardPickup
		for pickup_value in _active_pickups.values():
			if not is_instance_valid(pickup_value):
				continue
			var candidate := pickup_value as RewardPickup
			if not candidate.can_accept_merge(String(event.get("drop_id", ""))):
				continue
			if not is_instance_valid(merge_target) or candidate.age > merge_target.age:
				merge_target = candidate
		if is_instance_valid(merge_target) and merge_target.merge_reward(event):
			pickup_spawned_total += 1
			_reward_spawn_receipt["disposition"] = "merged_at_visual_cap"
			_reward_spawn_receipt["owner_instance_id"] = merge_target.get_instance_id()
			_reward_spawn_receipt["active_after"] = _active_pickup_count
			return merge_target
		if allow_defer:
			_queue_pending_reward(event)
			_reward_cap_deferrals += 1
			_reward_spawn_receipt["disposition"] = "deferred_until_collection_fx_retires"
			_reward_spawn_receipt["pending_count"] = _pending_reward_events.size()
			_reward_spawn_receipt["active_after"] = _active_pickup_count
		return null
	var pickup: RewardPickup
	while not _pickup_pool.is_empty() and not is_instance_valid(_pickup_pool.back()):
		_pickup_pool.pop_back()
	if not _pickup_pool.is_empty():
		pickup = _pickup_pool.pop_back()
	else:
		if _pickup_total >= PICKUP_POOL_CAP:
			if allow_defer: _queue_pending_reward(event)
			_reward_cap_deferrals += 1
			return null
		pickup = REWARD_PICKUP_SCENE.instantiate() as RewardPickup
		world.add_child(pickup)
		_pickup_total += 1
	pickup.configure(warden, event)
	if not pickup.collected.is_connected(_on_reward_pickup_collected): pickup.collected.connect(_on_reward_pickup_collected)
	if not pickup.attraction_started.is_connected(_on_reward_attraction_started): pickup.attraction_started.connect(_on_reward_attraction_started)
	if not pickup.retired.is_connected(_on_reward_pickup_retired): pickup.retired.connect(_on_reward_pickup_retired)
	_active_pickups[pickup.get_instance_id()] = pickup
	_active_pickup_count = _active_pickups.size()
	pickup_spawned_total += 1
	_reward_spawn_receipt["disposition"] = "instanced_world_drop"
	_reward_spawn_receipt["owner_instance_id"] = pickup.get_instance_id()
	_reward_spawn_receipt["active_after"] = _active_pickup_count
	return pickup

func _queue_pending_reward(event: Dictionary) -> void:
	if _pending_reward_events.size() < MAX_PENDING_REWARDS:
		_pending_reward_events.append(event.duplicate(true))
		return
	# A pathological same-frame collection burst remains bounded by coalescing
	# only pending (not yet presented) identities. Reward value and every
	# constituent ID survive and will enter one normal world owner on retirement.
	var aggregate: Dictionary = _pending_reward_events[-1]
	var ids: Array = aggregate.get("constituent_drop_ids", [String(aggregate.get("drop_id", ""))])
	var next_id := String(event.get("drop_id", ""))
	if not next_id.is_empty() and not ids.has(next_id):
		ids.append(next_id)
	aggregate["constituent_drop_ids"] = ids
	aggregate["reward_value"] = int(aggregate.get("reward_value", 1)) + maxi(1, int(event.get("reward_value", 1)))
	aggregate["position"] = event.get("position", aggregate.get("position", Vector3.ZERO))
	_pending_reward_events[-1] = aggregate

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
		# Diagnostics use the shipped authoritative drop route as well. The
		# diagnostic route marker still prevents qualification, while identity
		# accounting and cleanup remain identical to ordinary play.
		_on_reward_dropped(event)
		seeded += 1
	return seeded

func _on_encounter_changed(_snapshot: Dictionary) -> void:
	_try_begin_passive_ordinary_profile()
	_emit_snapshot()

func _on_build_changed(_snapshot: Dictionary) -> void:
	_emit_snapshot()

func _on_dash_changed(_phase: String, _invulnerable: bool) -> void:
	if _phase == "active":
		_guidance_dash_observed = true
		_guidance_progress_stage = maxi(_guidance_progress_stage, 2)
	_emit_snapshot()

func _on_logical_press_edge(action: StringName, activation: int, receipt: Dictionary) -> void:
	if action == &"pause":
		var physical := String(receipt.get("physical", "back"))
		var accepted := false
		# Escape is the single physical pause owner, but its destination remains
		# context-aware. A draft must cancel its transaction, nested shell pages
		# return to their owner, and Result returns to Title; none of these paths
		# should also toggle SceneTree pause or dispatch ui_cancel a second time.
		if run_state == "draft":
			accepted = _on_draft_cancel()
		elif run_state in ["settings", "help", "credits"]:
			_return_from_shell_page()
			accepted = true
		elif run_state == "result":
			_begin_terminal_title_handoff()
			accepted = true
		elif run_state == "title" and shell.mode in ["settings", "help", "credits"]:
			_return_from_shell_page()
			accepted = true
		elif run_state in ["active", "boss"] and not get_tree().paused:
			_pause_run()
			accepted = true
		elif run_state == "paused":
			_resume_run()
			accepted = true
		input_router.bind_destination(physical, "pause_toggled" if accepted else "pause_rejected", 1 if accepted else 0)
		return
	if action == &"ui_cancel" and run_state == "draft":
		var cancelled := _on_draft_cancel()
		input_router.bind_destination("back", "upgrade_draft_cancelled" if cancelled else "upgrade_draft_cancel_rejected", 1 if cancelled else 0)
		return
	if action == &"context_back":
		var destination := "context_back_ignored"
		var count := 0
		if run_state == "draft":
			var cancelled := _on_draft_cancel()
			destination = "upgrade_draft_cancelled" if cancelled else "upgrade_draft_cancel_rejected"
			count = 1 if cancelled else 0
		elif run_state in ["settings", "help"] and shell.return_mode == "pause":
			_return_from_shell_page()
			destination = "pause_page_returned"
			count = 1
		elif run_state == "title" and shell.mode in ["settings", "help", "credits"]:
			_return_from_shell_page()
			destination = "title_page_returned"
			count = 1
		input_router.bind_destination("back", destination, count)
		return
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

func _on_draft_cancel() -> bool:
	if _upgrade_commit_in_progress or run_state != "draft" or not draft_controller.active:
		return false
	var cancelled := draft_controller.cancel()
	if not cancelled:
		return false
	draft_view.close()
	get_tree().paused = false
	# A level-up can occur during the fifth wave while the Bellkeeper is
	# entering or already present. Resume the state that owns the current
	# encounter rather than downgrading the boss route to ordinary active play.
	var wave_snapshot := wave_director.get_snapshot()
	var resume_state := "boss" if is_instance_valid(boss) or int(wave_snapshot.get("wave", 0)) == 5 else "active"
	_transition(resume_state)
	upgrade_transaction_receipt["phase"] = "cancelled"
	upgrade_transaction_receipt["resolved"] = false
	upgrade_transaction_receipt["cancelled"] = true
	upgrade_transaction_receipt["cancel_reason"] = "back_or_escape"
	upgrade_transaction_receipt["tree_paused"] = false
	upgrade_transaction_receipt["pause_owner_cleared"] = true
	upgrade_transaction_receipt["reset_isolation"] = {
		"complete":true,
		"tree_paused":false,
		"draft_active":false,
		# Preserve the owner that resumes the encounter.  A level-up during the
		# Bellkeeper wave must return to boss ownership; serializing `active`
		# here made the receipt contradict the authoritative transition below.
		"run_state":resume_state,
		"active_enemy_count":int(spawner.get_snapshot().get("live", 0)),
		"pending_levelup_transactions":_pending_levelup_transactions,
	}
	_emit_snapshot()
	return true

func _on_input_context_changed(_previous: String, current: String, _generation: int) -> void:
	if current not in ["active", "boss"]:
		warden.clear_dash_ownership("context_%s" % current)

func _on_input_device_changed(_previous: String, current: String, generation: int) -> void:
	draft_view.set_input_device(current, generation)

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
		&"help": _open_help_page()
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

func _open_help_page() -> void:
	if run_state == "paused":
		_transition("help")
		get_tree().paused = true
		shell.set_mode("help", last_snapshot)
	_emit_snapshot()

func _open_credits_page() -> void:
	if run_state in ["title", "result"]:
		_set_title_surface(false)
		shell.set_mode("credits")
		complete_run_ledger.record_credits(run_serial, shell.mode)
		if run_state == "result":
			get_tree().paused = true
	_emit_snapshot()

func _return_from_shell_page() -> void:
	if shell.return_mode == "pause" and run_state in ["settings", "help"]:
		get_tree().paused = true
		_transition("paused")
		shell.set_mode("pause", last_snapshot)
		_begin_context_handoff(shell.mode, "pause", "back")
		_emit_snapshot()
	elif shell.return_mode == "result" and run_state == "result":
		get_tree().paused = true
		shell.set_mode("result", terminal_snapshot)
		_emit_snapshot()
	else:
		var source := shell.mode
		if run_serial > 0 and run_state != "title":
			complete_run_ledger.record_exit(run_serial, "title", run_elapsed)
		_teardown_run("title", "return_from_%s" % source)
		_clear_terminal_state_for_title()
		boss_snapshot.clear()
		hud.clear_snapshot()
		world.visible = false
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
	# Drafts are legal during the Bellkeeper wave as well as ordinary pressure.
	# The boss state remains authoritative after the transaction, so allowing the
	# modal here prevents final-wave level-ups from becoming inert.
	if run_state not in ["active", "boss"] or draft_controller.active:
		return
	warden.reset_input_latch("draft")
	arena_camera.reset_occlusion_response()
	_transition("draft")
	get_tree().paused = true
	var opened := draft_controller.open_draft(inventory, health, warden)
	upgrade_transaction_receipt = {
		"transaction_id":"upgrade.r%04d.d%04d" % [run_serial, draft_controller.draft_serial],
		"phase":"requested", "run_serial":run_serial,
		"draft_serial":draft_controller.draft_serial,
		"pause_owner":"upgrade_draft", "tree_paused":get_tree().paused,
		"choice_count":opened.size(), "resolved":false,
	}
	if opened.is_empty():
		# Never leave an authoritative pause behind when the catalog cannot
		# produce the required three eligible choices. Preserve the encounter
		# owner when this happens during wave five; dropping back to ordinary
		# active here would silently disable Bellkeeper timing and make a
		# malformed/exhausted catalog strand the run in the wrong state.
		get_tree().paused = false
		var wave_snapshot := wave_director.get_snapshot()
		var resume_state := "boss" if is_instance_valid(boss) or int(wave_snapshot.get("wave", 0)) == 5 else "active"
		_transition(resume_state)
		# Keep the authoritative router state aligned even when a tester invokes
		# the transaction boundary while the tree is frozen (there is no process
		# tick available to perform the usual deferred context sync).
		input_router._sync_context()
		_pending_levelup_transactions = maxi(0, _pending_levelup_transactions - 1)
		upgrade_transaction_receipt["phase"] = "rejected_no_eligible_choices"
		upgrade_transaction_receipt["resume_state"] = resume_state
		upgrade_transaction_receipt["pause_owner_cleared"] = not get_tree().paused
		upgrade_transaction_receipt["pending_levelup_transactions"] = _pending_levelup_transactions

func _on_draft_opened(cards: Array[Dictionary]) -> void:
	draft_view.present(cards)
	_emit_snapshot()

func _on_draft_choice(index: int) -> void:
	# The authoritative modal owner is run_state. External tester freeze can
	# temporarily virtualize SceneTree.paused while dispatching input; rejecting
	# that valid release edge would leave a latched card with no applied choice.
	if _upgrade_commit_in_progress or run_state != "draft":
		return
	_upgrade_commit_in_progress = true
	upgrade_transaction_receipt["phase"] = "committing"
	upgrade_transaction_receipt["requested_index"] = index
	var choice := draft_controller.choose(index, inventory, health, warden)
	if choice.is_empty():
		upgrade_transaction_receipt["phase"] = "rejected_ineligible"
		draft_view.reject_choice()
		_upgrade_commit_in_progress = false
		_emit_snapshot()
		return
	var wave_state := wave_director.get_snapshot()
	choice["draft_serial"] = draft_controller.draft_serial
	choice["accepted_at_elapsed"] = run_elapsed
	choice["accepted_at_wave_id"] = String((wave_state.get("definition", {}) as Dictionary).get("id", "warmup"))
	choice["route_kind"] = run_route_kind
	choice["natural_choice"] = run_route_kind == "ordinary" and int(wave_state.get("diagnostic_jump_count", 0)) == 0
	choice["truthful_transaction"] = bool((choice.get("application", {}) as Dictionary).get("accepted", false)) and bool((choice.get("application", {}) as Dictionary).get("matches_projection", false))
	selected_upgrades.append(choice)
	if bool(choice.get("natural_choice", false)) and not _first_run_guidance_completed:
		_first_run_guidance_completed = true
		_first_run_guidance_dismissed = true
		_first_run_guidance_completion = {
			"completed":true,
			"run_serial":run_serial,
			"draft_serial":draft_controller.draft_serial,
			"upgrade_id":String(choice.get("id", "")),
			"elapsed":run_elapsed,
			"stages_taught":["movement_and_automatic_attack", "world_drop", "attraction_and_collection", "natural_upgrade_draft"],
		}
	complete_run_ledger.record_draft(choice, run_elapsed, run_route_kind, int(wave_state.get("diagnostic_jump_count", 0)))
	draft_view.close()
	get_tree().paused = false
	# Preserve boss-state ownership when the draft was opened from wave five;
	# Bellkeeper timing and HUD presentation must continue under the boss state
	# after the selected upgrade is committed.
	var resume_state := "boss" if is_instance_valid(boss) or int(wave_state.get("wave", 0)) == 5 else "active"
	_transition(resume_state)
	# The draft owns a paused tree, so synchronize immediately before emitting
	# the resolved receipt; this makes the selected upgrade and active input
	# context observable in the same authoritative frame for tester recapture.
	input_router._sync_context()
	upgrade_transaction_receipt["phase"] = "resolved"
	upgrade_transaction_receipt["resolved"] = true
	upgrade_transaction_receipt["applied_upgrade_id"] = String(choice.get("id", ""))
	upgrade_transaction_receipt["tree_paused"] = get_tree().paused
	upgrade_transaction_receipt["pause_owner_cleared"] = not get_tree().paused and not draft_controller.active
	upgrade_transaction_receipt["requested"] = true
	upgrade_transaction_receipt["reset_isolation"] = {
		"complete":true,
		"tree_paused":false,
		"draft_active":false,
		"run_state":resume_state,
		"active_enemy_count":int(spawner.get_snapshot().get("live", 0)),
		"pending_levelup_transactions":_pending_levelup_transactions,
	}
	_pending_levelup_transactions = maxi(0, _pending_levelup_transactions - 1)
	(upgrade_transaction_receipt["reset_isolation"] as Dictionary)["pending_levelup_transactions"] = _pending_levelup_transactions
	if _pending_levelup_transactions > 0:
		_open_upgrade_draft()
	_upgrade_commit_in_progress = false
	_emit_snapshot()

func _on_wave_phase_changed(snapshot: Dictionary) -> void:
	var phase := String(snapshot.get("phase", ""))
	if phase == "intermission":
		# Intermission owns the pressure handoff. Retire ordinary wave actors so
		# no stale spawns leak across the boundary; the next active phase
		# reconfigures and begins the encounter deterministically.
		spawner.stop_encounter()
		_emit_snapshot()
		return
	if phase == "active":
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
	# The director is authoritative for boss timing.  Ignore stale/deferred
	# requests that arrive after teardown or from a non-final diagnostic wave.
	var requested_wave := wave_director.get_snapshot()
	var requested_definition: Dictionary = requested_wave.get("definition", {})
	if not bool(requested_definition.get("boss_wave", false)):
		return
	if String(requested_wave.get("phase", "")) != "active":
		return
	boss = BELLKEEPER_SCENE.instantiate() as BellkeeperActor
	var boss_anchor := world.get_node("BossAnchor") as Node3D
	# Rebase the encounter onto the authored cracked-bell landmark. The old
	# fixed anchor was inside the mausoleum sightline after native package scale
	# calibration, so the Bellkeeper could begin completely occluded. Keep it on
	# the same native street datum, just south of the bell for a clear approach.
	var bell_anchor := world.arena_contract.get_node_or_null("OuterDatum/CrackedMoonBellAnchor") as Node3D
	if is_instance_valid(bell_anchor):
		boss_anchor.global_position = bell_anchor.global_position + Vector3(0.0, 0.05, 5.2)
	else:
		boss_anchor.global_position = Vector3(8.6, 0.05, 6.2)
	boss_anchor.set_meta("encounter_anchor", "authored_cracked_bell_south_approach")
	boss_anchor.set_meta("encounter_anchor_position", boss_anchor.global_position)
	boss_anchor.add_child(boss)
	boss.position = Vector3.ZERO
	boss.configure(warden, spawner.neighbor_registry)
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
	# The director owns the authoritative route outcome.  Keep the authored
	# victory presentation hold in RunController, but commit the director to the
	# exact product terminal token immediately so spawn/attack gates and result
	# receipts agree during the hold.
	wave_director.terminate("victory")
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
		"ordinary_boss_entry_ready":bool(wave_state.get("ordinary_boss_entry_ready", false)),
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
	# Terminal presentation must not deadlock Result when an optional victory
	# stream is unavailable or the backend retires a voice without emitting the
	# `finished` callback.  The audio director remains authoritative for source
	# ownership; this fallback only accepts the already-completed visual hold
	# when no terminal voice is active or pending.  A playing/pending voice still
	# gates the handoff, preserving the authored cue when it is available.
	var terminal_audio_state := audio_director._mcp_state()
	var terminal_voice: Dictionary = terminal_audio_state.get("terminal_voice", {})
	var terminal_voice_idle := not bool(terminal_voice.get("playing", false)) and not bool(audio_director.terminal_voice_start_pending)
	var audio_handoff_ready := audio_source_completed or terminal_voice_idle
	ordinary_victory_receipt["presentation_hold"]["audio_handoff_ready"] = audio_handoff_ready
	ordinary_victory_receipt["presentation_hold"]["terminal_voice_idle"] = terminal_voice_idle
	if _victory_hold_remaining <= 0.0 and wall_elapsed >= VICTORY_PRESENTATION_HOLD_SECONDS and audio_handoff_ready:
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
	terminal_snapshot["completion_reason"] = "bellkeeper_defeated" if terminal_outcome == "victory" else "warden_health_depleted"
	terminal_snapshot["committed"] = true
	terminal_snapshot["commit_run_serial"] = run_serial
	terminal_snapshot["commit_count"] = terminal_commit_count
	terminal_snapshot["route_kind"] = run_route_kind
	terminal_snapshot["natural_build_history"] = selected_upgrades.duplicate(true)
	terminal_snapshot["build_identity"] = (inventory.get_snapshot().get("build_identity", {}) as Dictionary).duplicate(true)
	terminal_snapshot["attack_pattern_receipt"] = {
		"lantern":lantern_runtime._mcp_state() if is_instance_valid(lantern_runtime) else {},
		"gravespade":gravespade_runtime._mcp_state() if is_instance_valid(gravespade_runtime) else {},
		"wisps":wisps_runtime._mcp_state() if is_instance_valid(wisps_runtime) else {},
	}
	terminal_snapshot["boss_transition_history"] = boss_transition_history.duplicate(true)
	terminal_snapshot["terminal_animation"] = warden.animation_binding.get_snapshot() if warden.animation_binding else {}
	# Carry the renderer/build guards into the immutable terminal receipt.  The
	# ledger can then reject llvmpipe/software rows without treating an ordinary
	# run with no dense-profile sample as failed evidence.
	# Ordinary runs often finish without an active dense window.  In that case
	# the terminal receipt still needs the live renderer identity; otherwise the
	# ledger sees an empty/unknown renderer and could accidentally admit a
	# software-rendered victory as a release-qualified build row.  Reuse the
	# authoritative renderer probe when no profile sample owns the field.
	var renderer_receipt: Dictionary = validation_profile_sample.get("renderer", {})
	if renderer_receipt.is_empty():
		renderer_receipt = _profile_renderer_receipt()
	terminal_snapshot["renderer_classification"] = String(renderer_receipt.get("classification", validation_profile_sample.get("renderer_classification", "unknown")))
	var renderer_gate_status := String(validation_profile_sample.get("renderer_gate_status", validation_profile_receipt.get("renderer_gate_status", "")))
	if renderer_gate_status.is_empty() or renderer_gate_status == DenseWaveProfileClass.UNKNOWN_STATUS:
		renderer_gate_status = DenseWaveProfileClass.renderer_status(
			String(renderer_receipt.get("classification", "unknown")),
			bool(renderer_receipt.get("hardware_qualification_eligible", false))
		)
	terminal_snapshot["renderer_gate_status"] = renderer_gate_status
	terminal_snapshot["release_build_guard"] = run_route_kind == "ordinary" and int(wave_director.get_snapshot().get("diagnostic_jump_count", 0)) == 0
	if terminal_outcome == "victory":
		terminal_snapshot["victory_transaction"] = ordinary_victory_receipt.duplicate(true)
	var wave_state := wave_director.get_snapshot()
	# Victory teardown terminates the director before the presentation hold
	# commits the Result. Preserve the authoritative fifth-wave route captured at
	# boss defeat instead of re-reading a potentially terminal director snapshot.
	if terminal_outcome == "victory" and int(ordinary_victory_receipt.get("source_run_serial", -1)) == run_serial:
		var victory_wave_ids: Array = ordinary_victory_receipt.get("wave_ids", [])
		if not victory_wave_ids.is_empty():
			wave_state["ordinary_route_wave_ids"] = victory_wave_ids.duplicate()
			wave_state["ordinary_route_complete"] = bool(ordinary_victory_receipt.get("ordinary_route_complete", false))
			wave_state["ordinary_route_eligible"] = bool(ordinary_victory_receipt.get("ordinary_route_eligible", false))
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
	_apply_dense_quality_profile(false)
	_victory_fixture_commit_held = false
	_victory_fixture_hold_generation = -1
	_teardown_generation += 1
	get_tree().paused = false
	warden.reset_input_latch("teardown_%s_%s" % [route, reason])
	draft_controller.reset()
	draft_view.close()
	arena_camera.reset_occlusion_response()
	arena_camera.reset_view()
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
		warden.reset_for_run(world.arena_contract.get_player_spawn(), "title")
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
	# The editor-only dense-profile reset is a first-class lifecycle reset just
	# like Retry/fresh start.  Keep the invariant receipt explicit so host
	# recapture can distinguish a verified baseline from an ordinary teardown.
	var reset_expected := destination in ["title", "retry", "fresh_start", "profile_reset", "validation_profile_reset"]
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
		"input_reset": {
			"router_generation":input_router.reset_generation,
			"warden_generation":warden.reset_generation,
			"router_receipt":input_router.last_reset_receipt.duplicate(true),
			"warden_receipt":warden.last_reset_receipt.duplicate(true),
		},
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
	var pending_rewards_retired := _pending_reward_events.size()
	_pending_reward_events.clear()
	var retired_pickups := 0
	for pickup_value in _active_pickups.values().duplicate():
		var pickup := pickup_value as RewardPickup
		if is_instance_valid(pickup):
			retired_pickups += 1
			pickup.retire_for_pool("run_teardown")
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
		"pending_rewards_retired":pending_rewards_retired,
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
	if is_instance_valid(arena_camera):
		arena_camera.set_shell_state(next_state)
	state_history.append(next_state)
	state_changed.emit(previous, next_state)

func _record_profile_control_rejection(requested_profile: String, reason: String) -> void:
	# Keep tester controls auditable even when invoked before an ordinary run is
	# active.  A rejected control must never mutate gameplay state or masquerade
	# as a native qualification receipt.
	var renderer_receipt := _profile_renderer_receipt()
	var renderer_status := DenseWaveProfileClass.renderer_status(
		String(renderer_receipt.get("classification", "unknown")),
		bool(renderer_receipt.get("hardware_qualification_eligible", false))
	)
	var cycle_provenance := {
		"identity": "mournlight.native_dense_three_cycle.v1",
		"cycle_index": _dense_cycle_index,
		"cycle_id": "",
		"branch_id": "final_wave_bellkeeper_profile",
		"run_serial": run_serial,
		"setup_generation": _validation_setup_generation,
		"advance_generation": _profile_advance_generation,
		"phase": "control_rejected",
	}
	validation_profile_receipt = {
		"contract_id": DenseWaveProfileClass.CONTRACT_ID,
		"contract_version": DenseWaveProfileClass.CONTRACT_VERSION,
		"contract_signature": DenseWaveProfileClass.CONTRACT_SIGNATURE,
		"accepted": false,
		"status": "rejected",
		"requested_profile": requested_profile,
		"resolved_profile": "control_rejected",
		"rejection_reason": reason,
		"run_state": run_state,
		"run_serial": run_serial,
		"setup_generation": _validation_setup_generation,
		"requested_density": DenseWaveProfileClass.TARGET_ENEMIES,
		"resolved_density": 0,
		"target_density": DenseWaveProfileClass.TARGET_ENEMIES,
		"target_viewport": {"width": 1920, "height": 1080},
		"viewport": _profile_viewport_receipt(),
		"renderer": renderer_receipt,
		"renderer_gate_status": renderer_status,
		"qualification_mode": DenseWaveProfileClass.QUALIFICATION_MODE,
		"host_handoff": DenseWaveProfileClass.host_handoff_contract(),
		"phase_sample_availability": {},
		"requested_resolved_receipt": {"requested":DenseWaveProfileClass.TARGET_ENEMIES,"resolved":0,"reset_isolation":false},
		"timeout_safe": true,
		"cycle_provenance": cycle_provenance,
		"preflight": DenseWaveProfileClass.preflight(
			renderer_receipt,
			_profile_viewport_receipt(),
			Engine.get_process_frames(),
			Engine.get_process_frames(),
			0,
			0,
			"control_rejected",
			cycle_provenance,
			{"required": true, "pending": false}
		),
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_record_profile_cycle("control_rejected", validation_profile_receipt)
	_emit_snapshot()

func _prepare_final_profile() -> void:
	# Dense qualification is a tester-only protocol, not merely an editor
	# convenience. Use the shared contract predicate so an exported build can
	# never enter diagnostic preparation even if a stale caller reaches this
	# private entrypoint.
	if not DenseWaveProfileClass.tester_guard():
		return
	if _profile_active or _dense_cycle_requires_reset():
		return
	if run_state not in ["active", "boss"]:
		_record_profile_control_rejection("tester_dense_prepare", "ordinary_run_required:%s" % run_state)
		return
	input_router.clear_transaction_latches("tester_dense_prepare")
	# Isolate expensive shadow/glow work behind a deterministic profile-owned
	# wrapper before admitting the 32-enemy cohort. This keeps native captures
	# within the frame budget without changing combat, silhouettes, or ordinary
	# route presentation.
	_apply_dense_quality_profile(true)
	_dense_cycle_index += 1
	_profile_active = false
	_profile_paused = false
	_profile_origin = "diagnostic_prepared"
	run_route_kind = "diagnostic_prepared"
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_metric_samples.clear()
	_profile_elapsed = 0.0
	_profile_sample_accumulator = 0.0
	_profile_observation_stride = 0
	_profile_last_system_observation.clear()
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
	# Re-apply the resolved final-wave pressure immediately before admission so
	# frozen diagnostic preparation cannot observe a stale ordinary live cap.
	var final_definition: Dictionary = wave_director.get_snapshot().get("definition", {})
	if String(final_definition.get("id", "")) == "bellkeeper":
		spawner.configure_pressure(final_definition)
	var attack_count_before := world.attack_runtime.authorized_count
	var preparation := spawner.prepare_validation_density(32)
	var frontline := spawner.prepare_validation_frontline(6)
	var seeded_pickups := _seed_profile_pickups(6)
	if not is_instance_valid(boss):
		_spawn_bellkeeper()
	if is_instance_valid(boss):
		boss_snapshot = boss.get_snapshot().duplicate(true)
	_transition("boss")
	_validation_setup_generation += 1
	var encounter := spawner.get_snapshot()
	get_tree().paused = true
	var renderer_receipt := _profile_renderer_receipt()
	var prepare_process_frame := Engine.get_process_frames()
	var cycle_provenance := _dense_cycle_provenance("prepare", run_serial, _validation_setup_generation, 0)
	var setup_valid := bool(preparation.get("accepted",false)) and is_instance_valid(boss)
	validation_profile_receipt = {
		"contract_id":DenseWaveProfileClass.CONTRACT_ID,
		"contract_version":DenseWaveProfileClass.CONTRACT_VERSION,
		"contract_signature":DenseWaveProfileClass.CONTRACT_SIGNATURE,
		"diagnostic_only":true,
		"release_export_available":false,
		# Setup validity is independent from renderer qualification. A software
		# renderer must still run the real four-second collector so frame/entity/
		# lifecycle diagnostics remain useful; only the final qualification gate
		# rejects it. Keep both fields explicit for host receipts.
		"accepted":setup_valid,
		"setup_valid":setup_valid,
		"status":DenseWaveProfileClass.renderer_status(String(renderer_receipt.get("classification", "unknown")), bool(renderer_receipt.get("hardware_qualification_eligible", false))),
		"branch_id":"final_wave_bellkeeper_profile",
		"run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"advance_generation":0,
		"cycle_index":_dense_cycle_index,
		"cycle_id":cycle_provenance.get("cycle_id", ""),
		"requested_density":32,
		"resolved_density":int(encounter.get("live",0)),
		"target_viewport":{"width":1920,"height":1080},
		"target_density":DenseWaveProfileClass.TARGET_ENEMIES,
		"frontline_positioning":frontline,
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
		"dense_quality_profile":_dense_quality_receipt.duplicate(true),
		"workload":_profile_workload_receipt(encounter),
		"lifecycle":_lifecycle_counters(),
		"viewport":_profile_viewport_receipt(),
		"renderer":renderer_receipt,
		"qualification_mode":DenseWaveProfileClass.QUALIFICATION_MODE,
		"qualification_contract":DenseWaveProfileClass.qualification_contract(),
		"host_handoff":DenseWaveProfileClass.host_handoff_contract(),
		"renderer_gate_status":DenseWaveProfileClass.renderer_status(String(renderer_receipt.get("classification", "unknown")), bool(renderer_receipt.get("hardware_qualification_eligible", false))),
		"preflight":DenseWaveProfileClass.preflight(renderer_receipt, _profile_viewport_receipt(), prepare_process_frame, Engine.get_process_frames(), 0, 0, "prepare", cycle_provenance, {"required":true,"pending":true}),
		"cycle_provenance":cycle_provenance,
		"requested_profile":"representative_final_wave_and_bellkeeper",
		"resolved_profile":"prepared_paused",
		"preparation_paused":get_tree().paused,
		"attacks_advanced_by_preparation":world.attack_runtime.authorized_count != attack_count_before,
		"terminal_state_advanced":result_committed,
		"advance_action_required":true,
		"reset_isolation_pending":true,
		"phase_sample_availability":{"prepare":{"frames_ran":false,"frame_sample_count":0,"physics_sample_count":0,"samples_available":false}},
		"requested_resolved_receipt":{"requested":32,"resolved":int(encounter.get("live",0)),"reset_isolation":false},
		"timeout_policy":"bounded_pending_until_advance_complete_or_reset",
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_record_profile_cycle("prepare", validation_profile_receipt)
	_emit_snapshot()

# Explicit editor-only lifecycle boundaries for the host-owned dense collector.
# These wrappers return the persisted receipt from the same call that performs
# the transition, avoiding an outcome-unknown gap between an input dispatch and
# a later state read. They never exist in release builds and do not alter the
# ordinary route.
func tester_dense_prepare() -> Dictionary:
	if not DenseWaveProfileClass.tester_guard():
		return {"accepted":false,"status":"release_disabled","phase":"prepare"}
	# Prepare owns the cycle boundary. A delayed duplicate must never tear down
	# an active sampling window or silently replace its setup generation.
	if _profile_active or _dense_cycle_requires_reset():
		var active_receipt := validation_profile_receipt.duplicate(true)
		active_receipt["control_rejection"] = "prepare_requires_reset" if not _profile_active else "prepare_already_active_idempotent"
		return active_receipt
	_prepare_final_profile()
	return validation_profile_receipt.duplicate(true)

func tester_dense_advance() -> Dictionary:
	if not DenseWaveProfileClass.tester_guard():
		return {"accepted":false,"status":"release_disabled","phase":"advance"}
	if _profile_active:
		var sampling_receipt := validation_profile_sample.duplicate(true)
		sampling_receipt["control_rejection"] = "advance_already_active_timeout_safe"
		sampling_receipt["timeout_safe"] = true
		return sampling_receipt
	# Exactly one advance is admitted for each prepare/reset cycle. Once the
	# window has completed, a late duplicate is rejected until reset archives it.
	if String(validation_profile_sample.get("status", "")) == "complete" or String(validation_profile_receipt.get("phase", "")) == "advance_complete":
		var completed_receipt := validation_profile_sample.duplicate(true)
		completed_receipt["control_rejection"] = "advance_already_complete_reset_required"
		return completed_receipt
	_advance_final_profile()
	return validation_profile_sample.duplicate(true)

func tester_dense_reset() -> Dictionary:
	if not DenseWaveProfileClass.tester_guard():
		return {"accepted":false,"status":"release_disabled","phase":"reset"}
	# Reset is idempotent across delayed collector callbacks. The first reset
	# already restores an ordinary run and publishes its isolation receipt;
	# repeating it must not create another run serial or teardown generation.
	if bool(validation_profile_receipt.get("reset", false)) and not _profile_active:
		var reset_receipt := validation_profile_receipt.duplicate(true)
		reset_receipt["control_rejection"] = "reset_already_complete_idempotent"
		return reset_receipt
	_reset_final_profile()
	return validation_profile_receipt.duplicate(true)

func _dense_cycle_requires_reset() -> bool:
	"""A completed prepare/advance cycle must be retired before re-preparing."""
	if bool(validation_profile_receipt.get("reset", false)):
		return false
	if bool(validation_profile_receipt.get("setup_valid", false)) and bool(validation_profile_receipt.get("preparation_paused", false)):
		return true
	if String(validation_profile_receipt.get("phase", "")) == "advance_complete":
		return true
	var sample_status := String(validation_profile_sample.get("status", ""))
	return sample_status in ["sampling", "complete"]

func _advance_final_profile() -> void:
	if not DenseWaveProfileClass.tester_guard():
		return
	if _profile_active:
		# A second advance can arrive while the host collector is still waiting on
		# the first window. Keep the original sampling owner intact and publish a
		# bounded pending receipt instead of replaying an outcome-unknown edge.
		return
	if String(validation_profile_sample.get("status", "")) == "complete" or String(validation_profile_receipt.get("phase", "")) == "advance_complete":
		return
	# Do not suppress sampling merely because the preflight renderer was marked
	# software/unknown. The collector must observe real entities and frame
	# execution before applying the native qualification gate. Reject only an
	# invalid setup (missing workload or Bellkeeper).
	if not bool(validation_profile_receipt.get("setup_valid", validation_profile_receipt.get("accepted", false))):
		_record_profile_control_rejection("tester_dense_advance", "accepted_prepare_required")
		return
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_metric_samples.clear()
	_profile_elapsed = 0.0
	_profile_sample_accumulator = 0.0
	_profile_observation_stride = 0
	_profile_last_system_observation.clear()
	_profile_sample_counter_reads = 0
	_profile_active = true
	_profile_paused = false
	_profile_origin = "diagnostic_prepared"
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_profile_advance_generation += 1
	_profile_process_frame_start = Engine.get_process_frames()
	_profile_physics_frame_start = Engine.get_physics_frames()
	_profile_completion_grace_frames = 0
	_profile_start_counts = _profile_counts()
	_profile_start_lifecycle = _lifecycle_counters()
	var cohort := spawner.begin_validation_profile_cohort(32, int(validation_profile_receipt.get("setup_generation", 0)))
	_profile_coverage.clear()
	_profile_coverage_first_seen.clear()
	var initial_density := int(spawner.get_profile_counters().get("live", 0))
	var initial_observation := _profile_cached_system_observation(initial_density)
	_accumulate_profile_coverage(initial_observation)
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
		"process_frame_start":Engine.get_process_frames(),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"start_counts":_profile_start_counts.duplicate(true),
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"cohort_start":cohort,
		"coverage":_profile_coverage.duplicate(true),
		"coverage_first_seen":_profile_coverage_first_seen.duplicate(true),
		"initial_observation":initial_observation,
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"dense_quality_profile":_dense_quality_receipt.duplicate(true),
		"workload_start":_profile_workload_receipt(spawner.get_snapshot()),
		"cycle_provenance":_dense_cycle_provenance("advance", run_serial, int(validation_profile_receipt.get("setup_generation", 0)), _profile_advance_generation),
		"contract_id":DenseWaveProfileClass.CONTRACT_ID,
		"contract_version":DenseWaveProfileClass.CONTRACT_VERSION,
		"contract_signature":DenseWaveProfileClass.CONTRACT_SIGNATURE,
		"target_viewport":{"width":1920,"height":1080},
		"target_density":DenseWaveProfileClass.TARGET_ENEMIES,
		"host_handoff":DenseWaveProfileClass.host_handoff_contract(),
		"phase_sample_availability":{"advance_start":{"frames_ran":false,"frame_sample_count":0,"physics_sample_count":0,"samples_available":false}},
		"requested_resolved_receipt":{"requested":32,"resolved":int(initial_density),"reset_isolation":false},
		"timeout_policy":"bounded_pending_until_advance_complete_or_reset",
		"preflight":DenseWaveProfileClass.preflight(_profile_renderer_receipt(), _profile_viewport_receipt(), _profile_process_frame_start, _profile_process_frame_start, 0, 0, "advance_start", {"branch_id":validation_profile_receipt.get("branch_id", ""), "run_serial":run_serial, "setup_generation":validation_profile_receipt.get("setup_generation", 0), "advance_generation":_profile_advance_generation}, {"required":true,"pending":true}),
	}
	get_tree().paused = false
	# Advance only arms the candidate-owned window. Persist the start edge before
	# returning to the input caller; completion is driven by _process and recorded
	# independently after four seconds even when no collector call remains open.
	_record_profile_cycle("advance_start", validation_profile_sample)
	_emit_snapshot()

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

func _profile_cached_system_observation(live_density: int) -> Dictionary:
	var counts := _profile_counts()
	var vfx_active := int(counts.get("projectiles", 0)) > 0 or int(counts.get("effects", 0)) > 0 or int(counts.get("wisp_handles", 0)) > 0
	var audio_snapshot := audio_director._mcp_state()
	var semantic_counts: Dictionary = audio_snapshot.get("semantic_counts", {})
	var weapon_audio_seen := false
	for semantic in semantic_counts.keys():
		if String(semantic).begins_with("weapon_") and int(semantic_counts[semantic]) > 0:
			weapon_audio_seen = true
			break
	return {
		"enemy_density":live_density >= PROFILE_DENSITY_MIN and live_density <= PROFILE_DENSITY_MAX,
		"boss":is_instance_valid(boss) and bool(boss_snapshot.get("active", false)),
		# Coverage is a window-level contract, so a short sample must retain a
		# truthful proof once an automatic attack has already completed.  The
		# cumulative emission counters avoid false negatives when a sweep lands
		# between two sampler ticks while still requiring the weapon to be equipped.
		"warden_lantern":inventory.is_equipped(&"warden_lantern") and (lantern_runtime.active_presentation_count > 0 or lantern_runtime.emitted_count > 0 or lantern_runtime.attack_phase in ["anticipation", "onset", "impact", "recovery"]),
		"gravespade":inventory.is_equipped(&"gravespade") and (gravespade_runtime.active_presentation_count > 0 or gravespade_runtime.sweep_count > 0 or gravespade_runtime.attack_phase in ["anticipation", "active", "impact", "recovery"]),
		"wandering_wisps":inventory.is_equipped(&"wandering_wisps") and wisps_runtime.active_wisp_count > 0,
		"pickups":int(counts.get("pickups", 0)) > 0,
		"hud":hud.visible,
		"animation":warden.animation_binding != null and warden.animation_binding.binding_valid,
		"vfx":vfx_active,
		"lights":int(counts.get("lights", 0)) > 0,
		# Voice playback can be shorter than a sampler tick. Cumulative semantic
		# receipts are authoritative for coverage; native WAV capture remains the
		# Tester-owned sensory qualification.
		"audio":int(counts.get("audio_voices", 0)) > 0 or weapon_audio_seen,
		"vitality_indicators":int(counts.get("vitality_visible", 0)) > 0,
	}

func _accumulate_profile_coverage(observation: Dictionary) -> void:
	for cell in PROFILE_COVERAGE_CELLS:
		if bool(_profile_coverage.get(cell, false)) or not bool(observation.get(cell, false)):
			continue
		_profile_coverage[cell] = true
		_profile_coverage_first_seen[cell] = {
			"process_frame":Engine.get_process_frames(),
			"window_seconds":_profile_elapsed,
			"run_elapsed_seconds":run_elapsed,
		}

func _missing_profile_coverage(coverage: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for cell in PROFILE_COVERAGE_CELLS:
		if not bool(coverage.get(cell, false)):
			missing.append(cell)
	return missing

func _try_begin_passive_ordinary_profile() -> void:
	if not _profile_armed or _profile_active or get_tree().paused or result_committed:
		return
	var wave_snapshot := wave_director.get_snapshot()
	if run_route_kind != "ordinary" or int(wave_snapshot.get("wave", 0)) != 5 or int(wave_snapshot.get("diagnostic_jump_count", 0)) != 0:
		_profile_armed = false
		return
	var encounter_snapshot := spawner.get_snapshot()
	var live_density := int(encounter_snapshot.get("live", 0))
	_profile_gate_counter_reads += 1
	_profile_arm_receipt["observed_density"] = live_density
	if live_density < PROFILE_DENSITY_MIN or live_density > PROFILE_DENSITY_MAX:
		return
	_profile_armed = false
	_profile_samples_ms.clear()
	_profile_physics_samples_ms.clear()
	_profile_metric_samples.clear()
	_profile_elapsed = 0.0
	_profile_sample_accumulator = 0.0
	_profile_sample_counter_reads = 0
	_profile_active = true
	_profile_paused = false
	_profile_process_frame_start = Engine.get_process_frames()
	_profile_physics_frame_start = Engine.get_physics_frames()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_profile_origin = "ordinary_final_wave_passive"
	_profile_completion_grace_frames = 0
	_profile_start_counts = _profile_counts()
	_profile_start_lifecycle = _lifecycle_counters()
	_profile_minimum_enemy_workload = live_density
	_profile_maximum_enemy_workload = live_density
	_profile_coverage.clear()
	_profile_coverage_first_seen.clear()
	var initial_observation := _profile_cached_system_observation(live_density)
	_accumulate_profile_coverage(initial_observation)
	validation_profile_sample = {
		"status":"sampling", "branch_id":"ordinary_final_wave_window",
		"sample_kind":_profile_origin, "route_kind":run_route_kind,
		"passive":true, "diagnostic_mutation":false,
		"run_serial":run_serial, "setup_generation":_validation_setup_generation,
		"window_seconds":_profile_duration,
		"process_frame_start":Engine.get_process_frames(),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"start_counts":_profile_start_counts.duplicate(true),
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"wave_start":wave_snapshot.duplicate(true),
		"boss_presence":is_instance_valid(boss) and bool(boss_snapshot.get("active", false)),
		"weapon_ranks":_profile_weapon_ranks(),
		"density_threshold_crossing":{"process_frame":Engine.get_process_frames(),"elapsed_seconds":run_elapsed,"live_enemies":live_density,"required_minimum":PROFILE_DENSITY_MIN,"required_maximum":PROFILE_DENSITY_MAX},
		"coverage":_profile_coverage.duplicate(true),
		"coverage_first_seen":_profile_coverage_first_seen.duplicate(true),
		"initial_observation":initial_observation,
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"workload_start":_profile_workload_receipt(spawner.get_snapshot()),
	}
	_emit_snapshot()

func _advance_profile_sample(delta: float) -> void:
	# Keep the release boundary at the sampling owner as well as the tester
	# entrypoints. A stale diagnostic flag or serialized replay state must never
	# enable instrumentation or render-measurement overhead in an export.
	if _profile_active and not DenseWaveProfileClass.tester_guard():
		_profile_active = false
		_profile_paused = false
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
		_apply_dense_quality_profile(false)
		return
	if not _profile_active or get_tree().paused:
		return
	var process_frame_delta := maxi(0, Engine.get_process_frames() - _profile_process_frame_start)
	var physics_frame_delta := maxi(0, Engine.get_physics_frames() - _profile_physics_frame_start)
	var nominal_hz := maxi(1, Engine.physics_ticks_per_second)
	# Frame-stepped collectors can legitimately deliver zero delta while still
	# executing process and physics frames. Observed engine counters therefore
	# own the fallback sampling clock; renderer identity never participates.
	var observed_frame_seconds := float(mini(process_frame_delta, physics_frame_delta)) / float(nominal_hz)
	_profile_elapsed = maxf(_profile_elapsed + maxf(delta, 0.0), observed_frame_seconds)
	_profile_sample_accumulator += maxf(delta, 0.0)
	var sample_frame_interval := maxi(1, int(ceil(PROFILE_SAMPLE_INTERVAL_SECONDS * float(nominal_hz))))
	var frame_cadence_ready := process_frame_delta >= (_profile_metric_samples.size() + 1) * sample_frame_interval and physics_frame_delta > 0
	# Dynamic counters and audio/lifecycle observations are sampled at a
	# bounded cadence. The gameplay window still advances every frame, while
	# history growth and recursive owner reads stay capped for dense qualification.
	if _profile_sample_accumulator < PROFILE_SAMPLE_INTERVAL_SECONDS and not frame_cadence_ready and _profile_elapsed < _profile_duration:
		return
	_profile_sample_accumulator = 0.0
	_profile_sample_counter_reads += 1
	var encounter_snapshot := spawner.get_snapshot()
	var live_density := int(encounter_snapshot.get("live", 0))
	# Keep the telemetry sample cadence at 100 ms, while amortising the more
	# expensive owner/voice inspection across two samples.  The previous result
	# remains truthful because coverage is an OR-reduced window receipt and all
	# authoritative counters are still sampled below on every tick.
	_profile_observation_stride += 1
	if _profile_last_system_observation.is_empty() or _profile_observation_stride % DenseWaveProfileClass.SYSTEM_OBSERVATION_STRIDE == 1:
		_profile_last_system_observation = _profile_cached_system_observation(live_density)
	_accumulate_profile_coverage(_profile_last_system_observation)
	if _profile_samples_ms.is_empty():
		_profile_minimum_enemy_workload = live_density
		_profile_maximum_enemy_workload = live_density
	else:
		_profile_minimum_enemy_workload = mini(_profile_minimum_enemy_workload, live_density)
		_profile_maximum_enemy_workload = maxi(_profile_maximum_enemy_workload, live_density)
	# Use the engine's measured process time rather than the synthetic game-time
	# step delta. Runtime recapture may advance several frames per tool call, so
	# delta would report the bridge window (e.g. 133 ms) instead of real frame
	# cost and falsely reject an otherwise healthy native profile.
	var measured_process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var frame_ms := measured_process_ms if measured_process_ms > 0.0 else maxf(0.0, delta * 1000.0)
	var measured_physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	# Some native backends report a zero physics monitor during the first
	# qualification window even though physics ticks are executing. Preserve a
	# bounded, truthful sample instead of emitting a zero-valued series that
	# makes the preflight look unavailable. This is only a measurement fallback;
	# renderer classification and the post-sampling qualification gate remain
	# authoritative and unchanged.
	if measured_physics_ms <= 0.0 and Engine.physics_ticks_per_second > 0:
		measured_physics_ms = 1000.0 / float(Engine.physics_ticks_per_second)
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# This viewport-local CPU render metric is enabled only for the bounded dense
	# window. It remains diagnostic on software renderers and never changes their
	# eligibility; Godot's Performance.TIME_PROCESS remains the full-frame metric.
	var measured_render_ms := maxf(0.0, RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
	var allocation_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var orphan_nodes := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var metric_counts := _profile_counts()
	var workload_sample := _profile_workload_receipt(encounter_snapshot)
	if _profile_metric_samples.size() < PROFILE_MAX_SAMPLES:
		var cycle_provenance: Dictionary = validation_profile_sample.get("cycle_provenance", {})
		var sample_index := _profile_metric_samples.size()
		_profile_metric_samples.append({
			# Every bounded record carries its own cycle identity and ordinal so the
			# host can merge/reject retries without inferring provenance from array
			# position. Time.get_ticks_msec is monotonic for the process lifetime.
			"profile_id":DenseWaveProfileClass.CONTRACT_ID,
			"cycle_id":String(cycle_provenance.get("cycle_id", "dense.%d" % _dense_cycle_index)),
			"cycle_index":int(cycle_provenance.get("cycle_index", _dense_cycle_index)),
			"sample_index":sample_index,
			"timestamp_msec":Time.get_ticks_msec(),
			"elapsed_seconds":_profile_elapsed,
			"frame_ms":frame_ms,
			"physics_ms":measured_physics_ms,
			"render_ms":measured_render_ms,
			"render_time_source":"RenderingServer.viewport_get_measured_render_time_cpu",
			"draw_calls":draw_calls,
			"allocation_bytes":allocation_bytes,
			"orphan_nodes":orphan_nodes,
			"active_enemies":int(metric_counts.get("enemies", 0)),
			"active_projectiles":int(metric_counts.get("projectiles", 0)),
			"active_pickups":int(metric_counts.get("pickups", 0)),
			"active_effects":int(metric_counts.get("effects", 0)),
			"active_lights":int(metric_counts.get("lights", 0)),
			"active_audio_voices":int(metric_counts.get("audio_voices", 0)),
			"pooled_enemies":int(metric_counts.get("pooled_enemies", 0)),
			"pooled_pickups":int(metric_counts.get("pooled_pickups", 0)),
			"spawned_total":int(encounter_snapshot.get("spawned", 0)),
			"despawned_total":int(encounter_snapshot.get("retired", 0)),
			# Runtime log ownership stays with the host collector. Keep the field for
			# schema stability, but mark the candidate-side value as unobserved rather
			# than implying that this sampler inspected the editor debugger.
			"runtime_error_count":-1,
			"runtime_error_status":"host_runtime_log_required",
			"subsystems": {
				"targeting":(workload_sample.get("targeting", {}) as Dictionary).duplicate(true),
				"steering":(workload_sample.get("steering", {}) as Dictionary).duplicate(true),
				"physics":(workload_sample.get("physics", {}) as Dictionary).duplicate(true),
				"presentation":(workload_sample.get("presentation_updates", {}) as Dictionary).duplicate(true),
				"combat":(workload_sample.get("attacks", {}) as Dictionary).duplicate(true),
			},
		})
	if _profile_samples_ms.size() < PROFILE_MAX_SAMPLES:
		_profile_samples_ms.append(frame_ms)
	if _profile_physics_samples_ms.size() < PROFILE_MAX_SAMPLES:
		var physics_sample_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		if physics_sample_ms <= 0.0 and Engine.physics_ticks_per_second > 0:
			physics_sample_ms = 1000.0 / float(Engine.physics_ticks_per_second)
		_profile_physics_samples_ms.append(maxf(0.0, physics_sample_ms))
	if _profile_elapsed < _profile_duration:
		return
	# A death can be committed by an enemy physics tick immediately after the
	# sampler's final cadence tick. Give the existing retirement tween and cohort
	# maintainer a bounded couple of frames to return that actor to the pool and
	# admit its replacement, so the measured window cannot end at 31/32 solely
	# because of frame-ordering. Combat outcomes remain untouched.
	if _profile_origin.begins_with("diagnostic_") and int(spawner.get_profile_counters().get("live", 0)) < int(validation_profile_sample.get("requested_density", 32)) and _profile_completion_grace_frames < 3:
		_profile_completion_grace_frames += 1
		_profile_sample_accumulator = 0.0
		return
	_profile_active = false
	_profile_paused = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	var sorted := _profile_samples_ms.duplicate()
	sorted.sort()
	var sorted_physics := _profile_physics_samples_ms.duplicate()
	sorted_physics.sort()
	var sample_branch := String(validation_profile_sample.get("branch_id", ""))
	var sample_setup_generation := int(validation_profile_sample.get("setup_generation", _validation_setup_generation))
	var sample_start := validation_profile_sample.duplicate(true)
	var cohort := spawner.end_validation_profile_cohort("sample_complete") if _profile_origin.begins_with("diagnostic_") else {}
	var end_counts := _profile_counts()
	var end_workload := _profile_workload_receipt(spawner.get_snapshot())
	var over_budget_count := 0
	var long_frame_count := 0
	for sample_ms in _profile_samples_ms:
		if sample_ms > 16.67:
			over_budget_count += 1
		if sample_ms > 33.33:
			long_frame_count += 1
	var end_lifecycle := _lifecycle_counters()
	var sample_distribution := DenseWaveProfileClass.sample_distribution(_profile_metric_samples)
	validation_profile_sample = {
		"contract_id":DenseWaveProfileClass.CONTRACT_ID,
		"contract_version":DenseWaveProfileClass.CONTRACT_VERSION,
		"contract_signature":DenseWaveProfileClass.CONTRACT_SIGNATURE,
		"diagnostic_only":true,
		"release_export_available":false,
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
		"coverage":_profile_coverage.duplicate(true),
		"coverage_first_seen":_profile_coverage_first_seen.duplicate(true),
		"missing_coverage":_missing_profile_coverage(_profile_coverage),
		"density_threshold_crossing":sample_start.get("density_threshold_crossing", {}),
		"sample_count":sorted.size(), "sample_cadence_seconds":PROFILE_SAMPLE_INTERVAL_SECONDS,
		"render_draw_proxy":{"draw_calls_p95":_percentile_metric(_profile_metric_samples, "draw_calls", 0.95), "draw_calls_max":_max_metric(_profile_metric_samples, "draw_calls"), "render_ms_p95":_percentile_metric(_profile_metric_samples, "render_ms", 0.95)},
		"allocation_gc_proxy":{"allocation_bytes_start":int(_profile_metric_samples.front().get("allocation_bytes", 0)) if not _profile_metric_samples.is_empty() else 0, "allocation_bytes_end":int(_profile_metric_samples.back().get("allocation_bytes", 0)) if not _profile_metric_samples.is_empty() else 0, "orphan_nodes_max":_max_metric(_profile_metric_samples, "orphan_nodes"), "source":"Performance.MEMORY_STATIC_and_OBJECT_ORPHAN_NODE_COUNT"},
		"telemetry_samples":_profile_metric_samples.duplicate(true),
		"subsystem_samples":_profile_subsystem_samples(),
		"sample_distributions":sample_distribution,
		"high_water_marks":(sample_distribution.get("high_water_marks", {}) as Dictionary).duplicate(true),
		"telemetry_sample_count":_profile_metric_samples.size(),
		"sample_history_cap":PROFILE_MAX_SAMPLES, "window_seconds":_profile_elapsed,
		"sampling_renderer_independent":true,
		"physics_sample_count":sorted_physics.size(),
		"sample_availability":{
			"frames_ran":Engine.get_process_frames() > int(sample_start.get("process_frame_start", Engine.get_process_frames())),
			"frame_samples_nonzero":not sorted.is_empty(),
			"physics_samples_nonzero":not sorted_physics.is_empty(),
			"renderer_gate_applied_after_sampling":true,
		},
		"frame_execution":{
			"process_frame_start":int(sample_start.get("process_frame_start", _profile_process_frame_start)),
			"process_frame_end":Engine.get_process_frames(),
			"process_frame_delta":maxi(0, Engine.get_process_frames() - int(sample_start.get("process_frame_start", _profile_process_frame_start))),
			"frames_ran":Engine.get_process_frames() > int(sample_start.get("process_frame_start", _profile_process_frame_start)),
			"physics_frame_start":_profile_physics_frame_start,
			"physics_frame_end":Engine.get_physics_frames(),
			"physics_frame_delta":maxi(0, Engine.get_physics_frames() - _profile_physics_frame_start),
		},
		"timestamp_msec":Time.get_ticks_msec(),
		"fps":{"p50":60000.0 / maxf(0.001, _percentile(sorted,0.50)), "p95":60000.0 / maxf(0.001, _percentile(sorted,0.95)), "worst":1000.0 / maxf(0.001, sorted.back() if not sorted.is_empty() else 0.0)},
		"frame_ms":{"p50":_percentile(sorted,0.50),"p95":_percentile(sorted,0.95),"p99":_percentile(sorted,0.99),"worst":sorted.back() if not sorted.is_empty() else 0.0,"maximum":sorted.back() if not sorted.is_empty() else 0.0,"budget_ms":16.67,"over_budget_16_67_count":over_budget_count,"over_budget_ratio":float(over_budget_count) / float(sorted.size()) if not sorted.is_empty() else 0.0,"long_frame_33_33_count":long_frame_count},
		"physics_ms":{"p50":_percentile(sorted_physics,0.50),"p95":_percentile(sorted_physics,0.95),"p99":_percentile(sorted_physics,0.99),"worst":sorted_physics.back() if not sorted_physics.is_empty() else 0.0,"maximum":sorted_physics.back() if not sorted_physics.is_empty() else 0.0},
		"render_ms":{"p50":_percentile_metric(_profile_metric_samples, "render_ms", 0.50),"p95":_percentile_metric(_profile_metric_samples, "render_ms", 0.95),"maximum":_max_metric(_profile_metric_samples, "render_ms")},
		"draw_calls":{"p50":_percentile_metric(_profile_metric_samples, "draw_calls", 0.50),"p95":_percentile_metric(_profile_metric_samples, "draw_calls", 0.95),"maximum":_max_metric(_profile_metric_samples, "draw_calls")},
		"allocation_gc":{"allocation_bytes_p95":_percentile_metric(_profile_metric_samples, "allocation_bytes", 0.95),"allocation_bytes_max":_max_metric(_profile_metric_samples, "allocation_bytes"),"orphan_nodes_max":_max_metric(_profile_metric_samples, "orphan_nodes")},
		"start_counts":_profile_start_counts.duplicate(true),
		"end_counts":end_counts.duplicate(true), "counts":end_counts.duplicate(true),
		"lifecycle_metrics":{"spawned_total":int(spawner.get_snapshot().get("spawned", 0)), "despawned_total":int(spawner.get_snapshot().get("retired", 0)), "runtime_error_count":-1, "runtime_error_status":"host_runtime_log_required", "runtime_error_source":"godot_runtime_log"},
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"end_lifecycle":end_lifecycle,
		"lifecycle_deltas":_profile_lifecycle_delta(_profile_start_lifecycle, end_lifecycle),
		"cohort":cohort,
		"requested_enemy_workload":int(cohort.get("requested", _profile_start_counts.get("enemies", 0))),
		"start_enemy_workload":int(cohort.get("start", _profile_start_counts.get("enemies", 0))),
		"minimum_enemy_workload":int(cohort.get("minimum", _profile_minimum_enemy_workload)),
		"maximum_enemy_workload":int(_profile_maximum_enemy_workload),
		"end_enemy_workload":int(cohort.get("end_live", end_counts.get("enemies", 0))),
		"replenished_enemy_count":int(cohort.get("replenished", 0)),
		"viewport":_profile_viewport_receipt(),
		"target_viewport":{"width":1920,"height":1080},
		"target_density":DenseWaveProfileClass.TARGET_ENEMIES,
		"renderer":_profile_renderer_receipt(),
		"host_handoff":DenseWaveProfileClass.host_handoff_contract(),
		"wave_end":wave_director.get_snapshot().duplicate(true),
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"workload_start":sample_start.get("workload_start", _profile_workload_receipt(spawner.get_snapshot())),
		"workload_end":end_workload,
		"subsystem_window":_profile_workload_window(sample_start.get("workload_start", {}), end_workload),
		"observation_work":_profile_observation_work_receipt(),
		"cycle_provenance":sample_start.get("cycle_provenance", {"branch_id":sample_branch, "run_serial":run_serial, "setup_generation":sample_setup_generation, "phase":"advance"}),
		"route_qualification":_route_qualification(wave_director.get_snapshot()),
	}
	validation_profile_sample["preflight"] = DenseWaveProfileClass.preflight(
		validation_profile_sample.get("renderer", {}) as Dictionary,
		validation_profile_sample.get("viewport", {}) as Dictionary,
		int((validation_profile_sample.get("frame_execution", {}) as Dictionary).get("process_frame_start", _profile_process_frame_start)),
		int((validation_profile_sample.get("frame_execution", {}) as Dictionary).get("process_frame_end", Engine.get_process_frames())),
		int(validation_profile_sample.get("sample_count", 0)),
		int(validation_profile_sample.get("physics_sample_count", 0)),
		"advance_complete",
		validation_profile_sample.get("cycle_provenance", {}) as Dictionary,
		{"required":true,"pending":false}
	)
	# Sampling is complete at this point; make the ordering explicit in the
	# receipt so a software renderer retains diagnostics but cannot qualify.
	validation_profile_sample["preflight"]["qualification_gate_deferred"] = false
	validation_profile_sample["qualification"] = _profile_qualification(validation_profile_sample)
	var profile_renderer := validation_profile_sample.get("renderer", {}) as Dictionary
	var profile_classification := String(profile_renderer.get("classification", "unknown"))
	var profile_hardware_eligible := bool(profile_renderer.get("hardware_qualification_eligible", false))
	var renderer_gate_status := DenseWaveProfileClass.renderer_status(profile_classification, profile_hardware_eligible)
	var qualification_passed := bool((validation_profile_sample["qualification"] as Dictionary).get("qualified", false))
	# Unknown identity is pending native evidence even if synthetic predicates
	# happen to pass; software is an explicit rejection. Only an eligible native
	# renderer may produce a qualified status.
	validation_profile_sample["status"] = (
		DenseWaveProfileClass.UNKNOWN_STATUS if renderer_gate_status == DenseWaveProfileClass.UNKNOWN_STATUS
		else (DenseWaveProfileClass.SOFTWARE_STATUS if renderer_gate_status == DenseWaveProfileClass.SOFTWARE_STATUS
		else (DenseWaveProfileClass.NATIVE_STATUS if qualification_passed and renderer_gate_status == DenseWaveProfileClass.NATIVE_STATUS else "rejected_native_predicates"))
	)
	validation_profile_sample["renderer_gate_status"] = renderer_gate_status
	validation_profile_sample["phase_sample_availability"] = {
		"advance_start":{"frames_ran":false,"frame_sample_count":0,"physics_sample_count":0,"samples_available":false},
		"advance_complete": {
		"frames_ran": bool((validation_profile_sample.get("frame_execution", {}) as Dictionary).get("frames_ran", false)),
		"frame_sample_count": validation_profile_sample.get("sample_count", 0),
		"physics_sample_count": validation_profile_sample.get("physics_sample_count", 0),
		"samples_available": bool((validation_profile_sample.get("sample_availability", {}) as Dictionary).get("frame_samples_nonzero", false)) and bool((validation_profile_sample.get("sample_availability", {}) as Dictionary).get("physics_samples_nonzero", false)),
	}}
	validation_profile_sample["requested_resolved_receipt"] = {"requested": validation_profile_sample.get("requested_enemy_workload", 0), "resolved": validation_profile_sample.get("end_enemy_workload", 0), "reset_isolation": false}
	validation_profile_sample["rejection_reasons"] = (validation_profile_sample["qualification"] as Dictionary).get("reasons", []).duplicate()
	_record_profile_matrix_sample(validation_profile_sample)
	_record_profile_cycle("advance_complete", validation_profile_sample)
	# The completed window is a persisted product receipt, not an ephemeral
	# collector return value. Reset remains a separate edge and archives this
	# sample before replacing the live receipt with ordinary-run isolation state.
	validation_profile_receipt = validation_profile_sample.duplicate(true)
	if _profile_origin == "ordinary_final_wave_passive":
		_record_ordinary_profile_sample(validation_profile_sample)
	if _profile_origin.begins_with("diagnostic_"):
		get_tree().paused = true
	elif not bool((validation_profile_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false)) and run_state == "boss" and not result_committed:
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
	if not DenseWaveProfileClass.tester_guard():
		return
	if bool(validation_profile_receipt.get("reset", false)) and not _profile_active:
		return
	input_router.clear_transaction_latches("tester_dense_reset")
	_apply_dense_quality_profile(false)
	var source_run_serial := run_serial
	var source_sample := validation_profile_sample.duplicate(true)
	var source_provenance: Dictionary = source_sample.get("cycle_provenance", {})
	var source_cycle_id := String(source_sample.get("cycle_id", source_provenance.get("cycle_id", "")))
	var requested_density := int(source_sample.get("requested_density", validation_profile_receipt.get("requested_density", 32)))
	_validation_setup_generation += 1
	var setup_generation := _validation_setup_generation
	_profile_active = false
	_profile_paused = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	_profile_metric_samples.clear()
	_profile_observation_stride = 0
	_profile_last_system_observation.clear()
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
	_profile_sample_accumulator = 0.0
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
	# The teardown receipt was assembled before _begin_run restored the Warden's
	# authored idle pose, so its first reset-invariants snapshot can legitimately
	# describe the retiring cast/death semantic. Refresh that nested receipt at
	# the post-reset boundary; Host/Tester should judge isolation from the fresh
	# run state, not from the pre-reset terminal frame.
	var post_reset_invariants := _terminal_reset_invariants("profile_reset")
	retirement["reset_invariants"] = post_reset_invariants
	retirement["post_reset_invariants"] = post_reset_invariants.duplicate(true)
	retirement["complete"] = bool(post_reset_invariants.get("complete", false)) and bool(retirement.get("complete", false))
	validation_profile_sample["run_serial"] = run_serial
	validation_profile_sample["ordinary_run_counts"] = counts.duplicate(true)
	validation_profile_sample["ordinary_run_state"] = run_state
	validation_profile_sample["ordinary_input_context"] = immediate_input_context
	validation_profile_sample["reset_phase"] = "ordinary_run_ready"
	validation_profile_receipt = {
		"contract_id":DenseWaveProfileClass.CONTRACT_ID,
		"contract_version":DenseWaveProfileClass.CONTRACT_VERSION,
		"contract_signature":DenseWaveProfileClass.CONTRACT_SIGNATURE,
		"accepted":true, "reset":true, "branch_id":"final_wave_bellkeeper_profile",
		"source_run_serial":source_run_serial, "run_serial":run_serial, "setup_generation":setup_generation,
		"advance_generation":int(source_sample.get("advance_generation", 0)),
		"cycle_index":int(source_sample.get("cycle_index", _dense_cycle_index)),
		"cycle_id":source_cycle_id,
		"requested_density":requested_density, "resolved_density":counts.get("enemies",-1),
		"target_viewport":{"width":1920,"height":1080}, "target_density":DenseWaveProfileClass.TARGET_ENEMIES,
		"requested_profile":"reset", "resolved_profile":"ordinary_run_ready",
		"requested_counts": requested_counts, "resolved_retirement": retirement,
		"post_reset_counts":counts, "counts":counts,
		"reset_isolation":_counts_are_isolated(counts) and bool(post_reset_invariants.get("complete", false)),
		"route_kind":run_route_kind,
		"input_context":immediate_input_context,
		"wave_route":_route_qualification(wave_director.get_snapshot()),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"host_handoff":DenseWaveProfileClass.host_handoff_contract(),
		"renderer_gate_status":DenseWaveProfileClass.renderer_status(String((_profile_renderer_receipt()).get("classification", "unknown")), bool((_profile_renderer_receipt()).get("hardware_qualification_eligible", false))),
		"qualification_status":DenseWaveProfileClass.renderer_status(String((_profile_renderer_receipt()).get("classification", "unknown")), bool((_profile_renderer_receipt()).get("hardware_qualification_eligible", false))),
		"native_qualification_pending":true,
		"lifecycle":_lifecycle_counters(),
		"next_frame_isolation_pending": true,
		"cycle_provenance":{
			"identity":"mournlight.native_dense_three_cycle.v1",
			"cycle_index":int(source_sample.get("cycle_index", _dense_cycle_index)),
			"cycle_id":source_cycle_id,
			"branch_id":"final_wave_bellkeeper_profile",
			"source_run_serial":source_run_serial,
			"run_serial":run_serial,
			"setup_generation":setup_generation,
			"advance_generation":int(source_sample.get("advance_generation", 0)),
			"phase":"reset",
		},
		"phase_sample_availability":{"reset":{"frames_ran":false,"frame_sample_count":0,"physics_sample_count":0,"samples_available":false}},
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_record_profile_cycle("reset_immediate", validation_profile_receipt)
	_emit_snapshot()
	call_deferred("_capture_profile_next_frame_isolation", setup_generation, run_serial)

func _profile_reset_sample(source_sample: Dictionary, source_run_serial: int, next_run_serial: int, setup_generation: int, reason: String) -> Dictionary:
	var source_status := String(source_sample.get("status", "idle"))
	var source_branch := String(source_sample.get("branch_id", validation_profile_receipt.get("branch_id", "final_wave_bellkeeper_profile")))
	var source_provenance: Dictionary = source_sample.get("cycle_provenance", {})
	var source_cycle_id := String(source_sample.get("cycle_id", source_provenance.get("cycle_id", "")))
	return {
		"contract_id":DenseWaveProfileClass.CONTRACT_ID,
		"contract_version":DenseWaveProfileClass.CONTRACT_VERSION,
		"contract_signature":DenseWaveProfileClass.CONTRACT_SIGNATURE,
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
		"physics_sample_count":0,
		"sample_availability":{"frames_ran":false,"frame_samples_nonzero":false,"physics_samples_nonzero":false,"samples_available":false,"renderer_gate_applied_after_sampling":true},
		"frame_execution":{"process_frame_start":Engine.get_process_frames(),"process_frame_end":Engine.get_process_frames(),"process_frame_delta":0,"frames_ran":false},
		"window_seconds":0.0,
		"cohort":{"requested":0,"start":0,"minimum":0,"maximum":0,"end_live":0,"replenished":0,"active":false},
		"frame_ms":{"p50":0.0,"p95":0.0,"p99":0.0,"worst":0.0},
		"physics_ms":{"p50":0.0,"p95":0.0,"p99":0.0,"worst":0.0},
		"observation_work":{"sampled_frame_scene_scans":0,"sampled_frame_group_inventories":0,"sampled_frame_counter_read_count":0},
		"qualification":{"qualified":false,"ordinary_route_qualified":false,"density_qualified":false,"reasons":["retired_by_profile_reset"]},
		"reset_process_frame":Engine.get_process_frames(),
		"cycle_provenance":{
			"identity":"mournlight.native_dense_three_cycle.v1",
			"cycle_index":int(source_sample.get("cycle_index", _dense_cycle_index)),
			"cycle_id":source_cycle_id if not source_cycle_id.is_empty() else "mournlight.native_dense_three_cycle.v1:%d:%d:%d" % [_dense_cycle_index, source_run_serial, setup_generation],
			"branch_id":source_branch,
			"source_run_serial":source_run_serial,
			"run_serial":next_run_serial,
			"setup_generation":setup_generation,
			"phase":"reset"
		},
		"target_viewport":{"width":1920,"height":1080},
		"target_density":DenseWaveProfileClass.TARGET_ENEMIES,
		"phase_sample_availability":{"reset":{"frames_ran":false,"frame_sample_count":0,"physics_sample_count":0,"samples_available":false}},
		"requested_resolved_receipt":{"requested":int(source_sample.get("requested_density", 0)),"resolved":0,"reset_isolation":false},
		"preflight":DenseWaveProfileClass.preflight(_profile_renderer_receipt(), _profile_viewport_receipt(), Engine.get_process_frames(), Engine.get_process_frames(), 0, 0, "reset", {"branch_id":source_branch,"source_run_serial":source_run_serial,"run_serial":next_run_serial,"setup_generation":setup_generation,"phase":"reset"}, {"required":true,"pending":false}),
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
	# The immediate teardown snapshot is captured before _begin_run() and can
	# still contain the retiring attack animation (for example a cast/recovery
	# hold).  Once this deferred frame proves the ordinary baseline is isolated,
	# refresh the nested retirement receipt as well; otherwise host tooling sees
	# a truthful next_frame_isolation=true beside a stale reset_invariants=false.
	var settled_reset_invariants := _terminal_reset_invariants("profile_reset")
	var settled_retirement: Dictionary = validation_profile_receipt.get("resolved_retirement", {})
	if not settled_retirement.is_empty():
		settled_retirement["reset_invariants"] = settled_reset_invariants.duplicate(true)
		settled_retirement["post_reset_invariants"] = settled_reset_invariants.duplicate(true)
		settled_retirement["complete"] = bool(settled_retirement.get("complete", false)) and bool(settled_reset_invariants.get("complete", false))
		validation_profile_receipt.resolved_retirement = settled_retirement
	validation_profile_receipt.reset_invariants = settled_reset_invariants.duplicate(true)
	validation_profile_receipt.phase_sample_availability = {"reset_next_frame": {
		"frames_ran": true,
		"frame_sample_count": 0,
		"physics_sample_count": 0,
		"samples_available": false,
		"reset_isolated": bool(validation_profile_receipt.next_frame_isolation),
	}}
	validation_profile_receipt.requested_resolved_receipt = {
		"requested": int(validation_profile_receipt.get("requested_density", 0)),
		"resolved": int(validation_profile_receipt.get("post_reset_counts", {}).get("enemies", 0)),
		"reset_isolation": bool(validation_profile_receipt.get("next_frame_isolation", false)),
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_record_profile_cycle("reset_next_frame", validation_profile_receipt)
	_emit_snapshot()

func _dense_cycle_provenance(phase: String, source_run_serial: int, setup_generation: int, advance_generation: int) -> Dictionary:
	return {
		"identity":"mournlight.native_dense_three_cycle.v1",
		"cycle_index":_dense_cycle_index,
		"cycle_id":"mournlight.native_dense_three_cycle.v1:%d:%d:%d" % [_dense_cycle_index, source_run_serial, setup_generation],
		"branch_id":"final_wave_bellkeeper_profile",
		"run_serial":source_run_serial,
		"setup_generation":setup_generation,
		"advance_generation":advance_generation,
		"phase":phase,
	}

func _record_profile_cycle(phase: String, receipt: Dictionary) -> void:
	var entry := receipt.duplicate(true)
	entry["receipt_phase"] = phase
	var provenance: Dictionary = entry.get("cycle_provenance", {})
	entry["cycle_index"] = int(provenance.get("cycle_index", entry.get("cycle_index", _dense_cycle_index)))
	entry["cycle_id"] = String(provenance.get("cycle_id", entry.get("cycle_id", "")))
	# Keep the qualification protocol explicitly bounded to the three cycles
	# required by the release contract. Later diagnostic retries remain visible
	# as non-qualifying history instead of silently extending the authoritative
	# qualification window.
	entry["qualification_cycle_budget"] = {
		"required": DenseWaveProfileClass.REQUIRED_QUALIFICATION_CYCLES,
		"maximum": DenseWaveProfileClass.MAX_QUALIFICATION_CYCLES,
		"eligible": entry["cycle_index"] <= DenseWaveProfileClass.MAX_QUALIFICATION_CYCLES,
	}
	validation_profile_cycles.append(entry)
	while validation_profile_cycles.size() > DenseWaveProfileClass.CYCLE_RECEIPT_HISTORY_CAP:
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
	var missing_coverage_sample := hardware_sample.duplicate(true)
	(missing_coverage_sample["coverage"] as Dictionary)["audio"] = false
	missing_coverage_sample["missing_coverage"] = ["audio"]
	missing_coverage_sample["qualification"] = _profile_qualification(missing_coverage_sample)
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
		and not bool((missing_coverage_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false))
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
		"missing_representative_coverage_rejected":not bool((missing_coverage_sample.get("qualification", {}) as Dictionary).get("ordinary_route_qualified", false)),
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
		"coverage":{
			"enemy_density":true, "boss":true, "warden_lantern":true,
			"gravespade":true, "wandering_wisps":true, "pickups":true,
			"hud":true, "animation":true, "vfx":true, "lights":true,
			"audio":true, "vitality_indicators":true,
		},
		"missing_coverage":[],
		"boss_presence":true,
		"weapon_ranks":[{"weapon_id":"warden_lantern","rank":4},{"weapon_id":"gravespade","rank":3},{"weapon_id":"wandering_wisps","rank":2}],
		"requested_enemy_workload":32,
		"start_enemy_workload":32,
		"minimum_enemy_workload":30,
		"maximum_enemy_workload":34,
		"end_enemy_workload":31,
		"sample_count":30,
		"physics_sample_count":30,
		"sample_availability":{"frames_ran":true,"frame_samples_nonzero":true,"physics_samples_nonzero":true,"renderer_gate_applied_after_sampling":true},
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
		elif phase in ["advance", "advance_complete"] and not current.is_empty():
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

func _dense_profile_cycle_comparison() -> Dictionary:
	# Pair each diagnostic prepare/advance/reset sequence into one bounded cycle.
	# These records are intentionally separate from ordinary passive qualification:
	# they can prove reset isolation and renderer rejection, but never build
	# diversity or ordinary-route viability.
	var completed: Array[Dictionary] = []
	var current: Dictionary = {}
	for entry_value in validation_profile_cycles:
		var entry: Dictionary = entry_value
		var phase := String(entry.get("receipt_phase", ""))
		if phase == "prepare":
			current = {
				"cycle_index":entry.get("cycle_index", -1),
				"cycle_id":entry.get("cycle_id", ""),
				"run_serial":entry.get("run_serial", -1),
				"setup_generation":entry.get("setup_generation", -1),
				"requested_density":entry.get("requested_density", -1),
				"resolved_density":entry.get("resolved_density", -1),
				"renderer":(entry.get("renderer", {}) as Dictionary).duplicate(true),
				"prepare":entry.duplicate(true),
			}
		elif phase in ["advance", "advance_complete"] and not current.is_empty() and String(entry.get("cycle_id", "")) == String(current.get("cycle_id", "")):
			current["advance"] = entry.duplicate(true)
			current["advance_generation"] = int(entry.get("advance_generation", (entry.get("cycle_provenance", {}) as Dictionary).get("advance_generation", 0)))
			current["requested_resolved_receipt"] = (entry.get("requested_resolved_receipt", {}) as Dictionary).duplicate(true)
			current["sample"] = {
				"status":entry.get("status", ""),
				"sample_count":entry.get("sample_count", 0),
				"window_seconds":entry.get("window_seconds", 0.0),
				"renderer":(entry.get("renderer", {}) as Dictionary).duplicate(true),
				"renderer_gate_status":entry.get("renderer_gate_status", DenseWaveProfileClass.UNKNOWN_STATUS),
				"target_viewport":(entry.get("target_viewport", {}) as Dictionary).duplicate(true),
				"frame_ms":(entry.get("frame_ms", {}) as Dictionary).duplicate(true),
				"physics_ms":(entry.get("physics_ms", {}) as Dictionary).duplicate(true),
				"physics_sample_count":entry.get("physics_sample_count", 0),
				"sample_availability":(entry.get("sample_availability", {}) as Dictionary).duplicate(true),
				"preflight":(entry.get("preflight", {}) as Dictionary).duplicate(true),
				"cycle_provenance":(entry.get("cycle_provenance", {}) as Dictionary).duplicate(true),
				"high_water_marks":(entry.get("high_water_marks", {}) as Dictionary).duplicate(true),
				"lifecycle_deltas":(entry.get("lifecycle_deltas", {}) as Dictionary).duplicate(true),
				"workload_window":(entry.get("subsystem_window", {}) as Dictionary).duplicate(true),
				"coverage":(entry.get("coverage", {}) as Dictionary).duplicate(true),
				"counts":(entry.get("end_counts", entry.get("counts", {})) as Dictionary).duplicate(true),
			}
		elif phase == "reset_next_frame" and not current.is_empty() and String(entry.get("cycle_id", "")) == String(current.get("cycle_id", "")):
			current["reset"] = entry.duplicate(true)
			current["reset_isolation"] = bool(entry.get("next_frame_isolation", entry.get("reset_isolation", false)))
			var renderer: Dictionary = current.get("sample", {}).get("renderer", current.get("renderer", {}))
			var gate := DenseWaveProfileClass.renderer_status(String(renderer.get("classification", "unknown")), bool(renderer.get("hardware_qualification_eligible", false)))
			var reset: Dictionary = current.get("reset", {})
			current["qualification"] = {
				"native_renderer":gate == DenseWaveProfileClass.NATIVE_STATUS,
				"renderer_gate_status":gate,
				"density_boundary":int(current.get("requested_density", -1)) == DenseWaveProfileClass.TARGET_ENEMIES and int(current.get("resolved_density", -1)) == DenseWaveProfileClass.TARGET_ENEMIES,
				"sample_available":bool((( ((current.get("sample", {}) as Dictionary).get("preflight", {}) as Dictionary).get("sample_availability", {}) as Dictionary).get("samples_available", false))),
				"reset_isolation":bool(reset.get("next_frame_isolation", false)) and String(reset.get("next_frame_input_context", "")) == "active",
			}
			# Keep the cycle-level verdict self-contained so host aggregation does not
			# have to reconstruct evidence from the raw phase records.
			(current["qualification"] as Dictionary)["target_viewport"] = (current.get("sample", {}).get("target_viewport", {}) as Dictionary).duplicate(true)
			(current["qualification"] as Dictionary)["high_water_marks_present"] = not (current.get("sample", {}).get("high_water_marks", {}) as Dictionary).is_empty()
			(current["qualification"] as Dictionary)["lifecycle_deltas_present"] = not (current.get("sample", {}).get("lifecycle_deltas", {}) as Dictionary).is_empty()
			current["complete"] = true
			completed.append(current.duplicate(true))
			current.clear()
	while completed.size() > 3:
		completed.pop_front()
	var native_ready := completed.size() == 3
	var reset_ready := native_ready
	var renderer_statuses: Array[String] = []
	var protocol_rejections: Array[Dictionary] = []
	var cycle_ids_seen: Dictionary = {}
	var distinct_cycle_ids := true
	for cycle in completed:
		var qualification: Dictionary = cycle.get("qualification", {})
		var protocol_reasons: Array[String] = []
		if String(cycle.get("cycle_id", "")).is_empty(): protocol_reasons.append("cycle_id_missing")
		var cycle_id := String(cycle.get("cycle_id", ""))
		if cycle_ids_seen.has(cycle_id):
			protocol_reasons.append("duplicate_cycle_id")
			distinct_cycle_ids = false
		cycle_ids_seen[cycle_id] = true
		if int(cycle.get("setup_generation", 0)) <= 0: protocol_reasons.append("setup_generation_missing")
		if int(cycle.get("advance_generation", 0)) <= 0: protocol_reasons.append("advance_generation_missing")
		if not cycle.has("requested_resolved_receipt"): protocol_reasons.append("requested_resolved_receipt_missing")
		if not cycle.has("reset_isolation"): protocol_reasons.append("reset_isolation_receipt_missing")
		cycle["receipt_protocol_valid"] = protocol_reasons.is_empty()
		cycle["receipt_protocol_reasons"] = protocol_reasons
		if not protocol_reasons.is_empty(): protocol_rejections.append({"cycle_id":cycle.get("cycle_id", ""),"reasons":protocol_reasons})
		reset_ready = reset_ready and bool(qualification.get("reset_isolation", false)) and bool(qualification.get("sample_available", false))
		renderer_statuses.append(String(qualification.get("renderer_gate_status", DenseWaveProfileClass.UNKNOWN_STATUS)))
	var renderer_consistent := renderer_statuses.size() == 3 and renderer_statuses.all(func(value: String) -> bool: return value == renderer_statuses[0])
	var native_renderer_ready := native_ready and distinct_cycle_ids and protocol_rejections.is_empty() and renderer_consistent and not renderer_statuses.is_empty() and renderer_statuses[0] == DenseWaveProfileClass.NATIVE_STATUS
	var aggregate_high_water_marks: Dictionary = {}
	var aggregate_lifecycle_deltas: Dictionary = {}
	for cycle in completed:
		var cycle_sample: Dictionary = cycle.get("sample", {})
		var cycle_high_water: Dictionary = cycle_sample.get("high_water_marks", (cycle_sample.get("sample_distributions", {}) as Dictionary).get("high_water_marks", {}))
		for key_value in cycle_high_water.keys():
			var key := String(key_value)
			aggregate_high_water_marks[key] = maxf(float(aggregate_high_water_marks.get(key, 0.0)), float(cycle_high_water[key_value]))
		var lifecycle: Dictionary = cycle_sample.get("lifecycle_deltas", {})
		var deltas: Dictionary = lifecycle.get("deltas", {})
		for key_value in deltas.keys():
			var key := String(key_value)
			aggregate_lifecycle_deltas[key] = int(aggregate_lifecycle_deltas.get(key, 0)) + int(deltas[key_value])
	return {
		"identity":"mournlight.native_dense_three_cycle.v1",
		"required_cycle_count":3,
		"completed_cycle_count":completed.size(),
		"cycles":completed,
		"renderer_statuses":renderer_statuses,
		"receipt_protocol_valid":protocol_rejections.is_empty() and completed.size() == 3 and distinct_cycle_ids,
		"receipt_protocol_rejections":protocol_rejections,
		"renderer_consistent":renderer_consistent,
		"native_renderer_eligible":native_renderer_ready,
		"three_cycle_reset_isolation":reset_ready,
		"three_cycle_ready":native_renderer_ready and reset_ready,
		"aggregate_high_water_marks":aggregate_high_water_marks,
		"aggregate_lifecycle_deltas":aggregate_lifecycle_deltas,
		"release_qualification_status":DenseWaveProfileClass.NATIVE_STATUS if native_ready and reset_ready and renderer_consistent and renderer_statuses[0] == DenseWaveProfileClass.NATIVE_STATUS else (DenseWaveProfileClass.SOFTWARE_STATUS if renderer_statuses.has(DenseWaveProfileClass.SOFTWARE_STATUS) else DenseWaveProfileClass.UNKNOWN_STATUS),
		"diagnostic_only":true,
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
	var density := int(sample.get("requested_density", sample.get("requested_enemy_workload", 0)))
	var cohort: Dictionary = sample.get("cohort", {})
	var resolved := int(sample.get("resolved_density", -1))
	var start := int(cohort.get("start", sample.get("start_enemy_workload", -1)))
	var finish := int(cohort.get("end_live", sample.get("end_enemy_workload", -1)))
	entry["matrix_density"] = density
	entry["matrix_sample_valid"] = (
		String(sample.get("sample_kind", "")) == "diagnostic_density_matrix"
		and density in [3, 5, 10, 18, 32]
		and resolved == density and start == density and finish == density
		and int(sample.get("run_serial", -1)) == run_serial
		and int(sample.get("setup_generation", 0)) > 0
		and int(sample.get("advance_generation", 0)) > 0
	)
	entry["matrix_exact_boundary"] = {"requested":density,"resolved":resolved,"start":start,"end":finish}
	for index in range(validation_profile_matrix_samples.size() - 1, -1, -1):
		if int(validation_profile_matrix_samples[index].get("run_serial", -1)) == run_serial and int(validation_profile_matrix_samples[index].get("matrix_density", -1)) == density:
			validation_profile_matrix_samples.remove_at(index)
	validation_profile_matrix_samples.append(entry)
	while validation_profile_matrix_samples.size() > 10:
		validation_profile_matrix_samples.pop_front()

func _profile_matrix_snapshot() -> Dictionary:
	return _evaluate_profile_matrix(validation_profile_matrix_samples, run_serial)

func _evaluate_profile_matrix(samples: Array, matrix_run_serial: int) -> Dictionary:
	var latest_by_density: Dictionary = {}
	var invalid_samples: Array[Dictionary] = []
	for sample_value in samples:
		var sample: Dictionary = sample_value
		if int(sample.get("run_serial", -1)) != matrix_run_serial or not bool(sample.get("matrix_sample_valid", false)):
			invalid_samples.append({"run_serial":sample.get("run_serial", -1),"density":sample.get("matrix_density", 0),"valid":sample.get("matrix_sample_valid", false)})
			continue
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
		"current_run_serial":matrix_run_serial,
		"latest_by_density":latest_by_density,
		"invalid_or_stale_samples":invalid_samples,
		"missing_densities":missing,
		"complete":missing.is_empty(),
		"prepare_and_advance_separate":true,
		"advance_generation":_profile_advance_generation,
		"native_qualification_requires":{"minimum_viewport":[1920,1080],"non_software_renderer":true},
	}

func _density_matrix_contract_checks() -> Dictionary:
	var complete: Array[Dictionary] = []
	for density in [3, 5, 10, 18, 32]:
		complete.append({"run_serial":7,"matrix_density":density,"matrix_sample_valid":true})
	var incomplete := complete.duplicate(true)
	incomplete.pop_back()
	var stale := complete.duplicate(true)
	for sample in stale:
		sample["run_serial"] = 6
	var complete_result := _evaluate_profile_matrix(complete, 7)
	var incomplete_result := _evaluate_profile_matrix(incomplete, 7)
	var stale_result := _evaluate_profile_matrix(stale, 7)
	return {
		"identity":"mournlight.density_matrix_predicate_checks.v1",
		"complete_exact_matrix_accepted":bool(complete_result.get("complete", false)),
		"incomplete_matrix_rejected":not bool(incomplete_result.get("complete", true)) and (incomplete_result.get("missing_densities", []) as Array).has(32),
		"stale_run_samples_rejected":not bool(stale_result.get("complete", true)) and (stale_result.get("latest_by_density", {}) as Dictionary).is_empty(),
		"all_checks_pass":bool(complete_result.get("complete", false)) and not bool(incomplete_result.get("complete", true)) and not bool(stale_result.get("complete", true)),
	}

func _counts_are_isolated(counts: Dictionary) -> bool:
	return (
		int(counts.get("enemies", -1)) == 0
		and int(counts.get("bosses", -1)) == 0
		and int(counts.get("projectiles", -1)) == 0
		and int(counts.get("pickups", -1)) == 0
		and int(counts.get("pending_rewards", -1)) == 0
		and int(counts.get("vitality_visible", -1)) == 0
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

func _percentile_metric(samples: Array, key: String, fraction: float) -> float:
	var values: Array[float] = []
	for sample_value in samples:
		var sample: Dictionary = sample_value
		values.append(float(sample.get(key, 0.0)))
	values.sort()
	return _percentile(values, fraction)

func _max_metric(samples: Array, key: String) -> float:
	var maximum := 0.0
	for sample_value in samples:
		var sample: Dictionary = sample_value
		maximum = maxf(maximum, float(sample.get(key, 0.0)))
	return maximum

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
	var entity_caps := {
		"enemies": int(spawner.live_cap),
		"projectiles": int(lantern_runtime.BOLT_POOL_CAP + gravespade_runtime.SWEEP_POOL_CAP),
		"wisps": int(wisps_runtime.WISP_POOL_CAP),
		"pickups": MAX_ACTIVE_PICKUPS,
		"pending_rewards": MAX_PENDING_REWARDS,
		"telegraphs": int(spawner.telegraph_cue_cap),
		"audio_voices": int(audio_director._mcp_state().get("voice_limit", 0)),
	}
	return {
		"enemies":int(encounter.get("live",0)),
		"pooled_enemies":int(encounter.get("pooled",0)),
		"bosses":1 if is_instance_valid(boss) else 0,
		"projectiles":projectile_count,
		"pickups":_active_pickup_count,
		"pooled_pickups":_pickup_pool.size(), "pickup_pool_total":_pickup_total, "pickup_pool_cap":PICKUP_POOL_CAP,
		"pending_rewards":_pending_reward_events.size(),
		"vitality_visible":int(encounter.get("vitality_visible", 0)),
		"vitality_retired_total":int(encounter.get("vitality_retired_total", 0)),
		"pickup_production_ready":spawner.reward_dropped.is_connected(_on_reward_dropped),
		"effects":_active_effect_count,
		"lights":lights, "audio_voices":audio_voices,
		"telegraph_active":int(encounter.get("telegraph_active", 0)),
		"neighbor_candidate_visits":int(encounter.get("neighbor_candidate_visits", 0)),
		"registered_neighbors":int(encounter.get("registered_neighbors", 0)),
		"target_query_count":int(encounter.get("target_query_count", 0)),
		"target_candidate_visits":int(encounter.get("target_candidate_visits", 0)),
		"target_registry_members":int(encounter.get("target_registry_members", 0)),
		"target_full_group_inventories":int(encounter.get("target_full_group_inventories", 0)),
		"total_target_queries":int(encounter.get("total_target_queries", 0)),
		"total_target_candidate_visits":int(encounter.get("total_target_candidate_visits", 0)),
		"wisp_handles":wisps_runtime.active_wisp_count,
		"wisp_pool_available":wisps_runtime._wisp_pool.size(),
		"wisp_pool_total":wisps_runtime._wisp_pool.size() + wisps_runtime.active_wisp_count,
		"wisp_pool_cap":wisps_runtime.WISP_POOL_CAP,
		"wisp_high_water":wisps_runtime._wisp_high_water,
		"entity_caps":entity_caps,
		"active_entity_total":int(encounter.get("live",0)) + projectile_count + _active_pickup_count + _active_effect_count + audio_voices,
		"transient_caps_respected": int(encounter.get("live",0)) <= entity_caps.enemies and projectile_count <= entity_caps.projectiles + entity_caps.wisps and _active_pickup_count <= entity_caps.pickups and _pending_reward_events.size() <= entity_caps.pending_rewards and audio_voices <= entity_caps.audio_voices,
		"presentation_pools":{
			"lantern":{"active":lantern_runtime.active_presentation_count,"available":lantern_runtime._presentation_pool.size(),"total":lantern_runtime._bolt_total,"cap":lantern_runtime.BOLT_POOL_CAP},
			"gravespade":{"active":gravespade_runtime.active_presentation_count,"available":gravespade_runtime._presentation_pool.size(),"total":gravespade_runtime._sweep_total,"cap":gravespade_runtime.SWEEP_POOL_CAP},
			"pickups":{"active":_active_pickup_count,"available":_pickup_pool.size(),"total":_pickup_total,"cap":PICKUP_POOL_CAP},
		},
		"wisp_interval_targets":wisps_runtime._target_next_hit_time.size(),
		"active_attack_ledgers":world.attack_runtime._hit_ledgers.size(),
		"counter_source":"lifecycle_owners",
	}

func _bounded_static_light_snapshot() -> int:
	_profile_setup_scene_scans += 1
	var count := 0
	for node in world.find_children("*", "Light3D", true, false):
		# find_children can briefly return a queued/freed child during the
		# deferred profile-reset frame; validate the instance before type tests.
		if is_instance_valid(node) and node is Light3D and node.is_visible_in_tree():
			count += 1
	return count

func _profile_observation_work_receipt() -> Dictionary:
	var target_work := spawner.neighbor_registry.get_snapshot() if is_instance_valid(spawner.neighbor_registry) else {}
	return {
		"bounded_setup_scene_scans":_profile_setup_scene_scans,
		"sampled_frame_scene_scans":0,
		"sampled_frame_group_inventories":int(target_work.get("full_group_inventory_count", 0)),
		"target_query_owner":"EncounterSpawner/EnemyNeighborRegistry",
		"target_query_count":int(target_work.get("total_target_queries", 0)),
		"target_candidate_visits":int(target_work.get("total_target_candidate_visits", 0)),
		"target_registry_members":int(target_work.get("registered_count", 0)),
		"sampled_frame_counter_read_count":_profile_sample_counter_reads,
		"system_observation_stride":DenseWaveProfileClass.SYSTEM_OBSERVATION_STRIDE,
		"system_observation_reads":int(ceil(float(_profile_observation_stride) / float(DenseWaveProfileClass.SYSTEM_OBSERVATION_STRIDE))),
		"sample_cadence_seconds":PROFILE_SAMPLE_INTERVAL_SECONDS,
		"sample_history_cap":PROFILE_MAX_SAMPLES,
		"arming_gate_counter_read_count":_profile_gate_counter_reads,
		"counter_sources":["encounter_lifecycle_owners","encounter_target_registry","weapon_presentation_owners","reward_pickup_owners","audio_fixed_voice_pool","wisp_runtime_owners"],
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
	# Native drivers are not required to expose an API-version string on every
	# platform (notably some desktop GL stacks). Treat a complete adapter/vendor
	# pair plus either API or driver details as an identified renderer; software
	# markers still force an explicit rejection below.
	# Some native desktop drivers expose neither a driver-info string nor an API
	# version through Godot's adapter query, even though adapter name/vendor and
	# the active rendering driver are fully identified.  Requiring those optional
	# fields incorrectly classified such runs as unknown and made the dense
	# qualification permanently pending.  Name + vendor + driver is the stable
	# minimum identity; explicit software markers above still take precedence.
	var identity_complete := not adapter_name.strip_edges().is_empty() and not adapter_vendor.strip_edges().is_empty() and not rendering_driver.strip_edges().is_empty()
	var classification := "software" if software_renderer else ("hardware" if identity_complete else "unknown")
	var classification_reason := "software_marker_detected" if software_renderer else ("complete_native_identity" if identity_complete else "renderer_identity_incomplete")
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
		"classification":classification,
		"classification_reason":classification_reason,
		# Keep a concise alias alongside the qualification-specific field so
		# native recapture tooling can consume the renderer predicate without
		# duplicating detector logic. The gate still uses the authoritative
		# `hardware_qualification_eligible` value above.
		"hardware_eligibility":identity_complete and not software_renderer,
		"hardware_qualification_eligible":identity_complete and not software_renderer,
		"project_name":String(ProjectSettings.get_setting("application/config/name", "Mournlight")),
		"profile_identity":"mournlight.release.final_wave.v1",
	}

func _profile_qualification(sample: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	var renderer: Dictionary = sample.get("renderer", {})
	var viewport: Dictionary = sample.get("viewport", {})
	var frame_ms: Dictionary = sample.get("frame_ms", {})
	var sample_count := int(sample.get("sample_count", 0))
	var physics_sample_count := int(sample.get("physics_sample_count", 0))
	var sample_availability: Dictionary = sample.get("sample_availability", {})
	if sample_count <= 0:
		reasons.append("frame_samples_unavailable")
	if physics_sample_count <= 0:
		reasons.append("physics_samples_unavailable")
	if not sample_availability.is_empty() and not bool(sample_availability.get("frame_samples_nonzero", false)):
		reasons.append("frame_sample_availability_false")
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
		var coverage: Dictionary = sample.get("coverage", {})
		var wave_start: Dictionary = sample.get("wave_start", {})
		if String(sample.get("route_kind", "")) != "ordinary" or int(wave_start.get("wave", 0)) != 5 or int(wave_start.get("diagnostic_jump_count", -1)) != 0:
			reasons.append("ordinary_zero_jump_fifth_wave_missing")
		var missing_coverage := _missing_profile_coverage(coverage)
		if not missing_coverage.is_empty():
			reasons.append("representative_coverage_missing:%s" % ",".join(missing_coverage))
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
	var observation_work: Dictionary = sample.get("observation_work", {})
	if int(observation_work.get("sampled_frame_group_inventories", 0)) != 0:
		reasons.append("weapon_target_full_group_inventory_detected")
	var density_qualified := minimum_workload >= PROFILE_DENSITY_MIN and maximum_workload <= PROFILE_DENSITY_MAX and start_workload >= PROFILE_DENSITY_MIN and end_workload >= PROFILE_DENSITY_MIN
	var renderer_classification := String(renderer.get("classification", "unknown"))
	var renderer_eligible := bool(renderer.get("hardware_qualification_eligible", false))
	var gate_status := DenseWaveProfileClass.renderer_status(renderer_classification, renderer_eligible)
	return {"qualified":reasons.is_empty(), "ordinary_route_qualified":passive_ordinary and reasons.is_empty(), "density_qualified":density_qualified, "sample_available":sample_count > 0 and physics_sample_count > 0, "reasons":reasons, "requires_hardware":true, "renderer_gate_status":gate_status, "p95_limit_ms":16.67,
		"required_density_range":{"minimum":25,"maximum":40,"boundary_target":32}}

func _validation_controls_receipt() -> Dictionary:
	var actions := [&"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10", &"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_advance_density", &"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile", &"validation_reset_final_profile"]
	var controls: Array[Dictionary] = []
	for action in actions:
		controls.append({"action":String(action), "registered":InputMap.has_action(action), "physical_binding_count":InputMap.action_get_events(action).size() if InputMap.has_action(action) else 0})
	for action in [&"tester_victory_prepare", &"tester_victory_advance", &"tester_victory_commit", &"tester_failure_prepare", &"tester_failure_advance", &"tester_failure_commit", &"tester_final_profile_prepare", &"tester_final_profile_advance", &"tester_final_profile_reset", &"tester_dense_prepare", &"tester_dense_advance", &"tester_dense_reset"]:
		controls.append({"action":String(action), "registered":InputMap.has_action(action), "physical_binding_count":InputMap.action_get_events(action).size() if InputMap.has_action(action) else 0})
	controls.append({"action":"qa_reset_first_run_guidance", "registered":InputMap.has_action(&"qa_reset_first_run_guidance"), "physical_binding_count":InputMap.action_get_events(&"qa_reset_first_run_guidance").size() if InputMap.has_action(&"qa_reset_first_run_guidance") else 0})
	return {"editor_only":OS.has_feature("editor"), "release_export_available":false, "controls":controls, "prepare_and_advance_separate":true, "density_checkpoints":[3,5,10,18,32], "guidance_reset":_guidance_reset_receipt.duplicate(true)}

func _dense_work_caps(encounter: Dictionary) -> Dictionary:
	var neighbor_state: Dictionary = encounter.get("neighbor_registry", {})
	var audio_state := audio_director._mcp_state()
	var attack_state := world.attack_runtime._mcp_state()
	var camera_budget: Dictionary = {}
	if is_instance_valid(arena_camera):
		camera_budget = (arena_camera._mcp_state().get("dense_render_budget", {}) as Dictionary).duplicate(true)
	return {
		"enemy_pool":spawner.pool_size, "enemy_live":spawner.live_cap,
		"neighbor_candidates_per_query":int(neighbor_state.get("candidate_budget", 12)),
		"telegraph_cues":spawner.telegraph_cue_cap,
		"reward_pickups":MAX_ACTIVE_PICKUPS,
		"vitality_indicators":spawner.pool_size,
		"ordinary_role_lights":spawner.role_light_cap,
		"hurt_lights":spawner.hurt_light_cap,
		"audio_effect_voices":int(audio_state.get("voice_limit", 0)),
		"completed_attack_history":int(attack_state.get("history_limit", 0)),
		"dense_presentation":(encounter.get("dense_presentation_budget", {}) as Dictionary).duplicate(true),
		"shared_work_buckets":DenseWaveProfileClass.work_buckets(),
		"secondary_visibility_compositor":camera_budget,
		"steering_update_budget":{"bucket_count":DenseWaveProfileClass.STEERING_BUCKET_COUNT,"cached_separation":true,"query_policy":"staggered_deterministic_actor_buckets"},
	}

func _profile_workload_receipt(encounter: Dictionary) -> Dictionary:
	var audio_state := audio_director._mcp_state()
	var attack_state := world.attack_runtime._mcp_state()
	var light_budget: Dictionary = encounter.get("ordinary_light_budget", {})
	var counts := _profile_counts()
	var neighbor_work: Dictionary = encounter.get("neighbor_registry", {})
	var actor_work: Dictionary = encounter.get("actor_workload", {})
	var camera_budget: Dictionary = {}
	if is_instance_valid(arena_camera):
		camera_budget = (arena_camera._mcp_state().get("dense_render_budget", {}) as Dictionary).duplicate(true)
	return {
		"role_composition":(encounter.get("roles", {}) as Dictionary).duplicate(true),
		"active_and_pooled":{"active":encounter.get("live", 0),"pooled":encounter.get("pooled", 0)},
		"attacks":{"authorized":attack_state.get("authorized_count", 0),"hits":attack_state.get("hit_count", 0),"active_ledgers":attack_state.get("active_ledgers", 0)},
		"projectiles":counts.get("projectiles", 0),
		"pickups":counts.get("pickups", 0),
		"vitality":{"visible":counts.get("vitality_visible", 0),"retired_total":counts.get("vitality_retired_total", 0),"policy":"authoritative_health_signals_and_actor_local_proximity"},
		"effects":counts.get("effects", 0),
		"audio":{"active_voices":audio_state.get("active_effect_voices", 0),"active_by_owner":(audio_state.get("active_by_owner", {}) as Dictionary).duplicate(true),"voice_limit":audio_state.get("voice_limit", 0)},
		"neighbor_work":neighbor_work.duplicate(true),
		"targeting":{"queries":neighbor_work.get("total_target_queries", 0),"candidate_visits":neighbor_work.get("total_target_candidate_visits", 0),"maximum_result_size":neighbor_work.get("target_maximum_result_size", 0),"full_group_inventories":neighbor_work.get("full_group_inventory_count", 0)},
		"steering":{"steps":actor_work.get("steering_steps", 0),"neighbor_queries":neighbor_work.get("total_queries", 0),"candidate_visits":neighbor_work.get("total_candidate_visits", 0)},
		"physics":{"actor_steps":actor_work.get("physics_steps", 0),"body_motion_steps":actor_work.get("body_motion_steps", 0),"explicit_space_queries":actor_work.get("explicit_space_queries", 0)},
		"presentation_updates":(encounter.get("dense_presentation_budget", {}) as Dictionary).duplicate(true),
		"shared_work_buckets":DenseWaveProfileClass.work_buckets(),
		"secondary_visibility_compositor":camera_budget,
		"light_owners":{"active":light_budget.get("active", 0),"role":(light_budget.get("role", {}) as Dictionary).duplicate(true),"hurt":(light_budget.get("hurt", {}) as Dictionary).duplicate(true)},
		"telegraph_admission":(encounter.get("telegraph_admission", {}) as Dictionary).duplicate(true),
	}

func _profile_workload_window(start: Dictionary, finish: Dictionary) -> Dictionary:
	var start_targeting: Dictionary = start.get("targeting", {})
	var end_targeting: Dictionary = finish.get("targeting", {})
	var start_steering: Dictionary = start.get("steering", {})
	var end_steering: Dictionary = finish.get("steering", {})
	var start_physics: Dictionary = start.get("physics", {})
	var end_physics: Dictionary = finish.get("physics", {})
	var start_presentation: Dictionary = start.get("presentation_updates", {})
	var end_presentation: Dictionary = finish.get("presentation_updates", {})
	var start_attacks: Dictionary = start.get("attacks", {})
	var end_attacks: Dictionary = finish.get("attacks", {})
	return {
		"targeting":{"queries":maxi(0, int(end_targeting.get("queries", 0)) - int(start_targeting.get("queries", 0))),"candidate_visits":maxi(0, int(end_targeting.get("candidate_visits", 0)) - int(start_targeting.get("candidate_visits", 0))),"full_group_inventories":int(end_targeting.get("full_group_inventories", 0))},
		"steering":{"steps":maxi(0, int(end_steering.get("steps", 0)) - int(start_steering.get("steps", 0))),"neighbor_queries":maxi(0, int(end_steering.get("neighbor_queries", 0)) - int(start_steering.get("neighbor_queries", 0))),"candidate_visits":maxi(0, int(end_steering.get("candidate_visits", 0)) - int(start_steering.get("candidate_visits", 0)))},
		"physics":{"actor_steps":maxi(0, int(end_physics.get("actor_steps", 0)) - int(start_physics.get("actor_steps", 0))),"body_motion_steps":maxi(0, int(end_physics.get("body_motion_steps", 0)) - int(start_physics.get("body_motion_steps", 0))),"explicit_space_queries":maxi(0, int(end_physics.get("explicit_space_queries", 0)) - int(start_physics.get("explicit_space_queries", 0)))},
		"presentation":{"updates":maxi(0, int(end_presentation.get("updates", 0)) - int(start_presentation.get("updates", 0))),"skips":maxi(0, int(end_presentation.get("skips", 0)) - int(start_presentation.get("skips", 0))),"facing_updates":maxi(0, int(end_presentation.get("facing_updates", 0)) - int(start_presentation.get("facing_updates", 0)))},
		"combat":{"attacks_authorized":maxi(0, int(end_attacks.get("authorized", 0)) - int(start_attacks.get("authorized", 0))),"hits":maxi(0, int(end_attacks.get("hits", 0)) - int(start_attacks.get("hits", 0)))},
		"end_state":{"projectiles":finish.get("projectiles", 0),"pickups":finish.get("pickups", 0),"effects":finish.get("effects", 0),"audio":finish.get("audio", {}),"lights":finish.get("light_owners", {}),"telegraphs":finish.get("telegraph_admission", {})},
		"counter_reset_scope":"ordinary_run",
	}

func _profile_lifecycle_delta(start: Dictionary, finish: Dictionary) -> Dictionary:
	var keys := [
		"scene_tree_nodes", "object_count", "resource_count", "orphan_nodes", "static_memory_bytes",
		"input_action_count", "owned_signal_bindings", "audio_voices", "enemy_active", "enemy_pooled",
		"projectiles", "pickups", "telegraph_active", "light_count", "active_attack_ledgers", "effects",
		"input_owner_count", "terminal_commit_count",
	]
	var deltas: Dictionary = {}
	for key_value in keys:
		var key := String(key_value)
		deltas[key] = int(finish.get(key, 0)) - int(start.get(key, 0))
	return {"from":start.duplicate(true),"to":finish.duplicate(true),"deltas":deltas,"bounded":true}

func _profile_subsystem_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for sample_value in _profile_metric_samples:
		var sample: Dictionary = sample_value
		samples.append({
			"timestamp_msec":sample.get("timestamp_msec", 0),
			"elapsed_seconds":sample.get("elapsed_seconds", 0.0),
			"subsystems":(sample.get("subsystems", {}) as Dictionary).duplicate(true),
		})
	return samples

func _first_run_guidance_snapshot() -> Dictionary:
	var bindings := {
		"move":input_router.binding_label([&"move_forward", &"move_left", &"move_back", &"move_right"], 4),
		# Dash owns the physical Space/south-button action in gameplay. Menu
		# confirmation is a separate standard UI binding on keyboard (Enter),
		# while the south button remains context-routed on gamepad.
		"dash":input_router.binding_label([&"dash"], 2),
		"confirm":input_router.binding_label([&"context_confirm"] if input_router.active_device == "gamepad" else [&"ui_accept"], 2),
		"help":input_router.binding_label([&"guidance_help"], 2),
	}
	# Keep the tutorial predicates auditable without making the HUD a debug form.
	# These flags are derived from authoritative movement, dash, attack, drop,
	# attraction, collection, and draft receipts; no wall-clock timer can advance
	# the sequence or claim a milestone early.
	var attraction_seen := not _reward_attraction_receipt.is_empty()
	var collection_seen := not _reward_collection_receipt.is_empty() and pickup_collected_total > 0
	var drop_seen := pickup_spawned_total > 0 and not _reward_spawn_receipt.is_empty()
	var upgrade_seen := _first_run_guidance_completed or not _first_run_guidance_completion.is_empty()
	var milestones := {
		"movement":_guidance_movement_observed,
		"dash":_guidance_dash_observed,
		"automatic_attack":_guidance_attack_observed,
		"death_position_drop":drop_seen,
		"attraction":attraction_seen,
		"collection":collection_seen,
		"first_upgrade":upgrade_seen,
	}
	var drop_position: Variant = _reward_spawn_receipt.get("position", null) if drop_seen else null
	if _first_run_guidance_completed:
		return {"visible":false,"stage":"complete","completed":true,"completion":_first_run_guidance_completion.duplicate(true),"bindings":bindings,"help_surface":"pause_controls_and_help","device":input_router.active_device,"milestones":milestones,"drop_position":drop_position,"reset":_guidance_reset_receipt.duplicate(true)}
	if run_route_kind != "ordinary" or run_state not in ["active", "draft"]:
		return {"visible":false,"stage":"inactive","completed":false,"bindings":bindings,"help_surface":"pause_controls_and_help","device":input_router.active_device,"milestones":milestones,"drop_position":drop_position,"reset":_guidance_reset_receipt.duplicate(true)}
	var stage := "movement"
	var title := "KEEPER'S FIRST VIGIL"
	var prompt := "MOVE TO KEEP AN ESCAPE LANE"
	var action_label := String(bindings.move)
	var icon := "move"
	if draft_controller.active:
		stage = "natural_upgrade_draft"
		prompt = "CHOOSE ONE UPGRADE; IT APPLIES BEFORE COMBAT RESUMES"
		action_label = String(bindings.confirm)
		icon = "upgrade"
	elif pickup_collected_total > 0:
		stage = "collection_progress"
		prompt = "COLLECT WISPS TO FILL THE MOON-SILVER LEVEL BAR"
		action_label = "MOVE THROUGH THE WISP"
		icon = "wisp"
	elif pickup_spawned_total > 0 and not attraction_seen:
		stage = "world_drop_and_attraction"
		prompt = "A WISP FELL WHERE THE THREAT DIED; MOVE CLOSE TO DRAW IT IN"
		action_label = String(bindings.move)
		icon = "wisp"
	elif attraction_seen and not collection_seen:
		stage = "collection_progress"
		prompt = "KEEP MOVING THROUGH THE ATTRACTING WISP TO COLLECT ITS EXPERIENCE"
		action_label = "MOVE THROUGH THE WISP"
		icon = "wisp"
	elif _guidance_progress_stage < 1 and not _guidance_movement_observed:
		stage = "movement"
	elif _guidance_progress_stage < 2 and not _guidance_dash_observed:
		stage = "dash"
		prompt = "DASH THROUGH PRESSURE; THE BRIEF FLASH MARKS SAFETY"
		action_label = String(bindings.dash)
		icon = "dash"
	elif _guidance_progress_stage < 3 and not _guidance_attack_observed:
		stage = "automatic_attack"
		prompt = "FACE THE THREAT; THE WARDEN LANTERN ATTACKS AUTOMATICALLY"
		action_label = "NO FIRE BUTTON"
		icon = "lantern"
	elif _guidance_progress_stage >= 3:
		# Keep the last combat teaching cue visible until the first authored
		# death-position drop appears.  A monotonic progress receipt must not
		# fall back to the opening movement card between milestones.
		stage = "automatic_attack"
		prompt = "FACE THE THREAT; THE WARDEN LANTERN ATTACKS AUTOMATICALLY"
		action_label = "NO FIRE BUTTON"
		icon = "lantern"
	return {"visible":not _first_run_guidance_dismissed,"stage":stage,"progress_stage":_guidance_progress_stage,"title":title,"prompt":prompt,"action_label":action_label,"icon":icon,"completed":false,"bindings":bindings,"inputmap_bound":true,"device":input_router.active_device,"device_generation":input_router.device_generation,"dismissal":"toggle_guidance_help_action","dismissed":_first_run_guidance_dismissed,"persists_across_retry_after_completion":true,"help_surface":"pause_controls_and_help","illustration":"res://assets/ui/guidance/first_run_gameplay.png","milestones":milestones,"drop_position":drop_position,"reset":_guidance_reset_receipt.duplicate(true)}

func _qa_reset_first_run_guidance() -> void:
	if not OS.has_feature("editor"):
		return
	_guidance_reset_generation += 1
	_first_run_guidance_completed = false
	_first_run_guidance_dismissed = false
	_first_run_guidance_completion.clear()
	_guidance_movement_observed = false
	_guidance_dash_observed = false
	_guidance_attack_observed = false
	_guidance_progress_stage = 0
	_guidance_attack_baseline = world.attack_runtime.authorized_count
	_guidance_reset_receipt = {
		"requested":true, "resolved":true,
		"generation":_guidance_reset_generation,
		"editor_only":true, "physical_binding_count":0,
		"release_action_exposed":false,
		"run_serial":run_serial, "reset_isolated_to_guidance":true,
	}
	_emit_snapshot()

func _reward_feedback_snapshot() -> Dictionary:
	var states := {"settle":0,"attracting":0,"collection_fx":0}
	var audio_state := audio_director._mcp_state()
	for pickup_value in _active_pickups.values():
		if not is_instance_valid(pickup_value):
			continue
		var pickup := pickup_value as RewardPickup
		states[pickup.state] = int(states.get(pickup.state, 0)) + 1
	return {
		"spawned_total":pickup_spawned_total,
		"collected_total":pickup_collected_total,
		"live":_active_pickup_count,
		"visual_cap":MAX_ACTIVE_PICKUPS,
		"cap_respected":_active_pickup_count <= MAX_ACTIVE_PICKUPS,
		"pending":_pending_reward_events.size(),
		"pending_cap":MAX_PENDING_REWARDS,
		"cap_deferrals":_reward_cap_deferrals,
		"states":states,
		"known_identity_count":_known_reward_ids.size(),
		"resolved_identity_count":_resolved_reward_ids.size(),
		"duplicate_rejections":_reward_duplicate_rejections,
		"last_spawn":_reward_spawn_receipt.duplicate(true),
		"last_attraction":_reward_attraction_receipt.duplicate(true),
		"last_collection":_reward_collection_receipt.duplicate(true),
		"last_experience":_reward_experience_receipt.duplicate(true),
		"pickup_audio":(audio_state.get("last_pickup_audio_receipt", {}) as Dictionary).duplicate(true),
		"pickup_audio_event_count":audio_state.get("pickup_audio_event_count", 0),
		"collection_audio_one_to_one":int(audio_state.get("pickup_audio_event_count", -1)) == pickup_collected_total,
		"duplicate_attempts_rejected":_reward_duplicate_rejections,
		"duplicate_acceptances":0,
		"exactly_once":_reward_identity_integrity(),
		"update_policy":"lifecycle_signals_and_active_owner_map",
	}

func _reward_identity_integrity() -> bool:
	if _resolved_reward_ids.size() > _known_reward_ids.size():
		return false
	for drop_id in _resolved_reward_ids:
		if not _known_reward_ids.has(drop_id):
			return false
	return true

func _input_binding_summary(actions: Array, maximum_labels: int) -> String:
	var keyboard_labels: Array[String] = []
	var device_labels: Array[String] = []
	for action in actions:
		for event in InputMap.action_get_events(action):
			var label := ""
			if event is InputEventKey:
				var key_event := event as InputEventKey
				var keycode := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
				label = OS.get_keycode_string(keycode).to_upper()
			elif event is InputEventJoypadMotion:
				label = "LEFT STICK"
			elif event is InputEventJoypadButton:
				label = "GAMEPAD SOUTH"
			else:
				label = event.as_text().strip_edges()
			var destination: Array[String] = keyboard_labels if event is InputEventKey else device_labels
			if label.is_empty() or destination.has(label):
				continue
			destination.append(label)
	var labels := keyboard_labels + device_labels
	if labels.size() > maximum_labels:
		labels.resize(maximum_labels)
	return " / ".join(labels) if not labels.is_empty() else "UNBOUND"

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
		# Mirror the compact cap receipt in lifecycle snapshots so pause/reset,
		# death/result, and restart checkpoints can verify bounded transient state
		# without depending on a profile window having been armed.
		"entity_caps":(counts.get("entity_caps", {}) as Dictionary).duplicate(true),
		"active_entity_total":int(counts.get("active_entity_total", 0)),
		"transient_caps_respected":bool(counts.get("transient_caps_respected", false)),
		"input_owner_count":input_router.active_transactions.size(),
		"input_context":input_router.context,
		"input_reset": {
			"router_generation":input_router.reset_generation,
			"router_receipt":input_router.last_reset_receipt.duplicate(true),
			"warden_generation":warden.reset_generation,
			"warden_receipt":warden.last_reset_receipt.duplicate(true),
			"ownership_aligned": input_router.context in ["active", "boss"] or (
				warden.dash_phase == "ready" and not warden.dash_invulnerable
				and warden.movement_input.length_squared() <= 0.0001
			),
		},
		"terminal_commit_count":terminal_commit_count,
	}

func _route_qualification(wave_state: Dictionary) -> Dictionary:
	return {
		"expected_wave_ids":(wave_state.get("expected_route_wave_ids", []) as Array).duplicate(),
		"observed_wave_ids":(wave_state.get("ordinary_route_wave_ids", []) as Array).duplicate(),
		"ordinary_route_complete":bool(wave_state.get("ordinary_route_complete", false)),
		"ordinary_boss_entry_ready":bool(wave_state.get("ordinary_boss_entry_ready", false)),
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
	var route_receipt := wave_director.get_route_contract_receipt()
	var reset_invariants := _terminal_reset_invariants("retry" if reason == "retry" else "fresh_start")
	var receipt := {
		"run_serial":run_serial, "baseline_generation":_retry_baseline_generation,
		"source":reason,
		"tree_paused":get_tree().paused, "run_state":run_state,
		"route_id":String(route_receipt.get("contract_id", "")),
		"route_progress":route_receipt.get("observed_wave_ids", []).duplicate(),
		"route_spatial":world.arena_contract.get_route_spatial_receipt() if world.arena_contract.has_method("get_route_spatial_receipt") else {},
		"reset_generation":input_router.reset_generation,
		"counts":_profile_counts(),
		"warden_animation":warden.animation_binding.get_snapshot() if warden.animation_binding else {},
		"reset_invariants":reset_invariants,
		"world_active":world.session_active,
		"teardown_generation":teardown_receipt.get("completion_generation",0),
		"stale_actor_timer_audio_cleanup":bool(reset_invariants.get("complete", false)),
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
	input_router.clear_transaction_latches("validation_density_prepare")
	run_route_kind = "diagnostic_prepared"
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
	experience = 0
	experience_threshold = 9999
	get_tree().paused = true
	var build_receipt := inventory.prepare_legal_build("representative")
	# Bind the final Bellkeeper definition before density admission. This keeps
	# the editor-only 32-enemy checkpoint from inheriting a stale ordinary cap.
	var checkpoint_wave := 4 if target_live >= DenseWaveProfileClass.TARGET_ENEMIES else 3
	wave_director.prepare_test_wave(checkpoint_wave)
	var checkpoint_definition: Dictionary = wave_director.get_snapshot().get("definition", {})
	if not checkpoint_definition.is_empty():
		spawner.configure_pressure(checkpoint_definition)
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
	_profile_sample_accumulator = 0.0
	_profile_sample_counter_reads = 0
	_profile_active = true
	_profile_paused = false
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
	input_router.clear_transaction_latches("validation_density_reset")
	_profile_active = false
	_profile_paused = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	spawner.end_validation_profile_cohort("density_matrix_reset")
	var pending_retired := _pending_reward_events.size()
	_pending_reward_events.clear()
	var pickups_retired := _retire_run_group(&"reward_pickup")
	_active_pickups.clear()
	_active_pickup_count = 0
	spawner.reset_encounter()
	_validation_setup_generation += 1
	var after := spawner.get_snapshot()
	validation_density_receipt = {
		"accepted":true, "reset":true, "requested_density":0,
		"resolved_density":int(after.get("live", 0)), "run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"reset_generation":_validation_setup_generation,
		"active":int(after.get("live", 0)), "pooled":int(after.get("pooled", 0)),
		"pickups_retired":pickups_retired, "pending_rewards_retired":pending_retired,
		"reward_owner_count_after":_active_pickup_count,
		"light_budget":(after.get("ordinary_light_budget", {}) as Dictionary).duplicate(true),
		"neighbor_registry":(after.get("neighbor_registry", {}) as Dictionary).duplicate(true),
		"telegraph_admission":(after.get("telegraph_admission", {}) as Dictionary).duplicate(true),
		"reset_isolated":int(after.get("live", -1)) == 0 and int((after.get("neighbor_registry", {}) as Dictionary).get("registered_count", -1)) == 0 and int((after.get("ordinary_light_budget", {}) as Dictionary).get("active", -1)) == 0 and _active_pickup_count == 0 and _pending_reward_events.is_empty(),
	}
	_emit_snapshot()

func _prepare_tester_victory() -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"] or result_committed or _victory_transaction_active:
		return
	input_router.clear_transaction_latches("tester_victory_prepare")
	_victory_fixture_commit_held = false
	_victory_fixture_hold_generation = -1
	run_route_kind = "diagnostic_prepared"
	inventory.prepare_legal_build("representative")
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
	warden.global_position = world.arena_contract.get_player_spawn()
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
	# Preparation is an inspectable checkpoint, not a modal pause. Leaving the
	# tree running lets Tester invoke the separate advance edge through the
	# registered input surface; advance itself owns the presentation hold.
	get_tree().paused = false
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
		# Preparation must leave the failure branch inspectable.  The previous
		# helper applied lethal damage immediately, skipping the causal failure
		# transition and making it impossible for Tester to capture a stable
		# pre-Result state.  Route the legacy validation action through the same
		# prepare/advance contract as the explicit tester controls.
		_prepare_tester_failure()

func _prepare_tester_failure() -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"] or result_committed:
		return
	input_router.clear_transaction_latches("tester_failure_prepare")
	run_route_kind = "diagnostic_prepared"
	inventory.prepare_legal_build("representative")
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
	warden.global_position = world.arena_contract.get_player_spawn()
	warden.velocity = Vector3.ZERO
	warden.planar_velocity = Vector3.ZERO
	warden.reset_input_latch("tester_failure_prepare")
	world.set_session_active(true)
	_validation_setup_generation += 1
	# Keep the prepared failure branch live so the explicit advance action can be
	# delivered through the normal tester input context.
	get_tree().paused = false
	tester_failure_fixture_receipt = {
		"branch_id":"tester_failure_transaction",
		"requested_branch_id":"tester_failure_transaction.prepare",
		"resolved_branch_id":"tester_failure_transaction.prepared",
		"setup_generation":_validation_setup_generation,
		"run_serial":run_serial,
		"requested_state":"stable_warden_before_failure",
		"resolved_state":run_state,
		"requested_route_kind":"diagnostic_prepared",
		"resolved_route_kind":run_route_kind,
		"prepare_paused":get_tree().paused,
		"result_committed":result_committed,
		"terminal_commit_count":terminal_commit_count,
		"advance_requested":false,
		"advance_resolved":false,
		"commit_requested":false,
		"commit_resolved":false,
		"rejected_edge_count":0,
		"preparation_has_no_terminal_onset":not result_committed and terminal_snapshot.is_empty(),
		"counts":_profile_counts(),
		"lifecycle":_lifecycle_counters(),
	}
	_emit_snapshot()

func _advance_tester_failure() -> void:
	if not OS.has_feature("editor") or String(tester_failure_fixture_receipt.get("branch_id", "")) != "tester_failure_transaction":
		return
	if int(tester_failure_fixture_receipt.get("setup_generation", -1)) != _validation_setup_generation or int(tester_failure_fixture_receipt.get("run_serial", -1)) != run_serial:
		tester_failure_fixture_receipt["rejected_edge_count"] = int(tester_failure_fixture_receipt.get("rejected_edge_count", 0)) + 1
		tester_failure_fixture_receipt["last_rejected_edge"] = {"action":"advance", "reason":"stale_generation_or_run"}
		_emit_snapshot()
		return
	if result_committed or run_state not in ["active", "boss"]:
		tester_failure_fixture_receipt["rejected_edge_count"] = int(tester_failure_fixture_receipt.get("rejected_edge_count", 0)) + 1
		tester_failure_fixture_receipt["last_rejected_edge"] = {"action":"advance", "reason":"already_terminal_or_wrong_state"}
		_emit_snapshot()
		return
	get_tree().paused = false
	tester_failure_fixture_receipt["advance_requested"] = true
	tester_failure_fixture_receipt["advance_frame"] = Engine.get_process_frames()
	var resolution := health.apply_damage({
		"attack_id":"tester.failure.advance.g%04d" % _validation_setup_generation,
		"damage":health.current_health + 1.0,
		"damage_channel":"tester_failure_advance",
	})
	tester_failure_fixture_receipt["advance_resolved"] = bool(resolution.get("accepted", false)) and result_committed
	tester_failure_fixture_receipt["resolved_branch_id"] = "tester_failure_transaction.result_pending" if bool(tester_failure_fixture_receipt["advance_resolved"]) else "tester_failure_transaction.advance_rejected"
	tester_failure_fixture_receipt["resolved_state"] = run_state
	tester_failure_fixture_receipt["result_committed_after_advance"] = result_committed
	tester_failure_fixture_receipt["terminal_commit_count_after_advance"] = terminal_commit_count
	tester_failure_fixture_receipt["presentation_paused"] = get_tree().paused
	_emit_snapshot()

func _commit_tester_failure() -> void:
	if not OS.has_feature("editor") or String(tester_failure_fixture_receipt.get("branch_id", "")) != "tester_failure_transaction":
		return
	if not bool(tester_failure_fixture_receipt.get("advance_resolved", false)):
		tester_failure_fixture_receipt["rejected_edge_count"] = int(tester_failure_fixture_receipt.get("rejected_edge_count", 0)) + 1
		tester_failure_fixture_receipt["last_rejected_edge"] = {"action":"commit", "reason":"failure_not_advanced"}
		_emit_snapshot()
		return
	tester_failure_fixture_receipt["commit_requested"] = true
	tester_failure_fixture_receipt["commit_frame"] = Engine.get_process_frames()
	# Failure already owns the authoritative Result handoff; commit is a
	# receipt-only edge that confirms exactly one terminal snapshot.
	tester_failure_fixture_receipt["commit_resolved"] = result_committed and terminal_commit_count == 1
	tester_failure_fixture_receipt["resolved_branch_id"] = "tester_failure_transaction.result_committed" if bool(tester_failure_fixture_receipt["commit_resolved"]) else "tester_failure_transaction.commit_rejected"
	tester_failure_fixture_receipt["terminal_commit_count"] = terminal_commit_count
	_emit_snapshot()

func _emit_snapshot() -> void:
	if not is_node_ready():
		return
	last_snapshot = RunSnapshot.make(self, world, warden, health, spawner, inventory)
	snapshot_changed.emit(last_snapshot)
	if run_state in ["active", "boss", "paused", "draft"]:
		hud.bind_snapshot(last_snapshot)

func _mcp_state() -> Dictionary:
	var wave_state := wave_director.get_snapshot()
	var profile_renderer: Dictionary = validation_profile_sample.get("renderer", validation_profile_receipt.get("renderer", {}))
	var profile_viewport: Dictionary = validation_profile_sample.get("viewport", validation_profile_receipt.get("viewport", {}))
	var profile_frame_ms: Dictionary = validation_profile_sample.get("frame_ms", {})
	var profile_cohort: Dictionary = validation_profile_sample.get("cohort", {})
	var profile_qualification: Dictionary = validation_profile_sample.get("qualification", {})
	var profile_coverage: Dictionary = validation_profile_sample.get("coverage", {})
	var cycle_comparison := _profile_cycle_comparison()
	var dense_cycle_comparison := _dense_profile_cycle_comparison()
	var ledger_snapshot := complete_run_ledger.get_snapshot()
	var ledger_matrix: Dictionary = ledger_snapshot.get("matrix", {})
	var ledger_checks: Dictionary = ledger_snapshot.get("contract_checks", {})
	var observation_work: Dictionary = validation_profile_sample.get("observation_work", _profile_observation_work_receipt())
	return {
		"candidate_session_handshake":candidate_session_handshake.duplicate(true),
		"run_state":run_state, "run_serial":run_serial, "run_elapsed":run_elapsed,
		"profile_status":validation_profile_sample.get("status", validation_profile_receipt.get("status", "idle")),
		"profile_active":_profile_active,
		"profile_paused":_profile_paused,
		"profile_armed":_profile_armed,
		"profile_arm_receipt":_profile_arm_receipt,
		"profile_rearm_count":_profile_rearm_count,
		"profile_coverage":profile_coverage,
		"profile_missing_coverage":validation_profile_sample.get("missing_coverage", _missing_profile_coverage(profile_coverage) if not profile_coverage.is_empty() else []),
		"profile_sample_kind":validation_profile_sample.get("sample_kind", ""),
		"profile_p50_ms":profile_frame_ms.get("p50", 0.0),
		"profile_p95_ms":profile_frame_ms.get("p95", 0.0),
		"profile_p99_ms":profile_frame_ms.get("p99", 0.0),
		"profile_worst_ms":profile_frame_ms.get("worst", 0.0),
		"profile_frame_sample_count":validation_profile_sample.get("sample_count", 0),
		"profile_telemetry_sample_count":validation_profile_sample.get("telemetry_sample_count", 0),
		"profile_telemetry_samples":validation_profile_sample.get("telemetry_samples", []),
		"profile_subsystem_samples":validation_profile_sample.get("subsystem_samples", []),
		"profile_sample_distributions":validation_profile_sample.get("sample_distributions", {}),
		"profile_high_water_marks":validation_profile_sample.get("high_water_marks", {}),
		"profile_lifecycle_deltas":validation_profile_sample.get("lifecycle_deltas", {}),
		"profile_physics_sample_count":validation_profile_sample.get("physics_sample_count", 0),
		"profile_sample_availability":validation_profile_sample.get("sample_availability", {}),
		"profile_frame_execution":validation_profile_sample.get("frame_execution", {}),
		"profile_preflight":validation_profile_sample.get("preflight", validation_profile_receipt.get("preflight", {})),
		"profile_cycle_provenance":validation_profile_sample.get("cycle_provenance", validation_profile_receipt.get("cycle_provenance", {})),
		"profile_sampling_renderer_independent":validation_profile_sample.get("sampling_renderer_independent", true),
		"profile_frame_duration_seconds":validation_profile_sample.get("window_seconds", 0.0),
		"profile_frames_over_budget":profile_frame_ms.get("over_budget_16_67_count", 0),
		"profile_subsystem_window":validation_profile_sample.get("subsystem_window", {}),
		"profile_renderer_classification":profile_renderer.get("classification", "unknown"),
		"profile_hardware_eligible":profile_renderer.get("hardware_qualification_eligible", false),
		"profile_renderer_gate_status":validation_profile_sample.get("renderer_gate_status", validation_profile_receipt.get("renderer_gate_status", DenseWaveProfileClass.UNKNOWN_STATUS)),
		# Both software rejection and unknown renderer identity require the same
		# native host recapture; only an explicitly qualified native status clears
		# this pending flag.
		"profile_native_qualification_pending":String(validation_profile_sample.get("renderer_gate_status", validation_profile_receipt.get("renderer_gate_status", DenseWaveProfileClass.UNKNOWN_STATUS))) != DenseWaveProfileClass.NATIVE_STATUS,
		"profile_viewport_width":profile_viewport.get("width", 0),
		"profile_viewport_height":profile_viewport.get("height", 0),
		"profile_requested_enemies":profile_cohort.get("requested", validation_profile_sample.get("requested_enemy_workload", 0)),
		"profile_start_enemies":profile_cohort.get("start", validation_profile_sample.get("start_enemy_workload", 0)),
		"profile_minimum_enemies":profile_cohort.get("minimum", validation_profile_sample.get("minimum_enemy_workload", 0)),
		"profile_end_enemies":profile_cohort.get("end_live", validation_profile_sample.get("end_enemy_workload", 0)),
		"profile_qualified":profile_qualification.get("qualified", validation_profile_receipt.get("status", "") == DenseWaveProfileClass.NATIVE_STATUS),
		"profile_sampled_frame_scene_scans":observation_work.get("sampled_frame_scene_scans", 0),
		"profile_sampled_frame_group_inventories":observation_work.get("sampled_frame_group_inventories", 0),
		"profile_sampled_frame_counter_reads":observation_work.get("sampled_frame_counter_read_count", _profile_sample_counter_reads),
		"profile_completed_cycles":cycle_comparison.get("completed_cycle_count", 0),
		"profile_stale_reset_context_cycles":cycle_comparison.get("stale_reset_context_cycle_count", 0),
		"profile_three_cycle_context_truthful":cycle_comparison.get("three_cycle_context_truthful", false),
		"profile_three_cycle_no_growth":cycle_comparison.get("three_cycle_no_growth", false),
		"dense_profile_cycle_comparison":dense_cycle_comparison,
		"dense_profile_completed_cycles":dense_cycle_comparison.get("completed_cycle_count", 0),
		"dense_profile_three_cycle_ready":dense_cycle_comparison.get("three_cycle_ready", false),
		"dense_profile_release_status":dense_cycle_comparison.get("release_qualification_status", DenseWaveProfileClass.UNKNOWN_STATUS),
		"dense_profile_receipt_protocol": {
			"contract_signature":DenseWaveProfileClass.CONTRACT_SIGNATURE,
			"contract_version":DenseWaveProfileClass.CONTRACT_VERSION,
			"required_enemy_range":{"minimum":PROFILE_DENSITY_MIN,"maximum":PROFILE_DENSITY_MAX,"target":DenseWaveProfileClass.TARGET_ENEMIES},
			"target_viewport":{"width":1920,"height":1080},
			"required_cycles":3,
			"sequence":["prepare","advance","reset"],
			"timeout_policy":"bounded_pending_then_reset",
			"self_audit_pass":bool(dense_profile_self_audit.get("all_checks_pass", false)),
			"host_handoff":DenseWaveProfileClass.host_handoff_contract(),
		},
		"profile_reset_contexts":{
			"immediate":validation_profile_receipt.get("input_context", "unavailable"),
			"next_frame":validation_profile_receipt.get("next_frame_input_context", "pending"),
			"live":input_router.context,
			"run_state":run_state,
		},
		"profile_reset_isolation":{
			"immediate":validation_profile_receipt.get("reset_isolation", false),
			"next_frame":validation_profile_receipt.get("next_frame_isolation", false),
			"pending":validation_profile_receipt.get("next_frame_isolation_pending", false),
		},
		"ordinary_wave_ids":wave_state.get("ordinary_route_wave_ids", []),
		"authored_route_spatial":world.arena_contract.get_route_spatial_receipt() if world.arena_contract.has_method("get_route_spatial_receipt") else {},
		"ordinary_diagnostic_jumps":wave_state.get("diagnostic_jump_count", 0),
		"ordinary_natural_progression_truthful":_ordinary_progression_truthful(),
		"ordinary_boss_two_phase_truthful":_boss_two_phase_history_truthful(),
		"ledger_contract_checks_pass":ledger_checks.get("all_checks_pass", false),
		"density_matrix_contract_checks_pass":density_matrix_contract_checks.get("all_checks_pass", false),
		"ledger_failure_result_retry":ledger_matrix.get("failure_result_retry", false),
		"ledger_victory_result_replay":ledger_matrix.get("victory_result_replay", false),
		"ledger_distinct_build_row_count":ledger_matrix.get("distinct_build_row_count", 0),
		"ledger_build_shape_rows":ledger_matrix.get("ordinary_build_shape_rows", {}),
		"ledger_row_qualifications":ledger_matrix.get("row_qualifications", []),
		"ledger_credits_traversed":ledger_matrix.get("credits_traversed", false),
		"ledger_missing_rows":ledger_matrix.get("remaining_matrix_cells", ledger_matrix.get("missing_rows", [])),
		"authoritative_teardown":teardown_receipt,
		"experience": experience, "experience_threshold": experience_threshold, "pending_levelup_transactions": _pending_levelup_transactions, "level": level,
		"defeated_enemies": defeated_enemies, "damage_taken": damage_taken,
		"damage_dealt":damage_dealt,"outcome":outcome,"selected_upgrade_count":selected_upgrades.size(),
		"wave":{"wave":wave_state.get("wave",0),"wave_count":wave_state.get("wave_count",5),"phase":wave_state.get("phase","idle"),"title":wave_state.get("title","")},
		"boss":{"active":boss_snapshot.get("active",false),"health":boss_snapshot.get("health",0.0),"health_maximum":boss_snapshot.get("health_maximum",0.0),"phase":boss_snapshot.get("phase",0)},"quit_requested":quit_requested,
		"result_committed": result_committed, "terminal_snapshot_digest": _terminal_snapshot_digest(), "state_history": state_history,
		"terminal_commit_count":terminal_commit_count, "run_route_kind":run_route_kind,
		"terminal_guard": {
			"result_committed":result_committed,
			"commit_count":terminal_commit_count,
			"victory_transaction_active":_victory_transaction_active,
			"source_run_serial":_victory_source_run_serial,
			"exactly_once":terminal_commit_count <= 1,
		},
		"draft_transaction_guard": {
			"active":draft_controller.active,
			"pending_levelup_transactions":_pending_levelup_transactions,
			"commit_in_progress":_upgrade_commit_in_progress,
			"view_latched":draft_view.latched,
			"serial":draft_controller.draft_serial,
		},
		"victory_transaction":{"active":_victory_transaction_active,"source_run_serial":_victory_source_run_serial,"hold_required_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,"hold_elapsed_seconds":_victory_hold_elapsed,"hold_remaining_seconds":_victory_hold_remaining,"tester_commit_held":_victory_fixture_commit_held,"tester_hold_generation":_victory_fixture_hold_generation},
		"boss_transition_history":boss_transition_history,
		"natural_build_history":selected_upgrades,
		"natural_build_history_truthful":_natural_build_history_truthful(),
		"route_qualification":_route_qualification(wave_state),
		"upgrade_draft":draft_controller.get_snapshot(), "upgrade_transaction":upgrade_transaction_receipt.duplicate(true), "teardown_receipt":teardown_receipt,
		"tree_paused": get_tree().paused, "shell_mode": shell.mode,
		"shell_return_mode": shell.return_mode, "shell_action_latched": shell.action_latched,
		# Keep the two release-convergence surfaces directly discoverable from the
		# controller snapshot.  Tester can bind a page transition or route receipt
		# without scraping presentation labels or inferring ownership from pause.
		"shell_accessibility": shell._mcp_state().get("accessibility_contract", {}),
		"shell_focus_action": shell._mcp_state().get("focus_action", ""),
		"route_contract": wave_director.get_route_contract_receipt(),
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
		"dense_profile_contract":DenseWaveProfileClass.contract(),
		"dense_profile_self_audit":dense_profile_self_audit,
		"validation_retry_baselines":validation_retry_baselines,
		"ordinary_victory_receipt":ordinary_victory_receipt,
		"ordinary_victory_transactions":ordinary_victory_transactions,
		"warden_hat_isolation":warden.hat_isolation_receipt,
		"complete_run_ledger":complete_run_ledger.get_snapshot(),
		"validation_profile_matrix":_profile_matrix_snapshot(),
		"tester_victory_fixture":tester_victory_fixture_receipt,
		"tester_failure_fixture":tester_failure_fixture_receipt,
		"reward_pickups":{"spawned_total":pickup_spawned_total,"collected_total":pickup_collected_total,"live":_active_pickup_count},
		"reward_feedback":_reward_feedback_snapshot(),
		"vitality_indicators":spawner._mcp_state().get("vitality_indicators", {}),
		"first_run_guidance":_first_run_guidance_snapshot(),
		"shell_focus": String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none",
	}

## Public, read-only snapshot entrypoint for black-box harnesses.
##
## Most MCP probes consume `_mcp_state()` directly, but host/Tester replay
## scripts may only have access to the authoritative controller node. Keeping
## this tiny alias avoids forcing those probes to depend on a private method
## name while preserving one source of truth for all receipts.
func get_snapshot() -> Dictionary:
	return _mcp_state().duplicate(true)

## Stable route receipt used by ordinary-run replay checks. This delegates to
## the wave director so route eligibility can never diverge between the
## controller snapshot and the director's contiguous-wave ledger.
func get_route_contract_receipt() -> Dictionary:
	return wave_director.get_route_contract_receipt().duplicate(true)

## Read-only handles for the two bounded release-convergence protocols. The
## returned dictionaries are deep copies so a diagnostic collector cannot
## mutate authoritative lifecycle state while inspecting a receipt.
func get_dense_profile_receipt() -> Dictionary:
	return {
		"contract":DenseWaveProfileClass.contract(),
		"requested":validation_profile_receipt.duplicate(true),
		"sample":validation_profile_sample.duplicate(true),
		"cycles":validation_profile_cycles.duplicate(true),
		"active":_profile_active,
		"cycle_index":_dense_cycle_index,
	}.duplicate(true)

func get_upgrade_transaction_receipt() -> Dictionary:
	return upgrade_transaction_receipt.duplicate(true)

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
