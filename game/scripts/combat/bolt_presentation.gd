class_name LanternBoltPresentation
extends Node3D

const TRAVEL_VARIANTS: Array[float] = [0.0, 0.025, -0.02, 0.04]

@export var travel_duration := 0.18
var attack_id := ""
var variant := 0
var phase := "onset"
var _origin := Vector3.ZERO
var _target_position := Vector3.ZERO
var _elapsed := 0.0

func configure(origin: Vector3, target_position: Vector3, event: Dictionary, variant_index: int) -> void:
	_origin = origin
	_target_position = target_position + Vector3.UP * 0.85
	attack_id = String(event.get("attack_id", ""))
	variant = posmod(variant_index, 4)
	global_position = _origin
	$VariantFork.visible = variant == 1
	$VariantHalo.visible = variant == 2
	$VariantComet.visible = variant == 3
	travel_duration += TRAVEL_VARIANTS[variant]

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
		var tween := create_tween()
		tween.tween_property($Impact, "scale", Vector3.ONE * (1.7 + variant * 0.16), 0.09)
		tween.tween_property($Impact, "scale", Vector3.ZERO, 0.12)
		tween.tween_callback(queue_free)
		set_process(false)

func _mcp_state() -> Dictionary:
	return {"attack_id": attack_id, "variant": variant, "presentation_phase": phase}
