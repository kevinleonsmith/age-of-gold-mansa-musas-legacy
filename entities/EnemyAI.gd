# Enemy AI (res://entities/EnemyAI.gd)
# Targets can be Units or Buildings: any Node2D with take_damage() that is not
# dead/destroyed. Hostile raiders prioritise (design doc "AI Behavior") gold
# caravans 60%, unprotected mosques 30% and the hero 10%; converted raiders
# hunt "enemies", which includes the Songhai rival buildings.
extends Unit

enum STATE {IDLE, PATROL, CHASE, MARCH}

signal converted

const RETARGET_INTERVAL := 0.5
const BOUNTY := 5
const CONVERTED_TINT := Color(0.7, 0.85, 1.0)
const ESCORT_DISTANCE := 150.0
const WANDER_RANGE := 80.0
# Priority targeting
const CLOSE_COMBAT_RANGE := 90.0 # an ally this close always wins the retarget
const PRIORITY_RADIUS := 600.0 # extended search radius for the weighted pick
const MOSQUE_GUARD_RADIUS := 200.0 # a mosque with an ally this close is "protected"
const PRIORITY_WEIGHTS := {"caravan": 60.0, "mosque": 30.0, "hero": 10.0}
# Marching toward the player's base
const MARCH_ARRIVE_DISTANCE := 160.0
const MARCH_SPEED_MULT := 1.2

@export var detection_radius := 250.0
@export var patrol_speed := 100.0
@export var chase_speed := 200.0
@export var patrol_range := 200.0
@export var is_guard := false # rival base garrison: patrols home, never marches

var current_state := STATE.IDLE
var target_position := Vector2.ZERO
var home_position := Vector2.ZERO
var idle_time_left := 0.0
var target = null # Unit or Building (untyped: may be freed at any time)
var _retarget_time_left := 0.0
var target_group := "allies" # the group this unit hunts; "enemies" once converted
var is_converted := false
var rng := RandomNumberGenerator.new()
var _priority_target := false # current target came from the weighted pick
var is_marching := false
var _march_point := Vector2.ZERO
var _march_refresh_left := 0.0
var _defend_node = null # rival wonder this unit was called to defend
var _defend_time_left := 0.0

func _init() -> void:
	max_health = 60.0
	attack_damage = 8.0
	attack_range = 36.0
	attack_cooldown = 1.0
	rng.randomize()

func _ready() -> void:
	add_to_group("enemies")
	home_position = global_position
	idle_time_left = randf_range(1.0, 3.0)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_defend_time_left = maxf(_defend_time_left - delta, 0.0)
	_retarget_time_left -= delta
	if _retarget_time_left <= 0.0:
		_retarget_time_left = RETARGET_INTERVAL
		_retarget()
	if not _is_valid_target(target) or not _is_hostile_to(target):
		target = null
		_priority_target = false

	if is_converted and target == null:
		_escort_player(delta)
		return

	if target != null and current_state == STATE.MARCH:
		current_state = STATE.CHASE

	match current_state:
		STATE.IDLE:
			handle_idle_state(delta)
		STATE.PATROL:
			handle_patrol_state()
		STATE.CHASE:
			handle_chase_state()
		STATE.MARCH:
			handle_march_state()

# --- Targeting ------------------------------------------------------------------

func _retarget() -> void:
	# Keep chasing a current target out to 1.5x detection (further for a priority
	# target or while defending the wonder), else look for a new one.
	var keep_radius := detection_radius * 1.5
	if _priority_target:
		keep_radius = PRIORITY_RADIUS * 1.25
	if _defend_time_left > 0.0:
		keep_radius = maxf(keep_radius, PRIORITY_RADIUS)
	var keep := _is_valid_target(target) and _is_hostile_to(target) and _distance_to_target(target) <= keep_radius
	if is_converted:
		var nearest = find_nearest_in_group(target_group, detection_radius)
		if nearest == null:
			nearest = _find_nearest_rival_building(detection_radius)
		if nearest != null:
			target = nearest
		elif not keep:
			target = null
		return
	# Hostile: something in close combat range always gets hit first.
	var close := find_nearest_in_group(target_group, CLOSE_COMBAT_RANGE)
	if close != null:
		target = close
		_priority_target = false
		return
	if keep and (_priority_target or _defend_time_left > 0.0):
		return
	var pick = pick_priority_target()
	if pick != null:
		target = pick
		_priority_target = true
		return
	_priority_target = false
	var nearest = find_nearest_in_group(target_group, detection_radius)
	if nearest == null:
		# No defender around: raid the nearest player building.
		nearest = _nearest_valid("buildings", detection_radius, false)
	if nearest != null:
		target = nearest
	elif not keep:
		target = null

