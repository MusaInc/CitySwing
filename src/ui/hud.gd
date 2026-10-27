class_name Hud
extends Control
## Reticle, speed, chain counter, mode readout and the performance overlay.

var player: Player
var camera: SwingCamera
var mode_text := ""
var mode_sub := ""
var banner := ""
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


func flash(text: String, seconds := 2.0) -> void:
	banner = text
	_banner_t = seconds


func _process(dt: float) -> void:
	_banner_t -= dt
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
	# Reticle on the predicted anchor.
	var t := player.targeting
	if t.has_target and player.line_state == Player.Line.IDLE and not cam.is_position_behind(t.point):
		var p := cam.unproject_position(t.point)
		var d := player.hand_position().distance_to(t.point)
		var r := clampf(900.0 / maxf(d, 1.0), 8.0, 22.0)
		draw_arc(p, r, 0, TAU, 32, Color(1.0, 0.82, 0.4, 0.95), 3.0, true)
		draw_circle(p, 3.0, Color(1.0, 0.82, 0.4, 0.95))
	elif player.line_state == Player.Line.IDLE:
		var c := size / 2.0
		draw_arc(c, 6, 0, TAU, 16, Color(1, 1, 1, 0.3), 1.5, true)

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
