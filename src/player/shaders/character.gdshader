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
const vec3 K_MASK = vec3(0.141, 0.141, 0.149);

// Cloth (secondary motion, CharacterRig._update_cloth): UV2.x is how freely
// a vertex moves (0 = held by the body … 1 = the hoodie's hem, the hood's
// peak, the cord ends). The rig integrates one damped spring per character
// for the fabric's lag against the air (wind − velocity), inertia and
// gravity, and passes it in world space; the shader offsets free vertices by
// it, never inward through the body (the inward part is flattened, as fabric
// pressed against the torso), and adds a travelling flutter at speed.
uniform vec3 cloth_drag = vec3(0.0);      // world metres at weight 1
uniform float cloth_flutter = 0.0;         // 0..1
uniform float cloth_time = 0.0;
uniform vec3 cloth_wind_dir = vec3(0.0, 0.0, 1.0);  // world, where the air comes from → goes

// Baked ambient occlusion (build_character.py bake_ao): UV = (ao, 1) on the
// meshes that carry it; anything else (UV.y = 0) stays unshaded.
varying float v_ao;
varying vec2 v_fab;     // fabric coords (m)
varying float v_cloth;  // 1 = knit fabric (hoodie, joggers, mask), 0 = trainers, gloves, gear

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float is_key(vec3 c, vec3 k) {
	vec3 d = abs(c - k);
	return step(max(d.r, max(d.g, d.b)), 0.012);
}

void vertex() {
	// UV2 = (0.5 + 0.5 ao, cloth weight); < 0.25 = no data (shop gear).
	bool has_data = UV2.x > 0.25;
	v_ao = has_data ? clamp(UV2.x * 2.0 - 1.0, 0.0, 1.0) : 1.0;
	float cw = has_data ? UV2.y : 0.0;
	v_fab = UV;
	if (cw > 0.001) {
		mat3 to_world = mat3(MODEL_MATRIX);
		vec3 n_w = normalize(to_world * NORMAL);
		vec3 p_w = to_world * VERTEX;
		vec3 off = cloth_drag * cw;
		// Fabric can't go into the body: flatten the inward part.
		float inward = dot(off, n_w);
		off -= n_w * min(inward, 0.0) * 0.92;
		// Flutter: ripples travelling along the hem with the airflow,
		// mostly outward (cloth billows, it doesn't fold into the body).
		float ph = dot(p_w, cloth_wind_dir) * 14.0 + dot(p_w, vec3(0.7, 0.0, -0.7)) * 9.0;
		float rip = sin(cloth_time * 17.0 - ph) * 0.6 + sin(cloth_time * 29.0 - ph * 1.7 + 1.3) * 0.4;
		off += n_w * (0.35 + 0.65 * rip) * cloth_flutter * cw * 0.016;
		off += cloth_wind_dir * rip * cloth_flutter * cw * 0.01;
		VERTEX += inverse(to_world) * off;
	}
	vec3 c = COLOR.rgb;
	vec3 o = c;
	v_cloth = max(max(is_key(c, K_JACKET), is_key(c, K_JACKET_DK)), max(is_key(c, K_PANTS), is_key(c, K_PANTS_DK)));
	v_cloth = max(v_cloth, is_key(c, K_MASK) * 0.6);
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
	float cloth = v_cloth;
	if (cloth > 0.0) {
		// Knit: fine ribs running up the garment, a heathered yarn mottle,
		// and broad soft tonal variation (dye, wear) – fabric, not plastic.
		// Faded out where a rib would be smaller than a pixel.
		float px = length(fwidth(v_fab));
		float near_k = 1.0 - smoothstep(0.004, 0.012, px);
		float rib = 0.5 + 0.5 * sin(v_fab.x * 6.2832 * 85.0);
		float yarn = vnoise(v_fab * vec2(220.0, 90.0));
		float tone = vnoise(v_fab * 6.0);
		float k = cloth * near_k;
		ALBEDO *= 1.0 - 0.09 * k * rib - 0.07 * k * yarn;
		ALBEDO *= mix(1.0, 0.9 + 0.2 * tone, cloth);
		// Wrinkle shading in the creases (AO-driven), stronger than skin-tight.
		ALBEDO *= mix(1.0, 0.82 + 0.18 * ao, cloth);
	}
	// Cotton is matte with a soft, wide sheen at grazing angles (velvet-like
	// rim from the fibres); trainers and gloves are a little glossier.
	ROUGHNESS = mix(mix(mix(0.55, 0.36, wetness), 0.92, cloth), 0.3, glow);
	SPECULAR = mix(0.5, 0.25, cloth);
	EMISSION = COLOR.rgb * glow * 2.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 n_w = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float sun_side = clamp(dot(n_w, sun_dir) * 0.5 + 0.5, 0.0, 1.0);
	// Fabric sheen: the garment's own colour brightening at the silhouette.
	ALBEDO += base * rim * 0.22 * cloth * ao;
	// A faint cool/warm edge keeps the silhouette readable against facades
	// (much softer than before: it read as a glowing plastic outline).
	vec3 rim_c = mix(vec3(0.55, 0.75, 1.0), mix(rim_color, vec3(0.6, 0.7, 1.0), night), sun_side);
	EMISSION += rim_c * pow(rim, 1.6) * rim_strength * 0.35 * mix(1.0, 0.75, night) * (1.0 - glow) * ao;
}
