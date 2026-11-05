class_name Contracts
extends RefCounted
## Jobs for coins and reputation – the rules only (no scene access), so tests
## and tools can drive them. JobBoard (src/modes/job_board.gd) puts them in
## the world during Free Swing.
##
## A contract is a Dictionary:
##   id, type, legal, tier (1-5), title, client, brief,
##   start: Vector3        where it is picked up (its beacon)
##   start_kind: "land" | "pass"
##   stops: [Vector3]      objectives after the pickup, in order
##   stop_kinds: ["land" | "pass" | "hold"]
##   time: seconds allowed once picked up, pay, rep, fine (criminal: busted)
##   heat: true when pursuit drones join (criminal work), drones: how many
##
## Movement is the whole game, so every job is a traversal problem: get
## somewhere specific, on time, and (for the risky ones) without being caught
## by drones that are quick but not as quick as a good swing line.

const TYPES := {
	# Legal – Courier Co. / city services.
	"delivery": {"legal": true, "title": "Rooftop Delivery", "client": "Courier Co.",
		"brief": "Collect the parcel and land on the drop roof.", "speed": 13.0, "slack": 30.0, "rate": 0.20, "base": 60},
	"express": {"legal": true, "title": "Express Courier", "client": "Courier Co.",
		"brief": "Fragile and urgent. Knockouts cost you; time left pays a bonus.", "speed": 17.0, "slack": 15.0, "rate": 0.30, "base": 80},
	"rescue": {"legal": true, "title": "Gondola Rescue", "client": "City Rescue",
		"brief": "A window cleaner is stranded. Swing past to grab them, then land on the medic roof.", "speed": 13.0, "slack": 28.0, "rate": 0.26, "base": 110},
	"survey": {"legal": true, "title": "Skyline Survey", "client": "City Planning",
		"brief": "Fly through every survey point over the rooftops.", "speed": 13.0, "slack": 30.0, "rate": 0.22, "base": 70},
	# Underworld – the Fence. Pays far more; drones hunt you.
	"hotdrop": {"legal": false, "title": "Hot Drop", "client": "The Fence",
		"brief": "Pick up the package and get it to the drop. A drone will be on you.", "speed": 14.0, "slack": 25.0, "rate": 0.48, "base": 160, "drones": 1},
	"getaway": {"legal": false, "title": "Getaway", "client": "The Fence",
		"brief": "You were seen. Shake the drones and land at the safehouse.", "speed": 14.0, "slack": 25.0, "rate": 0.46, "base": 180, "drones": 2},
	"heist": {"legal": false, "title": "Rooftop Heist", "client": "The Fence",
		"brief": "Land on the target roof and hold still to crack the case, then get it to the fence.", "speed": 14.0, "slack": 32.0, "rate": 0.55, "base": 220, "drones": 2},
}
const LEGAL_TYPES := ["delivery", "express", "rescue", "survey"]
const CRIME_TYPES := ["hotdrop", "getaway", "heist"]

## Reputation ladder. Each rank opens the next contract tier.
const RANKS := ["Rookie", "Runner", "Courier", "Pro", "Ace", "Legend"]
const RANK_REP := [0, 120, 360, 800, 1600, 3000]

## Objective radii (metres).
const LAND_R := 11.0     # horizontal radius for a rooftop landing
const LAND_DY := 5.0     # and how far above/below the marker it counts
const PASS_R := 8.0      # fly-through radius
const HOLD_TIME := 2.2   # seconds standing still on a heist roof
const HOLD_SPEED := 3.5  # m/s: slower than this counts as "still"

## Heat (0..1): busted at 1.
const HEAT_SPOT_RATE := 0.20   # per second while a drone has you spotted…
const HEAT_TIER_RATE := 0.035  # …plus this per tier
const HEAT_STREET_RATE := 0.18 # extra per second on the street (easy to see)
const HEAT_COOL_RATE := 0.07   # per second out of sight
const HEAT_KNOCKOUT := 0.22    # a wall knockout while hot
const SPOT_RADIUS := 32.0
const DRONE_SPEED := 21.0      # m/s at tier 1 (+0.8 per tier): a good swing line outruns it
const DRONE_ACCEL := 14.0

