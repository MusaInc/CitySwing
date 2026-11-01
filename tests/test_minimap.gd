extends Node
## Minimap: forward is up, right is right, north tick in the right place,
## zoom eases with speed; markers keep priority and pin to the rim.

var player: Player
var map: Minimap


func setup() -> void:
	player = Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	add_child(player)
	player.bot = null
	map = Minimap.new()
	map.size = Vector2(160, 160)
	add_child(map)
	map.player = player
	player.global_position = Vector3(100, 50, -200)
	await get_tree().physics_frame


func teardown() -> void:
	map.queue_free()
	player.queue_free()
	await get_tree().process_frame


func test_map_is_oriented_to_the_heading(t) -> void:
	var c := map.size * 0.5
	# Heading -z (yaw 0): a point 40 m ahead is straight up, one to +x is right.
	map._yaw = 0.0
	var ahead := map.world_to_map(player.global_position + Vector3(0, 0, -40)) - c
	var right := map.world_to_map(player.global_position + Vector3(40, 0, 0)) - c
	t.check(ahead.y < -10.0 and absf(ahead.x) < 0.5, "ahead is up the map (%s)" % ahead)
	t.check(right.x > 10.0 and absf(right.y) < 0.5, "+x is right when facing -z (%s)" % right)
	# Facing +x (yaw -90°): a point ahead (+x) is up; -z (north) is on the left.
	map._yaw = -PI / 2.0
	ahead = map.world_to_map(player.global_position + Vector3(40, 0, 0)) - c
	var north := map.world_to_map(player.global_position + Vector3(0, 0, -40)) - c
	t.check(ahead.y < -10.0 and absf(ahead.x) < 0.5, "turned: ahead is still up (%s)" % ahead)
	t.check(north.x < -10.0, "turned: north is to the left (%s)" % north)


func test_zoom_widens_with_speed_smoothly(t) -> void:
	var r0 := map._radius
	player.s.velocity = Vector3(0, 0, -40)
	for i in 30:
		map._process(1.0 / 60.0)
	var r1 := map._radius
	t.check(r1 > r0 and r1 < Minimap.R_FAST, "zoom eases out with speed (%.0f → %.0f m)" % [r0, r1])
