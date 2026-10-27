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
## Reel speed in m/s. Reeling in while taut conserves angular momentum (pumping).
@export var reel_in_speed: float = 9.0
@export var reel_out_speed: float = 11.0
## Constraint sub-steps per physics tick. More = stiffer, more accurate rope.
@export_range(1, 16) var substeps: int = 4
## Fraction of outward radial velocity removed when the rope snaps taut (1 = inelastic).
@export_range(0.0, 1.0) var taut_inelasticity: float = 1.0
## Hard cap on tangential speed gained purely from reeling (stops infinite pumping).
@export var reel_speed_cap: float = 55.0

@export_group("Control authority")
## Tangential force the player can add while attached (body "kick"), m/s².
@export var swing_steer_accel: float = 4.5
## Extra fraction of swing_steer_accel when pushing along the current direction of travel.
@export_range(0.0, 2.0) var swing_pump_bonus: float = 0.35
## Horizontal steering acceleration while free-flying, m/s².
@export var air_steer_accel: float = 5.0
## Air steering can't push horizontal speed in the input direction above this.
@export var air_steer_speed_limit: float = 9.0

@export_group("Ground")
@export var run_speed: float = 11.0
@export var run_accel: float = 45.0
@export var ground_friction: float = 9.0
## Speed above run_speed decays at this rate (m/s²) so landings keep some flow.
@export var ground_overspeed_decel: float = 14.0
@export var jump_speed: float = 9.5
## Jumping while touching a wall in the air kicks off it (recovery move).
@export var wall_kick_speed: float = 11.0
@export var wall_kick_up: float = 8.0

@export_group("Impacts")
## Speed into a surface above which a hard-impact event fires (bonk, haptics).
@export var hard_impact_speed: float = 14.0
## Speed into the floor above which the landing is a "roll" rather than a step.
@export var roll_landing_speed: float = 18.0
## Speed into a wall above which the body goes limp (ragdoll + recovery).
@export var ragdoll_impact_speed: float = 28.0
## Vertical landing speed above which the body crumples (ragdoll + recovery).
@export var ragdoll_fall_speed: float = 30.0
## Fraction of along-wall speed lost per second while scraping a facade.
@export var wall_friction: float = 1.2
## Below this world Y the player respawns.
@export var kill_plane_y: float = -30.0
