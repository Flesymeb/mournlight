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
	"help":preload("res://assets/ui/icon_book.svg"),
	"master":preload("res://assets/ui/upgrades/health_max.svg"),
	"music":preload("res://assets/ui/upgrades/lantern_cadence.svg"),
	"effects":preload("res://assets/ui/upgrades/wisps_orbit.svg"),
	"window_mode":preload("res://assets/ui/icon_settings.svg"),
	"ui_scale":preload("res://assets/ui/upgrades/lantern_focus.svg"),
	"screen_shake":preload("res://assets/ui/upgrades/dash_cooldown.svg"),
	"hit_flash":preload("res://assets/ui/upgrades/recovery.svg"),
	"damage_numbers":preload("res://assets/ui/upgrades/spade_edge.svg"),
	"danger_contrast":preload("res://assets/ui/upgrades/lantern_range.svg"),
	"target_bias":preload("res://assets/ui/upgrades/wisps_radius.svg"),
}
const WEAPON_ICONS := {
	"warden_lantern":preload("res://assets/ui/upgrades/lantern_focus.svg"),
	"gravespade":preload("res://assets/ui/upgrades/spade_unlock.svg"),
	"wandering_wisps":preload("res://assets/ui/upgrades/wisps_unlock.svg"),
}
const SETTING_GROUPS := [
	{"title":"AUDIO", "caption":"MIX", "actions":["master","music","effects"]},
	{"title":"DISPLAY", "caption":"VIEW", "actions":["window_mode","ui_scale"]},
	{"title":"FEEDBACK", "caption":"MOTION & IMPACT", "actions":["screen_shake","hit_flash","damage_numbers"]},
	{"title":"ACCESSIBILITY", "caption":"READABILITY", "actions":["danger_contrast"]},
	{"title":"TARGETING", "caption":"AUTOMATIC AIM", "actions":["target_bias"]},
]
const SHADE := Color(0.004,0.007,0.025,0.88)
const BRASS := Color("b78442")
const GOLD := Color("ffd173")
const SILVER := Color("aebbd8")

var mode := "title"
var return_mode := "title"
var summary: Dictionary = {}
var action_latched := false
var action_generation := 0
var last_action_receipt: Dictionary = {}
var buttons: Array[Button] = []
var actions: Array[StringName] = []
var title_label: Label
var subtitle_label: Label
var body_label: Label
var setting_group_labels: Array[Label] = []
var result_cards: Array[Panel] = []
var result_upgrade_panel: Panel
var result_upgrade_icon: TextureRect
var result_upgrade_label: Label
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
	_build_setting_groups()
	_build_result_presentation()
	setting_values = settings.load_settings()
	set_mode("title")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and mode in ["settings", "help", "credits"]:
		_record_shell_action(&"back", false)
		action_requested.emit(&"back")
		get_viewport().set_input_as_handled()

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

func _build_setting_groups() -> void:
	for group in SETTING_GROUPS:
		var label := Label.new()
		label.add_theme_font_override("font", FONT_BOLD)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", GOLD)
		label.text = "%s   ·   %s" % [group.title, group.caption]
		label.visible = false
		add_child(label)
		setting_group_labels.append(label)

func _build_result_presentation() -> void:
	for index in range(3):
		var card := Panel.new()
		card.visible = false
		card.add_theme_stylebox_override("panel", _result_card_style(index))
		var icon := TextureRect.new()
		icon.name = "WeaponIcon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon)
		var name_label := _result_label("WeaponName", 13, GOLD)
		card.add_child(name_label)
		var rank_label := _result_label("WeaponRank", 11, SILVER)
		card.add_child(rank_label)
		var value_label := _result_label("WeaponValue", 11, Color("e7ecff"))
		card.add_child(value_label)
		add_child(card)
		result_cards.append(card)
	result_upgrade_panel = Panel.new()
	result_upgrade_panel.visible = false
	result_upgrade_panel.add_theme_stylebox_override("panel", _upgrade_panel_style())
	result_upgrade_icon = TextureRect.new()
	result_upgrade_icon.texture = ICONS.credits
	result_upgrade_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_upgrade_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_upgrade_panel.add_child(result_upgrade_icon)
	result_upgrade_label = _result_label("UpgradeSummary", 12, Color("e7ecff"))
	result_upgrade_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_upgrade_label.max_lines_visible = 3
	result_upgrade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_upgrade_panel.add_child(result_upgrade_label)
	add_child(result_upgrade_panel)

