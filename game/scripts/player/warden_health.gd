class_name WardenHealth
extends HealthComponent

signal failed(event: Dictionary)

@export var post_hit_invulnerability := 0.72
var invulnerability_remaining := 0.0
var rejected_damage_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	invulnerability_remaining = maxf(0.0, invulnerability_remaining - delta)

func apply_damage(event: Dictionary) -> Dictionary:
	var warden := get_parent() as WardenController
	if (warden and warden.dash_invulnerable) or invulnerability_remaining > 0.0:
		rejected_damage_count += 1
		return {"accepted": false, "rejection_reason": "warden_invulnerable"}
	var resolved: Dictionary = super.apply_damage(event)
	if bool(resolved.get("accepted", false)):
		invulnerability_remaining = post_hit_invulnerability
		if current_health <= 0.0:
			failed.emit(resolved)
	return resolved

func reset_warden_health() -> void:
	invulnerability_remaining = 0.0
	rejected_damage_count = 0
	reset_health()

func _mcp_state() -> Dictionary:
	var state := super._mcp_state()
	state.invulnerability_remaining = invulnerability_remaining
	state.rejected_damage_count = rejected_damage_count
	return state
