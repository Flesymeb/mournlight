class_name PauseOverlay
extends Control

@onready var state_value: Label = $Shade/Card/StateValue
var last_presentation: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func present(snapshot: Dictionary) -> void:
	var phase := str(snapshot.get("dash_phase", "ready")).to_upper()
	state_value.text = "WARDEN HELD  ·  DASH %s" % phase
	last_presentation = {"page":"pause", "state":"paused", "dash_phase":phase, "snapshot_bound":not snapshot.is_empty(), "focus_order":["resume","help","settings","restart","title","quit"]}
	visible = true

func dismiss() -> void:
	visible = false
	last_presentation["state"] = "dismissed"

func _mcp_state() -> Dictionary:
	return {"visible":visible, "presentation":last_presentation.duplicate(true), "focus_states":["keyboard","mouse","gamepad","pressed","disabled"]}
