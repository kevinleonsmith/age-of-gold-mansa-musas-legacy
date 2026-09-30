extends SceneTree
# Songhai rival faction: war camps, the Gao palace wonder, raider targeting.
# Run: timeout 300 ~/Godot_v4.4-stable_linux.arm64 --headless --fixed-fps 60 --path P -s P/tests/rival/test_rival.gd

var failures := 0
var m: Node
var gd: Node
var enemies: Node
var base: Node2D
var player: Node2D
var BUILDING_SCRIPT: Script
var ENEMY_SCENE: PackedScene
var LANCER_SCENE: PackedScene

const BASE_POS := Vector2(1500, -450)

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	m = current_scene
	gd = root.get_node("GameData")
	root.get_node("DilemmaManager").auto_triggers_enabled = false
	var sm := m.get_node_or_null("SpawnManager")
	if sm:
		sm.free()
	enemies = m.get_node("Enemies")
	for e in enemies.get_children():
		e.free()
	player = m.get_node("Player")
	BUILDING_SCRIPT = load("res://rival/RivalBuilding.gd")
	ENEMY_SCENE = load("res://entities/EnemyAI.tscn")
	LANCER_SCENE = load("res://entities/CamelLancer.tscn")
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)

	# Use main's RivalBase once the coordinator has placed one; else add our own.
	base = m.get_node_or_null("RivalBase")
	if base == null:
		base = load("res://rival/RivalBase.tscn").instantiate()
		base.position = BASE_POS
		m.add_child(base)
	await process_frame
	for c in get_nodes_in_group("rival_camps"):
		c._spawn_elapsed = 0.0

	await test_groups()
	await test_ambient_spawner()
	await test_camp_spawn_and_march()
	await test_camp_cap_and_pause()
	await test_wonder_defenders()
	await test_priority_weights()
	await test_enemies_damage_buildings()
	await test_allies_hit_buildings()
	await test_converted_attack_buildings()
	await test_sandstorm()
	await test_camp_bounty()
	await test_collapse_stops_camps()

	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)

func camps() -> Array:
	return get_nodes_in_group("rival_camps")

func wonder() -> Node2D:
	return get_first_node_in_group("rival_wonders") as Node2D

func clear_raiders() -> void:
	for e in enemies.get_children():
		e.free()
	for g in base.get_node("Guards").get_children():
		g.free()

func spawn_raider(pos: Vector2) -> Node2D:
	var e := ENEMY_SCENE.instantiate() as Node2D
	e.position = pos
	enemies.add_child(e)
	return e

func test_groups() -> void:
	print("--- Groups")
	check(get_nodes_in_group("rival_wonders").size() == 1, "1 rival wonder")
	check(camps().size() == 2, "2 war camps")
	check(get_nodes_in_group("rival_buildings").size() == 3, "3 rival buildings")
	var ok := true
	for b in get_nodes_in_group("rival_buildings"):
		ok = ok and is_instance_of(b, BUILDING_SCRIPT) and b.is_in_group("enemies") \
			and b.has_method("take_damage") and not b.is_destroyed and b.has_signal("destroyed") \
			and not b.has_method("convert_to_ally")
	check(ok, "rival buildings: RivalBuilding, in enemies, take_damage/is_destroyed/destroyed, not convertible")
	check(is_equal_approx(wonder().max_health, 1200.0) and is_equal_approx(camps()[0].health, 400.0), "HP: wonder 1200, camp 400")
	check(base.get_node("Guards").get_child_count() == 3, "3 pre-placed guards")

func test_ambient_spawner() -> void:
	print("--- Ambient spawner")
	var sm = load("res://systems/SpawnManager.gd").new()
	sm.spawn_interval = 0.5
	sm.max_enemies = 50
	m.add_child(sm)
	check(sm.has_rival_camps(), "spawner sees rival camps")
	check(sm.count_raiders() == 0, "guards and rival buildings are not counted as raiders (got %d)" % sm.count_raiders())
	for c in camps():
		c.spawn_interval = 1000.0
	gd.set_modifier("enemy_spawn_rate_mult", 1.0)
	await wait(2.2)
	var with_camps: int = enemies.get_child_count()
	check(with_camps == 2, "half ambient rate while camps stand (%d in 2.2 s, x1 would be 4)" % with_camps)
	sm.max_enemies = with_camps + 1
	var r := spawn_raider(Vector2(-900, 1400))
	await wait(1.2)
	check(enemies.get_child_count() == with_camps + 1 and sm.count_raiders() == with_camps + 1, "every raider counts toward max_enemies")
	r.free()
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)
	sm.free()
	clear_raiders()

