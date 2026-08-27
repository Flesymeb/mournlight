class_name RunShellView
extends Control

signal action_requested(action: StringName)

const FONT_BOLD := preload("res://assets/fonts/Montserrat-Bold.ttf")
const FONT_MEDIUM := preload("res://assets/fonts/Montserrat-Medium.ttf")
const ICONS := {
	"play":preload("res://assets/ui/icon_play.svg"), "resume":preload("res://assets/ui/icon_resume.svg"),
	"settings":preload("res://assets/ui/icon_settings.svg"), "credits":preload("res://assets/ui/icon_book.svg"),
	"quit":preload("res://assets/ui/icon_quit.svg"), "retry":preload("res://assets/ui/icon_restart.svg"),
	"title":preload("res://assets/ui/icon_title.svg"), "back":preload("res://assets/ui/icon_resume.svg"),
}
const SHADE := Color(0.004,0.007,0.025,0.88)
const BRASS := Color("b78442")
const GOLD := Color("ffd173")
const SILVER := Color("aebbd8")

var mode := "title"
var return_mode := "title"
var summary: Dictionary = {}
var action_latched := false
var buttons: Array[Button] = []
var actions: Array[StringName] = []
var title_label: Label
var subtitle_label: Label
var body_label: Label
var settings := MournlightSettingsStore.new()
var setting_values: Dictionary
var last_setting_mutation: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	buttons = [$PrimaryButton, $SecondaryButton]
	for index in range(10):
		var button := Button.new()
		button.name = "ActionButton%d" % (index + 3)
		button.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(button)
		buttons.append(button)
	for index in buttons.size():
		var button := buttons[index]
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_button.bind(index))
	_build_labels()
	setting_values = settings.load_settings()
	set_mode("title")

func _build_labels() -> void:
	title_label = Label.new()
	title_label.add_theme_font_override("font", FONT_BOLD)
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", GOLD)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.add_theme_font_override("font", FONT_MEDIUM)
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.add_theme_color_override("font_color", SILVER)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(subtitle_label)
	body_label = Label.new()
	body_label.add_theme_font_override("font", FONT_MEDIUM)
	body_label.add_theme_font_size_override("font_size", 14)
	body_label.add_theme_color_override("font_color", Color("e7ecff"))
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(body_label)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(title_label):
		_layout()

func _layout() -> void:
	var center := size * 0.5
	var page_top := maxf(78.0, center.y - 266.0)
	title_label.position = Vector2(center.x - 360,page_top)
	title_label.size = Vector2(720,58)
	subtitle_label.position = Vector2(center.x - 340,page_top + 54)
	subtitle_label.size = Vector2(680,30)
	body_label.position = Vector2(center.x - 400,page_top + 86)
	body_label.size = Vector2(800,190 if mode == "credits" else 150 if mode == "result" else 56)
	var visible_count := 0
	for button in buttons:
		if button.visible:
			visible_count += 1
	if mode == "settings":
		var start_y := page_top + 154
		for index in buttons.size():
			var button := buttons[index]
			button.position = Vector2(center.x - 360 + (index % 2) * 370, start_y + (index / 2) * 54)
			button.size = Vector2(350,42)
		return
	var compact := visible_count >= 5
	var start_y := page_top + (315 if mode == "credits" else 255 if mode == "result" else 184)
	var spacing := 48 if compact else 56
	var button_height := 42 if compact else 46
	for index in buttons.size():
		var button := buttons[index]
		button.position = Vector2(center.x - 180, start_y + index * spacing)
		button.size = Vector2(360,button_height)

