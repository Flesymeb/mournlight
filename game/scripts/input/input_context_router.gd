class_name InputContextRouter
extends Node

const CONFIRM_PHYSICAL := &"context_confirm"
const BACK_PHYSICAL := &"context_back"

var context := "title"
var context_generation := 0
var activation_generation := 0
var confirm_dispatch := &""
var back_dispatch := &""
var last_receipt: Dictionary = {}
var last_activation_receipt: Dictionary = {}
var last_context_receipt: Dictionary = {}
var last_press_receipt: Dictionary = {}
var last_release_receipt: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_context()

func _process(_delta: float) -> void:
	_sync_context()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(CONFIRM_PHYSICAL):
		_dispatch_press("confirm", _confirm_action())
		get_viewport().set_input_as_handled()
	elif event.is_action_released(CONFIRM_PHYSICAL):
		_dispatch_release("confirm")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(BACK_PHYSICAL):
		_dispatch_press("back", _back_action())
		get_viewport().set_input_as_handled()
	elif event.is_action_released(BACK_PHYSICAL):
		_dispatch_release("back")
		get_viewport().set_input_as_handled()

func _sync_context() -> void:
	var next_context := _resolve_context()
	if next_context == context:
		return
	# A context change owns interruption cleanup. A held physical control can
	# never keep its old gameplay or shell action pressed behind the new page.
	_release_action(confirm_dispatch)
	_release_action(back_dispatch)
	confirm_dispatch = &""
	back_dispatch = &""
	context = next_context
	context_generation += 1
	last_context_receipt = {
		"phase":"context_changed", "context":context,
		"context_generation":context_generation,
	}
	last_receipt = last_context_receipt.duplicate(true)

func _resolve_context() -> String:
	var controller := get_parent()
	if not controller:
		return "unavailable"
	var shell = controller.get("shell")
	if is_instance_valid(shell) and shell.visible and String(shell.mode) != "hidden":
		return String(shell.mode)
	var state := String(controller.get("run_state"))
	return state if state != "" else "unavailable"

func _confirm_action() -> StringName:
	if context in ["active", "boss"]:
		return &"dash"
	if context in ["title", "pause", "paused", "settings", "credits", "draft", "result"]:
		return &"ui_accept"
	return &""

func _back_action() -> StringName:
	if context in ["active", "boss", "pause", "paused"]:
		return &"pause"
	if context in ["title", "settings", "credits"]:
		return &"ui_cancel"
	return &""

func _dispatch_press(physical: String, action: StringName) -> void:
	activation_generation += 1
	if physical == "confirm":
		confirm_dispatch = action
	else:
		back_dispatch = action
	if action != &"":
		_parse_action(action, true)
	last_receipt = {
		"phase":"pressed", "physical":physical, "logical_action":String(action),
		"accepted":action != &"", "context":context,
		"context_generation":context_generation,
		"activation_generation":activation_generation,
	}
	last_activation_receipt = last_receipt.duplicate(true)
	last_press_receipt = last_receipt.duplicate(true)

func _dispatch_release(physical: String) -> void:
	var action := confirm_dispatch if physical == "confirm" else back_dispatch
	_release_action(action)
	if physical == "confirm":
		confirm_dispatch = &""
	else:
		back_dispatch = &""
	last_receipt = {
		"phase":"released", "physical":physical, "logical_action":String(action),
		"accepted":action != &"", "context":context,
		"context_generation":context_generation,
		"activation_generation":activation_generation,
	}
	last_activation_receipt = last_receipt.duplicate(true)
	last_release_receipt = last_receipt.duplicate(true)

func _release_action(action: StringName) -> void:
	if action != &"":
		_parse_action(action, false)

func _parse_action(action: StringName, pressed: bool) -> void:
	var synthetic := InputEventAction.new()
	synthetic.action = action
	synthetic.pressed = pressed
	synthetic.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(synthetic)

func _mcp_state() -> Dictionary:
	return {
		"context":context, "context_generation":context_generation,
		"activation_generation":activation_generation,
		"confirm_dispatch":String(confirm_dispatch),
		"back_dispatch":String(back_dispatch),
		"last_receipt":last_receipt,
		"last_activation_receipt":last_activation_receipt,
		"last_context_receipt":last_context_receipt,
		"last_press_receipt":last_press_receipt,
		"last_release_receipt":last_release_receipt,
	}
