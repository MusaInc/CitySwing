extends SceneTree
## Wardrobe review: the hero, idle, under the game's light, dressed in each
## face, top and mask (tiles saved to <outdir>/<set>_<i>.png).
##   xvfb-run -a godot --rendering-method mobile --resolution 640x720 --fixed-fps 30 \
##     -s res://tools/wardrobe_lab.gd -- <outdir> [faces|tops|masks|hats|hair|hairback|hairhats|torso|feet]

var SETS := {
	"faces": [{"hero": "hero_kai"}, {"hero": "hero_ade"}, {"hero": "hero_ren"}, {"hero": "hero_theo"}, {"hero": "hero_malik"}],
	"tops": [{"top": "top_long"}, {"top": "top_tq", "suit": "tangerine"}, {"top": "top_short", "suit": "sky"},
		{"top": "top_vest", "suit": "graphite", "hero": "hero_ade"}],
	"masks": [{"face": "mask_courier"}, {"face": "mask_runner"}, {"face": "mask_domino"}, {"face": "mask_balaclava"},
		{"face": "mask_respirator"}, {"face": "face_mask", "suit": "tangerine"}, {"face": "face_mask", "hero": "hero_ade", "suit": "sky"}],
	"torso": [{"top": "top_tq", "suit": "tangerine"}, {"top": "top_short", "suit": "sky"}],
	"feet": [{}, {"top": "top_short", "pants": "pants_white", "shoes": "shoes_blackout"}, {"pants": "pants_khaki", "shoes": "shoes_gum"}],
	"hair": _hair_set(),
	"hairback": _hair_set(),
	"hairtheo": _hair_set("hero_theo"),
	"hairtheoback": _hair_set("hero_theo"),
	"hairhats": [{"face": "face_none", "hair": "hair_bob", "head": "head_cap"},
		{"face": "face_none", "hair": "hair_ponytail", "head": "head_cap", "hero": "hero_ade"},
		{"face": "face_none", "hair": "hair_curls", "head": "head_phones"},
		{"face": "face_none", "hair": "hair_bun", "head": "head_crown", "hero": "hero_theo"},
		{"face": "face_shades", "hair": "hair_pixie", "hero": "hero_ren"},
		{"face": "face_visor", "hair": "hair_fade", "hero": "hero_malik"}],
	"hats": [{"head": "head_cap"}, {"head": "head_beanie"}, {"head": "head_phones"}, {"face": "face_shades"}, {"face": "face_visor"}],
}


## Every cut on its own, on a mix of faces (no mask, so the hair shows).
static func _hair_set(only := "") -> Array:
	var heroes := [only] if only != "" else ["hero_kai", "hero_ade", "hero_ren", "hero_theo", "hero_malik"]
	var out := []
	var k := 0
	for st: String in ["buzz", "crop", "fade", "curls", "pixie", "bob", "ponytail", "bun"]:
		out.append({"face": "face_none", "hair": "hair_" + st, "hero": heroes[k % heroes.size()]})
		k += 1
	return out


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "screenshots/wardrobe"
	var which: String = args[1] if args.size() > 1 else "faces"
	DirAccess.make_dir_recursive_absolute(out)
	var atmo := Atmosphere.new()
	root.add_child(atmo)
	var stage := Node3D.new()
	root.add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(200, 1, 200), Color(0.42, 0.43, 0.45), false, true)
	PrototypeWorld.add_box(stage, Vector3(0, 30, -30), Vector3(40, 60, 4), Color(0.62, 0.6, 0.57))
	var player := Player.new()
	player.params = load("res://config/swing_params.tres").duplicate()
	player.input_enabled = false
	root.add_child(player)
	player.respawn(Vector3(0, 0.95, 0))
	var rig := CharacterRig.new()
	player.add_child(rig)
	rig.set_player(player)
	rig.set_facing(Vector3.BACK)
	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	cam.make_current()
	var close := which in ["faces", "masks", "hats", "hair", "hairback", "hairhats", "hairtheo", "hairtheoback"]
	var mid := which == "torso"
	var feet := which == "feet"
	var look_at := player.global_position + Vector3(0, 0.78 if close else (0.35 if mid else (-0.72 if feet else 0.05)), 0)
	var view := Vector3(0.75, 0.12, -1.4) if which.ends_with("back") else Vector3(0.55, 0.05, 1.45)
	cam.global_position = look_at + view * (1.0 if close else (1.9 if mid else (0.75 if feet else 3.4)))
	cam.look_at(look_at, Vector3.UP)
	var i := 0
	for preview: Dictionary in SETS[which]:
		rig.apply_look(Shop.look(preview))
		for f in 24:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%d.png" % [out, which, i])
		i += 1
	print("WARDROBE ", which, " ", i)
	quit()
