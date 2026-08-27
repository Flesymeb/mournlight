class_name WeaponInventory
extends Node

signal build_changed(snapshot: Dictionary)

@export var definitions: Array[WeaponDefinition] = []
@export var equipped_weapon_ids: Array[StringName] = [&"warden_lantern"]

var _ranks: Dictionary = {&"warden_lantern": 1}

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
	var definition := get_definition(weapon_id)
	if not definition:
		return {}
	return definition.stats_for_rank(maxi(1, get_rank(weapon_id)))

func prepare_legal_build(profile: String = "representative") -> Dictionary:
	var before := get_snapshot()
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
	build_changed.emit(get_snapshot())

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
	return {"equipped_weapon_ids": equipped_weapon_ids.duplicate(), "weapons": weapons}

func _validate_unique_ids() -> void:
	var seen: Dictionary = {}
	for definition in definitions:
		assert(definition != null, "Weapon inventory contains an empty definition")
		assert(not seen.has(definition.weapon_id), "Duplicate weapon id: %s" % definition.weapon_id)
		seen[definition.weapon_id] = true

func _mcp_state() -> Dictionary:
	return get_snapshot()
