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
const BELLKEEPER_SCENE := preload("res://scenes/enemies/bellkeeper.tscn")

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
var boss: BellkeeperActor
var boss_snapshot: Dictionary = {}
var quit_requested := false
var _resume_state := "active"
var result_committed := false
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
var _validation_setup_generation := 0
var validation_density_receipt: Dictionary = {}
var validation_profile_receipt: Dictionary = {}
var validation_profile_sample: Dictionary = {}
var validation_retry_baselines: Array[Dictionary] = []
var _profile_samples_ms: Array[float] = []
var _profile_active := false
var _profile_elapsed := 0.0
var _profile_duration := 4.0
var _next_baseline_reason := "fresh_start"
var _retry_baseline_generation := 0

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
		for action in [&"validation_prepare_wave4", &"validation_prepare_boss", &"validation_prepare_draft", &"validation_prepare_result_failure", &"validation_prepare_result_victory", &"validation_prepare_density_3", &"validation_prepare_density_5", &"validation_prepare_density_10", &"validation_prepare_density_18", &"validation_prepare_density_32", &"validation_reset_density", &"validation_prepare_final_profile", &"validation_advance_final_profile", &"validation_reset_final_profile"]:
			if not InputMap.has_action(action):
				InputMap.add_action(action)
	_enter_title()

func _process(delta: float) -> void:
	_advance_terminal_handoff()
	_advance_profile_sample(delta)
	if run_state in ["active","boss"] and not get_tree().paused:
		run_elapsed += delta
	_snapshot_clock -= delta
	if _snapshot_clock <= 0.0:
		_snapshot_clock = 0.1
		_emit_snapshot()

func _unhandled_input(event: InputEvent) -> void:
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
		_prepare_validation_result("victory")
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
	_transition("initializing")
	run_serial += 1
	run_elapsed = 0.0
	experience = 0
	experience_threshold = 5
	level = 1
	defeated_enemies = 0
	damage_taken = 0
	damage_dealt = 0
	outcome = ""
	selected_upgrades.clear()
	boss_snapshot.clear()
	result_committed = false
	terminal_snapshot.clear()
	draft_controller.reset()
	audio_director.reset_for_run()
	world.reset_session()
	_health_accounting_suspended = true
	health.maximum_health = 100.0
	health.reset_warden_health()
	warden.cooldown_duration = 0.72
	_last_health = health.current_health
	_health_accounting_suspended = false
	inventory.reset_starting_build()
	world.set_session_active(true)
	title_menu.hide()
	shell.set_mode("hidden")
	spawner.reset_encounter()
	wave_director.begin()
	_transition("active")
	_record_retry_baseline(_next_baseline_reason)
	_next_baseline_reason = "ordinary_run"
	_emit_snapshot()

func retry_run() -> void:
	_next_baseline_reason = "retry"
	_teardown_run("retry", "player_retry")
	_transition("retrying")
	_begin_run()

func _enter_title() -> void:
	_terminal_handoff_active = false
	_teardown_run("title", "return_to_title")
	boss_snapshot.clear()
	hud.clear_snapshot()
	_transition("title")
	shell.set_mode("hidden")
	title_menu.show()
	title_menu.new_game_button.grab_focus.call_deferred()
	_emit_snapshot()

func _begin_terminal_title_handoff() -> void:
	if _terminal_handoff_active:
		return
	_terminal_handoff_generation += 1
	_terminal_handoff_active = true
	_terminal_handoff_release_frames = 0
	terminal_handoff_receipt = {
		"generation":_terminal_handoff_generation,
		"source":"result", "action":"title",
		"shell_action_generation":shell.action_generation,
		"stage":"consuming_initiating_confirm",
		"release_observed":false, "title_exposed":false,
		"teardown_complete":false,
	}
	_teardown_run("title", "return_to_title")
	boss_snapshot.clear()
	hud.clear_snapshot()
	_transition("title")
	shell.set_mode("hidden")
	title_menu.hide()
	terminal_handoff_receipt.teardown_complete = bool(teardown_receipt.get("complete", false))
	terminal_handoff_receipt.teardown_generation = int(teardown_receipt.get("completion_generation", 0))
	_emit_snapshot()

