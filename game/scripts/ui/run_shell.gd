class_name RunShellView
extends Control

signal action_requested(action: StringName)

@onready var primary_button: Button = $PrimaryButton
@onready var secondary_button: Button = $SecondaryButton

var mode := "title"
var summary: Dictionary = {}
var action_latched := false

const INK := Color("e7ecff")
const SILVER := Color("aab8d7")
const BRASS := Color("b78442")
const GOLD := Color("ffd173")
const SHADE := Color(0.008, 0.012, 0.038, 0.86)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	primary_button.pressed.connect(_on_primary_pressed)
	secondary_button.pressed.connect(_on_secondary_pressed)
	set_mode("title")

func set_mode(next_mode: String, next_summary: Dictionary = {}) -> void:
	mode = next_mode
	summary = next_summary.duplicate(true)
	action_latched = false
	visible = mode != "hidden"
	primary_button.visible = visible
	secondary_button.visible = mode in ["pause", "result"]
	match mode:
		"title":
			primary_button.text = "PLAY"
			secondary_button.visible = false
		"pause":
			primary_button.text = "RESUME"
			secondary_button.text = "RETURN TO TITLE"
		"result":
			primary_button.text = "RETRY"
			secondary_button.text = "TITLE"
	if visible:
		primary_button.grab_focus()
	queue_redraw()

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), SHADE, true)
	var center := size * 0.5
	_draw_moon_seal(center + Vector2(0, -184), 58.0)
	draw_line(center + Vector2(-210, -104), center + Vector2(210, -104), BRASS, 2.0, true)
	match mode:
		"title":
			_draw_centered("MOURNLIGHT", center + Vector2(0, -54), 42, GOLD, 520)
			_draw_centered("THE CEMETERY GARDEN STIRS", center + Vector2(0, -17), 14, SILVER, 480)
			_draw_centered("Keep an escape lane. Let the lantern choose its mark.", center + Vector2(0, 33), 15, INK, 580)
		"pause":
			_draw_centered("NIGHT HELD", center + Vector2(0, -54), 38, GOLD, 520)
			_draw_centered("THE WARDEN'S FLAME WAITS", center + Vector2(0, -12), 13, SILVER, 480)
		"result":
			_draw_centered("FLAME EXTINGUISHED", center + Vector2(0, -54), 34, GOLD, 580)
			var time := float(summary.get("elapsed", 0.0))
			_draw_centered("WATCH %02d:%02d     LEVEL %d     BANISHED %d" % [int(time) / 60, int(time) % 60, int(summary.get("level", 1)), int(summary.get("defeated", 0))], center + Vector2(0, -7), 14, INK, 620)
			_draw_centered("DAMAGE TAKEN  %d" % int(summary.get("damage_taken", 0)), center + Vector2(0, 25), 12, SILVER, 420)
	draw_line(center + Vector2(-210, 82), center + Vector2(210, 82), Color(BRASS, 0.65), 1.0, true)

func _draw_moon_seal(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color(0.035, 0.05, 0.11, 0.96))
	draw_arc(center, radius, 0.0, TAU, 48, BRASS, 3.0, true)
	draw_circle(center, radius * 0.62, SILVER)
	draw_circle(center + Vector2(radius * 0.27, -radius * 0.17), radius * 0.53, Color("111937"))
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius + 7.0), center + direction * (radius + 19.0), GOLD, 3.0, true)

func _draw_centered(value: String, baseline: Vector2, font_size: int, color: Color, width: float) -> void:
	draw_string(ThemeDB.fallback_font, baseline - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

func _on_primary_pressed() -> void:
	if action_latched:
		return
	action_latched = true
	match mode:
		"title": action_requested.emit(&"play")
		"pause": action_requested.emit(&"resume")
		"result": action_requested.emit(&"retry")

func _on_secondary_pressed() -> void:
	if action_latched:
		return
	action_latched = true
	action_requested.emit(&"title")

func _mcp_state() -> Dictionary:
	return {"mode": mode, "visible": visible, "focus": String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none", "action_latched": action_latched, "summary": summary}
