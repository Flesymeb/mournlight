extends MainMenu

## Compatibility bridge for the product shell.  The curated menu component
## exposes generic sub-menu signals, while RunController owns the authored
## settings/credits pages; these signals keep that binding explicit without
## opening the component's optional stock sub-menu windows.
signal settings_requested
signal credits_requested

## Product-ready skin keeps the template flow while allowing a host game to
## bind start_game through the existing game_started signal before a concrete
## gameplay scene path is known.

@export_range(0.0, 24.0, 0.5) var background_parallax_pixels := 10.0
@export_range(1.0, 16.0, 0.5) var background_parallax_response := 5.5
@export_range(0.0, 96.0, 1.0) var background_overscan_pixels := 36.0

@onready var _background: TextureRect = $BackgroundTextureRect

var _background_motion := Vector2.ZERO


func _ready() -> void:
	super._ready()
	new_game_button.show()
	new_game_button.grab_focus.call_deferred()
	_configure_product_focus_contract()
	_resize_background()
	get_viewport().size_changed.connect(_resize_background)

func _configure_product_focus_contract() -> void:
	# The retained Maaack menu owns title-page traversal, but its stock focus
	# graph is implicit. Rebind the four visible product actions explicitly so
	# keyboard, mouse and gamepad all share one deterministic loop and every
	# control exposes a stable accessibility name/state.
	var menu_buttons: Array[Button] = []
	for node in get_tree().get_nodes_in_group("menu_button"):
		if node is Button and node.is_visible_in_tree():
			menu_buttons.append(node as Button)
	if menu_buttons.is_empty():
		for path in [
			"MenuContainer/MenuButtonsMargin/MenuButtonsContainer/MenuButtonsBoxContainer/NewGameButton",
			"MenuContainer/MenuButtonsMargin/MenuButtonsContainer/MenuButtonsBoxContainer/OptionsButton",
			"MenuContainer/MenuButtonsMargin/MenuButtonsContainer/MenuButtonsBoxContainer/CreditsButton",
			"MenuContainer/MenuButtonsMargin/MenuButtonsContainer/MenuButtonsBoxContainer/ExitButton"]:
			var button := get_node_or_null(path) as Button
			if is_instance_valid(button):
				menu_buttons.append(button)
	for index in menu_buttons.size():
		var button := menu_buttons[index]
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.accessibility_name = button.text
		button.set_meta("title_shell_action", button.name)
		button.focus_neighbor_top = button.get_path_to(menu_buttons[(index - 1 + menu_buttons.size()) % menu_buttons.size()])
		button.focus_neighbor_bottom = button.get_path_to(menu_buttons[(index + 1) % menu_buttons.size()])
	set_meta("title_accessibility_contract", {
		"focus_traversal":true,
		"keyboard_mouse_gamepad":true,
		"actions":["play","settings","credits","quit"],
		"state_styles":["normal","hover","focused","pressed","disabled"],
	})


func _process(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var target := _parallax_target_for_position(get_viewport().get_mouse_position(), viewport_size)
	var weight := 1.0 - exp(-background_parallax_response * delta)
	_background_motion = _background_motion.lerp(target, weight)
	_apply_background_motion()


func new_game() -> void:
	if get_game_scene_path().is_empty():
		game_started.emit()
		return
	super.new_game()


func _on_options_button_pressed() -> void:
	settings_requested.emit()


func _on_credits_button_pressed() -> void:
	credits_requested.emit()


func _parallax_target_for_position(pointer: Vector2, viewport_size: Vector2) -> Vector2:
	if background_parallax_pixels <= 0.0 or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO
	var normalized := (pointer / viewport_size - Vector2(0.5, 0.5)).clamp(
		Vector2(-0.5, -0.5), Vector2(0.5, 0.5)
	)
	return -normalized * background_parallax_pixels * 2.0


func _resize_background() -> void:
	_apply_background_motion()


func _apply_background_motion() -> void:
	var overscan := maxf(background_overscan_pixels, background_parallax_pixels + 2.0)
	_background.offset_left = -overscan + _background_motion.x
	_background.offset_top = -overscan + _background_motion.y
	_background.offset_right = overscan + _background_motion.x
	_background.offset_bottom = overscan + _background_motion.y
