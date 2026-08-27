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
	_enter_title()

func _process(delta: float) -> void:
	if run_state in ["active","boss"] and not get_tree().paused:
		run_elapsed += delta
	_snapshot_clock -= delta
	if _snapshot_clock <= 0.0:
		_snapshot_clock = 0.1
		_emit_snapshot()

func _unhandled_input(event: InputEvent) -> void:
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
	spawner.configure_pressure(6,1.75)
	spawner.begin_encounter()
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
	spawner.stop_encounter()
	wave_director.terminate("failure")
	outcome = "failure"
	if warden.animation_binding: warden.animation_binding.trigger("death",999.0)
	get_tree().paused = true
	_transition("failure")
	_emit_snapshot()
	call_deferred("_present_result", event)

func _present_result(_event: Dictionary) -> void:
	_transition("result")
	shell.set_mode("result", last_snapshot)
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
		&"quit":
			quit_requested = true
			if not OS.has_feature("editor"):
				get_tree().quit()

func _on_title_page_requested(page: String) -> void:
	title_menu.hide()
	shell.set_mode(page)

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
		spawner.configure_pressure(int(definition.get("cap",10)),float(definition.get("cadence",1.45)))
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
	boss.phase_shifted.connect(func(_phase: int) -> void: audio_director.play_semantic("boss_phase",preload("res://assets/audio_library/SFX/621155__ktfreesound__reload-escopeta-m7.wav"),-5.0))
	boss_snapshot = boss.get_snapshot()

func _on_boss_changed(snapshot: Dictionary) -> void:
	boss_snapshot = snapshot.duplicate(true)
	_emit_snapshot()

func _on_boss_defeated(_event: Dictionary) -> void:
	if result_committed:
		return
	result_committed = true
	outcome = "victory"
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

func _transition(next_state: String) -> void:
	if run_state == next_state:
		return
	var previous := run_state
	run_state = next_state
	state_history.append(next_state)
	state_changed.emit(previous, next_state)

func _emit_snapshot() -> void:
	if not is_node_ready():
		return
	last_snapshot = RunSnapshot.make(self, world, warden, health, spawner, inventory)
	snapshot_changed.emit(last_snapshot)
	if run_state in ["active", "boss", "paused", "draft"]:
		hud.bind_snapshot(last_snapshot)

func _mcp_state() -> Dictionary:
	return {
		"run_state": run_state, "run_serial": run_serial, "run_elapsed": run_elapsed,
		"experience": experience, "experience_threshold": experience_threshold, "level": level,
		"defeated_enemies": defeated_enemies, "damage_taken": damage_taken,
		"damage_dealt":damage_dealt,"outcome":outcome,"selected_upgrades":selected_upgrades,
		"wave":wave_director.get_snapshot(),"boss":boss_snapshot,"quit_requested":quit_requested,
		"result_committed": result_committed, "state_history": state_history,
		"tree_paused": get_tree().paused, "snapshot": last_snapshot,
	}
