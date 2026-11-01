extends CanvasLayer
## Small launch scene: display branding before loading the game scene. The
## resource loader owns progress; world construction keeps its own honest stage.
## No dependency on Main/MenuParts: those pull in the city and hero resources.

@export var scene_path := "res://scenes/main.tscn"
@export var auto_start := true
var surface: Control
var status: Label
var progress: ProgressBar
var retry: Button
var _requested := false
var _finishing := false
var _starting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	_build_view()
	if auto_start:
		_begin.call_deferred()


func _build_view() -> void:
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(surface)
	var bg := ColorRect.new()
	bg.color = Color("110D26")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(bg)
	var art := TextureRect.new()
	art.texture = preload("res://assets/brand/splash.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(art)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -160
	box.offset_right = 160
	box.offset_top = -105
	box.offset_bottom = -45
	box.add_theme_constant_override("separation", 12)
	surface.add_child(box)
	status = Label.new()
	status.text = "LOADING CITY"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_override("font", preload("res://assets/fonts/outfit_semibold.ttf"))
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("a6a2b1"))
	box.add_child(status)
	progress = ProgressBar.new()
	progress.max_value = 1.0
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(320, 2)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("FFC93C")
	progress.add_theme_stylebox_override("background", track)
	progress.add_theme_stylebox_override("fill", fill)
	box.add_child(progress)
	retry = Button.new()
	retry.text = "Try again"
	retry.visible = false
	retry.add_theme_font_override("font", preload("res://assets/fonts/outfit_bold.ttf"))
	retry.add_theme_color_override("font_color", Color("FFC93C"))
	retry.pressed.connect(_begin)
	box.add_child(retry)


func _begin() -> void:
	if _requested or _finishing or _starting:
		return
	_starting = true
	retry.hide()
	progress.show()
	progress.value = 0
	status.text = "LOADING CITY"
	# Let the branded frame reach the display before requesting heavier assets.
	await get_tree().process_frame
	await get_tree().process_frame
	var err := ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if err != OK:
		_failed()
		return
	_requested = true
	_starting = false


func _process(_delta: float) -> void:
	if not _requested or _finishing:
		return
	var amount: Array = []
	var state := ResourceLoader.load_threaded_get_status(scene_path, amount)
	if not amount.is_empty():
		progress.value = float(amount[0])
	match state:
		ResourceLoader.THREAD_LOAD_LOADED:
			_finishing = true
			_open_city()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_failed()


func _open_city() -> void:
	status.text = "PREPARING STREETS"
	progress.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		_failed()
		return
	var game := packed.instantiate()
	if game == null:
		_failed()
		return
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	status.text = ""
	# Includes Main._ready and deferred city work. Input stays covered until
	# the loaded world has had a chance to render beneath the fade.
	await get_tree().process_frame
	await get_tree().process_frame
	var fade := create_tween()
	fade.tween_property(surface, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	await fade.finished
	queue_free()


func _failed() -> void:
	_requested = false
	_finishing = false
	_starting = false
	status.text = "Couldn't load the city. Please try again."
	progress.hide()
	retry.show()
	retry.grab_focus()