func _advance_terminal_handoff() -> void:
	if not _terminal_handoff_active:
		return
	if Input.is_action_pressed(&"ui_accept"):
		_terminal_handoff_release_frames = 0
		return
	_terminal_handoff_release_frames += 1
	terminal_handoff_receipt.release_observed = true
	terminal_handoff_receipt.release_frames = _terminal_handoff_release_frames
	if _terminal_handoff_release_frames < 2:
		return
	_terminal_handoff_active = false
	title_menu.show()
	title_menu.new_game_button.grab_focus.call_deferred()
	terminal_handoff_receipt.stage = "complete"
	terminal_handoff_receipt.title_exposed = true
	terminal_handoff_receipt.focus_target = "Play"
	terminal_handoff_receipt.quit_requested = quit_requested
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
	_commit_terminal_snapshot("failure")
	if warden.animation_binding: warden.animation_binding.trigger("death",999.0)
	_teardown_run("result", "failure")
	get_tree().paused = true
	_transition("failure")
	_emit_snapshot()
	call_deferred("_present_result", event)

func _present_result(_event: Dictionary) -> void:
	_transition("result")
	hud.visible = false
	shell.set_mode("result", terminal_snapshot)
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

func _on_reward_dropped(_event: Dictionary) -> void:
	experience += 1
	if experience >= experience_threshold:
		experience -= experience_threshold
		level += 1
		experience_threshold = 5 + (level - 1) * 2
		_open_upgrade_draft()
	_emit_snapshot()

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
				_enter_title()
		&"settings": _open_settings_page()
		&"credits": _open_credits_page()
		&"back": _return_from_shell_page()
		&"quit":
			quit_requested = true
			if not OS.has_feature("editor"):
				get_tree().quit()

func _on_title_page_requested(page: String) -> void:
	title_menu.hide()
	shell.set_mode(page)

func _open_settings_page() -> void:
	if run_state == "paused":
		_transition("settings")
		get_tree().paused = true
		shell.set_mode("settings", last_snapshot)
	elif run_state == "title":
		title_menu.hide()
		shell.set_mode("settings")
	_emit_snapshot()

func _open_credits_page() -> void:
	if run_state == "title":
		title_menu.hide()
		shell.set_mode("credits")
	_emit_snapshot()

func _return_from_shell_page() -> void:
	if shell.return_mode == "pause" and run_state == "settings":
		get_tree().paused = true
		_transition("paused")
		shell.set_mode("pause",last_snapshot)
		_emit_snapshot()
	else:
		_enter_title()

func _on_title_exit_requested() -> void:
	quit_requested = true
	if not OS.has_feature("editor"):
		get_tree().quit()

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
	_emit_snapshot()

func _spawn_bellkeeper() -> void:
	if is_instance_valid(boss) or result_committed:
		return
	boss = BELLKEEPER_SCENE.instantiate() as BellkeeperActor
	world.get_node("BossAnchor").add_child(boss)
	boss.position = Vector3.ZERO
	boss.configure(warden)
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
	if result_committed:
		return
	result_committed = true
	outcome = "victory"
	_commit_terminal_snapshot("victory")
	_teardown_run("result", "victory")
	get_tree().paused = true
	_transition("victory")
	if warden.animation_binding: warden.animation_binding.trigger("victory",999.0)
	_emit_snapshot()
	call_deferred("_present_result",{})

func _on_player_hit_resolved(event: Dictionary) -> void:
	damage_dealt += int(round(float(event.get("damage",0.0))))

