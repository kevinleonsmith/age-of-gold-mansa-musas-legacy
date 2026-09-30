# Control of gold / salt nodes (res://ai/NodeControl.gd)
# Every gold / salt ResourceNode under `nodes_path` has an owner: the player
# (PLAYER = 0), an AI empire (its empire_id, 1-3) or NEUTRAL (-1). A side
# takes a node by keeping units within RADIUS of it, uncontested, for
# CAPTURE_TIME seconds: player side = living "allies" units; AI side = AI
# workers and raiders (group "ai_units", meta "empire_id", still in
# "enemies"). If units of two sides are near, the node is contested and the
# timer resets. After NEUTRALIZE_TIME of an uncontested challenge an owned
# node first falls to neutral, then goes to the challenger at CAPTURE_TIME.
# Nobody near: the owner keeps it. A ring and a flag (ai/ControlMarker.gd)
# show the owner on every node. Normal player harvesting is untouched.
# Owners are mirrored into node meta "control_owner" for the AI controllers.
extends Node

signal owner_changed(node, new_owner: int)

const PLAYER := 0
const NEUTRAL := -1
const RADIUS := 150.0
const CAPTURE_TIME := 10.0
const NEUTRALIZE_TIME := 5.0
const UPDATE_INTERVAL := 0.25
const MANUSCRIPT_TYPE := 2
const PLAYER_COLOR := Color(1.0, 0.82, 0.3)
const NEUTRAL_COLOR := Color(0.85, 0.82, 0.76)
const MARKER_SCRIPT := preload("res://ai/ControlMarker.gd")

@export var nodes_path: NodePath = ^"../Resources"
@export var time_scale := 1.0

# node instance id -> {"node", "owner", "challenger", "progress", "contested", "marker"}
var states := {}
var _acc := 0.0

func _ready() -> void:
	add_to_group("node_control")
	refresh_nodes.call_deferred()

# Registers every gold / salt ResourceNode under nodes_path (safe to repeat).
func refresh_nodes() -> void:
	var parent := get_node_or_null(nodes_path)
	if parent == null:
		return
	for child in parent.get_children():
		if child.get("resource_type") != null and int(child.resource_type) != MANUSCRIPT_TYPE:
			register(child)

func register(node: Node2D) -> void:
	var id := node.get_instance_id()
	if states.has(id):
		return
	node.add_to_group("control_nodes")
	node.set_meta("control_owner", NEUTRAL)
	var marker := Node2D.new()
	marker.set_script(MARKER_SCRIPT)
	marker.name = "ControlMarker"
	marker.control = self
	node.add_child(marker)
	states[id] = {"node": node, "owner": NEUTRAL, "challenger": NEUTRAL, "progress": 0.0,
		"contested": false, "marker": marker}
	node.tree_exiting.connect(_unregister.bind(id))

func _unregister(id: int) -> void:
	states.erase(id)

func _process(delta: float) -> void:
	_acc += delta * time_scale
	if _acc >= UPDATE_INTERVAL:
		var step := _acc
		_acc = 0.0
		tick(step)

# Advances capture timers by `seconds` (tests call this to fast-forward).
func tick(seconds: float) -> void:
	for id in states.keys():
		var st: Dictionary = states[id]
		if not is_instance_valid(st["node"]) or st["node"].is_queued_for_deletion():
			states.erase(id)
			continue
		_update(st, seconds)
	_publish_counts()

func _update(st: Dictionary, seconds: float) -> void:
	var sides := sides_near(st["node"])
	st["contested"] = sides.size() >= 2
	if sides.size() != 1:
		st["challenger"] = NEUTRAL
		st["progress"] = 0.0
		_redraw(st)
		return
	var side: int = sides[0]
	if side == st["owner"]:
		st["challenger"] = NEUTRAL
		st["progress"] = 0.0
		_redraw(st)
		return
	if side != st["challenger"]:
		st["challenger"] = side
		st["progress"] = 0.0
	st["progress"] += seconds
	if st["owner"] != NEUTRAL and st["progress"] >= NEUTRALIZE_TIME:
		_set_owner(st, NEUTRAL)
	if st["progress"] >= CAPTURE_TIME:
		_set_owner(st, side)
		st["challenger"] = NEUTRAL
		st["progress"] = 0.0
	_redraw(st)

