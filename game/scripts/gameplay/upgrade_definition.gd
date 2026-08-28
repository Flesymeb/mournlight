class_name MournlightUpgradeDefinition
extends Resource

@export var upgrade_id: StringName
@export var title := ""
@export var category := "lantern"
@export_enum("weapon_rank", "health_max", "dash_cooldown", "recovery", "pickup_economy", "risk_reward") var action := "weapon_rank"
@export var max_rank := 1
@export var weapon_id: StringName = &"warden_lantern"
@export var required_weapon_rank := -1
@export var icon: Texture2D

const STAT_FIELDS := ["damage", "cooldown", "range", "area", "count", "duration", "hit_interval"]
const STAT_LABELS := {"damage":"DAMAGE", "cooldown":"COOLDOWN", "range":"RANGE", "area":"AREA", "count":"COUNT", "duration":"DURATION", "hit_interval":"HIT INTERVAL"}

func is_eligible(current_upgrade_rank: int, inventory: WeaponInventory) -> bool:
	if current_upgrade_rank >= max_rank:
		return false
	if action != "weapon_rank":
		return true
	var current_weapon_rank := inventory.get_rank(weapon_id)
	var definition := inventory.get_definition(weapon_id)
	return definition != null and current_weapon_rank == required_weapon_rank and current_weapon_rank < definition.max_rank

func project(current_upgrade_rank: int, inventory: WeaponInventory, health: WardenHealth, warden: WardenController) -> Dictionary:
	var projection := {
		"id": String(upgrade_id), "title": title, "category": category,
		"rank": current_upgrade_rank + 1, "rank_label": "R%d" % (current_upgrade_rank + 1),
		"action": action, "weapon": String(weapon_id),
		"icon_path": icon.resource_path if icon else "", "changes": [],
	}
	match action:
		"weapon_rank": _project_weapon(projection, inventory)
		"health_max": _project_health_max(projection, health)
		"dash_cooldown": _project_dash(projection, warden)
		"recovery": _project_recovery(projection, health)
		"pickup_economy": _project_pickup_economy(projection, warden)
		"risk_reward": _project_risk_reward(projection, inventory, health)
	projection["effect_lines"] = _effect_lines(projection.changes)
	projection["concrete_change"] = " | ".join(projection.effect_lines)
	projection["consequence"] = _consequence_line(projection)
	projection["available"] = true
	projection["newly_unlocked"] = action == "weapon_rank" and int((projection.get("current", {}) as Dictionary).get("rank", 0)) == 0
	return projection

func apply_projection(projection: Dictionary, inventory: WeaponInventory, health: WardenHealth, warden: WardenController) -> Dictionary:
	var before := _authoritative_state(inventory, health, warden)
	var accepted := false
	match action:
		"weapon_rank":
			accepted = inventory.apply_rank_projection(weapon_id, int(projection.result.rank), int(projection.current.rank))
		"health_max":
			if is_equal_approx(health.current_health, float(projection.current.health)) and is_equal_approx(health.maximum_health, float(projection.current.health_maximum)):
				health.maximum_health = float(projection.result.health_maximum)
				health.current_health = float(projection.result.health)
				accepted = true
		"dash_cooldown":
			if is_equal_approx(warden.cooldown_duration, float(projection.current.dash_cooldown)):
				warden.cooldown_duration = float(projection.result.dash_cooldown)
				accepted = true
		"recovery":
			if is_equal_approx(health.current_health, float(projection.current.health)) and is_equal_approx(health.maximum_health, float(projection.current.health_maximum)):
				health.current_health = float(projection.result.health)
				accepted = true
		"pickup_economy":
			if is_equal_approx(warden.pickup_collection_radius, float(projection.current.pickup_collection_radius)) and is_equal_approx(warden.experience_yield_multiplier, float(projection.current.experience_yield_multiplier)):
				warden.pickup_collection_radius = float(projection.result.pickup_collection_radius)
				warden.experience_yield_multiplier = float(projection.result.experience_yield_multiplier)
				accepted = true
		"risk_reward":
			var health_matches := is_equal_approx(health.current_health, float(projection.current.health)) and is_equal_approx(health.maximum_health, float(projection.current.health_maximum))
			if health_matches and inventory.apply_damage_multiplier_projection(float(projection.result.global_damage_multiplier), float(projection.current.global_damage_multiplier)):
				health.maximum_health = float(projection.result.health_maximum)
				health.current_health = float(projection.result.health)
				accepted = true
	var after := _authoritative_state(inventory, health, warden)
	return {"accepted": accepted, "before": before, "advertised_result": projection.result.duplicate(true), "after": after, "matches_projection": accepted and _result_matches(projection.result, after)}

