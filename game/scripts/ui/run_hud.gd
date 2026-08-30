class_name RunHUD
extends Control

var snapshot: Dictionary = {}
var snapshot_serial := 0
var _displayed_experience_ratio := 0.0
var _target_experience_ratio := 0.0
var _last_level := 1
var _last_resolved_reward_count := 0
var _collection_flash := 0.0
var _guidance_panel: Panel
var _guidance_image: TextureRect
var _guidance_title: Label
var _guidance_action: Label
var _guidance_prompt: Label
var _guidance_dismiss: Label
var _guidance_help_hint: Label

@onready var _vitals_meter: FPSVitalsHUD = $VitalsMeter

const INK := Color("dce7ff")
const SILVER := Color("aebbd8")
const BRASS := Color("b9853f")
const GOLD := Color("ffc45b")
const EMBER := Color("ff7f3b")
const TEAL := Color("5cf4df")
const VIOLET := Color("c27cff")
const STONE := Color(0.025, 0.032, 0.065, 0.78)
const FONT_BODY := preload("res://assets/fonts/Montserrat-Medium.ttf")
const FONT_NUMERAL := preload("res://assets/fonts/Montserrat-SemiBold.ttf")
const GUIDANCE_ART := preload("res://assets/ui/guidance/first_run_gameplay.png")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_vitals_meter.set_armor_visible(false)
	_vitals_meter.custom_minimum_size = Vector2(250.0, 24.0)
	(_vitals_meter.get_node("Rows") as VBoxContainer).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health_row := _vitals_meter.get_node("Rows/HealthRow") as HBoxContainer
	health_row.custom_minimum_size = Vector2(250.0, 24.0)
	health_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_vitals_meter.get_node("Rows/HealthRow/HealthIcon") as TextureRect).visible = false
	(_vitals_meter.get_node("Rows/HealthRow/HealthValue") as Label).visible = false
	var health_bar := _vitals_meter.get_node("Rows/HealthRow/HealthBar") as Control
	health_bar.custom_minimum_size = Vector2(250.0, 18.0)
	_build_guidance_panel()

func _process(delta: float) -> void:
	var before := _displayed_experience_ratio
	_displayed_experience_ratio = move_toward(_displayed_experience_ratio, _target_experience_ratio, delta * 1.65)
	_collection_flash = maxf(0.0, _collection_flash - delta * 1.8)
	if not is_equal_approx(before, _displayed_experience_ratio) or _collection_flash > 0.0:
		queue_redraw()

func _build_guidance_panel() -> void:
	_guidance_panel = Panel.new()
	_guidance_panel.name = "FirstRunGuidancePanel"
	_guidance_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.012, 0.018, 0.045, 0.96)
	surface.border_width_left = 2
	surface.border_width_top = 2
	surface.border_width_right = 2
	surface.border_width_bottom = 2
	surface.border_color = BRASS
	surface.corner_radius_top_right = 12
	surface.corner_radius_bottom_left = 12
	_guidance_panel.add_theme_stylebox_override("panel", surface)
	add_child(_guidance_panel)
	_guidance_image = TextureRect.new()
	_guidance_image.texture = GUIDANCE_ART
	_guidance_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_guidance_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_guidance_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guidance_panel.add_child(_guidance_image)
	var shade := ColorRect.new()
	shade.position = Vector2(0, 154)
	shade.size = Vector2(468, 124)
	shade.color = Color(0.008, 0.012, 0.035, 0.92)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guidance_panel.add_child(shade)
	_guidance_title = _guidance_label(11, GOLD)
	_guidance_action = _guidance_label(19, INK)
	_guidance_prompt = _guidance_label(11, SILVER)
	_guidance_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guidance_dismiss = _guidance_label(9, Color(BRASS, 0.95))
	_guidance_help_hint = _guidance_label(10, Color(BRASS, 0.95))
	_guidance_help_hint.text = "H  HELP"
	add_child(_guidance_help_hint)
	for label in [_guidance_title, _guidance_action, _guidance_prompt, _guidance_dismiss]:
		_guidance_panel.add_child(label)
	_guidance_panel.visible = false
	_layout_guidance_panel()

