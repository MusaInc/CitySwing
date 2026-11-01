class_name Shop
extends RefCounted
## The shop: everything the hero can wear, bought with coins earned by
## swinging (see CoinMeter). Ownership and the equipped outfit live in
## SaveData ("owned", "outfit"; the suit stays in "suit" as before).
## Free items (price 0, no req) are always owned. Suits with a `req` are the
## old progression suits: earned through play (Progress.unlocked), not sold.

const SLOTS := [
	["suit", "Suits"], ["pants", "Trousers"], ["shoes", "Shoes"], ["gloves", "Gloves"],
	["head", "Hats"], ["face", "Face"], ["web", "Webs"], ["gadget", "Gadgets"],
]
const DEFAULTS := {"suit": "ember", "pants": "pants_navy", "shoes": "shoes_classic", "gloves": "gloves_black",
	"head": "head_hood", "face": "face_none", "web": "web_classic",
	"gadget": "gadget_none"}
## The classic web glow (gauntlet LEDs, spool rings, visor) is teal under a
## white line.
const CLASSIC_GLOW := Color(0.2, 0.945, 0.945)

## Bought suits (the earned ones come from Progress.SUITS).
const SUITS_FOR_SALE := [
	{"id": "tangerine", "name": "Tangerine", "color": Color(0.95, 0.42, 0.08), "price": 250},
	{"id": "sky", "name": "Sky", "color": Color(0.3, 0.62, 0.95), "price": 250},
	{"id": "rose", "name": "Rose", "color": Color(0.92, 0.36, 0.58), "price": 400},
	{"id": "lime", "name": "Lime", "color": Color(0.55, 0.85, 0.12), "price": 400},
	{"id": "graphite", "name": "Graphite", "color": Color(0.32, 0.34, 0.37), "price": 500},
	{"id": "royal", "name": "Royal", "color": Color(0.24, 0.16, 0.62), "price": 650},
	{"id": "mint", "name": "Mint", "color": Color(0.5, 0.9, 0.76), "price": 650},
	{"id": "sunset", "name": "Sunset", "color": Color(0.85, 0.2, 0.32), "price": 800},
	{"id": "chrome", "name": "Chrome", "color": Color(0.7, 0.73, 0.78), "price": 1500},
	{"id": "onyx", "name": "Onyx", "color": Color(0.04, 0.04, 0.05), "price": 2000},
]

