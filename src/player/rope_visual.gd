class_name RopeVisual
extends MeshInstance3D
## Draws the web as a camera-facing ribbon from the character's animated hand
## (visual only – physics uses Player.hand_position) through any corner wraps
## to the anchor. Slack ropes sag; a flying line ripples as it travels.

const SEGMENTS := 14

var player: Player
## Optional node whose position the web leaves from (the rig's launcher hand).
var hand: Node3D
var width := 0.012  # half-width (m); a fine line, like a real web
var _mesh := ImmediateMesh.new()
var _wave := 0.0
var _mat: StandardMaterial3D
var _glow := 0.0
const WHITE := Color(0.96, 0.95, 0.9)
const SWEET := Color(1.0, 0.78, 0.3)
## Web colour from the shop (Shop.look()); rainbow cycles hues along the line.
var color := WHITE
var rainbow := false
var _hue := 0.0
var _twang := 0.0   # 1 → 0 after the web catches: a quick decaying vibration
var _load := 0.0    # 0..1 smoothed swing tension (v²/r against gravity)
var _hooked := false


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = WHITE
	mat.vertex_color_use_as_albedo = true
	_mat = mat
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Transparent + top priority: drawn after the LookFilter pass, so the web
	# stays a clean bright line instead of getting inked over.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 127
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
	_wave += dt * 30.0
	if player.line_state == Player.Line.ATTACHED and not _hooked:
		_twang = 1.0
	_hooked = player.line_state == Player.Line.ATTACHED
	_twang = maxf(0.0, _twang - dt * 2.8)
	var want_load := 0.0
	if _hooked and player.s.taut:
		var r := maxf(player.s.position.distance_to(player.s.anchor), 1.0)
		want_load = clampf(player.s.velocity.length_squared() / r / 25.0, 0.0, 1.0)
	_load = lerpf(_load, want_load, 1.0 - exp(-8.0 * dt))
	# Timing cue: the web glows gold inside the perfect-release window.
	var want := 1.0 if player.line_state == Player.Line.ATTACHED and player.is_perfect_release() else 0.0
	_glow = move_toward(_glow, want, dt * (12.0 if want > _glow else 5.0))
	_hue = fmod(_hue + dt * 0.35, 1.0)
	_mat.albedo_color = (Color.WHITE if rainbow else color).lerp(SWEET, _glow)
	# Under load the line pulls thin and bright; it leaves the hand thicker.
	var w_scale := (1.0 + _glow * 0.6) * (1.0 - 0.22 * _load)
	var start := hand.global_position if hand else player.hand_position()
	var pts: PackedVector3Array
	var sag := 0.0
	var amp := 0.0
	if player.line_state == Player.Line.FLYING:
		pts = PackedVector3Array([start, player.line_tip])
		amp = 0.22
	else:
		pts = player.rope_points()
		pts[0] = start
		var s := player.s
		var slack := maxf(0.0, s.rope_length - s.position.distance_to(s.anchor))
		sag = sqrt(slack * maxf(start.distance_to(s.anchor), 0.1)) * 0.45
	# Never through the world: the animated hand isn't the physics pivot, so an
	# edge can sit between it and the first pivot – bend the drawn line round it.
	pts = _clear_path(pts)
	if sag > 0.0:
		sag = _clear_sag(pts[0], pts[1], sag)
	if player.line_state == Player.Line.FLYING and pts.size() == 2:
		amp = minf(amp, _clear_sag(pts[0], pts[1], amp))
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var cam_pos := cam.global_position
	for seg_i in pts.size() - 1:
		var a := pts[seg_i]
		var b := pts[seg_i + 1]
		var side := (b - a).cross(Vector3.UP).normalized()
		if side.length_squared() < 0.5:
			side = Vector3.RIGHT
		var tangent := (b - a).normalized()
		var first := seg_i == 0
		for i in SEGMENTS + 1:
			if i == 0 and seg_i > 0:
				continue  # shared joint with the previous segment
			var t := float(i) / SEGMENTS
			var p := a.lerp(b, t)
			if first:
				# Only the free segment (hand → nearest pivot) sags or ripples.
				p += Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
				p += side * sin(t * 9.0 - _wave) * amp * t * (1.0 - t) * 4.0
				# Catch twang: a standing wave along the taut line, dying fast.
				p += side * sin(t * PI * 3.0) * sin(_wave * 1.7) * 0.09 * _twang * _twang
			var to_cam := (cam_pos - p).normalized()
			var taper := 1.0 + 0.6 * maxf(0.0, 1.0 - p.distance_to(pts[0]) / 1.2)
			var w := tangent.cross(to_cam).normalized() * width * w_scale * taper * (1.0 + p.distance_to(cam_pos) * 0.009)
			if rainbow:
				_mesh.surface_set_color(Color.from_hsv(fmod(_hue + (seg_i + t) * 0.35, 1.0), 0.75, 1.0))
			else:
				_mesh.surface_set_color(Color(1.0 + 0.25 * _load, 1.0 + 0.25 * _load, 1.0 + 0.25 * _load))
			_mesh.surface_add_vertex(p - w)
			_mesh.surface_add_vertex(p + w)
	_mesh.surface_end()


const MASK := 1 | (1 << 1) | (1 << 3) | (1 << 4)


## Inserts corner points where the straight hand → pivot segment meets geometry.
func _clear_path(pts: PackedVector3Array) -> PackedVector3Array:
	if not is_inside_tree() or pts.size() < 2:
		return pts
	var space := get_world_3d().direct_space_state
	var out := PackedVector3Array([pts[0]])
	var a := pts[0]
	var b := pts[1]
	for i in 3:
		var d := b - a
		if d.length() < 0.5:
			break
		var q := PhysicsRayQueryParameters3D.create(a, b - d.normalized() * 0.35, MASK, [player.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		# Slide the corner to the edge: step out along the normal until the
		# line to the pivot is clear.
		var n: Vector3 = hit["normal"]
		var c: Vector3 = hit["position"] + n * 0.05
		for k in 6:
			q.from = c
			q.to = b - (b - c).normalized() * 0.35
			if space.intersect_ray(q).is_empty():
				break
			c += (n + (b - c).normalized()).normalized() * 0.25
		out.append(c)
		a = c
	for j in range(1, pts.size()):
		out.append(pts[j])
	return out


## Largest sag (≤ want) whose curve stays clear of anything below the segment.
func _clear_sag(a: Vector3, b: Vector3, want: float) -> float:
	if not is_inside_tree():
		return want
	var space := get_world_3d().direct_space_state
	var mid := (a + b) * 0.5
	var q := PhysicsRayQueryParameters3D.create(mid, mid + Vector3.DOWN * (want + 0.1), MASK, [player.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return want
	return maxf(mid.y - (hit["position"] as Vector3).y - 0.1, 0.0)
