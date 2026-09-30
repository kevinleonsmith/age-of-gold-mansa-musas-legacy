# Donson Ton (res://entities/DonsonTon.gd)
# Age II elite hunter-guard with innate poisoned spears (design: "-3 HP/sec"):
# every hit also poisons the target for poison_dps over poison_duration. It
# guards the player tightly and intercepts enemies that close in on the player.
extends Unit

@export var move_speed := 230.0
@export var guard_distance := 60.0 # stays within this of the player
@export var intercept_radius := 220.0 # enemies this close to the player get intercepted
@export var aggro_radius := 110.0 # enemies this close to the guard itself
@export var leash_distance := 320.0 # never chases further than this from the player
@export var poison_dps := 3.0
@export var poison_duration := 3.0

var target: Unit = null

func _init() -> void:
	max_health = 180.0
	attack_damage = 22.0
	attack_range = 42.0
	attack_cooldown = 0.9

func _ready() -> void:
	add_to_group("allies")

func _physics_process(_delta: float) -> void:
	if is_dead:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	target = _pick_target(player)
	if target != null:
		if global_position.distance_to(target.global_position) <= attack_range:
			velocity = Vector2.ZERO
			strike(target)
		else:
			_move_toward(target.global_position)
		return
	if player == null:
		velocity = Vector2.ZERO
		return
	# Guard post: just beside the player.
	var post := player.global_position + Vector2(guard_distance * 0.6, 0)
	if global_position.distance_to(player.global_position) > guard_distance or global_position.distance_to(post) > guard_distance * 0.5:
		_move_toward(post)
	else:
		velocity = Vector2.ZERO

# Enemy nearest the player within intercept_radius, else the nearest one to
# the guard within aggro_radius (while not leashed too far from the player).
func _pick_target(player: Node2D) -> Unit:
	if player == null:
		return find_nearest_in_group("enemies", aggro_radius)
	var best: Unit = null
	var best_d := intercept_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		var unit := node as Unit
		if unit == null or unit.is_dead:
			continue
		var d := player.global_position.distance_to(unit.global_position)
		if d <= best_d:
			best_d = d
			best = unit
	if best != null:
		return best
	var near := find_nearest_in_group("enemies", aggro_radius)
	if near != null and player.global_position.distance_to(near.global_position) <= leash_distance:
		return near
	return null

# Attacks with a poisoned spear. Returns true if the blow landed.
func strike(enemy) -> bool:
	if not is_instance_valid(enemy) or not try_attack(enemy):
		return false
	if is_instance_valid(enemy) and not enemy.is_dead:
		enemy.apply_poison(poison_dps, poison_duration)
	return true

func _move_toward(point: Vector2) -> void:
	var speed := move_speed * GameData.get_modifier("sandstorm_slow_mult")
	var dist := global_position.distance_to(point)
	if dist < 30.0:
		speed *= maxf(dist / 30.0, 0.3)
	velocity = _steer(global_position.direction_to(point)) * speed
	move_and_slide()

# Sidesteps a body (usually the player being guarded) hit head-on last frame,
# so the guard walks around it instead of pushing against it.
func _steer(dir: Vector2) -> Vector2:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() == target:
			continue
		var n := col.get_normal()
		if dir.dot(n) < -0.3:
			var tangent := n.orthogonal()
			if tangent.dot(dir) < 0.0:
				tangent = -tangent
			return (dir + tangent * 1.5).normalized()
	return dir