const OTHER_ITEMS := [
	# Trousers
	{"id": "pants_navy", "slot": "pants", "name": "Graphite", "color": Color(0.24, 0.26, 0.28), "price": 0},
	{"id": "pants_black", "slot": "pants", "name": "Black", "color": Color(0.05, 0.05, 0.06), "price": 150},
	{"id": "pants_grey", "slot": "pants", "name": "Charcoal", "color": Color(0.26, 0.27, 0.29), "price": 150},
	{"id": "pants_khaki", "slot": "pants", "name": "Khaki", "color": Color(0.52, 0.45, 0.3), "price": 250},
	{"id": "pants_denim", "slot": "pants", "name": "Denim", "color": Color(0.2, 0.3, 0.5), "price": 250},
	{"id": "pants_olive", "slot": "pants", "name": "Olive", "color": Color(0.27, 0.32, 0.16), "price": 300},
	{"id": "pants_white", "slot": "pants", "name": "White", "color": Color(0.85, 0.85, 0.83), "price": 400},
	{"id": "pants_red", "slot": "pants", "name": "Red", "color": Color(0.6, 0.07, 0.07), "price": 400},
	# Shoes: upper + sole (null = the sole matches the suit)
	{"id": "shoes_classic", "slot": "shoes", "name": "Classic", "color": Color(0.929, 0.929, 0.894), "sole": Color(0.929, 0.929, 0.894), "price": 0},
	{"id": "shoes_blackout", "slot": "shoes", "name": "Blackout", "color": Color(0.08, 0.08, 0.09), "sole": Color(0.14, 0.14, 0.15), "price": 200},
	{"id": "shoes_gum", "slot": "shoes", "name": "Gum Sole", "color": Color(0.92, 0.9, 0.85), "sole": Color(0.55, 0.35, 0.18), "price": 250},
	{"id": "shoes_royal", "slot": "shoes", "name": "Royal", "color": Color(0.15, 0.28, 0.8), "sole": Color(0.93, 0.93, 0.9), "price": 400},
	{"id": "shoes_volt", "slot": "shoes", "name": "Volt", "color": Color(0.85, 0.95, 0.1), "sole": Color(0.08, 0.08, 0.09), "price": 450},
	{"id": "shoes_gold", "slot": "shoes", "name": "Gold", "color": Color(0.95, 0.7, 0.2), "sole": Color(0.93, 0.93, 0.9), "price": 1500},
	# Gloves
	{"id": "gloves_black", "slot": "gloves", "name": "Black", "color": Color(0.098, 0.098, 0.106), "price": 0},
	{"id": "gloves_white", "slot": "gloves", "name": "White", "color": Color(0.88, 0.88, 0.86), "price": 150},
	{"id": "gloves_red", "slot": "gloves", "name": "Red", "color": Color(0.7, 0.08, 0.07), "price": 200},
	{"id": "gloves_teal", "slot": "gloves", "name": "Teal", "color": Color(0.1, 0.6, 0.6), "price": 250},
	{"id": "gloves_gold", "slot": "gloves", "name": "Gold", "color": Color(0.95, 0.7, 0.2), "price": 900},
	# Headwear (models in assets/models/gear.glb; "" = none)
	{"id": "head_hood", "slot": "head", "name": "Hood", "model": "hood", "price": 0},
	{"id": "head_bare", "slot": "head", "name": "No Hat", "model": "", "price": 0},
	{"id": "head_cap", "slot": "head", "name": "Cap", "model": "cap", "price": 600},
	{"id": "head_beanie", "slot": "head", "name": "Beanie", "model": "beanie", "price": 700},
	{"id": "head_phones", "slot": "head", "name": "Headphones", "model": "headphones", "price": 1000},
	{"id": "head_crown", "slot": "head", "name": "Crown", "model": "crown", "price": 5000},
	# Face
	{"id": "face_none", "slot": "face", "name": "None", "model": "", "price": 0},
	{"id": "face_shades", "slot": "face", "name": "Shades", "model": "shades", "price": 500},
	{"id": "face_mask", "slot": "face", "name": "Bandana", "model": "mask", "price": 700},
	{"id": "face_visor", "slot": "face", "name": "Visor", "model": "visor", "price": 900},
	# Webs (the line, plus the gear glow)
	{"id": "web_classic", "slot": "web", "name": "Classic", "color": Color(0.96, 0.95, 0.9), "glow": CLASSIC_GLOW, "price": 0},
	{"id": "web_gold", "slot": "web", "name": "Gold", "color": Color(1.0, 0.78, 0.25), "price": 600},
	{"id": "web_cyan", "slot": "web", "name": "Cyan", "color": Color(0.3, 0.95, 1.0), "price": 600},
	{"id": "web_pink", "slot": "web", "name": "Pink", "color": Color(1.0, 0.4, 0.75), "price": 600},
	{"id": "web_lime", "slot": "web", "name": "Lime", "color": Color(0.6, 1.0, 0.25), "price": 600},
	{"id": "web_red", "slot": "web", "name": "Red", "color": Color(1.0, 0.22, 0.18), "price": 600},
	{"id": "web_shadow", "slot": "web", "name": "Shadow", "color": Color(0.1, 0.08, 0.14), "glow": Color(0.6, 0.25, 1.0), "price": 900},
	{"id": "web_rainbow", "slot": "web", "name": "Rainbow", "color": Color(1, 1, 1), "rainbow": true, "price": 3000},
	# Gadgets: one equipped, used with the GADGET button (see Gadgets).
	# parts = gear.glb pieces worn; active = shown while it runs (replaces
	# the parts when `swap`). duration/cooldown in seconds.
	{"id": "gadget_none", "slot": "gadget", "name": "None", "kind": "", "price": 0},
	{"id": "gadget_jets", "slot": "gadget", "name": "Jet Boots", "kind": "boost", "price": 1500,
		"desc": "Blast forward and up, off a web or the ground", "parts": ["jet_l", "jet_r"],
		"active": ["jet_l_fire", "jet_r_fire"], "duration": 0.7, "cooldown": 7.0},
	{"id": "gadget_glider", "slot": "gadget", "name": "Glider", "kind": "glide", "price": 2000,
		"desc": "Wings out: float for 4 s between webs", "parts": ["glider"], "active": ["glider_open"], "swap": true,
		"duration": 4.0, "cooldown": 10.0},
	{"id": "gadget_chrono", "slot": "gadget", "name": "Chrono Watch", "kind": "focus", "price": 2500,
		"desc": "Slow time for 3 s to line up the next web", "parts": ["chrono"], "duration": 3.0, "cooldown": 15.0},
	{"id": "gadget_magnet", "slot": "gadget", "name": "Coin Magnet", "kind": "surge", "price": 3000,
		"desc": "Double coins for 8 s", "parts": ["magnet"], "duration": 8.0, "cooldown": 25.0},
]

