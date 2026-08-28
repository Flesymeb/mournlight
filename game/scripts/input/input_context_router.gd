class_name InputContextRouter
extends Node

signal logical_press_edge(action: StringName, activation_generation: int, receipt: Dictionary)
signal context_changed(previous: String, current: String, context_generation: int)
signal device_changed(previous: String, current: String, device_generation: int)

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
var active_transactions: Dictionary = {}
var completed_transactions: Array[Dictionary] = []
var active_device := "keyboard"
var device_generation := 0
var last_device_receipt: Dictionary = {}
var movement_vector := Vector2.ZERO
var _movement_actions := {
	&"move_left": false, &"move_right": false,
	&"move_forward": false, &"move_back": false,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_context()

func _process(_delta: float) -> void:
	_sync_context()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	_observe_device(event)
	# Keep an authoritative edge-backed movement state. Some embedded runners
	# synthesize InputEventAction edges without updating Input's polling cache;
	# Warden can consume this state during its physics tick just like a native
	# keyboard/gamepad action.
	for action in _movement_actions.keys():
		var action_name := StringName(action)
		if event.is_action_pressed(action_name):
			_movement_actions[action_name] = true
			_recompute_movement_vector()
		elif event.is_action_released(action_name):
			_movement_actions[action_name] = false
			_recompute_movement_vector()
	if event.is_action_pressed(&"dash") and context in ["active", "boss"]:
		_dispatch_press("confirm", &"dash")
		get_viewport().set_input_as_handled()
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

func _recompute_movement_vector() -> void:
	movement_vector = Vector2(
		float(_movement_actions[&"move_right"]) - float(_movement_actions[&"move_left"]),
		float(_movement_actions[&"move_back"]) - float(_movement_actions[&"move_forward"])
	).limit_length(1.0)

func get_movement_vector() -> Vector2:
	return movement_vector

func clear_movement_latch(reason := "reset") -> void:
	for action in _movement_actions.keys():
		_movement_actions[action] = false
	movement_vector = Vector2.ZERO
	last_receipt = {"phase":"movement_reset", "reason":reason, "process_frame":Engine.get_process_frames()}

func _observe_device(event: InputEvent) -> void:
	var next_device := active_device
	if event is InputEventJoypadButton:
		next_device = "gamepad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= 0.35:
		next_device = "gamepad"
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		next_device = "keyboard"
	else:
		return
	if next_device == active_device:
		return
	var previous := active_device
	active_device = next_device
	device_generation += 1
	last_device_receipt = {
		"previous":previous, "current":active_device,
		"generation":device_generation, "event_type":event.get_class(),
		"process_frame":Engine.get_process_frames(),
	}
	device_changed.emit(previous, active_device, device_generation)

func binding_label(actions: Array, maximum_labels: int = 4) -> String:
	var labels: Array[String] = []
	for action_value in actions:
		var action := StringName(action_value)
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			var is_gamepad := event is InputEventJoypadButton or event is InputEventJoypadMotion
			if (active_device == "gamepad") != is_gamepad:
				continue
			var label := _event_label(event)
			if not label.is_empty() and not labels.has(label):
				labels.append(label)
			if labels.size() >= maximum_labels:
				return " / ".join(labels)
	return " / ".join(labels) if not labels.is_empty() else "UNBOUND"

func _event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var keycode := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
		return OS.get_keycode_string(keycode).to_upper()
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "LEFT STICK" if motion.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] else "RIGHT STICK"
	if event is InputEventJoypadButton:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_A: return "SOUTH BUTTON"
			JOY_BUTTON_B: return "EAST BUTTON"
			JOY_BUTTON_BACK: return "VIEW / BACK"
			JOY_BUTTON_START: return "MENU"
			_: return "BUTTON %d" % ((event as InputEventJoypadButton).button_index + 1)
	return event.as_text().strip_edges().to_upper()

func _sync_context() -> void:
	var next_context := _resolve_context()
	if next_context == context:
		return
	# A context change releases the logical action, but never transfers the
	# still-held physical activation. Its originating transaction survives
	# until the matching physical release is observed.
	_release_transaction_action("confirm", "context_changed")
	_release_transaction_action("back", "context_changed")
	var previous_context := context
	context = next_context
	if context not in ["active", "boss"]:
		clear_movement_latch("context_%s" % context)
	context_generation += 1
	last_context_receipt = {
		"phase":"context_changed", "context":context,
		"context_generation":context_generation,
	}
	last_receipt = last_context_receipt.duplicate(true)
	context_changed.emit(previous_context, context, context_generation)

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
	if context in ["title", "pause", "paused", "settings", "help", "credits", "draft", "result"]:
		return &"ui_accept"
	return &""

func _back_action() -> StringName:
	if context in ["active", "boss", "pause", "paused"]:
		return &"pause"
	if context in ["title", "settings", "help", "credits"]:
		return &"ui_cancel"
	return &""

