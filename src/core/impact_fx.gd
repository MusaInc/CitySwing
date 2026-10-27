class_name ImpactFx
extends Node
## Game-feel time effects: a wall knockout freezes for a beat (hit-stop),
## then plays the crumple in slow motion and eases back to full speed.
## Runs on real time (unaffected by its own time_scale) and always restores
## Engine.time_scale – also when the game is paused or the effect is cut.

const FREEZE := 0.07       # s at near-zero speed
const SLOW := 0.55         # s of slow motion after the freeze
const SLOW_SCALE := 0.3
const EASE := 0.45         # s back to full speed

var _t := -1.0
var _last_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func knockout(speed: float) -> void:
	# Harder hits hold the freeze a touch longer.
	_t = -clampf((speed - 17.0) / 40.0, 0.0, 1.0) * 0.05
	_last_ms = Time.get_ticks_msec()
	Engine.time_scale = 0.03


func cancel() -> void:
	_t = -1.0
	Engine.time_scale = 1.0


func active() -> bool:
	return _t > -1.0 or Engine.time_scale < 1.0


func _process(_dt: float) -> void:
	if _t <= -1.0:
		return
	if get_tree().paused:
		cancel()
		return
	var now := Time.get_ticks_msec()
	_t += (now - _last_ms) / 1000.0
	_last_ms = now
	var t := _t - FREEZE
	if t < 0.0:
		Engine.time_scale = 0.03
	elif t < SLOW:
		Engine.time_scale = SLOW_SCALE
	elif t < SLOW + EASE:
		var k := (t - SLOW) / EASE
		Engine.time_scale = lerpf(SLOW_SCALE, 1.0, k * k * (3.0 - 2.0 * k))
	else:
		cancel()
