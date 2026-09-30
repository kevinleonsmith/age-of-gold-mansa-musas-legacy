extends SceneTree

var _fails := 0
var _spot := 0
var menu
var player: Node2D

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)

# Places a building via BuildMenu at a fresh spot (moving the player next to it).
func build(type: String) -> Node:
	var gd = root.get_node("GameData")
	var saved := {"gold": gd.gold, "salt": gd.salt, "manuscripts": gd.manuscripts, "ingots": gd.ingots}
	gd.gold = 100000
	gd.salt = 100000
	_spot += 1
	var pos := Vector2(1500 + (_spot % 5) * 300, 1500 + (_spot / 5) * 300)
	player.global_position = pos + Vector2(0, 150)
	var b = menu.place_building(type, pos)
	for key in saved:
		gd.set(key, saved[key])
	return b

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gd = root.get_node("GameData")
	var am = root.get_node("AgeManager")
	# EconomyManager drives inflation from gold held; pin prices for exact checks.
	var em = root.get_node_or_null("EconomyManager")
	if em:
		em.set_process(false)
		em.set_physics_process(false)
	gd.set_modifier("gold_price_mult", 1.0)
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	await process_frame
	var sm = current_scene.get_node_or_null("SpawnManager")
	if sm:
		sm.free()
	menu = current_scene.get_node_or_null("BuildMenu")
	if menu == null:
		menu = load("res://ui/BuildMenu.tscn").instantiate()
		current_scene.add_child(menu)
	player = get_first_node_in_group("player")
	await process_frame
	var ui = current_scene.get_node("GameUI")
	var advance: Button = ui.get_node("%AdvanceAgeButton")
	# Unit training buttons live in UnitMenu (instanced here until main.tscn has it).
	var units = current_scene.get_node_or_null("UnitMenu")
	if units == null:
		units = load("res://ui/UnitMenu.tscn").instantiate()
		current_scene.add_child(units)
	var griot: Button = units.get_button("griot_bard")
	var lancer: Button = units.get_button("camel_lancer")
	var health: Label = ui.get_node("%HealthLabel")
	var age_label: Label = ui.get_node("%AgeLabel")
	print("AgeLabel: ", age_label.text, " | Advance: ", advance.text, " | Griot: ", griot.text, " | Health: ", health.text, " visible=", health.is_visible_in_tree())

	gd.gold = 0
	gd.manuscripts = 0
	check(am.current_age == am.AGES.SAND_CHIEFDOMS, "starts in Sand Chiefdoms")
	check(gd.income_per_second == 1, "income 1 in Age I")
	check(advance.disabled, "advance disabled at 0 gold")
	check(lancer.disabled, "lancer disabled at 0 gold")
	check(griot.disabled, "griot locked in Age I")
	check(health.text.begins_with("HP: "), "health label shows HP: " + health.text)

	gd.gold = 500
	check(advance.disabled, "advance disabled at 500 gold without buildings")
	check("needs 5 more houses" in advance.text, "advance text shows requirement: " + advance.text)
	check("1 more mosque" in advance.tooltip_text, "advance tooltip lists mosque: " + advance.tooltip_text.replace("\n", " "))
	for i in 5:
		check(build("house") != null, "built house %d via BuildMenu" % (i + 1))
	check(build("mosque") != null, "built mosque via BuildMenu")
	await process_frame
	var base_income: int = gd.income_per_second
	check(base_income == 6, "income 1 + 5 houses = 6 (%d)" % base_income)
	gd.gold = 500
	check(not advance.disabled, "advance enabled at 500 gold with 5 houses + 1 mosque")
	check(not lancer.disabled, "lancer enabled at 500 gold")
	advance.pressed.emit()
	check(am.current_age == am.AGES.MALI_ASCENDANCY, "advanced to Mali Ascendancy")
	check(gd.gold == 0, "500 gold deducted (gold=%d)" % gd.gold)
	check(gd.income_per_second == base_income + 1, "income raised by 1 (%d)" % gd.income_per_second)
	var ann: Label = ui.get_node("%AgeAnnouncement")
	check(ann.visible and ann.text == "The Mali Ascendancy begins!", "announcement: " + ann.text)
	print("AgeLabel: ", age_label.text, " | Advance: ", advance.text)

	check(griot.disabled, "griot disabled when unaffordable in Age II")
	gd.gold = 100
	gd.manuscripts = 1
	check(not griot.disabled, "griot enabled with 100 gold + 1 manuscript")
	var before := get_nodes_in_group("allies").size()
	griot.pressed.emit()
	await process_frame
	check(gd.gold == 25 and gd.manuscripts == 0, "griot cost 75 gold + 1 manuscript (gold=%d ms=%d)" % [gd.gold, gd.manuscripts])
	var found := false
	for c in current_scene.get_children():
		if c.scene_file_path == "res://entities/GriotBard.tscn":
			found = true
	check(found, "GriotBard node added to scene (allies %d -> %d)" % [before, get_nodes_in_group("allies").size()])

	gd.gold = 1000
	gd.manuscripts = 4
	check(advance.disabled, "advance to Golden Hajj disabled with 4 manuscripts")
	check(not am.advance_age(), "advance_age() returns false with 4 manuscripts")
	gd.manuscripts = 5
	check(advance.disabled, "advance to Golden Hajj needs 3 mosques + 2 gold mines: " + advance.text)
	check(build("mosque") != null and build("mosque") != null, "built 2 more mosques")
	var mine = load("res://systems/ResourceNode.tscn").instantiate()
	mine.position = Vector2(-500, -500)
	current_scene.add_child(mine)
	await process_frame
	gd.gold = 1000
	gd.manuscripts = 5
	check(not advance.disabled, "advance enabled with 1000 gold + 5 manuscripts + requirements: " + advance.text)
	advance.pressed.emit()
	check(am.current_age == am.AGES.GOLDEN_HAJJ, "advanced to Golden Hajj")
	check(gd.gold == 0 and gd.manuscripts == 0, "Golden Hajj cost deducted")
	check(gd.income_per_second == base_income + 3, "income raised to age III level (%d)" % gd.income_per_second)
	gd.gold = 99999
	gd.manuscripts = 99
	check(am.is_max_age() and advance.disabled, "advance disabled at max age")
	check(advance.text == "Final Age reached", "advance text: " + advance.text)
	check(not am.advance_age(), "advance_age() false at max age")
	print("AgeLabel: ", age_label.text)
	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails else 0)
