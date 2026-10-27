class_name TouchControls
extends Control
## Landscape two-thumb controls with per-finger roles (tracked by touch index).
##   Left side  : floating analogue stick → move_* actions.
##   JUMP       : button (jump, wall-kick, mid-air flip).
##   Right side : the web. The big SWING button marks it, but any touch on the
##                right (outside JUMP / pause) counts – hard to miss mid-swing.
##                Hold to keep the web, lift that finger to let go; pressing
##                again with another finger re-attaches immediately.
##                Aim "assist" (default): fires at the reticle target ahead.
##                Aim "tap" (setting): touches on the world fire at the exact
##                surface; SWING remains the assisted fallback.
## There is no manual camera control: the camera frames the action itself.

signal pause_pressed
## Feedback for the HUD: where the finger went, whether it fired, and why not.
signal web_feedback(screen_pos: Vector2, ok: bool, reason: String)

const STICK_RADIUS := 78.0

var camera: SwingCamera
var player: Player
var buttons := {
	"grapple": {"pos": Vector2(-150, -150), "r": 92.0, "label": "SWING"},
	"jump": {"pos": Vector2(-338, -92), "r": 60.0, "label": "JUMP"},
}

## touch index -> {"kind": stick|button|web, "start", "last", "action"}
var touches := {}
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _safe := Rect2()
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	resized.connect(_update_safe)
	_update_safe()
	visibility_changed.connect(func(): if not visible: release_all())


func _update_safe() -> void:
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if sa.size.x <= 0 or win.x <= 0:
		_safe = Rect2(Vector2.ZERO, size)
		return
	var k := size / Vector2(win)
	_safe = Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k).intersection(Rect2(Vector2.ZERO, size))
	if _safe.size.x < 10:
		_safe = Rect2(Vector2.ZERO, size)


func button_center(action: String) -> Vector2:
	return _safe.end + buttons[action]["pos"]


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_down(event.index, event.position)
		else:
			touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		touch_drag(event.index, event.position)
		get_viewport().set_input_as_handled()


## Positions are viewport coordinates (the same space the 3D camera projects in).
func touch_down(idx: int, pos: Vector2) -> void:
	var local := _to_local(pos)
	if local.distance_to(Vector2(_safe.end.x - 44, _safe.position.y + 44)) < 40:
		pause_pressed.emit()
		return
	var jc := button_center("jump")
	if local.distance_to(jc) <= buttons["jump"]["r"] * 1.15:
		touches[idx] = {"kind": "button", "action": "jump", "start": pos, "last": pos}
		Input.action_press("jump")
		Settings.haptic(8, 0.3)
		queue_redraw()
		return
	if local.x < size.x * 0.40:
		if not _has_kind("stick"):
			touches[idx] = {"kind": "stick", "start": pos, "last": pos}
			_stick_origin = local
			_stick_pos = local
		queue_redraw()
		return
	# Everything else on the right is the web.
	touches[idx] = {"kind": "web", "start": pos, "last": pos}
	if player == null:
		return
	var on_swing: bool = local.distance_to(button_center("grapple")) <= buttons["grapple"]["r"] * 1.15
	if Settings.aim_mode == "tap" and not on_swing and camera and camera.cam:
		var r := player.screen_target(camera.cam, pos)
		if r["ok"]:
			player.fire_at(r["point"], idx)
			web_feedback.emit(local, true, "")
			Settings.haptic(10, 0.35)
		else:
			web_feedback.emit(local, false, r["reason"])
			Settings.haptic(20, 0.15)
	else:
		var fired := player.assist_fire(idx)
		web_feedback.emit(local, fired, "" if fired else "waiting")
		Settings.haptic(10 if fired else 8, 0.35 if fired else 0.2)
	queue_redraw()


func touch_drag(idx: int, pos: Vector2) -> void:
	if not touches.has(idx):
		return
	var t: Dictionary = touches[idx]
	t["last"] = pos
	if t["kind"] == "stick":
		_stick_pos = _to_local(pos)
		_apply_stick()
	queue_redraw()


func touch_up(idx: int) -> void:
	if not touches.has(idx):
		return
	var t: Dictionary = touches[idx]
	touches.erase(idx)
	match t["kind"]:
		"stick":
			for a in ["move_left", "move_right", "move_forward", "move_back"]:
				Input.action_release(a)
		"button":
			Input.action_release(t["action"])
		"web":
			if player:
				player.release_web(idx)  # only if this finger still owns the web
	queue_redraw()


func release_all() -> void:
	for idx in touches.keys():
		touch_up(idx)


func _has_kind(kind: String) -> bool:
	for t in touches.values():
		if t["kind"] == kind:
			return true
	return false


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _apply_stick() -> void:
	var d := _stick_pos - _stick_origin
	if d.length() > STICK_RADIUS:
		# Floating stick: drag the base along so reversing direction is instant.
		_stick_origin = _stick_pos - d.normalized() * STICK_RADIUS
		d = d.normalized() * STICK_RADIUS
	var v := d / STICK_RADIUS
	_set_axis("move_right", "move_left", v.x)
	_set_axis("move_back", "move_forward", v.y)


func _set_axis(pos_action: String, neg_action: String, value: float) -> void:
	if value > 0.08:
		Input.action_press(pos_action, minf(value, 1.0))
		Input.action_release(neg_action)
	elif value < -0.08:
		Input.action_press(neg_action, minf(-value, 1.0))
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


func _process(_dt: float) -> void:
	queue_redraw()  # SWING button glows when a target is ready


func _draw() -> void:
	var white := Color(1, 1, 1, 0.85)
	var faint := Color(1, 1, 1, 0.16)
	if _has_kind("stick"):
		draw_circle(_stick_origin, STICK_RADIUS, faint)
		draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		draw_circle(_stick_pos, 34.0, Color(1, 1, 1, 0.55))
	else:
		var hint := Vector2(_safe.position.x + 150, _safe.end.y - 150)
		draw_arc(hint, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0, true)
	var web_down := _has_kind("web")
	var jump_down := false
	for t in touches.values():
		if t.get("action", "") == "jump":
			jump_down = true
	var ready := player != null and player.targeting.has_target and player.line_state == Player.Line.IDLE
	for action in buttons:
		var b: Dictionary = buttons[action]
		var c := button_center(action)
		var down := web_down if action == "grapple" else jump_down
		var fill := Color(1, 1, 1, 0.34 if down else 0.12)
		if action == "grapple" and (ready or down) and Settings.aim_mode != "tap":
			fill = Color(1.0, 0.78, 0.35, 0.55 if down else 0.28)
		draw_circle(c, b["r"], fill)
		draw_arc(c, b["r"], 0, TAU, 48, white if down else Color(1, 1, 1, 0.5), 2.5, true)
		var fs := 24 if action == "grapple" else 15
		var tw := _font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, c + Vector2(-tw / 2.0, fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
	var pp := Vector2(_safe.end.x - 44, _safe.position.y + 44)
	draw_circle(pp, 24, faint)
	draw_rect(Rect2(pp + Vector2(-8, -9), Vector2(5, 18)), white)
	draw_rect(Rect2(pp + Vector2(3, -9), Vector2(5, 18)), white)
