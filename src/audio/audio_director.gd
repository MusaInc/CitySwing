class_name AudioDirector
extends Node
## Continuous layers driven by the simulation (wind ← speed, rope hum ← rope
## tension, ambience ← height above street) plus event one-shots and haptics.
## All sounds are synthesised by tools/audio/gen_audio.py.

const DIR := "res://assets/audio/"
const LOOPS := ["wind_loop", "rope_tension_loop", "city_ambience", "music_loop", "traffic_loop", "rain_loop"]
const SHOTS := ["knockout", "grapple_fire", "grapple_attach", "grapple_miss", "release_whoosh", "rope_snap", "land", "roll",
	"impact", "splash", "thunder", "checkpoint", "finish", "fail", "ui_click", "wall_kick", "bump", "horn",
	"step_concrete_0", "step_concrete_1", "step_concrete_2", "step_gravel_0", "step_gravel_1", "step_gravel_2",
	"step_grass_0", "step_grass_1", "step_grass_2"]

var _step_dist := 0.0
var _step_i := 0
var _horn_in := 9.0
var _rig_steps := false  # footsteps come from the rig's foot plants

var player: Player
var atmosphere: Atmosphere
var _loops := {}
var _shots := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for name in LOOPS:
		var stream := _load(name)
		if stream == null:
			continue
		if stream is AudioStreamWAV:
			var w := stream as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Music" if name == "music_loop" else "SFX"
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_loops[name] = p
	for name in SHOTS:
		var s := _load(name)
		if s:
			_shots[name] = s
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	apply_volumes()
	Settings.changed.connect(apply_volumes)


func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _load(name: String) -> AudioStream:
	var path := DIR + name + ".wav"
	return load(path) if ResourceLoader.exists(path) else null


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Settings.music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Settings.sfx_volume, 0.0001)))


func attach_player(p: Player) -> void:
	player = p
	p.grapple_fired.connect(func(_t, _hit): play("grapple_fire", -4.0, randf_range(0.95, 1.08)))
	p.attached.connect(func(_a):
		play("grapple_attach", -3.0, randf_range(0.93, 1.07))
		Settings.haptic(12, 0.35))
	p.grapple_missed.connect(func(): play("grapple_miss", -8.0, randf_range(0.92, 1.08)))
	p.released.connect(func(v: Vector3):
		play("release_whoosh", linear_to_db(clampf(v.length() / 35.0, 0.2, 1.0)), 0.9 + v.length() / 120.0)
		Settings.haptic(8, 0.2))
	p.rope_snapped.connect(func(spd: float):
		play("rope_snap", linear_to_db(clampf(spd / 12.0, 0.2, 1.0)), randf_range(0.94, 1.06))
		Settings.haptic(20, clampf(spd / 15.0, 0.2, 0.8)))
	p.perfect_release.connect(func(streak: int):
		# A rising chime: each perfect in a row climbs a semitone (max an octave).
		play("checkpoint", -7.0, pow(2.0, mini(streak - 1, 12) / 12.0) * 1.15)
		Settings.haptic(18, 0.55))
	p.landed.connect(_on_landed)
	p.impact.connect(func(spd: float):
		play("impact", linear_to_db(clampf(spd / 30.0, 0.3, 1.0)), randf_range(0.92, 1.05))
		Settings.haptic(int(clampf(spd * 3.0, 40.0, 120.0)), 1.0))
	p.launched.connect(func(): play("wall_kick", -4.0, randf_range(1.12, 1.25)))
	p.bumped.connect(func(spd: float, _n: Vector3):
		play("bump", linear_to_db(clampf(spd / 10.0, 0.25, 0.9)), randf_range(0.9, 1.1))
		Settings.haptic(int(clampf(spd * 2.5, 8.0, 30.0)), 0.35))
	var rig := p.get_node_or_null("Rig")
	if rig and rig.has_signal("footstep"):
		rig.footstep.connect(_on_footstep)
		_rig_steps = true
	p.wall_run_started.connect(func(_n: Vector3):
		play("wall_kick", -5.0, 0.9)
		Settings.haptic(18, 0.45))
	p.wall_run_launched.connect(func(): play("release_whoosh", -7.0, 1.1))
	p.wall_kicked.connect(func():
		play("wall_kick", -2.0)
		Settings.haptic(25, 0.6))


## A building rushing past: a short, bright whoosh (higher when faster).
func close_call(speed: float, razor: bool) -> void:
	play("release_whoosh", -3.0 if razor else -6.0, 1.35 + speed / 90.0)
	Settings.haptic(14 if razor else 8, 0.4 if razor else 0.25)


func attach_weather(a: Atmosphere) -> void:
	atmosphere = a
	a.thunder.connect(func(delay: float, strength: float):
		get_tree().create_timer(delay).timeout.connect(func():
			play("thunder", linear_to_db(0.35 + 0.5 * strength), randf_range(0.85, 1.1))))