func _commit_terminal_snapshot(terminal_outcome: String) -> void:
	if not terminal_snapshot.is_empty():
		return
	terminal_snapshot = RunSnapshot.make(self,world,warden,health,spawner,inventory)
	terminal_snapshot.outcome = terminal_outcome
	terminal_snapshot.state = "result"
	terminal_snapshot["committed"] = true
	terminal_snapshot["commit_run_serial"] = run_serial
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
	spawner.stop_encounter()
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
	world.set_session_active(false)
	world.reset_session()
	var retired_attack_presentations := _retire_run_group("friendly_attack")
	var audio_retirement := audio_director.retire_run_ownership(route, _teardown_generation)
	var encounter := spawner.get_snapshot()
	teardown_receipt = {
		"run_serial":run_serial, "route":route, "reason":reason,
		"boss_retirement":boss_retirement, "boss_reference_cleared":boss == null,
		"active_enemy_group_count":get_tree().get_nodes_in_group("active_enemies").size(),
		"spawner_live":encounter.get("live", -1), "spawner_pooled":encounter.get("pooled", -1),
		"spawner_registered":(encounter.get("neighbor_registry", {}) as Dictionary).get("registered_count", -1),
		"world_active":world.session_active, "tree_paused":get_tree().paused,
		"retired_attack_presentations":retired_attack_presentations,
		"remaining_attack_presentations":get_tree().get_nodes_in_group("friendly_attack").size(),
		"audio_retirement":audio_retirement, "terminal_snapshot_preserved":not terminal_snapshot.is_empty(),
		"completion_generation":_teardown_generation, "complete":true,
	}
	_teardown_active = false
	return teardown_receipt.duplicate(true)

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
	_profile_samples_ms.clear()
	_profile_elapsed = 0.0
	get_tree().paused = false
	health.maximum_health = 5000.0
	health.reset_warden_health()
	_last_health = health.current_health
	experience = 0
	experience_threshold = 9999
	var build_receipt := inventory.prepare_legal_build("representative")
	wave_director.prepare_test_wave(3)
	var attack_count_before := world.attack_runtime.authorized_count
	var preparation := spawner.prepare_validation_density(32)
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
		"telegraph_admission":(encounter.get("telegraph_admission",{}) as Dictionary).duplicate(true),
		"neighbor_registry":(encounter.get("neighbor_registry",{}) as Dictionary).duplicate(true),
		"ordinary_light_budget":(encounter.get("ordinary_light_budget",{}) as Dictionary).duplicate(true),
		"pool_counts":{"active":encounter.get("live",0),"pooled":encounter.get("pooled",0)},
		"requested_profile":"representative_final_wave_and_bellkeeper",
		"resolved_profile":"prepared_paused",
		"preparation_paused":get_tree().paused,
		"attacks_advanced_by_preparation":world.attack_runtime.authorized_count != attack_count_before,
		"terminal_state_advanced":result_committed,
		"advance_action_required":true,
		"reset_isolation_pending":true,
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_emit_snapshot()

func _advance_final_profile() -> void:
	if not OS.has_feature("editor") or not bool(validation_profile_receipt.get("accepted",false)) or _profile_active:
		return
	_profile_samples_ms.clear()
	_profile_elapsed = 0.0
	_profile_active = true
	validation_profile_sample = {
		"status":"sampling", "branch_id":validation_profile_receipt.get("branch_id",""),
		"run_serial":run_serial, "setup_generation":validation_profile_receipt.get("setup_generation",0),
		"window_seconds":_profile_duration,
	}
	get_tree().paused = false

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
	validation_profile_sample = {
		"status":"complete", "branch_id":validation_profile_receipt.get("branch_id",""),
		"run_serial":run_serial, "setup_generation":validation_profile_receipt.get("setup_generation",0),
		"sample_count":sorted.size(), "window_seconds":_profile_elapsed,
		"frame_ms":{"p50":_percentile(sorted,0.50),"p95":_percentile(sorted,0.95),"p99":_percentile(sorted,0.99),"worst":sorted.back() if not sorted.is_empty() else 0.0},
		"counts":_profile_counts(),
	}
	get_tree().paused = true
	_emit_snapshot()

