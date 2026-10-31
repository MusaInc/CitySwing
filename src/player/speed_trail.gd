class_name SpeedTrail
extends MeshInstance3D
## Wind ribbons off the hero's feet at speed: two thin camera-facing strips
## that trace the swing arc, fading in above ~60 km/h and out with age.
## A perfect release flashes them gold for a moment.

const LIFE := 0.45        # s a point stays in the ribbon
const MIN_SPEED := 17.0   # m/s where ribbons start to show
const FULL_SPEED := 34.0
const WIDTH := 0.05
const ALPHA := 0.09        # peak opacity of the white ribbons (was 0.22: too loud)
const FLASH_ALPHA := 0.4   # extra opacity while a perfect release flashes gold

var player: Player
var rig: CharacterRig
var _pts := [[], []]      # per ribbon: [position, age]
var _mesh := ImmediateMesh.new()
var _flash := 0.0
var _amount := 0.0


func _ready() -> void:
	mesh = _mesh
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m
	if player:
		player.perfect_release.connect(func(_s): _flash = 1.0)
		player.respawned.connect(func(): _pts = [[], []])


func _process(dt: float) -> void:
	_mesh.clear_surfaces()
	if player == null or rig == null:
		return
	var speed := player.velocity.length()
	var target := clampf((speed - MIN_SPEED) / (FULL_SPEED - MIN_SPEED), 0.0, 1.0)
	if player.is_on_floor():
		target = 0.0
	_amount = move_toward(_amount, target, dt * 3.0)
	_flash = maxf(0.0, _flash - dt * 1.6)
	var src := [rig.bones["foot_l"], rig.bones["foot_r"]]
	for i in 2:
		var arr: Array = _pts[i]
		for p in arr:
			p[1] += dt
		while not arr.is_empty() and arr[0][1] > LIFE:
			arr.pop_front()
		if _amount > 0.0:
			arr.append([(src[i] as Node3D).global_position, 0.0])
		elif not arr.is_empty():
			arr.pop_front()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _amount <= 0.0 and _pts[0].is_empty():
		return
	var eye := cam.global_position
	var col := Color(0.85, 0.93, 1.0).lerp(UiStyle.GOLD, _flash)
	for arr: Array in _pts:
		if arr.size() < 3:
			continue
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for j in arr.size():
			var p: Vector3 = arr[j][0]
			var nxt: Vector3 = arr[mini(j + 1, arr.size() - 1)][0]
			var prv: Vector3 = arr[maxi(j - 1, 0)][0]
			var along := (nxt - prv)
			if along.length_squared() < 1e-6:
				along = Vector3.UP
			var side := along.cross(eye - p).normalized()
			var k := float(j) / float(arr.size() - 1)  # 0 = oldest tail, 1 = at the foot
			var a := k * k * _amount * (ALPHA + FLASH_ALPHA * _flash)
			var w := WIDTH * (0.25 + 0.75 * k) * (1.0 + _flash)
			_mesh.surface_set_color(Color(col, a))
			_mesh.surface_add_vertex(p + side * w)
			_mesh.surface_set_color(Color(col, a))
			_mesh.surface_add_vertex(p - side * w)
		_mesh.surface_end()
