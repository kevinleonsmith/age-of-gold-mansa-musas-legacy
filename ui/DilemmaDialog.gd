# Dilemma dialog (res://ui/DilemmaDialog.gd)
# Centered modal for DilemmaManager events. Opens on dilemma_started and pauses
# the game; a choice (button or keys 1/2/3) unpauses, then the speaker's response
# shows for RESPONSE_TIME seconds (or until clicked) before the dialog closes.
extends CanvasLayer

enum State { HIDDEN, CHOOSING, RESPONDING }

const RESPONSE_TIME := 2.5
const DISABLED_COLOR := Color(1.0, 0.6, 0.5)

var state := State.HIDDEN
var _close_token := 0

@onready var _portrait: Panel = %Portrait
@onready var _initial: Label = %Initial
@onready var _title: Label = %Title
@onready var _speaker: Label = %Speaker
@onready var _line: Label = %Line
@onready var _options: VBoxContainer = %Options
@onready var _response: Label = %Response
@onready var _hint: Label = %Hint

func _ready() -> void:
	add_to_group("dilemma_dialog")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	for i in _options.get_child_count():
		(_options.get_child(i) as Button).pressed.connect(_on_option_pressed.bind(i))
	var dm := _dm()
	if dm != null:
		dm.dilemma_started.connect(_on_dilemma_started)
		dm.dilemma_resolved.connect(_on_dilemma_resolved)
		if dm.has_signal("dilemma_response"):
			dm.dilemma_response.connect(_on_dilemma_response)
	GameData.gold_changed.connect(_on_resources_changed)
	GameData.salt_changed.connect(_on_resources_changed)
	GameData.manuscripts_changed.connect(_on_resources_changed)
	GameData.ingots_changed.connect(_on_resources_changed)

func get_option_button(index: int) -> Button:
	return _options.get_child(index) as Button

func _dm() -> Node:
	return get_node_or_null("/root/DilemmaManager")

func _on_dilemma_started(_id: String) -> void:
	_close_token += 1
	var data: Dictionary = _dm().get_active()
	var color: Color = data.get("color", Color(0.5, 0.4, 0.3))
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(32)
	_portrait.add_theme_stylebox_override("panel", style)
	var speaker: String = data.get("speaker", "")
	_initial.text = speaker.left(1).to_upper()
	_title.text = data.get("title", "Dilemma")
	_speaker.text = speaker
	_line.text = "\"%s\"" % data.get("line", "")
	_refresh_options()
	_options.visible = true
	_hint.text = "Press 1, 2 or 3 to choose"
	_response.visible = false
	state = State.CHOOSING
	visible = true
	get_tree().paused = true

func _refresh_options() -> void:
	var dm := _dm()
	if dm == null or not dm.is_active():
		return
	var options: Array = dm.get_active().get("options", [])
	for i in _options.get_child_count():
		var button := get_option_button(i)
		if i >= options.size():
			button.visible = false
			continue
		var opt: Dictionary = options[i]
		button.visible = true
		var text := "%d. %s (%s)\nCost: %s  |  %s" % [i + 1, opt.label, opt.tag, opt.cost_text, opt.summary]
		if not opt.available:
			text += "\nUnavailable: %s" % opt.reason
		button.text = text
		button.disabled = not opt.available
		button.tooltip_text = opt.reason
		button.add_theme_color_override("font_disabled_color", DISABLED_COLOR)

func _on_resources_changed(_value: int) -> void:
	if state == State.CHOOSING:
		_refresh_options()

func _on_option_pressed(index: int) -> void:
	if state != State.CHOOSING:
		return
	if not _dm().choose(index):
		_refresh_options()

func _on_dilemma_resolved(_id: String, _option: int) -> void:
	get_tree().paused = false

func _on_dilemma_response(_id: String, speaker: String, text: String) -> void:
	state = State.RESPONDING
	_options.visible = false
	_response.text = "%s: \"%s\"" % [speaker, text]
	_response.visible = true
	_hint.text = "Click to continue"
	_close_token += 1
	var token := _close_token
	await get_tree().create_timer(RESPONSE_TIME, true).timeout
	if token == _close_token and state == State.RESPONDING:
		close()

func close() -> void:
	_close_token += 1
	state = State.HIDDEN
	visible = false

func _input(event: InputEvent) -> void:
	if state == State.HIDDEN:
		return
	if state == State.CHOOSING and event is InputEventKey and event.pressed and not event.echo:
		var index := _key_index(event as InputEventKey)
		if index >= 0:
			get_viewport().set_input_as_handled()
			_on_option_pressed(index)
	elif state == State.RESPONDING:
		if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
			get_viewport().set_input_as_handled()
			close()

func _key_index(event: InputEventKey) -> int:
	for key in [event.keycode, event.physical_keycode]:
		match key:
			KEY_1, KEY_KP_1:
				return 0
			KEY_2, KEY_KP_2:
				return 1
			KEY_3, KEY_KP_3:
				return 2
	return -1
