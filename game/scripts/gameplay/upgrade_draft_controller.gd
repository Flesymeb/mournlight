class_name UpgradeDraftController
extends Node

signal draft_opened(cards: Array[Dictionary])
signal draft_closed(choice: Dictionary)

const CATALOG: MournlightUpgradeCatalog = preload("res://resources/upgrades/mournlight_upgrade_catalog.tres")

var ranks: Dictionary = {}
var offered: Array[Dictionary] = []
var selected: Array[Dictionary] = []
var draft_serial := 0
var active := false

func _ready() -> void:
	CATALOG.validate_catalog()

func reset() -> void:
	ranks.clear()
	offered.clear()
	selected.clear()
	draft_serial = 0
	active = false

func open_draft(inventory: WeaponInventory, health: WardenHealth, warden: WardenController) -> Array[Dictionary]:
	if active:
		return offered
	var eligible: Array[MournlightUpgradeDefinition] = []
	for resource in CATALOG.upgrades:
		var upgrade := resource as MournlightUpgradeDefinition
		if upgrade.is_eligible(int(ranks.get(upgrade.upgrade_id, 0)), inventory):
			eligible.append(upgrade)
	if eligible.size() < 3:
		return []
	active = true
	draft_serial += 1
	offered.clear()
	var start := (draft_serial * 3 - 3) % eligible.size()
	for offset in 3:
		var definition := eligible[(start + offset) % eligible.size()]
		offered.append(definition.project(int(ranks.get(definition.upgrade_id, 0)), inventory, health, warden))
	draft_opened.emit(offered)
	return offered

func choose(index: int, inventory: WeaponInventory, health: WardenHealth, warden: WardenController) -> Dictionary:
	if not active or index < 0 or index >= offered.size():
		return {}
	var projection: Dictionary = offered[index].duplicate(true)
	var definition := CATALOG.get_by_id(StringName(projection.id))
	if not definition:
		return {}
	var application := definition.apply_projection(projection, inventory, health, warden)
	if not bool(application.accepted) or not bool(application.matches_projection):
		return {}
	active = false
	ranks[definition.upgrade_id] = int(ranks.get(definition.upgrade_id, 0)) + 1
	var choice := projection.duplicate(true)
	choice["application"] = application
	selected.append(choice)
	draft_closed.emit(choice)
	return choice

func get_snapshot() -> Dictionary:
	return {"active":active, "serial":draft_serial, "offered":offered.duplicate(true), "selected":selected.duplicate(true), "ranks":ranks.duplicate(true), "catalog_size":CATALOG.upgrades.size()}

func _mcp_state() -> Dictionary:
	var offer_digest: Array[Dictionary] = []
	for card in offered:
		offer_digest.append({"id":card.id, "title":card.title, "rank":card.rank, "icon_path":card.icon_path, "current":card.current, "result":card.result, "effect_lines":card.effect_lines})
	return {"authoritative_offer":offer_digest, "authoritative_selection":_selection_digest(), "active":active, "serial":draft_serial, "catalog_size":CATALOG.upgrades.size(), "ranks":ranks}

func _selection_digest() -> Dictionary:
	if selected.is_empty():
		return {}
	var card: Dictionary = selected[-1]
	var application: Dictionary = card.get("application", {})
	var post_weapon: Dictionary = {}
	if not String(card.get("weapon", "")).is_empty():
		for weapon in ((application.get("after", {}) as Dictionary).get("weapons", {}) as Dictionary).get("weapons", []):
			if String(weapon.get("weapon_id", "")) == String(card.weapon):
				post_weapon = weapon
				break
	return {"id":card.id, "current":card.current, "advertised_result":card.result, "effect_lines":card.effect_lines, "application_accepted":application.get("accepted", false), "matches_projection":application.get("matches_projection", false), "post_weapon":post_weapon}
