class_name Hud
extends Control
## Reticle, speed, chain counter, mode readout and the performance overlay.
## The reticle sits on the web pick (the swing GrappleTargeting actually
## chose by flying it) and a dotted line previews that swing's path, so
## steering with the stick shows where it will take you.

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
## Something to use within reach at home ("" = none). On touch the controls
## draw it as a button; otherwise the HUD shows it with the key.
var prompt := ""
var coins: CoinMeter
## Live map at the top centre (src/ui/minimap.gd).
var minimap: Minimap
var gadgets: Gadgets
## Free Swing contracts (src/modes/job_board.gd); null elsewhere.
var jobs: JobBoard
const GADGET_NAMES := {"boost": "JET BOOST", "glide": "GLIDE", "focus": "SLOW-MO", "surge": "DOUBLE COINS"}
var _coin_shown := -1.0    # rolling balance readout
var _gain := 0             # coins in the current "+n" burst
var _gain_t := 0.0
var _mult_pop := 0.0       # multiplier step-up pop (s remaining)
var _lost_t := 0.0         # multiplier lost flash (s remaining, real time)
var _lost_from := 1.0
var _marks: Array = []  # [{pos, ok, reason, t}]
var _banner_t := 0.0
var _font: Font
var _font_black: Font
var _reticle_spin := 0.0
var _ko_t := 0.0           # knockout flash + banner (s remaining, real time)
var _ko_kmh := 0
const KO_TIME := 2.2
var _reticle_pos := Vector2.INF
var _speed_smooth := 0.0
var _frame_ms := 0.0
var _worst_ms := 0.0
var _worst_t := 0.0
var _lines_seed := 0.0
var _perfect_t := 0.0
var _close_t := 0.0        # "CLOSE CALL" callout timer
var _close_txt := ""
var _perfect_n := 0
var _lines_boost := 0.0  # extra speed-line burst after a perfect release
## Speed lines start at this speed (m/s) and peak at SPEED_LINES_FULL.
const SPEED_LINES_FROM := 20.0
const SPEED_LINES_FULL := 42.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiStyle.font("bold")
	_font_black = UiStyle.font("black")
	minimap = Minimap.new()
	minimap.name = "Minimap"
	add_child(minimap)


func web_feedback(pos: Vector2, ok: bool, reason: String) -> void:
	_marks.append({"pos": pos, "ok": ok, "reason": reason, "t": 0.0})
	if _marks.size() > 6:
		_marks.pop_front()


func on_perfect(streak: int) -> void:
	_perfect_t = 0.9
	_perfect_n = streak
	_lines_boost = 1.0


## Close call past a facade: a quick white/cyan callout under PERFECT.
func on_close_call(razor: bool, coins_won: int) -> void:
	_close_t = 0.8
	_close_txt = ("RAZOR CLOSE" if razor else "CLOSE CALL") + ("  +%d" % coins_won if coins_won > 0 else "")
	_lines_boost = maxf(_lines_boost, 0.6)


## Wall knockout: red flash from the edges and a shaking KNOCKED OUT.
func on_knockout(speed: float) -> void:
	_ko_t = KO_TIME
	_ko_kmh = int(speed * 3.6)


func on_gadget(kind: String) -> void:
	flash(GADGET_NAMES.get(kind, ""), 0.9)


func on_coins(n: int) -> void:
	_gain = (_gain if _gain_t > 0.0 else 0) + n
	_gain_t = 1.1


func on_multiplier(_mult: float, up: bool, from: float) -> void:
	if up:
		_mult_pop = 0.6
	else:
		_lost_t = KO_TIME
		_lost_from = from


func flash(text: String, seconds := 2.0) -> void:
	banner = text
	_banner_t = seconds


