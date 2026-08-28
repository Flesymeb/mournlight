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
const BELLKEEPER_SCENE := preload("res://scenes/enemies/bellkeeper.tscn")
const REWARD_PICKUP_SCENE := preload("res://scenes/gameplay/reward_pickup.tscn")
const MAX_ACTIVE_PICKUPS := 16
const VICTORY_PRESENTATION_HOLD_SECONDS := 2.6

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	if OS.has_feature("editor"):
		for action in [&"validation_prepare_wave4", &"validation_prepare_boss", &"validation_prepare_draft", &"validation_prepare_result_failure", &"validation_prepare_result_victory", &"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10", &"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile", &"validation_reset_final_profile", &"tester_victory_prepare", &"tester_victory_advance", &"tester_final_profile_prepare", &"tester_final_profile_advance", &"tester_final_profile_reset"]:
			if not InputMap.has_action(action):
				InputMap.add_action(action)
	_enter_title()

func _process(delta: float) -> void:
	_advance_context_handoff()
	_advance_victory_transaction(delta)
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
	_profile_elapsed = 0.0
	_profile_start_counts.clear()
	_transition("initializing")
	run_serial += 1
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
	warden.pickup_collection_radius = 1.15
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
	var victory_transaction := ordinary_victory_receipt.duplicate(true)
	var victory_fixture := tester_victory_fixture_receipt.duplicate(true)
	_next_baseline_reason = "retry"
	_teardown_run("retry", "player_retry")
	_transition("retrying")
	_begin_run()
	if not victory_fixture.is_empty():
		tester_victory_fixture_receipt = victory_fixture
	if not victory_transaction.is_empty():
		_finalize_victory_retry(victory_transaction)

func _enter_title() -> void:
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
	warden.reset_input_latch()
	_resume_state = run_state
	_transition("paused")
	get_tree().paused = true
	shell.set_mode("pause", last_snapshot)
	_emit_snapshot()

func _resume_run() -> void:
	get_tree().paused = false
	warden.reset_input_latch()
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
	hud.visible = false
	shell.set_mode("result", terminal_snapshot)
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

func _spawn_reward_pickup(event: Dictionary) -> RewardPickup:
	var active_pickups := get_tree().get_nodes_in_group(&"reward_pickup")
	if active_pickups.size() >= MAX_ACTIVE_PICKUPS:
		var merge_target := active_pickups.front() as RewardPickup
		if is_instance_valid(merge_target):
			merge_target.merge_reward(event)
			pickup_spawned_total += 1
			return merge_target
	var pickup := REWARD_PICKUP_SCENE.instantiate() as RewardPickup
	world.add_child(pickup)
	pickup.configure(warden, event)
	pickup.collected.connect(_on_reward_pickup_collected)
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
	_emit_snapshot()

func _on_build_changed(_snapshot: Dictionary) -> void:
	_emit_snapshot()

func _on_dash_changed(_phase: String, _invulnerable: bool) -> void:
	_emit_snapshot()

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
	warden.reset_input_latch()
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
	draft_view.close()
	get_tree().paused = false
	_transition("active")
	_emit_snapshot()

func _on_wave_phase_changed(snapshot: Dictionary) -> void:
	if String(snapshot.get("phase","")) == "active":
		var definition: Dictionary = snapshot.get("definition",{})
		spawner.configure_pressure(definition)
		if not spawner.active:
			spawner.begin_encounter()
		if int(snapshot.get("wave",1)) == 5:
			_transition("boss")
			_begin_passive_ordinary_profile(snapshot)
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
	boss.boss_changed.connect(_on_boss_changed)
	boss.defeated.connect(_on_boss_defeated)
	boss.phase_shifted.connect(_on_boss_phase_shifted)
	boss_snapshot = boss.get_snapshot()

func _on_boss_phase_shifted(_phase: int) -> void:
	audio_director.play_semantic("boss_phase")

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
		and _natural_build_history_truthful()
	)
	terminal_snapshot = terminal_snapshot.duplicate(true)

