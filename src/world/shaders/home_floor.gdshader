shader_type spatial;
render_mode diffuse_burley;
uniform vec3 timber : source_color = vec3(0.35, 0.23, 0.14);
uniform vec2 room_size = vec2(10.0);
void fragment() {
 vec2 p = UV * room_size;
 float board = floor(p.x / 0.22);
 float across = fract(p.x / 0.22);
 float along = fract((p.y + mod(board, 3.0) * 0.67) / 2.0);
 float grain = sin(p.y * 55.0 + sin(p.x * 18.0) * 3.0) * 0.025;
 float variation = fract(sin(board * 31.7) * 1763.3) * 0.12;
 float seam = (1.0 - smoothstep(0.005, 0.02, across)) + (1.0 - smoothstep(0.001, 0.004, along));
 ALBEDO = timber * (0.94 + variation + grain - min(seam, 1.0) * 0.22);
 ROUGHNESS = 0.73;
 SPECULAR = 0.22;
}