func _process(dt: float) -> void:
	if minimap:
		# Responsive: ~22% of the short side, inside the safe area (clear of
		# the Dynamic Island / notch in landscape: it's centred, below the top).
		var d := clampf(minf(size.x, size.y) * 0.22, 104.0, 196.0)
		minimap.size = Vector2(d, d)
		minimap.position = Vector2(size.x * 0.5 - d * 0.5, _safe_origin().y + 10.0)
	_banner_t -= dt
	_lines_seed += dt
	_perfect_t = maxf(_perfect_t - dt, 0.0)
	_close_t = maxf(_close_t - dt, 0.0)
	_lines_boost = maxf(_lines_boost - dt * 1.6, 0.0)
	_reticle_spin += dt * 1.4
	_ko_t = maxf(_ko_t - dt / maxf(Engine.time_scale, 0.05), 0.0)
	_lost_t = maxf(_lost_t - dt / maxf(Engine.time_scale, 0.05), 0.0)
	_gain_t = maxf(_gain_t - dt, 0.0)
	_mult_pop = maxf(_mult_pop - dt, 0.0)
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
	if prompt != "" and not touch_mode:
		var sz := get_viewport_rect().size
		TouchControls.draw_use_prompt(self, _font, Rect2(Vector2(sz.x * 0.5 - 140.0, sz.y - 120.0), Vector2(280.0, 60.0)),
			prompt, true)
	# Live anchor marker (where the web is actually stuck).
	if player.line_state != Player.Line.IDLE:
		var a := player.rope_anchor() if player.line_state == Player.Line.ATTACHED else player.line_target
		if not cam.is_position_behind(a):
			var ap := cam.unproject_position(a)
			draw_arc(ap, 7.0, 0, TAU, 20, gold, 2.5, true)
			draw_circle(ap, 2.5, gold)
	if (not touch_mode or Settings.aim_mode != "tap") and not player.stunned:
		# Reticle on the web pick: where SWING will attach.
		var t := player.targeting
		var aim_pt := t.pick if t.pick_ok else t.point
		if t.has_target and player.line_state == Player.Line.IDLE and not cam.is_position_behind(aim_pt):
			if t.pick_ok and not player.is_on_floor():
				_draw_path(cam, t.pick_path)
			var p := cam.unproject_position(aim_pt)
			# Glide between picks instead of jumping.
			_reticle_pos = p if _reticle_pos == Vector2.INF or _reticle_pos.distance_to(p) > 260.0 \
				else _reticle_pos.lerp(p, 0.35)
			var d := player.hand_position().distance_to(aim_pt)
			var r := clampf(900.0 / maxf(d, 1.0), 11.0, 24.0)
			_draw_reticle(_reticle_pos, r, gold if t.pick_ok else Color(1, 1, 1, 0.8))
			if t.pick_ok:
				# A soft ring breathing out from a ready anchor: "SWING now works here".
				var ph := fmod(_reticle_spin * 1.6, 1.0)
				draw_arc(_reticle_pos, r + 4.0 + ph * 14.0, 0, TAU, 28, Color(gold, 0.5 * (1.0 - ph)), 2.0, true)
		elif player.line_state == Player.Line.IDLE:
			_reticle_pos = Vector2.INF
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
	# Top-left corner inside the safe area (clear of the notch / Dynamic
	# Island on iPhones held in landscape).
	var g := _safe_origin() + Vector2(86, 86)
	_draw_speed_gauge(g, white, shadow)
	if coins and coins.active:
		_draw_coins(g + Vector2(78, -50), white, shadow)
	if player.chain > 1:
		var ct := "CHAIN ×%d" % player.chain
		var cw := _font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		UiStyle.pill(self, Rect2(Vector2(g.x - cw / 2.0 - 14, g.y + 64), Vector2(cw + 28, 30)), Color(UiStyle.GOLD, 0.22))
		_text(Vector2(g.x - cw / 2.0, g.y + 85), ct, 18, gold, shadow)
	if mode_text != "":
		# Mode readout (trial clock, endurance distance, training step):
		# compact, just under the minimap.
		var ty := minimap.position.y + minimap.size.y + 8.0 if minimap and minimap.visible else 22.0
		var w := _font.get_string_size(mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var w2 := _font.get_string_size(mode_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x if mode_sub != "" else 0.0
		var pw := maxf(w, w2) + 32.0
		UiStyle.pill(self, Rect2(Vector2(size.x / 2.0 - pw / 2.0, ty), Vector2(pw, 50 if mode_sub != "" else 34)))
		_text(Vector2(size.x / 2.0 - w / 2.0, ty + 25), mode_text, 22, white, shadow)
		if mode_sub != "":
			_text(Vector2(size.x / 2.0 - w2 / 2.0, ty + 42), mode_sub, 13, Color(1, 1, 1, 0.7), shadow)
	if _perfect_t > 0.0:
		# "PERFECT" pops in big, settles, and fades; the streak counts up.
		var age := 0.9 - _perfect_t
		var pop := 1.0 + 0.5 * exp(-age * 14.0)
		var a := clampf(_perfect_t / 0.35, 0.0, 1.0)
		var txt := "PERFECT" if _perfect_n < 2 else "PERFECT ×%d" % _perfect_n
		var fs := int(36 * pop)
		var tw := _font_black.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pp := Vector2(size.x / 2.0 - tw / 2.0, size.y * 0.24 - age * 30.0)
		draw_string(_font_black, pp + Vector2(2, 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4 * a))
		draw_string(_font_black, pp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.82, 0.4, a))
	if _close_t > 0.0:
		# Slides in from the side it happened on feel: a small, fast callout
		# (lower and lighter than PERFECT so the two can share the screen).
		var age := 0.8 - _close_t
		var a := clampf(_close_t / 0.3, 0.0, 1.0)
		var fs := int(24 * (1.0 + 0.35 * exp(-age * 16.0)))
		var tw := _font_black.get_string_size(_close_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pp := Vector2(size.x / 2.0 - tw / 2.0, size.y * 0.32 - age * 18.0)
		draw_string(_font_black, pp + Vector2(2, 3), _close_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4 * a))
		draw_string(_font_black, pp, _close_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.75, 0.95, 1.0, a))
	if jobs:
		_draw_jobs(cam, white, shadow)
	if pointer != Vector3.INF:
		_draw_pointer(cam)
	if gadgets and gadgets.enabled and gadgets.kind() != "":
		_draw_gadget_status(white, shadow)
	if _ko_t > 0.0:
		_draw_knockout()
	if hint != "":
		var hs := 24
		var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
		var hp := Vector2(size.x / 2.0 - hw / 2.0, 132.0)  # under the mode readout, clear of thumbs
		UiStyle.pill(self, Rect2(hp + Vector2(-26, -34), Vector2(hw + 52, 48)), Color(0, 0, 0, 0.5))
		_text(hp, hint, hs, white, shadow)
	if _banner_t > 0.0:
		var a := clampf(_banner_t * 2.0, 0.0, 1.0)
		var bw := _font_black.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		draw_string(_font_black, Vector2(size.x / 2.0 - bw / 2.0 + 2, size.y * 0.32 + 3), banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0, 0, 0, 0.4 * a))
		draw_string(_font_black, Vector2(size.x / 2.0 - bw / 2.0, size.y * 0.32), banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1, 1, 1, a))
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


