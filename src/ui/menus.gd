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
## Homes: go to an owned home now (Free Swing), and "ownership/selection changed".
signal go_home(id: String)
signal homes_changed
## The hero should wear this Shop.look() (equipped outfit or a try-on).
signal look_changed(look: Dictionary)
## Shop preview camera (main → CinematicDirector): framing by category,
## drag to orbit (radians), pinch/wheel zoom (factor), reset.
signal preview_focus(slot: String)
signal preview_orbit(dx: float)
signal preview_zoom(f: float)
signal preview_reset

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
## Free Swing's contracts while a session runs (main sets it), else null.
var jobs: JobBoard
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
	root.add_child(MenuParts.edge_shade(0.55))
	root.add_child(MenuParts.floor_fade(0.45))
	_brand(root, true)
	var col := _menu_column(root)
	var tap := _label("TAP TO START" if DisplayServer.is_touchscreen_available() else "PRESS TO START",
		22, ACCENT, "black", HORIZONTAL_ALIGNMENT_RIGHT)
	col.add_child(tap)
	var tw := tap.create_tween().set_loops()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(tap, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(tap, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	# The whole screen is the button.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_ALL
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for st in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(func():
		_tap()
		_splash_done = true
		_show_main())
	root.add_child(hit)
	_reg("start", hit)
	hit.grab_focus.call_deferred()
	_enter(col)


## Small wordmark bottom-left (and the studio line on the splash). The city
## and the hero are the show; the brand signs it.
func _brand(root: Control, studio := false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(MenuParts.Logo.new(0.64 if studio else 0.48))
	if studio:
		box.add_child(_label("A MUSA STUDIOS GAME", 12, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	root.add_child(box)
	var place := func():
		var vp := get_viewport_rect().size
		var sa := _safe_rect()
		box.position = Vector2(sa.position.x + 34.0, sa.end.y - box.size.y - 26.0)
	place.call_deferred()
	root.resized.connect(place)


## The safe area in viewport pixels (notch / Dynamic Island, home bar).
func _safe_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	# (The safe area is in screen space: only meaningful for a full-screen
	# window, i.e. on the phone/tablet. Windowed on desktop: the whole view.)
	if sa.size.x <= 0 or win.x <= 0 or DisplayServer.screen_get_size() != win:
		return Rect2(Vector2.ZERO, vp)
	var k := vp / Vector2(win)
	return Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k).intersection(Rect2(Vector2.ZERO, vp))


## Right-aligned menu column anchored top-right inside the safe area.
func _menu_column(root: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(col)
	var place := func():
		var sa := _safe_rect()
		var w := clampf(sa.size.x * 0.3, 280.0, 380.0)
		col.custom_minimum_size.x = w
		col.size.x = w
		col.position = Vector2(sa.end.x - w - 34.0, sa.position.y + 30.0)
	place.call_deferred()
	root.resized.connect(place)
	return col


## A text row of the title menu: right-aligned title with a quiet caption,
## no box; focus/hover turns it gold with a slim bar at the right edge.
func _menu_row(title: String, caption: String, cb: Callable, size := 24, primary := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 64 if primary else (54 if size >= 22 else 46))
	var empty := StyleBoxEmpty.new()
	var on := StyleBoxFlat.new()
	on.bg_color = Color(UiStyle.INK, 0.35)
	on.border_color = ACCENT
	on.border_width_right = 3
	on.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", on)
	b.add_theme_stylebox_override("focus", on)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_right = -16
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := _label(title, size, ACCENT if primary else Color.WHITE, "black" if primary else "bold",
		HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(tl)
	if caption != "":
		box.add_child(_label(caption, 13, DIM, "semibold", HORIZONTAL_ALIGNMENT_RIGHT))
	b.add_child(box)
	var light := func(on_: bool):
		tl.add_theme_color_override("font_color", ACCENT if (on_ or primary) else Color.WHITE)
	b.focus_entered.connect(light.bind(true))
	b.focus_exited.connect(light.bind(false))
	b.mouse_entered.connect(light.bind(true))
	b.mouse_exited.connect(func(): light.call(b.has_focus()))
	b.pressed.connect(func():
		_tap()
		cb.call())
	return b


func _show_main() -> void:
	var root := _new_screen("title")
	root.add_child(MenuParts.edge_shade(0.75))
	_brand(root)
	var col := _menu_column(root)
	var trained: bool = SaveData.data["tutorial_done"]
	var mc := Progress.medal_counts()
	var best_e: float = SaveData.data["best_endurance_m"]
	var play := _menu_row("PLAY", "Jobs, homes, tokens  ·  %s" % Contracts.rank_name(int(SaveData.data.get("rep", 0))),
		func(): start_mode.emit("free", ""), 34, true)
	_reg("free", play)
	var train := _menu_row("Training", "Start here" if not trained else "Swing, release, steer",
		func(): start_mode.emit("training", ""))
	_reg("training", train)
	if not trained:
		col.add_child(train)
	col.add_child(play)
	var trial := _menu_row("Time Trial", "%d/%d gold medals" % [mc[1], CourseBuilder.COURSES.size()], show_courses)
	_reg("trial", trial)
	col.add_child(trial)
	var endu := _menu_row("Endurance", ("best %d m" % int(best_e)) if best_e > 0.0 else "Stay airborne",
		func(): start_mode.emit("endurance", ""))
	_reg("endurance", endu)
	col.add_child(endu)
	if trained:
		col.add_child(train)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.14)
	sep.custom_minimum_size = Vector2(0, 1)
	col.add_child(_gap(6))
	col.add_child(sep)
	col.add_child(_gap(6))
	var shop := _menu_row("Shop", "%s coins" % Hud._fmt_int(Shop.coins()), show_shop.bind("", "", true), 20)
	_reg("shop_card", shop)
	_reg("shop", shop)
	col.add_child(shop)
	var cur_home: String = Homes.spec(Homes.selected()).get("name", "Starter Bedsit")
	col.add_child(_reg("homes", _menu_row("Homes", cur_home, func(): show_homes(show_title), 20)))
	col.add_child(_reg("stats", _menu_row("Progress", "Stats and records", show_stats, 20)))
	col.add_child(_reg("settings", _menu_row("Settings", "", func(): show_settings(show_title), 20)))
	var ver := _label("v%s" % ProjectSettings.get_setting("application/config/version", "1.0"), 12, FAINT,
		"semibold", HORIZONTAL_ALIGNMENT_RIGHT)
	root.add_child(ver)
	var place := func():
		var sa := _safe_rect()
		ver.position = Vector2(sa.end.x - ver.size.x - 34.0, sa.end.y - 30.0)
	place.call_deferred()
	(train if not trained else play).grab_focus.call_deferred()
	_enter(col)


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
## The wardrobe. Left: categories, a grid of thumbnails rendered from the
## real character (ThumbStudio, cached), and the picked item with one clear
## action. Right: the hero, live, on a quiet rooftop – drag to turn, pinch or
## scroll to zoom; the camera frames the category being browsed. Picking an
## item only previews it; Wear / Buy (confirmed) commit, leaving restores the
## equipped look.
const SHOP_FOCUS := {"hero": "face", "hair": "face", "top": "suit", "suit": "suit", "pants": "pants", "shoes": "shoes", "gloves": "gloves",
	"head": "head", "face": "face", "web": "web", "gadget": "gadget"}
var _thumbs: ThumbStudio
var _thumb_rects := {}     # item id -> TextureRect on the current grid
var _confirm_id := ""      # purchase awaiting its confirming tap
var _pinch := {}           # touch index -> position (right-side preview area)


func show_shop(tab := "", sel := "", anim := true) -> void:
	if tab != "":
		_shop_tab = tab
	if Shop.in_slot(_shop_tab).is_empty():
		_shop_tab = "suit"
	_shop_sel = sel if not Shop.item(sel).is_empty() else Shop.equipped(_shop_tab)
	if _confirm_id != _shop_sel:
		_confirm_id = ""
	if _thumbs == null:
		_thumbs = ThumbStudio.new()
		_thumbs.name = "Thumbs"
		add_child(_thumbs)
		_thumbs.ready_thumb.connect(func(id: String, tex: Texture2D):
			var tr: TextureRect = _thumb_rects.get(id)
			if is_instance_valid(tr):
				tr.texture = tex)
	var root := _new_screen("shop")
	root.add_child(MenuParts.edge_shade(0.95, 0.62, false))
	var sa := _safe_rect()
	var panel_w := clampf(sa.size.x * 0.52, 560.0, 720.0)
	# --- right: the live preview area (drag / pinch / wheel) ---------------
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_STOP
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.offset_left = sa.position.x + panel_w + 40.0
	area.gui_input.connect(_preview_input)
	root.add_child(area)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	tools.add_child(_reg("view_reset", _icon_button("restart", "View", func(): preview_reset.emit())))
	tools.add_child(_reg("view_full", _icon_button("suit", "Full look", func(): preview_focus.emit("full"))))
	root.add_child(tools)
	var hint := _label("Drag to turn  ·  pinch to zoom", 13, FAINT, "semibold", HORIZONTAL_ALIGNMENT_RIGHT)
	root.add_child(hint)
	var place := func():
		var r := _safe_rect()
		tools.position = Vector2(r.end.x - tools.size.x - 30.0, r.end.y - tools.size.y - 22.0)
		hint.position = Vector2(r.end.x - hint.size.x - 34.0, r.end.y - tools.size.y - 46.0)
	place.call_deferred()
	# --- left: the wardrobe ---------------------------------------------------
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	m.offset_left = sa.position.x + 28.0
	m.offset_right = sa.position.x + 28.0 + panel_w
	m.offset_top = sa.position.y + 20.0
	m.offset_bottom = -(get_viewport_rect().size.y - sa.end.y) - 18.0
	root.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	m.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var bb := Button.new()
	bb.custom_minimum_size = Vector2(56, 56)
	bb.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.08), 28))
	bb.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.16), 28))
	bb.add_theme_stylebox_override("focus", _box(Color(1, 1, 1, 0.12), 28, ACCENT, 3))
	bb.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.35), 28, ACCENT, 3))
	var bic := MenuParts.Icon.new("back", Color.WHITE, 26)
	bic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bic.position -= Vector2(13, 13)
	bb.add_child(bic)
	bb.pressed.connect(func():
		_tap(0.8)
		_leave_shop())
	head.add_child(_reg("back", bb))
	var title := _label("Wardrobe", 34, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(_spacer())
	var bal := _coin_chip(Shop.coins(), 20)
	bal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bal)
	col.add_child(head)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	# Categories: a compact sidebar (icon over name), not a cramped tab row.
	var cats := VBoxContainer.new()
	cats.add_theme_constant_override("separation", 4)
	cats.custom_minimum_size.x = 92
	for sl in Shop.SLOTS:
		var slot: String = sl[0]
		cats.add_child(_reg("tab_" + slot, _shop_cat(slot, sl[1], slot == _shop_tab)))
	body.add_child(cats)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	right.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3 if panel_w >= 600.0 else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	_thumb_rects.clear()
	var focus: Button
	for it in Shop.in_slot(_shop_tab):
		var t := _shop_tile(it)
		grid.add_child(t)
		if it["id"] == _shop_sel:
			focus = t
	right.add_child(_shop_detail(Shop.item(_shop_sel)))
	look_changed.emit(Shop.try_on(_shop_tab, _shop_sel))
	preview_focus.emit(SHOP_FOCUS.get(_shop_tab, "full"))
	if focus:
		focus.grab_focus.call_deferred()
	if anim:
		_enter(col)


