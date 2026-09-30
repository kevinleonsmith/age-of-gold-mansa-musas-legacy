# Headless test for the AI-rival game modes (Trans-Saharan Showdown, Scholars of
# Sankore), ModeSelect and the MainMenu hook.
# Run: ~/Godot_v4.4-stable_linux.arm64 --headless --fixed-fps 60 --path <P> -s <P>/tests/showdown/test_showdown.gd
extends SceneTree

const SHOWDOWN := "res://modes/Showdown.tscn"
const SCHOLARS := "res://modes/Scholars.tscn"
const PLAYER := 0
const NEUTRAL := -1

var failures := 0
var won: Array = []
var lost: Array = []
var gs: Node
var vm: Node
var dm: Node
var gd: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _start(path: String) -> Node:
	gs.start(path)
	await _frames(4)
	dm.auto_triggers_enabled = false
	won.clear()
	lost.clear()
	return current_scene

func _on_won(id, _t, _x) -> void:
	won.append(id)

func _on_lost(id, _t, _x) -> void:
	lost.append(id)

# Gives `count` nodes to `side` directly through NodeControl's state.
func _give_nodes(nc: Node, side: int, count: int) -> void:
	var nodes: Array = nc.get_nodes()
	for i in mini(count, nodes.size()):
		nc._set_owner(nc.get_state_of(nodes[i]), side)

func _label_texts(node: Node) -> String:
	var out := ""
	for child in node.find_children("*", "Label", true, false):
		out += (child as Label).text + "\n"
	return out

