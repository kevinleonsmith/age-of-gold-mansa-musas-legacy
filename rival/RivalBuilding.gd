# Songhai rival building (res://rival/RivalBuilding.gd)
# Two kinds, chosen with `building_kind`:
#   "camp"   War Camp  (group "rival_camps"): spawns raiders on a timer and
#            sends them toward the player's base in waves; pays a bounty.
#   "wonder" Rival Wonder, the Songhai palace at Gao (group "rival_wonders"):
#            spawns nothing, but calls nearby raiders to defend it when hit.
#
# It extends Unit (a CharacterBody2D that never moves) rather than StaticBody2D
# so it can sit in the "enemies" group: Player.attack_nearest, CamelLancer and
# converted raiders all find targets through Unit.find_nearest_in_group, which
# only returns Units, and Unit.try_attack takes a Unit. The collision footprint
# is kept small enough that attackers reach it with a centre-distance check.
class_name RivalBuilding
extends Unit

signal destroyed

const KIND_CAMP := "camp"
const KIND_WONDER := "wonder"
const RAIDER_SCENE := preload("res://entities/EnemyAI.tscn")

@export_enum("camp", "wonder") var building_kind := "camp"
# War Camp
@export var spawn_interval := 18.0 # seconds per raider at enemy_spawn_rate_mult 1
@export var max_raiders := 4 # living raiders from this camp at once
@export var wave_size := 3 # raiders gather at the camp until a wave is ready
@export var bounty := 100
@export var spawn_offset := Vector2(0, 48)
# Rival Wonder
@export var defend_radius := 600.0
@export var defend_call_cooldown := 2.0
@export var defend_duration := 10.0

var is_destroyed := false
var raiders: Array = [] # raiders spawned by this camp (may hold freed nodes)
var _waiting: Array = [] # spawned raiders still gathering at the camp
var _spawn_elapsed := 0.0
var _call_cooldown_left := 0.0

func _init() -> void:
	max_health = 400.0
	attack_damage = 0.0
	attack_range = 0.0
	show_health_bar = true

func _ready() -> void:
	add_to_group("rival_buildings")
	add_to_group("enemies")
	if building_kind == KIND_WONDER:
		add_to_group("rival_wonders")
	else:
		add_to_group("rival_camps")
	velocity = Vector2.ZERO

func is_camp() -> bool:
	return building_kind == KIND_CAMP

func is_wonder() -> bool:
	return building_kind == KIND_WONDER

# Replaces Unit._process on purpose: buildings are not poisoned and are not
# drained by the Salt Monopoly tech, and they never attack.
func _process(delta: float) -> void:
	_call_cooldown_left = maxf(_call_cooldown_left - delta, 0.0)

func apply_poison(_dps: float, _duration: float) -> void:
	pass

