extends SceneTree
# Campaign test: Mission 1 securing, Mission 2 escort / outposts / sandstorm /
# defeat, Mission 7 market strikes / charity / mosques / red zones / Mecca.
# Every mission is launched through GameSession.start like the real menu.
var failures := 0
var won := []
var lost := []
var vm
var gd
var em

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
	print("PASS: " if cond else "FAIL: ", msg)

func wait_frames(n: int) -> void:
	for i in n:
		await process_frame

func wait_until(cond: Callable, seconds: float) -> bool:
	for i in int(seconds * 60.0):
		if cond.call():
			return true
		await process_frame
	return cond.call()

func start(path: String):
	won.clear()
	lost.clear()
	root.get_node("GameSession").start(path)
	await wait_frames(3)
	return current_scene

func clear_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		e.queue_free()

func enemy_count() -> int:
	var n := 0
	for e in get_nodes_in_group("enemies"):
		if not e.is_queued_for_deletion():
			n += 1
	return n

func toast_has(fragment: String) -> bool:
	var t = get_first_node_in_group("toasts")
	for text in t.get_toast_texts():
		if fragment in text:
			return true
	return false

func _initialize() -> void:
	await process_frame  # autoloads enter the tree after _initialize
	create_timer(200.0, true, false, true).timeout.connect(func():
		print("FAIL: watchdog timeout")
		print("RESULT: FAILED (watchdog)")
		quit(1))
	vm = root.get_node("VictoryManager")
	gd = root.get_node("GameData")
	em = root.get_node("EconomyManager")
	vm.game_won.connect(func(id, _t, _x): won.append(id))
	vm.game_lost.connect(func(id, _t, _x): lost.append(id))
	await _test_loading()
	await _test_mission1()
	await _test_mission2_escort()
	await _test_mission2_sandstorm()
	await _test_mission2_defeat()
	await _test_mission7()
	await _test_mission7_defeats()
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)

# --- Loading ------------------------------------------------------------------

func _test_loading() -> void:
	for path in ["res://missions/Mission1.tscn", "res://missions/Mission2.tscn", "res://missions/Mission7.tscn"]:
		var m = await start(path)
		var ok: bool = m != null and m.scene_file_path == path
		check(ok, "%s loads via GameSession.start" % path)
		check(ok and vm.objectives.size() >= 2 and not vm.skirmish_conditions_enabled and not root.get_node("DilemmaManager").auto_triggers_enabled,
			"%s sets objectives %s" % [path.get_file(), str(vm.objectives.map(func(o): return o["text"]))])
		check(ok and get_first_node_in_group("toasts") != null and m.get_node_or_null("BuildMenu") != null and m.get_node_or_null("EconomyPanel") != null,
			"%s has HUD instances" % path.get_file())

# --- Mission 1 ------------------------------------------------------------------

func _test_mission1() -> void:
	var m = await start("res://missions/Mission1.tscn")
	m.waves_enabled = false
	check(enemy_count() >= 6, "M1 raiders guard the mines (%d)" % enemy_count())
	var p = m.get_node("Player")
	var mine: Dictionary = m.mines[0]
	# Clear mine 1's guards without harvesting: not secured yet.
	var other: Dictionary = m.mines[1]
	for e in get_nodes_in_group("enemies"):
		if e.global_position.distance_to(other["pos"]) < 300.0:
			e.queue_free()
	await wait_frames(2)
	m.update_mines()
	check(not m.is_mine_secured(1), "M1 cleared but unharvested mine is not secured")
	# Harvest mine 0 while its guards stand nearby: harvested, not secured.
	p.global_position = mine["pos"]
	await wait_until(func(): return mine["harvested"] or (is_instance_valid(mine["node"]) and mine["node"].quantity < m.MINE_QUANTITY), 3.0)
	m.update_mines()
	check(mine["harvested"] and not m.is_mine_secured(0), "M1 harvested mine with raiders within 250 px is not secured")
	for e in get_nodes_in_group("enemies"):
		if e.global_position.distance_to(mine["pos"]) < 400.0:
			e.queue_free()
	await wait_frames(2)
	m.update_mines()
	check(m.is_mine_secured(0) and m.gold_mines_secured == 1, "M1 harvested + cleared mine is secured")
	check("1/3" in vm.objectives[0]["text"], "M1 objective text: %s" % vm.objectives[0]["text"])
	# Waves spawn on the contested mines.
	var before := enemy_count()
	m.send_wave()
	check(enemy_count() > before and m.waves_sent == 1, "M1 raider wave spawns (%d -> %d)" % [before, enemy_count()])

