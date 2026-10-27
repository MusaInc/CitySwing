// Character: one vertex-coloured surface per body part (baked by the Blender
// kit). COLOR.a == 0 marks emissive gear (spool rings, gauntlet LED, goggles).
// A soft rim light keeps the silhouette readable against busy facades.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec3 rim_color : source_color = vec3(1.0, 0.88, 0.72);
uniform float rim_strength = 0.35;

void fragment() {
	float glow = 1.0 - COLOR.a;
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(0.72, 0.3, glow);
	EMISSION = COLOR.rgb * glow * 2.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += rim_color * rim * rim_strength * (1.0 - glow);
}
