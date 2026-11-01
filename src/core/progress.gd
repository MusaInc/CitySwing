class_name Progress
extends RefCounted
## Medals and suit unlocks, derived from SaveData (nothing extra is stored
## apart from the chosen suit, so unlocks can never drift out of sync).

enum Medal { NONE, BRONZE, SILVER, GOLD }

const MEDAL_NAMES := ["", "Bronze", "Silver", "Gold"]
const MEDAL_COLORS := [Color(1, 1, 1, 0.3), Color(0.8, 0.52, 0.3), Color(0.8, 0.84, 0.9), Color(1.0, 0.8, 0.3)]
## Fraction of par each medal allows. Par is the recorded autopilot time + 10%.
const MEDAL_FACTORS := {Medal.GOLD: 1.0, Medal.SILVER: 1.25, Medal.BRONZE: 1.6}

## Total tokens hidden around the city in Free Swing (see TokenField).
const TOKEN_TOTAL := 40

## Suit colours. `req` is checked by unlocked(); `hint` explains it.
const SUITS := [
	{"id": "ember", "name": "Courier", "color": Color(0.22, 0.24, 0.26), "req": {}, "hint": "Default"},
	{"id": "cobalt", "name": "Cobalt", "color": Color(0.1, 0.3, 0.85), "req": {"tutorial": true}, "hint": "Finish Training"},
	{"id": "jade", "name": "Jade", "color": Color(0.05, 0.62, 0.38), "req": {"tokens": 10}, "hint": "Collect 10 tokens"},
	{"id": "violet", "name": "Violet", "color": Color(0.5, 0.16, 0.8), "req": {"medals": 3}, "hint": "Earn 3 Time Trial medals"},
	{"id": "midnight", "name": "Midnight", "color": Color(0.1, 0.11, 0.16), "req": {"endurance": 1500.0}, "hint": "Endurance: 1,500 m"},
	{"id": "arctic", "name": "Arctic", "color": Color(0.85, 0.88, 0.92), "req": {"tokens": 25}, "hint": "Collect 25 tokens"},
	{"id": "gilded", "name": "Gilded", "color": Color(0.95, 0.68, 0.18), "req": {"golds": 3}, "hint": "Gold on every course"},
	{"id": "neon", "name": "Neon", "color": Color(0.2, 1.0, 0.75), "req": {"tokens": TOKEN_TOTAL}, "hint": "Collect every token"},
]


static func medal_for(par: float, seconds: float) -> int:
	if seconds == INF:
		return Medal.NONE
	for m in [Medal.GOLD, Medal.SILVER, Medal.BRONZE]:
		if seconds <= par * MEDAL_FACTORS[m]:
			return m
	return Medal.NONE


static func medal_target(par: float, medal: int) -> float:
	return par * MEDAL_FACTORS[medal]


static func _save() -> Node:
	return Engine.get_main_loop().root.get_node("/root/SaveData")


static var _pars := {}


static func par(id: String) -> float:
	if not _pars.has(id):
		var c := CourseBuilder.load_course(id)
		_pars[id] = INF if c.is_empty() else c["par"]
	return _pars[id]


static func course_medal(id: String) -> int:
	return medal_for(par(id), _save().best_trial(id))


## [medals earned (any colour), golds]
static func medal_counts() -> Array:
	var any := 0
	var golds := 0
	for id in CourseBuilder.COURSES:
		var m := course_medal(id)
		any += int(m != Medal.NONE)
		golds += int(m == Medal.GOLD)
	return [any, golds]


static func suit(id: String) -> Dictionary:
	for s in SUITS:
		if s["id"] == id:
			return s
	return SUITS[0]


static func unlocked(s: Dictionary) -> bool:
	var d: Dictionary = _save().data
	var r: Dictionary = s["req"]
	if r.get("tutorial", false) and not d["tutorial_done"]:
		return false
	if d["tokens"].size() < r.get("tokens", 0):
		return false
	if d["best_endurance_m"] < r.get("endurance", 0.0):
		return false
	if r.has("medals") or r.has("golds"):
		var mc := medal_counts()
		if mc[0] < r.get("medals", 0) or mc[1] < r.get("golds", 0):
			return false
	return true


static func unlocked_ids() -> Array:
	var out := []
	for s in SUITS:
		if unlocked(s):
			out.append(s["id"])
	return out


## Names of suits in `now` that weren't in `before`.
static func newly_unlocked(before: Array) -> Array:
	var out := []
	for id in unlocked_ids():
		if not id in before:
			out.append(suit(id)["name"])
	return out


static func current_suit_color() -> Color:
	return Shop.item(Shop.equipped("suit"))["color"]