func _draw_knockout() -> void:
	var age := KO_TIME - _ko_t
	var a := clampf(_ko_t / 0.6, 0.0, 1.0)
	# Edge vignette: strong at the hit, fading.
	var hit := exp(-age * 3.0)
	for i in 6:
		var inset := i * 14.0
		var col := Color(0.85, 0.05, 0.04, (0.32 - i * 0.05) * (0.35 + 0.65 * hit) * a)
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), col, false, 16.0)
	var shake := Vector2(sin(age * 53.0), sin(age * 47.0 + 1.0)) * 7.0 * exp(-age * 4.0)
	var pop := 1.0 + 0.6 * exp(-age * 12.0)
	var fs := int(56 * pop)
	var txt := "KNOCKED OUT"
	var tw := _font_black.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(size.x / 2.0 - tw / 2.0, size.y * 0.36) + shake
	draw_string(_font_black, p + Vector2(3, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5 * a))
	draw_string(_font_black, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.32, 0.26, a))
	var sub := "WALL · %d KM/H" % _ko_kmh
	var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_text(Vector2(size.x / 2.0 - sw / 2.0, size.y * 0.36 + 32), sub, 18, Color(1, 1, 1, 0.8 * a), Color(0, 0, 0, 0.4 * a))
	if _lost_t > 0.0:
		var lt := "×%s MULTIPLIER LOST" % _fmt_mult(_lost_from)
		var lw := _font_black.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var lp := Vector2(size.x / 2.0 - lw / 2.0, size.y * 0.36 + 64)
		draw_string(_font_black, lp + Vector2(2, 2), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.45 * a))
		draw_string(_font_black, lp, lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UiStyle.GOLD, a))


