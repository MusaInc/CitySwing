# Status: 2026-10-27 (foot contact + kerbs)

## Foot contact and kerbs (latest)

- **Planted feet** (`CharacterRig._plant_feet`): a stance foot locks where it
  touches the ground (raycast), the leg is solved onto it with two-bone IK,
  and the heel rolls up over the ball of the foot for toe-off and on long
  running contacts. Swing feet reach down for the ground before contact and
  never dip into it; the hips drop when a planted foot is out of reach.
  Stance-foot slide at 11 m/s: 31% → 7% of body speed.
- Gait fixes: toe-off used to tilt the toes *up*; the swing leg now arrives
  already sweeping back (Hermite swing), so touchdown no longer skates.
- **Step-up** (`Player._try_step_up`): running bodies climb anything up to
  0.35 m (kerbs, stairs, rooftop lips) instead of stopping dead; taller
  obstacles are still walls. The visual body eases up over the step.
  Expert feel report unchanged (59 km/h airborne, 0 crashes).
- `tools/pose_lab.gd` has a `steps` scenario; new native test
  `test_running_up_and_down_kerbs` (67 native tests).
- Browser test: the debug bridge publishes `rig` (skinned, planted feet, foot
  gap, web hand off the rope line); Chromium 15/15, WebKit 9/9 against a
  local server.

## Character visual + movement overhaul

- **Model** (`tools/blender/build_character.py`): one continuous skinned body
  (torso, neck, arms, legs; ~9k tris) built from lofted anatomy (V-taper torso,
  pecs/lats/traps, glutes, thigh/calf shape), voxel-remeshed so joints bend as
  one surface, auto-weighted on a 17-bone armature matching the rig. Rigid
  parts: head with eyes/brows/nose/lips/ears/hair and goggles, gloved
  segmented hands + fists, sneakers, back spool, web gauntlet. ~19k visible
  tris in total. The scarf was removed (it read as a stiff rod in motion).
  Jacket colours/unlockable suits still work (same vertex colours).
- **Rig** (`character_rig.gd`): the physics-driven pivots stay the source of
  truth and are mapped onto the skeleton each frame (bound in an A-pose).
  New: two-bone IK web arm (hand on the line), second hand grips under heavy
  load, body stretches when taut / tucks when slack, jolt on catching the
  web; stance/swing gait matched to ground speed (planted feet, toe-off, knee
  drive, hip bob, sprint lean, braking and turn lean), richer idle; jump
  push-off and readable flight poses; dive only in fast steep descents; wall
  run pose; get-up after crashes.
- **Ragdoll**: knee/elbow hinge direction and hip/shoulder cones.
- `tools/pose_lab.gd` films scripted scenarios (idle, run, jump, swing,
  release, wall run, crash, landing) for review.
- Tests: 66 native (4 new in tests/test_animation.gd), Chromium 12/12, WebKit 7/7.

Limits: face is stylised; not yet seen on an iPhone. (Foot contact: see the
section above.)

## Swing feel pass (latest)

Measured with `tools/feel_report.gd` (6 autopilot runs × 40 s; bots are
chaotic, so these are rough):

| | before | after |
|---|---|---|
| Expert: airborne speed / ragdoll crashes per run | 54 km/h / 1.2 | 59 km/h / 0.0 |
| Novice: airborne speed / ragdoll crashes per run | not measured | 66 km/h / 0.2 (was 2.0 before wall runs) |
| Prototype range cleared by expert timing | 1/5 | 5/5 (novice still 0/5) |

- Perfect release (gold web cue, PERFECT ×n pop, FOV punch, rising chime).
- Momentum kept when a web is caught mid-flight; hang time at the apex.
- Head-on wall hits below 50 m/s become wall runs; glancing hits are wall taps.
- Speed lines from 72 km/h. Time Trial courses re-recorded for the new physics.

## Progression

Training mode (first-run), 40 Free Swing tokens with a HUD pointer, Time Trial
medals with targets shown in the course list and HUD, 8 unlockable suit
colours (jacket recoloured in the character shader), unlock notices on the
results screen, "End session" in Free Swing pause. 62 native tests; browser
tests Chromium 12/12, WebKit 7/7. Still **not tried on a physical iPhone**:
the swing feel numbers above come from the autopilot only.

## Overhaul (earlier)


- Assisted SWING touch catches the best valid anchor while held; if none is in
  range it launches and catches the next one automatically. Optional precise
  building taps use the camera ray, range and line-of-sight checks.
