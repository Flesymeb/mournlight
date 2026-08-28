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
	assert(upgrades.size() >= 14, "Mournlight requires at least fourteen authored upgrade definitions")
	var categories: Dictionary = {}
	for resource in upgrades:
		var upgrade := resource as MournlightUpgradeDefinition
		assert(upgrade != null, "Upgrade catalog contains an empty definition")
		assert(not seen.has(upgrade.upgrade_id), "Duplicate upgrade id: %s" % upgrade.upgrade_id)
		assert(upgrade.icon != null and not upgrade.icon.resource_path.is_empty(), "Upgrade icon is not bound: %s" % upgrade.upgrade_id)
		seen[upgrade.upgrade_id] = true
		categories[upgrade.category] = true
	assert(categories.has("economy"), "Upgrade catalog requires an authored pickup/experience economy choice")
	assert(categories.has("risk_reward"), "Upgrade catalog requires an authored risk/reward choice")