func _dispatch_press(physical: String, action: StringName) -> void:
	if active_transactions.has(physical):
		var duplicate: Dictionary = active_transactions[physical]
		duplicate["duplicate_press_count"] = int(duplicate.get("duplicate_press_count", 0)) + 1
		active_transactions[physical] = duplicate
		last_receipt = duplicate.duplicate(true)
		return
	activation_generation += 1
	if physical == "confirm":
		confirm_dispatch = action
	else:
		back_dispatch = action
	var transaction := {
		"phase":"pressed", "physical":physical, "logical_action":String(action),
		"accepted":action != &"", "context":context,
		"originating_context":context,
		"originating_context_generation":context_generation,
		"context_generation":context_generation,
		"activation_generation":activation_generation,
		"logical_press_dispatched":action != &"",
		"logical_release_dispatched":false,
		"physical_release_observed":false,
		"resolved_destination":"pending",
		"downstream_action_count":1 if action != &"" else 0,
		"duplicate_press_count":0,
	}
	active_transactions[physical] = transaction
	last_receipt = transaction.duplicate(true)
	last_activation_receipt = last_receipt.duplicate(true)
	last_press_receipt = last_receipt.duplicate(true)
	# Publish ownership before synthesizing the logical press. Input parsing may
	# synchronously invoke page code, which must be able to bind this transaction.
	if action != &"":
		# Motor actions consume this transaction-scoped edge directly. The
		# synthetic action remains for non-motor observers and UI compatibility,
		# but authoritative gameplay never has to rediscover a transient global
		# Input edge during a later physics tick.
		logical_press_edge.emit(action, activation_generation, transaction.duplicate(true))
		_parse_action(action, true)

func _dispatch_release(physical: String) -> void:
	var transaction: Dictionary = active_transactions.get(physical, {})
	var action := StringName(String(transaction.get("logical_action", "")))
	if not bool(transaction.get("logical_release_dispatched", false)):
		transaction["logical_release_dispatched"] = action != &""
		transaction["logical_release_reason"] = "physical_release"
		active_transactions[physical] = transaction
		_release_action(action)
		# A button may commit synchronously on logical release and annotate the
		# active transaction with its destination.
		transaction = active_transactions.get(physical, transaction)
	if physical == "confirm":
		confirm_dispatch = &""
	else:
		back_dispatch = &""
	transaction.merge({
		"phase":"released", "physical":physical, "logical_action":String(action),
		"accepted":action != &"", "release_context":context,
		"release_context_generation":context_generation,
		"physical_release_observed":true,
		"release_observation_frame":Engine.get_process_frames(),
	}, true)
	if String(transaction.get("resolved_destination", "pending")) == "pending":
		transaction["resolved_destination"] = context
	active_transactions.erase(physical)
	completed_transactions.append(transaction.duplicate(true))
	if completed_transactions.size() > 12:
		completed_transactions.pop_front()
	last_receipt = transaction.duplicate(true)
	last_activation_receipt = last_receipt.duplicate(true)
	last_release_receipt = last_receipt.duplicate(true)

func _release_transaction_action(physical: String, reason: String) -> void:
	if not active_transactions.has(physical):
		return
	var transaction: Dictionary = active_transactions[physical]
	if bool(transaction.get("logical_release_dispatched", false)):
		return
	var action := StringName(String(transaction.get("logical_action", "")))
	transaction["logical_release_dispatched"] = action != &""
	transaction["logical_release_reason"] = reason
	active_transactions[physical] = transaction
	_release_action(action)

func bind_destination(physical: String, destination: String, downstream_action_count: int = 1) -> Dictionary:
	if not active_transactions.has(physical):
		return {}
	var transaction: Dictionary = active_transactions[physical]
	transaction["resolved_destination"] = destination
	transaction["downstream_action_count"] = downstream_action_count
	active_transactions[physical] = transaction
	last_activation_receipt = transaction.duplicate(true)
	return transaction.duplicate(true)

func transaction_released(physical: String, expected_activation_generation: int) -> bool:
	for transaction in completed_transactions:
		if String(transaction.get("physical", "")) == physical and int(transaction.get("activation_generation", -1)) == expected_activation_generation:
			return bool(transaction.get("physical_release_observed", false))
	return false

func transaction_receipt(physical: String, expected_activation_generation: int) -> Dictionary:
	if active_transactions.has(physical):
		var active: Dictionary = active_transactions[physical]
		if int(active.get("activation_generation", -1)) == expected_activation_generation:
			return active.duplicate(true)
	for transaction in completed_transactions:
		if String(transaction.get("physical", "")) == physical and int(transaction.get("activation_generation", -1)) == expected_activation_generation:
			return transaction.duplicate(true)
	return {}

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
		"active_transactions":active_transactions,
		"completed_transactions":completed_transactions,
		"active_device":active_device,
		"device_generation":device_generation,
		"last_device_receipt":last_device_receipt,
		"movement_vector":movement_vector,
		"movement_actions":_movement_actions,
	}
