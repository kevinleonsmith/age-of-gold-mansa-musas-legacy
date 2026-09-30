# Desert Scout (res://entities/DesertScout.gd)
# Age I camel rider (design: "+4 LOS"). There is no fog of war, so the scout
# instead ranges ahead of the player in the direction the player last moved
# and marks the nearest enemy within mark_radius with a large reticle and a
# sight line. Fast but fragile: below flee_fraction health it runs back to
# the player. Camel rider: unaffected by sandstorms.
extends Unit

const MARK_COLOR := Color(0.55, 0.6, 1.0)

@export var move_speed := 500.0 # 2x the Camel Lancer
@export var range_ahead := 250.0 # how far ahead of the player it scouts
@export var mark_radius := 450.0
@export var aggro_radius := 140.0
@export var flee_fraction := 0.4

var marked_enemy: Unit = null
var _last_player_dir := Vector2.RIGHT
var _last_player_pos := Vector2.ZERO
var _has_last_player_pos := false
var _pulse := 0.0

func _init() -> void:
	max_health = 70.0
	attack_damage = 5.0
	attack_range = 40.0
	attack_cooldown = 1.0

func _ready() -> void:
	add_to_group("allies")
	add_to_group("camel")

func is_fleeing() -> bool:
	return health < max_health * flee_fraction

# The point ahead of the player the scout heads for.
func get_scout_point() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return global_position
	return player.global_position + _last_player_dir * range_ahead

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_pulse += delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	# Track the player's heading from its actual motion (works for any mover).
	if player != null:
		if _has_last_player_pos:
			var moved := player.global_position - _last_player_pos
			if moved.length() > 0.5:
				_last_player_dir = moved.normalized()
		_last_player_pos = player.global_position
		_has_last_player_pos = true
	marked_enemy = find_nearest_in_group("enemies", mark_radius)
	queue_redraw()

	if is_fleeing():
		if player != null and global_position.distance_to(player.global_position) > 40.0:
			_move_toward(player.global_position)
		else:
			velocity = Vector2.ZERO
		return
	var enemy := find_nearest_in_group("enemies", aggro_radius)
	if enemy != null:
		if global_position.distance_to(enemy.global_position) <= attack_range:
			velocity = Vector2.ZERO
			try_attack(enemy)
		else:
			_move_toward(enemy.global_position)
		return
	var point := get_scout_point()
	if global_position.distance_to(point) > 12.0:
		_move_toward(point)
	else:
		velocity = Vector2.ZERO

func _move_toward(point: Vector2) -> void:
	var speed := move_speed
	if not is_in_group("camel"):
		speed *= GameData.get_modifier("sandstorm_slow_mult")
	var dist := global_position.distance_to(point)
	if dist < 40.0:
		speed *= maxf(dist / 40.0, 0.25) # ease in to avoid jitter
	velocity = global_position.direction_to(point) * speed
	move_and_slide()

func _draw() -> void:
	if is_instance_valid(marked_enemy) and not marked_enemy.is_dead:
		var p := to_local(marked_enemy.global_position)
		# Dashed sight line from the scout to the mark.
		var length := p.length()
		var dir := p / maxf(length, 1.0)
		var t := 20.0
		while t < length - 26.0:
			draw_line(dir * t, dir * minf(t + 8.0, length - 26.0), Color(MARK_COLOR, 0.55), 1.5)
			t += 16.0
		# Pulsing reticle and a downward chevron above the enemy.
		var r := 22.0 + sin(_pulse * 6.0) * 3.0
		draw_arc(p, r, 0.0, TAU, 32, Color(MARK_COLOR, 0.95), 2.5)
		for i in 4:
			var a := i * PI / 2.0
			var v := Vector2.from_angle(a)
			draw_line(p + v * (r - 6.0), p + v * (r + 6.0), MARK_COLOR, 2.5)
		var top := p + Vector2(0, -r - 14.0 - absf(sin(_pulse * 4.0)) * 4.0)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-8, -8), top + Vector2(8, -8), top]), MARK_COLOR)
	if is_fleeing():
		draw_string(ThemeDB.fallback_font, Vector2(-4, -32), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.4, 0.3))
	super()
