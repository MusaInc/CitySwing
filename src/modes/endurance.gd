class_name EnduranceMode
extends GameMode
## Travel as far as possible without touching the street (or the water).
## Rooftops are fine – but standing still on one for 4 s also ends the run,
## so it stays a test of swinging, not of walking.

const ROOF_IDLE_LIMIT := 4.0

var distance := 0.0
var _last := Vector3.ZERO
var _idle := 0.0


func mode_name() -> String:
	return "Endurance"


func start() -> void:
	super.start()
	distance = 0.0
	_last = player.global_position
	hud.flash("ENDURANCE", 1.6)


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if not running:
		return
	var p := player.global_position
	distance += Vector2(p.x - _last.x, p.z - _last.z).length()
	_last = p
	if player.is_on_floor() and player.speed() < 2.0:
		_idle += dt
		if _idle > ROOF_IDLE_LIMIT:
			_finish("Stalled on a rooftop")
	else:
		_idle = 0.0
	hud.mode_text = "%d m" % int(distance)
	var best: float = SaveData.data["best_endurance_m"]
	hud.mode_sub = "best %d m%s" % [int(best), "  ·  stalling!" if _idle > 1.5 else ""]


func _on_landed(_speed: float, street: bool) -> void:
	if running and street:
		_finish("Touched the street")


func _on_water() -> void:
	_finish("Into the river")


func _on_respawned() -> void:
	if running:
		_finish("Fell")


func _finish(reason: String) -> void:
	if not running:
		return
	var best := SaveData.submit_endurance(distance)
	if audio:
		audio.play("finish" if best else "fail")
	end_run({"mode": "endurance", "distance": distance, "reason": reason, "new_best": best,
		"best": SaveData.data["best_endurance_m"], "swings": player.swings, "chain": player.best_chain,
		"top_speed": player.top_speed, "time": elapsed})