func test_camp_spawn_and_march() -> void:
	print("--- Camp spawns and march")
	var camp = camps()[0]
	var other = camps()[1]
	camp.spawn_interval = 0.25
	camp.wave_size = 2
	other.spawn_interval = 1000.0
	camp._spawn_elapsed = 0.0
	gd.set_modifier("enemy_spawn_rate_mult", 1.0)
	await wait(0.4)
	var first := get_nodes_in_group("camp_raiders")
	check(first.size() == 1 and first[0].get_parent() == enemies, "camp spawned a raider into Enemies")
	check(first.size() == 1 and first[0].global_position.distance_to(camp.global_position) < 90.0, "raider spawns at its camp")
	check(first.size() == 1 and not first[0].is_marching, "raider gathers until the wave is ready")
	await wait(0.3)
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)
	var wave := get_nodes_in_group("camp_raiders")
	var all_marching := wave.size() == 2
	for r in wave:
		all_marching = all_marching and r.is_marching
	check(all_marching, "wave of 2 marches together")
	var d0: Array = []
	for r in wave:
		d0.append(r.global_position.distance_to(player.global_position))
	await wait(2.0)
	var closer := wave.size() == 2
	for i in wave.size():
		closer = closer and is_instance_valid(wave[i]) \
			and wave[i].global_position.distance_to(player.global_position) < d0[i] - 150.0
	check(closer, "raiders march toward the player's base")
	# With a building placed, the march heads for the nearest building instead.
	var house: Node2D = load("res://buildings/House.tscn").instantiate()
	house.position = Vector2(900, -200)
	m.get_node("Buildings").add_child(house)
	await process_frame
	var r2 = wave[0]
	r2.start_march()
	check(r2._march_point.distance_to(house.global_position) < 1.0, "march target = nearest player building")
	house.free()
	clear_raiders()

func test_camp_cap_and_pause() -> void:
	print("--- Camp cap and pause")
	var camp = camps()[0]
	camp.spawn_interval = 0.1
	camp.max_raiders = 2
	camp.wave_size = 10
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)
	await wait(0.6)
	check(camp.living_raider_count() == 0, "no camp spawns at enemy_spawn_rate_mult 0")
	gd.set_modifier("enemy_spawn_rate_mult", 1.0)
	await wait(1.0)
	check(camp.living_raider_count() == 2 and enemies.get_child_count() == 2, "per-camp cap of 2 (%d)" % camp.living_raider_count())
	# A converted raider no longer counts toward the camp cap.
	camp.raiders[0].convert_to_ally()
	await wait(0.4)
	check(camp.living_raider_count() == 2 and enemies.get_child_count() == 3, "converted raider frees a cap slot")
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)
	camp.max_raiders = 4
	camp.wave_size = 3
	clear_raiders()
	gd.set_modifier("converted_count", 0.0)

func test_wonder_defenders() -> void:
	print("--- Wonder calls defenders")
	var w := wonder()
	var near := spawn_raider(w.global_position + Vector2(-420, 250))
	var far := spawn_raider(w.global_position + Vector2(900, 900))
	await process_frame
	var lancer := LANCER_SCENE.instantiate() as Node2D
	lancer.position = w.global_position + Vector2(0, 150)
	lancer.set_physics_process(false)
	m.add_child(lancer)
	await process_frame
	var d0 := near.global_position.distance_to(w.global_position)
	w.take_damage(10.0)
	check(near.is_defending() and near.target == lancer, "raider in range is called to defend and targets the attacker")
	check(not far.is_defending(), "raider far away is not called")
	await wait(1.5)
	check(is_instance_valid(near) and near.global_position.distance_to(w.global_position) < d0 - 150.0, "defender rushes to the wonder")
	lancer.free()
	near.free()
	far.free()
	w.heal(10000.0)