func set_mode(next_mode: String, next_summary: Dictionary = {}) -> void:
	if next_mode == "settings" or next_mode == "credits":
		return_mode = mode if mode in ["title","pause"] else "title"
	mode = next_mode
	summary = next_summary.duplicate(true)
	action_latched = false
	visible = mode != "hidden"
	match mode:
		"title":
			_configure("MOURNLIGHT","THE CEMETERY GARDEN STIRS","Keep an escape lane. Let the lantern choose its mark.",
				[["play","PLAY"],["settings","SETTINGS"],["credits","CREDITS & NOTICES"],["quit","QUIT"]])
		"pause":
			_configure("NIGHT HELD","THE WARDEN'S FLAME WAITS","The run is paused; no combat clock is advancing.",
				[["resume","RESUME"],["settings","SETTINGS"],["retry","RESTART RUN"],["title","RETURN TO TITLE"],["quit","QUIT"]])
		"settings":
			_refresh_settings_page()
		"credits":
			_configure("CREDITS & NOTICES","MOURNLIGHT — RELEASE CANDIDATE",
				"MOURNLIGHT — DESIGN, CODE & CEMETERY GARDEN\nAuthored production assembled for this release candidate.\n\nMontserrat typography — SIL Open Font License.\nBellkeeper / possessed lantern — CC BY 4.0.\nMaaack menu navigation mechanism — MIT.\nAudio sources — credited library; see THIRD_PARTY_NOTICES.\n\nThank you for keeping the last lantern lit.",
				[["back","BACK"]])
		"result":
			var won := String(summary.get("outcome","failure")) == "victory"
			var time := float(summary.get("elapsed",0.0))
			_configure("DAWN ANSWERS" if won else "FLAME EXTINGUISHED","VICTORY" if won else "THE WATCH ENDS",
				"TIME  %02d:%02d     WAVE  %d / %d     LEVEL  %d     BANISHED  %d\nDAMAGE DEALT  %d     DAMAGE TAKEN  %d\n\nARSENAL  %s\nVIGILS  %s" % [int(time)/60,int(time)%60,int(summary.get("wave",1)),int(summary.get("wave_count",5)),int(summary.get("level",1)),int(summary.get("defeated",0)),int(summary.get("damage_dealt",0)),int(summary.get("damage_taken",0)),_weapon_summary(summary),_upgrade_summary(summary)],
				[["retry","RETRY"],["title","RETURN TO TITLE"]])
		"draft":
			_configure("CHOOSE A VIGIL","THE NIGHT HOLDS ITS BREATH","Select one upgrade. The choice applies before combat resumes.",[])
	if visible and not buttons.is_empty():
		for button in buttons:
			if button.visible:
				button.grab_focus()
				break
	_layout()
	queue_redraw()

func _configure(title: String, subtitle: String, body: String, entries: Array) -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	body_label.text = body
	actions.clear()
	for index in buttons.size():
		var button := buttons[index]
		if index < entries.size():
			var entry: Array = entries[index]
			var action := StringName(entry[0])
			actions.append(action)
			button.text = String(entry[1])
			button.icon = ICONS.get(String(action), ICONS.settings)
			button.visible = true
			button.disabled = false
		else:
			button.visible = false
	for index in actions.size():
		var button := buttons[index]
		var previous := buttons[(index - 1 + actions.size()) % actions.size()]
		var next := buttons[(index + 1) % actions.size()]
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(next)
		if mode == "settings":
			button.focus_neighbor_left = button.get_path_to(buttons[index - 1] if index % 2 == 1 else button)
			button.focus_neighbor_right = button.get_path_to(buttons[index + 1] if index % 2 == 0 and index + 1 < actions.size() else button)

func _refresh_settings_page() -> void:
	var display := "FULLSCREEN" if int(setting_values.window_mode) == 1 else "WINDOWED"
	_configure("SETTINGS","ONE CONTROL · ONE PERSISTED CHOICE","Audio, display, feedback and targeting update independently.",
		[["master","MASTER VOLUME  %d%%" % int(float(setting_values.master_volume)*100.0)],
		["music","MUSIC VOLUME  %d%%" % int(float(setting_values.music_volume)*100.0)],
		["effects","EFFECTS VOLUME  %d%%" % int(float(setting_values.effects_volume)*100.0)],
		["window_mode","WINDOW  %s" % display],["ui_scale","UI SCALE  %.0f%%" % (float(setting_values.ui_scale)*100.0)],
		["screen_shake","SCREEN SHAKE  %s" % _onoff(setting_values.screen_shake)],
		["hit_flash","HIT FLASH  %s" % _onoff(setting_values.hit_flash)],
		["damage_numbers","DAMAGE NUMBERS  %s" % _onoff(setting_values.damage_numbers)],
		["danger_contrast","DANGER CONTRAST  %s" % _onoff(setting_values.danger_contrast)],
		["target_bias","TARGETING  %s" % ("DIRECTIONAL" if int(setting_values.target_bias) == 1 else "AUTOMATIC")],
		["back","BACK"]])

