class_name MenuParts
extends RefCounted
## Building blocks for the front end: vector icons (drawn in code, sharp at
## any resolution), the brand wordmark, and the backdrop gradients.


## A small vector icon. `kind`: play, timer, endurance, training, suit, stats,
## gear, back, token, medal, pause, restart, home, lock, check, tune, bench.
class Icon:
	extends Control
	var kind := "play"
	var color := Color.WHITE
	var stroke := 3.0

	func _init(k := "play", c := Color.WHITE, size := 40.0) -> void:
		kind = k
		color = c
		custom_minimum_size = Vector2(size, size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		var c := o + Vector2(s, s) * 0.5
		var w := maxf(2.0, s * 0.075)
		match kind:
			"play":
				draw_colored_polygon(PackedVector2Array([o + Vector2(0.3, 0.2) * s, o + Vector2(0.82, 0.5) * s,
					o + Vector2(0.3, 0.8) * s]), color)
			"timer":
				draw_arc(c + Vector2(0, s * 0.05), s * 0.36, 0.0, TAU, 32, color, w, true)
				draw_line(c + Vector2(0, s * 0.05), c + Vector2(0, -s * 0.18), color, w, true)
				draw_line(c + Vector2(0, s * 0.05), c + Vector2(s * 0.14, s * 0.12), color, w, true)
				draw_line(c + Vector2(-s * 0.1, -s * 0.42), c + Vector2(s * 0.1, -s * 0.42), color, w, true)
			"endurance":
				# Infinity loop.
				var pts := PackedVector2Array()
				for i in 49:
					var a := TAU * i / 48.0
					var den := 1.0 + sin(a) * sin(a)
					pts.append(c + Vector2(cos(a) / den, sin(a) * cos(a) / den) * s * 0.42)
				draw_polyline(pts, color, w, true)
			"training":
				# Target with an arrow.
				draw_arc(c, s * 0.38, 0.0, TAU, 32, color, w, true)
				draw_arc(c, s * 0.2, 0.0, TAU, 24, color, w, true)
				draw_circle(c, s * 0.06, color)
			"suit":
				# Hoodie silhouette.
				var p := PackedVector2Array([Vector2(0.32, 0.16), Vector2(0.42, 0.12), Vector2(0.5, 0.2),
					Vector2(0.58, 0.12), Vector2(0.68, 0.16), Vector2(0.9, 0.36), Vector2(0.8, 0.48),
					Vector2(0.72, 0.42), Vector2(0.72, 0.88), Vector2(0.28, 0.88), Vector2(0.28, 0.42),
					Vector2(0.2, 0.48), Vector2(0.1, 0.36)])
				for i in p.size():
					p[i] = o + p[i] * s
				draw_colored_polygon(p, color)
			"stats":
				for i in 3:
					var h: float = [0.3, 0.55, 0.42][i] * s
					var x := o.x + s * (0.18 + i * 0.25)
					draw_rect(Rect2(x, o.y + s * 0.85 - h, s * 0.16, h), color)
			"gear":
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * s * 0.26, c + Vector2(cos(a), sin(a)) * s * 0.42, color,
						s * 0.13)
				draw_circle(c, s * 0.3, color)
				draw_circle(c, s * 0.12, Color(0, 0, 0, 0.0) if color.a < 0.1 else UiStyle.INK)
			"back":
				draw_polyline(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.24), c + Vector2(-s * 0.14, 0),
					c + Vector2(s * 0.1, s * 0.24)]), color, w * 1.3, true)
			"token":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.4), c + Vector2(s * 0.3, 0),
					c + Vector2(0, s * 0.4), c + Vector2(-s * 0.3, 0)]), color)
			"medal":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.42), c + Vector2(-s * 0.05, -s * 0.42),
					c + Vector2(s * 0.08, -s * 0.05), c + Vector2(-s * 0.06, -s * 0.05)]), color.darkened(0.25))
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.2, -s * 0.42), c + Vector2(s * 0.05, -s * 0.42),
					c + Vector2(-s * 0.08, -s * 0.05), c + Vector2(s * 0.06, -s * 0.05)]), color.darkened(0.1))
				draw_circle(c + Vector2(0, s * 0.14), s * 0.24, color)
			"pause":
				draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.25), Vector2(s * 0.13, s * 0.5)), color)
				draw_rect(Rect2(c + Vector2(s * 0.07, -s * 0.25), Vector2(s * 0.13, s * 0.5)), color)
			"restart":
				draw_arc(c, s * 0.3, -PI * 0.35, PI * 1.45, 28, color, w, true)
				var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * s * 0.3
				draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.02, -s * 0.16), tip + Vector2(s * 0.15, s * 0.02),
					tip + Vector2(-s * 0.1, s * 0.08)]), color)
			"home":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.36), c + Vector2(s * 0.36, -s * 0.02),
					c + Vector2(s * 0.26, -s * 0.02), c + Vector2(s * 0.26, s * 0.34), c + Vector2(-s * 0.26, s * 0.34),
					c + Vector2(-s * 0.26, -s * 0.02), c + Vector2(-s * 0.36, -s * 0.02)]), color)
			"lock":
				draw_arc(c + Vector2(0, -s * 0.08), s * 0.16, PI, TAU, 16, color, w, true)
				draw_line(c + Vector2(-s * 0.16, -s * 0.08), c + Vector2(-s * 0.16, s * 0.02), color, w)
				draw_line(c + Vector2(s * 0.16, -s * 0.08), c + Vector2(s * 0.16, s * 0.02), color, w)
				draw_rect(Rect2(c + Vector2(-s * 0.25, 0), Vector2(s * 0.5, s * 0.34)), color)
			"job":
				# Briefcase: handle, body, clasp line.
				draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.3), Vector2(s * 0.24, s * 0.12)), color, false, w * 0.8)
				draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.18), Vector2(s * 0.72, s * 0.48)), color)
				draw_line(c + Vector2(-s * 0.36, s * 0.0), c + Vector2(s * 0.36, s * 0.0), Color(0, 0, 0, 0.45), w * 0.7)
			"crime":
				# Domino mask.
				var m := PackedVector2Array([c + Vector2(-s * 0.42, -s * 0.12), c + Vector2(-s * 0.1, -s * 0.16),
					c + Vector2(0, -s * 0.06), c + Vector2(s * 0.1, -s * 0.16), c + Vector2(s * 0.42, -s * 0.12),
					c + Vector2(s * 0.36, s * 0.14), c + Vector2(s * 0.08, s * 0.16), c + Vector2(0, s * 0.06),
					c + Vector2(-s * 0.08, s * 0.16), c + Vector2(-s * 0.36, s * 0.14)])
				draw_colored_polygon(m, color)
				draw_circle(c + Vector2(-s * 0.2, 0), s * 0.07, Color(0, 0, 0, 0.6))
				draw_circle(c + Vector2(s * 0.2, 0), s * 0.07, Color(0, 0, 0, 0.6))
			"check":
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.25, 0), c + Vector2(-s * 0.06, s * 0.2),
					c + Vector2(s * 0.28, -s * 0.2)]), color, w * 1.4, true)
			"tune":
				for i in 3:
					var y := o.y + s * (0.25 + i * 0.25)
					draw_line(Vector2(o.x + s * 0.15, y), Vector2(o.x + s * 0.85, y), color, w * 0.8)
					draw_circle(Vector2(o.x + s * float([0.35, 0.65, 0.45][i]), y), s * 0.09, color)
			"bench":
				draw_arc(c + Vector2(0, s * 0.12), s * 0.36, PI, TAU, 24, color, w, true)
				draw_line(c + Vector2(0, s * 0.12), c + Vector2(s * 0.2, -s * 0.12), color, w, true)
			"coin":
				Hud.draw_coin(self, c, s * 0.4)
			"shop":
				# Shopping bag.
				draw_rect(Rect2(o + Vector2(0.2, 0.34) * s, Vector2(0.6, 0.52) * s), color)
				draw_arc(o + Vector2(0.5, 0.34) * s, s * 0.15, PI, TAU, 16, color, w, true)
			_:
				draw_circle(c, s * 0.3, color)


