# Resource Collection System (res://systems/ResourceNode.gd)
class_name ResourceNode
extends Area2D

signal depleted

enum RESOURCE_TYPE {GOLD, SALT, MANUSCRIPTS}

# World map sprites (64x64); HUD icons live in assets/ui/.
const GOLD_SPRITE := preload("res://assets/resources/gold_mine.png")
const SALT_SPRITE := preload("res://assets/resources/salt_deposit.png")
const MANUSCRIPT_SPRITE := preload("res://assets/resources/manuscript_cache.png")
const HARVEST_TIME := 1.0
# The sprite shrinks from full size to this scale as quantity runs out.
const MIN_DEPLETED_SCALE := 0.8

@export var resource_type: RESOURCE_TYPE = RESOURCE_TYPE.GOLD
@export var quantity := 50

var being_harvested := false
var players_inside := 0
var _yield_carry := 0.0
var _initial_quantity := 1
var _base_sprite_scale := Vector2.ONE

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_initial_quantity = maxi(quantity, 1)
	_base_sprite_scale = $Sprite2D.scale
	match resource_type:
		RESOURCE_TYPE.GOLD:
			$Sprite2D.texture = GOLD_SPRITE
		RESOURCE_TYPE.SALT:
			$Sprite2D.texture = SALT_SPRITE
		RESOURCE_TYPE.MANUSCRIPTS:
			$Sprite2D.texture = MANUSCRIPT_SPRITE
	_update_depletion_visual()

# Visual only: shrink the sprite as the node runs out.
func _update_depletion_visual() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var frac := clampf(float(quantity) / float(_initial_quantity), 0.0, 1.0)
	sprite.scale = _base_sprite_scale * lerpf(MIN_DEPLETED_SCALE, 1.0, frac)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		players_inside += 1
		if not being_harvested:
			start_harvest()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		players_inside = maxi(players_inside - 1, 0)

# Harvests once per HARVEST_TIME for as long as a player stays inside.
func start_harvest() -> void:
	being_harvested = true
	while players_inside > 0 and quantity > 0:
		await get_tree().create_timer(HARVEST_TIME).timeout
		if not is_inside_tree() or is_queued_for_deletion():
			return
		if players_inside <= 0:
			break
		harvest_once()
	being_harvested = false

func harvest_once() -> void:
	# Base yield: 10 gold/salt or 1 manuscript. Tech modifiers scale it; the
	# fractional part carries over so small bonuses aren't lost to rounding.
	var base := 1.0 if resource_type == RESOURCE_TYPE.MANUSCRIPTS else 10.0
	var mult := GameData.get_modifier("harvest_mult")
	if resource_type == RESOURCE_TYPE.SALT:
		mult *= GameData.get_modifier("salt_harvest_mult")
	_yield_carry += base * mult
	var amount := int(floor(_yield_carry + 0.0001))
	_yield_carry = maxf(_yield_carry - amount, 0.0)
	if amount > 0:
		match resource_type:
			RESOURCE_TYPE.GOLD:
				GameData.gold += amount
			RESOURCE_TYPE.SALT:
				GameData.salt += amount
			RESOURCE_TYPE.MANUSCRIPTS:
				GameData.manuscripts += amount

	# Quantity drains at the base rate, so bonuses mean more total yield.
	quantity -= 10
	_update_depletion_visual()

	if quantity <= 0:
		depleted.emit()
		queue_free()