func _on_button(index: int) -> void:
	if action_latched or index >= actions.size():
		return
	var action := actions[index]
	if action in [&"master",&"music",&"effects"]:
		var key := String(action) + "_volume"
		var before: Variant = setting_values[key]
		var next := fmod(float(setting_values[key]) + 0.2, 1.01)
		setting_values[key] = next
		settings.set_value(key,next)
		last_setting_mutation = {"key":key,"before":before,"after":next}
		_refresh_settings_page()
		return
	if action == &"window_mode":
		var before := int(setting_values.window_mode)
		setting_values.window_mode = 1 - before
		settings.set_value("window_mode",setting_values.window_mode)
		last_setting_mutation = {"key":"window_mode","before":before,"after":setting_values.window_mode}
		_refresh_settings_page()
		return
	if action == &"ui_scale":
		var before := float(setting_values.ui_scale)
		var choices := [0.9,1.0,1.25]
		var choice_index := choices.find(before)
		setting_values.ui_scale = choices[(choice_index+1)%choices.size()]
		settings.set_value("ui_scale",setting_values.ui_scale)
		last_setting_mutation = {"key":"ui_scale","before":before,"after":setting_values.ui_scale}
		_refresh_settings_page()
		return
	if action in [&"screen_shake",&"hit_flash",&"damage_numbers",&"danger_contrast"]:
		var key := String(action)
		var before := bool(setting_values[key])
		setting_values[key] = not before
		settings.set_value(key,setting_values[key])
		last_setting_mutation = {"key":key,"before":before,"after":setting_values[key]}
		_refresh_settings_page()
		return
	if action == &"target_bias":
		var before := int(setting_values.target_bias)
		setting_values.target_bias = 1-before
		settings.set_value("target_bias",setting_values.target_bias)
		last_setting_mutation = {"key":"target_bias","before":before,"after":setting_values.target_bias}
		_refresh_settings_page()
		return
	if action in [&"settings",&"credits",&"back"]:
		action_requested.emit(action)
		return
	action_latched = true
	action_requested.emit(action)

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO,size),SHADE,true)
	var center := size*0.5
	var page_top := maxf(78.0,center.y-266.0)
	var seal := Vector2(maxf(74.0,center.x-470.0),page_top+30.0)
	draw_circle(seal,38,Color(0.03,0.045,0.11,0.96))
	draw_arc(seal,38,0,TAU,40,BRASS,3,true)
	draw_circle(seal+Vector2(-3,-2),21,Color("d4def6"))
	draw_circle(seal+Vector2(8,-8),19,Color("101733"))
	draw_line(Vector2(center.x-230,page_top+132),Vector2(center.x+230,page_top+132),BRASS,2,true)

func _upgrade_summary(data: Dictionary) -> String:
	var upgrades: Array = data.get("selected_upgrades",[])
	return "NONE SELECTED" if upgrades.is_empty() else ", ".join(upgrades.map(func(item: Dictionary) -> String:return "%s %s" % [String(item.get("title",item.get("upgrade_id","VIGIL"))),String(item.get("rank_label",item.get("concrete_change","")))]))

func _weapon_summary(data: Dictionary) -> String:
	var build: Dictionary = data.get("weapons",{})
	var rows: Array[String] = []
	for weapon in build.get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			var stats: Dictionary = weapon.get("stats",{})
			rows.append("%s R%d" % [String(stats.get("display_name",weapon.get("weapon_id","WEAPON"))).to_upper(),int(weapon.get("rank",1))])
	return "WARDEN LANTERN R1" if rows.is_empty() else "  ·  ".join(rows)

func _onoff(value: Variant) -> String:
	return "ON" if bool(value) else "OFF"

func _mcp_state() -> Dictionary:
	return {"mode":mode,"return_mode":return_mode,"visible":visible,"action_latched":action_latched,"displayed_result_fields":_displayed_result_fields(),"focus":String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none","actions":actions,"settings":setting_values,"last_setting_mutation":last_setting_mutation}

func _displayed_result_fields() -> Dictionary:
	if mode != "result": return {}
	var weapon_ranks: Array[Dictionary] = []
	for weapon in (summary.get("weapons",{}) as Dictionary).get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			weapon_ranks.append({"weapon_id":weapon.get("weapon_id",""),"rank":weapon.get("rank",0)})
	return {"outcome":summary.get("outcome","failure"),"elapsed":summary.get("elapsed",0.0),"wave":summary.get("wave",1),"level":summary.get("level",1),"defeated":summary.get("defeated",0),"damage_dealt":summary.get("damage_dealt",0),"damage_taken":summary.get("damage_taken",0),"weapon_ranks":weapon_ranks,"selected_upgrades":summary.get("selected_upgrades",[])}
