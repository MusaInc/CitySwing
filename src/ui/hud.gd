class_name Hud
extends Control
## Reticle, speed, chain counter, mode readout and the performance overlay.

var player: Player
var camera: SwingCamera
var mode_text := ""
var mode_sub := ""
var banner := ""
## Touch play: no auto-target reticle; tap feedback instead.
var touch_mode := false
var _marks: Array = []  # [{pos, ok, reason, t}]
var _banner_t := 0.0
var _font: Font
var _speed_smooth := 0.0
var _frame_ms := 0.0
var _worst_ms := 0.0
var _worst_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func web_feedback(pos: Vector2, ok: bool, reason: String) -> void:
	_marks.append({"pos": pos, "ok": ok, "reason": reason, "t": 0.0})
	if _marks.size() > 6:
		_marks.pop_front()


func flash(text: String, seconds := 2.0) -> void:
	banner = text
	_banner_t = seconds


func _process(dt: float) -> void:
	_banner_t -= dt
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
	# Live anchor marker (where the web is actually stuck).
	if player.line_state != Player.Line.IDLE:
		var a := player.rope_anchor() if player.line_state == Player.Line.ATTACHED else player.line_target
		if not cam.is_position_behind(a):
			var ap := cam.unproject_position(a)
			draw_arc(ap, 7.0, 0, TAU, 20, gold, 2.5, true)
			draw_circle(ap, 2.5, gold)
	if not touch_mode:
		# Controller/keyboard: reticle on the assisted target.
		var t := player.targeting
		if t.has_target and player.line_state == Player.Line.IDLE and not cam.is_position_behind(t.point):
			var p := cam.unproject_position(t.point)
			var d := player.hand_position().distance_to(t.point)
			var r := clampf(900.0 / maxf(d, 1.0), 8.0, 22.0)
			draw_arc(p, r, 0, TAU, 32, gold, 3.0, true)
			draw_circle(p, 3.0, gold)
		elif player.line_state == Player.Line.IDLE:
			draw_arc(size / 2.0, 6, 0, TAU, 16, Color(1, 1, 1, 0.3), 1.5, true)
	# Tap feedback: gold pulse = web fired here; red cross + reason = rejected.
	for m in _marks:
		var pos: Vector2 = m["pos"]
		var k: float = m["t"]
		if m["ok"]:
			draw_arc(pos, 10.0 + k * 70.0, 0, TAU, 28, Color(1.0, 0.82, 0.4, 1.0 - k / 0.45), 3.0, true)
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


func _text(pos: Vector2, s: String, fs: int, col: Color, sh: Color) -> void:
	draw_string(_font, pos + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
