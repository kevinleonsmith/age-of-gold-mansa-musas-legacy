extends SceneTree

var _fails := 0
var gd
var am
var tm
var menu
var player: Node2D
var _spot := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

# Fresh free spot far from everything; moves the player next to it.
func next_spot() -> Vector2:
	_spot += 1
	var pos := Vector2(1500 + (_spot % 5) * 300, 1500 + (_spot / 5) * 300)
	player.global_position = pos + Vector2(0, 150)
	return pos

func give_plenty() -> void:
	gd.gold = 100000
	gd.salt = 100000
	gd.manuscripts = 1000
	gd.ingots = 1000

func spent(before: Dictionary, cost: Dictionary) -> bool:
	for key in ["gold", "salt", "manuscripts", "ingots"]:
		if gd.get_amount(key) != int(before[key]) - int(cost.get(key, 0)):
			print("   ", key, ": before=", before[key], " now=", gd.get_amount(key), " expected cost=", cost.get(key, 0))
			return false
	return true

func snapshot() -> Dictionary:
	return {"gold": gd.gold, "salt": gd.salt, "manuscripts": gd.manuscripts, "ingots": gd.ingots}

func place_checked(type: String, expected: Dictionary) -> Node:
	var pos := next_spot()
	var before := snapshot()
	var b = menu.place_building(type, pos)
	check(b != null, "placed %s" % type)
	check(spent(before, expected), "%s deducted %s" % [type, str(expected)])
	if b:
		check(b.is_in_group("buildings") and b.is_in_group("building_" + type), "%s in groups" % type)
		check(b.get_parent().name == "Buildings" and b.get_parent().get_parent() == current_scene, "%s under current_scene/Buildings" % type)
	return b

