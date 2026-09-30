# Units test: Desert Scout, Gold Gilder, Donson Ton, Golden Mansa and UnitMenu.
extends SceneTree

var _fails := 0
var gd
var am
var em
var menu
var player: Node2D

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func seconds(t: float) -> void:
	await frames(int(ceil(t * 60.0)))

func set_age(age: int) -> void:
	am.current_age = age
	menu.refresh_buttons()

func set_res(gold: int, salt := 0, manuscripts := 0) -> void:
	gd.gold = gold
	gd.salt = salt
	gd.manuscripts = manuscripts

# Frees every Unit except the player (and `keep`).
func clear_units(keep: Array = []) -> void:
	for group in ["enemies", "allies"]:
		for n in get_nodes_in_group(group):
			if n == player or n in keep or not is_instance_of(n, load("res://entities/Unit.gd")):
				continue
			n.free()

func spawn_enemy(pos: Vector2, frozen := true) -> Node2D:
	var e: Node2D = load("res://entities/EnemyAI.tscn").instantiate()
	e.position = pos
	current_scene.add_child(e)
	if frozen:
		e.set_physics_process(false)
	return e

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	gd = root.get_node("GameData")
	am = root.get_node("AgeManager")
	em = root.get_node("EconomyManager")
	em.set_process(false)
	em.set_physics_process(false)
	root.get_node("DilemmaManager").auto_triggers_enabled = false
	gd.set_modifier("gold_price_mult", 1.0)
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	for c in gd.get_children():
		if c is Timer:
			c.stop() # no passive income: exact resource checks
	var sm = current_scene.get_node_or_null("SpawnManager")
	if sm:
		sm.free()
	for group in ["rival_camps", "rival_buildings", "rival_wonders"]:
		for n in get_nodes_in_group(group):
			n.free()
	player = get_first_node_in_group("player")
	player.set_physics_process(false) # the test moves the player by hand
	player.global_position = Vector2(0, 0)
	clear_units()
	menu = current_scene.get_node_or_null("UnitMenu")
	if menu == null:
		menu = load("res://ui/UnitMenu.tscn").instantiate()
		current_scene.add_child(menu)
	await process_frame

	await _test_menu_costs_and_ages()
	await _test_scout()
	await _test_gilder()
	await _test_donson()
	await _test_mansa()
	await _test_sandstorm()

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails else 0)

