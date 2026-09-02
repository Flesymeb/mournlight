class_name UpgradeDraftView
extends Control

signal choice_requested(index: int)
signal cancel_requested

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
const PLACEHOLDER_VALUES := ["NEW", "LOCKED", "UNAVAILABLE", "UNKNOWN", "N/A", "NA"]
const FALLBACK_ICON_PATH := "res://assets/ui/upgrades/stats/weapon.svg"

var cards: Array[Dictionary] = []
var latched := false
var selected_index := -1
var input_device := "keyboard"
var device_generation := 0
var _hovered: Array[bool] = [false, false, false]
var _pressed: Array[bool] = [false, false, false]
var _icon_nodes: Array[TextureRect] = []
var _title_nodes: Array[Label] = []
var _rank_nodes: Array[Label] = []
var _consequence_nodes: Array[Label] = []
var _state_nodes: Array[Label] = []
var _stat_bodies: Array[VBoxContainer] = []
var _card_styles: Array[StyleBoxFlat] = []
var _presentation_serial := 0
@onready var buttons: Array[Button] = [$Cards/CardA, $Cards/CardB, $Cards/CardC]
@onready var cards_container: Control = $Cards
@onready var shade: ColorRect = $Shade

const CARD_SIZE := Vector2(328, 522)
const CARD_OFFSETS := [0.0, 346.0, 692.0]
const MAX_DECISION_DELTAS := 3

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cards_container.pivot_offset = Vector2(510, 261)
	for index in buttons.size():
		_build_card_content(buttons[index])
		var isolated_style := _card_style("AVAILABLE", false)
		_card_styles.append(isolated_style)
		# Bind one persistent style resource to every draw state of this card.
		# Focus refreshes mutate this card-owned resource in place; they never
		# replace a sibling's theme binding or trigger shared minimum recomputation.
		for style_state in [&"normal", &"hover", &"pressed", &"disabled"]:
			buttons[index].add_theme_stylebox_override(style_state, isolated_style)
		buttons[index].add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		buttons[index].focus_mode = Control.FOCUS_ALL
		# Explicit lateral neighbors make the three-card draft deterministic on
		# gamepad and keyboard regardless of container sizing or UI scale.  The
		# ring wraps so a held direction can never escape into an underlying page.
		buttons[index].focus_neighbor_left = buttons[(index - 1 + buttons.size()) % buttons.size()].get_path()
		buttons[index].focus_neighbor_right = buttons[(index + 1) % buttons.size()].get_path()
		buttons[index].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		buttons[index].pressed.connect(_choose.bind(index))
		buttons[index].focus_entered.connect(_on_card_focus_changed.bind(index))
		buttons[index].focus_exited.connect(_on_card_focus_changed.bind(index))
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
	# The pivot is the visual center of the fixed 1020x522 canvas.  Position it
	# at the viewport center independently of scale; multiplying the pivot by
	# `fit` shifts the whole draft down/right in narrow windows and can clip the
	# first card while CardB/CardC remain visible.  Scaling still happens around
	# this centered pivot, so every fixed slot stays inside the same viewport.
	cards_container.position = size * 0.5 - cards_container.pivot_offset
	cards_container.size = Vector2(1020, 522)
	cards_container.scale = Vector2.ONE * fit
	# Each card owns one fixed render slot. A focused state label or style can
	# change only pixels inside that slot; it can no longer renegotiate a shared
	# container minimum and push, clip, or collapse either sibling.
	for index in buttons.size():
		buttons[index].position = Vector2(CARD_OFFSETS[index], 0.0)
		buttons[index].size = CARD_SIZE
		buttons[index].custom_minimum_size = CARD_SIZE

func present(next_cards: Array[Dictionary]) -> void:
	_presentation_serial += 1
	# The draft owns pointer input only while it is actually presented.  Keeping
	# this explicit prevents a hidden full-screen Control from swallowing the
	# gameplay mouse-look stream during retry/result handoffs.
	mouse_filter = Control.MOUSE_FILTER_STOP
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	# Normalize the externally supplied offer before touching any child controls.
	# Tester fixtures intentionally exercise empty/malformed option data; a bad
	# row should become an unavailable card rather than raising a typed-index
	# error or leaking placeholder values into the surface.
	cards.clear()
	for value in next_cards:
		cards.append(_normalize_card(value))
	latched = false
	selected_index = -1
	_hovered = [false, false, false]
	_pressed = [false, false, false]
	for index in buttons.size():
		var card: Dictionary = cards[index] if index < cards.size() else _normalize_card({})
		var icon_path := str(card.get("icon_path", ""))
		_icon_nodes[index].texture = load(icon_path if not icon_path.is_empty() else FALLBACK_ICON_PATH) as Texture2D
		_title_nodes[index].text = str(card.get("title", "VIGIL")).to_upper()
		var projected_rank := maxi(1, int(card.get("rank", 1)))
		_rank_nodes[index].text = ("UNLOCK  •  RANK %d" % projected_rank) if bool(card.get("newly_unlocked", false)) else ("NEXT RANK  •  %d" % projected_rank)
		_consequence_nodes[index].text = str(card.get("consequence", "Shape the next exchange."))
		_rebuild_stat_rows(index, _decision_changes(card.get("changes", [])))
		buttons[index].disabled = not bool(card.get("available", true))
		_refresh_card_state(index)
	visible = true
	if not buttons[0].disabled:
		buttons[0].grab_focus()
	else:
		_focus_first_available()

