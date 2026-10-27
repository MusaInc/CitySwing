class_name GameMode
extends Node
## Base for Free Swing / Time Trial / Endurance. A mode owns its HUD text,
## decides when a run ends, and records personal bests via SaveData.

signal finished(result: Dictionary)

var player: Player
var hud: Hud
var audio: AudioDirector
var world: Node3D
var elapsed := 0.0
var running := false


func setup(p: Player, h: Hud, a: AudioDirector, w: Node3D) -> void:
	player = p
	hud = h
	audio = a
	world = w
	player.reset_stats()
	player.landed.connect(_on_landed)
	player.respawned.connect(_on_respawned)


func mode_name() -> String:
	return ""


func start() -> void:
	running = true
	elapsed = 0.0


func _physics_process(dt: float) -> void:
	if running:
		elapsed += dt
		if world and world.has_method("is_water") and player.global_position.y < -0.5 \
				and world.is_water(player.global_position):
			if audio:
				audio.play("splash")
			_on_water()


func _on_landed(_speed: float, _street: bool) -> void:
	pass


func _on_respawned() -> void:
	pass


func _on_water() -> void:
	player.respawn()


func end_run(result: Dictionary) -> void:
	if not running:
		return
	running = false
	SaveData.add_stats(player.distance_travelled, player.swings, player.top_speed, player.best_chain, elapsed)
	finished.emit(result)
