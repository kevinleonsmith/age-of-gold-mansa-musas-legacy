# Trade caravan (res://entities/Caravan.gd)
# Shuttles between home (nearest outpost building, else its spawn point) and
# the farthest trade post. Loads cargo worth distance/10 gold (x2 on long
# desert routes, x caravan_cargo_mult), plus salt from salt posts, then
# returns home and pays out through GameData.add_resources. Repeats forever.
#
# Escort mode (campaign): set `one_way = true` and `route_points` (global
# positions) before adding it to the tree. It walks the route once, emits
# `arrived` at the last point and stops (no cargo payout). With
# `wait_for_player_distance` > 0 it halts while the player is farther away.
# Caravans are "camel" units: sandstorms (sandstorm_slow_mult) don't slow them.
class_name Caravan
extends Unit

enum State { IDLE, TO_POST, TO_HOME, ESCORT, ARRIVED }

const BASE_SPEED := 90.0
const ARRIVE_DISTANCE := 8.0
const LONG_ROUTE := 800.0  # "Golden Caravans: 2x gold when crossing deserts"
const RETRY_TIME := 1.0

signal cargo_loaded(gold: int, salt: int)
signal cargo_delivered(gold: int, salt: int)
signal arrived
signal waypoint_reached(index: int)

@export var one_way := false
@export var route_points: Array[Vector2] = []
@export var wait_for_player_distance := 0.0
@export var speed_scale := 1.0

var state := State.IDLE
var spawn_point := Vector2.ZERO
var home_position := Vector2.ZERO
var destination: Node2D = null
var cargo_gold := 0
var cargo_salt := 0
var trips_completed := 0
var _retry_left := 0.0
var route_index := 0
var has_arrived := false
var is_waiting := false
var _rest_left := 0.0

func _init() -> void:
	max_health = 80.0
	attack_damage = 0.0
	attack_range = 0.0

func _ready() -> void:
	add_to_group("allies")
	add_to_group("caravans")
	add_to_group("camel")
	spawn_point = global_position
	if one_way:
		if route_points.is_empty():
			var post := find_destination(global_position)
			if post != null:
				route_points.append(post.global_position)
		state = State.ESCORT
	else:
		_start_trip()

func has_cargo() -> bool:
	return cargo_gold > 0 or cargo_salt > 0

func get_speed() -> float:
	return BASE_SPEED * speed_scale * GameData.get_modifier("caravan_speed_mult")

# Total length of the escort route from the spawn point (px).
func get_route_length() -> float:
	var total := 0.0
	var prev := spawn_point
	for p in route_points:
		total += prev.distance_to(p)
		prev = p
	return total

# Share of the escort route travelled, 0..1.
func get_route_progress() -> float:
	if has_arrived:
		return 1.0
	var total := get_route_length()
	if total <= 0.0 or route_index >= route_points.size():
		return 1.0 if total <= 0.0 else 0.0
	var done := 0.0
	var prev := spawn_point
	for i in route_index:
		done += prev.distance_to(route_points[i])
		prev = route_points[i]
	var leg := prev.distance_to(route_points[route_index])
	var left := global_position.distance_to(route_points[route_index])
	done += maxf(leg - left, 0.0)
	return clampf(done / total, 0.0, 1.0)

# Home: the nearest "building_outpost" node, or the spawn point.
func find_home() -> Vector2:
	var best := INF
	var result := spawn_point
	for node in get_tree().get_nodes_in_group("building_outpost"):
		var n := node as Node2D
		if n == null or not n.is_inside_tree():
			continue
		var d := global_position.distance_to(n.global_position)
		if d < best:
			best = d
			result = n.global_position
	return result

# Destination: the trade post farthest from `from`.
func find_destination(from: Vector2) -> Node2D:
	var best := -1.0
	var result: Node2D = null
	for node in get_tree().get_nodes_in_group("trade_posts"):
		var n := node as Node2D
		if n == null or not n.is_inside_tree():
			continue
		var d := from.distance_to(n.global_position)
		if d > best:
			best = d
			result = n
	return result