func _result_label(label_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_font_override("font", FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

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
	var body_height := 190.0 if mode == "credits" else 154.0 if mode == "help" else 66.0 if mode == "result" else 56.0
	body_label.size = Vector2(800,body_height)
	var visible_count := 0
	for button in buttons:
		if button.visible:
			visible_count += 1
	if mode == "settings":
		_layout_settings(center, page_top)
		return
	if mode == "result":
		_layout_result(center, page_top)
		return
	var compact := visible_count >= 5
	var start_y := page_top + (360 if mode == "credits" else 350 if mode == "help" else 255 if mode == "result" else 184)
	var spacing := 48 if compact else 56
	var button_height := 42 if compact else 46
	for index in buttons.size():
		var button := buttons[index]
		button.position = Vector2(center.x - 180, start_y + index * spacing)
		button.size = Vector2(360,button_height)

func _layout_settings(center: Vector2, page_top: float) -> void:
	var left_x := center.x - 374.0
	var right_x := center.x + 18.0
	var group_layout := [
		{"x":left_x, "y":page_top + 142.0},
		{"x":right_x, "y":page_top + 142.0},
		{"x":left_x, "y":page_top + 294.0},
		{"x":right_x, "y":page_top + 254.0},
		{"x":right_x, "y":page_top + 334.0},
	]
	for index in setting_group_labels.size():
		var header := setting_group_labels[index]
		header.position = Vector2(group_layout[index].x, group_layout[index].y)
		header.size = Vector2(356,22)
	var action_positions := {
		"master":Vector2(left_x,page_top+166), "music":Vector2(left_x,page_top+206),
		"effects":Vector2(left_x,page_top+246), "window_mode":Vector2(right_x,page_top+166),
		"ui_scale":Vector2(right_x,page_top+206), "screen_shake":Vector2(left_x,page_top+318),
		"hit_flash":Vector2(left_x,page_top+358), "damage_numbers":Vector2(left_x,page_top+398),
		"danger_contrast":Vector2(right_x,page_top+278), "target_bias":Vector2(right_x,page_top+358),
		"back":Vector2(right_x,page_top+418),
	}
	for index in actions.size():
		var action := String(actions[index])
		var button := buttons[index]
		button.position = action_positions.get(action, Vector2(left_x,page_top+418))
		button.size = Vector2(356,34 if action != "back" else 38)

func _layout_result(center: Vector2, page_top: float) -> void:
	var visible_cards := result_cards.filter(func(card: Panel) -> bool: return card.visible)
	var card_width := 214.0
	var gap := 16.0
	if not visible_cards.is_empty():
		card_width = minf(card_width, maxf(132.0, (size.x - 64.0 - gap * float(visible_cards.size() - 1)) / float(visible_cards.size())))
	var total_width := visible_cards.size() * card_width + maxi(0,visible_cards.size()-1) * gap
	for index in visible_cards.size():
		var card: Panel = visible_cards[index]
		card.position = Vector2(center.x-total_width*0.5+index*(card_width+gap),page_top+154)
		card.size = Vector2(card_width,108)
		var icon := card.get_node("WeaponIcon") as TextureRect
		icon.position = Vector2(12,16); icon.size = Vector2(66,72)
		var name_label := card.get_node("WeaponName") as Label
		name_label.position = Vector2(82,13); name_label.size = Vector2(124,36)
		var rank_label := card.get_node("WeaponRank") as Label
		rank_label.position = Vector2(82,47); rank_label.size = Vector2(124,20)
		var value_label := card.get_node("WeaponValue") as Label
		value_label.position = Vector2(82,68); value_label.size = Vector2(124,28)
	var panel_width := minf(676.0, maxf(280.0, size.x - 64.0))
	result_upgrade_panel.position = Vector2(center.x-panel_width*0.5,page_top+278)
	result_upgrade_panel.size = Vector2(panel_width,92)
	result_upgrade_icon.position = Vector2(18,13); result_upgrade_icon.size = Vector2(46,44)
	result_upgrade_label.position = Vector2(78,8); result_upgrade_label.size = Vector2(maxf(120.0,panel_width-96.0),76)
	for index in buttons.size():
		var button := buttons[index]
		if button.visible:
			var button_width := minf(360.0, maxf(220.0, size.x - 64.0))
			button.position = Vector2(center.x-button_width*0.5,page_top+392+index*52)
			button.size = Vector2(button_width,42)

func set_mode(next_mode: String, next_summary: Dictionary = {}) -> void:
	if next_mode in ["settings", "help", "credits"]:
		return_mode = mode if mode in ["title","pause","result"] else "title"
	mode = next_mode
	summary = next_summary.duplicate(true)
	action_latched = false
	visible = mode != "hidden"
	body_label.add_theme_font_size_override("font_size", 14)
	_set_auxiliary_visibility(false, false)
	match mode:
		"title":
			_configure("MOURNLIGHT","THE CEMETERY GARDEN STIRS","Keep an escape lane. Let the lantern choose its mark.",
				[["play","PLAY"],["settings","SETTINGS"],["credits","CREDITS & NOTICES"],["quit","QUIT"]])
		"pause":
			var guidance: Dictionary = summary.get("first_run_guidance", {})
			var bindings: Dictionary = guidance.get("bindings", {})
			var controls := "MOVE  %s    ·    DASH  %s\nThe lantern attacks automatically; fallen threats release collectible wisps." % [String(bindings.get("move", "MOVE")), String(bindings.get("dash", "DASH"))]
			_configure("NIGHT HELD","THE WARDEN'S FLAME WAITS","The run is paused; no combat clock is advancing.\n\n" + controls,
				[["resume","RESUME"],["help","CONTROLS & HELP"],["settings","SETTINGS"],["retry","RESTART RUN"],["title","RETURN TO TITLE"],["quit","QUIT"]])
		"help":
			var guidance: Dictionary = summary.get("first_run_guidance", {})
			var bindings: Dictionary = guidance.get("bindings", {})
			_configure("CONTROLS & HELP","THE KEEPER'S FIELD NOTES",
				"MOVE  %s\nDASH  %s\nDISMISS / RECALL GUIDANCE  %s\n\nThe Warden Lantern attacks legal threats automatically. Defeated enemies release warm wisps: move into their lantern radius to draw them in. Filling the level bar opens a three-choice upgrade draft; the selected change applies before the night resumes." % [String(bindings.get("move", "UNBOUND")),String(bindings.get("dash", "UNBOUND")),String(bindings.get("help", "UNBOUND"))],
				[["back","BACK TO PAUSE"]])
		"settings":
			_refresh_settings_page()
		"credits":
			body_label.add_theme_font_size_override("font_size", 13)
			_configure("CREDITS & NOTICES","MOURNLIGHT — RELEASE CANDIDATE",
				"MOURNLIGHT — DESIGN, CODE & RELEASE ASSEMBLY\n\nCemetery garden, keeper post, cracked bell, lantern props and enemy character sources — CC BY 4.0.\nKayKit Adventurers Mage / Warden rig and authored animation clips — CC0 1.0.\nMontserrat typography — SIL Open Font License 1.1.\nMaaack menu navigation and GodotX vitals adaptations — MIT (bundled font/icon notices retained).\nBoomer Shooter library plus Kenney, Cogito, COBRA and gd-dialog selected audio — upstream licenses retained.\nOvanisound Sound FX Starter Pack Achievement cue — royalty-free commercial-use license.\n\nExact revisions, hashes, receipts and runtime bindings:\nASSET_PROVENANCE.json  ·  THIRD_PARTY_NOTICES.md\n\nThank you for keeping the last lantern lit.",
				[["back","BACK"]])
		"result":
			var won := String(summary.get("outcome","failure")) == "victory"
			var time := float(summary.get("elapsed",0.0))
			_configure("DAWN ANSWERS" if won else "FLAME EXTINGUISHED","VICTORY" if won else "THE WATCH ENDS",
				"%02d:%02d   ·   WAVE %d/%d   ·   LEVEL %d   ·   %d BANISHED\n%d DEALT   ·   %d TAKEN\nPROVENANCE BOUND  ·  ASSET_PROVENANCE.JSON" % [int(time)/60,int(time)%60,int(summary.get("wave",1)),int(summary.get("wave_count",5)),int(summary.get("level",1)),int(summary.get("defeated",0)),int(summary.get("damage_dealt",0)),int(summary.get("damage_taken",0))],
				[["retry","RETRY"],["title","RETURN TO TITLE"],["credits","CREDITS & NOTICES"]])
			_bind_result_presentation()
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
			_apply_button_surface(button, mode == "settings")
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
	_set_auxiliary_visibility(true, false)

func _set_auxiliary_visibility(settings_visible: bool, result_visible: bool) -> void:
	for label in setting_group_labels:
		label.visible = settings_visible
	for card in result_cards:
		card.visible = result_visible and card.visible
	if is_instance_valid(result_upgrade_panel):
		result_upgrade_panel.visible = result_visible

func _bind_result_presentation() -> void:
	var equipped: Array[Dictionary] = []
	for weapon in (summary.get("weapons",{}) as Dictionary).get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			equipped.append(weapon)
	for index in result_cards.size():
		var card := result_cards[index]
		card.visible = index < equipped.size()
		if not card.visible:
			continue
		var weapon := equipped[index]
		var weapon_id := String(weapon.get("weapon_id","warden_lantern"))
		var stats: Dictionary = weapon.get("stats",{})
		(card.get_node("WeaponIcon") as TextureRect).texture = WEAPON_ICONS.get(weapon_id,ICONS.settings)
		(card.get_node("WeaponName") as Label).text = String(stats.get("display_name",weapon_id)).to_upper()
		(card.get_node("WeaponRank") as Label).text = "RANK %d" % int(weapon.get("rank",1))
		(card.get_node("WeaponValue") as Label).text = "%d DMG  ·  %.2fs" % [int(stats.get("damage",0)),float(stats.get("cooldown",0.0))]
	result_upgrade_panel.visible = true
	result_upgrade_label.text = "SELECTED VIGIL\n%s" % _upgrade_summary(summary)

func _apply_button_surface(button: Button, semantic_row: bool) -> void:
	for surface in ["normal","hover","pressed"]:
		button.remove_theme_stylebox_override(surface)
	if not semantic_row:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.015,0.022,0.05,0.34)
	normal.border_width_bottom = 1
	normal.border_color = Color(0.55,0.42,0.22,0.38)
	normal.content_margin_left = 12.0; normal.content_margin_right = 8.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12,0.09,0.055,0.76)
	hover.border_width_left = 3
	hover.border_color = GOLD
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover)

