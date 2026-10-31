// Facade shader for all procedural buildings. Geometry is plain massing; this
// draws windows, mullions, floor bands, shopfronts and roof gravel from
// world-metre UVs, so detail costs no vertices (mobile-friendly).
//   COLOR.rgb  base tint            COLOR.a  surface kind (see KIND_*)
//   UV         (metres along wall, metres above street)
//   UV2        x: window style 0..7 (+0..1 across a wall face)
//              y: per-building random 0..1 (+ face width in ¼ m steps)
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Sky colours (linear) and the sun, set by Atmosphere every frame as the day
// turns; `night` 0..1 lights the windows, `wetness` 0..1 darkens and glosses.
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
global uniform float night;
global uniform float wetness;
uniform vec3 interior_warm : source_color = vec3(1.0, 0.78, 0.48);
uniform float lit_fraction = 0.025;
uniform float lit_strength = 0.35;
uniform float detail_fade_start = 250.0;
uniform float detail_fade_end = 700.0;

const float KIND_WALL = 0.0;
const float KIND_TRIM = 1.0;
const float KIND_ROOF = 2.0;
const float KIND_GLASS = 3.0;
const float KIND_SIGN = 4.0;

varying flat float v_kind;
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
void window_layout(float style, vec2 uv, out float glass, out vec2 cell, out float frame, out vec2 wpos,
		out vec2 whalf) {
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
	wpos = f * size;
	whalf = win * size * 0.5;
	frame = 1.0 - smoothstep(-aa * 2.0, aa, max(edge.x, edge.y) + 0.04);
}