func _shop_cat(slot: String, name: String, on: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 62)
	b.focus_mode = Control.FOCUS_ALL
	if on:
		for st in ["normal", "hover", "focus", "pressed"]:
			b.add_theme_stylebox_override(st, _box(Color(ACCENT, 0.95), 14, Color.WHITE if st == "focus" else Color.TRANSPARENT,
				2 if st == "focus" else 0, 4))
	else:
		b.add_theme_stylebox_override("normal", _box(Color(UiStyle.INK, 0.45), 14, Color(1, 1, 1, 0.06), 1, 4))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := UiStyle.INK if on else ACCENT
	var ic: Control
	if slot in ["head", "face"]:
		ic = MenuParts.Swatch.new({"slot": slot, "model": "cap" if slot == "head" else "", "mask": "" if slot == "head" else "domino"}, 30)
	elif slot == "hero":
		ic = MenuParts.Swatch.new({"slot": "hero", "skin": ink, "hair": Color(ink, 0.5)}, 30)
	elif slot == "top":
		ic = MenuParts.Swatch.new({"slot": "top", "cut": "short", "color": ink}, 30)
	else:
		ic = MenuParts.Swatch.new({"slot": slot, "color": ink, "glow": ink, "sole": ink}, 30)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(_label(name, 13, UiStyle.INK if on else Color.WHITE, "bold",
		HORIZONTAL_ALIGNMENT_CENTER))
	b.add_child(v)
	b.pressed.connect(func():
		_tap()
		show_shop(slot, "", false))
	return b