func _result_card_style(index: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018,0.026,0.058,0.91)
	style.border_width_left = 2
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = BRASS if index != 2 else SILVER
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	return style

func _upgrade_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045,0.035,0.035,0.88)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(BRASS,0.72)
	return style

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
		_record_shell_action(action, false)
		action_requested.emit(action)
		return
	action_latched = true
	_record_shell_action(action, true)
	action_requested.emit(action)

func _record_shell_action(action: StringName, latched: bool) -> void:
	action_generation += 1
	last_action_receipt = {"generation":action_generation, "action":String(action), "mode":mode, "latched":latched}

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
	if upgrades.is_empty():
		return "NONE SELECTED"
	var rows: Array[String] = []
	for item in upgrades:
		var detail := String(item.get("rank_label", item.get("concrete_change", "")))
		rows.append("%s %s" % [String(item.get("title", item.get("upgrade_id", "VIGIL"))), detail])
	return "%d CHOICES · %s" % [upgrades.size(), "  ·  ".join(rows)]

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
	return {"mode":mode,"return_mode":return_mode,"visible":visible,"action_latched":action_latched,"action_generation":action_generation,"last_action_receipt":last_action_receipt,"displayed_result_fields":_displayed_result_fields(),"focus":String(get_viewport().gui_get_focus_owner().get_path()) if get_viewport().gui_get_focus_owner() else "none","actions":actions,"settings":setting_values,"last_setting_mutation":last_setting_mutation}

func _displayed_result_fields() -> Dictionary:
	if mode != "result": return {}
	var weapon_ranks: Array[Dictionary] = []
	for weapon in (summary.get("weapons",{}) as Dictionary).get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			weapon_ranks.append({"weapon_id":weapon.get("weapon_id",""),"rank":weapon.get("rank",0)})
	return {"outcome":summary.get("outcome","failure"),"elapsed":summary.get("elapsed",0.0),"wave":summary.get("wave",1),"level":summary.get("level",1),"defeated":summary.get("defeated",0),"damage_dealt":summary.get("damage_dealt",0),"damage_taken":summary.get("damage_taken",0),"weapon_ranks":weapon_ranks,"selected_upgrades":summary.get("selected_upgrades",[])}