## Coin balance (rolling up as coins come in, with a "+n" burst) over the
## multiplier and its progress to the next step. Top-left, right of the
## speed gauge.
func _draw_coins(p: Vector2, white: Color, shadow: Color) -> void:
	var bal := float(SaveData.data.get("coins", 0))
	_coin_shown = bal if _coin_shown < 0.0 or absf(bal - _coin_shown) > 5000.0 else move_toward(_coin_shown, bal,
		maxf(absf(bal - _coin_shown) * 0.12, 0.5))
	var txt := _fmt_int(int(round(_coin_shown)))
	var tw := _font_black.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	UiStyle.pill(self, Rect2(p, Vector2(tw + 62, 40)), Color(0, 0, 0, 0.32))
	draw_coin(self, p + Vector2(21, 20), 11.0)
	draw_string(_font_black, p + Vector2(40, 30), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, shadow)
	draw_string(_font_black, p + Vector2(38, 28), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, white)
	if _gain_t > 0.0:
		var ga := clampf(_gain_t / 0.4, 0.0, 1.0)
		var gp := p + Vector2(tw + 72, 29 - (1.1 - _gain_t) * 10.0)
		draw_string(_font_black, gp + Vector2(2, 2), "+%d" % _gain, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.4 * ga))
		draw_string(_font_black, gp, "+%d" % _gain, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UiStyle.GOLD, ga))
	# Multiplier: warms from white to gold as it climbs; pops on each step.
	var m := coins.multiplier()
	var hot := clampf((m - 1.0) / (CoinMeter.MAX_MULT - 1.0), 0.0, 1.0)
	var col := Color(1, 1, 1, 0.92).lerp(UiStyle.GOLD, minf(hot * 2.0, 1.0))
	var pop := 1.0 + 0.45 * (_mult_pop / 0.6) * (_mult_pop / 0.6)
	var fs := int(30 * pop)
	var mt := "×%s" % _fmt_mult(m)
	var mp := p + Vector2(4, 80)
	draw_string(_font_black, mp + Vector2(2, 3), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, shadow)
	draw_string(_font_black, mp, mt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var bar := Rect2(p + Vector2(6, 90), Vector2(96, 6))
	UiStyle.pill(self, bar, Color(1, 1, 1, 0.18))
	var k := coins.level_progress()
	if k > 0.02:
		UiStyle.pill(self, Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), col)


## Gadget readiness. On touch the GADGET button shows it; with keys/pad a
## small badge bottom-right ("E" / X) does, plus a bar while it runs.
func _draw_gadget_status(white: Color, shadow: Color) -> void:
	if gadgets.running():
		var left: float = gadgets.active_t / maxf(float(gadgets.item.get("duration", 1.0)), 0.01)
		var r := Rect2(Vector2(size.x / 2.0 - 90, size.y * 0.32 + 18), Vector2(180, 8))
		UiStyle.pill(self, r, Color(0, 0, 0, 0.35))
		UiStyle.pill(self, Rect2(r.position, Vector2(r.size.x * left, r.size.y)), Color(UiStyle.TEAL, 0.9))
	if touch_mode:
		return
	var c := size - Vector2(70, 70)
	var ready := gadgets.ready_to_use()
	draw_circle(c, 40.0, Color(UiStyle.INK, 0.45))
	var k := gadgets.charge()
	draw_arc(c, 38.0, -PI / 2, -PI / 2 + TAU * k, maxi(4, int(40 * k)), UiStyle.GOLD if ready else Color(1, 1, 1, 0.5),
		4.0, true)
	MenuParts.draw_gadget(self, gadgets.kind(), c, 34.0, white if ready or gadgets.running() else Color(1, 1, 1, 0.45))
	_text(c + Vector2(-58, -30), "E", 18, white if ready else Color(1, 1, 1, 0.5), shadow)


## A gold coin (also used by the shop).
static func draw_coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, Color(0.78, 0.52, 0.12))
	ci.draw_circle(c + Vector2(0, -0.8), r * 0.86, UiStyle.GOLD)
	ci.draw_arc(c + Vector2(0, -0.8), r * 0.56, 0, TAU, 20, Color(0.78, 0.52, 0.12), maxf(1.5, r * 0.14), true)


static func _fmt_mult(m: float) -> String:
	return ("%d" % int(m)) if is_equal_approx(m, round(m)) else ("%.1f" % m)


