# Pause menu (res://ui/PauseMenu.gd)
# P toggles it; Esc closes it while open (Esc is otherwise left to BuildMenu's
# "cancel"). It won't open during a dilemma or after the game is over, and it
# never unpauses the tree while a dilemma is active.
extends CanvasLayer

const MAIN_MENU_SCENE := "res://ui/MainMenu.tscn"
const MenuThemeScript := preload("res://ui/MenuTheme.gd")

const CONTROLS := [
	["WASD / Arrows", "Move the Mansa"],
	["Space", "Attack the nearest enemy"],
	["B", "Build menu"],
	["T", "Tech tree"],
	["E", "Debug: +10 gold"],
	["P", "Pause / resume"],
	["Esc", "Cancel placement / close menu"],
	["1 / 2 / 3", "Choose in a dilemma"],
]

var is_open := false

var resume_button: Button
var restart_button: Button
var menu_button: Button
var progress_title: Label
var progress_label: Label

func _ready() -> void:
	add_to_group("pause_menu")
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	VictoryManager.game_won.connect(_on_game_over.unbind(3))
	VictoryManager.game_lost.connect(_on_game_over.unbind(3))
	var dm := get_node_or_null("/root/DilemmaManager")
	if dm != null:
		dm.dilemma_started.connect(_on_dilemma_started.unbind(1))

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuThemeScript.get_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.03, 0.1, 0.65)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var heading := MenuThemeScript.label("Paused", 36, MenuThemeScript.GOLD, 8)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)
	vbox.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	vbox.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	resume_button = _button(left, "Resume")
	resume_button.pressed.connect(close)
	restart_button = _button(left, "Restart")
	restart_button.pressed.connect(restart)
	menu_button = _button(left, "Main Menu")
	menu_button.pressed.connect(go_to_main_menu)

	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(300, 0)
	middle.add_theme_constant_override("separation", 6)
	columns.add_child(middle)
	progress_title = MenuThemeScript.label("Victory progress", 18, MenuThemeScript.GOLD)
	middle.add_child(progress_title)
	progress_label = MenuThemeScript.label("", 15)
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.custom_minimum_size = Vector2(300, 0)
	middle.add_child(progress_label)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	columns.add_child(right)
	right.add_child(MenuThemeScript.label("Controls", 18, MenuThemeScript.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	right.add_child(grid)
	for entry in CONTROLS:
		grid.add_child(MenuThemeScript.label(entry[0], 14, MenuThemeScript.GOLD))
		grid.add_child(MenuThemeScript.label(entry[1], 14))

func _button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 19)
	parent.add_child(button)
	return button

func can_open() -> bool:
	if VictoryManager.is_game_over:
		return false
	var dm := get_node_or_null("/root/DilemmaManager")
	return dm == null or not dm.is_active()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if is_open or not can_open():
		return
	is_open = true
	refresh()
	visible = true
	get_tree().paused = true
	_focus_resume.call_deferred()

func _focus_resume() -> void:
	if is_open and resume_button.is_inside_tree() and resume_button.is_visible_in_tree():
		resume_button.grab_focus()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	# A dilemma keeps the game paused until it is resolved; so does game over.
	var dm := get_node_or_null("/root/DilemmaManager")
	var dilemma_active: bool = dm != null and dm.is_active()
	if not dilemma_active and not VictoryManager.is_game_over:
		get_tree().paused = false

func refresh() -> void:
	progress_label.text = describe_progress()
	progress_title.text = "Victory progress" if VictoryManager.skirmish_conditions_enabled else "Objectives"

# Skirmish: the three victory conditions; missions: the objective list.
static func describe_progress() -> String:
	var lines: PackedStringArray = []
	if VictoryManager.skirmish_conditions_enabled:
		var progress: Dictionary = VictoryManager.get_progress()
		for id in ["economic", "cultural", "military"]:
			var entry: Dictionary = progress[id]
			lines.append("%s (%d%%)\n    %s" % [entry["name"], int(round(entry["fraction"] * 100.0)), entry["detail"]])
	else:
		for objective in VictoryManager.objectives:
			var mark := "✓" if objective["done"] else "•"
			var optional := " (optional)" if objective.get("optional", false) else ""
			lines.append("%s %s%s" % [mark, objective.get("text", ""), optional])
		if lines.is_empty():
			lines.append("No objectives.")
	return "\n".join(lines)

func restart() -> void:
	_hide()
	var scene := get_tree().current_scene
	GameSession.start(scene.scene_file_path if scene != null else "res://main.tscn")

func go_to_main_menu() -> void:
	_hide()
	GameSession.start(MAIN_MENU_SCENE)

func _hide() -> void:
	is_open = false
	visible = false

func _on_game_over() -> void:
	# The end screen takes over; the tree stays paused.
	_hide()

func _on_dilemma_started() -> void:
	# The dilemma dialog takes over; it unpauses the tree when resolved.
	_hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if is_open or can_open():
			toggle()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Esc only closes the menu while it is open; otherwise BuildMenu gets it.
	if is_open and event.is_action_pressed("cancel") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()