func _test_menu_costs_and_ages() -> void:
	set_age(am.AGES.SAND_CHIEFDOMS)
	set_res(0)
	for id in menu.ORDER:
		var b: Button = menu.get_button(id)
		check(b != null and b.icon != null, "%s button has an icon" % id)
		check(b.disabled, "%s disabled at 0 gold in Age I" % id)
		check(menu.UNITS[id]["name"] in b.text, "%s button shows its name: %s" % [id, b.text.replace("\n", " | ")])
	check("Not enough" in menu.get_button("camel_lancer").tooltip_text, "lancer tooltip gives the unaffordable reason")
	check("Requires Age II" in menu.get_button("gold_gilder").tooltip_text, "gilder tooltip: requires Age II")
	check("Requires Age III" in menu.get_button("golden_mansa").tooltip_text, "mansa tooltip: requires Age III")

	# Scaled costs (inflation) in text and payment.
	gd.set_modifier("gold_price_mult", 1.5)
	await process_frame
	check("75 Gold" in menu.get_button("camel_lancer").text, "lancer shows scaled 75 Gold: " + menu.get_button("camel_lancer").text.replace("\n", " "))
	check("120 Gold" in menu.get_button("desert_scout").text, "scout shows scaled 120 Gold")
	set_res(130)
	var u = menu.train("camel_lancer")
	check(u != null and u.scene_file_path == "res://entities/CamelLancer.tscn", "lancer trained")
	check(gd.gold == 55, "lancer cost 75 at x1.5 (gold=%d)" % gd.gold)
	check(u.is_in_group("camel"), "Camel Lancer is in group camel")
	gd.set_modifier("gold_price_mult", 1.0)
	await process_frame

	# Age I: scout yes, others locked even when rich.
	set_res(80)
	check(not menu.get_button("desert_scout").disabled, "scout enabled with 80 gold in Age I")
	var scout = menu.train("desert_scout")
	check(scout != null and scout.scene_file_path == "res://entities/DesertScout.tscn" and gd.gold == 0, "scout trained for 80 gold")
	check(scout.is_in_group("allies") and scout.is_in_group("camel"), "scout in allies + camel")
	set_res(100000, 1000, 10)
	for id in ["griot_bard", "gold_gilder", "donson_ton", "golden_mansa"]:
		check(menu.get_button(id).disabled, "%s age-locked in Age I" % id)
		check(menu.train(id) == null, "%s train() refused in Age I" % id)
	check(gd.gold == 100000, "locked training spent nothing")
	var toasts = get_first_node_in_group("toasts")
	if toasts:
		check(toasts.get_toast_texts().any(func(t): return "Cannot train" in t), "failure toast shown")

	# Age II
	set_age(am.AGES.MALI_ASCENDANCY)
	set_res(120)
	check(not menu.get_button("gold_gilder").disabled, "gilder enabled with 120 gold in Age II")
	var gil = menu.train("gold_gilder")
	check(gil != null and gd.gold == 0, "gilder costs 120 gold (gold=%d)" % gd.gold)
	set_res(150, 0)
	check(menu.get_button("donson_ton").disabled, "donson disabled without 30 salt")
	gd.salt = 30
	check(not menu.get_button("donson_ton").disabled, "donson enabled with 150 gold + 30 salt")
	var dt = menu.train("donson_ton")
	check(dt != null and gd.gold == 0 and gd.salt == 0, "donson costs 150 gold + 30 salt")
	set_res(75, 0, 1)
	var gr = menu.train("griot_bard")
	check(gr != null and gd.gold == 0 and gd.manuscripts == 0, "griot costs 75 gold + 1 manuscript")
	check(menu.get_button("golden_mansa").disabled, "mansa still locked in Age II")

	# Age III + uniqueness
	set_age(am.AGES.GOLDEN_HAJJ)
	set_res(4000)
	check(not menu.get_button("golden_mansa").disabled, "mansa enabled with 2000+ gold in Age III")
	var mansa = menu.train("golden_mansa")
	check(mansa != null and gd.gold == 2000, "mansa costs 2000 gold (gold=%d)" % gd.gold)
	check(mansa.is_in_group("hero") and mansa.is_in_group("allies"), "mansa in hero + allies")
	check(menu.get_button("golden_mansa").disabled, "mansa button disabled while the hero lives")
	check("Only one" in menu.get_button("golden_mansa").tooltip_text, "tooltip explains uniqueness")
	check(menu.train("golden_mansa") == null and gd.gold == 2000, "second mansa refused, nothing spent")
	mansa.take_damage(10000)
	await process_frame
	await process_frame
	if toasts:
		check(toasts.get_toast_texts().any(func(t): return "Golden Mansa has fallen" in t), "mansa death toast")
	check(not menu.get_button("golden_mansa").disabled, "mansa button re-enabled after the hero dies")
	clear_units()
	await process_frame