func _on_landed(speed: float, _street: bool) -> void:
	if player and player.params and speed > player.params.roll_landing_speed:
		play("roll", -2.0, randf_range(0.94, 1.06))
		Settings.haptic(45, 0.7)
	elif speed > 3.0:
		play("land", linear_to_db(clampf(speed / 15.0, 0.25, 1.0)), randf_range(0.93, 1.07) - clampf(speed / 200.0, 0.0, 0.08))
		Settings.haptic(int(clampf(speed * 2.0, 10.0, 40.0)), 0.5)


func play(name: String, db := 0.0, pitch := 1.0) -> void:
	var s: AudioStream = _shots.get(name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _process(dt: float) -> void:
	if player == null:
		return
	var spd := player.speed()
	var k := 1.0 - exp(-6.0 * dt)
	var wind: AudioStreamPlayer = _loops.get("wind_loop")
	if wind:
		var w := smoothstep(3.0, 50.0, spd)
		wind.volume_db = lerpf(wind.volume_db, linear_to_db(maxf(w * 0.9, 0.003)), k)
		wind.pitch_scale = lerpf(wind.pitch_scale, 0.75 + 0.6 * w, k)
	var rope: AudioStreamPlayer = _loops.get("rope_tension_loop")
	if rope:
		var load_ := clampf(player.s.tension / 55.0, 0.0, 1.0) if player.s.attached and player.s.taut else 0.0
		rope.volume_db = lerpf(rope.volume_db, linear_to_db(maxf(load_ * 0.55, 0.002)), 1.0 - exp(-12.0 * dt))
		rope.pitch_scale = 0.85 + 0.4 * load_
	var amb: AudioStreamPlayer = _loops.get("city_ambience")
	if amb:
		# The street hum fades as you climb above the rooftops.
		var height := clampf(player.height_above_ground() / 120.0, 0.0, 1.0)
		amb.volume_db = lerpf(amb.volume_db, linear_to_db(0.55 - 0.35 * height), k)
	var traffic: AudioStreamPlayer = _loops.get("traffic_loop")
	if traffic:
		# Street-level traffic: loud on the pavement, gone above the rooftops.
		var low := 1.0 - clampf(player.height_above_ground() / 60.0, 0.0, 1.0)
		traffic.volume_db = lerpf(traffic.volume_db, linear_to_db(maxf(low * low * 0.4, 0.002)), k)
	var rain: AudioStreamPlayer = _loops.get("rain_loop")
	if rain:
		var r: float = atmosphere.w["rain"] if atmosphere else 0.0
		rain.volume_db = lerpf(rain.volume_db, linear_to_db(maxf(r * 0.5, 0.001)), k)
	_horn_in -= dt
	if _horn_in <= 0.0:
		_horn_in = randf_range(8.0, 24.0)
		var above := player.height_above_ground()
		if above < 50.0:
			play("horn", linear_to_db(0.12 + 0.18 * (1.0 - above / 50.0)), randf_range(0.9, 1.12))
	_footsteps(dt)
	var music: AudioStreamPlayer = _loops.get("music_loop")
	if music:
		music.volume_db = lerpf(music.volume_db, -9.0, 1.0 - exp(-0.5 * dt))


## One step per stride while running on the ground; the sound follows the
## surface: grass in parks, gravel on roofs, concrete on the street.
func _footsteps(dt: float) -> void:
	if not player.is_on_floor() or player.s.attached or player.stunned:
		_step_dist = 0.0
		return
	var v := player.s.velocity
	var vh := Vector2(v.x, v.z).length()
	if vh < 0.8:
		_step_dist = 0.0
		return
	if _rig_steps:
		return  # the rig plays them on each real touchdown
	_step_dist += vh * dt
	var stride := 0.65 + 0.07 * vh
	if _step_dist < stride:
		return
	_step_dist -= stride
	_step_sound(player.global_position, vh)


func _on_footstep(pos: Vector3) -> void:
	if player == null or player.s.attached or player.stunned or not player.is_on_floor():
		return
	var v := player.s.velocity
	var vh := Vector2(v.x, v.z).length()
	if vh < 0.5:
		return  # settle shuffles on the spot stay quiet
	_step_sound(pos, vh)


func _step_sound(pos: Vector3, vh: float) -> void:
	var surf := "gravel" if player.height_above_ground() > 3.0 else "concrete"
	var world := get_parent().get_node_or_null("World") if get_parent() else null
	if surf == "concrete" and world and world.get("layout") and world.layout.is_park(Vector2(pos.x, pos.z)):
		surf = "grass"
	_step_i = (_step_i + 1 + randi() % 2) % 3
	# Sprinting lands harder: louder and a touch lower.
	play("step_%s_%d" % [surf, _step_i], linear_to_db(clampf(0.25 + vh / 14.0, 0.25, 0.85)),
		randf_range(0.94, 1.06) - clampf((vh - 10.0) * 0.008, 0.0, 0.06))
