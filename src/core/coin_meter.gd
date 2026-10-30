class_name CoinMeter
extends Node
## Coins for swinging. Every metre covered off the ground (on a web or flying
## between webs) pays a trickle of coins, times the multiplier. The
## multiplier starts at ×1 and climbs a step for every LEVEL_METRES swung
## (a perfect release pushes it along) – until a wall knockout, which drops
## it straight back to ×1. Coins bank as they're earned; the save file is
## written every few seconds and when the run ends.

signal earned(n: int)
## up = climbed a step; otherwise it was lost (`from` = the multiplier lost).
signal multiplier_changed(mult: float, up: bool, from: float)

const METRES_PER_COIN := 25.0
const LEVEL_METRES := 120.0
const PERFECT_METRES := 40.0
const STEP := 0.5
const MAX_MULT := 10.0
const MAX_LEVEL := int((MAX_MULT - 1.0) / STEP)
const SAVE_EVERY := 8.0
## Tokens found in Free Swing (first time) pay a flat bonus.
const TOKEN_COINS := 100

var player: Player
## Only true in a human-played run (not the title autopilot or benchmark).
var active := false
var level := 0
var progress := 0.0   # metres toward the next step
var run_coins := 0
var best_mult := 1.0
## Coin Magnet gadget running: payouts doubled (the multiplier itself is
## unchanged).
var surge := false
var _frac := 0.0
var _last_dist := 0.0
var _dirty_t := 0.0


func set_player(p: Player) -> void:
	player = p
	p.knockout.connect(func(_s, _n): lose())
	p.perfect_release.connect(func(_streak): if active: _advance(PERFECT_METRES))


func multiplier() -> float:
	return minf(1.0 + level * STEP, MAX_MULT)


## 0..1 toward the next step (1 at the cap).
func level_progress() -> float:
	return 1.0 if level >= MAX_LEVEL else progress / LEVEL_METRES


func start_run() -> void:
	level = 0
	progress = 0.0
	run_coins = 0
	best_mult = 1.0
	_frac = 0.0
	_last_dist = player.distance_travelled if player else 0.0
	active = true


func stop_run() -> void:
	active = false
	surge = false
	flush()


func flush() -> void:
	if _dirty_t > 0.0:
		_dirty_t = 0.0
		SaveData.save()


func lose() -> void:
	if not active:
		return
	var was := multiplier()
	level = 0
	progress = 0.0
	if was > 1.0:
		multiplier_changed.emit(1.0, false, was)


## Pays for `metres` swung and moves the multiplier along.
func swing(metres: float) -> void:
	if metres <= 0.0:
		return
	_frac += metres / METRES_PER_COIN * multiplier() * (2.0 if surge else 1.0)
	var n := int(_frac)
	if n > 0:
		_frac -= n
		bonus(n)
	_advance(metres)


func bonus(n: int) -> void:
	run_coins += n
	SaveData.add_coins(n)
	_dirty_t = maxf(_dirty_t, 0.001)
	earned.emit(n)


func _advance(metres: float) -> void:
	if level >= MAX_LEVEL:
		return
	progress += metres
	while progress >= LEVEL_METRES and level < MAX_LEVEL:
		progress -= LEVEL_METRES
		level += 1
		best_mult = maxf(best_mult, multiplier())
		if best_mult > float(SaveData.data.get("best_multiplier", 1.0)):
			SaveData.data["best_multiplier"] = best_mult
		multiplier_changed.emit(multiplier(), true, multiplier() - STEP)
	if level >= MAX_LEVEL:
		progress = 0.0


func _physics_process(dt: float) -> void:
	if player == null:
		return
	var d := player.distance_travelled
	var moved := d - _last_dist
	_last_dist = d
	if not active:
		return
	if _dirty_t > 0.0:
		_dirty_t += dt
		if _dirty_t > SAVE_EVERY:
			flush()
	# Swinging and flying count; running, standing and lying in a heap don't.
	if player.stunned or player.is_on_floor() or moved <= 0.0 or moved > 20.0:
		return
	swing(moved)