## Express: each knockout cuts pay by this fraction (never below EXPRESS_FLOOR).
const EXPRESS_KO_CUT := 0.2
const EXPRESS_FLOOR := 0.4
const EXPRESS_TIME_BONUS := 0.5  # up to +50% for time left
const BUSTED_FINE := 0.35        # of the pay, capped by what you hold


static func rank_for(rep: int) -> int:
	var r := 0
	for i in RANK_REP.size():
		if rep >= RANK_REP[i]:
			r = i
	return r


static func rank_name(rep: int) -> String:
	return RANKS[rank_for(rep)]


## 0..1 toward the next rank (1 at the top).
static func rank_progress(rep: int) -> float:
	var r := rank_for(rep)
	if r >= RANK_REP.size() - 1:
		return 1.0
	return clampf(float(rep - RANK_REP[r]) / float(RANK_REP[r + 1] - RANK_REP[r]), 0.0, 1.0)


## Highest contract tier on offer at a reputation.
static func max_tier(rep: int) -> int:
	return mini(rank_for(rep) + 1, 5)


## Route length for a tier (straight-line metres from pickup to the end).
static func route_length(tier: int) -> float:
	return 260.0 + 150.0 * (tier - 1)


static func path_length(c: Dictionary) -> float:
	var d := 0.0
	var prev: Vector3 = c["start"]
	for s in c["stops"]:
		d += prev.distance_to(s)
		prev = s
	return d


static func time_for(type: String, dist: float) -> float:
	var t: Dictionary = TYPES[type]
	return snappedf(dist / float(t["speed"]) + float(t["slack"]), 1.0)


static func pay_for(type: String, dist: float, tier: int) -> int:
	var t: Dictionary = TYPES[type]
	var tier_k := 1.0 + 0.18 * (tier - 1)
	return int(round((float(t["base"]) + dist * float(t["rate"])) * tier_k / 5.0) * 5.0)


static func rep_for(type: String, tier: int) -> int:
	return (14 if TYPES[type]["legal"] else 22) * tier


static func drone_speed(tier: int) -> float:
	return DRONE_SPEED + 0.8 * (tier - 1)


## Builds a contract of `type` from candidate spots.
## roofs: [{position: Vector3}] rooftop landing spots (standing capsule centres).
## rescue: [Vector3] gondola positions (only rescue uses them).
## vantage: [Vector3] fly-through survey points.
## Returns {} when nothing in reach fits.
static func make(rng: RandomNumberGenerator, type: String, tier: int, from: Vector3,
		roofs: Array, rescue: Array = [], vantage: Array = []) -> Dictionary:
	var spec: Dictionary = TYPES[type]
	var want := route_length(tier)
	var c := {"type": type, "legal": spec["legal"], "tier": tier, "title": spec["title"],
		"client": spec["client"], "brief": spec["brief"], "drones": int(spec.get("drones", 0)),
		"heat": not spec["legal"], "stops": [], "stop_kinds": []}
	match type:
		"rescue":
			var g := _pick(rng, rescue, from, 120.0, 520.0)
			if g == Vector3.INF:
				return {}
			c["start"] = g
			c["start_kind"] = "pass"
			var med := _pick_roof(rng, roofs, g, want * 0.6, want * 1.1)
			if med == Vector3.INF:
				return {}
			c["stops"] = [med]
			c["stop_kinds"] = ["land"]
		"survey":
			var first := _pick(rng, vantage, from, 120.0, 480.0)
			if first == Vector3.INF:
				return {}
			c["start"] = first
			c["start_kind"] = "pass"
			var n := 2 + mini(tier, 3)  # 3-5 points in all
			var prev := first
			var used := [first]
			for i in n - 1:
				var nx := Vector3.INF
				for attempt in 8:
					var cand := _pick(rng, vantage, prev, 140.0, 340.0)
					if cand != Vector3.INF and not cand in used:
						nx = cand
						break
				if nx == Vector3.INF:
					break
				used.append(nx)
				c["stops"].append(nx)
				c["stop_kinds"].append("pass")
				prev = nx
			if c["stops"].size() < 2:
				return {}
		"heist":
			var tgt := _pick_roof(rng, roofs, from, 140.0, 480.0)
			if tgt == Vector3.INF:
				return {}
			c["start"] = tgt
			c["start_kind"] = "hold"
			var fence := _pick_roof(rng, roofs, tgt, want * 0.8, want * 1.25)
			if fence == Vector3.INF:
				return {}
			c["stops"] = [fence]
			c["stop_kinds"] = ["land"]
		_:
			var a := _pick_roof(rng, roofs, from, 120.0, 460.0)
			if a == Vector3.INF:
				return {}
			c["start"] = a
			c["start_kind"] = "land"
			var b := _pick_roof(rng, roofs, a, want * 0.8, want * 1.25)
			if b == Vector3.INF:
				return {}
			c["stops"] = [b]
			c["stop_kinds"] = ["land"]
	var dist := path_length(c)
	c["time"] = time_for(type, dist)
	c["pay"] = pay_for(type, dist, tier)
	c["rep"] = rep_for(type, tier)
	c["fine"] = 0 if spec["legal"] else int(c["pay"] * BUSTED_FINE)
	return c