func _teardown_run(route: String, reason: String) -> Dictionary:
	if _teardown_active:
		return teardown_receipt.duplicate(true)
	_teardown_active = true
	_teardown_generation += 1
	get_tree().paused = false
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
		"remaining_attack_presentations":get_tree().get_nodes_in_group("friendly_attack").size(),
		"audio_retirement":transient_retirement.get("audio_retirement",{}), "terminal_snapshot_preserved":not terminal_snapshot.is_empty(),
		"presentation_reset":presentation_reset,
		"post_counts":post_counts,
		"completion_generation":_teardown_generation, "complete":teardown_complete,
	}
	_teardown_active = false
	return teardown_receipt.duplicate(true)

func _retire_transient_ownership(route: String, reason: String, generation: int) -> Dictionary:
	# Both ordinary lifecycle routes and the dense diagnostic reset enter this
	# exact ordering: stop update owners, synchronously invalidate weapon/combat
	# references, retire encounters, then retire generic presentation and audio.
	var runtime_retirement := world.retire_run_ownership(reason, generation)
	spawner.stop_encounter()
	var retired_attack_presentations := _retire_run_group("friendly_attack")
	var retired_pickups := _retire_run_group("reward_pickup")
	var audio_retirement := audio_director.retire_run_ownership(route, generation)
	return {
		"route": route, "reason": reason, "generation": generation,
		"runtime_retirement": runtime_retirement,
		"retired_attack_presentations": retired_attack_presentations,
		"remaining_attack_presentations": get_tree().get_nodes_in_group("friendly_attack").size(),
		"retired_pickups":retired_pickups,
		"remaining_pickups":get_tree().get_nodes_in_group("reward_pickup").size(),
		"audio_retirement": audio_retirement,
		"complete": bool(runtime_retirement.get("complete", false)) and get_tree().get_nodes_in_group("friendly_attack").is_empty() and get_tree().get_nodes_in_group("reward_pickup").is_empty(),
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
	_profile_elapsed = 0.0
	_profile_active = true
	_profile_origin = "diagnostic_prepared"
	_profile_start_counts = _profile_counts()
	_profile_start_lifecycle = _lifecycle_counters()
	var cohort := spawner.begin_validation_profile_cohort(32, int(validation_profile_receipt.get("setup_generation", 0)))
	validation_profile_sample = {
		"status":"sampling", "branch_id":validation_profile_receipt.get("branch_id",""),
		"sample_kind":_profile_origin, "route_kind":run_route_kind,
		"run_serial":run_serial, "setup_generation":validation_profile_receipt.get("setup_generation",0),
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

func _begin_passive_ordinary_profile(wave_snapshot: Dictionary) -> void:
	if run_route_kind != "ordinary" or _profile_active:
		return
	if int(wave_snapshot.get("wave", 0)) != 5 or int(wave_snapshot.get("diagnostic_jump_count", 0)) != 0:
		return
	_profile_samples_ms.clear()
	_profile_elapsed = 0.0
	_profile_active = true
	_profile_origin = "ordinary_final_wave_passive"
	_profile_start_counts = _profile_counts()
	_profile_start_lifecycle = _lifecycle_counters()
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
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
	}
	_emit_snapshot()

func _advance_profile_sample(delta: float) -> void:
	if not _profile_active or get_tree().paused:
		return
	var frame_ms := maxf(0.0,delta*1000.0)
	_profile_samples_ms.append(frame_ms)
	_profile_elapsed += delta
	if _profile_elapsed < _profile_duration:
		return
	_profile_active = false
	var sorted := _profile_samples_ms.duplicate()
	sorted.sort()
	var sample_branch := String(validation_profile_sample.get("branch_id", ""))
	var sample_setup_generation := int(validation_profile_sample.get("setup_generation", _validation_setup_generation))
	var cohort := spawner.end_validation_profile_cohort("sample_complete") if _profile_origin == "diagnostic_prepared" else {}
	validation_profile_sample = {
		"status":"complete", "branch_id":sample_branch,
		"sample_kind":_profile_origin, "route_kind":run_route_kind,
		"passive":_profile_origin == "ordinary_final_wave_passive",
		"diagnostic_mutation":_profile_origin == "diagnostic_prepared",
		"run_serial":run_serial, "setup_generation":sample_setup_generation,
		"sample_count":sorted.size(), "window_seconds":_profile_elapsed,
		"frame_ms":{"p50":_percentile(sorted,0.50),"p95":_percentile(sorted,0.95),"p99":_percentile(sorted,0.99),"worst":sorted.back() if not sorted.is_empty() else 0.0},
		"start_counts":_profile_start_counts.duplicate(true),
		"end_counts":_profile_counts(), "counts":_profile_counts(),
		"start_lifecycle":_profile_start_lifecycle.duplicate(true),
		"end_lifecycle":_lifecycle_counters(),
		"cohort":cohort,
		"requested_enemy_workload":int(cohort.get("requested", _profile_start_counts.get("enemies", 0))),
		"start_enemy_workload":int(cohort.get("start", _profile_start_counts.get("enemies", 0))),
		"minimum_enemy_workload":int(cohort.get("minimum", _profile_start_counts.get("enemies", 0))),
		"end_enemy_workload":int(cohort.get("end_live", _profile_counts().get("enemies", 0))),
		"replenished_enemy_count":int(cohort.get("replenished", 0)),
		"viewport":_profile_viewport_receipt(),
		"renderer":_profile_renderer_receipt(),
		"wave_end":wave_director.get_snapshot().duplicate(true),
		"work_caps":_dense_work_caps(spawner.get_snapshot()),
		"workload_end":_profile_workload_receipt(spawner.get_snapshot()),
	}
	validation_profile_sample["qualification"] = _profile_qualification(validation_profile_sample)
	_record_profile_cycle("advance", validation_profile_sample)
	if _profile_origin == "diagnostic_prepared":
		get_tree().paused = true
	_emit_snapshot()

func _reset_final_profile() -> void:
	if not OS.has_feature("editor"):
		return
	_profile_active = false
	_profile_origin = ""
	_profile_samples_ms.clear()
	_profile_elapsed = 0.0
	spawner.end_validation_profile_cohort("profile_reset")
	get_tree().paused = false
	var source_run_serial := run_serial
	var requested_counts := _profile_counts()
	_validation_setup_generation += 1
	var setup_generation := _validation_setup_generation
	var retirement := _teardown_run("validation_profile_reset", "validation_profile_reset")
	_next_baseline_reason = "validation_profile_reset"
	_begin_run()
	var counts := _profile_counts()
	validation_profile_receipt = {
		"accepted":true, "reset":true, "branch_id":"final_wave_bellkeeper_profile",
		"source_run_serial":source_run_serial, "run_serial":run_serial, "setup_generation":setup_generation,
		"requested_density":requested_counts.get("enemies",-1), "resolved_density":counts.get("enemies",-1),
		"requested_profile":"reset", "resolved_profile":"ordinary_run_ready",
		"requested_counts": requested_counts, "resolved_retirement": retirement,
		"post_reset_counts":counts, "counts":counts,
		"reset_isolation":_counts_are_isolated(counts),
		"route_kind":run_route_kind,
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

func _capture_profile_next_frame_isolation(setup_generation: int, expected_run_serial: int) -> void:
	await get_tree().process_frame
	if setup_generation != _validation_setup_generation or expected_run_serial != run_serial:
		return
	var next_counts := _profile_counts()
	validation_profile_receipt.next_frame_counts = next_counts
	validation_profile_receipt.next_frame_isolation = _counts_are_isolated(next_counts)
	validation_profile_receipt.next_frame_lifecycle = _lifecycle_counters()
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
			current["reset"] = {
				"source_run_serial":entry.get("source_run_serial", -1),
				"next_run_serial":entry.get("run_serial", -1),
				"reset_setup_generation":entry.get("setup_generation", -1),
					"immediate_isolation":entry.get("reset_isolation", false),
					"immediate_lifecycle":(entry.get("lifecycle", {}) as Dictionary).duplicate(true),
			}
		elif phase == "reset_next_frame" and not current.is_empty():
			var reset: Dictionary = current.get("reset", {})
			reset["next_frame_isolation"] = entry.get("next_frame_isolation", false)
			reset["next_frame_counts"] = (entry.get("next_frame_counts", {}) as Dictionary).duplicate(true)
			reset["next_frame_lifecycle"] = (entry.get("next_frame_lifecycle", {}) as Dictionary).duplicate(true)
			current["reset"] = reset
			current["complete"] = true
			completed.append(current.duplicate(true))
			current.clear()
	while completed.size() > 3:
		completed.pop_front()
	var growth := _profile_cycle_growth(completed)
	return {
		"required_cycle_count":3,
		"completed_cycle_count":completed.size(),
		"cycles":completed,
		"three_cycle_ready":completed.size() == 3,
		"growth":growth,
		"three_cycle_no_growth":completed.size() == 3 and bool(growth.get("no_structural_growth", false)),
	}

func _profile_cycle_growth(completed: Array[Dictionary]) -> Dictionary:
	if completed.is_empty():
		return {"ready":false}
	var first_reset: Dictionary = (completed.front().get("reset", {}) as Dictionary).get("next_frame_lifecycle", {})
	var last_reset: Dictionary = (completed.back().get("reset", {}) as Dictionary).get("next_frame_lifecycle", {})
	if first_reset.is_empty() or last_reset.is_empty():
		return {"ready":false}
	var node_growth := int(last_reset.get("scene_tree_nodes", 0)) - int(first_reset.get("scene_tree_nodes", 0))
	var object_growth := int(last_reset.get("object_count", 0)) - int(first_reset.get("object_count", 0))
	var orphan_growth := int(last_reset.get("orphan_nodes", 0)) - int(first_reset.get("orphan_nodes", 0))
	var memory_growth := int(last_reset.get("static_memory_bytes", 0)) - int(first_reset.get("static_memory_bytes", 0))
	var input_growth := int(last_reset.get("input_action_count", 0)) - int(first_reset.get("input_action_count", 0))
	var signal_growth := int(last_reset.get("owned_signal_bindings", 0)) - int(first_reset.get("owned_signal_bindings", 0))
	return {
		"ready":completed.size() == 3,
		"node_growth":node_growth,
		"object_growth":object_growth,
		"orphan_growth":orphan_growth,
		"static_memory_growth_bytes":memory_growth,
		"input_action_growth":input_growth,
		"owned_signal_binding_growth":signal_growth,
		"no_structural_growth":node_growth <= 0 and orphan_growth <= 0 and input_growth == 0 and signal_growth == 0,
		"memory_observational_only":true,
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
	var encounter := spawner.get_snapshot()
	var wisps: WanderingWispsRuntime = $World/Warden/Weapons/WanderingWispsRuntime
	var lights := 0
	for node in world.find_children("*","Light3D",true,false):
		if node is Light3D and node.is_visible_in_tree():
			lights += 1
	var audio_voices := 0
	audio_voices = audio_director.active_effect_voice_count()
	return {
		"enemies":int(encounter.get("live",0)),
		"pooled_enemies":int(encounter.get("pooled",0)),
		"bosses":1 if is_instance_valid(boss) else 0,
		"projectiles":get_tree().get_nodes_in_group("friendly_attack").size(),
		"pickups":get_tree().get_nodes_in_group("reward_pickup").size(),
		"pickup_production_ready":spawner.reward_dropped.is_connected(_on_reward_dropped),
		"effects":get_tree().get_nodes_in_group("impact_effect").size(),
		"lights":lights, "audio_voices":audio_voices,
		"telegraph_active":int((encounter.get("telegraph_admission",{}) as Dictionary).get("active",0)),
		"neighbor_candidate_visits":int((encounter.get("neighbor_registry",{}) as Dictionary).get("candidate_visits",0)),
		"registered_neighbors":int((encounter.get("neighbor_registry",{}) as Dictionary).get("registered_count",0)),
		"wisp_handles":wisps.active_wisp_count,
		"wisp_interval_targets":wisps._target_next_hit_time.size(),
		"active_attack_ledgers":world.attack_runtime._hit_ledgers.size(),
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
	var end_workload := int(sample.get("end_enemy_workload", -1))
	# Combat deaths are real work and can transiently lower the live cohort before
	# the bounded pool replenishes it. The PRD qualifies 25-40 simultaneous
	# enemies; require the authored 32 at both boundaries and never disguise an
	# ordinary combat death as a profile failure.
	if requested_workload != 32 or start_workload != 32 or end_workload != 32:
		reasons.append("enemy_cohort_boundary_not_32")
	if minimum_workload < 25 or minimum_workload > 40:
		reasons.append("enemy_density_outside_25_40")
	if float(frame_ms.get("p95", INF)) > 16.67:
		reasons.append("p95_above_16_67ms")
	return {"qualified":reasons.is_empty(), "reasons":reasons, "requires_hardware":true, "p95_limit_ms":16.67,
		"required_density_range":{"minimum":25,"maximum":40,"boundary_target":32}}

func _validation_controls_receipt() -> Dictionary:
	var actions := [&"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10", &"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile", &"validation_reset_final_profile"]
	var controls: Array[Dictionary] = []
	for action in actions:
		controls.append({"action":String(action), "registered":InputMap.has_action(action), "physical_binding_count":InputMap.action_get_events(action).size() if InputMap.has_action(action) else 0})
	for action in [&"tester_victory_prepare", &"tester_victory_advance", &"tester_final_profile_prepare", &"tester_final_profile_advance", &"tester_final_profile_reset"]:
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
	return {
		"role_composition":(encounter.get("roles", {}) as Dictionary).duplicate(true),
		"active_and_pooled":{"active":encounter.get("live", 0),"pooled":encounter.get("pooled", 0)},
		"attacks":{"authorized":attack_state.get("authorized_count", 0),"hits":attack_state.get("hit_count", 0),"active_ledgers":attack_state.get("active_ledgers", 0)},
		"projectiles":get_tree().get_nodes_in_group("friendly_attack").size(),
		"pickups":get_tree().get_nodes_in_group("reward_pickup").size(),
		"effects":get_tree().get_nodes_in_group("impact_effect").size(),
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
	return {
		"scene_tree_nodes":get_tree().get_node_count(),
		"object_count":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"input_action_count":InputMap.get_actions().size(),
		"owned_signal_bindings":owned_signal_bindings,
		"audio_voices":audio_director.active_effect_voice_count(),
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
	}

func _natural_build_history_truthful() -> bool:
	for choice in selected_upgrades:
		if not bool(choice.get("natural_choice", false)) or not bool(choice.get("truthful_transaction", false)):
			return false
	return true

func _record_retry_baseline(reason: String) -> void:
	_retry_baseline_generation += 1
	var receipt := {
		"run_serial":run_serial, "baseline_generation":_retry_baseline_generation,
		"source":reason,
		"tree_paused":get_tree().paused, "run_state":run_state,
		"counts":_profile_counts(),
		"warden_animation":warden.animation_binding.get_snapshot() if warden.animation_binding else {},
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
	wave_director.prepare_test_wave(3)
	_record_validation_density(target_live)

func _record_validation_density(target_live: int) -> void:
	var before := spawner.get_snapshot()
	var preparation := spawner.prepare_validation_density(target_live)
	_validation_setup_generation += 1
	var after := spawner.get_snapshot()
	validation_density_receipt = {
		"accepted":bool(preparation.get("accepted", false)),
		"requested_density":target_live,
		"resolved_density":int(after.get("live", 0)),
		"run_serial":run_serial,
		"setup_generation":_validation_setup_generation,
		"active":int(after.get("live", 0)), "pooled":int(after.get("pooled", 0)),
		"before_active":int(before.get("live", 0)),
		"light_budget":(after.get("ordinary_light_budget", {}) as Dictionary).duplicate(true),
		"neighbor_registry":(after.get("neighbor_registry", {}) as Dictionary).duplicate(true),
		"telegraph_admission":(after.get("telegraph_admission", {}) as Dictionary).duplicate(true),
		"preparation":preparation.duplicate(true),
		"attacks_advanced_by_preparation":false,
		"terminal_state_advanced":false,
	}
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
	run_route_kind = "diagnostic_prepared"
	inventory.prepare_legal_build("representative")
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
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
	tester_victory_fixture_receipt = {
		"branch_id":"tester_victory_transaction",
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
		"reset_isolation":_counts_are_isolated(_profile_counts()),
		"counts":_profile_counts(),
		"lifecycle":_lifecycle_counters(),
	}
	_emit_snapshot()

func _advance_tester_victory() -> void:
	if not OS.has_feature("editor") or String(tester_victory_fixture_receipt.get("branch_id", "")) != "tester_victory_transaction":
		return
	if int(tester_victory_fixture_receipt.get("setup_generation", -1)) != _validation_setup_generation or int(tester_victory_fixture_receipt.get("run_serial", -1)) != run_serial:
		return
	if not is_instance_valid(boss) or result_committed or _victory_transaction_active:
		return
	get_tree().paused = false
	tester_victory_fixture_receipt["advance_requested"] = true
	tester_victory_fixture_receipt["advance_frame"] = Engine.get_process_frames()
	var resolution := boss.health.apply_damage({
		"attack_id":"tester.victory.advance.g%04d" % _validation_setup_generation,
		"damage":boss.health.current_health,
		"damage_channel":"tester_terminal_advance",
	})
	tester_victory_fixture_receipt["advance_resolved"] = bool(resolution.get("accepted", false)) and not boss.health.is_alive()
	tester_victory_fixture_receipt["resolved_state"] = run_state
	tester_victory_fixture_receipt["boss_defeat_committed"] = bool(boss_snapshot.get("defeat_committed", false))
	tester_victory_fixture_receipt["result_committed_after_advance"] = result_committed
	tester_victory_fixture_receipt["terminal_commit_count_after_advance"] = terminal_commit_count
	tester_victory_fixture_receipt["presentation_transaction"] = ordinary_victory_receipt.duplicate(true)
	tester_victory_fixture_receipt["reset_isolation"] = false
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
	return {
		"authoritative_teardown":teardown_receipt,
		"run_state": run_state, "run_serial": run_serial, "run_elapsed": run_elapsed,
		"experience": experience, "experience_threshold": experience_threshold, "level": level,
		"defeated_enemies": defeated_enemies, "damage_taken": damage_taken,
		"damage_dealt":damage_dealt,"outcome":outcome,"selected_upgrade_count":selected_upgrades.size(),
		"wave":{"wave":wave_state.get("wave",0),"wave_count":wave_state.get("wave_count",5),"phase":wave_state.get("phase","idle"),"title":wave_state.get("title","")},
		"boss":{"active":boss_snapshot.get("active",false),"health":boss_snapshot.get("health",0.0),"health_maximum":boss_snapshot.get("health_maximum",0.0),"phase":boss_snapshot.get("phase",0)},"quit_requested":quit_requested,
		"result_committed": result_committed, "terminal_snapshot_digest": _terminal_snapshot_digest(), "state_history": state_history,
		"terminal_commit_count":terminal_commit_count, "run_route_kind":run_route_kind,
		"victory_transaction":{"active":_victory_transaction_active,"source_run_serial":_victory_source_run_serial,"hold_required_seconds":VICTORY_PRESENTATION_HOLD_SECONDS,"hold_elapsed_seconds":_victory_hold_elapsed,"hold_remaining_seconds":_victory_hold_remaining},
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
		"validation_profile_cycle_comparison":_profile_cycle_comparison(),
		"validation_controls":_validation_controls_receipt(),
		"validation_retry_baselines":validation_retry_baselines,
		"ordinary_victory_receipt":ordinary_victory_receipt,
		"ordinary_victory_transactions":ordinary_victory_transactions,
		"tester_victory_fixture":tester_victory_fixture_receipt,
		"reward_pickups":{"spawned_total":pickup_spawned_total,"collected_total":pickup_collected_total,"live":get_tree().get_nodes_in_group("reward_pickup").size()},
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
