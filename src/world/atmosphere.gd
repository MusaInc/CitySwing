class_name Atmosphere
extends Node3D
## Sky, sun, fog and tonemapping for the whole game. One preset: late-afternoon
## golden hour over the river – low warm sun, long shadows, hazy depth.
## Building/water shaders receive the same sky colours so their reflections match.

const ZENITH := Color(0.17, 0.38, 0.74)
const HORIZON := Color(0.78, 0.84, 0.9)
## Sun direction (towards the sun), shared with the facade shader so window
## reveals and corners shade on the side the light actually comes from.
const SUN_ROT := Vector3(-38.0, -112.0, 0.0)

var env: Environment
var sun: DirectionalLight3D


static func sun_direction() -> Vector3:
	return Basis.from_euler(SUN_ROT * PI / 180.0) * Vector3.BACK


func _ready() -> void:
	var settings := get_node_or_null("/root/Settings")
	var preset: Dictionary = settings.preset() if settings else {"shadows": true, "glow": true}
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://src/world/shaders/sky.gdshader")
	sky_mat.set_shader_parameter("zenith", ZENITH)
	sky_mat.set_shader_parameter("horizon", HORIZON)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Warm sun, cool sky fill: lit faces read gold, shaded faces read blue-violet
	# instead of one warm-grey wash. Kept low so faces away from the sun have
	# real contrast against faces towards it.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.ambient_light_color = Color(0.56, 0.66, 0.9)
	env.ambient_light_sky_contribution = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	# Depth haze: nothing within ~180 m, building to a soft blue veil on the
	# skyline – nearby blocks stay crisp, the far city recedes.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 180.0
	env.fog_depth_end = 2600.0
	env.fog_depth_curve = 1.6
	env.fog_density = 0.62
	env.fog_light_color = Color(0.68, 0.77, 0.9)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.3
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.15
	env.glow_enabled = preset.get("glow", true)
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.1
	env.adjustment_color_correction = grade_lut()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# West-south-west, behind the river: a warm late-afternoon sun, high
	# enough (38°) that it reaches down into the avenues.
	sun.rotation_degrees = SUN_ROT
	sun.light_color = Color(1.0, 0.84, 0.64)
	sun.light_energy = 2.3
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = preset.get("shadows", true)
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_blend_splits = false
	add_child(sun)


## CitySwing's grade, as a 3D LUT: cool, slightly lifted shadows, warm
## highlights, a gentle S-curve and richer mid saturation. Built once (17³).
static func grade_lut() -> ImageTexture3D:
	const N := 17
	var layers: Array[Image] = []
	for b in N:
		var img := Image.create(N, N, false, Image.FORMAT_RGB8)
		for g in N:
			for r in N:
				img.set_pixel(r, g, grade(Color(r / (N - 1.0), g / (N - 1.0), b / (N - 1.0))))
		layers.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, N, N, N, false, layers)
	return tex


static func grade(c: Color) -> Color:
	var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	# S-curve on luminance (smoothstep blended 35%), applied as a ratio.
	var s := lerpf(l, l * l * (3.0 - 2.0 * l), 0.35)
	var k := s / maxf(l, 0.0001)
	var o := Color(c.r * k, c.g * k, c.b * k)
	# Split tone: shadows towards blue-violet, highlights towards warm gold.
	var sh := clampf(1.0 - s * 2.2, 0.0, 1.0)
	var hi := clampf((s - 0.55) * 2.2, 0.0, 1.0)
	o += Color(-0.012, 0.004, 0.035) * sh + Color(0.03, 0.012, -0.03) * hi
	# Mid saturation boost (fades out in deep shadow and near-white).
	var ol := 0.2126 * o.r + 0.7152 * o.g + 0.0722 * o.b
	var sat := 1.0 + 0.12 * (1.0 - absf(ol * 2.0 - 1.0))
	o = Color(ol + (o.r - ol) * sat, ol + (o.g - ol) * sat, ol + (o.b - ol) * sat)
	return Color(clampf(o.r, 0.0, 1.0), clampf(o.g, 0.0, 1.0), clampf(o.b, 0.0, 1.0))
