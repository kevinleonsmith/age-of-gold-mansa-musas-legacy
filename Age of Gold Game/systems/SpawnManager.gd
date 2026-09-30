# Enemy Spawner (res://systems/SpawnManager.gd)
# Spawns an enemy every spawn_interval / enemy_spawn_rate_mult seconds.
# A multiplier of 0 pauses spawning; once the rival treasuries collapse
# (EconomyManager.rivals_collapsed) spawning stops for good.
# While Songhai war camps ("rival_camps") stand, the camps do most of the
# spawning, so this ambient spawner runs at camp_rate_factor of its rate.
# max_enemies counts every hostile raider in the scene (ambient, camp and event
# raiders), but not the rival buildings or the rival base's stationary guards.
extends Node

@export var spawn_interval := 10.0
@export var spawn_radius := 500.0
@export var max_enemies := 10
@export var camp_rate_factor := 0.5

const ENEMY_SCENE := preload("res://entities/EnemyAI.tscn")

var _elapsed := 0.0
var stopped := false

func _ready() -> void:
	add_to_group("spawn_manager")
	EconomyManager.rivals_collapsed.connect(_on_rivals_collapsed)
	if EconomyManager.is_rivals_collapsed():
		stopped = true

func _process(delta: float) -> void:
	if stopped:
		return
	var rate := GameData.get_modifier("enemy_spawn_rate_mult")
	if rate <= 0.0:
		return
	if has_rival_camps():
		rate *= camp_rate_factor
	_elapsed += delta * rate
	if _elapsed >= spawn_interval:
		_elapsed -= spawn_interval
		_spawn()

func is_paused() -> bool:
	return GameData.get_modifier("enemy_spawn_rate_mult") <= 0.0

func has_rival_camps() -> bool:
	for camp in get_tree().get_nodes_in_group("rival_camps"):
		if is_instance_valid(camp) and not camp.get("is_destroyed"):
			return true
	return false

# Living hostile raiders anywhere in the scene (skips rival buildings and guards).
func count_raiders() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.is_in_group("rival_buildings") or node.get("is_guard") == true or node.get("is_dead") == true:
			continue
		count += 1
	return count

func _on_rivals_collapsed() -> void:
	stopped = true

func _spawn() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var container: Node = scene.get_node_or_null("Enemies")
	if container == null:
		container = scene
	if count_raiders() >= max_enemies:
		return null
	var new_enemy := ENEMY_SCENE.instantiate() as Node2D
	new_enemy.position = get_random_spawn_position()
	container.add_child(new_enemy)
	return new_enemy

func get_random_spawn_position() -> Vector2:
	var center := Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		center = player.global_position
	return center + Vector2.RIGHT.rotated(randf() * TAU) * spawn_radius
