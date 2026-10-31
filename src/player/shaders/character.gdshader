// Character: one vertex-coloured surface per body part (baked by the Blender
// kit). COLOR.a == 0 marks emissive gear (spool rings, gauntlet LED, visor).
// A soft rim light keeps the silhouette readable against busy facades.
//
// Outfit (shop): the baked palette colours are keys. Each region's key is
// swapped for the equipped colour per vertex (so the swap interpolates
// cleanly across seams); unknown colours are left alone.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec3 rim_color : source_color = vec3(1.0, 0.88, 0.72);
global uniform vec3 sun_dir;
global uniform float night;
global uniform float wetness;
uniform float rim_strength = 0.55;
// Same space as the baked vertex colours.
uniform vec3 suit_color = vec3(0.796, 0.098, 0.09);
uniform vec3 pants_color = vec3(0.118, 0.141, 0.2);
uniform vec3 shoe_color = vec3(0.929, 0.929, 0.894);
uniform vec3 sole_color = vec3(0.796, 0.118, 0.098);
uniform vec3 glove_color = vec3(0.098, 0.098, 0.106);
uniform vec3 glow_color = vec3(0.2, 0.945, 0.945);

const vec3 K_JACKET = vec3(0.796, 0.098, 0.090);
const vec3 K_JACKET_DK = vec3(0.416, 0.047, 0.047);
const vec3 K_SOLE = vec3(0.796, 0.118, 0.098);
const vec3 K_PANTS = vec3(0.118, 0.141, 0.200);
const vec3 K_PANTS_DK = vec3(0.078, 0.090, 0.129);
const vec3 K_SNEAKER = vec3(0.929, 0.929, 0.894);
const vec3 K_GLOVE = vec3(0.098, 0.098, 0.106);

// Baked ambient occlusion (build_character.py bake_ao): UV = (ao, 1) on the
// meshes that carry it; anything else (UV.y = 0) stays unshaded.
varying float v_ao;

float is_key(vec3 c, vec3 k) {
	vec3 d = abs(c - k);
	return step(max(d.r, max(d.g, d.b)), 0.012);
}

void vertex() {
	v_ao = UV.y > 0.5 ? UV.x : 1.0;
	vec3 c = COLOR.rgb;
	vec3 o = c;
	if (COLOR.a < 0.5) {
		o = glow_color;
	} else {
		o = mix(o, suit_color, is_key(c, K_JACKET));
		o = mix(o, suit_color * 0.52, is_key(c, K_JACKET_DK));
		o = mix(o, sole_color, is_key(c, K_SOLE));
		o = mix(o, pants_color, is_key(c, K_PANTS));
		o = mix(o, pants_color * 0.66, is_key(c, K_PANTS_DK));
		o = mix(o, shoe_color, is_key(c, K_SNEAKER));
		o = mix(o, glove_color, is_key(c, K_GLOVE));
	}
	COLOR.rgb = o;
}

void fragment() {
	float glow = 1.0 - COLOR.a;
	// The palette was authored in display (sRGB) values; take it most of the
	// way to linear so the suit reads deep crimson under the warm sun instead
	// of a pale salmon, and the trousers a true dark navy.
	vec3 base = pow(COLOR.rgb, vec3(2.0));
	// Creases and contact shadow (underarms, collar, between the legs,
	// inside the hood) – a little in the albedo so it reads in direct sun
	// too, the rest on ambient light.
	float ao = clamp(v_ao, 0.0, 1.0);
	ALBEDO = base * mix(0.55, 1.0, smoothstep(0.1, 0.95, ao));
	AO = ao;
	AO_LIGHT_AFFECT = 0.0;
	// Suit fabric has a soft sheen; trainers and gloves stay matte.
	ROUGHNESS = mix(mix(0.6, 0.38, wetness), 0.3, glow);
	EMISSION = COLOR.rgb * glow * 2.5;
	// Two-tone rim: warm on the sun side, cool sky-blue elsewhere, so the
	// silhouette separates from both lit and shaded facades at a distance.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 n_w = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float sun_side = clamp(dot(n_w, sun_dir) * 0.5 + 0.5, 0.0, 1.0);
	vec3 rim_c = mix(vec3(0.55, 0.75, 1.0), mix(rim_color, vec3(0.6, 0.7, 1.0), night), sun_side);
	// (At night a cooler, softer moonlit rim keeps the silhouette readable.)
	EMISSION += rim_c * rim * rim_strength * mix(1.0, 0.75, night) * (1.0 - glow) * ao;
}
