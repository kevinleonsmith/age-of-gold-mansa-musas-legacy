# Game-mode picker (res://ui/ModeSelect.gd)
# Classic skirmish, Trans-Saharan Showdown and Scholars of Sankore (the design
# doc's "Multiplayer Modes", played against AI rival empires), plus the AI
# difficulty. The difficulty is stored in AISettings (a static var) because
# GameSession.start() resets every autoload.
extends Control

signal closed

const MenuThemeScript := preload("res://ui/MenuTheme.gd")
const AISettingsScript := preload("res://ai/AISettings.gd")

const MODES := [
	{
		"id": "skirmish",
		"title": "Classic Skirmish",
		"scene": "res://main.tscn",
		"description": "Free play against the Songhai of Gao. Win by Economic Domination, Cultural Victory or Military Conquest.",
		"uses_difficulty": false,
	},
	{
		"id": "showdown",
		"title": "Trans-Saharan Showdown",
		"scene": "res://modes/Showdown.tscn",
		"description": "Three rival empires race you for the gold and salt nodes of the Sahel. Hold 60% of the nodes for 90 seconds, or burn every rival camp. Sandstorms sweep the map; only camel riders keep moving.",
		"uses_difficulty": true,
	},
	{
		"id": "scholars",
		"title": "Scholars of Sankore",
		"scene": "res://modes/Scholars.tscn",
		"description": "A race of learning: the first power to complete five manuscript techs wins. Research with manuscripts, commission scholarly treatises at your mosques, and defend them from raiders.",
		"uses_difficulty": true,
	},
]

var mode_buttons := {}
var difficulty_buttons := {}
var selected_mode := "showdown"
var play_button: Button
var back_button: Button
var _title: Label
var _description: Label
var _difficulty_row: Control

func _ready() -> void:
	theme = MenuThemeScript.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false

func _build() -> void:
	var panel := PanelContainer.new()
	panel.name = "ModePanel"
	panel.add_theme_stylebox_override("panel", MenuThemeScript.panel_box(0.94))
	panel.position = Vector2(176, 150)
	panel.custom_minimum_size = Vector2(800, 400)
	add_child(panel)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	panel.add_child(root_box)
	root_box.add_child(MenuThemeScript.label("Game Modes", 26, MenuThemeScript.GOLD, 4))
	root_box.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(columns)

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(260, 0)
	list.add_theme_constant_override("separation", 8)
	columns.add_child(list)
	for mode in MODES:
		var button := Button.new()
		button.name = "Mode_" + mode["id"]
		button.text = mode["title"]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 48)
		button.add_theme_font_size_override("font_size", 19)
		button.pressed.connect(select_mode.bind(mode["id"]))
		list.add_child(button)
		mode_buttons[mode["id"]] = button

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	columns.add_child(detail)
	_title = MenuThemeScript.label("", 24, MenuThemeScript.GOLD, 3)
	detail.add_child(_title)
	_description = MenuThemeScript.label("", 17)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(460, 0)
	detail.add_child(_description)

	var diff_box := HBoxContainer.new()
	diff_box.add_theme_constant_override("separation", 8)
	diff_box.add_child(MenuThemeScript.label("AI difficulty:", 17, MenuThemeScript.SAND))
	var group := ButtonGroup.new()
	for level in AISettingsScript.DIFFICULTIES:
		var button := Button.new()
		button.name = "Difficulty_" + level
		button.text = level.capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(90, 38)
		button.pressed.connect(set_difficulty.bind(level))
		diff_box.add_child(button)
		difficulty_buttons[level] = button
	detail.add_child(diff_box)
	_difficulty_row = diff_box

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	root_box.add_child(buttons)
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(140, 44)
	back_button.pressed.connect(close)
	buttons.add_child(back_button)
	play_button = Button.new()
	play_button.name = "PlayButton"
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(180, 44)
	play_button.add_theme_font_size_override("font_size", 20)
	play_button.pressed.connect(launch)
	buttons.add_child(play_button)

func open() -> void:
	visible = true
	set_difficulty(AISettingsScript.normalized(AISettingsScript.difficulty))
	select_mode(selected_mode)

func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func get_mode(id: String) -> Dictionary:
	for mode in MODES:
		if mode["id"] == id:
			return mode
	return {}

func select_mode(id: String) -> void:
	var mode := get_mode(id)
	if mode.is_empty():
		return
	selected_mode = id
	for key in mode_buttons:
		mode_buttons[key].button_pressed = key == id
	_title.text = mode["title"]
	_description.text = mode["description"]
	_difficulty_row.visible = mode["uses_difficulty"]
	play_button.disabled = not ResourceLoader.exists(mode["scene"])

func set_difficulty(level: String) -> void:
	AISettingsScript.difficulty = AISettingsScript.normalized(level)
	for key in difficulty_buttons:
		difficulty_buttons[key].button_pressed = key == AISettingsScript.difficulty

# Starts the selected mode with a fresh game state.
func launch() -> void:
	var mode := get_mode(selected_mode)
	if mode.is_empty() or play_button.disabled:
		return
	AISettingsScript.last_mode = mode["scene"]
	AudioManager.play_sfx("click")
	GameSession.start(mode["scene"])

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()
