class_name TrainingMode
extends GameMode
## Guided first session: one instruction at a time, each completed by doing
## it for real. Falling or touching the street never fails a step, it just
## waits; the run ends when every step is done.

const STEPS := [
	{"id": "web", "title": "Fire a web",
		"touch": "Hold SWING to shoot a web at a building ahead",
		"keys": "Hold SPACE or the left mouse button to shoot a web at a building ahead"},
	{"id": "release", "title": "Let go and fly",
		"touch": "Swing through the bottom, then lift your finger to let go",
		"keys": "Swing through the bottom, then let go of SPACE to fly"},
	{"id": "chain", "title": "Catch the next web",
		"touch": "While flying, hold SWING again to catch another building",
		"keys": "While flying, hold SPACE again to catch another building"},
	{"id": "chain4", "title": "Build a chain",
		"touch": "Chain 4 swings without touching the ground. Steer with the left stick",
		"keys": "Chain 4 swings without touching the ground. Steer with WASD"},
	{"id": "trick", "title": "Jump in the air",
		"touch": "Tap JUMP in mid-air to flip, or next to a wall to kick off it",
		"keys": "Press SHIFT in mid-air to flip, or next to a wall to kick off it"},
	{"id": "speed", "title": "Pick up speed",
		"touch": "Hit 90 km/h: let go just past the bottom of each swing",
		"keys": "Hit 90 km/h: let go just past the bottom of each swing"},
	{"id": "roof", "title": "Stick the landing",
		"touch": "Land on any rooftop",
		"keys": "Land on any rooftop"},
]
const SPEED_GOAL := 25.0  # m/s (90 km/h)

var step := 0
var touch := false
var _hold := 0.0  # short pause between steps so each "done" registers


func mode_name() -> String:
	return "Training"


func start() -> void:
	super.start()
	step = 0
	player.attached.connect(func(_a): _event("web"))
	player.released.connect(func(_v): _on_release())
	player.trick.connect(func(): _event("trick"))
	player.wall_kicked.connect(func(): _event("trick"))
	hud.flash("TRAINING", 1.6)
	_show()


func _on_release() -> void:
	_event("release")
	if player.chain >= 2:
		_event("chain")
	if player.chain >= 4:
		_event("chain4")


func _on_landed(_speed: float, street: bool) -> void:
	# landed fires before Player resets air_time, so this is the flight that just ended.
	if running and not street and player.air_time > 1.0:
		_event("roof")


func _event(id: String) -> void:
	if not running or _hold > 0.0 or step >= STEPS.size() or STEPS[step]["id"] != id:
		return
	_advance()


func _advance() -> void:
	step += 1
	Settings.haptic(15, 0.4)
	if step >= STEPS.size():
		_finish()
		return
	if audio:
		audio.play("checkpoint")
	hud.flash("NICE!", 0.9)
	_hold = 0.9
	_show()


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if not running:
		return
	_hold = maxf(_hold - dt, 0.0)
	if _hold <= 0.0 and step < STEPS.size() and STEPS[step]["id"] == "speed" and player.speed() >= SPEED_GOAL:
		_advance()


func _show() -> void:
	var s: Dictionary = STEPS[step]
	hud.mode_text = "%d/%d  %s" % [step + 1, STEPS.size(), s["title"]]
	hud.mode_sub = ""
	hud.hint = s["touch"] if touch else s["keys"]


func _on_water() -> void:
	player.respawn()


func _finish() -> void:
	if not running:
		return
	hud.hint = ""
	SaveData.complete_tutorial()
	if audio:
		audio.play("finish")
	end_run({"mode": "training", "steps": step, "swings": player.swings, "chain": player.best_chain,
		"top_speed": player.top_speed, "time": elapsed})


func _exit_tree() -> void:
	if is_instance_valid(hud):
		hud.hint = ""
