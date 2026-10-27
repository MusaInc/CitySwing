class_name Menus
extends Control
## All menu screens, built in code: title (over an attract-mode swing),
## course select, pause, results, settings, live physics tuning, stats.
## Big touch targets; focus-navigable for controllers.

signal start_mode(mode: String, arg: String)
signal resume
signal restart
signal quit_to_title
signal tuning_changed
signal end_session
signal suit_changed(color: Color)

const ACCENT := Color(1.0, 0.76, 0.32)
const PANEL := Color(0.05, 0.06, 0.09, 0.78)

const TUNABLES := [
	# property, label, min, max, step
	["gravity", "Gravity", 9.0, 30.0, 0.5],
	["air_drag", "Air drag", 0.0, 0.006, 0.0002],
	["swing_steer_accel", "Swing steering", 0.0, 12.0, 0.25],
	["swing_pump_bonus", "Pump bonus", 0.0, 1.5, 0.05],
	["air_steer_accel", "Air steering", 0.0, 12.0, 0.25],
	["air_steer_speed_limit", "Air steer speed cap", 0.0, 25.0, 0.5],
	["reel_in_speed", "Web pull strength", 0.0, 16.0, 0.5],
	["auto_tighten_min_fraction", "Shortest pull (of attach length)", 0.3, 1.0, 0.05],
	["jump_speed", "Jump power", 8.0, 24.0, 0.5],
	["grapple_range", "Grapple range", 30.0, 120.0, 1.0],
	["line_speed", "Line speed", 80.0, 600.0, 10.0],
	["attach_length_factor", "Rope length on attach", 0.6, 1.0, 0.02],
]

var params: SwingParams  # live params of the player (tuning edits these)
var _screen: Control
var _theme := Theme.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_theme()
	theme = _theme


func _build_theme() -> void:
	var font := UiStyle.font("bold")
	_theme.default_font = font
	_theme.default_font_size = 26
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.08)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	normal.border_color = Color(1, 1, 1, 0.18)
	normal.set_border_width_all(2)
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.16)
	var focus := normal.duplicate()
	focus.border_color = ACCENT
	focus.set_border_width_all(3)
	focus.bg_color = Color(1, 1, 1, 0.14)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(ACCENT, 0.4)
	for type in ["Button", "CheckButton"]:
		_theme.set_stylebox("normal", type, normal)
		_theme.set_stylebox("hover", type, hover)
		_theme.set_stylebox("focus", type, focus)
		_theme.set_stylebox("pressed", type, pressed)
		_theme.set_color("font_color", type, Color(1, 1, 1, 0.95))
		_theme.set_color("font_hover_color", type, Color.WHITE)
		_theme.set_color("font_focus_color", type, Color.WHITE)
	_theme.set_color("font_color", "Label", Color(1, 1, 1, 0.92))
	_theme.set_constant("separation", "VBoxContainer", 14)
	_theme.set_constant("separation", "HBoxContainer", 16)


# ----------------------------------------------------------------- screens
func show_title() -> void:
	var box := _screen_box(0.5, 0.56)
	var title := _label("CITY SWING", 72, ACCENT)
	box.add_child(title)
	box.add_child(_label("Momentum is everything.", 24, Color(1, 1, 1, 0.75)))
	var mc := Progress.medal_counts()
	box.add_child(_label("%d/%d tokens   ·   %d/%d medals   ·   %d/%d suits" % [SaveData.token_count(),
		Progress.TOKEN_TOTAL, mc[0], CourseBuilder.COURSES.size(), Progress.unlocked_ids().size(),
		Progress.SUITS.size()], 17, Color(1, 1, 1, 0.55)))
	var first: Button
	var trained: bool = SaveData.data["tutorial_done"]
	if not trained:
		first = _button("Training  ·  start here", func(): start_mode.emit("training", ""))
		box.add_child(first)
	var b1 := _button("Free Swing", func(): start_mode.emit("free", ""))
	box.add_child(b1)
	box.add_child(_button("Time Trial", show_courses))
	box.add_child(_button("Endurance", func(): start_mode.emit("endurance", "")))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if trained:
		row.add_child(_button("Training", func(): start_mode.emit("training", "")))
	row.add_child(_button("Suits", show_suits))
	row.add_child(_button("Settings", func(): show_settings(show_title)))
	row.add_child(_button("Stats", show_stats))
	box.add_child(row)
	(first if first else b1).grab_focus.call_deferred()


