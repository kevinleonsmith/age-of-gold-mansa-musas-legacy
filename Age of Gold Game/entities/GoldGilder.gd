# Gold Gilder (res://entities/GoldGilder.gd)
# Age II non-combat craftsman (design: "Converts 100 Gold Dust -> 1 Ingot every
# 30s"). While alive, every mint_interval seconds it mints one ingot through
# EconomyManager.mint_ingot() if the treasury can afford it. It follows the
# player at a distance and retreats to the player when enemies come close.
extends Unit

signal ingot_minted

const POP_TIME := 1.2
const RETREAT_HOLD := 2.5 # keep hiding by the player this long after a threat
const INGOT_COLOR := Color(1.0, 0.8, 0.15)

@export var move_speed := 200.0
@export var mint_interval := 30.0
@export var follow_distance := 110.0
@export var follow_tolerance := 15.0
@export var enemy_flee_radius := 110.0

var ingots_minted := 0
var _mint_time_left := 0.0
var _pop_left := 0.0
var _generation := 0
var _retreat_left := 0.0

func _init() -> void:
	max_health = 80.0
	attack_damage = 0.0

func _ready() -> void:
	add_to_group("allies")
	_mint_time_left = mint_interval
	_generation = GameData.generation

func get_mint_time_left() -> float:
	return _mint_time_left

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_mint_time_left -= delta
	if _mint_time_left <= 0.0:
		_mint_time_left += mint_interval
		try_mint()
	if _pop_left > 0.0:
		_pop_left = maxf(_pop_left - delta, 0.0)
	queue_redraw() # the mint progress arc changes every frame
	_retreat_left = maxf(_retreat_left - delta, 0.0)
	velocity = _compute_velocity() * GameData.get_modifier("sandstorm_slow_mult")
	move_and_slide()

# Mints one ingot if affordable. Returns true on success.
func try_mint() -> bool:
	if GameData.generation != _generation:
		# The game was reset under us: don't touch the new game's treasury this tick.
		_generation = GameData.generation
		return false
	if not EconomyManager.mint_ingot():
		return false
	ingots_minted += 1
	_pop_left = POP_TIME
	AudioManager.play_sfx("coin", global_position)
	ingot_minted.emit()
	queue_redraw()
	return true

func _compute_velocity() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return Vector2.ZERO
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	if find_nearest_in_group("enemies", enemy_flee_radius) != null:
		_retreat_left = RETREAT_HOLD
	if _retreat_left > 0.0:
		# Threatened recently: retreat to (and stay at) the player's side.
		if distance > 30.0:
			return to_player.normalized() * move_speed
		return Vector2.ZERO
	if absf(distance - follow_distance) <= follow_tolerance:
		return Vector2.ZERO
	var slot := player.global_position - to_player.normalized() * follow_distance
	var to_slot := slot - global_position
	if to_slot.length() < 4.0:
		return Vector2.ZERO
	var speed := move_speed
	if to_slot.length() < 30.0:
		speed *= to_slot.length() / 30.0
	return to_slot.normalized() * speed

func _draw() -> void:
	if _pop_left > 0.0:
		var t := 1.0 - _pop_left / POP_TIME
		var alpha := 1.0 - t * t
		var c := Vector2(0, -26.0 - t * 22.0)
		var ingot := PackedVector2Array([c + Vector2(-7, 3), c + Vector2(7, 3), c + Vector2(5, -3), c + Vector2(-5, -3)])
		draw_colored_polygon(ingot, Color(INGOT_COLOR, alpha))
		draw_polyline(ingot + PackedVector2Array([ingot[0]]), Color(0.35, 0.2, 0.0, alpha), 1.0)
		draw_string(ThemeDB.fallback_font, c + Vector2(10, 5), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.4, alpha))
	# Small progress arc toward the next ingot.
	var progress := 1.0 - clampf(_mint_time_left / maxf(mint_interval, 0.01), 0.0, 1.0)
	draw_arc(Vector2(12, -18), 4.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 16, Color(INGOT_COLOR, 0.8), 2.0)
	super()
