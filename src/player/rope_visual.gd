class_name RopeVisual
extends MeshInstance3D
## Draws the grapple line as a camera-facing ribbon. Taut ropes are straight;
## slack ropes sag (approximate catenary from the unused length); a flying line
## ripples slightly as it travels.

const SEGMENTS := 18

var player: Player
var width := 0.045
var _mesh := ImmediateMesh.new()
var _wave := 0.0


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.93, 0.86)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	extra_cull_margin = 200.0


func _process(dt: float) -> void:
	_mesh.clear_surfaces()
	global_transform = Transform3D.IDENTITY
	if player == null or player.line_state == Player.Line.IDLE:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var a := player.hand_position()
	var b := player.line_tip if player.line_state == Player.Line.FLYING else player.s.anchor
	var dist := a.distance_to(b)
	if dist < 0.05:
		return
	var sag := 0.0
	if player.line_state == Player.Line.ATTACHED:
		var slack := maxf(0.0, player.s.rope_length - player.s.position.distance_to(player.s.anchor))
		sag = sqrt(slack * dist) * 0.45
	_wave += dt * 30.0
	var amp := 0.25 if player.line_state == Player.Line.FLYING else 0.0
	var side := (b - a).cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var cam_pos := cam.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var p := a.lerp(b, t)
		p += Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		p += side * sin(t * 9.0 - _wave) * amp * t * (1.0 - t) * 4.0
		var tangent := (b - a).normalized()
		var to_cam := (cam_pos - p).normalized()
		var w := tangent.cross(to_cam).normalized() * width * (1.0 + p.distance_to(cam_pos) * 0.012)
		_mesh.surface_add_vertex(p - w)
		_mesh.surface_add_vertex(p + w)
	_mesh.surface_end()