func _guidance_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT_BODY)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _layout_guidance_panel() -> void:
	if not is_instance_valid(_guidance_panel):
		return
	_guidance_panel.position = Vector2(maxf(28.0, size.x - 500.0), maxf(178.0, size.y - 426.0))
	_guidance_panel.size = Vector2(468, 278)
	_guidance_image.position = Vector2(2, 2)
	_guidance_image.size = Vector2(464, 190)
	_guidance_title.position = Vector2(18, 160); _guidance_title.size = Vector2(430, 20)
	_guidance_action.position = Vector2(18, 180); _guidance_action.size = Vector2(430, 28)
	_guidance_prompt.position = Vector2(18, 210); _guidance_prompt.size = Vector2(430, 38)
	_guidance_dismiss.position = Vector2(18, 250); _guidance_dismiss.size = Vector2(430, 18)
	_guidance_help_hint.position = Vector2(size.x - 108, size.y - 42)
	_guidance_help_hint.size = Vector2(82, 20)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_guidance_panel()

func bind_snapshot(next_snapshot: Dictionary) -> void:
	snapshot = next_snapshot.duplicate(true)
	snapshot_serial += 1
	visible = bool(snapshot.get("world_active", false)) and String(snapshot.get("state", "")) in ["active", "boss", "paused", "draft"]
	_vitals_meter.set_health(
		float(snapshot.get("health", 0.0)),
		maxf(1.0, float(snapshot.get("health_maximum", 1.0))),
		snapshot_serial > 1
	)
	var threshold := maxf(1.0, float(snapshot.get("experience_threshold", 1)))
	_target_experience_ratio = clampf(float(snapshot.get("experience", 0)) / threshold, 0.0, 1.0)
	var next_level := int(snapshot.get("level", 1))
	var reward_feedback: Dictionary = snapshot.get("reward_feedback", {})
	var resolved_count := int(reward_feedback.get("resolved_identity_count", 0))
	if snapshot_serial == 1:
		_displayed_experience_ratio = _target_experience_ratio
	elif next_level > _last_level:
		_displayed_experience_ratio = 0.0
		_collection_flash = 1.0
	elif resolved_count > _last_resolved_reward_count:
		_collection_flash = 1.0
	_last_level = next_level
	_last_resolved_reward_count = resolved_count
	_bind_guidance_panel(snapshot.get("first_run_guidance", {}))
	queue_redraw()

func _bind_guidance_panel(guidance_value: Variant) -> void:
	var guidance: Dictionary = guidance_value if guidance_value is Dictionary else {}
	_guidance_panel.visible = visible and bool(guidance.get("visible", false))
	_guidance_help_hint.visible = visible and bool(guidance.get("dismissed", false)) and not bool(guidance.get("completed", false))
	if not _guidance_panel.visible:
		return
	_guidance_title.text = "%s   ·   %s" % [String(guidance.get("title", "KEEPER'S FIRST VIGIL")), String(guidance.get("device", "keyboard")).to_upper()]
	_guidance_action.text = String(guidance.get("action_label", ""))
	_guidance_prompt.text = String(guidance.get("prompt", ""))
	var bindings: Dictionary = guidance.get("bindings", {})
	_guidance_dismiss.text = "%s  DISMISS / RECALL     ·     ESC  PAUSE & HELP" % String(bindings.get("help", "H"))

func clear_snapshot() -> void:
	snapshot = {}
	visible = false
	if is_instance_valid(_guidance_panel):
		_guidance_panel.visible = false
	if is_instance_valid(_guidance_help_hint):
		_guidance_help_hint.visible = false
	queue_redraw()

func _draw() -> void:
	if snapshot.is_empty():
		return
	var viewport := size
	_draw_health_cluster(Vector2(32, viewport.y - 120))
	_draw_experience_cluster(Vector2(viewport.x * 0.5 - 185, 24))
	_draw_encounter_cluster(Vector2(viewport.x - 270, 28))
	_draw_weapon_cluster(Vector2(viewport.x * 0.5 - 128, viewport.y - 106))
	_draw_dash_cluster(Vector2(viewport.x - 132, viewport.y - 126))
	if bool(snapshot.get("boss_active", false)):
		_draw_boss_cluster(Vector2(viewport.x * 0.5 - 260, 72))

