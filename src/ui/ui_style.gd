class_name UiStyle
extends RefCounted
## Shared HUD / controls / menu look: Outfit (assets/fonts, OFL) and the
## palette. Fonts fall back to the engine font if the files are missing.

const GOLD := Color(1.0, 0.82, 0.4)
const TEAL := Color(0.45, 1.0, 0.85)
const INK := Color(0.05, 0.06, 0.09)
const PANEL := Color(0.05, 0.06, 0.09, 0.42)

static var _fonts := {}


## weight: "semibold", "bold" or "black".
static func font(weight := "bold") -> Font:
	if not _fonts.has(weight):
		var path := "res://assets/fonts/outfit_%s.ttf" % weight
		_fonts[weight] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[weight]


## Rounded translucent pill behind HUD text.
static func pill(ci: CanvasItem, rect: Rect2, col := PANEL) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rect.size.y * 0.5))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, rect)
