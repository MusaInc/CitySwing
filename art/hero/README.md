# CitySwing Courier

The hero is built from the MakeHuman body itself: skin-tight compression
tops (long, three-quarter, short, sleeveless) cut from the skin with clean
plane-cut hems, a knitted mock neck, contrast side panels and bare skin
where the sleeves end; five faces (Kai, Ade, Ren, Theo, Malik) shaped with
MakeHuman's facial targets, each with eyes, lashes, brows and short hair cut
from the scalp; five fitted masks (Courier, Runner, Domino, Balaclava,
Respirator); cargo pants, trainers and gloves as before. Everything ships in
one GLB; the game shows the chosen variants (CharacterRig._show_variants)
and tints skin, hair, eyes and the top (Shop "hero", "top", "suit", "face").

Where download.blender.org is unreachable, the PyPI `bpy==4.5.3` module
(Python 3.11) runs the same scripts; any `blender` on PATH that accepts
`-b --python script -- args` works.

Rebuild with Blender 4.5:

```
blender -b --factory-startup --python tools/blender/build_character.py -- assets/models
godot --headless --editor --import --quit
```

`courier.blend` is the editable fitted and skinned character. `sources/` retains
original author assets, fitting records, UVs, textures and attribution. The
build script adapts the anatomy and garment fit, transfers skin weights,
creates glove grip morphs, bakes packed occlusion/roughness/metallic maps,
and exports the same 17-bone skeleton the gameplay animation drives.

`art/.gdignore` keeps source art out of Godot imports and shipping packages.
The GLB embeds textures; Godot extracts them as `assets/models/character_*.png`.
Their committed `.import` files enable GPU compression, mipmaps and size limits
(1024 for colour/normal, 512 for ORM). Keep those settings on regeneration.

Default outfit IDs remain `ember`, `pants_navy`, `shoes_classic`, and
`gloves_black` for save compatibility. Their display names/colours now describe
the Courier outfit. Shop recolouring uses instance-local PBR material tints.

Visual review:

```
xvfb-run -a godot --rendering-method mobile --resolution 960x800 --fixed-fps 30 -s res://tools/pose_lab.gd -- screenshots/courier/review review
xvfb-run -a godot --rendering-method mobile --resolution 1280x960 --fixed-fps 30 -s res://tools/hero_city_lab.gd -- --mode=free --seed=9137 --quality=2 --time=15 --weather=clear --save=user://hero_capture.json
```

Sources and licences: [CREDITS.md](CREDITS.md).
