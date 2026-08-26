class_name SurvivalFoundation
extends Node3D

@export var run_state := "active"
@export var pause_state := "running"
@export var combat_state := "seeking"

@onready var warden: WardenController = $Warden
@onready var inventory: WeaponInventory = $Warden/Weapons/WeaponInventory
@onready var attack_runtime: AttackRuntime = $Warden/Weapons/AttackRuntime
@onready var lantern_runtime: WardenLanternRuntime = $Warden/Weapons/WardenLanternRuntime
@onready var pause_overlay: PauseOverlay = $Interface/PauseOverlay
@onready var dash_label: Label = $Interface/HUD/DashCluster/DashLabel
@onready var dash_meter: ProgressBar = $Interface/HUD/DashCluster/DashMeter
@onready var dash_icon: Control = $Interface/HUD/DashCluster/DashIcon
@onready var combat_label: Label = $Interface/HUD/CombatCluster/CombatLabel
@onready var weapons_label: Label = $Interface/HUD/CombatCluster/WeaponsLabel

var last_attack_event: Dictionary = {}
var last_hit_event: Dictionary = {}
var last_drop_event: Dictionary = {}
var validation_build_profile := "starting"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Runtime-only Tester controls: registered without physical bindings and
	# intentionally absent from project.godot/release controls.
	if not InputMap.has_action(&"validation_prepare_build"):
		InputMap.add_action(&"validation_prepare_build")
	if not InputMap.has_action(&"validation_reset_build"):
		InputMap.add_action(&"validation_reset_build")
	if not InputMap.has_action(&"validation_prepare_wisps"):
		InputMap.add_action(&"validation_prepare_wisps")
	warden.dash_phase_changed.connect(_on_dash_phase_changed)
	warden.dash_readiness_changed.connect(_on_dash_readiness_changed)
	attack_runtime.attack_authorized.connect(_on_attack_authorized)
	attack_runtime.hit_resolved.connect(_on_hit_resolved)
	inventory.build_changed.connect(_on_build_changed)
	for target in get_tree().get_nodes_in_group("combat_targets"):
		var health := target.get_node_or_null("HealthComponent")
		var drops := target.get_node_or_null("DropTransaction")
		if health:
			health.died.connect(_on_target_died)
		if drops:
			drops.drop_committed.connect(_on_drop_committed)
	_on_dash_phase_changed("ready", false)
	_on_build_changed(inventory.get_snapshot())
	get_tree().paused = false

func _exit_tree() -> void:
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"validation_prepare_build"):
		prepare_weapon_validation("representative")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"validation_prepare_wisps"):
		prepare_weapon_validation("wisps_only")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"validation_reset_build"):
		reset_weapon_validation()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and not event.is_echo():
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if warden.dash_phase == "cooldown":
		dash_meter.value = 1.0 - clampf(warden.dash_cooldown_remaining / warden.cooldown_duration, 0.0, 1.0)
	combat_state = lantern_runtime.attack_phase
	combat_label.text = _combat_copy()

func prepare_weapon_validation(profile: String = "representative") -> Dictionary:
	validation_build_profile = profile
	return inventory.prepare_legal_build(profile)

func reset_weapon_validation() -> void:
	validation_build_profile = "starting"
	inventory.reset_starting_build()

func _toggle_pause() -> void:
	var should_pause := not get_tree().paused
	warden.reset_input_latch()
	if should_pause:
		pause_state = "paused"
		run_state = "ui_paused"
		pause_overlay.present(warden.get_movement_snapshot())
		get_tree().paused = true
	else:
		get_tree().paused = false
		pause_overlay.dismiss()
		warden.reset_input_latch()
		pause_state = "running"
		run_state = "active"

func _on_attack_authorized(event: Dictionary) -> void:
	last_attack_event = event.duplicate(true)

func _on_hit_resolved(event: Dictionary) -> void:
	last_hit_event = event.duplicate(true)

func _on_target_died(event: Dictionary) -> void:
	last_hit_event = event.duplicate(true)

func _on_drop_committed(event: Dictionary) -> void:
	last_drop_event = event.duplicate(true)

func _on_build_changed(_snapshot: Dictionary) -> void:
	var lines: Array[String] = []
	for weapon in inventory.get_snapshot().weapons:
		if weapon.equipped:
			lines.append("%s  ·  RANK %d" % [String(weapon.stats.display_name).to_upper(), int(weapon.rank)])
	weapons_label.text = "\n".join(lines)

func _combat_copy() -> String:
	match lantern_runtime.attack_phase:
		"anticipation": return "LANTERN FOCUSING"
		"onset": return "SPECTRAL BOLT"
		"impact": return "HOSTILE BOUND"
		"recovery": return "FLAME STEADIES"
		"ready_no_target": return "LANTERN WATCHFUL"
		_: return "AUTOMATIC LANTERN"

func _on_dash_phase_changed(phase: String, _invulnerable: bool) -> void:
	match phase:
		"ready":
			dash_label.text = "DASH READY"
			dash_meter.value = 1.0
			dash_label.modulate = Color("ffe0a0")
		"anticipation":
			dash_label.text = "FOCUSING"
			dash_meter.value = 0.2
			dash_label.modulate = Color("ffc35d")
		"active":
			dash_label.text = "PHASE SHIFT"
			dash_meter.value = 1.0
			dash_label.modulate = Color("79fff2")
		"recovery":
			dash_label.text = "STEADYING"
			dash_meter.value = 0.08
			dash_label.modulate = Color("f5b5ff")
		"cooldown":
			dash_label.text = "REKINDLING"
			dash_meter.value = 0.0
			dash_label.modulate = Color("b9b7d9")
	dash_icon.queue_redraw()

func _on_dash_readiness_changed(ready: bool, remaining: float) -> void:
	if ready:
		dash_meter.value = 1.0
	elif warden.dash_phase == "cooldown":
		dash_meter.value = 1.0 - clampf(remaining / warden.cooldown_duration, 0.0, 1.0)

func _mcp_state() -> Dictionary:
	return {
		"run_state": run_state,
		"pause_state": pause_state,
		"tree_paused": get_tree().paused,
		"combat_state": combat_state,
		"validation_build_profile": validation_build_profile,
		"last_attack_event": last_attack_event,
		"last_hit_event": last_hit_event,
		"last_drop_event": last_drop_event,
		"build": inventory.get_snapshot() if inventory else {},
	}
