# Griot Bard (res://entities/GriotBard.gd)
# Non-combat support unit: follows the player and periodically sings a morale
# pulse that boosts the attack of every nearby ally (+15% by default).
# Griot Diplomacy: sings an "epic meter" to the nearest enemy in range; when
# the meter fills, that enemy converts to the player's side.
extends Unit

signal conversion_completed(unit: Node)

const PULSE_RING_TIME := 0.6
const RING_COLOR := Color(1.0, 0.84, 0.2)

@export var move_speed := 220.0
@export var follow_distance := 80.0 # ideal distance from the player
@export var follow_tolerance := 10.0 # stop anywhere within follow_distance +/- this
@export var enemy_flee_radius := 80.0 # retreat to the player if an enemy is this close
@export var pulse_interval := 6.0
@export var boost_multiplier := 1.15
@export var boost_duration := 5.0
@export var boost_radius := 120.0
@export var show_aura := true
@export var convert_radius := 140.0
@export var convert_time := 4.0 # seconds to fill the epic meter at speed 1.0
@export var convert_cooldown := 8.0 # rest between songs
@export var attacked_radius := 40.0 # an enemy this close counts as attacking the griot

var _pulse_timer := 0.0
var _ring_progress := 0.0 # 0..1 while the pulse ring expands; 0 when idle
var _ring_tween: Tween
var _last_player_dir := Vector2.DOWN # direction the player last moved in
var conversion_target: Unit = null # enemy the griot is singing to
var conversion_progress := 0.0 # 0..1 epic meter
var _convert_cooldown_left := 0.0
var _note_time := 0.0 # drives the floating note animation
const BEAM_COLOR := Color(0.55, 0.8, 1.0)
const DECAY_MULT := 2.0

func _init() -> void:
	max_health = 60.0
	attack_damage = 0.0

func _ready() -> void:
	add_to_group("allies")
	_pulse_timer = pulse_interval

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_pulse_timer += pulse_interval
		activate_morale_boost()

	_update_conversion(delta)
	velocity = _compute_velocity() * GameData.get_modifier("sandstorm_slow_mult")
	move_and_slide()

func _compute_velocity() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	if player is CharacterBody2D and (player as CharacterBody2D).velocity.length() > 1.0:
		_last_player_dir = (player as CharacterBody2D).velocity.normalized()

	var to_player := player.global_position - global_position
	var distance := to_player.length()

	# Threatened: run straight to the player's side. The enemy being sung to
	# only counts as a threat if it is close enough to be attacking the griot.
	if _is_threatened():
		if distance > follow_distance * 0.5:
			return to_player.normalized() * move_speed
		return Vector2.ZERO

	# Close enough: hold position.
	if absf(distance - follow_distance) <= follow_tolerance:
		return Vector2.ZERO

	# Otherwise head for a slot behind the player (relative to its movement).
	var slot := player.global_position - _last_player_dir * follow_distance
	if distance < follow_distance - follow_tolerance:
		# Too close: step away from the player rather than through it.
		slot = player.global_position - to_player.normalized() * follow_distance
	var to_slot := slot - global_position
	if to_slot.length() < 4.0:
		return Vector2.ZERO
	var speed := move_speed
	if to_slot.length() < 30.0:
		speed *= to_slot.length() / 30.0 # ease in to avoid jitter
	return to_slot.normalized() * speed

func _is_threatened() -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var unit := node as Unit
		if unit == null or unit == self or unit.is_dead or unit.is_in_group("rival_buildings"):
			continue
		var d := global_position.distance_to(unit.global_position)
		var radius := attacked_radius if unit == conversion_target else enemy_flee_radius
		if d <= radius:
			return true
	return false

# Untyped on purpose: a typed `Unit` parameter errors when handed a freed target.
func _is_valid_song_target(unit) -> bool:
	return is_instance_valid(unit) and not unit.is_dead \
		and unit.is_in_group("enemies") and unit.has_method("convert_to_ally")

# Nearest convertible enemy within convert_radius, or null.
func _find_song_target() -> Unit:
	var best: Unit = null
	var best_d := convert_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		var unit := node as Unit
		if not _is_valid_song_target(unit):
			continue
		var d := global_position.distance_to(unit.global_position)
		if d <= best_d:
			best_d = d
			best = unit
	return best

