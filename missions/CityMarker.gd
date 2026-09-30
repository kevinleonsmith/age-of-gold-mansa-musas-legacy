# City marker for campaign maps (res://missions/CityMarker.gd)
# A skyline sprite with a name label, in the "cities" group.
extends Node2D

@export var city_name := "Walata"
@export var texture: Texture2D

func _ready() -> void:
	add_to_group("cities")
	z_index = -1
	if texture != null:
		$Sprite2D.texture = texture
	$Label.text = city_name
