# Courier character implementation and visual review

Released as **0.17.0 (27)**, App Store Connect **VALID** on 1 November 2026:
[TestFlight workflow](https://github.com/MusaInc/CitySwing/actions/runs/41350418539),
source `66e57d4697751960356ed61ee16b4866d9d901a8`.
The subsequent branding regression run caught a remaining old shop expectation
that classic soles followed jacket colour; this was corrected to require white
trainers and independently coloured purchased soles. See the
[branding verification](qa/branding/README.md) for the retained logs and rerun.

The default hero now uses authored garment topology and UVs in place of the
previous fused primitive body. The outfit is a black hooded zip jacket with
an inner collar, graphite cargo trousers with fitted side pockets, white
trainers, full gloves, and an opaque textile mask with a smoked eye band.
A small yellow zipper pull and rear chevron provide the signature.

The jacket, trousers, footwear and gloves were adapted from licensed
MakeHuman community assets. The original meshes, UVs, fitting records,
author metadata and source textures are retained. See
[character attribution](../art/hero/CREDITS.md) and the in-game Character credits
page. [courier.blend](../art/hero/courier.blend) is the editable fitted and skinned
source; [build_character.py](../tools/blender/build_character.py) reproduces it.

The pipeline fits garments to an athletic anatomy, transfers the source skin
weights through barycentric clothing records, and retargets them to the same
17 gameplay bones. It preserves authored seams/folds, adds restrained cloth
thickness, bakes UV ambient occlusion and roughness into packed ORM textures,
and retains the source normal maps. Godot now preserves those textured PBR
surfaces. It no longer adds its emergency primitive body under a fully
skinned model. Wardrobe tint changes remain local to each actor.

Grip morphs smoothly curl either glove for running and rope contact. The
existing spring poses, ground IK, jumping, swinging, falls, landing crouches,
window moves and ragdoll/recovery remain driven by the existing gameplay
simulation. Cloth lag affects the free jacket hem without changing physics.
Default outfit IDs are retained for save compatibility.

## Real Godot captures

These are direct Godot Mobile renderer screenshots, not Blender renders or
image-generation mockups. The close-up stage uses the actual Player and
CharacterRig, and the city sequence loads the shipped main scene.

| View | Capture |
|---|---|
| Front | [Front](qa/courier/front.png) |
| Rear | [Rear](qa/courier/rear.png) |
| Side | [Side](qa/courier/side.png) |
| Three-quarter | [Three-quarter](qa/courier/threequarter.png) |
| City front / rear / side | [Front](qa/courier/city_front.png) · [Rear](qa/courier/city_rear.png) · [Side](qa/courier/city_side.png) |
| Running | [Running](qa/courier/city_running.png) |
| Swinging on a real tower anchor | [Swinging](qa/courier/city_swing_1.png) |
| Physical rooftop landing | [Landing](qa/courier/city_landing.png) |
| Starter home window | [Window](qa/courier/city_window.png) |

The previous head/torso can be compared with the
[previous in-game capture](qa/overhaul/hero-standing.png).

Visual corrections made after rendering included the mask's skull/neck
silhouette, jacket chest fit, closed inner collar, pocket placement, trainer
height, source face winding, and a fallback-body integration defect. The
shadow comparison identified stippling from the very-low shadow filter;
medium filtering and a closer near cascade make clothing readable without
adding post-processing effects.

## Budgets and limits

- 43,128 triangles; 17 gameplay bones; at most four normalized skin weights.
- Two grip morphs. The original Godot-generated mesh LODs remain enabled.
- Albedo/normal imports capped at 1024; packed ORM imports capped at 512.
- Ten mobile GPU-compressed textures, approximately 5.5 MiB including mipmaps.
- Editable source art is excluded from imports and shipping exports by
  `art/.gdignore`.

The captures run on llvmpipe software rendering. They verify the actual
asset and rendering path, not iPhone GPU performance. The existing on-device
45-second benchmark remains available in Settings. Device frame rate and
thermal performance still require an iPhone run. This implementation is a
substantial character replacement; the supplied reference's photographic
lighting and overall city fidelity are not claimed as achieved.

The final city capture recorded 96–144 draw calls and 98.7 MiB of total scene texture memory. These are scene-wide rendering resource counts, not measured phone FPS. [Raw capture metrics](qa/courier/render_metrics.json).

## Verification

- Full regression suite: **124 passed, 0 failed**. Covers traversal physics,
  planted running feet, rope-hand alignment, jumping, landings, ragdoll,
  recovery, apartments, modes, save/economy and wardrobe systems.
- Final targeted asset checks cover actual exported UVs, normalized weights,
  texture imports, actor-local tints, continuous grip morphs, mobile triangle
  budget, and independent upper/sole colours for purchased trainers.
- Shop suite: **5 passed, 0 failed**.
- Linux export and packaged resource self-test completed successfully before
  release; the check now verifies the skinned hero and named shop accessories.
- Final city capture confirms floor contact at landing and a live attached
  rope on a real tower anchor. [Metrics](qa/courier/render_metrics.json).

Logs: [full suite](qa/courier/regression-tests.log),
[asset tests](qa/courier/asset-tests.log), [shop](qa/courier/shop-tests.log),
[packaged self-test](qa/courier/packaged-selftest.log).
Godot still emits shutdown resource warnings in the full-suite/city harness;
these runs have no script/parse errors, and all test assertions pass.