static func _fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Speed: a 270° gauge (full at 144 km/h) that warms from white to gold
## once speed lines kick in, with the number in the middle.
func _draw_speed_gauge(c: Vector2, white: Color, shadow: Color) -> void:
	var r := 52.0
	var a0 := PI * 0.75
	var sweep := PI * 1.5
	var k := clampf(_speed_smooth / 40.0, 0.0, 1.0)
	draw_circle(c, r + 6.0, Color(UiStyle.INK, 0.45))
	draw_arc(c, r, a0, a0 + sweep, 48, Color(1, 1, 1, 0.16), 6.0, true)
	if k > 0.005:
		var hot := clampf((_speed_smooth - SPEED_LINES_FROM) / (SPEED_LINES_FULL - SPEED_LINES_FROM), 0.0, 1.0)
		draw_arc(c, r, a0, a0 + sweep * k, maxi(4, int(48 * k)), Color(1, 1, 1, 0.9).lerp(UiStyle.GOLD, hot), 6.0, true)
	var txt := "%d" % int(_speed_smooth * 3.6)
	var tw := _font_black.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	draw_string(_font_black, c + Vector2(-tw / 2.0 + 2, 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, shadow)
	draw_string(_font_black, c + Vector2(-tw / 2.0, 10), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, white)
	var uw := _font.get_string_size("KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(_font, c + Vector2(-uw / 2.0, 30), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))


## Four corner brackets turning slowly round a dot.
func _draw_reticle(p: Vector2, r: float, col: Color) -> void:
	for i in 4:
		var a := _reticle_spin + i * PI * 0.5
		draw_arc(p, r, a - 0.42, a + 0.42, 8, Color(0, 0, 0, 0.35), 5.0, true)
		draw_arc(p, r, a - 0.42, a + 0.42, 8, col, 3.0, true)
	draw_circle(p, 3.5, col)


## The predicted swing as fading dots (screen-projected body path).
func _draw_path(cam: Camera3D, path: PackedVector3Array) -> void:
	var n := path.size()
	for i in range(1, n):
		if cam.is_position_behind(path[i]):
			continue
		var a := 0.55 * (1.0 - float(i) / n)
		draw_circle(cam.unproject_position(path[i]), 3.0, Color(1.0, 0.82, 0.4, a))


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
	if jobs and not jobs.active.is_empty():
		teal = Color(JobBoard.COL_GOAL, 0.97)
	var dist := player.global_position.distance_to(pointer)
	var label := "%d m" % int(dist)
	var behind := cam.is_position_behind(pointer)
	var sp := cam.unproject_position(pointer)
	var margin := 48.0
	var on := not behind and sp.x > margin and sp.x < size.x - margin and sp.y > margin and sp.y < size.y - margin \
		and not (sp.x < 340.0 and sp.y < 200.0)
	if on:
		sp = _clear_of_thumbs(sp)
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
	if p.x < 340.0 and p.y < 200.0:
		p.y = 200.0  # keep clear of the speed gauge
	p = _clear_of_thumbs(p)
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([p + dir * 14.0, p - dir * 8.0 + side * 10.0, p - dir * 8.0 - side * 10.0]), teal)
	_text(p - dir * 30.0 + Vector2(-18, 5), label, 15, teal, Color(0, 0, 0, 0.4))


## Contracts: labels over offer beacons, the active job's card (top right,
## left of pause), heist crack progress and the settle toast.
func _draw_jobs(cam: Camera3D, white: Color, shadow: Color) -> void:
	var pp := player.global_position
	if jobs.active.is_empty():
		# At most three labels (tracked first, then nearest), and they fade
		# out at swing speed: the beacons themselves carry the city view.
		var calm := 1.0 - smoothstep(16.0, 26.0, player.speed())
		var list: Array = jobs.offers.duplicate()
		list.sort_custom(func(a, b):
			if (a["id"] == jobs.tracked) != (b["id"] == jobs.tracked):
				return a["id"] == jobs.tracked
			return pp.distance_squared_to(a["start"]) < pp.distance_squared_to(b["start"]))
		var shown := 0
		for o in list:
			if shown >= 3 or calm <= 0.02:
				break
			var at: Vector3 = (o["start"] as Vector3) + Vector3.UP * 5.0
			var d := pp.distance_to(at)
			if d > 650.0 or d < 6.0 or cam.is_position_behind(at):
				continue
			shown += 1
			var sp := cam.unproject_position(at)
			if sp.x < 0.0 or sp.x > size.x or sp.y < 0.0 or sp.y > size.y:
				continue
			var col: Color = JobBoard.COL_LEGAL if o["legal"] else JobBoard.COL_CRIME
			var a := clampf(1.4 - d / 650.0, 0.35, 1.0) * (1.0 if o["id"] == jobs.tracked or d < 300.0 else 0.75) * calm
			var t1: String = o["title"].to_upper()
			var t2 := "%s  ·  %d m" % [_fmt_int(o["pay"]), int(d)]
			var fs := 15 if d < 250.0 else 13
			var w := maxf(_font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
				_font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2).x + 16.0) + 22.0
			var r := Rect2(sp - Vector2(w * 0.5, 40.0), Vector2(w, 38.0))
			UiStyle.pill(self, r, Color(UiStyle.INK, 0.62 * a))
			draw_rect(Rect2(r.position + Vector2(8, 6), Vector2(3, 26)), Color(col, a))
			_text(r.position + Vector2(16, 17), t1, fs, Color(col, a), Color(shadow, shadow.a * a))
			_coin_glyph(r.position + Vector2(22, 29), 5.0, a)
			_text(r.position + Vector2(31, 33), t2, fs - 2, Color(1, 1, 1, 0.85 * a), Color(shadow, shadow.a * a))
		if not jobs.hold_offer.is_empty():
			var k := clampf(jobs.hold_t / Contracts.HOLD_TIME, 0.0, 1.0)
			var c := size * Vector2(0.5, 0.62)
			draw_arc(c, 34.0, 0.0, TAU, 40, Color(UiStyle.INK, 0.5), 9.0, true)
			draw_arc(c, 34.0, -PI * 0.5, -PI * 0.5 + TAU * k, 40, JobBoard.COL_CRIME, 6.0, true)
			_text(c + Vector2(-46, 62), "HOLD STILL", 16, white, shadow)
	else:
		_draw_job_card(white, shadow)
	if not jobs.toast.is_empty():
		_draw_job_toast(white, shadow)