func show_suits() -> void:
	var box := _screen_box(0.5, 0.5, 720)
	box.add_child(_label("SUITS", 52, ACCENT))
	var current: String = SaveData.data.get("suit", "ember")
	var focus: Button
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	for sd in Progress.SUITS:
		var open := Progress.unlocked(sd)
		var txt: String = sd["name"] if open else "%s  ·  %s" % [sd["name"], sd["hint"]]
		if sd["id"] == current:
			txt = "✓ " + txt
		var id: String = sd["id"]
		var col: Color = sd["color"]
		var b := _button(txt, func():
			if not open:
				return
			SaveData.set_suit(id)
			suit_changed.emit(col)
			show_suits())
		b.custom_minimum_size = Vector2(320, 60)
		b.add_theme_font_size_override("font_size", 20 if open else 16)
		b.icon = _swatch(col, open)
		b.disabled = not open
		grid.add_child(b)
		if sd["id"] == current:
			focus = b
	box.add_child(grid)
	var back := _button("Back", show_title)
	box.add_child(back)
	(focus if focus else back).grab_focus.call_deferred()


func _swatch(c: Color, open: bool) -> ImageTexture:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(c, 1.0) if open else Color(0.3, 0.3, 0.32))
	for i in 28:
		for e in [0, 27]:
			img.set_pixel(i, e, Color(1, 1, 1, 0.6))
			img.set_pixel(e, i, Color(1, 1, 1, 0.6))
	return ImageTexture.create_from_image(img)


func show_courses() -> void:
	var box := _screen_box(0.5, 0.5)
	box.add_child(_label("TIME TRIAL", 52, ACCENT))
	var first: Button
	for id in CourseBuilder.COURSES:
		var c := CourseBuilder.load_course(id)
		if c.is_empty():
			continue
		var best := SaveData.best_trial(id)
		var medal := Progress.medal_for(c["par"], best)
		var txt := "%s     best %s" % [CourseBuilder.COURSES[id]["name"], TimeTrialMode._fmt(best)]
		if medal != Progress.Medal.NONE:
			txt += "   ·   " + Progress.MEDAL_NAMES[medal].to_upper()
		var b := _button(txt, func(): start_mode.emit("trial", id))
		b.tooltip_text = CourseBuilder.COURSES[id]["desc"]
		if medal != Progress.Medal.NONE:
			b.add_theme_color_override("font_color", Progress.MEDAL_COLORS[medal])
		box.add_child(b)
		box.add_child(_label("%s\ngold %s  ·  silver %s  ·  bronze %s" % [CourseBuilder.COURSES[id]["desc"],
			TimeTrialMode._fmt(Progress.medal_target(c["par"], Progress.Medal.GOLD)),
			TimeTrialMode._fmt(Progress.medal_target(c["par"], Progress.Medal.SILVER)),
			TimeTrialMode._fmt(Progress.medal_target(c["par"], Progress.Medal.BRONZE))], 17, Color(1, 1, 1, 0.6)))
		if first == null:
			first = b
	box.add_child(_gap(10))
	box.add_child(_button("Back", show_title))
	if first:
		first.grab_focus.call_deferred()


func show_pause(free_swing := false) -> void:
	var box := _screen_box(0.5, 0.5)
	box.add_child(_label("PAUSED", 56, ACCENT))
	var b := _button("Resume", func(): resume.emit())
	box.add_child(b)
	if free_swing:
		box.add_child(_button("End session", func(): end_session.emit()))
	else:
		box.add_child(_button("Restart", func(): restart.emit()))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_button("Settings", func(): show_settings(show_pause)))
	row.add_child(_button("Tuning", show_tuning))
	box.add_child(row)
	box.add_child(_button("Quit to title", func(): quit_to_title.emit()))
	b.grab_focus.call_deferred()


