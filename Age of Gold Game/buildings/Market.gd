# Market (res://buildings/Market.gd): with the "gold_standard" tech,
# generates gold on an interval.
extends Building

@export var gold_interval := 60.0
@export var gold_per_interval := 5

var _gold_timer := 0.0

func _process(delta: float) -> void:
	if is_destroyed or not TechManager.is_researched("gold_standard"):
		return
	_gold_timer += delta
	if gold_interval > 0.0 and _gold_timer >= gold_interval:
		_gold_timer -= gold_interval
		GameData.gold += gold_per_interval
