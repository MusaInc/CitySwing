shader_type spatial;
render_mode diffuse_burley;
// Home floors, one plane per room (UV 0..1 over the room, room_size in m).
// style: 0 timber boards  1 polished concrete  2 marble tiles
//        3 herringbone parquet  4 dark honed stone (large format)
uniform vec3 timber : source_color = vec3(0.35, 0.23, 0.14);
uniform vec2 room_size = vec2(10.0);
uniform int style = 0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.3) * 0.3 + vnoise(p * 5.1) * 0.15; }

void fragment() {
	vec2 p = UV * room_size;
	vec3 c = timber;
	float rough = 0.73;
	float spec = 0.22;
	if (style == 0) {
		float board = floor(p.x / 0.22);
		float across = fract(p.x / 0.22);
		float along = fract((p.y + mod(board, 3.0) * 0.67) / 2.0);
		float grain = sin(p.y * 55.0 + sin(p.x * 18.0) * 3.0) * 0.025;
		float variation = fract(sin(board * 31.7) * 1763.3) * 0.12;
		float seam = (1.0 - smoothstep(0.005, 0.02, across)) + (1.0 - smoothstep(0.001, 0.004, along));
		c = timber * (0.94 + variation + grain - min(seam, 1.0) * 0.22);
	} else if (style == 1) {
		// Trowelled concrete: cloudy, a few saw cuts, low sheen.
		float cl = fbm(p * 0.6) * 0.16 + fbm(p * 3.0) * 0.05;
		vec2 g = fract(p / 3.6);
		float cut = 1.0 - smoothstep(0.0, 0.004, min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)));
		c = timber * (0.9 + cl) * (1.0 - cut * 0.35);
		rough = 0.42 - cl * 0.3;
		spec = 0.4;
	} else if (style == 2 || style == 4) {
		// Large tiles (1.2 m marble or 1.5 m honed stone) with veining.
		float s = style == 2 ? 1.2 : 1.5;
		vec2 t = floor(p / s);
		vec2 g = fract(p / s);
		float joint = 1.0 - smoothstep(0.0, 0.006, min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)));
		vec2 q = p + vec2(h21(t) * 9.0, h21(t + 3.1) * 9.0);
		// Long, gently wandering veins (one or two per tile), not squiggles.
		float vein = abs(sin((q.x * 0.9 + q.y * 0.5) * 0.8 + fbm(q * 0.25) * 1.3));
		vein = 1.0 - smoothstep(0.0, style == 2 ? 0.05 : 0.025, vein);
		float tone = (h21(t) - 0.5) * 0.06;
		vec3 vein_c = style == 2 ? vec3(0.55, 0.55, 0.57) : vec3(0.85, 0.78, 0.62);
		c = mix(timber * (1.0 + tone + fbm(q * 2.0) * 0.06), vein_c, vein * (style == 2 ? 0.3 : 0.12));
		c *= 1.0 - joint * 0.3;
		rough = style == 2 ? 0.16 : 0.22;
		spec = 0.55;
	} else {
		// Chevron parquet: 0.6 m rows of 0.12 m blocks skewed alternately.
		float row = floor(p.y / 0.6);
		float dir = mod(row, 2.0) * 2.0 - 1.0;
		float sx = p.x + p.y * dir;
		float col = floor(sx / 0.12);
		vec2 f = vec2(fract(sx / 0.12), fract(p.y / 0.6));
		float seam = 1.0 - smoothstep(0.03, 0.12, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y) * 5.0));
		float grain = sin(p.y * 60.0 + sx * 6.0 + vnoise(p * 8.0) * 4.0) * 0.03;
		c = timber * (0.9 + h21(vec2(col, row)) * 0.18 + grain - seam * 0.25);
		rough = 0.55;
		spec = 0.3;
	}
	// Fine joints alias at grazing angles: fade them to the mean tone.
	float fw = max(fwidth(p.x), fwidth(p.y)) / 0.12;
	c = mix(c, timber * 0.95, smoothstep(0.35, 0.9, fw) * (style == 0 || style == 3 ? 1.0 : 0.0));
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