func test_priority_weights() -> void:
	print("--- 60/30/10 targeting")
	# Exact proportions of the pure weighted choice over uniform rolls.
	var counts := {"caravan": 0, "mosque": 0, "hero": 0}
	var n := 1000
	for i in n:
		var k: String = load("res://entities/EnemyAI.gd").choose_priority_key(["caravan", "mosque", "hero"], (i + 0.5) / n)
		counts[k] += 1
	check(counts["caravan"] == 600 and counts["mosque"] == 300 and counts["hero"] == 100, "choose_priority_key 60/30/10 %s" % counts)
	var sub := {"mosque": 0, "hero": 0}
	for i in n:
		sub[load("res://entities/EnemyAI.gd").choose_priority_key(["hero", "mosque"], (i + 0.5) / n)] += 1
	check(sub["mosque"] == 750 and sub["hero"] == 250, "only mosque+hero: 75/25 %s" % sub)

	# In-scene: nearest caravan, unprotected mosque and hero around a raider.
	var c := Vector2(-600, 1200)
	var raider := spawn_raider(c)
	raider.set_physics_process(false)
	var caravan := LANCER_SCENE.instantiate() as Node2D
	caravan.position = c + Vector2(300, 0)
	caravan.add_to_group("caravans")
	var hero := LANCER_SCENE.instantiate() as Node2D
	hero.position = c + Vector2(-300, 0)
	hero.add_to_group("hero")
	for u in [caravan, hero]:
		u.set_physics_process(false)
		m.add_child(u)
	var mosque: Node2D = load("res://buildings/Mosque.tscn").instantiate()
	mosque.position = c + Vector2(0, 320)
	m.get_node("Buildings").add_child(mosque)
	await process_frame
	var cand: Dictionary = raider.find_priority_candidates()
	check(cand.get("caravan") == caravan and cand.get("mosque") == mosque and cand.get("hero") == hero, "candidates: caravan, unprotected mosque, hero")
	raider.rng.seed = 424242
	var hits := {"caravan": 0, "mosque": 0, "hero": 0}
	var samples := 20000
	for i in samples:
		var t = raider.pick_priority_target()
		if t == caravan:
			hits["caravan"] += 1
		elif t == mosque:
			hits["mosque"] += 1
		elif t == hero:
			hits["hero"] += 1
	var fc := float(hits["caravan"]) / samples
	var fm := float(hits["mosque"]) / samples
	var fh := float(hits["hero"]) / samples
	check(absf(fc - 0.6) < 0.015 and absf(fm - 0.3) < 0.015 and absf(fh - 0.1) < 0.015, "seeded pick %.3f/%.3f/%.3f ~ 0.6/0.3/0.1" % [fc, fm, fh])
	# A guard next to the mosque protects it.
	var guard := LANCER_SCENE.instantiate() as Node2D
	guard.position = mosque.position + Vector2(60, 40)
	guard.set_physics_process(false)
	m.add_child(guard)
	await process_frame
	cand = raider.find_priority_candidates()
	check(not cand.has("mosque") and cand.has("caravan"), "mosque with an ally within 200 px is not a candidate")
	guard.free()
	# Out of the extended radius nothing is picked; the raider falls back to nearest-ally logic.
	caravan.position = c + Vector2(700, 0)
	hero.position = c + Vector2(-700, 0)
	mosque.free()
	await process_frame
	check(raider.find_priority_candidates().is_empty() and raider.pick_priority_target() == null, "no candidates beyond 600 px")
	# Retarget uses the pick when nothing is in close combat range.
	caravan.position = c + Vector2(300, 0)
	await process_frame
	raider._retarget()
	check(raider.target == caravan or raider.target == hero, "retarget picks a priority target (not idle)")
	var close := LANCER_SCENE.instantiate() as Node2D
	close.position = c + Vector2(50, 0)
	close.set_physics_process(false)
	m.add_child(close)
	await process_frame
	raider._retarget()
	check(raider.target == close, "an ally in close combat range wins over the weighted pick")
	for u in [caravan, hero, close, raider]:
		u.free()

func test_enemies_damage_buildings() -> void:
	print("--- Enemies damage buildings")
	var c := Vector2(-700, 1300)
	var mosque: Node2D = load("res://buildings/Mosque.tscn").instantiate()
	mosque.position = c
	m.get_node("Buildings").add_child(mosque)
	await process_frame
	var h0: float = mosque.health
	# 50 px below the mosque centre: its footprint (80x28) edge is 36 px away.
	var raider := spawn_raider(c + Vector2(0, 62))
	await wait(3.0)
	check(is_instance_valid(mosque) and mosque.health < h0 - 10.0, "raider damages an unprotected mosque (%.0f -> %.0f)" % [h0, mosque.health if is_instance_valid(mosque) else -1.0])
	check(raider.global_position.distance_to(c) > 20.0, "raider stops at the footprint edge, not the centre")
	raider.free()
	if is_instance_valid(mosque):
		mosque.free()

