class_name SwingParams
extends Resource
## Every tunable number of the traversal model lives here so feel can be
## adjusted in config/swing_params.tres (or the in-game tuning panel)
## without touching code. Units are metres, seconds, m/s and m/s².

@export_group("World")
## Game gravity. Higher than Earth's 9.81 so 40 m ropes swing at a readable pace.
@export var gravity: float = 19.0
## Quadratic air drag coefficient (per metre). Bleeds energy so momentum must be earned.
@export var air_drag: float = 0.0016
## Linear drag (per second) – tiny, stops creeping drift at low speed.
@export var linear_drag: float = 0.02
@export var max_fall_speed: float = 70.0

@export_group("Rope")
@export var grapple_range: float = 75.0
## How fast the fired line travels (m/s). Attaching isn't instant: lead your shots.
@export var line_speed: float = 280.0
## Anchors must be at least this far above the player (unless standing).
@export var min_anchor_height: float = 3.0
@export var min_rope_length: float = 4.0
@export var max_rope_length: float = 75.0
## Rope length on attach as a fraction of current distance (<1 gives an immediate tug).
@export var attach_length_factor: float = 1.0
## Max speed (m/s) at which the web tightens by itself through the bottom of
## each arc. Shortening a taut line conserves angular momentum, so this is real
## pumping: the pull does work, the swing gains speed and lifts the body.
@export var reel_in_speed: float = 8.0
## The automatic pull never shortens the line below this fraction of its
## length at attach (each swing keeps its character).
@export_range(0.3, 1.0) var auto_tighten_min_fraction: float = 0.6
## The line also tightens to keep the lowest point of the arc this far above
## the street.
@export var swing_ground_clearance: float = 8.0
## Assisted hold-to-climb: metres/second, without an extra touch button.
## These assists apply to human controls; recorded autopilot courses retain their model.
@export var auto_climb_speed: float = 4.5
@export var auto_climb_upswing_bonus: float = 1.8
@export var auto_climb_stop_distance: float = 6.0
@export var auto_climb_accel: float = 36.0
@export var reel_out_speed: float = 11.0
## Constraint sub-steps per physics tick. More = stiffer, more accurate rope.
@export_range(1, 16) var substeps: int = 4
## Fraction of outward radial velocity removed when the rope snaps taut (1 = inelastic).
@export_range(0.0, 1.0) var taut_inelasticity: float = 1.0
## Ropes catch on building corners (new pivot) and unwrap when the line clears.
@export var rope_wrapping: bool = true
## A corner that would leave less free line than this cuts the web (momentum kept).
@export var wrap_cut_length: float = 6.0
## Hard cap on tangential speed gained purely from reeling (stops infinite pumping).
@export var reel_speed_cap: float = 55.0
## Share of the radial energy lost when a slack rope snaps taut that is turned
## into speed along the swing instead (0 = pure inelastic jerk). Catching a web
## mid-flight carries you on rather than braking you.
@export_range(0.0, 1.0) var snap_redirect: float = 0.7

@export_group("Release")
## Letting go on the upswing inside the sweet spot (flight path this many
## degrees above horizontal, at speed) is a perfect release: speed × boost.
@export var perfect_release_min_deg: float = 20.0
@export var perfect_release_max_deg: float = 42.0
@export var perfect_release_min_speed: float = 12.0
@export var perfect_release_boost: float = 1.1
## Extra upward speed (m/s) on a perfect release, for a satisfying launch.
@export var perfect_release_lift: float = 2.5
## After any release, gravity is scaled by this near the top of the flight
## (|vy| below apex_window) for a moment of hang time to line up the next web.
@export_range(0.2, 1.0) var apex_gravity_scale: float = 0.55
@export var apex_window: float = 5.0

@export_group("Control authority")
## Tangential force the player can add while attached (body "kick"), m/s².
@export var swing_steer_accel: float = 4.5
## Extra fraction of swing_steer_accel when pushing along the current direction of travel.
@export_range(0.0, 2.0) var swing_pump_bonus: float = 0.35
## Human steering assist (the bots don't use it): how fast full sideways
## stick turns the direction of travel, keeping speed – deg/s on a web / in
## free flight.
@export var swing_turn_rate: float = 55.0
@export var air_turn_rate: float = 85.0
## Horizontal steering acceleration while free-flying, m/s².
@export var air_steer_accel: float = 5.0
## Air steering can't push horizontal speed in the input direction above this.
@export var air_steer_speed_limit: float = 9.0

@export_group("Ground")
@export var run_speed: float = 11.0
@export var run_accel: float = 45.0
## Human players sprint faster than this base speed (Controls.human). Bots and
## the recorded courses keep run_speed: their routes depend on it.
@export var player_run_speed: float = 14.5
@export var player_run_accel: float = 58.0
@export var ground_friction: float = 9.0
## Speed above run_speed decays at this rate (m/s²) so landings keep some flow.
@export var ground_overspeed_decel: float = 14.0
@export var jump_speed: float = 16.0
## Jumping while touching a wall in the air kicks off it (recovery move).
@export var wall_kick_speed: float = 11.0
@export var wall_kick_up: float = 11.0

@export_group("Impacts")
## Speed into a surface above which a hard-impact event fires (bonk, haptics).
@export var hard_impact_speed: float = 14.0
## Speed into the floor above which the landing is a "roll" rather than a step.
@export var roll_landing_speed: float = 18.0
## Speed into anything that is not a facade (ledge corners, roof edges, …)
## above which the body goes limp. Facades: see the wall settings below.
@export var ragdoll_impact_speed: float = 28.0
## Fast wall hits at a shallower angle than this (speed into the wall ÷ total
## speed; 0.6 ≈ 37°) are wall taps that bounce you off instead of crashing.
@export_range(0.0, 1.0) var wall_glance_ratio: float = 0.6
## Share of the into-wall speed returned as an outward push on a wall tap.
@export_range(0.0, 1.0) var wall_glance_bounce: float = 0.35
## Head-on facade hits between hard_impact_speed and this become a wall run:
## the body plants its feet and runs up the facade at into-speed × wall_run_up.
## Above it (≈79 km/h into the wall) you are knocked out: the web lets go and
## the body ragdolls off the wall.
@export var wall_run_max_speed: float = 22.0
## Minimum time a knockout keeps you down (then: settled on something).
@export var knockout_time: float = 2.2
## JUMP pressed up to this long before a knockout-speed wall hit kicks you
## off the wall instead (the skill escape).
@export var wall_save_window: float = 0.22
@export_range(0.0, 1.0) var wall_run_up: float = 0.55
## Vertical landing speed above which the body crumples (ragdoll + recovery).
@export var ragdoll_fall_speed: float = 30.0
## Fraction of along-wall speed lost per second while scraping a facade.
@export var wall_friction: float = 1.2
## Below this world Y the player respawns.
@export var kill_plane_y: float = -30.0