# --- Mission 2 ------------------------------------------------------------------

func _teleport_to_end(c) -> void:
	c.wait_for_player_distance = 0.0
	c.route_index = c.route_points.size() - 1
	c.global_position = c.route_points[-1] + Vector2(-20, 0)

func _test_mission2_escort() -> void:
	var m = await start("res://missions/Mission2.tscn")
	m.scripted_dilemmas = false
	m.ambushes_enabled = false
	var cars: Array = m.active_caravans()
	check(cars.size() == 3, "M2 convoy of 3 caravans")
	check(cars.all(func(c): return c.one_way and c.is_in_group("camel") and c.is_in_group("caravans")), "M2 caravans are one-way camel units")
	var c0 = cars[0]
	# Waits for the escort when the Mansa is far away.
	m.get_node("Player").global_position = Vector2(-1500, 1500)
	await wait_frames(10)
	check(c0.is_waiting, "M2 caravan waits for a distant escort")
	m.get_node("Player").global_position = Vector2(160, 120)
	var arrivals := []
	c0.arrived.connect(func(): arrivals.append(true))
	_teleport_to_end(c0)
	var ok: bool = await wait_until(func(): return m.delivered == 1, 2.0)
	check(ok and arrivals.size() == 1, "M2 one-way caravan arrives and counts (delivered %d)" % m.delivered)
	check("1/3" in vm.objectives[0]["text"], "M2 caravan objective: %s" % vm.objectives[0]["text"])
	check(vm.is_objective_done("walata") and m.lancers_unlocked and get_nodes_in_group("camel").size() >= 4, "M2 Walata reached in time: Camel Lancers unlocked")
	check(toast_has("Camel Lancers"), "M2 Camel Lancer toast shown")
	# Outposts via the build menu.
	gd.gold = 3000
	gd.salt = 500
	var p = m.get_node("Player")
	p.global_position = Vector2(500, 500)
	var bm = m.get_node("BuildMenu")
	var o1 = bm.place_building("outpost", Vector2(650, 500))
	var o2 = bm.place_building("outpost", Vector2(350, 560))
	check(o1 != null and o2 != null, "M2 outposts placed")
	ok = await wait_until(func(): return vm.is_objective_done("outposts"), 1.0)
	check(ok, "M2 outposts objective complete (%s)" % vm.objectives[1]["text"])
	check(won.is_empty(), "M2 not won before 3 deliveries")
	for c in m.active_caravans():
		_teleport_to_end(c)
	ok = await wait_until(func(): return not won.is_empty(), 3.0)
	check(ok and won[0] == "mission" and m.delivered == 3, "M2 victory after 3 caravans + 2 outposts (%s)" % str(won))

