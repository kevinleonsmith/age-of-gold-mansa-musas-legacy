# Victory / defeat conditions (res://autoload/VictoryManager.gd)
# Owns the end of a game: the three skirmish victory conditions from the design
# doc (checked about once per second), mission objectives, and session stats
# for ui/EndScreen. declare_victory / declare_defeat pause the tree; use
# GameSession.start() to leave a finished game.
extends Node

signal game_won(condition_id: String, title: String, text: String)
signal game_lost(reason_id: String, title: String, text: String)
signal objectives_changed
# Emitted after each skirmish check so the HUD can redraw the progress bars.
signal progress_changed

# --- Skirmish victory targets (scaled down for the prototype) ---------------
# Design doc: "Accumulate 10,000 Gold Ingots".
const ECONOMIC_INGOTS := 100
# Design doc: "Produce 25 Manuscripts + convert 3 enemy leaders" (kept as is;
# any converted enemy counts as a leader here).
const CULTURAL_MANUSCRIPTS := 25
const CULTURAL_CONVERSIONS := 3
# Design doc: "Destroy all rival wonders". Needs at least one wonder to have
# existed in the scene ("rival_wonders" group), so it can't trigger on maps
# without a rival faction.
const WONDER_GROUP := "rival_wonders"
const CHECK_INTERVAL := 1.0

const CONDITION_TEXT := {
	"economic": ["Economic Domination",
		"The treasuries of Mali overflow. Gold ingots stamped with the Mansa's seal set the price of trade from Cairo to Timbuktu."],
	"cultural": ["Cultural Victory",
		"Scholars flock to the libraries of Timbuktu, and former enemies now recite the Mansa's praises. Mali's legacy is written in ink, not only in gold."],
	"military": ["Military Conquest",
		"The last rival wonder has fallen. No power in the Sahel can challenge the Mansa's armies."],
}

var is_game_over := false
# Missions set this false so the skirmish victory conditions don't apply.
var skirmish_conditions_enabled := true
# Mission objectives shown in the HUD: [{"id", "text", "done", "optional"}].
var objectives: Array = []

# How the last game ended: {"won": bool, "id", "title", "text"} or {}.
var result := {}

# --- Session tracking ----------------------------------------------------------
var manuscripts_produced := 0
var gold_earned := 0
# Unpaused seconds since the last reset.
var elapsed_time := 0.0
var _wonders_seen := false
var _last_manuscripts := 0
var _last_gold := 0
var _check_left := CHECK_INTERVAL

func _ready() -> void:
	GameData.manuscripts_changed.connect(_on_manuscripts_changed)
	GameData.gold_changed.connect(_on_gold_changed)
	_last_manuscripts = GameData.manuscripts
	_last_gold = GameData.gold

func reset() -> void:
	is_game_over = false
	skirmish_conditions_enabled = true
	objectives = []
	result = {}
	manuscripts_produced = 0
	gold_earned = 0
	elapsed_time = 0.0
	_wonders_seen = false
	_last_manuscripts = GameData.manuscripts
	_last_gold = GameData.gold
	_check_left = CHECK_INTERVAL
	objectives_changed.emit()
	progress_changed.emit()

func _process(delta: float) -> void:
	if is_game_over:
		return
	elapsed_time += delta
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL
		check_conditions()

