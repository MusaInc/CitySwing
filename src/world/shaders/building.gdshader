// Facade shader for all procedural buildings. Geometry is plain massing; this
// draws windows, mullions, floor bands, shopfronts and roof gravel from
// world-metre UVs, so detail costs no vertices (mobile-friendly).
//   COLOR.rgb  base tint            COLOR.a  surface kind (see KIND_*)
//   UV         (metres along wall, metres above street)
//   UV2        (window style 0..7, per-building random 0..1)
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 sky_top : source_color = vec3(0.36, 0.55, 0.82);
uniform vec3 sky_horizon : source_color = vec3(0.95, 0.82, 0.68);
uniform vec3 interior_warm : source_color = vec3(1.0, 0.78, 0.48);
uniform float lit_fraction = 0.05;
uniform float lit_strength = 0.35;
uniform float detail_fade_start = 250.0;
uniform float detail_fade_end = 700.0;

const float KIND_WALL = 0.0;
const float KIND_TRIM = 1.0;
const float KIND_ROOF = 2.0;
const float KIND_GLASS = 3.0;

varying float v_kind;
varying vec3 v_world_normal;
varying float v_dist;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_kind = floor(COLOR.a * 8.0 + 0.5);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

// Returns window mask (1 = glass) and cell id, for a style.
// style: 0 stone office, 1 brick flats, 2 glass curtain, 3 warehouse,
//        4 modern grid, 5 sandstone, 6 dark glass, 7 deco bands
void window_layout(float style, vec2 uv, out float glass, out vec2 cell, out float frame) {
	vec2 size = vec2(3.0, 3.6);
	vec2 win = vec2(0.55, 0.6);
	if (style == 1.0) { size = vec2(3.2, 3.0); win = vec2(0.42, 0.55); }
	else if (style == 2.0) { size = vec2(1.6, 3.8); win = vec2(0.92, 0.78); }
	else if (style == 3.0) { size = vec2(4.0, 4.4); win = vec2(0.42, 0.5); }
	else if (style == 4.0) { size = vec2(2.6, 3.6); win = vec2(0.7, 0.62); }
	else if (style == 5.0) { size = vec2(3.6, 4.2); win = vec2(0.4, 0.56); }
	else if (style == 6.0) { size = vec2(1.5, 3.7); win = vec2(0.94, 0.9); }
	else if (style == 7.0) { size = vec2(2.2, 3.6); win = vec2(0.5, 0.7); }
	cell = floor(uv / size);
	vec2 f = fract(uv / size) - 0.5;
	vec2 edge = abs(f) - win * 0.5;
	float aa = fwidth(uv.x / size.x) * 1.5 + 0.001;
	glass = 1.0 - smoothstep(-aa, aa, max(edge.x, edge.y));
	frame = 1.0 - smoothstep(-aa * 2.0, aa, max(edge.x, edge.y) + 0.04);
}

void fragment() {
	vec3 base = COLOR.rgb;
	float style = floor(UV2.x + 0.5);
	float seed = UV2.y;
	vec2 uv = UV;
	float rough = 0.85;
	float metal = 0.0;
	vec3 albedo = base;
	vec3 emit = vec3(0.0);
	float detail = 1.0 - smoothstep(detail_fade_start, detail_fade_end, v_dist);

	if (v_kind == KIND_ROOF) {
		// Roof membrane panels, softly varied (no per-pixel noise: it shimmers).
		float n = hash12(floor(uv / 4.0) + seed * 91.0);
		vec2 pf = abs(fract(uv / 4.0) - 0.5);
		float seam = step(0.47, max(pf.x, pf.y)) * detail;
		albedo = base * (0.9 + 0.1 * n) * (1.0 - 0.15 * seam);
		rough = 0.95;
	} else if (v_kind == KIND_TRIM) {
		albedo = base;
		rough = 0.7;
	} else {
		float glass;
		vec2 cell;
		float frame;
		window_layout(style, uv, glass, cell, frame);
		// Ground floor: tall shopfront glazing + fascia band.
		bool shop = uv.y < 4.6 && style != 3.0;
		if (shop) {
			float bay = fract(uv.x / 6.0);
			glass = step(0.08, bay) * step(bay, 0.92) * step(0.25, uv.y) * step(uv.y, 3.6);
			cell = vec2(floor(uv.x / 6.0), -1.0);
		}
		if (v_kind == KIND_GLASS || style == 2.0 || style == 6.0) {
			// Curtain wall: mostly glass with spandrel bands and mullions.
			float spandrel = step(fract(uv.y / (style == 6.0 ? 3.7 : 3.8)), 0.16);
			glass = shop ? glass : (1.0 - spandrel) * glass;
		}
		// Brick courses / stone joints at close range only.
		float tex = 1.0;
		if (style == 1.0 || style == 3.0) {
			vec2 b = uv * vec2(4.2, 13.0);
			b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
			vec2 bf = fract(b);
			float mortar = step(bf.x, 0.06) + step(bf.y, 0.1);
			tex = mix(1.0, 0.82 + 0.18 * hash12(floor(b) + seed), detail) * mix(1.0, 1.0 - 0.18 * clamp(mortar, 0.0, 1.0), detail);
		} else if (style == 5.0 || style == 0.0 || style == 7.0) {
			float course = step(fract(uv.y / 0.6), 0.04) * detail;
			tex = 1.0 - 0.08 * course;
		}
		// Floor bands for deco/stone styles.
		if (style == 7.0 || style == 0.0) {
			float band = step(fract(uv.y / 3.6), 0.09);
			tex *= 1.0 - 0.12 * band;
		}
		vec3 wall = base * tex;

		// Glass: sky reflection by view-reflected normal + interior + rare lit rooms.
		vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 r = reflect(-view_w, normalize(v_world_normal));
		float fres = pow(1.0 - clamp(dot(view_w, normalize(v_world_normal)), 0.0, 1.0), 3.0);
		vec3 refl = mix(sky_horizon, sky_top, clamp(r.y * 1.6, 0.0, 1.0));
		float rnd = hash12(cell + seed * 113.0);
		vec3 tint = style == 6.0 ? vec3(0.12, 0.16, 0.2) : (style == 2.0 ? vec3(0.2, 0.32, 0.38) : vec3(0.1, 0.11, 0.12));
		vec3 interior = tint * (0.6 + 0.6 * rnd);
		float lit = step(1.0 - lit_fraction, hash12(cell * 1.31 + seed * 7.0)) * (shop ? 1.0 : 0.7);
		vec3 gcol = mix(interior, refl, 0.25 + 0.6 * fres);
		gcol += interior_warm * lit * lit_strength * 0.35;
		emit = interior_warm * lit * lit_strength * glass * 0.5;
		// Window reveal: slightly darker frame around each opening.
		vec3 framed = mix(wall, wall * 0.72, (1.0 - glass) * frame * detail);
		albedo = mix(framed, gcol, glass);
		rough = mix(0.88, 0.08, glass);
		metal = mix(0.0, 0.2, glass);
		if (shop) {
			float fascia = step(3.7, uv.y) * step(uv.y, 4.5);
			albedo = mix(albedo, base * 0.45, fascia);
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = emit;
}
