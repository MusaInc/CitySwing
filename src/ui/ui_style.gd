class_name UiStyle
extends RefCounted
## Shared HUD / controls / menu look: Outfit (assets/fonts, OFL) and the
## brand palette (docs/BRAND.md). Fonts fall back to the engine font if the
## files are missing.

const GOLD := Color("#FFC93C")   # Signal Gold: primary, calls to action
const EMBER := Color("#FF4D3D")  # hero suit, warnings
const TEAL := Color("#5CF2D0")   # Web Teal: tokens, highlights
const WEB := Color("#F7F3EA")    # Web White: text, the web line
const DUSK := Color("#43286F")   # panels, sky
const INK := Color("#110D26")    # Night Ink: type on gold, silhouettes
const PANEL := Color(0.067, 0.051, 0.149, 0.5)

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
