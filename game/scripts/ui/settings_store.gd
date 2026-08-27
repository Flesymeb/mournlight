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

func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for key in DEFAULTS:
			values[key] = config.get_value("settings", key, DEFAULTS[key])
	apply()
	return values.duplicate(true)

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = value
	apply()
	var config := ConfigFile.new()
	for stored_key in values:
		config.set_value("settings", stored_key, values[stored_key])
	config.save(PATH)

func apply() -> void:
	_set_bus("Master", float(values.master_volume))
	_set_bus("Music", float(values.music_volume))
	_set_bus("Effects", float(values.effects_volume))
	var mode := int(values.window_mode)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if mode == 1 else DisplayServer.WINDOW_MODE_WINDOWED)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.content_scale_factor = clampf(float(values.ui_scale), 0.9, 1.25)
		tree.root.set_meta("mournlight_screen_shake", bool(values.screen_shake))
		tree.root.set_meta("mournlight_hit_flash", bool(values.hit_flash))
		tree.root.set_meta("mournlight_damage_numbers", bool(values.damage_numbers))
		tree.root.set_meta("mournlight_danger_contrast", bool(values.danger_contrast))
	TargetSelector.configure_bias(int(values.target_bias))

func _set_bus(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.001, 1.0)))