## A gadget's icon (shop swatch, touch button, HUD). `s` = icon size.
static func draw_gadget(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.09)
	match kind:
		"boost":  # boot with flames
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, -0.45) * s, c + Vector2(-0.05, -0.45) * s,
				c + Vector2(-0.05, -0.05) * s, c + Vector2(0.4, 0.05) * s, c + Vector2(0.4, 0.2) * s,
				c + Vector2(-0.3, 0.2) * s]), col)
			for x in [-0.22, 0.0, 0.22]:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(x - 0.08, 0.27) * s, c + Vector2(x + 0.08, 0.27) * s,
					c + Vector2(x, 0.5) * s]), UiStyle.GOLD)
		"glide":  # swept wings
			for sx in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(sx * 0.06, -0.12) * s, c + Vector2(sx * 0.5, -0.02) * s,
					c + Vector2(sx * 0.44, 0.1) * s, c + Vector2(sx * 0.06, 0.16) * s]), col)
			ci.draw_circle(c + Vector2(0, -0.2) * s, s * 0.08, col)
		"focus":  # watch face
			ci.draw_rect(Rect2(c + Vector2(-0.14, -0.5) * s, Vector2(0.28, 1.0) * s), Color(col, 0.45))
			ci.draw_circle(c, s * 0.34, Color(0.1, 0.1, 0.12))
			ci.draw_arc(c, s * 0.34, 0, TAU, 28, col, w, true)
			ci.draw_line(c, c + Vector2(0, -0.22) * s, col, w, true)
			ci.draw_line(c, c + Vector2(0.15, 0.06) * s, col, w, true)
		"surge":  # horseshoe magnet
			ci.draw_arc(c + Vector2(0, -0.05) * s, s * 0.28, PI, TAU, 20, Color(0.85, 0.12, 0.2), s * 0.16, true)
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(sx * 0.28 - 0.08, -0.05) * s, Vector2(0.16, 0.3) * s), Color(0.85, 0.12, 0.2))
				ci.draw_rect(Rect2(c + Vector2(sx * 0.28 - 0.08, 0.25) * s, Vector2(0.16, 0.13) * s), col)