func _preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		preview_orbit.emit(ev.relative.x * 0.009)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			preview_zoom.emit(0.92)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			preview_zoom.emit(1.08)
		elif ev.double_click:
			preview_reset.emit()
	elif ev is InputEventMagnifyGesture:
		preview_zoom.emit(1.0 / maxf(ev.factor, 0.01))
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_pinch[ev.index] = ev.position
		else:
			_pinch.erase(ev.index)
	elif ev is InputEventScreenDrag:
		if _pinch.size() >= 2 and _pinch.has(ev.index):
			var other: Vector2
			for k in _pinch:
				if k != ev.index:
					other = _pinch[k]
			var before := (_pinch[ev.index] as Vector2).distance_to(other)
			var after := (ev.position as Vector2).distance_to(other)
			if before > 1.0 and after > 1.0:
				preview_zoom.emit(before / after)
		elif _pinch.size() <= 1:
			preview_orbit.emit(ev.relative.x * 0.009)
		_pinch[ev.index] = ev.position


## Set while the Wardrobe is open from a home (main restores the game).
var shop_return := Callable()


func _leave_shop() -> void:
	_confirm_id = ""
	look_changed.emit(Shop.look())
	if shop_return.is_valid():
		var r := shop_return
		shop_return = Callable()
		r.call()
	else:
		show_title()


