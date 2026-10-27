// Streets, pavements, lawns. COLOR.rgb tint; UV = world XZ metres.
shader_type spatial;
render_mode cull_back, diffuse_burley;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float n = vnoise(UV * 0.35) * 0.6 + vnoise(UV * 2.1) * 0.4;
	float slabs = 1.0;
	if (c.r > 0.5 && c.g > 0.5) {
		// Pavement flagstones.
		vec2 f = fract(UV / 1.8);
		slabs = 1.0 - 0.1 * (step(f.x, 0.03) + step(f.y, 0.03));
	}
	ALBEDO = c * (0.88 + 0.2 * n) * slabs;
	ROUGHNESS = 0.92;
}
