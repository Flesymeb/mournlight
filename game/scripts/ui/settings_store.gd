class_name MournlightSettingsStore
extends RefCounted

const PATH := "user://mournlight_settings.cfg"
const DEFAULTS := {
	"master_volume": 0.82, "music_volume": 0.68, "effects_volume": 0.86,
	"window_mode": 0, "ui_scale": 1.0, "screen_shake": true,
	"hit_flash": true, "damage_numbers": true, "danger_contrast": true,
	"target_bias": 0,
}

var values: Dictionary = DEFAULTS.duplicate(true)
var apply_generation := 0
var persisted_generation := 0
var last_apply_receipt: Dictionary = {}
var last_persist_receipt: Dictionary = {}

func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	var load_status := config.load(PATH)
	if load_status == OK:
		for key in DEFAULTS:
			values[key] = config.get_value("settings", key, DEFAULTS[key])
		persisted_generation = int(config.get_value("meta", "generation", 0))
	apply()
	last_persist_receipt = {
		"path": PATH,
		"loaded": load_status == OK,
		"generation": persisted_generation,
		"keys": values.keys(),
		"transaction":"reload_then_apply",
	}
	return values.duplicate(true)

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = value
	apply()
	var config := ConfigFile.new()
	for stored_key in values:
		config.set_value("settings", stored_key, values[stored_key])
	config.set_value("meta", "generation", persisted_generation + 1)
	var save_status := config.save(PATH)
	if save_status == OK:
		persisted_generation += 1
	last_persist_receipt = {
		"path": PATH,
		"saved": save_status == OK,
		"generation": persisted_generation,
		"keys": values.keys(),
		"last_key": key,
		"transaction":"mutate_apply_persist",
	}
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.set_meta("mournlight_settings_persistence_receipt", last_persist_receipt.duplicate(true))

func reload_settings() -> Dictionary:
	"""Reload persisted values and re-apply them for retry/title transitions."""
	return load_settings()

func apply() -> void:
	_set_bus("Master", float(values.master_volume))
	_set_bus("Music", float(values.music_volume))
	_set_bus("Effects", float(values.effects_volume))
	apply_generation += 1
	var mode := int(values.window_mode)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if mode == 1 else DisplayServer.WINDOW_MODE_WINDOWED)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.content_scale_factor = clampf(float(values.ui_scale), 0.9, 1.25)
		tree.root.set_meta("mournlight_screen_shake", bool(values.screen_shake))
		tree.root.set_meta("mournlight_hit_flash", bool(values.hit_flash))
		tree.root.set_meta("mournlight_damage_numbers", bool(values.damage_numbers))
		tree.root.set_meta("mournlight_danger_contrast", bool(values.danger_contrast))
		last_apply_receipt = {
			"apply_generation":apply_generation,
			"configured_linear":{
				"Master":float(values.master_volume),
				"Music":float(values.music_volume),
				"Effects":float(values.effects_volume),
			},
			"resolved_buses":{
				"Master":_bus_receipt(&"Master"),
				"Music":_bus_receipt(&"Music"),
				"Effects":_bus_receipt(&"Effects"),
			},
		}
		last_apply_receipt["settings_persistence"] = last_persist_receipt.duplicate(true)
		tree.root.set_meta("mournlight_audio_settings_receipt", last_apply_receipt.duplicate(true))
	TargetSelector.configure_bias(int(values.target_bias))

func _set_bus(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.001, 1.0)))

func _bus_receipt(bus_name: StringName) -> Dictionary:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return {"name":String(bus_name), "index":-1, "present":false}
	return {
		"name":AudioServer.get_bus_name(index), "index":index, "present":true,
		"send":String(AudioServer.get_bus_send(index)),
		"volume_db":AudioServer.get_bus_volume_db(index),
		"volume_linear":AudioServer.get_bus_volume_linear(index),
		"mute":AudioServer.is_bus_mute(index),
		"bypass_effects":AudioServer.is_bus_bypassing_effects(index),
	}
