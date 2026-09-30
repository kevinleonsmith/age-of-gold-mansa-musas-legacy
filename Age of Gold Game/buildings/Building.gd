# Base class for player buildings (res://buildings/Building.gd)
# Subclasses override _apply_effects / _remove_effects for passive bonuses.
# Effects are applied when the building enters play (_ready) and removed
# exactly once when it leaves the tree (destroyed or scene change).
class_name Building
extends StaticBody2D

signal destroyed
signal health_changed(new_health: float, max_health: float)

@export var building_type := ""
@export var max_health := 150.0
@export var is_wonder := false

var health := 0.0
var is_destroyed := false
var _hp_mult := 1.0
var _effects_applied := false
var _generation := -1 # GameData.generation when effects were applied

func _ready() -> void:
	add_to_group("buildings")
	if building_type != "":
		add_to_group("building_" + building_type)
	_hp_mult = GameData.get_modifier("building_hp_mult")
	health = get_max_health()
	GameData.modifiers_changed.connect(_on_modifiers_changed)
	_effects_applied = true
	_generation = GameData.generation
	_apply_effects()

func _exit_tree() -> void:
	_clear_effects()

# Removes passive bonuses once, and only if no new game started since they
# were applied (GameData.reset() already cleared them in that case).
func _clear_effects() -> void:
	if _effects_applied:
		_effects_applied = false
		if _generation == GameData.generation:
			_remove_effects()

func get_max_health() -> float:
	return max_health * _hp_mult

func take_damage(amount: float) -> void:
	if is_destroyed or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, get_max_health())
	queue_redraw()
	if health <= 0.0:
		destroy()

func repair(amount: float) -> void:
	if is_destroyed:
		return
	health = minf(health + amount, get_max_health())
	health_changed.emit(health, get_max_health())
	queue_redraw()

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	# Leave the groups now so counts (age requirements, wonders) update
	# before the node is actually freed at the end of the frame.
	for group in get_groups():
		if String(group).begins_with("building"):
			remove_from_group(group)
	# Remove passive bonuses immediately rather than when the node is freed.
	_clear_effects()
	destroyed.emit()
	queue_free()

# Footprint = the collision rectangle, in global coordinates.
func get_footprint_rect() -> Rect2:
	var local := get_local_footprint()
	return Rect2(global_position + local.position, local.size)

# Footprint relative to the building origin (works before entering the tree).
func get_local_footprint() -> Rect2:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size
		return Rect2(shape_node.position - size / 2.0, size)
	return Rect2(Vector2(-24, -24), Vector2(48, 48))

func _on_modifiers_changed(key: String, value: float) -> void:
	if key != "building_hp_mult" or value <= 0.0:
		return
	# Keep the same health fraction when the HP multiplier changes.
	var fraction := health / get_max_health() if get_max_health() > 0.0 else 1.0
	_hp_mult = value
	health = get_max_health() * fraction
	queue_redraw()

# --- Overridables -------------------------------------------------------------

func _apply_effects() -> void:
	pass

func _remove_effects() -> void:
	pass

func _draw() -> void:
	if health >= get_max_health() or is_destroyed:
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	var top := -32.0
	var width := 40.0
	if sprite and sprite.texture:
		var size := sprite.texture.get_size()
		top = sprite.position.y - size.y / 2.0
		width = clampf(size.x * 0.6, 32.0, 80.0)
	var bar := Rect2(-width / 2.0, top - 8.0, width, 5.0)
	draw_rect(bar, Color(0.3, 0, 0, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / get_max_health(), bar.size.y)), Color(0.2, 0.9, 0.2))
	draw_rect(bar, Color(0, 0, 0, 0.9), false, 1.0)