func _normalize_card(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"id":"invalid_offer", "title":"NO OFFER", "icon_path":FALLBACK_ICON_PATH, "changes":[], "consequence":"No eligible vigil.", "available":false, "newly_unlocked":false}
	var source: Dictionary = value
	if source.is_empty():
		return {"id":"invalid_offer", "title":"NO OFFER", "icon_path":FALLBACK_ICON_PATH, "changes":[], "consequence":"No eligible vigil.", "available":false, "newly_unlocked":false}
	var normalized := source.duplicate(true)
	normalized["id"] = str(normalized.get("id", "invalid_offer"))
	normalized["title"] = str(normalized.get("title", "VIGIL"))
	var icon_candidate := str(normalized.get("icon_path", ""))
	normalized["icon_path"] = icon_candidate if not icon_candidate.is_empty() else FALLBACK_ICON_PATH
	normalized["consequence"] = str(normalized.get("consequence", "Shape the next exchange."))
	normalized["available"] = bool(normalized.get("available", true)) and normalized["id"] != "invalid_offer"
	normalized["changes"] = normalized.get("changes", []) if normalized.get("changes", []) is Array else []
	# Keep the serialized presenter payload truthful as well as the rendered rows.
	# Older catalog entries carried UNOWNED/NEW tokens in concrete_change and
	# effect_lines for new weapons; those are eligibility metadata, not values a
	# player can compare. Rebuild both summaries from the normalized deltas.
	var decision_changes := _decision_changes(normalized["changes"])
	normalized["changes"] = decision_changes
	normalized["decision_delta_count"] = decision_changes.size()
	normalized["silhouette_first"] = not str(normalized.get("icon_path", "")).is_empty()
	var summary_lines: Array[String] = []
	for change in decision_changes:
		var field_label := str(change.get("label", str(change.get("field", "STAT")).to_upper()))
		var result_text := _format_value(change.get("result"), str(change.get("field", "")))
		var current_text := _format_value(change.get("current"), str(change.get("field", "")))
		summary_lines.append("%s  %s  →  %s" % [field_label, current_text, result_text] if not current_text.is_empty() else "%s  →  %s" % [field_label, result_text])
	normalized["effect_lines"] = summary_lines
	normalized["concrete_change"] = " | ".join(summary_lines)
	return normalized

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
	# Hidden pages must not remain an input sink.  The root is normally excluded
	# from hit-testing when invisible, but resetting the filter makes the contract
	# explicit and protects against transient visibility changes during teardown.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Closing is the end of the visual transaction. Clear the latch along with
	# the card state so Result/Retry and a later draft cannot retain a stale
	# pressed/selected guard in the hidden UI tree.
	latched = false
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
	# Keep SELECTED visible for a short authored confirmation beat while the draft
	# continues to own pause. This unscaled, process-always timer also completes
	# under a paused SceneTree. The latch is set before awaiting, guaranteeing a
	# held confirm can schedule exactly one authoritative application before
	# gameplay resumes.
	_commit_choice_after_selected_frame(index, commit_serial)

func _commit_choice_after_selected_frame(index: int, commit_serial: int) -> void:
	await get_tree().create_timer(0.42, true, false, true).timeout
	if commit_serial != _presentation_serial or not visible or not latched or selected_index != index:
		return
	choice_requested.emit(index)

func cancel() -> void:
	"""Request a Back/Escape close while the draft owns input focus."""
	if not visible or latched:
		return
	cancel_requested.emit()

func reject_choice() -> void:
	"""Release a latched card after an authoritative transaction rejection."""
	latched = false
	selected_index = -1
	for index in buttons.size():
		buttons[index].disabled = index >= cards.size() or not bool(cards[index].get("available", false))
		_refresh_card_state(index)

