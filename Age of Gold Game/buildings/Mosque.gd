# Mosque (res://buildings/Mosque.gd): produces manuscripts; with the
# "mansas_blessing" tech it heals allied units nearby. The Great Mosque
# wonder reuses this script (90 s interval, no healing).
extends Building

@export var manuscript_interval := 60.0
@export var manuscripts_per_interval := 1
@export var heals_allies := true
@export var heal_radius := 150.0
@export var heal_per_second := 3.0

var _manuscript_timer := 0.0

func _process(delta: float) -> void:
	if is_destroyed:
		return
	_manuscript_timer += delta
	if manuscript_interval > 0.0 and _manuscript_timer >= manuscript_interval:
		_manuscript_timer -= manuscript_interval
		GameData.manuscripts += manuscripts_per_interval
	if heals_allies and TechManager.is_researched("mansas_blessing"):
		_heal_allies(delta)

func _heal_allies(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("allies"):
		var unit := node as Unit
		if unit == null or unit.is_dead or unit.health >= unit.max_health:
			continue
		if unit.global_position.distance_to(global_position) <= heal_radius:
			unit.heal(heal_per_second * delta)
