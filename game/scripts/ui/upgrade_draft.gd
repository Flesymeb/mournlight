class_name UpgradeDraftView
extends Control

signal choice_requested(index: int)

const STAT_ICON_PATHS := {
	"equipped":"res://assets/ui/upgrades/stats/weapon.svg", "rank":"res://assets/ui/upgrades/stats/rank.svg",
	"damage":"res://assets/ui/upgrades/stats/damage.svg", "global_damage_multiplier":"res://assets/ui/upgrades/stats/damage.svg",
	"cooldown":"res://assets/ui/upgrades/stats/cooldown.svg", "dash_cooldown":"res://assets/ui/upgrades/stats/cooldown.svg",
	"range":"res://assets/ui/upgrades/stats/range.svg", "pickup_collection_radius":"res://assets/ui/upgrades/stats/range.svg",
	"area":"res://assets/ui/upgrades/stats/area.svg", "count":"res://assets/ui/upgrades/stats/count.svg",
	"duration":"res://assets/ui/upgrades/stats/duration.svg", "hit_interval":"res://assets/ui/upgrades/stats/interval.svg",
	"health":"res://assets/ui/upgrades/stats/health.svg", "health_maximum":"res://assets/ui/upgrades/stats/health.svg",
	"experience_yield_multiplier":"res://assets/ui/upgrades/stats/experience.svg",
}
const VIOLET := Color("c27cff")

var cards: Array[Dictionary] = []
var latched := false
var selected_index := -1
var input_device := "keyboard"
var device_generation := 0
var _hovered: Array[bool] = [false, false, false]
var _pressed: Array[bool] = [false, false, false]
var _icon_nodes: Array[TextureRect] = []
var _title_nodes: Array[Label] = []
var _consequence_nodes: Array[Label] = []
var _state_nodes: Array[Label] = []
var _stat_bodies: Array[VBoxContainer] = []
var _presentation_serial := 0
@onready var buttons: Array[Button] = [$Cards/CardA, $Cards/CardB, $Cards/CardC]
@onready var cards_container: HBoxContainer = $Cards

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cards_container.pivot_offset = Vector2(510, 261)
	for index in buttons.size():
		_build_card_content(buttons[index])
		buttons[index].pressed.connect(_choose.bind(index))
		buttons[index].focus_entered.connect(_refresh_card_state.bind(index))
		buttons[index].focus_exited.connect(_refresh_card_state.bind(index))
		buttons[index].mouse_entered.connect(_set_hovered.bind(index, true))
		buttons[index].mouse_exited.connect(_set_hovered.bind(index, false))
		buttons[index].button_down.connect(_set_pressed.bind(index, true))
		buttons[index].button_up.connect(_set_pressed.bind(index, false))
	visible = false
	_layout_cards()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(cards_container):
		_layout_cards()

func _layout_cards() -> void:
	if not is_instance_valid(cards_container):
		return
	# Keep the authored three-card hierarchy intact while fitting the full
	# choice family inside narrow windowed modes and high UI scales.
	var width_ratio := (size.x - 48.0) / 1056.0
	var height_ratio := (size.y - 190.0) / 522.0
	var fit := clampf(minf(width_ratio, height_ratio), 0.58, 1.0)
	cards_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cards_container.position = size * 0.5 - cards_container.pivot_offset * fit
	cards_container.size = Vector2(1020, 522)
	cards_container.scale = Vector2.ONE * fit

func present(next_cards: Array[Dictionary]) -> void:
	_presentation_serial += 1
	cards = next_cards.duplicate(true)
	latched = false
	selected_index = -1
	for index in buttons.size():
		var card: Dictionary = cards[index]
		_icon_nodes[index].texture = load(String(card.icon_path)) as Texture2D
		_title_nodes[index].text = String(card.title).to_upper()
		_consequence_nodes[index].text = String(card.get("consequence", "Shape the next exchange."))
		_rebuild_stat_rows(index, _decision_changes(card.get("changes", [])))
		buttons[index].disabled = not bool(card.get("available", true))
		_refresh_card_state(index)
	visible = true
	buttons[0].grab_focus()