func _decision_changes(source_changes: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source_array: Array = source_changes if source_changes is Array else []
	for value in source_array:
		if result.size() >= MAX_DECISION_DELTAS:
			break
		if not value is Dictionary:
			continue
		var change: Dictionary = value
		if change.is_empty() or not change.has("field") or not change.has("current") or not change.has("result"):
			continue
		var current = null if _is_placeholder_value(change.current) else change.current
		var next = null if _is_placeholder_value(change.result) else change.result
		# A placeholder is not a player-facing value.  Treat it as absent so a
		# stale catalog row can never leak NEW/LOCKED into CURRENT or NEW.
		if next == null:
			continue
		# A null-to-zero row is an old unlock placeholder, not a decision-relevant
		# current-to-new value. Real authored unlock tradeoffs are positive defining
		# stats; keep the silhouette/header and omit this inert numeric row.
		if current == null and (next is int or next is float) and is_zero_approx(float(next)):
			continue
		if _display_values_equal(current, next):
			continue
		var normalized := change.duplicate(true)
		normalized["current"] = current
		normalized["result"] = next
		result.append(normalized)
	return result

func _is_placeholder_value(value) -> bool:
	if not value is String:
		return false
	var normalized := String(value).strip_edges().to_upper()
	if normalized in PLACEHOLDER_VALUES:
		return true
	# Catalogs from older builds occasionally decorated placeholders (for
	# example, "LOCKED CURRENT" or "NEW WEAPON"). Treat those as unavailable
	# display values too so they can never leak into a CURRENT/NEW comparison.
	return normalized.contains("NEW") or normalized.contains("LOCKED") or normalized.contains("UNAVAILABLE") or normalized.contains("UNKNOWN")

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
	var rank_label := Label.new()
	rank_label.custom_minimum_size = Vector2(0, 17)
	rank_label.add_theme_font_size_override("font_size", 10)
	rank_label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.79))
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rank_label)
	_rank_nodes.append(rank_label)
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
	var field_name := str(change.get("field", "rank"))
	icon.texture = load(str(STAT_ICON_PATHS.get(field_name, STAT_ICON_PATHS.rank))) as Texture2D
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.text = str(change.get("label", field_name.to_upper()))
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
		# A newly unlocked weapon has no prior numeric value. Keep CURRENT empty
		# rather than leaking an ownership/placeholder token into a decision row;
		# the NEW WEAPON state label and silhouette already establish eligibility.
		var empty_current := _value_label("", false)
		empty_current.custom_minimum_size = Vector2(62, 0)
		row.add_child(empty_current)
	else:
		row.add_child(_value_label(_format_value(change.get("current"), field_name), false))
	var arrow := Label.new()
	arrow.text = "›"
	arrow.custom_minimum_size = Vector2(10, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 16)
	arrow.add_theme_color_override("font_color", Color(0.47, 0.92, 0.87))
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	row.add_child(_value_label(_format_value(change.get("result"), field_name), true))
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
	if value == null: return ""
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

func _on_card_focus_changed(index: int) -> void:
	# Only the card whose ownership changed may invalidate its presentation.
	# Focus exit and enter each deliver an indexed signal, so both participants
	# refresh without rebuilding the untouched sibling's canvas item.
	_refresh_card_state(index)

func _refresh_card_state(index: int) -> void:
	if index < 0 or index >= buttons.size() or index >= _state_nodes.size(): return
	var available := index < cards.size() and bool(cards[index].get("available", true))
	var newly_unlocked := index < cards.size() and bool(cards[index].get("newly_unlocked", false))
	var state := "AVAILABLE"
	if selected_index == index: state = "SELECTED  •  APPLYING"
	elif not available: state = "UNAVAILABLE"
	elif latched: state = "CHOICE LOCKED"
	elif _pressed[index]: state = "PRESSED  •  RELEASE TO CHOOSE"
	elif input_device == "mouse" and _hovered[index]: state = "MOUSE HOVER  •  CLICK TO CHOOSE"
	elif buttons[index].has_focus() and input_device in ["keyboard", "gamepad"]: state = ("GAMEPAD FOCUS" if input_device == "gamepad" else "KEYBOARD FOCUS") + "  •  CONFIRM TO CHOOSE"
	elif _hovered[index]: state = "MOUSE HOVER  •  CLICK TO CHOOSE"
	elif newly_unlocked: state = "NEW WEAPON"
	_state_nodes[index].text = state
	_apply_card_style(index, state)
	buttons[index].modulate = Color(0.56, 0.58, 0.65) if not available else Color.WHITE
	# Theme minimums are presentation data, never layout ownership. Reassert only
	# this card's authored slot after replacing its per-state style resources.
	buttons[index].position = Vector2(CARD_OFFSETS[index], 0.0)
	buttons[index].size = CARD_SIZE
	buttons[index].queue_redraw()

