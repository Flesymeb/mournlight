class_name CombatTarget
extends Node3D

@export var stable_id := &"target.possessed_lantern.a"
@export var death_fade_duration := 0.45
@onready var health: HealthComponent = $HealthComponent
@onready var drops: DropTransaction = $DropTransaction
@onready var model_pivot: Node3D = $ModelPivot
@onready var hurt_flash: OmniLight3D = $HurtFlash

var hurt_count := 0
var death_count := 0
var drop_count := 0
var _dead := false
var _time := 0.0

func _ready() -> void:
	health.actor_id = stable_id
	health.hurt.connect(_on_hurt)
	health.died.connect(_on_died)
	drops.drop_committed.connect(_on_drop_committed)

func _process(delta: float) -> void:
	_time += delta
	if not _dead:
		model_pivot.position.y = sin(_time * 2.2 + float(stable_id.hash() % 7)) * 0.08
		model_pivot.rotation.y += delta * 0.22
	hurt_flash.light_energy = move_toward(hurt_flash.light_energy, 0.0, delta * 12.0)

func get_stable_id() -> StringName:
	return stable_id

func is_legal_target() -> bool:
	return not _dead and health.is_alive() and is_inside_tree()

func _on_hurt(_event: Dictionary) -> void:
	hurt_count += 1
	hurt_flash.light_energy = 3.0
	var tween := create_tween()
	tween.tween_property(model_pivot, "scale", Vector3(1.12, 0.82, 1.12), 0.06)
	tween.tween_property(model_pivot, "scale", Vector3.ONE, 0.12)

func _on_died(event: Dictionary) -> void:
	if _dead:
		return
	_dead = true
	death_count += 1
	drops.commit_from_death(event)
	var tween := create_tween()
	tween.tween_property(model_pivot, "scale", Vector3(0.35, 1.25, 0.35), death_fade_duration * 0.45)
	tween.tween_property(model_pivot, "scale", Vector3.ZERO, death_fade_duration * 0.55)
	tween.tween_callback(model_pivot.hide)

func _on_drop_committed(_event: Dictionary) -> void:
	drop_count += 1
	$DropGlow.visible = true
	var tween := create_tween().set_loops(3)
	tween.tween_property($DropGlow, "scale", Vector3.ONE * 1.35, 0.12)
	tween.tween_property($DropGlow, "scale", Vector3.ONE * 0.82, 0.12)

func _mcp_state() -> Dictionary:
	return {
		"stable_id": String(stable_id), "legal_target": is_legal_target(), "hurt_count": hurt_count,
		"death_count": death_count, "drop_count": drop_count, "health": health.current_health,
	}

