class_name RunSnapshot
extends RefCounted

static func make(controller: Node, world: Node, warden: Node, health: Node, spawner: Node, inventory: Node) -> Dictionary:
	var health_current := float(health.current_health) if health else 0.0
	var health_maximum := float(health.maximum_health) if health else 0.0
	return {
		"serial": int(controller.run_serial),
		"state": String(controller.run_state),
		"elapsed": float(controller.run_elapsed),
		"health": health_current,
		"health_maximum": health_maximum,
		"experience": int(controller.experience),
		"experience_threshold": int(controller.experience_threshold),
		"level": int(controller.level),
		"defeated": int(controller.defeated_enemies),
		"damage_taken": int(controller.damage_taken),
		"encounter": spawner.get_snapshot() if spawner else {},
		"weapons": inventory.get_snapshot() if inventory else {},
		"dash_phase": String(warden.dash_phase) if warden else "ready",
		"dash_remaining": float(warden.dash_cooldown_remaining) if warden else 0.0,
		"dash_duration": float(warden.cooldown_duration) if warden else 1.0,
		"boss_active": false,
		"boss_health": 0.0,
		"boss_health_maximum": 0.0,
		"world_active": world.session_active if world else false,
	}
