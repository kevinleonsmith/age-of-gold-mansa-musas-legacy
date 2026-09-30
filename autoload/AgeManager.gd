# Age progression (res://autoload/AgeManager.gd)
# Sand Chiefdoms -> Mali Ascendancy -> Golden Hajj. Advancing needs buildings
# (and gold mines), costs resources from GameData and raises passive income.
extends Node

signal age_changed(new_age)

enum AGES { SAND_CHIEFDOMS, MALI_ASCENDANCY, GOLDEN_HAJJ }

const AGE_NAMES := {
	AGES.SAND_CHIEFDOMS: "Sand Chiefdoms (1200–1300)",
	AGES.MALI_ASCENDANCY: "Mali Ascendancy (1300–1324)",
	AGES.GOLDEN_HAJJ: "Golden Hajj (1324–1337)",
}

# Cost to advance, keyed by the age you are advancing FROM.
const ADVANCE_COSTS := {
	AGES.SAND_CHIEFDOMS: {"gold": 500, "salt": 0, "manuscripts": 0},
	AGES.MALI_ASCENDANCY: {"gold": 1000, "salt": 0, "manuscripts": 5},
}

# Building / territory prerequisites, keyed by the age you are advancing FROM
# (design doc): I->II needs 5 houses + 1 mosque; II->III needs 3 mosques and
# control of 2 gold mines. Keys are building types ("building_<type>" groups)
# or "gold_mine" (GOLD ResourceNodes still in the scene).
const ADVANCE_REQUIREMENTS := {
	AGES.SAND_CHIEFDOMS: {"house": 5, "mosque": 1},
	AGES.MALI_ASCENDANCY: {"mosque": 3, "gold_mine": 2},
}

const REQUIREMENT_LABELS := {
	"house": ["house", "houses"],
	"mosque": ["mosque", "mosques"],
	"gold_mine": ["gold mine", "gold mines"],
}

# Passive gold per second in each age.
const AGE_INCOME := {
	AGES.SAND_CHIEFDOMS: 1,
	AGES.MALI_ASCENDANCY: 2,
	AGES.GOLDEN_HAJJ: 4,
}

var current_age := AGES.SAND_CHIEFDOMS

func _ready() -> void:
	_apply_age_effects()

# Back to the first age (call after GameData.reset(), which resets income).
func reset() -> void:
	current_age = AGES.SAND_CHIEFDOMS
	_apply_age_effects()
	age_changed.emit(current_age)

func is_max_age() -> bool:
	return current_age >= AGES.GOLDEN_HAJJ

# Cost of advancing from the current age, or {} at the final age.
func get_next_age_cost() -> Dictionary:
	if is_max_age():
		return {}
	return ADVANCE_COSTS.get(current_age, {})

func can_advance() -> bool:
	if is_max_age():
		return false
	return GameData.can_afford(get_next_age_cost()) and get_unmet_requirements().is_empty()

# Missing prerequisites for the next age, e.g. ["3 more houses", "1 more mosque"].
func get_unmet_requirements() -> PackedStringArray:
	var unmet: PackedStringArray = []
	if is_max_age():
		return unmet
	var reqs: Dictionary = ADVANCE_REQUIREMENTS.get(current_age, {})
	for key in reqs:
		var missing := int(reqs[key]) - count_requirement(key)
		if missing > 0:
			var labels: Array = REQUIREMENT_LABELS.get(key, [key, key])
			unmet.append("%d more %s" % [missing, labels[0] if missing == 1 else labels[1]])
	return unmet

# How many of a requirement the player currently has.
func count_requirement(key: String) -> int:
	if not is_inside_tree():
		return 0
	if key == "gold_mine":
		return count_gold_mines()
	var count := 0
	for node in get_tree().get_nodes_in_group("building_" + key):
		if not node.is_queued_for_deletion():
			count += 1
	return count

# GOLD ResourceNodes still standing in the current scene.
func count_gold_mines() -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return 0
	var count := 0
	for node in scene.find_children("*", "Area2D", true, false):
		var res := node as ResourceNode
		if res and res.resource_type == ResourceNode.RESOURCE_TYPE.GOLD \
				and res.quantity > 0 and not res.is_queued_for_deletion():
			count += 1
	return count

# Pays the cost and moves to the next age. Returns false if not possible.
func advance_age() -> bool:
	if not can_advance():
		return false
	if not GameData.spend(get_next_age_cost()):
		return false
	var old_income: int = AGE_INCOME.get(current_age, 1)
	current_age = (current_age + 1) as AGES
	# Add the difference so bonuses from houses etc. are kept.
	GameData.income_per_second += AGE_INCOME.get(current_age, 1) - old_income
	age_changed.emit(current_age)
	return true

func get_age_name(age: int = current_age) -> String:
	return AGE_NAMES.get(age, "Unknown Age")

# Short name without the year range, e.g. "Mali Ascendancy".
func get_age_short_name(age: int = current_age) -> String:
	return get_age_name(age).get_slice(" (", 0)

func is_unlocked(age: int) -> bool:
	return current_age >= age

# Kept for compatibility: the scaled (inflation-aware) cost string.
func format_cost(cost: Dictionary) -> String:
	return GameData.format_cost(cost)

# Sets the base income for the starting age (called once at startup).
func _apply_age_effects() -> void:
	GameData.income_per_second = AGE_INCOME.get(current_age, 1)
