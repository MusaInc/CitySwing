class_name HomeBoard
extends Label3D
## A board on a home's wall showing your progress – rank, contracts, tokens,
## records – so coming home shows how far you've come. The studio's is a
## corkboard; the penthouse's is the Hall of Fame on the mezzanine.
## Refreshes from SaveData every few seconds while the camera is near.

var tier := 0
var board_w := 1.2
var _t := 0.0


func _ready() -> void:
	font = UiStyle.font("bold")
	pixel_size = board_w / 900.0
	font_size = 48
	outline_size = 0
	modulate = Color(0.12, 0.1, 0.08) if tier == 0 else Color(0.97, 0.94, 0.88)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	double_sided = false
	no_depth_test = false
	shaded = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	visibility_range_end = 40.0
	refresh()


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 3.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and cam.global_position.distance_to(global_position) < 40.0:
		refresh()


func refresh() -> void:
	text = board_text(_data(), tier)


static func board_text(d: Dictionary, home_tier: int) -> String:
	var rep := int(d.get("rep", 0))
	var lines: Array[String] = []
	lines.append("HALL OF FAME" if home_tier == 4 else ("THE BOARD" if home_tier == 0 else "PROGRESS"))
	lines.append("%s  ·  %d rep" % [Contracts.rank_name(rep).to_upper(), rep])
	lines.append("%d contracts  ·  %d underworld" % [int(d.get("jobs_done", 0)), int(d.get("jobs_crime", 0))])
	lines.append("%d / %d tokens" % [(d.get("tokens", []) as Array).size(), Progress.TOKEN_TOTAL])
	lines.append("best chain ×%d  ·  top %d km/h" % [int(d.get("best_chain", 0)), int(float(d.get("top_speed_ms", 0.0)) * 3.6)])
	lines.append("%.1f km swung" % (float(d.get("total_distance_m", 0.0)) / 1000.0))
	return "\n".join(lines)


func _data() -> Dictionary:
	var sd := get_node_or_null("/root/SaveData") if is_inside_tree() else null
	return sd.data if sd else {}