func _test_scout() -> void:
	set_age(am.AGES.SAND_CHIEFDOMS)
	set_res(80)
	var scout = menu.train("desert_scout")
	player.global_position = Vector2.ZERO
	scout.global_position = Vector2(0, 30)
	# Player walks right for a few frames.
	for i in 10:
		player.global_position += Vector2(4, 0)
		await physics_frame
	await seconds(1.5)
	var goal: Vector2 = player.global_position + Vector2(250, 0)
	check(scout.global_position.distance_to(goal) < 30.0, "scout ranges ~250 px ahead of the player (at %s, goal %s)" % [scout.global_position, goal])
	# Walk up: the scout re-positions ahead (north).
	for i in 10:
		player.global_position += Vector2(0, -4)
		await physics_frame
	await seconds(1.5)
	goal = player.global_position + Vector2(0, -250)
	check(scout.global_position.distance_to(goal) < 30.0, "scout follows the new heading north (at %s)" % scout.global_position)

	var far = spawn_enemy(scout.global_position + Vector2(0, -600))
	await frames(3)
	check(scout.marked_enemy == null, "enemy 600 px away not marked")
	var near = spawn_enemy(scout.global_position + Vector2(300, -200))
	await frames(3)
	check(scout.marked_enemy == near, "enemy ~360 px away is marked")
	far.free()
	near.free()
	await frames(2)
	check(scout.marked_enemy == null, "mark clears when the enemy is gone")

	scout.take_damage(45) # 25/70 < 40%
	check(scout.is_fleeing(), "scout flees below 40% health")
	await seconds(1.0)
	check(scout.global_position.distance_to(player.global_position) < 60.0, "fleeing scout returns to the player (%.0f px)" % scout.global_position.distance_to(player.global_position))
	clear_units()

func _test_gilder() -> void:
	set_age(am.AGES.MALI_ASCENDANCY)
	set_res(120)
	var gil = menu.train("gold_gilder")
	check(gil.mint_interval == 30.0, "gilder mints every 30 s by default")
	gil.mint_interval = 0.5
	gil._mint_time_left = 0.5
	var minted := [0]
	gil.ingot_minted.connect(func(): minted[0] += 1)
	set_res(250)
	gd.ingots = 0
	await seconds(1.1)
	check(gd.ingots == 2 and gd.gold == 50, "two mints: 200 gold -> 2 ingots (gold=%d ingots=%d)" % [gd.gold, gd.ingots])
	check(minted[0] == 2 and gil.ingots_minted == 2, "ingot_minted fired twice")
	await seconds(1.0)
	check(gd.ingots == 2 and gd.gold == 50, "no mint when gold < 100")
	check(gil.attack_damage == 0.0 and gil.max_health == 80.0, "gilder: 80 HP, non-combat")
	# Retreats from enemies toward the player.
	player.global_position = Vector2.ZERO
	gil.global_position = Vector2(200, 0)
	spawn_enemy(Vector2(260, 0))
	await seconds(1.0)
	check(gil.global_position.distance_to(player.global_position) < 60.0, "gilder retreats to the player (%.0f px)" % gil.global_position.distance_to(player.global_position))
	clear_units()

func _test_donson() -> void:
	set_age(am.AGES.MALI_ASCENDANCY)
	set_res(150, 30)
	var dt = menu.train("donson_ton")
	check(dt.max_health == 180.0 and dt.health == 180.0, "donson has 180 HP")
	player.global_position = Vector2.ZERO
	dt.global_position = Vector2(200, 200)
	await seconds(1.5)
	check(dt.global_position.distance_to(player.global_position) <= 62.0, "donson guards within 60 px (%.0f)" % dt.global_position.distance_to(player.global_position))
	# An enemy closes in on the player: the donson intercepts and poisons it.
	var e = spawn_enemy(player.global_position + Vector2(-150, 0))
	await seconds(2.0)
	check(e.health < e.max_health, "donson attacked the intruder (hp %.1f)" % e.health)
	check(e._poison_dps >= 3.0, "hit applied 3 HP/s poison (dps %.1f)" % e._poison_dps)
	# Direct strike on a fresh enemy.
	var e2 = spawn_enemy(dt.global_position + Vector2(20, 0))
	dt._attack_timer = 0.0
	check(dt.strike(e2), "strike lands")
	check(e2._poison_dps == 3.0 and e2._poison_time_left >= 2.9, "strike poisons 3 HP/s for 3 s")
	var hp_after_hit: float = e2.health
	dt.set_physics_process(false)
	await seconds(1.0)
	check(e2.health < hp_after_hit - 2.5 and e2.health > hp_after_hit - 3.5, "poison ticks ~3 HP/s (%.1f -> %.1f)" % [hp_after_hit, e2.health])
	clear_units()