func _coin_glyph(c: Vector2, r: float, a: float) -> void:
	draw_circle(c, r, Color(UiStyle.GOLD, a))
	draw_circle(c, r * 0.55, Color(0.85, 0.6, 0.1, a))


func _draw_job_card(white: Color, shadow: Color) -> void:
	var c: Dictionary = jobs.active
	var legal: bool = c["legal"]
	var col: Color = JobBoard.COL_LEGAL if legal else JobBoard.COL_CRIME
	var w := 272.0
	var h := 96.0 if legal else 126.0
	var origin := Vector2(size.x - _safe_origin().x - 92.0 - w, _safe_origin().y + 18.0)
	var r := Rect2(origin, Vector2(w, h))
	UiStyle.pill(self, r, Color(UiStyle.INK, 0.6))
	draw_rect(Rect2(origin + Vector2(10, 12), Vector2(3, h - 24)), col)
	var stops: int = (c["stops"] as Array).size()
	var title: String = c["title"].to_upper()
	if stops > 1:
		title += "  %d/%d" % [jobs.stage, stops]
	_text(origin + Vector2(22, 26), title, 15, col, shadow)
	var obj: String = {"rescue": "Land on the medic roof", "survey": "Fly through the survey point",
		"heist": "Get the case to the fence", "getaway": "Land at the safehouse"}.get(c["type"], "Land on the drop roof")
	var dist := player.global_position.distance_to(jobs.objective())
	_text(origin + Vector2(22, 48), obj, 14, Color(1, 1, 1, 0.78), shadow)
	# Clock: big, turns red in the last 15 s.
	var tl := maxf(jobs.time_left, 0.0)
	var urgent := tl < 15.0
	var clock := "%d:%02d" % [int(tl) / 60, int(tl) % 60]
	var cc := Color(1.0, 0.36, 0.3) if urgent and fmod(tl, 1.0) > 0.35 else white
	draw_string(_font_black, origin + Vector2(22, 84), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, cc)
	var right := "%d m" % int(dist)
	var rw := _font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_text(origin + Vector2(w - rw - 18, 82), right, 17, white, shadow)
	var pay := "%s" % _fmt_int(c["pay"])
	var pw := _font.get_string_size(pay, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_coin_glyph(origin + Vector2(w - pw - 30, 21), 6.0, 1.0)
	_text(origin + Vector2(w - pw - 18, 26), pay, 15, white, shadow)
	if not legal:
		# Heat: fills toward BUSTED; flashes while a drone has you.
		var bar := Rect2(origin + Vector2(22, 98), Vector2(w - 44, 7))
		draw_rect(bar, Color(1, 1, 1, 0.12))
		var hc := Color(1.0, 0.75, 0.2).lerp(Color(1.0, 0.2, 0.15), jobs.heat)
		if jobs.spotted and fmod(Time.get_ticks_msec() / 1000.0, 0.4) < 0.2:
			hc = hc.lightened(0.35)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * jobs.heat, bar.size.y)), hc)
		var ht := "SPOTTED" if jobs.spotted else "HEAT"
		var hw := _font.get_string_size(ht, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_text(origin + Vector2(w - 22 - hw, 116), ht, 11, Color(hc, 0.95), shadow)
		if jobs._drones.size() > 0:
			_text(origin + Vector2(22, 116), "%d DRONE%s" % [jobs._drones.size(), "" if jobs._drones.size() == 1 else "S"],
				11, Color(1, 1, 1, 0.6), shadow)
	elif c["type"] == "express" and jobs.knockouts > 0:
		_text(origin + Vector2(110, 82), "−%d%%" % int(minf(jobs.knockouts * Contracts.EXPRESS_KO_CUT,
			1.0 - Contracts.EXPRESS_FLOOR) * 100.0), 15, Color(1.0, 0.45, 0.35), shadow)


func _draw_job_toast(white: Color, shadow: Color) -> void:
	var t: Dictionary = jobs.toast
	var age: float = t["t"]
	var a := clampf(minf(age / 0.25, (4.5 - age) / 0.6), 0.0, 1.0)
	var ok: bool = t["outcome"] == "done"
	var head: String = {"done": "CONTRACT COMPLETE", "late": "OUT OF TIME", "busted": "BUSTED",
		"abandoned": "CONTRACT DROPPED"}[t["outcome"]]
	var sub := ""
	if ok:
		sub = "+%s coins  ·  +%d rep" % [_fmt_int(t["coins"]), t["rep"]]
		if int(t["bonus"]) > 0:
			sub += "  ·  time bonus %s" % _fmt_int(t["bonus"])
	elif int(t["coins"]) < 0:
		sub = "Fined %s coins" % _fmt_int(-int(t["coins"]))
	else:
		sub = String(t["title"])
	var fs := int(38 * (1.0 + 0.25 * exp(-age * 10.0)))
	var hw := _font_black.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := maxf(size.y * 0.36, (minimap.position.y + minimap.size.y + 60.0) if minimap else 0.0)
	var hc := Color(UiStyle.GOLD, a) if ok else Color(1.0, 0.38, 0.3, a)
	draw_string(_font_black, Vector2(size.x / 2.0 - hw / 2.0 + 2, y + 3), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4 * a))
	draw_string(_font_black, Vector2(size.x / 2.0 - hw / 2.0, y), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hc)
	var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_text(Vector2(size.x / 2.0 - sw / 2.0, y + 32), sub, 20, Color(white, a), Color(shadow, shadow.a * a))
	if t["rank_up"]:
		var rt := "RANK UP — %s" % String(t["rank"]).to_upper()
		var rw := _font_black.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		UiStyle.pill(self, Rect2(Vector2(size.x / 2.0 - rw / 2.0 - 18, y + 46), Vector2(rw + 36, 36)), Color(UiStyle.GOLD, 0.9 * a))
		draw_string(_font_black, Vector2(size.x / 2.0 - rw / 2.0, y + 72), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UiStyle.INK, a))


## Safe-area top-left in HUD pixels (zero on desktop).
func _safe_origin() -> Vector2:
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if sa.size.x <= 0 or win.x <= 0 or DisplayServer.screen_get_size() != win:
		return Vector2.ZERO  # (windowed on desktop: screen-space safe area doesn't apply)
	return (Vector2(sa.position) * size / Vector2(win)).clamp(Vector2.ZERO, size * 0.2)


## Markers never sit under the stick (bottom left) or SWING/JUMP (bottom
## right) in touch mode: pushed up above those zones.
func _clear_of_thumbs(p: Vector2) -> Vector2:
	if not touch_mode:
		return p
	var top := size.y - (390.0 if gadgets and gadgets.kind() != "" else 270.0)
	if p.y > top and (p.x < 330.0 or p.x > size.x - 480.0):
		p.y = top
	return p


func _text(pos: Vector2, s: String, fs: int, col: Color, sh: Color) -> void:
	draw_string(_font, pos + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