func set_input_device(next_device: String, generation: int) -> void:
	if next_device not in ["keyboard", "gamepad", "mouse"]:
		return
	input_device = next_device
	device_generation = generation
	if visible and input_device in ["keyboard", "gamepad"] and not _focused_card_available():
		_focus_first_available()
	for index in buttons.size():
		_refresh_card_state(index)

func _focused_card_available() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner in buttons and not (owner as Button).disabled

func _focus_first_available() -> void:
	for button in buttons:
		if not button.disabled:
			button.grab_focus()
			return

func close() -> void:
	_presentation_serial += 1
	visible = false
	cards.clear()
	selected_index = -1
	for index in buttons.size():
		_hovered[index] = false
		_pressed[index] = false

func _choose(index: int) -> void:
	if latched or index < 0 or index >= cards.size() or buttons[index].disabled:
		return
	latched = true
	var commit_serial := _presentation_serial
	selected_index = index
	for card_index in buttons.size():
		buttons[card_index].disabled = card_index != index
		_refresh_card_state(card_index)
	await get_tree().create_timer(0.18, true, false, true).timeout
	if commit_serial != _presentation_serial or not visible:
		return
	choice_requested.emit(index)

func _decision_changes(source_changes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in source_changes:
		if result.size() >= 3:
			break
		var change := value as Dictionary
		if change.is_empty() or not change.has("field") or not change.has("current") or not change.has("result"):
			continue
		if _display_values_equal(change.current, change.result):
			continue
		result.append(change.duplicate(true))
	return result

func _display_values_equal(current, next) -> bool:
	if current == null or next == null:
		return current == next
	if current is String or next is String:
		return current is String and next is String and String(current) == String(next)
	if current is float or next is float or current is int or next is int:
		return is_equal_approx(float(current), float(next))
	return current == next

func _build_card_content(button: Button) -> void:
	button.text = ""
	button.clip_contents = false
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var state_label := Label.new()
	state_label.custom_minimum_size = Vector2(0, 20)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	state_label.add_theme_font_size_override("font_size", 10)
	state_label.add_theme_color_override("font_color", Color(0.48, 0.95, 0.9))
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(state_label)
	_state_nodes.append(state_label)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 118)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)
	_icon_nodes.append(icon)
	var title_label := Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.48))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_label)
	_title_nodes.append(title_label)
	var consequence := Label.new()
	consequence.custom_minimum_size = Vector2(0, 34)
	consequence.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	consequence.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	consequence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	consequence.add_theme_font_size_override("font_size", 12)
	consequence.add_theme_color_override("font_color", Color(0.72, 0.77, 0.88))
	consequence.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(consequence)
	_consequence_nodes.append(consequence)
	var divider := HSeparator.new()
	divider.modulate = Color(0.78, 0.58, 0.25, 0.78)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)
	column.add_child(_build_stat_header())
	var stat_body := VBoxContainer.new()
	stat_body.add_theme_constant_override("separation", 1)
	stat_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stat_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(stat_body)
	_stat_bodies.append(stat_body)

func _build_stat_header() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 19)
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(104, 0)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	for text in ["CURRENT", "", "NEW"]:
		var label := Label.new()
		label.text = text
		label.custom_minimum_size = Vector2(62 if not text.is_empty() else 10, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.79))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
	return row

func _rebuild_stat_rows(index: int, changes: Array) -> void:
	var body := _stat_bodies[index]
	for child in body.get_children():
		child.queue_free()
	for change_value in changes:
		body.add_child(_build_stat_row(change_value as Dictionary))

func _build_stat_row(change: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 25)
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(String(STAT_ICON_PATHS.get(String(change.field), STAT_ICON_PATHS.rank))) as Texture2D
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.text = String(change.label)
	label.custom_minimum_size = Vector2(81, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.91))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	# A newly unlocked weapon has no truthful "current" value. Keep the
	# current column visually empty; NEW belongs in the card state/header, never
	# in a faux current-value cell.
	var is_new := change.current == null
	if is_new:
		var empty_current := _value_label("", false)
		empty_current.custom_minimum_size = Vector2(62, 0)
		row.add_child(empty_current)
	else:
		row.add_child(_value_label(_format_value(change.current, String(change.field)), false))
	var arrow := Label.new()
	arrow.text = "›"
	arrow.custom_minimum_size = Vector2(10, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 16)
	arrow.add_theme_color_override("font_color", Color(0.47, 0.92, 0.87))
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	row.add_child(_value_label(_format_value(change.result, String(change.field)), true))
	return row

