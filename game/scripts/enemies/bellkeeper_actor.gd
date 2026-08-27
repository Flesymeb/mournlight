class_name BellkeeperActor
extends CharacterBody3D

signal boss_changed(snapshot: Dictionary)
signal defeated(event: Dictionary)
signal phase_shifted(phase: int)

@onready var health: HealthComponent = $HealthComponent
@onready var telegraph: MeshInstance3D = $Telegraph
@onready var presentation: Node3D = $Presentation
var target: WardenController
var state := "entrance"
var phase := 1
var attack_clock := 2.4
var state_clock := 1.7
var attack_serial := 0
var committed := false

func _ready() -> void:
	add_to_group("combat_targets")
	add_to_group("active_enemies")
	add_to_group("mcp_watch")
	health.hurt.connect(_on_hurt)
	health.died.connect(_on_died)
	telegraph.visible = false
	boss_changed.emit(get_snapshot())

func configure(next_target: WardenController) -> void:
	target = next_target
	health.reset_health()
	state = "entrance"
	phase = 1
	committed = false

func _physics_process(delta: float) -> void:
	if committed or not is_instance_valid(target):
		return
	state_clock = maxf(0.0, state_clock - delta)
	attack_clock = maxf(0.0, attack_clock - delta)
	presentation.rotation.y += delta * (0.22 if phase == 1 else 0.46)
	if state == "entrance":
		velocity = Vector3.ZERO
		if state_clock <= 0.0:
			state = "pursuit"
	elif state == "telegraph":
		velocity = Vector3.ZERO
		telegraph.scale = Vector3.ONE * (1.0 + (0.9 - state_clock) * 0.7)
		if state_clock <= 0.0:
			_resolve_toll()
	else:
		var direction := target.global_position - global_position
		direction.y = 0.0
		velocity = direction.normalized() * (1.55 if phase == 1 else 2.15)
		if direction.length() < 5.0 and attack_clock <= 0.0:
			state = "telegraph"
			state_clock = 0.9 if phase == 1 else 0.65
			telegraph.visible = true
	move_and_slide()
	global_position.y = 0.05

func _resolve_toll() -> void:
	attack_serial += 1
	telegraph.visible = false
	state = "pursuit"
	attack_clock = 3.4 if phase == 1 else 2.35
	if global_position.distance_to(target.global_position) <= 5.4:
		target.get_node("HealthComponent").apply_damage({"attack_id":"bellkeeper.toll.%d" % attack_serial,"damage":18.0 if phase == 1 else 24.0,"damage_channel":"boss_toll"})
	boss_changed.emit(get_snapshot())

func _on_hurt(_event: Dictionary) -> void:
	if phase == 1 and health.current_health <= health.maximum_health * 0.5:
		phase = 2
		state = "phase_shift"
		state_clock = 1.2
		phase_shifted.emit(phase)
	boss_changed.emit(get_snapshot())

func _on_died(event: Dictionary) -> void:
	if committed:
		return
	committed = true
	state = "defeated"
	velocity = Vector3.ZERO
	telegraph.visible = false
	var tween := create_tween()
	tween.tween_property(presentation, "scale", Vector3(1.4, 0.15, 1.4), 0.75)
	defeated.emit(event)
	boss_changed.emit(get_snapshot())

func is_legal_target() -> bool:
	return not committed and health.is_alive()

func get_stable_id() -> StringName:
	return &"boss.bellkeeper"

func get_snapshot() -> Dictionary:
	return {"active":not committed,"state":state,"phase":phase,"health":health.current_health,"health_maximum":health.maximum_health,"attack_clock":attack_clock}

func _mcp_state() -> Dictionary:
	return get_snapshot()

