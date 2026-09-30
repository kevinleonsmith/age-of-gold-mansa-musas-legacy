extends SceneTree
# Game-flow test: skirmish victory conditions, player defeat, end screen, retry
# via GameSession, pause menu, objectives HUD, mission registry and main menu.

const MAIN := "res://main.tscn"
const MENU := "res://ui/MainMenu.tscn"
const MISSION1 := "res://missions/Mission1.tscn"
const TEST_SAVE := "user://test_campaign_flow.cfg"
const REAL_SAVE := "user://campaign.cfg"

var failures := 0
var gd: Node
var vm: Node
var dm: Node
var gs: Node
var am: Node
var tm: Node
var registry: GDScript
var won: Array = []
var lost: Array = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
	print(("PASS: " if cond else "FAIL: ") + msg)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _frames(n := 2) -> void:
	for i in n:
		await process_frame

# Fresh game via GameSession, with random spawns and dilemmas off, and the
# flow UI instanced if the scene doesn't have it yet.
func _fresh(path := MAIN) -> void:
	gs.start(path)
	await _frames(3)
	dm.auto_triggers_enabled = false
	var sm := current_scene.get_node_or_null("SpawnManager")
	if sm:
		sm.queue_free()
	for entry in [["end_screen", "res://ui/EndScreen.tscn"], ["pause_menu", "res://ui/PauseMenu.tscn"], ["objectives_hud", "res://ui/ObjectivesHUD.tscn"]]:
		if get_first_node_in_group(entry[0]) == null:
			current_scene.add_child((load(entry[1]) as PackedScene).instantiate())
	won.clear()
	lost.clear()
	await _frames(1)

func _on_won(id, _title, _text) -> void:
	won.append(id)

func _on_lost(id, _title, _text) -> void:
	lost.append(id)

func _key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)

