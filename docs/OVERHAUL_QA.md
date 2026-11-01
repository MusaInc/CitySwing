# CitySwing 0.16 visual and residential overhaul

This release preserves the existing island, bridge, mainland, districts, currency, home IDs/prices, ownership and save schema. It changes the generated geography, so course gates were recorded again for all eight existing course IDs.

## Implemented

- Blender hero asset rebuilt with a fitted masked helmet, continuous visor, tailored waist, asymmetric utility hem, layered front/back vest, diagonal harness, hardware and skyline insignia. Existing skeleton, hands, footwear, gait, ragdoll, suit palettes and clothing spring remain compatible. No exposed face.
- Broad northern/eastern bays and a headland replace high-frequency coastline bumps. The east rises to a stronger ridge; harbour levels and bridge connections stay fixed. Shore apron variation is smoother. The loop railway is re-eased to follow the changed coast without track kinks.
- Tall buildings gain architectural facade blades/piers with matching human collision. Window exclusions now remove both drawn detail and human-only collision; previously invisible detail could block windows. Water has softer normals and reduced sparkle.
- Five larger homes: 56, 110, 168, 252 and 432 square metres, with 3.2–5.2 m ceilings. Room partitions, open doorways, bedrooms, bathrooms, kitchens, living areas, wardrobes, floor boards, art, skirting and ceiling details. Premium homes have a second lounge; the penthouse has a separate study and kitchen island. Eight original Blender furniture assets are shared across homes, with distance culling and simple major-furniture collision.
- Homes remain recessed cutouts in their real building geometry. Spawn and entry IDs/prices are unchanged. Window vaults use a velocity-matched cubic path and speed-dependent duration. Respawning cancels an active window animation. Ground launch selection rejects tiny rooftop pendulums, with an 8 m/s initial forward launch impulse; the swing integrator remains unchanged.
- Collision recovery in the camera is rate-limited only along a clear camera path. Altitude extends world streaming range so high apartments retain distant skyline geometry after spawning.
- Asset regeneration now rebuilds the skinned hero after the legacy kit, preventing the kit from overwriting it.

## Verification

The real Godot Mobile renderer was captured under Xvfb/Vulkan llvmpipe. These are game renders, not Blender previews or concept images. Selected images are in `docs/qa/overhaul`; full sequences remain in `screenshots/overhaul`.

- Targeted home tests: all five spawns stay grounded; window exit rays are clear; catch/hang/climb, vault, reckless-entry rejection and ownership purchases pass.
- New capsule checks pass at 9, 16 and 23 m/s for every home (15 entry cases).
- Respawning during entry returns control and cancels the old path.
- Railway: maximum turn 5.2° per 2 m, maximum grade 11.3%; clear of buildings.
- Launch audit: 7/8 sampled street/roof launches pass the existing acceptance threshold. One sampled street location still requires manual aiming.
- Camera transition targeted check: maximum extra step 0.85 m, below the 1 m threshold.
- Packaged Linux smoke test: eight courses, 33 sounds, asset kit and Mobile renderer load successfully.
- Aerial medium-quality render: 173 draw calls, 228,207 primitives, 346.3 MB static memory and 140.1 MB video memory. These are VPS measurements, **not iPhone frame-rate claims**.

## Remaining limits

This is a tested visual/system iteration, not a claim of finished AAA art. Interiors still use a small reusable furniture palette and restrained material detail; the high penthouse view depends strongly on camera position and pitch. Existing ragdoll and gait systems were retained rather than replaced. Real-device performance, thermal behaviour and extended touch-play sessions remain unverified. Godot reports shutdown resource/RID warnings in the test tools. TestFlight processing is a separate release gate; record the actual result below.

## Acceptance result

Final full suite: **122 passed, 0 failed**, 298.6 seconds on the VPS. The final penthouse gameplay capture measured 113 draw calls, 172,564 primitives, 357.4 MB static and 154.5 MB video memory. Some thin character details still show aliasing in software-rendered motion captures; real-device visual review is outstanding. This release does not claim to resolve every art-quality aspiration in the broader brief.

The final committed home suite was rerun after adjusting bedroom furniture clearance: **8 passed, 0 failed** (55.4 seconds).

### In-game captures

[Hero standing](qa/overhaul/hero-standing.png) · [Running](qa/overhaul/hero-running.png) · [Swinging](qa/overhaul/hero-swinging.png) · [Skyline](qa/overhaul/skyline.png) · [Waterfront](qa/overhaul/waterfront.png) · [Starter](qa/overhaul/starter.png) · [Starter view](qa/overhaul/starter-view.png) · [Mid-tier home](qa/overhaul/loft.png) · [Penthouse](qa/overhaul/penthouse.png) · [Penthouse gameplay view](qa/overhaul/penthouse-view.png) · [Window entry](qa/overhaul/window-entry.png) · [Window exit](qa/overhaul/window-exit.png)

[Full test log](qa/overhaul/tests.log) · [Committed apartment test log](qa/overhaul/home-tests.log)

TestFlight upload: version **0.16.0**, build **26**, source commit `72b25c8a57419f9616defeab7c86881c95ada0a5`. The archive and upload steps succeeded in [release run 41336273328](https://github.com/MusaInc/CitySwing/actions/runs/41336273328); Apple processing completed successfully at 2026-11-01 18:26:17 UTC: **FINAL_STATE VALID**. The workflow finished successfully.
