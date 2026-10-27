# Tuning the swing

All traversal numbers are fields of `SwingParams` (`src/physics/swing_params.gd`).
Defaults live there; `config/swing_params.tres` can override any of them, and
the in-game **Pause → Tuning** panel edits the most important ones live on the
device (saved per device in `user://settings.cfg`, "Reset defaults" clears them).

| Parameter | Default | Feel |
|---|---|---|
| `gravity` | 19 m/s² | Swing tempo. Lower = floatier, longer arcs. |
| `air_drag` | 0.0016 /m | How fast momentum bleeds. Higher = harder to keep a chain going. |
| `linear_drag` | 0.02 /s | Low-speed creep damping. |
| `grapple_range` / `max_rope_length` | 75 m | Reach. Long ropes = long, fast, harder-to-control arcs. |
| `line_speed` | 280 m/s | Line travel time: how far players must lead a shot. |
| `attach_length_factor` | 1.0 | <1 snaps the rope shorter on attach (instant tug, more assist). |
| `reel_in_speed` / `reel_out_speed` | 9 / 11 m/s | Pumping strength (reeling in conserves angular momentum). |
| `reel_speed_cap` | 55 m/s | Ceiling on speed gained from reeling alone. |
| `swing_steer_accel` | 4.5 m/s² | Tangential kick on the rope (sideways lines, small pumps). |
| `swing_pump_bonus` | 0.35 | Extra kick when pushing along the direction of travel. |
| `air_steer_accel` | 5 m/s² | Mid-air steering. |
| `air_steer_speed_limit` | 9 m/s | Air steering can't accelerate you past this on its own. |
| `run_speed`, `jump_speed` | 11, 9.5 m/s | Rooftop movement. |
| `wall_kick_speed`, `wall_kick_up` | 11, 8 m/s | Recovery when pinned against a facade. |
| `substeps` | 4 | Rope solver substeps per 60 Hz tick. |

## Checking a change

1. `tools/build.sh`. The physics tests pin the model's behaviour (period,
   energy, angular momentum), and the scene tests check that the expert
   autopilot still chains the range while the novice still fails.
2. If the expert numbers move a lot, re-record the courses:
   `tools/build.sh courses` (Time Trial gates are placed along real flights).
3. Feel it: `tools/filmstrip.sh` for captures, and the device for real input.

The skill gap is deliberate and tested. A player who grabs a 70 m rope from a
31 m roof and never reels scrapes the street; one who reels to keep ground
clearance, pumps through the bottom and releases ~30° into the upswing chains
indefinitely.