void fragment() {
	vec3 base = COLOR.rgb;
	float style = floor(UV2.x);
	float face_t = fract(UV2.x) / 0.999;
	float face_w = floor(UV2.y) * 0.25;
	// Wall faces pack the seed beside their width (see BuildingMesher
	// _face_span); interpolation adds noise in the low bits, so snap it.
	float seed = face_w > 0.0 ? floor(fract(UV2.y) * 256.0) / 256.0 : UV2.y;
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
		// Weathering: broad soft patches (puddle stains, newer membrane) from
		// a smoothed 9 m lattice, and a paver walkway on some roofs.
		vec2 g = uv / 9.0 + seed * 17.0;
		vec2 gi = floor(g);
		vec2 gf = smoothstep(0.0, 1.0, fract(g));
		float blot = mix(mix(hash12(gi), hash12(gi + vec2(1, 0)), gf.x),
			mix(hash12(gi + vec2(0, 1)), hash12(gi + vec2(1, 1)), gf.x), gf.y);
		albedo *= mix(0.84, 1.08, blot);
		if (fract(seed * 13.7) < 0.45) {
			float lane = abs(fract(uv.x / 23.0 + seed) - 0.5) * 23.0;
			vec2 pv = abs(fract(uv / vec2(1.0, 1.0)) - 0.5);
			albedo = mix(albedo, vec3(0.62, 0.6, 0.56) * (1.0 - 0.25 * step(0.44, max(pv.x, pv.y))), step(lane, 0.8) * detail);
		}
		rough = 0.95;
	} else if (v_kind == KIND_TRIM) {
		albedo = base;
		rough = 0.7;
	} else if (v_kind == KIND_SIGN) {
		// Billboard: UV.y is metres up the panel. Frame, a bold headline bar
		// broken into "words", a thinner strapline and a contrasting stripe.
		float h = uv.y;
		vec3 ink = dot(base, vec3(0.33)) > 0.6 ? vec3(0.08, 0.1, 0.14) : vec3(0.97, 0.95, 0.9);
		float word = step(0.25, hash12(vec2(floor(uv.x / 1.7), seed * 37.0)));
		float gap = step(0.18, fract(uv.x / 1.7));
		float headline = step(2.6, h) * step(h, 4.1) * word * gap;
		float strap = step(1.3, h) * step(h, 1.8) * step(0.4, hash12(vec2(floor(uv.x / 0.9), seed * 53.0)));
		float frame = 1.0 - step(0.35, h) * step(h, 6.9 + seed * 0.0);
		float stripe = step(0.35, h) * step(h, 0.9);
		albedo = mix(base, ink, max(headline, strap) * detail);
		albedo = mix(albedo, base * 0.35, stripe);
		albedo = mix(albedo, vec3(0.16), clamp(frame, 0.0, 1.0) * 0.0);
		emit = base * mix(0.18, 1.2, night);  // billboards are floodlit at night
		rough = 0.55;
	} else {
		float glass;
		vec2 cell;
		float frame;
		vec2 wpos;
		vec2 whalf;
		window_layout(style, uv, glass, cell, frame, wpos, whalf);
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
		// Weathering: faint rain streaks under each window column on masonry.
		if (style != 2.0 && style != 6.0 && v_kind != KIND_GLASS) {
			float col_n = hash12(vec2(floor(uv.x / 1.5), seed * 29.0));
			tex *= 1.0 - 0.07 * col_n * detail * smoothstep(0.0, 1.0, fract(uv.y / 14.4));
		}
		vec3 wall = base * tex;

		// Glass: sky reflection by view-reflected normal + interior + rare lit rooms.
		vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 r = reflect(-view_w, normalize(v_world_normal));
		float fres = pow(1.0 - clamp(dot(view_w, normalize(v_world_normal)), 0.0, 1.0), 3.0);
		vec3 refl = mix(sky_horizon, sky_top, clamp(r.y * 1.6, 0.0, 1.0));
		float rnd = hash12(cell + seed * 113.0);
		vec3 tint = style == 6.0 ? vec3(0.12, 0.16, 0.2) : (style == 2.0 ? vec3(0.2, 0.32, 0.38) : vec3(0.1, 0.11, 0.12));
		// Curtain-wall towers pick a glass colour per building (teal, bronze,
		// green, blue) so the skyline isn't one sky-blue mass; reflections are
		// seen through that tint like real coated glass.
		float pick = fract(seed * 7.31);
		// (Blue-sky reflections made every tower read the same blue: the
		// coating colour now dominates, with warm champagne/bronze/silver
		// towers among the teal, green and blue.)
		if (style == 2.0) {
			tint = pick < 0.18 ? vec3(0.16, 0.34, 0.36) : (pick < 0.36 ? vec3(0.42, 0.28, 0.15)
				: (pick < 0.5 ? vec3(0.17, 0.33, 0.24) : (pick < 0.64 ? vec3(0.18, 0.27, 0.42)
				: (pick < 0.82 ? vec3(0.46, 0.42, 0.34) : vec3(0.36, 0.38, 0.4)))));
		} else if (style == 6.0) {
			tint = pick < 0.4 ? vec3(0.1, 0.14, 0.2) : (pick < 0.75 ? vec3(0.22, 0.15, 0.09) : vec3(0.13, 0.13, 0.12));
		}
		if (style == 2.0 || style == 6.0) {
			float lum = dot(refl, vec3(0.3, 0.55, 0.15));
			refl = mix(refl, clamp(tint * 2.4, 0.0, 1.3) * lum * 1.6, 0.75);
		}
		vec3 interior = tint * (0.75 + 0.35 * rnd);
		// Blinds half-drawn in some windows (offices and flats, not shops).
		float blind_h = step(0.86, hash12(cell * 2.7 + seed * 17.0)) * (shop ? 0.0 : 1.0);
		float in_blind = blind_h * step(1.0 - hash12(cell + 5.1) * 0.6, fract(uv.y / (style == 1.0 ? 3.0 : 3.6)) + 0.3);
		// Lit rooms: a few by day; after dusk they come on one by one (each
		// window has its own threshold) up to a per-building share, in warm
		// tungsten, cool office white or the odd blue TV glow.
		float lit_share = mix(lit_fraction, 0.08 + 0.2 * fract(seed * 3.7), night);
		float lit = step(1.0 - lit_share, hash12(cell * 1.31 + seed * 7.0)) * (shop ? 1.0 : 0.7);
		float lk = hash12(cell * 3.17 + seed * 11.0);
		vec3 lamp_col = lk < 0.55 ? interior_warm : (lk < 0.88 ? vec3(0.86, 0.9, 1.0) : vec3(0.5, 0.66, 1.0));
		lamp_col = mix(interior_warm, lamp_col, night);
		float lit_k = mix(lit_strength, 1.3, night) * (0.45 + 0.75 * hash12(cell * 0.71 + seed));
		vec3 gcol = mix(interior, refl, 0.25 + 0.6 * fres);
		// Blinds: a paler band in the glass's own colour, not a beige patch.
		gcol = mix(gcol, mix(gcol, vec3(0.78, 0.76, 0.72), 0.45) * (0.85 + 0.15 * rnd), in_blind * 0.8 * detail);
		gcol += lamp_col * lit * lit_k * 0.35 * (1.0 - night * 0.6);
		emit = lamp_col * lit * lit_k * glass * 0.5;
		// Window reveal: slightly darker frame around each opening.
		vec3 framed = mix(wall, wall * 0.72, (1.0 - glass) * frame * detail);
		bool punched = !shop && style != 2.0 && style != 6.0 && v_kind != KIND_GLASS;
		if (punched && detail > 0.0) {
			// Stone sill under each window and (brick) a lintel over it.
			vec3 stone = (style == 1.0 || style == 3.0) ? vec3(0.8, 0.76, 0.68) : base * 1.16;
			float in_x = step(abs(wpos.x), whalf.x + 0.12);
			float sill = in_x * step(-whalf.y - 0.16, wpos.y) * step(wpos.y, -whalf.y);
			float lintel = in_x * step(whalf.y, wpos.y) * step(wpos.y, whalf.y + 0.22)
				* ((style == 1.0 || style == 3.0) ? 1.0 : 0.0);
			framed = mix(framed, stone, max(sill, lintel) * detail);
			framed = mix(framed, stone * 0.55, in_x * step(-whalf.y - 0.22, wpos.y) * step(wpos.y, -whalf.y - 0.16)
				* detail * 0.6);
		}
		// Recessed glazing: the reveal casts a sun shadow across the top and
		// the sun-side edge of the glass (a deep punched window on masonry,
		// a shallow one on curtain walls), and the frame inside darkens.
		vec3 n_w = normalize(v_world_normal);
		vec3 tang = normalize(cross(vec3(0.0, 1.0, 0.0), n_w));
		float lit_face = dot(n_w, sun_dir);
		float depth = punched ? 0.26 : 0.07;
		float reveal = 0.0;
		if (!shop) {
			if (lit_face > 0.04) {
				float top_sh = clamp(depth * max(sun_dir.y, 0.0) / lit_face, 0.0, whalf.y * 1.2);
				float lt = dot(sun_dir, tang);
				float side_sh = clamp(depth * abs(lt) / lit_face, 0.0, whalf.x * 1.2);
				float side_edge = lt > 0.0 ? wpos.x - (whalf.x - side_sh) : -(whalf.x - side_sh) - wpos.x;
				reveal = max(step(whalf.y - top_sh, wpos.y), step(0.0, side_edge));
			}
			float rim = 1.0 - smoothstep(0.0, 0.07, min(whalf.x - abs(wpos.x), whalf.y - abs(wpos.y)));
			reveal = max(reveal * 0.85, rim * 0.6);
		}
		gcol *= 1.0 - reveal * 0.55 * detail;
		albedo = mix(framed, gcol, glass);
		rough = mix(0.88, 0.08, glass);
		metal = mix(0.0, 0.2, glass);
		if (shop) {
			// Shopfront: stall riser, central door, mullions, lit interior and
			// a signage fascia coloured per shop.
			float bay_x = fract(uv.x / 6.0) * 6.0;
			float sid = hash12(vec2(floor(uv.x / 6.0), seed * 41.0));
			vec3 sign_col = sid < 0.2 ? vec3(0.62, 0.14, 0.12) : (sid < 0.4 ? vec3(0.12, 0.3, 0.26)
				: (sid < 0.6 ? vec3(0.13, 0.18, 0.34) : (sid < 0.75 ? vec3(0.8, 0.6, 0.2) : base * 0.42)));
			float riser = step(uv.y, 0.6) * glass;
			float door = step(abs(bay_x - 3.0), 0.55) * step(uv.y, 2.5) * step(0.25, uv.y);
			float mull = step(abs(abs(bay_x - 3.0) - 1.75), 0.05) * step(uv.y, 3.6);
			float transom = step(abs(uv.y - 2.65), 0.05);
			vec3 shop_in = mix(vec3(0.05, 0.05, 0.06), interior_warm * 0.5, 0.2 + 0.35 * sid);
			albedo = mix(albedo, mix(shop_in, refl, 0.22 + 0.5 * fres), glass * (1.0 - riser));
			albedo = mix(albedo, base * 0.5, max(riser, max(mull, transom) * glass) * detail);
			albedo = mix(albedo, vec3(0.08, 0.07, 0.07), door * 0.85 * detail);
			emit += interior_warm * glass * (1.0 - door) * (1.0 - riser) * mix(0.07, 0.3, night) * (0.5 + sid) * mix(detail, 1.0, night);
			float fascia = step(3.7, uv.y) * step(uv.y, 4.5);
			albedo = mix(albedo, sign_col, fascia);
			// Lettering blocks on the fascia.
			float letters = step(0.35, hash12(vec2(floor(uv.x / 0.45), sid * 77.0))) * step(abs(bay_x - 3.0), 1.9)
				* step(abs(uv.y - 4.1), 0.16);
			albedo = mix(albedo, vec3(0.95, 0.92, 0.84), letters * fascia * detail * step(0.25, sid));
		}
		// Corners: dressed stone quoins on masonry (alternating long/short
		// blocks), and on every face a fine shaded arris so box edges read
		// crisply up close instead of melting into the next face.
		if (face_w > 0.0) {
			float dc = min(face_t, 1.0 - face_t) * face_w;
			bool masonry = style == 0.0 || style == 1.0 || style == 3.0 || style == 5.0 || style == 7.0;
			if (masonry && v_kind == KIND_WALL && !shop) {
				float course = floor(uv.y / 0.62);
				float qw = mod(course, 2.0) < 0.5 ? 0.95 : 0.55;
				float joint = step(fract(uv.y / 0.62), 0.07);
				vec3 qcol = (style == 1.0 || style == 3.0) ? vec3(0.84, 0.8, 0.72) : base * 1.18;
				float q = step(dc, qw) * detail;
				albedo = mix(albedo, qcol * (1.0 - 0.25 * joint), q);
			}
			float arris = 1.0 - smoothstep(0.0, fwidth(dc) * 1.5 + 0.02, dc);
			albedo *= 1.0 - 0.32 * arris * detail;
		}
		// Contact shading: walls darken toward the street (light blocked by
		// the canyon), so buildings sit on the ground instead of floating;
		// and a long gradient up the facade (tops catch more sky).
		albedo *= mix(vec3(0.5, 0.54, 0.62), vec3(1.0), smoothstep(0.0, 12.0, uv.y));
		albedo *= mix(0.86, 1.04, smoothstep(6.0, 80.0, uv.y));
	}
	// Rain: surfaces darken and gloss (glass is already glossy).
	ALBEDO = albedo * (1.0 - 0.16 * wetness);
	ROUGHNESS = mix(rough, min(rough, 0.32), wetness * 0.75);
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = emit;
}
