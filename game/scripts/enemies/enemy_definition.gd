class_name EnemyProfile
extends Resource

@export var role_id := &"mossling"
@export var display_name := "Mossling"
@export var maximum_health := 90.0
@export var movement_speed := 2.25
@export var attack_range := 1.25
@export var attack_damage := 8.0
@export var telegraph_duration := 0.52
@export var recovery_duration := 0.85
@export var presentation_scale := 1.0
@export var separation_radius := 1.25
@export var accent_color := Color("7fd45b")
@export_enum("melee", "flank", "ranged", "slam") var attack_kind := "melee"
