class_name MournlightUpgradeCatalog
extends Resource

@export var upgrades: Array[Resource] = []

func get_by_id(upgrade_id: StringName) -> MournlightUpgradeDefinition:
	for resource in upgrades:
		var upgrade := resource as MournlightUpgradeDefinition
		if upgrade and upgrade.upgrade_id == upgrade_id:
			return upgrade
	return null

func validate_catalog() -> void:
	var seen: Dictionary = {}
	assert(upgrades.size() == 12, "Mournlight requires exactly twelve upgrade definitions")
	for resource in upgrades:
		var upgrade := resource as MournlightUpgradeDefinition
		assert(upgrade != null, "Upgrade catalog contains an empty definition")
		assert(not seen.has(upgrade.upgrade_id), "Duplicate upgrade id: %s" % upgrade.upgrade_id)
		assert(upgrade.icon != null and not upgrade.icon.resource_path.is_empty(), "Upgrade icon is not bound: %s" % upgrade.upgrade_id)
		seen[upgrade.upgrade_id] = true
