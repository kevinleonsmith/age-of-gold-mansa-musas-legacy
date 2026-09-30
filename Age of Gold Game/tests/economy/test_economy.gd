extends SceneTree

var failures := 0
var collapse_count := 0

func _check(name: String, ok: bool, info := "") -> void:
	if not ok:
		failures += 1
	print("[%s] %s - %s" % ["PASS" if ok else "FAIL", name, info])

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var m := current_scene
	var gd := root.get_node("GameData")
	var em := root.get_node("EconomyManager")
	var tm := root.get_node("TechManager")
	var am := root.get_node("AgeManager")
	# Automatic dilemmas (e.g. Inflation Debate at index >= 1.75, Tuareg on the
	# first caravan) would pause the tree and freeze the time-based checks.
	root.get_node("DilemmaManager").auto_triggers_enabled = false
	root.get_node("VictoryManager").skirmish_conditions_enabled = false # ingot amounts here would trigger Economic Domination
	var old_sm := m.get_node_or_null("SpawnManager")
	if old_sm:
		old_sm.free()
	# The rival base spawns camp raiders and its wonder would end the game if freed.
	var rival_base = m.get_node_or_null("RivalBase")
	if rival_base:
		rival_base.free()
	var p: Node2D = m.get_node("Player")
	var enemies := m.get_node("Enemies")
	for e in enemies.get_children():
		e.free()
	em.rivals_collapsed.connect(func(): collapse_count += 1)
	# main.tscn already instances the EconomyPanel; use it rather than a duplicate.
	var panel = m.get_node("EconomyPanel")
	# Remove main's own trade posts so the test controls the route layout below.
	for tp in m.get_node("TradePosts").get_children():
		tp.free()

	# 1. Inflation from hoarding
	gd.ingots = 0
	gd.gold = 6000
	var cost0: int = gd.scaled_cost({"gold": 100})["gold"]
	await _wait(2.0)
	var pi: float = em.price_index
	var cost1: int = gd.scaled_cost({"gold": 100})["gold"]
	_check("price index rises with hoard", pi > 1.3, "index %.3f target %.2f" % [pi, em.get_target_price()])
	_check("modifier mirrors index", absf(gd.get_modifier("gold_price_mult") - pi) < 0.011, "mult %.3f" % gd.get_modifier("gold_price_mult"))
	_check("gold costs inflate", cost1 > cost0 and cost0 == 100, "100 gold -> %d -> %d" % [cost0, cost1])
	_check("state label", em.get_inflation_state() == ("Rising" if pi < 1.75 else "Crisis"), em.get_inflation_state())
	_check("panel meter follows", absf(panel.price_meter.value - gd.get_modifier("gold_price_mult")) < 0.02 and "x" in panel.price_label.text, panel.price_label.text)
	# Slow recovery once the hoard is gone
	gd.gold = 0
	var hi: float = em.price_index
	await _wait(1.0)
	var rec: float = hi - em.price_index
	_check("slow recovery ~0.01/s", rec > 0.005 and rec < 0.02, "dropped %.4f in 1s" % rec)
	tm.grant_tech("economic_stabilization")
	hi = em.price_index
	await _wait(1.0)
	rec = hi - em.price_index
	_check("stabilization doubles recovery", rec > 0.015 and rec < 0.03, "dropped %.4f in 1s" % rec)
	em.reset_inflation()
	_check("reset_inflation", em.price_index == 1.0 and gd.get_modifier("gold_price_mult") == 1.0 and em.get_inflation_state() == "Stable")

	# 2. Minting
	gd.gold = 250
	var ok: bool = em.mint_ingot()
	_check("mint ingot", ok and gd.gold == 150 and gd.ingots == 1, "gold %d ingots %d" % [gd.gold, gd.ingots])
	gd.gold = 50
	_check("mint needs 100 raw gold", not em.mint_ingot() and gd.ingots == 1 and gd.gold == 50)
	gd.ingots = 0

	# 3. distribute_gold
	am.current_age = am.AGES.GOLDEN_HAJJ
	em.price_index = 2.0
	em._publish_price()
	gd.gold = 1000
	var atk0: float = gd.get_modifier("ally_attack_mult")
	ok = em.distribute_gold(200)
	_check("distribute lowers inflation", ok and absf(em.price_index - 1.9) < 0.001 and gd.gold == 800 and absf(gd.get_modifier("gold_price_mult") - 1.9) < 0.001, "index %.3f gold %d" % [em.price_index, gd.gold])
	_check("distribute morale", absf(gd.get_modifier("ally_attack_mult") - atk0 * 1.05) < 0.0001, "mult %.3f" % gd.get_modifier("ally_attack_mult"))
	gd.gold = 100
	_check("distribute needs gold", not em.distribute_gold(200))
	Engine.time_scale = 20.0
	await _wait(31.0)
	Engine.time_scale = 1.0
	_check("morale undone after 30s", absf(gd.get_modifier("ally_attack_mult") - atk0) < 0.0001, "mult %.3f" % gd.get_modifier("ally_attack_mult"))
	em.reset_inflation()

	# 4. SpawnManager
	var sm = load("res://systems/SpawnManager.gd").new()
	sm.name = "TestSpawner"
	sm.spawn_interval = 0.5
	sm.max_enemies = 50
	m.add_child(sm)
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)
	await _wait(1.2)
	_check("spawn paused at mult 0", enemies.get_child_count() == 0, "enemies %d" % enemies.get_child_count())
	gd.set_modifier("enemy_spawn_rate_mult", 1.0)
	await _wait(1.1)
	var n1: int = enemies.get_child_count()
	for e in enemies.get_children():
		e.free()
	gd.set_modifier("enemy_spawn_rate_mult", 2.0)
	await _wait(1.1)
	var n2: int = enemies.get_child_count()
	_check("spawn rate mult", n1 == 2 and n2 == 4, "x1: %d in 1.1s, x2: %d in 1.1s" % [n1, n2])
	gd.set_modifier("enemy_spawn_rate_mult", 1.0)
	for e in enemies.get_children():
		e.free()
	sm.max_enemies = 2
	await _wait(2.0)
	_check("max_enemies cap", enemies.get_child_count() == 2, "enemies %d" % enemies.get_child_count())
	for e in enemies.get_children():
		e.free()
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)

	# 5. Caravans
	var post_scene: PackedScene = load("res://systems/TradePost.tscn")
	var near = post_scene.instantiate()
	near.post_name = "Walata"
	near.trade_good = "gold"
	near.position = p.global_position + Vector2(200, 0)
	m.add_child(near)
	var far = post_scene.instantiate()
	far.post_name = "Taghaza"
	far.trade_good = "salt"
	far.position = p.global_position + Vector2(400, 0)
	m.add_child(far)
	_check("trade posts grouped", get_nodes_in_group("trade_posts").size() == 2 and far.get_node("Label").text == "Taghaza (Salt)", far.get_node("Label").text)

	gd.set_modifier("caravan_speed_mult", 4.0)
	gd.gold = 0
	gd.salt = 0
	var c = load("res://entities/Caravan.tscn").instantiate()
	c.position = p.global_position
	m.add_child(c)
	_check("caravan groups/stats", c.is_in_group("allies") and c.is_in_group("caravans") and c.max_health == 80.0 and c.attack_damage == 0.0 and c.get_script().get_global_name() == "Caravan", "hp %s" % c.max_health)
	_check("caravan heads to farthest post", c.destination == far, str(c.destination.post_name if c.destination else "null"))
	_check("caravan speed mult", absf(c.get_speed() - 360.0) < 0.01, "speed %.1f" % c.get_speed())
	var delivered := []
	c.cargo_delivered.connect(func(g, s): delivered.append([g, s, c.global_position]))
	var loaded_seen := [false]
	c.cargo_loaded.connect(func(_g, _s): loaded_seen[0] = c.has_cargo())
	var t := 0.0
	while delivered.is_empty() and t < 6.0:
		await _wait(0.1)
		t += 0.1
	_check("caravan round trip pays out", delivered.size() == 1 and delivered[0][0] == 40 and delivered[0][1] == 20 and loaded_seen[0], "%s after %.1fs" % [str(delivered), t])
	_check("caravan returned to spawn home", delivered.size() == 1 and delivered[0][2].distance_to(c.spawn_point) < 1.0, "home %s spawn %s" % [str(delivered[0][2]) if delivered.size() else "-", str(c.spawn_point)])
	_check("payout reached GameData", gd.salt == 20 and gd.gold >= 40, "gold %d salt %d" % [gd.gold, gd.salt])
	_check("caravan repeats", c.state == c.State.TO_POST and not c.has_cargo())
	# Cargo mult on the next trip
	gd.set_modifier("caravan_cargo_mult", 1.5)
	t = 0.0
	while delivered.size() < 2 and t < 6.0:
		await _wait(0.1)
		t += 0.1
	_check("caravan_cargo_mult", delivered.size() == 2 and delivered[1][0] == 60 and delivered[1][1] == 30, str(delivered))
	gd.set_modifier("caravan_cargo_mult", 1.0)
	# Damage taken mult
	gd.set_modifier("caravan_damage_taken_mult", 2.0)
	c.take_damage(10.0)
	_check("caravan_damage_taken_mult", absf(c.health - 60.0) < 0.01, "hp %.1f" % c.health)
	gd.set_modifier("caravan_damage_taken_mult", 1.0)
	c.queue_free()

	# Outpost as home: long route (outpost -> Taghaza = 900 px > 800) doubles gold.
	var outpost := Node2D.new()
	outpost.position = p.global_position + Vector2(-500, 0)
	outpost.add_to_group("building_outpost")
	m.add_child(outpost)
	var c2 = load("res://entities/Caravan.tscn").instantiate()
	c2.position = p.global_position
	m.add_child(c2)
	_check("outpost used as home", c2.home_position.distance_to(outpost.position) < 0.1, str(c2.home_position))
	_check("long route cargo x2", c2.compute_cargo(900.0, far) == {"gold": 180, "salt": 90} and c2.compute_cargo(500.0, near) == {"gold": 50, "salt": 0}, str(c2.compute_cargo(900.0, far)))
	var d2 := []
	c2.cargo_delivered.connect(func(g, s): d2.append([g, s, c2.global_position]))
	t = 0.0
	while d2.is_empty() and t < 8.0:
		await _wait(0.1)
		t += 0.1
	_check("outpost round trip", d2.size() == 1 and d2[0][0] == int(round(outpost.position.distance_to(far.position) / 10.0 * 2.0)) and outpost.position.distance_to(far.position) > 800.0 and d2[0][2].distance_to(outpost.position) < 1.0, str(d2))
	c2.queue_free()
	gd.set_modifier("caravan_speed_mult", 1.0)

	# 6. Panel buttons
	gd.gold = 1000
	gd.ingots = 0
	panel.refresh()
	panel.mint_button.pressed.emit()
	_check("panel mint", gd.ingots == 1 and gd.gold == 900, "gold %d ingots %d" % [gd.gold, gd.ingots])
	var caravans_before: int = get_nodes_in_group("caravans").size()
	await process_frame
	caravans_before = get_nodes_in_group("caravans").size()
	em.price_index = 1.5
	em._publish_price()
	_check("panel caravan cost scaled", "90 Gold" in panel.caravan_button.text, panel.caravan_button.text)
	gd.gold = 1000
	var spawn_at := p.global_position
	panel.caravan_button.pressed.emit()
	await process_frame
	var cars: Array = get_nodes_in_group("caravans")
	_check("panel send caravan", cars.size() == caravans_before + 1 and gd.gold == 910 and cars[-1].spawn_point.distance_to(spawn_at) < 1.0, "caravans %d (before %d) gold %d at %s player %s" % [cars.size(), caravans_before, gd.gold, str(cars[-1].spawn_point) if cars.size() else "-", str(spawn_at)])
	for cv in cars:
		cv.queue_free()
	em.reset_inflation()
	gd.gold = 1000
	panel.distribute_button.pressed.emit()
	_check("panel distribute", gd.gold == 800, "gold %d" % gd.gold)
	_check("sell hidden without bazaar", not panel.sell_button.visible)
	tm.grant_tech("manuscript_bazaar")
	gd.manuscripts = 1
	_check("sell visible with bazaar", panel.sell_button.visible and not panel.sell_button.disabled, panel.sell_button.text)
	panel.sell_button.pressed.emit()
	_check("panel sell manuscript", gd.manuscripts == 0 and gd.gold == 1000 and panel.sell_button.disabled, "gold %d ms %d '%s'" % [gd.gold, gd.manuscripts, panel.sell_button.text])
	gd.gold = 10
	_check("disabled with reason", panel.mint_button.disabled and "need" in panel.mint_button.text and panel.caravan_button.disabled and panel.distribute_button.disabled, "%s | %s | %s" % [panel.mint_button.text, panel.caravan_button.text, panel.distribute_button.text])

	# 7. Rival drain + collapse
	gd.gold = 0
	gd.ingots = 100
	em.rival_gold = 5000.0
	var r0: float = em.rival_gold
	await _wait(1.0)
	var d1: float = r0 - em.rival_gold
	_check("rival drain with ingots (~10/s)", d1 > 8.5 and d1 < 11.5, "drained %.2f" % d1)
	tm.grant_tech("hyperinflation")
	r0 = em.rival_gold
	await _wait(1.0)
	var d3: float = r0 - em.rival_gold
	_check("hyperinflation 3x drain", d3 > 26.0 and d3 < 34.0, "drained %.2f" % d3)
	gd.set_modifier("enemy_spawn_rate_mult", 4.0)
	em.drain_rival_gold(em.rival_gold - 20.0)
	t = 0.0
	while collapse_count == 0 and t < 3.0:
		await _wait(0.1)
		t += 0.1
	_check("rivals collapse emitted", collapse_count == 1 and em.is_rivals_collapsed(), "after %.1fs" % t)
	em.drain_rival_gold(100.0)
	await _wait(0.5)
	_check("collapse emitted once", collapse_count == 1)
	_check("banner shown", panel.banner.visible and "collapse" in panel.banner.text)
	for e in enemies.get_children():
		e.free()
	await _wait(1.0)
	_check("spawning stops after collapse", sm.stopped and enemies.get_child_count() == 0, "enemies %d" % enemies.get_child_count())
	_check("panel shows bankrupt", "bankrupt" in panel.rival_label.text, panel.rival_label.text)

	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAIL", failures])
	quit()