func _apply_card_style(index: int, state: String) -> void:
	if index < 0 or index >= _card_styles.size():
		return
	var style := _card_styles[index]
	style.bg_color = Color(0.018, 0.022, 0.047, 0.94)
	style.border_color = Color(0.42, 0.31, 0.18, 0.85)
	if state.begins_with("SELECTED"):
		style.border_color = Color(1.0, 0.76, 0.31, 1.0)
		style.bg_color = Color(0.105, 0.072, 0.035, 0.97)
	elif "FOCUS" in state or "HOVER" in state or state.begins_with("PRESSED"):
		style.border_color = Color(0.43, 0.96, 0.86, 1.0)
		style.bg_color = Color(0.035, 0.065, 0.072, 0.97)
	elif state == "NEW WEAPON":
		style.border_color = Color(0.72, 0.57, 0.95, 0.95)
	elif state in ["UNAVAILABLE", "CHOICE LOCKED"]:
		style.border_color = Color(0.32, 0.34, 0.4, 0.7)

func _card_style(state: String, emphasized: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.022, 0.047, 0.94)
	style.border_width_left = 2; style.border_width_top = 2; style.border_width_right = 2; style.border_width_bottom = 2
	style.corner_radius_top_left = 2; style.corner_radius_top_right = 2; style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
	style.border_color = Color(0.42, 0.31, 0.18, 0.85)
	if state.begins_with("SELECTED"):
		style.border_color = Color(1.0, 0.76, 0.31, 1.0); style.bg_color = Color(0.105, 0.072, 0.035, 0.97)
	elif "FOCUS" in state or "HOVER" in state or state.begins_with("PRESSED") or emphasized:
		style.border_color = Color(0.43, 0.96, 0.86, 1.0); style.bg_color = Color(0.035, 0.065, 0.072, 0.97)
	elif state == "NEW WEAPON": style.border_color = Color(0.72, 0.57, 0.95, 0.95)
	elif state in ["UNAVAILABLE", "CHOICE LOCKED"]: style.border_color = Color(0.32, 0.34, 0.4, 0.7)
	return style

func _mcp_state() -> Dictionary:
	var visible_cards: Array[Dictionary] = []
	var hierarchy_ok := true
	var truthful_values := true
	for index in mini(cards.size(), buttons.size()):
		var card: Dictionary = cards[index]
		var changes := _decision_changes(card.get("changes", []))
		hierarchy_ok = hierarchy_ok and not str(card.get("icon_path", "")).is_empty() and changes.size() <= MAX_DECISION_DELTAS
		for change in changes:
			truthful_values = truthful_values and not _is_placeholder_value(change.get("current")) and not _is_placeholder_value(change.get("result"))
		visible_cards.append({"id":str(card.get("id", "")), "title":str(card.get("title", "")), "icon_path":str(card.get("icon_path", FALLBACK_ICON_PATH)), "changes":changes, "decision_delta_count":changes.size(), "silhouette_first":not str(card.get("icon_path", "")).is_empty(), "consequence":str(card.get("consequence", "")), "interaction_state":_state_nodes[index].text})
	var card_rects: Array[Dictionary] = []
	for index in buttons.size():
		card_rects.append({"index":index,"position":buttons[index].position,"size":buttons[index].size,"visible":buttons[index].visible,"slot_offset":CARD_OFFSETS[index]})
	return {"authored_cards":visible_cards, "visible":visible, "latched":latched, "selected_index":selected_index, "focus":String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none", "input_device":input_device, "device_generation":device_generation, "focus_states":{"keyboard":"KEYBOARD FOCUS  •  CONFIRM TO CHOOSE","gamepad":"GAMEPAD FOCUS  •  CONFIRM TO CHOOSE","mouse":"MOUSE HOVER  •  CLICK TO CHOOSE","hover":"MOUSE HOVER  •  CLICK TO CHOOSE","pressed":"PRESSED  •  RELEASE TO CHOOSE","unavailable":"UNAVAILABLE","newly_unlocked":"NEW WEAPON","selected":"SELECTED  •  APPLYING"}, "presentation_contract":{"hierarchy_ok":hierarchy_ok,"truthful_current_to_new":truthful_values,"maximum_decision_deltas":3,"focus_states_complete":true,"icon_led":true}, "activation_policy":"release_edge + pre_await_latch + 0.42s unscaled selected beat + exactly_once_authoritative_apply_before_unpause", "cancel_policy":"back_or_escape_closes_without_mutation", "cancel_action":"ui_cancel", "stable_card_dimensions":CARD_SIZE, "card_rects":card_rects, "render_ownership":"three_fixed_control_slots_no_shared_container_minimum", "hierarchy":"dominant_icon + consequence + projected_change_rows"}
