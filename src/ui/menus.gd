class_name Menus
extends Control
## The front end, built in code: a tap-to-start splash, the main menu down
## the left of the screen (the attract-mode swing stays visible on the
## right), and every other screen – time trials, the shop, stats, settings,
## pause, results, live tuning – in the same layout: a header with a back
## button, cards with icons and progress, slide-in transitions, UI clicks.
## Big touch targets; focus-navigable for controllers and keyboards.

signal start_mode(mode: String, arg: String)
signal resume
signal restart
signal quit_to_title
signal tuning_changed
signal end_session
## The hero should wear this Shop.look() (equipped outfit or a try-on).
signal look_changed(look: Dictionary)

const ACCENT := UiStyle.GOLD
const DIM := Color(1, 1, 1, 0.62)
const FAINT := Color(1, 1, 1, 0.42)
const MARGIN := 64.0

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
var screen_name := ""    # current screen id (debug bridge / tests)
var _screen: Control
var _theme := Theme.new()
var _splash_done := false
var _buttons := {}       # name -> Button on the current screen
var _click: AudioStreamPlayer
var _card_style := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_theme()
	theme = _theme
	_click = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/ui_click.wav"):
		_click.stream = load("res://assets/audio/ui_click.wav")
	_click.volume_db = -8.0
	add_child(_click)


func _build_theme() -> void:
	_theme.default_font = UiStyle.font("bold")
	_theme.default_font_size = 24
	# Cards: dusk glass with a hairline edge; gold edge on focus.
	var normal := _box(Color(UiStyle.INK, 0.62), 18, Color(1, 1, 1, 0.09), 1)
	var hover := _box(Color(UiStyle.DUSK, 0.7), 18, Color(1, 1, 1, 0.16), 1)
	var focus := _box(Color(UiStyle.DUSK, 0.7), 18, ACCENT, 3)
	var pressed := _box(Color(ACCENT, 0.3), 18, ACCENT, 3)
	var disabled := _box(Color(UiStyle.INK, 0.35), 18)
	for type in ["Button", "OptionButton", "CheckButton"]:
		_theme.set_stylebox("normal", type, normal)
		_theme.set_stylebox("hover", type, hover)
		_theme.set_stylebox("focus", type, focus)
		_theme.set_stylebox("pressed", type, pressed)
		_theme.set_stylebox("hover_pressed", type, pressed)
		_theme.set_stylebox("disabled", type, disabled)
		_theme.set_color("font_color", type, UiStyle.WEB)
		_theme.set_color("font_hover_color", type, Color.WHITE)
		_theme.set_color("font_focus_color", type, Color.WHITE)
		_theme.set_color("font_pressed_color", type, Color.WHITE)
		_theme.set_color("font_disabled_color", type, Color(1, 1, 1, 0.4))
	_theme.set_color("font_color", "Label", UiStyle.WEB)
	_theme.set_constant("separation", "VBoxContainer", 12)
	_theme.set_constant("separation", "HBoxContainer", 14)
	_theme.set_font_size("font_size", "PopupMenu", 24)
	_theme.set_stylebox("panel", "PopupMenu", _box(Color(UiStyle.INK, 0.98), 14, Color(1, 1, 1, 0.1), 1))
	_theme.set_stylebox("slider", "HSlider", _box(Color(1, 1, 1, 0.14), 6, Color.TRANSPARENT, 0, 6))
	var fill := _box(ACCENT, 6, Color.TRANSPARENT, 0, 6)
	_theme.set_stylebox("grabber_area", "HSlider", fill)
	_theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var bar := _box(Color(1, 1, 1, 0.05), 4, Color.TRANSPARENT, 0, 2)
	var grab := _box(Color(1, 1, 1, 0.3), 4, Color.TRANSPARENT, 0, 2)
	_theme.set_stylebox("scroll", "VScrollBar", bar)
	_theme.set_stylebox("grabber", "VScrollBar", grab)
	_theme.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(ACCENT, 0.7), 4, Color.TRANSPARENT, 0, 2))
	_theme.set_stylebox("grabber_pressed", "VScrollBar", _box(ACCENT, 4, Color.TRANSPARENT, 0, 2))
	# Card variants: primary (gold, dark text) and plain.
	_card_style["primary"] = [_box(ACCENT, 18), _box(ACCENT.lightened(0.12), 18),
		_box(ACCENT.lightened(0.08), 18, Color.WHITE, 3), _box(ACCENT.darkened(0.12), 18, Color.WHITE, 3)]


