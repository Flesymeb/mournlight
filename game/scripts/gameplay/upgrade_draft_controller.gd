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
var offer_strategy := "three_weapon_lanes"
var offer_slots: Array[Dictionary] = []
var last_selection_receipt: Dictionary = {}
var selection_generation := 0

func _ready() -> void:
	CATALOG.validate_catalog()

func reset() -> void:
	ranks.clear()
	offered.clear()
	selected.clear()
	draft_serial = 0
	active = false
	offer_slots.clear()
	last_selection_receipt.clear()
	selection_generation = 0

func cancel() -> bool:
	"""Close the current offer without mutating ranks or the selected build.

	The draft is a paused decision surface, so Back/Escape must have a
	deterministic, transaction-safe route back to gameplay.  Keeping the rank
	ledger intact allows the pending level-up to be offered again later.
	"""
	if not active:
		return false
	active = false
	offered.clear()
	offer_slots.clear()
	return true

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
	offer_slots.clear()
	var chosen: Array[MournlightUpgradeDefinition] = []
	# One truthful next step from each weapon lane keeps all three identities
	# naturally reachable. Exhausted lanes deterministically yield to utility.
	for weapon_id in [&"warden_lantern", &"gravespade", &"wandering_wisps"]:
		for definition in eligible:
			if definition.action == "weapon_rank" and definition.weapon_id == weapon_id:
				chosen.append(definition)
				offer_slots.append({"slot":chosen.size() - 1, "lane":String(weapon_id), "upgrade_id":String(definition.upgrade_id)})
				break
	var utility: Array[MournlightUpgradeDefinition] = []
	for definition in eligible:
		if not chosen.has(definition):
			utility.append(definition)
	var utility_start := (draft_serial - 1) % maxi(1, utility.size())
	for offset in utility.size():
		if chosen.size() >= 3:
			break
		var definition := utility[(utility_start + offset) % utility.size()]
		chosen.append(definition)
		offer_slots.append({"slot":chosen.size() - 1, "lane":"utility", "upgrade_id":String(definition.upgrade_id)})
	if chosen.size() < 3:
		active = false
		return []
	for definition in chosen:
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
	selection_generation += 1
	last_selection_receipt = {
		"generation": selection_generation,
		"draft_serial": draft_serial,
		"id": String(choice.get("id", "")),
		"rank": int(choice.get("rank", 0)),
		"applied_modifier": choice.get("changes", []),
		"application_accepted": bool(application.get("accepted", false)),
		"matches_projection": bool(application.get("matches_projection", false)),
		"exactly_once": true,
		"transaction":"authoritative_choice_commit",
	}
	# The authoritative offer is a transient transaction payload. Retire it as
	# soon as the choice commits so runtime snapshots cannot report a stale,
	# still-actionable draft while the run has already resumed. The selected
	# projection above remains the durable build receipt for Result and retry
	# handoff.
	offered.clear()
	offer_slots.clear()
	draft_closed.emit(choice)
	return choice

func get_snapshot() -> Dictionary:
	return {"active":active, "serial":draft_serial, "offered":offered.duplicate(true), "selected":selected.duplicate(true), "ranks":ranks.duplicate(true), "catalog_size":CATALOG.upgrades.size(), "offer_strategy":offer_strategy, "offer_slots":offer_slots.duplicate(true), "last_selection_receipt":last_selection_receipt.duplicate(true), "selection_generation":selection_generation}

func _mcp_state() -> Dictionary:
	var offer_digest: Array[Dictionary] = []
	for card in offered:
		offer_digest.append({"id":card.id, "title":card.title, "rank":card.rank, "icon_path":card.icon_path, "current":card.current, "result":card.result, "effect_lines":card.effect_lines})
	return {"authoritative_offer":offer_digest, "authoritative_selection":_selection_digest(), "active":active, "serial":draft_serial, "catalog_size":CATALOG.upgrades.size(), "ranks":ranks, "offer_strategy":offer_strategy, "offer_slots":offer_slots.duplicate(true), "last_selection_receipt":last_selection_receipt.duplicate(true), "selection_generation":selection_generation}

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
	return {
		"id":card.id,
		"rank":int(card.get("rank", 0)),
		"current":card.current,
		"advertised_result":card.result,
		"effect_lines":card.effect_lines,
		"applied_modifier":card.get("changes", []),
		"application_accepted":application.get("accepted", false),
		"matches_projection":application.get("matches_projection", false),
		"post_weapon":post_weapon,
	}