func _run() -> void:
	gd = root.get_node("GameData")
	am = root.get_node("AgeManager")
	tm = root.get_node("TechManager")
	# Reaching Age II auto-triggers the Tuareg dilemma, which pauses the tree
	# (freezing the market timer); events have their own test.
	root.get_node("DilemmaManager").auto_triggers_enabled = false
	root.get_node("VictoryManager").skirmish_conditions_enabled = false # ingot amounts here would trigger Economic Domination
	# EconomyManager drives gold_price_mult from gold held; pin prices for exact checks.
	var em = root.get_node_or_null("EconomyManager")
	if em:
		em.set_process(false)
		em.set_physics_process(false)
	gd.set_modifier("gold_price_mult", 1.0)
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var sm = current_scene.get_node_or_null("SpawnManager")
	if sm:
		sm.free()
	menu = current_scene.get_node_or_null("BuildMenu")
	if menu == null:
		menu = load("res://ui/BuildMenu.tscn").instantiate()
		current_scene.add_child(menu)
	await frames(2)
	player = get_first_node_in_group("player")
	var bd = load("res://buildings/BuildingData.gd")

	# --- Age locks & buttons ---
	gd.gold = 0
	gd.salt = 0
	await frames(1)
	var house_btn: Button = menu._buttons["house"]
	check(house_btn.disabled, "house button disabled at 0 gold: '%s'" % house_btn.text.replace("\n", " | "))
	give_plenty()
	await frames(1)
	check(not house_btn.disabled, "house button enabled with gold")
	check(menu._buttons["market"].disabled and not menu.can_build("market"), "market locked in Age I (%s)" % menu.get_block_reason("market"))
	check(menu.place_building("market", next_spot()) == null, "market placement refused in Age I")
	check(menu.place_building("great_mosque", next_spot()) == null, "great mosque refused in Age I")
	check(menu.place_building("salt_cathedral", next_spot()) == null, "salt cathedral refused in Age I")

	# --- Age requirements: I -> II ---
	gd.gold = 500
	await frames(1)
	check(not am.can_advance(), "cannot advance with 500 gold and no buildings")
	var unmet: PackedStringArray = am.get_unmet_requirements()
	check(unmet.size() == 2 and unmet[0] == "5 more houses" and unmet[1] == "1 more mosque", "unmet: %s" % str(unmet))

	# --- Costs & income ---
	give_plenty()
	var income0: int = gd.income_per_second
	var houses := []
	for i in 5:
		houses.append(place_checked("house", {"gold": 50}))
	check(gd.income_per_second == income0 + 5, "5 houses raise income by 5 (%d -> %d)" % [income0, gd.income_per_second])
	houses[4].take_damage(10)
	check(houses[4].health == 140.0, "house took damage (%.0f)" % houses[4].health)
	houses[4].take_damage(1000)
	check(gd.income_per_second == income0 + 4, "destroyed house lowers income (%d)" % gd.income_per_second)
	await frames(2)
	check(not is_instance_valid(houses[4]), "destroyed house freed")
	houses[4] = place_checked("house", {"gold": 50})
	var mosque = place_checked("mosque", {"gold": 150, "salt": 20})
	var outpost = place_checked("outpost", {"gold": 200, "salt": 100})
	check(get_nodes_in_group("building_outpost").size() == 1, "outpost in building_outpost group")
	check(am.get_unmet_requirements().is_empty(), "requirements met for Age II")

	# --- Invalid placement ---
	var before := snapshot()
	var near: Vector2 = mosque.global_position + Vector2(70, 0)
	player.global_position = mosque.global_position + Vector2(0, 150)
	check(not menu.is_valid_placement("house", near), "placement next to a mosque is invalid")
	check(menu.place_building("house", near) == null, "place_building refuses spot near another building")
	var far := next_spot()
	player.global_position = far + Vector2(600, 0)
	check(menu.place_building("house", far) == null, "place_building refuses spot >400 px from player")
	check(menu.place_building("house", player.global_position) == null, "place_building refuses spot on the player")
	check(spent(before, {}), "refused placements cost nothing")

	# --- Mosque manuscripts & healing ---
	mosque.manuscript_interval = 0.25
	var ms0: int = gd.manuscripts
	await frames(20)
	check(gd.manuscripts == ms0 + 1, "mosque produced a manuscript (%d -> %d)" % [ms0, gd.manuscripts])
	var lancer = load("res://entities/CamelLancer.tscn").instantiate()
	lancer.position = mosque.global_position + Vector2(0, 100)
	current_scene.add_child(lancer)
	await frames(1)
	lancer.set_physics_process(false)
	lancer.health = 50.0
	await frames(30)
	check(is_equal_approx(lancer.health, 50.0), "no healing without mansas_blessing (%.2f)" % lancer.health)
	tm.grant_tech("mansas_blessing")
	await frames(60)
	check(lancer.health > 52.0 and lancer.health < 54.0, "mansas_blessing heals ~3 HP/s (%.2f)" % lancer.health)
	lancer.queue_free()

	# --- Advance to Age II ---
	gd.gold = 500
	gd.salt = 0
	gd.manuscripts = 0
	var income_before: int = gd.income_per_second
	check(am.can_advance() and am.advance_age(), "advanced to Age II")
	check(gd.gold == 0, "age cost paid via spend (gold=%d)" % gd.gold)
	check(gd.income_per_second == income_before + 1, "age raise keeps house bonus (%d -> %d)" % [income_before, gd.income_per_second])

	# --- Age II buildings ---
	give_plenty()
	await frames(1)
	var market = place_checked("market", {"gold": 120})
	market.gold_interval = 0.25
	var g0: int = gd.gold
	await frames(20)
	check(gd.gold - g0 < 5, "market idle without gold_standard")
	tm.grant_tech("gold_standard")
	g0 = gd.gold
	await frames(20)
	check(gd.gold - g0 >= 5, "market +5 gold with gold_standard (%d)" % (gd.gold - g0))
	var gm = place_checked("great_mosque", {"gold": 1500, "manuscripts": 10})
	check(gm.max_health == 800.0 and gm.health == 800.0, "great mosque 800 HP")
	check(gm.manuscript_interval == 90.0 and not gm.heals_allies, "great mosque: manuscript every 90 s")
	await frames(1)
	check(menu._buttons["great_mosque"].disabled, "great mosque button disabled once built")
	check(menu.place_building("great_mosque", next_spot()) == null, "second great mosque refused")
	check(menu.place_building("salt_cathedral", next_spot()) == null, "salt cathedral still locked in Age II")

	# --- Age II -> III requirements ---
	# main.tscn ships two gold mines; remove one so the gold-mine requirement is
	# still exercised (one missing, then satisfied by the mine placed below).
	var mine2 = current_scene.get_node_or_null("Resources/GoldMine2")
	if mine2:
		mine2.free()
	check(am.count_gold_mines() == 1, "one gold mine left in main (%d)" % am.count_gold_mines())
	gd.gold = 1000
	gd.manuscripts = 5
	gd.salt = 0
	var u2: PackedStringArray = am.get_unmet_requirements()
	check(u2.size() == 2 and u2[0] == "2 more mosques" and u2[1] == "1 more gold mine", "Age III unmet: %s" % str(u2))
	check(not am.can_advance(), "cannot advance to Age III yet")
	give_plenty()
	place_checked("mosque", {"gold": 150, "salt": 20})
	place_checked("mosque", {"gold": 150, "salt": 20})
	var mine = load("res://systems/ResourceNode.tscn").instantiate()
	mine.position = Vector2(-500, -500)
	current_scene.add_child(mine)
	check(am.get_unmet_requirements().is_empty(), "Age III requirements met (%s)" % str(am.get_unmet_requirements()))
	check(am.advance_age(), "advanced to Age III")

	# --- Salt Cathedral ---
	give_plenty()
	var salt0: float = gd.get_modifier("salt_harvest_mult")
	var sc = place_checked("salt_cathedral", {"salt": 2000, "ingots": 5})
	check(is_equal_approx(gd.get_modifier("salt_harvest_mult"), salt0 * 2.0), "salt cathedral doubles salt harvest")
	check(menu.place_building("salt_cathedral", next_spot()) == null, "second salt cathedral refused")
	sc.take_damage(99999)
	check(is_equal_approx(gd.get_modifier("salt_harvest_mult"), salt0), "destroyed cathedral undoes salt bonus")
	await frames(2)
	check(menu.can_build("salt_cathedral"), "salt cathedral buildable again after destruction")

	# --- Inflation & building_cost_mult ---
	give_plenty()
	gd.set_modifier("gold_price_mult", 2.0)
	await frames(1)
	check(house_btn.text.ends_with("100 Gold"), "house button shows inflated cost: %s" % house_btn.text.replace("\n", " | "))
	place_checked("house", {"gold": 100})
	place_checked("mosque", {"gold": 300, "salt": 20})
	gd.set_modifier("gold_price_mult", 1.0)
	gd.set_modifier("building_cost_mult", 1.5)
	place_checked("outpost", {"gold": 300, "salt": 150})
	gd.set_modifier("building_cost_mult", 1.0)

	# --- building_hp_mult ---
	gd.set_modifier("building_hp_mult", 1.15)
	var h = place_checked("house", {"gold": 50})
	check(is_equal_approx(h.health, 172.5), "building_hp_mult applies to new building HP (%.1f)" % h.health)
	gd.set_modifier("building_hp_mult", 1.0)

	# --- Placement mode (ghost) ---
	menu.start_placement("house")
	check(menu.is_placing() and is_instance_valid(menu._ghost), "placement mode shows a ghost")
	var ev := InputEventAction.new()
	ev.action = "cancel"
	ev.pressed = true
	menu._unhandled_input(ev)
	check(not menu.is_placing(), "cancel exits placement mode")
	var bev := InputEventAction.new()
	bev.action = "toggle_build"
	bev.pressed = true
	menu._unhandled_input(bev)
	check(not menu._bar.visible, "toggle_build hides the bar")
	menu._unhandled_input(bev)
	check(menu._bar.visible, "toggle_build shows the bar again")

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails else 0)
