class_name MenuParts
extends RefCounted
## Building blocks for the front end: vector icons, the logo with its web
## line, and the left-hand backdrop gradient. Everything is drawn in code
## (no image assets), so it stays sharp at any resolution.


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
			_:
				draw_circle(c, s * 0.3, color)


## CITY / SWING lockup with a web line slung under the second word.
class Logo:
	extends Control
	var scale_k := 1.0

	func _init(k := 1.0) -> void:
		scale_k = k
		custom_minimum_size = Vector2(470, 196) * k
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := scale_k
		var black := UiStyle.font("black")
		var fs := int(124 * k)
		var sw := "SWING"
		var width := black.get_string_size(sw, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# SWING hangs off a web line: anchored up and to the right, taut down
		# to the top of the G (drawn first, so the letters sit over it).
		var anchor := Vector2(4 + width / k + 34, 4) * k
		var grip := Vector2(4 + width / k - 30, 78) * k
		draw_line(anchor, grip, Color(1, 1, 1, 0.9), 3.0 * k, true)
		draw_circle(anchor, 5.0 * k, Color.WHITE)
		draw_string(black, Vector2(6, 52) * k, "C I T Y", HORIZONTAL_ALIGNMENT_LEFT, -1, int(44 * k),
			Color(1, 1, 1, 0.95))
		draw_string(black, Vector2(4, 158) * k + Vector2(4, 5) * k, sw, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0, 0, 0, 0.35))
		draw_string(black, Vector2(4, 158) * k, sw, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.GOLD)
		draw_circle(grip, 4.5 * k, UiStyle.TEAL)


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
