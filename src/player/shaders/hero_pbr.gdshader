// Authored UV textures; garment fit and skinning live in the Blender asset.
shader_type spatial;
// Both sides: looking into an opening (waistband, cuff, hem, collar) shows
// the garment's shaded inside, never the sky through the body.
render_mode cull_disabled, diffuse_burley;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec3 tint = vec3(1.0);
uniform vec3 sole_tint = vec3(1.0);
uniform bool has_sole = false;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D ao_map : filter_linear_mipmap, hint_default_white;
uniform sampler2D roughness_map : filter_linear_mipmap, hint_default_white;
uniform float roughness = 0.8;
uniform float normal_strength = 0.0;
uniform vec3 surface_emission = vec3(0.0);
uniform vec3 cloth_drag = vec3(0.0);
uniform float cloth_flutter = 0.0;
uniform float cloth_time = 0.0;
uniform vec3 cloth_wind_dir = vec3(0.0, 0.0, 1.0);
global uniform float wetness;
void vertex() {
    float freedom = UV2.x;
    mat3 world = mat3(MODEL_MATRIX);
    vec3 normal_world = normalize(world * NORMAL);
    vec3 offset = cloth_drag * freedom;
    offset -= normal_world * min(dot(offset, normal_world), 0.0);
    float ripple = sin(cloth_time * 11.0 + VERTEX.y * 16.0 + VERTEX.x * 7.0);
    offset += normal_world * ripple * cloth_flutter * freedom * 0.004;
    VERTEX += inverse(world) * offset;
}
void fragment() {
    vec3 outfit_tint = has_sole ? mix(tint, sole_tint, clamp(UV2.y, 0.0, 1.0)) : tint;
    ALBEDO = texture(albedo_map, UV).rgb * base_color.rgb * outfit_tint;
    if (!FRONT_FACING) {
        ALBEDO *= 0.32;  // the inside of the cloth, in its own shadow
    }
    float surface_roughness = roughness * texture(roughness_map, UV).g;
    ROUGHNESS = mix(surface_roughness, max(0.3, surface_roughness - 0.18), wetness);
    SPECULAR = 0.35;
    EMISSION = surface_emission;
    AO = FRONT_FACING ? texture(ao_map, UV).r : 0.35;
    AO_LIGHT_AFFECT = 0.15;
    NORMAL_MAP = texture(normal_map, UV).rgb;
    NORMAL_MAP_DEPTH = normal_strength;
}