# Nearest living rival building (converted-ally rule), or null.
func _find_nearest_rival_building(max_distance: float):
	var best = null
	var best_d := max_distance
	for node in get_tree().get_nodes_in_group("rival_buildings"):
		if not _is_valid_target(node):
			continue
		var d := _distance_to_target(node)
		if d <= best_d:
			best_d = d
			best = node
	return best

# The priority candidates within PRIORITY_RADIUS: {"caravan", "mosque", "hero"}
# -> node, only for the kinds that exist.
func find_priority_candidates() -> Dictionary:
	var found := {}
	var caravan = _nearest_valid("caravans", PRIORITY_RADIUS, false)
	if caravan != null:
		found["caravan"] = caravan
	var mosque = _nearest_valid("building_mosque", PRIORITY_RADIUS, true)
	if mosque != null:
		found["mosque"] = mosque
	var hero = _nearest_valid("hero", PRIORITY_RADIUS, false)
	if hero != null:
		found["hero"] = hero
	return found

# Weighted 60/30/10 pick among the candidates that exist, or null.
func pick_priority_target():
	var candidates := find_priority_candidates()
	var key := choose_priority_key(candidates.keys(), rng.randf())
	return candidates.get(key) if key != "" else null

# Pure weighted choice: `roll` in [0, 1). Returns "" for an empty list.
static func choose_priority_key(keys: Array, roll: float) -> String:
	var total := 0.0
	for key in keys:
		total += float(PRIORITY_WEIGHTS.get(key, 0.0))
	if total <= 0.0:
		return ""
	var pick := roll * total
	for key in ["caravan", "mosque", "hero"]:
		if not keys.has(key):
			continue
		pick -= float(PRIORITY_WEIGHTS[key])
		if pick < 0.0:
			return key
	return String(keys[keys.size() - 1])

func _nearest_valid(group: String, max_distance: float, unprotected_only: bool):
	var best = null
	var best_d := max_distance
	for node in get_tree().get_nodes_in_group(group):
		if node == self or not _is_valid_target(node):
			continue
		var d := _distance_to_target(node)
		if d > best_d:
			continue
		if unprotected_only and _is_protected(node):
			continue
		best_d = d
		best = node
	return best

# True if a living allied unit stands within MOSQUE_GUARD_RADIUS of `building`.
func _is_protected(building) -> bool:
	for node in get_tree().get_nodes_in_group("allies"):
		if not is_instance_valid(node) or node.get("is_dead") or not (node is Node2D):
			continue
		if node.global_position.distance_to(building.global_position) <= MOSQUE_GUARD_RADIUS:
			return true
	return false

# Untyped on purpose: a typed parameter errors when handed a freed target.
func _is_valid_target(node) -> bool:
	if not is_instance_valid(node) or not (node is Node2D) or not node.has_method("take_damage"):
		return false
	if node.get("is_dead") == true or node.get("is_destroyed") == true:
		return false
	return true

# Whether this unit fights `node`: converted units fight "enemies" (which holds
# the rival buildings); hostile raiders fight allies and player buildings.
func _is_hostile_to(node) -> bool:
	if is_converted:
		return node.is_in_group(target_group) or node.is_in_group("rival_buildings")
	return node.is_in_group(target_group) or node.is_in_group("buildings")

# Distance to a target's footprint edge (buildings) or centre (units).
func _distance_to_target(node) -> float:
	if node.has_method("get_footprint_rect"):
		var rect: Rect2 = node.get_footprint_rect()
		var closest := global_position.clamp(rect.position, rect.end)
		return global_position.distance_to(closest)
	return global_position.distance_to(node.global_position)

# Attacks any target (Unit or Building) in range; returns true if a hit landed.
func attack_target(node) -> bool:
	if not can_attack() or not _is_valid_target(node):
		return false
	if node is Unit and not node.has_method("get_footprint_rect"):
		return try_attack(node)
	if _distance_to_target(node) > attack_range:
		return false
	_attack_timer = attack_cooldown
	var damage := attack_damage * attack_multiplier
	if is_in_group("allies"):
		damage *= GameData.get_modifier("ally_attack_mult")
	node.take_damage(damage)
	AudioManager.play_sfx("hit", global_position)
	return true

# --- Movement -------------------------------------------------------------------

# Movement speed after the sandstorm slow (camel units ride through it).
func _speed(base: float) -> float:
	if is_in_group("camel"):
		return base
	return base * GameData.get_modifier("sandstorm_slow_mult")

func handle_idle_state(delta: float) -> void:
	velocity = Vector2.ZERO
	if target != null:
		current_state = STATE.CHASE
		return
	if _defend_time_left > 0.0 and _return_to_defend():
		return
	idle_time_left -= delta
	if idle_time_left <= 0.0:
		start_patrol()

func start_patrol() -> void:
	target_position = home_position + Vector2(
		randf_range(-patrol_range, patrol_range),
		randf_range(-patrol_range, patrol_range)
	)
	current_state = STATE.PATROL

