extends SceneTree
# Mission1 end-to-end: clear the raiders, harvest each Bambuk mine once so it
# is secured, and the mission declares victory (VictoryManager.game_won).
var failures := 0
var won := []

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
	print("PASS: " if cond else "FAIL: ", msg)

func wait_until(cond: Callable, seconds: float) -> bool:
	var frames := int(seconds * 60.0)
	for i in frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()

func _initialize() -> void:
	await process_frame  # autoloads enter the tree after _initialize
	create_timer(60.0, true, false, true).timeout.connect(func():
		print("FAIL: watchdog timeout")
		print("RESULT: FAILED (watchdog)")
		quit(1))
	var vm = root.get_node("VictoryManager")
	var gd = root.get_node("GameData")
	vm.game_won.connect(func(id, title, _text): won.append([id, title]))
	root.get_node("GameSession").start("res://missions/Mission1.tscn")
	await process_frame
	await process_frame
	await process_frame
	var m = current_scene
	check(m != null and m.scene_file_path == "res://missions/Mission1.tscn", "Mission1 loaded")
	check(vm.objectives.size() == 2 and not vm.skirmish_conditions_enabled, "objectives set, skirmish conditions off")
	m.waves_enabled = false
	for e in m.get_node("Enemies").get_children():
		e.queue_free()
	await process_frame
	var p = m.get_node("Player")
	for i in m.mines.size():
		var entry: Dictionary = m.mines[i]
		p.global_position = entry["pos"]
		var g0: int = gd.gold
		var ok: bool = await wait_until(func(): return m.is_mine_secured(i), 4.0)
		check(ok, "mine %d secured after harvesting (gold +%d)" % [i, gd.gold - g0])
	var got_win: bool = await wait_until(func(): return not won.is_empty(), 2.0)
	check(got_win and won[0][0] == "mission", "Mission1 won via game_won %s" % str(won))
	check(vm.is_objective_done("mines"), "mines objective complete")
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