func _reset_final_profile() -> void:
	if not OS.has_feature("editor"):
		return
	_profile_active = false
	_profile_samples_ms.clear()
	_profile_elapsed = 0.0
	get_tree().paused = false
	spawner.reset_encounter()
	_retire_run_group("friendly_attack")
	audio_director.reset_for_run()
	if is_instance_valid(boss):
		boss.retire_run_actor("validation_profile_reset",_validation_setup_generation+1)
		boss.queue_free()
	boss = null
	boss_snapshot.clear()
	_validation_setup_generation += 1
	var counts := _profile_counts()
	validation_profile_receipt = {
		"accepted":true, "reset":true, "branch_id":"final_wave_bellkeeper_profile",
		"run_serial":run_serial, "setup_generation":_validation_setup_generation,
		"requested_density":0, "resolved_density":counts.get("enemies",-1),
		"requested_profile":"reset", "resolved_profile":"ordinary_run_ready",
		"counts":counts,
		"reset_isolation":int(counts.get("enemies",-1)) == 0 and int(counts.get("projectiles",-1)) == 0 and not is_instance_valid(boss),
	}
	validation_density_receipt = validation_profile_receipt.duplicate(true)
	_transition("active")
	_emit_snapshot()

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
	var lights := 0
	for node in world.find_children("*","Light3D",true,false):
		if node is Light3D and node.is_visible_in_tree():
			lights += 1
	var audio_voices := 0
	for voice in audio_director.voices:
		if voice.playing:
			audio_voices += 1
	return {
		"enemies":int(encounter.get("live",0)),
		"pooled_enemies":int(encounter.get("pooled",0)),
		"bosses":1 if is_instance_valid(boss) else 0,
		"projectiles":get_tree().get_nodes_in_group("friendly_attack").size(),
		"pickups":get_tree().get_nodes_in_group("reward_pickup").size(),
		"effects":get_tree().get_nodes_in_group("impact_effect").size(),
		"lights":lights, "audio_voices":audio_voices,
		"telegraph_active":int((encounter.get("telegraph_admission",{}) as Dictionary).get("active",0)),
		"neighbor_candidate_visits":int((encounter.get("neighbor_registry",{}) as Dictionary).get("candidate_visits",0)),
		"active_attack_ledgers":world.attack_runtime._hit_ledgers.size(),
	}

func _record_retry_baseline(reason: String) -> void:
	_retry_baseline_generation += 1
	var receipt := {
		"run_serial":run_serial, "baseline_generation":_retry_baseline_generation,
		"source":reason,
		"tree_paused":get_tree().paused, "run_state":run_state,
		"counts":_profile_counts(),
		"world_active":world.session_active,
		"teardown_generation":teardown_receipt.get("completion_generation",0),
	}
	validation_retry_baselines.append(receipt)
	if validation_retry_baselines.size() > 3:
		validation_retry_baselines.pop_front()

func _prepare_validation_wave(index: int) -> void:
	if not OS.has_feature("editor") or run_state not in ["active", "boss"]:
		return
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

func _prepare_validation_result(validation_outcome: String) -> void:
	if not OS.has_feature("editor") or run_state not in ["active","boss"]:
		return
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
		_on_boss_defeated({"validation":true})
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
		"validation_density":validation_density_receipt,
		"validation_profile":validation_profile_receipt,
		"validation_profile_sample":validation_profile_sample,
		"validation_retry_baselines":validation_retry_baselines,
		"shell_focus": String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none",
	}

func _terminal_snapshot_digest() -> Dictionary:
	if terminal_snapshot.is_empty(): return {}
	return {"committed":terminal_snapshot.get("committed",false),"commit_run_serial":terminal_snapshot.get("commit_run_serial",0),
		"outcome":terminal_snapshot.get("outcome",""),"elapsed":terminal_snapshot.get("elapsed",0.0),"wave":terminal_snapshot.get("wave",0),
		"level":terminal_snapshot.get("level",0),"defeated":terminal_snapshot.get("defeated",0),"damage_dealt":terminal_snapshot.get("damage_dealt",0),
		"damage_taken":terminal_snapshot.get("damage_taken",0),"weapon_ranks":_terminal_weapon_ranks(),"selected_upgrades":terminal_snapshot.get("selected_upgrades",[])}

func _terminal_weapon_ranks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon in (terminal_snapshot.get("weapons",{}) as Dictionary).get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			result.append({"weapon_id":weapon.get("weapon_id",""),"rank":weapon.get("rank",0)})
	return result
