# City Swing identity

![Identity sheet](brand_sheet.png)

The main menu sets the visual language: Outfit lettering, Signal Gold actions,
warm white text and Night Ink. The city and player provide the imagery.
The launch artwork uses the same restrained palette, without the old cartoon
hero, sun, outlined lettering or coloured gradients.

## Logo and icon

An open gold C describes a swinging arc; a rising white cable ends at an anchor.
The lockup pairs this ascent mark with upright CITY / SWING lettering. It appears
at bottom left in the live title and main menu. The app icon uses the same mark
on an opaque Night Ink square, with generous space for platform corner masks.
The horizontal wordmark is available for wider placements.

| Colour | Hex | Use |
|---|---|---|
| Signal Gold | `#FFC93C` | Mark, SWING, primary actions and focus |
| Web White | `#F7F3EA` | CITY, cable, primary text |
| Night Ink | `#110D26` | Launch background, menu shading |

Outfit Black is used for the logo and titles, Bold for actions, SemiBold for
supporting text. The existing licensed fonts live in `assets/fonts`.
Gameplay's teal collectibles and red warnings retain their existing meanings.

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

Run `node tools/brand/render.mjs`, or append an asset name to render just that
asset. This uses the existing Playwright renderer; set `PLAYWRIGHT` to override
its local module location. No remote fonts, stock artwork or generated imagery.

| Asset | Source | Runtime output |
|---|---|---|
| App icon | `tools/brand/icon.svg` | `assets/icon_1024.png`, `assets/icon.png` |
| Ascent mark | `tools/brand/mark.svg` | `assets/brand/mark.png` |
| Logos | `tools/brand/wordmark.js`, HTML wrappers | `assets/brand/wordmark*.png` |
| Boot artwork | `tools/brand/splash.html` | `assets/brand/splash.png` |
| Identity sheet | `tools/brand/sheet.html` | `docs/brand_sheet.png` |

Preserve flat colours and the authored clear space. Do not add shadows, outlines,
character illustrations or gradients to the logo. Update the shared symbol
geometry in mark, icon and wordmark together.

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
