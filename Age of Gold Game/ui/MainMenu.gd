# Main menu and campaign mission select (res://ui/MainMenu.gd)
# Title art, Skirmish / Campaign / Quit. The campaign panel lists the missions
# from MissionRegistry with their lock / completed state, description and
# historical note. Everything except the background is built in code.
extends Control

const SKIRMISH_SCENE := "res://main.tscn"
const MissionRegistryScript := preload("res://missions/MissionRegistry.gd")
const MenuThemeScript := preload("res://ui/MenuTheme.gd")

var skirmish_button: Button
var campaign_button: Button
var modes_button: Button
var mode_select: Control
var quit_button: Button
var main_panel: Control
var campaign_panel: Control
var play_button: Button
var back_button: Button
var mission_buttons := {}
var selected_mission := ""

var _mission_title: Label
var _mission_chapter: Label
var _mission_status: Label
var _mission_description: Label
var _mission_note: Label

func _ready() -> void:
	theme = MenuThemeScript.get_theme()
	get_tree().paused = false
	_build_title()
	_build_main_panel()
	_build_campaign_panel()
	show_main()
	AudioManager.play_music("menu")

func _build_title() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -560
	box.offset_right = 560
	box.offset_top = 34
	box.offset_bottom = 170
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var title := MenuThemeScript.label("Age of Gold: Mansa Musa's Legacy", 50, MenuThemeScript.GOLD, 12)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.06, 0.02))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 4)
	box.add_child(title)
	var subtitle := MenuThemeScript.label("The Mali Empire, 14th century: rule with gold, salt and scholarship", 20, MenuThemeScript.SAND, 6)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

func _build_main_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "MainPanel"
	panel.add_theme_stylebox_override("panel", MenuThemeScript.panel_box(0.82))
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(836, 214)
	panel.custom_minimum_size = Vector2(260, 0)
	add_child(panel)
	main_panel = panel
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/menu/emblem.png")
	emblem.custom_minimum_size = Vector2(64, 64)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(emblem)
	skirmish_button = _menu_button(vbox, "Skirmish", "Free play on the Mali plains: win by gold, culture or conquest.")
	skirmish_button.name = "SkirmishButton"
	skirmish_button.pressed.connect(_on_skirmish_pressed)
	campaign_button = _menu_button(vbox, "Campaign", "Historical missions from the rise of Mali to the 1324 Hajj.")
	campaign_button.name = "CampaignButton"
	campaign_button.pressed.connect(show_campaign)
	modes_button = _menu_button(vbox, "Game Modes", "Trans-Saharan Showdown and Scholars of Sankore against AI rival empires.")
	modes_button.name = "GameModesButton"
	modes_button.pressed.connect(show_modes)
	quit_button = _menu_button(vbox, "Quit", "Leave the court of the Mansa.")
	quit_button.name = "QuitButton"
	quit_button.pressed.connect(func() -> void: get_tree().quit())

func _menu_button(parent: Control, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0, 50)
	button.add_theme_font_size_override("font_size", 22)
	parent.add_child(button)
	return button