func _test_mission2_sandstorm() -> void:
	var m = await start("res://missions/Mission2.tscn")
	m.scripted_dilemmas = false
	m.ambushes_enabled = false
	var storm = m.get_node("Sandstorm")
	check(storm.is_in_group("sandstorm") and not storm.active, "M2 sandstorm idle at start")
	m.mission_time = m.SANDSTORM_TIME - 0.5
	var ok: bool = await wait_until(func(): return storm.active, 1.5)
	check(ok and absf(gd.get_modifier("sandstorm_slow_mult") - 0.4) < 0.001, "M2 sandstorm starts at the scripted time (slow %.2f)" % gd.get_modifier("sandstorm_slow_mult"))
	check(toast_has("Sandstorm"), "M2 sandstorm toast")
	# Player slowed.
	var p = m.get_node("Player")
	var p0: Vector2 = p.global_position
	Input.action_press("move_right")
	await wait_frames(30)
	Input.action_release("move_right")
	var moved: float = p.global_position.x - p0.x
	check(moved > 20.0 and moved < 300.0 * 0.5 * 0.6, "M2 player slowed in sandstorm (%.1f px in 0.5 s)" % moved)
	# EnemyAI slowed.
	var e = m.spawn_enemy(Vector2(1200, -900))
	await wait_frames(1)
	e.current_state = e.STATE.PATROL
	e.target_position = e.global_position + Vector2(600, 0)
	await physics_frame
	await physics_frame
	var ev: float = e.velocity.length()
	check(ev > 0.0 and ev < e.patrol_speed * 0.5, "M2 EnemyAI slowed in sandstorm (%.1f vs %.1f)" % [ev, e.patrol_speed])
	e.queue_free()
	# Caravans are camels: not slowed.
	var c = m.active_caravans()[0]
	c.wait_for_player_distance = 0.0
	var c0: Vector2 = c.global_position
	await wait_frames(30)
	var cm: float = c.global_position.distance_to(c0)
	check(cm > 90.0 * 0.5 * 0.85, "M2 caravan keeps its pace in the storm (%.1f px in 0.5 s)" % cm)
	storm.stop()
	check(not storm.active and absf(gd.get_modifier("sandstorm_slow_mult") - 1.0) < 0.001, "M2 sandstorm stop restores speed")
	# Duration timer ends it too.
	storm.start(0.3)
	ok = await wait_until(func(): return not storm.active, 1.5)
	check(ok and absf(gd.get_modifier("sandstorm_slow_mult") - 1.0) < 0.001, "M2 sandstorm ends after its duration")

func _test_mission2_defeat() -> void:
	var m = await start("res://missions/Mission2.tscn")
	m.scripted_dilemmas = false
	m.ambushes_enabled = false
	m.reserve_caravans = 1
	var cars: Array = m.active_caravans()
	cars[0].take_damage(10000.0)
	await wait_frames(2)
	check(m.lost == 1 and m.reserve_caravans == 0 and lost.is_empty(), "M2 lost caravan uses a reserve")
	var ok: bool = await wait_until(func(): return m.caravans.size() == 4, m.REPLACEMENT_DELAY + 1.0)
	check(ok, "M2 replacement caravan leaves Taghaza")
	for c in m.active_caravans():
		c.take_damage(10000.0)
	ok = await wait_until(func(): return not lost.is_empty(), 1.0)
	check(ok and lost[0] == "caravans_lost", "M2 losing all caravans is a defeat (%s)" % str(lost))

# --- Mission 7 ------------------------------------------------------------------

