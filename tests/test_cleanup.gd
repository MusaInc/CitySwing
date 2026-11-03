extends Node
var world: CityWorld
func setup() -> void:
	world = CityWorld.new()
	add_child(world)
	await get_tree().physics_frame
func teardown() -> void:
	world.queue_free()
	await get_tree().process_frame

func test_bridge_has_a_continuous_walkable_city_connection(t) -> void:
	var l := world.layout
	t.check(l.bridge_ramp.size() > 20, "bridge has a real island approach")
	if l.bridge_ramp.is_empty():
		return
	t.near(l.bridge_ramp[0].y, CityLayout.BRIDGE_DECK, 0.01, "starts at bridge deck")
	var end := l.bridge_ramp[-1]
	t.near(end.y, l.terrain.road_y(end.x, end.z), 0.02, "lands at street level")
	var max_grade := 0.0
	var space := world.get_world_3d().direct_space_state
	var missing := 0
	for i in l.bridge_ramp.size() - 1:
		var a := l.bridge_ramp[i]
		var b := l.bridge_ramp[i + 1]
		max_grade = maxf(max_grade, absf(b.y - a.y) / Vector2(b.x - a.x, b.z - a.z).length())
		var p := a.lerp(b, 0.5)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.6, 3))
		if hit.is_empty() or absf(hit.position.y - p.y) > 0.2:
			missing += 1
	t.check(max_grade < 0.14, "approach grade %.1f%%" % (max_grade * 100))
	t.check(missing == 0, "every approach segment has matching collision (%d missing)" % missing)
	var through := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(48, 25.2, CityLayout.BRIDGE_Z), Vector3(70, 25.2, CityLayout.BRIDGE_Z), 3))
	t.check(through.is_empty(), "no painted portal / solid wall across the roadway")

func test_public_spaces_leave_streets_clear(t) -> void:
	var l := world.layout
	t.check(l.public_gardens.size() >= 12, "waterfront and courtyards have planted spaces")
	t.check(l.public_furniture.size() >= 24, "seating and bins in the public realm")
	var on_road := 0
	var water := 0
	for p in l.public_gardens:
		if l.roads.on_road(Vector2(p.x, p.z)):
			on_road += 1
		if l.is_water(p):
			water += 1
	t.check(on_road == 0 and water == 0, "gardens stay off roads and water")

func test_open_rail_sampling_does_not_wrap_at_terminals(t) -> void:
	var points := PackedVector3Array([Vector3.ZERO, Vector3(2, 1, 0), Vector3(4, 2, 0)])
	t.check(RailNetwork._at(points, -2, false) == points[0], "before first buffer clamps to first point")
	t.check(RailNetwork._at(points, 50, false) == points[-1], "after last buffer clamps to last point")
	var buffers := false
	for structure in world.layout.structures:
		if structure.get("name", "") == "valley_buffers":
			buffers = true
	t.check(buffers, "Valley shuttle has physical buffer stops")
