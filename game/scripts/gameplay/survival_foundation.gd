class_name SurvivalFoundation
extends Node3D

@export var session_active := false
@export var combat_state := "seeking"

@onready var warden: WardenController = $Warden
@onready var inventory: WeaponInventory = $Warden/Weapons/WeaponInventory
@onready var attack_runtime: AttackRuntime = $Warden/Weapons/AttackRuntime
@onready var lantern_runtime: WardenLanternRuntime = $Warden/Weapons/WardenLanternRuntime
@onready var gravespade_runtime: GravespadeRuntime = $Warden/Weapons/GravespadeRuntime
@onready var wisps_runtime: WanderingWispsRuntime = $Warden/Weapons/WanderingWispsRuntime
@onready var spawner: EncounterSpawner = $EncounterSpawner

var last_attack_event: Dictionary = {}
var last_hit_event: Dictionary = {}
var last_drop_event: Dictionary = {}
var validation_build_profile := "starting"

func _ready() -> void:
	# Runtime-only Tester controls: registered without physical bindings and
	# intentionally absent from project.godot/release controls.
	if OS.has_feature("editor"):
		if not InputMap.has_action(&"validation_prepare_build"):
			InputMap.add_action(&"validation_prepare_build")
		if not InputMap.has_action(&"validation_reset_build"):
			InputMap.add_action(&"validation_reset_build")
		if not InputMap.has_action(&"validation_prepare_wisps"):
			InputMap.add_action(&"validation_prepare_wisps")
	attack_runtime.attack_authorized.connect(_on_attack_authorized)
	attack_runtime.hit_resolved.connect(_on_hit_resolved)
	spawner.enemy_lifecycle.connect(_on_enemy_lifecycle)
	spawner.reward_dropped.connect(_on_drop_committed)
	set_session_active(false)

func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("editor"):
		return
	if event.is_action_pressed(&"validation_prepare_build"):
		prepare_weapon_validation("representative")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"validation_prepare_wisps"):
		prepare_weapon_validation("wisps_only")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"validation_reset_build"):
		reset_weapon_validation()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	combat_state = lantern_runtime.attack_phase

func set_session_active(value: bool) -> void:
	session_active = value
	warden.set_physics_process(value)
	warden.set_process(value)
	for runtime in [$Warden/Weapons/WardenLanternRuntime, $Warden/Weapons/GravespadeRuntime, $Warden/Weapons/WanderingWispsRuntime]:
		runtime.set_physics_process(value)

func reset_session(reset_presentation := true, presentation_reset_owner := "run_reset") -> void:
	if reset_presentation:
		warden.reset_for_run(Vector3(0, 0.05, 6.0), presentation_reset_owner)
	else:
		# Result teardown retires combat ownership but leaves the authored
		# terminal deformation and lantern attachment alive until Retry/Title.
		warden.set_process(true)
	attack_runtime.reset_runtime()
	for runtime in [$Warden/Weapons/WardenLanternRuntime, $Warden/Weapons/GravespadeRuntime, $Warden/Weapons/WanderingWispsRuntime]:
		if runtime.has_method("reset_runtime"):
			runtime.reset_runtime()
	last_attack_event = {}
	last_hit_event = {}
	last_drop_event = {}
	validation_build_profile = "starting"

func retire_run_ownership(reason: String, generation: int) -> Dictionary:
	# Disable every update owner before invalidating its handles. This boundary
	# is intentionally repeat-safe and precedes generic friendly-attack cleanup.
	set_session_active(false)
	var weapon_receipts: Array[Dictionary] = []
	for runtime in [lantern_runtime, gravespade_runtime, wisps_runtime]:
		if runtime.has_method("retire_runtime"):
			weapon_receipts.append(runtime.retire_runtime(reason, generation))
	var combat_receipt := attack_runtime.retire_runtime(reason, generation)
	return {
		"reason": reason, "generation": generation,
		"weapon_receipts": weapon_receipts,
		"combat_receipt": combat_receipt,
		"wisp_handles": wisps_runtime.active_wisp_count,
		"wisp_intervals": wisps_runtime._target_next_hit_time.size(),
		"active_attack_ledgers": attack_runtime._hit_ledgers.size(),
		"complete": wisps_runtime.active_wisp_count == 0 and attack_runtime._hit_ledgers.is_empty(),
	}

func prepare_weapon_validation(profile: String = "representative") -> Dictionary:
	validation_build_profile = profile
	return inventory.prepare_legal_build(profile)

func reset_weapon_validation() -> void:
	validation_build_profile = "starting"
	inventory.reset_starting_build()

func _on_attack_authorized(event: Dictionary) -> void:
	last_attack_event = event.duplicate(true)

func _on_hit_resolved(event: Dictionary) -> void:
	last_hit_event = event.duplicate(true)

func _on_enemy_lifecycle(event: Dictionary) -> void:
	if String(event.get("phase", "")) in ["hurt", "death", "damage"]:
		last_hit_event = event.duplicate(true)

func _on_drop_committed(event: Dictionary) -> void:
	last_drop_event = event.duplicate(true)
	# Health/death/drop signals are synchronous. AttackRuntime holds this final
	# link until apply_damage returns, preserving damage -> death -> drop order.
	attack_runtime.record_reward(event)

func _mcp_state() -> Dictionary:
	return {
		"session_active": session_active,
		"combat_state": combat_state,
		"validation_build_profile": validation_build_profile,
		"last_attack_event": last_attack_event,
		"last_hit_event": last_hit_event,
		"last_drop_event": last_drop_event,
		"build": inventory.get_snapshot() if inventory else {},
	}
