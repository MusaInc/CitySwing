# Visual QA – v0.14.0 (2026-11-01)

Every image below was rendered by the real game (Mobile renderer under Xvfb, software Vulkan) and opened and inspected during the pass. Device rendering (iPhone/iPad GPU) was not available.

| Area | Before | After | Notes |
|---|---|---|---|
| Gameplay HUD | `hud_before.png` (TOKENS 0/40 banner, km/swings line) | `hud_minimap_gameplay.png`, `minimap_closeup.png` | Banner removed. The minimap is baked from the real layout: roads, blocks, parks, footprints shaded by height, water, bridge and mainland. Forward is up; north tick; nearest token pinned to the rim. |
| Main menu | `menu_before.png` (splash with large logo) | `menu_after.png` | Minimal top-right column, small wordmark bottom-left, hero framed in the open left half. |
| Cinematic backdrops | – | `menu_cinematic_shots.jpg` (rows: golden hour, canyon, skyline, momentum, rooftops; 3 frames each) | First pass rejected: hero tiny or missing, walls filling the frame. Fixed with offset-relative smoothing, open-side selection and lens-shift composition. Momentum reworked from a front view (hero not visible) to a rear three-quarter chase. |
| Shop | `shop_before.png` (text cards, swinging background) | `shop_hoodies.png`, `shop_shoes_gadgets.png` | Category sidebar, thumbnails rendered from the character model, live rooftop preview with category framing, one action per item, buying needs a confirming tap. |
| Other screens | – | `screens_pause_results_stats_settings.jpg` | Same heading style, glass cards and gold primary action. |
| Aspect ratios | – | `ipad_4x3.jpg` (1024×768), `iphone_19x9.jpg` (1560×720) | Menu, wardrobe and HUD (with touch controls) fit with no overlap. |
| Landing | – | `landing_stumble.jpg` | Off-balance catch: arm out, torso tips toward the slide, corrective steps. |

Known visual limits:
- Glove and web thumbnails are close-ups of the launcher hand (the web is a short line in its colour).
- Hats and Face sidebar glyphs use the coloured cap and shades drawings.
- The hoodie shows a few dark baked-AO patches at the shoulders up close (from the fold shapes).