static func _box(col: Color, radius: int, border := Color.TRANSPARENT, bw := 0, margin := -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	if margin >= 0:
		sb.set_content_margin_all(margin)
	else:
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
	return sb


# =================================================================== title
func show_title() -> void:
	if not _splash_done:
		_show_splash()
	else:
		_show_main()


func _show_splash() -> void:
	var root := _new_screen("splash")
	root.add_child(MenuParts.backdrop(0.75, 0.9))
	root.add_child(MenuParts.floor_fade(0.7))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	col.position = Vector2(MARGIN + 30, 0)
	col.add_theme_constant_override("separation", 6)
	col.add_child(MenuParts.Logo.new(1.25))
	col.add_child(_label("Momentum is everything.", 26, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	root.add_child(col)
	var tap := PanelContainer.new()
	tap.add_theme_stylebox_override("panel", _box(ACCENT, 26, Color.TRANSPARENT, 0, 14))
	tap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tap_l := _label("  TAP TO START  ", 24, UiStyle.INK, "black", HORIZONTAL_ALIGNMENT_CENTER)
	tap.add_child(tap_l)
	root.add_child(tap)
	var studio := _label("A MUSA STUDIOS GAME", 15, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT)
	root.add_child(studio)
	var place := func():
		var vp := get_viewport_rect().size
		col.position = Vector2(MARGIN + 30, vp.y * 0.5 - col.size.y * 0.62)
		tap.position = Vector2(MARGIN + 34, vp.y * 0.5 + col.size.y * 0.5 + 8)
		studio.position = Vector2(MARGIN + 36, vp.y - 54)
	place.call_deferred()
	# Breathing prompt.
	var tw := tap.create_tween().set_loops()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(tap, "modulate:a", 0.55, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(tap, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	# The whole screen is the button.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_ALL
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hit.pressed.connect(func():
		_tap()
		_splash_done = true
		_show_main())
	root.add_child(hit)
	_reg("start", hit)
	hit.grab_focus.call_deferred()
	_enter(col)


func _show_main() -> void:
	var root := _new_screen("title")
	root.add_child(MenuParts.backdrop(1.0, 0.6))
	root.add_child(MenuParts.floor_fade(0.55))
	var m := _margins(root, MARGIN, 30, MARGIN, 26)
	var row := HBoxContainer.new()
	m.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 540
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(MenuParts.Logo.new(0.72))
	left.add_child(_gap(4))
	var trained: bool = SaveData.data["tutorial_done"]
	var tokens := SaveData.token_count()
	var play := _card("FREE SWING", "Explore the city  ·  %d/%d tokens found" % [tokens, Progress.TOKEN_TOTAL],
		"play", func(): start_mode.emit("free", ""), "", true)
	_reg("free", play)
	var mc := Progress.medal_counts()
	var trial := _card("Time Trial", "Beat the clock", "timer",
		show_courses, "%d/%d" % [mc[0], CourseBuilder.COURSES.size()], false, "medal")
	_reg("trial", trial)
	var best_e: float = SaveData.data["best_endurance_m"]
	var endu := _card("Endurance", "Stay airborne", "endurance",
		func(): start_mode.emit("endurance", ""), ("%d m" % int(best_e)) if best_e > 0.0 else "")
	_reg("endurance", endu)
	var train := _card("Training", "Learn to swing  ·  start here" if not trained else "Swing, release, steer, wall-kick",
		"training", func(): start_mode.emit("training", ""), "NEW" if not trained else "", false,
		"" if not trained else "check")
	_reg("training", train)
	if not trained:
		left.add_child(train)
	left.add_child(play)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	trial.custom_minimum_size.x = 264
	endu.custom_minimum_size.x = 264
	grid.add_child(trial)
	grid.add_child(endu)
	if trained:
		train.custom_minimum_size.x = 264
		grid.add_child(train)
		var shop := _card("Shop", "Suits, clothes, webs", "shop", show_shop.bind("", "", true),
			Hud._fmt_int(Shop.coins()), false, "coin", ACCENT)
		shop.custom_minimum_size.x = 264
		_reg("shop_card", shop)
		grid.add_child(shop)
	left.add_child(grid)
	row.add_child(_spacer())
	# Right: progress chips at the top, quick buttons at the bottom.
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(right)
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_child(_chip("token", UiStyle.TEAL, "%d/%d" % [tokens, Progress.TOKEN_TOTAL]))
	chips.add_child(_chip("medal", Progress.MEDAL_COLORS[Progress.Medal.GOLD], "%d/%d" % [mc[0], CourseBuilder.COURSES.size()]))
	chips.add_child(_coin_chip(Shop.coins()))
	right.add_child(chips)
	right.add_child(_spacer(true))
	var quick := HBoxContainer.new()
	quick.alignment = BoxContainer.ALIGNMENT_END
	if not trained:
		quick.add_child(_reg("shop", _icon_button("shop", "Shop", show_shop.bind("", "", true))))
	quick.add_child(_reg("stats", _icon_button("stats", "Stats", show_stats)))
	quick.add_child(_reg("settings", _icon_button("gear", "Settings", func(): show_settings(show_title))))
	right.add_child(quick)
	right.add_child(_label("v%s" % ProjectSettings.get_setting("application/config/version", "1.0"), 14, FAINT,
		"semibold", HORIZONTAL_ALIGNMENT_RIGHT))
	(train if not trained else play).grab_focus.call_deferred()
	_enter(left)
	_enter(right, 30.0)


# ================================================================= courses
func show_courses() -> void:
	var box := _page("time_trial", "TIME TRIAL", show_title, 640)
	box.add_child(_label("Fly the rings in order. Medals come from the par time.", 18, DIM, "semibold",
		HORIZONTAL_ALIGNMENT_LEFT))
	var first: Button
	for id in CourseBuilder.COURSES:
		var c := CourseBuilder.load_course(id)
		if c.is_empty():
			continue
		var best := SaveData.best_trial(id)
		var medal := Progress.medal_for(c["par"], best)
		var info: Dictionary = CourseBuilder.COURSES[id]
		var stat := TimeTrialMode._fmt(best) if best < INF and best > 0.0 else "--:--"
		var b := _card(info["name"], info["desc"], "timer", func(): start_mode.emit("trial", id), stat, false,
			"medal" if medal != Progress.Medal.NONE else "", Progress.MEDAL_COLORS[medal])
		b.custom_minimum_size.y = 96
		_reg("course_" + id, b)
		box.add_child(b)
		var targets := HBoxContainer.new()
		targets.add_child(_gap_x(70))
		for md in [Progress.Medal.GOLD, Progress.Medal.SILVER, Progress.Medal.BRONZE]:
			targets.add_child(_chip("medal", Progress.MEDAL_COLORS[md],
				TimeTrialMode._fmt(Progress.medal_target(c["par"], md)), 15))
		box.add_child(targets)
		if first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()


# ==================================================================== shop
var _shop_tab := "suit"
var _shop_sel := ""


func show_suits() -> void:
	show_shop("suit")


## The shop: a tab per slot, the picked item (worn on the hero straight away
## as a try-on) with its Buy / Wear button, and every item in the slot.
## Leaving puts the equipped outfit back on.
func show_shop(tab := "", sel := "", anim := true) -> void:
	if tab != "":
		_shop_tab = tab
	if Shop.in_slot(_shop_tab).is_empty():
		_shop_tab = "suit"
	_shop_sel = sel if not Shop.item(sel).is_empty() else Shop.equipped(_shop_tab)
	var box := _page("shop", "SHOP", _leave_shop, 700, 0.0, anim)
	var col := box.get_parent().get_parent() as VBoxContainer
	var head := col.get_child(0) as HBoxContainer
	head.add_child(_spacer())
	var bal := _coin_chip(Shop.coins(), 22)
	bal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bal)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for sl in Shop.SLOTS:
		var slot: String = sl[0]
		var on := slot == _shop_tab
		var b := Button.new()
		b.text = sl[1]
		b.add_theme_font_size_override("font_size", 17)
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if on:
			for st in ["normal", "hover", "focus", "pressed"]:
				b.add_theme_stylebox_override(st, _box(ACCENT, 14, Color.WHITE if st == "focus" else Color.TRANSPARENT,
					3 if st == "focus" else 0, 4))
			for fc in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
				b.add_theme_color_override(fc, UiStyle.INK)
		else:
			b.add_theme_stylebox_override("normal", _box(Color(UiStyle.INK, 0.62), 14, Color(1, 1, 1, 0.09), 1, 4))
		b.pressed.connect(func():
			_tap()
			show_shop(slot, "", false))
		_reg("tab_" + slot, b)
		tabs.add_child(b)
	col.add_child(tabs)
	col.move_child(tabs, 1)
	var detail := _shop_detail(Shop.item(_shop_sel))
	col.add_child(detail)
	col.move_child(detail, 2)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var focus: Button
	for it in Shop.in_slot(_shop_tab):
		var t := _shop_tile(it)
		grid.add_child(t)
		if it["id"] == _shop_sel:
			focus = t
	box.add_child(grid)
	look_changed.emit(Shop.look({_shop_tab: _shop_sel}))
	if focus:
		focus.grab_focus.call_deferred()


func _leave_shop() -> void:
	look_changed.emit(Shop.look())
	show_title()


func _shop_tile(it: Dictionary) -> Button:
	var id: String = it["id"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(222, 84)
	b.focus_mode = Control.FOCUS_ALL
	if id == _shop_sel:
		b.add_theme_stylebox_override("normal", _box(Color(UiStyle.DUSK, 0.8), 16, ACCENT, 3))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -10
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw := MenuParts.Swatch.new(it, 52)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := _label(it["name"], 19, Color.WHITE, "bold", HORIZONTAL_ALIGNMENT_LEFT)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(nl)
	texts.add_child(_shop_status(it, 15))
	row.add_child(texts)
	b.add_child(row)
	b.pressed.connect(func():
		_tap(1.1)
		show_shop(_shop_tab, id, false))
	_reg("item_" + id, b)
	return b


## Equipped / Owned / price / how to earn it.
func _shop_status(it: Dictionary, size: int) -> Control:
	var id: String = it["id"]
	if Shop.equipped(it["slot"]) == id:
		return _label("Equipped", size, UiStyle.TEAL, "bold", HORIZONTAL_ALIGNMENT_LEFT)
	if Shop.owns(id):
		return _label("Owned", size, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT)
	if not Shop.for_sale(id):
		var l := _label(it.get("hint", "Locked"), size, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		return l
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := MenuParts.Icon.new("coin", Color.WHITE, size + 3)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var dear: bool = Shop.coins() < it["price"]
	row.add_child(_label(Hud._fmt_int(it["price"]), size + 1, FAINT if dear else ACCENT, "black", HORIZONTAL_ALIGNMENT_LEFT))
	return row


## The picked item: big swatch, name, and what you can do with it.
func _shop_detail(it: Dictionary) -> PanelContainer:
	var id: String = it["id"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(UiStyle.INK, 0.7), 18, Color(1, 1, 1, 0.1), 1, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	p.add_child(row)
	row.add_child(_gap_x(2))
	var sw := MenuParts.Swatch.new(it, 72)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(_label(it["name"], 30, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT))
	var equipped := Shop.equipped(it["slot"]) == id
	var sub: String = "Wearing it now" if equipped else ("Yours – try it on" if Shop.owns(id) else
		("Trying it on – buy to keep it" if Shop.for_sale(id) else "Earned: " + it.get("hint", "")))
	texts.add_child(_label(sub, 16, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(texts)
	var act: Button
	if equipped:
		row.add_child(_chip("check", UiStyle.TEAL, "EQUIPPED", 18))
	elif Shop.owns(id):
		act = _card("Wear", "", "check", func():
			Shop.equip(id)
			show_shop(_shop_tab, id, false), "", true)
	elif Shop.for_sale(id):
		var need: int = int(it["price"]) - Shop.coins()
		if need <= 0:
			act = _card("Buy", "", "coin", func():
				if Shop.buy(id):
					Shop.equip(id)
					Settings.haptic(30, 0.7)
					_tap(1.4)
				show_shop(_shop_tab, id, false), Hud._fmt_int(it["price"]), true)
		else:
			act = _card("%s more" % Hud._fmt_int(need), "Swing to earn coins", "coin", func(): pass)
			act.disabled = true
	else:
		row.add_child(MenuParts.Icon.new("lock", FAINT, 34))
	if act:
		act.custom_minimum_size = Vector2(230, 76)
		act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_reg("shop_action", act)
		row.add_child(act)
	row.add_child(_gap_x(2))
	return p


func _coin_chip(n: int, size := 17) -> PanelContainer:
	return _chip("coin", Color.WHITE, Hud._fmt_int(n), size)


# =================================================================== stats
func show_stats() -> void:
	var box := _page("stats", "STATS", show_title, 640)
	var d: Dictionary = SaveData.data
	var mc := Progress.medal_counts()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for e in [
		["%.1f km" % (d["total_distance_m"] / 1000.0), "Distance swung"],
		["%d" % d["total_swings"], "Swings"],
		["%d km/h" % int(d["top_speed_ms"] * 3.6), "Top speed"],
		["×%d" % d["best_chain"], "Longest chain"],
		["%d m" % int(d["best_endurance_m"]), "Endurance best"],
		["%d/%d" % [SaveData.token_count(), Progress.TOKEN_TOTAL], "Tokens"],
		["%d/%d" % [mc[0], CourseBuilder.COURSES.size()], "Medals  (gold %d)" % mc[1]],
		["%d min" % int(d["play_time_s"] / 60.0), "Time played"],
		[Hud._fmt_int(int(d["coins_earned"])), "Coins earned"],
		["×%s" % Hud._fmt_mult(float(d["best_multiplier"])), "Best multiplier"],
	]:
		grid.add_child(_tile(e[0], e[1]))
	box.add_child(grid)
	_buttons["back"].grab_focus.call_deferred()


# ================================================================ settings
func show_settings(back: Callable) -> void:
	var box := _page("settings", "SETTINGS", back, 700)
	box.add_child(_section("Graphics"))
	var q := OptionButton.new()
	for n in ["Low  ·  lighter, 70% scale", "Medium  ·  balanced", "High  ·  sharpest, always 60 fps"]:
		q.add_item(n)
	q.selected = Settings.quality
	q.item_selected.connect(func(i):
		_tap()
		Settings.quality = i
		Settings.save())
	box.add_child(_row("Quality", q))
	box.add_child(_row("60 FPS", _check(Settings.fps_60, func(v): Settings.fps_60 = v; Settings.save())))
	if OS.is_debug_build():
		box.add_child(_row("Performance overlay", _check(Settings.show_perf, func(v): Settings.show_perf = v; Settings.save())))
	box.add_child(_label("Draw-distance changes apply on next launch.", 15, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(_section("Controls"))
	var aim := OptionButton.new()
	aim.add_item("SWING button (assisted)")
	aim.add_item("Tap buildings + SWING assist")
	aim.selected = 1 if Settings.aim_mode == "tap" else 0
	aim.item_selected.connect(func(i):
		_tap()
		Settings.aim_mode = "tap" if i == 1 else "assist"
		Settings.save())
	box.add_child(_row("Web aiming", aim))
	box.add_child(_row("Haptics", _check(Settings.haptics, func(v): Settings.haptics = v; Settings.save())))
	box.add_child(_section("Audio"))
	box.add_child(_row("Music", _slider(Settings.music_volume, 0.0, 1.0, 0.05, func(v): Settings.music_volume = v; Settings.save())))
	box.add_child(_row("Effects", _slider(Settings.sfx_volume, 0.0, 1.0, 0.05, func(v): Settings.sfx_volume = v; Settings.save())))
	box.add_child(_section("Device"))
	var bench := _card("Run benchmark", "45 s scripted flight  ·  saves benchmark.json", "bench",
		func(): start_mode.emit("benchmark", ""))
	_reg("benchmark", bench)
	box.add_child(bench)
	box.add_child(_gap(6))
	box.add_child(_label("City Swing v%s  ·  Musa Studios  ·  Outfit font (SIL OFL)" %
		ProjectSettings.get_setting("application/config/version", "1.0"), 14, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	q.grab_focus.call_deferred()


# =================================================================== pause
func show_pause(free_swing := false) -> void:
	var box := _page("pause", "PAUSED", Callable(), 520, 0.35)
	var b := _card("Resume", "Back to the swing", "play", func(): resume.emit(), "", true)
	_reg("resume", b)
	box.add_child(b)
	if free_swing:
		box.add_child(_reg("end", _card("End session", "See your distance and tokens", "check", func(): end_session.emit())))
	else:
		box.add_child(_reg("restart", _card("Restart", "From the start line", "restart", func(): restart.emit())))
	var row := HBoxContainer.new()
	row.add_child(_reg("settings", _icon_button("gear", "Settings", func(): show_settings(show_pause.bind(free_swing)))))
	if OS.is_debug_build():  # developer tool: not in TestFlight/App Store builds
		row.add_child(_reg("tuning", _icon_button("tune", "Tuning", show_tuning)))
	row.add_child(_reg("quit", _icon_button("home", "Title", func(): quit_to_title.emit())))
	box.add_child(row)
	b.grab_focus.call_deferred()


# ================================================================= results
func show_results(r: Dictionary) -> void:
	var mode: String = r.get("mode", "")
	var titles := {"trial": "COURSE COMPLETE", "endurance": "RUN OVER", "benchmark": "BENCHMARK",
		"training": "TRAINING COMPLETE"}
	var box := _page("results", titles.get(mode, "SESSION"), Callable(), 640, 0.2)
	if mode == "benchmark":
		box.add_child(_big("%.1f fps" % r["avg_fps"]))
		box.add_child(_label("%s · %s quality · target %d fps" % [r["device"], r["quality"], r["target_fps"]], 20, DIM,
			"semibold", HORIZONTAL_ALIGNMENT_LEFT))
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 10)
		g.add_theme_constant_override("v_separation", 10)
		for e in [["%.1f ms" % r["avg_ms"], "Average frame"], ["%.1f ms" % r["p99_ms"], "1% worst"],
				["%.1f ms" % r["worst_ms"], "Worst"], ["%d/%d" % [r["frames_over_33ms"], r["frames"]], "Over 33 ms"],
				["%d" % int(r["avg_draw_calls"]), "Draw calls"], ["%dk" % int(r["avg_prims"] / 1000.0), "Primitives"]]:
			g.add_child(_tile(e[0], e[1], 190))
		box.add_child(g)
		box.add_child(_label("CPU %.1f ms process + %.1f ms physics  ·  saved to benchmark.json" % [r["cpu_process_ms"],
			r["cpu_physics_ms"]], 15, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
		var bb := _card("Title", "", "home", func(): quit_to_title.emit(), "", true)
		_reg("title", bb)
		box.add_child(bb)
		bb.grab_focus.call_deferred()
		return
	var headline := ""
	var detail := ""
	match mode:
		"trial":
			headline = TimeTrialMode._fmt(r["time"])
			detail = "%s   ·   par %s   ·   best %s" % [r["course"], TimeTrialMode._fmt(r["par"]), TimeTrialMode._fmt(r["best"])]
		"endurance":
			headline = "%d m" % int(r["distance"])
			detail = "%s   ·   best %d m" % [r["reason"], int(r["best"])]
		"training":
			headline = "You're ready"
			detail = "Free Swing hides %d tokens around the city." % Progress.TOKEN_TOTAL
		_:
			headline = "%.2f km" % (r.get("distance", 0.0) / 1000.0)
			detail = "%d token%s this session   ·   %d/%d found" % [r.get("tokens_session", 0),
				"" if r.get("tokens_session", 0) == 1 else "s", r.get("tokens_total", 0), Progress.TOKEN_TOTAL]
	var badges := HBoxContainer.new()
	var medal: int = r.get("medal", Progress.Medal.NONE)
	if medal != Progress.Medal.NONE:
		badges.add_child(_chip("medal", Progress.MEDAL_COLORS[medal], "%s MEDAL" % Progress.MEDAL_NAMES[medal].to_upper(), 18))
	if r.get("new_best", false):
		badges.add_child(_chip("check", ACCENT, "NEW PERSONAL BEST", 18))
	if badges.get_child_count() > 0:
		box.add_child(badges)
	box.add_child(_big(headline))
	box.add_child(_label(detail, 20, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	var g2 := HBoxContainer.new()
	g2.add_child(_tile("%d" % r.get("swings", 0), "Swings", 190))
	g2.add_child(_tile("×%d" % r.get("chain", 0), "Longest chain", 190))
	g2.add_child(_tile("%d km/h" % int(r.get("top_speed", 0.0) * 3.6), "Top speed", 190))
	box.add_child(g2)
	if r.has("coins"):
		var cr := HBoxContainer.new()
		cr.add_child(_chip("coin", Color.WHITE, "+%s COINS" % Hud._fmt_int(r["coins"]), 20))
		cr.add_child(_chip("coin", Color.WHITE, "BEST ×%s" % Hud._fmt_mult(r.get("best_mult", 1.0)), 20))
		cr.add_child(_chip("coin", Color.WHITE, "BALANCE %s" % Hud._fmt_int(Shop.coins()), 20))
		box.add_child(cr)
	for u in r.get("unlocks", []):
		box.add_child(_chip("suit", UiStyle.TEAL, "SUIT UNLOCKED: %s" % String(u).to_upper(), 18))
	var b: Button
	if mode == "training":
		b = _card("Free Swing", "The whole city, your pace", "play", func(): start_mode.emit("free", ""), "", true)
	else:
		b = _card("Go again", "Same mode, fresh start", "restart", func(): restart.emit(), "", true)
	_reg("again", b)
	box.add_child(b)
	box.add_child(_reg("title", _card("Title", "Main menu", "home", func(): quit_to_title.emit())))
	b.grab_focus.call_deferred()


# ================================================================== tuning
func show_tuning() -> void:
	var box := _page("tuning", "PHYSICS TUNING", show_pause, 820, 0.35)
	box.add_child(_label("Live – changes apply immediately and are saved on this device.", 16, FAINT, "semibold",
		HORIZONTAL_ALIGNMENT_LEFT))
	var first: Control
	for t in TUNABLES:
		var prop: String = t[0]
		var val: float = params.get(prop)
		var value_label := _label(_fmt_val(val, t[4]), 18, ACCENT, "bold", HORIZONTAL_ALIGNMENT_RIGHT)
		value_label.custom_minimum_size.x = 80
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
	row2.add_child(_icon_button("check", "Save", func(): Settings.save()))
	row2.add_child(_icon_button("restart", "Reset defaults", func():
		Settings.tuning_overrides = {}
		Settings.save()
		var fresh: SwingParams = load("res://config/swing_params.tres")
		for t in TUNABLES:
			params.set(t[0], fresh.get(t[0]))
		show_tuning()))
	box.add_child(row2)
	first.grab_focus.call_deferred()


func hide_all() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
	_buttons.clear()
	screen_name = ""
	visible = false


## Centre of each named button on the current screen, as viewport fractions
## (published on the web debug bridge so browser tests can tap by name).
func button_points() -> Dictionary:
	var out := {}
	var vs := get_viewport_rect().size
	for k in _buttons:
		var b: Control = _buttons[k]
		if is_instance_valid(b) and b.is_visible_in_tree():
			var c := b.get_global_rect().get_center()
			out[k] = [snappedf(c.x / vs.x, 0.001), snappedf(c.y / vs.y, 0.001)]
	return out


# ================================================================= layout
func _new_screen(id: String) -> Control:
	if _screen:
		_screen.queue_free()
	_buttons.clear()
	screen_name = id
	visible = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_screen = root
	return root


func _margins(root: Control, l: float, t: float, r: float, b: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", int(l))
	m.add_theme_constant_override("margin_top", int(t))
	m.add_theme_constant_override("margin_right", int(r))
	m.add_theme_constant_override("margin_bottom", int(b))
	root.add_child(m)
	return m


## A left-hand page: header (back button + title) over a scrolling column.
## `dim` darkens the whole view too (pause / results over gameplay).
func _page(id: String, title: String, back: Callable, width := 640, dim := 0.0, anim := true) -> VBoxContainer:
	var root := _new_screen(id)
	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, dim)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(shade)
	root.add_child(MenuParts.backdrop(1.0, 0.66))
	var m := _margins(root, MARGIN, 30, MARGIN, 24)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = width
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 14)
	m.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	if back.is_valid():
		var bb := Button.new()
		bb.custom_minimum_size = Vector2(64, 64)
		bb.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.08), 32))
		bb.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.16), 32))
		bb.add_theme_stylebox_override("focus", _box(Color(1, 1, 1, 0.12), 32, ACCENT, 3))
		bb.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.35), 32, ACCENT, 3))
		var ic := MenuParts.Icon.new("back", Color.WHITE, 30)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position -= Vector2(15, 15)
		bb.add_child(ic)
		bb.pressed.connect(func():
			_tap(0.8)
			back.call())
		head.add_child(bb)
		_reg("back", bb)
	var t := _label(title, 46, ACCENT, "black", HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	col.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	if anim:
		_enter(col)
	return box


## Slide + fade in (runs while the tree is paused too).
func _enter(c: Control, delay_ms := 0.0) -> void:
	c.modulate.a = 0.0
	var go := func():
		var x := c.position.x
		c.position.x = x - 36.0
		var tw := c.create_tween().set_parallel()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(c, "modulate:a", 1.0, 0.28).set_delay(delay_ms / 1000.0)
		tw.tween_property(c, "position:x", x, 0.36).set_delay(delay_ms / 1000.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	go.call_deferred()


func _tap(pitch := 1.0) -> void:
	Settings.haptic(6, 0.25)
	if _click.stream:
		_click.pitch_scale = pitch
		_click.volume_db = linear_to_db(maxf(Settings.sfx_volume, 0.001)) - 8.0
		_click.play()


func _reg(id: String, b: Control) -> Control:
	_buttons[id] = b
	return b


# ============================================================== components
## A mode card: icon, title, subtitle, and a stat (or badge) on the right.
func _card(title: String, sub: String, icon: String, cb: Callable, stat := "", primary := false,
		stat_icon := "", stat_color := ACCENT, icon_color := Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 92 if primary else 80)
	b.focus_mode = Control.FOCUS_ALL
	var ink := UiStyle.INK if primary else Color.WHITE
	if primary:
		var st: Array = _card_style["primary"]
		b.add_theme_stylebox_override("normal", st[0])
		b.add_theme_stylebox_override("hover", st[1])
		b.add_theme_stylebox_override("focus", st[2])
		b.add_theme_stylebox_override("pressed", st[3])
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20
	row.offset_right = -20
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := MenuParts.Icon.new(icon, icon_color if icon_color.a > 0.0 else (ink if primary else ACCENT),
		38 if primary else 32)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := _label(title, 30 if primary else 23, ink, "black" if primary else "bold", HORIZONTAL_ALIGNMENT_LEFT)
	texts.add_child(tl)
	if sub != "":
		var sl := _label(sub, 15, Color(ink, 0.68), "semibold", HORIZONTAL_ALIGNMENT_LEFT)
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.clip_text = true
		texts.add_child(sl)
	row.add_child(texts)
	if stat_icon != "":
		var si := MenuParts.Icon.new(stat_icon, stat_color, 24)
		si.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(si)
	if stat != "":
		var stl := _label(stat, 19 if stat != "NEW" else 16, stat_color if not primary else ink, "black",
			HORIZONTAL_ALIGNMENT_RIGHT)
		stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if stat == "NEW":
			var badge := PanelContainer.new()
			badge.add_theme_stylebox_override("panel", _box(UiStyle.TEAL, 10, Color.TRANSPARENT, 0, 6))
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stl.add_theme_color_override("font_color", UiStyle.INK)
			badge.add_child(stl)
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(badge)
		else:
			row.add_child(stl)
	b.add_child(row)
	b.pressed.connect(func():
		_tap()
		cb.call())
	return b


## Round-cornered icon + label button (secondary actions).
func _icon_button(icon: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 64)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(MenuParts.Icon.new(icon, ACCENT, 26))
	row.add_child(_label(text, 20, Color.WHITE, "bold"))
	b.add_child(row)
	var tw := UiStyle.font("bold").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	b.custom_minimum_size.x = tw + 26 + 10 + 48
	b.pressed.connect(func():
		_tap()
		cb.call())
	return b


func _chip(icon: String, col: Color, text: String, size := 17) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(UiStyle.INK, 0.6), 20, Color(1, 1, 1, 0.1), 1, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ic := MenuParts.Icon.new(icon, col, size + 4)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	row.add_child(_label(text, size, Color.WHITE, "bold"))
	row.add_child(_gap_x(4))
	p.add_child(row)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


func _tile(value: String, caption: String, width := 300) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.06), 16, Color.TRANSPARENT, 0, 16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_label(value, 32, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(_label(caption, 15, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	p.add_child(v)
	return p


func _big(text: String) -> Label:
	return _label(text, 84, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT)


func _section(text: String) -> Label:
	var l := _label(text.to_upper(), 15, ACCENT, "black", HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size.y = 34
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


func _label(text: String, size: int, color: Color, weight := "bold",
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", UiStyle.font(weight))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _gap_x(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _spacer(vertical := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(text, 21, Color(1, 1, 1, 0.9), "bold", HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(250, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _check(value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.custom_minimum_size = Vector2(0, 56)
	# On/off reads from the switch and its label, not a gold-filled bar
	# (the shared "pressed" style is for buttons being held).
	c.text = "On" if value else "Off"
	for st in ["pressed", "hover_pressed"]:
		c.add_theme_stylebox_override(st, _theme.get_stylebox("normal" if st == "pressed" else "hover", "Button"))
	c.toggled.connect(func(v):
		_tap()
		c.text = "On" if v else "Off"
		cb.call(v))
	return c


func _slider(value: float, lo: float, hi: float, step: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 52)
	s.value_changed.connect(cb)
	return s


static func _fmt_val(v: float, step: float) -> String:
	return ("%.4f" % v) if step < 0.001 else (("%.2f" % v) if step < 0.1 else ("%.1f" % v))
