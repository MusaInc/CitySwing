// Stylised golden-hour sky: gradient zenith→horizon, warm haze band, sun disc
// with a wide glow, and a layer of soft drifting cloud. Cheap enough to drive
// the radiance map on mobile.
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.24, 0.42, 0.72);
uniform vec3 horizon : source_color = vec3(0.84, 0.8, 0.78);
uniform vec3 haze : source_color = vec3(1.0, 0.66, 0.42);
uniform vec3 ground : source_color = vec3(0.32, 0.3, 0.3);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.86, 0.72);
uniform vec3 cloud_shade : source_color = vec3(0.56, 0.55, 0.64);
uniform float cloud_cover = 0.45;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = max(dot(d, sun_dir), 0.0);
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon, zenith, pow(h, 0.45));
		// Warm haze hugging the horizon, stronger toward the sun.
		col = mix(col, haze, exp(-h * 12.0) * (0.15 + 0.6 * pow(sd, 3.0)));
	} else {
		col = mix(horizon * 0.9, ground, clamp(-h * 4.0, 0.0, 1.0));
	}
	col += sun_tint * (pow(sd, 6.0) * 0.35 + pow(sd, 64.0) * 0.6);
	if (!AT_CUBEMAP_PASS) {
		col += sun_tint * smoothstep(0.9993, 0.9997, sd) * 6.0;
	}
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 1.4;
		uv += vec2(TIME * 0.004, TIME * 0.002);
		float c = fbm(uv);
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, c) * smoothstep(0.0, 0.18, h);
		vec3 cc = mix(cloud_shade, cloud_lit, clamp(0.4 + pow(sd, 2.0) + (c - 0.5), 0.0, 1.0));
		col = mix(col, cc, cov * 0.85);
	}
	COLOR = col;
}
