// Subtle fisheye toward the screen edges, drawn on a CanvasLayer under the
// HUD (LensFx), so it bends the 3D world and never the HUD or menus.
// The centre stays almost undistorted; the bend grows with radius², and the
// mapping is normalised so the corners stay filled (no black borders).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 0.06;   // barrel amount at the corners
uniform float aspect = 1.78;     // width / height

void fragment() {
	vec2 p = SCREEN_UV - 0.5;
	vec2 q = vec2(p.x * aspect, p.y);
	float corner2 = 0.25 * (aspect * aspect + 1.0);
	float r2 = dot(q, q) / corner2;            // 0 centre … 1 corner
	float k = strength;
	// Barrel: an output pixel at radius r samples the image further out,
	// compressing the edges; ÷(1+k) keeps the corner mapped to the corner.
	float s = (1.0 + k * r2 * r2 * 0.35 + k * r2 * 0.65) / (1.0 + k);
	COLOR = vec4(texture(screen_tex, 0.5 + p * s).rgb, 1.0);
}