func handle_patrol_state() -> void:
	if target != null:
		current_state = STATE.CHASE
		return
	if global_position.distance_to(target_position) > 10:
		velocity = global_position.direction_to(target_position) * _speed(patrol_speed)
		move_and_slide()
	else:
		idle_time_left = randf_range(1.0, 3.0)
		current_state = STATE.IDLE

func handle_chase_state() -> void:
	if target == null:
		if is_converted:
			current_state = STATE.IDLE
			return
		if is_marching:
			current_state = STATE.MARCH
			return
		start_patrol()
		return
	if _distance_to_target(target) <= attack_range:
		velocity = Vector2.ZERO
		attack_target(target)
		return
	velocity = global_position.direction_to(target.global_position) * _speed(chase_speed)
	move_and_slide()

# Camp raiders: march toward the player's base (nearest "buildings" node, else
# the player). On arrival they patrol there instead of at the camp.
func start_march() -> void:
	if is_converted or is_dead or is_guard:
		return
	is_marching = true
	_march_point = _find_march_point()
	current_state = STATE.MARCH

func _find_march_point() -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if not _is_valid_target(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node.global_position
	if best == Vector2.INF:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		best = player.global_position if player != null else global_position
	return best

func handle_march_state() -> void:
	if target != null:
		current_state = STATE.CHASE
		return
	if not is_marching:
		start_patrol()
		return
	# The base may have moved (new buildings, player walked off): refresh.
	_march_refresh_left -= get_physics_process_delta_time()
	if _march_refresh_left <= 0.0:
		_march_refresh_left = 1.0
		_march_point = _find_march_point()
	if global_position.distance_to(_march_point) <= MARCH_ARRIVE_DISTANCE:
		is_marching = false
		home_position = global_position
		start_patrol()
		return
	velocity = global_position.direction_to(_march_point) * _speed(patrol_speed * MARCH_SPEED_MULT)
	move_and_slide()

# Called by a Rival Wonder under attack: rush back and fight the attacker.
# Untyped parameters on purpose (either may be freed later).
func defend(wonder, attacker = null, duration := 10.0) -> void:
	if is_converted or is_dead:
		return
	_defend_node = wonder
	_defend_time_left = duration
	is_marching = false
	if is_instance_valid(wonder):
		home_position = wonder.global_position + Vector2(randf_range(-80, 80), randf_range(40, 90))
	if _is_valid_target(attacker) and _is_hostile_to(attacker):
		target = attacker
		_priority_target = false
		current_state = STATE.CHASE
	else:
		target_position = home_position
		current_state = STATE.PATROL

func is_defending() -> bool:
	return _defend_time_left > 0.0 and is_instance_valid(_defend_node)

func _return_to_defend() -> bool:
	if not is_instance_valid(_defend_node):
		return false
	if global_position.distance_to(home_position) <= 20.0:
		return false
	target_position = home_position
	current_state = STATE.PATROL
	return true

# --- Conversion -----------------------------------------------------------------

# Griot conversion: this unit switches sides and fights for the player.
func convert_to_ally() -> void:
	if is_dead or is_converted:
		return
	is_converted = true
	is_marching = false
	_defend_time_left = 0.0
	_priority_target = false
	remove_from_group("enemies")
	remove_from_group("camp_raiders")
	add_to_group("allies")
	add_to_group("converted")
	target_group = "enemies"
	target = null
	_retarget_time_left = 0.0
	current_state = STATE.IDLE
	idle_time_left = 0.0
	target_position = global_position
	var sprite := get_node_or_null("Sprite2D") as CanvasItem
	if sprite != null:
		sprite.modulate = CONVERTED_TINT
	else:
		modulate = CONVERTED_TINT
	heal(max_health)
	converted.emit()
	GameData.add_modifier("converted_count", 1.0)

# Converted units with nothing to fight escort the player, like the CamelLancer.
func _escort_player(delta: float) -> void:
	current_state = STATE.IDLE
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and global_position.distance_to(player.global_position) > ESCORT_DISTANCE:
		_move_toward(player.global_position)
		target_position = global_position
		return
	if global_position.distance_to(target_position) > 10:
		_move_toward(target_position)
		return
	velocity = Vector2.ZERO
	idle_time_left -= delta
	if idle_time_left <= 0.0:
		idle_time_left = randf_range(1.5, 3.5)
		var center := player.global_position if player != null else global_position
		target_position = center + Vector2(
			randf_range(-WANDER_RANGE, WANDER_RANGE),
			randf_range(-WANDER_RANGE, WANDER_RANGE)
		)

func _move_toward(point: Vector2) -> void:
	velocity = global_position.direction_to(point) * _speed(chase_speed)
	move_and_slide()

func _on_died() -> void:
	if not is_converted and is_in_group("enemies"):
		GameData.gold += BOUNTY
	queue_free()
