# Trade post (res://systems/TradePost.gd)
# A caravan destination such as Walata (gold) or Taghaza (salt). Caravans
# head for the farthest post in the "trade_posts" group; salt posts also
# send back salt.
class_name TradePost
extends Node2D

@export var post_name := "Walata"
@export_enum("gold", "salt") var trade_good := "gold"

func _ready() -> void:
	add_to_group("trade_posts")
	_update_label()

func _update_label() -> void:
	var label := get_node_or_null("Label") as Label
	if label:
		label.text = "%s (%s)" % [post_name, trade_good.capitalize()]
