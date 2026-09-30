# Camel Lancer ally (res://entities/CamelLancer.gd)
extends Unit

const SPEED := 250.0
const AGGRO_RADIUS := 300.0
const ESCORT_DISTANCE := 150.0
const WANDER_RANGE := 80.0

var target_position := Vector2.ZERO
var idle_time_left := 0.0

func _init() -> void:
	max_health = 120.0
	attack_damage = 15.0
	attack_range = 44.0
	attack_cooldown = 0.8

func _ready() -> void:
	add_to_group("allies")
	add_to_group("camel") # camel riders ignore sandstorms
	target_position = global_position

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var enemy := find_nearest_in_group("enemies", AGGRO_RADIUS)
	if enemy != null:
		_engage(enemy)
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and global_position.distance_to(player.global_position) > ESCORT_DISTANCE:
		# Too far from the player: catch up.
		_move_toward(player.global_position)
		target_position = global_position
		return

	# Near the player (or no player): idle, then wander a little around them.
	if global_position.distance_to(target_position) > 10:
		_move_toward(target_position)
		return
	velocity = Vector2.ZERO
	idle_time_left -= delta
	if idle_time_left <= 0.0:
		idle_time_left = randf_range(1.5, 3.5)
		var center := player.global_position if player != null else global_position
		target_position = center + Vector2(
			randf_range(-WANDER_RANGE, WANDER_RANGE),
			randf_range(-WANDER_RANGE, WANDER_RANGE)
		)

func _engage(enemy: Unit) -> void:
	if global_position.distance_to(enemy.global_position) <= attack_range:
		velocity = Vector2.ZERO
		try_attack(enemy)
	else:
		_move_toward(enemy.global_position)
	target_position = global_position

func _move_toward(point: Vector2) -> void:
	velocity = global_position.direction_to(point) * SPEED
	move_and_slide()
