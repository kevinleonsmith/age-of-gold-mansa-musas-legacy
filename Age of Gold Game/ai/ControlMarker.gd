# Owner ring + flag drawn on a controlled node (res://ai/ControlMarker.gd)
# Child of a ResourceNode, created by ai/NodeControl.gd. Draws a ring in the
# owner's colour behind the node, a faint dashed ring at the 150 px control
# radius, and a capture-progress arc in the challenger's colour.
extends Node2D

const RING_RADIUS := 40.0

var control = null # NodeControl
var _flag: Sprite2D
var _flag_key := ""

func _ready() -> void:
	show_behind_parent = true
	_flag = Sprite2D.new()
	_flag.name = "Flag"
	_flag.position = Vector2(30, -34)
	add_child(_flag)
	update_flag()

func _state() -> Dictionary:
	if control == null or not is_instance_valid(control):
		return {}
	return control.get_state_of(get_parent())

func update_flag() -> void:
	if _flag == null:
		return
	var st := _state()
	var key: String = control.side_key(int(st.get("owner", -1))) if not st.is_empty() else "neutral"
	if key != _flag_key:
		_flag_key = key
		_flag.texture = load("res://assets/ai/flag_%s.png" % key)

func _draw() -> void:
	var st := _state()
	if st.is_empty():
		return
	var owner := int(st["owner"])
	var col: Color = control.side_color(owner)
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, RING_RADIUS, Color(col, 0.18 if owner != -1 else 0.08))
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 40, Color(col, 0.95 if owner != -1 else 0.5), 3.0)
	# Control radius, dashed.
	var r: float = control.RADIUS
	for i in 24:
		var a := TAU * i / 24.0
		draw_arc(Vector2.ZERO, r, a, a + TAU / 48.0, 3, Color(col, 0.25), 2.0)
	if st["contested"]:
		draw_arc(Vector2.ZERO, RING_RADIUS + 7.0, 0.0, TAU, 40, Color(1, 0.3, 0.2, 0.8), 2.0)
	elif float(st["progress"]) > 0.0:
		var frac := clampf(float(st["progress"]) / control.CAPTURE_TIME, 0.0, 1.0)
		var ccol: Color = control.side_color(int(st["challenger"]))
		draw_arc(Vector2.ZERO, RING_RADIUS + 7.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, ccol, 4.0)
	draw_set_transform(Vector2.ZERO)
