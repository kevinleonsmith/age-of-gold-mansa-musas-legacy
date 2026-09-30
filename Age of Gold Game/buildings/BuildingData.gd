# Building catalogue (res://buildings/BuildingData.gd)
# Base costs, age locks and scenes for every building type. Stats (HP,
# footprint, sprite) live in each type's scene.
class_name BuildingData
extends RefCounted

const TYPES := ["house", "mosque", "market", "outpost", "great_mosque", "salt_cathedral"]

const DEFS := {
	"house": {
		"name": "House", "cost": {"gold": 50}, "age": 0,
		"scene": "res://buildings/House.tscn",
		"desc": "+1 passive Gold/s while it stands.",
	},
	"mosque": {
		"name": "Mosque", "cost": {"gold": 150, "salt": 20}, "age": 0,
		"scene": "res://buildings/Mosque.tscn",
		"desc": "+1 Manuscript every 60 s. With Mansa's Blessing, heals nearby allies.",
	},
	"market": {
		"name": "Market", "cost": {"gold": 120}, "age": 1,
		"scene": "res://buildings/Market.tscn",
		"desc": "With Gold Standard, +5 Gold every 60 s.",
	},
	"outpost": {
		"name": "Trade Outpost", "cost": {"gold": 200, "salt": 100}, "age": 0,
		"scene": "res://buildings/Outpost.tscn",
		"desc": "Home and drop-off point for caravans.",
	},
	"great_mosque": {
		"name": "Great Mosque", "cost": {"gold": 1500, "manuscripts": 10}, "age": 1,
		"scene": "res://buildings/GreatMosque.tscn", "wonder": true,
		"desc": "Wonder. Timbuktu University: +1 Manuscript every 90 s.",
	},
	"salt_cathedral": {
		"name": "Salt Cathedral", "cost": {"salt": 2000, "ingots": 5}, "age": 2,
		"scene": "res://buildings/SaltCathedral.tscn", "wonder": true,
		"desc": "Wonder. Doubles salt harvested.",
	},
}

static func get_display_name(type: String) -> String:
	return DEFS[type]["name"] if DEFS.has(type) else type

static func get_required_age(type: String) -> int:
	return int(DEFS[type]["age"]) if DEFS.has(type) else 0

static func is_wonder(type: String) -> bool:
	return DEFS.has(type) and bool(DEFS[type].get("wonder", false))

# Base cost with "building_cost_mult" applied to every resource. Pass the
# result to GameData.spend / format_cost / can_afford (which add inflation).
static func get_cost(type: String) -> Dictionary:
	var mult := GameData.get_modifier("building_cost_mult")
	var result := {}
	var base: Dictionary = DEFS[type]["cost"] if DEFS.has(type) else {}
	for key in base:
		result[key] = int(ceil(float(base[key]) * mult))
	return result
