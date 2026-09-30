# Scholars of Sankore (res://modes/Scholars.gd)
# Design doc "Multiplayer Modes" 2, single-player: the first side to complete
# 5 manuscript techs wins. Same map style as the Showdown, plus manuscript
# caches, and no random sandstorms.
# Player manuscript techs = researched TechManager techs whose cost includes
#   manuscripts, plus each "Scholarly Treatise" commissioned from the mode
#   panel (3 manuscripts + 60 s, needs at least one mosque), because some
#   manuscript techs need Age III.
# AI empires research abstract manuscript techs with manuscripts from their
#   libraries and held nodes (ai/AIEmpire.gd). Their raiders favour the
#   player's mosques (EnemyAI's 30% mosque priority).
# Win: 5 techs first. Lose: an AI reaches 5, or the Mansa dies.
extends "res://ai/RivalModeBase.gd"

const TARGET_TECHS := 5
const TREATISE_COST := {"manuscripts": 3}
const TREATISE_TIME := 60.0

var treatises_done := 0
var treatise_active := false
var treatise_elapsed := 0.0

var treatise_button: Button
var treatise_label: Label
var treatise_bar: ProgressBar

func _mode_ready() -> void:
	mode_id = "scholars"
	GameData.manuscripts = maxi(GameData.manuscripts, 2)
	set_objectives([
		{"id": "techs", "text": _techs_text()},
		{"id": "treatise", "text": "Commission a Scholarly Treatise (needs a mosque)", "optional": true},
	])
	_build_panel.call_deferred()
	toast("Mansa: The scholars of Songhai, Mossi and the Tuareg race us for knowledge. Five great works, and Sankore's glory is Mali's.")

func _mission_process(delta: float) -> void:
	update_scholars(delta * time_scale)
	if hud_due(delta, 0.25):
		objective_text("techs", _techs_text())
		refresh_panel()

# Advances the treatise by `dt` seconds of game time and checks the outcome.
func update_scholars(dt: float) -> void:
	if finished:
		return
	if treatise_active:
		treatise_elapsed += dt
		if treatise_elapsed >= TREATISE_TIME:
			_finish_treatise()
	check_outcome()

# --- Tech counts ------------------------------------------------------------------

static func is_manuscript_tech(tech: Dictionary) -> bool:
	return (tech.get("cost", {}) as Dictionary).has("manuscripts")

func researched_manuscript_techs() -> int:
	var n := 0
	for tech in TechManager.get_all_techs():
		if is_manuscript_tech(tech) and TechManager.is_researched(tech["id"]):
			n += 1
	return n

func player_manuscript_techs() -> int:
	return researched_manuscript_techs() + treatises_done

func check_outcome() -> void:
	if finished:
		return
	if player_manuscript_techs() >= TARGET_TECHS:
		complete("techs")
		end_victory("scholars", "Light of Sankore",
			"Five great works bear the Mansa's seal. Scholars from Cairo to Fez now travel to Timbuktu, and Mali's legacy is written in ink as well as gold.")
		return
	for e in empires():
		if e.techs_completed >= TARGET_TECHS:
			end_defeat("scholars_lost", "The %s Scholars Prevail" % e.empire_name,
				"The libraries of %s completed five great works first. The learned men of the Sahel now look to the %s, not to Mali." % [e.capital_name, e.empire_name])
			return

# --- Scholarly Treatise ---------------------------------------------------------------

func count_mosques() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("building_mosque"):
		if not b.is_queued_for_deletion() and b.get("is_destroyed") != true:
			n += 1
	return n

# Why a treatise can't be commissioned now ("" if it can).
func treatise_block_reason() -> String:
	if finished:
		return "The contest is over"
	if treatise_active:
		return "A treatise is being written"
	if count_mosques() < 1:
		return "Requires a mosque"
	if not GameData.can_afford(TREATISE_COST):
		return "Needs %s" % GameData.format_cost(TREATISE_COST)
	return ""

func commission_treatise() -> bool:
	if treatise_block_reason() != "" or not GameData.spend(TREATISE_COST):
		AudioManager.play_sfx("error")
		refresh_panel()
		return false
	treatise_active = true
	treatise_elapsed = 0.0
	AudioManager.play_sfx("click")
	toast("The scholars of the mosque begin a new treatise.", COLOR_STORY)
	refresh_panel()
	return true

