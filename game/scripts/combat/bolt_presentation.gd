class_name LanternBoltPresentation
extends Node3D

signal retired(presentation: LanternBoltPresentation)

const TRAVEL_VARIANTS: Array[float] = [0.0, 0.025, -0.02, 0.04]

@export var travel_duration := 0.18
var _base_travel_duration := 0.18
var attack_id := ""
var variant := 0
var phase := "onset"
var _origin := Vector3.ZERO
var _target_position := Vector3.ZERO
var _elapsed := 0.0
var _retired := true
var _tween: Tween

func _ready() -> void:
	_base_travel_duration = travel_duration
	set_process(false)

func configure(origin: Vector3, target_position: Vector3, event: Dictionary, variant_index: int) -> void:
	if not is_in_group(&"friendly_attack"): add_to_group(&"friendly_attack")
	_origin = origin
	_target_position = target_position + Vector3.UP * 0.85
	attack_id = String(event.get("attack_id", ""))
	variant = posmod(variant_index, 4)
	global_position = _origin
	$VariantFork.visible = variant == 1
	$VariantHalo.visible = variant == 2
	$VariantComet.visible = variant == 3
	travel_duration = _base_travel_duration + TRAVEL_VARIANTS[variant]
	_elapsed = 0.0
	_retired = false
	rotation = Vector3.ZERO
	scale = Vector3.ONE
	$Core.visible = true; $Trail.visible = true; $Impact.visible = false
	$VariantFork.visible = variant == 1; $VariantHalo.visible = variant == 2; $VariantComet.visible = variant == 3
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	var weight := clampf(_elapsed / travel_duration, 0.0, 1.0)
	global_position = _origin.lerp(_target_position, ease(weight, -0.35))
	phase = "active" if weight < 0.78 else "impact"
	rotation.y += delta * (8.0 + variant * 2.0)
	if weight >= 1.0:
		$Core.visible = false
		$Trail.visible = false
		$Impact.visible = true
		phase = "recovery"
		_tween = create_tween()
		_tween.tween_property($Impact, "scale", Vector3.ONE * (1.7 + variant * 0.16), 0.09)
		_tween.tween_property($Impact, "scale", Vector3.ZERO, 0.12)
		_tween.tween_callback(_retire)
		set_process(false)

func retire_for_pool() -> void:
	if _tween and _tween.is_valid(): _tween.kill()
	_retire()

func _retire() -> void:
	if _retired: return
	_retired = true
	visible = false
	set_process(false)
	phase = "pooled"
	remove_from_group(&"friendly_attack")
	retired.emit(self)

func _mcp_state() -> Dictionary:
	return {"attack_id": attack_id, "variant": variant, "presentation_phase": phase}