func _build_campaign_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "CampaignPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(126, 160)
	panel.custom_minimum_size = Vector2(900, 440)
	panel.size = Vector2(900, 440)
	add_child(panel)
	campaign_panel = panel
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	panel.add_child(root_box)
	var header := MenuThemeScript.label("Campaign: The Legacy of Mansa Musa", 26, MenuThemeScript.GOLD, 4)
	root_box.add_child(header)
	root_box.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(columns)

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(300, 0)
	list.add_theme_constant_override("separation", 8)
	columns.add_child(list)
	for mission in MissionRegistryScript.get_missions():
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 56)
		button.toggle_mode = true
		button.pressed.connect(select_mission.bind(mission["id"]))
		list.add_child(button)
		mission_buttons[mission["id"]] = button

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	columns.add_child(details)
	_mission_chapter = MenuThemeScript.label("", 15, MenuThemeScript.MUTED)
	details.add_child(_mission_chapter)
	_mission_title = MenuThemeScript.label("", 24, MenuThemeScript.GOLD, 3)
	details.add_child(_mission_title)
	_mission_status = MenuThemeScript.label("", 15)
	details.add_child(_mission_status)
	_mission_description = MenuThemeScript.label("", 17)
	_mission_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_description.custom_minimum_size = Vector2(520, 0)
	details.add_child(_mission_description)
	var note_box := PanelContainer.new()
	note_box.add_theme_stylebox_override("panel", MenuThemeScript.box(Color(0.3, 0.13, 0.07, 0.8), Color(0.45, 0.25, 0.12), 1, 4, 10.0))
	details.add_child(note_box)
	_mission_note = MenuThemeScript.label("", 15, Color(0.93, 0.84, 0.68))
	_mission_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_box.add_child(_mission_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	root_box.add_child(buttons)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(120, 44)
	back_button.pressed.connect(show_main)
	buttons.add_child(back_button)
	play_button = Button.new()
	play_button.text = "Play Mission"
	play_button.custom_minimum_size = Vector2(180, 44)
	play_button.add_theme_font_size_override("font_size", 20)
	play_button.pressed.connect(_on_play_pressed)
	buttons.add_child(play_button)

func show_main() -> void:
	main_panel.visible = true
	campaign_panel.visible = false
	if mode_select != null:
		mode_select.visible = false

# Opens the game-mode picker (ui/ModeSelect.tscn), created on first use.
func show_modes() -> void:
	if mode_select == null:
		mode_select = (load("res://ui/ModeSelect.tscn") as PackedScene).instantiate()
		add_child(mode_select)
		mode_select.closed.connect(show_main)
	main_panel.visible = false
	campaign_panel.visible = false
	mode_select.open()

func show_campaign() -> void:
	main_panel.visible = false
	campaign_panel.visible = true
	refresh_campaign()
	# Select the furthest unlocked, playable mission.
	var pick := ""
	for mission in MissionRegistryScript.get_missions():
		if MissionRegistryScript.is_unlocked(mission["id"]) and MissionRegistryScript.is_available(mission["id"]):
			pick = mission["id"]
	if pick == "":
		pick = MissionRegistryScript.get_missions()[0]["id"]
	select_mission(pick)

# Status of a mission: "completed", "locked", "coming_soon" or "ready".
func mission_state(id: String) -> String:
	if not MissionRegistryScript.is_available(id):
		return "coming_soon"
	if not MissionRegistryScript.is_unlocked(id):
		return "locked"
	if MissionRegistryScript.is_completed(id):
		return "completed"
	return "ready"

func refresh_campaign() -> void:
	var index := 0
	for mission in MissionRegistryScript.get_missions():
		index += 1
		var button: Button = mission_buttons[mission["id"]]
		var state := mission_state(mission["id"])
		var suffix := ""
		match state:
			"completed":
				suffix = "   ✓ Completed"
			"locked":
				suffix = "   (Locked)"
			"coming_soon":
				suffix = "   (Coming soon)"
		button.text = "%d. %s\n%s" % [index, mission["title"], suffix.strip_edges()] if suffix != "" else "%d. %s" % [index, mission["title"]]
		button.add_theme_color_override("font_color", MenuThemeScript.GOOD if state == "completed" else (MenuThemeScript.MUTED if state != "ready" else MenuThemeScript.SAND))
		button.button_pressed = mission["id"] == selected_mission

func select_mission(id: String) -> void:
	selected_mission = id
	var mission: Dictionary = MissionRegistryScript.get_mission(id)
	if mission.is_empty():
		return
	var state := mission_state(id)
	_mission_chapter.text = mission["chapter"]
	_mission_title.text = mission["title"]
	_mission_description.text = mission["description"]
	_mission_note.text = "Historical note: " + mission["historical_note"]
	match state:
		"completed":
			_mission_status.text = "✓ Completed. Play again any time."
			_mission_status.add_theme_color_override("font_color", MenuThemeScript.GOOD)
		"locked":
			_mission_status.text = "Locked: win the previous mission to unlock it."
			_mission_status.add_theme_color_override("font_color", MenuThemeScript.BAD)
		"coming_soon":
			_mission_status.text = "Coming soon"
			_mission_status.add_theme_color_override("font_color", MenuThemeScript.MUTED)
		_:
			_mission_status.text = "Unlocked"
			_mission_status.add_theme_color_override("font_color", MenuThemeScript.GOLD)
	play_button.disabled = state == "locked" or state == "coming_soon"
	refresh_campaign()

func _on_skirmish_pressed() -> void:
	AudioManager.play_sfx("click")
	GameSession.start(SKIRMISH_SCENE)

func _on_play_pressed() -> void:
	var mission: Dictionary = MissionRegistryScript.get_mission(selected_mission)
	if mission.is_empty() or play_button.disabled:
		return
	AudioManager.play_sfx("click")
	GameSession.start(mission["scene"])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and campaign_panel.visible:
		show_main()
		get_viewport().set_input_as_handled()