# Ends the game with a win (missions and victory conditions call this).
func declare_victory(condition_id: String, title: String, text: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	result = {"won": true, "id": condition_id, "title": title, "text": text}
	AudioManager.play_sfx("victory")
	get_tree().paused = true
	game_won.emit(condition_id, title, text)

func declare_defeat(reason_id: String, title: String, text: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	result = {"won": false, "id": reason_id, "title": title, "text": text}
	AudioManager.play_sfx("defeat")
	get_tree().paused = true
	game_lost.emit(reason_id, title, text)

# --- Skirmish conditions -------------------------------------------------------

# Evaluates the three skirmish victory conditions (called once per second).
func check_conditions() -> void:
	_update_wonders_seen()
	progress_changed.emit()
	if is_game_over or not skirmish_conditions_enabled:
		return
	var progress := get_progress()
	for id in ["economic", "cultural", "military"]:
		if progress[id]["done"]:
			var info: Array = CONDITION_TEXT[id]
			declare_victory(id, info[0], info[1])
			return

# {"economic"|"cultural"|"military": {"name", "current", "target", "fraction",
# "done", "detail"}} for the HUD and pause menu.
func get_progress() -> Dictionary:
	var ingots: int = GameData.ingots
	var converted := int(GameData.get_modifier("converted_count", 0.0))
	var m_frac := minf(float(manuscripts_produced) / CULTURAL_MANUSCRIPTS, 1.0)
	var c_frac := minf(float(converted) / CULTURAL_CONVERSIONS, 1.0)
	var wonders := _count_wonders()
	var mil_frac := 0.0
	var mil_detail := "No rival wonders found"
	if wonders > 0:
		mil_detail = "%d rival wonder%s standing" % [wonders, "" if wonders == 1 else "s"]
	elif _wonders_seen:
		mil_frac = 1.0
		mil_detail = "All rival wonders destroyed"
	return {
		"economic": {
			"name": CONDITION_TEXT["economic"][0],
			"current": ingots, "target": ECONOMIC_INGOTS,
			"fraction": minf(float(ingots) / ECONOMIC_INGOTS, 1.0),
			"done": ingots >= ECONOMIC_INGOTS,
			"detail": "%d / %d Ingots" % [ingots, ECONOMIC_INGOTS],
		},
		"cultural": {
			"name": CONDITION_TEXT["cultural"][0],
			"current": mini(manuscripts_produced, CULTURAL_MANUSCRIPTS) + mini(converted, CULTURAL_CONVERSIONS),
			"target": CULTURAL_MANUSCRIPTS + CULTURAL_CONVERSIONS,
			"fraction": (m_frac * CULTURAL_MANUSCRIPTS + c_frac * CULTURAL_CONVERSIONS) / (CULTURAL_MANUSCRIPTS + CULTURAL_CONVERSIONS),
			"manuscripts": manuscripts_produced, "converted": converted,
			"done": manuscripts_produced >= CULTURAL_MANUSCRIPTS and converted >= CULTURAL_CONVERSIONS,
			"detail": "%d / %d Manuscripts, %d / %d converted" % [manuscripts_produced, CULTURAL_MANUSCRIPTS, converted, CULTURAL_CONVERSIONS],
		},
		"military": {
			"name": CONDITION_TEXT["military"][0],
			"current": wonders, "target": 0,
			"fraction": mil_frac,
			"done": _wonders_seen and wonders == 0,
			"detail": mil_detail,
		},
	}

func _count_wonders() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(WONDER_GROUP):
		if node.is_queued_for_deletion():
			continue
		if "is_destroyed" in node and node.is_destroyed:
			continue
		count += 1
	return count

func _update_wonders_seen() -> void:
	if not _wonders_seen and _count_wonders() > 0:
		_wonders_seen = true

func _on_manuscripts_changed(value) -> void:
	# Cumulative: spending manuscripts never lowers the produced count.
	if value > _last_manuscripts:
		manuscripts_produced += value - _last_manuscripts
	_last_manuscripts = value

func _on_gold_changed(value) -> void:
	if value > _last_gold:
		gold_earned += value - _last_gold
	_last_gold = value

# Stats for the end screen: {"time", "gold_earned", "buildings", "conversions", "techs"}.
func get_session_stats() -> Dictionary:
	var techs := 0
	var tech_manager := get_node_or_null("/root/TechManager")
	if tech_manager != null and "researched" in tech_manager:
		techs = tech_manager.researched.size()
	return {
		"time": elapsed_time,
		"gold_earned": gold_earned,
		"buildings": get_tree().get_nodes_in_group("buildings").size(),
		"conversions": int(GameData.get_modifier("converted_count", 0.0)),
		"techs": techs,
	}

# --- Mission objectives --------------------------------------------------------

func set_objectives(list: Array) -> void:
	objectives = []
	for entry in list:
		var objective: Dictionary = {"done": false, "optional": false}
		objective.merge(entry, true)
		objectives.append(objective)
	objectives_changed.emit()

func set_objective_text(objective_id: String, text: String) -> void:
	for objective in objectives:
		if objective["id"] == objective_id:
			objective["text"] = text
			objectives_changed.emit()
			return

func complete_objective(objective_id: String) -> void:
	for objective in objectives:
		if objective["id"] == objective_id and not objective["done"]:
			objective["done"] = true
			objectives_changed.emit()
			return

func is_objective_done(objective_id: String) -> bool:
	for objective in objectives:
		if objective["id"] == objective_id:
			return objective["done"]
	return false