func _update_conversion(delta: float) -> void:
	_note_time += delta
	if _convert_cooldown_left > 0.0:
		_convert_cooldown_left = maxf(_convert_cooldown_left - delta, 0.0)
		if conversion_target != null or conversion_progress > 0.0:
			conversion_target = null
			conversion_progress = 0.0
		queue_redraw()
		return

	if conversion_target != null and not _is_valid_song_target(conversion_target):
		conversion_target = null
		conversion_progress = 0.0

	var in_range := conversion_target != null \
		and global_position.distance_to(conversion_target.global_position) <= convert_radius
	if conversion_target == null or (not in_range and conversion_progress <= 0.0):
		# Pick a new target (progress resets when the target changes).
		var nearest := _find_song_target()
		if nearest != conversion_target:
			conversion_target = nearest
			conversion_progress = 0.0
		in_range = conversion_target != null

	if conversion_target != null:
		var rate := 1.0 / maxf(convert_time, 0.01)
		if in_range:
			conversion_progress += rate * GameData.get_modifier("conversion_speed_mult") * delta
			if conversion_progress >= 1.0:
				_complete_conversion()
		else:
			conversion_progress = maxf(conversion_progress - rate * DECAY_MULT * delta, 0.0)
			if conversion_progress <= 0.0:
				conversion_target = null
	queue_redraw()

func _complete_conversion() -> void:
	var unit := conversion_target
	conversion_target = null
	conversion_progress = 0.0
	_convert_cooldown_left = convert_cooldown
	if unit != null and is_instance_valid(unit) and unit.has_method("convert_to_ally"):
		unit.convert_to_ally()
		conversion_completed.emit(unit)

func is_singing() -> bool:
	return conversion_target != null and _convert_cooldown_left <= 0.0

# Boosts every living ally Unit (including this griot) within boost_radius.
# Returns the number of units boosted.
func activate_morale_boost() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("allies"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		if global_position.distance_to(unit.global_position) <= boost_radius:
			unit.apply_morale_boost(boost_multiplier, boost_duration)
			count += 1
	_play_pulse_ring()
	return count

func _play_pulse_ring() -> void:
	if _ring_tween and _ring_tween.is_valid():
		_ring_tween.kill()
	_ring_tween = create_tween()
	_ring_tween.tween_method(_set_ring_progress, 0.0001, 1.0, PULSE_RING_TIME)
	_ring_tween.tween_callback(_set_ring_progress.bind(0.0))

func _set_ring_progress(value: float) -> void:
	_ring_progress = value
	queue_redraw()

func _draw() -> void:
	if show_aura:
		draw_arc(Vector2.ZERO, boost_radius, 0.0, TAU, 64, Color(RING_COLOR, 0.15), 1.0)
	if _ring_progress > 0.0:
		var radius := lerpf(16.0, boost_radius, _ring_progress)
		var alpha := 1.0 - _ring_progress
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(RING_COLOR, 0.9 * alpha), 3.0)
	if is_singing() and is_instance_valid(conversion_target):
		_draw_song(to_local(conversion_target.global_position))
	super()

# Dotted "musical beam" to the target, an epic-meter bar above it, and notes.
func _draw_song(target_pos: Vector2) -> void:
	var length := target_pos.length()
	if length < 1.0:
		return
	var dir := target_pos / length
	var normal := Vector2(-dir.y, dir.x)
	# Wavy dotted beam that scrolls toward the target.
	var step := 10.0
	var offset := fmod(_note_time * 40.0, step)
	var t := offset
	while t < length:
		var wave := sin((t / length) * TAU * 2.0 - _note_time * 6.0) * 4.0
		draw_circle(dir * t + normal * wave, 1.5, Color(BEAM_COLOR, 0.8))
		t += step
	# Epic meter above the enemy.
	var bar := Rect2(target_pos + Vector2(-18, -40), Vector2(36, 5))
	draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(conversion_progress, 0.0, 1.0), bar.size.y)), RING_COLOR)
	# Two floating notes drifting along the beam.
	for i in 2:
		var phase := fmod(_note_time * 0.6 + i * 0.5, 1.0)
		var p := dir * (length * phase) + normal * (-10.0 - 6.0 * sin(phase * PI))
		_draw_note(p, Color(RING_COLOR, 1.0 - phase * 0.6))

# A simple eighth note: filled head, stem and flag.
func _draw_note(pos: Vector2, color: Color) -> void:
	draw_circle(pos, 3.0, color)
	var stem_top := pos + Vector2(2.5, -11.0)
	draw_line(pos + Vector2(2.5, 0), stem_top, color, 1.5)
	draw_line(stem_top, stem_top + Vector2(5.0, 4.0), color, 1.5)
