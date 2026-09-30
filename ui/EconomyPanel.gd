# Economy panel, top-right (res://ui/EconomyPanel.gd)
# Ingots, the inflation meter, the rivals' treasury, and the economy actions.
# Unavailable buttons are disabled and say why.
extends CanvasLayer

const DISTRIBUTE_AMOUNT := 200
const BANNER_TIME := 6.0
const STATE_COLORS := {
	"Stable": Color(0.3, 0.8, 0.3),
	"Rising": Color(0.95, 0.8, 0.2),
	"Crisis": Color(0.9, 0.25, 0.2),
}

@onready var ingot_label: Label = %IngotLabel
@onready var rival_label: Label = %RivalLabel
@onready var price_label: Label = %PriceLabel
@onready var price_meter: ProgressBar = %PriceMeter
@onready var mint_button: Button = %MintButton
@onready var caravan_button: Button = %CaravanButton
@onready var distribute_button: Button = %DistributeButton
@onready var sell_button: Button = %SellButton
@onready var banner: Label = %Banner

var _meter_fill := StyleBoxFlat.new()

func _ready() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.1, 0.05, 0.8)
	price_meter.add_theme_stylebox_override("background", bg)
	price_meter.add_theme_stylebox_override("fill", _meter_fill)

	mint_button.pressed.connect(_on_mint_pressed)
	caravan_button.pressed.connect(_on_caravan_pressed)
	distribute_button.pressed.connect(_on_distribute_pressed)
	sell_button.pressed.connect(_on_sell_pressed)

	for sig in [GameData.gold_changed, GameData.ingots_changed, GameData.manuscripts_changed]:
		sig.connect(func(_v): refresh())
	GameData.modifiers_changed.connect(func(_k, _v): refresh())
	EconomyManager.price_index_changed.connect(func(_v): refresh())
	EconomyManager.rival_gold_changed.connect(func(_v): refresh())
	EconomyManager.rivals_collapsed.connect(_on_rivals_collapsed)
	TechManager.tech_researched.connect(func(_id): refresh())
	AgeManager.age_changed.connect(func(_a): refresh())
	refresh()

func refresh() -> void:
	var ingots := GameData.ingots
	ingot_label.text = "%d Ingot%s" % [ingots, "" if ingots == 1 else "s"]
	if EconomyManager.is_rivals_collapsed():
		rival_label.text = "Rivals: bankrupt"
	else:
		rival_label.text = "Rivals: %d gold" % int(ceil(EconomyManager.rival_gold))

	var state := EconomyManager.get_inflation_state()
	var price := EconomyManager.price_index
	price_label.text = "Gold price x%.2f - %s" % [price, state]
	price_label.add_theme_color_override("font_color", STATE_COLORS[state])
	price_meter.value = price
	_meter_fill.bg_color = STATE_COLORS[state]

	var gold := GameData.gold
	var mint_cost := EconomyManager.INGOT_GOLD_COST
	_set_button(mint_button, "Mint Ingot (%d Gold)" % mint_cost,
		"" if EconomyManager.can_mint_ingot() else "need %d Gold" % mint_cost)

	var caravan_cost: Dictionary = EconomyManager.CARAVAN_COST
	var caravan_reason := ""
	if not GameData.can_afford(caravan_cost):
		caravan_reason = "not enough Gold"
	elif _get_player() == null:
		caravan_reason = "no Mansa"
	_set_button(caravan_button, "Send Caravan (%s)" % GameData.format_cost(caravan_cost), caravan_reason)

	var dist_reason := "" if gold >= DISTRIBUTE_AMOUNT else "need %d Gold" % DISTRIBUTE_AMOUNT
	_set_button(distribute_button, "Distribute Gold (%d)" % DISTRIBUTE_AMOUNT, dist_reason)
	if EconomyManager.is_hajj_age():
		distribute_button.tooltip_text = "Hajj charity: lowers prices, allies +5% attack for 30 s."
	else:
		distribute_button.tooltip_text = "Before the Golden Hajj: half the price relief, no morale boost."

	sell_button.visible = TechManager.is_researched("manuscript_bazaar")
	_set_button(sell_button, "Sell Manuscript (%d Gold)" % EconomyManager.MANUSCRIPT_SALE_GOLD,
		"" if GameData.manuscripts >= 1 else "no Manuscripts")

func _set_button(button: Button, label: String, reason: String) -> void:
	button.disabled = reason != ""
	button.text = label if reason == "" else "%s - %s" % [label, reason]

func _get_player() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Node2D

func _on_mint_pressed() -> void:
	EconomyManager.mint_ingot()
	refresh()

func _on_caravan_pressed() -> void:
	var player := _get_player()
	if player != null:
		EconomyManager.send_caravan(player.global_position, player.get_parent())
	refresh()

func _on_distribute_pressed() -> void:
	EconomyManager.distribute_gold(DISTRIBUTE_AMOUNT)
	refresh()

func _on_sell_pressed() -> void:
	EconomyManager.sell_manuscript()
	refresh()

func _on_rivals_collapsed() -> void:
	refresh()
	banner.visible = true
	banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(BANNER_TIME)
	tween.tween_property(banner, "modulate:a", 0.0, 1.5)
	tween.tween_callback(func(): banner.visible = false)
