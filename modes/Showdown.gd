# Trans-Saharan Showdown (res://modes/Showdown.gd)
# Design doc "Multiplayer Modes" 1, single-player: the Mansa and three AI
# empires (Songhai, Mossi, Tuareg; ai/AIEmpire.gd) compete for the gold and
# salt nodes of a large map. Random sandstorms (systems/Sandstorm) slow every
# unit except camel riders.
# Win: hold >= 60% of the nodes for 90 s in a row, or destroy every AI war
#   camp (an empire whose camps all fall is out).
# Lose: an AI holds >= 60% for 90 s, or the Mansa dies (Player.gd).
extends "res://ai/RivalModeBase.gd"

const CONTROL_SHARE := 0.6
const HOLD_TIME := 90.0
const STORM_MIN_GAP := 120.0
const STORM_MAX_GAP := 240.0
const STORM_DURATION := 30.0

@export var sandstorms_enabled := true

var player_hold := 0.0
var ai_hold := {} # empire_id -> seconds held at >= 60%
var next_storm_at := 0.0
var storms_fired := 0
var rng := RandomNumberGenerator.new()

@onready var sandstorm: Node = $Sandstorm

func _mode_ready() -> void:
	mode_id = "showdown"
	rng.randomize()
	next_storm_at = rng.randf_range(STORM_MIN_GAP, STORM_MAX_GAP)
	set_objectives([
		{"id": "control", "text": _control_text()},
		{"id": "camps", "text": _camps_text()},
	])
	toast("Mansa: Songhai, Mossi and Tuareg all covet the gold and salt of the Sahel. Hold the nodes, and hold them long.")

func _mission_process(delta: float) -> void:
	update_control(delta * time_scale)
	if sandstorms_enabled and not finished and mission_time >= next_storm_at:
		fire_sandstorm()
	if hud_due(delta):
		objective_text("control", _control_text())
		objective_text("camps", _camps_text())

func required_nodes() -> int:
	return int(ceil(total_nodes() * CONTROL_SHARE - 0.0001))

func _has_majority(side: int) -> bool:
	var total := total_nodes()
	return total > 0 and node_control.count_owned(side) >= required_nodes()

# Advances the 90 s hold timers by `dt` seconds and checks the outcome.
func update_control(dt: float) -> void:
	if finished or node_control == null:
		return
	player_hold = player_hold + dt if _has_majority(PLAYER) else 0.0
	for e in empires():
		var id: int = e.empire_id
		ai_hold[id] = float(ai_hold.get(id, 0.0)) + dt if _has_majority(id) and not e.eliminated else 0.0
	_check_outcome()

func _check_outcome() -> void:
	if finished:
		return
	if player_hold >= HOLD_TIME:
		complete("control")
		end_victory("showdown", "Master of the Sahara",
			"For ninety days and nights the gold and salt of the desert answered only to Mali. Songhai, Mossi and Tuareg bow to the Mansa.")
		return
	var list := empires()
	if not list.is_empty() and list.all(func(e): return e.eliminated):
		complete("camps")
		end_victory("showdown", "The Rival Camps Burn",
			"Every rival war camp lies in ashes. The trans-Saharan roads belong to Mali alone.")
		return
	for e in list:
		if float(ai_hold.get(e.empire_id, 0.0)) >= HOLD_TIME:
			end_defeat("showdown_lost", "The %s Rule the Sands" % e.empire_name,
				"The %s of %s held the desert's wealth for ninety days. Mali's caravans now pay tribute to a rival." % [e.empire_name, e.capital_name])
			return

# --- Sandstorms ---------------------------------------------------------------------

func fire_sandstorm() -> void:
	storms_fired += 1
	next_storm_at = mission_time + STORM_DURATION + rng.randf_range(STORM_MIN_GAP, STORM_MAX_GAP)
	if sandstorm != null and sandstorm.has_method("start"):
		sandstorm.start(STORM_DURATION)

# --- HUD ------------------------------------------------------------------------------

func _control_text() -> String:
	var total := total_nodes()
	var text := "Hold %d of %d nodes for %s: %d held" % [required_nodes(), total, format_clock(HOLD_TIME), player_nodes()]
	if player_hold > 0.0:
		text += " (%s left)" % format_clock(HOLD_TIME - player_hold)
	return text

func _camps_text() -> String:
	var camps := 0
	var out := 0
	for e in empires():
		camps += e.living_camps().size()
		if e.eliminated:
			out += 1
	return "Or destroy every rival war camp: %d standing, %d/%d empires out" % [camps, out, empires().size()]

func get_scoreboard_title() -> String:
	return "Trans-Saharan Showdown · need %d/%d nodes" % [required_nodes(), total_nodes()]

func get_scoreboard_rows() -> Array:
	var rows := [{
		"name": PLAYER_NAME, "color": PLAYER_COLOR, "nodes": player_nodes(),
		"score": player_score(), "hold": player_hold, "status": "", "is_player": true,
	}]
	for e in empires():
		rows.append({
			"name": e.empire_name, "color": e.color, "nodes": e.nodes_controlled,
			"score": e.get_score(), "hold": float(ai_hold.get(e.empire_id, 0.0)),
			"status": "out" if e.eliminated else "", "is_player": false,
		})
	return rows

# --- Save / load ------------------------------------------------------------------------

func _get_mode_state() -> Dictionary:
	var holds := {}
	for id in ai_hold:
		holds[str(id)] = ai_hold[id]
	return {"player_hold": player_hold, "ai_hold": holds, "next_storm_at": next_storm_at,
		"storms_fired": storms_fired}

func _load_mode_state(d: Dictionary) -> void:
	player_hold = float(d.get("player_hold", 0.0))
	ai_hold.clear()
	var holds: Dictionary = d.get("ai_hold", {})
	for key in holds:
		ai_hold[int(key)] = float(holds[key])
	next_storm_at = float(d.get("next_storm_at", next_storm_at))
	storms_fired = int(d.get("storms_fired", storms_fired))