func _start_trip() -> void:
	home_position = find_home()
	destination = find_destination(home_position)
	if destination == null:
		state = State.IDLE
		_retry_left = RETRY_TIME
	else:
		state = State.TO_POST

# Payout for a route of `distance` px, loaded at `post`.
func compute_cargo(distance: float, post: Node) -> Dictionary:
	var gold := distance / 10.0 * GameData.get_modifier("caravan_cargo_mult")
	if distance > LONG_ROUTE:
		gold *= 2.0
	var g := int(round(gold))
	var s := 0
	if post != null and str(post.get("trade_good")) == "salt":
		s = g / 2
	return {"gold": g, "salt": s}

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	match state:
		State.ESCORT:
			_escort_step(delta)
		State.ARRIVED:
			velocity = Vector2.ZERO
		State.IDLE:
			velocity = Vector2.ZERO
			_retry_left -= delta
			if _retry_left <= 0.0:
				_start_trip()
		State.TO_POST:
			if not is_instance_valid(destination) or not destination.is_inside_tree():
				_start_trip()
				return
			if _move_to(destination.global_position, delta):
				var cargo := compute_cargo(home_position.distance_to(destination.global_position), destination)
				cargo_gold = cargo["gold"]
				cargo_salt = cargo["salt"]
				state = State.TO_HOME
				queue_redraw()
				cargo_loaded.emit(cargo_gold, cargo_salt)
		State.TO_HOME:
			if _move_to(home_position, delta):
				var g := cargo_gold
				var s := cargo_salt
				GameData.add_resources({"gold": g, "salt": s})
				cargo_gold = 0
				cargo_salt = 0
				trips_completed += 1
				queue_redraw()
				cargo_delivered.emit(g, s)
				_start_trip()

func _escort_step(delta: float) -> void:
	if route_index >= route_points.size():
		_arrive()
		return
	is_waiting = false
	if _rest_left > 0.0:
		_rest_left -= delta
		velocity = Vector2.ZERO
		return
	if wait_for_player_distance > 0.0:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and global_position.distance_to(player.global_position) > wait_for_player_distance:
			is_waiting = true
			velocity = Vector2.ZERO
			return
	if _move_to(route_points[route_index], delta):
		waypoint_reached.emit(route_index)
		route_index += 1
		if route_index >= route_points.size():
			_arrive()

# Escort mode: halt for `seconds` (e.g. a stop at a city).
func rest(seconds: float) -> void:
	_rest_left = maxf(_rest_left, seconds)

func is_resting() -> bool:
	return _rest_left > 0.0

func _arrive() -> void:
	if has_arrived:
		return
	has_arrived = true
	state = State.ARRIVED
	velocity = Vector2.ZERO
	arrived.emit()

# Moves toward point; returns true on arrival. Caravans follow trade roads
# and pass through other bodies rather than getting stuck on them.
func _move_to(point: Vector2, delta: float) -> bool:
	var step := get_speed() * delta
	var to_point := point - global_position
	if to_point.length() <= maxf(step, ARRIVE_DISTANCE):
		global_position = point
		velocity = Vector2.ZERO
		return true
	velocity = to_point.normalized() * get_speed()
	global_position += velocity * delta
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.flip_h = velocity.x < 0.0
	return false

func take_damage(amount: float) -> void:
	super(amount * GameData.get_modifier("caravan_damage_taken_mult"))

func _draw() -> void:
	super()
	if has_cargo():
		# Small cargo sack above the caravan: gold, with a white salt slab.
		draw_rect(Rect2(-5, -38, 10, 7), Color(1.0, 0.8, 0.1), true)
		draw_rect(Rect2(-5, -38, 10, 7), Color(0.2, 0.12, 0.05), false, 1.0)
		if cargo_salt > 0:
			draw_rect(Rect2(6, -37, 6, 5), Color(0.96, 0.96, 0.94), true)
			draw_rect(Rect2(6, -37, 6, 5), Color(0.2, 0.12, 0.05), false, 1.0)
