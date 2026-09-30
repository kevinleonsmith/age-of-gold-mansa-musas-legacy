extends SceneTree

var failures := 0

func _check(name: String, ok: bool, info := "") -> void:
	if not ok:
		failures += 1
	print("[%s] %s %s" % ["PASS" if ok else "FAIL", name, info])

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var m := current_scene
	var gd := root.get_node("GameData")
	var tm := root.get_node("TechManager")
	var am := root.get_node("AgeManager")
	# Reaching Age II would auto-trigger the Tuareg dilemma, which pauses the tree.
	root.get_node("DilemmaManager").auto_triggers_enabled = false
	var sm := m.get_node_or_null("SpawnManager")
	if sm:
		sm.queue_free()

	# Panel
	# main.tscn already instances the TechPanel; test that one (no duplicate).
	var tp = m.get_node("TechPanel")
	await process_frame
	_check("panel hidden by default", not tp.is_open())
	var ev := InputEventAction.new()
	ev.action = "toggle_tech"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check("T toggles panel open", tp.is_open())
	tp.toggle_button.pressed.emit()
	_check("button toggles panel closed", not tp.is_open())
	tp.toggle()

	_check("hidden tech not listed", tm.get_all_techs().all(func(t): return t["id"] != "economic_stabilization"))
	_check("economic_stabilization exists, not researchable", not tm.get_tech("economic_stabilization").is_empty() and not tm.can_research("economic_stabilization"))

	# Age locks
	gd.gold = 5000
	gd.salt = 5000
	gd.manuscripts = 20
	await process_frame
	_check("age II tech locked in age I", not tm.can_research("poisoned_spears"))
	_check("age III tech locked in age I", not tm.can_research("salt_monopoly"))
	_check("start_research refuses locked", not tm.start_research("poisoned_spears"))
	_check("panel shows Locked", tp.rows["poisoned_spears"]["button"].disabled and tp.rows["poisoned_spears"]["button"].text == "Locked")
	_check("panel research button enabled", not tp.rows["mud_architecture"]["button"].disabled)

	# Research mud_architecture with shortened time
	gd.set_modifier("research_time_mult", 1.0 / 25.0)  # 25 s -> 1 s
	gd.gold = 1000
	var g0: int = gd.gold
	tp.rows["mud_architecture"]["button"].pressed.emit()
	await process_frame
	_check("research started via panel", tm.get_current_research() == "mud_architecture")
	_check("gold spent", g0 - gd.gold == 200, "spent=%d" % (g0 - gd.gold))
	_check("one research at a time", not tm.can_research("camel_saddlecraft") and not tm.start_research("camel_saddlecraft"))
	_check("other rows disabled while researching", tp.rows["camel_saddlecraft"]["button"].disabled)
	await _wait(0.5)
	var prog: float = tm.get_progress()
	_check("progress mid-way", prog > 0.3 and prog < 0.7, "p=%.2f" % prog)
	_check("panel progress bar", absf(tp.progress_bar.value - prog) < 0.1, "bar=%.2f" % tp.progress_bar.value)
	_check("not done at 0.5s", not tm.is_researched("mud_architecture"))
	await _wait(0.7)
	_check("done after ~1s", tm.is_researched("mud_architecture"))
	_check("building_hp_mult set", is_equal_approx(gd.get_modifier("building_hp_mult"), 1.15))
	await process_frame
	_check("panel shows ✓", tp.rows["mud_architecture"]["button"].text == "✓")
	_check("can't research twice", not tm.can_research("mud_architecture"))

	# Cancel refunds 50%
	gd.salt = 1000
	tm.start_research("camel_saddlecraft")
	_check("salt spent", gd.salt == 850)
	tp.cancel_button.pressed.emit()
	_check("cancel refunds 50%", gd.salt == 925 and tm.get_current_research() == "", "salt=%d" % gd.salt)

	# Mosque speed-up
	gd.set_modifier("research_time_mult", 1.0)
	var base: float = tm.get_research_time("camel_saddlecraft")
	var mosques := []
	for i in 5:
		var n := Node2D.new()
		n.add_to_group("building_mosque")
		m.add_child(n)
		mosques.append(n)
		if i == 0:
			_check("1 mosque: x0.8", is_equal_approx(tm.get_research_time("camel_saddlecraft"), base * 0.8))
	_check("5 mosques capped at 3: x0.512", is_equal_approx(tm.get_research_time("camel_saddlecraft"), base * 0.512), "t=%.2f" % tm.get_research_time("camel_saddlecraft"))
	for n in mosques:
		n.queue_free()
	await process_frame

	# Harvest multipliers
	var rn_scene: PackedScene = load("res://systems/ResourceNode.tscn")
	var rn = rn_scene.instantiate()
	rn.resource_type = 1  # SALT (class_name not usable from -s script before autoloads)
	rn.quantity = 1000
	rn.position = Vector2(-5000, -5000)
	m.add_child(rn)
	await process_frame
	var s0: int = gd.salt
	rn.harvest_once()
	_check("salt base yield 10", gd.salt - s0 == 10)
	tm.grant_tech("oral_histories")
	_check("grant_tech applies harvest_mult", tm.is_researched("oral_histories") and is_equal_approx(gd.get_modifier("harvest_mult"), 1.1))
	gd.set_modifier("salt_harvest_mult", 2.0)
	s0 = gd.salt
	rn.harvest_once()
	_check("salt yield x1.1 x2 = 22", gd.salt - s0 == 22, "got %d" % (gd.salt - s0))
	gd.set_modifier("salt_harvest_mult", 1.0)
	rn.resource_type = 2  # MANUSCRIPTS
	var m0: int = gd.manuscripts
	for i in 10:
		rn.harvest_once()
	_check("manuscripts x1.1 over 10 harvests = 11", gd.manuscripts - m0 == 11, "got %d" % (gd.manuscripts - m0))
	rn.queue_free()

	# Poisoned spears + salt monopoly via grant (age-independent)
	tm.grant_tech("poisoned_spears")
	tm.grant_tech("salt_monopoly")
	_check("poison_dps=3", is_equal_approx(gd.get_modifier("poison_dps", 0.0), 3.0))
	_check("enemy_hp_drain=1", is_equal_approx(gd.get_modifier("enemy_hp_drain", 0.0), 1.0))
	var e = load("res://entities/EnemyAI.tscn").instantiate()
	e.position = Vector2(-4000, -4000)
	m.add_child(e)
	e.set_physics_process(false)  # after add_child: _ready re-enables it
	await process_frame
	var hp0: float = e.health
	await _wait(1.0)
	var drained: float = hp0 - e.health
	_check("salt monopoly drains ~1 HP/s", drained > 0.7 and drained < 1.3, "drained=%.2f" % drained)
	var ally = load("res://entities/CamelLancer.tscn").instantiate()
	ally.position = e.position + Vector2(20, 0)
	m.add_child(ally)
	ally.set_physics_process(false)
	await process_frame
	_check("lancer hit lands", ally.try_attack(e))
	var hp1: float = e.health
	await _wait(1.0)
	var lost: float = hp1 - e.health
	_check("poison + drain ~4 HP/s", lost > 3.3 and lost < 4.7, "lost=%.2f" % lost)
	ally.queue_free()
	if is_instance_valid(e):
		e.queue_free()

	# Age unlock: I->II needs 5 houses + 1 mosque (counted by group) plus the cost.
	var reqs := []
	for i in 6:
		var b := Node2D.new()
		b.add_to_group("building_house" if i < 5 else "building_mosque")
		m.add_child(b)
		reqs.append(b)
	gd.gold = 5000
	_check("advance_age succeeds with requirements met", am.advance_age(), str(am.get_unmet_requirements()))
	for b in reqs:
		b.queue_free()
	await process_frame
	_check("age II tech researchable after advancing", tm.can_research("gold_standard"))
	_check("panel unlocks age II row", not tp.rows["gold_standard"]["button"].disabled)
	_check("age III still locked", not tm.can_research("sankore_curriculum"))

	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit()