func _project_weapon(projection: Dictionary, inventory: WeaponInventory) -> void:
	var definition := inventory.get_definition(weapon_id)
	var current_rank := inventory.get_rank(weapon_id)
	var next_rank := current_rank + 1
	var before_stats := inventory.get_stats(weapon_id) if current_rank > 0 else {}
	var after_stats := inventory.get_stats_for_rank(weapon_id, next_rank)
	projection["current"] = {"equipped": inventory.is_equipped(weapon_id), "rank": current_rank, "stats": before_stats}
	projection["result"] = {"equipped": true, "rank": next_rank, "stats": after_stats}
	var changes: Array[Dictionary] = []
	if current_rank == 0:
		changes.append({"field":"equipped", "label":"WEAPON", "current":"LOCKED", "result":"EQUIPPED"})
	changes.append({"field":"rank", "label":"WEAPON RANK", "current":current_rank, "result":next_rank})
	for field in STAT_FIELDS:
		var current_value = before_stats.get(field, null)
		var result_value = after_stats.get(field, null)
		if current_rank == 0 or not _values_equal(current_value, result_value):
			changes.append({"field":field, "label":STAT_LABELS[field], "current":current_value, "result":result_value})
	projection["changes"] = changes

func _project_health_max(projection: Dictionary, health: WardenHealth) -> void:
	projection["current"] = {"health":health.current_health, "health_maximum":health.maximum_health}
	projection["result"] = {"health":minf(health.maximum_health + 15.0, health.current_health + 15.0), "health_maximum":health.maximum_health + 15.0}
	projection["changes"] = [
		{"field":"health_maximum", "label":"MAX HEALTH", "current":health.maximum_health, "result":projection.result.health_maximum},
		{"field":"health", "label":"HEALTH", "current":health.current_health, "result":projection.result.health},
	]

func _project_dash(projection: Dictionary, warden: WardenController) -> void:
	projection["current"] = {"dash_cooldown":warden.cooldown_duration}
	projection["result"] = {"dash_cooldown":maxf(0.42, warden.cooldown_duration * 0.85)}
	projection["changes"] = [{"field":"dash_cooldown", "label":"DASH COOLDOWN", "current":warden.cooldown_duration, "result":projection.result.dash_cooldown}]

func _project_recovery(projection: Dictionary, health: WardenHealth) -> void:
	projection["current"] = {"health":health.current_health, "health_maximum":health.maximum_health}
	projection["result"] = {"health":minf(health.maximum_health, health.current_health + 20.0), "health_maximum":health.maximum_health}
	projection["changes"] = [{"field":"health", "label":"HEALTH", "current":health.current_health, "result":projection.result.health}]

func _project_pickup_economy(projection: Dictionary, warden: WardenController) -> void:
	projection["current"] = {
		"pickup_collection_radius":warden.pickup_collection_radius,
		"experience_yield_multiplier":warden.experience_yield_multiplier,
	}
	projection["result"] = {
		"pickup_collection_radius":minf(2.2, warden.pickup_collection_radius + 0.35),
		"experience_yield_multiplier":minf(1.6, warden.experience_yield_multiplier + 0.2),
	}
	projection["changes"] = [
		{"field":"pickup_collection_radius", "label":"PICKUP REACH", "current":warden.pickup_collection_radius, "result":projection.result.pickup_collection_radius},
		{"field":"experience_yield_multiplier", "label":"EXPERIENCE YIELD", "current":warden.experience_yield_multiplier, "result":projection.result.experience_yield_multiplier},
	]

