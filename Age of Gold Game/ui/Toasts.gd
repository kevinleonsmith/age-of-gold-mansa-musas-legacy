# Toast messages and Mansa Musa voice lines (res://ui/Toasts.gd)
# Bottom-center stack of fading messages. Others find it via the "toasts" group:
#   get_tree().get_first_node_in_group("toasts").show_toast("text", Color.WHITE)
# Mansa Musa comments on the gold reserves every mansa_interval seconds and
# whenever the gold tier changes (not while paused or during a dilemma).
extends CanvasLayer

const MAX_TOASTS := 5
const LIFETIME := 4.0
const FADE_TIME := 0.8
const WEALTHY_GOLD := 1000
const POOR_GOLD := 100
const MANSA_COLOR := Color(1.0, 0.84, 0.3)

# Lines per gold tier (design doc "Dynamic Dialog" + MansaDialogue.jsx).
const MANSA_LINES := {
	"wealthy": [
		"The desert itself kneels before Mali!",
		"The world bends to Mali's golden will!",
		"Let Cairo count our gold and marvel.",
	],
	"steady": [
		"Balance in all things, as the scales decree.",
		"A patient caravan crosses every desert.",
		"Gold flows like the Niger; guard its banks.",
	],
	"poor": [
		"Even salt loses its savor without gold.",
		"Even dust holds value when properly gathered.",
		"An empty treasury is a silent drum.",
	],
}

@export var mansa_interval := 45.0
# Minimum seconds between two tier-change lines.
@export var tier_change_cooldown := 8.0

var _mansa_time_left := 0.0
var _since_mansa_line := 1000.0
var _tier := ""
var _tier_line_pending := false
var _last_line := ""

@onready var _stack: VBoxContainer = %Stack

func _ready() -> void:
	add_to_group("toasts")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mansa_time_left = mansa_interval
	_tier = get_gold_tier(GameData.gold)
	GameData.gold_changed.connect(_on_gold_changed)

func _process(delta: float) -> void:
	if get_tree().paused or _dilemma_active():
		return
	_since_mansa_line += delta
	_mansa_time_left -= delta
	if _tier_line_pending and _since_mansa_line >= tier_change_cooldown:
		show_mansa_line()
	elif _mansa_time_left <= 0.0:
		show_mansa_line()

func show_toast(text: String, color := Color.WHITE) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.04, 0.82)
	style.border_color = Color(color, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 15)
	panel.add_child(label)
	_stack.add_child(panel)
	while _stack.get_child_count() > MAX_TOASTS:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()
	var tween := panel.create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(panel.queue_free)

# Texts of the toasts currently on screen (oldest first).
func get_toast_texts() -> Array:
	var texts := []
	for panel in _stack.get_children():
		if panel.is_queued_for_deletion():
			continue
		texts.append((panel.get_child(0) as Label).text)
	return texts

# Shows a gold-dependent Mansa Musa line. Returns false during a dilemma.
func show_mansa_line() -> bool:
	if _dilemma_active():
		return false
	var line := pick_mansa_line(GameData.gold)
	show_toast("Mansa Musa: \"%s\"" % line, MANSA_COLOR)
	_since_mansa_line = 0.0
	_mansa_time_left = mansa_interval
	_tier_line_pending = false
	return true

func get_gold_tier(gold: int) -> String:
	if gold >= WEALTHY_GOLD:
		return "wealthy"
	if gold < POOR_GOLD:
		return "poor"
	return "steady"

func pick_mansa_line(gold: int) -> String:
	var lines: Array = MANSA_LINES[get_gold_tier(gold)]
	var choices := lines.filter(func(l): return l != _last_line)
	_last_line = choices.pick_random()
	return _last_line

func _on_gold_changed(value: int) -> void:
	var tier := get_gold_tier(value)
	if tier != _tier:
		_tier = tier
		_tier_line_pending = true

func _dilemma_active() -> bool:
	var dm := get_node_or_null("/root/DilemmaManager")
	return dm != null and dm.has_method("is_active") and dm.is_active()
