# Unit training menu (res://ui/UnitMenu.gd)
# Left-edge vertical panel with one button per trainable unit. Each button
# shows the unit icon, name and scaled cost; its tooltip gives the role, or
# the reason it is disabled (age-locked, unaffordable, unique hero alive).
# Units are bought through GameData.spend() and spawn at the player.
#
# Public API:
#   train(unit_id) -> Node          spend + spawn; null (and a toast) on failure
#   can_train(unit_id) -> bool
#   get_block_reason(unit_id) -> String   "" when trainable
#   get_button(unit_id) -> Button
#   get_cost(unit_id) -> Dictionary        unscaled cost
#   refresh_buttons()
#   signal unit_trained(unit_id, unit)
extends CanvasLayer

signal unit_trained(unit_id: String, unit: Node)

const ORDER := ["camel_lancer", "griot_bard", "desert_scout", "gold_gilder", "donson_ton", "golden_mansa"]

const UNITS := {
	"camel_lancer": {
		"name": "Camel Lancer",
		"scene": "res://entities/CamelLancer.tscn",
		"icon": "res://assets/sprites/camel_lancer.png",
		"cost": {"gold": 50},
		"age": 0,
		"role": "Mounted escort that charges nearby enemies. Ignores sandstorms.",
	},
	"griot_bard": {
		"name": "Griot Bard",
		"scene": "res://entities/GriotBard.tscn",
		"icon": "res://assets/sprites/griot_bard.png",
		"cost": {"gold": 75, "manuscripts": 1},
		"age": 1,
		"role": "Support: morale songs boost nearby allies and slowly convert enemies.",
	},
	"desert_scout": {
		"name": "Desert Scout",
		"scene": "res://entities/DesertScout.tscn",
		"icon": "res://assets/units/desert_scout.png",
		"cost": {"gold": 80},
		"age": 0,
		"role": "Fast camel rider: ranges ahead of you and marks the nearest enemy. Ignores sandstorms.",
	},
	"gold_gilder": {
		"name": "Gold Gilder",
		"scene": "res://entities/GoldGilder.tscn",
		"icon": "res://assets/units/gold_gilder.png",
		"cost": {"gold": 120},
		"age": 1,
		"role": "Craftsman: turns 100 Gold into 1 Ingot every 30 s. Does not fight.",
	},
	"donson_ton": {
		"name": "Donson Ton",
		"scene": "res://entities/DonsonTon.tscn",
		"icon": "res://assets/units/donson_ton.png",
		"cost": {"gold": 150, "salt": 30},
		"age": 1,
		"role": "Elite hunter-guard: stays at your side, poisoned spears (-3 HP/s).",
	},
	"golden_mansa": {
		"name": "Golden Mansa",
		"scene": "res://entities/GoldenMansa.tscn",
		"icon": "res://assets/units/golden_mansa.png",
		"cost": {"gold": 2000},
		"age": 2,
		"unique": true,
		"role": "Unique hero: golden aura converts enemies (5 HP/s) and gives away gold to cool inflation.",
	},
}

const AGE_NUMERALS := ["I", "II", "III"]

var _buttons := {}
var _refresh_queued := false

@onready var _list: VBoxContainer = %UnitList

func _ready() -> void:
	for id in ORDER:
		var def: Dictionary = UNITS[id]
		var button := Button.new()
		button.name = "Train_" + id
		button.focus_mode = Control.FOCUS_NONE # Space is the attack key
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = load(def["icon"])
		button.expand_icon = true
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_constant_override("icon_max_width", 32)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_button_pressed.bind(id))
		_list.add_child(button)
		_buttons[id] = button
	# Resource changes refresh synchronously so the buttons are always current.
	GameData.gold_changed.connect(_on_resources_changed)
	GameData.salt_changed.connect(_on_resources_changed)
	GameData.manuscripts_changed.connect(_on_resources_changed)
	GameData.ingots_changed.connect(_on_resources_changed)
	GameData.modifiers_changed.connect(_queue_refresh.unbind(2))
	AgeManager.age_changed.connect(_on_resources_changed)
	refresh_buttons()

func _on_resources_changed(_value) -> void:
	refresh_buttons()

func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	refresh_buttons.call_deferred()

# --- Public API ---------------------------------------------------------------

func get_button(unit_id: String) -> Button:
	return _buttons.get(unit_id)

func get_cost(unit_id: String) -> Dictionary:
	return UNITS[unit_id]["cost"] if UNITS.has(unit_id) else {}

func hero_alive() -> bool:
	for node in get_tree().get_nodes_in_group("hero"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and not node.get("is_dead"):
			return true
	return false

# Why unit_id can't be trained right now, or "" if it can.
func get_block_reason(unit_id: String) -> String:
	if not UNITS.has(unit_id):
		return "Unknown unit"
	var def: Dictionary = UNITS[unit_id]
	if not AgeManager.is_unlocked(def["age"]):
		return "Requires Age %s" % AGE_NUMERALS[def["age"]]
	if def.get("unique", false) and hero_alive():
		return "Only one %s may live at a time" % def["name"]
	if not GameData.can_afford(def["cost"]):
		return "Not enough resources (needs %s)" % GameData.format_cost(def["cost"])
	return ""

func can_train(unit_id: String) -> bool:
	return get_block_reason(unit_id) == ""

# Spends the scaled cost and spawns the unit at the player. Returns the new
# unit, or null (with a toast) if it can't be trained.
func train(unit_id: String) -> Node:
	var reason := get_block_reason(unit_id)
	var scene := get_tree().current_scene
	if reason == "" and scene == null:
		reason = "No scene to spawn into"
	if reason != "" or not GameData.spend(get_cost(unit_id)):
		if reason == "":
			reason = "Not enough resources"
		_toast("Cannot train %s: %s" % [UNITS.get(unit_id, {}).get("name", unit_id), reason], Color(1.0, 0.5, 0.4))
		AudioManager.play_sfx("error")
		return null
	var unit := (load(UNITS[unit_id]["scene"]) as PackedScene).instantiate() as Node2D
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		unit.position = player.global_position + Vector2(randf_range(-24, 24), randf_range(20, 36))
	scene.add_child(unit)
	unit.tree_exited.connect(_queue_refresh)
	AudioManager.play_sfx("click")
	unit_trained.emit(unit_id, unit)
	refresh_buttons()
	return unit

func refresh_buttons() -> void:
	_refresh_queued = false
	for id in _buttons:
		var def: Dictionary = UNITS[id]
		var button: Button = _buttons[id]
		var reason := get_block_reason(id)
		button.text = "%s\n%s" % [def["name"], GameData.format_cost(def["cost"])]
		button.disabled = reason != ""
		var tip := "%s (%s)\n%s" % [def["name"], GameData.format_cost(def["cost"]), def["role"]]
		if reason != "":
			tip += "\nUnavailable: " + reason
		button.tooltip_text = tip

# --- Internals ----------------------------------------------------------------

func _on_button_pressed(unit_id: String) -> void:
	train(unit_id)

func _toast(text: String, color: Color) -> void:
	var toasts := get_tree().get_first_node_in_group("toasts")
	if toasts != null and toasts.has_method("show_toast"):
		toasts.show_toast(text, color)
