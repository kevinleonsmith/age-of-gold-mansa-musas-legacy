# Objectives HUD (res://ui/ObjectivesHUD.gd)
# Compact box on the right edge below the EconomyPanel. Missions: the objective
# list from VictoryManager with ✓ marks. Skirmish: a progress bar per victory
# condition. The small button collapses it to the header.
extends CanvasLayer

const MenuThemeScript := preload("res://ui/MenuTheme.gd")
const WIDTH := 230.0
const TOP := 240.0
const CONDITIONS := ["economic", "cultural", "military"]

var collapsed := false
var panel: PanelContainer
var header_label: Label
var collapse_button: Button
var content: VBoxContainer
# Skirmish widgets per condition id: {"label": Label, "bar": ProgressBar}.
var bars := {}
# Mission objective labels, in order.
var objective_labels: Array = []

var _mode := ""

func _ready() -> void:
	add_to_group("objectives_hud")
	layer = 4
	_build()
	VictoryManager.objectives_changed.connect(refresh)
	VictoryManager.progress_changed.connect(_on_progress_changed)
	refresh()

func _build() -> void:
	panel = PanelContainer.new()
	panel.theme = MenuThemeScript.get_theme()
	panel.add_theme_stylebox_override("panel", MenuThemeScript.box(Color(MenuThemeScript.INDIGO, 0.78), MenuThemeScript.GOLD_DARK, 1, 5, 7.0))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -WIDTH - 10.0
	panel.offset_right = -10.0
	panel.offset_top = TOP
	panel.offset_bottom = TOP + 40.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)
	header_label = MenuThemeScript.label("Objectives", 15, MenuThemeScript.GOLD)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_label)
	collapse_button = Button.new()
	collapse_button.text = "–"
	collapse_button.tooltip_text = "Collapse / expand"
	collapse_button.focus_mode = Control.FOCUS_NONE
	collapse_button.custom_minimum_size = Vector2(24, 20)
	collapse_button.add_theme_font_size_override("font_size", 13)
	for state in ["normal", "hover", "pressed"]:
		var style := MenuThemeScript.box(MenuThemeScript.LATERITE if state != "hover" else MenuThemeScript.LATERITE_LIGHT, MenuThemeScript.GOLD_DARK, 1, 3, 1.0)
		style.content_margin_left = 6
		style.content_margin_right = 6
		collapse_button.add_theme_stylebox_override(state, style)
	collapse_button.pressed.connect(toggle_collapsed)
	header.add_child(collapse_button)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(content)

func toggle_collapsed() -> void:
	set_collapsed(not collapsed)

func set_collapsed(value: bool) -> void:
	collapsed = value
	content.visible = not collapsed
	collapse_button.text = "+" if collapsed else "–"
	_shrink()

# Rebuilds the list (objectives changed, or skirmish/mission mode switched).
func refresh() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	bars.clear()
	objective_labels.clear()
	if VictoryManager.skirmish_conditions_enabled:
		_mode = "skirmish"
		header_label.text = "Victory Progress"
		for id in CONDITIONS:
			var l := MenuThemeScript.label("", 13)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(WIDTH - 16.0, 0)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(l)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(0, 8)
			bar.max_value = 1.0
			bar.step = 0.001
			bar.show_percentage = false
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(bar)
			bars[id] = {"label": l, "bar": bar}
		_update_bars()
	else:
		_mode = "mission"
		header_label.text = "Objectives"
		for objective in VictoryManager.objectives:
			var done: bool = objective.get("done", false)
			var text := "%s %s" % ["✓" if done else "•", objective.get("text", "")]
			if objective.get("optional", false):
				text += " (optional)"
			var l := MenuThemeScript.label(text, 13, MenuThemeScript.GOOD if done else MenuThemeScript.SAND)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(WIDTH - 16.0, 0)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(l)
			objective_labels.append(l)
		if objective_labels.is_empty():
			var none := MenuThemeScript.label("No objectives.", 13, MenuThemeScript.MUTED)
			content.add_child(none)
	content.visible = not collapsed
	_shrink()

func _on_progress_changed() -> void:
	var want := "skirmish" if VictoryManager.skirmish_conditions_enabled else "mission"
	if want != _mode:
		refresh()
	elif _mode == "skirmish":
		_update_bars()

func _update_bars() -> void:
	var progress: Dictionary = VictoryManager.get_progress()
	for id in bars:
		var entry: Dictionary = progress[id]
		bars[id]["label"].text = "%s: %s" % [entry["name"].get_slice(" ", 0), entry["detail"]]
		bars[id]["bar"].value = entry["fraction"]

# Lets the panel shrink back to its content height.
func _shrink() -> void:
	panel.offset_bottom = TOP + 40.0
	panel.reset_size.call_deferred()
