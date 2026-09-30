# Golden Mansa (res://entities/GoldenMansa.gd)
# Age III unique hero (design: "Hero unit distributing gold; converts enemies
# at 5 HP/sec"). No normal attack. Every enemy inside its golden aura gains
# devotion at devotion_rate per second (x "conversion_speed_mult"); once an
# enemy's devotion reaches its current health it converts to the player's side.
# Every distribute_interval seconds it gives away distribute_amount gold via
# EconomyManager.distribute_gold(), cooling inflation. Its death is announced.
extends Unit

signal enemy_converted(unit: Node)
signal gold_distributed(amount: int)

const AURA_COLOR := Color(1.0, 0.82, 0.2)
const SPARKLE_TIME := 1.0

@export var move_speed := 150.0
@export var follow_distance := 90.0
@export var aura_radius := 200.0
@export var devotion_rate := 5.0 # devotion per second, compared against enemy HP
@export var devotion_decay := 5.0 # per second once an enemy leaves the aura
@export var distribute_interval := 20.0
@export var distribute_amount := 50

var conversions := 0
var _devotion := {} # instance_id -> {"ref": WeakRef, "value": float}
var _distribute_left := 0.0
var _sparkle_left := 0.0
var _time := 0.0
var _generation := 0

func _init() -> void:
	max_health = 400.0
	attack_damage = 0.0

func _ready() -> void:
	add_to_group("allies")
	add_to_group("hero")
	_distribute_left = distribute_interval
	_generation = GameData.generation

# Devotion accumulated by `unit` (0 if none). Untyped: the unit may be freed.
func get_devotion(unit) -> float:
	if not is_instance_valid(unit):
		return 0.0
	var entry = _devotion.get(unit.get_instance_id())
	return entry["value"] if entry != null else 0.0

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_time += delta
	_update_devotion(delta)
	_distribute_left -= delta
	if _distribute_left <= 0.0:
		_distribute_left += distribute_interval
		try_distribute()
	if _sparkle_left > 0.0:
		_sparkle_left = maxf(_sparkle_left - delta, 0.0)
	queue_redraw()

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or global_position.distance_to(player.global_position) <= follow_distance:
		velocity = Vector2.ZERO
		return
	var speed := move_speed * GameData.get_modifier("sandstorm_slow_mult")
	velocity = global_position.direction_to(player.global_position) * speed
	move_and_slide()

func _update_devotion(delta: float) -> void:
	var rate := devotion_rate * GameData.get_modifier("conversion_speed_mult")
	var inside := {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var unit := node as Unit
		if unit == null or unit.is_dead or not unit.has_method("convert_to_ally"):
			continue
		if global_position.distance_to(unit.global_position) > aura_radius:
			continue
		var id := unit.get_instance_id()
		inside[id] = true
		if not _devotion.has(id):
			_devotion[id] = {"ref": weakref(unit), "value": 0.0}
		_devotion[id]["value"] += rate * delta
		if _devotion[id]["value"] >= unit.health:
			_devotion.erase(id)
			inside.erase(id)
			unit.convert_to_ally()
			conversions += 1
			AudioManager.play_sfx("convert", unit.global_position)
			enemy_converted.emit(unit)
	# Enemies outside the aura (or gone) slowly lose their devotion.
	for id in _devotion.keys():
		if inside.has(id):
			continue
		var u = _devotion[id]["ref"].get_ref()
		_devotion[id]["value"] -= devotion_decay * delta
		if u == null or not is_instance_valid(u) or u.is_dead or not u.is_in_group("enemies") or _devotion[id]["value"] <= 0.0:
			_devotion.erase(id)

# Gives away distribute_amount gold if affordable. Returns true on success.
func try_distribute() -> bool:
	if GameData.generation != _generation:
		_generation = GameData.generation
		return false
	if GameData.gold < distribute_amount or not EconomyManager.distribute_gold(distribute_amount):
		return false
	_sparkle_left = SPARKLE_TIME
	AudioManager.play_sfx("coin", global_position)
	gold_distributed.emit(distribute_amount)
	return true

func _on_died() -> void:
	var toasts := get_tree().get_first_node_in_group("toasts")
	if toasts != null and toasts.has_method("show_toast"):
		toasts.show_toast("The Golden Mansa has fallen! Mali mourns its king.", Color(1.0, 0.35, 0.25))
	AudioManager.play_sfx("horn", global_position)
	super()

func _draw() -> void:
	# Golden aura: soft fill, rotating dashed rim.
	draw_circle(Vector2.ZERO, aura_radius, Color(AURA_COLOR, 0.06))
	var segments := 24
	for i in segments:
		if i % 2 == 0:
			var a := float(i) / segments * TAU + _time * 0.3
			draw_arc(Vector2.ZERO, aura_radius, a, a + TAU / segments, 4, Color(AURA_COLOR, 0.55), 2.0)
	# Devotion bars above every enemy inside the aura.
	for id in _devotion:
		var u = _devotion[id]["ref"].get_ref()
		if u == null or not is_instance_valid(u) or u.is_dead:
			continue
		var p := to_local(u.global_position)
		var frac := clampf(_devotion[id]["value"] / maxf(u.health, 0.01), 0.0, 1.0)
		var bar := Rect2(p + Vector2(-18, -38), Vector2(36, 4))
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), AURA_COLOR)
		draw_line(Vector2.ZERO, p, Color(AURA_COLOR, 0.15 + 0.35 * frac), 1.0)
	# Coin sparkle after a distribution.
	if _sparkle_left > 0.0:
		var t := 1.0 - _sparkle_left / SPARKLE_TIME
		for i in 8:
			var dir := Vector2.from_angle(i * TAU / 8.0 + t)
			var pos := dir * (14.0 + t * 46.0) + Vector2(0, -10.0 - t * 10.0)
			draw_circle(pos, 3.0 * (1.0 - t) + 1.0, Color(1.0, 0.9, 0.3, 1.0 - t))
	super()