func _test_mission7() -> void:
	var m = await start("res://missions/Mission7.tscn")
	m.scripted_dilemmas = false
	var age_mgr = root.get_node("AgeManager")
	check(age_mgr.current_age == age_mgr.AGES.GOLDEN_HAJJ and gd.gold >= 4000, "M7 starts in the Golden Hajj with a big treasury (%d)" % gd.gold)
	var c = m.caravan
	check(c != null and c.one_way and c.max_health >= 500.0 and c.route_points.size() == 6, "M7 Hajj caravan on a 6-point route")
	check(m.city_stops.values() == ["Walata", "Cairo", "Mecca"], "M7 city stops %s" % str(m.city_stops))
	# Market strike.
	em.price_index = 2.0
	m.arrive_at_city("Cairo", false)
	check(m.strikes == 1 and toast_has("Crashed Cairo's gold market"), "M7 arriving with a high price index is a strike")
	em.price_index = 1.0
	m.arrive_at_city("Walata", false)
	check(m.strikes == 1, "M7 green arrival: no strike")
	# Charity through the Economy panel lowers the index and is counted.
	em.price_index = 2.0
	var panel = m.get_node("EconomyPanel")
	var before: float = em.price_index
	panel.distribute_button.pressed.emit()
	check(em.price_index < before - 0.05 and m.total_distributed == 200, "M7 distribution lowers the index (%.2f -> %.2f), counted %d" % [before, em.price_index, m.total_distributed])
	# Overspending draws bandits.
	var e0 := enemy_count()
	for i in 3:
		m.distribute(200)
	check(m.overspend_raids == 1 and enemy_count() > e0, "M7 overspending triggers a bandit raid (%d -> %d)" % [e0, enemy_count()])
	clear_enemies()
	# Mosques near / far from the route.
	gd.gold = 20000
	gd.salt = 500
	var p = m.get_node("Player")
	var bm = m.get_node("BuildMenu")
	var markers: Array = m.get_node("Route").get_children()
	p.global_position = markers[0].global_position
	var far = bm.place_building("mosque", markers[0].global_position + Vector2(-100, -360))
	check(far != null and m.distance_to_route(far.global_position) > m.MOSQUE_ROUTE_RADIUS and m.count_mosques_near_route() == 0, "M7 mosque far from the route doesn't count")
	var placed := 0
	for i in 4:
		p.global_position = markers[i + 1].global_position
		if bm.place_building("mosque", markers[i + 1].global_position + Vector2(0, -150)) != null:
			placed += 1
	check(placed == 4 and m.count_mosques_near_route() == 4, "M7 mosques near the route count (%d)" % m.count_mosques_near_route())
	await wait_frames(20)
	check(vm.is_objective_done("mosques"), "M7 mosque objective complete")
	# Red zone bandits.
	clear_enemies()
	await wait_frames(1)
	m.red_zone_interval = 0.4
	c.rest(3.0)
	c.global_position = m.RED_ZONES[0][0]
	var ok: bool = await wait_until(func(): return m.red_zone_raids >= 2, 1.5)
	check(ok and m.in_red_zone and enemy_count() >= 2, "M7 red zone spawns Mamluk bandits (raids %d, enemies %d)" % [m.red_zone_raids, enemy_count()])
	clear_enemies()
	# Reach Mecca.
	gd.gold = 50
	em.price_index = 1.0
	c.set("_rest_left", 0.0)
	_teleport_to_end(c)
	c.global_position = c.route_points[-1] + Vector2(-20, 0)
	ok = await wait_until(func(): return not won.is_empty(), 3.0)
	check(ok and won[0] == "mission" and m.at_mecca, "M7 reaching Mecca is a victory (%s, strikes %d)" % [str(won), m.strikes])
	check(toast_has("Cairo's gold price fell"), "M7 historical note toast")

func _test_mission7_defeats() -> void:
	var m = await start("res://missions/Mission7.tscn")
	m.scripted_dilemmas = false
	for city in ["Walata", "Cairo", "Mecca"]:
		em.price_index = 2.0
		m.arrive_at_city(city, false)
	check(m.strikes == 3 and lost.size() == 1 and lost[0] == "markets_crashed", "M7 three market crashes is a defeat (%s)" % str(lost))
	m = await start("res://missions/Mission7.tscn")
	m.scripted_dilemmas = false
	var t := 0
	while lost.is_empty() and t < 20:
		m.distribute(200)
		t += 1
	check(lost.size() == 1 and lost[0] == "treasury_squandered" and m.total_distributed > m.DISTRIBUTION_CAP, "M7 exceeding the charity cap is a defeat (%d given)" % m.total_distributed)
	m = await start("res://missions/Mission7.tscn")
	m.caravan.take_damage(100000.0)
	await wait_frames(2)
	check(lost.size() == 1 and lost[0] == "caravan_destroyed", "M7 destroyed caravan is a defeat")