func _draw_first_run_guidance(viewport: Vector2) -> void:
	var guidance: Dictionary = snapshot.get("first_run_guidance", {})
	if not bool(guidance.get("visible", false)):
		return
	var rect := Rect2(Vector2(viewport.x * 0.5 - 295.0, viewport.y - 174.0), Vector2(590.0, 48.0))
	draw_rect(rect, Color(0.015, 0.02, 0.045, 0.82), true)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), BRASS, 2.0, true)
	draw_line(rect.end - Vector2(rect.size.x, 0), rect.end, Color(BRASS, 0.38), 1.0, true)
	var icon_center := rect.position + Vector2(28.0, 24.0)
	match String(guidance.get("icon", "lantern")):
		"wisp":
			draw_circle(icon_center, 8.0, VIOLET)
			draw_arc(icon_center, 14.0, -2.6, 0.55, 18, SILVER, 2.0, true)
		"upgrade":
			draw_colored_polygon(PackedVector2Array([icon_center + Vector2(0,-12),icon_center + Vector2(11,0),icon_center + Vector2(0,12),icon_center + Vector2(-11,0)]), Color(GOLD,0.9))
		_:
			_draw_lantern(icon_center, 15.0, GOLD)
	_draw_text(String(guidance.get("title", "KEEPER'S FIRST VIGIL")), rect.position + Vector2(52, 18), 10, GOLD)
	_draw_text(String(guidance.get("prompt", "")), rect.position + Vector2(52, 36), 10, INK)

func _draw_health_cluster(origin: Vector2) -> void:
	var current := float(snapshot.get("health", 0.0))
	var maximum := maxf(1.0, float(snapshot.get("health_maximum", 1.0)))
	var ratio := clampf(current / maximum, 0.0, 1.0)
	_draw_lantern(origin + Vector2(35, 38), 30.0, GOLD if ratio > 0.3 else EMBER)
	_draw_health_frame(Rect2(origin + Vector2(70, 25), Vector2(250, 24)))
	_draw_text("WARDEN  %d / %d" % [int(current), int(maximum)], origin + Vector2(75, 18), 14, INK)
	_draw_text("LANTERN HEART", origin + Vector2(75, 67), 11, SILVER)

func _draw_experience_cluster(origin: Vector2) -> void:
	var experience := int(snapshot.get("experience", 0))
	var threshold := maxi(1, int(snapshot.get("experience_threshold", 1)))
	var level := int(snapshot.get("level", 1))
	_draw_moon(origin + Vector2(20, 18), 17.0, SILVER)
	_draw_text("LEVEL %d" % level, origin + Vector2(47, 13), 13, INK)
	_draw_carved_bar(Rect2(origin + Vector2(118, 6), Vector2(250, 15)), _displayed_experience_ratio, SILVER, VIOLET)
	if _collection_flash > 0.0:
		draw_arc(origin + Vector2(20, 18), 22.0 + (1.0 - _collection_flash) * 8.0, 0.0, TAU, 28, Color(GOLD, _collection_flash), 3.0, true)
	_draw_text("%d / %d WISPS" % [experience, threshold], origin + Vector2(215, 42), 10, SILVER, HORIZONTAL_ALIGNMENT_CENTER, 150)

