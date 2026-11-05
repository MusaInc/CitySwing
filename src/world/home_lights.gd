extends Node3D
## A home's lamps follow the day: at dusk and at night (Atmosphere.night)
## they come up, so the flat glows warm against the dark city instead of
## going dim with the sky. Each OmniLight3D keeps its daytime energy in meta.

var _t := 0.0


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 1.0
	var atmo := get_tree().get_first_node_in_group("atmosphere")
	var night: float = atmo.night if atmo else 0.0
	var k := 1.0 + 1.6 * night
	for c in get_children():
		if c is OmniLight3D and c.has_meta("base"):
			(c as OmniLight3D).light_energy = float(c.get_meta("base")) * k