func _file_stamp(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	return "%d:%s" % [FileAccess.get_modified_time(path), FileAccess.get_md5(path)]

func _initialize() -> void:
	gd = root.get_node("GameData")
	vm = root.get_node("VictoryManager")
	dm = root.get_node("DilemmaManager")
	gs = root.get_node("GameSession")
	am = root.get_node("AgeManager")
	tm = root.get_node("TechManager")
	registry = load("res://missions/MissionRegistry.gd")
	var real_save_before := _file_stamp(REAL_SAVE)
	registry.set_save_path(TEST_SAVE)
	registry.clear_progress()
	vm.game_won.connect(_on_won)
	vm.game_lost.connect(_on_lost)
	change_scene_to_file(MAIN)
	await _frames(2)

	# --- Economic Domination ---------------------------------------------------
	await _fresh()
	gd.ingots = vm.ECONOMIC_INGOTS - 1
	await _wait(1.3)
	check(won.is_empty(), "economic: %d ingots is not yet a win" % gd.ingots)
	gd.ingots = vm.ECONOMIC_INGOTS
	await _wait(1.3)
	check(won == ["economic"], "economic: holding %d ingots wins (won=%s)" % [vm.ECONOMIC_INGOTS, won])
	check(paused and vm.is_game_over, "economic: game over pauses the tree")
	var end_screen = get_first_node_in_group("end_screen")
	check(end_screen.visible and end_screen.heading_label.text == "VICTORY" and end_screen.title_label.text == "Economic Domination", "end screen shows the victory (%s)" % end_screen.title_label.text)
	check(not end_screen.next_button.visible, "skirmish win has no Next Mission button")
	check(end_screen.stats_label.text.contains("Gold earned") and end_screen.stats_label.text.contains("Techs researched"), "end screen shows session stats")

	# --- Cultural Victory ------------------------------------------------------
	await _fresh()
	gd.manuscripts += 20
	gd.manuscripts += 5
	check(gd.spend({"manuscripts": 20}), "cultural: spent 20 manuscripts")
	await _wait(1.3)
	var cultural: Dictionary = vm.get_progress()["cultural"]
	check(cultural["manuscripts"] == 25 and gd.manuscripts == 5, "cultural: spending doesn't reduce produced manuscripts (%d produced, %d held)" % [cultural["manuscripts"], gd.manuscripts])
	check(won.is_empty(), "cultural: manuscripts alone don't win")
	gd.add_modifier("converted_count", 2.0)
	await _wait(1.3)
	check(won.is_empty(), "cultural: 2 conversions are not enough")
	gd.add_modifier("converted_count", 1.0)
	await _wait(1.3)
	check(won == ["cultural"], "cultural: 25 manuscripts + 3 conversions win (won=%s)" % [won])

	# --- Military Conquest -----------------------------------------------------
	# A map without a rival faction: remove main's RivalBase before the first check.
	await _fresh()
	var rival_base := current_scene.get_node_or_null("RivalBase")
	if rival_base:
		rival_base.free()
	await _wait(1.3)
	check(won.is_empty(), "military: no win when no rival wonder ever existed")
	# main.tscn's real Gao palace: standing blocks the win, destroying it wins.
	await _fresh()
	await _wait(1.3)
	var wonders := get_nodes_in_group("rival_wonders")
	check(won.is_empty() and wonders.size() == 1 and vm.get_progress()["military"]["current"] == 1, "military: a standing wonder blocks the win")
	for wonder in wonders:
		wonder.take_damage(1.0e6)
	await _wait(1.3)
	check(won == ["military"], "military: destroying the last rival wonder wins (won=%s)" % [won])

	# --- Conditions disabled (missions) ---------------------------------------
	await _fresh()
	vm.skirmish_conditions_enabled = false
	gd.ingots = 500
	gd.manuscripts = 50
	gd.add_modifier("converted_count", 5.0)
	await _wait(1.5)
	check(won.is_empty() and not vm.is_game_over, "skirmish_conditions_enabled = false disables the conditions")

	# --- Player death -> defeat, then Retry ------------------------------------
	await _fresh()
	var old_gen: int = gd.generation
	gd.gold = 900
	am.current_age = am.AGES.MALI_ASCENDANCY
	tm.grant_tech(tm.get_all_techs()[0]["id"])
	var house = (load("res://buildings/House.tscn") as PackedScene).instantiate()
	house.position = Vector2(700, 300)
	current_scene.get_node("Buildings").add_child(house)
	await _frames(1)
	var income_with_house: int = gd.income_per_second
	var player = current_scene.get_node("Player")
	player.take_damage(100000)
	await _wait(1.6)
	check(lost == ["player_died"] and vm.is_game_over and paused, "player death is a defeat (lost=%s)" % [lost])
	end_screen = get_first_node_in_group("end_screen")
	check(end_screen.visible and end_screen.heading_label.text == "DEFEAT" and end_screen.title_label.text == "The Mansa has fallen", "end screen shows the defeat")
	check(end_screen.stats_label.text.contains("Buildings 1") and end_screen.stats_label.text.contains("Techs researched 1"), "defeat stats count the house and tech (%s)" % end_screen.stats_label.text.replace("\n", " / "))
	end_screen.retry()
	await _frames(3)
	check(current_scene != null and current_scene.scene_file_path == MAIN, "retry reloads main.tscn")
	check(not paused and not vm.is_game_over, "retry unpauses and clears game over")
	check(gd.gold <= 1 and am.current_age == am.AGES.SAND_CHIEFDOMS and tm.researched.is_empty(), "retry resets gold (%d), age and techs" % gd.gold)
	check(gd.generation > old_gen, "retry bumps the generation")
	check(income_with_house == 2 and gd.income_per_second == 1, "old house's income isn't double-removed (with house %d, after %d)" % [income_with_house, gd.income_per_second])

	# --- Pause menu -------------------------------------------------------------
	await _fresh()
	var pm = get_first_node_in_group("pause_menu")
	_key(KEY_P)
	await _frames(1)
	check(pm.is_open and pm.visible and paused, "P opens the pause menu and pauses")
	check(pm.progress_label.text.contains("Economic Domination"), "pause menu shows victory progress")
	_key(KEY_P)
	await _frames(1)
	check(not pm.is_open and not paused, "P again resumes")
	pm.open()
	_key(KEY_ESCAPE)
	await _frames(1)
	check(not pm.is_open and not paused, "Esc closes the pause menu")
	dm.trigger(dm.get_dilemma_ids()[0])
	await _frames(1)
	check(dm.is_active() and paused, "dilemma pauses the game")
	_key(KEY_P)
	await _frames(1)
	check(not pm.is_open, "pause menu doesn't open during a dilemma")
	pm.is_open = true # force the close path while a dilemma is active
	pm.close()
	check(paused, "closing the pause menu doesn't unpause during a dilemma")
	await _fresh()
	pm = get_first_node_in_group("pause_menu")
	pm.open()
	check(pm.is_open, "pause menu reopens in a new game")
	dm.trigger(dm.get_dilemma_ids()[0])
	await _frames(1)
	check(not pm.is_open and paused and dm.is_active(), "a dilemma starting hides the pause menu and stays paused")
	await _fresh()
	pm = get_first_node_in_group("pause_menu")
	vm.declare_defeat("test", "Test", "Test")
	_key(KEY_P)
	await _frames(1)
	check(not pm.is_open, "pause menu doesn't open after game over")

	# --- Objectives HUD -------------------------------------------------------------
	await _fresh()
	var hud = get_first_node_in_group("objectives_hud")
	check(hud.bars.size() == 3, "HUD shows three victory bars in skirmish")
	gd.ingots = 50
	await _wait(1.3)
	check(is_equal_approx(hud.bars["economic"]["bar"].value, 0.5), "economic bar updates (%.2f)" % hud.bars["economic"]["bar"].value)
	vm.skirmish_conditions_enabled = false
	vm.set_objectives([{"id": "mines", "text": "Secure the gold mines"}, {"id": "wells", "text": "Hold the wells", "optional": true}])
	await _frames(1)
	check(hud.objective_labels.size() == 2 and hud.objective_labels[0].text.begins_with("•") and hud.objective_labels[1].text.ends_with("(optional)"), "HUD lists mission objectives")
	vm.complete_objective("mines")
	await _frames(1)
	check(hud.objective_labels[0].text.begins_with("✓"), "HUD ticks completed objectives (%s)" % hud.objective_labels[0].text)
	vm.set_objective_text("wells", "Hold the wells (1/2)")
	await _frames(1)
	check(hud.objective_labels[1].text.contains("(1/2)"), "HUD updates objective text")
	pm = get_first_node_in_group("pause_menu")
	pm.open()
	check(pm.progress_label.text.contains("✓ Secure the gold mines"), "pause menu lists mission objectives")
	pm.close()
	hud.toggle_collapsed()
	check(hud.collapsed and not hud.content.visible, "HUD collapses")
	hud.toggle_collapsed()
	check(hud.content.visible, "HUD expands")

	# --- Mission registry ---------------------------------------------------------
	registry.clear_progress()
	var ids: Array = registry.get_missions().map(func(m): return m["id"])
	check(ids == ["mission1", "mission2", "mission3", "mission4", "mission5", "mission6", "mission7", "mission8", "mission9", "scholars_revolt"], "registry lists the campaign in order (%s)" % [ids])
	check(registry.is_unlocked("mission1") and not registry.is_unlocked("mission2") and not registry.is_unlocked("mission7"), "only mission1 starts unlocked")
	check(registry.get_next("mission1")["id"] == "mission2" and registry.get_next("mission7")["id"] == "mission8" and registry.get_next("mission9").is_empty(), "get_next skips the bonus mission and ends after mission9")
	check(not registry.is_unlocked("scholars_revolt"), "bonus mission starts locked")
	registry.mark_completed("mission4")
	check(registry.is_unlocked("scholars_revolt") and registry.is_unlocked("mission5") and not registry.is_unlocked("mission6"), "mission4 unlocks the bonus mission and mission5")
	registry.set_flag("salt_famine", true)
	check(registry.get_flag("salt_famine", false) == true and registry.get_flag("missing", 7) == 7, "campaign flags persist")
	registry.clear_progress()
	check(registry.find_by_scene(MISSION1)["id"] == "mission1" and registry.find_by_scene(MAIN).is_empty(), "find_by_scene")
	check(registry.is_available("mission7") == ResourceLoader.exists("res://missions/Mission7.tscn"), "missing scenes are 'coming soon'")
	registry.mark_completed("mission1")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SAVE)
	check(registry.is_unlocked("mission2") and cfg.get_value("completed", "mission1", false), "completing mission1 unlocks mission2 and persists")
	registry.clear_progress()
	# A mission win through the end screen records progress.
	await _fresh(MISSION1)
	vm.skirmish_conditions_enabled = false
	vm.declare_victory("mission", "Mission complete", "The mines are secure.")
	await _frames(1)
	end_screen = get_first_node_in_group("end_screen")
	check(registry.is_completed("mission1") and registry.is_unlocked("mission2"), "campaign win marks the mission completed")
	check(end_screen.next_button.visible == registry.is_available("mission2"), "Next Mission shown only if the next scene exists")
	check(end_screen.campaign_label.text.contains("Sand & Sovereignty"), "end screen names the completed mission")

	# --- Main menu -------------------------------------------------------------------
	gs.start(MENU)
	await _frames(3)
	var menu = current_scene
	check(menu != null and menu.scene_file_path == MENU and not paused, "main menu loads")
	menu.show_campaign()
	check(menu.campaign_panel.visible and menu.mission_buttons.size() == registry.get_missions().size(), "campaign panel lists the missions")
	check(menu.mission_state("mission1") == "completed" and menu.mission_state("mission7") in ["locked", "coming_soon"], "mission states (%s, %s)" % [menu.mission_state("mission1"), menu.mission_state("mission7")])
	menu.select_mission("mission7")
	check(menu.play_button.disabled, "locked / coming-soon mission can't be played")
	menu.show_main()
	var gen_before: int = gd.generation
	menu.skirmish_button.pressed.emit()
	await _frames(3)
	check(current_scene != null and current_scene.scene_file_path == MAIN and gd.generation > gen_before, "Skirmish starts main.tscn with a fresh session")

	# --- Cleanup -------------------------------------------------------------------
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	check(_file_stamp(REAL_SAVE) == real_save_before, "the real campaign save is untouched")
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
