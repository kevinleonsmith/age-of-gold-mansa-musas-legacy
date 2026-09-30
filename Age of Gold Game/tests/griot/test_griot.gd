extends SceneTree

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)

func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	# Load Unit.gd at runtime: naming the Unit class_name here would compile it
	# before the autoloads (GameData) exist and fail to load this script.
	var UnitScript: Script = load("res://entities/Unit.gd")
	var main: Node = load("res://main.tscn").instantiate()
	var spawner := main.get_node_or_null("SpawnManager")
	if spawner:
		main.remove_child(spawner)
		spawner.free()
	root.add_child(main)
	current_scene = main
	await wait_frames(2)
	for e in get_nodes_in_group("enemies"):
		e.queue_free()

	var player := get_first_node_in_group("player") as Node2D
	check(player != null, "player found in main.tscn")
	print("player is Unit: ", is_instance_of(player, UnitScript), ", in allies: ", player.is_in_group("allies"))

	var griot = load("res://entities/GriotBard.tscn").instantiate()
	griot.pulse_interval = 1000.0 # manual pulses for the first part of the test
	main.add_child(griot)
	griot.global_position = player.global_position + Vector2(400, 0)

	var near_ally = UnitScript.new()
	near_ally.show_health_bar = false
	near_ally.add_to_group("allies")
	main.add_child(near_ally)
	var far_ally = UnitScript.new()
	far_ally.add_to_group("allies")
	main.add_child(far_ally)
	far_ally.global_position = player.global_position + Vector2(-1000, 0)

	check(griot.max_health == 60.0 and griot.attack_damage == 0.0, "stats: max_health 60, attack_damage 0")
	check(griot.is_in_group("allies"), "griot joined allies")

	# Follow
	var d0: float = griot.global_position.distance_to(player.global_position)
	await wait_frames(180)
	var d1: float = griot.global_position.distance_to(player.global_position)
	print("distance to player: start %.1f -> after 3 s %.1f" % [d0, d1])
	check(d1 >= 60.0 and d1 <= 100.0, "griot follows player to ~70-90 px")
	var p_before: Vector2 = griot.global_position
	await wait_frames(30)
	check(griot.global_position.distance_to(p_before) < 1.0, "griot stops when close enough")

	# Move player; griot should follow again
	player.global_position += Vector2(0, 500)
	await wait_frames(240)
	var d2: float = griot.global_position.distance_to(player.global_position)
	print("after player moved 500 px: distance %.1f" % d2)
	check(d2 >= 60.0 and d2 <= 100.0, "griot re-follows after player moves")

	# Retreat from enemy
	var enemy = UnitScript.new()
	enemy.add_to_group("enemies")
	main.add_child(enemy)
	griot.global_position = player.global_position + Vector2(200, 0)
	enemy.global_position = griot.global_position + Vector2(40, 0)
	var start_d: float = griot.global_position.distance_to(player.global_position)
	await wait_frames(20)
	var end_d: float = griot.global_position.distance_to(player.global_position)
	print("retreat: distance to player %.1f -> %.1f" % [start_d, end_d])
	check(end_d < start_d - 30.0, "griot retreats toward player when enemy within 80 px")
	enemy.queue_free()
	await wait_frames(120)

	# Pulse
	near_ally.global_position = griot.global_position + Vector2(50, 0)
	far_ally.global_position = griot.global_position + Vector2(400, 0)
	await wait_frames(1)
	var n: int = griot.activate_morale_boost()
	print("units boosted: ", n)
	check(n >= 2, "pulse boosted griot + near ally (count >= 2)")
	check(is_equal_approx(near_ally.attack_multiplier, 1.15) and near_ally.is_boosted(), "near ally boosted to 1.15")
	check(is_equal_approx(griot.attack_multiplier, 1.15) and griot.is_boosted(), "griot boosts itself")
	check(far_ally.attack_multiplier == 1.0 and not far_ally.is_boosted(), "far ally (400 px) not boosted")
	if is_instance_of(player, UnitScript) and player.global_position.distance_to(griot.global_position) <= 120.0:
		check(player.is_boosted() and is_equal_approx(player.attack_multiplier, 1.15), "player boosted")
	await wait_frames(15)
	check(griot._ring_progress > 0.0, "pulse ring animating (progress %.2f)" % griot._ring_progress)
	await wait_frames(40)
	check(griot._ring_progress == 0.0, "pulse ring finished after ~0.6 s")

	# Expiry (5 s total)
	await wait_frames(220) # 15+40+220 = 275 frames ~ 4.6 s
	check(near_ally.is_boosted(), "still boosted at ~4.6 s")
	await wait_frames(40)
	check(not near_ally.is_boosted() and near_ally.attack_multiplier == 1.0, "boost expired after 5 s")

	# Automatic pulse via timer
	griot.pulse_interval = 6.0
	griot._pulse_timer = 0.5
	near_ally.global_position = griot.global_position + Vector2(30, 30)
	await wait_frames(40)
	check(near_ally.is_boosted(), "automatic pulse fires from timer")

	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(failures)
