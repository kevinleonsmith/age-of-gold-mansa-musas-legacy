# Gold economy: inflation, ingots, rival treasuries (res://autoload/EconomyManager.gd)
# Mansa Musa's 1324 Hajj flooded Cairo with gold and crashed its price. Here the
# player's hoard (gold + ingots) drives a price index that inflates every gold
# cost (GameData "gold_price_mult"), while ingots drain the rivals' treasuries.
extends Node

signal price_index_changed(value: float)
signal rival_gold_changed(value: float)
signal rivals_collapsed
signal gold_distributed(amount: int)

const MIN_PRICE := 1.0
const MAX_PRICE := 3.0
const GOLD_PER_PRICE_POINT := 3000.0  # +1.0 price per 3000 gold held
const PRICE_PER_INGOT := 0.015
const RISE_RATE := 0.02  # base upward easing per second (+25% of the gap per second)
const RECOVERY_RATE := 0.01  # downward easing per second (x2 with economic_stabilization)
const MIRROR_STEP := 0.01  # re-publish the modifier when the index moves this much

const INGOT_GOLD_COST := 100  # raw gold per ingot (design: 1000 dust, scaled)
const MANUSCRIPT_SALE_GOLD := 200
const CHARITY_PRICE_DIVISOR := 2000.0  # distribute_gold lowers price by amount / 2000
const CHARITY_MORALE_MULT := 1.05
const CHARITY_MORALE_TIME := 30.0

const RIVAL_START_GOLD := 5000.0
const INGOTS_PER_DRAIN := 10.0  # rivals lose 1 gold/s per 10 ingots (design: per 1000)
const HYPERINFLATION_MULT := 3.0

const CARAVAN_COST := {"gold": 60}
const CARAVAN_SCENE_PATH := "res://entities/Caravan.tscn"

# 1.0 = stable prices. Mirrored into GameData "gold_price_mult".
var price_index := 1.0
var rival_gold := 5000.0

var _mirrored_price := 1.0
var _collapse_emitted := false
var _last_rival_whole := 5000

func reset() -> void:
	rival_gold = RIVAL_START_GOLD
	_collapse_emitted = false
	_last_rival_whole = int(RIVAL_START_GOLD)
	rival_gold_changed.emit(rival_gold)
	reset_inflation()

func _process(delta: float) -> void:
	_update_price(delta)
	_drain_rivals(delta)

# --- Inflation -------------------------------------------------------------

func get_target_price() -> float:
	var target := 1.0 + GameData.gold / GOLD_PER_PRICE_POINT + GameData.ingots * PRICE_PER_INGOT
	return clampf(target, MIN_PRICE, MAX_PRICE)

func _update_price(delta: float) -> void:
	var target := get_target_price()
	if price_index < target:
		var rate := RISE_RATE + (target - price_index) * 0.25
		price_index = minf(price_index + rate * delta, target)
	elif price_index > target:
		var down := RECOVERY_RATE
		if TechManager.is_researched("economic_stabilization"):
			down *= 2.0
		price_index = maxf(price_index - down * delta, target)
	if absf(price_index - _mirrored_price) >= MIRROR_STEP:
		_publish_price()

func _publish_price() -> void:
	price_index = clampf(price_index, MIN_PRICE, MAX_PRICE)
	_mirrored_price = price_index
	GameData.set_modifier("gold_price_mult", price_index)
	price_index_changed.emit(price_index)

# "Stable" / "Rising" / "Crisis".
func get_inflation_state() -> String:
	if price_index < 1.25:
		return "Stable"
	if price_index < 1.75:
		return "Rising"
	return "Crisis"

# Resets prices to 1.0 (e.g. "Flood the markets" event option).
func reset_inflation() -> void:
	price_index = 1.0
	_publish_price()

# --- Player actions --------------------------------------------------------

func can_mint_ingot() -> bool:
	return GameData.gold >= INGOT_GOLD_COST

# Raw (uninflated) conversion: 100 gold -> 1 ingot.
func mint_ingot() -> bool:
	if not can_mint_ingot():
		return false
	GameData.gold -= INGOT_GOLD_COST
	GameData.ingots += 1
	return true

func is_hajj_age() -> bool:
	return AgeManager.current_age == AgeManager.AGES.GOLDEN_HAJJ

# Hajj charity: gives away `amount` raw gold. Lowers the price index by
# amount/2000 at once and boosts allied morale (ally_attack_mult x1.05 for 30 s).
# Before the Golden Hajj age it still works, at half the price effect and
# without the morale boost.
func distribute_gold(amount: int) -> bool:
	if amount <= 0 or GameData.gold < amount:
		return false
	GameData.gold -= amount
	var drop := amount / CHARITY_PRICE_DIVISOR
	if not is_hajj_age():
		drop *= 0.5
	price_index = maxf(price_index - drop, MIN_PRICE)
	_publish_price()
	gold_distributed.emit(amount)
	if is_hajj_age():
		GameData.multiply_modifier("ally_attack_mult", CHARITY_MORALE_MULT)
		var generation := GameData.generation
		get_tree().create_timer(CHARITY_MORALE_TIME, false).timeout.connect(
			func():
				if generation == GameData.generation:
					GameData.multiply_modifier("ally_attack_mult", 1.0 / CHARITY_MORALE_MULT))
	return true

func can_sell_manuscript() -> bool:
	return TechManager.is_researched("manuscript_bazaar") and GameData.manuscripts >= 1

# Needs the manuscript_bazaar tech: 1 manuscript -> 200 gold.
func sell_manuscript() -> bool:
	if not can_sell_manuscript():
		return false
	GameData.manuscripts -= 1
	GameData.gold += MANUSCRIPT_SALE_GOLD
	return true

# Buys a caravan (inflated cost via GameData.spend) and spawns it at `at`
# under `parent` (defaults to the current scene). Returns it, or null.
func send_caravan(at: Vector2, parent: Node = null) -> Node2D:
	if parent == null:
		parent = get_tree().current_scene
	if parent == null or not GameData.spend(CARAVAN_COST):
		return null
	var caravan := (load(CARAVAN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	caravan.position = at
	parent.add_child(caravan)
	return caravan

# --- Rival treasuries ------------------------------------------------------

func get_rival_drain_rate() -> float:
	var rate := GameData.ingots / INGOTS_PER_DRAIN
	if TechManager.is_researched("hyperinflation"):
		rate *= HYPERINFLATION_MULT
	return rate

func _drain_rivals(delta: float) -> void:
	if rival_gold <= 0.0:
		return
	var rate := get_rival_drain_rate()
	if rate > 0.0:
		_set_rival_gold(rival_gold - rate * delta)

func _set_rival_gold(value: float) -> void:
	rival_gold = maxf(value, 0.0)
	var whole := int(ceil(rival_gold))
	if whole != _last_rival_whole:
		_last_rival_whole = whole
		rival_gold_changed.emit(rival_gold)
	if rival_gold <= 0.0 and not _collapse_emitted:
		_collapse_emitted = true
		rivals_collapsed.emit()

# Drains the rivals' treasury directly (events). Emits rivals_collapsed at 0.
func drain_rival_gold(amount: float) -> void:
	_set_rival_gold(rival_gold - amount)

func is_rivals_collapsed() -> bool:
	return rival_gold <= 0.0