static var _items: Array = []
static var _by_id := {}


static func items() -> Array:
	if _items.is_empty():
		for s in Progress.SUITS:
			var it: Dictionary = s.duplicate()
			it["slot"] = "suit"
			it["price"] = 0
			_items.append(it)
		for s in SUITS_FOR_SALE:
			var it: Dictionary = s.duplicate()
			it["slot"] = "suit"
			_items.append(it)
		_items.append_array(OTHER_ITEMS)
		for it in _items:
			_by_id[it["id"]] = it
	return _items


static func item(id: String) -> Dictionary:
	items()
	return _by_id.get(id, {})


static func in_slot(slot: String) -> Array:
	return items().filter(func(it): return it["slot"] == slot)


static func _save() -> Node:
	return Engine.get_main_loop().root.get_node("/root/SaveData")


static func coins() -> int:
	return int(_save().data.get("coins", 0))


static func owns(id: String) -> bool:
	var it := item(id)
	if it.is_empty():
		return false
	if it.has("req") and not (it["req"] as Dictionary).is_empty():
		return Progress.unlocked(it)
	if it["price"] == 0:
		return true
	return id in _save().data.get("owned", [])


## Earned (progression) items can't be bought.
static func for_sale(id: String) -> bool:
	var it := item(id)
	return not it.is_empty() and it["price"] > 0


## Spends the coins and adds the item. False if owned, unknown or too dear.
static func buy(id: String) -> bool:
	var it := item(id)
	if it.is_empty() or owns(id) or not for_sale(id) or coins() < it["price"]:
		return false
	var d: Dictionary = _save().data
	d["coins"] = coins() - int(it["price"])
	d["owned"].append(id)
	_save().save()
	return true


## Wears an owned item. False if not owned.
static func equip(id: String) -> bool:
	if not owns(id):
		return false
	var it := item(id)
	if it["slot"] == "suit":
		_save().set_suit(id)
	else:
		_save().data["outfit"][it["slot"]] = id
		_save().save()
	return true


## The equipped item in a slot (falls back to the default if the saved one
## is unknown or no longer owned).
static func equipped(slot: String) -> String:
	var d: Dictionary = _save().data
	var id: String = d.get("suit", DEFAULTS["suit"]) if slot == "suit" else d.get("outfit", {}).get(slot, DEFAULTS[slot])
	return id if owns(id) and item(id)["slot"] == slot else DEFAULTS[slot]


## Everything the rig and rope need to draw the outfit. `preview` overrides
## slots (slot -> item id) for trying things on in the shop.
static func look(preview := {}) -> Dictionary:
	var pick := {}
	for s in SLOTS:
		var slot: String = s[0]
		pick[slot] = item(preview.get(slot, equipped(slot)))
		if pick[slot].is_empty():
			pick[slot] = item(DEFAULTS[slot])
	var suit: Color = pick["suit"]["color"]
	var shoes: Dictionary = pick["shoes"]
	var web: Dictionary = pick["web"]
	return {
		"suit": suit,
		"pants": pick["pants"]["color"],
		"shoe": shoes["color"],
		"sole": shoes["sole"] if shoes.get("sole") is Color else suit,
		"glove": pick["gloves"]["color"],
		"web": web["color"],
		"glow": web.get("glow", web["color"]),
		"rainbow": web.get("rainbow", false),
		"head": pick["head"]["model"],
		"face": pick["face"]["model"],
		"gadget": pick["gadget"],
	}


static func owned_count() -> int:
	return items().filter(func(it): return owns(it["id"])).size()
