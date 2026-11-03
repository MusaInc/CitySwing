extends SceneTree
## Prints the street level (layout.ground_y) at x,z pairs, for placing
## capture cameras relative to the ground.
##   godot --headless -s res://tools/ground_probe.gd -- x,z x,z ...

func _initialize() -> void:
	var l := CityLayout.new().generate()
	for a in OS.get_cmdline_user_args():
		var v := a.split_floats(",")
		print("GROUND %s,%s %.1f" % [v[0], v[1], l.ground_y(v[0], v[1])])
	quit()
