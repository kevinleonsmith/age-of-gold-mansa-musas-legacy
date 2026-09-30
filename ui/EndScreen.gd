# Victory / defeat overlay (res://ui/EndScreen.gd)
# Opens on VictoryManager.game_won / game_lost with the result, session stats and
# Retry / Main Menu / Next Mission buttons. A win in a campaign mission (a scene
# listed in MissionRegistry) is saved as completed, unlocking the next mission.
extends CanvasLayer

const MAIN_MENU_SCENE := "res://ui/MainMenu.tscn"
const MissionRegistryScript := preload("res://missions/MissionRegistry.gd")
const MenuThemeScript := preload("res://ui/MenuTheme.gd")

var is_open := false
var won := false
# The campaign mission being played ({} in skirmish) and the one after it.
var mission := {}
var next_mission := {}
var scene_path := ""

var retry_button: Button
var menu_button: Button
var next_button: Button
var heading_label: Label
var title_label: Label
var text_label: Label
var stats_label: Label
var campaign_label: Label

var _dim: ColorRect
var _panel: PanelContainer
var _emblem: TextureRect

func _ready() -> void:
	add_to_group("end_screen")
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	VictoryManager.game_won.connect(_on_game_won)
	VictoryManager.game_lost.connect(_on_game_lost)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuThemeScript.get_theme()
	add_child(root)
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_emblem = TextureRect.new()
	_emblem.texture = load("res://assets/menu/emblem.png")
	_emblem.custom_minimum_size = Vector2(72, 72)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(_emblem)
	heading_label = MenuThemeScript.label("VICTORY", 44, MenuThemeScript.GOLD, 10)
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading_label)
	title_label = MenuThemeScript.label("", 24, MenuThemeScript.SAND, 4)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	text_label = MenuThemeScript.label("", 16)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(text_label)
	vbox.add_child(HSeparator.new())
	stats_label = MenuThemeScript.label("", 16, MenuThemeScript.SAND)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_label)
	campaign_label = MenuThemeScript.label("", 16, MenuThemeScript.GOOD)
	campaign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	campaign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(campaign_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	vbox.add_child(buttons)
	retry_button = _button(buttons, "Retry")
	retry_button.pressed.connect(retry)
	menu_button = _button(buttons, "Main Menu")
	menu_button.pressed.connect(go_to_main_menu)
	next_button = _button(buttons, "Next Mission")
	next_button.pressed.connect(play_next)

func _button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 46)
	button.add_theme_font_size_override("font_size", 19)
	parent.add_child(button)
	return button

func _on_game_won(condition_id: String, title: String, text: String) -> void:
	open(true, condition_id, title, text)

func _on_game_lost(reason_id: String, title: String, text: String) -> void:
	open(false, reason_id, title, text)

func open(is_win: bool, _id: String, title: String, text: String) -> void:
	won = is_win
	is_open = true
	var scene := get_tree().current_scene
	scene_path = scene.scene_file_path if scene != null else ""
	mission = MissionRegistryScript.find_by_scene(scene_path)
	next_mission = {}
	campaign_label.text = ""
	if won and not mission.is_empty():
		MissionRegistryScript.mark_completed(mission["id"])
		next_mission = MissionRegistryScript.get_next(mission["id"])
		campaign_label.text = "Mission complete: %s" % mission["title"]
		if not next_mission.is_empty():
			if MissionRegistryScript.is_available(next_mission["id"]):
				campaign_label.text += "\nUnlocked: %s" % next_mission["title"]
			else:
				campaign_label.text += "\nNext: %s (coming soon)" % next_mission["title"]
		else:
			campaign_label.text += "\nThe campaign is complete. Mali's legacy endures."
	next_button.visible = won and not next_mission.is_empty() and MissionRegistryScript.is_available(next_mission["id"])
	campaign_label.visible = campaign_label.text != ""

	heading_label.text = "VICTORY" if won else "DEFEAT"
	heading_label.add_theme_color_override("font_color", MenuThemeScript.GOLD if won else MenuThemeScript.BAD)
	heading_label.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.0) if won else Color(0.15, 0.0, 0.0))
	title_label.text = title
	text_label.text = text
	_dim.color = Color(0.12, 0.08, 0.02, 0.72) if won else Color(0.16, 0.02, 0.02, 0.78)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_emblem.modulate = Color.WHITE if won else Color(0.55, 0.45, 0.45)
	stats_label.text = format_stats(VictoryManager.get_session_stats())
	visible = true
	_focus_default.call_deferred()

func _focus_default() -> void:
	var button := next_button if next_button.visible else retry_button
	if is_open and button.is_inside_tree() and button.is_visible_in_tree():
		button.grab_focus()

func _panel_style() -> StyleBoxFlat:
	var style := MenuThemeScript.panel_box(0.96)
	if not won:
		style.bg_color = Color(0.14, 0.05, 0.08, 0.96)
		style.border_color = Color(0.6, 0.2, 0.15)
	return style

static func format_stats(stats: Dictionary) -> String:
	return "Time %s   |   Gold earned %d   |   Buildings %d\nConversions %d   |   Techs researched %d" % [
		MenuThemeScript.format_time(stats.get("time", 0.0)), int(stats.get("gold_earned", 0)),
		int(stats.get("buildings", 0)), int(stats.get("conversions", 0)), int(stats.get("techs", 0))]

func close() -> void:
	is_open = false
	visible = false

func retry() -> void:
	close()
	GameSession.start(scene_path if scene_path != "" else "res://main.tscn")

func go_to_main_menu() -> void:
	close()
	GameSession.start(MAIN_MENU_SCENE)

func play_next() -> void:
	if next_mission.is_empty():
		return
	close()
	GameSession.start(next_mission["scene"])
