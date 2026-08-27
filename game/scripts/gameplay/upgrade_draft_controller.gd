class_name UpgradeDraftController
extends Node

signal draft_opened(cards: Array[Dictionary])
signal draft_closed(choice: Dictionary)

const CATALOG := [
	{"id":"lantern_focus","title":"Focused Flame","description":"Lantern bolts deal +25% damage.","weapon":"warden_lantern"},
	{"id":"lantern_cadence","title":"Quick Wick","description":"Lantern cooldown is reduced.","weapon":"warden_lantern"},
	{"id":"lantern_range","title":"Long Vigil","description":"Lantern target range expands.","weapon":"warden_lantern"},
	{"id":"spade_unlock","title":"Gravespade","description":"Unlock the close spectral sweep.","weapon":"gravespade"},
	{"id":"spade_edge","title":"Moon-honed Edge","description":"Gravespade gains damage.","weapon":"gravespade"},
	{"id":"spade_reach","title":"Wide Burial","description":"Gravespade controls a wider area.","weapon":"gravespade"},
	{"id":"wisps_unlock","title":"Wandering Wisps","description":"Unlock three orbiting ward lights.","weapon":"wandering_wisps"},
	{"id":"wisps_orbit","title":"Restless Orbit","description":"Wisps orbit faster and strike harder.","weapon":"wandering_wisps"},
	{"id":"wisps_radius","title":"Procession Ring","description":"Wisp orbit radius expands.","weapon":"wandering_wisps"},
	{"id":"health_max","title":"Steady Heart","description":"Gain 15 maximum health and heal 15.","weapon":""},
	{"id":"dash_cooldown","title":"Moonstep","description":"Dash recovers 15% faster.","weapon":""},
	{"id":"recovery","title":"Last Ember","description":"Recover 20 health immediately.","weapon":""},
]

var ranks: Dictionary = {}
var offered: Array[Dictionary] = []
var selected: Array[Dictionary] = []
var draft_serial := 0
var active := false

func reset() -> void:
	ranks.clear()
	offered.clear()
	selected.clear()
	draft_serial = 0
	active = false

func open_draft() -> Array[Dictionary]:
	if active:
		return offered
	active = true
	draft_serial += 1
	offered.clear()
	var start := (draft_serial * 3 - 3) % CATALOG.size()
	for offset in 3:
		var card: Dictionary = CATALOG[(start + offset) % CATALOG.size()].duplicate(true)
		card["rank"] = int(ranks.get(card.id, 0)) + 1
		offered.append(card)
	draft_opened.emit(offered)
	return offered

func choose(index: int, inventory: WeaponInventory, health: WardenHealth, warden: WardenController) -> Dictionary:
	if not active or index < 0 or index >= offered.size():
		return {}
	var card: Dictionary = offered[index].duplicate(true)
	active = false
	ranks[card.id] = int(ranks.get(card.id, 0)) + 1
	selected.append(card)
	_apply(card, inventory, health, warden)
	draft_closed.emit(card)
	return card

func _apply(card: Dictionary, inventory: WeaponInventory, health: WardenHealth, warden: WardenController) -> void:
	var id := String(card.id)
	if id.ends_with("_unlock"):
		inventory.unlock_weapon(StringName(card.weapon))
	elif not String(card.weapon).is_empty():
		inventory.rank_up(StringName(card.weapon))
	elif id == "health_max":
		health.maximum_health += 15.0
		health.current_health = minf(health.maximum_health, health.current_health + 15.0)
	elif id == "recovery":
		health.current_health = minf(health.maximum_health, health.current_health + 20.0)
	elif id == "dash_cooldown":
		warden.cooldown_duration = maxf(0.42, warden.cooldown_duration * 0.85)

func get_snapshot() -> Dictionary:
	return {"active":active,"serial":draft_serial,"offered":offered,"selected":selected,"ranks":ranks}

