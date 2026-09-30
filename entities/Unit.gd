# Shared base for combat units (res://entities/Unit.gd)
# Subclasses: use _physics_process for behaviour. If you override _ready or
# _process, call super() / super(delta) so health and timers keep working.
class_name Unit
extends CharacterBody2D

signal died
signal health_changed(new_health: float, max_health: float)

@export var max_health := 100.0
@export var attack_damage := 10.0
@export var attack_range := 40.0
@export var attack_cooldown := 1.0
@export var show_health_bar := true
# How far this unit reveals the fog of war (allies only).
@export var vision_radius := 260.0

@onready var health := max_health

var attack_multiplier := 1.0
var is_dead := false
var _attack_timer := 0.0
var _morale_time_left := 0.0
var _poison_dps := 0.0
var _poison_time_left := 0.0

const POISON_DURATION := 3.0

func _process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	if _morale_time_left > 0.0:
		_morale_time_left -= delta
		if _morale_time_left <= 0.0:
			attack_multiplier = 1.0
			queue_redraw()
	if is_dead:
		return
	if _poison_time_left > 0.0:
		_poison_time_left -= delta
		take_damage(_poison_dps * delta)
	# Salt Monopoly tech: enemies slowly lose health.
	if is_in_group("enemies"):
		var drain := GameData.get_modifier("enemy_hp_drain", 0.0)
		if drain > 0.0:
			take_damage(drain * delta)

func can_attack() -> bool:
	return _attack_timer <= 0.0 and not is_dead

# Deals attack_damage * attack_multiplier (and, for allies, the global
# "ally_attack_mult" modifier) if target is alive, in range and off cooldown.
func try_attack(target: Unit) -> bool:
	if not can_attack() or not is_instance_valid(target) or target.is_dead:
		return false
	if distance_to_target(target) > attack_range:
		return false
	_attack_timer = attack_cooldown
	var damage := attack_damage * attack_multiplier
	if is_in_group("allies"):
		damage *= GameData.get_modifier("ally_attack_mult")
		# Poisoned Spears tech: allied hits poison enemies.
		var poison := GameData.get_modifier("poison_dps", 0.0)
		if poison > 0.0 and damage > 0.0 and target.is_in_group("enemies"):
			target.apply_poison(poison, POISON_DURATION)
	target.take_damage(damage)
	AudioManager.play_sfx("hit", global_position)
	return true

# Distance to a target's edge when it has a footprint (rival buildings), else to its centre.
func distance_to_target(target) -> float:
	if target.has_method("get_footprint_rect"):
		var rect: Rect2 = target.get_footprint_rect()
		return global_position.distance_to(global_position.clamp(rect.position, rect.end))
	return global_position.distance_to(target.global_position)

func apply_poison(dps: float, duration: float) -> void:
	_poison_dps = maxf(_poison_dps, dps)
	_poison_time_left = maxf(_poison_time_left, duration)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	if is_in_group("allies"):
		amount *= GameData.get_modifier("ally_damage_taken_mult")
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	queue_redraw()
	if health <= 0.0:
		is_dead = true
		AudioManager.play_sfx("death", global_position)
		died.emit()
		_on_died()

func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)
	queue_redraw()

# Override for custom death handling (e.g. game over); default frees the unit.
func _on_died() -> void:
	queue_free()

func apply_morale_boost(multiplier: float, duration: float) -> void:
	attack_multiplier = maxf(attack_multiplier, multiplier)
	_morale_time_left = maxf(_morale_time_left, duration)
	queue_redraw()

func is_boosted() -> bool:
	return _morale_time_left > 0.0

# Nearest living Unit in `group` within max_distance, or null.
func find_nearest_in_group(group: StringName, max_distance := INF) -> Unit:
	var nearest: Unit = null
	var best := max_distance
	for node in get_tree().get_nodes_in_group(group):
		var unit := node as Unit
		if unit == null or unit == self or unit.is_dead:
			continue
		var distance := distance_to_target(unit)
		if distance <= best:
			best = distance
			nearest = unit
	return nearest

func _draw() -> void:
	if is_boosted():
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(1, 0.84, 0.2, 0.9), 2.0)
	if show_health_bar and health < max_health:
		var bar := Rect2(-16, -28, 32, 4)
		draw_rect(bar, Color(0.3, 0, 0, 0.8))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health / max_health, bar.size.y)), Color(0.2, 0.9, 0.2))
