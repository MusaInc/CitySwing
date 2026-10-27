class_name Hud
extends Control
## Reticle, speed, chain counter, mode readout and the performance overlay.

var player: Player
var camera: SwingCamera
var mode_text := ""
var mode_sub := ""
var banner := ""
## Bottom-centre instruction (Training).
var hint := ""
## World point to guide the player to (nearest token); Vector3.INF = none.
var pointer := Vector3.INF
## Touch play: show the assisted target unless precise tap mode is selected.
var touch_mode := false
var _marks: Array = []  # [{pos, ok, reason, t}]
var _banner_t := 0.0
var _font: Font
var _speed_smooth := 0.0
var _frame_ms := 0.0
var _worst_ms := 0.0
var _worst_t := 0.0
var _lines_seed := 0.0
var _perfect_t := 0.0
var _perfect_n := 0
var _lines_boost := 0.0  # extra speed-line burst after a perfect release
## Speed lines start at this speed (m/s) and peak at SPEED_LINES_FULL.
const SPEED_LINES_FROM := 20.0
const SPEED_LINES_FULL := 42.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func web_feedback(pos: Vector2, ok: bool, reason: String) -> void:
	_marks.append({"pos": pos, "ok": ok, "reason": reason, "t": 0.0})
	if _marks.size() > 6:
		_marks.pop_front()


func on_perfect(streak: int) -> void:
	_perfect_t = 0.9
	_perfect_n = streak
	_lines_boost = 1.0


func flash(text: String, seconds := 2.0) -> void:
	banner = text
	_banner_t = seconds


func _process(dt: float) -> void:
	_banner_t -= dt
	_lines_seed += dt
	_perfect_t = maxf(_perfect_t - dt, 0.0)
	_lines_boost = maxf(_lines_boost - dt * 1.6, 0.0)
	for m in _marks:
		m["t"] += dt
	_marks = _marks.filter(func(m): return m["t"] < (0.45 if m["ok"] else 0.9))
	_frame_ms = lerpf(_frame_ms, dt * 1000.0, 0.1)
	_worst_t -= dt
	if dt * 1000.0 > _worst_ms or _worst_t <= 0.0:
		_worst_ms = dt * 1000.0
		_worst_t = 2.0
	queue_redraw()


