class_name Homes
extends RefCounted
## Home ownership on top of SaveData (no new currency: coins, like the Shop).
## "homes": owned home ids (the starter is always owned), "home": the one
## Free Swing starts in. Prices live in Apartments.TIERS.

static func _save() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("SaveData")


static func spec(id: String) -> Dictionary:
	for t in Apartments.TIERS:
		if t["id"] == id:
			return t
	return {}


static func owns(id: String) -> bool:
	if id == "starter":
		return true
	var sd := _save()
	return sd != null and id in (sd.data.get("homes", []) as Array)


static func selected() -> String:
	var sd := _save()
	var id: String = sd.data.get("home", "starter") if sd else "starter"
	return id if owns(id) else "starter"


static func price(id: String) -> int:
	return int(spec(id).get("price", 0))


## Buys `id` with coins (and makes it home). False if unaffordable or owned.
static func buy(id: String) -> bool:
	var sd := _save()
	if sd == null or owns(id) or spec(id).is_empty():
		return false
	var p := price(id)
	if int(sd.data.get("coins", 0)) < p:
		return false
	sd.data["coins"] = int(sd.data["coins"]) - p
	var owned: Array = sd.data.get("homes", [])
	owned.append(id)
	sd.data["homes"] = owned
	sd.data["home"] = id
	sd.save()
	return true


static func select(id: String) -> bool:
	var sd := _save()
	if sd == null or not owns(id):
		return false
	sd.data["home"] = id
	sd.save()
	return true
