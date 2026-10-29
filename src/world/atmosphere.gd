class_name Atmosphere
extends Node3D
## Sky, sun, fog and tonemapping for the whole game. One preset: late-afternoon
## golden hour over the river – low warm sun, long shadows, hazy depth.
## Building/water shaders receive the same sky colours so their reflections match.

const ZENITH := Color(0.24, 0.42, 0.72)
const HORIZON := Color(0.84, 0.8, 0.78)

var env: Environment
var sun: DirectionalLight3D


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
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	# Part sky, part warm street bounce: shaded canyons read as warm stone and
	# coloured glass, not one blue-grey wash.
	env.ambient_light_color = Color(0.78, 0.7, 0.62)
	env.ambient_light_sky_contribution = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.8, 0.78, 0.8)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.18
	env.fog_density = 0.00048
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	env.fog_height = 40.0
	env.fog_height_density = 0.004
	env.glow_enabled = preset.get("glow", true)
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# West-south-west, behind the river: still a warm late-afternoon sun, but
	# high enough (36°) that it reaches down into the avenues.
	sun.rotation_degrees = Vector3(-36.0, -112.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.light_energy = 1.8
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = preset.get("shadows", true)
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_blend_splits = false
	add_child(sun)