func _draw_encounter_cluster(origin: Vector2) -> void:
	var encounter: Dictionary = snapshot.get("encounter", {})
	var live := int(encounter.get("live", 0))
	var defeated := int(snapshot.get("defeated", 0))
	var elapsed := float(snapshot.get("elapsed", 0.0))
	draw_line(origin, origin + Vector2(236, 0), BRASS, 2.0, true)
	var wave := int(snapshot.get("wave", 1))
	var wave_count := int(snapshot.get("wave_count", 5))
	_draw_text("WAVE %d / %d" % [wave,wave_count], origin + Vector2(0, 24), 12, GOLD)
	_draw_text("%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], origin + Vector2(128, 24), 15, INK, HORIZONTAL_ALIGNMENT_RIGHT, 108)
	_draw_text("THREATS  %d     BANISHED  %d" % [live, defeated], origin + Vector2(0, 49), 10, SILVER)
	_draw_text(String(snapshot.get("wave_title","NIGHT WATCH")).to_upper(), origin + Vector2(0, 68), 9, SILVER)

func _draw_boss_cluster(origin: Vector2) -> void:
	var current := float(snapshot.get("boss_health",0.0))
	var maximum := maxf(1.0,float(snapshot.get("boss_health_maximum",1.0)))
	draw_line(origin,origin+Vector2(520,0),Color(VIOLET,0.75),2,true)
	_draw_text("THE BELLKEEPER   PHASE %d" % int(snapshot.get("boss_phase",1)),origin+Vector2(0,24),13,GOLD,HORIZONTAL_ALIGNMENT_CENTER,520)
	_draw_carved_bar(Rect2(origin+Vector2(20,34),Vector2(480,14)),current/maximum,VIOLET,EMBER)

func _draw_weapon_cluster(origin: Vector2) -> void:
	var build: Dictionary = snapshot.get("weapons", {})
	var weapons: Array = build.get("weapons", [])
	var shown := 0
	for weapon in weapons:
		if not bool(weapon.get("equipped", false)):
			continue
		var center := origin + Vector2(42 + shown * 86, 38)
		var weapon_id := String(weapon.get("weapon_id", ""))
		_draw_weapon_sigil(center, weapon_id, int(weapon.get("rank", 1)))
		# Identity is intentionally compact: a recognizable sigil, a short name,
		# and one defining attack-shape cue are enough to read the current build
		# without turning the gameplay HUD into a stat table.
		_draw_text(_weapon_short_name(weapon_id), center + Vector2(-38, 65), 9, INK, HORIZONTAL_ALIGNMENT_CENTER, 76)
		_draw_text(_weapon_shape_cue(weapon_id), center + Vector2(-38, 78), 8, SILVER, HORIZONTAL_ALIGNMENT_CENTER, 76)
		shown += 1
	if shown == 0:
		_draw_weapon_sigil(origin + Vector2(42, 38), "warden_lantern", 1)
		_draw_text("LANTERN", origin + Vector2(4, 103), 9, INK, HORIZONTAL_ALIGNMENT_CENTER, 76)
		_draw_text("FOCUSED", origin + Vector2(4, 116), 8, SILVER, HORIZONTAL_ALIGNMENT_CENTER, 76)

func _weapon_short_name(weapon_id: String) -> String:
	match weapon_id:
		"gravespade": return "GRAVESPADE"
		"wandering_wisps": return "WISPS"
		_: return "LANTERN"

func _weapon_shape_cue(weapon_id: String) -> String:
	match weapon_id:
		"gravespade": return "SWEEP"
		"wandering_wisps": return "ORBIT"
		_: return "FOCUSED"

func _draw_dash_cluster(origin: Vector2) -> void:
	var phase := String(snapshot.get("dash_phase", "ready"))
	var remaining := float(snapshot.get("dash_remaining", 0.0))
	var duration := maxf(0.01, float(snapshot.get("dash_duration", 1.0)))
	var ready := phase == "ready"
	var ratio := 1.0 if ready else 1.0 - clampf(remaining / duration, 0.0, 1.0)
	var color := TEAL if phase == "active" else GOLD if ready else VIOLET
	draw_circle(origin + Vector2(46, 42), 31.0, STONE)
	draw_arc(origin + Vector2(46, 42), 31.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, color, 4.0, true)
	_draw_dash_wing(origin + Vector2(46, 42), color)
	_draw_text("DASH", origin + Vector2(-4, 91), 11, SILVER, HORIZONTAL_ALIGNMENT_CENTER, 100)
	_draw_text(phase.to_upper(), origin + Vector2(-4, 107), 9, color, HORIZONTAL_ALIGNMENT_CENTER, 100)

func _draw_lantern(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, STONE)
	draw_arc(center, radius - 2.0, 0.0, TAU, 32, BRASS, 3.0, true)
	draw_line(center + Vector2(-13, -19), center + Vector2(13, -19), BRASS, 3.0, true)
	draw_arc(center + Vector2(0, -18), 8.0, PI, TAU, 12, BRASS, 3.0, true)
	var flame := PackedVector2Array([center + Vector2(0,-16), center + Vector2(10,6), center + Vector2(3,17), center + Vector2(-9,9), center + Vector2(-8,0)])
	draw_colored_polygon(flame, Color(color, 0.92))
	draw_circle(center + Vector2(1, 7), 5.0, Color("fff2bd"))

func _draw_moon(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)
	draw_circle(center + Vector2(7, -5), radius * 0.82, Color("10172f"))
	draw_arc(center, radius + 3.0, -PI * 0.65, PI * 0.65, 20, BRASS, 2.0, true)

func _draw_weapon_sigil(center: Vector2, weapon_id: String, rank: int) -> void:
	draw_circle(center, 31.0, STONE)
	draw_arc(center, 31.0, 0.0, TAU, 24, BRASS, 2.0, true)
	match weapon_id:
		"gravespade":
			draw_line(center + Vector2(-10, 16), center + Vector2(11, -15), INK, 5.0, true)
			draw_colored_polygon(PackedVector2Array([center + Vector2(6,-17), center + Vector2(19,-10), center + Vector2(10,1)]), SILVER)
		"wandering_wisps":
			for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				var p := center + Vector2(cos(angle), sin(angle)) * 15.0
				draw_circle(p, 5.0, VIOLET)
				draw_arc(center, 18.0, angle, angle + 0.65, 8, SILVER, 2.0, true)
		_:
			_draw_lantern(center, 22.0, GOLD)
	_draw_text("R%d" % rank, center + Vector2(-16, 47), 9, INK, HORIZONTAL_ALIGNMENT_CENTER, 32)

func _draw_dash_wing(center: Vector2, color: Color) -> void:
	var wing := PackedVector2Array([center + Vector2(-19, 5), center + Vector2(5,-15), center + Vector2(0,-3), center + Vector2(19,-8), center + Vector2(-4,15), center + Vector2(1,3)])
	draw_colored_polygon(wing, Color(color, 0.9))

func _draw_carved_bar(rect: Rect2, ratio: float, from_color: Color, to_color: Color) -> void:
	draw_rect(rect, STONE, true)
	draw_rect(Rect2(rect.position + Vector2(3,3), Vector2((rect.size.x - 6) * clampf(ratio, 0.0, 1.0), rect.size.y - 6)), from_color.lerp(to_color, 1.0 - ratio), true)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), BRASS, 2.0, true)
	draw_line(rect.end - Vector2(rect.size.x, 0), rect.end, Color(BRASS, 0.5), 1.0, true)

