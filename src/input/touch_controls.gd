class_name TouchControls
extends Control
## Landscape two-thumb controls with per-finger roles (tracked by touch index).
##   Left side  : floating analogue stick → move_* actions. It also steers
##                the web: pushed, it turns the assisted pick toward its
##                direction (see GrappleTargeting).
##   JUMP       : button (jump, wall-kick, mid-air flip).
##   SWING      : the web. Hold to keep it, lift that finger to let go;
##                pressing again with another finger re-attaches immediately.
##                Aim "assist" (default): fires at the reticle target ahead.
##   Right side : free look. Any other touch on the right (outside the
##                buttons) drags the camera round the player, 360°. In aim
##                "tap" mode the touch also fires at the exact surface.
## Every finger has its own role, so move + jump + swing + look all work at once.

signal home_pressed
var home_button_rect := Rect2()
signal pause_pressed
## The home prompt's button was tapped (see use_label).
signal use_pressed
## Feedback for the HUD: where the finger went, whether it fired, and why not.
signal web_feedback(screen_pos: Vector2, ok: bool, reason: String)

const STICK_DRAW_RADIUS := 78.0
const STICK_RADIUS := 128.0  # finger travel for full speed (longer = finer walking control)

var camera: SwingCamera
var player: Player
var gadgets: Gadgets
## Above SWING, only drawn (and tappable) with a gadget equipped.
const GADGET_POS := Vector2(-118, -318)
const GADGET_R := 50.0
var buttons := {
	"grapple": {"pos": Vector2(-150, -150), "r": 92.0, "label": "SWING"},
	"jump": {"pos": Vector2(-338, -92), "r": 60.0, "label": "JUMP"},
}

## touch index -> {"kind": stick|button|web, "start", "last", "action"}
var touches := {}
## Something to use within reach at home ("" = none): drawn as a button.
var use_label := ""
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _safe := Rect2()
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiStyle.font("bold")
	resized.connect(_update_safe)
	_update_safe()
	visibility_changed.connect(func(): if not visible: release_all())


func _update_safe() -> void:
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if sa.size.x <= 0 or win.x <= 0 or DisplayServer.screen_get_size() != win:
		_safe = Rect2(Vector2.ZERO, size)
		return
	var k := size / Vector2(win)
	_safe = Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k).intersection(Rect2(Vector2.ZERO, size))
	if _safe.size.x < 10:
		_safe = Rect2(Vector2.ZERO, size)


## The home prompt's button: bottom centre, between the thumbs.
func use_rect() -> Rect2:
	var w := 250.0
	return Rect2(Vector2(_safe.get_center().x - w * 0.5, _safe.end.y - 96.0), Vector2(w, 64.0))


