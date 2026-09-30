extends SceneTree

var gold_deltas: Array = []
var _last_gold := 0
var failures := 0

func _check(name: String, ok: bool, info: String) -> void:
	if not ok:
		failures += 1
	print("[%s] %s - %s" % ["PASS" if ok else "FAIL", name, info])

func _on_gold(v) -> void:
	gold_deltas.append(v - _last_gold)
	_last_gold = v

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var m := current_scene
	var gd := root.get_node("GameData")
	var sm := m.get_node_or_null("SpawnManager")
	if sm:
		sm.queue_free()  # keep random spawns out of the test
	var p = m.get_node("Player")
	var enemies := m.get_node("Enemies")
	var enemy_scene: PackedScene = load("res://entities/EnemyAI.tscn")
	var lancer_scene: PackedScene = load("res://entities/CamelLancer.tscn")
	print("player hp=", p.health, "/", p.max_health, " groups=", p.get_groups())

	# (a) enemy next to player damages it
	var e = enemy_scene.instantiate()
	e.position = p.global_position + Vector2(32, 0)
	enemies.add_child(e)
	var hp0: float = p.health
	await _wait(1.3)
	_check("a enemy damages player", p.health < hp0, "player hp %s -> %s" % [hp0, p.health])

	# (b) player attack kills enemy, bounty paid
	_last_gold = gd.gold
	gd.gold_changed.connect(_on_gold)
	var died := [false]
	e.died.connect(func(): died[0] = true)
	Input.action_press("attack")
	for i in 60:
		await physics_frame
		Input.action_release("attack")
		await physics_frame
		if died[0]:
			break
		Input.action_press("attack")
	Input.action_release("attack")
	await process_frame
	_check("b player kills enemy", died[0] and not is_instance_valid(e), "died=%s, gold deltas=%s" % [died[0], gold_deltas])
	_check("b bounty paid", gold_deltas.has(5), "")

	# (c) lancer engages and kills a nearby enemy
	var l = lancer_scene.instantiate()
	l.position = p.global_position + Vector2(-60, 0)
	m.add_child(l)
	var e2 = enemy_scene.instantiate()
	e2.position = l.global_position + Vector2(-220, 0)
	enemies.add_child(e2)
	var died2 := [false]
	e2.died.connect(func(): died2[0] = true)
	var t := 0.0
	while not died2[0] and t < 10.0:
		await _wait(0.1)
		t += 0.1
	_check("c lancer kills enemy", died2[0], "after %.1fs, lancer hp=%s at %s" % [t, l.health, l.global_position])
	await _wait(1.0)
	_check("c lancer escorts back", l.global_position.distance_to(p.global_position) <= 170.0, "dist to player %.1f" % l.global_position.distance_to(p.global_position))

	# (d) player death is handled: the Mansa falling is a defeat
	var vm := root.get_node("VictoryManager")
	var lost := [""]
	vm.game_lost.connect(func(id, _title, _text): lost[0] = id)
	p.take_damage(10000)
	await process_frame
	_check("d player hidden on death", not p.visible and p.is_dead, "")
	await _wait(2.0)
	_check("d defeat declared", vm.is_game_over and lost[0] == "player_died" and paused, "game_over=%s reason=%s paused=%s" % [vm.is_game_over, lost[0], paused])
	paused = false
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