func _value_label(value: String, result_value: bool) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size = Vector2(62, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.48) if result_value else Color(0.72, 0.78, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _format_value(value, field: String) -> String:
	if value == null: return "—"
	if value is String: return value
	if field in ["count", "rank"]: return str(int(value))
	if field in ["cooldown", "duration", "hit_interval", "dash_cooldown"]: return "%.2fs" % float(value)
	if field in ["experience_yield_multiplier", "global_damage_multiplier"]: return "×%.2f" % float(value)
	if field == "pickup_collection_radius": return "%.2fm" % float(value)
	return "%.1f" % float(value) if not is_equal_approx(float(value), roundf(float(value))) else str(int(roundf(float(value))))

func _set_hovered(index: int, hovered: bool) -> void:
	_hovered[index] = hovered
	_refresh_card_state(index)

func _set_pressed(index: int, pressed: bool) -> void:
	_pressed[index] = pressed
	_refresh_card_state(index)

func _refresh_card_state(index: int) -> void:
	if index < 0 or index >= buttons.size() or index >= _state_nodes.size(): return
	var available := index < cards.size() and bool(cards[index].get("available", true))
	var newly_unlocked := index < cards.size() and bool(cards[index].get("newly_unlocked", false))
	var state := "AVAILABLE"
	if selected_index == index: state = "SELECTED  •  APPLYING"
	elif not available: state = "UNAVAILABLE"
	elif latched: state = "CHOICE LOCKED"
	elif _pressed[index]: state = "PRESS  •  RELEASE TO CHOOSE"
	elif buttons[index].has_focus(): state = ("GAMEPAD FOCUS" if input_device == "gamepad" else "KEYBOARD FOCUS") + "  •  CONFIRM TO CHOOSE"
	elif _hovered[index]: state = "HOVER  •  CLICK TO CHOOSE"
	elif newly_unlocked: state = "NEW WEAPON"
	_state_nodes[index].text = state
	buttons[index].add_theme_stylebox_override("normal", _card_style(state, false))
	buttons[index].add_theme_stylebox_override("hover", _card_style(state, true))
	buttons[index].add_theme_stylebox_override("pressed", _card_style(state, true))
	buttons[index].add_theme_stylebox_override("disabled", _card_style(state, false))
	buttons[index].add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	buttons[index].modulate = Color(0.56, 0.58, 0.65) if not available else Color.WHITE

func _card_style(state: String, emphasized: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.022, 0.047, 0.94)
	style.border_width_left = 2; style.border_width_top = 2; style.border_width_right = 2; style.border_width_bottom = 2
	style.corner_radius_top_left = 2; style.corner_radius_top_right = 2; style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
	style.border_color = Color(0.42, 0.31, 0.18, 0.85)
	if state.begins_with("SELECTED"):
		style.border_color = Color(1.0, 0.76, 0.31, 1.0); style.bg_color = Color(0.105, 0.072, 0.035, 0.97)
	elif "FOCUS" in state or state.begins_with("HOVER") or emphasized:
		style.border_color = Color(0.43, 0.96, 0.86, 1.0); style.bg_color = Color(0.035, 0.065, 0.072, 0.97)
	elif state == "NEW WEAPON": style.border_color = Color(0.72, 0.57, 0.95, 0.95)
	elif state in ["UNAVAILABLE", "CHOICE LOCKED"]: style.border_color = Color(0.32, 0.34, 0.4, 0.7)
	return style

func _mcp_state() -> Dictionary:
	var visible_cards: Array[Dictionary] = []
	for index in cards.size():
		var card: Dictionary = cards[index]
		visible_cards.append({"id":card.id, "title":card.title, "icon_path":card.icon_path, "changes":_decision_changes(card.changes), "consequence":card.get("consequence", ""), "interaction_state":_state_nodes[index].text})
	return {"authored_cards":visible_cards, "visible":visible, "latched":latched, "selected_index":selected_index, "focus":String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none", "input_device":input_device, "device_generation":device_generation, "cancel_policy":"draft_is_deliberately_non_cancelable", "stable_card_dimensions":Vector2(328,522), "hierarchy":"dominant_icon + consequence + projected_change_rows"}
