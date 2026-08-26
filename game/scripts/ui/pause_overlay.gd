class_name PauseOverlay
extends Control

@onready var state_value: Label = $Shade/Card/StateValue

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func present(snapshot: Dictionary) -> void:
	var phase := str(snapshot.get("dash_phase", "ready")).to_upper()
	state_value.text = "WARDEN HELD  ·  DASH %s" % phase
	visible = true

func dismiss() -> void:
	visible = false
