class_name WeaponInventory
extends Node

signal build_changed(snapshot: Dictionary)

@export var definitions: Array[WeaponDefinition] = []
@export var equipped_weapon_ids: Array[StringName] = [&"warden_lantern"]

var _ranks: Dictionary = {&"warden_lantern": 1}
var global_damage_multiplier := 1.0

func _ready() -> void:
	_validate_unique_ids()

func get_definition(weapon_id: StringName) -> WeaponDefinition:
	for definition in definitions:
		if definition and definition.weapon_id == weapon_id:
			return definition
	return null

func is_equipped(weapon_id: StringName) -> bool:
	return equipped_weapon_ids.has(weapon_id)

func get_rank(weapon_id: StringName) -> int:
	return int(_ranks.get(weapon_id, 0))

func get_stats(weapon_id: StringName) -> Dictionary:
	return get_stats_for_rank(weapon_id, maxi(1, get_rank(weapon_id)))

func get_stats_for_rank(weapon_id: StringName, rank: int) -> Dictionary:
	var definition := get_definition(weapon_id)
	if not definition:
		return {}
	var stats := definition.stats_for_rank(rank)
	if stats.has("damage"):
		stats["damage"] = snappedf(float(stats.damage) * global_damage_multiplier, 0.1)
	stats["global_damage_multiplier"] = global_damage_multiplier
	return stats

func prepare_legal_build(profile: String = "representative") -> Dictionary:
	var before := get_snapshot()
	global_damage_multiplier = 1.0
	equipped_weapon_ids.clear()
	_ranks.clear()
	for definition in definitions:
		if not definition:
			continue
		if profile == "wisps_only" and definition.weapon_id != &"wandering_wisps":
			continue
		equipped_weapon_ids.append(definition.weapon_id)
		_ranks[definition.weapon_id] = definition.max_rank if profile in ["representative", "wisps_only"] else 1
	var after := get_snapshot()
	build_changed.emit({"profile": profile, "before": before, "after": after})
	return {"profile": profile, "before": before, "after": after}

func reset_starting_build() -> void:
	equipped_weapon_ids = [&"warden_lantern"]
	_ranks = {&"warden_lantern": 1}
	global_damage_multiplier = 1.0
	build_changed.emit(get_snapshot())

func apply_damage_multiplier_projection(result_multiplier: float, expected_current: float) -> bool:
	if not is_equal_approx(global_damage_multiplier, expected_current):
		return false
	if result_multiplier <= expected_current or result_multiplier > 1.6:
		return false
	global_damage_multiplier = result_multiplier
	build_changed.emit(get_snapshot())
	return true

func unlock_weapon(weapon_id: StringName) -> void:
	if not equipped_weapon_ids.has(weapon_id) and get_definition(weapon_id):
		equipped_weapon_ids.append(weapon_id)
	_ranks[weapon_id] = maxi(1, int(_ranks.get(weapon_id, 0)))
	build_changed.emit(get_snapshot())

func rank_up(weapon_id: StringName) -> void:
	var definition := get_definition(weapon_id)
	if not definition:
		return
	if not equipped_weapon_ids.has(weapon_id):
		equipped_weapon_ids.append(weapon_id)
	_ranks[weapon_id] = mini(definition.max_rank, maxi(1, int(_ranks.get(weapon_id, 0))) + 1)
	build_changed.emit(get_snapshot())

func apply_rank_projection(weapon_id: StringName, result_rank: int, expected_current_rank: int) -> bool:
	var definition := get_definition(weapon_id)
	if not definition or get_rank(weapon_id) != expected_current_rank:
		return false
	if result_rank != expected_current_rank + 1 or result_rank < 1 or result_rank > definition.max_rank:
		return false
	if not equipped_weapon_ids.has(weapon_id):
		equipped_weapon_ids.append(weapon_id)
	_ranks[weapon_id] = result_rank
	build_changed.emit(get_snapshot())
	return true

func get_snapshot() -> Dictionary:
	var weapons: Array[Dictionary] = []
	for definition in definitions:
		if definition:
			weapons.append({
				"weapon_id": String(definition.weapon_id),
				"equipped": is_equipped(definition.weapon_id),
				"rank": get_rank(definition.weapon_id),
				"stats": get_stats(definition.weapon_id),
			})
	return {"equipped_weapon_ids": equipped_weapon_ids.duplicate(), "weapons": weapons,
		"global_damage_multiplier":global_damage_multiplier,
		"build_identity":_build_identity(weapons)}

func _build_identity(weapons: Array[Dictionary]) -> Dictionary:
	var lanes: Array[Dictionary] = []
	var dominant := "starting_lantern"
	var dominant_rank := -1
	for weapon in weapons:
		if not bool(weapon.get("equipped", false)):
			continue
		var stats: Dictionary = weapon.get("stats", {})
		var lane := {
			"weapon_id":String(weapon.get("weapon_id", "")),
			"rank":int(weapon.get("rank", 0)),
			"strategy":String(stats.get("strategy", "")),
		}
		lanes.append(lane)
		if int(lane.rank) > dominant_rank:
			dominant_rank = int(lane.rank)
			dominant = String(lane.strategy)
	return {"dominant_shape":dominant,"dominant_rank":dominant_rank,"lanes":lanes,
		"supported_shapes":["focused_bolt","threat_sweep","persistent_orbit"]}

func _validate_unique_ids() -> void:
	var seen: Dictionary = {}
	for definition in definitions:
		assert(definition != null, "Weapon inventory contains an empty definition")
		assert(not seen.has(definition.weapon_id), "Duplicate weapon id: %s" % definition.weapon_id)
		seen[definition.weapon_id] = true

func _mcp_state() -> Dictionary:
	return get_snapshot()
