class_name WanderingWispPresentation
extends Node3D

var variant := 0
var _time := 0.0

func configure(variant_index: int) -> void:
	variant = posmod(variant_index, 4)
	match variant:
		0:
			$Core.scale = Vector3(1.0, 1.18, 1.0)
			$Tail.rotation_degrees.z = 22.0
		1:
			$Core.scale = Vector3(1.26, 0.82, 0.9)
			$Tail.rotation_degrees.z = -32.0
		2:
			$Core.scale = Vector3(0.78, 1.42, 0.78)
			$Tail.scale = Vector3(0.75, 1.36, 0.75)
		3:
			$Core.scale = Vector3(1.1, 1.0, 1.34)
			$Tail.position.x = 0.13
			$Tail.rotation_degrees.z = 48.0

func _process(delta: float) -> void:
	_time += delta
	$Core.rotation.y += delta * (2.4 + variant * 0.55)
	$Glow.light_energy = 0.58 + sin(_time * (3.1 + variant * 0.35)) * 0.22
	$Tail.position.y = -0.24 + sin(_time * 4.0 + variant) * 0.035

func _mcp_state() -> Dictionary:
	return {"variant": variant, "presentation_phase": "persistent_orbit"}