func apply_morale_boost(_multiplier: float, _duration: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	if is_destroyed or not is_camp():
		return
	_prune()
	if not can_spawn():
		return
	var rate := GameData.get_modifier("enemy_spawn_rate_mult")
	_spawn_elapsed += delta * rate
	if _spawn_elapsed >= spawn_interval:
		# Never bank more than one extra spawn (e.g. after spawn_interval shrinks).
		_spawn_elapsed = minf(_spawn_elapsed - spawn_interval, spawn_interval)
		spawn_raider()

# True if the camp may spawn right now (ignores the timer).
func can_spawn() -> bool:
	if is_destroyed or not is_camp():
		return false
	if GameData.get_modifier("enemy_spawn_rate_mult") <= 0.0:
		return false
	if EconomyManager.is_rivals_collapsed():
		return false
	if living_raider_count() >= max_raiders:
		return false
	var spawner := get_tree().get_first_node_in_group("spawn_manager")
	if spawner != null and spawner.has_method("count_raiders") \
			and spawner.count_raiders() >= int(spawner.get("max_enemies")):
		return false
	return true

func living_raider_count() -> int:
	_prune()
	return raiders.size()

# Drops raiders that died or were converted by a griot.
func _prune() -> void:
	raiders = raiders.filter(_is_hostile_raider)
	_waiting = _waiting.filter(_is_hostile_raider)

# Untyped on purpose: may be handed a freed node.
func _is_hostile_raider(raider) -> bool:
	return is_instance_valid(raider) and not raider.is_dead and raider.is_in_group("enemies")

# Spawns one raider in front of the camp (into the scene's "Enemies" node).
# It gathers at the camp; every `wave_size` raiders march together.
func spawn_raider() -> Node2D:
	if not can_spawn():
		return null
	var scene := get_tree().current_scene
	var container: Node = scene.get_node_or_null("Enemies") if scene != null else null
	if container == null:
		container = get_parent()
	var raider := RAIDER_SCENE.instantiate() as Node2D
	var jitter := Vector2(randf_range(-24.0, 24.0), randf_range(-6.0, 6.0))
	container.add_child(raider)
	raider.global_position = global_position + spawn_offset + jitter
	raider.home_position = raider.global_position
	raider.add_to_group("camp_raiders")
	raiders.append(raider)
	_waiting.append(raider)
	if _waiting.size() >= wave_size:
		launch_wave()
	return raider

# Sends every raider still gathering at the camp toward the player's base.
func launch_wave() -> int:
	_prune()
	var sent := 0
	for raider in _waiting:
		if raider.has_method("start_march"):
			raider.start_march()
			sent += 1
	_waiting.clear()
	return sent

func take_damage(amount: float) -> void:
	if is_destroyed or amount <= 0.0:
		return
	super(amount)
	if is_wonder() and not is_dead:
		call_defenders()

# Rival Wonder: every hostile raider within defend_radius rushes to defend it.
# Returns the number of raiders called.
func call_defenders() -> int:
	if _call_cooldown_left > 0.0:
		return 0
	_call_cooldown_left = defend_call_cooldown
	var attacker = _find_attacker()
	var called := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node) or not node.has_method("defend"):
			continue
		if node.get("is_converted") or node.get("is_dead"):
			continue
		if global_position.distance_to(node.global_position) > defend_radius:
			continue
		node.defend(self, attacker, defend_duration)
		called += 1
	return called

# Nearest living ally unit close to the wonder (the likely attacker), or null.
func _find_attacker():
	var best = null
	var best_d := 260.0
	for node in get_tree().get_nodes_in_group("allies"):
		if not is_instance_valid(node) or node.get("is_dead"):
			continue
		var d := global_position.distance_to(node.global_position)
		if d <= best_d:
			best_d = d
			best = node
	return best

func _on_died() -> void:
	is_destroyed = true
	for group in ["rival_buildings", "rival_camps", "rival_wonders", "enemies"]:
		remove_from_group(group)
	set_physics_process(false)
	if is_camp():
		# Raiders still gathering at a destroyed camp march out anyway.
		launch_wave()
		if bounty > 0:
			GameData.gold += bounty
	destroyed.emit()
	queue_free()

# Footprint = the collision rectangle, in global coordinates (same API as Building).
func get_footprint_rect() -> Rect2:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size
		return Rect2(global_position + shape_node.position - size / 2.0, size)
	return Rect2(global_position - Vector2(24, 24), Vector2(48, 48))

func _draw() -> void:
	if is_destroyed or health >= max_health:
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	var top := -40.0
	var width := 60.0
	if sprite and sprite.texture:
		var size := sprite.texture.get_size()
		top = sprite.position.y - size.y / 2.0
		width = clampf(size.x * 0.6, 40.0, 90.0)
	var bar := Rect2(-width / 2.0, top - 8.0, width, 5.0)
	draw_rect(bar, Color(0.3, 0, 0, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / max_health, bar.size.y)), Color(0.85, 0.2, 0.15))
	draw_rect(bar, Color(0, 0, 0, 0.9), false, 1.0)