static func _pick(rng: RandomNumberGenerator, pts: Array, from: Vector3, lo: float, hi: float) -> Vector3:
	var ok: Array = []
	for p in pts:
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d >= lo and d <= hi:
			ok.append(p)
	if ok.is_empty():
		return Vector3.INF
	return ok[rng.randi() % ok.size()]


static func _pick_roof(rng: RandomNumberGenerator, roofs: Array, from: Vector3, lo: float, hi: float) -> Vector3:
	var pts: Array = []
	for r in roofs:
		pts.append(r["position"] if r is Dictionary else r)
	return _pick(rng, pts, from, lo, hi)


## One step of the pursuit: heat rises while a drone has you spotted (more on
## the street, where you're easy to see) and cools when you're out of sight.
static func heat_step(heat: float, spotted: bool, on_street: bool, tier: int, dt: float) -> float:
	if spotted:
		heat += (HEAT_SPOT_RATE + HEAT_TIER_RATE * (tier - 1)) * dt
		if on_street:
			heat += HEAT_STREET_RATE * dt
	else:
		heat -= HEAT_COOL_RATE * dt
	return clampf(heat, 0.0, 1.0)


## Is a point reached? kind: "land" needs feet on a roof near it, "pass" a
## fly-through (segment a→b within PASS_R), "hold" is "land" plus time.
static func reached(kind: String, target: Vector3, a: Vector3, b: Vector3, grounded: bool) -> bool:
	if kind == "pass":
		return Geometry3D.get_closest_point_to_segment(target, a, b).distance_to(target) <= PASS_R
	if not grounded:
		return false
	return Vector2(b.x - target.x, b.z - target.z).length() <= LAND_R and absf(b.y - target.y) <= LAND_DY


## Coins and reputation for a finished contract.
## outcome: "done" | "late" | "busted" | "abandoned"
static func settle(c: Dictionary, outcome: String, time_left: float, knockouts: int) -> Dictionary:
	var pay := int(c["pay"])
	if outcome != "done":
		var fine: int = int(c.get("fine", 0)) if outcome == "busted" else 0
		return {"coins": -fine, "rep": 0, "bonus": 0}
	var bonus := 0
	if c["type"] == "express":
		var k := maxf(1.0 - EXPRESS_KO_CUT * knockouts, EXPRESS_FLOOR)
		pay = int(pay * k)
		bonus = int(c["pay"] * EXPRESS_TIME_BONUS * clampf(time_left / float(c["time"]), 0.0, 1.0))
	return {"coins": pay + bonus, "rep": int(c["rep"]), "bonus": bonus}
