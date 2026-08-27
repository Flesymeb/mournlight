class_name UpgradeDraftView
extends Control

signal choice_requested(index: int)
var cards: Array[Dictionary] = []
var latched := false
@onready var buttons: Array[Button] = [$Cards/CardA,$Cards/CardB,$Cards/CardC]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in buttons.size():
		buttons[index].pressed.connect(_choose.bind(index))
	visible = false

func present(next_cards: Array[Dictionary]) -> void:
	cards = next_cards.duplicate(true)
	latched = false
	visible = true
	for index in buttons.size():
		var card: Dictionary = cards[index]
		buttons[index].text = "%s\nRANK %d\n%s" % [String(card.title).to_upper(),int(card.rank),String(card.description)]
	buttons[0].grab_focus()

func close() -> void:
	visible = false
	cards.clear()

func _choose(index: int) -> void:
	if latched or index >= cards.size():
		return
	latched = true
	choice_requested.emit(index)

func _mcp_state() -> Dictionary:
	return {"visible":visible,"latched":latched,"cards":cards,"focus":String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none"}

