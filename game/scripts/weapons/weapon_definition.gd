class_name WeaponDefinition
extends Resource

@export var weapon_id := &"weapon.none"
@export var display_name := "Unnamed Weapon"
@export_enum("focused_bolt", "threat_sweep", "persistent_orbit") var strategy := "focused_bolt"
@export var base_damage := 10.0
@export var base_cooldown := 1.0
@export var base_range := 8.0
@export var base_area := 1.0
@export var base_count := 1
@export var base_duration := 0.0
@export var base_hit_interval := 0.0
@export var max_rank := 4
@export var rank_modifiers: Array[Dictionary] = []

func stats_for_rank(requested_rank: int) -> Dictionary:
	var rank := clampi(requested_rank, 1, max_rank)
	var stats := {
		"weapon_id": String(weapon_id),
		"display_name": display_name,
		"strategy": strategy,
		"rank": rank,
		"damage": base_damage,
		"cooldown": base_cooldown,
		"range": base_range,
		"area": base_area,
		"count": base_count,
		"duration": base_duration,
		"hit_interval": base_hit_interval,
	}
	for index in range(mini(rank - 1, rank_modifiers.size())):
		_apply_modifier(stats, rank_modifiers[index])
	stats.damage = maxf(0.1, float(stats.damage))
	stats.cooldown = clampf(float(stats.cooldown), 0.12, 8.0)
	stats.range = clampf(float(stats.range), 0.5, 40.0)
	stats.area = clampf(float(stats.area), 0.2, 12.0)
	stats.count = clampi(int(stats.count), 1, 8)
	stats.duration = clampf(float(stats.duration), 0.0, 30.0)
	stats.hit_interval = clampf(float(stats.hit_interval), 0.12, 6.0) if float(stats.hit_interval) > 0.0 else 0.0
	return stats

func _apply_modifier(stats: Dictionary, modifier: Dictionary) -> void:
	# Deterministic stacking: additive fields first, then multipliers.
	for key in ["damage", "cooldown", "range", "area", "count", "duration", "hit_interval"]:
		var add_key: String = String(key) + "_add"
		if modifier.has(add_key):
			stats[key] = float(stats[key]) + float(modifier[add_key])
	for key in ["damage", "cooldown", "range", "area", "duration", "hit_interval"]:
		var multiply_key: String = String(key) + "_mult"
		if modifier.has(multiply_key):
			stats[key] = float(stats[key]) * float(modifier[multiply_key])
