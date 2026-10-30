class_name FreeSwingMode
extends GameMode
## Explore, and hunt the tokens hidden over the city (collection persists).
## The HUD points at the nearest uncollected token.

var tokens: TokenField
var _prev := Vector3.ZERO
var _suits_before := []
var _session_tokens := 0


func mode_name() -> String:
	return "Free Swing"


func start() -> void:
	super.start()
	hud.mode_text = ""
	hud.mode_sub = ""
	hud.flash("FREE SWING", 1.6)
	_suits_before = Progress.unlocked_ids()
	if world is CityWorld:
		tokens = TokenField.new()
		tokens.name = "Tokens"
		world.add_child(tokens)
		tokens.setup((world as CityWorld).layout)
		tokens.collected.connect(_on_token)
	_prev = player.global_position


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if running and tokens:
		var p := player.global_position
		tokens.check(_prev, p)
		_prev = p


func _process(_dt: float) -> void:
	if not running:
		return
	var line := "%.1f km · %d swings" % [player.distance_travelled / 1000.0, player.swings]
	if tokens:
		var got := SaveData.token_count()
		hud.mode_text = "TOKENS %d/%d" % [got, Progress.TOKEN_TOTAL]
		hud.pointer = tokens.nearest(player.global_position)
	hud.mode_sub = line


func _on_token(_id: int, left: int) -> void:
	_session_tokens += 1
	if audio:
		audio.play("checkpoint")
	Settings.haptic(20, 0.5)
	if coins and coins.active:
		coins.bonus(CoinMeter.TOKEN_COINS)
	var fresh := Progress.newly_unlocked(_suits_before)
	if not fresh.is_empty():
		_suits_before = Progress.unlocked_ids()
		hud.flash("SUIT UNLOCKED: %s" % ", ".join(fresh).to_upper(), 2.5)
	elif left == 0:
		hud.flash("EVERY TOKEN FOUND!", 3.0)
	else:
		hud.flash("TOKEN +%d COINS  ·  %d LEFT" % [CoinMeter.TOKEN_COINS, left], 1.6)


func stop() -> void:
	var found := SaveData.token_count()
	end_run({"mode": "free", "distance": player.distance_travelled, "swings": player.swings,
		"tokens_session": _session_tokens, "tokens_total": found,
		"chain": player.best_chain, "top_speed": player.top_speed, "time": elapsed})


func _exit_tree() -> void:
	if is_instance_valid(hud):
		hud.pointer = Vector3.INF
	if tokens:
		tokens.queue_free()
