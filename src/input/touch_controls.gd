class_name TouchControls
extends Control
## Landscape two-thumb layout.
##   Left thumb : floating analogue stick anywhere on the left 42% → move_* actions.
##   Right thumb: drag empty space to aim the camera; HOLD the grapple button to
##                fire and stay attached, lift to release. Sliding the thumb while
##                holding grapple keeps aiming. Reel in/out and jump sit above it.
## Everything is fed into the InputMap actions, so gameplay code is input-agnostic.

signal look(delta: Vector2)
signal pause_pressed

const STICK_RADIUS := 78.0
const LOOK_SENS := 0.0042

var camera: SwingCamera
var buttons := {
	"grapple": {"pos": Vector2(-150, -150), "r": 86.0, "label": "SWING"},
	"jump": {"pos": Vector2(-322, -96), "r": 50.0, "label": "JUMP"},
	"reel_in": {"pos": Vector2(-104, -330), "r": 44.0, "label": "IN"},
	"reel_out": {"pos": Vector2(-222, -300), "r": 44.0, "label": "OUT"},
}
var target_locked := false  # grapple button tint when a target is available

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _button_touch := {}  # touch index -> action
var _safe := Rect2()
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	resized.connect(_update_safe)
	_update_safe()


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


func _button_center(b: Dictionary) -> Vector2:
	return _safe.end + b["pos"]


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var pos := _to_local(event.position)
		if event.pressed:
			_touch_down(event.index, pos)
		else:
			_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var pos := _to_local(event.position)
		if event.index == _stick_touch:
			_stick_pos = pos
			_apply_stick()
		elif event.index == _look_touch:
			_emit_look((pos - _look_last))
			_look_last = pos
		elif _button_touch.get(event.index, "") == "grapple":
			_emit_look(event.relative * get_global_transform_with_canvas().affine_inverse().get_scale() * 0.6)
		get_viewport().set_input_as_handled()
	queue_redraw()


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _touch_down(idx: int, pos: Vector2) -> void:
	if pos.distance_to(Vector2(_safe.end.x - 44, _safe.position.y + 44)) < 40:
		pause_pressed.emit()
		return
	for action in buttons:
		var b: Dictionary = buttons[action]
		if pos.distance_to(_button_center(b)) <= b["r"] * 1.25:
			_button_touch[idx] = action
			Input.action_press(action)
			Settings.haptic(8, 0.3)
			return
	if pos.x < size.x * 0.42 and _stick_touch == -1:
		_stick_touch = idx
		_stick_origin = pos
		_stick_pos = pos
	elif _look_touch == -1:
		_look_touch = idx
		_look_last = pos


func _touch_up(idx: int) -> void:
	if idx == _stick_touch:
		_stick_touch = -1
		for a in ["move_left", "move_right", "move_forward", "move_back"]:
			Input.action_release(a)
	elif idx == _look_touch:
		_look_touch = -1
	elif _button_touch.has(idx):
		Input.action_release(_button_touch[idx])
		_button_touch.erase(idx)


func _apply_stick() -> void:
	var d := (_stick_pos - _stick_origin)
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
	if _stick_touch != -1:
		draw_circle(_stick_origin, STICK_RADIUS, faint)
		draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		draw_circle(_stick_pos, 34.0, Color(1, 1, 1, 0.55))
	else:
		var hint := Vector2(_safe.position.x + 150, _safe.end.y - 150)
		draw_arc(hint, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0, true)
	for action in buttons:
		var b: Dictionary = buttons[action]
		var c := _button_center(b)
		var down := _button_touch.values().has(action)
		var fill := Color(1, 1, 1, 0.38 if down else 0.14)
		if action == "grapple" and target_locked:
			fill = Color(1.0, 0.78, 0.35, 0.55 if down else 0.3)
		draw_circle(c, b["r"], fill)
		draw_arc(c, b["r"], 0, TAU, 48, white if down else Color(1, 1, 1, 0.5), 2.5, true)
		var fs := 22 if action == "grapple" else 15
		var tw := _font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, c + Vector2(-tw / 2.0, fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
	# Pause
	var pp := Vector2(_safe.end.x - 44, _safe.position.y + 44)
	draw_circle(pp, 24, faint)
	draw_rect(Rect2(pp + Vector2(-8, -9), Vector2(5, 18)), white)
	draw_rect(Rect2(pp + Vector2(3, -9), Vector2(5, 18)), white)
