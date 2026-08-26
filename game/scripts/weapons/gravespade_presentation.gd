class_name GravespadePresentation
extends Node3D

var variant := 0
var phase := "onset"

func configure(variant_index: int) -> void:
	variant = posmod(variant_index, 3)
	$SilverArc.visible = variant != 1
	$SplitArcA.visible = variant == 1
	$SplitArcB.visible = variant == 1
	$ShardBurst.visible = variant == 2
	$GroundRune.visible = variant != 1
	match variant:
		0:
			$SilverArc.scale = Vector3(1.22, 0.22, 0.58)
			$GroundRune.scale = Vector3.ONE
		1:
			$SplitArcA.rotation.y = -0.34
			$SplitArcB.rotation.y = 0.34
		2:
			$SilverArc.scale = Vector3(0.92, 0.34, 0.78)
			$GroundRune.scale = Vector3.ONE * 1.35
	rotation.y = -0.62
	var tween := create_tween()
	tween.tween_callback(_set_phase.bind("active"))
	tween.tween_property(self, "rotation:y", 0.82, 0.13 + variant * 0.018)
	tween.tween_callback(_set_phase.bind("impact"))
	tween.parallel().tween_property(self, "scale", Vector3.ONE * (1.12 + variant * 0.08), 0.07)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.11)
	tween.tween_callback(queue_free)

func _set_phase(value: String) -> void:
	phase = value

func _mcp_state() -> Dictionary:
	return {"variant": variant, "presentation_phase": phase}
