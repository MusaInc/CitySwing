class_name Player
extends CharacterBody3D
## Bridges the pure SwingPhysics model with engine collision. Each tick:
## read input → update grapple targeting/line → integrate model → move_and_slide
## against real geometry → feed contact normals back into the model's velocity.

signal grapple_fired(target: Vector3, will_hit: bool)
signal attached(anchor: Vector3)
signal released(velocity: Vector3)
signal grapple_missed
signal landed(speed: float, on_street: bool)
signal impact(speed: float)
signal rope_snapped(speed: float)
signal respawned
signal wall_kicked

enum Line { IDLE, FLYING, ATTACHED }

const CENTER_HEIGHT := 0.95
const HAND_OFFSET := Vector3(0.0, 0.7, 0.0)

@export var params: SwingParams

var s := SwingPhysics.State.new()
var controls := SwingPhysics.Controls.new()
var targeting := GrappleTargeting.new()
## Node providing the view basis for camera-relative input (the SwingCamera).
var view: Node3D
## Optional autopilot (tests / attract mode): object with drive(player, dt) -> Dictionary.
var bot: Object = null
var input_enabled := true

var line_state := Line.IDLE
var line_tip := Vector3.ZERO
var line_target := Vector3.ZERO
var line_will_hit := false
var aim_dir := Vector3.FORWARD

var spawn_transform := Transform3D.IDENTITY
var last_safe_position := Vector3.ZERO
var on_street := false
var was_on_floor := false
var air_time := 0.0

# Run statistics (reset by game modes).
var distance_travelled := 0.0
var swings := 0
var chain := 0
var best_chain := 0
var top_speed := 0.0

var _grapple_held := false


func _ready() -> void:
	if params == null:
		var settings := get_node_or_null("/root/Settings")
		params = settings.swing_params() if settings else load("res://config/swing_params.tres")
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 3)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	safe_margin = 0.02
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		shape.shape = cap
		shape.position.y = 0.0
		add_child(shape)
	spawn_transform = global_transform
	last_safe_position = global_position
	s.position = global_position


func speed() -> float:
	return s.velocity.length()


func hand_position() -> Vector3:
	return global_position + HAND_OFFSET


func _read_input(dt: float) -> Dictionary:
	if bot != null:
		return bot.drive(self, dt)
	if not input_enabled:
		return {"move": Vector3.ZERO, "aim": aim_dir, "grapple": false, "reel": 0.0, "jump": false}
	var mv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var basis := view.global_transform.basis if view else global_transform.basis
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	return {
		"move": (right * mv.x + fwd * mv.y).limit_length(1.0),
		"aim": -basis.z,
		"grapple": Input.is_action_pressed("grapple"),
		"reel": Input.get_action_strength("reel_in") - Input.get_action_strength("reel_out"),
		"jump": Input.is_action_just_pressed("jump"),
		"respawn": Input.is_action_just_pressed("respawn"),
	}


func _physics_process(dt: float) -> void:
	var inp := _read_input(dt)
	controls.move = inp.get("move", Vector3.ZERO)
	controls.reel = inp.get("reel", 0.0)
	controls.jump = inp.get("jump", false)
	aim_dir = inp.get("aim", aim_dir)
	if inp.get("respawn", false):
		respawn()
		return

	var origin := hand_position()
	targeting.update(get_world_3d().direct_space_state, origin, aim_dir, s.velocity, params,
		is_on_floor(), [get_rid()])

	var held: bool = inp.get("grapple", false)
	if held and not _grapple_held:
		_fire(origin)
	elif not held and _grapple_held:
		_let_go()
	_grapple_held = held
	_advance_line(dt, origin)

	if controls.jump and not is_on_floor() and is_on_wall():
		var n := get_wall_normal()
		s.velocity += Vector3(n.x, 0.0, n.z).normalized() * params.wall_kick_speed
		s.velocity.y = maxf(s.velocity.y, 0.0) + params.wall_kick_up
		controls.jump = false
		wall_kicked.emit()

	# Integrate the model from the body's real position.
	s.position = global_position
	s.grounded = is_on_floor()
	var start := global_position
	SwingPhysics.step(s, controls, params, dt)
	if s.snap_speed > 2.0:
		rope_snapped.emit(s.snap_speed)
	floor_snap_length = 0.0 if (s.attached or s.velocity.y > 0.5) else 0.4
	velocity = (s.position - start) / dt
	move_and_slide()
	_resolve_contacts()

	var moved := global_position - start
	distance_travelled += Vector3(moved.x, 0.0, moved.z).length()
	top_speed = maxf(top_speed, s.velocity.length())
	if is_on_floor():
		air_time = 0.0
	else:
		air_time += dt
	if global_position.y < params.kill_plane_y:
		respawn()


func _resolve_contacts() -> void:
	var worst_into := 0.0
	var floor_street := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var into := -s.velocity.dot(n)
		if into > 0.0:
			s.velocity += n * into
			if n.y < 0.6:
				worst_into = maxf(worst_into, into)
			elif not was_on_floor:
				worst_into = maxf(worst_into, into * 0.5)
		var col := c.get_collider()
		if n.y > 0.6 and col is Node and (col as Node).is_in_group("street"):
			floor_street = true
	var on_floor := is_on_floor()
	if on_floor and not was_on_floor:
		on_street = floor_street
		var land_speed := -get_real_velocity().y
		landed.emit(maxf(land_speed, worst_into), floor_street)
		chain = 0
		if not floor_street:
			last_safe_position = global_position + Vector3.UP * 0.2
	elif on_floor:
		on_street = floor_street
	if worst_into > params.hard_impact_speed:
		impact.emit(worst_into)
	was_on_floor = on_floor


func _fire(origin: Vector3) -> void:
	if line_state != Line.IDLE:
		return
	line_state = Line.FLYING
	line_tip = origin
	line_will_hit = targeting.has_target
	line_target = targeting.point if line_will_hit else origin + aim_dir.normalized() * params.grapple_range * 0.8
	grapple_fired.emit(line_target, line_will_hit)


func _advance_line(dt: float, origin: Vector3) -> void:
	if line_state != Line.FLYING:
		return
	var to := line_target - line_tip
	var step := params.line_speed * dt
	if to.length() > step:
		line_tip += to.normalized() * step
		return
	line_tip = line_target
	if line_will_hit and SwingPhysics.attach(s, line_target, _range_tolerant()):
		line_state = Line.ATTACHED
		attached.emit(line_target)
	else:
		line_state = Line.IDLE
		grapple_missed.emit()


## The anchor may drift slightly out of range while the line travels; allow 10%.
func _range_tolerant() -> SwingParams:
	if s.position.distance_to(line_target) <= params.grapple_range:
		return params
	var p: SwingParams = params.duplicate()
	p.grapple_range *= 1.1
	return p


func _let_go() -> void:
	if line_state == Line.ATTACHED:
		SwingPhysics.release(s)
		swings += 1
		chain += 1
		best_chain = maxi(best_chain, chain)
		released.emit(s.velocity)
	line_state = Line.IDLE


func respawn(at: Variant = null) -> void:
	SwingPhysics.release(s)
	line_state = Line.IDLE
	_grapple_held = true  # require a fresh press
	global_position = at if at is Vector3 else last_safe_position
	s.velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	s.position = global_position
	chain = 0
	respawned.emit()


func reset_stats() -> void:
	distance_travelled = 0.0
	swings = 0
	chain = 0
	best_chain = 0
	top_speed = 0.0
