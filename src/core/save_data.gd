extends Node
## Local personal bests and lifetime statistics (user://save.json).

signal changed

const DEFAULT_PATH := "user://save.json"

## Tests point this at a scratch file so they never touch a player's records.
var path := DEFAULT_PATH
var data := {}
const DEFAULTS := {
	"best_trial_times": {},  # course id -> seconds
	"best_endurance_m": 0.0,
	"best_chain": 0,
	"total_distance_m": 0.0,
	"total_swings": 0,
	"top_speed_ms": 0.0,
	"play_time_s": 0.0,
	"tokens": [],  # collected Free Swing token ids
	"tutorial_done": false,
	"suit": "ember",
	"coins": 0,         # spendable (Shop)
	"coins_earned": 0,  # lifetime
	"best_multiplier": 1.0,
	"owned": [],        # bought Shop item ids
	"outfit": {},       # Shop slot -> item id (the suit stays in "suit")
	"homes": [],        # bought homes (Homes; the starter is always owned)
	"home": "starter",  # the home Free Swing starts in
	# Contracts (Contracts / JobBoard). Flat keys: older saves load unchanged.
	"rep": 0,           # reputation (rank ladder in Contracts.RANKS)
	"jobs_done": 0,     # contracts completed (legal + underworld)
	"jobs_crime": 0,    # of which underworld
	"jobs_failed": 0,   # out of time / busted / abandoned
	"jobs_busted": 0,
	"jobs_earned": 0,   # coins paid by contracts (net of fines)
}


func _ready() -> void:
	load_data()


func use_file(p: String) -> void:
	path = p
	load_data()


func load_data() -> void:
	data = DEFAULTS.duplicate(true)
	# The save, or – if it is missing or unreadable (the app killed mid-write
	# on an older build, a bad disk block) – the last good copy.
	for p in [path, path + ".bak"]:
		var parsed = _read(p)
		if parsed is Dictionary:
			for k in parsed:
				data[k] = parsed[k]
			if p != path:
				push_warning("SaveData: %s unreadable, recovered from backup" % path)
			_sanitise()
			return


## A readable file can still hold nonsense: wrong-typed fields go back to
## their defaults, the rest of the progress is kept (SH-03).
func _sanitise() -> void:
	SafeSave.repair(data, DEFAULTS)
	data["coins"] = maxi(0, int(data["coins"]))
	for k in ["owned", "homes"]:
		data[k] = (data[k] as Array).filter(func(x): return x is String)
	data["tokens"] = (data["tokens"] as Array).filter(func(x): return x is float or x is int)
	var best: Dictionary = data["best_trial_times"]
	for c in best.keys():
		if not ((best[c] is float or best[c] is int) and is_finite(float(best[c])) and float(best[c]) > 0.0):
			best.erase(c)
	if not (data["home"] is String) or (data["home"] != "starter" and not (data["home"] in data["homes"])):
		data["home"] = "starter"


static func _read(p: String):
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary and not (parsed as Dictionary).is_empty() else null


## Atomic save: write a temp file, check it reads back, keep the previous save
## as .bak, then move the new one into place. A crash or the OS killing the
## app at any point leaves a complete save (or its backup) on disk.
func save() -> void:
	# (SafeSave: read-back check, only a valid file becomes .bak, every rename
	# and copy checked.)
	last_error = SafeSave.write(path, data)
	if last_error != "":
		push_warning("SaveData: save failed – %s; keeping the old save" % last_error)
	changed.emit()


## "" after a good save, else why it failed.
var last_error := ""


## Returns true if `seconds` is a new best for the course.
func submit_trial(course: String, seconds: float) -> bool:
	var best = data["best_trial_times"].get(course, INF)
	if seconds < best:
		data["best_trial_times"][course] = seconds
		save()
		return true
	return false


func best_trial(course: String) -> float:
	return data["best_trial_times"].get(course, INF)


func submit_endurance(metres: float) -> bool:
	if metres > data["best_endurance_m"]:
		data["best_endurance_m"] = metres
		save()
		return true
	return false


func add_stats(distance: float, swings: int, top_speed: float, chain: int, seconds: float) -> void:
	data["total_distance_m"] += distance
	data["total_swings"] += swings
	data["top_speed_ms"] = maxf(data["top_speed_ms"], top_speed)
	data["best_chain"] = maxi(data["best_chain"], chain)
	data["play_time_s"] += seconds
	save()


## Returns true the first time a token is collected.
func collect_token(id: int) -> bool:
	if has_token(id):
		return false
	data["tokens"].append(id)
	save()
	return true


func has_token(id: int) -> bool:
	# JSON round-trips ints as floats.
	for t in data["tokens"]:
		if int(t) == id:
			return true
	return false


func token_count() -> int:
	return data["tokens"].size()


func complete_tutorial() -> void:
	if not data["tutorial_done"]:
		data["tutorial_done"] = true
		save()


## Banks coins in memory; `save()` (or the next save) writes them out.
func add_coins(n: int) -> void:
	data["coins"] = int(data["coins"]) + n
	data["coins_earned"] = int(data["coins_earned"]) + n


## Records a settled contract: coins (may be a fine), reputation, counters.
## A fine never takes the balance below zero.
func record_job(legal: bool, outcome: String, coins: int, rep: int) -> int:
	if coins < 0:
		coins = -mini(-coins, int(data["coins"]))
		data["coins"] = int(data["coins"]) + coins
	elif coins > 0:
		add_coins(coins)
	data["jobs_earned"] = int(data.get("jobs_earned", 0)) + coins
	data["rep"] = int(data.get("rep", 0)) + rep
	if outcome == "done":
		data["jobs_done"] = int(data.get("jobs_done", 0)) + 1
		if not legal:
			data["jobs_crime"] = int(data.get("jobs_crime", 0)) + 1
	else:
		data["jobs_failed"] = int(data.get("jobs_failed", 0)) + 1
		if outcome == "busted":
			data["jobs_busted"] = int(data.get("jobs_busted", 0)) + 1
	save()
	return coins


func set_suit(id: String) -> void:
	data["suit"] = id
	save()
