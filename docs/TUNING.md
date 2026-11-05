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

### Player flow layer (people only)

These apply only when a person is playing (`Controls.human`). The autopilot,
the recorded courses and the model tests keep the plain model above.

| Parameter | Default | Feel |
|---|---|---|
| `flow_accel` / `flow_cruise_speed` | 7 m/s² / 38 m/s | A taut web carries you through the low part of the arc, easing off towards the cruise speed (none on a steep climb). |
| `flow_drag_scale` | 0.75 | Air drag multiplier: momentum carries between webs. |
| `flow_release_boost` / `flow_release_lift` | 1.05 / 3 m/s | Letting go on the way up (below cruise) throws you on out of the arc. |
| `wall_run_min_speed` | 8 m/s | Hitting a facade this fast (short of a head-on knockout) starts a wall run, unless the stick pulls away. |
| `wall_run_time` | 1.1 s | Longest wall run: up the wall head-on, along it at an angle, then a push-off into the air (JUMP pushes harder). Not a climb. |
| `wall_run_up_decel` / `wall_run_side_decel` | 11 / 3 m/s² | How quickly the run up / along the wall runs out. |
| `wall_run_launch_out` / `wall_run_launch_up` | 6 / 6.5 m/s | Push-off off the wall. |

Near a roof edge (feet within about 5 m of it), pushing at the wall scrambles
over the lip, round a cornice if there is one (`Player._top_out`).
`tools/flow_probe.gd` plays with human input and reports swing speeds
(`--plain` turns the flow layer off) and the wall moves at real facades.

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
