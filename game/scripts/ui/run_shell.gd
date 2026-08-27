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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	buttons = [$PrimaryButton, $SecondaryButton]
	for index in range(4):
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
	title_label.position = center + Vector2(-360,-84)
	title_label.size = Vector2(720,58)
	subtitle_label.position = center + Vector2(-340,-28)
	subtitle_label.size = Vector2(680,30)
	body_label.position = center + Vector2(-370,2)
	body_label.size = Vector2(740,76)
	var visible_count := 0
	for button in buttons:
		if button.visible:
			visible_count += 1
	var compact := visible_count >= 6
	var start_y := center.y + (84 if compact else 82)
	var spacing := 42 if compact else 54
	var button_height := 38 if compact else 44
	for index in buttons.size():
		var button := buttons[index]
		button.position = Vector2(center.x - 170, start_y + index * spacing)
		button.size = Vector2(340,button_height)

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
				"Authored cemetery, Warden and lantern sources are preserved with receipts.\nMontserrat typography: upstream font license retained.\nBellkeeper: Stylized Possessed Lantern, CC-BY-4.0.\nMenus: Maaack template mechanism, MIT. Audio: credited source library; see THIRD_PARTY_NOTICES.",
				[["back","BACK"]])
		"result":
			var won := String(summary.get("outcome","failure")) == "victory"
			var time := float(summary.get("elapsed",0.0))
			_configure("DAWN ANSWERS" if won else "FLAME EXTINGUISHED","VICTORY" if won else "THE WATCH ENDS",
				"%02d:%02d   WAVE %d / 5   LEVEL %d   BANISHED %d\nDAMAGE DEALT %d   TAKEN %d\n%s" % [int(time)/60,int(time)%60,int(summary.get("wave",1)),int(summary.get("level",1)),int(summary.get("defeated",0)),int(summary.get("damage_dealt",0)),int(summary.get("damage_taken",0)),_upgrade_summary(summary)],
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
			button.icon = ICONS.get(String(action))
			button.visible = true
			button.disabled = false
		else:
			button.visible = false

func _refresh_settings_page() -> void:
	var display := "FULLSCREEN" if int(setting_values.window_mode) == 1 else "WINDOWED"
	var access := "SHAKE %s  FLASH %s  NUMBERS %s  CONTRAST %s  BIAS %d" % [_onoff(setting_values.screen_shake),_onoff(setting_values.hit_flash),_onoff(setting_values.damage_numbers),_onoff(setting_values.danger_contrast),int(setting_values.target_bias)]
	_configure("SETTINGS","PERSISTED BETWEEN WATCHES","%s   UI %.0f%%\n%s" % [display,float(setting_values.ui_scale)*100.0,access],
		[["master","MASTER VOLUME  %d%%" % int(float(setting_values.master_volume)*100.0)],
		["music","MUSIC VOLUME  %d%%" % int(float(setting_values.music_volume)*100.0)],
		["effects","EFFECTS VOLUME  %d%%" % int(float(setting_values.effects_volume)*100.0)],
		["display","DISPLAY & UI SCALE"],["accessibility","ACCESSIBILITY & TARGETING"],["back","BACK"]])

func _on_button(index: int) -> void:
	if action_latched or index >= actions.size():
		return
	var action := actions[index]
	if action in [&"master",&"music",&"effects"]:
		var key := String(action) + "_volume"
		var next := fmod(float(setting_values[key]) + 0.2, 1.01)
		setting_values[key] = next
		settings.set_value(key,next)
		_refresh_settings_page()
		return
	if action == &"display":
		setting_values.window_mode = 1 - int(setting_values.window_mode)
		setting_values.ui_scale = 1.25 if float(setting_values.ui_scale) < 1.1 else 0.9 if float(setting_values.ui_scale) > 1.1 else 1.0
		settings.set_value("window_mode",setting_values.window_mode)
		settings.set_value("ui_scale",setting_values.ui_scale)
		_refresh_settings_page()
		return
	if action == &"accessibility":
		for key in ["screen_shake","hit_flash","damage_numbers","danger_contrast"]:
			setting_values[key] = not bool(setting_values[key])
			settings.set_value(key,setting_values[key])
		setting_values.target_bias = (int(setting_values.target_bias)+1)%3
		settings.set_value("target_bias",setting_values.target_bias)
		_refresh_settings_page()
		return
	if action == &"back":
		if return_mode == "title":
			action_requested.emit(&"title")
		else:
			set_mode(return_mode,summary)
		return
	action_latched = true
	action_requested.emit(action)

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO,size),SHADE,true)
	var center := size*0.5
	draw_circle(center+Vector2(0,-174),48,Color(0.03,0.045,0.11,0.96))
	draw_arc(center+Vector2(0,-174),48,0,TAU,48,BRASS,3,true)
	draw_circle(center+Vector2(-4,-176),27,Color("d4def6"))
	draw_circle(center+Vector2(9,-184),24,Color("101733"))
	draw_line(center+Vector2(-230,-105),center+Vector2(230,-105),BRASS,2,true)

func _upgrade_summary(data: Dictionary) -> String:
	var upgrades: Array = data.get("selected_upgrades",[])
	return "NO UPGRADES" if upgrades.is_empty() else "VIGILS: " + ", ".join(upgrades.map(func(item: Dictionary) -> String:return String(item.get("title",""))))

func _onoff(value: Variant) -> String:
	return "ON" if bool(value) else "OFF"

func _mcp_state() -> Dictionary:
	return {"mode":mode,"visible":visible,"focus":String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none","actions":actions,"settings":setting_values,"summary":summary}
