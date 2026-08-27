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
		for action in [&"validation_prepare_wave4", &"validation_prepare_boss", &"validation_prepare_result_failure", &"validation_prepare_result_victory"]:
			if not InputMap.has_action(action):
				InputMap.add_action(action)
	_enter_title()

func _process(delta: float) -> void:
	if run_state in ["active","boss"] and not get_tree().paused:
		run_elapsed += delta
	_snapshot_clock -= delta
	if _snapshot_clock <= 0.0:
		_snapshot_clock = 0.1
		_emit_snapshot()

func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_wave4"):
		_prepare_validation_wave(3)
		get_viewport().set_input_as_handled()
		return
	if OS.has_feature("editor") and event.is_action_pressed(&"validation_prepare_boss"):
		_prepare_validation_wave(4)
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
	if is_instance_valid(boss): boss.queue_free()
	boss = null
	result_committed = false
	terminal_snapshot.clear()
	draft_controller.reset()
	audio_director.reset_for_run()
	world.reset_session()
	health.maximum_health = 100.0
	health.reset_warden_health()
	warden.cooldown_duration = 0.72
	_last_health = health.current_health
	inventory.reset_starting_build()
	world.set_session_active(true)
	title_menu.hide()
	shell.set_mode("hidden")
	spawner.reset_encounter()
	wave_director.begin()
	_transition("active")
	_emit_snapshot()

func retry_run() -> void:
	_transition("retrying")
	get_tree().paused = false
	spawner.stop_encounter()
	wave_director.reset()
	draft_controller.reset()
	draft_view.close()
	if is_instance_valid(boss): boss.queue_free()
	boss = null
	start_run()

func _enter_title() -> void:
	get_tree().paused = false
	spawner.stop_encounter()
	wave_director.reset()
	if is_instance_valid(boss):
		boss.queue_free()
	boss = null
	boss_snapshot.clear()
	world.reset_session()
	world.set_session_active(false)
	hud.clear_snapshot()
	_transition("title")
	shell.set_mode("hidden")
	title_menu.show()
	title_menu.new_game_button.grab_focus.call_deferred()
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
	spawner.stop_encounter()
	wave_director.terminate("failure")
	world.set_session_active(false)
	if is_instance_valid(boss):
		boss.terminate("failure")
	if warden.animation_binding: warden.animation_binding.trigger("death",999.0)
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
		&"title": _enter_title()
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
	draft_controller.open_draft()

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
	boss.phase_shifted.connect(func(_phase: int) -> void: audio_director.play_semantic("boss_phase"))
	boss_snapshot = boss.get_snapshot()

func _on_boss_changed(snapshot: Dictionary) -> void:
	boss_snapshot = snapshot.duplicate(true)
	_emit_snapshot()

func _on_boss_defeated(_event: Dictionary) -> void:
	if result_committed:
		return
	result_committed = true
	outcome = "victory"
	_commit_terminal_snapshot("victory")
	spawner.stop_encounter()
	wave_director.terminate("victory")
	world.set_session_active(false)
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

func _transition(next_state: String) -> void:
	if run_state == next_state:
		return
	var previous := run_state
	run_state = next_state
	state_history.append(next_state)
	state_changed.emit(previous, next_state)

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
		spawner.prepare_validation_density(32)

func _prepare_validation_result(validation_outcome: String) -> void:
	if not OS.has_feature("editor") or run_state not in ["active","boss"]:
		return
	inventory.prepare_legal_build("representative")
	selected_upgrades = [
		{"id":"lantern_focus","title":"Focused Flame","rank_label":"R2","concrete_change":"+25% DAMAGE"},
		{"id":"dash_cooldown","title":"Moonstep","rank_label":"R1","concrete_change":"15% FASTER DASH"},
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
		"run_state": run_state, "run_serial": run_serial, "run_elapsed": run_elapsed,
		"experience": experience, "experience_threshold": experience_threshold, "level": level,
		"defeated_enemies": defeated_enemies, "damage_taken": damage_taken,
		"damage_dealt":damage_dealt,"outcome":outcome,"selected_upgrade_count":selected_upgrades.size(),
		"wave":{"wave":wave_state.get("wave",0),"wave_count":wave_state.get("wave_count",5),"phase":wave_state.get("phase","idle"),"title":wave_state.get("title","")},
		"boss":{"active":boss_snapshot.get("active",false),"health":boss_snapshot.get("health",0.0),"health_maximum":boss_snapshot.get("health_maximum",0.0),"phase":boss_snapshot.get("phase",0)},"quit_requested":quit_requested,
		"result_committed": result_committed, "terminal_snapshot_digest": _terminal_snapshot_digest(), "state_history": state_history,
		"tree_paused": get_tree().paused, "shell_mode": shell.mode,
		"shell_return_mode": shell.return_mode, "shell_action_latched": shell.action_latched,
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
