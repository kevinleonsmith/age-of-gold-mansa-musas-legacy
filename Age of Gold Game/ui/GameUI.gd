extends CanvasLayer

# Unit training buttons live in ui/UnitMenu (left edge).

const ANNOUNCEMENT_HOLD := 1.5
const ANNOUNCEMENT_FADE := 1.0

var _announcement_tween: Tween
var _refresh_queued := false

func _ready() -> void:
	GameData.gold_changed.connect(_on_gold_changed)
	GameData.salt_changed.connect(_on_salt_changed)
	GameData.manuscripts_changed.connect(_on_manuscripts_changed)
	GameData.ingots_changed.connect(_on_ingots_changed)
	GameData.modifiers_changed.connect(_queue_refresh.unbind(2))
	# Age requirements depend on buildings and gold mines coming and going.
	get_tree().node_added.connect(_on_tree_node_changed)
	get_tree().node_removed.connect(_on_tree_node_changed)
	AgeManager.age_changed.connect(_on_age_changed)
	%AdvanceAgeButton.pressed.connect(_on_AdvanceAgeButton_pressed)
	%AgeAnnouncement.hide()
	_on_gold_changed(GameData.gold)
	_on_salt_changed(GameData.salt)
	_on_manuscripts_changed(GameData.manuscripts)
	_on_ingots_changed(GameData.ingots)
	_update_age_label()
	# The player may be added (or become ready) after this UI, so look it up
	# once the current frame's setup has finished.
	_connect_player.call_deferred()

func _on_gold_changed(new_value: int) -> void:
	%GoldLabel.text = "Gold: %d" % new_value
	_refresh_buttons()

func _on_salt_changed(new_value: int) -> void:
	%SaltLabel.text = "Salt: %d" % new_value
	_refresh_buttons()

func _on_manuscripts_changed(new_value: int) -> void:
	%ManuscriptsLabel.text = "Manuscripts: %d" % new_value
	_refresh_buttons()

func _on_ingots_changed(new_value: int) -> void:
	%IngotsLabel.text = "Ingots: %d" % new_value
	_refresh_buttons()

func _on_tree_node_changed(node: Node) -> void:
	if node is Building or node is ResourceNode:
		_queue_refresh()

func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	_refresh_buttons.call_deferred()

func _on_age_changed(new_age: int) -> void:
	_update_age_label()
	_refresh_buttons()
	_show_announcement("The %s begins!" % AgeManager.get_age_short_name(new_age))

func _update_age_label() -> void:
	%AgeLabel.text = "Age: %s" % AgeManager.get_age_name()

func _refresh_buttons() -> void:
	_refresh_queued = false
	# Advance Age
	var advance: Button = %AdvanceAgeButton
	if AgeManager.is_max_age():
		advance.text = "Final Age reached"
		advance.disabled = true
	else:
		var next_age: int = AgeManager.current_age + 1
		advance.text = "Advance to %s (%s)" % [
			AgeManager.get_age_short_name(next_age),
			GameData.format_cost(AgeManager.get_next_age_cost()),
		]
		var unmet := AgeManager.get_unmet_requirements()
		if unmet.is_empty():
			advance.tooltip_text = "All requirements met."
		else:
			advance.text += " (needs %s%s)" % [unmet[0], "" if unmet.size() == 1 else ", ..."]
			advance.tooltip_text = "Still needed:\n- " + "\n- ".join(unmet)
		advance.disabled = not AgeManager.can_advance()

func _on_AdvanceAgeButton_pressed() -> void:
	AgeManager.advance_age()

func _show_announcement(text: String) -> void:
	var label: Label = %AgeAnnouncement
	if _announcement_tween and _announcement_tween.is_valid():
		_announcement_tween.kill()
	label.text = text
	label.modulate.a = 1.0
	label.show()
	_announcement_tween = create_tween()
	_announcement_tween.tween_interval(ANNOUNCEMENT_HOLD)
	_announcement_tween.tween_property(label, "modulate:a", 0.0, ANNOUNCEMENT_FADE)
	_announcement_tween.tween_callback(label.hide)

func _connect_player() -> void:
	var label: Label = %HealthLabel
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_signal("health_changed"):
		label.get_parent().hide()
		return
	player.health_changed.connect(_on_player_health_changed)
	_on_player_health_changed(player.get("health"), player.get("max_health"))

func _on_player_health_changed(new_health: float, max_health: float) -> void:
	%HealthLabel.text = "HP: %d/%d" % [ceili(new_health), ceili(max_health)]