func _project_risk_reward(projection: Dictionary, inventory: WeaponInventory, health: WardenHealth) -> void:
	var next_multiplier := minf(1.6, inventory.global_damage_multiplier + 0.2)
	var next_maximum := maxf(55.0, health.maximum_health - 12.0)
	projection["current"] = {
		"global_damage_multiplier":inventory.global_damage_multiplier,
		"health":health.current_health,
		"health_maximum":health.maximum_health,
	}
	projection["result"] = {
		"global_damage_multiplier":next_multiplier,
		"health":minf(health.current_health, next_maximum),
		"health_maximum":next_maximum,
	}
	projection["changes"] = [
		{"field":"global_damage_multiplier", "label":"WEAPON DAMAGE", "current":inventory.global_damage_multiplier, "result":next_multiplier},
		{"field":"health_maximum", "label":"MAX HEALTH COST", "current":health.maximum_health, "result":next_maximum},
	]

func _effect_lines(changes: Array) -> Array[String]:
	var lines: Array[String] = []
	for change in changes:
		lines.append("%s  %s  →  %s" % [change.label, _format_value(change.current, String(change.field)), _format_value(change.result, String(change.field))])
	return lines

func _consequence_line(projection: Dictionary) -> String:
	match action:
		"weapon_rank":
			if int((projection.get("current", {}) as Dictionary).get("rank", 0)) == 0:
				return "Add a new attack pattern to the vigil."
			match weapon_id:
				&"warden_lantern": return "Make each focused bolt more decisive."
				&"gravespade": return "Carve a safer lane at close range."
				&"wandering_wisps": return "Strengthen the orbiting control ring."
		"health_max": return "Hold the line through one more heavy hit."
		"dash_cooldown": return "Recover Moonstep sooner between threats."
		"recovery": return "Restore strength without changing the build."
		"pickup_economy": return "Gather more wisps from a safer distance."
		"risk_reward": return "Trade endurance for sharper weapon damage."
	return "Shape the next exchange."

func _format_value(value, field: String) -> String:
	if value == null:
		return "—"
	if value is String:
		return value
	if field in ["count", "rank"]:
		return str(int(value))
	if field in ["cooldown", "duration", "hit_interval", "dash_cooldown"]:
		return "%.2fs" % float(value)
	if field in ["experience_yield_multiplier", "global_damage_multiplier"]:
		return "×%.2f" % float(value)
	if field == "pickup_collection_radius":
		return "%.2fm" % float(value)
	return "%.1f" % float(value) if not is_equal_approx(float(value), roundf(float(value))) else str(int(roundf(float(value))))

func _values_equal(a, b) -> bool:
	if a == null or b == null:
		return a == b
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b

func _authoritative_state(inventory: WeaponInventory, health: WardenHealth, warden: WardenController) -> Dictionary:
	return {
		"weapons":inventory.get_snapshot(),
		"health":health.current_health,
		"health_maximum":health.maximum_health,
		"dash_cooldown":warden.cooldown_duration,
		"pickup_collection_radius":warden.pickup_collection_radius,
		"experience_yield_multiplier":warden.experience_yield_multiplier,
		"global_damage_multiplier":inventory.global_damage_multiplier,
	}

func _result_matches(expected: Dictionary, after: Dictionary) -> bool:
	if action == "weapon_rank":
		for weapon in (after.weapons.get("weapons", []) as Array):
			if String(weapon.weapon_id) == String(weapon_id):
				return bool(weapon.equipped) == bool(expected.equipped) and int(weapon.rank) == int(expected.rank) and (weapon.stats as Dictionary).recursive_equal(expected.stats, 0)
		return false
	for key in expected:
		if not after.has(key) or not _values_equal(expected[key], after[key]):
			return false
	return true
