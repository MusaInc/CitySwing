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
uniform float rim_strength = 0.35;
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

float is_key(vec3 c, vec3 k) {
	vec3 d = abs(c - k);
	return step(max(d.r, max(d.g, d.b)), 0.012);
}

void vertex() {
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
	vec3 base = COLOR.rgb;
	ALBEDO = base;
	ROUGHNESS = mix(0.72, 0.3, glow);
	EMISSION = base * glow * 2.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += rim_color * rim * rim_strength * (1.0 - glow);
}
