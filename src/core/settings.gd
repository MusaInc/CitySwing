extends Node
## Player settings + graphics quality presets (user://settings.cfg).

signal changed

const PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH }

const PRESETS := {
	Quality.LOW: {
		"fps": 30, "render_scale": 0.7, "shadows": false, "view_distance": 650.0,
		"msaa": Viewport.MSAA_DISABLED, "fog": true, "props": 0.5, "traffic": 0.4, "glow": false,
	},
	Quality.MEDIUM: {
		"fps": 30, "render_scale": 0.85, "shadows": true, "view_distance": 900.0,
		"msaa": Viewport.MSAA_2X, "fog": true, "props": 0.8, "traffic": 0.7, "glow": true,
	},
	Quality.HIGH: {
		"fps": 60, "render_scale": 1.0, "shadows": true, "view_distance": 1300.0,
		"msaa": Viewport.MSAA_4X, "fog": true, "props": 1.0, "traffic": 1.0, "glow": true,
	},
}

var quality: int = Quality.MEDIUM
var fps_60 := true  # swinging needs it; Settings can drop to 30 for battery
const VERSION := 2  # bump to migrate saved settings to new defaults
var haptics := true
var show_perf := false
var look_sensitivity := 1.0
var invert_y := false
## "assist": SWING fires at the reticle target. "tap": fire where you touch.
var aim_mode := "assist"
var music_volume := 0.6
var sfx_volume := 1.0
## Post-process style, a LookFilter.STYLES key.
var look := "comic"
var tuning_overrides := {}  # SwingParams property -> value, from the in-game tuning panel


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		quality = cfg.get_value("gfx", "quality", quality)
		fps_60 = cfg.get_value("gfx", "fps_60", fps_60)
		show_perf = cfg.get_value("gfx", "show_perf", show_perf)
		look = cfg.get_value("gfx", "look", look)
		haptics = cfg.get_value("input", "haptics", haptics)
		look_sensitivity = cfg.get_value("input", "look_sensitivity", look_sensitivity)
		invert_y = cfg.get_value("input", "invert_y", invert_y)
		aim_mode = cfg.get_value("input", "aim_mode", aim_mode)
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		tuning_overrides = cfg.get_value("tuning", "overrides", {})
		if cfg.get_value("meta", "version", 1) < 2:
			fps_60 = true  # 0.1.x saved the old 30 fps default
		if not OS.is_debug_build():
			tuning_overrides = {}  # the tuning panel is a developer tool
	apply()


func preset() -> Dictionary:
	return PRESETS[quality]


func apply() -> void:
	var p := preset()
	Engine.max_fps = 60 if (fps_60 or p["fps"] == 60) else 30
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = p["render_scale"]
		# Stylised looks read the depth buffer, which MSAA leaves unresolved on
		# the Mobile/Compatibility renderers: swap MSAA for FXAA (it smooths the
		# ink lines too).
		var stylised := look != "clean" and RenderingServer.get_current_rendering_method() != "gl_compatibility"
		vp.msaa_3d = Viewport.MSAA_DISABLED if stylised else p["msaa"]
		if RenderingServer.get_current_rendering_method() != "gl_compatibility":  # no FXAA there
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if stylised else Viewport.SCREEN_SPACE_AA_DISABLED
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gfx", "quality", quality)
	cfg.set_value("gfx", "fps_60", fps_60)
	cfg.set_value("gfx", "show_perf", show_perf)
	cfg.set_value("gfx", "look", look)
	cfg.set_value("input", "haptics", haptics)
	cfg.set_value("input", "look_sensitivity", look_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "aim_mode", aim_mode)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("tuning", "overrides", tuning_overrides)
	cfg.set_value("meta", "version", VERSION)
	cfg.save(PATH)
	apply()


## Base params from config/swing_params.tres with in-game tuning applied on top.
func swing_params() -> SwingParams:
	var p: SwingParams = load("res://config/swing_params.tres").duplicate()
	for k in tuning_overrides:
		p.set(k, tuning_overrides[k])
	return p


func haptic(ms: int, amplitude: float = 0.5) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)
