extends Node
## Registers keyboard/mouse and gamepad bindings in code so project.godot stays
## readable. Touch input is handled by TouchControls, which writes into the same
## actions through Input.action_press/release.

const BINDINGS := {
	"move_forward": [KEY_W, JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [KEY_S, JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [KEY_A, JOY_AXIS_LEFT_X, -1.0],
	"move_right": [KEY_D, JOY_AXIS_LEFT_X, 1.0],
	"look_up": [KEY_UP, JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [KEY_DOWN, JOY_AXIS_RIGHT_Y, 1.0],
	"look_left": [KEY_LEFT, JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [KEY_RIGHT, JOY_AXIS_RIGHT_X, 1.0],
	"grapple": [KEY_SPACE, JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"reel_in": [KEY_E, JOY_BUTTON_RIGHT_SHOULDER],
	"reel_out": [KEY_Q, JOY_BUTTON_LEFT_SHOULDER],
	"jump": [KEY_SHIFT, JOY_BUTTON_A],
	"respawn": [KEY_R, JOY_BUTTON_Y],
	"pause": [KEY_ESCAPE, JOY_BUTTON_START],
	"toggle_debug": [KEY_F3, JOY_BUTTON_BACK],
}


func _ready() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		var b: Array = BINDINGS[action]
		var key := InputEventKey.new()
		key.physical_keycode = b[0]
		InputMap.action_add_event(action, key)
		if b.size() == 3:
			var axis := InputEventJoypadMotion.new()
			axis.axis = b[1]
			axis.axis_value = b[2]
			InputMap.action_add_event(action, axis)
		else:
			var btn := InputEventJoypadButton.new()
			btn.button_index = b[1]
			InputMap.action_add_event(action, btn)
	if DisplayServer.is_touchscreen_available():
		# Menus are Godot GUI controls, which only react to mouse events: let
		# taps emulate the mouse. Gameplay touches go through TouchControls, so
		# a mouse-button grapple binding would fire the rope on every menu tap.
		Input.emulate_mouse_from_touch = true
	else:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("grapple", mouse)
