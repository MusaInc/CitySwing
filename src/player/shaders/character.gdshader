// Character: one vertex-coloured surface per body part (baked by the Blender
// kit). COLOR.a == 0 marks emissive gear (spool rings, gauntlet LED, goggles).
// A soft rim light keeps the silhouette readable against busy facades.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec3 rim_color : source_color = vec3(1.0, 0.88, 0.72);
uniform float rim_strength = 0.35;
// Suit colour (same space as the baked vertex colours). The jacket's reds are
// recoloured by brightness relative to the main jacket red (0.796).
uniform vec3 suit_color = vec3(0.796, 0.098, 0.09);

void fragment() {
	float glow = 1.0 - COLOR.a;
	vec3 base = COLOR.rgb;
	float red = step(0.3, base.r) * step(max(base.g, base.b), base.r * 0.2) * COLOR.a;
	base = mix(base, suit_color * (base.r / 0.796), red);
	ALBEDO = base;
	ROUGHNESS = mix(0.72, 0.3, glow);
	EMISSION = base * glow * 2.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += rim_color * rim * rim_strength * (1.0 - glow);
}
