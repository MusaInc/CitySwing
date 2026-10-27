// Cars driven entirely on the GPU: each MultiMesh instance sits at the start
// of a lane segment facing along it; INSTANCE_CUSTOM = (speed m/s, phase m,
// segment length m, unused). The car slides along local -Z and wraps.
// One material per car surface: paint takes the instance colour, others keep
// their own tint; lamps emit.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.4;

void vertex() {
	float spd = INSTANCE_CUSTOM.x;
	float len = INSTANCE_CUSTOM.z;
	float d = mod(INSTANCE_CUSTOM.y + TIME * spd, len);
	// Shrink over the first/last metres so wrapping at the segment ends isn't a pop.
	float s = smoothstep(0.0, 4.0, d) * smoothstep(len, len - 4.0, d);
	VERTEX *= s;
	VERTEX.z -= d;
}

void fragment() {
	vec3 c = use_instance_color ? COLOR.rgb : tint;
	ALBEDO = c;
	ROUGHNESS = roughness;
	METALLIC = use_instance_color ? 0.35 : 0.0;
	EMISSION = tint * emission;
}
