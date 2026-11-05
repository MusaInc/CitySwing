# CitySwing identity — "Sunset Swing" (v3, 2026-11-05)

![Identity sheet](brand_sheet.png)

**Why it changed.** The v1 mark (a gold open "C" with a white stick) read as a
power button or a settings dial: nothing in it said city, character or
swinging, so the icon under-sold the game in App Store charts.

**Directions considered.** (1) *Hero in the Arc* – the real hero mid-swing,
the real dusk skyline, the gold swing arc. (2) *Skyline Arc* – symbol over a
stylised skyline (elegant, but the hero vanishes at small sizes). (3) *Masked
Portrait* – a close-up of the mask (superhero-poster feel; the mask is only one
of nine face options). **Chosen: 1** – most readable at 40 px and the most
truthful: every raster comes from the game.

**Truthfulness rule.** Brand art is rendered by the game: the hero
(`tools/brand/hero_render.gd`: the real CharacterRig and default look, flown by
the real swing physics on a real web, transparent background, studio key +
Signal Gold rim) and the city (`tools/store_shots.sh --cam … --nohud`: the
downtown towers at sunset from street level). No stock art, no painted
character, no effects the game doesn't have.

## The system

| Asset | Source | Output |
|---|---|---|
| App icon | `tools/brand/icon_compose.py` (art/skyline_sea.png, art/hero_swing.png) | `assets/icon_1024.png`, `assets/icon.png` (256, web) |
| Emblem | `tools/brand/mark.html` → `wordmark.js` `emblemSVG()` (art/hero_silhouette_ink.png) | `assets/brand/mark.png` |
| Wordmark | `wordmark.html` → `drawWordmark({horizontal})` | `assets/brand/wordmark.png` |
| Lockup (title, splash) | `wordmark_stacked.html` → `drawWordmark()` | `assets/brand/wordmark_stacked.png` |
| Boot artwork | `splash.html` (real towers, deep-graded) | `assets/brand/splash.png` |
| Sheet | `sheet.html` | `docs/brand_sheet.png` |

* **Icon (v3):** a hard-edged sunset disc behind the real downtown skyline
  (rendered from the sea at sunset; the sky is keyed out column by column so
  the sun sits behind the towers, which go to near-silhouette with their lit
  windows), and the hero crossing the disc in silhouette, white web line out of
  frame. Reads at 40 px: one bold disc, one figure.
* **Wordmark:** one word, CITYSWING – Outfit Black skewed −10°, CITY Web White,
  SWING Signal Gold; the swing path runs under the word and rises to a web
  anchor after the G (never through the letters).
* **Emblem:** the icon reduced – the hero's silhouette (render alpha, Night
  Ink) inside the gold sun disc, the white web line breaking out to its anchor
  dot. Legible down to ~40 px.
* **Title screen:** lockup bottom-left over the live cinematics (nine 12 s
  shots of the real game) on a soft Night Ink pool; gold actions on the right.

Palette: Signal Gold `#FFC93C` (action, arc), Web White `#F7F3EA` (type, web),
Night Ink `#110D26` (ground); Sunset `#FF9A4D` only as light.

## Startup

`project.godot` uses `assets/brand/splash.png` for the engine boot image. The iOS
storyboard inherits this image and aspect-fit behaviour from the boot settings
(`storyboard/image_scale_mode=0`); its background matches Night Ink. This follows
[Godot 4.5.1's iOS exporter](https://github.com/godotengine/godot/blob/4.5.1-stable/platform/ios/export/export_plugin.cpp).

`scenes/boot.tscn` displays the same image before requesting the main scene's
resources in the background. A thin gold bar reports resource-loader progress.
The label then switches to “PREPARING STREETS” while the existing synchronous
city construction runs; no fabricated percentage is shown for this phase.
The overlay fades away after the game scene initializes. Failure leaves a
readable retry action. Desktop shows “PRESS TO START”; touch devices show
“TAP TO START”. The title retains keyboard, controller and full-screen tap input.

## Editable sources

`node tools/brand/render.mjs [asset]` renders everything above (Playwright;
set `PLAYWRIGHT` to override the module). Re-shoot the art with:

```sh
xvfb-run -a -s "-screen 0 1400x1400x24" godot --rendering-method mobile \
  --resolution 1024x1024 --fixed-fps 60 -s res://tools/brand/hero_render.gd -- <dir>
bash tools/store_shots.sh <dir> 1024x1024 sky "4" --mode=free --time=18.4 \
  --weather=clear --seed=3 --cam=640,30,-80,560,280,-160 --fov=62 --nohud
```

## Verification

`tools/brand_review.gd` boots the real game, captures loading/title/menu frames,
checks that the overlay is freed and the game becomes the active scene, sends
keyboard input to start, then pointer input to Play. Run it with a scratch save:

```sh
xvfb-run -a godot --rendering-method mobile --resolution 1280x720 \
  --fixed-fps 30 -s res://tools/brand_review.gd -- \
  --time=17 --weather=clear --seed=9137 --save=user://branding_capture.json
```

Add `--brand-out=res://docs/qa/branding/tablet` to capture another aspect ratio.
Screenshots and verification logs are in `docs/qa/branding`.
