class_name TouchControls
extends Control
## Landscape two-thumb controls with per-finger roles (tracked by touch index).
##   Left side   : floating analogue stick → move_* actions.
##   LOOK pad    : drag to rotate the camera; never fires a web.
##   JUMP        : button (rooftop jump, wall-kick, mid-air trick).
##   Anywhere else: the camera ray through that exact pixel. A valid building
##                 surface fires the web *there*; holding that finger keeps
##                 the web; lifting it releases. An invalid spot never fires:
##                 dragging it turns the camera, tapping it shows why it was
##                 rejected. A new valid tap while swinging re-attaches.

signal look(delta: Vector2)
signal pause_pressed
## Feedback for the HUD: where the finger went, whether it was valid, and why not.
signal web_feedback(screen_pos: Vector2, ok: bool, reason: String)

const STICK_RADIUS := 78.0
const LOOK_SENS := 0.0042
const DRAG_THRESHOLD := 14.0

var camera: SwingCamera
var player: Player
var buttons := {
	"jump": {"pos": Vector2(-118, -112), "r": 66.0, "label": "JUMP"},
	"look": {"pos": Vector2(-292, -104), "r": 66.0, "label": "LOOK"},
}

## touch index -> {"kind": stick|button|look|web|aim, "start", "last", "moved", "action", "result"}
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
	for action in buttons:
		var b: Dictionary = buttons[action]
		if local.distance_to(button_center(action)) <= b["r"] * 1.2:
			touches[idx] = {"kind": "look" if action == "look" else "button", "action": action, "last": pos,
				"start": pos, "moved": false}
			if action != "look":
				Input.action_press(action)
			Settings.haptic(8, 0.3)
			queue_redraw()
			return
	if local.x < size.x * 0.40:
		if not _has_kind("stick"):
			touches[idx] = {"kind": "stick", "start": pos, "last": pos, "moved": false}
			_stick_origin = local
			_stick_pos = local
		queue_redraw()
		return
	# World touch: aim the web exactly where the finger landed.
	var result := {"ok": false, "reason": "no camera", "point": Vector3.ZERO}
	if player and camera and camera.cam:
		result = player.screen_target(camera.cam, pos)
	if result["ok"]:
		touches[idx] = {"kind": "web", "start": pos, "last": pos, "moved": false, "result": result}
		player.fire_at(result["point"], idx)
		web_feedback.emit(local, true, "")
		Settings.haptic(10, 0.35)
	else:
		# Not a valid surface: becomes a camera drag if it moves; a tap shows why.
		touches[idx] = {"kind": "aim", "start": pos, "last": pos, "moved": false, "result": result}
	queue_redraw()


func touch_drag(idx: int, pos: Vector2) -> void:
	if not touches.has(idx):
		return
	var t: Dictionary = touches[idx]
	var delta: Vector2 = pos - t["last"]
	t["last"] = pos
	if not t["moved"] and pos.distance_to(t["start"]) > DRAG_THRESHOLD:
		t["moved"] = true
	match t["kind"]:
		"stick":
			_stick_pos = _to_local(pos)
			_apply_stick()
		"look", "aim":
			if t["moved"]:
				_emit_look(delta)
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
		"aim":
			if not t["moved"]:
				web_feedback.emit(_to_local(t["start"]), false, t["result"]["reason"])
				Settings.haptic(20, 0.15)
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


func _emit_look(d: Vector2) -> void:
	var inv := -1.0 if Settings.invert_y else 1.0
	var delta := d * LOOK_SENS * Settings.look_sensitivity * Vector2(1.0, inv)
	if camera:
		camera.add_look(delta)
	look.emit(delta)


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
	var held := {}
	for t in touches.values():
		if t.has("action"):
			held[t["action"]] = true
	for action in buttons:
		var b: Dictionary = buttons[action]
		var c := button_center(action)
		var down := held.has(action)
		draw_circle(c, b["r"], Color(1, 1, 1, 0.34 if down else 0.12))
		draw_arc(c, b["r"], 0, TAU, 48, white if down else Color(1, 1, 1, 0.45), 2.0, true)
		if action == "look":
			for k in 4:  # four-way arrows
				var dir := Vector2.RIGHT.rotated(k * PI * 0.5)
				var tip: Vector2 = c + dir * (float(b["r"]) - 12.0)
				draw_line(tip, tip - dir * 10 + dir.orthogonal() * 7, Color(1, 1, 1, 0.6), 2.0, true)
				draw_line(tip, tip - dir * 10 - dir.orthogonal() * 7, Color(1, 1, 1, 0.6), 2.0, true)
		var fs := 15
		var tw := _font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, c + Vector2(-tw / 2.0, fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
	var pp := Vector2(_safe.end.x - 44, _safe.position.y + 44)
	draw_circle(pp, 24, faint)
	draw_rect(Rect2(pp + Vector2(-8, -9), Vector2(5, 18)), white)
	draw_rect(Rect2(pp + Vector2(3, -9), Vector2(5, 18)), white)