## Shared look (the HUD draws the same pill, with a key hint, off touch).
static func draw_use_prompt(ci: CanvasItem, font: Font, r: Rect2, label: String, key_hint: bool) -> void:
	var rad := r.size.y * 0.5
	var col := Color(UiStyle.INK, 0.72)
	ci.draw_circle(r.position + Vector2(rad, rad), rad, col)
	ci.draw_circle(r.end - Vector2(rad, rad), rad, col)
	ci.draw_rect(Rect2(r.position + Vector2(rad, 0), r.size - Vector2(rad * 2.0, 0)), col)
	ci.draw_arc(r.position + Vector2(rad, rad), rad, PI * 0.5, PI * 1.5, 16, Color(UiStyle.GOLD, 0.9), 2.5, true)
	ci.draw_arc(r.end - Vector2(rad, rad), rad, -PI * 0.5, PI * 0.5, 16, Color(UiStyle.GOLD, 0.9), 2.5, true)
	ci.draw_line(r.position + Vector2(rad, 0), Vector2(r.end.x - rad, r.position.y), Color(UiStyle.GOLD, 0.9), 2.5)
	ci.draw_line(Vector2(r.position.x + rad, r.end.y), r.end - Vector2(rad, 0), Color(UiStyle.GOLD, 0.9), 2.5)
	var text := ("F  ·  " + label) if key_hint else label
	var fs := 22
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, r.get_center() + Vector2(-tw * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


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
	if home_button_rect.has_area() and home_button_rect.has_point(local):
		release_all()
		home_pressed.emit()
		Settings.haptic(12, 0.4)
		return
	if local.distance_to(Vector2(_safe.end.x - 44, _safe.position.y + 44)) < 40:
		pause_pressed.emit()
		return
	if use_label != "" and use_rect().grow(14.0).has_point(local):
		touches[idx] = {"kind": "use", "start": pos, "last": pos}
		use_pressed.emit()
		Settings.haptic(12, 0.4)
		queue_redraw()
		return
	if _gadget_shown() and local.distance_to(_safe.end + GADGET_POS) <= GADGET_R * 1.2:
		touches[idx] = {"kind": "gadget", "start": pos, "last": pos}
		gadgets.trigger()
		queue_redraw()
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
	var on_swing: bool = local.distance_to(button_center("grapple")) <= buttons["grapple"]["r"] * 1.3
	var tap_aim := Settings.aim_mode == "tap" and not on_swing
	if not on_swing and not tap_aim:
		# The open right side: free look (one look finger at a time).
		if not _has_kind("look"):
			touches[idx] = {"kind": "look", "start": pos, "last": pos}
		return
	touches[idx] = {"kind": "web", "start": pos, "last": pos, "look": tap_aim}
	if player == null:
		return
	if tap_aim and camera and camera.cam:
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
	var moved := pos - (t["last"] as Vector2)
	t["last"] = pos
	if (t["kind"] == "look" or t.get("look", false)) and camera:
		camera.add_touch_look(moved, size.x)
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


func _gadget_shown() -> bool:
	return gadgets != null and gadgets.kind() != "" and gadgets.enabled


func release_all() -> void:
	for idx in touches.keys():
		touch_up(idx)


func _look_web_held() -> bool:
	for t in touches.values():
		if t.get("look", false) and (t["last"] as Vector2).distance_to(t["start"]) > 12.0:
			return true
	return false


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
	if camera and (_has_kind("look") or _look_web_held()):
		camera.hold_look()
	queue_redraw()  # SWING button glows when a target is ready


func _draw() -> void:
	var white := Color(1, 1, 1, 0.85)
	var shade := Color(0, 0, 0, 0.22)
	if _has_kind("stick"):
		draw_circle(_stick_origin, STICK_DRAW_RADIUS, Color(UiStyle.INK, 0.3))
		draw_arc(_stick_origin, STICK_DRAW_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		var d := _stick_pos - _stick_origin
		if d.length() > 14.0:
			# Steering: a gold chevron on the rim where the web will lean.
			var u := d.normalized()
			var tip := _stick_origin + u * (STICK_DRAW_RADIUS + 16.0)
			var side := Vector2(-u.y, u.x)
			var k := clampf(d.length() / STICK_RADIUS, 0.0, 1.0)
			draw_colored_polygon(PackedVector2Array([tip, tip - u * 14.0 + side * 11.0, tip - u * 14.0 - side * 11.0]),
				Color(UiStyle.GOLD, 0.4 + 0.5 * k))
			draw_arc(_stick_origin, STICK_DRAW_RADIUS, d.angle() - 0.5 * k, d.angle() + 0.5 * k, 12, Color(UiStyle.GOLD, 0.8), 4.0, true)
		var nub := _stick_origin + d.limit_length(STICK_RADIUS) * (STICK_DRAW_RADIUS / STICK_RADIUS)
		draw_circle(nub, 25.0, shade)
		draw_circle(nub, 23.0, Color(1, 1, 1, 0.42))
	else:
		var hint := Vector2(_safe.position.x + 150, _safe.end.y - 150)
		draw_circle(hint, STICK_DRAW_RADIUS, Color(1, 1, 1, 0.025))
		draw_arc(hint, STICK_DRAW_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.14), 1.5, true)
		draw_circle(hint, 26.0, Color(1, 1, 1, 0.08))  # resting thumb nub
		draw_arc(hint, 26.0, 0, TAU, 32, Color(1, 1, 1, 0.2), 1.5, true)
		var lw := _font.get_string_size("MOVE · STEER", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(_font, hint + Vector2(-lw / 2.0, STICK_DRAW_RADIUS - 14.0), "MOVE · STEER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.26))
	var web_down := _has_kind("web")
	var jump_down := false
	for t in touches.values():
		if t.get("action", "") == "jump":
			jump_down = true
	var ready := player != null and player.targeting.has_target and player.line_state == Player.Line.IDLE and not player.stunned
	for action in buttons:
		var b: Dictionary = buttons[action]
		var c := button_center(action)
		var down := web_down if action == "grapple" else jump_down
		# Same family as the HUD panels: Night Ink glass, a hairline ring, and
		# gold only to say "a web will land" (ring + label), filled when held.
		var hot: bool = action == "grapple" and ready and Settings.aim_mode != "tap"
		# Drawn smaller than the touch target and faint at rest: the city
		# behind stays readable; a press or "a web will land" brings it up.
		var visual_r: float = 54.0 if action == "grapple" else 38.0
		var fill := Color(UiStyle.INK, 0.46 if down else 0.12)
		if down and action == "grapple":
			fill = Color(UiStyle.GOLD, 0.5)
		draw_circle(c, visual_r, fill)
		var ring := Color(UiStyle.WEB, 0.9 if down else 0.26)
		if hot:
			ring = Color(UiStyle.GOLD, 0.95)
			draw_arc(c, visual_r + 7.0, -PI * 0.75, -PI * 0.25, 20, Color(UiStyle.GOLD, 0.55), 3.0, true)
			draw_arc(c, visual_r + 7.0, PI * 0.25, PI * 0.75, 20, Color(UiStyle.GOLD, 0.55), 3.0, true)
		draw_arc(c, visual_r, 0, TAU, 48, ring, 1.5 if not hot else 2.0, true)
		var fs := 15 if action == "grapple" else 12
		var tw := _font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var label_col := UiStyle.GOLD if hot and not down else (white if down else Color(1, 1, 1, 0.55))
		draw_string(_font, c + Vector2(-tw / 2.0, fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)
	if _gadget_shown():
		_draw_gadget(_safe.end + GADGET_POS, white, shade)
	if use_label != "":
		draw_use_prompt(self, _font, use_rect(), use_label, false)
	var pp := Vector2(_safe.end.x - 44, _safe.position.y + 44)
	draw_circle(pp, 24, Color(UiStyle.INK, 0.38))
	draw_arc(pp, 24, 0, TAU, 32, Color(UiStyle.WEB, 0.3), 1.5, true)
	draw_rect(Rect2(pp + Vector2(-8, -9), Vector2(5, 18)), white)
	draw_rect(Rect2(pp + Vector2(3, -9), Vector2(5, 18)), white)


## The gadget button: its icon, a ring that fills as it recharges, gold when
## ready, lit while it runs.
func _draw_gadget(c: Vector2, white: Color, shade: Color) -> void:
	var k := gadgets.charge()
	var ready := gadgets.ready_to_use()
	var on := gadgets.running()
	draw_circle(c, GADGET_R + 3.0, shade)
	draw_circle(c, GADGET_R, Color(UiStyle.TEAL, 0.4) if on else Color(1, 1, 1, 0.08))
	draw_arc(c, GADGET_R, 0, TAU, 40, Color(1, 1, 1, 0.18), 3.0, true)
	if k > 0.01:
		draw_arc(c, GADGET_R, -PI / 2, -PI / 2 + TAU * k, maxi(4, int(40 * k)),
			Color(UiStyle.GOLD, 0.95) if ready else Color(1, 1, 1, 0.55), 4.0, true)
	MenuParts.draw_gadget(self, gadgets.kind(), c, 30.0, white if ready or on else Color(1, 1, 1, 0.45))
