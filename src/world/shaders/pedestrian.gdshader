// Pedestrians walked entirely on the GPU (like traffic.gdshader): each
// MultiMesh instance starts at one end of a pavement segment facing along it;
// INSTANCE_CUSTOM = (speed m/s, phase m, segment length m, unused). The body
// slides along local -Z and wraps, with a walk cycle in the vertex shader:
// legs (|x| < 0.2, below the hips) and arms (|x| > 0.2) swing in opposition,
// and the body bobs twice per stride. One material per surface: "shirt"
// takes the instance colour.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float roughness = 0.8;

void vertex() {
	float spd = INSTANCE_CUSTOM.x;
	float len = INSTANCE_CUSTOM.z;
	float d = mod(INSTANCE_CUSTOM.y + TIME * spd, len);
	float ph = d / 0.72 * 3.14159;  // one step per 0.72 m
	float sw = sin(ph);
	float side = sign(VERTEX.x);
	if (abs(VERTEX.x) < 0.2 && VERTEX.y < 0.86) {
		float k = (0.86 - VERTEX.y);
		VERTEX.z += sw * side * k * 0.6;
		VERTEX.y += max(0.0, sw * side) * k * 0.12;  // swinging foot lifts
	} else if (abs(VERTEX.x) > 0.2 && VERTEX.y < 1.45) {
		VERTEX.z -= sw * side * (1.45 - VERTEX.y) * 0.45;
	}
	VERTEX.y += abs(cos(ph)) * 0.035;
	// Fade in/out at the segment ends so the wrap isn't a pop.
	float s = smoothstep(0.0, 1.5, d) * smoothstep(len, len - 1.5, d);
	VERTEX *= s;
	VERTEX.z -= d;
}

void fragment() {
	ALBEDO = use_instance_color ? COLOR.rgb : tint;
	ROUGHNESS = roughness;
}
