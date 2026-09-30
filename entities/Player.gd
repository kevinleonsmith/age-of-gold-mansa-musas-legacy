# Player Controller (res://entities/Player.gd)
extends Unit

const SPEED := 300.0
# Seconds between the Mansa falling and the defeat screen.
const DEFEAT_DELAY := 1.0

func _init() -> void:
	max_health = 150.0
	attack_damage = 25.0
	attack_range = 56.0
	attack_cooldown = 0.5

func _ready() -> void:
	add_to_group("player")
	add_to_group("allies")

func _physics_process(_delta: float) -> void:
	if is_dead:
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * SPEED * GameData.get_modifier("sandstorm_slow_mult")
	move_and_slide()

	if Input.is_action_just_pressed("attack"):
		attack_nearest()

	# Debug: press interact to get free gold
	if Input.is_action_just_pressed("interact"):
		GameData.gold += 10

# Attacks the nearest enemy in range. Returns true if a hit landed.
func attack_nearest() -> bool:
	var target := find_nearest_in_group("enemies", attack_range)
	if target == null:
		return false
	return try_attack(target)

func _on_died() -> void:
	# Game over: hide, stop acting, then declare the defeat (skirmish and missions).
	hide()
	velocity = Vector2.ZERO
	set_process(false)
	set_physics_process(false)
	set_deferred("collision_layer", 0)
	var generation := GameData.generation
	get_tree().create_timer(DEFEAT_DELAY).timeout.connect(_declare_defeat.bind(generation))

func _declare_defeat(generation: int) -> void:
	# Skip if a new game started in the meantime.
	if generation != GameData.generation:
		return
	VictoryManager.declare_defeat("player_died", "The Mansa has fallen",
		"Without its ruler the court scatters, and the gold of Mali passes to other hands.")
