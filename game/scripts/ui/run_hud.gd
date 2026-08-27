class_name RunHUD
extends Control

var snapshot: Dictionary = {}
var snapshot_serial := 0

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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
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

func bind_snapshot(next_snapshot: Dictionary) -> void:
	snapshot = next_snapshot.duplicate(true)
	snapshot_serial += 1
	visible = bool(snapshot.get("world_active", false)) and String(snapshot.get("state", "")) in ["active", "boss", "paused", "draft"]
	_vitals_meter.set_health(
		float(snapshot.get("health", 0.0)),
		maxf(1.0, float(snapshot.get("health_maximum", 1.0))),
		snapshot_serial > 1
	)
	queue_redraw()

func clear_snapshot() -> void:
	snapshot = {}
	visible = false
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
	_draw_carved_bar(Rect2(origin + Vector2(118, 6), Vector2(250, 15)), float(experience) / threshold, SILVER, VIOLET)
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
		_draw_weapon_sigil(center, String(weapon.get("weapon_id", "")), int(weapon.get("rank", 1)))
		shown += 1
	if shown == 0:
		_draw_weapon_sigil(origin + Vector2(42, 38), "warden_lantern", 1)

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
		"boss_active":snapshot.get("boss_active",false),"boss_health":snapshot.get("boss_health",0.0),"boss_health_maximum":snapshot.get("boss_health_maximum",0.0)},
		"snapshot_serial": snapshot_serial, "visible": visible}

func _weapon_rank_digest() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon in (snapshot.get("weapons",{}) as Dictionary).get("weapons",[]):
		if bool(weapon.get("equipped",false)):
			result.append({"weapon_id":weapon.get("weapon_id",""),"rank":weapon.get("rank",0)})
	return result
