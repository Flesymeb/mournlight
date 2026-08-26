extends Control

@export var glow_color := Color("ffba4c")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, 25.0, Color(0.04, 0.045, 0.075, 0.92))
	draw_arc(center, 24.0, 0.0, TAU, 32, Color("8b6734"), 3.0, true)
	draw_arc(center, 18.0, 0.0, TAU, 32, Color(1.0, 0.71, 0.28, 0.3), 2.0, true)
	var flame := PackedVector2Array([
		center + Vector2(0, -15), center + Vector2(9, 3), center + Vector2(4, 14),
		center + Vector2(-6, 13), center + Vector2(-10, 3)
	])
	draw_colored_polygon(flame, Color(glow_color, 0.92))
	draw_circle(center + Vector2(1, 5), 5.0, Color("fff1b0"))
	draw_line(center + Vector2(-16, -21), center + Vector2(16, -21), Color("c39a58"), 3.0, true)
	draw_arc(center + Vector2(0, -20), 8.0, PI, TAU, 12, Color("c39a58"), 3.0, true)
