class_name FreeSwingMode
extends GameMode
## No objectives: explore. Shows the current chain and lifetime totals.


func mode_name() -> String:
	return "Free Swing"


func start() -> void:
	super.start()
	hud.mode_text = ""
	hud.mode_sub = ""
	hud.flash("FREE SWING", 1.6)


func _process(_dt: float) -> void:
	if running:
		hud.mode_sub = "%.1f km travelled · %d swings" % [player.distance_travelled / 1000.0, player.swings]


func stop() -> void:
	end_run({"mode": "free", "distance": player.distance_travelled, "swings": player.swings,
		"chain": player.best_chain, "top_speed": player.top_speed, "time": elapsed})