## A thumbnail tile: the item rendered on the hero, its name, its state.
func _shop_tile(it: Dictionary) -> Button:
	var id: String = it["id"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(138, 168)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	var sel := id == _shop_sel
	var eq := Shop.equipped(it["slot"]) == id
	b.add_theme_stylebox_override("normal", _box(Color(UiStyle.DUSK, 0.75) if sel else Color(UiStyle.INK, 0.5), 14,
		ACCENT if sel else Color(1, 1, 1, 0.06), 3 if sel else 1, 6))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 6
	v.offset_bottom = -6
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb := TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lockedish := not Shop.owns(id) and not Shop.for_sale(id)
	thumb.modulate = Color(1, 1, 1, 0.55) if lockedish else Color.WHITE
	if ThumbStudio.cache.has(id):
		thumb.texture = ThumbStudio.cache[id]
	else:
		_thumbs.request(id)
	_thumb_rects[id] = thumb
	v.add_child(thumb)
	var nl := _label(it["name"], 15, Color.WHITE, "bold", HORIZONTAL_ALIGNMENT_LEFT)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nl)
	v.add_child(_shop_status(it, 12))
	b.add_child(v)
	if eq:
		var tick := MenuParts.Icon.new("check", UiStyle.TEAL, 20)
		tick.position = Vector2(10, 10)
		b.add_child(tick)
	elif lockedish:
		var lk := MenuParts.Icon.new("lock", Color(1, 1, 1, 0.8), 18)
		lk.position = Vector2(10, 10)
		b.add_child(lk)
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
		var l := _label("Locked", size, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT)
		return l
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := MenuParts.Icon.new("coin", Color.WHITE, size + 2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var dear: bool = Shop.coins() < it["price"]
	row.add_child(_label(Hud._fmt_int(it["price"]), size + 1, FAINT if dear else ACCENT, "black", HORIZONTAL_ALIGNMENT_LEFT))
	return row


## The picked item: name, what it is / what it takes, and exactly one action
## (Wear, Buy → Confirm, or the unlock requirement). Buying never happens on a
## single tap.
func _shop_detail(it: Dictionary) -> PanelContainer:
	var id: String = it["id"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(UiStyle.INK, 0.72), 16, Color(1, 1, 1, 0.1), 1, 12))
	p.custom_minimum_size.y = 96
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(_label(it["name"], 24, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT))
	var equipped := Shop.equipped(it["slot"]) == id
	if it.has("desc"):
		var dl := _label(it["desc"] + "  ·  %d s recharge" % int(it["cooldown"]), 13, ACCENT, "semibold",
			HORIZONTAL_ALIGNMENT_LEFT)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(dl)
	var sub: String = "Wearing it now" if equipped else ("Yours – previewing" if Shop.owns(id) else
		("Previewing – buy to keep it" if Shop.for_sale(id) else "Unlock: " + it.get("hint", "")))
	var sl := _label(sub, 14, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(sl)
	row.add_child(texts)
	var act: Button
	if equipped:
		row.add_child(_chip("check", UiStyle.TEAL, "EQUIPPED", 16))
	elif Shop.owns(id):
		act = _card("Wear", "", "check", func():
			Shop.equip(id)
			Settings.haptic(15, 0.4)
			show_shop(_shop_tab, id, false), "", true)
	elif Shop.for_sale(id):
		var need: int = int(it["price"]) - Shop.coins()
		if need <= 0:
			if _confirm_id == id:
				act = _card("Confirm", "Spend %s coins" % Hud._fmt_int(it["price"]), "coin", func():
					_confirm_id = ""
					if Shop.buy(id):
						Shop.equip(id)
						Settings.haptic(30, 0.7)
						_tap(1.4)
					show_shop(_shop_tab, id, false), "", true)
			else:
				act = _card("Buy", "", "coin", func():
					_confirm_id = id
					show_shop(_shop_tab, id, false), Hud._fmt_int(it["price"]), true)
		else:
			act = _card("%s more" % Hud._fmt_int(need), "Swing to earn coins", "coin", func(): pass)
			act.disabled = true
	else:
		row.add_child(MenuParts.Icon.new("lock", FAINT, 30))
	if act:
		act.custom_minimum_size = Vector2(196, 72)
		act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_reg("shop_action", act)
		row.add_child(act)
	return p


func _coin_chip(n: int, size := 17) -> PanelContainer:
	return _chip("coin", Color.WHITE, Hud._fmt_int(n), size)


# =================================================================== stats
func show_stats(back := Callable()) -> void:
	var box := _page("stats", "STATS", back if back.is_valid() else show_title, 640)
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
	box.add_child(_section("World"))
	var tod := OptionButton.new()
	var tod_ids := ["cycle", "day", "sunset", "night"]
	for n in ["Day & night cycle", "Always day", "Always sunset", "Always night"]:
		tod.add_item(n)
	tod.selected = maxi(tod_ids.find(Settings.time_of_day), 0)
	tod.item_selected.connect(func(i):
		_tap()
		Settings.time_of_day = tod_ids[i]
		Settings.save())
	box.add_child(_row("Time of day", tod))
	var wx := OptionButton.new()
	var wx_ids := ["changing", "clear", "cloudy", "rain", "storm", "fog"]
	for n in ["Changing", "Clear", "Cloudy", "Rain", "Storm", "Fog"]:
		wx.add_item(n)
	wx.selected = maxi(wx_ids.find(Settings.weather), 0)
	wx.item_selected.connect(func(i):
		_tap()
		Settings.weather = wx_ids[i]
		Settings.save())
	box.add_child(_row("Weather", wx))
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
	box.add_child(_menu_row("Character credits", "", func(): show_character_credits(back), 16))
	q.grab_focus.call_deferred()


func show_character_credits(back: Callable) -> void:
	var box := _page("character_credits", "CHARACTER CREDITS", show_settings.bind(back), 700)
	box.add_child(_label("Courier adaptations · Musa Studios", 20, Color.WHITE))
	box.add_child(_label("Hooded sweat jacket · Elvaerwyn · CC BY\nRunning shoes 01 · punkduck · CC BY 3.0\nCargo pants · Cortu Johnstone · CC0\nGloves Hand · MRT / toigo · CC0\nAnatomy and weights · MakeHuman contributors · CC0", 16, FAINT))
	box.add_child(_label("Adapted meshes, fit, skinning, textures and materials for CitySwing.", 15, FAINT))
	box.add_child(_menu_row("MakeHuman asset library", "", func(): OS.shell_open("https://static.makehumancommunity.org/assets/assetpacks.html"), 16))
	box.add_child(_menu_row("Creative Commons attribution licence", "", func(): OS.shell_open("https://creativecommons.org/licenses/by/3.0/"), 16))


# =================================================================== pause
func show_pause(free_swing := false) -> void:
	var box := _page("pause", "PAUSED", Callable(), 520, 0.35)
	if free_swing:
		# Token totals live here now (the HUD shows them on the minimap).
		var st := HBoxContainer.new()
		st.add_child(_chip("token", UiStyle.TEAL, "TOKENS %d/%d" % [SaveData.token_count(), Progress.TOKEN_TOTAL], 17))
		st.add_child(_chip("coin", Color.WHITE, "%s COINS" % Hud._fmt_int(Shop.coins()), 17))
		var rep := int(SaveData.data.get("rep", 0))
		st.add_child(_chip("job", UiStyle.GOLD, Contracts.rank_name(rep).to_upper(), 17))
		box.add_child(st)
	var b := _card("Resume", "Back to the swing", "play", func(): resume.emit(), "", true)
	_reg("resume", b)
	box.add_child(b)
	if free_swing and jobs:
		var sub := "Pick up work around the city"
		if not jobs.active.is_empty():
			sub = "On the job: %s" % jobs.active["title"]
		box.add_child(_reg("jobs", _card("Job Board", sub, "job", func(): show_jobs(show_pause.bind(free_swing)), "%d" % jobs.offers.size())))
	if free_swing:
		box.add_child(_reg("end", _card("End session", "See your distance and tokens", "check", func(): end_session.emit())))
	else:
		box.add_child(_reg("restart", _card("Restart", "From the start line", "restart", func(): restart.emit())))
	var row := HBoxContainer.new()
	if free_swing:
		row.add_child(_reg("homes", _icon_button("home", "Homes", func(): show_homes(show_pause.bind(free_swing), true))))
	row.add_child(_reg("settings", _icon_button("gear", "Settings", func(): show_settings(show_pause.bind(free_swing)))))
	if OS.is_debug_build():  # developer tool: not in TestFlight/App Store builds
		row.add_child(_reg("tuning", _icon_button("tune", "Tuning", show_tuning)))
	row.add_child(_reg("quit", _icon_button("home", "Title", func(): quit_to_title.emit())))
	box.add_child(row)
	b.grab_focus.call_deferred()


# =================================================================== jobs
## Contracts on offer around you (the same ones standing as beacons in the
## city), your rank, and the job you're on. Tracking an offer points the
## route arrow and the minimap at its pickup; the job starts when you get
## there.
func show_jobs(back: Callable) -> void:
	var box := _page("jobs", "Job Board", back, 680, 0.35)
	var rep := int(SaveData.data.get("rep", 0))
	var r := Contracts.rank_for(rep)
	# Rank card: name, bar to the next, totals.
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _box(Color(UiStyle.INK, 0.7), 16, Color(UiStyle.GOLD, 0.35), 1, 14))
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rp.add_child(rv)
	var top := HBoxContainer.new()
	top.add_child(MenuParts.Icon.new("job", UiStyle.GOLD, 30))
	var rn := _label(Contracts.RANKS[r], 26, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT)
	rn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rn)
	var nxt := "MAX RANK" if r >= Contracts.RANKS.size() - 1 else "%d / %d rep  →  %s" % [rep, Contracts.RANK_REP[r + 1], Contracts.RANKS[r + 1]]
	top.add_child(_label(nxt, 15, DIM, "semibold", HORIZONTAL_ALIGNMENT_RIGHT))
	rv.add_child(top)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = Contracts.rank_progress(rep)
	bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.1), 4))
	bar.add_theme_stylebox_override("fill", _box(UiStyle.GOLD, 4))
	rv.add_child(bar)
	rv.add_child(_label("%d done  ·  %d underworld  ·  %d busted  ·  %s coins earned  ·  contracts up to tier %d" % [
		int(SaveData.data.get("jobs_done", 0)), int(SaveData.data.get("jobs_crime", 0)),
		int(SaveData.data.get("jobs_busted", 0)), Hud._fmt_int(int(SaveData.data.get("jobs_earned", 0))),
		Contracts.max_tier(rep)], 14, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(rp)
	if jobs == null:
		return
	if not jobs.active.is_empty():
		var c := jobs.active
		box.add_child(_section("On the job"))
		box.add_child(_job_row(c, -1, back))
		var ab := _card("Drop the contract", "Counts as failed" + ("" if c["legal"] else " (no fine)"), "back",
			func():
				jobs.abandon()
				show_jobs(back))
		box.add_child(_reg("job_abandon", ab))
		return
	box.add_child(_section("Legal work"))
	box.add_child(_para("Steady pay and reputation. Land on a teal beacon to take the job.", 14))
	for o in jobs.offers:
		if o["legal"]:
			box.add_child(_job_row(o, o["id"], back))
	box.add_child(_section("Underworld"))
	box.add_child(_para("About 2.4× the pay – and drones. Stay fast and high: heat builds while one can see you, and getting busted costs a fine.", 14))
	for o in jobs.offers:
		if not o["legal"]:
			box.add_child(_job_row(o, o["id"], back))


func _job_row(c: Dictionary, id: int, back: Callable) -> PanelContainer:
	var legal: bool = c["legal"]
	var col: Color = JobBoard.COL_LEGAL if legal else JobBoard.COL_CRIME
	var on := id >= 0 and jobs.tracked == id
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(UiStyle.INK, 0.7), 16,
		col if on else Color(1, 1, 1, 0.08), 2 if on else 1, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	var ic := MenuParts.Icon.new("job" if legal else "crime", col, 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tx := VBoxContainer.new()
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tx.add_theme_constant_override("separation", 0)
	var tier := " ·  " + "★".repeat(int(c["tier"]))
	tx.add_child(_label("%s%s" % [c["title"], tier], 21, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT))
	var dist := 0
	if jobs.player:
		dist = int(jobs.player.global_position.distance_to(c["start"]))
	var info := "%s  ·  %d m away  ·  %d m route  ·  %ds" % [c["client"], dist, int(Contracts.path_length(c)), int(c["time"])]
	tx.add_child(_label(info, 14, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
	var br := _label(c["brief"], 13, FAINT, "semibold", HORIZONTAL_ALIGNMENT_LEFT)
	br.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.add_child(br)
	row.add_child(tx)
	var pay := VBoxContainer.new()
	pay.alignment = BoxContainer.ALIGNMENT_CENTER
	pay.add_child(_label(Hud._fmt_int(c["pay"]), 24, UiStyle.GOLD, "black", HORIZONTAL_ALIGNMENT_RIGHT))
	pay.add_child(_label("+%d rep" % int(c["rep"]), 13, DIM, "semibold", HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(pay)
	if id >= 0:
		var tb := _icon_button("check" if on else "play", "Tracking" if on else "Track", func():
			jobs.track(id)
			show_jobs(back))
		tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_reg("job_track_%d" % id, tb))
	return p


# ================================================================== homes
## Five real homes in the city's buildings, from the bedsit to the penthouse:
## where each is, how high, and one action – Home / Make home / Buy (with a
## confirming tap) / how many coins it needs. In Free Swing, owned homes can
## be gone to right away.
var homes_info: Array = []   # [{id, name, height, price}] (main fills it from the layout)
## One line on each home's character (HomeInteriors builds them to match).
const HOME_STYLE := ["Courier studio", "Scandi one-bed", "Industrial loft", "Marble & walnut", "Pool, mezzanine, Hall of Fame"]
var _home_confirm := ""


func show_homes(back: Callable, in_game := false) -> void:
	var box := _page("homes", "Homes", back, 640)
	var cur := Homes.selected()
	box.add_child(_para("Each home is a real flat in a real tower – wake up there, run out of the window, swing home and climb back in. Coming home rests you: your coin multiplier starts higher the better the home. At home: change in the wardrobe, sleep the day away, take work from the job screen, and see your trophies on the shelf."))
	var bal := _coin_chip(Shop.coins(), 18)
	box.add_child(bal)
	for i in homes_info.size():
		var hi: Dictionary = homes_info[i]
		var id: String = hi["id"]
		var owned := Homes.owns(id)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color(UiStyle.INK, 0.7), 16,
			ACCENT if id == cur else Color(1, 1, 1, 0.08), 2 if id == cur else 1, 12))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		p.add_child(row)
		var shot := "res://assets/ui/homes/%s.jpg" % id
		if ResourceLoader.exists(shot):
			var pic := TextureRect.new()
			pic.texture = load(shot)
			pic.custom_minimum_size = Vector2(176, 99)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.modulate = Color.WHITE if owned else Color(0.78, 0.78, 0.8)
			row.add_child(pic)
		var tx := VBoxContainer.new()
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tx.add_theme_constant_override("separation", 0)
		tx.add_child(_label(hi["name"], 22, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT))
		var perk := "  ·  rested ×%s" % Hud._fmt_mult(1.0 + i * CoinMeter.STEP) if i > 0 else ""
		tx.add_child(_label("%s  ·  %s  ·  %d m up%s" % [HOME_STYLE[i] if i < HOME_STYLE.size() else "Tier %d" % (i + 1),
			hi.get("size", ""), int(hi["height"]), perk], 14, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(tx)
		if id == cur:
			row.add_child(_chip("home", ACCENT, "HOME", 16))
		elif owned:
			var mk := _card("Make home", "", "check", func():
				Homes.select(id)
				homes_changed.emit()
				show_homes(back, in_game), "", false)
			mk.custom_minimum_size = Vector2(170, 60)
			row.add_child(_reg("home_select_" + id, mk))
		else:
			var price := Homes.price(id)
			var need := price - Shop.coins()
			var act: Button
			if need > 0:
				act = _card("%s more" % Hud._fmt_int(need), "to buy · %s" % Hud._fmt_int(price), "coin", func(): pass)
				act.disabled = true
			elif _home_confirm == id:
				act = _card("Confirm", "Spend %s" % Hud._fmt_int(price), "coin", func():
					_home_confirm = ""
					if Homes.buy(id):
						Settings.haptic(30, 0.7)
						_tap(1.4)
						homes_changed.emit()
					show_homes(back, in_game), "", true)
			else:
				act = _card("Buy", "", "coin", func():
					_home_confirm = id
					show_homes(back, in_game), Hud._fmt_int(price), true)
			act.custom_minimum_size = Vector2(196, 60)
			row.add_child(_reg("home_buy_" + id, act))
		if in_game and owned:
			var go := _icon_button("play", "Go", func(): go_home.emit(id))
			row.add_child(_reg("home_go_" + id, go))
		elif in_game:
			# Look round before you buy: you can't use it or come back in
			# through its window until it's yours.
			var vis := _icon_button("home", "Visit", func(): go_home.emit(id))
			row.add_child(_reg("home_visit_" + id, vis))
		box.add_child(p)


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
	var tw := 140 if r.has("close_calls") else 190  # four tiles fit the 640 px page
	g2.add_child(_tile("%d" % r.get("swings", 0), "Swings", tw))
	g2.add_child(_tile("×%d" % r.get("chain", 0), "Longest chain", tw))
	g2.add_child(_tile("%d km/h" % int(r.get("top_speed", 0.0) * 3.6), "Top speed", tw))
	if r.has("close_calls"):
		g2.add_child(_tile("%d" % r["close_calls"], "Close calls", tw))
	box.add_child(g2)
	if r.has("coins"):
		var cr := HBoxContainer.new()
		cr.add_child(_chip("coin", Color.WHITE, "+%s COINS" % Hud._fmt_int(r["coins"]), 20))
		cr.add_child(_chip("coin", Color.WHITE, "BEST ×%s" % Hud._fmt_mult(r.get("best_mult", 1.0)), 20))
		cr.add_child(_chip("coin", Color.WHITE, "BALANCE %s" % Hud._fmt_int(Shop.coins()), 20))
		box.add_child(cr)
	if int(r.get("jobs_session", 0)) > 0 or int(r.get("job_coins", 0)) != 0:
		box.add_child(_chip("job", UiStyle.GOLD, "%d CONTRACT%s  ·  %s COINS" % [int(r.get("jobs_session", 0)),
			"" if int(r.get("jobs_session", 0)) == 1 else "S", Hud._fmt_int(int(r.get("job_coins", 0)))], 18))
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
	var t := _label(title.capitalize() if title == title.to_upper() else title, 34, Color.WHITE, "black", HORIZONTAL_ALIGNMENT_LEFT)
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


## A wrapping paragraph for page intros (never widens the page).
func _para(text: String, size := 15) -> Label:
	var l := _label(text, size, DIM, "semibold", HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 200
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
