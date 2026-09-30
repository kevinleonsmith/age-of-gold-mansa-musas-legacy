# Build menu (res://ui/BuildMenu.gd)
# Bottom-left bar with one button per building type. Clicking a button
# enters placement mode: a ghost follows the mouse in world space, tinted
# red where placement is invalid. Left-click builds, right-click/Esc cancels.
# B (toggle_build) shows or hides the bar.
extends CanvasLayer

signal building_placed(building: Node)

const MIN_GAP := 48.0          # clearance around other buildings' footprints
const MAX_PLAYER_DIST := 400.0 # must build near the Mansa
const VALID_TINT := Color(0.6, 1.0, 0.6, 0.6)
const INVALID_TINT := Color(1.0, 0.25, 0.25, 0.6)

var placing_type := ""
var _buttons := {}
var _templates := {}
var _ghost: Sprite2D
var _refresh_queued := false

@onready var _bar: HBoxContainer = %BuildBar
@onready var _hint: Label = %PlacementHint

func _ready() -> void:
	for type in BuildingData.TYPES:
		var button := Button.new()
		button.name = "Build_" + type
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(start_placement.bind(type))
		_bar.add_child(button)
		_buttons[type] = button
	GameData.gold_changed.connect(_queue_refresh.unbind(1))
	GameData.salt_changed.connect(_queue_refresh.unbind(1))
	GameData.manuscripts_changed.connect(_queue_refresh.unbind(1))
	GameData.ingots_changed.connect(_queue_refresh.unbind(1))
	GameData.modifiers_changed.connect(_queue_refresh.unbind(2))
	AgeManager.age_changed.connect(_queue_refresh.unbind(1))
	_hint.hide()
	refresh_buttons()

func _exit_tree() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	for t in _templates.values():
		if is_instance_valid(t):
			t.free()
	_templates.clear()

# --- Public API ---------------------------------------------------------------

# Validates, spends the scaled cost and places a building. Returns the new
# building, or null if the type is locked/unaffordable or the spot is invalid.
func place_building(type: String, world_pos: Vector2) -> Node:
	if not can_build(type) or not is_valid_placement(type, world_pos):
		return null
	var scene := get_tree().current_scene
	if scene == null or not GameData.spend(BuildingData.get_cost(type)):
		return null
	var building := (load(BuildingData.DEFS[type]["scene"]) as PackedScene).instantiate() as Node2D
	building.position = world_pos
	_get_buildings_parent(scene).add_child(building)
	building.tree_exited.connect(_queue_refresh)
	building_placed.emit(building)
	refresh_buttons()
	return building

# Why a type can't be built right now ("" if it can, ignoring placement).
func get_block_reason(type: String) -> String:
	if not BuildingData.DEFS.has(type):
		return "Unknown building"
	var age := BuildingData.get_required_age(type)
	if not AgeManager.is_unlocked(age):
		return "Requires %s" % AgeManager.get_age_short_name(age)
	if BuildingData.is_wonder(type) and wonder_exists(type):
		return "Wonder already built"
	if not GameData.can_afford(BuildingData.get_cost(type)):
		return "Not enough resources"
	return ""

func can_build(type: String) -> bool:
	return get_block_reason(type) == ""

func wonder_exists(type: String) -> bool:
	for node in get_tree().get_nodes_in_group("building_" + type):
		if not node.is_queued_for_deletion():
			return true
	return false

func is_valid_placement(type: String, world_pos: Vector2) -> bool:
	var template := _get_template(type)
	if template == null:
		return false
	var local: Rect2 = template.get_local_footprint()
	var rect := Rect2(world_pos + local.position, local.size)
	var padded := rect.grow(MIN_GAP)
	for node in get_tree().get_nodes_in_group("buildings"):
		if node.is_queued_for_deletion() or not node is Node2D:
			continue
		var other: Rect2
		if node.has_method("get_footprint_rect"):
			other = node.get_footprint_rect()
		else:
			other = Rect2((node as Node2D).global_position - Vector2(24, 24), Vector2(48, 48))
		if padded.intersects(other):
			return false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		if player.global_position.distance_to(world_pos) > MAX_PLAYER_DIST:
			return false
		# Don't wall the Mansa in.
		if rect.grow(16.0).has_point(player.global_position):
			return false
	# Keep resource deposits reachable.
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "Area2D", true, false):
			if node is ResourceNode and rect.grow(24.0).has_point((node as Node2D).global_position):
				return false
	return true

func start_placement(type: String) -> void:
	if not can_build(type):
		return
	cancel_placement()
	var template := _get_template(type)
	var scene := get_tree().current_scene
	if template == null or scene == null:
		return
	placing_type = type
	var src := template.get_node("Sprite2D") as Sprite2D
	_ghost = Sprite2D.new()
	_ghost.name = "BuildGhost"
	_ghost.texture = src.texture
	_ghost.offset = src.position
	_ghost.z_index = 100
	scene.add_child(_ghost)
	_hint.text = "Placing %s: left-click to build, right-click / Esc to cancel" % BuildingData.get_display_name(type)
	_hint.show()
	_update_ghost()

func cancel_placement() -> void:
	placing_type = ""
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if _hint:
		_hint.hide()

func is_placing() -> bool:
	return placing_type != ""

func refresh_buttons() -> void:
	_refresh_queued = false
	for type in _buttons:
		var button: Button = _buttons[type]
		var cost := BuildingData.get_cost(type)
		button.text = "%s\n%s" % [BuildingData.get_display_name(type), GameData.format_cost(cost)]
		var reason := get_block_reason(type)
		button.disabled = reason != ""
		var tip: String = BuildingData.DEFS[type]["desc"]
		if reason != "":
			tip += "\n(%s)" % reason
		button.tooltip_text = tip
	# Leave placement mode if the type became unavailable (e.g. spent the gold).
	if is_placing() and not can_build(placing_type):
		cancel_placement()

# --- Internals ----------------------------------------------------------------

func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	refresh_buttons.call_deferred()

func _get_template(type: String) -> Building:
	if not _templates.has(type):
		if not BuildingData.DEFS.has(type):
			return null
		var packed := load(BuildingData.DEFS[type]["scene"]) as PackedScene
		_templates[type] = packed.instantiate() as Building
	return _templates[type]

func _get_buildings_parent(scene: Node) -> Node:
	var parent := scene.get_node_or_null("Buildings")
	if parent == null:
		parent = Node2D.new()
		parent.name = "Buildings"
		scene.add_child(parent)
	return parent

func _world_mouse() -> Vector2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_mouse_position()

func _process(_delta: float) -> void:
	if is_placing():
		_update_ghost()

func _update_ghost() -> void:
	if not is_instance_valid(_ghost):
		return
	var pos := _world_mouse()
	_ghost.global_position = pos
	_ghost.modulate = VALID_TINT if is_valid_placement(placing_type, pos) else INVALID_TINT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build"):
		_bar.visible = not _bar.visible
		if not _bar.visible:
			cancel_placement()
		get_viewport().set_input_as_handled()
		return
	if not is_placing():
		return
	if event.is_action_pressed("cancel"):
		cancel_placement()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var type := placing_type
			if place_building(type, _world_mouse()) != null and not event.shift_pressed:
				cancel_placement()
			get_viewport().set_input_as_handled()
