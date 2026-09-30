# AI empire library (res://ai/AIBuilding.gd, scene ai/AILibrary.tscn)
# A destructible AI building that produces manuscripts for its AIEmpire (the
# empire does the accounting; this node only has to exist). Like
# rival/RivalBuilding.gd it extends Unit so player units find it through
# Unit.find_nearest_in_group("enemies") and hit it with try_attack.
# Groups: "rival_buildings", "enemies", "ai_libraries", "ai_empire_<id>".
extends Unit

signal destroyed

var is_destroyed := false
var empire_id := 0

func _init() -> void:
	max_health = 300.0
	attack_damage = 0.0
	attack_range = 0.0
	vision_radius = 0.0

func _ready() -> void:
	add_to_group("rival_buildings")
	add_to_group("enemies")
	add_to_group("ai_libraries")

# Buildings are not poisoned, drained or boosted.
func _process(_delta: float) -> void:
	pass

func apply_poison(_dps: float, _duration: float) -> void:
	pass

func apply_morale_boost(_multiplier: float, _duration: float) -> void:
	pass

func take_damage(amount: float) -> void:
	if is_destroyed or amount <= 0.0:
		return
	super(amount)

func _on_died() -> void:
	is_destroyed = true
	for group in ["rival_buildings", "enemies", "ai_libraries"]:
		remove_from_group(group)
	GameData.gold += 60
	destroyed.emit()
	queue_free()

func get_footprint_rect() -> Rect2:
	return Rect2(global_position - Vector2(26, 16), Vector2(52, 32))

func _draw() -> void:
	if is_destroyed or health >= max_health:
		return
	var bar := Rect2(-28, -64, 56, 5)
	draw_rect(bar, Color(0.3, 0, 0, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / max_health, bar.size.y)), Color(0.85, 0.2, 0.15))
	draw_rect(bar, Color(0, 0, 0, 0.9), false, 1.0)