func _draw() -> void:
	if player == null or camera == null:
		return
	var cam := camera.cam
	var white := Color(1, 1, 1, 0.92)
	var shadow := Color(0, 0, 0, 0.35)
	var gold := Color(1.0, 0.82, 0.4, 0.95)
	_draw_speed_lines()
	# Live anchor marker (where the web is actually stuck).
	if player.line_state != Player.Line.IDLE:
		var a := player.rope_anchor() if player.line_state == Player.Line.ATTACHED else player.line_target
		if not cam.is_position_behind(a):
			var ap := cam.unproject_position(a)
			draw_arc(ap, 7.0, 0, TAU, 20, gold, 2.5, true)
			draw_circle(ap, 2.5, gold)
	if not touch_mode or Settings.aim_mode != "tap":
		# Reticle on the assisted target: where SWING will attach.
		var t := player.targeting
		if t.has_target and player.line_state == Player.Line.IDLE and not cam.is_position_behind(t.point):
			var p := cam.unproject_position(t.point)
			var d := player.hand_position().distance_to(t.point)
			var r := clampf(900.0 / maxf(d, 1.0), 8.0, 22.0)
			draw_arc(p, r, 0, TAU, 32, gold, 3.0, true)
			draw_circle(p, 3.0, gold)
		elif player.line_state == Player.Line.IDLE:
			draw_arc(size / 2.0, 6, 0, TAU, 16, Color(1, 1, 1, 0.3), 1.5, true)
	# Tap feedback: gold pulse = fired, amber ring = holding for a target,
	# red cross + reason = an invalid precise tap.
	for m in _marks:
		var pos: Vector2 = m["pos"]
		var k: float = m["t"]
		if m["ok"]:
			draw_arc(pos, 10.0 + k * 70.0, 0, TAU, 28, Color(1.0, 0.82, 0.4, 1.0 - k / 0.45), 3.0, true)
		elif m["reason"] == "waiting":
			var amber := Color(1.0, 0.82, 0.4, clampf(1.0 - k / 0.9, 0.0, 1.0))
			draw_arc(pos, 16.0 + k * 18.0, 0, TAU, 28, amber, 3.0, true)
			_text(pos + Vector2(20, 5), "hold to catch", 17, amber, shadow)
		else:
			var a2 := clampf(1.0 - (k - 0.5) / 0.4, 0.0, 1.0)
			var red := Color(1.0, 0.32, 0.28, a2)
			draw_line(pos + Vector2(-11, -11), pos + Vector2(11, 11), red, 3.5, true)
			draw_line(pos + Vector2(-11, 11), pos + Vector2(11, -11), red, 3.5, true)
			var label: String = {"sky": "no surface", "street": "street", "too far": "too far", "blocked": "blocked"}.get(m["reason"], m["reason"])
			_text(pos + Vector2(16, 6), label, 18, red, Color(0, 0, 0, 0.4 * a2))

	_speed_smooth = lerpf(_speed_smooth, player.speed(), 0.15)
	var kmh := int(_speed_smooth * 3.6)
	var sx := 36.0
	var sy := 70.0
	_text(Vector2(sx, sy), "%d" % kmh, 44, white, shadow)
	_text(Vector2(sx + 4, sy + 24), "KM/H", 14, Color(1, 1, 1, 0.6), shadow)
	if player.chain > 1:
		_text(Vector2(sx, sy + 58), "CHAIN ×%d" % player.chain, 20, Color(1.0, 0.82, 0.4), shadow)
	if mode_text != "":
		var w := _font.get_string_size(mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_text(Vector2(size.x / 2.0 - w / 2.0, 52), mode_text, 30, white, shadow)
	if mode_sub != "":
		var w2 := _font.get_string_size(mode_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(Vector2(size.x / 2.0 - w2 / 2.0, 76), mode_sub, 16, Color(1, 1, 1, 0.7), shadow)
	if _perfect_t > 0.0:
		# "PERFECT" pops in big, settles, and fades; the streak counts up.
		var age := 0.9 - _perfect_t
		var pop := 1.0 + 0.5 * exp(-age * 14.0)
		var a := clampf(_perfect_t / 0.35, 0.0, 1.0)
		var txt := "PERFECT" if _perfect_n < 2 else "PERFECT ×%d" % _perfect_n
		var fs := int(34 * pop)
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_text(Vector2(size.x / 2.0 - tw / 2.0, size.y * 0.24 - age * 30.0), txt, fs, Color(1.0, 0.82, 0.4, a), Color(0, 0, 0, 0.4 * a))
	if pointer != Vector3.INF:
		_draw_pointer(cam)
	if hint != "":
		var hs := 24
		var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
		var hp := Vector2(size.x / 2.0 - hw / 2.0, 124.0)  # under the mode readout, clear of thumbs
		draw_rect(Rect2(hp + Vector2(-22, -34), Vector2(hw + 44, 50)), Color(0, 0, 0, 0.45))
		_text(hp, hint, hs, white, shadow)
	if _banner_t > 0.0:
		var a := clampf(_banner_t * 2.0, 0.0, 1.0)
		var bw := _font.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		_text(Vector2(size.x / 2.0 - bw / 2.0, size.y * 0.32), banner, 40, Color(1, 1, 1, a), Color(0, 0, 0, 0.4 * a))
	if Settings.show_perf:
		var fps := Engine.get_frames_per_second()
		var lines := [
			"FPS %d  (%.1f ms avg, %.1f worst/2s)" % [fps, _frame_ms, _worst_ms],
			"draw calls %d   prims %dk" % [
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000],
			"objects %d   vram %d MB" % [
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576],
			"quality %s  scale %.2f" % [["LOW", "MEDIUM", "HIGH"][Settings.quality], get_viewport().scaling_3d_scale],
			"rope %.1f m  tension %.0f  E %.0f" % [player.s.rope_length if player.s.attached else 0.0,
				player.s.tension, SwingPhysics.energy(player.s, player.params)],
		]
		var y := size.y - 20.0 - lines.size() * 18.0
		for l in lines:
			_text(Vector2(size.x * 0.3, y), l, 14, Color(0.7, 1.0, 0.7), shadow)
			y += 18.0


## Streaks radiating from the screen centre, scaled by speed. Positions are
## hashed from a slowly ticking seed, so they flicker like wind, not noise.
func _draw_speed_lines() -> void:
	var k := clampf((player.speed() - SPEED_LINES_FROM) / (SPEED_LINES_FULL - SPEED_LINES_FROM), 0.0, 1.0)
	k = maxf(k, _lines_boost * 0.8)
	if k <= 0.0:
		return
	var c := size / 2.0
	var r0 := size.length() * 0.32
	var r1 := size.length() * 0.62
	var tick := int(_lines_seed * 14.0)
	var n := int(10 + k * 22)
	for i in n:
		var h := hash(Vector2i(i, tick))
		var ang := float(h % 3600) / 3600.0 * TAU
		var len := 0.25 + float((h >> 12) % 100) / 100.0 * 0.5
		var a := r0 + float((h >> 20) % 100) / 100.0 * (r1 - r0) * 0.4
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * a, c + d * (a + (r1 - r0) * len), Color(1, 1, 1, 0.12 + 0.33 * k), 2.5, true)


## Marker on the guided point; an edge arrow when it is off screen.
func _draw_pointer(cam: Camera3D) -> void:
	var teal := Color(0.45, 1.0, 0.85, 0.95)
	var dist := player.global_position.distance_to(pointer)
	var label := "%d m" % int(dist)
	var behind := cam.is_position_behind(pointer)
	var sp := cam.unproject_position(pointer)
	var margin := 48.0
	var on := not behind and sp.x > margin and sp.x < size.x - margin and sp.y > margin and sp.y < size.y - margin
	if on:
		var pts := PackedVector2Array([sp + Vector2(0, -12), sp + Vector2(10, 0), sp + Vector2(0, 12), sp + Vector2(-10, 0), sp + Vector2(0, -12)])
		draw_polyline(pts, teal, 2.5, true)
		_text(sp + Vector2(16, 6), label, 16, teal, Color(0, 0, 0, 0.4))
		return
	var c := size / 2.0
	var dir := sp - c
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half := c - Vector2(margin, margin)
	var t := minf(half.x / maxf(absf(dir.x), 1e-4), half.y / maxf(absf(dir.y), 1e-4))
	var p := c + dir * t
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([p + dir * 14.0, p - dir * 8.0 + side * 10.0, p - dir * 8.0 - side * 10.0]), teal)
	_text(p - dir * 30.0 + Vector2(-18, 5), label, 15, teal, Color(0, 0, 0, 0.4))


func _text(pos: Vector2, s: String, fs: int, col: Color, sh: Color) -> void:
	draw_string(_font, pos + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