func test_allies_hit_buildings() -> void:
	print("--- Player and lancer hit rival buildings")
	clear_raiders()
	var camp = camps()[0]
	var h0: float = camp.health
	var old_pos := player.global_position
	player.global_position = camp.global_position + Vector2(0, 36)
	await physics_frame
	await physics_frame
	Input.action_press("attack")
	await physics_frame
	await physics_frame
	Input.action_release("attack")
	await physics_frame
	check(camp.health < h0, "player's Space attack damages a war camp (%.0f -> %.0f)" % [h0, camp.health])
	player.global_position = old_pos
	var camp2 = camps()[1]
	var h1: float = camp2.health
	var lancer := LANCER_SCENE.instantiate() as Node2D
	lancer.position = camp2.global_position + Vector2(-180, 120)
	m.add_child(lancer)
	await wait(4.0)
	check(camp2.health < h1 - 15.0, "camel lancer attacks a war camp (%.0f -> %.0f)" % [h1, camp2.health])
	lancer.free()
	camp.heal(10000.0)
	camp2.heal(10000.0)

func test_converted_attack_buildings() -> void:
	print("--- Converted raiders attack rival buildings")
	var w := wonder()
	var h0: float = w.health
	var r := spawn_raider(w.global_position + Vector2(20, -170))
	await process_frame
	r.convert_to_ally()
	await wait(4.0)
	check(w.health < h0 - 10.0, "converted raider damages the rival wonder (%.0f -> %.0f)" % [h0, w.health])
	check(r.target == w, "converted raider targets the wonder")
	r.free()
	w.heal(10000.0)
	gd.set_modifier("converted_count", 0.0)

func test_sandstorm() -> void:
	print("--- Sandstorm")
	var a := spawn_raider(Vector2(-800, -600))
	var b := spawn_raider(Vector2(-800, -500))
	b.add_to_group("camel")
	await process_frame
	for r in [a, b]:
		r.start_march()
	var pa := a.global_position
	var pb := b.global_position
	await wait(1.0)
	var free_speed := a.global_position.distance_to(pa)
	gd.set_modifier("sandstorm_slow_mult", 0.5)
	pa = a.global_position
	pb = b.global_position
	await wait(1.0)
	var slow_speed := a.global_position.distance_to(pa)
	var camel_speed := b.global_position.distance_to(pb)
	check(free_speed > 100.0 and absf(slow_speed / free_speed - 0.5) < 0.1, "sandstorm halves raider speed (%.0f -> %.0f px/s)" % [free_speed, slow_speed])
	check(camel_speed > free_speed * 0.9, "\"camel\" raiders ignore the sandstorm (%.0f px/s)" % camel_speed)
	gd.set_modifier("sandstorm_slow_mult", 1.0)
	a.free()
	b.free()

func test_camp_bounty() -> void:
	print("--- Destroying a camp")
	var camp = camps()[0]
	camp.spawn_interval = 0.1
	camp.wave_size = 10
	camps()[1].spawn_interval = 1000.0
	var got_signal := [false]
	camp.destroyed.connect(func() -> void: got_signal[0] = true)
	var gold0: int = gd.gold
	camp.take_damage(10000.0)
	check(gd.gold - gold0 == 100, "camp bounty of 100 gold (got %d)" % (gd.gold - gold0))
	check(camp.is_destroyed and got_signal[0] and not camp.is_in_group("rival_camps") and not camp.is_in_group("enemies"), "camp destroyed: signal, left groups")
	gd.set_modifier("enemy_spawn_rate_mult", 1.0)
	var n0: int = enemies.get_child_count()
	await wait(0.5)
	check(not is_instance_valid(camp) and camps().size() == 1, "camp freed, one camp left")
	check(enemies.get_child_count() == n0, "destroyed camp spawns nothing")
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)
	clear_raiders()

func test_collapse_stops_camps() -> void:
	print("--- Rival collapse")
	var camp = camps()[0]
	camp.spawn_interval = 0.1
	var em := root.get_node("EconomyManager")
	em.drain_rival_gold(1.0e9)
	gd.set_modifier("enemy_spawn_rate_mult", 1.0)
	await wait(0.6)
	check(camp.living_raider_count() == 0 and not camp.can_spawn(), "no camp spawns once rivals collapse")
	gd.set_modifier("enemy_spawn_rate_mult", 0.0)
	em.reset()
