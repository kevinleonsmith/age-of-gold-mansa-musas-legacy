# Taghaza Salt Cathedral wonder (res://buildings/SaltCathedral.gd):
# doubles salt harvested while it stands.
extends Building

const SALT_FACTOR := 2.0

func _apply_effects() -> void:
	GameData.multiply_modifier("salt_harvest_mult", SALT_FACTOR)

func _remove_effects() -> void:
	GameData.multiply_modifier("salt_harvest_mult", 1.0 / SALT_FACTOR)
