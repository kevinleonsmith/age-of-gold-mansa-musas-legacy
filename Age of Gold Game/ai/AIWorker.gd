# AI empire worker (res://ai/AIWorker.gd)
# A porter owned by an AIEmpire (ai/AIEmpire.gd). It walks to the gold / salt
# ResourceNode it is assigned and stands beside it; while it is there (and no
# player unit contests the node) its empire earns proximity income. It never
# uses ResourceNode's player-only harvest. Hostile to the player: it sits in
# "enemies" so the Mansa and allied units can cut it down (small bounty).
# Groups: "enemies", "ai_units", "ai_workers", "ai_empire_<id>".
extends Unit

const SPEED := 110.0
# Close enough to the node to earn income.
const HARVEST_RADIUS := 70.0
const STAND_DISTANCE := 44.0
const BOUNTY := 10

var empire = null # owning AIEmpire (untyped: it may be freed first)
var empire_id := 0
var target_node = null # ResourceNode (untyped: may be freed at any time)
# Multiplies walking speed (the empire's time_scale, for fast-forwarded tests).
var time_scale := 1.0
var _stand_offset := Vector2.ZERO

func _init() -> void:
	max_health = 50.0
	attack_damage = 0.0
	attack_range = 0.0
	vision_radius = 0.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("ai_units")
	add_to_group("ai_workers")

# Sends the worker to `node` (null: stay put).
func assign(node) -> void:
	target_node = node
	var angle := randf() * TAU
	_stand_offset = Vector2(STAND_DISTANCE, 0).rotated(angle) * Vector2(1.0, 0.6)

func has_target() -> bool:
	return is_instance_valid(target_node) and not target_node.is_queued_for_deletion()

func is_harvesting() -> bool:
	return not is_dead and has_target() \
		and global_position.distance_to(target_node.global_position) <= HARVEST_RADIUS

func stand_point() -> Vector2:
	return target_node.global_position + _stand_offset if has_target() else global_position

func _speed() -> float:
	return SPEED * GameData.get_modifier("sandstorm_slow_mult")

func _physics_process(_delta: float) -> void:
	if is_dead or not has_target():
		velocity = Vector2.ZERO
		return
	var point := stand_point()
	if global_position.distance_to(point) <= 6.0:
		velocity = Vector2.ZERO
		return
	velocity = global_position.direction_to(point) * _speed() * time_scale
	move_and_slide()

# Fast-forward: moves straight toward the stand point, no physics (tests / tick()).
func advance(seconds: float) -> void:
	if is_dead or not has_target():
		return
	global_position = global_position.move_toward(stand_point(), _speed() * seconds)

func _on_died() -> void:
	GameData.gold += BOUNTY
	queue_free()