func _finish_treatise() -> void:
	treatise_active = false
	treatise_elapsed = 0.0
	treatises_done += 1
	complete("treatise")
	AudioManager.play_sfx("research_done")
	toast("A Scholarly Treatise is complete (%d/%d manuscript techs)." % [player_manuscript_techs(), TARGET_TECHS], COLOR_GOOD)
	refresh_panel()

# --- Panel (in the scoreboard footer) ------------------------------------------------

func _build_panel() -> void:
	var board := get_tree().get_first_node_in_group("scoreboard")
	if board == null or not board.has_method("add_footer") or treatise_button != null:
		return
	var box := VBoxContainer.new()
	box.name = "TreatisePanel"
	box.add_theme_constant_override("separation", 2)
	treatise_button = Button.new()
	treatise_button.name = "TreatiseButton"
	treatise_button.text = "Commission a Scholarly Treatise"
	treatise_button.tooltip_text = "3 Manuscripts + 60 s, needs a mosque. Counts as one manuscript tech."
	treatise_button.focus_mode = Control.FOCUS_NONE
	treatise_button.add_theme_font_size_override("font_size", 13)
	treatise_button.custom_minimum_size = Vector2(0, 26)
	treatise_button.pressed.connect(commission_treatise)
	box.add_child(treatise_button)
	var row := HBoxContainer.new()
	treatise_bar = ProgressBar.new()
	treatise_bar.custom_minimum_size = Vector2(90, 10)
	treatise_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	treatise_bar.show_percentage = false
	treatise_bar.max_value = 1.0
	treatise_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(treatise_bar)
	treatise_label = Label.new()
	treatise_label.add_theme_font_size_override("font_size", 12)
	treatise_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(treatise_label)
	box.add_child(row)
	board.add_footer(box)
	refresh_panel()

func refresh_panel() -> void:
	if treatise_button == null:
		return
	var reason := treatise_block_reason()
	treatise_button.disabled = reason != ""
	treatise_bar.value = treatise_elapsed / TREATISE_TIME if treatise_active else 0.0
	if treatise_active:
		treatise_label.text = "Writing... %s left" % format_clock(TREATISE_TIME - treatise_elapsed)
	elif reason != "":
		treatise_label.text = reason
	else:
		treatise_label.text = "Ready: %s, %ds" % [GameData.format_cost(TREATISE_COST), int(TREATISE_TIME)]

# --- HUD / scoreboard ---------------------------------------------------------------------

func _techs_text() -> String:
	return "Complete %d manuscript techs first: %d/%d (treatises %d)" % [TARGET_TECHS, player_manuscript_techs(), TARGET_TECHS, treatises_done]

func get_scoreboard_title() -> String:
	return "Scholars of Sankore · first to %d manuscript techs" % TARGET_TECHS

func get_scoreboard_rows() -> Array:
	var progress := treatise_elapsed / TREATISE_TIME if treatise_active else 0.0
	var current := TechManager.get_current_research()
	if current != "" and is_manuscript_tech(TechManager.get_tech(current)):
		progress = maxf(progress, TechManager.get_progress())
	var rows := [{
		"name": PLAYER_NAME, "color": PLAYER_COLOR, "techs": player_manuscript_techs(),
		"target": TARGET_TECHS, "progress": progress, "nodes": player_nodes(),
		"score": player_score(), "status": "", "is_player": true,
	}]
	for e in empires():
		rows.append({
			"name": e.empire_name, "color": e.color, "techs": e.techs_completed,
			"target": TARGET_TECHS, "progress": e.research_progress(), "nodes": e.nodes_controlled,
			"score": e.get_score(), "status": "out" if e.eliminated else "", "is_player": false,
		})
	return rows

# --- Save / load ----------------------------------------------------------------------------

func _get_mode_state() -> Dictionary:
	return {"treatises_done": treatises_done, "treatise_active": treatise_active,
		"treatise_elapsed": treatise_elapsed}

func _load_mode_state(d: Dictionary) -> void:
	treatises_done = int(d.get("treatises_done", 0))
	treatise_active = bool(d.get("treatise_active", false))
	treatise_elapsed = float(d.get("treatise_elapsed", 0.0))
	refresh_panel()
