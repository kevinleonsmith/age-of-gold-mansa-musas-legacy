extends SceneTree

var _fails := 0
var gd
var am
var dm
var econ
var tech
var dialog
var toasts

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

func count_resources(type: int) -> int:
	var n := 0
	for c in current_scene.find_children("*", "Area2D", true, false):
		if c.get("resource_type") == type and c.get("quantity") == 100 and not c.is_queued_for_deletion():
			n += 1
	return n

func count_lancers() -> int:
	var n := 0
	for c in get_nodes_in_group("allies"):
		if c.scene_file_path == "res://entities/CamelLancer.tscn":
			n += 1
	return n

func mansa_toasts() -> int:
	var n := 0
	for t in toasts.get_toast_texts():
		if t.begins_with("Mansa Musa"):
			n += 1
	return n

func press_key(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	root.push_input(up)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	gd = root.get_node("GameData")
	am = root.get_node("AgeManager")
	dm = root.get_node("DilemmaManager")
	econ = root.get_node("EconomyManager")
	tech = root.get_node("TechManager")
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var sm = current_scene.get_node_or_null("SpawnManager")
	if sm:
		sm.free()
	# The rival base spawns camp raiders and its wonder would end the game if freed.
	var rival_base = current_scene.get_node_or_null("RivalBase")
	if rival_base:
		rival_base.free()
	dialog = load("res://ui/DilemmaDialog.tscn").instantiate()
	toasts = load("res://ui/Toasts.tscn").instantiate()
	current_scene.add_child(dialog)
	current_scene.add_child(toasts)
	await process_frame
	dm.auto_triggers_enabled = false
	dm.duration_scale = 0.02
	dm.rng.seed = 12345
	toasts.mansa_interval = 1000.0
	toasts._mansa_time_left = 1000.0
	print("--- Toasts / Mansa lines")
	toasts.show_toast("hello world", Color.RED)
	check("hello world" in toasts.get_toast_texts(), "show_toast displays a toast")
	check(is_instance_valid(get_first_node_in_group("toasts")), "toasts registered in group")
	gd.gold = 2000
	toasts.show_mansa_line()
	var last: String = toasts.get_toast_texts().back()
	check(last.begins_with("Mansa Musa") and toasts.pick_mansa_line(2000) in toasts.MANSA_LINES["wealthy"], "wealthy line: " + last)
	check(toasts.pick_mansa_line(50) in toasts.MANSA_LINES["poor"], "poor tier line")
	check("The desert itself kneels before Mali!" in toasts.MANSA_LINES["wealthy"] and "Even salt loses its savor without gold." in toasts.MANSA_LINES["poor"], "design doc lines present")
	await wait(5.0)
	check(toasts.get_toast_texts().is_empty(), "toasts fade out")
	toasts.tier_change_cooldown = 0.0
	gd.gold = 10
	await wait(0.1)
	check(mansa_toasts() == 1, "tier change (to poor) shows a Mansa line: %s" % str(toasts.get_toast_texts()))
	toasts._mansa_time_left = 0.05
	await wait(0.2)
	check(mansa_toasts() == 2, "periodic Mansa line fires")

	print("--- Salt Famine")
	gd.salt = 0
	gd.manuscripts = 0
	check(dm.trigger("salt_famine"), "salt_famine triggers")
	check(not dm.trigger("mosque_crisis"), "trigger refused while one is active")
	check(paused, "game paused while dialog open")
	check(dialog.visible, "dialog visible")
	check(dm.get_active().id == "salt_famine" and dm.get_active().options.size() == 3, "get_active returns data")
	check(dialog.get_node("%Speaker").text == "Starving Villager", "speaker shown")
	check(dialog.get_option_button(2).disabled, "option C disabled without manuscripts")
	print("  Option C text: ", dialog.get_option_button(2).text.replace("\n", " / "))
	toasts._mansa_time_left = 0.0
	await wait(0.1)
	check(mansa_toasts() <= 2, "no Mansa line while a dilemma is active")
	check(not dm.choose(2), "unaffordable option C refused")
	check(dm.is_active(), "still active after refusal")
	dialog.get_option_button(0).pressed.emit()
	check(not paused, "unpaused after choice")
	check(gd.salt == 500, "A: +500 salt (salt=%d)" % gd.salt)
	check(near(gd.get_modifier("harvest_mult"), 0.75), "A: harvest_mult 0.75")
	check(dialog.get_node("%Response").visible and "at what cost" in dialog.get_node("%Response").text, "response shown")
	# Pause should freeze the modifier timer: open another dilemma and wait.
	dm.trigger("salt_famine")
	check(paused, "paused again")
	await wait(3.0)
	check(near(gd.get_modifier("harvest_mult"), 0.75), "temp modifier frozen while paused")
	var salt_nodes: int = count_resources(1)
	press_key(KEY_2)
	await process_frame
	check(not dm.is_active() and not paused, "key 2 chooses option B")
	await wait(2.7)
	check(near(gd.get_modifier("harvest_mult"), 1.0), "A: harvest_mult reverts to 1.0")
	check(not dialog.visible, "dialog closes after response")
	check(count_resources(1) == salt_nodes + 1, "B: salt mine spawned after delay")
	gd.manuscripts = 1
	var salt_before: int = gd.salt
	dm.trigger("salt_famine")
	check(not dialog.get_option_button(2).disabled, "option C enabled with 1 manuscript")
	check(dm.choose(2), "C chosen")
	check(gd.salt == salt_before + 100 and gd.manuscripts == 0, "C: 1 manuscript -> 100 salt")
	check(near(gd.get_modifier("harvest_mult"), 0.9), "C: harvest_mult 0.9")
	await wait(1.4)
	check(near(gd.get_modifier("harvest_mult"), 1.0), "C: harvest_mult reverts")

	print("--- Inflation Debate")
	econ.price_index = 2.0
	gd.ingots = 30
	dm.trigger("inflation_debate")
	dm.choose(0)
	check(gd.ingots == 10, "A: lose 20 ingots (ingots=%d)" % gd.ingots)
	check(near(econ.price_index, 1.0), "A: inflation reset")
	check(tech.is_researched("economic_stabilization"), "A: economic_stabilization granted")
	var rival_before: float = econ.rival_gold
	var gold_nodes: int = count_resources(0)
	dm.trigger("inflation_debate")
	dm.choose(1)
	check(econ.rival_gold <= maxf(rival_before - 2500.0, 0.0) + 0.01, "B: rival gold drained (%s -> %s)" % [rival_before, econ.rival_gold])
	check(count_resources(0) == gold_nodes + 1, "B: gold mine spawned")
	gd.salt = 1000
	dm.trigger("inflation_debate")
	check("Age III" in dm.get_option_block_reason(2), "C: blocked reason mentions Age III")
	check(dialog.get_option_button(2).disabled and "Age III" in dialog.get_option_button(2).text, "C: button disabled with reason")
	check(not dm.choose(2), "C: refused below Age III")
	am.current_age = am.AGES.GOLDEN_HAJJ
	econ.price_index = 2.0
	check(dm.choose(2), "C: allowed in Age III")
	check(gd.salt == 0 and gd.ingots == 11 and near(econ.price_index, 1.0), "C: 1000 salt -> 1 ingot, inflation reset")
	am.current_age = am.AGES.SAND_CHIEFDOMS

	print("--- Mosque Crisis")
	gd.gold = 0
	dm.trigger("mosque_crisis")
	check(not dm.choose(0), "A: refused without 300 gold")
	gd.gold = 1000
	var lancers: int = count_lancers()
	var price: int = gd.scaled_cost({"gold": 300})["gold"]
	var ms: int = gd.manuscripts
	check(dm.choose(0), "A: chosen with gold")
	await process_frame
	check(gd.gold <= 1000 - price + 2, "A: 300 gold paid (gold=%d)" % gd.gold)
	check(count_lancers() == lancers + 2, "A: 2 zealots spawned")
	await wait(1.3)
	check(gd.manuscripts >= ms + 1, "A: manuscripts trickle in (%d -> %d)" % [ms, gd.manuscripts])
	dm.trigger("mosque_crisis")
	dm.choose(1)
	check(near(gd.get_modifier("conversion_speed_mult"), 1.15), "B: conversion x1.15")
	check(near(gd.get_modifier("enemy_spawn_rate_mult"), 1.5), "B: enemy spawn x1.5")
	await wait(2.0)
	check(near(gd.get_modifier("enemy_spawn_rate_mult"), 1.0), "B: enemy spawn reverts")
	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node2D\nvar converted := false\nfunc convert_to_ally() -> void:\n\tconverted = true\n\tremove_from_group(\"enemies\")\n"
	fake_script.reload()
	var fakes := []
	for i in 10:
		var f := Node2D.new()
		f.set_script(fake_script)
		f.add_to_group("enemies")
		current_scene.add_child(f)
		fakes.append(f)
	dm.trigger("mosque_crisis")
	dm.choose(2)
	var converted := 0
	for f in fakes:
		if f.converted:
			converted += 1
		f.queue_free()
	check(converted > 0 and converted < 10, "C: ~50%% converted (%d/10)" % converted)

	print("--- Tuareg Negotiation")
	gd.salt = 200
	dm.trigger("mosque_crisis")
	dm.choose(1)  # x1.5 for 1.8 s, overlapping the truce
	var res_before: int = count_resources(0) + count_resources(1)
	dm.trigger("tuareg_negotiation")
	check(dm.choose(0), "A: chosen with 200 salt")
	check(gd.salt == 0, "A: 200 salt paid")
	check(near(gd.get_modifier("enemy_spawn_rate_mult"), 0.0), "A: raids paused (spawn mult 0)")
	check(count_resources(0) + count_resources(1) == res_before + 2, "A: hidden oasis spawned")
	await wait(2.0)
	check(near(gd.get_modifier("enemy_spawn_rate_mult"), 0.0), "A: still neutral after revolt ends")
	await wait(2.0)
	check(near(gd.get_modifier("enemy_spawn_rate_mult"), 1.0), "A: spawn mult restored to 1.0 (%s)" % gd.get_modifier("enemy_spawn_rate_mult"))
	gd.manuscripts = 0
	dm.trigger("tuareg_negotiation")
	check(not dm.choose(1), "B: refused without manuscript")
	gd.manuscripts = 1
	lancers = count_lancers()
	check(dm.choose(1), "B: chosen with manuscript")
	await process_frame
	check(count_lancers() == lancers + 2, "B: 2 camel lancers")
	check(near(gd.get_modifier("caravan_damage_taken_mult"), 0.5), "B: caravan damage x0.5")
	var enemies_before := get_nodes_in_group("enemies").size()
	dm.trigger("tuareg_negotiation")
	dm.choose(2)
	await process_frame
	var enemies := get_nodes_in_group("enemies")
	check(enemies.size() == enemies_before + 5, "C: 5 raiders spawned")
	var ppos: Vector2 = get_first_node_in_group("player").global_position
	var dist_ok := true
	for e in enemies:
		if absf(e.global_position.distance_to(ppos) - 350.0) > 5.0:
			dist_ok = false
	check(dist_ok, "C: raiders at 350 px")
	check(near(gd.get_modifier("caravan_speed_mult"), 0.9), "C: caravan speed x0.9")
	for e in enemies:
		e.queue_free()
	await wait(3.0)

	print("--- Automatic triggers")
	dm._fired.clear()
	dm._last_resolved_time = -1.0e9
	dm.game_time = 0.0
	dm.check_interval = 0.1
	dm.min_gap = 1.0
	dm.salt_min_time = 0.5
	dm.mosque_gap = 0.0
	dm.mosque_chance = 1.0
	dm.auto_triggers_enabled = true
	gd.salt = 0
	econ.price_index = 1.0
	await wait(0.25)
	check(not dm.is_active(), "salt famine waits for game time")
	await wait(0.5)
	check(dm.is_active() and dm.get_active().id == "salt_famine", "salt famine auto-triggers (salt low + time)")
	check(paused, "auto trigger pauses via dialog")
	dm.choose(1)
	am.current_age = am.AGES.MALI_ASCENDANCY
	await wait(0.5)
	check(not dm.is_active(), "cooldown: nothing within min_gap")
	await wait(0.8)
	check(dm.is_active() and dm.get_active().id == "tuareg_negotiation", "tuareg auto-triggers after cooldown (Age II)")
	dm.choose(2)
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	econ.price_index = 2.0
	await wait(1.3)
	check(dm.is_active() and dm.get_active().id == "inflation_debate", "inflation auto-triggers (price index)")
	dm.choose(1)
	var mosque := Node2D.new()
	mosque.add_to_group("building_mosque")
	current_scene.add_child(mosque)
	await wait(1.3)
	check(dm.is_active() and dm.get_active().id == "mosque_crisis", "mosque crisis auto-triggers (mosque built)")
	dm.choose(2)
	await wait(1.5)
	check(not dm.is_active(), "each dilemma fires only once")
	check(dm.has_fired("salt_famine") and dm.has_fired("tuareg_negotiation") and dm.has_fired("inflation_debate") and dm.has_fired("mosque_crisis"), "all four fired")
	check(not paused, "game unpaused at end")
	am.current_age = am.AGES.SAND_CHIEFDOMS

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails else 0)