func _test_mansa() -> void:
	set_age(am.AGES.GOLDEN_HAJJ)
	set_res(2000)
	var mansa = menu.train("golden_mansa")
	check(mansa.max_health == 400.0 and mansa.attack_damage == 0.0, "mansa: 400 HP, no attack")
	player.global_position = Vector2.ZERO
	mansa.global_position = Vector2(0, 40)
	var e = spawn_enemy(Vector2(0, 160))
	check(e.health == 60.0, "enemy has 60 HP")
	await seconds(10.0)
	check(not e.is_converted and e.is_in_group("enemies"), "not converted after 10 s (devotion %.1f)" % mansa.get_devotion(e))
	check(mansa.get_devotion(e) > 45.0, "devotion accumulates at ~5/s (%.1f)" % mansa.get_devotion(e))
	await seconds(2.5)
	check(e.is_converted and e.is_in_group("allies"), "60 HP enemy converted by devotion after ~12 s")
	check(mansa.conversions == 1, "mansa counts 1 conversion")
	# Outside the aura: no devotion.
	var far = spawn_enemy(Vector2(0, 600))
	await seconds(1.0)
	check(mansa.get_devotion(far) == 0.0, "no devotion outside the 200 px aura")

	# Gold distribution.
	check(mansa.distribute_interval == 20.0 and mansa.distribute_amount == 50, "distributes 50 gold every 20 s")
	var gifts := [0]
	mansa.gold_distributed.connect(func(_a): gifts[0] += 1)
	em.price_index = 1.5
	set_res(100)
	mansa._distribute_left = 0.1
	await seconds(0.3)
	check(gd.gold == 50 and gifts[0] == 1, "distributed 50 gold (gold=%d)" % gd.gold)
	check(em.price_index < 1.5, "distribution cooled inflation (%.3f)" % em.price_index)
	set_res(30)
	mansa._distribute_left = 0.1
	await seconds(0.3)
	check(gd.gold == 30 and gifts[0] == 1, "no distribution when gold < 50")
	em.price_index = 1.0
	gd.set_modifier("gold_price_mult", 1.0)
	clear_units()

func _test_sandstorm() -> void:
	var paths := {
		"res://entities/CamelLancer.tscn": [250.0, true],
		"res://entities/DesertScout.tscn": [500.0, true],
		"res://entities/GriotBard.tscn": [220.0, false],
		"res://entities/GoldGilder.tscn": [200.0, false],
		"res://entities/DonsonTon.tscn": [230.0, false],
		"res://entities/GoldenMansa.tscn": [150.0, false],
	}
	player.global_position = Vector2.ZERO
	gd.set_modifier("sandstorm_slow_mult", 0.3)
	var units := {}
	var i := 0
	for p in paths:
		var u: Node2D = load(p).instantiate()
		u.position = Vector2(-2000 + i * 800, 1500)
		current_scene.add_child(u)
		units[p] = u
		i += 1
	await frames(3)
	for p in paths:
		var expected: float = paths[p][0] * (1.0 if paths[p][1] else 0.3)
		var speed: float = units[p].velocity.length()
		check(absf(speed - expected) < 2.0, "sandstorm: %s moves at %.0f (expected %.0f)" % [p.get_file(), speed, expected])
	gd.set_modifier("sandstorm_slow_mult", 1.0)
	await frames(2)
	for p in paths:
		var speed: float = units[p].velocity.length()
		check(absf(speed - paths[p][0]) < 2.0, "clear skies: %s moves at %.0f" % [p.get_file(), speed])
	clear_units()
