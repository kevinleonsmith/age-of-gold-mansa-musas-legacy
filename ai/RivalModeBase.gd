# Shared base for the AI-rival game modes (res://ai/RivalModeBase.gd)
# modes/Showdown.gd and modes/Scholars.gd extend this by path. It extends
# missions/MissionBase.gd (mission clock, objectives, toasts; it also sets
# VictoryManager.skirmish_conditions_enabled = false) and adds:
#   - the AI empires (children in group "ai_empires", ai/AIEmpire.gd)
#   - node control (child "NodeControl", ai/NodeControl.gd)
#   - scoreboard rows for ui/Scoreboard (group "rival_mode")
#   - victory / defeat with the mode's own ids
#   - save / load of the empires and node owners.
extends "res://missions/MissionBase.gd"

const PLAYER := 0
const NEUTRAL := -1
const PLAYER_NAME := "Mali (you)"
const PLAYER_COLOR := Color(1.0, 0.82, 0.3)

@export var start_gold := 400
@export var start_salt := 100
@export var start_manuscripts := 0

var mode_id := "showdown"
var node_control: Node
var _hud_left := 0.0

func _mission_ready() -> void:
	add_to_group("rival_mode")
	GameData.gold = start_gold
	GameData.salt = start_salt
	GameData.manuscripts = start_manuscripts
	node_control = get_node_or_null("NodeControl")
	_mode_ready()
	for e in empires():
		e.mode = mode_id
	set_time_scale(time_scale)

func _mode_ready() -> void:
	pass

# AI empires of this mode (untyped AIEmpire nodes).
func empires() -> Array:
	return get_tree().get_nodes_in_group("ai_empires").filter(func(e): return is_ancestor_of(e))

func get_empire(id: int):
	for e in empires():
		if e.empire_id == id:
			return e
	return null

# Speeds up the mode clock, every empire and the node-control timers (tests).
func set_time_scale(scale: float) -> void:
	time_scale = scale
	for e in empires():
		e.time_scale = scale
		for w in e.workers:
			if is_instance_valid(w):
				w.time_scale = scale
	if node_control != null:
		node_control.time_scale = scale

func player_nodes() -> int:
	return node_control.count_owned(PLAYER) if node_control != null else 0

func total_nodes() -> int:
	return node_control.total_nodes() if node_control != null else 0

func player_score() -> int:
	return player_nodes() * 100 + GameData.gold / 10 + TechManager.researched.size() * 150

# True every `interval` real seconds (throttles objective text updates).
func hud_due(delta: float, interval := 0.5) -> bool:
	_hud_left -= delta
	if _hud_left > 0.0:
		return false
	_hud_left = interval
	return true

# --- Outcome ----------------------------------------------------------------------

func end_victory(id: String, title: String, text: String) -> void:
	if finished or VictoryManager.is_game_over:
		return
	finished = true
	VictoryManager.declare_victory(id, title, text)

func end_defeat(id: String, title: String, text: String) -> void:
	if finished or VictoryManager.is_game_over:
		return
	finished = true
	VictoryManager.declare_defeat(id, title, text)

# --- Scoreboard -------------------------------------------------------------------

# "showdown" (nodes + score) or "scholars" (tech progress).
func get_scoreboard_kind() -> String:
	return mode_id

func get_scoreboard_title() -> String:
	return ""

# [{"name", "color", "nodes", "score", "techs", "target", "status", "is_player"}]
func get_scoreboard_rows() -> Array:
	return []

# --- Save / load --------------------------------------------------------------------

func get_mission_state() -> Dictionary:
	var emp := []
	for e in empires():
		emp.append(e.get_save_state())
	return {
		"mode": mode_id,
		"mission_time": mission_time,
		"empires": emp,
		"nodes": node_control.get_save_state() if node_control != null else {},
		"mode_state": _get_mode_state(),
	}

func load_mission_state(d: Dictionary) -> void:
	mission_time = float(d.get("mission_time", mission_time))
	for entry in d.get("empires", []):
		var e = get_empire(int(entry.get("empire_id", 0)))
		if e != null:
			e.load_save_state(entry)
	if node_control != null:
		node_control.load_save_state(d.get("nodes", {}))
	_load_mode_state(d.get("mode_state", {}))

func _get_mode_state() -> Dictionary:
	return {}

func _load_mode_state(_d: Dictionary) -> void:
	pass
