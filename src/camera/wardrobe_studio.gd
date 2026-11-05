class_name WardrobeStudio
extends RefCounted
## The wardrobe at home: the hero turns from the rail to face into the room
## and an orbit camera frames whatever category is being browsed – the shop's
## rooftop studio (CinematicDirector.shop_xf), in your own flat. Same preview
## controls (shop_focus / shop_yaw / shop_zoom) so the Wardrobe screen drives
## either.

var player: Player
var camera: SwingCamera
var face := Vector3.FORWARD
var shop_focus := "full"
var shop_yaw := 0.0
var shop_zoom := 1.0
var _h := 1.0
var _d := 3.0
var _yaw_s := 0.0
var _fresh := true


func reset_shop_view() -> void:
	shop_yaw = 0.3
	shop_zoom = 1.0


func xf(dt: float) -> Array:
	var fr: Array = CinematicDirector.SHOP_FRAME.get(shop_focus, CinematicDirector.SHOP_FRAME["full"])
	var k := 1.0 if _fresh else 1.0 - exp(-4.0 * dt)
	_h = lerpf(_h, fr[0], k)
	_d = lerpf(_d, float(fr[1]) * shop_zoom * 0.85, k)  # rooms are smaller than rooftops
	_yaw_s = shop_yaw if _fresh else lerp_angle(_yaw_s, shop_yaw, 1.0 - exp(-10.0 * dt))
	var feet := player.global_position + Vector3.DOWN * 0.9
	var aim := feet + Vector3.UP * _h
	var dir := face.rotated(Vector3.UP, _yaw_s)
	var pitch := lerpf(0.42, -0.05, clampf((_h - 0.08) / 1.2, 0.0, 1.0))
	var want := aim + (dir + Vector3.UP * (pitch + 0.08)).normalized() * _d
	# Walls and furniture: pull in rather than film through them.
	var q := PhysicsRayQueryParameters3D.create(aim, want, 1 | (1 << 1) | CityWorld.HUMAN_LAYER)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3 = want if hit.is_empty() else aim + ((hit.position as Vector3) - aim) * 0.85
	var vp := player.get_viewport().get_visible_rect().size
	var width := 2.0 * aim.distance_to(pos) * tan(deg_to_rad(44.0) * 0.5) * (vp.x / maxf(vp.y, 1.0))
	var off := -width * 0.21  # hero right of centre, clear of the wardrobe panel
	camera.cam.h_offset = off if _fresh else lerpf(camera.cam.h_offset, off, 1.0 - exp(-5.0 * dt))
	_fresh = false
	return [Transform3D(Basis.looking_at((aim - pos).normalized(), Vector3.UP), pos), 44.0]
