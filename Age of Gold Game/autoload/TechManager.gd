# Tech tree (res://autoload/TechManager.gd)
# Data-driven tech tree based on the design doc's "Complete Tech Tree".
# One research runs at a time; progress advances in _process.
#
# Skipped from the doc: Salt Preservation (no food system exists) and
# Siege Ladders (no walls exist).
extends Node

signal research_started(tech_id: String)
signal tech_researched(tech_id: String)
signal research_progress(tech_id: String, progress: float)
signal research_cancelled(tech_id: String)

# Sankore Scholars: each mosque makes research 20% faster, up to 3 mosques.
const MOSQUE_SPEEDUP := 0.8
const MAX_MOSQUES := 3
const CANCEL_REFUND := 0.5
const AgeScript := preload("res://autoload/AgeManager.gd")

var researched := {}

# Tech dicts in display order. Built in _init because effects are lambdas.
var techs: Array = []
var _by_id := {}

var _current_id := ""
var _elapsed := 0.0
var _duration := 0.0
var _paid_cost := {}

func _init() -> void:
	var A: Dictionary = AgeScript.AGES
	_add("mud_architecture", "Mud Architecture", A.SAND_CHIEFDOMS, {"gold": 200}, 25.0,
		"Djenné-style mud walls: buildings +15% HP.",
		func(): GameData.multiply_modifier("building_hp_mult", 1.15))
	_add("camel_saddlecraft", "Camel Saddlecraft", A.SAND_CHIEFDOMS, {"salt": 150}, 20.0,
		"Better saddles: caravans carry 25% more cargo.",
		func(): GameData.multiply_modifier("caravan_cargo_mult", 1.25))
	_add("oral_histories", "Oral Histories", A.SAND_CHIEFDOMS, {"manuscripts": 1}, 20.0,
		"Griot knowledge: all harvesting yields +10%.",
		func(): GameData.multiply_modifier("harvest_mult", 1.1))
	_add("poisoned_spears", "Poisoned Spears", A.MALI_ASCENDANCY, {"gold": 300, "salt": 50}, 30.0,
		"Allied hits poison enemies for 3 DPS over 3 s.",
		func(): GameData.add_modifier("poison_dps", 3.0))
	_add("leather_shields", "Leather Shields", A.MALI_ASCENDANCY, {"gold": 200}, 25.0,
		"Allied units take 10% less damage.",
		func(): GameData.multiply_modifier("ally_damage_taken_mult", 0.9))
	_add("gold_standard", "Gold Standard", A.MALI_ASCENDANCY, {"gold": 400}, 35.0,
		"Markets generate +5 Gold every 60 s.",
		func(): pass)
	_add("caravan_guards", "Caravan Guards", A.MALI_ASCENDANCY, {"gold": 200}, 25.0,
		"Caravans take 30% less damage.",
		func(): GameData.multiply_modifier("caravan_damage_taken_mult", 0.7))
	_add("friday_mosques", "Friday Mosques", A.GOLDEN_HAJJ, {"manuscripts": 3}, 35.0,
		"Buildings cost 15% less.",
		func(): GameData.multiply_modifier("building_cost_mult", 0.85))
	_add("sankore_curriculum", "Sankore Curriculum", A.GOLDEN_HAJJ, {"manuscripts": 5}, 40.0,
		"All research is 30% faster.",
		func(): GameData.multiply_modifier("research_time_mult", 0.7))
	_add("mansas_blessing", "Mansa's Blessing", A.GOLDEN_HAJJ, {"gold": 1000}, 45.0,
		"Mosques heal allies within 150 px by 3 HP/s.",
		func(): pass)
	_add("salt_monopoly", "Salt Monopoly", A.GOLDEN_HAJJ, {"salt": 500}, 40.0,
		"Enemy units lose 1 HP per second.",
		func(): GameData.add_modifier("enemy_hp_drain", 1.0))
	_add("manuscript_bazaar", "Manuscript Bazaar", A.GOLDEN_HAJJ, {"manuscripts": 7}, 35.0,
		"Unlocks selling manuscripts for 200 Gold each.",
		func(): pass)
	_add("hyperinflation", "Hyperinflation", A.GOLDEN_HAJJ, {"ingots": 10}, 45.0,
		"Rival treasuries drain 3x faster.",
		func(): pass)
	# Granted only by the Inflation Debate event; never researchable.
	_add("economic_stabilization", "Economic Stabilization", A.MALI_ASCENDANCY, {}, 0.0,
		"Price index recovers 2x faster.",
		func(): pass, true)