- Stable follow camera (behind travel, rate-limited yaw, no flips/orbits).
- Jump 16 m/s (apex 6.7 m). Reel buttons removed; automatic web pull also
  tightens slack line during ground launches. Eight street and rooftop launch
  scenarios clear cleanly in the scene tests.
- Rope wraps round corners (cuts if < 6 m line would remain); crash stun with
  a Verlet ragdoll (keeps the web on the rope) and recovery.
- New Blender character (lofted anatomy, techwear, goggles, harness, spool,
  scarf, grip hands), spring-damped physical animation, flips on release.
- Free Swing starts on a random valid rooftop facing a promising route.
- 55 native tests; browser tests: Chromium 12/12 (simulated held multi-touch),
  WebKit 7/7 (real single taps; Linux WebKit cannot simulate held touches).
- Safari preview: https://musastudios.co.uk/cityswing/ (workspace sign-in).
- **Not yet tried on a physical iPhone.**

## Original milestones

## Milestones

| # | Milestone | State | Evidence |
|---|---|---|---|
| 1 | Physics prototype | **Done** | Pure rope/pendulum model + Jolt controller; 17 model tests (period within 1.5% of theory, <0.15% energy drift over 20 s of large swings, angular momentum conserved when reeling, slack/snap, exact velocity on release); prototype tower range (`--world=prototype`). |
| 2 | Gameplay refinement | **Done (pending device feel)** | Camera: critically damped trailing, speed FOV, look-ahead capped by distance, anchor-biased framing, sphere-cast collision, gentle roll, no shake. Touch two-thumb layout, controller and keyboard. Wall-kick recovery. Scene tests: expert autopilot chains 420 m with 5 swings at 178 km/h top speed, never touching the street; the novice pattern hits the street. |
| 3 | Procedural city | **Done** | ~680 buildings, 5 districts, landmarks, viaduct, skybridges, docks, parks, outskirts. Threaded chunk streaming (~1.5 ms/chunk), detail/low LODs, occluders, MultiMesh props, GPU traffic. City tests incl. a 590 m expert run with 0 street touches. |
| 4 | Presentation | **Done (first pass)** | Blender-generated character in streetwear with wrist launcher and backpack spool, posed per frame from physics; golden-hour sky, fog, AgX; facade/water/ground shaders; synthesised audio driven by speed, tension and height; haptics; three modes; menus, settings, live tuning, stats; benchmark mode. |
| 5 | iOS delivery | **Prepared, not built** | Xcode project exports from Linux (`tools/export_ios.sh`). Linux export of the same project passes the packaged self-test (3 courses, 18 sounds, 11 kit meshes, character, Mobile renderer). Mac/Xcode/TestFlight steps in `docs/IOS_BUILD.md`. |

`tools/build.sh` runs the whole chain (import, 55 tests, Linux export
self-test, iOS export) in about 40 s on the VPS.

## Measured on the VPS (not device numbers)

Headless x86 vCPU, no GPU. Indicative of gameplay CPU cost only:

- Physics: ~1.8 ms per 60 Hz tick steady state, with the full city colliders
  and a swinging player (2 ticks per 30 fps frame).
- Grapple targeting 26 µs (35 rays), swing model 8 µs/tick, streaming scan 94 µs.
- City layout + all colliders: ~40–50 ms at load; 16 chunks around spawn: ~25 ms.
- Rendering at swing height (software Vulkan, so not a performance figure):
  100–140 draw calls, 170–190k primitives at Medium.

## Not done / blockers

1. **No device testing.** I have not run the game on an iPhone, so 30/60 fps,
   touch feel, haptics and thermals are unverified. Run Settings → benchmark
   and the perf overlay on the baseline phone (`docs/IOS_BUILD.md` §4).
2. **iOS compile, signing and TestFlight need a Mac with Xcode** and your Apple
   Developer team. The exported project uses a placeholder team unless
   `IOS_TEAM_ID` is set.
3. **Swing feel has only been tuned with the autopilot.** Human touch tuning
   on the device is still needed. The live Tuning panel exists for exactly this.
4. Visual polish left: the facade shader is uniform up close, the character
   has no facial detail, there is no motion blur or speed lines, and there is
   one time of day.
5. Godot logs a Jolt "job system exceeded the maximum number of jobs" warning
   when several city worlds are built in one process (the course recorder);
   it did not appear in a 40 s headless Free Swing session (0 occurrences). Watch for it on device.