func show_results(r: Dictionary) -> void:
	var box := _screen_box(0.5, 0.5)
	var headline := ""
	var detail := ""
	match r.get("mode", ""):
		"trial":
			headline = TimeTrialMode._fmt(r["time"])
			detail = "%s   ·   par %s   ·   best %s" % [r["course"], TimeTrialMode._fmt(r["par"]),
				TimeTrialMode._fmt(r["best"])]
		"endurance":
			headline = "%d m" % int(r["distance"])
			detail = "%s   ·   best %d m" % [r["reason"], int(r["best"])]
		"benchmark":
			headline = "%.1f fps" % r["avg_fps"]
			detail = "%s · %s quality · target %d fps" % [r["device"], r["quality"], r["target_fps"]]
			box.add_child(_label(headline, 76, Color.WHITE))
			box.add_child(_label(detail, 22, Color(1, 1, 1, 0.75)))
			box.add_child(_label("avg %.1f ms · 1%% worst %.1f ms · worst %.1f ms · %d/%d frames over 33 ms" % [
				r["avg_ms"], r["p99_ms"], r["worst_ms"], r["frames_over_33ms"], r["frames"]], 20, Color(1, 1, 1, 0.7)))
			box.add_child(_label("%d draw calls · %dk primitives · CPU %.1f ms process + %.1f ms physics (averages)" % [
				int(r["avg_draw_calls"]), int(r["avg_prims"] / 1000.0), r["cpu_process_ms"], r["cpu_physics_ms"]], 18,
				Color(1, 1, 1, 0.55)))
			box.add_child(_label("Saved to benchmark.json", 16, Color(1, 1, 1, 0.45)))
			var bb := _button("Title", func(): quit_to_title.emit())
			box.add_child(bb)
			bb.grab_focus.call_deferred()
			return
		"training":
			headline = "Training complete"
			detail = "You're ready. Free Swing hides %d tokens around the city." % Progress.TOKEN_TOTAL
		_:
			headline = "%.2f km" % (r.get("distance", 0.0) / 1000.0)
			detail = "Free swing   ·   %d token%s this session   ·   %d/%d found" % [r.get("tokens_session", 0),
				"" if r.get("tokens_session", 0) == 1 else "s", r.get("tokens_total", 0), Progress.TOKEN_TOTAL]
	var medal: int = r.get("medal", Progress.Medal.NONE)
	if medal != Progress.Medal.NONE:
		box.add_child(_label("%s MEDAL" % Progress.MEDAL_NAMES[medal].to_upper(), 30, Progress.MEDAL_COLORS[medal]))
	if r.get("new_best", false):
		box.add_child(_label("NEW PERSONAL BEST", 26, ACCENT))
	box.add_child(_label(headline, 76, Color.WHITE))
	box.add_child(_label(detail, 22, Color(1, 1, 1, 0.75)))
	box.add_child(_label("%d swings   ·   longest chain ×%d   ·   top speed %d km/h" % [r.get("swings", 0),
		r.get("chain", 0), int(r.get("top_speed", 0.0) * 3.6)], 20, Color(1, 1, 1, 0.6)))
	for u in r.get("unlocks", []):
		box.add_child(_label("SUIT UNLOCKED: %s" % String(u).to_upper(), 22, Color(0.45, 1.0, 0.85)))
	box.add_child(_gap(14))
	var b: Button
	if r.get("mode", "") == "training":
		b = _button("Free Swing", func(): start_mode.emit("free", ""))
	else:
		b = _button("Go again", func(): restart.emit())
	box.add_child(b)
	box.add_child(_button("Title", func(): quit_to_title.emit()))
	b.grab_focus.call_deferred()


func show_stats() -> void:
	var box := _screen_box(0.5, 0.5)
	var d: Dictionary = SaveData.data
	box.add_child(_label("STATS", 52, ACCENT))
	for line in [
		"Distance swung   %.1f km" % (d["total_distance_m"] / 1000.0),
		"Swings   %d" % d["total_swings"],
		"Top speed   %d km/h" % int(d["top_speed_ms"] * 3.6),
		"Longest chain   ×%d" % d["best_chain"],
		"Endurance best   %d m" % int(d["best_endurance_m"]),
		"Tokens   %d/%d" % [SaveData.token_count(), Progress.TOKEN_TOTAL],
		"Medals   %d/%d   (gold %d)" % [Progress.medal_counts()[0], CourseBuilder.COURSES.size(), Progress.medal_counts()[1]],
		"Time played   %d min" % int(d["play_time_s"] / 60.0),
	]:
		box.add_child(_label(line, 24, Color(1, 1, 1, 0.85)))
	var b := _button("Back", show_title)
	box.add_child(b)
	b.grab_focus.call_deferred()


