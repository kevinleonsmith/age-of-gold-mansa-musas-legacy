# Shared campaign mission helpers (res://missions/MissionBase.gd)
# Missions extend this by path: extends "res://missions/MissionBase.gd".
# Override _mission_ready() / _mission_process(delta) instead of _ready /
# _process. Provides a mission clock (mission_time, scaled by time_scale so
# tests can fast-forward), scripted events at a mission time, objectives,
# toasts, spawning and victory / defeat wrappers around VictoryManager.
extends Node2D

const ENEMY_SCENE_PATH := "res://entities/EnemyAI.tscn"
const COLOR_STORY := Color(1.0, 0.9, 0.6)
const COLOR_GOOD := Color(0.6, 1.0, 0.6)
const COLOR_BAD := Color(1.0, 0.55, 0.45)

# Multiplies how fast mission_time runs (tests fast-forward scripted events).
@export var time_scale := 1.0
# Seconds added to the clock at start (skip ahead to a scripted beat).
@export var time_offset := 0.0

var mission_time := 0.0
var finished := false
var _events: Array = []  # [{"time", "callback", "fired"}]

func _ready() -> void:
	VictoryManager.skirmish_conditions_enabled = false
	mission_time = time_offset
	VictoryManager.game_won.connect(_on_game_over.unbind(3))
	VictoryManager.game_lost.connect(_on_game_over.unbind(3))
	_mission_ready()

func _process(delta: float) -> void:
	if finished:
		return
	mission_time += delta * time_scale
	for event in _events:
		if not event["fired"] and mission_time >= float(event["time"]):
			event["fired"] = true
			(event["callback"] as Callable).call()
			if finished:
				return
	_mission_process(delta)

# --- Overridables -------------------------------------------------------------

func _mission_ready() -> void:
	pass

func _mission_process(_delta: float) -> void:
	pass

# --- Clock / scripted events --------------------------------------------------

# Runs callback once when mission_time reaches `at` seconds.
func schedule(at: float, callback: Callable) -> void:
	_events.append({"time": at, "callback": callback, "fired": false})

static func format_clock(seconds: float) -> String:
	var s := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [s / 60, s % 60]

# --- Objectives / outcome -----------------------------------------------------

func set_objectives(list: Array) -> void:
	VictoryManager.set_objectives(list)

func objective_text(id: String, text: String) -> void:
	VictoryManager.set_objective_text(id, text)

func complete(id: String, announce := "") -> void:
	if VictoryManager.is_objective_done(id):
		return
	VictoryManager.complete_objective(id)
	if announce != "":
		toast(announce, COLOR_GOOD)

func is_done(id: String) -> bool:
	return VictoryManager.is_objective_done(id)

func win(title: String, text: String) -> void:
	if finished or VictoryManager.is_game_over:
		return
	finished = true
	VictoryManager.declare_victory("mission", title, text)

func lose(reason_id: String, title: String, text: String) -> void:
	if finished or VictoryManager.is_game_over:
		return
	finished = true
	VictoryManager.declare_defeat(reason_id, title, text)

func _on_game_over() -> void:
	finished = true

# --- Helpers ------------------------------------------------------------------

func toast(text: String, color := COLOR_STORY) -> void:
	var toasts := get_tree().get_first_node_in_group("toasts")
	if toasts != null and toasts.has_method("show_toast"):
		toasts.show_toast(text, color)

func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

# Returns the node named `container_name`, creating a Node2D if missing.
func container(container_name: String) -> Node2D:
	var node := get_node_or_null(container_name) as Node2D
	if node == null:
		node = Node2D.new()
		node.name = container_name
		add_child(node)
	return node

# Spawns an EnemyAI at `pos` (global) under the "Enemies" container. It
# patrols around `guard_point` (defaults to pos).
func spawn_enemy(pos: Vector2, guard_point = null) -> Node2D:
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as Node2D
	enemy.position = pos
	container("Enemies").add_child(enemy)
	if guard_point is Vector2 and "home_position" in enemy:
		enemy.home_position = guard_point
	return enemy

# `count` enemies scattered within `radius` of `center`.
func spawn_group(center: Vector2, count: int, radius := 60.0, guard_point = null) -> Array:
	var spawned := []
	for i in count:
		var angle := TAU * float(i) / maxf(count, 1)
		spawned.append(spawn_enemy(center + Vector2(radius, 0).rotated(angle), guard_point))
	return spawned

func count_enemies_near(point: Vector2, radius: float) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var unit := node as Node2D
		if unit == null or unit.is_queued_for_deletion() or unit.get("is_dead") == true:
			continue
		if unit.global_position.distance_to(point) <= radius:
			n += 1
	return n

func count_group(group: String) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion() and not node.get("is_destroyed") == true:
			n += 1
	return n
