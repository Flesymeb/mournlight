class_name UpgradeDraftView
extends Control

signal choice_requested(index: int)

var cards: Array[Dictionary] = []
var latched := false
var _icon_nodes: Array[TextureRect] = []
var _title_nodes: Array[Label] = []
var _rank_nodes: Array[Label] = []
var _effect_nodes: Array[Label] = []
@onready var buttons: Array[Button] = [$Cards/CardA, $Cards/CardB, $Cards/CardC]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in buttons.size():
		_build_card_content(buttons[index])
		buttons[index].pressed.connect(_choose.bind(index))
		buttons[index].focus_entered.connect(_set_card_focus.bind(index, true))
		buttons[index].focus_exited.connect(_set_card_focus.bind(index, false))
	visible = false

func present(next_cards: Array[Dictionary]) -> void:
	cards = next_cards.duplicate(true)
	latched = false
	visible = true
	for index in buttons.size():
		var card: Dictionary = cards[index]
		_icon_nodes[index].texture = load(String(card.icon_path)) as Texture2D
		_title_nodes[index].text = String(card.title).to_upper()
		_rank_nodes[index].text = "%s  •  %s" % [String(card.rank_label), String(card.category).to_upper()]
		_effect_nodes[index].text = "\n".join(card.effect_lines)
	buttons[0].grab_focus()

func close() -> void:
	visible = false
	cards.clear()
	for index in buttons.size():
		_set_card_focus(index, false)

func _choose(index: int) -> void:
	if latched or index >= cards.size():
		return
	latched = true
	choice_requested.emit(index)

func _build_card_content(button: Button) -> void:
	button.text = ""
	button.clip_contents = false
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 88)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)
	_icon_nodes.append(icon)
	var divider := HSeparator.new()
	divider.modulate = Color(0.78, 0.58, 0.25, 0.85)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(divider)
	var title_label := Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.48))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_label)
	_title_nodes.append(title_label)
	var rank_label := Label.new()
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 12)
	rank_label.add_theme_color_override("font_color", Color(0.45, 0.93, 0.88))
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rank_label)
	_rank_nodes.append(rank_label)
	var effect_label := Label.new()
	effect_label.custom_minimum_size = Vector2(0, 126)
	effect_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	effect_label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.98))
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(effect_label)
	_effect_nodes.append(effect_label)

func _set_card_focus(index: int, focused: bool) -> void:
	if index < 0 or index >= buttons.size():
		return
	var button := buttons[index]
	if not is_instance_valid(button):
		return
	var tween := button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.025, 1.025) if focused else Vector2.ONE, 0.12)
	tween.parallel().tween_property(button, "modulate", Color(1.08, 1.04, 0.96) if focused else Color.WHITE, 0.12)

func _mcp_state() -> Dictionary:
	var visible_cards: Array[Dictionary] = []
	for card in cards:
		visible_cards.append({"id":card.id, "title":card.title, "rank_label":card.rank_label, "icon_path":card.icon_path, "effect_lines":card.effect_lines})
	return {"authored_cards":visible_cards, "visible":visible, "latched":latched, "focus":String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none"}
