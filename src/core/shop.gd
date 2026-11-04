class_name Shop
extends RefCounted
## The shop: everything the hero can wear, bought with coins earned by
## swinging (see CoinMeter). Ownership and the equipped outfit live in
## SaveData ("owned", "outfit"; the suit stays in "suit" as before).
## Free items (price 0, no req) are always owned. Suits with a `req` are the
## old progression suits: earned through play (Progress.unlocked), not sold.

## "hero" is who you are (face, skin, hair, eyes); "top" the cut of the
## skin-tight top ("suit" stays its colour, for old saves); "face" holds the
## masks and eyewear (the slot id is kept for old saves).
const SLOTS := [
	["hero", "Faces"], ["hair", "Hair"], ["top", "Tops"], ["suit", "Colours"], ["pants", "Trousers"], ["shoes", "Shoes"],
	["gloves", "Gloves"], ["head", "Hats"], ["face", "Masks"], ["web", "Webs"], ["gadget", "Gadgets"],
]
const DEFAULTS := {"hero": "hero_kai", "hair": "hair_natural", "top": "top_long", "suit": "ember", "pants": "pants_navy",
	"shoes": "shoes_classic", "gloves": "gloves_black", "head": "head_bare", "face": "mask_courier",
	"web": "web_classic", "gadget": "gadget_none"}
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
	# Faces (character.glb Face_<face> / Hair_<face>): skin, hair and eye
	# colours are tints. All free: who you are isn't for sale.
	{"id": "hero_kai", "slot": "hero", "name": "Kai", "face": "kai", "style": "buzz", "skin": Color(0.6, 0.42, 0.3),
		"hair": Color(0.06, 0.045, 0.035), "eyes": Color(0.28, 0.17, 0.08), "price": 0},
	{"id": "hero_ade", "slot": "hero", "name": "Ade", "face": "ade", "style": "crop", "skin": Color(0.32, 0.2, 0.14),
		"hair": Color(0.03, 0.025, 0.02), "eyes": Color(0.16, 0.09, 0.05), "price": 0},
	{"id": "hero_ren", "slot": "hero", "name": "Ren", "face": "ren", "style": "crop", "skin": Color(0.84, 0.66, 0.52),
		"hair": Color(0.04, 0.035, 0.035), "eyes": Color(0.2, 0.12, 0.06), "price": 0},
	{"id": "hero_theo", "slot": "hero", "name": "Theo", "face": "theo", "style": "buzz", "skin": Color(0.9, 0.72, 0.62),
		"hair": Color(0.36, 0.22, 0.12), "eyes": Color(0.26, 0.42, 0.55), "price": 0},
	{"id": "hero_malik", "slot": "hero", "name": "Malik", "face": "malik", "style": "crop", "skin": Color(0.46, 0.3, 0.2),
		"hair": Color(0.05, 0.04, 0.03), "eyes": Color(0.22, 0.13, 0.06), "price": 0},
	# Hair (character.glb Hair_<style>_<face>: every cut is fitted to every
	# face's own scalp). Natural = the face's own cut; the colour stays the
	# face's. Hidden under the beanie, the balaclava and the courier hood.
	{"id": "hair_natural", "slot": "hair", "name": "Natural", "style": "", "price": 0},
	{"id": "hair_buzz", "slot": "hair", "name": "Buzz Cut", "style": "buzz", "price": 0},
	{"id": "hair_crop", "slot": "hair", "name": "Crop", "style": "crop", "price": 0},
	{"id": "hair_fade", "slot": "hair", "name": "High Fade", "style": "fade", "price": 300},
	{"id": "hair_curls", "slot": "hair", "name": "Curls", "style": "curls", "price": 400},
	{"id": "hair_pixie", "slot": "hair", "name": "Pixie", "style": "pixie", "price": 300},
	{"id": "hair_bob", "slot": "hair", "name": "Bob", "style": "bob", "price": 400},
	{"id": "hair_ponytail", "slot": "hair", "name": "Ponytail", "style": "ponytail", "price": 400},
	{"id": "hair_bun", "slot": "hair", "name": "Bun", "style": "bun", "price": 400},
	# Tops: skin-tight compression, the colour comes from the Colours slot.
	{"id": "top_long", "slot": "top", "name": "Long Sleeve", "cut": "long", "price": 0},
	{"id": "top_tq", "slot": "top", "name": "Three-Quarter", "cut": "tq", "price": 0},
	{"id": "top_short", "slot": "top", "name": "Short Sleeve", "cut": "short", "price": 0},
	{"id": "top_vest", "slot": "top", "name": "Sleeveless", "cut": "vest", "price": 150},
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
	{"id": "head_bare", "slot": "head", "name": "No Hat", "model": "", "price": 0},
	{"id": "head_cap", "slot": "head", "name": "Cap", "model": "cap", "price": 600},
	{"id": "head_beanie", "slot": "head", "name": "Beanie", "model": "beanie", "price": 700},
	{"id": "head_phones", "slot": "head", "name": "Headphones", "model": "headphones", "price": 1000},
	{"id": "head_crown", "slot": "head", "name": "Crown", "model": "crown", "price": 5000},
	# Masks (character.glb Mask_<mask>, fitted to the face) and eyewear
	# (gear.glb models). The Courier mask is the original signature look.
	{"id": "face_none", "slot": "face", "name": "None", "model": "", "price": 0},
	{"id": "mask_courier", "slot": "face", "name": "Courier", "model": "", "mask": "courier", "price": 0},
	{"id": "mask_runner", "slot": "face", "name": "Runner", "model": "", "mask": "runner", "price": 300},
	{"id": "mask_domino", "slot": "face", "name": "Domino", "model": "", "mask": "domino", "price": 400},
	{"id": "mask_balaclava", "slot": "face", "name": "Balaclava", "model": "", "mask": "balaclava", "price": 500},
	{"id": "mask_respirator", "slot": "face", "name": "Respirator", "model": "", "mask": "respirator", "price": 900},
	{"id": "face_shades", "slot": "face", "name": "Shades", "model": "shades", "price": 500},
	{"id": "face_mask", "slot": "face", "name": "Bandana", "model": "", "mask": "bandana", "price": 700},
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
	var hero: Dictionary = pick["hero"]
	return {
		"hero": hero["face"],
		"hair_style": pick["hair"]["style"] if pick["hair"]["style"] != "" else hero["style"],
		"skin": hero["skin"],
		"hair": hero["hair"],
		"eyes": hero["eyes"],
		"top": pick["top"]["cut"],
		"mask": pick["face"].get("mask", ""),
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


## Masks that cover the hair (and, for the courier hood, the face).
const HAIR_MASKS := ["courier", "balaclava"]


## The look for trying `id` on in the shop: a face or a haircut is shown
## without whatever would hide it (the hood or balaclava; the beanie for hair).
static func try_on(slot: String, id: String) -> Dictionary:
	var p := {slot: id}
	if slot in ["hero", "hair"]:
		if item(equipped("face")).get("mask", "") in HAIR_MASKS:
			p["face"] = "face_none"
		if slot == "hair" and item(equipped("head")).get("model", "") == "beanie":
			p["head"] = "head_bare"
	return look(p)


static func owned_count() -> int:
	return items().filter(func(it): return owns(it["id"])).size()
