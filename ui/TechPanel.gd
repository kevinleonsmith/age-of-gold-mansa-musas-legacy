# Tech tree panel (res://ui/TechPanel.gd)
# Right-side panel listing techs by age. Toggle with T or the "Tech (T)" button.
extends CanvasLayer

const DONE_COLOR := Color(0.55, 0.9, 0.55)
const LOCKED_COLOR := Color(0.6, 0.6, 0.6)

@onready var toggle_button: Button = %ToggleButton
@onready var panel: PanelContainer = %Panel
@onready var current_label: Label = %CurrentLabel
@onready var cancel_button: Button = %CancelButton
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var list: VBoxContainer = %List

# tech id -> {"row", "name", "cost", "button"}
var rows := {}
var _refresh_queued := false

func _ready() -> void:
	toggle_button.pressed.connect(toggle)
	cancel_button.pressed.connect(func(): TechManager.cancel_research())
	_build_rows()
	GameData.gold_changed.connect(_queue_refresh.unbind(1))
	GameData.salt_changed.connect(_queue_refresh.unbind(1))
	GameData.manuscripts_changed.connect(_queue_refresh.unbind(1))
	GameData.ingots_changed.connect(_queue_refresh.unbind(1))
	GameData.modifiers_changed.connect(_queue_refresh.unbind(2))
	AgeManager.age_changed.connect(_queue_refresh.unbind(1))
	TechManager.research_started.connect(_queue_refresh.unbind(1))
	TechManager.tech_researched.connect(_queue_refresh.unbind(1))
	TechManager.research_progress.connect(_on_research_progress)
	if TechManager.has_signal("research_cancelled"):
		TechManager.research_cancelled.connect(_queue_refresh.unbind(1))
	refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_tech") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		refresh()

func is_open() -> bool:
	return panel.visible

func _build_rows() -> void:
	var last_age := -1
	for tech in TechManager.get_all_techs():
		if tech["age"] != last_age:
			last_age = tech["age"]
			var header := Label.new()
			header.text = "Age %s: %s" % [["I", "II", "III"][last_age], AgeManager.get_age_short_name(last_age)]
			header.add_theme_color_override("font_color", Color(1, 0.84, 0.3))
			header.mouse_filter = Control.MOUSE_FILTER_IGNORE
			list.add_child(header)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.tooltip_text = tech["description"]
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_theme_constant_override("separation", 0)
		var name_label := Label.new()
		name_label.text = tech["name"]
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cost_label := Label.new()
		cost_label.add_theme_font_size_override("font_size", 10)
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(name_label)
		info.add_child(cost_label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(76, 0)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = tech["description"]
		var id: String = tech["id"]
		button.pressed.connect(func(): TechManager.start_research(id))
		row.add_child(info)
		row.add_child(button)
		list.add_child(row)
		rows[id] = {"row": row, "name": name_label, "cost": cost_label, "button": button}

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	refresh.call_deferred()

func refresh() -> void:
	_refresh_queued = false
	var current := TechManager.get_current_research()
	for id in rows:
		var r: Dictionary = rows[id]
		var tech := TechManager.get_tech(id)
		var button: Button = r["button"]
		var cost_label: Label = r["cost"]
		var unlocked := AgeManager.is_unlocked(tech["age"])
		cost_label.text = "%s · %ds" % [GameData.format_cost(tech["cost"]), roundi(TechManager.get_research_time(id))]
		if TechManager.is_researched(id):
			button.text = "✓"
			button.disabled = true
			r["row"].modulate = DONE_COLOR
		elif id == current:
			button.text = "…"
			button.disabled = true
			r["row"].modulate = Color.WHITE
		elif not unlocked:
			button.text = "Locked"
			button.disabled = true
			r["row"].modulate = LOCKED_COLOR
		else:
			button.text = "Research"
			button.disabled = not TechManager.can_research(id)
			r["row"].modulate = Color.WHITE if GameData.can_afford(tech["cost"]) else LOCKED_COLOR
	_update_current()

func _update_current() -> void:
	var current := TechManager.get_current_research()
	if current == "":
		current_label.text = "No research"
		progress_bar.value = 0.0
		cancel_button.disabled = true
	else:
		current_label.text = "Researching: %s" % TechManager.get_tech(current)["name"]
		progress_bar.value = TechManager.get_progress()
		cancel_button.disabled = false

func _on_research_progress(_id: String, _progress: float) -> void:
	if panel.visible:
		_update_current()