func _add(id: String, tech_name: String, age: int, cost: Dictionary, time: float,
		desc: String, effects: Callable, hidden := false) -> void:
	var tech := {
		"id": id, "name": tech_name, "age": age, "cost": cost,
		"research_time": time, "description": desc, "effects": effects,
		"hidden": hidden,
	}
	techs.append(tech)
	_by_id[id] = tech

# Forgets all research (modifiers are cleared by GameData.reset()).
func reset() -> void:
	var current := _current_id
	_clear_current()
	researched.clear()
	if current != "":
		research_cancelled.emit(current)

# --- Queries ---------------------------------------------------------------

func is_researched(tech_id: String) -> bool:
	return researched.has(tech_id)

func get_tech(tech_id: String) -> Dictionary:
	return _by_id.get(tech_id, {})

# Researchable techs in display order (hidden ones excluded).
func get_all_techs() -> Array:
	return techs.filter(func(t): return not t["hidden"])

func get_current_research() -> String:
	return _current_id

func is_researching() -> bool:
	return _current_id != ""

func get_progress() -> float:
	if _current_id == "" or _duration <= 0.0:
		return 0.0
	return clampf(_elapsed / _duration, 0.0, 1.0)

func is_age_unlocked(tech_id: String) -> bool:
	var tech := get_tech(tech_id)
	return not tech.is_empty() and AgeManager.is_unlocked(tech["age"])

# Research time after research_time_mult and the mosque speed-up.
func get_research_time(tech_id: String) -> float:
	var tech := get_tech(tech_id)
	if tech.is_empty():
		return 0.0
	var mosques := mini(get_tree().get_nodes_in_group("building_mosque").size(), MAX_MOSQUES) \
		if is_inside_tree() else 0
	return float(tech["research_time"]) * GameData.get_modifier("research_time_mult") \
		* pow(MOSQUE_SPEEDUP, mosques)

func can_research(tech_id: String) -> bool:
	var tech := get_tech(tech_id)
	if tech.is_empty() or tech["hidden"]:
		return false
	if is_researched(tech_id) or is_researching():
		return false
	if not AgeManager.is_unlocked(tech["age"]):
		return false
	return GameData.can_afford(tech["cost"])

# --- Actions ---------------------------------------------------------------

func start_research(tech_id: String) -> bool:
	if not can_research(tech_id):
		return false
	var tech := get_tech(tech_id)
	var paid := GameData.scaled_cost(tech["cost"])
	if not GameData.spend(tech["cost"]):
		return false
	_paid_cost = paid
	_current_id = tech_id
	_elapsed = 0.0
	_duration = get_research_time(tech_id)
	research_started.emit(tech_id)
	research_progress.emit(tech_id, 0.0)
	return true

# Stops the current research and refunds half of what was paid.
func cancel_research() -> void:
	if _current_id == "":
		return
	var id := _current_id
	var refund := {}
	for key in _paid_cost:
		refund[key] = int(floor(int(_paid_cost[key]) * CANCEL_REFUND))
	_clear_current()
	GameData.add_resources(refund)
	research_cancelled.emit(id)
	research_progress.emit(id, 0.0)

# Instantly completes a tech with no cost (used by events). Applies its effects.
func grant_tech(tech_id: String) -> void:
	if is_researched(tech_id):
		return
	if tech_id == _current_id:
		_clear_current()
	_complete(tech_id)

func _process(delta: float) -> void:
	if _current_id == "":
		return
	_elapsed += delta
	var id := _current_id
	if _elapsed >= _duration:
		_clear_current()
		research_progress.emit(id, 1.0)
		_complete(id)
	else:
		research_progress.emit(id, get_progress())

func _clear_current() -> void:
	_current_id = ""
	_elapsed = 0.0
	_duration = 0.0
	_paid_cost = {}

func _complete(tech_id: String) -> void:
	researched[tech_id] = true
	var tech := get_tech(tech_id)
	if not tech.is_empty():
		(tech["effects"] as Callable).call()
	tech_researched.emit(tech_id)
