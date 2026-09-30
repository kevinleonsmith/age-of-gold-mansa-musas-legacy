# Mud house (res://buildings/House.gd): +1 passive gold per second.
extends Building

@export var income_bonus := 1

func _apply_effects() -> void:
	GameData.income_per_second += income_bonus

func _remove_effects() -> void:
	GameData.income_per_second -= income_bonus
