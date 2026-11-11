class_name LensFx
extends CanvasLayer
## Fisheye at the screen edges (lens.gdshader) between the 3D world and the
## HUD: layer -1 draws after the 3D image and before every UI layer (≥ 0).
## SwingCamera feeds it speed; the bend widens a touch as you go faster.

const BASE := 0.045
const FAST := 0.05   # extra at full swing speed

var _rect: ColorRect
var _mat: ShaderMaterial
var _speed := 0.0


func _ready() -> void:
	layer = -1
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/ui/shaders/lens.gdshader")
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	get_viewport().size_changed.connect(_on_size)
	_on_size()
	_apply()


func _on_size() -> void:
	var s := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", s.x / maxf(s.y, 1.0))


## 0..1 swing speed (smoothed here).
func set_speed(amount: float, dt: float) -> void:
	_speed = lerpf(_speed, clampf(amount, 0.0, 1.0), 1.0 - exp(-3.0 * dt))
	_apply()


func _apply() -> void:
	_mat.set_shader_parameter("strength", BASE + FAST * _speed)