## A shop item's picture: colour items as a swatch shaped like the garment,
## webs as a line, headwear and face pieces as small drawings on a head.
class Swatch:
	extends Control
	var it := {}

	func _init(item: Dictionary, size := 52.0) -> void:
		it = item
		custom_minimum_size = Vector2(size, size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		var c := o + Vector2(s, s) * 0.5
		draw_circle(c, s * 0.5, Color(1, 1, 1, 0.07))
		var col: Color = it.get("color", Color.WHITE)
		var P := func(pts: Array) -> PackedVector2Array:
			var out := PackedVector2Array()
			for q in pts:
				out.append(o + (q as Vector2) * s)
			return out
		match it.get("slot", ""):
			"suit":
				draw_colored_polygon(P.call([Vector2(0.32, 0.2), Vector2(0.42, 0.16), Vector2(0.5, 0.24),
					Vector2(0.58, 0.16), Vector2(0.68, 0.2), Vector2(0.88, 0.38), Vector2(0.79, 0.5),
					Vector2(0.71, 0.44), Vector2(0.71, 0.84), Vector2(0.29, 0.84), Vector2(0.29, 0.44),
					Vector2(0.21, 0.5), Vector2(0.12, 0.38)]), col)
			"pants":
				draw_colored_polygon(P.call([Vector2(0.3, 0.16), Vector2(0.7, 0.16), Vector2(0.74, 0.86),
					Vector2(0.56, 0.86), Vector2(0.5, 0.36), Vector2(0.44, 0.86), Vector2(0.26, 0.86)]), col)
			"shoes":
				var sole: Color = it["sole"] if it.get("sole") is Color else Progress.current_suit_color()
				draw_colored_polygon(P.call([Vector2(0.16, 0.36), Vector2(0.4, 0.34), Vector2(0.52, 0.5),
					Vector2(0.84, 0.56), Vector2(0.86, 0.66), Vector2(0.16, 0.66)]), col)
				draw_rect(Rect2(o + Vector2(0.14, 0.66) * s, Vector2(0.74, 0.1) * s), sole)
			"gloves":
				draw_colored_polygon(P.call([Vector2(0.3, 0.86), Vector2(0.3, 0.42), Vector2(0.22, 0.3),
					Vector2(0.3, 0.26), Vector2(0.38, 0.36), Vector2(0.38, 0.16), Vector2(0.47, 0.16), Vector2(0.48, 0.13),
					Vector2(0.58, 0.14), Vector2(0.6, 0.17), Vector2(0.68, 0.2), Vector2(0.72, 0.42), Vector2(0.7, 0.86)]), col)
			"gadget":
				if it.get("kind", "") == "":
					draw_arc(c, s * 0.42, 0, TAU, 24, Color(1, 1, 1, 0.25), 2.0, true)
				else:
					MenuParts.draw_gadget(self, it["kind"], c, s * 0.62, UiStyle.TEAL)
			"web":
				var pts := PackedVector2Array()
				for i in 25:
					var t := i / 24.0
					pts.append(o + Vector2(0.16 + 0.68 * t, 0.24 + 0.52 * t + 0.22 * sin(t * PI)) * s)
				if it.get("rainbow", false):
					for i in 24:
						draw_line(pts[i], pts[i + 1], Color.from_hsv(i / 24.0, 0.75, 1.0), s * 0.08, true)
				else:
					draw_polyline(pts, col, s * 0.08, true)
				draw_circle(pts[0], s * 0.06, Color(1, 1, 1, 0.5))
			_:
				_draw_head(c, s)

	func _draw_head(c: Vector2, s: float) -> void:
		var skin := Color(0.74, 0.52, 0.4)
		var suit := Progress.current_suit_color()
		var model: String = it.get("model", "")
		var r := s * 0.26
		var hc := c + Vector2(0, s * 0.06)
		if model != "hood":
			draw_circle(hc, r, skin)
			draw_arc(hc, r, PI * 1.05, PI * 1.95, 16, Color(0.08, 0.06, 0.05), s * 0.1, true)
		match model:
			"hood":
				draw_circle(hc, r * 1.3, suit)
				draw_circle(hc + Vector2(0, s * 0.03), r * 0.82, skin)
			"cap":
				draw_arc(hc, r * 1.04, PI, TAU, 18, suit, s * 0.16, true)
				draw_rect(Rect2(hc + Vector2(-r * 0.2, -r * 0.42), Vector2(r * 1.6, s * 0.07)), suit.darkened(0.45))
			"beanie":
				draw_colored_polygon(PackedVector2Array([hc + Vector2(-r * 1.08, -r * 0.1), hc + Vector2(-r * 0.9, -r * 0.85),
					hc + Vector2(0, -r * 1.2), hc + Vector2(r * 0.9, -r * 0.85), hc + Vector2(r * 1.08, -r * 0.1)]),
					Color(0.92, 0.9, 0.84))
				draw_rect(Rect2(hc + Vector2(-r * 1.1, -r * 0.3), Vector2(r * 2.2, r * 0.3)), Color(0.84, 0.82, 0.76))
				draw_circle(hc + Vector2(0, -r * 1.3), r * 0.28, suit)
			"headphones":
				draw_arc(hc, r * 1.12, PI * 1.02, PI * 1.98, 18, Color(0.08, 0.08, 0.09), s * 0.07, true)
				for sx in [-1.0, 1.0]:
					draw_rect(Rect2(hc + Vector2(sx * r * 1.05 - r * 0.22, -r * 0.3), Vector2(r * 0.44, r * 0.66)),
						Color(0.2, 0.22, 0.24))
					draw_circle(hc + Vector2(sx * r * 1.05, r * 0.03), r * 0.14, Shop.CLASSIC_GLOW)
			"crown":
				var gold := Color(0.96, 0.74, 0.22)
				var pts := PackedVector2Array([hc + Vector2(-r * 0.9, -r * 0.6)])
				for i in 5:
					pts.append(hc + Vector2(-r * 0.9 + r * 0.45 * (i + 0.5) * 0.8, -r * (1.45 if i % 2 == 0 else 1.0)))
				pts.append_array([hc + Vector2(r * 0.9, -r * 1.45), hc + Vector2(r * 0.9, -r * 0.6)])
				draw_colored_polygon(pts, gold)
			"shades":
				for sx in [-1.0, 1.0]:
					draw_circle(hc + Vector2(sx * r * 0.42, r * 0.02), r * 0.32, Color(0.05, 0.05, 0.07))
				draw_line(hc + Vector2(-r * 0.12, -r * 0.05), hc + Vector2(r * 0.12, -r * 0.05), Color(0.05, 0.05, 0.07), s * 0.04)
			"visor":
				draw_rect(Rect2(hc + Vector2(-r * 1.02, -r * 0.24), Vector2(r * 2.04, r * 0.42)), Shop.CLASSIC_GLOW)
			"mask":
				draw_colored_polygon(PackedVector2Array([hc + Vector2(-r * 1.0, r * 0.12), hc + Vector2(r * 1.0, r * 0.12),
					hc + Vector2(r * 0.75, r * 0.8), hc + Vector2(0, r * 1.05), hc + Vector2(-r * 0.75, r * 0.8)]), suit)
			"":
				if it.get("slot", "") == "face":
					draw_arc(c, s * 0.42, 0, TAU, 24, Color(1, 1, 1, 0.25), 2.0, true)


## The City Swing wordmark (assets/brand/wordmark_stacked.png, rendered by
## tools/brand/render.mjs). `k` = 1 is 470 px wide.
class Logo:
	extends TextureRect

	func _init(k := 1.0) -> void:
		texture = load("res://assets/brand/wordmark_stacked.png")
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		var aspect := texture.get_height() / float(texture.get_width()) if texture else 0.42
		custom_minimum_size = Vector2(470.0, 470.0 * aspect) * k
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE


## Full-rect gradient: dark on the left where the menus sit, clear on the
## right so the city and the hero stay visible.
static func backdrop(strength := 1.0, reach := 0.62) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, reach * 0.55, reach, 1.0])
	g.colors = PackedColorArray([Color(UiStyle.INK, 0.9 * strength), Color(UiStyle.INK, 0.72 * strength),
		Color(UiStyle.INK, 0.0), Color(UiStyle.INK, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Vertical fade (bottom dark) for screens with content along the bottom.
static func floor_fade(strength := 0.6) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(UiStyle.INK, 0.0), Color(UiStyle.INK, 0.0), Color(UiStyle.INK, strength)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Soft shade along one edge (right by default) so menu text over the live
## city stays readable without a panel: dark at the edge, clear by `reach`.
static func edge_shade(strength := 0.7, reach := 0.42, right := true) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0 - reach, 1.0 - reach * 0.45, 1.0])
	g.colors = PackedColorArray([Color(UiStyle.INK, 0.0), Color(UiStyle.INK, 0.0),
		Color(UiStyle.INK, 0.45 * strength), Color(UiStyle.INK, 0.8 * strength)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	if not right:
		tex.fill_from = Vector2(1, 0)
		tex.fill_to = Vector2(0, 0)
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
