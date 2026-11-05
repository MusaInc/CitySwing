shader_type spatial;
render_mode diffuse_burley;
// Feature walls in the homes (a quad laid just off a wall; UV over the quad,
// size in metres). style: 0 exposed brick  1 walnut slats  2 book-matched
// marble  3 board-formed concrete  4 fabric/acoustic panels  5 plaster
// 6 a painting (abstract, from `tint`, `seed`)  7 wall panelling (wainscot)
// All but paintings shade into their corners (floor, ceiling, side walls).
uniform vec3 tint : source_color = vec3(0.55, 0.3, 0.22);
uniform vec2 size = vec2(6.0, 3.0);
uniform int style = 0;
uniform float seed = 0.0;
uniform float corners = 1.0;  // 0 for pieces hung on a wall (paintings)

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y) * size;
	vec3 c = tint;
	float rough = 0.85;
	vec3 nrm_bump = vec3(0.0);
	if (style == 0) {
		vec2 b = p / vec2(0.215, 0.075);
		b.x += mod(floor(b.y), 2.0) * 0.5;
		vec2 id = floor(b);
		vec2 f = fract(b);
		float mortar = 1.0 - smoothstep(0.03, 0.09, min(min(f.x, 1.0 - f.x) * 2.87, min(f.y, 1.0 - f.y)));
		float tone = h21(id) * 0.28 - 0.1;
		float burnt = step(0.86, h21(id + 7.0)) * 0.25;
		vec3 brick = tint * (1.0 + tone - burnt) * (0.92 + vnoise(p * 30.0) * 0.12);
		c = mix(brick, vec3(0.62, 0.6, 0.56), mortar);
		// Far away the courses alias into swirls: fade to the wall's average.
		float fw = fwidth(b.y);
		c = mix(c, mix(tint, vec3(0.62, 0.6, 0.56), 0.22), smoothstep(0.08, 0.3, fw));
		rough = 0.92;
	} else if (style == 1) {
		float s = fract(p.x / 0.06);
		float gap = 1.0 - smoothstep(0.0, 0.18, min(s, 1.0 - s));
		float id = floor(p.x / 0.06);
		float grain = sin(p.y * 40.0 + vnoise(vec2(id, p.y * 3.0)) * 5.0) * 0.04;
		c = tint * (0.92 + h21(vec2(id, 2.0)) * 0.14 + grain) * (1.0 - gap * 0.75);
		c = mix(c, tint * 0.82, smoothstep(0.1, 0.35, fwidth(p.x / 0.06)));
		rough = 0.6;
	} else if (style == 2) {
		vec2 q = vec2(abs(p.x - size.x * 0.5), p.y);  // book-matched about the centre
		float v = abs(sin(q.x * 1.3 + q.y * 0.7 + vnoise(q * 1.2) * 5.0 + vnoise(q * 4.0) * 1.2));
		float vein = 1.0 - smoothstep(0.0, 0.06, v);
		c = mix(tint * (0.96 + vnoise(q * 2.0) * 0.06), vec3(0.42, 0.4, 0.4), vein * 0.5);
		rough = 0.18;
	} else if (style == 3) {
		float board = floor(p.y / 0.15);
		float seam = 1.0 - smoothstep(0.0, 0.02, abs(fract(p.y / 0.15) - 0.5) - 0.47);
		float tie = 1.0 - smoothstep(0.015, 0.03, length(fract(p / vec2(0.6, 0.45)) - 0.5));
		c = tint * (0.9 + h21(vec2(board, 5.0)) * 0.1 + vnoise(p * vec2(1.0, 6.0)) * 0.08) * (1.0 - seam * 0.2 - tie * 0.35);
		rough = 0.9;
	} else if (style == 5) {
		float m = vnoise(p * 0.7 + seed) * 0.6 + vnoise(p * 2.3) * 0.3 + vnoise(p * 9.0) * 0.1;
		c = tint * (0.93 + m * 0.1);
		rough = 0.92;
	} else if (style == 6) {
		vec2 q = UV;
		vec3 a = tint;
		vec3 b = vec3(1.0) - tint * 0.8;
		vec3 d = mix(tint.brg, vec3(0.95, 0.92, 0.85), 0.4);
		float n1 = vnoise(q * vec2(2.2, 3.1) + seed * 3.1);
		float n2 = vnoise(q * vec2(4.5, 2.0) - seed * 1.7);
		float field = smoothstep(0.35, 0.65, n1 + (q.y - 0.5) * 0.6);
		c = mix(a, b, field);
		float band = smoothstep(0.02, 0.0, abs(n2 - 0.5) - 0.06);
		c = mix(c, d, band * 0.85);
		float stroke = sin(q.x * 90.0 + vnoise(q * 8.0) * 6.0) * 0.03;
		c *= 0.92 + stroke + vnoise(q * 40.0) * 0.06;
		rough = 0.7;
	} else if (style == 7) {
		float rail = 1.0 - smoothstep(0.0, 0.025, abs(p.y - 1.0) - 0.02);
		vec2 g = vec2(fract(p.x / 0.9), p.y);
		float stile = 1.0 - smoothstep(0.0, 0.02, min(g.x, 1.0 - g.x) * 0.9 - 0.04);
		float low = step(p.y, 1.0);
		float bev = (1.0 - smoothstep(0.0, 0.03, abs(g.x - 0.08))) + (1.0 - smoothstep(0.0, 0.03, abs(g.x - 0.92)));
		c = tint * (0.95 + vnoise(p * 3.0 + seed) * 0.05);
		c *= 1.0 - (stile * 0.12 + bev * 0.08) * low - rail * 0.15;
		c *= 1.0 + rail * 0.0;
		rough = 0.8;
	} else {
		vec2 g = fract(p / vec2(0.6, 0.6));
		float edge = 1.0 - smoothstep(0.0, 0.03, min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)));
		c = tint * (0.95 + vnoise(p * 40.0) * 0.08) * (1.0 - edge * 0.35);
		rough = 1.0;
	}
	if (corners > 0.5) {
		// Ambient occlusion into the room's corners and along floor/ceiling.
		float ao = mix(0.72, 1.0, smoothstep(0.0, 0.55, p.y));
		ao *= mix(0.84, 1.0, smoothstep(0.0, 0.6, size.y - p.y));
		ao *= mix(0.8, 1.0, smoothstep(0.0, 0.7, min(p.x, size.x - p.x)));
		c *= ao;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
