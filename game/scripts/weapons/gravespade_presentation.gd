class_name GravespadePresentation
extends Node3D

signal retired(presentation: GravespadePresentation)

var variant := 0
var phase := "onset"
var _retired := true
var _tween: Tween

func _ready() -> void:
	set_process(false)

func configure(variant_index: int) -> void:
	if not is_in_group(&"friendly_attack"): add_to_group(&"friendly_attack")
	if _tween and _tween.is_valid(): _tween.kill()
	_retired = false
	visible = true
	set_process(true)
	scale = Vector3.ONE
	$SilverArc.scale = Vector3.ONE
	$SplitArcA.scale = Vector3.ONE; $SplitArcB.scale = Vector3.ONE
	$ShardBurst.scale = Vector3.ONE; $GroundRune.scale = Vector3.ONE
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
	_tween = create_tween()
	_tween.tween_callback(_set_phase.bind("active"))
	_tween.tween_property(self, "rotation:y", 0.82, 0.13 + variant * 0.018)
	_tween.tween_callback(_set_phase.bind("impact"))
	_tween.parallel().tween_property(self, "scale", Vector3.ONE * (1.12 + variant * 0.08), 0.07)
	_tween.tween_property(self, "scale", Vector3.ZERO, 0.11)
	_tween.tween_callback(_retire)

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

func _set_phase(value: String) -> void:
	phase = value

func _mcp_state() -> Dictionary:
	return {"variant": variant, "presentation_phase": phase}
