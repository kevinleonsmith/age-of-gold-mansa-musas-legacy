# GameManager Autoload (res://autoload/GameData.gd)
extends Node

signal gold_changed(new_value)
signal salt_changed(new_value)
signal manuscripts_changed(new_value)
signal ingots_changed(new_value)
signal modifiers_changed(key: String, value: float)

# Resource keys used in cost / amount dictionaries, e.g. {"gold": 200, "salt": 50}.
const RESOURCES := ["gold", "salt", "manuscripts", "ingots"]
const RESOURCE_LABELS := {"gold": "Gold", "salt": "Salt", "manuscripts": "Manuscript", "ingots": "Ingot"}

# Passive gold per timer tick (1 s). AgeManager raises this each age.
var income_per_second := 1

var gold := 0:
	set(value):
		gold = max(value, 0)
		gold_changed.emit(gold)

var salt := 0:
	set(value):
		salt = max(value, 0)
		salt_changed.emit(salt)

var manuscripts := 0:
	set(value):
		manuscripts = max(value, 0)
		manuscripts_changed.emit(manuscripts)

var ingots := 0:
	set(value):
		ingots = max(value, 0)
		ingots_changed.emit(ingots)

# Global gameplay modifiers set by techs, buildings, events and the economy.
# Multiplicative keys default to 1.0, additive keys to 0.0 (pass the default).
var modifiers := {}

# Bumped by reset(). Delayed effects compare it so they don't leak into a new game.
var generation := 0

func _ready() -> void:
	var gold_timer := Timer.new()
	gold_timer.wait_time = 1.0
	gold_timer.autostart = true
	gold_timer.timeout.connect(_on_GoldTimer_timeout)
	add_child(gold_timer)

func _on_GoldTimer_timeout() -> void:
	gold += income_per_second

# Clears resources, income and every modifier for a fresh game.
# Use GameSession.reset_all() to reset every autoload together.
func reset() -> void:
	generation += 1
	gold = 0
	salt = 0
	manuscripts = 0
	ingots = 0
	income_per_second = 1
	for key in modifiers.keys():
		modifiers.erase(key)
		modifiers_changed.emit(key, get_modifier(key))

# --- Resources -------------------------------------------------------------

func get_amount(resource: String) -> int:
	return int(get(resource))

func add_resources(amounts: Dictionary) -> void:
	for key in amounts:
		if key in RESOURCES:
			set(key, get_amount(key) + int(amounts[key]))

# Cost after price modifiers: "gold_price_mult" (inflation) scales the gold part.
func scaled_cost(cost: Dictionary) -> Dictionary:
	var result := {}
	for key in cost:
		var amount := float(cost[key])
		if key == "gold":
			amount *= get_modifier("gold_price_mult")
		result[key] = int(ceil(amount))
	return result

func can_afford(cost: Dictionary) -> bool:
	var scaled := scaled_cost(cost)
	for key in scaled:
		if get_amount(key) < int(scaled[key]):
			return false
	return true

# Pays the scaled cost. Returns false (and pays nothing) if unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	var scaled := scaled_cost(cost)
	for key in scaled:
		set(key, get_amount(key) - int(scaled[key]))
	return true

# Human-readable scaled cost, e.g. "230 Gold, 5 Manuscripts".
func format_cost(cost: Dictionary) -> String:
	var scaled := scaled_cost(cost)
	var parts: PackedStringArray = []
	for key in RESOURCES:
		var amount := int(scaled.get(key, 0))
		if amount > 0:
			var label: String = RESOURCE_LABELS[key]
			if amount != 1 and key != "gold" and key != "salt":
				label += "s"
			parts.append("%d %s" % [amount, label])
	return ", ".join(parts)

# --- Modifiers -------------------------------------------------------------

func get_modifier(key: String, default := 1.0) -> float:
	return float(modifiers.get(key, default))

func set_modifier(key: String, value: float) -> void:
	modifiers[key] = value
	modifiers_changed.emit(key, value)

# For stacking multiplicative effects: multiply_modifier("harvest_mult", 1.1).
# Undo a temporary effect by multiplying with 1.0 / factor.
func multiply_modifier(key: String, factor: float) -> void:
	set_modifier(key, get_modifier(key, 1.0) * factor)

# For stacking additive effects (default 0.0): add_modifier("poison_dps", 3.0).
func add_modifier(key: String, amount: float) -> void:
	set_modifier(key, get_modifier(key, 0.0) + amount)