func show_settings(back: Callable) -> void:
	var box := _screen_box(0.5, 0.5, 760)
	box.add_child(_label("SETTINGS", 48, ACCENT))
	var q := OptionButton.new()
	for n in ["Low (30 fps, 70% scale)", "Medium (30 fps)", "High (60 fps)"]:
		q.add_item(n)
	q.selected = Settings.quality
	q.item_selected.connect(func(i):
		Settings.quality = i
		Settings.save())
	box.add_child(_row("Graphics", q))
	box.add_child(_row("60 FPS", _check(Settings.fps_60, func(v): Settings.fps_60 = v; Settings.save())))
	box.add_child(_row("Haptics", _check(Settings.haptics, func(v): Settings.haptics = v; Settings.save())))
	var aim := OptionButton.new()
	aim.add_item("SWING button (assisted)")
	aim.add_item("Tap buildings + SWING assist")
	aim.selected = 1 if Settings.aim_mode == "tap" else 0
	aim.item_selected.connect(func(i):
		Settings.aim_mode = "tap" if i == 1 else "assist"
		Settings.save())
	box.add_child(_row("Web aiming", aim))
	box.add_child(_row("Performance overlay", _check(Settings.show_perf, func(v): Settings.show_perf = v; Settings.save())))
	box.add_child(_row("Music", _slider(Settings.music_volume, 0.0, 1.0, 0.05, func(v): Settings.music_volume = v; Settings.save())))
	box.add_child(_row("Effects", _slider(Settings.sfx_volume, 0.0, 1.0, 0.05, func(v): Settings.sfx_volume = v; Settings.save())))
	box.add_child(_label("Graphics changes to draw distance apply on next launch.", 16, Color(1, 1, 1, 0.5)))
	box.add_child(_button("Run 45 s benchmark", func(): start_mode.emit("benchmark", "")))
	var b := _button("Back", back)
	box.add_child(b)
	q.grab_focus.call_deferred()


func show_tuning() -> void:
	var box := _screen_box(0.5, 0.5, 820)
	box.add_child(_label("PHYSICS TUNING", 40, ACCENT))
	box.add_child(_label("Live – changes apply immediately and are saved on this device.", 16, Color(1, 1, 1, 0.55)))
	var first: Control
	for t in TUNABLES:
		var prop: String = t[0]
		var val: float = params.get(prop)
		var value_label := _label(_fmt_val(val, t[4]), 18, ACCENT)
		var s := _slider(val, t[2], t[3], t[4], func(v):
			params.set(prop, v)
			Settings.tuning_overrides[prop] = v
			value_label.text = _fmt_val(v, t[4])
			tuning_changed.emit())
		var row := _row(t[1], s)
		row.add_child(value_label)
		box.add_child(row)
		if first == null:
			first = s
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_child(_button("Save", func(): Settings.save()))
	row2.add_child(_button("Reset defaults", func():
		Settings.tuning_overrides = {}
		Settings.save()
		var fresh: SwingParams = load("res://config/swing_params.tres")
		for t in TUNABLES:
			params.set(t[0], fresh.get(t[0]))
		show_tuning()))
	row2.add_child(_button("Back", func():
		Settings.save()
		show_pause()))
	box.add_child(row2)
	first.grab_focus.call_deferred()


func hide_all() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
	visible = false


# ----------------------------------------------------------------- helpers
func _screen_box(x: float, y: float, width := 640) -> VBoxContainer:
	if _screen:
		_screen.queue_free()
	visible = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(34)
	panel.add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(width, 0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	panel.add_child(scroll)
	root.add_child(panel)
	add_child(root)
	_screen = root
	# Centre the panel; cap height to the viewport so long screens scroll.
	var fit := func():
		var vp := get_viewport_rect().size
		var h := minf(box.get_combined_minimum_size().y, vp.y - 120.0)
		scroll.custom_minimum_size.y = h
		panel.reset_size()
		panel.position = Vector2(vp.x * x, vp.y * y) - panel.size * 0.5
	fit.call_deferred()
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 40:  # headings
		l.add_theme_font_override("font", UiStyle.font("black"))
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(func():
		Settings.haptic(6, 0.25)
		cb.call())
	return b


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", 22)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _check(value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.custom_minimum_size = Vector2(0, 56)
	c.toggled.connect(cb)
	return c


func _slider(value: float, lo: float, hi: float, step: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 48)
	s.value_changed.connect(cb)
	return s


static func _fmt_val(v: float, step: float) -> String:
	return ("%.4f" % v) if step < 0.001 else (("%.2f" % v) if step < 0.1 else ("%.1f" % v))