func _set_owner(st: Dictionary, side: int) -> void:
	if st["owner"] == side:
		return
	st["owner"] = side
	st["node"].set_meta("control_owner", side)
	owner_changed.emit(st["node"], side)

func _redraw(st: Dictionary) -> void:
	if is_instance_valid(st["marker"]):
		st["marker"].queue_redraw()
		st["marker"].update_flag()

# Sides (PLAYER / empire ids) with a living unit within RADIUS of `node`.
func sides_near(node: Node2D) -> Array:
	var sides := []
	var at := node.global_position
	for unit in get_tree().get_nodes_in_group("allies"):
		if _alive(unit) and unit.global_position.distance_to(at) <= RADIUS:
			sides.append(PLAYER)
			break
	for unit in get_tree().get_nodes_in_group("ai_units"):
		if not _alive(unit) or not unit.is_in_group("enemies") or not unit.has_meta("empire_id"):
			continue
		var side := int(unit.get_meta("empire_id"))
		if not sides.has(side) and unit.global_position.distance_to(at) <= RADIUS:
			sides.append(side)
	return sides

func _alive(unit) -> bool:
	return is_instance_valid(unit) and unit is Node2D and not unit.is_queued_for_deletion() \
		and unit.get("is_dead") != true

func _publish_counts() -> void:
	for empire in get_tree().get_nodes_in_group("ai_empires"):
		empire.nodes_controlled = count_owned(empire.empire_id)

# --- Queries ----------------------------------------------------------------------

func get_owner_of(node) -> int:
	if not is_instance_valid(node):
		return NEUTRAL
	var st: Dictionary = states.get(node.get_instance_id(), {})
	return int(st.get("owner", NEUTRAL))

func get_state_of(node) -> Dictionary:
	return states.get(node.get_instance_id(), {}) if is_instance_valid(node) else {}

func get_nodes() -> Array:
	var out := []
	for st in states.values():
		if is_instance_valid(st["node"]):
			out.append(st["node"])
	return out

func total_nodes() -> int:
	return get_nodes().size()

func count_owned(side: int) -> int:
	var n := 0
	for st in states.values():
		if st["owner"] == side and is_instance_valid(st["node"]):
			n += 1
	return n

func share(side: int) -> float:
	var total := total_nodes()
	return float(count_owned(side)) / total if total > 0 else 0.0

func side_color(side: int) -> Color:
	if side == PLAYER:
		return PLAYER_COLOR
	for empire in get_tree().get_nodes_in_group("ai_empires"):
		if empire.empire_id == side:
			return empire.color
	return NEUTRAL_COLOR

func side_key(side: int) -> String:
	if side == PLAYER:
		return "player"
	for empire in get_tree().get_nodes_in_group("ai_empires"):
		if empire.empire_id == side:
			return empire.get_key()
	return "neutral"

# --- Save / load (plain data: owners by node name) --------------------------------

func get_save_state() -> Dictionary:
	var owners := {}
	for st in states.values():
		if is_instance_valid(st["node"]):
			owners[String(st["node"].name)] = int(st["owner"])
	return {"owners": owners}

func load_save_state(d: Dictionary) -> void:
	refresh_nodes()
	var owners: Dictionary = d.get("owners", {})
	for st in states.values():
		if is_instance_valid(st["node"]) and owners.has(String(st["node"].name)):
			_set_owner(st, int(owners[String(st["node"].name)]))
			st["challenger"] = NEUTRAL
			st["progress"] = 0.0
			_redraw(st)
	_publish_counts()
