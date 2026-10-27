extends Node
## Local personal bests and lifetime statistics (user://save.json).

signal changed

const PATH := "user://save.json"

var data := {
	"best_trial_times": {},  # course id -> seconds
	"best_endurance_m": 0.0,
	"best_chain": 0,
	"total_distance_m": 0.0,
	"total_swings": 0,
	"top_speed_ms": 0.0,
	"play_time_s": 0.0,
}


func _ready() -> void:
	load_data()


func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed:
			data[k] = parsed[k]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
	changed.emit()


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
