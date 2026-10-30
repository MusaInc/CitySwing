class_name Gadgets
extends Node
## The equipped shop gadget: GADGET (E / pad X / the touch button) sets it
## off, it runs for its duration, then recharges over its cooldown.
##   boost  Jet Boots: a burst toward where the camera looks, and up a bit
##          (lets go of the web).
##   glide  Glider: wings out; off the web you sink slowly and carry on.
##   focus  Chrono Watch: time slows so the next web is easy to line up.
##   surge  Coin Magnet: coins pay double.
## Players only: never on the title autopilot. Timers run on real time so
## the Chrono Watch's own slow motion doesn't stretch it.

signal used(kind: String)
signal ended(kind: String)

const BOOST_FORWARD := 17.0
const BOOST_UP := 7.0
const FOCUS_SCALE := 0.4

var player: Player
var coins: CoinMeter
var rig: CharacterRig
var camera: SwingCamera
var impact_fx: ImpactFx
var audio: AudioDirector
## True while a human run is being played.
var enabled := false
var item := {}
var cooldown := 0.0
var active_t := 0.0
var _last_ms := 0


func kind() -> String:
	return item.get("kind", "")


func equip(it: Dictionary) -> void:
	if it.get("id", "") != item.get("id", ""):
		stop()
		cooldown = 0.0
	item = it


## 0..1: how charged it is (1 = ready). Full while running.
func charge() -> float:
	if active_t > 0.0:
		return 1.0
	var cd: float = item.get("cooldown", 1.0)
	return clampf(1.0 - cooldown / cd, 0.0, 1.0)


func running() -> bool:
	return active_t > 0.0


func ready_to_use() -> bool:
	return enabled and kind() != "" and cooldown <= 0.0 and active_t <= 0.0 and player != null \
		and player.bot == null and not player.stunned


func trigger() -> bool:
	if not ready_to_use():
		return false
	active_t = item.get("duration", 1.0)
	match kind():
		"boost":
			var fwd := -camera.cam.global_basis.z if camera else -player.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
			player.boost(fwd * BOOST_FORWARD + Vector3.UP * BOOST_UP)
			_sound("release_whoosh", 0.7)
			if camera:
				camera.shake(0.25)
		"glide":
			player.glide = true
			_sound("release_whoosh", 1.25)
		"focus":
			_sound("checkpoint", 0.6)
		"surge":
			if coins:
				coins.surge = true
			_sound("checkpoint", 1.35)
	if rig:
		rig.set_gadget_active(true)
	Settings.haptic(25, 0.6)
	used.emit(kind())
	return true


## Ends whatever is running (run over, respawn, gadget swapped).
func stop() -> void:
	if active_t > 0.0:
		_end()


func _end() -> void:
	var k := kind()
	active_t = 0.0
	cooldown = item.get("cooldown", 0.0)
	if player:
		player.glide = false
	if coins:
		coins.surge = false
	if k == "focus" and not (impact_fx and impact_fx.busy()):
		Engine.time_scale = 1.0
	if rig:
		rig.set_gadget_active(false)
	ended.emit(k)


func _sound(name: String, pitch: float) -> void:
	if audio:
		audio.play(name, -3.0, pitch)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := minf((now - _last_ms) / 1000.0, 0.1) if _last_ms > 0 else 0.0
	_last_ms = now
	if enabled and Input.is_action_just_pressed("gadget"):
		trigger()
	if active_t > 0.0:
		if player and player.stunned and kind() != "surge":
			_end()  # a knockout cuts it short
			return
		active_t -= dt
		if kind() == "focus" and not (impact_fx and impact_fx.busy()):
			# Ease in quickly, back out over the last half second.
			Engine.time_scale = lerpf(FOCUS_SCALE, 1.0, clampf(1.0 - active_t / 0.5, 0.0, 1.0))
		if active_t <= 0.0:
			_end()
	elif cooldown > 0.0:
		cooldown = maxf(cooldown - dt, 0.0)