func _draw_health_frame(rect: Rect2) -> void:
	draw_rect(rect, STONE, true)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), BRASS, 2.0, true)
	draw_line(rect.end - Vector2(rect.size.x, 0), rect.end, Color(BRASS, 0.5), 1.0, true)

func _draw_text(value: String, position: Vector2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font: Font = FONT_NUMERAL if value.contains("%") or value.contains("/") else FONT_BODY
	draw_string(font, position, value, alignment, width, font_size, color)

func _mcp_state() -> Dictionary:
	return {"displayed_fields":{"health":snapshot.get("health",0.0),"health_maximum":snapshot.get("health_maximum",0.0),
		"experience":snapshot.get("experience",0),"experience_threshold":snapshot.get("experience_threshold",0),
		"level":snapshot.get("level",1),"wave":snapshot.get("wave",1),"wave_count":snapshot.get("wave_count",5),
		"elapsed":snapshot.get("elapsed",0.0),"weapon_ranks":_weapon_rank_digest(),"dash_phase":snapshot.get("dash_phase","ready"),
		"boss_active":snapshot.get("boss_active",false),"boss_health":snapshot.get("boss_health",0.0),"boss_health_maximum":snapshot.get("boss_health_maximum",0.0),
		"first_run_guidance":snapshot.get("first_run_guidance",{}),
		"displayed_experience_ratio":_displayed_experience_ratio,
		"target_experience_ratio":_target_experience_ratio,
		"collection_flash":_collection_flash},
		"help_hint_visible":is_instance_valid(_guidance_help_hint) and _guidance_help_hint.visible,
		"snapshot_serial": snapshot_serial, "visible": visible}

func _weapon_rank_digest() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon in (snapshot.get("weapons",{}) as Dictionary).get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			result.append({"weapon_id":weapon.get("weapon_id",""),"rank":weapon.get("rank",0)})
	return result