func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameSession")
	vm = root.get_node("VictoryManager")
	dm = root.get_node("DilemmaManager")
	gd = root.get_node("GameData")
	vm.game_won.connect(_on_won)
	vm.game_lost.connect(_on_lost)

	# --- Showdown loads ---------------------------------------------------------------
	var mode := await _start(SHOWDOWN)
	check(mode != null and mode.scene_file_path == SHOWDOWN, "Showdown loads via GameSession.start")
	check(not vm.skirmish_conditions_enabled, "skirmish victory conditions are off in Showdown")
	check(vm.objectives.size() >= 2, "Showdown sets objectives (%d)" % vm.objectives.size())
	var empires: Array = mode.empires()
	check(empires.size() == 3, "three AI empires (%d)" % empires.size())
	var nc: Node = mode.node_control
	check(nc != null and nc.total_nodes() >= 10 and nc.total_nodes() <= 14, "10-14 contested nodes (%d)" % (nc.total_nodes() if nc else 0))

	# --- AI economy over fast-forwarded time -------------------------------------------
	var e = empires[0]
	var assets_before: int = e.living_camps().size() + e.living_raiders().size() + e.workers.size()
	var score_before: int = e.get_score()
	var earned_before: float = e.gold + e.salt
	e.tick(1.0)
	check(e.gold + e.salt > earned_before, "AI empire earns income (%.1f -> %.1f)" % [earned_before, e.gold + e.salt])
	for i in 60:
		e.tick(3.0)
	var assets_after: int = e.living_camps().size() + e.living_raiders().size() + e.workers.size()
	check(assets_after > assets_before, "AI builds camps / trains raiders or workers over 3 min (%d -> %d)" % [assets_before, assets_after])
	check(e.get_score() >= score_before, "AI score doesn't drop while it grows (%d -> %d)" % [score_before, e.get_score()])
	check(e.living_raiders().size() > 0 or e.elapsed > 0.0, "AI has raiders or has been running (%d raiders)" % e.living_raiders().size())

	# --- Node control --------------------------------------------------------------------
	var node: Node2D = nc.get_nodes()[0]
	var st: Dictionary = nc.get_state_of(node)
	nc._set_owner(st, NEUTRAL)
	var player: Node2D = mode.get_node("Player")
	# Keep AI units away from this node for the capture check.
	for unit in get_nodes_in_group("ai_units"):
		if unit is Node2D and unit.global_position.distance_to(node.global_position) < 400.0:
			unit.global_position = node.global_position + Vector2(2000, 2000)
	player.global_position = node.global_position + Vector2(40, 0)
	nc.tick(5.0)
	check(nc.get_owner_of(node) == NEUTRAL, "5 s near a node is not enough to capture it")
	nc.tick(6.0)
	check(nc.get_owner_of(node) == PLAYER, "player captures an uncontested node after 10 s")
	var intruder := Node2D.new()
	intruder.add_to_group("ai_units")
	intruder.add_to_group("enemies")
	intruder.set_meta("empire_id", 1)
	mode.add_child(intruder)
	intruder.global_position = node.global_position + Vector2(-40, 0)
	nc.tick(12.0)
	check(nc.get_owner_of(node) == PLAYER and nc.get_state_of(node)["contested"], "a contested node keeps its owner and shows contested")
	player.global_position = node.global_position + Vector2(3000, 3000)
	nc.tick(5.5)
	check(nc.get_owner_of(node) == NEUTRAL, "an enemy alone neutralizes the player's node after 5 s")
	nc.tick(5.0)
	check(nc.get_owner_of(node) == 1, "then captures it for its empire (owner %d)" % nc.get_owner_of(node))
	intruder.queue_free()

	# --- Showdown win: hold the majority -------------------------------------------------
	mode = await _start(SHOWDOWN)
	nc = mode.node_control
	_give_nodes(nc, PLAYER, mode.required_nodes())
	mode.update_control(45.0)
	check(won.is_empty(), "holding the majority for 45 s is not yet a win")
	_give_nodes(nc, PLAYER, mode.required_nodes())
	mode.update_control(46.0)
	check(won == ["showdown"], "holding 60%% of nodes for 90 s wins (%s)" % [won])

	# --- Showdown loss: an AI holds the majority -----------------------------------------
	mode = await _start(SHOWDOWN)
	nc = mode.node_control
	_give_nodes(nc, 2, mode.required_nodes())
	mode.update_control(91.0)
	check(lost == ["showdown_lost"], "an AI holding 60%% for 90 s is a defeat (%s)" % [lost])

	# --- Showdown win: destroy every camp -------------------------------------------------
	mode = await _start(SHOWDOWN)
	for emp in mode.empires():
		emp.tick(0.5)
		for camp in emp.living_camps():
			camp.take_damage(1.0e6)
	await _frames(2)
	for emp in mode.empires():
		emp.tick(0.5)
	check(mode.empires().all(func(x): return x.eliminated), "destroying every camp eliminates each empire")
	mode.update_control(0.1)
	check(won == ["showdown"], "burning every rival camp wins (%s)" % [won])

	# --- Sandstorms ------------------------------------------------------------------------
	mode = await _start(SHOWDOWN)
	check(mode.next_storm_at >= mode.STORM_MIN_GAP and mode.next_storm_at <= mode.STORM_MAX_GAP, "first sandstorm scheduled 2-4 min in (%.0f s)" % mode.next_storm_at)
	mode.mission_time = mode.next_storm_at
	await _frames(3)
	check(mode.storms_fired == 1, "a sandstorm fires when its time comes")
	check(gd.get_modifier("sandstorm_slow_mult") < 1.0, "the sandstorm slows non-camel units (mult %.2f)" % gd.get_modifier("sandstorm_slow_mult"))
	check(mode.next_storm_at > mode.mission_time + mode.STORM_DURATION, "the next storm is rescheduled")

	# --- Scoreboard --------------------------------------------------------------------------
	var board := get_first_node_in_group("scoreboard")
	check(board != null, "Scoreboard is present")
	check(mode.get_scoreboard_rows().size() == 4, "scoreboard has a row for the player and each empire")
	if board != null:
		board.refresh()
		var text := _label_texts(board)
		check(text.contains("Mali") and text.contains("Songhai"), "scoreboard shows the empires")

	# --- Save state round-trip -----------------------------------------------------------------
	var emp1 = mode.get_empire(1)
	emp1.gold = 777.0
	emp1.techs_completed = 2
	var saved: Dictionary = mode.get_mission_state()
	emp1.gold = 1.0
	emp1.techs_completed = 0
	mode.load_mission_state(saved)
	check(is_equal_approx(emp1.gold, 777.0) and emp1.techs_completed == 2, "AI empire state round-trips through get/load_mission_state")

	# --- Scholars ------------------------------------------------------------------------------
	mode = await _start(SCHOLARS)
	check(mode != null and mode.scene_file_path == SCHOLARS, "Scholars loads via GameSession.start")
	check(mode.player_manuscript_techs() == 0, "player starts with no manuscript techs")
	root.get_node("TechManager").grant_tech("oral_histories")
	check(mode.player_manuscript_techs() == 1, "a researched manuscript tech counts")
	check(mode.treatise_block_reason() == "Requires a mosque", "treatise needs a mosque")
	gd.gold = 2000
	gd.salt = 200
	var menu := current_scene.get_node_or_null("BuildMenu")
	var mosque = null
	if menu != null:
		var p: Node2D = current_scene.get_node("Player")
		for offset in [Vector2(160, 0), Vector2(-160, 0), Vector2(0, 160), Vector2(0, -160), Vector2(220, 220)]:
			mosque = menu.place_building("mosque", p.global_position + offset)
			if mosque != null:
				break
	check(mosque != null and mode.count_mosques() >= 1, "a mosque can be built in Scholars")
	gd.manuscripts = 3
	check(mode.commission_treatise(), "commissioning a treatise spends 3 manuscripts")
	check(gd.manuscripts == 0 and mode.treatise_active, "the treatise is being written")
	mode.update_scholars(30.0)
	check(mode.treatises_done == 0, "not done after 30 s")
	mode.update_scholars(31.0)
	check(mode.treatises_done == 1 and mode.player_manuscript_techs() == 2, "done after 60 s and counts as a manuscript tech")
	check(won.is_empty(), "two manuscript techs is not yet a win")
	var tm := root.get_node("TechManager")
	for id in ["friday_mosques", "sankore_curriculum", "manuscript_bazaar"]:
		tm.grant_tech(id)
	mode.check_outcome()
	check(won == ["scholars"], "five manuscript techs win Scholars (%s, count %d)" % [won, mode.player_manuscript_techs()])

	mode = await _start(SCHOLARS)
	var rival = mode.empires()[0]
	rival.techs_completed = 5
	mode.check_outcome()
	check(lost == ["scholars_lost"], "an AI completing five manuscript techs is a defeat (%s)" % [lost])

	# --- ModeSelect and the MainMenu hook -------------------------------------------------------
	gs.start("res://ui/MainMenu.tscn")
	await _frames(4)
	var main_menu := current_scene
	var modes_button: Button = main_menu.find_child("GameModesButton", true, false)
	check(modes_button != null, "MainMenu has a Game Modes button")
	if modes_button != null:
		modes_button.pressed.emit()
		await _frames(2)
	var picker = main_menu.get("mode_select")
	check(picker != null and picker.visible and not main_menu.main_panel.visible, "Game Modes opens ModeSelect")
	if picker != null:
		picker.select_mode("skirmish")
		check(not picker._difficulty_row.visible, "classic skirmish hides the AI difficulty")
		picker.close()
		check(not picker.visible and main_menu.main_panel.visible, "closing ModeSelect returns to the main panel")
		main_menu.show_modes()
		picker.select_mode("scholars")
		picker.set_difficulty("hard")
		picker.launch()
		await _frames(5)
		check(current_scene.scene_file_path == SCHOLARS, "ModeSelect launches Scholars of Sankore")
		var settings: Script = load("res://ai/AISettings.gd")
		check(settings.difficulty == "hard", "the chosen difficulty is kept for the mode")
		var hard_income: float = settings.profile("hard")["income"]
		var emp = current_scene.empires()[0] if current_scene.has_method("empires") else null
		check(emp != null and is_equal_approx(emp.income_mult(), hard_income), "AI empires use the chosen difficulty (income x%.1f)" % (emp.income_mult() if emp else 0.0))
		settings.difficulty = "normal"

	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit()
